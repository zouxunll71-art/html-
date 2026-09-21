import UIKit
import WebKit
import UniformTypeIdentifiers
import CoreText
final class StudioController:UIViewController,UITableViewDataSource,UITableViewDelegate,UITableViewDragDelegate,UIDocumentPickerDelegate,UIDropInteractionDelegate,UITextFieldDelegate,UIColorPickerViewControllerDelegate,WKScriptMessageHandler {
 let inspectorTabs=UISegmentedControl(items:["iOS 属性","HTML 资源","iOS 图层"]),sourceBrowser=SourceBrowser(),iosBrowser=SourceBrowser(),thumbnailScene=NativeSceneController()
 let repairSyncButton=UIButton(type:.system),runIOSButton=UIButton(type:.system),closeWebButton=UIButton(type:.system)
 var iosRunJob:String?;var exportJobID:String?
 var repairingSync=false
 let helpButton=UIButton(type:.system),moreTools=UIButton(type:.system),moreProject=UIButton(type:.system),syncStateLabel=UILabel(),sourcePageButton=UIButton(type:.system)
 var sourceNodes=[StudioNode](),sourceFrame:[String:Any]=[:],sourceSignature="",sourceThumbnails=[String:UIImage](),sourcePendingAssets=Set<String>(),sourceLoadedFonts=Set<String>(),sourceLoading=false,pendingSourceFocus:String?,sourceFrameRevision = -1,statusHoldUntil=Date.distantPast
 var sourceThumbnailWork:DispatchWorkItem?
 let scrollRelay=ScrollRelay()
 let simulatorInput=SimulatorInput(),simulatorTools=UIStackView()
 let web=WKWebView(frame:.zero,configuration:WKWebViewConfiguration());var observedRevision = -1;var liveStatusBusy=false;var activePage="";var linked=true;var running=false;var rawScene:[String:Any]=[:];var syncRevision=0
 let editingTools=UIStackView();var toolButtons:[String:UIButton]=[:];let iosFrames=IOSFrames();let androidFrames=IOSFrames();let androidBack=UIButton(type:.system);var lastPreview=Date.distantPast
 let toolbar=UIView(),sidebar=UIView(),inspector=UIScrollView(),workspace=StudioWorkspace(),footer=UILabel()
 let titleLabel=UILabel(),projectButton=UIButton(type:.system),segments=UISegmentedControl(items:["页面","资源","原生组件"]),search=UISearchBar()
 let catalog=UITableView(frame:.zero,style:.plain),layers=UITableView(frame:.zero,style:.plain)
 let left=DeviceSurface(),right=DeviceSurface(),leftTitle=UILabel(),rightTitle=UILabel(),syncLabel=UILabel(),hint=UILabel()
 let mode=UISegmentedControl(items:["编辑","运行"]),copyButton=UIButton(type:.system),refreshButton=UIButton(type:.system)
 let splashButton=UIButton(type:.system);var splashPinned=false;var splashRequestBusy=false
 let extractionProgress=ExtractionProgress();let propertyStack=UIStackView();let leftTools=UIStackView();var fields:[String:UITextField]=[:]
 var snappingEnabled = !UserDefaults.standard.bool(forKey:"disableAlignmentSnapping")
 var snapCorrection=CGPoint.zero
 var project:StudioProject?;var pageIndex=0;var multiSelection=Set<String>();var selected:String? {didSet{if selected==nil || !multiSelection.contains(selected!){multiSelection=[]}}};var sourceSelected:String?;var source:AndroidSnapshot?
 var pendingAssets=Set<String>();var assets:[StudioAsset]=[];let assetCache=AssetImageCache();let libraryThumbs=AssetImageCache(megabytes:16);var undoStates:[Data]=[] {didSet{updateHistoryButtons()}};var redoStates:[Data]=[] {didSet{updateHistoryButtons()}}
 var editGeneration=0;var saveInFlight=false
 var screenTimer:Timer?;var iosBusy=false;var androidBusy=false;var snapshotBusy=false;var dirty=false;var saveTimer:Timer?;var previewTimer:Timer?;var isolatedSelection:String?;var previewInFlight=false;var pendingPreview:[String:Any]?;var historyGesture=false;var syncing=true
 var bulkTimer:Timer?;var bulkRunning=false;var progressDismissTimer:Timer?
 var buildTimer:Timer?;var routeTimer:Timer?;var routeTick=0
 var statusMessage="正在连接本机服务…";var buttons:[UIButton]=[];var zoom:CGFloat=1
 var isManifest:Bool {false}
 var page:StudioPage? {guard let p=project,p.pages.indices.contains(pageIndex)else{return nil};return p.pages[pageIndex]}
 override func viewDidLoad(){super.viewDidLoad();view.backgroundColor = .white;buildUI();loadProjects()
  screenTimer=Timer.scheduledTimer(withTimeInterval:0.35,repeats:true){[weak self]_ in self?.refreshScreens();self?.pollRoute()}
  view.addInteraction(UIDropInteraction(delegate:self));setupHTML();iosFrames.imageView=left.imageView;iosFrames.start()
 }
 func label(_ text:String,_ size:CGFloat=13,_ weight:UIFont.Weight = .regular)->UILabel{let l=UILabel();l.text=text;l.font = .systemFont(ofSize:size,weight:weight);l.textColor=UIColor(studioHex:"#263240");return l}
 func button(_ text:String,_ action:@escaping()->Void)->UIButton{let b=UIButton(type:.system);var c=UIButton.Configuration.bordered();c.title=text;c.baseForegroundColor=UIColor(studioHex:"#263240");c.cornerStyle = .medium;c.contentInsets=NSDirectionalEdgeInsets(top:7,leading:10,bottom:7,trailing:10);b.configuration=c;b.addAction(UIAction{_ in action()},for:.touchUpInside);return b}
 var nativeEntries:[NativeEntry]{let term=search.text ?? "";return NativeEntry.all.filter{term.isEmpty || $0.title.localizedCaseInsensitiveContains(term) || $0.detail.localizedCaseInsensitiveContains(term)}}
 func buildUI(){
  for v in [toolbar,sidebar,workspace,inspector,footer]{view.addSubview(v)}
  toolbar.backgroundColor = .white;sidebar.backgroundColor=UIColor(studioHex:"#F8F9FB");workspace.backgroundColor=UIColor(studioHex:"#EEF0F3");inspector.backgroundColor = .white
  titleLabel.text="HTML → 原生 iOS";titleLabel.font = .systemFont(ofSize:19,weight:.semibold);toolbar.addSubview(titleLabel)
  projectButton.setTitle("选择项目 ▾",for:.normal);projectButton.addAction(UIAction{[weak self]_ in self?.chooseProject()},for:.touchUpInside);toolbar.addSubview(projectButton)
  buttons=[button("导入项目",{[weak self] in self?.importProject()}),button("HTML 模板",{[weak self] in self?.showAuthoringKit()}),button("撤销",{[weak self] in self?.undo()}),button("重做",{[weak self] in self?.redo()}),button("版本记录",{[weak self] in self?.versions()}),button("保存布局",{[weak self] in self?.save()}),button("导出 UIKit",{[weak self] in self?.export()})]
  buttons.last?.configuration?.baseBackgroundColor = .systemBlue;buttons.last?.configuration?.baseForegroundColor = .white
  buttons.forEach{toolbar.addSubview($0)}
  segments.selectedSegmentIndex=0;segments.addAction(UIAction{[weak self]_ in self?.reloadCatalog()},for:.valueChanged);sidebar.addSubview(segments)
  search.placeholder="搜索页面或原始资源";search.searchBarStyle = .minimal;search.searchTextField.addTarget(self,action:#selector(searchChanged),for:.editingChanged);sidebar.addSubview(search)
  for t in [catalog,layers]{t.dataSource=self;t.delegate=self;t.backgroundColor = .clear;t.separatorStyle = .none;t.rowHeight=42;sidebar.addSubview(t)}
  layers.rowHeight=64
  catalog.dragDelegate=self;catalog.dragInteractionEnabled=true
  let layerTitle=label("图层",13,.semibold);layerTitle.tag=99;sidebar.addSubview(layerTitle)
  let add=button("＋ 空白页",{[weak self] in self?.newPage()});add.tag=98;sidebar.addSubview(add)
  for v in [left,right,leftTitle,rightTitle,syncLabel,hint,mode,copyButton,refreshButton,splashButton,leftTools,androidBack,editingTools]{workspace.addSubview(v)}
  leftTitle.text="iOS · 真实模拟器";rightTitle.text="HTML · 即时预览"
  for l in [leftTitle,rightTitle]{l.font = .systemFont(ofSize:14,weight:.semibold);l.textAlignment = .center}
  syncLabel.font = .systemFont(ofSize:12);syncLabel.textColor = .secondaryLabel;syncLabel.textAlignment = .center
  hint.font = .systemFont(ofSize:12);hint.textColor = .secondaryLabel;hint.textAlignment = .center;hint.numberOfLines=2
  right.webHosted=true;mode.setTitle("编辑",forSegmentAt:0);mode.setTitle("运行",forSegmentAt:1);mode.selectedSegmentIndex=0;mode.addAction(UIAction{[weak self]_ in self?.toggleRun()},for:.valueChanged)
  copyButton.setTitle("两端联动",for:.normal);copyButton.addAction(UIAction{[weak self]_ in self?.copyAllPages()},for:.touchUpInside)
  copyButton.menu=nil
  splashButton.setTitle("编辑启动页",for:.normal);splashButton.addAction(UIAction{[weak self]_ in self?.toggleSplashEditor()},for:.touchUpInside)
  refreshButton.setTitle("源码 / 同步详情",for:.normal);refreshButton.addAction(UIAction{[weak self]_ in guard let self=self else{return};if self.splashPinned{self.toggleSplashEditor(forceOpen:true)}else{self.refreshSnapshot()}},for:.touchUpInside)
  androidBack.setTitle("← 返回",for:.normal);androidBack.addAction(UIAction{[weak self]_ in self?.dispatchEvent(["type":"back"],side:"web")},for:.touchUpInside)
  editingTools.axis = .vertical;editingTools.spacing=8
  for (key,title,icon) in [("select","选择","cursorarrow"),("clickMulti","点击多选","checkmark.circle"),("multi","框选","square.dashed"),("move","移动","arrow.up.and.down.and.arrow.left.and.right"),("resize","缩放","arrow.up.left.and.arrow.down.right"),("rotate","旋转","rotate.right")] {
   let b=button(title,{[weak self]in self?.setTool(self?.left.tool==key && key=="clickMulti" ? "select" : key)});b.configuration?.image=UIImage(systemName:icon);b.configuration?.imagePlacement = .top;b.configuration?.imagePadding=5;b.configuration?.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer{var a=$0;a.font = .systemFont(ofSize:11);return a};b.heightAnchor.constraint(equalToConstant:54).isActive=true;editingTools.addArrangedSubview(b);toolButtons[key]=b
  }
  for (title,action) in [("组合",{[weak self] () -> Void in self?.groupSelection()}),("解组",{[weak self] () -> Void in self?.ungroupSelection()})] {let b=button(title,action);b.configuration?.contentInsets=NSDirectionalEdgeInsets(top:7,leading:3,bottom:7,trailing:3);editingTools.addArrangedSubview(b)}
  let colorButton=button("选框色",{[weak self]in self?.pickSelectionColor()});colorButton.configuration?.image=UIImage(systemName:"paintpalette");colorButton.configuration?.imagePlacement = .top;colorButton.configuration?.imagePadding=5;editingTools.addArrangedSubview(colorButton)
  setTool("select")
  leftTools.axis = .horizontal;leftTools.spacing=7;leftTools.distribution = .fillEqually
  [button("↶ 上一步",{[weak self]in self?.undo()}),button("↷ 下一步",{[weak self]in self?.redo()}),button("＋ 文字",{[weak self] in self?.addText()}),button("＋ 色块",{[weak self] in self?.addShape()})].forEach{leftTools.addArrangedSubview($0)}
  left.onSelect={[weak self] id in self?.chooseLayer(id)}
  left.onMarquee={[weak self] rect in self?.selectRegion(rect)}
  left.onMove={[weak self] id,delta,kind,end in self?.move(id,delta,kind,end)}
  left.onDrop={[weak self] payload,point in self?.drop(payload,point)}
  right.previewAsset={[weak self] id in self?.assetCache[id]}
  right.onSelect={[weak self] id in
   guard let self=self else{return};self.selected=nil;self.left.selected=nil;self.left.selectedIDs=[];self.sourceSelected=id;self.renderInspector()
   if let n=self.source?.nodes.first(where:{$0.id==id}),n.type=="image",!n.asset.isEmpty,self.assetCache[n.asset]==nil,let p=self.project {
    Bridge.shared.image("/asset?project=\(p.id)&id=\(n.asset)"){[weak self]image in guard self?.project?.id==p.id else{return};self?.assetCache[n.asset]=image}
   }
  }
  right.onPointer={[weak self] kind,p in self?.androidPointer(kind,p)}
  right.onTap={[weak self] p in self?.androidInput(p,nil)};right.onSwipe={[weak self] a,b in self?.androidInput(a,b)}
  propertyStack.axis = .vertical;propertyStack.spacing=12;inspector.addSubview(propertyStack)
  footer.font = .systemFont(ofSize:12);footer.textColor = .secondaryLabel;footer.backgroundColor = .white
  workspace.addSubview(extractionProgress)
  workspace.onBackgroundTap={[weak self] in
   guard let self=self else{return}
   self.view.endEditing(true);self.sourceSelected=nil;self.right.selected=nil;self.right.selectedIDs=[]
   self.chooseLayer(nil)
   self.web.evaluateJavaScript("window.getSelection()?.removeAllRanges()",completionHandler:nil)
  }
  configureWorkspaceDesign();setupSourceBrowser();renderInspector()
 }
 override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();layoutWorkspaceDesign()}
 @objc func searchChanged(){reloadCatalog()}
 func setStatus(_ s:String){statusHoldUntil=Date().addingTimeInterval(4);statusMessage=s;footer.text="  \(s)";let running=bulkRunning || snapshotBusy || splashRequestBusy || buildTimer?.isValid==true;progressDismissTimer?.invalidate();if running || s.hasPrefix("正在"){extractionProgress.show(s)}else if !extractionProgress.isHidden{extractionProgress.show(s,running:false);progressDismissTimer=Timer.scheduledTimer(withTimeInterval:5,repeats:false){[weak self]_ in self?.extractionProgress.isHidden=true}}}
 func error(_ e:Error){setStatus(e.localizedDescription);hint.text=e.localizedDescription}
 var projectLoadRetries=0
 func loadProjects(){Bridge.shared.request("/projects"){[weak self]r in
  guard let self=self else{return}
  do {
   let data=try r.get();let projects=try JSONDecoder().decode([StudioProject].self,from:data);self.projectLoadRetries=0
   if self.project==nil{let previous=UserDefaults.standard.string(forKey:"studio.lastProject");if let first=projects.first(where:{$0.id==previous}) ?? projects.first{self.useProject(first)}else{self.newHTMLProject()}}
  }catch{
   self.error(error)
   NSLog("Project list failed: %@",String(describing:error))
   if self.projectLoadRetries<3{self.projectLoadRetries+=1;DispatchQueue.main.asyncAfter(deadline:.now()+Double(self.projectLoadRetries)){[weak self]in self?.loadProjects()}}
  }
 }}
 func useProject(_ p:StudioProject){
  releaseSimulatorTouches();simulatorInput.stop()
  scrollRelay.cancel();UserDefaults.standard.set(p.id,forKey:"studio.lastProject");pendingSourceFocus=nil
  sourceLoadedFonts.removeAll();sourceNodes=[];sourceFrame=[:];sourceSignature="";sourceThumbnails.removeAll();sourceBrowser.update([],projectID:p.id,signature:"");sourceFrameRevision = -1
  project=p;snapshotBusy=false;pageIndex=0;selected=nil;assetCache.removeAll();libraryThumbs.removeAll();undoStates=[];redoStates=[];source=nil;dirty=false;activePage="";projectButton.setTitle(p.name+" ▾",for:.normal);reloadCatalog();updatePage()
  Bridge.shared.json("/activate-project",["id":p.id]){[weak self]r in if case .failure(let e)=r{self?.error(e)}else{self?.observedRevision = -1;self?.pollRoute();self?.connectEmbeddedSimulator()}}
 }
 func loadManifestPage(){
  guard isManifest,let p=project,let page=page else{return}
  let pageID=page.id
  if source?.quality=="manifest",source?.route==page.route{return}
  right.nodes=[];source=nil;right.imageView.image=nil
  right.logicalSize=CGSize(width:page.width,height:page.height)
  guard p.referenceAssets?[pageID] != nil else{return}
  Bridge.shared.request("/manifest-page?id=\(p.id)&page=\(pageID)"){[weak self]r in
   guard let self=self,self.project?.id==p.id,self.page?.id==pageID else{return}
   if case .success(let data)=r,let snapshot=try? JSONDecoder().decode(AndroidSnapshot.self,from:data){self.source=snapshot;self.right.nodes=snapshot.nodes}
   else if case .failure(let error)=r{self.error(error)}
  }
  if let asset=p.referenceAssets?[pageID]{Bridge.shared.request("/asset?project=\(p.id)&id=\(asset)"){[weak self]r in
   guard let self=self,self.project?.id==p.id,self.page?.id==pageID else{return}
   if case .success(let data)=r{self.right.imageView.image=UIImage(data:data)}
  }}
 }
 func setupHTML(){
  web.configuration.userContentController.add(self,name:"studio");web.scrollView.isScrollEnabled=false;web.isOpaque=false;web.backgroundColor = .clear;web.scrollView.backgroundColor = .clear;right.addSubview(web)
  let encoded=Bridge.shared.token.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? "";web.load(URLRequest(url:URL(string:Bridge.shared.base+"/web?token="+encoded)!))
  left.onTap={[weak self]p in self?.androidInput(p,nil)};left.onScroll={[weak self]phase,point,translation,velocity in self?.relayScroll(phase,point,translation,velocity)}
  configureEmbeddedSimulator()
  copyButton.setTitle("两端联动",for:.normal);hint.text="选右侧找素材，拖到左侧补齐；选左侧改外观。"
 }
 func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){guard let m=message.body as? [String:Any] else{return};if handleNativePreviewMessage(m){return};if m["type"] as? String=="toggleMode"{switchRunMode();return};if m["type"] as? String=="select",let id=m["id"] as? String{chooseSource(id)};if m["type"] as? String=="resourceDrop",let id=m["id"] as? String,let x=m["x"] as? Double,let y=m["y"] as? Double{let point=web.convert(CGPoint(x:x,y:y),to:left);if left.screenRect.contains(point){copySource(id,point:left.logical(point),signature:m["signature"] as? String,projectID:m["projectID"] as? String)}};if m["type"] as? String=="rendered",let rev=m["revision"] as? Int,rev != sourceFrameRevision{sourceFrameRevision=rev;if inspectorTabs.selectedSegmentIndex==1{loadSourceLayers()}}}
 func dispatchEvent(_ event:[String:Any],side:String){var body:[String:Any]=["side":side,"event":event,"eventID":UUID().uuidString];if let id=project?.id{body["projectID"]=id};Bridge.shared.json("/event",body){[weak self]r in if case .failure(let e)=r{self?.error(e)}else{self?.pollRoute()}}}
 func toggleRun(){releaseSimulatorTouches();simulatorInput.stop();scrollRelay.cancel();running=mode.selectedSegmentIndex==1;editingTools.isUserInteractionEnabled = !running;editingTools.alpha=running ? 0.45:1;sourcePageButton.isEnabled = !running;rightTitle.text=running ? "HTML 原型 · 运行预览":"HTML 原型 · 点击取资源";left.operate=running;if !running{leftTitle.text="iOS 成品 · 真实模拟器"};leftTools.isHidden=running;simulatorTools.isHidden = !running;iosBrowser.isUserInteractionEnabled = !running;iosBrowser.alpha=running ? 0.45:1;sourceBrowser.isUserInteractionEnabled = !running;sourceBrowser.alpha=running ? 0.45:1;inspector.isUserInteractionEnabled = !running;inspector.alpha=running ? 0.45:1;left.setNeedsLayout();if !running{updatePage()};Bridge.shared.json("/mode",["editing":!running]){[weak self]result in if case .failure(let error)=result{self?.error(error)}else{self?.connectEmbeddedSimulator()}}}
 func newHTMLProject(name:String?=nil){Bridge.shared.json("/new",name.map{["name":$0]} ?? [:]){[weak self]r in if case .success(let d)=r,let p=try? JSONDecoder().decode(StudioProject.self,from:d){self?.useProject(p);self?.loadProjects()}else if case .failure(let e)=r{self?.error(e)}}}
 func showSyncDetails(){Bridge.shared.request("/status"){[weak self]r in guard let self=self else{return};if case .success(let d)=r,let s=try? JSONSerialization.jsonObject(with:d) as? [String:Any]{
   let conflicts=s["conflicts"] as? [[String:Any]] ?? []
   if let c=conflicts.first{let text="图层：\(c["key"] ?? "")\n属性：\(c["field"] ?? "")\n原值：\(c["base"] ?? "已删除")\nHTML：\(c["html"] ?? "无")\niOS：\(c["ios"] ?? "")";let a=UIAlertController(title:"iOS 修改冲突",message:text,preferredStyle:.alert)
    for choice in ["ios","html"]{a.addAction(UIAlertAction(title:choice=="ios" ? "保留 iOS" : "采用 HTML",style:.default){_ in Bridge.shared.json("/conflict",["key":c["key"]!,"field":c["field"]!,"choice":choice]){_ in self.pollRoute()}})};a.addAction(UIAlertAction(title:"稍后",style:.cancel));self.present(a,animated:true)
   }else{self.showMessage("源码与同步",(self.project?.sourcePath ?? "")+"\n\n"+(s["error"] as? String ?? "")+"\n保存源码后会自动编译。请在上述目录编辑 app.json 与 pages 下的 HTML/CSS。")}
  }}}
 func restoreFollowing(){guard let n=page?.nodes.first(where:{$0.id==selected})else{return};Bridge.shared.json("/restore-follow",["key":n.sharedKey ?? n.id]){[weak self]_ in self?.pollRoute()}}
 func importProject(){
  showProjectImport()
 }
 func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]){if let u=urls.first{importURL(u)}}
 func importURL(_ url:URL){let access=url.startAccessingSecurityScopedResource();setStatus("正在校验 HTML 项目、资源与交互…");Bridge.shared.json("/import",["path":url.path]){[weak self] r in if access{url.stopAccessingSecurityScopedResource()};guard let self=self else{return};switch r{case .failure(let e):self.error(e);case .success(let d):if let p=try? JSONDecoder().decode(StudioProject.self,from:d){self.useProject(p);self.loadProjects()}}}}
 func dropInteraction(_ interaction:UIDropInteraction,canHandle session:UIDropSession)->Bool{session.hasItemsConforming(toTypeIdentifiers:[UTType.fileURL.identifier])}
 func dropInteraction(_ interaction:UIDropInteraction,sessionDidEnter session:UIDropSession){workspace.backgroundColor=UIColor.systemBlue.withAlphaComponent(0.12);hint.text="松开即可导入 HTML 项目"}
 func dropInteraction(_ interaction:UIDropInteraction,sessionDidExit session:UIDropSession){workspace.backgroundColor=UIColor(studioHex:"#EEF0F3")}
 func dropInteraction(_ interaction:UIDropInteraction,sessionDidUpdate session:UIDropSession)->UIDropProposal{UIDropProposal(operation:.copy)}
 func dropInteraction(_ interaction:UIDropInteraction,performDrop session:UIDropSession){
  workspace.backgroundColor=UIColor(studioHex:"#EEF0F3")
  guard let provider=session.items.first?.itemProvider else{return}
  provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil){[weak self]item,error in
   DispatchQueue.main.async {
    guard let self=self else{return}
    if let url=ProjectImportController.folderURL(item){self.showProjectImport(url)}
    else{self.setStatus(error?.localizedDescription ?? "无法读取拖入的文件夹")}
   }
  }
 }
 func reloadCatalog(){search.placeholder=segments.selectedSegmentIndex==2 ? "搜索 UIKit 组件" : "搜索页面或原始资源";let term=search.text?.lowercased() ?? "";assets=(project?.assets ?? []).filter{$0.kind=="image" && (term.isEmpty || $0.name.lowercased().contains(term))};catalog.reloadData();layers.reloadData()}
 var visiblePages:[Int]{(project?.pages.indices.map{$0} ?? []).filter{search.text?.isEmpty != false || project!.pages[$0].name.localizedCaseInsensitiveContains(search.text!)}}
 func tableView(_ t:UITableView,numberOfRowsInSection section:Int)->Int{if t===layers{return page?.nodes.count ?? 0};return segments.selectedSegmentIndex==0 ? visiblePages.count : segments.selectedSegmentIndex==2 ? nativeEntries.count : assets.count}
 func tableView(_ t:UITableView,cellForRowAt index:IndexPath)->UITableViewCell{
  let c=UITableViewCell(style:.subtitle,reuseIdentifier:nil);c.backgroundColor = .clear;c.textLabel?.font = .systemFont(ofSize:13);c.detailTextLabel?.font = .systemFont(ofSize:11);c.textLabel?.lineBreakMode = .byTruncatingMiddle
  if t===layers,let n=page?.nodes.reversed()[index.row]{c.textLabel?.text=(n.hidden ? "◌ " : n.locked ? "▣ " : "")+sourceBrowser.displayName(n);c.detailTextLabel?.text="\(Int(n.width)) × \(Int(n.height))";c.imageView?.image=layerThumbnail(n);c.imageView?.contentMode = .scaleAspectFit;c.imageView?.layer.cornerRadius=5;c.imageView?.clipsToBounds=true;if selectionIDs.contains(n.id){c.backgroundColor=left.selectionColor.withAlphaComponent(0.14)}
   if n.type=="image",!n.asset.isEmpty,assetCache[n.asset]==nil,!pendingAssets.contains(n.asset),let project=project {pendingAssets.insert(n.asset);Bridge.shared.image("/asset?project=\(project.id)&id=\(n.asset)"){[weak self,weak c]image in guard let self=self else{return};self.pendingAssets.remove(n.asset);if self.project?.id==project.id,let image=image{self.assetCache[n.asset]=image;c?.imageView?.image=self.layerThumbnail(n);c?.setNeedsLayout()}}}
  }
  else if segments.selectedSegmentIndex==0 {let idx=visiblePages[index.row];let p=project!.pages[idx];c.textLabel?.text=p.name;c.detailTextLabel?.text="\(p.nodes.count) 个图层";if idx==pageIndex{c.backgroundColor=UIColor.systemBlue.withAlphaComponent(0.1)}}
  else if segments.selectedSegmentIndex==2 {let n=nativeEntries[index.row];c.textLabel?.text=n.title;c.detailTextLabel?.text=n.detail;c.imageView?.image=UIImage(systemName:n.symbol);c.imageView?.tintColor = .systemBlue}
  else {let a=assets[index.row];c.textLabel?.text=a.name;c.detailTextLabel?.text=a.source;c.imageView?.contentMode = .scaleAspectFit
   if let img=libraryThumbs[a.id]{c.imageView?.image=img}else if let p=project {Bridge.shared.image("/asset?project=\(p.id)&id=\(a.id)&thumbnail=192",maxPixels:192){[weak self,weak c]img in guard let self=self,self.project?.id==p.id,let img=img else{return};self.libraryThumbs[a.id]=img;c?.imageView?.image=img;c?.setNeedsLayout()}}
  };return c
 }
 func tableView(_ t:UITableView,didSelectRowAt i:IndexPath){if t===layers{chooseLayer(Array(page!.nodes.reversed())[i.row].id)}
  else if segments.selectedSegmentIndex==0{pageIndex=visiblePages[i.row];selected=nil;syncing=false;updatePage();dispatchEvent(["type":"navigate","page":project!.pages[pageIndex].id],side:"ios");setStatus("已切换页面，可以选取图层或运行预览")}
  else if segments.selectedSegmentIndex==2{insert(nativeEntries[i.row].node())}
  else {let asset=assets[i.row];var n=StudioNode();n.asset=asset.id;n.name=asset.name;insert(n)}
 }
 func tableView(_ tableView:UITableView,itemsForBeginning session:UIDragSession,at indexPath:IndexPath)->[UIDragItem]{guard tableView===catalog,segments.selectedSegmentIndex != 0 else{return []};let payload=segments.selectedSegmentIndex==2 ? "native:"+nativeEntries[indexPath.row].type : "asset:"+assets[indexPath.row].id;return [UIDragItem(itemProvider:NSItemProvider(object:payload as NSString))]}
 func tableView(_ t:UITableView,trailingSwipeActionsConfigurationForRowAt i:IndexPath)->UISwipeActionsConfiguration?{guard t===layers,let p=page else{return nil};let n=Array(p.nodes.reversed())[i.row];return UISwipeActionsConfiguration(actions:[UIContextualAction(style:.destructive,title:"删除"){[weak self]_,_,done in self?.selected=n.id;self?.deleteSelected();done(true)}])}
 func updateHistoryButtons(){guard buttons.count>3 else{return};buttons[2].isEnabled = !undoStates.isEmpty;buttons[3].isEnabled = !redoStates.isEmpty}
 func checkpoint(){if let p=project,let d=try? JSONEncoder().encode(p){undoStates.append(d);if undoStates.count>80{undoStates.removeFirst()};redoStates=[]}}
 func undo(){guard let d=undoStates.popLast(),let p=try? JSONDecoder().decode(StudioProject.self,from:d) else{return};if let current=project,let now=try? JSONEncoder().encode(current){redoStates.append(now)};project=p;pageIndex=min(pageIndex,p.pages.count-1);selected=nil;changed()}
 func redo(){guard let d=redoStates.popLast(),let p=try? JSONDecoder().decode(StudioProject.self,from:d)else{return};if let current=project,let now=try? JSONEncoder().encode(current){undoStates.append(now)};project=p;pageIndex=min(pageIndex,p.pages.count-1);changed()}
 func changed(){editGeneration+=1;project?.reconcileNavigation(editedPage:pageIndex);dirty=true;updatePage();saveTimer?.invalidate();saveTimer=Timer.scheduledTimer(withTimeInterval:1,repeats:false){[weak self]_ in self?.save(silent:true)}}
 func updatePage(){if isManifest{loadManifestPage()};applySelectionColor();guard let p=page else{return};left.nodes=p.nodes;left.logicalSize=CGSize(width:p.width,height:p.height);left.selected=selected;left.selectedIDs=selectionIDs;syncLabel.text="\(p.name) · \(Int(p.width)) × \(Int(p.height))";reloadCatalog();if !running{renderInspector();refreshIOSBrowser()};if dirty{previewTimer?.invalidate();previewTimer=Timer.scheduledTimer(withTimeInterval:0.08,repeats:false){[weak self]_ in self?.sendPreview()}}}
 func sendPreview(){guard let p=project,let page=page,let pd=try? JSONEncoder().encode(page),let po=try? JSONSerialization.jsonObject(with:pd)else{return};pendingPreview=["projectID":p.id,"page":po,"compileRevision":p.compileRevision ?? ""];flushPreview()}
 func flushPreview(){guard !previewInFlight,let payload=pendingPreview else{return};pendingPreview=nil;previewInFlight=true
  Bridge.shared.json("/preview",payload){[weak self]r in guard let self=self else{return};self.previewInFlight=false;if case .failure(let e)=r{self.pendingPreview=nil;self.error(e)}else{self.flushPreview()}}
 }
 func save(silent:Bool=false){
  if saveInFlight || historyGesture || previewInFlight || pendingPreview != nil{saveTimer?.invalidate();saveTimer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:false){[weak self]_ in self?.save(silent:silent)};return}
  guard let p=project,let data=try? JSONEncoder().encode(p)else{return}
  let generation=editGeneration;saveInFlight=true
  Bridge.shared.request("/save",body:data){[weak self]r in
   guard let self=self else{return};self.saveInFlight=false
   switch r{case .failure(let e):self.error(e)
   case .success:
    if self.project?.id==p.id,self.editGeneration==generation,!self.historyGesture{self.dirty=false}
    if !silent{self.setStatus("布局已保存，上一版本已自动备份")}
   }
  }
 }


 func versions(){guard let p=project else{return};Bridge.shared.request("/versions?id=\(p.id)"){[weak self]r in guard let self=self else{return};if case .success(let d)=r,let items=try? JSONSerialization.jsonObject(with:d) as? [[String:Any]]{
  let sheet=UIAlertController(title:"恢复布局版本",message:"恢复前会备份当前布局",preferredStyle:.actionSheet);let f=DateFormatter();f.dateFormat="MM-dd HH:mm:ss"
  for item in items.prefix(12){if let id=item["file"] as? String,let date=item["time"] as? Double{sheet.addAction(UIAlertAction(title:f.string(from:Date(timeIntervalSince1970:date)),style:.default){_ in self.checkpoint();Bridge.shared.json("/restore",["id":p.id,"file":id]){r in if case .success(let d)=r,let restored=try? JSONDecoder().decode(StudioProject.self,from:d){self.useProject(restored)}}})}}
  sheet.addAction(UIAlertAction(title:"取消",style:.cancel));sheet.popoverPresentationController?.sourceView=self.moreProject;self.present(sheet,animated:true)
 }} }
 func newPage(){guard let p=project else{return};ask("新建页面",value:"新页面"){[weak self] name in
  Bridge.shared.json("/new-page",["id":p.id,"name":name]){result in guard let self=self else{return};switch result{case .success(let data):if let next=try? JSONDecoder().decode(StudioProject.self,from:data){self.useProject(next);self.setStatus("新页面已写入 HTML 项目并登记到 app.json")};case .failure(let e):self.error(e)}}
 }}
 func ask(_ title:String,value:String,completion:@escaping(String)->Void){let a=UIAlertController(title:title,message:nil,preferredStyle:.alert);a.addTextField{$0.text=value};a.addAction(UIAlertAction(title:"取消",style:.cancel));a.addAction(UIAlertAction(title:"保存",style:.default){_ in completion(a.textFields?.first?.text ?? value)});present(a,animated:true)}
 func showMessage(_ title:String,_ message:String){present(MessageDetailsController(title:title,message:message),animated:true)}
 func insert(_ node:StudioNode){guard page != nil else{return};checkpoint();var n=node;n.id=UUID().uuidString;project!.pages[pageIndex].nodes.append(n);selected=n.id;changed()}
 func addText(){var n=StudioNode();n.type="text";n.text="编辑文字";n.name="文字";n.width=180;n.height=35;insert(n)}
 func addShape(){var n=StudioNode();n.type="shape";n.name="色块";n.fill="#E7EDF5";insert(n)}
 func drop(_ payload:String,_ point:CGPoint){
  if acceptHTMLDrop(payload,at:point){return}
  if payload.hasPrefix("native:"),let entry=NativeEntry.all.first(where:{$0.type==String(payload.dropFirst(7))}){var n=entry.node();n.x=point.x;n.y=point.y;insert(n)}
  else if payload.hasPrefix("asset:"),let a=project?.assets.first(where:{$0.id==String(payload.dropFirst(6))}){var n=StudioNode();n.asset=a.id;n.name=a.name;n.x=point.x;n.y=point.y;insert(n)}
  else if payload.hasPrefix("node:"),var n=source?.nodes.first(where:{$0.id==String(payload.dropFirst(5))}){
   guard n.type != "region" else{sourceSelected=n.id;segments.selectedSegmentIndex=1;reloadCatalog();setStatus("此区域尚未关联原图，请在资源库点选对应图片");return}
   n.x=point.x;n.y=point.y;insert(n)
  }
 }
 func bindSourceAsset(_ a:StudioAsset){guard let idx=source?.nodes.firstIndex(where:{$0.id==sourceSelected})else{return};source!.nodes[idx].asset=a.id;source!.nodes[idx].type="image";source!.nodes[idx].name=a.name;right.nodes=source!.nodes;renderInspector();setStatus("已关联原图，可从右侧拖到左侧，或点击「复制选中元素」")}
 func move(_ id:String,_ delta:CGPoint,_ kind:String,_ end:Bool){guard let i=project?.pages[pageIndex].nodes.firstIndex(where:{$0.id==id}),!project!.pages[pageIndex].nodes[i].locked else{return}
  if !historyGesture{editGeneration+=1;scrollRelay.stopMomentum();saveTimer?.invalidate();previewTimer?.invalidate();checkpoint();historyGesture=true;dirty=true;snapCorrection = .zero}
  let ids=selectionIDs
  let beforeMove=project!.pages[pageIndex].nodes
  let delta=kind=="move" ? snappedDelta(delta,ids:ids):delta
  if ids.count>1 {
   if kind=="groupResize"{scaleSelection(delta)}else{for index in project!.pages[pageIndex].nodes.indices where ids.contains(project!.pages[pageIndex].nodes[index].id){project!.pages[pageIndex].nodes[index].x+=delta.x;project!.pages[pageIndex].nodes[index].y+=delta.y}}
  }else {
  var n=project!.pages[pageIndex].nodes[i];if kind=="resize"{n.width=max(4,n.width+delta.x);n.height=max(4,n.height+delta.y)}else if kind=="rotate"{n.rotation+=delta.x}else{n.x+=delta.x;n.y+=delta.y}
  project!.pages[pageIndex].nodes[i]=n}
  if kind=="move" {
   let map=Dictionary(beforeMove.map{($0.id,$0)},uniquingKeysWith:{_,latest in latest})
   for index in project!.pages[pageIndex].nodes.indices {
    let child=project!.pages[pageIndex].nodes[index]
    guard !ids.contains(child.id) else{continue}
    var parent=child.parent;var visited=Set<String>()
    while let pid=parent,visited.insert(pid).inserted {
     if ids.contains(pid){project!.pages[pageIndex].nodes[index].x+=delta.x;project!.pages[pageIndex].nodes[index].y+=delta.y;break}
     parent=map[pid]?.parent
    }
   }
  }
  left.nodes=project!.pages[pageIndex].nodes;left.setNeedsLayout();if Date().timeIntervalSince(lastPreview)>0.033{lastPreview=Date();sendPreview()}
  if end{historyGesture=false;snapCorrection = .zero;left.guideX=nil;left.guideY=nil;sendPreview();changed()}
 }
 func mutate(_ block:(inout StudioNode)->Void){guard let i=project?.pages[pageIndex].nodes.firstIndex(where:{$0.id==selected})else{return};checkpoint();block(&project!.pages[pageIndex].nodes[i]);changed()}
 func deleteSelected(){guard let i=project?.pages[pageIndex].nodes.firstIndex(where:{$0.id==selected})else{return};checkpoint();project!.pages[pageIndex].nodes.remove(at:i);selected=nil;changed()}
 func refreshScreens(){}
 func androidPointer(_ kind:String,_ p:CGPoint){}
 func nativeHit(at point:CGPoint)->StudioNode? {
  let raw=Dictionary(((rawScene["nodes"] as? [[String:Any]]) ?? []).compactMap{n in (n["id"] as? String).map{($0,n)}},uniquingKeysWith:{_,latest in latest})
  let displayed=Dictionary(left.nodes.map{($0.id,$0)},uniquingKeysWith:{_,latest in latest})
  return left.nodes.reversed().first{n in
   guard !n.hidden,n.opacity>0.01,n.frame.contains(point),raw[n.id]?["disabled"] as? Bool != true else{return false}
   var parent=raw[n.id]?["parent"] as? String ?? ""
   while let r=raw[parent],let p=displayed[parent]{if (r["clip"] as? Bool==true || p.type=="scroll") && !p.frame.contains(point){return false};parent=r["parent"] as? String ?? ""}
   let action=(rawScene["events"] as? [String:[String:Any]])?[n.id]?["action"] as? String ?? ""
   return n.type != "container" || !action.isEmpty || UIColor(studioHex:n.fill).cgColor.alpha>0
  }
 }
 func androidInput(_ a:CGPoint,_ b:CGPoint?){if b==nil,handleNativeChromeTap(a){return};if let b=b {if let n=left.nodes.reversed().first(where:{$0.type=="scroll" && $0.frame.contains(a)}){let raw=(rawScene["nodes"] as? [[String:Any]])?.first{$0["id"] as? String==n.id};let y=(raw?["scrollY"] as? Double ?? 0)+Double(a.y-b.y);dispatchEvent(["type":"scroll","node":n.id,"x":0,"y":max(0,y)],side:"ios")};return};guard let n=nativeHit(at:a),n.type.hasPrefix("native") || !((rawScene["events"] as? [String:[String:Any]])?[n.id]?["action"] as? String ?? "").isEmpty else{return}
  let rawControl=(rawScene["nodes"] as? [[String:Any]])?.first{$0["id"] as? String==n.id};if rawControl?["disabled"] as? Bool==true{return}
  if n.type=="nativeSegment" {dispatchEvent(["node":n.id,"value":min(max(0,Int((a.x-n.x)/n.width*CGFloat(n.options.count))),max(0,n.options.count-1))],side:"ios");return}
  if n.type=="nativeStepper" {let low=rawControl?["minimum"] as? Double ?? 0,high=rawControl?["maximum"] as? Double ?? 100,step=rawControl?["step"] as? Double ?? 1;dispatchEvent(["node":n.id,"value":min(high,max(low,Double(n.value)+(a.x<n.x+n.width/2 ? -step:step)))],side:"ios");return}
  if n.type=="nativeSlider" {let value=n.value;let raw=(rawScene["nodes"] as? [[String:Any]])?.first{$0["id"] as? String==n.id};let low=raw?["minimum"] as? Double ?? 0,high=raw?["maximum"] as? Double ?? 1;let t=min(1,max(0,Double((a.x-n.x)/n.width)));dispatchEvent(["node":n.id,"value":low+t*(high-low)],side:"ios");_ = value;return};if n.type=="nativeTextField" || n.type=="nativeTextView" {let alert=UIAlertController(title:"输入",message:n.placeholder,preferredStyle:.alert);alert.addTextField{$0.text=n.text};alert.addAction(UIAlertAction(title:"取消",style:.cancel));alert.addAction(UIAlertAction(title:"确定",style:.default){[weak self]_ in self?.dispatchEvent(["node":n.id,"value":alert.textFields?.first?.text ?? ""],side:"ios")});present(alert,animated:true)}else{dispatchEvent(["node":n.id,"value":!n.isOn],side:"ios")}
 }
 func pollRoute(){guard !liveStatusBusy,!historyGesture,!dirty,!scrollRelay.isActive else{return};liveStatusBusy=true
  Bridge.shared.request("/status"){[weak self]r in guard let self=self else{return}
   var fetching=false;defer{if !fetching{self.liveStatusBusy=false}}
   guard case .success(let d)=r,let status=try? JSONSerialization.jsonObject(with:d) as? [String:Any],let rev=status["revision"] as? Int else{return}
   if status["active"] is NSNull,let p=self.project {Bridge.shared.json("/activate-project",["id":p.id]){[weak self]r in if case .failure(let e)=r{self?.error(e)}else{self?.observedRevision = -1}};return}
   let problem=status["error"] as? String ?? "",conflicts=status["conflicts"] as? [[String:Any]] ?? [],acks=status["ack"] as? [String:Int] ?? [:]
   self.linked=status["linked"] as? Bool ?? true;self.copyButton.setTitle(self.linked ? "两端联动" : "独立操作",for:.normal)
   if !problem.isEmpty{self.showSyncStatus("同步失败 · 保留上一版 · "+problem)}else if !conflicts.isEmpty{self.showSyncStatus("\(conflicts.count) 项 iOS 调整冲突 · 点击「更多」处理")}else if !self.iosFrames.isFresh{self.showSyncStatus("同步失败 · 工作台画面连接中断，正在重连")}else{self.showSyncStatus(acks["ios"]==rev && acks["web"]==rev ? "已同步 · HTML 与原生 iOS 内容一致" : "同步中 · 正在更新两端")}
   guard rev != self.observedRevision,let p=self.project,status["active"] as? String==p.id else{return}
   fetching=true
   Bridge.shared.request("/editor-state?id=\(p.id)&compile=\(p.compileRevision ?? "")"){[weak self]result in
    guard let self=self else{return};defer{self.liveStatusBusy=false}
    guard !self.dirty,!self.historyGesture,!self.scrollRelay.isActive,self.project?.id==p.id,case .success(let data)=result,let state=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],state["projectID"] as? String==p.id,let current=state["raw"] as? [String:Any],let receivedRevision=state["revision"] as? Int else{return}
    let route=current["id"] as? String ?? ""
    var next=self.project!
    if let full=state["project"],let encoded=try? JSONSerialization.data(withJSONObject:full),let fullProject=try? JSONDecoder().decode(StudioProject.self,from:encoded){next=fullProject}
    else if let rawPage=state["page"],let encoded=try? JSONSerialization.data(withJSONObject:rawPage),let latest=try? JSONDecoder().decode(StudioPage.self,from:encoded),let index=next.pages.firstIndex(where:{$0.id==latest.id}){
     next.pages[index]=latest;next.updated=state["updated"] as? Double ?? next.updated;next.selectionColor=state["selectionColor"] as? String ?? next.selectionColor
    }else{return}
    let changed = !NSDictionary(dictionary:self.rawScene).isEqual(to:current) || state["project"] != nil
    self.rawScene=current;self.activePage=route;self.project=next;self.observedRevision=receivedRevision
    if changed{
     self.closeWebButton.isHidden = !(current["browserOpen"] as? Bool ?? false);self.view.setNeedsLayout()
     if let i=next.pages.firstIndex(where:{$0.id==route}){self.pageIndex=i};self.pageIndex=min(self.pageIndex,max(0,next.pages.count-1));self.updatePage()
    }
   }
  }
 }

 func buildAndroid(){showSyncDetails()}
 func pollBuild(){guard let p=project else{return};Bridge.shared.request("/build-status?id=\(p.id)"){[weak self]r in guard let self=self else{return};if case .success(let d)=r,let obj=try? JSONSerialization.jsonObject(with:d) as? [String:String]{switch obj["status"]{case "ready":self.buildTimer?.invalidate();self.setStatus("Android 副本已运行，正在连接原始图层");self.refreshSnapshot();case "failed":self.buildTimer?.invalidate();self.setStatus("构建失败："+(obj["log"] ?? ""));self.showMessage("Android 构建失败",obj["detail"] ?? "");default:break}}}}

 func refreshSnapshot(){showSyncDetails()}
 func copyPage(){guard let s=source,page != nil else{return};let valid=s.nodes.filter{$0.type != "region"};guard !valid.isEmpty else{setStatus("当前页尚无可复制元素，请先刷新或关联原图");return}
  checkpoint();let existing=Set(project!.pages[pageIndex].nodes.map{$0.id});project!.pages[pageIndex].nodes+=valid.filter{!existing.contains($0.id)};selected=nil;changed();setStatus("已复制 \(valid.count) 个图层"+(s.quality=="exact" ? "" : "；未关联的图片区域未复制"))
 }
 func activeResponder(in root:UIView)->UIView?{if root.isFirstResponder{return root};for child in root.subviews{if let found=activeResponder(in:child){return found}};return nil}
 var canToggleModeFromKeyboard:Bool{
  guard presentedViewController==nil,!historyGesture else{return false}
  func typing(_ root:UIView)->Bool{
   if let field=root as? UITextField,field.isEditing{return true}
   if let field=root as? UITextView,field.isFirstResponder{return true}
   if let bar=root as? UISearchBar,bar.isFirstResponder || bar.searchTextField.isEditing{return true}
   return root.subviews.contains(where:typing)
  }
  if typing(view.window ?? view){return false}
  guard let responder=activeResponder(in:view.window ?? view) else{return true}
  // WebKit handles Ctrl+Q itself, with DOM/IME-aware input checks.
  return !(responder is UITextInput) && !(responder is UISearchBar) && responder !== web && !responder.isDescendant(of:web)
 }
 override func canPerformAction(_ action:Selector,withSender sender:Any?)->Bool{if action == #selector(keyNudge(_:)){return canNudge};if action == #selector(keyToggleMode){return canToggleModeFromKeyboard};return super.canPerformAction(action,withSender:sender)}
 @objc func keyToggleMode(){guard canToggleModeFromKeyboard else{return};switchRunMode()}
 func switchRunMode(){guard presentedViewController==nil,!historyGesture else{return};mode.selectedSegmentIndex=running ? 0:1;toggleRun();setStatus(running ? "运行预览 · 按 Ctrl+Q 返回编辑":"选取与编辑 · 按 Ctrl+Q 运行预览")}
 override var keyCommands:[UIKeyCommand]?{[
  UIKeyCommand(title:"运行 / 编辑",action:#selector(keyToggleMode),input:"q",modifierFlags:.control),
  UIKeyCommand(title:"保存布局",action:#selector(keySave),input:"s",modifierFlags:.command),UIKeyCommand(title:"撤销",action:#selector(keyUndo),input:"z",modifierFlags:.command),UIKeyCommand(title:"重做",action:#selector(keyRedo),input:"z",modifierFlags:[.command,.shift]),UIKeyCommand(title:"删除图层",action:#selector(keyDelete),input:UIKeyCommand.inputDelete,modifierFlags:[])] + nudgeCommands}
 override var canBecomeFirstResponder:Bool{true}
 @objc func keySave(){save()};@objc func keyUndo(){undo()};@objc func keyRedo(){redo()};@objc func keyDelete(){if !running && !fields.values.contains(where:{$0.isFirstResponder}){deleteSelected()}}
 func renderInspector(){
  propertyStack.arrangedSubviews.forEach{$0.removeFromSuperview()};fields=[:]
  func add(_ v:UIView){propertyStack.addArrangedSubview(v)}
  guard let p=page else{add(label("页面属性",15,.semibold));let help=label("导入项目后，在真实模拟器中\n选取元素并编辑。",12);help.numberOfLines=0;add(help);view.setNeedsLayout();return}
  if selectionIDs.count>1 {
   renderBatchInspector()
  }else if let n=p.nodes.first(where:{$0.id==selected}) {
   if n.sharedKey != nil{add(label(isManifest ? "共用组件 · 尺寸和文字样式同步引用页面" : "共用组件 · 调整同步所有引用页面",11))}
   add(button("查看内部图层 / 缩略图",{[weak self]in self?.openIOSLayers()}))
   add(button("选中区域内全部图层",{[weak self]in self?.selectRegion(n.frame)}))
   add(label("选中图层",15,.semibold));if !n.id.hasPrefix("import-") && n.id.contains("/"){add(button("恢复此图层跟随 HTML",{[weak self]in self?.restoreFollowing()}))};addField("名称","name",n.name);add(label(n.type=="image" ? "图片图层" : n.type=="text" ? "文字图层" : "外观与布局",12))
   let row=UIStackView();row.axis = .horizontal;row.spacing=8;row.distribution = .fillEqually;row.addArrangedSubview(fieldBox("横向位置","x",format(n.x)));row.addArrangedSubview(fieldBox("纵向位置","y",format(n.y)));add(row)
   let row2=UIStackView();row2.axis = .horizontal;row2.spacing=8;row2.distribution = .fillEqually;row2.addArrangedSubview(fieldBox("宽","width",format(n.width)));row2.addArrangedSubview(fieldBox("高","height",format(n.height)));add(row2)
   addField("旋转 °","rotation",format(n.rotation));addField("不透明度 0–1","opacity",format(n.opacity))
   if n.type.hasPrefix("native") {
    add(label("iOS 原生组件",13,.semibold));addField("文字 / 标题","text",n.text);addField("组件颜色","color",n.color);addField("文字字号","fontSize",format(n.fontSize))
    if ["nativeCheckbox","nativeSwitch","nativeSpinner"].contains(n.type){add(button(n.isOn ? "状态：已开启 / 已勾选" : "状态：关闭 / 未勾选",{[weak self]in self?.mutate{$0.isOn.toggle()}}))}
    if ["nativeSlider","nativeProgress","nativeStepper","nativeSegment"].contains(n.type){addField("当前值","value",format(n.value))}
    if n.type=="nativeTextField"{addField("占位文字","placeholder",n.placeholder)}
    if n.type=="nativeSegment"{addField("选项，用逗号分隔","options",n.options.joined(separator:","))}
   }
   if n.type=="text" || n.type=="button"{addField("文字","text",n.text);addField("字号","fontSize",format(n.fontSize));addField("自定义字体名称（可选）","fontName",n.fontName);addField("字重 100–900","fontWeight",format(n.fontWeight));addField("颜色 #RRGGBB","color",n.color)
    add(menuButton("对齐：\(friendlyOption(n.alignment))",["left","center","right"]){[weak self]v in self?.mutate{$0.alignment=v}})
   }
   if n.type=="image" {add(menuButton("图片显示：\(friendlyOption(n.fit))",["fit","fill","stretch"]){[weak self]v in self?.mutate{$0.fit=v}});if n.fit=="nineSlice"{addField("原图边角 px","capPixels",format(n.capPixels));addField("目标边角 pt","capPoints",format(n.capPoints))};add(button("替换图片：从资源库选择",{[weak self]in self?.chooseAssetForSelected()}))}
   addField("背景 #RRGGBBAA","fill",n.fill);addField("圆角","cornerRadius",format(n.cornerRadius))
   add(menuButton("定位基准：\(friendlyOption(n.anchor))",["topLeft","bottomLeft","center"]){[weak self]v in self?.mutate{$0.anchor=v}})
   let order=UIStackView();order.axis = .horizontal;order.spacing=8;order.distribution = .fillEqually
   order.addArrangedSubview(button("上移一层",{[weak self]in self?.reorder(1)}));order.addArrangedSubview(button("下移一层",{[weak self]in self?.reorder(-1)}));add(order)
   add(button(n.locked ? "解锁图层" : "锁定图层",{[weak self]in self?.mutate{$0.locked.toggle()}}));add(button(n.hidden ? "显示图层" : "隐藏图层",{[weak self]in self?.mutate{$0.hidden.toggle()}}));add(button("复制图层",{[weak self]in var copy=n;copy.x+=12;copy.y+=12;self?.insert(copy)}));add(button("删除图层",{[weak self]in self?.deleteSelected()}))

  }else if let n=source?.nodes.first(where:{$0.id==sourceSelected}) {
   add(label(isManifest ? "文档原始图层" : "Android 选中元素",15,.semibold));let name=label(n.name,13);name.numberOfLines=0;add(name);add(label("\(Int(n.width)) × \(Int(n.height))",12));add(button("复制选中元素",{[weak self]in if n.type=="region"{self?.segments.selectedSegmentIndex=1;self?.reloadCatalog();self?.setStatus("请在资源库关联此区域的原图")}else{self?.insert(n)}}));add(button("关联原始图片",{[weak self]in self?.segments.selectedSegmentIndex=1;self?.reloadCatalog()}));let note=label("选择左侧资源库图片后，此区域\n将关联原图，不使用截图裁片。",12);note.numberOfLines=0;add(note)
  }else{
   add(label("页面属性",15,.semibold));addField("页面名称","pageName",p.name);addField("画布背景","pageBackground",p.background);addField("此项目选框颜色","selectionColor",project?.selectionColor ?? "#147DF5");add(button("选择选框颜色…",{[weak self]in self?.pickSelectionColor()}));add(label("\(Int(p.width)) × \(Int(p.height)) pt",13,.medium));let text=label("点左侧手机可修改外观。\n点右侧手机可查看内部资源。\n切换「运行预览」可体验交互。",12);text.numberOfLines=0;add(text)
   if false {add(button("返回",{}))
   add(button("跟随 Android 当前页",{[weak self]in self?.refreshSnapshot()}))
   add(button("重命名当前页",{[weak self]in self?.ask("页面名称",value:p.name){value in self?.checkpoint();self?.project?.pages[self!.pageIndex].name=value;self?.changed()}}))
   add(button("构建并运行 Android 副本",{[weak self]in self?.buildAndroid()}))};add(button("源码与同步详情",{[weak self]in self?.showSyncDetails()}));add(label("页面、状态和弹窗由 HTML 规范驱动\niOS 调整独立保存",12));propertyStack.arrangedSubviews.last.flatMap{$0 as? UILabel}?.numberOfLines=0
  }
  view.setNeedsLayout()
 }
 func setTool(_ key:String){left.tool=key;for(k,b)in toolButtons{b.configuration?.baseBackgroundColor=k==key ? UIColor.systemBlue.withAlphaComponent(0.15) : UIColor.secondarySystemFill;b.configuration?.baseForegroundColor=k==key ? .systemBlue : .label};setStatus(["clickMulti":"点击多选已开启：再次点击取消该项；拖动已选元素可一起移动","multi":"框选：拖出矩形选择多个图层","select":"选择图层或拖动图层","move":"移动：拖动资源调整位置","resize":"缩放：拖动资源调整大小","rotate":"旋转：围绕资源中心拖动"] [key] ?? "")}
 func applySelectionColor(){let color=UIColor(studioHex:project?.selectionColor ?? "#147DF5");left.selectionColor=color;right.selectionColor=color}
 func setSelectionColor(_ value:String){guard project != nil else{return};checkpoint();project?.selectionColor=value;applySelectionColor();save(silent:true)}
 func pickSelectionColor(){guard project != nil else{return};let picker=UIColorPickerViewController();picker.title="此项目的资源选框颜色";picker.selectedColor=left.selectionColor;picker.supportsAlpha=false;picker.delegate=self;present(picker,animated:true)}
 func colorPickerViewControllerDidFinish(_ picker:UIColorPickerViewController){var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0;picker.selectedColor.getRed(&r,green:&g,blue:&b,alpha:&a);setSelectionColor(String(format:"#%02X%02X%02X",Int(r*255),Int(g*255),Int(b*255)))}
 func colorPickerViewController(_ viewController:UIColorPickerViewController,didSelect color:UIColor,continuously:Bool){left.selectionColor=color;right.selectionColor=color}
 func format(_ n:CGFloat)->String{String(format:"%.1f",Double(n))}
 func fieldBox(_ title:String,_ key:String,_ value:String)->UIView{let stack=UIStackView();stack.axis = .vertical;stack.spacing=5;stack.addArrangedSubview(label(title,11));let f=UITextField();f.text=value;f.font = .systemFont(ofSize:12);f.borderStyle = .roundedRect;f.backgroundColor=UIColor(studioHex:"#F7F8FA");f.accessibilityIdentifier=key;f.delegate=self;f.addTarget(self,action:#selector(fieldCommitted(_:)),for:.editingDidEnd);f.heightAnchor.constraint(equalToConstant:30).isActive=true;fields[key]=f;stack.addArrangedSubview(f);return stack}
 func addField(_ title:String,_ key:String,_ value:String){propertyStack.addArrangedSubview(fieldBox(title,key,value))}
 func textFieldShouldReturn(_ textField:UITextField)->Bool{textField.resignFirstResponder();return true}
 @objc func fieldCommitted(_ field:UITextField){guard let key=field.accessibilityIdentifier,let value=field.text else{return}
  if key.hasPrefix("batch."){commitBatch(key,value);return}
  if key=="selectionColor"{setSelectionColor(value);return}
  if key=="pageName" || key=="pageBackground"{checkpoint();if key=="pageName"{project?.pages[pageIndex].name=value}else{project?.pages[pageIndex].background=value};changed();return}
  let number=CGFloat(Double(value) ?? 0)
  mutate{n in switch key{case "value":n.value=number;case "placeholder":n.placeholder=value;case "options":n.options=value.split(whereSeparator:{$0=="," || $0=="，"}).map(String.init);case "name":n.name=value;case "text":n.text=value;case "fontName":n.fontName=value;case "color":n.color=value;case "fill":n.fill=value;case "x":n.x=number;case "y":n.y=number;case "width":n.width=max(1,number);case "height":n.height=max(1,number);case "rotation":n.rotation=number;case "opacity":n.opacity=min(1,max(0,number));case "fontSize":n.fontSize=max(1,number);case "fontWeight":n.fontWeight=min(900,max(100,number));case "cornerRadius":n.cornerRadius=max(0,number);case "capPixels":n.capPixels=max(0,number);case "capPoints":n.capPoints=max(0,number);default:break}}
 }
 func friendlyOption(_ value:String)->String{["fit":"完整显示","fill":"填满并裁切","stretch":"拉伸铺满","left":"靠左","center":"居中","right":"靠右","topLeft":"左上角","bottomLeft":"左下角"][value] ?? value}
 func menuButton(_ title:String,_ options:[String],action:@escaping(String)->Void)->UIButton{let b=button(title,{});b.showsMenuAsPrimaryAction=true;b.menu=UIMenu(children:options.map{v in UIAction(title:friendlyOption(v)){_ in action(v)}});return b}
 func reorder(_ delta:Int){guard let i=project?.pages[pageIndex].nodes.firstIndex(where:{$0.id==selected})else{return};let j=i+delta;guard project!.pages[pageIndex].nodes.indices.contains(j)else{return};checkpoint();project!.pages[pageIndex].nodes.swapAt(i,j);changed()}
 func chooseAssetForSelected(){guard let p=project else{return};let alert=UIAlertController(title:"替换原始图片",message:nil,preferredStyle:.actionSheet);for a in p.assets where a.kind=="image"{alert.addAction(UIAlertAction(title:a.name,style:.default){[weak self]_ in self?.mutate{$0.asset=a.id;$0.name=a.name}})};alert.addAction(UIAlertAction(title:"取消",style:.cancel));alert.popoverPresentationController?.sourceView=inspector;present(alert,animated:true)}
}
