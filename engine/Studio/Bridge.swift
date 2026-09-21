import UIKit
final class Bridge {
 static let shared=Bridge();let base="http://127.0.0.1:18775"
 let token=(try? String(contentsOf:Bundle.main.url(forResource:"bridge-token",withExtension:"txt")!))?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
 func request(_ path:String,body:Data?=nil,completion:@escaping(Result<Data,Error>)->Void){
  var r=URLRequest(url:URL(string:base+path)!);r.timeoutInterval=30;r.setValue(token,forHTTPHeaderField:"X-Studio-Token")
  if let body=body{r.httpMethod="POST";r.httpBody=body;r.setValue("application/json",forHTTPHeaderField:"Content-Type")}
  URLSession.shared.dataTask(with:r){data,response,error in
   let result:Result<Data,Error>
   if let error=error{result = .failure(error)}
   else if let data=data,let http=response as? HTTPURLResponse,http.statusCode==200{result = .success(data)}
   else {let message=(data.flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]})?["error"] as? String ?? "本机服务未响应";result = .failure(NSError(domain:"Studio",code:1,userInfo:[NSLocalizedDescriptionKey:message]))}
   DispatchQueue.main.async{completion(result)}
  }.resume()
 }
 private var imageWaiters:[String:[(UIImage?)->Void]]=[:]
 private var imageQueue:[(String,String,Int)]=[]
 private var imageActive=0
 func image(_ path:String,maxPixels:Int=1024,completion:@escaping(UIImage?)->Void){
  let key=path+"#"+String(maxPixels)
  if imageWaiters[key] != nil{imageWaiters[key]?.append(completion);return}
  imageWaiters[key]=[completion];imageQueue.append((key,path,maxPixels));pumpImages()
 }
 private func pumpImages(){
  while imageActive<4 && !imageQueue.isEmpty {
   let (key,path,pixels)=imageQueue.removeFirst();imageActive+=1
   let finish:(UIImage?)->Void={image in
    let callbacks=self.imageWaiters.removeValue(forKey:key) ?? [];self.imageActive-=1
    callbacks.forEach{$0(image)};self.pumpImages()
   }
   request(path){result in
    guard case .success(let data)=result else{finish(nil);return}
    AssetImages.queue.addOperation{let image=autoreleasepool{AssetImages.decode(data,maxPixels:pixels)};DispatchQueue.main.async{finish(image)}}
   }
  }
 }
 func json(_ path:String,_ body:[String:Any],completion:@escaping(Result<Data,Error>)->Void){request(path,body:try? JSONSerialization.data(withJSONObject:body),completion:completion)}
}
