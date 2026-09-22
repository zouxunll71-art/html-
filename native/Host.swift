import UIKit
import WebKit
import UniformTypeIdentifiers

final class ClientWebView: WKWebView {
 var passthrough=[CGRect]()
 var modal=false
 var pasteImage:(()->Bool)?
 override func paste(_ sender:Any?){
  evaluateJavaScript("document.activeElement?.id === 'prompt'"){[weak self] result,_ in
   guard let self=self else{return};if result as? Bool == true,self.pasteImage?() == true{return};self.pasteNormally(sender)
  }
 }
 private func pasteNormally(_ sender:Any?){super.paste(sender)}
 override func hitTest(_ point:CGPoint,with event:UIEvent?)->UIView? {
  if !modal && passthrough.contains(where:{$0.contains(point)}) {return nil}
  return super.hitTest(point,with:event)
 }
}
final class ClientHostController:UIViewController,WKScriptMessageHandler,WKNavigationDelegate,WKUIDelegate, UIDocumentPickerDelegate, UIDropInteractionDelegate {
 let editor=StudioController(),leftPanel=UIView(),rightPanel=UIView()
 var web:ClientWebView!
 var composerDropRect=CGRect.zero
 var folderDrop=UIView()
 var folderRequest:String?
 var pickerRequest:String?
 var embedded=false
 var currentProject:String?
 var projectLoading=false
 var mirrorTimer:Timer?
 var mirrorBusy=false
 override var keyCommands:[UIKeyCommand]?{let paste=UIKeyCommand(title:"粘贴",action:#selector(pasteClipboardShortcut),input:"v",modifierFlags:.command);paste.wantsPriorityOverSystemBehavior=true;return [paste]}
 @objc func pasteClipboardShortcut(){web.evaluateJavaScript("document.activeElement?.id === 'prompt'"){[weak self] value,_ in
  guard let self=self else{return};guard value as? Bool == true else{self.web.paste(nil);return}
  if self.web.pasteImage?() != true,let text=UIPasteboard.general.string,let data=try? JSONSerialization.data(withJSONObject:[text]),let json=String(data:data,encoding:.utf8){self.web.evaluateJavaScript("window.receiveClipboardText?.(\(json)[0])",completionHandler:nil)}
 }}
 override func viewDidLoad(){
  super.viewDidLoad();view.backgroundColor = .white
  let config=WKWebViewConfiguration();config.userContentController.add(self,name:"native")
  web=ClientWebView(frame:.zero,configuration:config);web.navigationDelegate=self;web.uiDelegate=self;web.isOpaque=false;web.backgroundColor = .clear;web.scrollView.backgroundColor = .clear;web.scrollView.isScrollEnabled=false;web.scrollView.bounces=false;web.clipsToBounds=true;web.scrollView.contentInsetAdjustmentBehavior = .never
  web.addInteraction(UIDropInteraction(delegate:self))
  view.addSubview(leftPanel);view.addSubview(rightPanel);view.addSubview(web)
  folderDrop.isHidden=true;folderDrop.backgroundColor = .clear;folderDrop.isAccessibilityElement=true;folderDrop.accessibilityLabel="选择项目文件夹，也可拖入文件夹";folderDrop.accessibilityTraits = .button;view.addSubview(folderDrop)
  folderDrop.addInteraction(UIDropInteraction(delegate:self));folderDrop.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(pickFolder)))
  leftPanel.clipsToBounds=true;rightPanel.clipsToBounds=true
  leftPanel.backgroundColor=UIColor(studioHex:"#F8FAFC");rightPanel.backgroundColor = .white
  web.pasteImage={[weak self] in
   guard let self=self,let image=UIPasteboard.general.image,let data=image.pngData() else{return false}
   let file=FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-"+UUID().uuidString+".png")
   do{try data.write(to:file);let json=String(data:try JSONSerialization.data(withJSONObject:[file.path]),encoding:.utf8)!;self.web.evaluateJavaScript("window.receiveComposerFiles?.(\(json))",completionHandler:nil);return true}catch{return false}
  }
  web.load(URLRequest(url:URL(string:"http://127.0.0.1:18777/?native=1")!))
  mirrorTimer=Timer.scheduledTimer(withTimeInterval:1.2,repeats:true){[weak self]_ in self?.pollMirror()}
 }
 func applyMirrorCommand(_ command:[String:Any]){
  let point=CGPoint(x:(command["x"] as? Double ?? 0)*view.bounds.width,y:(command["y"] as? Double ?? 0)*view.bounds.height),kind=command["kind"] as? String ?? ""
  if kind=="text"{
   let text=command["text"] as? String ?? ""
   if let input=editor.activeResponder(in:view) as? UITextField{input.text=text;input.sendActions(for:.editingChanged);input.sendActions(for:.editingDidEnd);return}
   if let input=editor.activeResponder(in:view) as? UITextView{input.text=text;return}
   let encoded=String(data:try! JSONSerialization.data(withJSONObject:[text]),encoding:.utf8)!
   web.evaluateJavaScript("(()=>{const e=document.activeElement;if(e&&(e.tagName==='INPUT'||e.tagName==='TEXTAREA')){e.value=\(encoded)[0];e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}))}})()",completionHandler:nil);return
  }
  guard let hit=view.hitTest(point,with:nil) else{return}
  var ancestor:UIView?=hit
  while let current=ancestor{
   if let browser=current as? WKWebView{
    let p=browser.convert(point,from:view),dy=command["dy"] as? Double ?? 0
    browser.evaluateJavaScript("(()=>{let e=document.elementFromPoint(\(p.x),\(p.y));if(!e)return;if('\(kind)'==='scroll'){while(e&&e.scrollHeight<=e.clientHeight)e=e.parentElement;(e||document.scrollingElement).scrollBy(0,\(dy))}else{e.focus?.();e.click?.()}})()",completionHandler:nil);return
   }
   if kind=="click",let canvas=current as? ClientCanvasScrollView,hit === canvas{canvas.onBackgroundTap?();return}
   if kind=="click",let workspace=current as? StudioWorkspace,hit === workspace{workspace.onBackgroundTap?();return}
   if kind=="scroll",let scroll=current as? UIScrollView{let dy=command["dy"] as? Double ?? 0;scroll.setContentOffset(CGPoint(x:scroll.contentOffset.x,y:max(0,min(scroll.contentSize.height-scroll.bounds.height,scroll.contentOffset.y+dy))),animated:false);return}
   if kind=="click",let field=current as? UITextField{field.becomeFirstResponder();return}
   if kind=="click",let button=current as? UIButton{button.sendActions(for:.touchUpInside);return}
   if kind=="click",let segment=current as? UISegmentedControl{let p=segment.convert(point,from:view);segment.selectedSegmentIndex=min(segment.numberOfSegments-1,max(0,Int(p.x/segment.bounds.width*CGFloat(segment.numberOfSegments))));segment.sendActions(for:.valueChanged);return}
   if let surface=current as? DeviceSurface,kind=="click"{let p=surface.logical(surface.convert(point,from:view));if surface.operate{if surface === editor.left && editor.simulatorInput.ready{surface.onPointer?("down",p);surface.onPointer?("up",p)}else{surface.onTap?(p)}}else{surface.selected=surface.hit(p)?.id;surface.onSelect?(surface.selected)};return}
   ancestor=current.superview
  }
 }
 func pollMirror(){
  guard !mirrorBusy,view.window != nil else{return};mirrorBusy=true
  var request=URLRequest(url:URL(string:"http://127.0.0.1:18777/api/mirror/demand")!);request.setValue(Bridge.shared.token,forHTTPHeaderField:"x-studio-token");request.timeoutInterval=3
  URLSession.shared.dataTask(with:request){[weak self] data,_,_ in DispatchQueue.main.async{
   guard let self=self else{return};guard let data=data,let response=try? JSONSerialization.jsonObject(with:data) as? [String:Any],response["active"] as? Bool==true else{self.mirrorBusy=false;return}
   for command in response["commands"] as? [[String:Any]] ?? []{self.applyMirrorCommand(command)}
   let config=WKSnapshotConfiguration();config.afterScreenUpdates=false
   self.web.takeSnapshot(with:config){[weak self] overlay,_ in
    guard let self=self else{return};let format=UIGraphicsImageRendererFormat();format.scale=1
    let image=UIGraphicsImageRenderer(bounds:self.view.bounds,format:format).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:false);overlay?.draw(in:self.web.frame)}
    guard let jpeg=image.jpegData(compressionQuality:0.85) else{self.mirrorBusy=false;return}
    var upload=URLRequest(url:URL(string:"http://127.0.0.1:18777/api/mirror/frame")!);upload.httpMethod="POST";upload.setValue(Bridge.shared.token,forHTTPHeaderField:"x-studio-token");upload.httpBody=jpeg;upload.timeoutInterval=3
    URLSession.shared.dataTask(with:upload){[weak self] _,_,_ in DispatchQueue.main.async{self?.mirrorBusy=false}}.resume()
   }
  }}.resume()
 }
 override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();let frame=view.safeAreaLayoutGuide.layoutFrame;guard web.frame != frame else{return};web.frame=frame;web.evaluateJavaScript("window.reportNativeLayout?.(true)",completionHandler:nil)}
 func embed(){
  guard !embedded else{return};embedded=true;editor.clientEmbedded=true
  addChild(editor);editor.view.clipsToBounds=true;view.insertSubview(editor.view,belowSubview:web);editor.didMove(toParent:self)
  editor.clientLeftContainer=leftPanel;editor.clientRightContainer=rightPanel
  leftPanel.addSubview(editor.sidebar)
  leftPanel.addSubview(editor.clientToolsScroll)
  editor.clientToolsScroll.alwaysBounceVertical=true
  for child in [editor.toolbar,editor.mode,editor.copyButton,editor.syncStateLabel,editor.repairSyncButton,editor.runIOSButton] as [UIView]{editor.clientToolsScroll.addSubview(child)}
  editor.workspace.addSubview(editor.clientEditingScroll);editor.clientEditingScroll.addSubview(editor.editingTools)
  editor.clientEditingScroll.showsVerticalScrollIndicator=false;editor.clientEditingScroll.alwaysBounceVertical=false
  editor.editingTools.axis = .vertical;editor.editingTools.spacing=4;editor.editingTools.distribution = .fillEqually
  editor.editingTools.arrangedSubviews.forEach{editor.editingTools.removeArrangedSubview($0);$0.removeFromSuperview()};editor.toolButtons.removeAll()
  for (key,title) in [("select","选择"),("clickMulti","多选"),("multi","框选"),("move","移动"),("resize","缩放"),("rotate","旋转")]{
   let button=editor.button(title,{[weak self] in self?.editor.setTool(key)});editor.toolButtons[key]=button;editor.editingTools.addArrangedSubview(button)
  }
  for (title,action) in [("＋",{[weak self] ()->Void in self?.editor.resizeSelectedResources(by:1.1)}),("−",{[weak self] ()->Void in self?.editor.resizeSelectedResources(by:1/1.1)}),("撤销",{[weak self] ()->Void in self?.editor.undo()}),("重做",{[weak self] ()->Void in self?.editor.redo()}),("组合",{[weak self] ()->Void in self?.editor.groupSelection()}),("解组",{[weak self] ()->Void in self?.editor.ungroupSelection()}),("选框色",{[weak self] ()->Void in self?.editor.pickSelectionColor()})]{editor.editingTools.addArrangedSubview(editor.button(title,action))}
  editor.moreTools.setTitle("更多",for:.normal);editor.moreTools.configuration?.title="更多";editor.editingTools.addArrangedSubview(editor.moreTools)
  for child in editor.editingTools.arrangedSubviews{
   guard let button=child as? UIButton else{continue}
   let title=button.configuration?.title ?? button.title(for:.normal) ?? "工具"
   for constraint in button.constraints where constraint.firstAttribute == .height{constraint.isActive=false}
   button.accessibilityLabel=title=="＋" ? "放大选中资源" : title=="−" ? "缩小选中资源" : title;button.setTitle(title,for:.normal)
   button.configuration?.image=nil;button.configuration?.title=title
   button.configuration?.contentInsets=NSDirectionalEdgeInsets(top:3,leading:2,bottom:3,trailing:2)
   button.configuration?.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer{var a=$0;a.font = .systemFont(ofSize:11,weight:.medium);return a}
   button.heightAnchor.constraint(equalToConstant:30).isActive=true
  }
  for child in [editor.inspector,editor.sourceBrowser,editor.iosBrowser,editor.inspectorTabs] as [UIView]{rightPanel.addSubview(child)}
  editor.setTool("select")
  editor.clientPhoneScroll.onBackgroundTap={[weak self] in self?.editor.workspace.onBackgroundTap?()}
  editor.workspace.addSubview(editor.clientPhoneScroll);editor.clientPhoneScroll.backgroundColor = .clear;editor.clientPhoneScroll.delaysContentTouches=false;editor.clientPhoneScroll.canCancelContentTouches=false
  for child in [editor.left,editor.right,editor.leftTitle,editor.rightTitle,editor.leftTools,editor.simulatorTools,editor.androidBack,editor.sourcePageButton,editor.closeWebButton] as [UIView]{editor.clientPhoneScroll.addSubview(child)}
  editor.workspace.bringSubviewToFront(editor.extractionProgress)
  editor.clientSyncChanged={[weak self] text in guard let data=try? JSONSerialization.data(withJSONObject:[text]),let json=String(data:data,encoding:.utf8) else{return};self?.web.evaluateJavaScript("window.receiveSyncStatus?.(\(json)[0])",completionHandler:nil)}
  editor.clientModeChanged={[weak self] running in self?.web.evaluateJavaScript("window.receivePreviewMode?.(\(running))",completionHandler:nil)}
  editor.clientModeChanged?(editor.running)
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
  case "iosToolbar":
   guard embedded,editor.project != nil else{return}
   switch body["command"] as? String{case "run":editor.runIOS();case "link":editor.copyAllPages();case "repair":editor.repairSynchronization();case "details":editor.showSyncDetails();default:break}
  case "previewMode":
   embed();guard let running=body["running"] as? Bool else{return};editor.mode.selectedSegmentIndex=running ? 1:0;editor.toggleRun()
  case "pasteClipboard":
   if web.pasteImage?() != true,let text=UIPasteboard.general.string,let data=try? JSONSerialization.data(withJSONObject:[text]),let json=String(data:data,encoding:.utf8){web.evaluateJavaScript("window.receiveClipboardText?.(\(json)[0])",completionHandler:nil)}
  case "copyImage":
   guard let raw=body["data"] as? String,let comma=raw.firstIndex(of:","),let data=Data(base64Encoded:String(raw[raw.index(after:comma)...])),let image=UIImage(data:data) else{web.evaluateJavaScript("window.imageCopyFinished?.(false)",completionHandler:nil);return}
   UIPasteboard.general.image=image;web.evaluateJavaScript("window.imageCopyFinished?.(true)",completionHandler:nil)
  case "chooseProjectFolder":
   folderRequest=body["requestId"] as? String;pickFolder()
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
   composerDropRect=body["composerDrop"] is [String:Double] ? web.convert(rect(body["composerDrop"]),from:view):.zero
   if let drop=body["projectDrop"] as? [String:Any],let request=drop["requestId"] as? String {
    folderRequest=request;folderDrop.frame=rect(drop.filter{$0.key != "requestId"});folderDrop.isHidden=false
   }else{folderRequest=nil;folderDrop.isHidden=true}
   embed();let center=rect(body["center"]),left=rect(body["left"]),right=rect(body["right"])
   let resized=editor.view.frame != center || leftPanel.frame != left || rightPanel.frame != right
   editor.view.frame=center;leftPanel.frame=left;rightPanel.frame=right
   leftPanel.isHidden=body["leftNative"] as? Bool != true;rightPanel.isHidden=body["rightNative"] as? Bool != true
   editor.sidebar.isHidden=body["leftMode"] as? String != "library";editor.clientToolsScroll.isHidden=body["leftMode"] as? String != "tools"
   let preview=body["preview"] as? Bool ?? true;editor.view.isHidden = !preview
   web.modal=body["modal"] as? Bool ?? false;web.passthrough=preview ? [web.convert(center,from:view)]:[]
   if !leftPanel.isHidden{web.passthrough.append(web.convert(left,from:view))};if !rightPanel.isHidden{web.passthrough.append(web.convert(right,from:view))}
   if resized{editor.view.setNeedsLayout();editor.view.layoutIfNeeded()}
   view.bringSubviewToFront(web);view.bringSubviewToFront(folderDrop)
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
 @objc func pickFolder(){
  guard let request=folderRequest,presentedViewController==nil else{return};pickerRequest=request
  let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.folder],asCopy:false)
  picker.allowsMultipleSelection=false;picker.delegate=self;present(picker,animated:true)
 }
 func deliverFolder(_ url:URL?,request:String,error:String?=nil){
  var path="",failure=error ?? ""
  if let url=url {
   let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
   if url.isFileURL,(try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true{path=url.standardizedFileURL.path}
   else{failure="请拖入文件夹，不能添加普通文件。"}
  }
  let args=(try? JSONSerialization.data(withJSONObject:[request,path,failure])).flatMap{String(data:$0,encoding:.utf8)} ?? "[]"
  web.evaluateJavaScript("window.receiveProjectFolder?.(...\(args))",completionHandler:nil)
 }
 func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]){
  guard let request=pickerRequest else{return};pickerRequest=nil;deliverFolder(urls.first,request:request)
 }
 func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController){pickerRequest=nil}
 func dropInteraction(_ interaction:UIDropInteraction,canHandle session:UIDropSession)->Bool{
  return (interaction.view===folderDrop ? folderRequest != nil : !composerDropRect.isEmpty) && session.hasItemsConforming(toTypeIdentifiers:[UTType.fileURL.identifier])
 }
 func dropInteraction(_ interaction:UIDropInteraction,sessionDidUpdate session:UIDropSession)->UIDropProposal{UIDropProposal(operation:interaction.view===folderDrop || composerDropRect.contains(session.location(in:web)) ? .copy:.forbidden)}
 func dropInteraction(_ interaction:UIDropInteraction,performDrop session:UIDropSession){
  if interaction.view===web {
   guard composerDropRect.contains(session.location(in:web)) else{return}
   guard session.items.count<=6 else{web.evaluateJavaScript("window.composerDropError?.('每次最多附加 6 个文件或文件夹')",completionHandler:nil);return}
   let group=DispatchGroup();let lock=NSLock();var paths=[Int:String]()
   for (index,item) in session.items.enumerated(){group.enter();item.itemProvider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil){value,error in
    let url:URL?;if let u=value as? URL{url=u}else if let data=value as? Data{url=URL(dataRepresentation:data,relativeTo:nil)}else{url=nil}
    if let url=url,url.isFileURL{lock.lock();paths[index]=url.path;lock.unlock()};group.leave()
   }}
   group.notify(queue:.main){[weak self] in
    guard let self=self else{return};if paths.count != session.items.count{self.web.evaluateJavaScript("window.composerDropError?.('无法读取拖入文件，请重新拖入')",completionHandler:nil);return}
    let ordered=paths.keys.sorted().compactMap{paths[$0]};let json=(try? JSONSerialization.data(withJSONObject:ordered)).flatMap{String(data:$0,encoding:.utf8)} ?? "[]"
    self.web.evaluateJavaScript("window.receiveComposerFiles?.(\(json))",completionHandler:nil)
   };return
  }
  guard let request=folderRequest else{return}
  guard session.items.count==1,let provider=session.items.first?.itemProvider else{deliverFolder(nil,request:request,error:"请一次拖入一个项目文件夹。");return}
  provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil){[weak self] item,error in
   let url:URL?
   if let value=item as? URL{url=value}else if let data=item as? Data{url=URL(dataRepresentation:data,relativeTo:nil)}else{url=nil}
   DispatchQueue.main.async{self?.deliverFolder(url,request:request,error:url==nil ? "无法读取文件夹，请点击选择文件夹。":nil)}
  }
 }
 func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){view.setNeedsLayout();view.layoutIfNeeded();web.evaluateJavaScript("window.reportNativeLayout?.(true)",completionHandler:nil)}
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
 override func buildMenu(with builder:UIMenuBuilder){
  super.buildMenu(with:builder)
  builder.replaceChildren(ofMenu:.standardEdit){children in children.map{element in
   if let command=element as? UICommand,command.action == #selector(UIResponderStandardEditActions.paste(_:)){return UIKeyCommand(title:"粘贴",action:#selector(ClientHostController.pasteClipboardShortcut),input:"v",modifierFlags:.command)}
   return element
  }}
 }

 func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {
  let w=UIWindow(frame:UIScreen.main.bounds);w.rootViewController=ClientHostController();w.overrideUserInterfaceStyle = .light;w.makeKeyAndVisible();window=w
  if let scene=w.windowScene {scene.sizeRestrictions?.minimumSize=CGSize(width:1100,height:780);scene.sizeRestrictions?.maximumSize=CGSize(width:3000,height:1900)}
  return true
 }
}
