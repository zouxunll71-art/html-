import UIKit
import SafariServices

extension NativeRuntimeController:SFSafariViewControllerDelegate,UIAdaptivePresentationControllerDelegate {
 func setupNativeBehavior(){
  navigationHost.onEvent={[weak self] event in self?.event(event)}
  navigationHost.onHitTargets={[weak self] targets in self?.publishChromeTargets(targets)}
  modalScene.assetProvider={[weak self] id in self?.images[id]};modalScene.onEvent={[weak self] event in self?.event(event)}
  navigationHost.onInsets={[weak self] top,bottom in
   guard let self=self,let width=(self.payload["model"] as? [String:Any])?["viewport"] as? [String:Any],let design=width["width"] as? Double,self.view.bounds.width>0 else{return}
   let factor=StudioWidthScale.factor(self.view.bounds.width,designWidth:CGFloat(design)),next=CGPoint(x:top/factor,y:bottom/factor),height=self.view.bounds.height/factor
   guard abs(next.x-self.lastChromeInsets.x)>0.5 || abs(next.y-self.lastChromeInsets.y)>0.5 || abs(height-self.lastChromeHeight)>0.5 else{return}
   self.lastChromeInsets=next;self.lastChromeHeight=height
   DispatchQueue.main.async{self.event(["type":"chromeInsets","top":next.x,"bottom":next.y,"height":height])}
  }
 }
 func publishChromeTargets(_ targets:[[String:Any]]){
  guard !standalone,let project=payload["projectID"] as? String,let page=payload["page"] as? [String:Any],let pageID=page["id"] as? String else{return}
  let design=(page["width"] as? Double) ?? 393,scale=StudioWidthScale.factor(view.bounds.width,designWidth:CGFloat(design));guard scale>0 else{return}
  let logical=targets.map{target -> [String:Any] in var target=target;for key in ["x","y","width","height"]{if let value=target[key] as? NSNumber{target[key]=(Double(truncating:value)/Double(scale)*10).rounded()/10}};return target}
  let body:[String:Any] = ["projectID":project,"pageID":pageID,"targets":logical]
  guard let data=try? JSONSerialization.data(withJSONObject:body,options:.sortedKeys),let signature=String(data:data,encoding:.utf8),signature != lastChromeTargets else{return}
  lastChromeTargets=signature;Bridge.shared.json("/chrome-layout",body){[weak self] result in if case .failure=result{self?.lastChromeTargets=""}}
 }
 func pinChild(_ controller:UIViewController){
  if controller.parent !== self {controller.willMove(toParent:nil);controller.view.removeFromSuperview();controller.removeFromParent();addChild(controller);controller.view.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(controller.view);NSLayoutConstraint.activate([controller.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),controller.view.trailingAnchor.constraint(equalTo:view.trailingAnchor),controller.view.topAnchor.constraint(equalTo:view.topAnchor),controller.view.bottomAnchor.constraint(equalTo:view.bottomAnchor)]);controller.didMove(toParent:self)}
 }
 func applyRuntimePage(_ page:[String:Any]){
  let chrome=page["nativeChrome"] as? [String:Any]
  let stack=(chrome?["stack"] as? [[String:Any]] ?? []).compactMap{$0["page"] as? String}
  let routeParts=[(payload["model"] as? [String:Any])?["id"] as? String ?? "",page["id"] as? String ?? ""]+stack+(page["modalPages"] as? [String] ?? [])
  let routeKey=String(data:(try? JSONSerialization.data(withJSONObject:routeParts)) ?? Data(),encoding:.utf8) ?? ""
  let changed = !renderedRouteKey.isEmpty && renderedRouteKey != routeKey
  renderedRouteKey=routeKey
  if changed {
   if routeAnimator?.state == .active{routeAnimator?.stopAnimation(true)};routeAnimator=nil;routeSnapshot?.removeFromSuperview();routeSnapshot=nil
   scene.finishSceneAnimation();modalScene.finishSceneAnimation()
  }
  if changed,view.window != nil,pageTransitionDuration>0,!UIAccessibility.isReduceMotionEnabled,let snapshot=view.snapshotView(afterScreenUpdates:false) {
   snapshot.frame=view.bounds;snapshot.autoresizingMask=[.flexibleWidth,.flexibleHeight];snapshot.isUserInteractionEnabled=false
   UIView.performWithoutAnimation{self.applyRuntimeContents(page,animated:false);self.view.layoutIfNeeded()}
   view.addSubview(snapshot);routeSnapshot=snapshot
   let animator=UIViewPropertyAnimator(duration:pageTransitionDuration,curve:.easeInOut){snapshot.alpha=0}
   animator.addCompletion{[weak self,weak snapshot]_ in
    snapshot?.removeFromSuperview()
    if self?.routeSnapshot === snapshot{self?.routeSnapshot=nil;self?.routeAnimator=nil}
   }
   routeAnimator=animator;animator.startAnimation()
  }else{applyRuntimeContents(page,animated:!changed)}
 }
 func applyRuntimeContents(_ page:[String:Any],animated:Bool){
  if let chrome=page["nativeChrome"] as? [String:Any]{
   pinChild(navigationHost);navigationHost.view.isHidden=false;navigationHost.apply(chrome,scene:scene)
   var content=page,overlay=page
   let modals=page["modalPages"] as? [String] ?? [],top=(page["contentInsets"] as? [String:Any])?["top"] as? Double ?? 0
   let all=page["nodes"] as? [[String:Any]] ?? []
   func isModal(_ node:[String:Any])->Bool{let id=node["id"] as? String ?? "";return id.hasPrefix("$shade") || modals.contains{ id==$0 || id.hasPrefix($0+"/") }}
   content["nodes"]=all.filter{!isModal($0)}.map {node -> [String:Any] in var node=node;if (node["parent"] as? String ?? "").isEmpty{node["y"]=(node["y"] as? Double ?? 0)-top};return node}
   scene.apply(content,animated:animated)
   pinChild(modalScene);view.bringSubviewToFront(modalScene.view);modalScene.view.backgroundColor = .clear;modalScene.view.isHidden=modals.isEmpty;overlay["nodes"]=all.filter{isModal($0)};modalScene.apply(overlay,animated:animated)
  }else{
   navigationHost.viewIfLoaded?.isHidden=true;modalScene.viewIfLoaded?.isHidden=true;pinChild(scene);view.layoutIfNeeded();scene.apply(page,animated:animated)
  }
  if page["closeBrowser"] as? Bool==true {
   if let controller=presentedViewController as? SFSafariViewController{controller.dismiss(animated:true){[weak self] in self?.reportBrowser(false)}}else{reportBrowser(false)}
  }else{processNativeEffects(page)}
 }
 func reportBrowser(_ opened:Bool){
  guard !standalone,let project=payload["projectID"] as? String else{return}
  Bridge.shared.json("/browser-state",["projectID":project,"open":opened]){_ in}
 }
 func presentationControllerDidDismiss(_ presentationController:UIPresentationController){reportBrowser(false);if standalone{renderStandalone()}else{revision = -1;poll()}}
 func safariViewControllerDidFinish(_ controller:SFSafariViewController){
  controller.dismiss(animated:true){[weak self] in guard let self=self else{return};self.reportBrowser(false);if self.standalone{self.renderStandalone()}else{self.revision = -1;self.poll()}}
 }
 func processNativeEffects(_ page:[String:Any]){
  let project=(payload["model"] as? [String:Any])?["id"] as? String ?? ""
  var acknowledged=[String]()
  for effect in page["effects"] as? [[String:Any]] ?? [] {
   guard let id=effect["id"] as? String else{continue};let key=project+":"+id
   if handledEffects.contains(key){acknowledged.append(id);continue}
   if effect["type"] as? String=="share" {if !shareDocument(effect){continue}}
   else if effect["type"] as? String=="openURL",let string=effect["url"] as? String,let url=URL(string:string),url.scheme=="https",url.host != nil {
    // Leave queued links pending while Safari is already on screen.
    guard presentedViewController==nil else{continue}
    let safari=SFSafariViewController(url:url);safari.modalPresentationStyle = .pageSheet;safari.delegate=self;present(safari,animated:true){[weak self] in self?.reportBrowser(true)};safari.presentationController?.delegate=self
   }else if standalone,effect["type"] as? String=="delay",let duration=effect["duration"] as? Double {
    DispatchQueue.main.asyncAfter(deadline:.now()+duration){[weak self] in self?.event(["type":"effectComplete","id":id])}
   }
   handledEffects.insert(key);acknowledged.append(id)
  }
  if !standalone,presentedViewController==nil,page["browserOpen"] as? Bool==true{reportBrowser(false)}
  if standalone,var session=payload["session"] as? [String:Any]{session["effects"]=(session["effects"] as? [[String:Any]] ?? []).filter{!acknowledged.contains($0["id"] as? String ?? "")};payload["session"]=session}
  else if !acknowledged.isEmpty,let projectID=payload["projectID"] as? String{Bridge.shared.json("/ack-effects",["side":"ios","projectID":projectID,"ids":acknowledged]){_ in}}
 }
}
