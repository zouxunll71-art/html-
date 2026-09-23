import UIKit

/// Shared logical dimensions always scale by width, never by screen height.
enum StudioWidthScale {
 static func factor(_ width:CGFloat,designWidth:CGFloat=393)->CGFloat {width/max(1,designWidth)}
 static func value(_ value:CGFloat,width:CGFloat,designWidth:CGFloat=393)->CGFloat {value*factor(width,designWidth:designWidth)}
}
final class NativeRouteController:UIViewController {
 let route:String
 init(_ route:String){self.route=route;super.init(nibName:nil,bundle:nil)}
 required init?(coder:NSCoder){fatalError()}
 override func viewDidLoad(){super.viewDidLoad();view.backgroundColor = .clear}
}
/// Owns system navigation. Navigation bars never become copied HTML layers.
final class NativeNavigationHost:UIViewController,UITabBarControllerDelegate,UINavigationControllerDelegate {
 let tabs=UITabBarController()
 var tabNavigation:[String:UINavigationController]=[:]
 var plainNavigation:UINavigationController?
 var signature="",applying=false,expectedDepth=1
 var scene:NativeSceneController?
 var onEvent:(([String:Any])->Void)?
 var onInsets:((CGFloat,CGFloat)->Void)?
 var onHitTargets:(([[String:Any]])->Void)?;var chrome:[String:Any]=[:];var actionButtons:[(UIButton,String)]=[]
 var attachedConstraints:[NSLayoutConstraint]=[]
 var activeNavigation:UINavigationController?
 override func viewDidLoad(){super.viewDidLoad();view.backgroundColor = .clear;tabs.delegate=self}
 func attach(_ child:UIViewController){
  if child.parent !== self {addChild(child);child.view.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(child.view);NSLayoutConstraint.activate([child.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),child.view.trailingAnchor.constraint(equalTo:view.trailingAnchor),child.view.topAnchor.constraint(equalTo:view.topAnchor),child.view.bottomAnchor.constraint(equalTo:view.bottomAnchor)]);child.didMove(toParent:self)}
 }
 func detach(_ child:UIViewController){child.willMove(toParent:nil);child.view.removeFromSuperview();child.removeFromParent()}
 func apply(_ chrome:[String:Any],scene:NativeSceneController){
  loadViewIfNeeded();applying=true;defer{applying=false};self.scene=scene;self.chrome=chrome;actionButtons=[]
  let entries=chrome["tabs"] as? [[String:Any]] ?? [],stack=chrome["stack"] as? [[String:Any]] ?? []
  let nextSignature=entries.compactMap{$0["page"] as? String}.joined(separator:"|")
  if signature != nextSignature || tabs.viewControllers==nil {
   signature=nextSignature;tabNavigation.removeAll()
   let controllers=entries.map {entry -> UIViewController in
    let route=entry["page"] as? String ?? "",nav=UINavigationController(rootViewController:NativeRouteController(route));nav.delegate=self;tabNavigation[route]=nav;return nav
   };tabs.setViewControllers(controllers,animated:false)
  }
  let tint=UIColor(studioHex:chrome["tint"] as? String ?? "#007AFF"),background=UIColor(studioHex:chrome["background"] as? String ?? "#FFFFFF")
  tabs.tabBar.tintColor=tint
  let tabAppearance=UITabBarAppearance();tabAppearance.configureWithOpaqueBackground();tabAppearance.backgroundColor=background;tabs.tabBar.standardAppearance=tabAppearance;tabs.tabBar.scrollEdgeAppearance=tabAppearance
  for entry in entries {if let route=entry["page"] as? String,let nav=tabNavigation[route]{nav.tabBarItem=UITabBarItem(title:entry["title"] as? String,image:UIImage(systemName:entry["symbol"] as? String ?? ""),tag:0)}}
  let root=stack.first?["page"] as? String ?? "",nav:UINavigationController
  if chrome["hasTabs"] as? Bool==true,let selected=tabNavigation[root] {
   if let plain=plainNavigation,plain.parent != nil{detach(plain)}
   attach(tabs);tabs.selectedViewController=selected;nav=selected
  }else{
   if tabs.parent != nil{detach(tabs)}
   if plainNavigation==nil{plainNavigation=UINavigationController();plainNavigation?.delegate=self}
   nav=plainNavigation!;attach(nav)
  }
  activeNavigation=nav
  let transparentTop=chrome["topBarTransparent"] as? Bool ?? false
  let appearance=UINavigationBarAppearance()
  if transparentTop {appearance.configureWithTransparentBackground();appearance.backgroundColor = .clear;appearance.backgroundEffect=nil;appearance.shadowColor = .clear}
  else {appearance.configureWithOpaqueBackground();appearance.backgroundColor=background}
  nav.navigationBar.standardAppearance=appearance;nav.navigationBar.scrollEdgeAppearance=appearance
  nav.navigationBar.compactAppearance=appearance;nav.navigationBar.compactScrollEdgeAppearance=appearance
  nav.navigationBar.isTranslucent=transparentTop;nav.navigationBar.tintColor=tint
  var controllers=[UIViewController]()
  for (index,entry) in stack.enumerated(){
   let route=entry["page"] as? String ?? ""
   let controller=(nav.viewControllers.indices.contains(index) ? nav.viewControllers[index] as? NativeRouteController:nil).flatMap{$0.route==route ? $0:nil} ?? NativeRouteController(route)
   controller.title=entry["title"] as? String;controller.hidesBottomBarWhenPushed=index>0
   if let back=entry["backTitle"] as? String{controller.navigationItem.backButtonTitle=back}else{controller.navigationItem.backButtonDisplayMode = .minimal}
   let buttons=entry["buttons"] as? [[String:Any]] ?? []
   func items(_ side:String)->[UIBarButtonItem]{buttons.filter{($0["side"] as? String ?? "right")==side}.map {button in
    let title=button["title"] as? String ?? "",node=button["node"] as? String ?? ""
    let action=UIAction(title:title,image:(button["symbol"] as? String).flatMap{UIImage(systemName:$0)}){[weak self]_ in self?.onEvent?(["node":node])}
    let button=UIButton(type:.system);button.tintColor=tint;button.titleLabel?.font = .systemFont(ofSize:17)
    if let image=action.image{button.setImage(image,for:.normal)}else{button.setTitle(title,for:.normal)}
    button.accessibilityLabel=title;button.addAction(action,for:.touchUpInside);button.sizeToFit();button.widthAnchor.constraint(greaterThanOrEqualToConstant:32).isActive=true;button.heightAnchor.constraint(equalToConstant:40).isActive=true
    let item=UIBarButtonItem(customView:button);if index==stack.count-1{actionButtons.append((button,node))};return item
   }}
   controller.navigationItem.leftBarButtonItems=items("left");controller.navigationItem.rightBarButtonItems=items("right");controllers.append(controller)
  }
  expectedDepth=controllers.count
  if nav.viewControllers.map({ObjectIdentifier($0)}) != controllers.map({ObjectIdentifier($0)}){nav.setViewControllers(controllers,animated:false)}
  nav.setNavigationBarHidden(stack.last?["hidden"] as? Bool ?? false,animated:false)
  guard let host=controllers.last else{return}
  if scene.parent !== host {
   NSLayoutConstraint.deactivate(attachedConstraints);scene.willMove(toParent:nil);scene.view.removeFromSuperview();scene.removeFromParent();host.addChild(scene);scene.view.translatesAutoresizingMaskIntoConstraints=false;host.view.addSubview(scene.view)
   let guide=host.view.safeAreaLayoutGuide;attachedConstraints=[scene.view.leadingAnchor.constraint(equalTo:guide.leadingAnchor),scene.view.trailingAnchor.constraint(equalTo:guide.trailingAnchor),scene.view.topAnchor.constraint(equalTo:guide.topAnchor),scene.view.bottomAnchor.constraint(equalTo:guide.bottomAnchor)];NSLayoutConstraint.activate(attachedConstraints);scene.didMove(toParent:host)
  }
  view.layoutIfNeeded();publishInsets()
 }
 override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();publishInsets()}
 func publishInsets(){guard let scene=scene,scene.view.window != nil,view.bounds.width>0 else{return};let rect=scene.view.convert(scene.view.bounds,to:view);guard rect.height>0 else{return};onInsets?(max(0,rect.minY),max(0,view.bounds.height-rect.maxY));publishHitTargets()}
 func publishHitTargets(){
  guard let nav=activeNavigation else{return};var targets=[[String:Any]]()
  func add(_ rect:CGRect,_ event:[String:Any]){guard rect.width>0,rect.height>0 else{return};targets.append(["x":rect.minX,"y":rect.minY,"width":rect.width,"height":rect.height,"event":event])}
  for(button,node) in actionButtons where button.window != nil{add(button.convert(button.bounds,to:view),["node":node])}
  let stack=chrome["stack"] as? [[String:Any]] ?? []
  if stack.count>1,!nav.isNavigationBarHidden,(stack.last?["buttons"] as? [[String:Any]] ?? []).allSatisfy({$0["side"] as? String != "left"}) {
   let bar=nav.navigationBar.convert(nav.navigationBar.bounds,to:view)
   let title=stack.dropLast().last?["backTitle"] as? String ?? ""
   let width=min(bar.width/2,44+(title as NSString).size(withAttributes:[.font:UIFont.systemFont(ofSize:17)]).width)
   add(CGRect(x:bar.minX,y:bar.minY,width:width,height:bar.height),["type":"back"])
  }
  if chrome["showTabs"] as? Bool==true{
   let entries=chrome["tabs"] as? [[String:Any]] ?? [];var controls=[UIControl]()
   func collect(_ root:UIView){for child in root.subviews where !child.isHidden && child.alpha>0{if let control=child as? UIControl{controls.append(control)}else{collect(child)}}}
   collect(tabs.tabBar);controls.sort{$0.convert($0.bounds,to:view).midX<$1.convert($1.bounds,to:view).midX}
   let bar=tabs.tabBar.convert(tabs.tabBar.bounds,to:view)
   for(index,entry) in entries.enumerated(){
    let rect=controls.count==entries.count ? controls[index].convert(controls[index].bounds,to:view):CGRect(x:bar.minX+bar.width*CGFloat(index)/CGFloat(entries.count),y:bar.minY,width:bar.width/CGFloat(entries.count),height:min(49,bar.height))
    add(rect,["type":"tab","page":entry["page"] ?? ""])
   }
  }
  onHitTargets?(targets)
 }
 func tabBarController(_ tabBarController:UITabBarController,didSelect viewController:UIViewController){guard !applying,let nav=viewController as? UINavigationController,let first=nav.viewControllers.first as? NativeRouteController else{return};onEvent?(["type":"tab","page":first.route])}
 func navigationController(_ navigationController:UINavigationController,didShow viewController:UIViewController,animated:Bool){guard !applying,navigationController===activeNavigation,navigationController.viewControllers.count<expectedDepth else{return};onEvent?(["type":"popTo","depth":navigationController.viewControllers.count])}
}
