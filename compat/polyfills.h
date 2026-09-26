#ifndef MAVERICKS_POLYFILLS_H
#define MAVERICKS_POLYFILLS_H

/* Node/V8-specific 10.9 back-fills NOT covered by the toolchain's bundled legacy-support.
 * This header carries only DECLARATIONS (macros + prototypes) and is safe to force-include into
 * every translation unit; the definitions live in polyfills.c, linked globally. Scope (see the port's
 * spec): QoS constants for V8 platform-posix.cc, and SecTrustEvaluateWithError for Node crypto.
 * recvmsg_x/sendmsg_x are deliberately NOT declared here -- libuv's own deps/uv/src/unix/
 * darwin-syscalls.h declares them (and struct mmsghdr); we only supply their definitions. */

#ifdef __cplusplus
extern "C" {
#endif

/* QoS class constants: absent from the 10.9 SDK; V8's platform-posix.cc references them. */
#ifndef QOS_CLASS_USER_INTERACTIVE
#define QOS_CLASS_USER_INTERACTIVE  0x21
#endif
#ifndef QOS_CLASS_USER_INITIATED
#define QOS_CLASS_USER_INITIATED    0x19
#endif
#ifndef QOS_CLASS_DEFAULT
#define QOS_CLASS_DEFAULT           0x15
#endif
#ifndef QOS_CLASS_UTILITY
#define QOS_CLASS_UTILITY           0x11
#endif
#ifndef QOS_CLASS_BACKGROUND
#define QOS_CLASS_BACKGROUND        0x09
#endif
#ifndef QOS_CLASS_UNSPECIFIED
#define QOS_CLASS_UNSPECIFIED       0x00
#endif

/* No-op on 10.9 (per-thread QoS self-assignment unavailable). Referenced by V8 platform-posix.cc. */
int pthread_set_qos_class_self_np(int qos_class, int relative_priority);

/* SecTrustEvaluateWithError arrived in 10.12; Node's src/crypto/crypto_context.cc calls it.
 * Forward-declare the types (guarded against the real Security/CoreFoundation headers) + the fn. */
#ifdef __APPLE__
#include <stdbool.h>
#ifndef _SECURITY_SECTRUST_H_
typedef struct __SecTrust *SecTrustRef;
#endif
#ifndef __COREFOUNDATION_CFERROR__
typedef struct __CFError *CFErrorRef;
#endif
bool SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error);
#endif

#ifdef __cplusplus
}
#endif

#endif /* MAVERICKS_POLYFILLS_H */
