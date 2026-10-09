#ifndef STUDIO_IOS_SURFACE_WIRE_H
#define STUDIO_IOS_SURFACE_WIRE_H
#include <mach/mach.h>
#include <stdint.h>
#include <stddef.h>
#include <uuid/uuid.h>
enum { StudioSurfaceMagic=0x53555246,StudioSurfaceVersion=1,StudioSurfaceMessageID=0x5353 };
enum { StudioSurfaceFrame=0,StudioSurfaceHeartbeat=1,StudioSurfaceChanged=2 };
typedef struct {
 mach_msg_header_t head;
 mach_msg_body_t body;
 mach_msg_port_descriptor_t surface;
 uint32_t magic,version;
 uuid_t session,device;
 uint64_t sequence,sentMachTicks,sourceFrameTicks,allocationBytes;
 uint32_t surfaceID,width,height,stride,pixelFormat,exifOrientation,flags,reserved;
} StudioSurfaceMessage;
// LocalSurfaceWire.swift reads explicit offsets; fail compilation on ABI drift.
_Static_assert(sizeof(StudioSurfaceMessage)==144,"Surface wire size changed");
_Static_assert(offsetof(StudioSurfaceMessage,magic)==40,"Surface wire descriptor changed");
_Static_assert(offsetof(StudioSurfaceMessage,session)==48,"Surface wire UUID changed");
_Static_assert(offsetof(StudioSurfaceMessage,sequence)==80,"Surface wire timing changed");
_Static_assert(offsetof(StudioSurfaceMessage,surfaceID)==112,"Surface wire dimensions changed");
_Static_assert(offsetof(StudioSurfaceMessage,flags)==136,"Surface wire flags changed");
#endif
