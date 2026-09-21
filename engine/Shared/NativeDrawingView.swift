import UIKit

/// Protocol drawing surface shared by every exported project.
final class NativeDrawingView: UIView {
 var specification:[String:Any]=[:] { didSet { setNeedsDisplay() } }
 override func draw(_ rect:CGRect) {
  guard let context=UIGraphicsGetCurrentContext() else {return}
  func path(_ points:[[Double]],closed:Bool)->UIBezierPath {
   let p=UIBezierPath()
   for (i,xy) in points.enumerated() where xy.count==2 {
    let point=CGPoint(x:xy[0]*Double(bounds.width),y:xy[1]*Double(bounds.height))
    if i==0 {p.move(to:point)} else {p.addLine(to:point)}
   }
   if closed {p.close()};return p
  }
  if let mesh=specification["mesh"] as? [[String:Any]] {
   for face in mesh {
    guard let points=face["points"] as? [[Double]] else {continue}
    let p=path(points,closed:true)
    UIColor(studioHex:face["color"] as? String ?? "#CCCCCC").setFill();p.fill()
   }
  } else if let points=specification["points"] as? [[Double]] {
   let p=path(points,closed:specification["closed"] as? Bool ?? false)
   if specification["closed"] as? Bool == true {UIColor(studioHex:specification["fill"] as? String ?? "#00000000").setFill();p.fill()}
   UIColor(studioHex:specification["color"] as? String ?? "#17212B").setStroke()
   p.lineWidth=max(1,(specification["strokeWidth"] as? Double ?? 2)*Double(bounds.width)/max(1,specification["width"] as? Double ?? 393))
   p.lineJoinStyle = .round;p.lineCapStyle = .round;p.stroke()
  }
  context.flush()
 }
 override func layoutSubviews(){super.layoutSubviews();setNeedsDisplay()}
}
