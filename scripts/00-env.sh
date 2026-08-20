#!/usr/bin/env bash
# Piranha Business II Tab (Allwinner A10 / sun4i) — ortak ortam
# Kullanım: source ~/projeler/piranha-a10/scripts/00-env.sh
# PRJ'yi script'in KENDI konumundan turet ($HOME sudo altinda /root olur)
PRJ_DERIVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PRJ="$PRJ_DERIVED"
export TC="$PRJ/toolchain/armv7-eabihf--glibc--stable-2024.05-1/bin"
export PATH="$TC:$PATH"
export ARCH=arm
export CROSS_COMPILE=arm-buildroot-linux-gnueabihf-
export JOBS="-j$(nproc)"
echo "PRJ=$PRJ"
echo -n "cross gcc: "; ${CROSS_COMPILE}gcc --version | head -1
