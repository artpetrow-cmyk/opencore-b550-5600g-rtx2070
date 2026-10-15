#!/bin/bash
# btfix.sh - stop bluetoothd crashing with SIGBUS when BlueToolFixup (Lilu) patches it on macOS 26.
# BlueToolFixup patches pages of /usr/sbin/bluetoothd (and BlueTool) in memory. On macOS 26 APFS re-hashes the whole
# 16 KB block of a sealed-volume file on page-in; when the block already holds a patched page the hash mismatches,
# page-in fails (EBADMSG) and bluetoothd dies - typically when a headset connects, leaving Bluetooth hung.
#
# Fix: rewrite /usr/sbin/bluetoothd and /usr/sbin/BlueTool on the live system volume with Apple's own bytes (same
# CDHash, valid signature, uncompressed, no seal hashes) and bless a new snapshot. The bytes come from the files
# themselves, read through a separate mount of the live volume (a vnode Lilu never patched), so any build works.
# Needs authenticated-root disabled (csr-active-config bit 0x800). Rerun after every macOS update.
#
#   sudo bash btfix.sh            apply
#   sudo bash btfix.sh --revert   boot the last sealed snapshot again (undo)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="$HERE/btfix-$(date +%Y%m%d-%H%M%S).log"
MNT=/System/Volumes/Update/mnt1
exec > >(tee -a "$LOG") 2>&1

die() { echo "STOP: $*"; echo "Log: $LOG"; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"

SNAPDEV=$(mount | awk '$3=="/"{print $1}')          # e.g. /dev/disk3s2s1
VOLDEV=$(echo "$SNAPDEV" | sed -E 's/s[0-9]+$//')    # e.g. /dev/disk3s2
diskutil apfs list | grep -q "${VOLDEV#/dev/} (System)" || die "$VOLDEV is not the system volume (snapshot $SNAPDEV)"
echo "system volume: $VOLDEV (booted snapshot $SNAPDEV)"

if [ "${1:-}" = "--revert" ]; then
    mkdir -p "$MNT"
    mount | grep -q " on $MNT " || mount -o nobrowse -t apfs "$VOLDEV" "$MNT" || die "cannot mount $VOLDEV"
    bless --mount "$MNT" --bootefi --last-sealed-snapshot || die "bless --last-sealed-snapshot failed"
    echo "Done: the next boot uses the last sealed snapshot. Reboot."
    exit 0
fi

csrutil authenticated-root status 2>/dev/null | grep -q disabled || die "authenticated-root is enabled (csr-active-config bit 0x800 needed)"

cdhash() { codesign -dvvv "$1" 2>&1 | awk -F= '/^CDHash=/{print $2}'; }

mkdir -p "$MNT"
if ! mount | grep -q " on $MNT "; then
    mount -o nobrowse -t apfs "$VOLDEV" "$MNT" || die "cannot mount $VOLDEV on $MNT"
fi
touch "$MNT/usr/sbin/.btfix-w" 2>/dev/null && rm -f "$MNT/usr/sbin/.btfix-w" || die "$MNT is mounted read-only"
echo "live volume mounted on $MNT"

TMP=$(mktemp -d /private/var/tmp/btfix.XXXXXX) || die "mktemp"
for f in bluetoothd BlueTool; do
    want=$(cdhash "/usr/sbin/$f"); [ -n "$want" ] || die "/usr/sbin/$f: cannot read its signature"
    cp -X "$MNT/usr/sbin/$f" "$TMP/$f" 2>/dev/null || die "$f: cannot copy it from the live volume"
    codesign -v --strict --all-architectures "$TMP/$f" 2>/dev/null || die "$f: the copy does not pass codesign"
    [ "$(cdhash "$TMP/$f")" = "$want" ] || die "$f: the copy's CDHash differs from the booted file's"
    echo "$f: clean copy from the live volume, signature ok (all architectures), CDHash $want"
    dst="$MNT/usr/sbin/$f"
    cp -X "$TMP/$f" "$dst.btfix" || die "copy $f"
    chown root:wheel "$dst.btfix" && chmod 755 "$dst.btfix" || die "permissions of $f"
    mv -f "$dst.btfix" "$dst" || die "replace $f"
    codesign -v --strict "$dst" 2>/dev/null || die "$dst: signature invalid after the copy"
    echo "$f replaced: $(ls -lO "$dst" | awk '{print $1,$3,$4,$5,$6}')"
done
rm -rf "$TMP"

bless --folder "$MNT/System/Library/CoreServices" --bootefi --create-snapshot || die "bless --create-snapshot failed (the files on the live volume are already replaced; undo: sudo bash $0 --revert)"
echo
echo "Done. A new snapshot is created and selected for the next boot."
echo "Reboot. If Bluetooth was already hung, shut the computer down fully for ~15 seconds instead of a restart."
echo "Undo: sudo bash $0 --revert"
echo "Log: $LOG"
