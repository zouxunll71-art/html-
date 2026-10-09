import UIKit
import ImageIO

/// Parsing and decoding stay off the UI thread. Input and display mailboxes
/// each hold one frame, so a slow consumer cannot build an image backlog.
private final class SimulatorFrameReceiver:NSObject,URLSessionDataDelegate {
 let queue:OperationQueue={let q=OperationQueue();q.name="studio.simulator.receive";q.maxConcurrentOperationCount=1;q.qualityOfService = .userInteractive;return q}()
 private let decodeQueue=DispatchQueue(label:"studio.simulator.decode",qos:.userInteractive)
 private var buffer=Data(),newestJPEG:Data?
 private var decoding=false,invalid=false
 private let lock=NSLock()
 private var newestImage:CGImage?
 var onFailure:(()->Void)?
 func takeImage()->CGImage?{lock.lock();defer{lock.unlock()};let image=newestImage;newestImage=nil;return image}
 func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data){
  guard !invalid else{return};buffer.append(data);var consumed=0
  while buffer.count-consumed>=4 {
   let size=buffer[consumed..<(consumed+4)].reduce(UInt32(0)){($0<<8)|UInt32($1)}
   guard size>0 && size<20_000_000 else{invalid=true;dataTask.cancel();return}
   guard buffer.count-consumed>=4+Int(size) else{break}
   newestJPEG=buffer.subdata(in:(consumed+4)..<(consumed+4+Int(size)));consumed+=4+Int(size)
  }
  if consumed>0{buffer.removeSubrange(0..<consumed)}
  decodeLatest()
 }
 private func decodeLatest(){
  guard !invalid,!decoding,let data=newestJPEG else{return};newestJPEG=nil;decoding=true
  decodeQueue.async{[weak self] in
   let image:CGImage?=autoreleasepool{
    guard let source=CGImageSourceCreateWithData(data as CFData,nil) else{return nil}
    return CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
   }
   guard let self=self else{return}
   self.queue.addOperation{[weak self] in
    guard let self=self else{return};self.decoding=false
    guard !self.invalid else{return}
    if let image=image{self.lock.lock();self.newestImage=image;self.lock.unlock()}
    self.decodeLatest()
   }
  }
 }
 func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){invalid=true;newestJPEG=nil;buffer.removeAll();DispatchQueue.main.async{[weak self] in self?.onFailure?()}}
}

