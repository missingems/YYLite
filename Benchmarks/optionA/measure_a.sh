#!/usr/bin/env bash
# Option A size probe: yyjson reader-only vs reader + mutable doc + writer, arm64-apple-ios, -Os, dead-strip.
set -euo pipefail
export PATH=/usr/bin:/usr/lib/llvm-19/bin:$PATH
H=$(cd "$(dirname "$0")" && pwd); SRC=$H/../../Sources/CYYJSON; SHIM=$H/shim; T=$(mktemp -d)
BASE=(-target arm64-apple-ios15.0 -nostdlibinc -isystem "$SHIM" -Os -ffunction-sections -fdata-sections -fvisibility=hidden
      -I"$SRC/include" -DYYJSON_DISABLE_UTILS=1 -DYYJSON_DISABLE_INCR_READER=1 -DYYJSON_DISABLE_NON_STANDARD=1
      -DYYJSON_DISABLE_FAST_FP_CONV=1 -DYYJSON_DISABLE_FILE=1 -DYYJSON_SIZE_OPT=1 -DYYJSON_SIZE_OPT_NO_MSG=1 -include stdio.h)
L="ld64.lld-19 -arch arm64 -platform_version ios 15.0 15.0 -dead_strip -undefined dynamic_lookup"
tot() { llvm-size -m "$1" | awk '/Section /{n=$0; if (n ~ /bss|common/) next; s+=$NF} END{print s}'; }
echo 'int main(int c,char**v){return c;}' > $T/e.c; clang -c "${BASE[@]}" $T/e.c -o $T/e.o; $L -o $T/e $T/e.o
run() { # name main extra-flags...
  local name=$1 main=$2; shift 2
  clang -c "${BASE[@]}" "$@" "$SRC/yyjson.c" -o $T/y.o
  clang -c "${BASE[@]}" "$@" "$H/$main" -o $T/m.o
  $L -o $T/a $T/m.o $T/y.o
  echo "$name $(( $(tot $T/a) - $(tot $T/e) ))"
}
run "reader-only (current)" main_r.c -DYYJSON_DISABLE_WRITER=1
run "reader+mut-doc+writer (option A)" main_rw.c
rm -rf $T
