#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <IOSurface/IOSurface.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <unistd.h>
#import <signal.h>
#import <string.h>
#import <arpa/inet.h>
#import <mach/mach_time.h>

static double monotonicTime(void) {
 static mach_timebase_info_data_t info;
 if (!info.denom) mach_timebase_info(&info);
 return (double)mach_absolute_time() * info.numer / info.denom / 1e9;
}

// Check pixels before lossless encoding. Some simulator versions update pixels
// without incrementing the IOSurface seed, so seed-only checks freeze frames.
static BOOL pixelsChanged(IOSurfaceRef surface, NSMutableData *previous, uint32_t *format,
                          size_t *width, size_t *height, size_t *stride) {
 size_t row = IOSurfaceGetBytesPerRow(surface), h = IOSurfaceGetHeight(surface);
 if (IOSurfaceGetPlaneCount(surface) != 0 || row == 0 || h > SIZE_MAX / row) return YES;
 size_t size = row * h;
 if (size == 0 || size > 128 * 1024 * 1024 || size > IOSurfaceGetAllocSize(surface)) return YES;
 if (IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL) != kIOReturnSuccess) return YES;
 const void *bytes = IOSurfaceGetBaseAddress(surface);
 BOOL changed = YES;
 if (bytes) {
  uint32_t nextFormat = IOSurfaceGetPixelFormat(surface);size_t w = IOSurfaceGetWidth(surface);
  changed = previous.length != size || *format != nextFormat || *width != w || *height != h || *stride != row || memcmp(previous.bytes, bytes, size) != 0;
  if (changed) {previous.length = size;memcpy(previous.mutableBytes, bytes, size);*format=nextFormat;*width=w;*height=h;*stride=row;}
 }
 IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
 return changed;
}

static BOOL sendFrame(NSData *jpeg) {
 if (!jpeg.length || jpeg.length > UINT32_MAX) return NO;
 uint32_t count = htonl((uint32_t)jpeg.length);
 return fwrite(&count, 4, 1, stdout) == 1 && fwrite(jpeg.bytes, 1, jpeg.length, stdout) == jpeg.length && fflush(stdout) == 0;
}
id get(id obj,NSString *key){return ((id(*)(id,SEL))objc_msgSend)(obj,NSSelectorFromString(key));}
int main(int argc,const char **argv){@autoreleasepool{
 if(argc<2)return 2;
 const pid_t parent=getppid();signal(SIGPIPE,SIG_IGN);
 dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",RTLD_NOW);
 NSString *developerDir=NSProcessInfo.processInfo.environment[@"DEVELOPER_DIR"];if(!developerDir){fprintf(stderr,"DEVELOPER_DIR is required\n");return 2;}
 NSError*error=nil;id ctx=((id(*)(id,SEL,id,NSError**))objc_msgSend)(NSClassFromString(@"SimServiceContext"),NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:"),developerDir,&error);
 id set=((id(*)(id,SEL,NSError**))objc_msgSend)(ctx,NSSelectorFromString(@"defaultDeviceSetWithError:"),&error);
 id dev=[get(set,@"devicesByUDID") objectForKey:[[NSUUID alloc]initWithUUIDString:[NSString stringWithUTF8String:argv[1]]]];id io=get(dev,@"io");id screen=nil;
 for(id port in get(io,@"ioPorts")){id desc=get(port,@"descriptor");if([desc conformsToProtocol:objc_getProtocol("SimDisplayIOSurfaceRenderable")]){IOSurfaceRef surface=(__bridge IOSurfaceRef)get(desc,@"framebufferSurface");if(surface && IOSurfaceGetWidth(surface)>0){screen=desc;break;}}}
 if(!screen){fprintf(stderr,"No framebuffer surface\n");return 3;}
 CIContext *context=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO,kCIContextCacheIntermediates:@YES}];CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();double lastSent=0,lastResolve=0,nextFrame=0,lastChanged=0;NSData *lastJPEG=nil;
 NSMutableData *previous=[NSMutableData data];uint32_t format=0;size_t width=0,height=0,stride=0;
 while(true){@autoreleasepool{
  if(getppid()!=parent)break;
  double now=monotonicTime();
  if(now<nextFrame){usleep((useconds_t)((nextFrame-now)*1e6));continue;}
  // Keep interaction at 60 fps; a static screen only needs an inexpensive wake-up check.
  nextFrame=now+(now-lastChanged<0.4 ? 1.0/60.0 : 1.0/10.0);
  if(now-lastResolve>1){
   io=get(dev,@"io");
   for(id port in get(io,@"ioPorts")){id desc=get(port,@"descriptor");if([desc conformsToProtocol:objc_getProtocol("SimDisplayIOSurfaceRenderable")]){IOSurfaceRef candidate=(__bridge IOSurfaceRef)get(desc,@"framebufferSurface");if(candidate && IOSurfaceGetWidth(candidate)>0){screen=desc;break;}}}
   lastResolve=now;
  }
  IOSurfaceRef surface=(__bridge IOSurfaceRef)get(screen,@"framebufferSurface");if(!surface){usleep(33000);continue;}
  if(argc<=2 && !pixelsChanged(surface,previous,&format,&width,&height,&stride) && lastJPEG){
   if(now-lastSent>=1){if(!sendFrame(lastJPEG))break;lastSent=now;}
   continue;
  }
  lastChanged=now;nextFrame=now+1.0/60.0;
  CIImage *image=[CIImage imageWithIOSurface:surface];
  NSData *jpeg=[context PNGRepresentationOfImage:image format:kCIFormatRGBA8 colorSpace:color options:@{}];
  if(!jpeg.length){previous.length=0;continue;}
  if(argc>2){[jpeg writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];break;}
  if([jpeg isEqualToData:lastJPEG] && now-lastSent<1)continue;lastJPEG=jpeg;
  if(!sendFrame(jpeg))break;lastSent=monotonicTime();
 }}CGColorSpaceRelease(color);
}}
