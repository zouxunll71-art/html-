import UIKit
extension StudioNode {
 var hasVisibleSelectionContent:Bool {
  guard !hidden,!locked,opacity>0.01,width>0,height>0 else{return false}
  let backdrop=UIColor(studioHex:fill).cgColor.alpha>0.01 || (strokeWidth>0 && UIColor(studioHex:strokeColor).cgColor.alpha>0.01) || gradient != nil
  if ["text","button","nativeButton"].contains(type),!backdrop,((text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && (symbol ?? "").isEmpty) || UIColor(studioHex:color).cgColor.alpha<=0.01){return false}
  if ["container","scroll","shape"].contains(type){return UIColor(studioHex:fill).cgColor.alpha>0.01 || (strokeWidth>0 && UIColor(studioHex:strokeColor).cgColor.alpha>0.01) || gradient != nil}
  return true
 }
 var selectionFrame:CGRect {
  guard type=="text",!text.isEmpty else{return frame}
  let fonts=LayoutViewController(),a=NSMutableAttributedString(string:text,attributes:[.font:fonts.font(self)])
  for span in textSpans ?? [] where span.start>=0 && span.end<=a.length && span.end>span.start {var style=self;style.fontSize=span.fontSize ?? fontSize;style.fontWeight=span.fontWeight ?? fontWeight;style.italic=span.italic ?? italic;a.addAttribute(.font,value:fonts.font(style),range:NSRange(location:span.start,length:span.end-span.start))}
  let p=NSMutableParagraphStyle();p.lineBreakMode = .byWordWrapping
  if let h=lineHeight{p.minimumLineHeight=max(h,fonts.font(self).lineHeight)}
  a.addAttribute(.paragraphStyle,value:p,range:NSRange(location:0,length:a.length))
  if let spacing=letterSpacing{a.addAttribute(.kern,value:spacing,range:NSRange(location:0,length:a.length))}
  let measured=a.boundingRect(with:CGSize(width:width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],context:nil)
  let w=min(width,ceil(measured.width)+2),h=min(height,ceil(measured.height)+2)
  return CGRect(x:x+(alignment=="center" ? (width-w)/2 : alignment=="right" ? width-w:0),y:y+(height-h)/2,width:w,height:h)
 }
 var selectionBounds:CGRect {
  let center=CGPoint(x:frame.midX,y:frame.midY)
  return selectionFrame.offsetBy(dx:-center.x,dy:-center.y).applying(CGAffineTransform(scaleX:scale ?? 1,y:scale ?? 1).rotated(by:rotation * .pi/180)).offsetBy(dx:center.x,dy:center.y)
 }
}
