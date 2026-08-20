#!/usr/bin/env bash
# ADIM 8: Yeni kernel + modulleri SD'ye guncelle (kernel yeniden derlendikten sonra)
# BU SCRIPT SD KARTI SILMEZ — sadece zImage/dtb/modulleri gunceller.
# KULLANIM: sudo bash scripts/80-update-kernel.sh /dev/sdc
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# CROSS_COMPILE'i env'den al (sudo altinda $HOME=/root oldugu icin script konumundan)
# shellcheck source=scripts/00-env.sh
if [ -f "$PRJ/scripts/00-env.sh" ]; then source "$PRJ/scripts/00-env.sh"; fi
[ -n "${CROSS_COMPILE:-}" ] || { echo "HATA: CROSS_COMPILE tanimsiz"; exit 1; }
DEV="${1:-/dev/sdc}"
[ -b "$DEV" ] || { echo "HATA: $DEV blok aygit degil"; exit 1; }
P1="${DEV}1"; P2="${DEV}2"
[ -b "$P1" ] || P1="${DEV}p1"; [ -b "$P2" ] || P2="${DEV}p2"

echo ">>> kernel dosyalari kontrol"
ZIMG="$PRJ/kernel/linux/arch/arm/boot/zImage"
DTB="$PRJ/kernel/linux/arch/arm/boot/dts/allwinner/sun4i-a10-piranha.dtb"
for f in "$ZIMG" "$DTB"; do [ -f "$f" ] || { echo "HATA: $f yok"; exit 1; }; done

echo ">>> boot bolumu guncelle"
M=$(mktemp -d); mount "$P1" "$M"
cp "$ZIMG" "$M/"; cp "$DTB" "$M/"
sync; umount "$M"; rmdir "$M"
echo "  zImage + dtb guncellendi"

echo ">>> moduller guncelle"
RMOUNT=$(mktemp -d); mount "$P2" "$RMOUNT"
cd "$PRJ/kernel/linux"
KVER="$(make -s ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" kernelrelease)"
make ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$RMOUNT" modules_install 2>&1 | tail -2
# gt827 + g_ether + rtl8192cu modullerinin varligi
for m in gt827 g_ether rtl8192cu; do
  find "$RMOUNT/lib/modules" -name "${m}.ko" >/dev/null && echo "  $m.ko: VAR" || echo "  $m.ko: YOK"
done
# Generate dependency files against the target rootfs.  chroot cannot run
# ARM binaries on the x86 host, so use the host depmod with -b instead.
depmod -b "$RMOUNT" "$KVER"
echo "  depmod: $KVER"
sync; umount "$RMOUNT"; rmdir "$RMOUNT"

echo "TAMAM. Yeni kernel + moduller SD'de."
