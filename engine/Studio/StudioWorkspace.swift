import UIKit

/// Only touches delivered to the background clear selection. Controls and phone
/// previews retain their own touch handling, including dragging and text input.
final class StudioWorkspace:UIView {
 var onBackgroundTap:(()->Void)?
 private var down:CGPoint?
 override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?){
  super.touchesBegan(touches,with:event)
  down=touches.first?.view === self ? touches.first?.location(in:self) : nil
 }
 override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?){
  super.touchesEnded(touches,with:event)
  defer{down=nil}
  guard let origin=down,let touch=touches.first,touch.view === self else{return}
  let end=touch.location(in:self)
  if hypot(end.x-origin.x,end.y-origin.y)<6{onBackgroundTap?()}
 }
 override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?){
  down=nil;super.touchesCancelled(touches,with:event)
 }
}
