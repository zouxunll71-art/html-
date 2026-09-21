import UIKit
extension StudioController {
 func runIOS(){
  guard iosRunJob==nil,!repairingSync,let p=project else{return}
  guard !historyGesture else{setStatus("请结束拖动后再运行 iOS");return}
  releaseSimulatorTouches();simulatorInput.stop()
  runIOSButton.isEnabled=false;repairSyncButton.isEnabled=false
  saveTimer?.invalidate();previewTimer?.invalidate();setStatus("正在保存当前布局并准备运行 iOS…")
  saveThenRunIOS(projectID:p.id,deadline:Date().addingTimeInterval(15))
 }
 func saveThenRunIOS(projectID:String,deadline:Date){
  guard let p=project,p.id==projectID else{finishRunIOS(error:"项目已切换，请重新点击运行 iOS。");return}
  if previewInFlight || pendingPreview != nil {
   guard Date()<deadline else{finishRunIOS(error:"布局同步尚未完成，请稍后重试；当前编辑仍然保留。");return}
   flushPreview();DispatchQueue.main.asyncAfter(deadline:.now()+0.2){[weak self] in self?.saveThenRunIOS(projectID:projectID,deadline:deadline)};return
  }
  guard let data=try? JSONEncoder().encode(p) else{finishRunIOS(error:"无法保存当前项目。");return}
  Bridge.shared.request("/save",body:data){[weak self] result in
   guard let self=self else{return}
   if case .failure(let error)=result{self.finishRunIOS(error:error.localizedDescription);return}
   self.dirty=false
   Bridge.shared.json("/run-ios",["id":projectID]){[weak self] result in
    guard let self=self else{return}
    do{let data=try result.get();guard let response=try JSONSerialization.jsonObject(with:data) as? [String:String],let job=response["job"] else{throw NSError(domain:"RunIOS",code:1,userInfo:[NSLocalizedDescriptionKey:"运行任务未创建"])};self.iosRunJob=job;self.pollRunIOS(job,projectID:projectID)}catch{self.finishRunIOS(error:error.localizedDescription)}
   }
  }
 }
 func pollRunIOS(_ job:String,projectID:String){
  Bridge.shared.request("/run-ios-status?job="+job){[weak self] result in
   guard let self=self,self.iosRunJob==job else{return}
   do{
    let data=try result.get();guard let state=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{return}
    let phase=state["stage"] as? String ?? "正在运行 iOS",progress=state["progress"] as? Int ?? 0
    if state["state"] as? String=="failed"{self.finishRunIOS(error:(state["error"] as? String ?? phase)+"\n\n日志："+(state["logPath"] as? String ?? ""));return}
    if state["state"] as? String=="done"{
     self.iosRunJob=nil;self.runIOSButton.isEnabled=true;self.runIOSButton.setTitle("运行 / 重启 iOS",for:.normal)
     self.iosFrames.start();self.observedRevision = -1;self.web.reload();self.pollRoute();self.connectEmbeddedSimulator()
     guard self.project?.id==projectID else{self.repairSyncButton.isEnabled=true;self.setStatus("iOS 已启动，当前项目已切换，请查看同步状态");return}
     self.repairingSync=true;self.setStatus("正在确认 iOS、HTML 和模拟器画面…");self.verifySyncRepair(projectID:projectID,deadline:Date().addingTimeInterval(20));return
    }
    self.runIOSButton.setTitle("运行中 \(progress)%",for:.normal);self.setStatus("正在"+phase+"（\(progress)%）")
    DispatchQueue.main.asyncAfter(deadline:.now()+1){[weak self] in self?.pollRunIOS(job,projectID:projectID)}
   }catch{self.finishRunIOS(error:error.localizedDescription+"\n后台任务可能仍在运行，重新点击会接回当前进度。")}
  }
 }
 func finishRunIOS(error:String){iosRunJob=nil;runIOSButton.isEnabled=true;repairSyncButton.isEnabled=true;runIOSButton.setTitle("运行 / 重启 iOS",for:.normal);setStatus("iOS 运行未完成");showMessage("iOS 运行未完成",error)}
}
