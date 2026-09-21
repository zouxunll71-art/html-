import UIKit

extension StudioController {
 func configureEmbeddedSimulator(){
  left.directSimulatorInput=true
  left.onPointer={[weak self]kind,point in self?.sendSimulatorPointer(kind,point)}
  simulatorInput.onFailure={[weak self]message in
   guard let self=self,self.running else{return};self.setStatus("模拟器直接操作未连接");self.showMessage("模拟器操作连接中断",message+"\n\n可以在手机下方选择「模拟器 → 重新连接操作」，或「打开独立模拟器」继续操作。")
  }
  simulatorInput.onReady={[weak self]ready in
   guard let self=self else{return};if !ready{self.left.cancelSimulatorGesture()}else{self.statusHoldUntil=Date().addingTimeInterval(2);self.footer.text="  模拟器操作已连接"};self.leftTitle.text=self.running ? (ready ? "iOS · 直接操作真实模拟器":"iOS · 操作连接未就绪") : "iOS 成品 · 真实模拟器"
  }
  simulatorInput.onRecovering={[weak self] in guard let self=self else{return};self.statusHoldUntil=Date().addingTimeInterval(4);self.footer.text="  模拟器操作连接恢复中…"}
  simulatorTools.axis = .horizontal;simulatorTools.spacing=6;simulatorTools.distribution = .fillEqually;simulatorTools.isHidden=true;workspace.addSubview(simulatorTools)
  simulatorTools.addArrangedSubview(button("输入文字",{[weak self] in self?.sendTextToSimulator()}))
  let menu=button("模拟器 ▾",{});menu.showsMenuAsPrimaryAction=true
  menu.menu=UIMenu(children:[
   UIAction(title:"收起独立模拟器窗口",image:UIImage(systemName:"rectangle.compress.vertical")){[weak self]_ in self?.simulatorInput.enqueue(["kind":"hide"])},
   UIAction(title:"打开独立模拟器",image:UIImage(systemName:"arrow.up.forward.app")){[weak self]_ in self?.openExternalSimulator()},
   UIAction(title:"重新连接操作",image:UIImage(systemName:"arrow.triangle.2.circlepath")){[weak self]_ in self?.connectEmbeddedSimulator()},
   UIAction(title:"回车",image:UIImage(systemName:"return")){[weak self]_ in self?.simulatorInput.enqueue(["kind":"key","code":40])},
   UIAction(title:"删除一个字符",image:UIImage(systemName:"delete.left")){[weak self]_ in self?.simulatorInput.enqueue(["kind":"key","code":42])}
  ]);simulatorTools.addArrangedSubview(menu)
  NotificationCenter.default.addObserver(self,selector:#selector(releaseSimulatorTouches),name:UIApplication.willResignActiveNotification,object:nil)
 }
 @objc func releaseSimulatorTouches(){left.cancelSimulatorGesture();simulatorInput.enqueue(["kind":"cancel"])}
 func connectEmbeddedSimulator(){
  guard running,iosRunJob==nil,let id=project?.id else{return}
  simulatorInput.start(id)
 }
 func sendSimulatorPointer(_ kind:String,_ point:CGPoint){
  guard running else{return}
  if kind=="cancel"{simulatorInput.enqueue(["kind":"cancel"]);return}
  guard iosFrames.isFresh else{simulatorInput.enqueue(["kind":"cancel"]);setStatus("模拟器画面暂时中断，恢复后再操作；可点击「检查并修复同步」");return}
  guard simulatorInput.ready else{setStatus("模拟器操作尚未连接，请在手机下方选择「模拟器 → 重新连接操作」");return}
  simulatorInput.enqueue(["kind":kind,"x":max(0,min(1,Double(point.x/left.logicalSize.width))),"y":max(0,min(1,Double(point.y/left.logicalSize.height)))])
 }
 func sendTextToSimulator(){
  guard running,simulatorInput.ready else{setStatus("请先连接模拟器操作");return}
  releaseSimulatorTouches()
  let alert=UIAlertController(title:"发送文字到 iOS",message:"先点击左侧手机中的输入框，再输入文字。通过模拟器剪贴板粘贴；iOS 如显示粘贴确认，请在左侧手机中允许。",preferredStyle:.alert)
  alert.addTextField{$0.placeholder="支持中文和英文"}
  alert.addAction(UIAlertAction(title:"取消",style:.cancel))
  alert.addAction(UIAlertAction(title:"发送",style:.default){[weak self,weak alert]_ in
   guard let self=self,self.running,let text=alert?.textFields?.first?.text,!text.isEmpty else{return};self.simulatorInput.enqueue(["kind":"text","text":text])
  });present(alert,animated:true)
 }
 func openExternalSimulator(){
  releaseSimulatorTouches();Bridge.shared.json("/ios-window",[:]){[weak self]result in if case .failure(let error)=result{self?.error(error)}}
 }
}
