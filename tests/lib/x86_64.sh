# platform: host-agnostic
#   usage: . tests/lib/x86_64.sh
#          x86_64_or_skip   exits 77, saying why, unless this host executes x86_64 natively: Mac OS X 10.9 or
#                           an Intel Mac. Decided from the host, never by running the binary: an Apple Silicon
#                           Mac with Rosetta would run it translated, and a Linux host runs no Mach-O at all.
x86_64_or_skip() {
  if [ "$(uname -s)" != Darwin ]; then
    echo "SKIP: $(uname -s) runs no Mach-O; the 10.9 acceptance job runs this against the installed pkg"
    exit 77
  fi
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
    echo "SKIP: an Apple Silicon Mac would run x86_64 only under Rosetta; the 10.9 acceptance job runs this"
    exit 77
  fi
}
