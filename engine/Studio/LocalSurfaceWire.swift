#if targetEnvironment(macCatalyst)
import Foundation
import Darwin
import IOSurface

/// A private bootstrap receive right for one authenticated project subscription.
/// The actual surface travels as a Mach right; numeric global IOSurface lookup
/// is never used. Kernel trailer identity is checked before surface import.
final class LocalSurfaceWire {
 let session=UUID()
 var service:String {"local.studio.surface."+session.uuidString.lowercased()}
 private var port:mach_port_t=0
 private let stateLock=NSLock()
 private var stopped=false,receiving=false
 private let queue=DispatchQueue(label:"studio.surface.receive",qos:.userInteractive)
 var onFrame:((LocalSurfaceFrame)->Void)?
 var onHeartbeat:(()->Void)?
 var onFailure:(()->Void)?
 init?() {
  guard mach_port_allocate(mach_task_self_,MACH_PORT_RIGHT_RECEIVE,&port)==KERN_SUCCESS else{return nil}
  var limits=mach_port_limits_t(mpl_qlimit:2)
  _=withUnsafeMutablePointer(to:&limits){p in p.withMemoryRebound(to:integer_t.self,capacity:1){mach_port_set_attributes(mach_task_self_,port,MACH_PORT_LIMITS_INFO,$0,StudioSurfaceLimitsCount())}}
  guard mach_port_insert_right(mach_task_self_,port,port,mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND))==KERN_SUCCESS,
        service.withCString({StudioSurfaceRegister($0,port)})==KERN_SUCCESS else {
   mach_port_mod_refs(mach_task_self_,port,MACH_PORT_RIGHT_RECEIVE,-1);mach_port_deallocate(mach_task_self_,port);port=0;return nil
  }
 }
 func authorize(pid:pid_t,device:UUID) {
  stateLock.lock();guard !stopped,!receiving,pid>0 else{stateLock.unlock();return}
  receiving=true;stateLock.unlock()
  queue.async{[self] in receive(pid:pid,device:device);dispose()}
 }
 func stop() {
  stateLock.lock();let wasStopped=stopped;stopped=true;let isReceiving=receiving;stateLock.unlock()
  if !wasStopped && !isReceiving {queue.async{[self] in dispose()}}
 }
 private var isStopped:Bool {stateLock.lock();defer{stateLock.unlock()};return stopped}
 private func dispose(){
  if port != 0 {service.withCString{_ = StudioSurfaceRegister($0,0)};mach_port_mod_refs(mach_task_self_,port,MACH_PORT_RIGHT_RECEIVE,-1);mach_port_deallocate(mach_task_self_,port);port=0}
 }
 private func receive(pid:pid_t,device:UUID) {
  let raw=UnsafeMutableRawPointer.allocate(byteCount:512,alignment:16);defer{raw.deallocate()}
  var lastSequence:UInt64=0,lastMessage=ProcessInfo.processInfo.systemUptime
  while !isStopped {
   raw.initializeMemory(as:UInt8.self,repeating:0,count:512)
   let header=raw.assumingMemoryBound(to:mach_msg_header_t.self)
   let result=mach_msg(header,StudioSurfaceReceiveOptions(),0,512,port,250,0)
   if result==MACH_RCV_TIMED_OUT {
    if ProcessInfo.processInfo.systemUptime-lastMessage>4 {break}
    continue
   }
   guard result==KERN_SUCCESS else{break}
   defer{mach_msg_destroy(header)}
   guard !isStopped,header.pointee.msgh_size==144,
         header.pointee.msgh_id==0x5353,
         header.pointee.msgh_bits & UInt32(MACH_MSGH_BITS_COMPLEX) != 0 else{continue}
   let trailer=raw.advanced(by:144).assumingMemoryBound(to:mach_msg_audit_trailer_t.self).pointee
   guard trailer.msgh_trailer_type==MACH_MSG_TRAILER_FORMAT_0,
         trailer.msgh_trailer_size>=MemoryLayout<mach_msg_audit_trailer_t>.size else{continue}
   // Darwin's audit ABI fields: euid=1, pid=5. libbsm wrappers are unavailable
   // to Catalyst; an ABI mismatch fails closed instead of bypassing identity.
   guard trailer.msgh_audit.val.5==UInt32(pid),trailer.msgh_audit.val.1==geteuid() else{continue}
   func u32(_ offset:Int)->UInt32 {raw.load(fromByteOffset:offset,as:UInt32.self)}
   func u64(_ offset:Int)->UInt64 {raw.load(fromByteOffset:offset,as:UInt64.self)}
   guard u32(24)==1,u32(40)==0x53555246,u32(44)==1 else{continue}
   let descriptor=raw.advanced(by:28).assumingMemoryBound(to:mach_msg_port_descriptor_t.self).pointee
   guard descriptor.type==MACH_MSG_PORT_DESCRIPTOR else{continue}
   let messageSession=NSUUID(uuidBytes:raw.advanced(by:48).assumingMemoryBound(to:UInt8.self)) as UUID
   let messageDevice=NSUUID(uuidBytes:raw.advanced(by:64).assumingMemoryBound(to:UInt8.self)) as UUID
   let sequence=u64(80),width=u32(116),height=u32(120),stride=u32(124),format=u32(128),orientation=u32(132),flags=u32(136)
   guard messageSession==session,messageDevice==device,sequence>lastSequence,
         width>0,height>0,width<=16384,height<=16384,stride>=width*4,
         u64(104)<=256*1024*1024,UInt64(stride)*UInt64(height)<=u64(104),
         format==0x42475241,[1,3,6,8].contains(orientation),flags<=2,
         let surface=IOSurfaceLookupFromMachPort(descriptor.name),
         IOSurfaceGetPlaneCount(surface)==0,IOSurfaceGetWidth(surface)==width,
         IOSurfaceGetHeight(surface)==height,IOSurfaceGetBytesPerRow(surface)==stride,
         IOSurfaceGetPixelFormat(surface)==format,IOSurfaceGetID(surface)==u32(112),
         IOSurfaceGetAllocSize(surface)==u64(104) else{continue}
   lastSequence=sequence;lastMessage=ProcessInfo.processInfo.systemUptime
   if flags==1 {onHeartbeat?();continue}
   let object=unsafeBitCast(surface,to:IOSurface.self)
   let frame=LocalSurfaceFrame(surface:object,session:session,device:device,sequence:sequence,
                              sourceFrameTicks:u64(96),orientation:Int32(orientation))
   onFrame?(frame)
  }
  if !isStopped {DispatchQueue.main.async{[weak self] in guard let self,!self.isStopped else{return};self.onFailure?()}}
 }
 deinit {assert(port==0,"Surface receive right must be stopped before release")}
}
#endif
