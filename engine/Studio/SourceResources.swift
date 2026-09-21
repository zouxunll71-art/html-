import UIKit
import CoreText
extension StudioController {
 func setupSourceBrowser(){
  inspectorTabs.selectedSegmentIndex=0;inspectorTabs.addAction(UIAction{[weak self]_ in self?.showInspectorMode()},for:.valueChanged);view.addSubview(inspectorTabs);view.addSubview(sourceBrowser);setupIOSBrowser()
  sourceBrowser.thumbnail={[weak self] n in self?.sourceThumbnail(n)}
  sourceBrowser.onSelect={[weak self] id in self?.highlightSource(id)}
  sourceBrowser.onCopy={[weak self] id,children in self?.copySource(id,children:children)}
  sourceBrowser.onDrop={[weak self]id,point,window in guard let self=self else{return};let location=self.left.convert(point,from:window);guard self.left.screenRect.contains(location) else{self.setStatus("请把资源拖到左侧 iOS 手机里面");return};self.copySource(id,point:self.left.logical(location))}
  showInspectorMode()
 }
 func showInspectorMode(){let mode=inspectorTabs.selectedSegmentIndex;sourceBrowser.isHidden = mode != 1;iosBrowser.isHidden = mode != 2;inspector.isHidden = mode != 0;if mode==1{loadSourceLayers()}else if mode==2{refreshIOSBrowser()};view.setNeedsLayout()}
 func highlightSource(_ id:String?){sourceSelected=id
  let value=(try? JSONSerialization.data(withJSONObject:[id as Any? ?? NSNull()])).flatMap{String(data:$0,encoding:.utf8)} ?? "[null]"
  web.evaluateJavaScript("window.studioSelect?.(\(value)[0])",completionHandler:nil)
 }
 func chooseSource(_ id:String){inspectorTabs.selectedSegmentIndex=1;selected=nil;multiSelection=[];left.selected=nil;left.selectedIDs=[];highlightSource(id);showInspectorMode();loadSourceLayers(focus:id)}
 func loadSourceLayers(focus:String?=nil){
  guard let p=project else{return};if let focus=focus{pendingSourceFocus=focus};guard !sourceLoading else{return};sourceLoading=true
  Bridge.shared.request("/source-layers"){[weak self]result in
   guard let self=self else{return};self.sourceLoading=false;guard self.project?.id==p.id else{return}
   switch result{case .failure(let e):self.setStatus(e.localizedDescription)
   case .success(let data):
    guard let dataObject=try? JSONSerialization.jsonObject(with:data) as? [String:Any],dataObject["projectID"] as? String==p.id,let raw=dataObject["raw"] as? [String:Any],let frame=dataObject["frame"] as? [String:Any],let nodes=frame["nodes"],let bytes=try? JSONSerialization.data(withJSONObject:nodes),let decoded=try? JSONDecoder().decode([StudioNode].self,from:bytes) else{return}
    self.sourceFrame=raw;self.sourceSignature=dataObject["signature"] as? String ?? "";self.sourceNodes=decoded;self.sourceThumbnails.removeAll()
    self.thumbnailScene.loadViewIfNeeded();self.thumbnailScene.view.frame=CGRect(x:0,y:0,width:raw["width"] as? Double ?? 402,height:raw["height"] as? Double ?? 874);self.thumbnailScene.assetProvider={[weak self] id in self?.assetCache[id]};self.thumbnailScene.apply(raw,animated:false);self.thumbnailScene.view.layoutIfNeeded()
    let focus=self.pendingSourceFocus;self.pendingSourceFocus=nil;self.sourceBrowser.update(decoded,projectID:p.id,signature:self.sourceSignature,focus:focus)
    let visibleAssets=Set(decoded.map(\.asset))
    for asset in p.assets where (asset.kind=="font" || visibleAssets.contains(asset.id)) && self.assetCache[asset.id]==nil && !self.sourcePendingAssets.contains(asset.id) && !self.sourceLoadedFonts.contains(asset.id){self.sourcePendingAssets.insert(asset.id);Bridge.shared.request("/asset?project=\(p.id)&id=\(asset.id)"){[weak self]r in guard let self=self else{return};self.sourcePendingAssets.remove(asset.id);guard self.project?.id==p.id,case .success(let d)=r else{return};if asset.kind=="font"{self.sourceLoadedFonts.insert(asset.id);let url=FileManager.default.temporaryDirectory.appendingPathComponent(asset.file);try? d.write(to:url);CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)}else{AssetImages.queue.addOperation{let image=AssetImages.decode(d);DispatchQueue.main.async{guard self.project?.id==p.id else{return};self.assetCache[asset.id]=image;self.scheduleSourceThumbnails()}}};self.scheduleSourceThumbnails()}}
   }
  }
 }
 func scheduleSourceThumbnails(){guard sourceThumbnailWork==nil else{return};let work=DispatchWorkItem{[weak self]in guard let self=self else{return};self.sourceThumbnailWork=nil;self.sourceThumbnails.removeAll();self.thumbnailScene.specs.removeAll();self.thumbnailScene.apply(self.sourceFrame,animated:false);self.sourceBrowser.refresh()};sourceThumbnailWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.05,execute:work)}
 func sourceThumbnail(_ n:StudioNode)->UIImage? {
  if let image=sourceThumbnails[n.id]{return image}
  let format=UIGraphicsImageRendererFormat();format.scale=2
  let image=UIGraphicsImageRenderer(size:CGSize(width:72,height:60),format:format).image{context in
   UIColor(studioHex:"#F1F4F8").setFill();context.fill(CGRect(x:0,y:0,width:72,height:60));UIColor(studioHex:"#E2E7EF").setFill()
   for y in stride(from:0,to:60,by:8){for x in stride(from:0,to:72,by:8) where (x/8+y/8)%2==0{context.fill(CGRect(x:x,y:y,width:8,height:8))}}
   guard let v=thumbnailScene.views[n.id],v.bounds.width>0,v.bounds.height>0 else{return}
   let scale=min(64/v.bounds.width,52/v.bounds.height),cg=context.cgContext;cg.saveGState();cg.translateBy(x:(72-v.bounds.width*scale)/2,y:(60-v.bounds.height*scale)/2);cg.scaleBy(x:scale,y:scale);v.layer.render(in:cg);cg.restoreGState()
  };sourceThumbnails[n.id]=image;return image
 }
 func copySource(_ id:String,children:Bool=false,point:CGPoint?=nil,signature:String?=nil,projectID:String?=nil){
  guard let p=project,let page=page,!sourceBrowser.busy,!running else{return}
  guard projectID==nil || projectID==p.id else{setStatus("资源来自另一个项目，请重新选择");return}
  checkpoint();sourceBrowser.busy=true;sourceBrowser.refresh();setStatus("添加图层中…")
  var body:[String:Any]=["projectID":p.id,"targetPage":page.id,"signature":signature ?? sourceSignature,"node":id,"children":children]
  if let point=point{body["point"]=["x":point.x,"y":point.y]}
  let perform={ [weak self] in Bridge.shared.json("/copy-source",body){result in
   guard let self=self else{return};self.sourceBrowser.busy=false;self.sourceBrowser.refresh()
   switch result{case .failure(let e):self.error(e);self.loadSourceLayers()
   case .success(let data):
    guard let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let raw=obj["project"],let bytes=try? JSONSerialization.data(withJSONObject:raw),let next=try? JSONDecoder().decode(StudioProject.self,from:bytes),self.project?.id==next.id else{return}
    self.project=next;self.pageIndex=next.pages.firstIndex{$0.id==page.id} ?? 0;let ids=obj["copiedIDs"] as? [String] ?? [];self.selected=ids.first;self.multiSelection=Set(ids);self.dirty=false;self.observedRevision = -1;self.updatePage();self.pollRoute();self.setStatus("已添加 \(ids.count) 个图层到 iOS，可在左边移动，也可以撤销")
   }
  }}
  saveTimer?.invalidate();previewTimer?.invalidate()
  if dirty,let data=try? JSONEncoder().encode(p){Bridge.shared.request("/save",body:data){[weak self]r in if case .failure(let e)=r{self?.sourceBrowser.busy=false;self?.sourceBrowser.refresh();self?.error(e)}else{self?.dirty=false;perform()}}}else{perform()}
 }
 func acceptHTMLDrop(_ value:String,at point:CGPoint)->Bool{guard value.hasPrefix("html-node:"),let data=String(value.dropFirst(10)).data(using:.utf8),let body=try? JSONSerialization.jsonObject(with:data) as? [String:String],let id=body["node"] else{return false};copySource(id,point:point,signature:body["signature"],projectID:body["projectID"]);return true}
}
