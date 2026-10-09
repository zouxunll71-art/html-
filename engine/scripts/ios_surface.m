#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <CoreGraphics/CGGeometry.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <servers/bootstrap.h>
#import <mach/mach_time.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <limits.h>
#import <stdatomic.h>
#import "ios_surface_wire.h"

static volatile sig_atomic_t terminated=0;
static _Atomic int stopCause=0;
static NSString *stopReason(int cause){switch(cause){case 10:return @"sigterm";case 11:return @"sigint";case 20:return @"unsupported-surface-format";case 21:return @"surface-port-creation-failed";case 22:return @"mach-send-failed";case 23:return @"callback-registration-failed";case 30:return @"parent-stdin-eof";case 31:return @"parent-changed";default:return @"loop-ended";}}
static void stopSignal(int s){atomic_store(&stopCause,s==SIGTERM?10:11);terminated=1;}
static void qaRecord(NSString *event,NSDictionary *fields);
static id readObject(id o,NSString *key){@try{return ((id(*)(id,SEL))objc_msgSend)(o,NSSelectorFromString(key));}@catch(NSException *e){qaRecord(@"getter-exception",@{@"selector":key});return nil;}}
static BOOL isSurface(id value){return value&&CFGetTypeID((__bridge CFTypeRef)value)==IOSurfaceGetTypeID();}
static double seconds(uint64_t ticks){static mach_timebase_info_data_t t;if(!t.denom)mach_timebase_info(&t);return ticks*(double)t.numer/t.denom/1e9;}

