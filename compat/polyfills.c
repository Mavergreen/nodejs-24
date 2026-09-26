#include "polyfills.h"
#include <sys/socket.h>
#include <sys/types.h>
#include <errno.h>

#ifdef __APPLE__

/* No-op: 10.9 has no per-thread QoS self-assignment. */
int pthread_set_qos_class_self_np(int qos_class, int relative_priority) {
  (void)qos_class;
  (void)relative_priority;
  return 0;
}

/* recvmsg_x/sendmsg_x are private Darwin bulk-message syscalls libuv (deps/uv/src/unix/udp.c) uses;
 * they are unavailable on 10.9. libuv's darwin-syscalls.h declares them + struct mmsghdr; we only
 * define them here over recvmsg/sendmsg. Our local struct mmsghdr matches libuv's layout
 * (msg_hdr + msg_len), so the definitions are ABI-compatible with libuv's call sites. */
struct mmsghdr {
  struct msghdr msg_hdr;
  size_t msg_len;
};

ssize_t recvmsg_x(int s, const struct mmsghdr* msgp, u_int cnt, int flags) {
  ssize_t total = 0;
  u_int i;
  for (i = 0; i < cnt; i++) {
    ssize_t ret = recvmsg(s, (struct msghdr*)&msgp[i].msg_hdr, flags | MSG_DONTWAIT);
    if (ret < 0) {
      if (i == 0) return ret;
      break;
    }
    ((struct mmsghdr*)msgp)[i].msg_len = ret;
    total++;
    if (ret == 0) break;
  }
  return total > 0 ? total : -1;
}

ssize_t sendmsg_x(int s, const struct mmsghdr* msgp, u_int cnt, int flags) {
  ssize_t total = 0;
  u_int i;
  for (i = 0; i < cnt; i++) {
    ssize_t ret = sendmsg(s, (struct msghdr*)&msgp[i].msg_hdr, flags | MSG_DONTWAIT);
    if (ret < 0) {
      if (i == 0) return ret;
      break;
    }
    ((struct mmsghdr*)msgp)[i].msg_len = ret;
    total++;
  }
  return total > 0 ? total : -1;
}

/* SecTrustEvaluateWithError (10.12+) over the older SecTrustEvaluate available on 10.9.
 * https://trac.macports.org/ticket/66749#comment:2 */
#include <Security/Security.h>
#include <CoreFoundation/CoreFoundation.h>

static CFStringRef mav_trust_message(SecTrustResultType result) {
  switch (result) {
    case kSecTrustResultProceed:                  return CFSTR("Proceed");
    case kSecTrustResultUnspecified:              return CFSTR("Rejected Certificate");
    case kSecTrustResultDeny:                     return CFSTR("User specified to deny trust");
    case kSecTrustResultRecoverableTrustFailure:  return CFSTR("Rejected Certificate");
    case kSecTrustResultFatalTrustFailure:        return CFSTR("Bad Certificate");
    default:                                      return CFSTR("Error evaluating certificate");
  }
}

bool SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error) {
  SecTrustResultType result = kSecTrustResultInvalid;
  OSStatus status = SecTrustEvaluate(trust, &result);
  if (status == errSecSuccess &&
      (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified)) {
    if (error) *error = NULL;
    return true;
  }
  if (error)
    *error = CFErrorCreate(kCFAllocatorDefault, mav_trust_message(result), 0, NULL);
  return false;
}

#endif /* __APPLE__ */
