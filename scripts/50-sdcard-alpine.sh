#!/usr/bin/env bash
# ADIM 6b (Alpine): SD kart hazirla + yaz.  *** BU SCRIPT SD KARTI SILER ***
# Kullanim: sudo bash 50-sdcard-alpine.sh /dev/sdX
#
# Farklar (Debian 50-sdcard.sh'e gore):
#  - rootfs = rootfs/alpine (musl/OpenRC)
#  - systemd yok: /etc/systemd silinir, OpenRC servisleri zaten rootfs'te
#  - boot.cmd: systemd yok, console=tty0 oncelikli (UART lehimli degil)
#  - modules-load.d + conf.d net.usb0 Alpine'a gore ayarli
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Proje dizini: $PRJ"
[ -n "${1:-}" ] || { echo "Kullanim: $0 /dev/sdX"; exit 1; }
DEV="$1"
RFS="$PRJ/rootfs/alpine"

# --- Gerekli dosyalar ---
UBOOT="$PRJ/uboot/u-boot/u-boot-sunxi-with-spl.bin"
ZIMG="$PRJ/kernel/linux/arch/arm/boot/zImage"
DTB="$PRJ/kernel/linux/arch/arm/boot/dts/allwinner/sun4i-a10-piranha.dtb"
MKIMAGE="$PRJ/uboot/u-boot/tools/mkimage"
for f in "$UBOOT" "$ZIMG" "$DTB" "$MKIMAGE"; do
  [ -f "$f" ] || { echo "HATA: eksik dosya: $f"; exit 1; }
done
[ -d "$RFS" ] || { echo "HATA: alpine rootfs yok: $RFS  (once bash scripts/45-alpine-rootfs.sh)"; exit 1; }
echo "Tum girdi dosyalari mevcut"

# --- Guvenlik ---
[ -b "$DEV" ] || { echo "HATA: $DEV blok aygit degil"; exit 1; }
case "$DEV" in *[0-9]) echo "HATA: bolum degil, tum diski ver (ornek /dev/sde)"; exit 1;; esac
RM=$(lsblk -ndo RM "$DEV"); SIZE=$(lsblk -ndo SIZE "$DEV"); MODEL=$(lsblk -ndo MODEL "$DEV" || true)
echo "Hedef: $DEV  boyut=$SIZE  cikarilabilir=$RM  model=$MODEL"
[ "$RM" = "1" ] || { echo "HATA: $DEV cikarilabilir degil! Iptal."; exit 1; }
SZB=$(blockdev --getsize64 "$DEV")
[ "$SZB" -lt 137438953472 ] || { echo "HATA: 128GB'dan buyuk — yanlis disk olabilir, iptal."; exit 1; }
echo; echo "!!! $DEV UZERINDEKI TUM VERI SILINECEK !!!"
read -rp "Devam icin 'YAZ' yaz: " OK
[ "$OK" = "YAZ" ] || { echo "iptal"; exit 1; }

echo ">>> bagli bolumleri ayir"
for p in "$DEV"?*; do umount "$p" 2>/dev/null || true; done

echo ">>> bolumleme (p1=64MB FAT16 boot, p2=kalan ext4)"
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

echo ">>> U-Boot (sektor 8, NAND'a DOKUNMAZ)"
dd if="$UBOOT" of="$DEV" bs=1k seek=8 conv=fsync

echo ">>> boot bolumu"
M=$(mktemp -d); mount "$P1" "$M"
cp "$ZIMG" "$M/"
cp "$DTB" "$M/"
cp "$PRJ/kernel/linux/arch/arm/boot/dts/allwinner/sun4i-a10-topwise-a721.dtb" "$M/" || true

# boot.cmd -> boot.scr
# Alpine/OpenRC: systemd yok. console=tty0 (ekran) SONDA olmali ki boot
# mesajlari panele dussun (UART lehimli degil).
cat > "$M/boot.cmd" <<'EOF'
setenv bootargs console=tty0 console=ttyS0,115200 root=/dev/mmcblk0p2 rootwait rw panic=10 loglevel=7 ignore_loglevel consoleblank=0 fbcon=map:0
load mmc 0:1 0x43000000 sun4i-a10-piranha.dtb
load mmc 0:1 0x42000000 zImage
bootz 0x42000000 - 0x43000000
EOF
"$MKIMAGE" -C none -A arm -T script -d "$M/boot.cmd" "$M/boot.scr"
sync; umount "$M"

echo ">>> rootfs kopyalaniyor (uzun surer)"
mount "$P2" "$M"
rsync -aHAX --numeric-ids --info=progress2 "$RFS"/ "$M"/

# --- Alpine artiklari duzelt ---
echo ">>> hostname/hosts/dns duzelt"
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

# OpenRC runlevel symlink'leri rootfs'ten geldi; chroot icinde rc-update
# tekrar calistir (modules-load.d -> /etc/modules-load.d zaten var)
echo ">>> OpenRC servisleri dogrula"
ls "$M/etc/runlevels/default/" 2>/dev/null | tr '\n' ' ' || echo "(runlevel yok)"
echo
echo "  sshd:   $(ls "$M/etc/runlevels/default/sshd" 2>/dev/null && echo OK || echo YOK)"
echo "  net.usb0: $(ls "$M/etc/runlevels/default/net.usb0" 2>/dev/null && echo OK || echo YOK)"

sync; umount "$M"; rmdir "$M"

echo; echo "TAMAM. SD hazir: $DEV"
echo "Boot: SD'yi tablete tak, gucu ver. Ekran gelmezse SD'yi PC'de oku:"
echo "  /var/log/dmesg  veya  tablet boot loglari orada."
echo "SSH: ssh piranha@10.0.0.2  (PC'de: ip addr add 10.0.0.1/24 dev enp...; usb0)"
