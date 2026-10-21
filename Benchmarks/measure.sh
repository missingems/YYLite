#!/bin/bash
# Size proxy: Static Linux SDK aarch64-musl, -Osize, function/data sections, --gc-sections, lld map attribution.
set -e
cd "$(dirname "$0")"; mkdir -p maps
for p in ${@:-sz_empty sz_codable_dec sz_codable_both sz_codableD_dec sz_lite_dec sz_lite_both sz_loop_dec sz_lite_core_both}; do
  swift build -c release --swift-sdk aarch64-swift-linux-musl --product $p \
    -Xswiftc -Osize -Xcc -Os -Xcc -ffunction-sections -Xcc -fdata-sections \
    -Xswiftc -Xfrontend -Xswiftc -function-sections -Xswiftc -Xfrontend -Xswiftc -internalize-at-link \
    -Xlinker --gc-sections -Xlinker --no-export-dynamic -Xlinker -Map=$PWD/maps/$p.txt >/dev/null
  echo "== $p"; python3 attribute.py maps/$p.txt
done
