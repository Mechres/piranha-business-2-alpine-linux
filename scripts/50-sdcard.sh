#!/usr/bin/env bash
# ADIM 6: SD kartı hazırla ve yaz.  *** BU SCRIPT SD KARTI SİLER ***
# Kullanım: sudo bash 50-sdcard.sh /dev/sdX
set -euo pipefail
# PRJ'yi script'in KENDİ konumundan türet.
# ($HOME kullanmıyoruz: sudo altında $HOME=/root olur ve yollar bozulur.)
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Proje dizini: $PRJ"
[ -n "${1:-}" ] || { echo "Kullanım: $0 /dev/sdX"; exit 1; }
DEV="$1"
RFS="$PRJ/rootfs/debian"

# --- Gerekli dosyalar önceden kontrol edilsin (kartı boşuna silmeyelim) ---
UBOOT="$PRJ/uboot/u-boot/u-boot-sunxi-with-spl.bin"
ZIMG="$PRJ/kernel/linux/arch/arm/boot/zImage"
DTB="$PRJ/kernel/linux/arch/arm/boot/dts/allwinner/sun4i-a10-piranha.dtb"
MKIMAGE="$PRJ/uboot/u-boot/tools/mkimage"
for f in "$UBOOT" "$ZIMG" "$DTB" "$MKIMAGE"; do
  [ -f "$f" ] || { echo "HATA: eksik dosya: $f"; exit 1; }
done
[ -d "$RFS" ] || { echo "HATA: rootfs yok: $RFS  (önce bash scripts/40-rootfs.sh)"; exit 1; }
echo "Tüm girdi dosyaları mevcut ✓"

# --- Güvenlik kontrolleri ---
[ -b "$DEV" ] || { echo "HATA: $DEV blok aygıt değil"; exit 1; }
case "$DEV" in *[0-9]) echo "HATA: bölüm değil, tüm diski ver (örn /dev/sde)"; exit 1;; esac
RM=$(lsblk -ndo RM "$DEV"); SIZE=$(lsblk -ndo SIZE "$DEV"); MODEL=$(lsblk -ndo MODEL "$DEV" || true)
echo "Hedef: $DEV  boyut=$SIZE  çıkarılabilir=$RM  model=$MODEL"
[ "$RM" = "1" ] || { echo "HATA: $DEV çıkarılabilir değil! İç diski korumak için iptal."; exit 1; }
SZB=$(blockdev --getsize64 "$DEV")
[ "$SZB" -lt 137438953472 ] || { echo "HATA: 128GB'dan büyük — yanlış disk olabilir, iptal."; exit 1; }
echo; echo "!!! $DEV ÜZERİNDEKİ TÜM VERİ SİLİNECEK !!!"
read -rp "Devam için 'YAZ' yaz: " OK
[ "$OK" = "YAZ" ] || { echo "iptal"; exit 1; }

echo ">>> bağlı bölümleri ayır"
for p in "$DEV"?*; do umount "$p" 2>/dev/null || true; done

echo ">>> bölümleme (p1=64MB FAT16 boot, p2=kalan ext4)"
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

echo ">>> U-Boot (sektör 8, NAND'a DOKUNMAZ)"
dd if="$UBOOT" of="$DEV" bs=1k seek=8 conv=fsync

echo ">>> boot bölümü"
M=$(mktemp -d); mount "$P1" "$M"
cp "$ZIMG" "$M/"
cp "$DTB" "$M/"
cp "$PRJ/kernel/linux/arch/arm/boot/dts/allwinner/sun4i-a10-topwise-a721.dtb" "$M/" || true

# boot.cmd -> boot.scr
#
# console SIRASI ÖNEMLİ: son yazılan /dev/console olur (birincil).
# UART'ımız lehimli DEĞİL, o yüzden tty0 (ekran) SONDA olmalı —
# böylece boot mesajları panele düşer ve teşhis edebiliriz.
# ttyS0 yine listede: ileride UART lehimlersen otomatik çalışır.
cat > "$M/boot.cmd" <<'EOF'
setenv bootargs console=ttyS0,115200 console=tty0 root=/dev/mmcblk0p2 rootwait rw panic=10 loglevel=7 ignore_loglevel consoleblank=0 fbcon=map:0
load mmc 0:1 0x43000000 sun4i-a10-piranha.dtb
load mmc 0:1 0x42000000 zImage
bootz 0x42000000 - 0x43000000
EOF
"$MKIMAGE" -C none -A arm -T script -d "$M/boot.cmd" "$M/boot.scr"
sync; umount "$M"

echo ">>> rootfs kopyalanıyor (uzun sürer)"
mount "$P2" "$M"
rsync -aHAX --numeric-ids --info=progress2 "$RFS"/ "$M"/

# --- podman export artıklarını düzelt ---
# podman /etc/hostname, /etc/hosts, /etc/resolv.conf'u bind-mount eder;
# export sırasında bunlar konteyner değerleriyle döner veya boşalır.
echo ">>> konteyner artıkları düzeltiliyor"
echo piranha > "$M/etc/hostname"
cat > "$M/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	piranha
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF
# systemd-resolved kullanmıyorsak sabit DNS iyi
cat > "$M/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
rm -f "$M/.dockerenv" "$M/run/.containerenv" 2>/dev/null || true
echo "  hostname=$(cat "$M/etc/hostname")  hosts=$(wc -l < "$M/etc/hosts") satır"

sync; umount "$M"; rmdir "$M"

echo; echo "TAMAM. SD hazır: $DEV"
echo "Boot: SD'yi tablete tak, gücü ver. Ekran gelmezse SD'yi PC'de oku:"
echo "  /var/log/journal  ve  dmesg  logları orada."
