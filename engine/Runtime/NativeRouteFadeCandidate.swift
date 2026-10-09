import Foundation
import QuartzCore

/// QA-only alternative to the route snapshot overlay. This does not claim
/// identical render-server caching or interruption behavior; compare real frames.
final class NativeRouteFadeCandidate {
 let enabled:Bool
 private let owner=UUID().uuidString
 private static let ownerKey="studioRouteFadeOwner"

 init(enabled:Bool=ProcessInfo.processInfo.arguments.contains("--studio-ca-route-fade")){
  self.enabled=enabled
 }

 /// Core Animation automatically uses kCATransition for a CATransition,
 /// regardless of a caller's preferred key. Never remove an unrelated owner.
 func cancel(on layer:CALayer){
  guard enabled,let animation=layer.animation(forKey:kCATransition),
        animation.value(forKey:Self.ownerKey) as? String==owner else{return}
  layer.removeAnimation(forKey:kCATransition)
 }

 /// Returns false without running updates when the original snapshot path
 /// should handle this change. The caller retains the existing route/window/
 /// Reduce Motion gate and supplies the editable transition duration.
 func perform(on layer:CALayer,duration:TimeInterval,updates:()->Void)->Bool{
  guard enabled,duration.isFinite,duration>0,layer.animation(forKey:kCATransition)==nil else{return false}
  let transition=CATransition()
  transition.type = .fade
  transition.duration=duration
  transition.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
  transition.startProgress=0;transition.endProgress=1
  transition.isRemovedOnCompletion=true
  transition.setValue(owner,forKey:Self.ownerKey)
  // Add before mutating the hierarchy, in the same explicit transaction.
  // Disable only implicit property actions; this explicit crossfade remains.
  CATransaction.begin()
  CATransaction.setDisableActions(true)
  layer.add(transition,forKey:kCATransition)
  updates()
  CATransaction.commit()
  return true
 }
}
