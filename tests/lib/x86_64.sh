#   usage: . tests/lib/x86_64.sh
#          x86_64_or_skip   exits 77, saying why, when this host cannot execute an x86_64 binary
#          x86_64_run CMD…  runs CMD as x86_64: natively on an x86_64 host, else through `arch -x86_64`
# spec: INGREDIENTS.md "Conformance deviations", rosetta:tests/lib/x86_64.sh -- a declared, best-effort
#       Rosetta use; never needed by the build.
x86_64_or_skip() {
  case "$(uname -m)" in x86_64) return 0 ;; esac
  arch -x86_64 /usr/bin/true 2>/dev/null && return 0
  echo "SKIP: this $(uname -m) host cannot execute x86_64 (no Rosetta); run on a real 10.9 box"
  exit 77
}
x86_64_run() {
  case "$(uname -m)" in
    x86_64) "$@" ;;
    *) arch -x86_64 "$@" ;;
  esac
}
