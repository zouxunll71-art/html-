import UIKit
extension StudioController {
 func layerThumbnail(_ n:StudioNode)->UIImage {
  let format=UIGraphicsImageRendererFormat();format.scale=2
  return UIGraphicsImageRenderer(size:CGSize(width:52,height:52),format:format).image{context in
   let bounds=CGRect(x:0,y:0,width:52,height:52)
   UIColor(studioHex:"#F2F4F7").setFill();context.fill(bounds)
   // Transparency grid belongs only to the inspector thumbnail.
   UIColor(studioHex:"#E3E7ED").setFill();for y in stride(from:0,to:52,by:8){for x in stride(from:0,to:52,by:8) where (x/8+y/8)%2==0{context.fill(CGRect(x:x,y:y,width:8,height:8))}}
   let w=max(4,n.width),h=max(4,n.height),scale=min(44/w,44/h)
   let rect=CGRect(x:(52-w*scale)/2,y:(52-h*scale)/2,width:w*scale,height:h*scale)
   let cg=context.cgContext;cg.saveGState();cg.translateBy(x:26,y:26);cg.rotate(by:n.rotation * .pi/180);cg.translateBy(x:-26,y:-26)
   if n.type=="image",let image=n.symbol.flatMap({UIImage(systemName:$0)?.withTintColor(UIColor(studioHex:n.color),renderingMode:.alwaysOriginal)}) ?? assetCache[n.asset]{
    let ratio=min(rect.width/image.size.width,rect.height/image.size.height);let size=CGSize(width:image.size.width*ratio,height:image.size.height*ratio)
    image.draw(in:CGRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height),blendMode:.normal,alpha:n.opacity)
   } else if n.type=="text" || n.type=="button" {
    let label=UILabel(frame:CGRect(x:3,y:4,width:46,height:44));label.text=n.text;label.numberOfLines=3;label.font = .systemFont(ofSize:12,weight:.medium);label.textColor=UIColor(studioHex:n.color);label.textAlignment = .center;label.layer.render(in:cg)
   } else if n.type.hasPrefix("native") {
    let host=NativeControlHost(kind:n.type);host.configure(n);host.frame=rect;host.layoutIfNeeded();cg.translateBy(x:rect.minX,y:rect.minY);host.layer.render(in:cg)
   } else {
    UIColor(studioHex:n.fill).setFill();let path=UIBezierPath(roundedRect:rect,cornerRadius:min(n.cornerRadius*scale,12));path.fill();UIColor(studioHex:n.strokeColor).setStroke();path.lineWidth=max(1,n.strokeWidth*scale);path.stroke()
   }
   cg.restoreGState()
  }
 }
}
