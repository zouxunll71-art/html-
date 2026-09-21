import UIKit
extension StudioController {
 func handleNativeChromeTap(_ point:CGPoint)->Bool {
  if rawScene["browserOpen"] as? Bool==true{setStatus("切到「运行预览」可在左侧手机操作网页；「关闭网页」返回应用");return true}
  guard running,(rawScene["modalPages"] as? [String] ?? []).isEmpty else{return false}
  for target in rawScene["chromeHitTargets"] as? [[String:Any]] ?? [] {
   guard let x=target["x"] as? Double,let y=target["y"] as? Double,let width=target["width"] as? Double,let height=target["height"] as? Double,let event=target["event"] as? [String:Any] else{continue}
   if CGRect(x:x,y:y,width:width,height:height).contains(point){dispatchEvent(event,side:"ios");return true}
  }
  return false
 }
}
