#!/usr/bin/env bash
# [LEGACY - Debian flow, superseded by 50-sdcard-alpine.sh]
# STEP 6: Prepare and write the SD card.  *** THIS SCRIPT ERASES THE SD CARD ***
# Usage: sudo bash 50-sdcard.sh /dev/sdX
set -euo pipefail
# Derive PRJ from the script's own location.
# (We do not use $HOME: under sudo it is /root and the paths would break.)
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Project directory: $PRJ"
[ -n "${1:-}" ] || { echo "Usage: $0 /dev/sdX"; exit 1; }
DEV="$1"
RFS="$PRJ/rootfs/debian"

# --- Check the required files first (do not erase the card for nothing) ---
UBOOT="$PRJ/uboot/u-boot/u-boot-sunxi-with-spl.bin"
ZIMG="$PRJ/kernel/linux/arch/arm/boot/zImage"
DTB="$PRJ/kernel/linux/arch/arm/boot/dts/allwinner/sun4i-a10-piranha.dtb"
MKIMAGE="$PRJ/uboot/u-boot/tools/mkimage"
for f in "$UBOOT" "$ZIMG" "$DTB" "$MKIMAGE"; do
  [ -f "$f" ] || { echo "ERROR: missing file: $f"; exit 1; }
done
[ -d "$RFS" ] || { echo "ERROR: rootfs missing: $RFS  (run bash scripts/40-rootfs.sh first)"; exit 1; }
echo "All input files are present ✓"

# --- Safety checks ---
[ -b "$DEV" ] || { echo "ERROR: $DEV is not a block device"; exit 1; }
case "$DEV" in *[0-9]) echo "ERROR: give the whole disk, not a partition (e.g. /dev/sde)"; exit 1;; esac
RM=$(lsblk -ndo RM "$DEV"); SIZE=$(lsblk -ndo SIZE "$DEV"); MODEL=$(lsblk -ndo MODEL "$DEV" || true)
echo "Target: $DEV  size=$SIZE  removable=$RM  model=$MODEL"
[ "$RM" = "1" ] || { echo "ERROR: $DEV is not removable! Aborting to protect internal disks."; exit 1; }
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
#
# The ORDER of console= matters: the last one becomes /dev/console (the primary).
# No UART is soldered, so tty0 (the screen) must come LAST —
# that way the boot messages show on the panel and we can diagnose problems.
# ttyS0 stays in the list: it works automatically if a UART is soldered later.
cat > "$M/boot.cmd" <<'EOF'
setenv bootargs console=ttyS0,115200 console=tty0 root=/dev/mmcblk0p2 rootwait rw panic=10 loglevel=7 ignore_loglevel consoleblank=0 fbcon=map:0
load mmc 0:1 0x43000000 sun4i-a10-piranha.dtb
load mmc 0:1 0x42000000 zImage
bootz 0x42000000 - 0x43000000
EOF
"$MKIMAGE" -C none -A arm -T script -d "$M/boot.cmd" "$M/boot.scr"
sync; umount "$M"

echo ">>> copying the rootfs (this takes a while)"
mount "$P2" "$M"
rsync -aHAX --numeric-ids --info=progress2 "$RFS"/ "$M"/

# --- fix leftovers from the podman export ---
# podman bind-mounts /etc/hostname, /etc/hosts and /etc/resolv.conf;
# during the export they come back with the container values or end up empty.
echo ">>> fixing the container leftovers"
echo piranha > "$M/etc/hostname"
cat > "$M/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	piranha
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF
# a static DNS configuration is fine when systemd-resolved is not used
cat > "$M/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
rm -f "$M/.dockerenv" "$M/run/.containerenv" 2>/dev/null || true
echo "  hostname=$(cat "$M/etc/hostname")  hosts=$(wc -l < "$M/etc/hosts") lines"

sync; umount "$M"; rmdir "$M"

echo; echo "DONE. SD card ready: $DEV"
echo "Boot: insert the SD card into the tablet and power it on. If the screen stays dark, read the SD card on the PC:"
echo "  /var/log/journal and the dmesg logs are there."
