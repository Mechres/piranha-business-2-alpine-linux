#!/usr/bin/env bash
# STEP 3: Build U-Boot (u-boot-sunxi-with-spl.bin + tools/mkimage) from uboot/piranha_a10_defconfig.
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PRJ/scripts/00-env.sh"
UBOOT_SRC="${UBOOT_SRC:-$PRJ/uboot/u-boot}"
[ -f "$UBOOT_SRC/Makefile" ] || { echo "ERROR: no U-Boot tree at $UBOOT_SRC (run scripts/fetch-sources.sh)"; exit 1; }
cp "$PRJ/uboot/piranha_a10_defconfig" "$UBOOT_SRC/configs/piranha_a10_defconfig"
cd "$UBOOT_SRC"
make piranha_a10_defconfig
make $JOBS
ls -l u-boot-sunxi-with-spl.bin tools/mkimage
