import UIKit
extension NativeRuntimeController {
 func shareDocument(_ effect:[String:Any])->Bool {
  guard presentedViewController==nil,let filename=effect["filename"] as? String,let content=effect["content"] as? String,filename.range(of:"^[A-Za-z0-9][A-Za-z0-9._-]{0,100}$",options:.regularExpression) != nil else {return false}
  do {
   let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
   try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   let url=folder.appendingPathComponent(filename);try content.write(to:url,atomically:true,encoding:.utf8)
   let share=UIActivityViewController(activityItems:[url],applicationActivities:nil)
   share.popoverPresentationController?.sourceView=view
   share.popoverPresentationController?.sourceRect=CGRect(x:view.bounds.midX,y:view.bounds.midY,width:1,height:1)
   share.completionWithItemsHandler={_,_,_,_ in try? FileManager.default.removeItem(at:folder)}
   present(share,animated:true);return true
  } catch {return false}
 }
}
