import Foundation
import CoreGraphics
@main struct Tests {
 static func main(){
  let frame=CGRect(x:35,y:50,width:100,height:40)
  for (old,target) in [(CGAffineTransform.identity,CGAffineTransform.identity),(CGAffineTransform(translationX:120,y:70).rotated(by:0.6).scaledBy(x:1.8,y:1.8),CGAffineTransform(translationX:10,y:-20).rotated(by:-0.3).scaledBy(x:0.8,y:0.8))] {
   let p=ClippingGeometry.release(frame:frame,rotation:17,scale:1.1,old:old,target:target)!
   for point in [CGPoint(x:-50,y:-20),CGPoint(x:50,y:20),CGPoint.zero] {
    let a=point.applying(CGAffineTransform(rotationAngle:17 * .pi/180).scaledBy(x:1.1,y:1.1)).applying(CGAffineTransform(translationX:frame.midX,y:frame.midY)).applying(old)
    let b=point.applying(CGAffineTransform(rotationAngle:p.rotation * .pi/180).scaledBy(x:p.scale,y:p.scale)).applying(CGAffineTransform(translationX:p.center.x,y:p.center.y)).applying(target)
    precondition(hypot(a.x-b.x,a.y-b.y)<0.00001)
   }
  }
  precondition(ClippingGeometry.release(frame:frame,rotation:0,scale:1,old:.identity,target:CGAffineTransform(scaleX:0,y:0)) == nil)
  print("PASS: flat and nested rotated/scaled release retains world corners; singular target rejected")
 }
}
