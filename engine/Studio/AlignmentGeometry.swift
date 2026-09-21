import Foundation
import CoreGraphics

/// Operates in document points; callers retain unsnapped pointer motion.
enum AlignmentGeometry {
 struct Result {var correction:CGPoint;var x:CGFloat?;var y:CGFloat?}
 static func snap(_ rect:CGRect,to targets:[CGRect],threshold:CGFloat)->Result {
  func nearest(_ anchors:[CGFloat],_ values:[CGFloat])->(CGFloat,CGFloat?) {
   var distance=threshold+1,delta:CGFloat=0,line:CGFloat?
   for target in values{for anchor in anchors{let d=target-anchor;if abs(d)<=threshold && abs(d)<distance{distance=abs(d);delta=d;line=target}}}
   return (delta,line)
  }
  let x=nearest([rect.minX,rect.midX,rect.maxX],targets.flatMap{[$0.minX,$0.midX,$0.maxX]})
  let y=nearest([rect.minY,rect.midY,rect.maxY],targets.flatMap{[$0.minY,$0.midY,$0.maxY]})
  return Result(correction:CGPoint(x:x.0,y:y.0),x:x.1,y:y.1)
 }
}
