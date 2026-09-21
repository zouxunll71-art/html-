import UIKit

/// At most one request and one pending motion; never replay clicks after a failure.
final class SimulatorInput {
 private var projectID:String?;private var session:String?;private var generation=0
 private var connecting=false;private var sending=false;private var events=[[String:Any]]()
 private var scheduled=false;private var wanted=false
 private var retry:DispatchWorkItem?;private var recoveryAttempts=0
 var onFailure:((String)->Void)?;var onReady:((Bool)->Void)?;var onRecovering:(()->Void)?
 var ready:Bool {session != nil && wanted}
 func start(_ project:String){stop();recoveryAttempts=0;wanted=true;projectID=project;connect()}
 func stop(){
  wanted=false;generation+=1;events.removeAll();scheduled=false;retry?.cancel();retry=nil;onReady?(false)
  if let old=session{session=nil;Bridge.shared.json("/ios-input-disconnect",["session":old]){_ in}}
 }
 private func connect(){
  guard wanted,!connecting,let project=projectID else{return};connecting=true;let revision=generation
  Bridge.shared.json("/ios-input-connect",["id":project]){[weak self]result in
   guard let self=self else{return};self.connecting=false
   let value=(try? result.get()).flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
   let key=value?["session"] as? String
   guard revision==self.generation,self.wanted else{
    if let key=key{Bridge.shared.json("/ios-input-disconnect",["session":key]){[weak self]_ in self?.connect()}}else{self.connect()};return
   }
   if let key=key{self.session=key;self.onReady?(true)}
   else{if case .failure(let error)=result{self.recover(error.localizedDescription)}else{self.recover("模拟器输入连接未就绪")}}
  }
 }
 func enqueue(_ event:[String:Any]){
  guard ready else{return}
  if event["kind"] as? String=="move",events.last?["kind"] as? String=="move"{events[events.count-1]=event}else{events.append(event)}
  guard events.count<=64 else{recover("模拟器响应过慢，已松开触点并清理积压");return}
  if event["kind"] as? String != "move"{pump();return}
  guard !scheduled else{return};scheduled=true
  DispatchQueue.main.asyncAfter(deadline:.now()+1.0/60){[weak self] in self?.scheduled=false;self?.pump()}
 }
 private func pump(){
  guard ready,!sending,!events.isEmpty,let project=projectID,let key=session else{return}
  sending=true;let batch=Array(events.prefix(16));events.removeFirst(batch.count);let revision=generation
  Bridge.shared.json("/ios-input",["id":project,"session":key,"events":batch]){[weak self]result in
   guard let self=self else{return};self.sending=false
   if revision==self.generation{if case .failure(let error)=result{self.recover(error.localizedDescription);return};self.recoveryAttempts=0}
   self.pump()
  }
 }
 private func recover(_ message:String){
  guard wanted else{return};generation+=1;events.removeAll();scheduled=false
  if let old=session{session=nil;Bridge.shared.json("/ios-input-disconnect",["session":old]){_ in}}
  onReady?(false);recoveryAttempts+=1
  guard recoveryAttempts<=3 else{stop();onFailure?("自动恢复操作连接未成功："+message);return}
  onRecovering?();let revision=generation
  let job=DispatchWorkItem{[weak self] in guard let self=self,self.wanted,self.generation==revision else{return};self.connect()}
  retry?.cancel();retry=job;DispatchQueue.main.asyncAfter(deadline:.now()+Double(recoveryAttempts)*0.5,execute:job)
 }
}
