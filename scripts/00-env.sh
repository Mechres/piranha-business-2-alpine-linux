#!/usr/bin/env bash
# Piranha Business II Tab (Allwinner A10 / sun4i) — common environment
# Usage: source scripts/00-env.sh
#
# Cross toolchain, in order of preference:
#   1. TOOLCHAIN_DIR=/path/to/toolchain/bin   (explicit override)
#   2. $PRJ/toolchain/armv7-eabihf--glibc--stable-2024.05-1/bin   (scripts/fetch-sources.sh downloads it)
#   3. an ARMv7 cross compiler already on PATH (e.g. gcc-arm-linux-gnueabihf)
# Derive PRJ from the script's own location ($HOME is /root under sudo)
PRJ_DERIVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PRJ="$PRJ_DERIVED"
LOCAL_TC="$PRJ/toolchain/armv7-eabihf--glibc--stable-2024.05-1/bin"
if [ -n "${TOOLCHAIN_DIR:-}" ]; then
    export TC="$TOOLCHAIN_DIR"
elif [ -d "$LOCAL_TC" ]; then
    export TC="$LOCAL_TC"
fi
[ -n "${TC:-}" ] && export PATH="$TC:$PATH"
export ARCH=arm
if [ -z "${CROSS_COMPILE:-}" ]; then
    for p in arm-buildroot-linux-gnueabihf- arm-linux-gnueabihf- arm-none-linux-gnueabihf-; do
        if command -v "${p}gcc" >/dev/null 2>&1; then CROSS_COMPILE="$p"; break; fi
    done
fi
export CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabihf-}"
export JOBS="-j$(nproc)"
echo "PRJ=$PRJ"
if command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
    echo -n "cross gcc: "; "${CROSS_COMPILE}gcc" --version | head -1
else
    echo "WARNING: no ARMv7 cross toolchain found (looked for ${CROSS_COMPILE}gcc)."
    echo "         Run scripts/fetch-sources.sh, set TOOLCHAIN_DIR, or install gcc-arm-linux-gnueabihf."
fi
