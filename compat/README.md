# Node compatibility declarations and MacPorts fallback

The pinned Mavergreen clang toolchain links Recaulk, which provides
`pthread_set_qos_class_self_np`, `recvmsg_x`, `sendmsg_x`, and
`SecTrustEvaluateWithError`. Its build flags define `MAVERGREEN_USE_RECAULK`, so
`polyfills.c` contributes none of these definitions. This avoids duplicate symbols
when Recaulk archive members are pulled into Node's executables and native tests.

The MacPorts fallback still compiles these definitions. For Mavergreen clang, `polyfills.h` includes Recaulk’s QoS header. Node crypto’s existing
Security include reaches Recaulk’s Security declarations without exposing Apple
framework types to unrelated libraries such as ICU.
Only the MacPorts fallback retains local declarations and QoS constants.
