import Foundation
import CoreGraphics

enum ClippingGeometry {
 static func release(frame:CGRect,rotation:CGFloat,scale:CGFloat,old:CGAffineTransform,target:CGAffineTransform)->(center:CGPoint,rotation:CGFloat,scale:CGFloat)? {
  guard abs(target.a*target.d-target.b*target.c)>0.000001 else{return nil}
  let relative=old.concatenating(target.inverted())
  return (CGPoint(x:frame.midX,y:frame.midY).applying(relative),rotation+atan2(relative.b,relative.a)*180 / .pi,scale*hypot(relative.a,relative.b))
 }
}
