import UIKit
extension StudioController {
 func updateSplashEditorButton(_ pinned:Bool){
  splashPinned=pinned
  let title=pinned ? "关闭启动页编辑":"编辑启动页"
  splashButton.setTitle(title,for:.normal);splashButton.configuration?.title=title
  splashButton.accessibilityLabel=title
 }
 func toggleSplashEditor(forceOpen:Bool=false){
  guard let projectID=project?.id,!splashRequestBusy else{return}
  splashRequestBusy=true
  Bridge.shared.request("/runtime?side=ios&after=-1"){[weak self] result in
   guard let self=self else{return}
   guard self.project?.id==projectID else{self.splashRequestBusy=false;return}
   guard case .success(let data)=result,
    let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
    let model=value["model"] as? [String:Any],
    let pages=model["pages"] as? [String:[String:Any]] else {self.splashRequestBusy=false;self.showMessage("启动页", "无法读取当前项目启动页");return}
   let pinned=(value["session"] as? [String:Any])?["editingPage"] as? String
   let closing=pinned != nil && !forceOpen
   let entry=model["entry"] as? String
   let pageID=closing ? pinned:entry.flatMap{pages[$0] != nil ? $0:nil} ?? pages.keys.sorted().first{pages[$0]?["role"] as? String=="startup"}
   guard let pageID=pageID else{self.splashRequestBusy=false;self.showMessage("启动页", "当前项目没有登记启动页");return}
   func navigate(){
    Bridge.shared.json("/event",["side":"ios","projectID":projectID,"eventID":UUID().uuidString,"event":["type":"navigate","page":pageID,"preview":!closing]]){[weak self] response in
     guard let self=self else{return};self.splashRequestBusy=false
     guard self.project?.id==projectID else{return}
     if case .failure(let error)=response{self.error(error);return}
     self.updateSplashEditorButton(!closing);self.pollRoute()
    }
   }
   if self.running {
    self.mode.selectedSegmentIndex=0;self.toggleRun()
    Bridge.shared.json("/mode",["editing":true]){[weak self] response in
     if case .failure(let error)=response{self?.splashRequestBusy=false;self?.error(error)}else{navigate()}
    }
   }else{navigate()}
  }
 }
}
