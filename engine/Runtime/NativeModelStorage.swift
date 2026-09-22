import UIKit
import CryptoKit

extension NativeRuntimeController {
 func setupModels(){for target in [scene,modalScene]{
  target.modelLoader={[weak self] id,completion in guard let self=self else{return};self.loadModel(id,completion:completion)}
  target.paintStore={[weak self] key,value,completion in guard let self=self else{return};self.exchangePainting(key,value,completion:completion)}
 }}
 func loadModel(_ id:String,completion:@escaping(Result<Data,Error>)->Void){
  if !standalone {let project=payload["projectID"] as? String ?? "";Bridge.shared.request("/asset?project=\(project)&id=\(id.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? "")",completion:completion);return}
  guard let assets=(payload["model"] as? [String:Any])?["assets"] as? [[String:Any]],let asset=assets.first(where:{$0["id"] as? String==id && $0["kind"] as? String=="model"}),let file=asset["file"] as? String,let url=Bundle.main.url(forResource:file,withExtension:nil,subdirectory:"assets") ?? Bundle.main.url(forResource:file,withExtension:nil) else{completion(.failure(NativeGLBError.invalid("Model resource missing")));return}
  DispatchQueue.global(qos:.userInitiated).async {let result=Result{try Data(contentsOf:url)};DispatchQueue.main.async{completion(result)}}
 }
 func exchangePainting(_ key:String,_ value:[String:Any]?,completion:@escaping(Result<[String:Any]?,Error>)->Void){
  if !standalone {let project=key.components(separatedBy:":").first ?? "";var event:[String:Any]=["type":"modelPaintStorage","method":value==nil ? "GET":"POST","key":key];if let value=value{event["value"]=value}else if let prior=paintingRecords[key]?["revision"]{event["knownRevision"]=prior}
   Bridge.shared.json("/event",["projectID":project,"side":"ios","event":event]){result in do{let data=try result.get(),record=try JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed);if let value=record as? [String:Any],value["unchanged"] as? Bool != true,value["png"] != nil{self.paintingRecords[key]=value};completion(.success((record as? [String:Any])?["unchanged"] as? Bool == true ? self.paintingRecords[key] : record as? [String:Any]))}catch{completion(.failure(error))}};return
  }
  DispatchQueue.global(qos:.utility).async {
   let result:Result<[String:Any]?,Error>=Result {
    let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ModelPaintings",isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let hash=SHA256.hash(data:Data(key.utf8)).map{String(format:"%02x",$0)}.joined(),url=folder.appendingPathComponent(hash+".json")
    if let value=value {guard let png=value["png"] as? String,png.count<=8_000_000,let data=Data(base64Encoded:png),let image=UIImage(data:data)?.cgImage,image.width==1024,image.height==1024 else{throw NativeGLBError.invalid("Invalid painting texture")};try JSONSerialization.data(withJSONObject:value).write(to:url,options:.atomic);return ["ok":true]}
    if !FileManager.default.fileExists(atPath:url.path){return nil};return try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]
   };DispatchQueue.main.async{completion(result)}
  }
 }
}
