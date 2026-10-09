#if targetEnvironment(macCatalyst)
import UIKit

/// Opt-in local transport. The authenticated HTTP control plane owns the helper;
/// failed authorization, format, watchdog, or Metal presentation falls back to JPEG.
final class LocalSurfaceSession {
 let projectID:String
 let view:LocalSurfaceView
 private let wire:LocalSurfaceWire
 private weak var imageView:UIImageView?
 private var active=true,authorized=false,pingBusy=false,hasPresented=false
 private var timer:Timer?
 private let mailboxLock=NSLock()
 private var mailboxFrame:LocalSurfaceFrame?,mailboxHeartbeat=false,mailboxScheduled=false,mailboxClosed=false
 private var startedAt=ProcessInfo.processInfo.systemUptime,lastReceive=ProcessInfo.processInfo.systemUptime
 private var lastPresented=ProcessInfo.processInfo.systemUptime,waitingSince:TimeInterval?
 var onPresented:((UInt64,UInt64,CFTimeInterval)->Void)?
 var onHealthy:(()->Void)?
 var onFailure:(()->Void)?
 init?(projectID:String,imageView:UIImageView) {
  guard !projectID.isEmpty,let renderer=LocalSurfaceView(surfacePreview:true),let receiver=LocalSurfaceWire() else{return nil}
  self.projectID=projectID;self.imageView=imageView;wire=receiver;view=renderer
  view.frame=imageView.bounds;view.autoresizingMask=[.flexibleWidth,.flexibleHeight]
 }
 private var control:[String:Any]{["projectID":projectID,"session":wire.session.uuidString.lowercased()]}
 func start() {
  precondition(Thread.isMainThread)
  let session=wire.session,body=control.merging(["service":wire.service]){_,new in new}
  wire.onFailure={[weak self] in self?.fail()}
  wire.onHeartbeat={[weak self] in self?.offer(nil)}
  wire.onFrame={[weak self] frame in self?.offer(frame)}
  view.onFailure={[weak self]_ in self?.fail()}
  view.onPresented={[weak self] sequence,ticks,presented in
   guard let self,self.active else{return};self.hasPresented=true;self.waitingSince=nil
   self.lastPresented=ProcessInfo.processInfo.systemUptime;self.onHealthy?();self.onPresented?(sequence,ticks,presented)
  }
  Bridge.shared.json("/local-surface/start",body){[weak self] result in
   guard let self,self.active else{Bridge.shared.json("/local-surface/stop",["projectID":body["projectID"]!,"session":body["session"]!]){_ in};return}
   guard case .success(let data)=result,
         let response=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
         response["session"] as? String==session.uuidString.lowercased(),
         response["projectID"] as? String==self.projectID,
         let deviceString=response["deviceUDID"] as? String,let device=UUID(uuidString:deviceString),
         let pid=response["pid"] as? Int,pid>0,pid<=Int(Int32.max) else{self.fail();return}
   self.authorized=true;self.view.start(session:session,device:device)
   self.imageView?.addSubview(self.view);self.wire.authorize(pid:pid_t(pid),device:device)
  }
  let timer=Timer(timeInterval:1,repeats:true){[weak self]_ in self?.tick()};self.timer=timer;RunLoop.main.add(timer,forMode:.common)
 }
 /// Coalesce before dispatching to main. A busy UI thread must never accumulate
 /// one retained surface/closure per producer frame.
 private func offer(_ frame:LocalSurfaceFrame?) {
  mailboxLock.lock();guard !mailboxClosed else{mailboxLock.unlock();return}
  if let frame{mailboxFrame=frame}else{mailboxHeartbeat=true}
  let schedule = !mailboxScheduled;mailboxScheduled=true;mailboxLock.unlock()
  if schedule {DispatchQueue.main.async{[weak self] in self?.drain()}}
 }
 private func drain(){
  mailboxLock.lock();let frame=mailboxFrame,heartbeat=mailboxHeartbeat
  mailboxFrame=nil;mailboxHeartbeat=false;mailboxScheduled=false;mailboxLock.unlock()
  guard active,authorized else{return}
  if heartbeat||frame != nil{lastReceive=ProcessInfo.processInfo.systemUptime}
  if heartbeat&&hasPresented{onHealthy?()}
  if let frame,frame.session==wire.session {
   // Existing pointer normalization assumes the phone viewport's aspect ratio.
   // A mismatched screen must use the established fallback until layout catches up.
   let source=CGFloat(frame.surface.width)/CGFloat(frame.surface.height)
   let target=view.bounds.width/max(1,view.bounds.height)
   guard target>0,abs(source-target)<0.025 else{fail();return}
   if waitingSince==nil{waitingSince=ProcessInfo.processInfo.systemUptime}
   view.enqueue(frame)
  }
 }
 private func tick() {
  guard active else{return};let now=ProcessInfo.processInfo.systemUptime
  if (!hasPresented&&now-startedAt>4)||(authorized&&now-lastReceive>4)||(waitingSince.map{now-$0>3} ?? false){fail();return}
  guard authorized,!pingBusy else{return};pingBusy=true
  Bridge.shared.json("/local-surface/ping",control){[weak self] result in
   guard let self,self.active else{return};self.pingBusy=false
   if case .failure = result {self.fail()}
  }
 }
 private func fail(){
  guard active else{return}
  // Preserve the last actual source frame during the rare transport fallback.
  // This readback is not part of ordinary presentation or its performance path.
  if hasPresented,let image=view.snapshot(){imageView?.image=UIImage(cgImage:image)}
  let callback=onFailure;stop();callback?()
 }
 func snapshot()->CGImage? {view.snapshot()}
 func stop() {
  precondition(Thread.isMainThread)
  guard active else{return};active=false;timer?.invalidate();timer=nil
  mailboxLock.lock();mailboxClosed=true;mailboxFrame=nil;mailboxHeartbeat=false;mailboxLock.unlock()
  wire.stop()
  view.stop();view.removeFromSuperview();Bridge.shared.json("/local-surface/stop",control){_ in}
 }
 deinit {assert(!active,"Local surface session must be stopped before release")}
}
#endif
