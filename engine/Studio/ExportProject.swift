import UIKit
extension StudioController {
 func export(){
  guard exportJobID==nil,let p=project,let data=try? JSONEncoder().encode(p) else{return}
  guard !historyGesture,!previewInFlight,pendingPreview==nil else{setStatus("请结束当前调整，等布局同步后再导出");return}
  buttons[6].isEnabled=false;setStatus("正在保存布局并检查完整工程…")
  Bridge.shared.request("/export-start",body:data){[weak self] result in
   guard let self=self else{return}
   do{let data=try result.get();guard let body=try JSONSerialization.jsonObject(with:data) as? [String:String],let job=body["job"] else{throw NSError(domain:"Export",code:1,userInfo:[NSLocalizedDescriptionKey:"导出任务创建失败"])};self.exportJobID=job;self.pollExport(job)}catch{self.finishExport(error.localizedDescription)}
  }
 }
 func pollExport(_ job:String){
  Bridge.shared.request("/export-status?job="+job){[weak self] result in
   guard let self=self,self.exportJobID==job else{return}
   do{
    let data=try result.get();guard let state=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{self.finishExport("导出状态不可读");return}
    if state["state"] as? String=="failed"{self.finishExport(state["error"] as? String ?? "导出未完成");return}
    if state["state"] as? String=="done",let path=state["path"] as? String{
     self.exportJobID=nil;self.buttons[6].isEnabled=true;UIPasteboard.general.string=path;self.setStatus("完整工程已导出，路径已复制");self.showMessage("iOS 工程已导出",path+"\n\n包含全部声明页面、弹窗、资源与动作；尚未执行 Xcode 构建。");return
    }
    self.setStatus("正在"+(state["stage"] as? String ?? "导出工程")+"（\(state["progress"] as? Int ?? 0)%）")
    DispatchQueue.main.asyncAfter(deadline:.now()+0.7){[weak self] in self?.pollExport(job)}
   }catch{self.finishExport(error.localizedDescription+"\n后台导出可能仍在继续，请检查桌面输出。")} 
  }
 }
 func finishExport(_ message:String){exportJobID=nil;buttons[6].isEnabled=true;setStatus("导出未完成");showMessage("导出检查",message)}
}
