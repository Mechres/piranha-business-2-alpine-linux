#!/usr/bin/env bash
# STEP 8: Update the SD card with a new kernel + modules (after rebuilding the kernel)
# THIS SCRIPT DOES NOT ERASE THE SD CARD — it only updates zImage/dtb/modules.
# USAGE: sudo bash scripts/80-update-kernel.sh /dev/sdX
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Take CROSS_COMPILE from the environment (under sudo $HOME is /root, so derive paths from the script location)
# shellcheck source=scripts/00-env.sh
if [ -f "$PRJ/scripts/00-env.sh" ]; then source "$PRJ/scripts/00-env.sh"; fi
[ -n "${CROSS_COMPILE:-}" ] || { echo "ERROR: CROSS_COMPILE is not set"; exit 1; }
DEV="${1:-/dev/sdc}"
[ -b "$DEV" ] || { echo "ERROR: $DEV is not a block device"; exit 1; }
P1="${DEV}1"; P2="${DEV}2"
[ -b "$P1" ] || P1="${DEV}p1"; [ -b "$P2" ] || P2="${DEV}p2"

echo ">>> checking the kernel files"
ZIMG="$PRJ/kernel/linux/arch/arm/boot/zImage"
DTB="$PRJ/kernel/linux/arch/arm/boot/dts/allwinner/sun4i-a10-piranha.dtb"
for f in "$ZIMG" "$DTB"; do [ -f "$f" ] || { echo "ERROR: $f does not exist"; exit 1; }; done

echo ">>> updating the boot partition"
M=$(mktemp -d); mount "$P1" "$M"
cp "$ZIMG" "$M/"; cp "$DTB" "$M/"
sync; umount "$M"; rmdir "$M"
echo "  zImage + dtb updated"

echo ">>> updating the modules"
RMOUNT=$(mktemp -d); mount "$P2" "$RMOUNT"
cd "$PRJ/kernel/linux"
KVER="$(make -s ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" kernelrelease)"
make ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$RMOUNT" modules_install 2>&1 | tail -2
# make sure the gt827, g_ether and rtl8192cu modules are present
for m in gt827 g_ether rtl8192cu; do
  find "$RMOUNT/lib/modules" -name "${m}.ko" >/dev/null && echo "  $m.ko: present" || echo "  $m.ko: MISSING"
done
# Generate dependency files against the target rootfs.  chroot cannot run
# ARM binaries on the x86 host, so use the host depmod with -b instead.
depmod -b "$RMOUNT" "$KVER"
echo "  depmod: $KVER"
sync; umount "$RMOUNT"; rmdir "$RMOUNT"

echo "DONE. The new kernel + modules are on the SD card."
