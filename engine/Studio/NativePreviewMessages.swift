import UIKit
import SafariServices
extension StudioController {
 func handleNativePreviewMessage(_ message:[String:Any])->Bool {
  if message["type"] as? String=="symbol" {
   guard let name=message["name"] as? String,let key=message["key"] as? String else{return true}
   guard let symbol=UIImage(systemName:name,withConfiguration:UIImage.SymbolConfiguration(pointSize:24)) else{setStatus("SF 图标不存在或当前系统不支持："+name);return true}
   let tinted=symbol.withTintColor(UIColor(studioHex:message["color"] as? String ?? "#17212B"),renderingMode:.alwaysOriginal)
   let image=UIGraphicsImageRenderer(size:CGSize(width:28,height:28)).image{_ in tinted.draw(in:CGRect(x:2,y:2,width:24,height:24))}
   guard let data=image.pngData(),let args=try? JSONSerialization.data(withJSONObject:[key,"data:image/png;base64,"+data.base64EncodedString()]),let json=String(data:args,encoding:.utf8) else{return true}
   web.evaluateJavaScript("window.studioSymbol?.(...\(json))",completionHandler:nil);return true
  }
  if message["type"] as? String=="openURL" {
   if linked{setStatus("链接已同步到 iOS，由系统浏览器打开")}
   else if let value=message["url"] as? String,let url=URL(string:value),url.scheme=="https",url.host != nil{
    let controller=SFSafariViewController(url:url);present(controller,animated:true)
   }
   return true
  }
  return false
 }
}
