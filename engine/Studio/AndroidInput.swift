import Foundation
/// Separate ordered input channel. Keep touch boundaries; coalesce only pending motion.
final class AndroidInput {
 static let shared=AndroidInput()
 struct Event {var body:[String:Any];var completion:(Result<Data,Error>)->Void}
 private var pending:[Event]=[];private var busy=false
 private let session:URLSession = {let c=URLSessionConfiguration.ephemeral;c.httpMaximumConnectionsPerHost=1;c.timeoutIntervalForRequest=3;return URLSession(configuration:c)}()
 func send(_ body:[String:Any],completion:@escaping(Result<Data,Error>)->Void){
  let event=Event(body:body,completion:completion)
  if body["kind"] as? String == "move",pending.last?.body["kind"] as? String == "move"{pending[pending.count-1]=event}else{pending.append(event)}
  drain()
 }
 private func drain(){guard !busy,!pending.isEmpty else{return};busy=true;let event=pending.removeFirst()
  var request=URLRequest(url:URL(string:Bridge.shared.base+"/input")!);request.httpMethod="POST";request.httpBody=try? JSONSerialization.data(withJSONObject:event.body);request.setValue(Bridge.shared.token,forHTTPHeaderField:"X-Studio-Token");request.setValue("application/json",forHTTPHeaderField:"Content-Type")
  session.dataTask(with:request){[weak self] data,response,error in
   let result:Result<Data,Error>
   if let error=error{result = .failure(error)}else if (response as? HTTPURLResponse)?.statusCode==200,let data=data{result = .success(data)}else{result = .failure(NSError(domain:"StudioInput",code:1,userInfo:[NSLocalizedDescriptionKey:"安卓模拟器触控连接中断，请重新启动工作台"]))}
   DispatchQueue.main.async{guard let self=self else{return};self.busy=false;event.completion(result);self.drain()}
  }.resume()
 }
}
