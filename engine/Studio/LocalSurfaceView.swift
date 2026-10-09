#if targetEnvironment(macCatalyst)
import UIKit
import Metal
import CoreImage
import IOSurface

/// Surface ownership lasts through the final GPU read, independent of Mach rights.
final class LocalSurfaceFrame {
 let surface:IOSurface
 let session:UUID,device:UUID
 let sequence:UInt64,sourceFrameTicks:UInt64
 let orientation:Int32
 let sourceColorSpace:CGColorSpace?
 init(surface:IOSurface,session:UUID,device:UUID,sequence:UInt64,sourceFrameTicks:UInt64,
      orientation:Int32,sourceColorSpace:CGColorSpace?=nil){
  self.surface=surface;self.session=session;self.device=device;self.sequence=sequence
  self.sourceFrameTicks=sourceFrameTicks;self.orientation=orientation;self.sourceColorSpace=sourceColorSpace
  surface.incrementUseCount()
 }
 deinit{surface.decrementUseCount()}
}

/// Latest-only surface presentation. Drawable acquisition and Core Image encoding
/// run on a private queue: a busy WindowServer never blocks the workbench UI.
/// The required GPU scale/color pass remains; no encoded images or CPU pixel copies.
final class LocalSurfaceView:UIView {
 override class var layerClass:AnyClass {CAMetalLayer.self}
 private var metalLayer:CAMetalLayer!
 private let lock=NSLock()
 private var pending:LocalSurfaceFrame?,lastPresented:LocalSurfaceFrame?
 private var presentation:(frame:LocalSurfaceFrame,time:CFTimeInterval,generation:UInt64)?
 private var renderScheduled=false,presentationScheduled=false
 private var activeSession:UUID?,activeDevice:UUID?
 private var lastAcceptedSequence:UInt64=0,generation:UInt64=0
 private var usableSize=false
 private var gpuInFlight=0
 private let rendering=DispatchQueue(label:"studio.surface.render",qos:.userInteractive)
 private let commands:MTLCommandQueue
 private let context:CIContext
 // Same destination as the existing encoder. Framebuffer input keeps its own tag.
 private let colorSpace=CGColorSpaceCreateDeviceRGB()
 var onPresented:((UInt64,UInt64,CFTimeInterval)->Void)?
 var onFailure:((String)->Void)?
 init?(surfacePreview:Bool){
  guard let gpu=MTLCreateSystemDefaultDevice(),let q=gpu.makeCommandQueue() else{return nil}
  commands=q;context=CIContext(mtlDevice:gpu,options:[.cacheIntermediates:true])
  super.init(frame:.zero);metalLayer=layer as? CAMetalLayer
  isUserInteractionEnabled=false;isOpaque=false;backgroundColor = .clear
  metalLayer.device=gpu;metalLayer.pixelFormat = .bgra8Unorm;metalLayer.framebufferOnly=false
  metalLayer.colorspace=colorSpace;metalLayer.maximumDrawableCount=2
  metalLayer.allowsNextDrawableTimeout=true;metalLayer.presentsWithTransaction=false
 }
 required init?(coder:NSCoder){fatalError("Use init(surfacePreview:)")}
 override func layoutSubviews(){
  super.layoutSubviews()
  let scale=window?.screen.scale ?? traitCollection.displayScale
  let size=CGSize(width:max(1,(bounds.width*scale).rounded()),height:max(1,(bounds.height*scale).rounded()))
  let resized=metalLayer.drawableSize != size;metalLayer.contentsScale=scale;metalLayer.drawableSize=size
  lock.lock();usableSize=bounds.width>0&&bounds.height>0
  if resized&&pending==nil{pending=lastPresented};lock.unlock();scheduleRender()
 }
 func start(session:UUID,device:UUID){
  precondition(Thread.isMainThread)
  lock.lock();generation &+= 1;activeSession=session;activeDevice=device;lastAcceptedSequence=0
  pending=nil;lastPresented=nil;presentation=nil;lock.unlock();setNeedsLayout()
 }
 func stop(){
  precondition(Thread.isMainThread)
  lock.lock();generation &+= 1;activeSession=nil;activeDevice=nil
  pending=nil;lastPresented=nil;presentation=nil;lock.unlock()
 }
 func enqueue(_ frame:LocalSurfaceFrame){
  lock.lock()
  guard frame.session==activeSession,frame.device==activeDevice,frame.sequence>lastAcceptedSequence,
        [1,3,6,8].contains(frame.orientation) else{lock.unlock();return}
  lastAcceptedSequence=frame.sequence;pending=frame;lock.unlock();scheduleRender()
 }
 private func scheduleRender(){
  lock.lock();let schedule = !renderScheduled&&gpuInFlight<2&&pending != nil&&usableSize&&activeSession != nil
  if schedule{renderScheduled=true};lock.unlock()
  if schedule{rendering.async{[weak self] in self?.renderLatest()}}
 }
 private func renderLatest(){
  // At most two GPU submissions, and at most one queued render. No UI-thread wait.
  lock.lock()
  guard gpuInFlight<2 else{renderScheduled=false;lock.unlock();return}
  gpuInFlight+=1
  let requestedGeneration=generation,live=activeSession != nil&&pending != nil;lock.unlock()
  guard live else{finishRenderWithoutSubmission();return}
  // nextDrawable can block during compositor pressure; this private queue owns it.
  guard let drawable=metalLayer.nextDrawable() else{
   finishRenderWithoutSubmission()
   rendering.asyncAfter(deadline:.now()+1.0/60.0){[weak self] in self?.scheduleRender()};return
  }
  lock.lock();let frame=pending
  let valid=generation==requestedGeneration&&activeSession != nil
  if valid{pending=nil};lock.unlock()
  guard valid,let frame,let command=commands.makeCommandBuffer() else{finishRenderWithoutSubmission();return}
  let size=CGSize(width:drawable.texture.width,height:drawable.texture.height)
  let options:[CIImageOption:Any]?=frame.sourceColorSpace.map{[.colorSpace:$0]}
  var image=CIImage(ioSurface:unsafeBitCast(frame.surface,to:IOSurfaceRef.self),options:options).oriented(forExifOrientation:frame.orientation)
  let extent=image.extent,scale=min(size.width/image.extent.width,size.height/image.extent.height)
  image=image.transformed(by:CGAffineTransform(translationX:-extent.minX,y:-extent.minY))
  image=image.transformed(by:CGAffineTransform(scaleX:scale,y:scale),highQualityDownsample:true)
  image=image.transformed(by:CGAffineTransform(translationX:(size.width-extent.width*scale)/2,y:(size.height-extent.height*scale)/2))
  let rect=CGRect(origin:.zero,size:size)
  image=image.composited(over:CIImage(color:.black).cropped(to:rect))
  // UIKit/Catalyst supplies the layer's presentation coordinate system. Keep
  // the source orientation: a second Y flip here inverted the real workbench.
  // Raw texture-vs-bitmap byte order is not an onscreen orientation oracle.
  context.render(image,to:drawable.texture,commandBuffer:command,bounds:rect,colorSpace:colorSpace)
  drawable.addPresentedHandler{[weak self,frame] shown in
   if shown.presentedTime>0{self?.offerPresentation(frame,time:shown.presentedTime,generation:requestedGeneration)}
  }
  command.addCompletedHandler{[weak self,frame] completed in
   _=frame // Keep IOSurface use count live through GPU completion.
   guard let self else{return};self.lock.lock();self.gpuInFlight-=1;self.lock.unlock()
   if completed.status == .error {
    DispatchQueue.main.async{[weak self] in
     guard let self else{return};self.lock.lock();let valid=self.generation==requestedGeneration&&self.activeSession != nil;self.lock.unlock()
     if valid{self.onFailure?(completed.error?.localizedDescription ?? "Metal render failed")}
    }
   }
   self.scheduleRender()
  }
  command.present(drawable);command.commit()
  lock.lock();renderScheduled=false;lock.unlock();scheduleRender()
 }
 private func finishRenderWithoutSubmission(){lock.lock();gpuInFlight-=1;renderScheduled=false;lock.unlock()}
 private func offerPresentation(_ frame:LocalSurfaceFrame,time:CFTimeInterval,generation value:UInt64){
  lock.lock();guard generation==value&&activeSession != nil else{lock.unlock();return}
  if (presentation?.frame.sequence ?? 0)<=frame.sequence {presentation=(frame,time,value)}
  let schedule = !presentationScheduled;presentationScheduled=true;lock.unlock()
  if schedule{DispatchQueue.main.async{[weak self] in self?.drainPresentation()}}
 }
 private func drainPresentation(){
  lock.lock();let value=presentation;presentation=nil;presentationScheduled=false
  let valid=value != nil&&value?.generation==generation&&activeSession != nil
  if valid{lastPresented=value?.frame};lock.unlock()
  if valid,let value{onPresented?(value.frame.sequence,value.frame.sourceFrameTicks,value.time)}
 }
 /// Explicit QA/failure snapshots only; normal presentation never reads pixels.
 func snapshot()->CGImage?{
  precondition(Thread.isMainThread)
  lock.lock();let frame=lastPresented;lock.unlock();guard let frame else{return nil}
  let options:[CIImageOption:Any]?=frame.sourceColorSpace.map{[.colorSpace:$0]}
  let image=CIImage(ioSurface:unsafeBitCast(frame.surface,to:IOSurfaceRef.self),options:options).oriented(forExifOrientation:frame.orientation)
  return context.createCGImage(image,from:image.extent,format:.RGBA8,colorSpace:colorSpace)
 }
}
#endif
