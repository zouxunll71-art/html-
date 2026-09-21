import UIKit
import WebKit

final class ClientWebView: WKWebView {
 var passthrough=[CGRect]()
 var modal=false
 override func hitTest(_ point:CGPoint,with event:UIEvent?)->UIView? {
  if !modal && passthrough.contains(where:{$0.contains(point)}) {return nil}
  return super.hitTest(point,with:event)
 }
}
final class ClientHostController:UIViewController,WKScriptMessageHandler,WKNavigationDelegate,WKUIDelegate {
 let editor=StudioController(),leftPanel=UIView(),rightPanel=UIView()
 var web:ClientWebView!
 var embedded=false
 var currentProject:String?
 var projectLoading=false
 override func viewDidLoad(){
  super.viewDidLoad();view.backgroundColor = .white
  let config=WKWebViewConfiguration();config.userContentController.add(self,name:"native")
  web=ClientWebView(frame:.zero,configuration:config);web.navigationDelegate=self;web.uiDelegate=self;web.isOpaque=false;web.backgroundColor = .clear;web.scrollView.backgroundColor = .clear;web.scrollView.isScrollEnabled=false;web.scrollView.contentInsetAdjustmentBehavior = .never
  view.addSubview(leftPanel);view.addSubview(rightPanel);view.addSubview(web)
  leftPanel.backgroundColor=UIColor(studioHex:"#F8FAFC");rightPanel.backgroundColor = .white
  web.load(URLRequest(url:URL(string:"http://127.0.0.1:18777/?native=1")!))
 }
 override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();let frame=view.safeAreaLayoutGuide.layoutFrame;guard web.frame != frame else{return};web.frame=frame;web.evaluateJavaScript("window.reportNativeLayout?.()",completionHandler:nil)}
 func embed(){
  guard !embedded else{return};embedded=true;editor.clientEmbedded=true
  addChild(editor);view.insertSubview(editor.view,belowSubview:web);editor.didMove(toParent:self)
  editor.clientLeftContainer=leftPanel;editor.clientRightContainer=rightPanel
  leftPanel.addSubview(editor.sidebar)
  leftPanel.addSubview(editor.clientToolsScroll)
  editor.clientToolsScroll.alwaysBounceVertical=true
  for child in [editor.toolbar,editor.mode,editor.copyButton,editor.syncStateLabel,editor.repairSyncButton,editor.runIOSButton,editor.editingTools] as [UIView]{editor.clientToolsScroll.addSubview(child)}
  editor.editingTools.axis = .vertical
  for child in [editor.inspector,editor.sourceBrowser,editor.iosBrowser,editor.inspectorTabs] as [UIView]{rightPanel.addSubview(child)}
  editor.workspace.addSubview(editor.clientPhoneScroll);editor.clientPhoneScroll.backgroundColor = .clear;editor.clientPhoneScroll.delaysContentTouches=false;editor.clientPhoneScroll.canCancelContentTouches=false
  for child in [editor.left,editor.right,editor.leftTitle,editor.rightTitle,editor.leftTools,editor.simulatorTools,editor.androidBack,editor.sourcePageButton,editor.closeWebButton] as [UIView]{editor.clientPhoneScroll.addSubview(child)}
  editor.workspace.bringSubviewToFront(editor.extractionProgress)
  editor.clientShowInspector={[weak self] in self?.web.evaluateJavaScript("window.setClientPanel?.('right','properties')",completionHandler:nil)}
  editor.clientProjectChanged={[weak self] id in
   guard let self=self else{return};self.currentProject=id
   let encoded=(try? JSONSerialization.data(withJSONObject:[id])).flatMap{String(data:$0,encoding:.utf8)} ?? "[]"
   self.web.evaluateJavaScript("window.nativeProjectChanged?.(\(encoded)[0])",completionHandler:nil)
  }
 }
 func rect(_ value:Any?)->CGRect {
  guard let r=value as? [String:Double] else{return .zero}
  return CGRect(x:(r["x"] ?? 0)+web.frame.minX,y:(r["y"] ?? 0)+web.frame.minY,width:max(0,r["width"] ?? 0),height:max(0,r["height"] ?? 0)).intersection(view.bounds)
 }
 func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){
  guard message.frameInfo.isMainFrame,let body=message.body as? [String:Any] else{return}
  switch body["action"] as? String {
  case "captureAnnotation":
   guard embedded,!editor.view.isHidden,editor.view.bounds.width>0 else {web.evaluateJavaScript("window.receiveAnnotationCapture?.(null)",completionHandler:nil);return}
   let format=UIGraphicsImageRendererFormat();format.scale=view.window?.screen.scale ?? 2;format.opaque=true
   let image=UIGraphicsImageRenderer(bounds:editor.view.bounds,format:format).image { context in
    UIColor.white.setFill();context.fill(editor.view.bounds)
    editor.view.drawHierarchy(in:editor.view.bounds,afterScreenUpdates:true)
   }
   if let data=image.pngData(){
    let value="data:image/png;base64,"+data.base64EncodedString()
    web.evaluateJavaScript("window.receiveAnnotationCapture?.('\(value)')",completionHandler:nil)
   }else{web.evaluateJavaScript("window.receiveAnnotationCapture?.(null)",completionHandler:nil)}
  case "layout":
   embed();let center=rect(body["center"]),left=rect(body["left"]),right=rect(body["right"])
   let resized=editor.view.frame != center || leftPanel.frame != left || rightPanel.frame != right
   editor.view.frame=center;leftPanel.frame=left;rightPanel.frame=right
   leftPanel.isHidden=body["leftNative"] as? Bool != true;rightPanel.isHidden=body["rightNative"] as? Bool != true
   editor.sidebar.isHidden=body["leftMode"] as? String != "library";editor.clientToolsScroll.isHidden=body["leftMode"] as? String != "tools"
   let preview=body["preview"] as? Bool ?? true;editor.view.isHidden = !preview
   web.modal=body["modal"] as? Bool ?? false;web.passthrough=preview ? [web.convert(center,from:view)]:[]
   if !leftPanel.isHidden{web.passthrough.append(web.convert(left,from:view))};if !rightPanel.isHidden{web.passthrough.append(web.convert(right,from:view))}
   if resized{editor.view.setNeedsLayout();editor.view.layoutIfNeeded()}
  case "project":
   guard let id=body["id"] as? String,currentProject != id,!projectLoading else{return};projectLoading=true
   Bridge.shared.request("/projects"){[weak self] result in guard let self=self else{return};self.projectLoading=false;if case .success(let data)=result,let projects=try? JSONDecoder().decode([StudioProject].self,from:data),let p=projects.first(where:{$0.id==id}){self.currentProject=id;self.editor.useProject(p)}}
  case "zoom":
   if let zoom=body["value"] as? Double{editor.clientZoom=CGFloat(min(1.5,max(0.35,zoom)))}
   editor.clientFit=body["fit"] as? Bool ?? false;editor.view.setNeedsLayout()
  case "openURL":
   if let raw=body["url"] as? String,let url=URL(string:raw),["https","http"].contains(url.scheme ?? ""){UIApplication.shared.open(url)}
  default:break
  }
 }
 func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){web.evaluateJavaScript("window.reportNativeLayout?.()",completionHandler:nil)}
 func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
  guard let url=action.request.url else{decisionHandler(.cancel);return}
  if url.host=="127.0.0.1" && url.port==18777 || url.scheme=="about" || url.scheme=="blob" {decisionHandler(.allow);return}
  if action.navigationType == .linkActivated,["https","http"].contains(url.scheme ?? ""){UIApplication.shared.open(url)}
  decisionHandler(.cancel)
 }
 func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for action:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView?{
  if let url=action.request.url,["https","http"].contains(url.scheme ?? ""){UIApplication.shared.open(url)};return nil
 }
}
@main final class AppDelegate:UIResponder,UIApplicationDelegate {
 var window:UIWindow?
 func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {
  let w=UIWindow(frame:UIScreen.main.bounds);w.rootViewController=ClientHostController();w.overrideUserInterfaceStyle = .light;w.makeKeyAndVisible();window=w
  if let scene=w.windowScene {scene.sizeRestrictions?.minimumSize=CGSize(width:1100,height:780);scene.sizeRestrictions?.maximumSize=CGSize(width:3000,height:1900)}
  return true
 }
}
