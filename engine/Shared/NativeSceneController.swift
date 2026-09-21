import UIKit
import CoreText
final class PassThroughContainer:UIView {var acceptsBackgroundTap=false;override func hitTest(_ point:CGPoint,with event:UIEvent?)->UIView?{let target=super.hitTest(point,with:event);return target===self && !acceptsBackgroundTap ? nil:target}}
final class NativeSceneController:UIViewController,UIScrollViewDelegate,UITextFieldDelegate,UITextViewDelegate,UIGestureRecognizerDelegate {
 var scene:[String:Any]=[:];var views:[String:UIView]=[:];var kinds:[String:String]=[:];var specs:[String:[String:Any]]=[:]
 var assetProvider:((String)->UIImage?)?;var onEvent:(([String:Any])->Void)?;var applying=false;var animation:UIViewPropertyAnimator?;var lastAnimationID="";var enteringAnimation=false
 var layoutConstraints:[String:[NSLayoutConstraint]]=[:];var contentConstraints:[String:[NSLayoutConstraint]]=[:];var layingOut=false;var renderedWidth:CGFloat = -1;var layoutSize=CGSize.zero
 let fonts=NativeTypography();var scrollWork:[String:DispatchWorkItem]=[:];var localScrollUntil:[String:TimeInterval]=[:]
 override func viewDidLoad(){super.viewDidLoad();view.backgroundColor = .white;let tap=UITapGestureRecognizer(target:self,action:#selector(dismissKeyboard));tap.cancelsTouchesInView=false;tap.delegate=self;view.addGestureRecognizer(tap)}
 func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive touch:UITouch)->Bool{var target=touch.view;while let item=target{if item is UIControl || item is UITextView{return false};target=item.superview};return true}
 @objc func dismissKeyboard(){view.endEditing(true)}
 func number(_ d:[String:Any],_ key:String,_ fallback:CGFloat=0)->CGFloat{(d[key] as? NSNumber).map{CGFloat(truncating:$0)} ?? fallback}
 func apply(_ page:[String:Any],animated:Bool=true) {
  loadViewIfNeeded()
  if animated,!UIAccessibility.isReduceMotionEnabled,let a=page["animation"] as? [String:Any],let duration=a["duration"] as? Double,duration>0,let aid=page["animationID"] as? String,aid != lastAnimationID {
   lastAnimationID=aid;animation?.stopAnimation(false);animation?.finishAnimation(at:.current)
   let incoming=Set((page["nodes"] as? [[String:Any]] ?? []).compactMap{$0["id"] as? String});let removed=Set(views.keys).subtracting(incoming);var ghosts=[UIView]()
   for id in removed where !removed.contains(specs[id]?["parent"] as? String ?? ""){if let old=views[id],let snapshot=old.snapshotView(afterScreenUpdates:false){snapshot.frame=old.convert(old.bounds,to:view);view.addSubview(snapshot);ghosts.append(snapshot)}}
   let changes={self.enteringAnimation=true;self.apply(page,animated:false);self.enteringAnimation=false;ghosts.forEach{$0.alpha=0}}
   let animator:UIViewPropertyAnimator
   if a["curve"] as? String=="spring"{animator=UIViewPropertyAnimator(duration:duration,dampingRatio:0.82,animations:changes)}else{animator=UIViewPropertyAnimator(duration:duration,curve:a["curve"] as? String=="linear" ? .linear : .easeInOut,animations:changes)}
   animator.addCompletion{_ in ghosts.forEach{$0.removeFromSuperview()}};animation=animator;animator.startAnimation(afterDelay:a["delay"] as? Double ?? 0);return
  }

  loadViewIfNeeded();scene=page;applying=true
  if abs(renderedWidth-view.bounds.width)>0.5{renderedWidth=view.bounds.width;specs.removeAll()}
  let nodes=page["nodes"] as? [[String:Any]] ?? [];let ids=Set(nodes.compactMap{$0["id"] as? String})
  for id in Array(views.keys) where !ids.contains(id){scrollWork.removeValue(forKey:id)?.cancel();localScrollUntil.removeValue(forKey:id);NSLayoutConstraint.deactivate(layoutConstraints.removeValue(forKey:id) ?? []);NSLayoutConstraint.deactivate(contentConstraints.removeValue(forKey:id) ?? []);views.removeValue(forKey:id)?.removeFromSuperview();kinds.removeValue(forKey:id);specs.removeValue(forKey:id)}
  for n in nodes {
   guard let id=n["id"] as? String,let kind=n["type"] as? String else{continue}
   if let previous=specs[id],NSDictionary(dictionary:previous).isEqual(to:n),let cached=views[id]{cached.superview?.bringSubviewToFront(cached);continue}
   var v=views[id]
   if kinds[id] != kind {
    NSLayoutConstraint.deactivate(layoutConstraints.removeValue(forKey:id) ?? []);NSLayoutConstraint.deactivate(contentConstraints.removeValue(forKey:id) ?? []);v?.removeFromSuperview()
    switch kind {
    case "text":let label=UILabel();label.numberOfLines=0;v=label
    case "image":v=UIImageView()
    case "path","model":v=NativeDrawingView()
    case "nativeButton","nativeCheckbox":let b=UIButton(type:.system);b.addTarget(self,action:#selector(controlChanged(_:)),for:.touchUpInside);v=b
    case "nativeSwitch":let c=UISwitch();c.addTarget(self,action:#selector(controlChanged(_:)),for:.valueChanged);v=c
    case "nativeSlider":let c=UISlider();c.addTarget(self,action:#selector(controlChanged(_:)),for:.valueChanged);v=c
    case "nativeSegment":let c=UISegmentedControl();c.addTarget(self,action:#selector(controlChanged(_:)),for:.valueChanged);v=c
    case "nativeStepper":let c=UIStepper();c.addTarget(self,action:#selector(controlChanged(_:)),for:.valueChanged);v=c
    case "nativeProgress":v=UIProgressView()
    case "nativeSpinner":let c=UIActivityIndicatorView(style:.medium);c.startAnimating();v=c
    case "nativeTextField":let c=UITextField();c.delegate=self;c.addTarget(self,action:#selector(controlChanged(_:)),for:.editingChanged);v=c
    case "nativeTextView":let c=UITextView();c.delegate=self;v=c
    case "container":v=PassThroughContainer()
    case "scroll":let c=UIScrollView();c.contentInsetAdjustmentBehavior = .never;c.delegate=self;c.keyboardDismissMode = .interactive;v=c
    default:v=UIView()
    }
    guard let fresh=v else{continue};fresh.accessibilityIdentifier=id;if enteringAnimation{fresh.alpha=0}
    if !(fresh is UIControl) && !(fresh is UITextView) && !((page["events"] as? [String:[String:Any]])?[id]?["action"] as? String ?? "").isEmpty{fresh.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tapped(_:))))}
    views[id]=fresh;kinds[id]=kind
   }
   guard let item=v else{continue};specs[id]=n
   if !(item is UIControl) && !(item is UITextView) && !(n["action"] as? String ?? "").isEmpty && (item.gestureRecognizers ?? []).isEmpty{item.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tapped(_:))))}
   if let container=item as? PassThroughContainer{container.acceptsBackgroundTap = !((page["events"] as? [String:[String:Any]])?[id]?["action"] as? String ?? "").isEmpty || UIColor(studioHex:n["fill"] as? String ?? "#00000000").cgColor.alpha>0}
   let parent=views[n["parent"] as? String ?? ""] ?? view!
   if item.superview !== parent{NSLayoutConstraint.deactivate(layoutConstraints.removeValue(forKey:id) ?? []);parent.addSubview(item)}
   item.translatesAutoresizingMaskIntoConstraints=false
   if layoutConstraints[id]==nil {
    let lead=(parent as? UIScrollView)?.contentLayoutGuide.leadingAnchor ?? parent.leadingAnchor,top=(parent as? UIScrollView)?.contentLayoutGuide.topAnchor ?? parent.topAnchor
    let constraints=[item.leadingAnchor.constraint(equalTo:lead),item.topAnchor.constraint(equalTo:top),item.widthAnchor.constraint(equalToConstant:1),item.heightAnchor.constraint(equalToConstant:1)];layoutConstraints[id]=constraints;NSLayoutConstraint.activate(constraints)
   }
   if let control=item as? UIControl{control.isSelected=n["selected"] as? Bool ?? false;control.isEnabled = !(n["disabled"] as? Bool ?? false)};item.isHidden=n["hidden"] as? Bool ?? false;item.isUserInteractionEnabled = !(n["disabled"] as? Bool ?? false)
   item.backgroundColor=UIColor(studioHex:n["fill"] as? String ?? "#00000000");item.alpha=number(n,"opacity",1);item.layer.cornerRadius=number(n,"cornerRadius");item.layer.borderWidth=number(n,"strokeWidth");item.layer.borderColor=UIColor(studioHex:n["strokeColor"] as? String ?? "#00000000").cgColor;item.clipsToBounds=(n["clip"] as? Bool ?? false)||kind=="image"||kind=="scroll"
   if let g=n["gradient"] as? [String:Any],let colors=g["colors"] as? [String]{let layer=(item.layer.sublayers?.first{$0.name=="studio.gradient"} as? CAGradientLayer) ?? CAGradientLayer();layer.name="studio.gradient";layer.colors=colors.map{UIColor(studioHex:$0).cgColor};layer.locations=(g["locations"] as? [Double])?.map{NSNumber(value:$0)};let start=g["start"] as? [CGFloat] ?? [0,0],end=g["end"] as? [CGFloat] ?? [0,1];layer.startPoint=CGPoint(x:start[0],y:start[1]);layer.endPoint=CGPoint(x:end[0],y:end[1]);layer.cornerRadius=item.layer.cornerRadius;if layer.superlayer==nil{item.layer.insertSublayer(layer,at:0)}}else{item.layer.sublayers?.first{$0.name=="studio.gradient"}?.removeFromSuperlayer()}
   if let sh=n["shadow"] as? [String:Any]{item.layer.shadowColor=UIColor(studioHex:sh["color"] as? String ?? "#00000033").cgColor;item.layer.shadowOpacity=1;item.layer.shadowOffset=CGSize(width:number(sh,"x"),height:number(sh,"y"));item.layer.shadowRadius=number(sh,"blur")/2}else{item.layer.shadowOpacity=0}
   let color=UIColor(studioHex:n["color"] as? String ?? "#17212B");item.tintColor=color
   if let drawing=item as? NativeDrawingView {drawing.specification=n;drawing.isOpaque=false;drawing.backgroundColor = .clear}
   var node=StudioNode();if let d=try? JSONSerialization.data(withJSONObject:n),let decoded=try? JSONDecoder().decode(StudioNode.self,from:d){node=decoded}
   let fontScale=StudioWidthScale.factor(view.bounds.width>0 ? view.bounds.width:number(scene,"width",393),designWidth:number(scene,"width",393));var scaledNode=node;scaledNode.fontSize *= fontScale;let font=fonts.font(scaledNode),text=n["text"] as? String ?? ""
   if let label=item as? UILabel {
    let a=NSMutableAttributedString(string:text,attributes:[.font:font,.foregroundColor:color]);let paragraph=NSMutableParagraphStyle();paragraph.alignment=node.alignment=="center" ? .center : node.alignment=="right" ? .right : .left
    if let h=node.lineHeight{paragraph.minimumLineHeight=h*fontScale;paragraph.maximumLineHeight=h*fontScale};a.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:a.length))
    if let space=node.letterSpacing{a.addAttribute(.kern,value:space*fontScale,range:NSRange(location:0,length:a.length))}
    for span in node.textSpans ?? [] where span.start>=0 && span.end<=a.length && span.end>span.start{var style=node;style.fontSize=(span.fontSize ?? node.fontSize)*fontScale;style.fontWeight=span.fontWeight ?? node.fontWeight;style.italic=span.italic ?? node.italic;let r=NSRange(location:span.start,length:span.end-span.start);a.addAttribute(.font,value:fonts.font(style),range:r);if let c=span.color{a.addAttribute(.foregroundColor,value:UIColor(studioHex:c),range:r)};if span.underline==true{a.addAttribute(.underlineStyle,value:1,range:r)}}
    if label.attributedText != a{label.attributedText=a}
   }
   if let image=item as? UIImageView{image.image=(n["symbol"] as? String).flatMap{UIImage(systemName:$0)} ?? assetProvider?(n["asset"] as? String ?? "");image.contentMode=node.fit=="stretch" ? .scaleToFill : node.fit=="fill" ? .scaleAspectFill : .scaleAspectFit}
   if let b=item as? UIButton{b.setTitle(text,for:.normal);if kind=="nativeCheckbox"{b.setImage(UIImage(systemName:(n["isOn"] as? Bool ?? false) ? "checkmark.square.fill":"square"),for:.normal);b.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize:font.pointSize),forImageIn:.normal)};b.setTitleColor(color,for:.normal);b.titleLabel?.font=font;b.titleLabel?.numberOfLines=0;b.contentHorizontalAlignment=node.alignment=="left" ? .left : node.alignment=="right" ? .right : .center}
   if let f=item as? UITextField{if f.text != text && !f.isFirstResponder{f.text=text};f.font=font;f.textColor=color;f.placeholder=n["placeholder"] as? String;f.isSecureTextEntry=n["inputType"] as? String=="password";f.keyboardType=n["inputType"] as? String=="number" ? .decimalPad : .default;f.borderStyle = .none}
   if let f=item as? UITextView{if f.text != text && !f.isFirstResponder{f.text=text};f.font=font;f.textColor=color;f.textContainerInset = .zero}
   if let c=item as? UISwitch{c.setOn(n["isOn"] as? Bool ?? false,animated:false)}
   if let c=item as? UISlider{c.minimumValue=Float(number(n,"minimum"));c.maximumValue=Float(number(n,"maximum",1));c.value=Float(number(n,"value"))}
   if let c=item as? UIProgressView{c.progress=Float(number(n,"value"))}
   if let c=item as? UISegmentedControl{let options=n["options"] as? [String] ?? [];if c.numberOfSegments != options.count || options.enumerated().contains(where:{c.titleForSegment(at:$0.offset) != $0.element}){c.removeAllSegments();for(i,title)in options.enumerated(){c.insertSegment(withTitle:title,at:i,animated:false)}};c.selectedSegmentIndex=Int(number(n,"value"))}
   if let c=item as? UIStepper{c.minimumValue=Double(number(n,"minimum"));c.maximumValue=Double(number(n,"maximum",100));c.stepValue=Double(number(n,"step",1));c.value=Double(number(n,"value"))}
   parent.bringSubviewToFront(item)
  }
  layoutNodes()
  applying=false
 }
 override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();guard !applying,!layingOut else{return};if abs(renderedWidth-view.bounds.width)>0.5{apply(scene,animated:false)}else if layoutSize != view.bounds.size{layoutNodes()}}
 func layoutNodes(){
  guard !layingOut else{return};layingOut=true;layoutSize=view.bounds.size;defer{layingOut=false}
  let scale=StudioWidthScale.factor(view.bounds.width,designWidth:number(scene,"width",393))
  for n in scene["nodes"] as? [[String:Any]] ?? [] {
   guard let id=n["id"] as? String,let item=views[id],let constraints=layoutConstraints[id] else{continue}
   for (index,key) in ["x","y","width","height"].enumerated(){constraints[index].constant=number(n,key)*scale}
   item.transform=CGAffineTransform(rotationAngle:number(n,"rotation") * .pi/180).scaledBy(x:number(n,"scale",1),y:number(n,"scale",1))
   item.layer.cornerRadius=number(n,"cornerRadius")*scale;item.layer.borderWidth=number(n,"strokeWidth")*scale
   if let sh=n["shadow"] as? [String:Any]{item.layer.shadowOffset=CGSize(width:number(sh,"x")*scale,height:number(sh,"y")*scale);item.layer.shadowRadius=number(sh,"blur")*scale/2}
   if let scroll=item as? UIScrollView {
    if contentConstraints[id]==nil{let values=[scroll.contentLayoutGuide.widthAnchor.constraint(equalToConstant:1),scroll.contentLayoutGuide.heightAnchor.constraint(equalToConstant:1)];contentConstraints[id]=values;NSLayoutConstraint.activate(values)}
    contentConstraints[id]?[0].constant=number(n,"contentWidth",number(n,"width"))*scale;contentConstraints[id]?[1].constant=number(n,"contentHeight",number(n,"height"))*scale

   }
  }
  view.layoutIfNeeded()
  // Apply offsets after content size and viewport constraints have settled.
  let wasApplying=applying;applying=true
  for n in scene["nodes"] as? [[String:Any]] ?? [] {
   guard let id=n["id"] as? String,let scroll=views[id] as? UIScrollView,!scroll.isDragging,!scroll.isDecelerating,Date.timeIntervalSinceReferenceDate>(localScrollUntil[id] ?? 0) else{continue}
   let point=CGPoint(x:number(n,"scrollX")*scale,y:number(n,"scrollY")*scale)
   if abs(scroll.contentOffset.x-point.x)>0.25 || abs(scroll.contentOffset.y-point.y)>0.25{scroll.setContentOffset(point,animated:false)}
  }
  applying=wasApplying
  for item in views.values{item.layer.sublayers?.first{$0.name=="studio.gradient"}?.frame=item.bounds}
 }
 /// Called only after the runtime verifies that geometry, content, assets,
 /// actions and chrome are unchanged. Keep UIKit's ongoing gesture in control.
 func applyScrollOffsets(from page:[String:Any]){
  guard isViewLoaded else{return}
  let offsets=Dictionary(((page["nodes"] as? [[String:Any]]) ?? []).filter{$0["type"] as? String=="scroll"}.compactMap{n in (n["id"] as? String).map{($0,n)}},uniquingKeysWith:{_,latest in latest})
  let scale=StudioWidthScale.factor(view.bounds.width,designWidth:number(scene,"width",393))
  let wasApplying=applying;applying=true;defer{applying=wasApplying}
  var nodes=scene["nodes"] as? [[String:Any]] ?? []
  for i in nodes.indices {
   guard let id=nodes[i]["id"] as? String,let n=offsets[id],let scroll=views[id] as? UIScrollView else{continue}
   for key in ["scrollX","scrollY"]{nodes[i][key]=n[key];specs[id]?[key]=n[key]}
   guard !scroll.isDragging,!scroll.isDecelerating,Date.timeIntervalSinceReferenceDate>(localScrollUntil[id] ?? 0) else{continue}
   let point=CGPoint(x:number(n,"scrollX")*scale,y:number(n,"scrollY")*scale)
   if abs(scroll.contentOffset.x-point.x)>0.25 || abs(scroll.contentOffset.y-point.y)>0.25{scroll.setContentOffset(point,animated:false)}
  }
  scene["nodes"]=nodes;scene["animationID"]=page["animationID"]
 }
 @objc func tapped(_ g:UITapGestureRecognizer){guard let id=g.view?.accessibilityIdentifier else{return};if let e=(scene["events"] as? [String:[String:Any]])?[id],!(e["action"] as? String ?? "").isEmpty {onEvent?(["node":id])}}
 @objc func controlChanged(_ sender:UIControl){guard let id=sender.accessibilityIdentifier else{return};var e:[String:Any]=["node":id]
  if let c=sender as? UISegmentedControl{e["value"]=c.selectedSegmentIndex};if let c=sender as? UIStepper{e["value"]=c.value};if let c=sender as? UISwitch{e["value"]=c.isOn};if let c=sender as? UISlider{e["value"]=c.value};if let c=sender as? UITextField{e["value"]=c.text ?? ""};if kinds[id]=="nativeCheckbox"{e["value"] = !(specs[id]?["isOn"] as? Bool ?? false)};onEvent?(e)
 }
 func textViewDidChange(_ textView:UITextView){if let id=textView.accessibilityIdentifier{onEvent?(["node":id,"value":textView.text ?? ""])}}
 func textFieldShouldReturn(_ textField:UITextField)->Bool{textField.resignFirstResponder();return true}
 func queueScroll(_ scrollView:UIScrollView){
  guard !applying,let id=scrollView.accessibilityIdentifier else{return}
  scrollWork[id]?.cancel();localScrollUntil[id]=Date.timeIntervalSinceReferenceDate+0.25
  let p=scrollView.contentOffset,scale=view.bounds.width/number(scene,"width",402);guard scale>0 else{return}
  let work=DispatchWorkItem{[weak self] in guard let self=self,self.views[id]===scrollView else{return};self.onEvent?(["type":"scroll","node":id,"x":max(0,p.x/scale),"y":max(0,p.y/scale)])}
  scrollWork[id]=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.08,execute:work)
 }
 func scrollViewDidScroll(_ scrollView:UIScrollView){if scrollView.isDragging || scrollView.isDecelerating{queueScroll(scrollView)}}
 func scrollViewDidEndDragging(_ scrollView:UIScrollView,willDecelerate decelerate:Bool){if !decelerate{queueScroll(scrollView)}}
 func scrollViewDidEndDecelerating(_ scrollView:UIScrollView){queueScroll(scrollView)}
}