// QA metadata only. Dedicated inherited FD: never redirect private-framework stderr.
// Callback threads enqueue at most 128 small records; disk I/O stays on a utility queue.
static int qaFD=-1;
static NSLock *qaLock;
static NSMutableArray *qaEvents;
static dispatch_source_t qaWake;
static dispatch_queue_t qaQueue;
static BOOL qaClosed=NO;
static NSUInteger qaBytes=0,qaDropped=0;
static const NSUInteger qaLimit=4*1024*1024;
static BOOL qaEnabled(void){return qaWake!=nil;}
static void qaDrain(void){@autoreleasepool{
 [qaLock lock];NSArray *events=qaEvents;qaEvents=[NSMutableArray new];NSUInteger dropped=qaDropped;qaDropped=0;[qaLock unlock];
 for(NSDictionary *event in events){
  if(qaFD<0)break;NSMutableDictionary *line=[event mutableCopy];if(dropped){line[@"droppedRecords"]=@(dropped);dropped=0;}
  NSData *data=[NSJSONSerialization dataWithJSONObject:line options:0 error:nil];if(!data)continue;
  const char end[]="{\"event\":\"log-limit\",\"limitBytes\":4194304}\n";if(qaBytes+data.length+1+sizeof(end)-1>qaLimit){write(qaFD,end,sizeof(end)-1);close(qaFD);qaFD=-1;[qaLock lock];qaClosed=YES;[qaLock unlock];break;}
  NSMutableData *record=[data mutableCopy];[record appendBytes:"\n" length:1];ssize_t n=write(qaFD,record.bytes,record.length);
  if(n!=(ssize_t)record.length){close(qaFD);qaFD=-1;[qaLock lock];qaClosed=YES;[qaLock unlock];break;}qaBytes+=record.length;
 }
}}
static void qaRecord(NSString *event,NSDictionary *fields){
 if(!qaEnabled())return;NSMutableDictionary *record=[fields mutableCopy];record[@"event"]=event;record[@"machTicks"]=@(mach_absolute_time());record[@"unixMs"]=@((uint64_t)(NSDate.date.timeIntervalSince1970*1000));
 [qaLock lock];if(qaClosed){[qaLock unlock];return;}if(qaEvents.count<128)[qaEvents addObject:record];else qaDropped++;[qaLock unlock];dispatch_source_merge_data(qaWake,1);
}
static void qaStart(void){
 const char *value=getenv("STUDIO_SURFACE_QA_FD");if(!value||!*value)return;char *end=NULL;long fd=strtol(value,&end,10);struct stat st;
 if(*end||fd<3||fd>INT_MAX||fstat((int)fd,&st)||!S_ISREG(st.st_mode)||st.st_uid!=getuid()||(st.st_mode&077)!=0)return;
 qaFD=(int)fd;qaLock=[NSLock new];qaEvents=[NSMutableArray new];qaQueue=dispatch_queue_create("studio.surface.qa-log",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));
 qaWake=dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD,0,0,qaQueue);dispatch_source_set_event_handler(qaWake,^{qaDrain();});dispatch_resume(qaWake);
}
static void qaFinish(void){if(!qaEnabled())return;[qaLock lock];qaClosed=YES;[qaLock unlock];dispatch_source_cancel(qaWake);dispatch_sync(qaQueue,^{qaDrain();if(qaFD>=0){close(qaFD);qaFD=-1;}});}
static NSDictionary *qaSurface(id value){
 if(!value)return @{@"kind":@"nil"};if(!isSurface(value))return @{@"kind":@"invalid-type"};IOSurfaceRef s=(__bridge IOSurfaceRef)value;
 return @{@"kind":@"surface",@"id":@(IOSurfaceGetID(s)),@"width":@(IOSurfaceGetWidth(s)),@"height":@(IOSurfaceGetHeight(s)),@"format":@(IOSurfaceGetPixelFormat(s))};
}
// Remote proxies may claim selectors that the remote object does not implement.
// Only object-returning selectors and the known unsigned-short displayClass ABI are read.
static id qaObject(id target,NSString *key,NSString **status){
 if(!target){*status=@"no-object";return nil;}@try{SEL selector=NSSelectorFromString(key);NSMethodSignature *sig=[target methodSignatureForSelector:selector];if(!sig||sig.methodReturnType[0]!='@'){*status=@"signature-unavailable";return nil;}id result=((id(*)(id,SEL))objc_msgSend)(target,selector);*status=result?@"value":@"nil";return result;}@catch(NSException *e){*status=@"exception";return nil;}
}
static NSDictionary *qaDisplay(id descriptor){
 NSMutableDictionary *result=[NSMutableDictionary new];
 @try{SEL selector=NSSelectorFromString(@"displaySize");NSMethodSignature *sig=[descriptor methodSignatureForSelector:selector];if(sig&&strcmp(sig.methodReturnType,@encode(CGSize))==0&&sig.methodReturnLength==sizeof(CGSize)){NSInvocation *call=[NSInvocation invocationWithMethodSignature:sig];call.target=descriptor;call.selector=selector;[call invoke];CGSize size={0};[call getReturnValue:&size];if(isfinite(size.width)&&isfinite(size.height)){result[@"displaySize"]=@{@"width":@(size.width),@"height":@(size.height)};result[@"displaySizeStatus"]=@"value";}else result[@"displaySizeStatus"]=@"nonfinite";}else result[@"displaySizeStatus"]=@"signature-unavailable";}@catch(NSException *e){result[@"displaySizeStatus"]=@"exception";}
 NSString *status=nil;id state=qaObject(descriptor,@"state",&status);result[@"stateStatus"]=status;
 if(state)@try{SEL selector=NSSelectorFromString(@"displayClass");NSMethodSignature *sig=[state methodSignatureForSelector:selector];if(sig&&strcmp(sig.methodReturnType,@encode(unsigned short))==0){result[@"displayClass"]=@(((unsigned short(*)(id,SEL))objc_msgSend)(state,selector));result[@"displayClassStatus"]=@"value";}else result[@"displayClassStatus"]=@"signature-unavailable";}@catch(NSException *e){result[@"displayClassStatus"]=@"exception";}
 id properties=qaObject(descriptor,@"screenProperties",&status);result[@"screenPropertiesStatus"]=status;
 if(properties){@try{SEL selector=NSSelectorFromString(@"screenID");NSMethodSignature *sig=[properties methodSignatureForSelector:selector];if(sig&&strcmp(sig.methodReturnType,@encode(unsigned int))==0){result[@"screenID"]=@(((unsigned int(*)(id,SEL))objc_msgSend)(properties,selector));result[@"screenIDStatus"]=@"value";}else result[@"screenIDStatus"]=@"signature-unavailable";}@catch(NSException *e){result[@"screenIDStatus"]=@"exception";}id unique=qaObject(properties,@"uniqueId",&status);result[@"uniqueIdStatus"]=status;if([unique isKindOfClass:NSString.class]&&[unique length]<=128)result[@"uniqueId"]=unique;else if(unique)result[@"uniqueIdStatus"]=@"unsupported-value-type";}
 return result;
}

