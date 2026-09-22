import UIKit
import JavaScriptCore
import CoreText
@main final class NativeRuntimeApp:UIResponder,UIApplicationDelegate {
 var window:UIWindow?
 func application(_ app:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool{let w=UIWindow(frame:UIScreen.main.bounds);w.rootViewController=NativeRuntimeController();w.overrideUserInterfaceStyle = .light;w.makeKeyAndVisible();window=w;return true}
}
final class NativeRuntimeController:UIViewController {
 // Editable exported route fade duration; 0 disables it.
 var pageTransitionDuration:TimeInterval=0.18
 var renderedRouteKey=""
 var routeSnapshot:UIView?;var routeAnimator:UIViewPropertyAnimator?
 let navigationHost=NativeNavigationHost(),modalScene=NativeSceneController();var lastChromeInsets=CGPoint(x:-1,y:-1);var lastChromeHeight:CGFloat = -1;var handledEffects=Set<String>();var lastChromeTargets=""
 var assetsNeedReload=false;private var lastRuntimeChange=Date.distantPast;private var pollStarted=Date.distantPast
 let scene=NativeSceneController();let engine=JSContext()!;var payload:[String:Any]=[:];var revision = -1;var busy=false;var timer:Timer?;var images:[String:UIImage]=[:];var fonts=Set<String>();var standalone=false;var assetGeneration=0;var imagePixels:[String:Int]=[:];var eventQueue=[[String:Any]]();var sending=false;var errorLabel=UILabel()
 override func viewDidLoad(){super.viewDidLoad();view.backgroundColor = .white;setupNativeBehavior();pinChild(scene);scene.assetProvider={[weak self]id in self?.images[id]};scene.onEvent={[weak self]e in self?.event(e)}
  engine.exceptionHandler={_,e in print("Engine: \(e?.toString() ?? "unknown")")}
  if let path=Bundle.main.path(forResource:"engine",ofType:"js"),let js=try? String(contentsOfFile:path){engine.evaluateScript(js)}
  if let path=Bundle.main.url(forResource:"contract",withExtension:"json"),let data=try? Data(contentsOf:path),let contract=try? JSONSerialization.jsonObject(with:data) as? [String:Any]{standalone=true;loadStandalone(contract)}else{poll()}
 }
 override func didReceiveMemoryWarning(){super.didReceiveMemoryWarning();images.removeAll();imagePixels.removeAll();assetsNeedReload=true;revision = -1}
 override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews()}
 func call(_ name:String,_ args:[Any])->Any?{engine.objectForKeyedSubscript("StudioEngine")?.invokeMethod(name,withArguments:args)?.toObject()}
 func loadStandalone(_ contract:[String:Any]){payload=contract;guard let model=contract["model"] as? [String:Any] else{return};let key="session.\(model["id"] ?? "app").\(model["stateVersion"] ?? 1)"
  if let data=UserDefaults.standard.data(forKey:key),let s=try? JSONSerialization.jsonObject(with:data){payload["session"]=s}else{payload["session"]=call("initial",[model])}
  if var session=payload["session"] as? [String:Any]{session["locale"]=Bundle.preferredLocalizations(from:["en","zh-Hans"]).first ?? "en";session["effects"]=Array((session["pendingEffects"] as? [String:[String:Any]] ?? [:]).values);payload["session"]=session}
  renderStandalone()
 }
 func composedPage(_ model:Any,_ session:Any)->[String:Any]? {call("compose",[model,session,payload["overrides"] ?? [:],payload["additions"] ?? [:]]) as? [String:Any]}
 func renderStandalone(){guard let model=payload["model"],let session=payload["session"],let page=composedPage(model,session) else{return}
  if !assetsNeedReload,applyScrollOnly(page){payload["page"]=page;return}
  loadPageAssets(page,assets:(model as? [String:Any])?["assets"] as? [[String:Any]] ?? [],project:nil){[weak self] in guard let self=self else{return};self.payload["page"]=page;self.applyRuntimePage(page);self.assetsNeedReload=false;self.writeAudit(page,model:model as? [String:Any] ?? [:])}
 }

