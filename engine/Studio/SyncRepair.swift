import UIKit
extension StudioController {
 func repairSynchronization(){
  guard !repairingSync,let p=project else{return}
  guard !dirty,!historyGesture,!previewInFlight,pendingPreview==nil else{showMessage("先保存当前调整","请点击「保存布局」，保存完成后再检查同步，以保留正在编辑的内容。");return}
  releaseSimulatorTouches();simulatorInput.stop()
  repairingSync=true;runIOSButton.isEnabled=false;repairSyncButton.isEnabled=false;repairSyncButton.setTitle("正在检查与修复…",for:.normal);setStatus("正在检查服务、iOS 运行端和画面连接…")
  Bridge.shared.json("/repair-sync",["id":p.id]){[weak self]result in
   guard let self=self else{return}
   switch result {
   case .failure(let e):self.finishSyncRepair("修复未完成",e.localizedDescription)
   case .success:
    guard self.project?.id==p.id else{self.finishSyncRepair("检查已停止","项目已切换，请对当前项目重新检查。");return}
    self.observedRevision = -1;self.iosFrames.start();self.web.reload();self.pollRoute();self.connectEmbeddedSimulator()
    self.verifySyncRepair(projectID:p.id,deadline:Date().addingTimeInterval(15))
   }
  }
 }
 func verifySyncRepair(projectID:String,deadline:Date){
  Bridge.shared.request("/status"){[weak self]result in
   guard let self=self,self.repairingSync else{return}
   guard self.project?.id==projectID else{self.finishSyncRepair("检查已停止","项目已切换。");return}
   if case .success(let data)=result,let s=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let rev=s["revision"] as? Int {
    let ack=s["ack"] as? [String:Int] ?? [:]
    if s["active"] as? String==projectID,ack["ios"]==rev,ack["web"]==rev,self.iosFrames.isFresh,self.observedRevision==rev {
     self.finishSyncRepair("同步连接已恢复",self.linked ? "HTML 和 iOS 已确认当前版本，工作台已收到新的模拟器画面。" : "两端连接和工作台画面已恢复。当前为独立操作模式，页面各自保留。");return
    }
   }
   if Date()>deadline{self.finishSyncRepair("同步仍需检查",self.iosFrames.isFresh ? "画面连接已恢复，但两端尚未确认同一版本。请查看「更多 → 源码与同步详情」。" : "未收到新的模拟器画面。请确认 iOS 模拟器已启动，然后重试。");return}
   DispatchQueue.main.asyncAfter(deadline:.now()+1){[weak self]in self?.verifySyncRepair(projectID:projectID,deadline:deadline)}
  }
 }
 func finishSyncRepair(_ title:String,_ detail:String){repairingSync=false;runIOSButton.isEnabled=true;repairSyncButton.isEnabled=true;repairSyncButton.setTitle("检查并修复同步",for:.normal);setStatus(title);showMessage(title,detail)}
}