/// Actual simulator frames, presented at display cadence with automatic recovery.
final class IOSFrames:NSObject {
 var endpoint="/ios-stream";weak var imageView:UIImageView?
 private var projectID:String?
 var onLocalSurfacePresented:((UInt64,UInt64,CFTimeInterval)->Void)?
 #if targetEnvironment(macCatalyst)
 private var localSurface:LocalSurfaceSession?
 private var localSurfaceRetry:DispatchWorkItem?
 private var localSurfacePolicy=LocalSurfaceRetryPolicy()
 #endif
 private(set) var frames=0
 private(set) var lastFrameAt=Date.distantPast
 private var session:URLSession?,receiver:SimulatorFrameReceiver?
 private var retry:DispatchWorkItem?,watchdog:Timer?,displayLink:CADisplayLink?
 private var startedAt=Date.distantPast
 var stopped=true
 var isFresh:Bool { !stopped && Date().timeIntervalSince(lastFrameAt)<4 }
 /// Called only after activation confirms this exact project. Every subscription
 /// then keeps that identity instead of consulting a mutable global selection.
 func bindProject(_ id:String){guard projectID != id else{return};projectID=id;if !stopped{start()}}
 func currentImageForProbe()->CGImage? {
  #if targetEnvironment(macCatalyst)
  if let image=localSurface?.snapshot(){return image}
  #endif
  return imageView?.image?.cgImage
 }
 func start(){restart(resetSurfaceBudget:true)}
 private func restart(resetSurfaceBudget:Bool){
  stop();stopped=false;lastFrameAt = .distantPast;startedAt=Date()
  #if targetEnvironment(macCatalyst)
  localSurfacePolicy.activate(projectID:projectID,resetBudget:resetSurfaceBudget)
  #endif
  startEncoded()
  let timer=Timer(timeInterval:2,repeats:true){[weak self]_ in guard let self=self,!self.stopped else{return};if Date().timeIntervalSince(max(self.lastFrameAt,self.startedAt))>6{self.restart(resetSurfaceBudget:false)}}
  RunLoop.main.add(timer,forMode:.common);watchdog=timer
 }
 #if targetEnvironment(macCatalyst)
 private func considerLocalSurface(){
  guard !stopped,localSurface==nil,localSurfaceRetry==nil,endpoint=="/ios-stream",
        ProcessInfo.processInfo.environment["STUDIO_LOCAL_SURFACE"]=="1",
        let projectID,let imageView,let due=localSurfacePolicy.nextAttemptAt else{return}
  let now=ProcessInfo.processInfo.systemUptime
  if due>now {
   let generation=localSurfacePolicy.generation
   let job=DispatchWorkItem{[weak self] in
    guard let self,!self.stopped,self.projectID==projectID,self.localSurfacePolicy.generation==generation else{return}
    self.localSurfaceRetry=nil;self.considerLocalSurface()
   }
   localSurfaceRetry=job;DispatchQueue.main.asyncAfter(deadline:.now()+(due-now),execute:job);return
  }
  guard let ticket=localSurfacePolicy.takeAttempt(now:now) else{return}
  if let direct=LocalSurfaceSession(projectID:projectID,imageView:imageView) {
   localSurface=direct
   direct.onHealthy={[weak self,weak direct] in guard let self,self.localSurface===direct,!self.stopped else{return};self.lastFrameAt=Date()}
   direct.onPresented={[weak self,weak direct] sequence,ticks,presented in
    guard let self,self.localSurface===direct,!self.stopped,self.localSurfacePolicy.isCurrent(ticket) else{return}
    self.frames+=1;self.lastFrameAt=Date();self.stopEncoded();self.onLocalSurfacePresented?(sequence,ticks,presented)
   }
   direct.onFailure={[weak self,weak direct] in
    guard let self,self.localSurface===direct,!self.stopped,self.localSurfacePolicy.isCurrent(ticket) else{return}
    self.localSurface=nil;self.localSurfacePolicy.failed(ticket,now:ProcessInfo.processInfo.systemUptime)
    self.lastFrameAt = .distantPast;self.startEncoded()
   }
   direct.start()
  }else{localSurfacePolicy.failed(ticket,now:now)}
 }
 #endif
 private func startEncoded(){
  guard !stopped,session==nil else{return}
  let source=SimulatorFrameReceiver();receiver=source
  source.onFailure={[weak self,weak source] in
   guard let self=self,!self.stopped,self.receiver===source else{return}
   let job=DispatchWorkItem{[weak self,weak source] in guard let self=self,!self.stopped,self.receiver===source else{return};self.restart(resetSurfaceBudget:false)}
   self.retry?.cancel();self.retry=job;DispatchQueue.main.asyncAfter(deadline:.now()+1,execute:job)
  }
  let c=URLSessionConfiguration.ephemeral;c.timeoutIntervalForRequest=15;c.timeoutIntervalForResource=86400
  session=URLSession(configuration:c,delegate:source,delegateQueue:source.queue)
  var r=URLRequest(url:URL(string:Bridge.shared.base+endpoint)!);r.setValue(Bridge.shared.token,forHTTPHeaderField:"X-Studio-Token");session?.dataTask(with:r).resume()
  let link=CADisplayLink(target:self,selector:#selector(presentLatest));link.preferredFramesPerSecond=60;link.add(to:.main,forMode:.common);displayLink=link
 }
 private func stopEncoded(){retry?.cancel();retry=nil;displayLink?.invalidate();displayLink=nil;receiver=nil;let old=session;session=nil;old?.invalidateAndCancel()}
 func stop(){
  stopped=true;watchdog?.invalidate();watchdog=nil
  #if targetEnvironment(macCatalyst)
  localSurfaceRetry?.cancel();localSurfaceRetry=nil;localSurfacePolicy.stop()
  localSurface?.stop();localSurface=nil
  #endif
  stopEncoded()
 }
 @objc private func presentLatest(){
  guard !stopped,let image=receiver?.takeImage() else{return};frames+=1;lastFrameAt=Date();imageView?.image=UIImage(cgImage:image)
  #if targetEnvironment(macCatalyst)
  localSurfacePolicy.receivedFrame(now:ProcessInfo.processInfo.systemUptime);considerLocalSurface()
  #endif
 }
}