@interface SurfaceRelay:NSObject
@property(nonatomic,strong) NSLock *lock;
@property(nonatomic,strong) id surface;
@property(nonatomic) uint64_t frameTicks,sequence;
@property(nonatomic) uint32_t flags;
@property(nonatomic) BOOL pending,closed;
@property(nonatomic) uint64_t frameCallbacks,surfaceChanges,nilChanges,heartbeats,sends,sendTimeouts,lastFrameCallbackTicks,lastSurfaceChangeTicks,lastSendTicks;
@property(nonatomic) mach_port_t recipient;
@property(nonatomic,strong) NSUUID *session;
@property(nonatomic,strong) NSUUID *device;
@property(nonatomic,strong) dispatch_source_t signal;
- (void)changed:(id)surface;
- (void)frame;
- (void)heartbeat;
- (void)sendLatest;
- (void)diagnosticSummary;
@end
@implementation SurfaceRelay
- (instancetype)init{if((self=[super init])){_lock=[NSLock new];}return self;}
- (void)changed:(id)value{[_lock lock];BOOL accepted=!_closed;if(accepted){_surface=isSurface(value)?value:nil;_frameTicks=mach_absolute_time();_flags=StudioSurfaceChanged;_pending=YES;if(qaEnabled()){_surfaceChanges++;if(!_surface)_nilChanges++;_lastSurfaceChangeTicks=_frameTicks;}}uint64_t seq=_sequence;[_lock unlock];if(accepted&&qaEnabled())qaRecord(@"surface-changed",@{@"surface":qaSurface(value),@"sequence":@(seq)});dispatch_source_merge_data(_signal,1);}
- (void)frame{[_lock lock];if(!_closed){_frameTicks=mach_absolute_time();_flags=StudioSurfaceFrame;_pending=YES;if(qaEnabled()){_frameCallbacks++;_lastFrameCallbackTicks=_frameTicks;}}[_lock unlock];dispatch_source_merge_data(_signal,1);}
- (void)heartbeat{[_lock lock];if(!_closed&&!_pending){_flags=StudioSurfaceHeartbeat;_pending=YES;if(qaEnabled())_heartbeats++;}[_lock unlock];dispatch_source_merge_data(_signal,1);}
- (void)sendLatest{@autoreleasepool{
 [_lock lock];if(_closed||!_pending){[_lock unlock];return;}id held=_surface;uint64_t ticks=_frameTicks;uint32_t flags=_flags;_pending=NO;uint64_t seq=++_sequence;[_lock unlock];
 if(!held)return;IOSurfaceRef s=(__bridge IOSurfaceRef)held;
 if(IOSurfaceGetPlaneCount(s)!=0||IOSurfaceGetPixelFormat(s)!=(uint32_t)'BGRA'||IOSurfaceGetAllocSize(s)>256*1024*1024){atomic_store(&stopCause,20);terminated=1;return;}
 StudioSurfaceMessage m={0};m.head.msgh_bits=MACH_MSGH_BITS_COMPLEX|MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND,0);m.head.msgh_size=sizeof(m);m.head.msgh_remote_port=_recipient;m.head.msgh_id=StudioSurfaceMessageID;m.body.msgh_descriptor_count=1;m.surface.type=MACH_MSG_PORT_DESCRIPTOR;m.surface.disposition=MACH_MSG_TYPE_COPY_SEND;
 m.magic=StudioSurfaceMagic;m.version=StudioSurfaceVersion;[_session getUUIDBytes:m.session];[_device getUUIDBytes:m.device];m.sequence=seq;m.sourceFrameTicks=ticks;m.surfaceID=IOSurfaceGetID(s);m.width=(uint32_t)IOSurfaceGetWidth(s);m.height=(uint32_t)IOSurfaceGetHeight(s);m.stride=(uint32_t)IOSurfaceGetBytesPerRow(s);m.pixelFormat=IOSurfaceGetPixelFormat(s);m.allocationBytes=IOSurfaceGetAllocSize(s);m.exifOrientation=1;m.flags=flags;
 mach_port_t surfacePort=IOSurfaceCreateMachPort(s);if(!MACH_PORT_VALID(surfacePort)){atomic_store(&stopCause,21);terminated=1;return;}m.surface.name=surfacePort;m.sentMachTicks=mach_absolute_time();
 kern_return_t result=mach_msg(&m.head,MACH_SEND_MSG|MACH_SEND_TIMEOUT,sizeof(m),0,MACH_PORT_NULL,0,MACH_PORT_NULL);mach_port_deallocate(mach_task_self(),surfacePort);
 if(qaEnabled()){[_lock lock];if(result==KERN_SUCCESS){_sends++;_lastSendTicks=m.sentMachTicks;}else if(result==MACH_SEND_TIMED_OUT)_sendTimeouts++;[_lock unlock];}
 if(result==MACH_SEND_TIMED_OUT){[_lock lock];if(!_pending){_pending=YES;_flags=flags;_frameTicks=ticks;}[_lock unlock];}
 else if(result!=KERN_SUCCESS){if(qaEnabled())qaRecord(@"send-error",@{@"kernReturn":@(result),@"sequence":@(seq)});atomic_store(&stopCause,22);terminated=1;}
}}
- (void)diagnosticSummary{
 if(!qaEnabled())return;[_lock lock];NSDictionary *info=@{@"sequence":@(_sequence),@"frameCallbacks":@(_frameCallbacks),@"surfaceChanges":@(_surfaceChanges),@"nilChanges":@(_nilChanges),@"heartbeats":@(_heartbeats),@"sends":@(_sends),@"sendTimeouts":@(_sendTimeouts),@"lastFrameCallbackTicks":@(_lastFrameCallbackTicks),@"lastSurfaceChangeTicks":@(_lastSurfaceChangeTicks),@"lastSendTicks":@(_lastSendTicks),@"surface":qaSurface(_surface),@"pending":@(_pending)};[_lock unlock];qaRecord(@"summary",info);
}
@end

