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
     self.exportJobID=nil;self.buttons[6].isEnabled=true;UIPasteboard.general.string=path;self.setStatus("成品已导出，目标路径已复制");self.showMessage("iOS 成品已导出",path+"\n\n若已接入外层空工程，代码和资源已迁入，原工程配置保持不变。成品为运行界面，不含编辑工具；工作区仍可编辑，外层成品不随编辑自动变化。尚未执行目标工程构建。");return
    }
    self.setStatus("正在"+(state["stage"] as? String ?? "导出工程")+"（\(state["progress"] as? Int ?? 0)%）")
    DispatchQueue.main.asyncAfter(deadline:.now()+0.7){[weak self] in self?.pollExport(job)}
   }catch{self.finishExport(error.localizedDescription+"\n后台导出可能仍在继续，请检查项目 HTMLNativeStudio/iOS 目录。")} 
  }
 }
 func finishExport(_ message:String){exportJobID=nil;buttons[6].isEnabled=true;setStatus("导出未完成");showMessage("导出检查",message)}
}
