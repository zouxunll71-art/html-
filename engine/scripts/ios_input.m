// SimulatorKit transport for the workbench, kept outside the shipped iOS app.
// Indigo wire layout informed by Meta's MIT-licensed idb (see THIRD_PARTY_NOTICES.md).
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <poll.h>
#import <unistd.h>
#import <math.h>

// The packed single-contact envelope is intentionally independent of SDK headers.
#pragma pack(push, 4)
typedef struct { uint32_t a,b,mask; double x,y,c,d,e; uint32_t range,touch,f,g,h; double i,j,k,l,m; } Contact;
typedef struct { uint32_t kind; uint64_t time; uint32_t reserved; uint8_t event[128]; } Payload;
typedef struct { uint8_t mach[24]; uint32_t size; uint8_t type; uint8_t reserved[3]; Payload first,second; } TouchMessage;
#pragma pack(pop)
_Static_assert(sizeof(Contact)==112 && sizeof(Payload)==144 && sizeof(TouchMessage)==320,"Unexpected Indigo layout");
typedef void *(*MouseBuilder)(CGPoint *,CGPoint *,uint32_t,NSUInteger,CGSize,uint32_t);
typedef void *(*KeyBuilder)(int,int);
static id HID;
static MouseBuilder MakeMouse;
static KeyBuilder MakeKey;
static BOOL Touching=NO;
static CGPoint LastPoint;
static uint32_t Edge=0;
static NSString *DeviceID,*DeveloperDir;
static id Get(id o,NSString *s){return ((id(*)(id,SEL))objc_msgSend)(o,NSSelectorFromString(s));}
static void Fail(NSString *s){@throw [NSException exceptionWithName:@"StudioInput" reason:s userInfo:nil];}
static void Send(void *bytes){
 if(!bytes)Fail(@"Unable to allocate input message");
 dispatch_semaphore_t done=dispatch_semaphore_create(0);__block NSError *failure=nil;
 // The client owns bytes, including when its send throws after accepting them.
 ((void(*)(id,SEL,void *,BOOL,dispatch_queue_t,id))objc_msgSend)(HID,NSSelectorFromString(@"sendWithMessage:freeWhenDone:completionQueue:completion:"),bytes,YES,dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE,0),^(NSError *error){failure=error;dispatch_semaphore_signal(done);});
 if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)))Fail(@"Simulator input delivery timed out");
 if(failure)Fail(failure.localizedDescription);
}
static void Touch(CGPoint point,BOOL down){
 void *source=MakeMouse(&point,NULL,0x32,down?1:2,CGSizeMake(1,1),Edge);
 if(!source)Fail(@"SimulatorKit could not create a touch");
 TouchMessage *message=calloc(1,sizeof(TouchMessage));
 if(!message){free(source);Fail(@"Unable to allocate touch");}
 message->size=sizeof(Payload);message->type=2;message->first.kind=11;message->first.time=mach_absolute_time();
 memcpy(message->first.event,(uint8_t *)source+0x30,sizeof(Contact));free(source);
 Contact *contact=(Contact *)message->first.event;contact->x=point.x;contact->y=point.y;
 message->second=message->first;((Contact *)message->second.event)->a=1;((Contact *)message->second.event)->b=2;
 LastPoint=point;if(down)Touching=YES;Send(message);if(!down)Touching=NO;
}
static void Release(void){if(Touching){Touch(LastPoint,NO);Touching=NO;}}
static void Key(int code,int direction){Send(MakeKey(code,direction));}
static void Reply(NSDictionary *object){NSData *data=[NSJSONSerialization dataWithJSONObject:object options:0 error:nil];fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);fflush(stdout);}
static void Connect(void){
 if(!dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",RTLD_NOW))Fail(@"CoreSimulator is unavailable");
 NSString *path=[DeveloperDir stringByAppendingPathComponent:@"Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"];
 void *kit=dlopen(path.UTF8String,RTLD_NOW);
 if(!kit)Fail(@"SimulatorKit is unavailable in the selected Xcode");
 MakeMouse=(MouseBuilder)dlsym(kit,"IndigoHIDMessageForMouseNSEvent");MakeKey=(KeyBuilder)dlsym(kit,"IndigoHIDMessageForKeyboardArbitrary");
 Class service=NSClassFromString(@"SimServiceContext"),client=NSClassFromString(@"SimulatorKit.SimDeviceLegacyHIDClient");
 if(!MakeMouse || !MakeKey || !service || !client || ![client instancesRespondToSelector:NSSelectorFromString(@"initWithDevice:error:")] || ![client instancesRespondToSelector:NSSelectorFromString(@"sendWithMessage:freeWhenDone:completionQueue:completion:")])Fail(@"This Xcode does not expose a compatible simulator input interface");
 NSError *error=nil;
 id context=((id(*)(id,SEL,id,NSError **))objc_msgSend)(service,NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:"),DeveloperDir,&error);
 if(!context)Fail(error.localizedDescription ?: @"Cannot connect to CoreSimulator");
 id set=((id(*)(id,SEL,NSError **))objc_msgSend)(context,NSSelectorFromString(@"defaultDeviceSetWithError:"),&error);
 id device=[Get(set,@"devicesByUDID") objectForKey:[[NSUUID alloc]initWithUUIDString:DeviceID]];
 if(!device)Fail(@"Configured simulator does not exist");
 HID=((id(*)(id,SEL,id,NSError **))objc_msgSend)([client alloc],NSSelectorFromString(@"initWithDevice:error:"),device,&error);
 if(!HID)Fail(error.localizedDescription ?: @"Simulator input is unavailable; start the configured device first");
}
static void Command(NSDictionary *command){
 NSString *kind=command[@"kind"];
 if([kind isEqual:@"cancel"]){Release();return;}
 if([kind isEqual:@"hide"]){for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.iphonesimulator"])[app hide];return;}
 if([kind isEqual:@"text"]){
  Release();NSString *text=command[@"text"];
  if(![text isKindOfClass:NSString.class] || text.length>16384)Fail(@"Invalid text");
  // Numeric edits use the persistent HID connection, not a subprocess per digit.
  NSCharacterSet *numeric=[NSCharacterSet characterSetWithCharactersInString:@"0123456789.-"];
  if(text.length && [text rangeOfCharacterFromSet:numeric.invertedSet].location==NSNotFound){
   for(NSUInteger i=0;i<text.length;i++){unichar c=[text characterAtIndex:i];int code=c=='0'?39:c=='.'?55:c=='-'?45:30+(c-'1');Key(code,1);Key(code,2);}return;
  }
  // Address the dedicated simulator pasteboard; do not write to NSPasteboard here.
  NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/xcrun"];task.arguments=@[@"simctl",@"pbcopy",DeviceID];
  task.environment=NSProcessInfo.processInfo.environment;NSPipe *pipe=NSPipe.pipe;task.standardInput=pipe;task.standardOutput=NSFileHandle.fileHandleWithNullDevice;task.standardError=NSFileHandle.fileHandleWithNullDevice;
  NSError *error=nil;if(![task launchAndReturnError:&error])Fail(error.localizedDescription);
  [pipe.fileHandleForWriting writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];[pipe.fileHandleForWriting closeFile];[task waitUntilExit];if(task.terminationStatus)Fail(@"Cannot update simulator clipboard");
  @try{Key(227,1);Key(25,1);Key(25,2);Key(227,2);}@finally{Key(25,2);Key(227,2);}return;
 }
 if([kind isEqual:@"key"]){Release();int code=[command[@"code"] intValue];if(code!=40 && code!=42 && code!=43 && code!=41)Fail(@"Unsupported key");Key(code,1);Key(code,2);return;}
 BOOL down=[kind isEqual:@"down"],move=[kind isEqual:@"move"],up=[kind isEqual:@"up"];
 if(!down && !move && !up)Fail(@"Unknown input command");
 if(![command[@"x"] isKindOfClass:NSNumber.class] || ![command[@"y"] isKindOfClass:NSNumber.class])Fail(@"Invalid touch coordinates");
 double x=[command[@"x"] doubleValue],y=[command[@"y"] doubleValue];
 if(!isfinite(x)||!isfinite(y)||x<0||x>1||y<0||y>1)Fail(@"Touch is outside the display");
 if(down){Release();Edge=x<0.015?2:y<0.015?1:y>0.985?3:x>0.985?4:0;}
 else if(!Touching)return;
 Touch(CGPointMake(x,y),!up);
}
int main(int argc,const char **argv){@autoreleasepool{
 if(argc!=2)return 2;
 DeviceID=[NSString stringWithUTF8String:argv[1]];DeveloperDir=NSProcessInfo.processInfo.environment[@"DEVELOPER_DIR"];
 if(!DeveloperDir){Reply(@{@"error":@"DEVELOPER_DIR is required"});return 2;}
 @try{Connect();Reply(@{@"ready":@YES,@"transport":@"SimulatorKit-Indigo"});}
 @catch(NSException *e){Reply(@{@"error":e.reason ?: e.name});return 3;}
 setvbuf(stdin,NULL,_IONBF,0);char *line=NULL;size_t capacity=0;
 while(YES){@autoreleasepool{
  struct pollfd input={STDIN_FILENO,POLLIN|POLLHUP,0};int ready=poll(&input,1,15000);
  if(ready==0){@try{Release();}@catch(NSException *e){break;}continue;}
  if(ready<0 || getline(&line,&capacity,stdin)<0)break;
  @try{NSData *data=[[NSString stringWithUTF8String:line] dataUsingEncoding:NSUTF8StringEncoding];id command=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];if(![command isKindOfClass:NSDictionary.class])Fail(@"Invalid input command");Command(command);Reply(@{@"ok":@YES});}
  @catch(NSException *e){@try{Release();}@catch(NSException *ignored){}Reply(@{@"error":e.reason ?: e.name});break;}
 }}
 free(line);@try{Release();}@catch(NSException *ignored){}return 0;
}}
