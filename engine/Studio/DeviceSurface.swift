import UIKit
final class DeviceSurface:UIView,UIDragInteractionDelegate,UIDropInteractionDelegate,UIGestureRecognizerDelegate {
 let video=AndroidVideo();let chrome=DeviceChrome();let screenMask=CALayer();let imageView=UIImageView();let overlay=UIView();let selectionClip=UIView();let selectionMask=CAShapeLayer();let selection=UIView();let handle=UIView();let rotateHandle=UIView()
 let guides=CAShapeLayer()
 var guideX:CGFloat? {didSet{setNeedsLayout()}}
 var guideY:CGFloat? {didSet{setNeedsLayout()}}
 var selectedIDs=Set<String>() {didSet{setNeedsLayout()}};var onMarquee:((CGRect)->Void)?;private var marqueeStart:CGPoint?
 var tool="select";var lastAngle:CGFloat=0;var selectionColor=UIColor.systemBlue {didSet {selection.layer.borderColor=selectionColor.cgColor;handle.layer.borderColor=selectionColor.cgColor;rotateHandle.layer.borderColor=selectionColor.cgColor}}
 var logicalSize=CGSize(width:402,height:874);var nodes:[StudioNode]=[];var selected:String? {didSet{setNeedsLayout()}}
 var webHosted=false {didSet{chrome.isHidden=webHosted || isSource;updateInputMode()}}
 var isSource=false {didSet {chrome.isHidden=isSource;imageView.layer.mask=isSource ? nil : screenMask;backgroundColor=isSource ? .white : .clear;layer.cornerRadius=isSource ? 28 : 0;layer.borderWidth=isSource ? 5 : 0;layer.borderColor=UIColor.black.cgColor;clipsToBounds=isSource;updateInputMode();setNeedsLayout()}};var operate=false {didSet{updateInputMode()}}
 var onScroll:((String,CGPoint,CGPoint,CGPoint)->Void)?;private var operatePanHandled=false;private var operateOrigin:CGPoint?
 private var sourceTouch=false;private var pointerOrigin:CGPoint?
 private var tapGesture:UITapGestureRecognizer!;private var panGesture:UIPanGestureRecognizer!;private var wheelSequence=false;private var resourceDrag:UIDragInteraction!
 var previewAsset:((String)->UIImage?)?
 var onPointer:((String,CGPoint)->Void)?
 var directSimulatorInput=false {didSet{updateInputMode()}}
 private var simulatorDirect:Bool {directSimulatorInput && operate && !isSource}
 private var simulatorWheel:UIPanGestureRecognizer!
 private var wheelTouch=false;private var wheelOrigin=CGPoint.zero
 var onModifiedSelect:((String?,Bool)->Void)?
 var onSelect:((String?)->Void)?;var onMove:((String,CGPoint,String,Bool)->Void)?;var onTap:((CGPoint)->Void)?;var onSwipe:((CGPoint,CGPoint)->Void)?;var onDrop:((String,CGPoint)->Void)?
 var dragStart=CGPoint.zero;var action="move";private var resizingGroup=false;var changed=false
 override init(frame:CGRect){super.init(frame:frame)
  backgroundColor = .clear;clipsToBounds=false;addSubview(chrome)
  imageView.contentMode = .scaleToFill;screenMask.contents=DeviceChrome.resource("ScreenMask")?.cgImage;imageView.layer.mask=screenMask;addSubview(imageView);addSubview(video);video.isHidden=true;overlay.isUserInteractionEnabled=false;overlay.clipsToBounds=true;addSubview(overlay);overlay.addSubview(selectionClip);selectionClip.layer.mask=selectionMask
  guides.strokeColor=UIColor.systemPink.cgColor;guides.lineWidth=1;guides.lineDashPattern=[4,3];overlay.layer.addSublayer(guides)
  selection.layer.borderColor=UIColor.systemBlue.cgColor;selection.layer.borderWidth=2;selection.layer.shadowColor=UIColor.white.cgColor;selection.layer.shadowOpacity=0.9;selection.layer.shadowRadius=1;selection.layer.shadowOffset = .zero;selection.isUserInteractionEnabled=false;selectionClip.addSubview(selection)
  for v in [handle,rotateHandle]{v.backgroundColor = .white;v.layer.borderColor=UIColor.systemBlue.cgColor;v.layer.borderWidth=1.5;v.layer.cornerRadius=3;selectionClip.addSubview(v)}
  tapGesture=UITapGestureRecognizer(target:self,action:#selector(tap(_:)));addGestureRecognizer(tapGesture)
  panGesture=UIPanGestureRecognizer(target:self,action:#selector(pan(_:)));panGesture.delegate=self;panGesture.allowedScrollTypesMask = .all;addGestureRecognizer(panGesture)
  simulatorWheel=UIPanGestureRecognizer(target:self,action:#selector(simulatorWheelChanged(_:)));simulatorWheel.allowedTouchTypes=[];simulatorWheel.allowedScrollTypesMask = .all;simulatorWheel.cancelsTouchesInView=false;simulatorWheel.isEnabled=false;addGestureRecognizer(simulatorWheel)
  resourceDrag=UIDragInteraction(delegate:self);resourceDrag.isEnabled=false;addInteraction(resourceDrag);addInteraction(UIDropInteraction(delegate:self))
  accessibilityLabel="模拟器实时画面"
 }
 private func updateInputMode(){
  let direct=webHosted || simulatorDirect
  tapGesture?.isEnabled = !direct;panGesture?.isEnabled = !direct;resourceDrag?.isEnabled = isSource && !operate
  simulatorWheel?.isEnabled = simulatorDirect
  if !direct && sourceTouch{sourceTouch=false;onPointer?("up",dragStart)}
 }
 override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?){
  if simulatorDirect,let touch=touches.first{
   let point=touch.location(in:self);guard screenRect.contains(point)else{return}
   cancelSimulatorGesture();sourceTouch=true;dragStart=logical(point);onPointer?("down",dragStart);return
  }
  if (!isSource || !operate),let touch=touches.first{pointerOrigin=logical(touch.location(in:self));if operate && !isSource{operateOrigin=pointerOrigin;operatePanHandled=false}}
  guard isSource && operate,let touch=touches.first else{super.touchesBegan(touches,with:event);return}
  let point=touch.location(in:self);guard screenRect.contains(point)else{return};sourceTouch=true;dragStart=logical(point);onPointer?("down",dragStart)
 }
 override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?){
  guard sourceTouch,let touch=touches.first else{super.touchesMoved(touches,with:event);return}
  dragStart=logical(touch.location(in:self));onPointer?("move",dragStart)
 }
 override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?){
  if simulatorDirect{if sourceTouch{sourceTouch=false;if let touch=touches.first{dragStart=logical(touch.location(in:self))};onPointer?("up",dragStart)};return}
  if operate && !isSource,!operatePanHandled,let origin=operateOrigin,let touch=touches.first{let end=logical(touch.location(in:self));let delta=CGPoint(x:end.x-origin.x,y:end.y-origin.y);if hypot(delta.x,delta.y)>10{onScroll?("begin",origin,.zero,.zero);onScroll?("end",origin,delta,.zero)}}
  operateOrigin=nil
  guard sourceTouch else{super.touchesEnded(touches,with:event);return};sourceTouch=false
  if let touch=touches.first{dragStart=logical(touch.location(in:self))};onPointer?("up",dragStart)
 }
 override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?){
  if simulatorDirect{cancelSimulatorGesture();return}
  if sourceTouch{sourceTouch=false;onPointer?("up",dragStart)}else{super.touchesCancelled(touches,with:event)}
 }
 required init?(coder:NSCoder){fatalError()}
 func cancelSimulatorGesture(){
  if directSimulatorInput && (sourceTouch || wheelTouch){sourceTouch=false;wheelTouch=false;onPointer?("cancel",dragStart)}
 }
 @objc private func simulatorWheelChanged(_ gesture:UIPanGestureRecognizer){
  guard simulatorDirect,!sourceTouch else{return}
  if gesture.state == .began{
   let point=gesture.location(in:self);guard screenRect.contains(point)else{return}
   wheelOrigin=logical(point);dragStart=wheelOrigin;wheelTouch=true;onPointer?("down",dragStart)
  }
  guard wheelTouch else{return}
  let offset=gesture.translation(in:self),scale=logicalSize.width/screenRect.width
  let point=CGPoint(x:wheelOrigin.x+offset.x*scale,y:wheelOrigin.y+offset.y*scale)
  dragStart=CGPoint(x:max(1,min(logicalSize.width-1,point.x)),y:max(1,min(logicalSize.height-1,point.y)))
  if gesture.state == .cancelled || gesture.state == .failed{wheelTouch=false;onPointer?("cancel",dragStart);return}
  onPointer?("move",dragStart)
  if gesture.state == .ended{wheelTouch=false;onPointer?("up",dragStart)}
  else if point != dragStart{
   // Continue long wheel scrolls without trapping the virtual finger at a display edge.
   onPointer?("up",dragStart);dragStart=wheelOrigin;gesture.setTranslation(.zero,in:self);onPointer?("down",dragStart)
  }
 }
 var screenRect:CGRect{if isSource{return bounds.insetBy(dx:5,dy:5)};let s=bounds.width/456;return CGRect(x:27*s,y:18*s,width:402*s,height:874*s)}
 func logical(_ point:CGPoint)->CGPoint{CGPoint(x:(point.x-screenRect.minX)/screenRect.width*logicalSize.width,y:(point.y-screenRect.minY)/screenRect.height*logicalSize.height)}
 func actual(_ rect:CGRect)->CGRect {CGRect(x:rect.minX/logicalSize.width*screenRect.width,y:rect.minY/logicalSize.height*screenRect.height,width:rect.width/logicalSize.width*screenRect.width,height:rect.height/logicalSize.height*screenRect.height)}
 override func layoutSubviews(){super.layoutSubviews();chrome.frame=bounds;imageView.frame=screenRect;video.frame=screenRect;screenMask.frame=imageView.bounds;overlay.frame=screenRect;selectionClip.frame=overlay.bounds;selectionMask.frame=overlay.bounds
  let guidePath=UIBezierPath()
  if !operate{if let x=guideX{let px=x/logicalSize.width*screenRect.width;guidePath.move(to:CGPoint(x:px,y:0));guidePath.addLine(to:CGPoint(x:px,y:screenRect.height))};if let y=guideY{let py=y/logicalSize.height*screenRect.height;guidePath.move(to:CGPoint(x:0,y:py));guidePath.addLine(to:CGPoint(x:screenRect.width,y:py))}}
  guides.frame=overlay.bounds;guides.path=guidePath.cgPath
  if operate {selection.isHidden=true;handle.isHidden=true;rotateHandle.isHidden=true;return}
  guard let n=nodes.first(where:{$0.id==selected}) else{selection.isHidden=true;handle.isHidden=true;rotateHandle.isHidden=true;return}
  let map=Dictionary(nodes.map{($0.id,$0)},uniquingKeysWith:{_,latest in latest})
  let clip=clippingRect(for:n,map:map)
  let maskPath=UIBezierPath()
  if selectedIDs.count>1{for item in nodes where selectedIDs.contains(item.id){let region=clippingRect(for:item,map:map);if !region.isNull{maskPath.append(UIBezierPath(rect:actual(region)))}}}else if !clip.isNull{maskPath.append(UIBezierPath(rect:actual(clip)))}
  selectionMask.path=maskPath.cgPath
  if selectedIDs.count<=1 && (clip.isNull || !clip.intersects(n.selectionBounds)){selection.isHidden=true;handle.isHidden=true;rotateHandle.isHidden=true;return}
  if selectedIDs.count>1 {
   let rect=nodes.filter{selectedIDs.contains($0.id)}.reduce(CGRect.null){$0.union($1.selectionBounds)}
   selection.isHidden=false;selection.transform = .identity;selection.frame=actual(rect);handle.isHidden=isSource;handle.frame=CGRect(x:selection.frame.maxX-6,y:selection.frame.maxY-6,width:12,height:12);rotateHandle.isHidden=true;return
  }
  selection.isHidden=false;handle.isHidden=isSource;rotateHandle.isHidden=isSource
  selection.transform = .identity;selection.frame=actual(n.selectionBounds)
  handle.frame=CGRect(x:selection.frame.maxX-5,y:selection.frame.maxY-5,width:10,height:10)
  rotateHandle.frame=CGRect(x:selection.center.x-5,y:selection.frame.minY-22,width:10,height:10)
 }
 func clippingRect(for node:StudioNode,map:[String:StudioNode])->CGRect{
  if node.hidden || node.opacity<=0.01{return .null}
  var rect=CGRect(origin:.zero,size:logicalSize),parent=node.parent,seen=Set<String>()
  while let id=parent,seen.insert(id).inserted,let container=map[id]{
   if container.hidden || container.opacity<=0.01{return .null}
   if container.type=="scroll" || container.clip==true{rect=rect.intersection(container.frame)}
   parent=container.parent
  }
  return rect
 }
 func hit(_ point:CGPoint)->StudioNode?{
  let map=Dictionary(nodes.map{($0.id,$0)},uniquingKeysWith:{_,latest in latest})
  let hits=nodes.reversed().filter{n in
   guard n.hasVisibleSelectionContent && clippingRect(for:n,map:map).contains(point) else{return false}
   let center=CGPoint(x:n.x+n.width/2,y:n.y+n.height/2);let p=CGPoint(x:point.x-center.x,y:point.y-center.y).applying(CGAffineTransform(rotationAngle: -n.rotation * .pi/180).scaledBy(x:1/max(0.001,n.scale ?? 1),y:1/max(0.001,n.scale ?? 1)))
   return n.selectionFrame.offsetBy(dx:-center.x,dy:-center.y).contains(p)
  }
  guard isSource else{return hits.first}
  // Resource picking favors the smallest visible leaf over a containing backdrop.
  return hits.enumerated().min { a,b in
   let aa=a.element.width*a.element.height,bb=b.element.width*b.element.height
   if abs(aa-bb)>1{return aa<bb}
   let ap=a.element.type=="shape" ? 1 : 0,bp=b.element.type=="shape" ? 1 : 0
   return ap==bp ? a.offset<b.offset : ap<bp
  }?.element
 }
 @objc func tap(_ g:UITapGestureRecognizer){let p=logical(g.location(in:self));if operate{onTap?(p)}else{selected=hit(p)?.id;if let modified=onModifiedSelect{modified(selected,g.modifierFlags.contains(.command))}else{onSelect?(selected)}}}
 // Wheel/trackpad scrolling never enters the layer move/resize/rotate path.
 @objc func wheel(_ g:UIPanGestureRecognizer){
  let t=g.translation(in:self),point=g.location(in:self),scale=logicalSize.width/screenRect.width
  if g.state == .began{dragStart=logical(point);onScroll?("begin",dragStart,.zero,.zero)}
  let phase=g.state == .ended ? "end" : g.state == .cancelled ? "cancel":"change"
  onScroll?(phase,dragStart,CGPoint(x:t.x*scale,y:t.y*scale),.zero)
 }
 @objc func pan(_ g:UIPanGestureRecognizer){
  if g.state == .began{wheelSequence = g.numberOfTouches == 0}
  if wheelSequence && !isSource{wheel(g);return}
  let point=g.location(in:self);let p=logical(point)
  if operate && !isSource{
   let t=g.translation(in:self),v=g.velocity(in:self),scale=logicalSize.width/screenRect.width
   if g.state == .began{operatePanHandled=true;dragStart=operateOrigin ?? logical(CGPoint(x:point.x-t.x,y:point.y-t.y));onScroll?("begin",dragStart,.zero,.zero)}
   let phase=g.state == .ended ? "end" : g.state == .cancelled ? "cancel":"change"
   onScroll?(phase,dragStart,CGPoint(x:t.x*scale,y:t.y*scale),CGPoint(x:v.x*scale,y:v.y*scale));return
  }
  if !isSource && g.state == .began {
   let t=g.translation(in:self);let start=pointerOrigin ?? logical(CGPoint(x:point.x-t.x,y:point.y-t.y))
   let overlayPoint=CGPoint(x:start.x/logicalSize.width*screenRect.width,y:start.y/logicalSize.height*screenRect.height)
   resizingGroup=selectedIDs.count>1 && ((!handle.isHidden && handle.frame.insetBy(dx:-12,dy:-12).contains(overlayPoint)) || (tool=="resize" && nodes.contains{selectedIDs.contains($0.id) && $0.visualBounds.contains(start)}))
   if resizingGroup{dragStart=start}
  }
  if resizingGroup,let id=selected {
   onMove?(id,CGPoint(x:p.x-dragStart.x,y:p.y-dragStart.y),"groupResize",g.state == .ended || g.state == .cancelled);dragStart=p
   if g.state == .ended || g.state == .cancelled{resizingGroup=false};return
  }
  if !isSource && tool=="multi" {
   if g.state == .began{let t=g.translation(in:self);marqueeStart=pointerOrigin ?? logical(CGPoint(x:point.x-t.x,y:point.y-t.y))}
   if let start=marqueeStart{let rect=CGRect(x:min(start.x,p.x),y:min(start.y,p.y),width:abs(p.x-start.x),height:abs(p.y-start.y));selection.isHidden=false;selection.transform = .identity;selection.frame=actual(rect);handle.isHidden=true;rotateHandle.isHidden=true;if g.state == .ended{marqueeStart=nil;onMarquee?(rect)}else if g.state == .cancelled{marqueeStart=nil;setNeedsLayout()}}
   return
  }
  if g.state == .began {
   let translation=g.translation(in:self);dragStart=pointerOrigin ?? logical(CGPoint(x:point.x-translation.x,y:point.y-translation.y));changed=false
   if isSource {if operate{onPointer?("down",p)};return}
   if selectedIDs.count>1 && nodes.contains(where:{selectedIDs.contains($0.id) && $0.selectionBounds.contains(dragStart)}){action="move"}
   else if !handle.isHidden && handle.frame.insetBy(dx:-12,dy:-12).contains(CGPoint(x:point.x-screenRect.minX,y:point.y-screenRect.minY)){action="resize"}
   else if !rotateHandle.isHidden && rotateHandle.frame.insetBy(dx:-12,dy:-12).contains(CGPoint(x:point.x-screenRect.minX,y:point.y-screenRect.minY)){action="rotate"}
   else{action=tool=="resize" || tool=="rotate" ? tool : "move";selected=hit(dragStart)?.id;onSelect?(selected)}
   if selectedIDs.count>1{action="move"}
   if let n=nodes.first(where:{$0.id==selected}){lastAngle=atan2(p.y-n.frame.midY,p.x-n.frame.midX)}
  }
  if isSource {if operate {onPointer?(g.state == .ended || g.state == .cancelled ? "up" : "move",p)};return}
  if let id=selected {var delta=CGPoint(x:p.x-dragStart.x,y:p.y-dragStart.y);if let n=nodes.first(where:{$0.id==id}){if action=="rotate"{let angle=atan2(p.y-n.frame.midY,p.x-n.frame.midX);var change=(angle-lastAngle)*180/CGFloat.pi;if change>180{change-=360};if change < -180{change+=360};delta.x=change;lastAngle=angle}else if action=="resize"{delta=delta.applying(CGAffineTransform(rotationAngle: -n.rotation * .pi/180))}};onMove?(id,delta,action,g.state == .ended || g.state == .cancelled);dragStart=p}
 }
 override func gestureRecognizerShouldBegin(_ gestureRecognizer:UIGestureRecognizer)->Bool{ !isSource || operate || gestureRecognizer !== panGesture }
 func dragInteraction(_ interaction:UIDragInteraction,itemsForBeginning session:UIDragSession)->[UIDragItem]{
  guard isSource && !operate,let n=hit(pointerOrigin ?? logical(session.location(in:self))) else{return []}
  selected=n.id;onSelect?(n.id)
  let item=UIDragItem(itemProvider:NSItemProvider(object:("node:"+n.id) as NSString));item.localObject=n
  item.previewProvider={[weak self] in self?.resourceDragPreview(n)}
  return [item]
 }
 func resourceDragPreview(_ n:StudioNode)->UIDragPreview {
  let scale=min(screenRect.width/logicalSize.width,180/max(1,n.width),180/max(1,n.height))
  let size=CGSize(width:max(20,n.width*scale),height:max(20,n.height*scale))
  let card=UIView(frame:CGRect(origin:.zero,size:size));card.backgroundColor=UIColor(studioHex:n.fill);card.layer.cornerRadius=n.cornerRadius*scale
  card.layer.borderColor=UIColor(studioHex:n.strokeColor).cgColor;card.layer.borderWidth=n.strokeWidth*scale
  if n.type=="image",let asset=previewAsset?(n.asset){let v=UIImageView(image:asset);v.frame=card.bounds;v.contentMode=n.fit=="stretch" ? .scaleToFill : n.fit=="fill" ? .scaleAspectFill : .scaleAspectFit;v.clipsToBounds=true;card.addSubview(v)}
  else if n.type=="text" || n.type=="button" || n.type=="image" || n.type=="region" {
   let label=UILabel(frame:card.bounds);label.text=n.type=="image" || n.type=="region" ? n.name : n.text;label.numberOfLines=0;label.textColor=UIColor(studioHex:n.color);label.font=UIFont(name:n.fontName,size:max(10,n.fontSize*scale)) ?? .systemFont(ofSize:max(10,n.fontSize*scale));label.textAlignment = .center;label.adjustsFontSizeToFitWidth=true;card.addSubview(label)
  }
  card.alpha=n.opacity
  let parameters=UIDragPreviewParameters();parameters.backgroundColor = .clear
  return UIDragPreview(view:card,parameters:parameters)
 }
 func dropInteraction(_ interaction:UIDropInteraction,canHandle session:UIDropSession)->Bool{!session.hasItemsConforming(toTypeIdentifiers:["public.file-url"]) && !isSource && session.canLoadObjects(ofClass:NSString.self)}
 func dropInteraction(_ interaction:UIDropInteraction,sessionDidUpdate session:UIDropSession)->UIDropProposal{UIDropProposal(operation:.copy)}
 func dropInteraction(_ interaction:UIDropInteraction,performDrop session:UIDropSession){let p=logical(session.location(in:self));session.loadObjects(ofClass:NSString.self){items in if let s=items.first as? String{DispatchQueue.main.async{self.onDrop?(s,p)}}}}
}
