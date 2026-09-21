import UIKit
import CoreText
/// The very same controller is used inside the editor and copied into the iOS export.
/// Element IDs remain stable. Business logic connects through onAction without changing layout.
final class LayoutViewController: UIViewController {
 var page=StudioPage(name:"空白页",route:"blank") {didSet { if isViewLoaded {rebuild()} }}
 var assetProvider:((String)->UIImage?)?;var fonts:[URL]=[] {didSet {registerFonts()}}
 var onAction:((String)->Void)?;var elements:[String:UIView]=[:]
 var previous:[String:StudioNode]=[:];var previousOrder:[String]=[];var editingCanvas=false;var lifecycle:[String]=[]
 override func viewDidLoad(){super.viewDidLoad();lifecycle.append("viewDidLoad");registerFonts();rebuild()}
 override func viewWillAppear(_ animated:Bool){super.viewWillAppear(animated);lifecycle.append("viewWillAppear")}
 override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);lifecycle.append("viewDidAppear")}
 override func viewWillDisappear(_ animated:Bool){super.viewWillDisappear(animated);lifecycle.append("viewWillDisappear")}
 func registerFonts(){for url in fonts {CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)}}
 func font(_ n:StudioNode)->UIFont {
  let weight=UIFont.Weight(rawValue:(n.fontWeight-400)/500)
  let familyName=n.fontFamily=="serif" ? "TimesNewRomanPSMT" : n.fontFamily=="monospace" ? "Menlo-Regular" : n.fontFamily=="cursive" ? "SnellRoundhand" : ""
  let f=UIFont(name:n.fontName.isEmpty ? familyName : n.fontName,size:n.fontSize) ?? .systemFont(ofSize:n.fontSize,weight:weight)
  let d=f.fontDescriptor.addingAttributes([UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String):[NSNumber(value:0x77676874):NSNumber(value:Double(n.fontWeight))]])
  var traits=d.symbolicTraits
  if n.italic==true{traits.insert(.traitItalic)}
  if n.fontWeight>=600{traits.insert(.traitBold)}
  return UIFont(descriptor:d.withSymbolicTraits(traits) ?? d,size:n.fontSize)
 }
 func rebuild(){
  view.backgroundColor=UIColor(studioHex:page.background)
  let visible=page.nodes.filter{ !$0.hidden };let ids=visible.map{$0.id};let wanted=Set(ids)
  for id in Array(elements.keys) where !wanted.contains(id){elements.removeValue(forKey:id)?.removeFromSuperview();previous.removeValue(forKey:id)}
  for n in visible {
   let old=previous[n.id]
   let sameKind=old?.type==n.type && (old?.fit=="nineSlice" && (old?.capPixels ?? 0)>0)==(n.fit=="nineSlice" && n.capPixels>0)
   var v:UIView
   if sameKind,let existing=elements[n.id]{v=existing}else{
    elements[n.id]?.removeFromSuperview()
    if n.type.hasPrefix("native"){let host=NativeControlHost(kind:n.type);host.onAction={[weak self]in self?.onAction?(n.id)};v=host}
    else if n.type=="text" || n.type=="button"{let l=UILabel();l.numberOfLines=0;v=l}
    else if n.type=="image"{v=n.fit=="nineSlice" && n.capPixels>0 ? NineSliceView() : UIImageView()}
    else{v=UIView()}
    v.accessibilityIdentifier=n.id;v.isUserInteractionEnabled = !editingCanvas
    if !editingCanvas && !n.type.hasPrefix("native"){v.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(activate(_:))))}
    view.addSubview(v);elements[n.id]=v
   }
   if old != n {
    if let host=v as? NativeControlHost{host.configure(n)}
    if let label=v as? UILabel {label.text=n.text;label.font=font(n);label.textColor=UIColor(studioHex:n.color);label.textAlignment=n.alignment=="center" ? .center : n.alignment=="right" ? .right : .left}
    if let label=v as? UILabel {
     label.lineBreakMode = .byWordWrapping
     let spans=n.textSpans ?? []
     let text=NSMutableAttributedString(string:n.text,attributes:[.font:font(n),.foregroundColor:UIColor(studioHex:n.color)])
     for span in spans where span.start>=0 && span.end<=text.length && span.end>span.start {
      var style=n;style.fontSize=span.fontSize ?? n.fontSize;style.fontWeight=span.fontWeight ?? n.fontWeight;style.italic=span.italic ?? n.italic
      let range=NSRange(location:span.start,length:span.end-span.start);text.addAttribute(.font,value:font(style),range:range)
      if let color=span.color{text.addAttribute(.foregroundColor,value:UIColor(studioHex:color),range:range)}
      if span.underline==true{text.addAttribute(.underlineStyle,value:NSUnderlineStyle.single.rawValue,range:range)}
     }
     let paragraph=NSMutableParagraphStyle();paragraph.alignment=label.textAlignment;paragraph.lineBreakMode = .byWordWrapping
     if let height=n.lineHeight,height>0{paragraph.minimumLineHeight=height;paragraph.maximumLineHeight=height}
     text.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:text.length))
     if let spacing=n.letterSpacing{text.addAttribute(.kern,value:spacing,range:NSRange(location:0,length:text.length))}
     label.attributedText=text
    }
    if let image=v as? UIImageView{if old?.asset != n.asset{image.image=assetProvider?(n.asset)};image.contentMode=n.fit=="fill" ? .scaleAspectFill : n.fit=="stretch" ? .scaleToFill : .scaleAspectFit}
    if let panel=v as? NineSliceView{panel.image=assetProvider?(n.asset);panel.sourceCap=n.capPixels;panel.destinationCap=n.capPoints;panel.setNeedsDisplay()}
    v.backgroundColor=UIColor(studioHex:n.fill);v.layer.cornerRadius=n.cornerRadius;v.layer.borderColor=UIColor(studioHex:n.strokeColor).cgColor;v.layer.borderWidth=n.strokeWidth;v.clipsToBounds=true;v.alpha=n.opacity;v.accessibilityLabel=n.name
   }
   previous[n.id]=n
  }
  if ids != previousOrder{for id in ids{if let v=elements[id]{view.bringSubviewToFront(v)}};previousOrder=ids}
  view.setNeedsLayout()
 }
 @objc func activate(_ g:UITapGestureRecognizer){if let id=g.view?.accessibilityIdentifier{onAction?(id)}}
 override func viewDidLayoutSubviews(){
  super.viewDidLayoutSubviews()
  let s=view.bounds.width/max(page.width,1);let dy=view.bounds.height-page.height*s
  for n in page.nodes {guard let v=elements[n.id] else{continue};v.transform = .identity
   let y=n.y*s+(n.anchor=="bottomLeft" ? dy : n.anchor=="center" ? dy/2 : 0)
   v.frame=CGRect(x:n.x*s,y:y,width:n.width*s,height:n.height*s);v.transform=CGAffineTransform(rotationAngle:n.rotation * .pi/180)
   if let label=v as? UILabel {label.font=font(n).withSize(n.fontSize*s)}
  }
 }
}
/// Pixel caps and point caps are distinct. This avoids stretching ornate source borders.
final class NineSliceView:UIView {
 var image:UIImage?;var sourceCap:CGFloat=0;var destinationCap:CGFloat=13
 override func draw(_ rect:CGRect){
  guard let image=image,let cg=image.cgImage,let ctx=UIGraphicsGetCurrentContext() else{return}
  let w=CGFloat(cg.width),h=CGFloat(cg.height),c=min(sourceCap,min(w,h)/2)
  let d=min(destinationCap,min(bounds.width,bounds.height)/2)
  let sx:[CGFloat]=[0,c,w-c,w],sy:[CGFloat]=[0,c,h-c,h],dx:[CGFloat]=[0,d,bounds.width-d,bounds.width],dy:[CGFloat]=[0,d,bounds.height-d,bounds.height]
  ctx.interpolationQuality = .high
  for row in 0..<3 {for col in 0..<3 {
   if let part=cg.cropping(to:CGRect(x:sx[col],y:sy[row],width:sx[col+1]-sx[col],height:sy[row+1]-sy[row])) {UIImage(cgImage:part).draw(in:CGRect(x:dx[col],y:dy[row],width:dx[col+1]-dx[col],height:dy[row+1]-dy[row]))}
  }}
 }
 override func layoutSubviews(){super.layoutSubviews();setNeedsDisplay()}
}
