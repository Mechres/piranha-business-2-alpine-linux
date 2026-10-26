#!/usr/bin/env bash
# Piranha Business II Tab (Allwinner A10 / sun4i) — common environment
# Usage: source scripts/00-env.sh
# Derive PRJ from the script's own location ($HOME is /root under sudo)
PRJ_DERIVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PRJ="$PRJ_DERIVED"
export TC="$PRJ/toolchain/armv7-eabihf--glibc--stable-2024.05-1/bin"
export PATH="$TC:$PATH"
export ARCH=arm
export CROSS_COMPILE=arm-buildroot-linux-gnueabihf-
export JOBS="-j$(nproc)"
echo "PRJ=$PRJ"
echo -n "cross gcc: "; ${CROSS_COMPILE}gcc --version | head -1
