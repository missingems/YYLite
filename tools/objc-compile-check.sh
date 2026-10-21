#!/bin/bash
# Compile-only check of the ObjC sources for arm64-apple-ios using STAND-IN headers (tools/objc-shim),
# for environments without an Apple SDK. Catches syntax/type/ARC errors and measures object size.
# It does NOT validate against the real Foundation headers and does not link or run anything.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SHIM=$ROOT/tools/objc-shim
OUT=${OUT:-$ROOT/.build/objc-check}
mkdir -p "$OUT"
COMMON=(-target arm64-apple-ios15.0 -nostdlibinc -isystem "$SHIM" -isystem "$SHIM/objc"
        -Os -ffunction-sections -fdata-sections -fvisibility=hidden -Wall -Wextra -Wno-unused-parameter)
YYDEFS=(-DYYJSON_DISABLE_WRITER=1 -DYYJSON_DISABLE_UTILS=1 -DYYJSON_DISABLE_INCR_READER=1
        -DYYJSON_DISABLE_NON_STANDARD=1 -DYYJSON_DISABLE_FAST_FP_CONV=1 -DYYJSON_DISABLE_FILE=1
        -DYYJSON_SIZE_OPT=1 -DYYJSON_SIZE_OPT_NO_MSG=1)
INC=(-I"$ROOT/Sources/CYYJSON/include" -I"$ROOT/Sources/YYLiteObjC/include")
OBJC=(-x objective-c -fobjc-arc -fobjc-runtime=ios-15.0 -fblocks -Wno-nullability-completeness)

clang -c "${COMMON[@]}" "${YYDEFS[@]}" "${INC[@]}" -Wno-sign-compare -Wno-unused-function "$ROOT/Sources/CYYJSON/yyjson.c" -o "$OUT/yyjson.o" 2>/dev/null
clang -c "${COMMON[@]}" "${INC[@]}" "$ROOT/Sources/CYYJSON/yylite_writer.c" -o "$OUT/yylite_writer.o"
clang -c "${COMMON[@]}" "${OBJC[@]}" "${INC[@]}" "$ROOT/Sources/YYLiteObjC/YYLiteObjC.m" -o "$OUT/YYLiteObjC.o"
clang -c "${COMMON[@]}" "${OBJC[@]}" "${INC[@]}" "$ROOT/Examples/ObjC/MTGCard.m" -o "$OUT/MTGCard.o"
clang -fsyntax-only "${COMMON[@]}" "${OBJC[@]}" "${INC[@]}" -I"$ROOT/Examples/ObjC" "$ROOT/Tests/YYLiteObjCTests/YYLiteObjCTests.m"
echo "compiled OK (stand-in headers) → $OUT"
for f in yyjson yylite_writer YYLiteObjC MTGCard; do
  printf '%-18s %s\n' "$f.o" "$(llvm-size -A "$OUT/$f.o" | awk '$1!~/debug|compact_unwind|eh_frame|LLVM|addrsig|Total/ && $2~/^[0-9]+$/ {t+=$2} END{print t " B (sections excl. unwind/debug)"}')"
done
