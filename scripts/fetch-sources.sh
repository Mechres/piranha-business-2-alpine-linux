#!/usr/bin/env bash
# STEP 1: Download the external inputs that are not part of this repository:
#   - Bootlin armv7 cross toolchain  -> toolchain/
#   - mainline Linux (pinned commit) -> kernel/linux
#   - mainline U-Boot                -> uboot/u-boot
# Safe to re-run: existing directories are left alone. Set SKIP_TOOLCHAIN=1 if you
# use your own cross compiler (see 00-env.sh).
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TC_NAME="armv7-eabihf--glibc--stable-2024.05-1"
TC_URL="https://toolchains.bootlin.com/downloads/releases/toolchains/armv7-eabihf/tarballs/$TC_NAME.tar.xz"
KERNEL_URL="https://github.com/torvalds/linux.git"
KERNEL_REV="${KERNEL_REV:-cb8a75eec0877810b50aa1c5a833f929525cd2ee}"   # the commit this port was built and tested on
UBOOT_URL="https://source.denx.de/u-boot/u-boot.git"
UBOOT_REV="${UBOOT_REV:-527115ef}"                                      # tested; falls back to the branch head

if [ -z "${SKIP_TOOLCHAIN:-}" ] && [ ! -d "$PRJ/toolchain/$TC_NAME" ]; then
    echo ">>> downloading the Bootlin toolchain"
    mkdir -p "$PRJ/toolchain"
    curl -fL "$TC_URL" | tar -xJ -C "$PRJ/toolchain"
fi

if [ ! -d "$PRJ/kernel/linux/.git" ]; then
    echo ">>> fetching Linux $KERNEL_REV (shallow)"
    mkdir -p "$PRJ/kernel/linux"
    git -C "$PRJ/kernel/linux" init -q
    git -C "$PRJ/kernel/linux" remote add origin "$KERNEL_URL"
    git -C "$PRJ/kernel/linux" fetch --depth 1 origin "$KERNEL_REV"
    git -C "$PRJ/kernel/linux" checkout -q FETCH_HEAD
fi

if [ ! -d "$PRJ/uboot/u-boot/.git" ]; then
    echo ">>> cloning U-Boot"
    git clone "$UBOOT_URL" "$PRJ/uboot/u-boot"
    git -C "$PRJ/uboot/u-boot" checkout -q "$UBOOT_REV" 2>/dev/null \
        || echo "WARNING: U-Boot $UBOOT_REV not found, staying on the branch head"
fi

echo "DONE. Next: scripts/25-uboot-build.sh and scripts/30-kernel-build.sh"
