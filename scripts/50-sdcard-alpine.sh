#!/usr/bin/env bash
# STEP 6b (Alpine): prepare and write the SD card.  *** THIS SCRIPT ERASES THE SD CARD ***
# Usage: sudo bash 50-sdcard-alpine.sh /dev/sdX
#
# Differences from the Debian-era 50-sdcard.sh:
#  - rootfs = rootfs/alpine (musl/OpenRC)
#  - no systemd: the OpenRC services are already part of the rootfs
#  - boot.cmd: console=tty0 comes last so it becomes the primary console (no UART is soldered)
#  - modules-load.d and conf.d/net.usb0 are set up for Alpine
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Project directory: $PRJ"
[ -n "${1:-}" ] || { echo "Usage: $0 /dev/sdX"; exit 1; }
DEV="$1"
RFS="$PRJ/rootfs/alpine"

# --- Required files ---
UBOOT="$PRJ/uboot/u-boot/u-boot-sunxi-with-spl.bin"
ZIMG="$PRJ/kernel/linux/arch/arm/boot/zImage"
DTB="$PRJ/kernel/linux/arch/arm/boot/dts/allwinner/sun4i-a10-piranha.dtb"
MKIMAGE="$PRJ/uboot/u-boot/tools/mkimage"
for f in "$UBOOT" "$ZIMG" "$DTB" "$MKIMAGE"; do
  [ -f "$f" ] || { echo "ERROR: missing file: $f"; exit 1; }
done
[ -d "$RFS" ] || { echo "ERROR: Alpine rootfs missing: $RFS  (run scripts/45-alpine-stage1.sh and 45-alpine-stage2.sh first)"; exit 1; }
echo "All input files are present"

# --- Safety checks ---
[ -b "$DEV" ] || { echo "ERROR: $DEV is not a block device"; exit 1; }
case "$DEV" in *[0-9]) echo "ERROR: give the whole disk, not a partition (e.g. /dev/sde)"; exit 1;; esac
RM=$(lsblk -ndo RM "$DEV"); SIZE=$(lsblk -ndo SIZE "$DEV"); MODEL=$(lsblk -ndo MODEL "$DEV" || true)
echo "Target: $DEV  size=$SIZE  removable=$RM  model=$MODEL"
[ "$RM" = "1" ] || { echo "ERROR: $DEV is not removable! Aborting."; exit 1; }
SZB=$(blockdev --getsize64 "$DEV")
[ "$SZB" -lt 137438953472 ] || { echo "ERROR: larger than 128 GB — possibly the wrong disk, aborting."; exit 1; }
echo; echo "!!! ALL DATA ON $DEV WILL BE ERASED !!!"
read -rp "Type 'WRITE' to continue: " OK
[ "$OK" = "WRITE" ] || { echo "aborted"; exit 1; }

echo ">>> unmounting mounted partitions"
for p in "$DEV"?*; do umount "$p" 2>/dev/null || true; done

echo ">>> partitioning (p1 = 64 MB FAT16 boot, p2 = rest ext4)"
wipefs -a "$DEV"
sfdisk "$DEV" <<'EOF'
label: dos
unit: sectors
2048,131072,c,*
133120,,83
EOF
partprobe "$DEV"; sleep 2
P1="${DEV}1"; P2="${DEV}2"
[ -b "$P1" ] || P1="${DEV}p1"; [ -b "$P2" ] || P2="${DEV}p2"

mkfs.vfat -F16 -n PIRBOOT "$P1"
mkfs.ext4 -F -L pirroot "$P2"

echo ">>> U-Boot (sector 8, does NOT touch the NAND)"
dd if="$UBOOT" of="$DEV" bs=1k seek=8 conv=fsync

echo ">>> boot partition"
M=$(mktemp -d); mount "$P1" "$M"
cp "$ZIMG" "$M/"
cp "$DTB" "$M/"
cp "$PRJ/kernel/linux/arch/arm/boot/dts/allwinner/sun4i-a10-topwise-a721.dtb" "$M/" || true

# boot.cmd -> boot.scr
# Alpine/OpenRC. console=tty0 (the screen) must come LAST so it becomes the primary
# console and the boot messages show on the panel (no UART is soldered).
cat > "$M/boot.cmd" <<'EOF'
setenv bootargs console=tty0 console=ttyS0,115200 root=/dev/mmcblk0p2 rootwait rw panic=10 loglevel=7 ignore_loglevel consoleblank=0 fbcon=map:0
load mmc 0:1 0x43000000 sun4i-a10-piranha.dtb
load mmc 0:1 0x42000000 zImage
bootz 0x42000000 - 0x43000000
EOF
"$MKIMAGE" -C none -A arm -T script -d "$M/boot.cmd" "$M/boot.scr"
sync; umount "$M"

echo ">>> copying the rootfs (this takes a while)"
mount "$P2" "$M"
rsync -aHAX --numeric-ids --info=progress2 "$RFS"/ "$M"/

# --- Fix leftovers from the container export ---
echo ">>> fixing hostname/hosts/dns"
echo piranha > "$M/etc/hostname"
cat > "$M/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	piranha
::1		localhost ip6-localhost ip6-loopback
EOF
cat > "$M/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# The OpenRC runlevel symlinks come from the rootfs; running rc-update again
# in a chroot is not needed (modules-load.d already exists).
echo ">>> verifying the OpenRC services"
ls "$M/etc/runlevels/default/" 2>/dev/null | tr '\n' ' ' || echo "(no runlevel)"
echo
echo "  sshd:     $(ls "$M/etc/runlevels/default/sshd" 2>/dev/null && echo OK || echo MISSING)"
echo "  net.usb0: $(ls "$M/etc/runlevels/default/net.usb0" 2>/dev/null && echo OK || echo MISSING)"

sync; umount "$M"; rmdir "$M"

echo; echo "DONE. SD card ready: $DEV"
echo "Boot: insert the SD card into the tablet and power it on. If the screen stays dark, read the SD card on the PC:"
echo "  /var/log/dmesg has the boot log."
echo "SSH: ssh piranha@10.0.0.2  (on the PC: ip addr add 10.0.0.1/24 dev <usb-ethernet-interface>)"
