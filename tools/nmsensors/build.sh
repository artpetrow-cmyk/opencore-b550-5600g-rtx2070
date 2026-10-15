#!/bin/bash
# build.sh - build NMSensors.kext (AMD Zen CPU temperature for VirtualSMC, read-only) with the Command Line Tools.
#     VSMC=<VirtualSMC-1.3.8 source> LILU=<Lilu-1.7.2 source>/Lilu bash build.sh      -> out/NMSensors.kext
# Use the source tags of the VirtualSMC and Lilu kexts you boot with. Installs nothing.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
die() { printf 'STOP: %s\n' "$*" >&2; exit 1; }
VSMC="${VSMC:-}"; LILU="${LILU:-}"
[ -f "$VSMC/VirtualSMCSDK/kern_vsmcapi.hpp" ] || die "set VSMC to a VirtualSMC source tree (VirtualSMCSDK/kern_vsmcapi.hpp)"
[ -f "$LILU/Headers/kern_util.hpp" ] || die "set LILU to the Lilu folder of a Lilu source tree (Headers/kern_util.hpp)"
SDK=$(xcrun --show-sdk-path); KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
B="$HERE/out"; rm -rf "$B"; mkdir -p "$B/NMSensors.kext/Contents/MacOS"
xcrun clang++ -arch x86_64 -fapple-kext -mkernel -nostdinc -I"$KHDR" -I"$LILU" -I"$VSMC" \
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -DPRODUCT_NAME=NMSensors -DMODULE_VERSION=1.0.0 \
  -std=c++17 -fno-rtti -fno-exceptions -fno-builtin -fno-common -Wall -Wno-unused-parameter -O2 \
  "-ffile-prefix-map=$HERE=/src" -c "$HERE/NMSensors.cpp" -o "$B/NMSensors.o" 2>"$B/cc.err" \
  || { grep -E 'error' "$B/cc.err" | head -20; die "compile failed, see $B/cc.err"; }
xcrun clang++ -arch x86_64 -fapple-kext -nostdlib -Xlinker -kext -lkmodc++ -lkmod -lcc_kext "$B/NMSensors.o" \
  -o "$B/NMSensors.kext/Contents/MacOS/NMSensors" 2>"$B/ld.err" || { head -20 "$B/ld.err"; die "link failed"; }
cp "$HERE/Info.plist" "$B/NMSensors.kext/Contents/Info.plist"
plutil -lint "$B/NMSensors.kext/Contents/Info.plist" >/dev/null || die "Info.plist does not parse"
echo "built $B/NMSensors.kext ($(shasum -a 256 "$B/NMSensors.kext/Contents/MacOS/NMSensors" | cut -c1-16))"
