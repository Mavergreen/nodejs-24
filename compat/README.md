# Node-specific 10.9 compat shims

Symbols/decls Node/V8 reference that the 10.9 SDK lacks and that the toolchain's legacy-support layer
does not already provide (recvmsg_x/sendmsg_x, os_signpost stubs, SecTrustEvaluateWithError,
pthread_set_qos_class_self_np, max_align_t). `build/build.sh` copies these into the Node build tree and
force-includes `polyfills.h`. As the toolchain gains coverage (mavericks-clang bundles
mavericks-legacy-support), trim whatever becomes redundant — keep only what stays genuinely missing.
