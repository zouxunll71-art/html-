import UIKit
extension StudioController {
 func copyAllPages(templates:Bool=true){
  let apply={Bridge.shared.json("/mode",["linked":!self.linked]){[weak self]_ in self?.pollRoute()}}
  if linked{apply()}else{let a=UIAlertController(title:"恢复联动",message:"以 iOS 当前页面和状态覆盖 HTML 运行状态。",preferredStyle:.alert);a.addAction(UIAlertAction(title:"取消",style:.cancel));a.addAction(UIAlertAction(title:"以 iOS 为准",style:.default){_ in apply()});present(a,animated:true)}
 }
}