int main(int argc,const char **argv){@autoreleasepool{
 if(argc!=7)return 2;NSMutableDictionary *args=[NSMutableDictionary dictionary];for(int i=1;i<argc;i+=2)args[[NSString stringWithUTF8String:argv[i]]]=[NSString stringWithUTF8String:argv[i+1]];
 NSString *device=args[@"--device"],*session=args[@"--session"],*service=args[@"--service"],*developer=NSProcessInfo.processInfo.environment[@"DEVELOPER_DIR"];
 NSUUID *sessionUUID=[[NSUUID alloc]initWithUUIDString:session],*deviceUUID=[[NSUUID alloc]initWithUUIDString:device];
 if(!sessionUUID||!deviceUUID||!developer||![service isEqualToString:[@"local.studio.surface." stringByAppendingString:session]])return 2;
 qaStart();qaRecord(@"start",@{@"device":device,@"session":session,@"pid":@(getpid()),@"parentPID":@(getppid()),@"uid":@(getuid())});
 signal(SIGTERM,stopSignal);signal(SIGINT,stopSignal);signal(SIGPIPE,SIG_IGN);pid_t parent=getppid();fcntl(STDIN_FILENO,F_SETFL,fcntl(STDIN_FILENO,F_GETFL)|O_NONBLOCK);
 dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",RTLD_NOW);NSError *error=nil;
 id context=((id(*)(id,SEL,id,NSError**))objc_msgSend)(NSClassFromString(@"SimServiceContext"),NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:"),developer,&error);
 id set=((id(*)(id,SEL,NSError**))objc_msgSend)(context,NSSelectorFromString(@"defaultDeviceSetWithError:"),&error);id dev=[readObject(set,@"devicesByUDID") objectForKey:deviceUUID],screen=nil;
 NSUInteger portIndex=0,selectedIndex=NSNotFound;
 for(id port in readObject(readObject(dev,@"io"),@"ioPorts")){id descriptor=readObject(port,@"descriptor");BOOL renderable=[descriptor conformsToProtocol:objc_getProtocol("SimDisplayIOSurfaceRenderable")];if(renderable){id s=readObject(descriptor,@"framebufferSurface");BOOL eligible=isSurface(s)&&IOSurfaceGetWidth((__bridge IOSurfaceRef)s);if(!screen&&eligible){screen=descriptor;selectedIndex=portIndex;}if(qaEnabled()){NSString *maskedStatus=nil;id masked=qaObject(descriptor,@"maskedFramebufferSurface",&maskedStatus);qaRecord(@"display-candidate",@{@"portIndex":@(portIndex),@"descriptorClass":NSStringFromClass([descriptor class]),@"selected":@(descriptor==screen),@"primary":qaSurface(s),@"masked":qaSurface(masked),@"maskedStatus":maskedStatus,@"display":qaDisplay(descriptor)});}if(screen&&!qaEnabled())break;}portIndex++;}
 if(!screen){qaRecord(@"stop",@{@"reason":@"no-nonempty-framebuffer-descriptor",@"exitCode":@3});qaFinish();return 3;}
 if(qaEnabled())qaRecord(@"display-selected",@{@"portIndex":@(selectedIndex),@"selectionRule":@"first-nonempty-framebuffer",@"display":qaDisplay(screen)});
 mach_port_t recipient=MACH_PORT_NULL;if(bootstrap_look_up(bootstrap_port,service.UTF8String,&recipient)!=KERN_SUCCESS){qaRecord(@"stop",@{@"reason":@"bootstrap-lookup-failed",@"exitCode":@4});qaFinish();return 4;}
 SurfaceRelay *relay=[SurfaceRelay new];relay.recipient=recipient;relay.session=sessionUUID;relay.device=deviceUUID;
 dispatch_queue_t sendQueue=dispatch_queue_create("studio.surface.send",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_USER_INTERACTIVE,0));
 dispatch_source_t wake=dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD,0,0,sendQueue);relay.signal=wake;__weak SurfaceRelay *weakRelay=relay;dispatch_source_set_event_handler(wake,^{[weakRelay sendLatest];});dispatch_resume(wake);
 dispatch_queue_t callbackQueue=dispatch_queue_create("studio.surface.callback",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_USER_INTERACTIVE,0));NSUUID *callbackID=NSUUID.UUID;BOOL registered=NO,newStyle=NO,legacySurface=NO;qaRecord(@"consumer-registration-begin",@{@"callbackUUID":callbackID.UUIDString,@"recipientLocalPortName":@(recipient)});
 @try{SEL sel=NSSelectorFromString(@"registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:");if([screen respondsToSelector:sel]){((void(*)(id,SEL,id,dispatch_queue_t,id,id,id))objc_msgSend)(screen,sel,callbackID,callbackQueue,^{[weakRelay frame];},^(id first,id mask){if(qaEnabled())qaRecord(@"surface-callback",@{@"primary":qaSurface(first),@"masked":qaSurface(mask)});[weakRelay changed:first];},^(id properties){if(qaEnabled())qaRecord(@"properties-callback",@{@"present":@(properties!=nil)});});registered=YES;newStyle=YES;qaRecord(@"registration",@{@"method":@"screen",@"success":@YES});}}@catch(NSException *e){qaRecord(@"registration-exception",@{@"method":@"screen"});@try{((void(*)(id,SEL,id))objc_msgSend)(screen,NSSelectorFromString(@"unregisterScreenCallbacksWithUUID:"),callbackID);}@catch(NSException *ignored){}}
 if(!registered){
  @try{((void(*)(id,SEL,id,id))objc_msgSend)(screen,NSSelectorFromString(@"registerCallbackWithUUID:ioSurfacesChangeCallback:"),callbackID,^(id value){[weakRelay changed:value];});legacySurface=YES;qaRecord(@"registration",@{@"method":@"legacy-surface",@"success":@YES});}@catch(NSException *e){qaRecord(@"registration-exception",@{@"method":@"legacy-surface"});}
  if(!legacySurface)@try{((void(*)(id,SEL,id,id))objc_msgSend)(screen,NSSelectorFromString(@"registerCallbackWithUUID:ioSurfaceChangeCallback:"),callbackID,^(id value){[weakRelay changed:value];});legacySurface=YES;qaRecord(@"registration",@{@"method":@"legacy-surface",@"success":@YES});}@catch(NSException *e){qaRecord(@"registration-exception",@{@"method":@"legacy-surface"});}
  if(legacySurface)@try{((void(*)(id,SEL,id,id))objc_msgSend)(screen,NSSelectorFromString(@"registerCallbackWithUUID:damageRectanglesCallback:"),callbackID,^(id ignored){[weakRelay frame];});registered=YES;qaRecord(@"registration",@{@"method":@"legacy-damage",@"success":@YES});}@catch(NSException *e){qaRecord(@"registration-exception",@{@"method":@"legacy-damage"});}
 }
 qaRecord(@"registration-complete",@{@"registered":@(registered),@"newStyle":@(newStyle),@"legacySurface":@(legacySurface)});
 if(!registered){atomic_store(&stopCause,23);terminated=1;}[relay changed:readObject(screen,@"framebufferSurface")];uint64_t lastHeartbeat=mach_absolute_time();
 while(!terminated&&getppid()==parent){@autoreleasepool{
  char c;ssize_t n=read(STDIN_FILENO,&c,1);if(n==0){atomic_store(&stopCause,30);break;}
  uint64_t now=mach_absolute_time();if(seconds(now-lastHeartbeat)>1){[relay heartbeat];[relay diagnosticSummary];lastHeartbeat=now;}
  // Retry only a bounded latest message after a full Mach queue; no pixel polling.
  [relay.lock lock];BOOL pending=relay.pending;[relay.lock unlock];if(pending)dispatch_source_merge_data(wake,1);
  [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0/60.0]];
 }}
 if(getppid()!=parent)atomic_store(&stopCause,31);[relay diagnosticSummary];
 [relay.lock lock];relay.closed=YES;relay.surface=nil;[relay.lock unlock];
 NSArray *unregister=newStyle?@[@"unregisterScreenCallbacksWithUUID:"]:@[@"unregisterIOSurfacesChangeCallbackWithUUID:",@"unregisterIOSurfaceChangeCallbackWithUUID:",@"unregisterDamageRectanglesCallbackWithUUID:"];
 for(NSString *name in unregister)@try{((void(*)(id,SEL,id))objc_msgSend)(screen,NSSelectorFromString(name),callbackID);}@catch(NSException *e){}
 dispatch_source_cancel(wake);dispatch_sync(sendQueue,^{});mach_port_deallocate(mach_task_self(),recipient);qaRecord(@"stop",@{@"reasonCode":@(atomic_load(&stopCause)),@"reason":stopReason(atomic_load(&stopCause)),@"exitCode":@(registered?0:5),@"callbackUUID":callbackID.UUIDString});qaFinish();return registered?0:5;
}}
