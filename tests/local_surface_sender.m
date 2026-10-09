#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <servers/bootstrap.h>
#import <unistd.h>
#import <sys/wait.h>
#import <spawn.h>
#import "../engine/scripts/ios_surface_wire.h"
extern char **environ;
// Adversarial protocol peer for receiver integration; never loads CoreSimulator.
int main(int argc,const char **argv){@autoreleasepool{
 if(argc!=7&&argc!=9)return 2;NSMutableDictionary *args=[NSMutableDictionary dictionary];for(int i=1;i<argc;i+=2)args[@(argv[i])]=@(argv[i+1]);mach_port_t recipient=0;
 if(bootstrap_look_up(bootstrap_port,[args[@"--service"] UTF8String],&recipient)!=KERN_SUCCESS)return 3;
 IOSurfaceRef s=IOSurfaceCreate((__bridge CFDictionaryRef)@{(__bridge NSString*)kIOSurfaceWidth:@32,(__bridge NSString*)kIOSurfaceHeight:@48,(__bridge NSString*)kIOSurfaceBytesPerElement:@4,(__bridge NSString*)kIOSurfacePixelFormat:@((uint32_t)'BGRA')});
 if(!s)return 4;mach_port_t right=IOSurfaceCreateMachPort(s);
 StudioSurfaceMessage m={0};m.head.msgh_bits=MACH_MSGH_BITS_COMPLEX|MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND,0);m.head.msgh_size=sizeof(m);m.head.msgh_remote_port=recipient;m.head.msgh_id=StudioSurfaceMessageID;m.body.msgh_descriptor_count=1;m.surface.type=MACH_MSG_PORT_DESCRIPTOR;m.surface.disposition=MACH_MSG_TYPE_COPY_SEND;m.surface.name=right;m.magic=StudioSurfaceMagic;m.version=StudioSurfaceVersion;uuid_parse([args[@"--session"] UTF8String],m.session);uuid_parse([args[@"--device"] UTF8String],m.device);m.allocationBytes=IOSurfaceGetAllocSize(s);m.surfaceID=IOSurfaceGetID(s);m.width=32;m.height=48;m.stride=(uint32_t)IOSurfaceGetBytesPerRow(s);m.pixelFormat=(uint32_t)'BGRA';m.exifOrientation=1;
 void(^send)(StudioSurfaceMessage)=^(StudioSurfaceMessage v){mach_msg(&v.head,MACH_SEND_MSG|MACH_SEND_TIMEOUT,sizeof(v),0,0,200,0);usleep(5000);};
 if(args[@"--foreign"]){m.sequence=999;send(m);mach_port_deallocate(mach_task_self(),right);mach_port_deallocate(mach_task_self(),recipient);CFRelease(s);return 0;}
 m.sequence=1;send(m);
 // Valid transport rights with wrong application identity/shape/ordering must be rejected.
 StudioSurfaceMessage bad=m;bad.sequence=2;bad.session[0]^=1;send(bad);
 bad=m;bad.sequence=3;bad.device[0]^=1;send(bad);
 bad=m;bad.sequence=4;bad.version=999;send(bad);
 bad=m;bad.sequence=5;bad.width=31;send(bad);
 bad=m;bad.sequence=6;bad.allocationBytes=UINT64_MAX;send(bad);
 bad=m;bad.sequence=7;bad.flags=99;send(bad);
 bad=m;bad.sequence=0;send(bad);
 // A child knows session and device but has a different kernel audit PID.
 pid_t child=0;char *foreignArgs[]={(char*)argv[0],(char*)argv[1],(char*)argv[2],(char*)argv[3],(char*)argv[4],(char*)argv[5],(char*)argv[6],"--foreign","yes",NULL};if(posix_spawn(&child,argv[0],NULL,NULL,foreignArgs,environ)==0){int st;waitpid(child,&st,0);}
 // Exercise repeated rejected rights. This would leak 50 send rights without destroy.
 for(int i=0;i<50;i++){bad=m;bad.sequence=UINT64_MAX;bad.device[0]^=1;send(bad);}
 m.sequence=8;m.flags=StudioSurfaceHeartbeat;send(m);m.sequence=9;m.flags=StudioSurfaceFrame;send(m);
 char byte;while(read(STDIN_FILENO,&byte,1)>0){}
 mach_port_deallocate(mach_task_self(),right);mach_port_deallocate(mach_task_self(),recipient);CFRelease(s);return 0;
}}
