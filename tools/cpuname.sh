#!/bin/bash
# cpuname.sh - the real CPU name in About This Mac / System Information without patching code.
# RestrictEvents' revpatch=cpuname rewrites AppleSystemInfo's code in memory; on macOS 26 that code sits in the sealed OS
# cryptex, and when the patched page is paged in again the APFS seal check fails (hash mismatch) and
# About This Mac / System Information crash with SIGBUS. Without the patch macOS names the CPU from
# SMBIOS ProcessorType 0x0601 and the core count: the key "6-Core Intel Core i5" of
# AppleSystemInfo.framework/Resources/Processors.loctable (a plain data file on the system volume, outside the cryptex).
# This script changes that one entry, in every language, to the real name, on the live system volume, and blesses a new
# snapshot (needs authenticated-root disabled, csr 0x800). Boot with revpatch=sbvmm (no cpuname).
#   sudo bash cpuname.sh ["AMD Ryzen 5 5600G"] [key]   default name: NVRAM revcpuname, else the CPU brand string;
#                                                       default key: "6-Core Intel Core i5"
#   sudo bash cpuname.sh --revert                       put back Apple's file (saved here before the first change)
#   bash cpuname.sh --check                              what the booted system's table says for the key
# A macOS update brings a fresh sealed system without the change: rerun after every update.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; MNT=/System/Volumes/Update/mnt1
REL=System/Library/PrivateFrameworks/AppleSystemInfo.framework/Versions/A/Resources/Processors.loctable
die() { printf 'STOP: %s\n' "$*" >&2; exit 1; }
show() { /usr/bin/python3 -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb")); k=sys.argv[2]; print("  en: %r\n  ru: %r" % (d.get("en",{}).get(k), d.get("ru",{}).get(k)))' "$1" "$2"; }
KEY_DEFAULT="6-Core Intel Core i5"
if [ "${1:-}" = --check ]; then
    echo "/$REL, key \"${2:-$KEY_DEFAULT}\":"; show "/$REL" "${2:-$KEY_DEFAULT}"
    system_profiler SPHardwareDataType 2>/dev/null | grep -E "Processor Name|Model Identifier"; exit 0
fi
[ "$(id -u)" = 0 ] || die "run with sudo"
csrutil authenticated-root status 2>/dev/null | grep -q disabled || die "authenticated-root is enabled (csr bit 0x800 needed)"
SNAPDEV=$(mount | awk '$3=="/"{print $1}'); VOLDEV=$(echo "$SNAPDEV" | sed -E 's/s[0-9]+$//')
diskutil apfs list | grep -q "${VOLDEV#/dev/} (System)" || die "$VOLDEV is not the system volume (booted snapshot $SNAPDEV)"
mkdir -p "$MNT"
mount | grep -q " on $MNT " || mount -o nobrowse -t apfs "$VOLDEV" "$MNT" || die "cannot mount $VOLDEV on $MNT"
F="$MNT/$REL"; [ -f "$F" ] || die "no $F"
BUILD=$(sw_vers -buildVersion); ORIG="$HERE/Processors.loctable.apple-$BUILD"
if [ "${1:-}" = --revert ]; then
    [ -f "$ORIG" ] || die "no saved original for build $BUILD ($ORIG)"
    cp "$ORIG" "$F.cpuname-new" && chown root:wheel "$F.cpuname-new" && chmod 644 "$F.cpuname-new" && mv "$F.cpuname-new" "$F" || die "restore failed"
    echo "Apple's Processors.loctable restored"
else
    NAME="${1:-}"; KEY="${2:-$KEY_DEFAULT}"
    [ -n "$NAME" ] || NAME=$(nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:revcpuname 2>/dev/null | cut -f2- | sed 's/%00//g')
    [ -n "$NAME" ] || NAME=$(sysctl -n machdep.cpu.brand_string | sed 's/ with Radeon Graphics//')
    [ -f "$ORIG" ] || { cmp -s "$F" "/$REL" && cp -p "$F" "$ORIG" || die "the live file already differs from the booted one - not saving it as Apple's"; }
    echo "Apple's file saved: $ORIG"
    /usr/bin/python3 - "$ORIG" "$F.cpuname-new" "$KEY" "$NAME" <<'PY' || die "editing the table failed"
import plistlib, sys
src, dst, key, name = sys.argv[1:5]
d = plistlib.load(open(src, 'rb'))
n = 0
for lang, table in d.items():
    if isinstance(table, dict) and key in table:
        table[key] = name; n += 1
if n == 0: sys.exit("key %r not found in any language" % key)
plistlib.dump(d, open(dst, 'wb'), fmt=plistlib.FMT_BINARY)
print("key %r -> %r in %d languages" % (key, name, n))
PY
    chown root:wheel "$F.cpuname-new" && chmod 644 "$F.cpuname-new" && mv "$F.cpuname-new" "$F" || die "cannot put the table in place"
    show "$F" "$KEY"
fi
bless --folder "$MNT/System/Library/CoreServices" --bootefi --create-snapshot || die "bless --create-snapshot failed"
echo; echo "New snapshot created and selected. Reboot, then: bash $0 --check"
