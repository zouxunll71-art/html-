#include <TargetConditionals.h>
#if TARGET_OS_MACCATALYST
// The SDK's Swift Darwin module omits bootstrap registration declarations.
// Import their public C declarations through a normal bridging header.
#include <servers/bootstrap.h>
#include <mach/mach.h>
// Ephemeral per-session registration has no modern Swift equivalent. Keep the
// deprecated public C compatibility call in this small, opt-in bridge; a denied
// registration falls back to the authenticated image stream.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static inline kern_return_t StudioSurfaceRegister(const char *name,mach_port_t port) {
 return bootstrap_register(bootstrap_port,(char *)name,port);
}
#pragma clang diagnostic pop
static inline mach_msg_type_number_t StudioSurfaceLimitsCount(void) {return MACH_PORT_LIMITS_INFO_COUNT;}
static inline mach_msg_option_t StudioSurfaceReceiveOptions(void) {
 return MACH_RCV_MSG | MACH_RCV_TIMEOUT |
  MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) |
  MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT);
}
#endif
