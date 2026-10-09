import UIKit
import CryptoKit
final class Bridge {
 static let shared=Bridge();let base="http://127.0.0.1:18775"
 let token=(try? String(contentsOf:Bundle.main.url(forResource:"bridge-token",withExtension:"txt") ?? URL(fileURLWithPath:"/nonexistent")))?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
 func request(_ path:String,body:Data?=nil,traceID:String?=nil,completion:@escaping(Result<Data,Error>)->Void){
  var r=URLRequest(url:URL(string:base+path)!);r.timeoutInterval=30;r.setValue(token,forHTTPHeaderField:"X-Studio-Token")
  if let project=ProcessInfo.processInfo.environment["STUDIO_PROJECT_ID"],!project.isEmpty{r.setValue(project,forHTTPHeaderField:"X-Studio-Project")}
  if let traceID=traceID{r.setValue(traceID,forHTTPHeaderField:"X-Studio-Trace-ID")}
  let requestStarted=traceID == nil ? 0:ProcessInfo.processInfo.systemUptime
  if let body=body{r.httpMethod="POST";r.httpBody=body;r.setValue("application/json",forHTTPHeaderField:"Content-Type")}
  URLSession.shared.dataTask(with:r){data,response,error in
   let received=traceID == nil ? 0:ProcessInfo.processInfo.systemUptime
   let result:Result<Data,Error>
   if let error=error{result = .failure(error)}
   else if let data=data,let http=response as? HTTPURLResponse,http.statusCode==200{result = .success(data)}
   else {let message=(data.flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]})?["error"] as? String ?? NSLocalizedString("studio.error.unavailable",comment:"");result = .failure(NSError(domain:"Studio",code:1,userInfo:[NSLocalizedDescriptionKey:message]))}
   DispatchQueue.main.async{
    if let traceID=traceID {let now=ProcessInfo.processInfo.systemUptime;let record:[String:Any] = ["schema":"studio-runtime-trace/1","traceID":traceID,"phase":"http.callback","monotonicMs":now*1000,"requestMs":(received-requestStarted)*1000,"mainQueueMs":(now-received)*1000];if let data=try? JSONSerialization.data(withJSONObject:record,options:.sortedKeys),let line=String(data:data,encoding:.utf8){NSLog("STUDIO_RUNTIME_TRACE %@",line)}}
    completion(result)
   }
  }.resume()
 }
 private let decodedImages=AssetResourcePool<UIImage>(limit:64*1024*1024,maxConcurrent:4)
 private var imageDecodes=0,imageDecodeMilliseconds=0.0,imageIntegrityMilliseconds=0.0,imageIntegrityFailures=0
 func retainImageResources(_ identities:Set<AssetResourceIdentity>){decodedImages.retainIdentities(identities)}
 func releaseImageCache(){decodedImages.releaseStrong()}
 func reportImageDiagnostics(_ phase:String){
  guard ProcessInfo.processInfo.arguments.contains("--studio-performance") else{return}
  var report:[String:Any]=decodedImages.diagnostics;report["phase"]=phase;report["decodes"]=imageDecodes;report["decodeMs"]=imageDecodeMilliseconds;report["integrityMs"]=imageIntegrityMilliseconds;report["integrityFailures"]=imageIntegrityFailures
  if let data=try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys),let text=String(data:data,encoding:.utf8){NSLog("STUDIO_ASSET_PERF %@",text)}
 }
 private func decodeImage(identity:AssetResourceIdentity,maxPixels:Int,expectedSHA256:String?,data:Data?,catalogName:String?=nil,completion:@escaping(UIImage?,Int)->Void){
  let queued=ProcessInfo.processInfo.systemUptime
  AssetImages.queue.addOperation{
   let start=ProcessInfo.processInfo.systemUptime
   let integrityOK:Bool
   if let expected=expectedSHA256,let data=data{integrityOK=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()==expected.lowercased()}else{integrityOK=true}
   let decodeStart=ProcessInfo.processInfo.systemUptime
   let image:UIImage?=autoreleasepool{
    guard integrityOK else{return nil}
    if let catalogName=catalogName{return UIImage(named:catalogName)?.preparingThumbnail(of:CGSize(width:maxPixels,height:maxPixels))}
    return data.flatMap{AssetImages.decode($0,maxPixels:maxPixels)}
   }
   let decoded=ProcessInfo.processInfo.systemUptime,elapsed=(decoded-decodeStart)*1000
   let bytes=image?.cgImage.map{$0.bytesPerRow*$0.height} ?? 0
   DispatchQueue.main.async{
    let delivered=ProcessInfo.processInfo.systemUptime
    self.imageIntegrityMilliseconds+=(decodeStart-start)*1000
    if integrityOK{self.imageDecodes+=1;self.imageDecodeMilliseconds+=elapsed}else{self.imageIntegrityFailures+=1}
    completion(image,bytes)
    if ProcessInfo.processInfo.arguments.contains("--studio-performance") {
     let report:[String:Any]=["asset":identity.asset,"requestedPixels":maxPixels,"decodedBytes":bytes,"queueMs":(start-queued)*1000,"integrityMs":(decodeStart-start)*1000,"decodeMs":elapsed,"mainQueueMs":(delivered-decoded)*1000,"integrityOK":integrityOK]
     if let data=try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys),let line=String(data:data,encoding:.utf8){NSLog("STUDIO_ASSET_DECODE %@",line)}
    }
   }
  }
 }
 func image(_ path:String,identity:AssetResourceIdentity,maxPixels:Int=1024,expectedSHA256:String?=nil,completion:@escaping(UIImage?)->Void){
  decodedImages.request(identity,pixels:maxPixels,produce:{finish in
   self.request(path){result in
    guard case .success(let data)=result else{finish(nil,0);return}
    self.decodeImage(identity:identity,maxPixels:maxPixels,expectedSHA256:expectedSHA256,data:data,completion:finish)
   }
  },completion:completion)
 }
 func bundledImage(_ url:URL,catalogName:String?,identity:AssetResourceIdentity,maxPixels:Int,expectedSHA256:String?,completion:@escaping(UIImage?)->Void){
  decodedImages.request(identity,pixels:maxPixels,produce:{finish in
   if let catalogName=catalogName{self.decodeImage(identity:identity,maxPixels:maxPixels,expectedSHA256:nil,data:nil,catalogName:catalogName,completion:finish);return}
   AssetImages.queue.addOperation{
    let data=try? Data(contentsOf:url)
    DispatchQueue.main.async{guard let data=data else{finish(nil,0);return};self.decodeImage(identity:identity,maxPixels:maxPixels,expectedSHA256:expectedSHA256,data:data,completion:finish)}
   }
  },completion:completion)
 }
 func json(_ path:String,_ body:[String:Any],traceID:String?=nil,completion:@escaping(Result<Data,Error>)->Void){request(path,body:try? JSONSerialization.data(withJSONObject:body),traceID:traceID,completion:completion)}
}
