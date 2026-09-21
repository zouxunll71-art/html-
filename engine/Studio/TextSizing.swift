import UIKit
extension StudioNode {
 var hasEditableText:Bool {["text","button","nativeButton","nativeTextField","nativeTextView","nativeSegment","nativeCheckbox"].contains(type)}
 mutating func resizeText(_ size:CGFloat){
  guard size.isFinite,size>0 else{return};let ratio=size/max(1,fontSize);fontSize=size
  if let h=lineHeight{lineHeight=h*ratio}
  if var spans=textSpans{for i in spans.indices{if let s=spans[i].fontSize{spans[i].fontSize=s*ratio}};textSpans=spans}
  fitTextBounds()
 }
 mutating func fitTextBounds(){
  guard hasEditableText else{return}
  let fonts=LayoutViewController(),font=fonts.font(self)
  let content=type=="nativeSegment" ? options.joined(separator:"    ") : text.isEmpty ? placeholder:text
  guard !content.isEmpty else{return}
  let a=NSMutableAttributedString(string:content,attributes:[.font:font])
  for span in textSpans ?? [] where span.start>=0 && span.end<=a.length && span.end>span.start{var style=self;style.fontSize=span.fontSize ?? fontSize;style.fontWeight=span.fontWeight ?? fontWeight;style.italic=span.italic ?? italic;a.addAttribute(.font,value:fonts.font(style),range:NSRange(location:span.start,length:span.end-span.start))}
  let p=NSMutableParagraphStyle();p.lineBreakMode = .byWordWrapping;p.minimumLineHeight=max(lineHeight ?? 0,font.lineHeight)
  a.addAttribute(.paragraphStyle,value:p,range:NSRange(location:0,length:a.length));if let spacing=letterSpacing{a.addAttribute(.kern,value:spacing,range:NSRange(location:0,length:a.length))}
  let single=["button","nativeButton","nativeTextField","nativeSegment","nativeCheckbox"].contains(type),padding:CGFloat=type=="text" ? 2:16
  if single{let natural=a.boundingRect(with:CGSize(width:100000,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],context:nil);width=max(width,ceil(natural.width)+padding+(type=="nativeCheckbox" ? 28:0))}
  let measured=a.boundingRect(with:CGSize(width:max(1,width-padding),height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],context:nil)
  height=max(height,ceil(measured.height)+padding)
 }
}
