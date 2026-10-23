# Node compatibility declarations and MacPorts fallback

The pinned Mavergreen clang toolchain links Recaulk, which provides
`pthread_set_qos_class_self_np`, `recvmsg_x`, `sendmsg_x`, and
`SecTrustEvaluateWithError`. Its build flags define `MAVERGREEN_USE_RECAULK`, so
`polyfills.c` contributes none of these definitions. This avoids duplicate symbols
when Recaulk archive members are pulled into Node's executables and native tests.

The MacPorts fallback still compiles these definitions. Both providers retain
`polyfills.h` for the declarations and QoS constants used by the Node sources.