 func writeAudit(_ page:[String:Any],model:[String:Any]){
  guard ProcessInfo.processInfo.arguments.contains("--studio-audit") else{return}
  let report:[String:Any]=["scrollViews":scene.views.compactMapValues{item -> [String:Any]? in guard let scroll=item as? UIScrollView else{return nil};return ["contentHeight":scroll.contentSize.height,"height":scroll.bounds.height,"offset":scroll.contentOffset.y,"enabled":scroll.isScrollEnabled,"interaction":scroll.isUserInteractionEnabled]},"standalone":standalone,"route":page["id"] ?? "","nodes":scene.views.count,"imagesLoaded":images.count,"fontsDeclared":(model["assets"] as? [[String:Any]] ?? []).filter{$0["kind"] as? String=="font"}.count,"fontsLoaded":(model["assets"] as? [[String:Any]] ?? []).filter{$0["kind"] as? String=="font" && UIFont(name:$0["postscript"] as? String ?? "",size:16) != nil}.count,"labels":scene.views.values.compactMap{($0 as? UILabel)?.text},"nativeKinds":Array(Set(scene.kinds.values)).sorted(),"gradientLayers":scene.views.values.filter{$0.layer.sublayers?.contains(where:{$0.name=="studio.gradient"}) ?? false}.count]
  if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first{try? data.write(to:url.appendingPathComponent("studio-audit.json"),options:.atomic)}
 }
 func event(_ event:[String:Any]){
  if standalone{guard let model=payload["model"] as? [String:Any],let s=payload["session"] else{return};var e=event
   if event["type"]==nil,let id=event["node"] as? String,let d=(composedPage(model,s)?["events"] as? [String:[String:Any]])?[id]{e=d;if let value=event["value"]{e["value"]=value}}
   guard let next=call("reduce",[model,s,e]) else{return};payload["session"]=next;if let data=try? JSONSerialization.data(withJSONObject:next){UserDefaults.standard.set(data,forKey:"session.\(model["id"] ?? "app").\(model["stateVersion"] ?? 1)")};renderStandalone();return
  }
  var request:[String:Any] = ["side":"ios","event":event,"eventID":UUID().uuidString]
  if let project=payload["projectID"]{request["projectID"]=project}
  if let page=(payload["page"] as? [String:Any])?["id"]{request["pageID"]=page}
  if event["type"] as? String=="scroll",let last=eventQueue.last,let prior=last["event"] as? [String:Any],prior["type"] as? String=="scroll",prior["node"] as? String==event["node"] as? String,last["projectID"] as? String==request["projectID"] as? String,last["pageID"] as? String==request["pageID"] as? String{eventQueue[eventQueue.count-1]=request}else{eventQueue.append(request)};sendNext()
 }
 func sendNext(){guard !sending,!eventQueue.isEmpty else{return};sending=true;let e=eventQueue.removeFirst();Bridge.shared.json("/event",e){[weak self]_ in guard let self=self else{return};self.sending=false;self.poll();self.sendNext()}}
 func finishPoll(changed:Bool){
  busy=false;if changed{lastRuntimeChange=Date()}
  let budget:TimeInterval=Date().timeIntervalSince(lastRuntimeChange)<0.5 ? 1.0/60 : 0.12
  let interval=max(0.001,budget-Date().timeIntervalSince(pollStarted))
  timer?.invalidate();let next=Timer(timeInterval:interval,repeats:false){[weak self]_ in self?.poll()};timer=next;RunLoop.main.add(next,forMode:.common)
 }
 func poll(){guard !busy,!standalone else{return};timer?.invalidate();busy=true;pollStarted=Date()
  let project=payload["projectID"] as? String ?? "",hash=(payload["model"] as? [String:Any])?["hash"] as? String ?? ""
  Bridge.shared.request("/runtime?side=ios&after=\(revision)&project=\(project)&model=\(hash)"){[weak self]r in
  guard let self=self else{return};guard case .success(let data)=r,var p=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let page=p["page"] as? [String:Any],let next=p["revision"] as? Int else{self.finishPoll(changed:false);return}
  if p["reuseModel"] as? Bool==true{
   guard p["projectID"] as? String==self.payload["projectID"] as? String,p["modelHash"] as? String==(self.payload["model"] as? [String:Any])?["hash"] as? String else{self.payload=[:];self.revision = -1;self.finishPoll(changed:false);return}
   p["model"]=self.payload["model"];p["assets"]=self.payload["assets"]
  }
  if !self.assetsNeedReload,self.payload["projectID"] as? String==p["projectID"] as? String,(self.payload["model"] as? [String:Any])?["hash"] as? String==(p["model"] as? [String:Any])?["hash"] as? String,self.applyScrollOnly(page){
   self.payload=p;self.revision=next;self.finishPoll(changed:true);Bridge.shared.json("/ack",["side":"ios","revision":next]){_ in};return
  }
  self.loadPageAssets(page,assets:p["assets"] as? [[String:Any]] ?? [],project:p["projectID"] as? String ?? ""){[weak self] in
   guard let self=self else{return};if self.payload["projectID"] as? String != p["projectID"] as? String{self.presentedViewController?.dismiss(animated:false);self.eventQueue.removeAll();self.lastChromeInsets=CGPoint(x:-1,y:-1);self.lastChromeHeight = -1;self.lastChromeTargets=""}
   self.payload=p;self.applyRuntimePage(page);self.revision=next;self.finishPoll(changed:true);self.assetsNeedReload=false;self.writeAudit(page,model:p["model"] as? [String:Any] ?? [:]);Bridge.shared.json("/ack",["side":"ios","revision":next]){_ in}
  }
 }}
 /// A scroll does not need asset lookup, navigation reconstruction, or a full
 /// scene pass. Any other change continues through the normal rendering path.
 func applyScrollOnly(_ page:[String:Any])->Bool{
  guard let previous=payload["page"] as? [String:Any],page["animation"]==nil || page["animation"] is NSNull else{return false}
  func withoutOffsets(_ input:[String:Any])->[String:Any]{
   var copy=input;copy.removeValue(forKey:"animationID")
   copy["nodes"]=(input["nodes"] as? [[String:Any]] ?? []).map{n -> [String:Any] in var node=n;if node["type"] as? String=="scroll"{node.removeValue(forKey:"scrollX");node.removeValue(forKey:"scrollY")};return node}
   return copy
  }
  guard NSDictionary(dictionary:withoutOffsets(previous)).isEqual(to:withoutOffsets(page)) else{return false}
  scene.applyScrollOffsets(from:page);modalScene.applyScrollOffsets(from:page);return true
 }
 /// Load only dependencies of the rendered page (including overlays and edits).
 /// Four in-flight requests; old page images are released on navigation.
 func loadPageAssets(_ page:[String:Any],assets:[[String:Any]],project:String?,completion:@escaping()->Void){
  assetGeneration+=1;let generation=assetGeneration
  let nodes=page["nodes"] as? [[String:Any]] ?? []
  var sizes:[String:Int]=[:]
  for node in nodes {if let id=node["asset"] as? String,!id.isEmpty {let dimension=max((node["width"] as? Double ?? 402),(node["height"] as? Double ?? 874));sizes[id]=max(sizes[id] ?? 0,min(4096,max(64,Int(dimension*3))))}}
  let names=Set(nodes.compactMap{$0["fontName"] as? String})
  images=images.filter{sizes[$0.key] != nil};imagePixels=imagePixels.filter{sizes[$0.key] != nil}
  var seen=Set<String>()
  var pending=assets.filter {asset in
   guard let id=asset["id"] as? String,seen.insert(id).inserted else{return false}
   if asset["kind"] as? String=="font"{return names.contains(asset["postscript"] as? String ?? "") && !fonts.contains(id)}
   return sizes[id] != nil && (images[id]==nil || (imagePixels[id] ?? 0)<sizes[id]!)
  }
  var active=0
  func pump(){
   guard generation==self.assetGeneration else{return}
   if pending.isEmpty && active==0{completion();return}
   while active<4 && !pending.isEmpty {
    let asset=pending.removeLast();guard let id=asset["id"] as? String,let file=asset["file"] as? String else{continue};active+=1
    let pixels=sizes[id] ?? 1024
    let finish: (UIImage?)->Void = {image in
     guard generation==self.assetGeneration else{return}
     if let image=image{self.images[id]=image;self.imagePixels[id]=pixels}
     active-=1;pump()
    }
    let font=asset["kind"] as? String=="font"
    if let project=project {
     let path="/asset?project=\(project)&id=\(id)"
     if font {Bridge.shared.request(path){result in
      if case .success(let data)=result{let url=FileManager.default.temporaryDirectory.appendingPathComponent(file);do{try data.write(to:url);if CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil){self.fonts.insert(id)}}catch{print(error)}}
      finish(nil)
     }}else{Bridge.shared.image(path,maxPixels:pixels,completion:finish)}
    }else{
     let url=Bundle.main.url(forResource:file,withExtension:nil,subdirectory:"assets") ?? Bundle.main.url(forResource:file,withExtension:nil) ?? Bundle.main.bundleURL.appendingPathComponent(file)
     if font{if CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil){self.fonts.insert(id)};DispatchQueue.main.async{finish(nil)}}else if let catalogName=asset["catalogName"] as? String{AssetImages.queue.addOperation{let image=UIImage(named:catalogName)?.preparingThumbnail(of:CGSize(width:CGFloat(pixels),height:CGFloat(pixels)));DispatchQueue.main.async{finish(image)}}}else{AssetImages.load(url,maxPixels:pixels,completion:finish)}
    }
   }
  }
  pump()
 }
}
