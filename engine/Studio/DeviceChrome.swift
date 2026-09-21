import UIKit
/// Both previews use the geometry of the user's Web/PhoneShell template.
/// The live iOS framebuffer remains native; only the decorative shell is drawn here.
final class DeviceChrome:UIView {
 static func resource(_ name:String)->UIImage? {
  guard let path=Bundle.main.path(forResource:name,ofType:"png"),let cg=UIImage(contentsOfFile:path)?.cgImage else{return nil}
  return UIImage(cgImage:cg,scale:3,orientation:.up)
 }
 override init(frame:CGRect){super.init(frame:frame);isUserInteractionEnabled=false;backgroundColor = .clear;isOpaque=false}
 required init?(coder:NSCoder){fatalError()}
 override func draw(_ rect:CGRect){
  guard let ctx=UIGraphicsGetCurrentContext() else{return}
  ctx.saveGState();defer{ctx.restoreGState()};ctx.scaleBy(x:bounds.width/456,y:bounds.width/456)
  func fill(_ r:CGRect,_ radius:CGFloat,_ hex:String){UIColor(studioHex:hex).setFill();UIBezierPath(roundedRect:r,cornerRadius:radius).fill()}
  func stroke(_ r:CGRect,_ radius:CGFloat,_ hex:String,_ width:CGFloat){let p=UIBezierPath(roundedRect:r,cornerRadius:radius);p.lineWidth=width;UIColor(studioHex:hex).setStroke();p.stroke()}
  // The 434 x 906 body is centered on a 456 x 910 comparison stage.
  for r in [CGRect(x:8,y:146,width:4,height:36),CGRect(x:8,y:214,width:4,height:66),CGRect(x:8,y:296,width:4,height:66),CGRect(x:444,y:228,width:4,height:102)]{fill(r,3,"#666969")}
  let body=CGRect(x:11,y:2,width:434,height:906)
  ctx.saveGState();UIBezierPath(roundedRect:body,cornerRadius:70).addClip()
  let colors=["#777A7B","#222425","#050606","#2C2E2E","#777A7B"].map{UIColor(studioHex:$0).cgColor} as CFArray
  let locations:[CGFloat]=[0,0.08,0.5,0.93,1]
  if let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:locations){ctx.drawLinearGradient(gradient,start:CGPoint(x:11,y:2),end:CGPoint(x:445,y:908),options:[])}
  ctx.restoreGState()
  stroke(body.insetBy(dx:1,dy:1),69,"#343637",2)
  stroke(body.insetBy(dx:5,dy:5),65,"#FFFFFF38",1)
  // Identical to the Web screen's 8px black outline and 58px corner radius.
  fill(CGRect(x:19,y:10,width:418,height:890),66,"#050606")
 }
 override func layoutSubviews(){super.layoutSubviews();setNeedsDisplay()}
}
