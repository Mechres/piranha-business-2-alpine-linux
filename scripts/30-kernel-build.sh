#!/usr/bin/env bash
# ADIM 4: Mainline kernel derle (sunxi_defconfig + ekstralar)
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Derive the project path from this script; sudo changes HOME to /root.
# shellcheck source=scripts/00-env.sh
source "$PRJ/scripts/00-env.sh"
cd "$PRJ/kernel/linux"

make sunxi_defconfig

# Ekstra config (crane/piranha için)
cat >> .config <<'EOF'
# --- Display / panel (starry,kr070pe2t) ---
CONFIG_DRM_SUN4I=y
CONFIG_DRM_SUN4I_BACKEND=y
CONFIG_DRM_PANEL_SIMPLE=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_FB_SIMPLE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y
CONFIG_LOGO=y
# --- PMIC / power ---
CONFIG_AXP20X_ADC=y
CONFIG_REGULATOR_AXP20X=y
CONFIG_BATTERY_AXP20X=y
CONFIG_CHARGER_AXP20X=y
# --- Touch (GT827 is provided as an out-of-tree board driver) ---
CONFIG_TOUCHSCREEN_EDT_FT5X06=y
CONFIG_TOUCHSCREEN_GOODIX=y
CONFIG_INPUT_TOUCHSCREEN=y
CONFIG_HID_MULTITOUCH=y
CONFIG_USB_HID=y
# --- WiFi RTL8188CUS ---
CONFIG_WLAN=y
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_RTL8192CU=m
CONFIG_RTLWIFI=m
CONFIG_RTLWIFI_USB=m
# --- USB / MMC ---
CONFIG_MMC_SUNXI=y
CONFIG_USB_EHCI_HCD=y
CONFIG_USB_OHCI_HCD=y
CONFIG_USB_MUSB_SUNXI=y
CONFIG_USB_MUSB_HOST=y
CONFIG_USB_STORAGE=y
CONFIG_USB_SERIAL=y
# --- GPU (Mali-400) ---
CONFIG_DRM_LIMA=y
# --- Audio ---
CONFIG_SND_SUN4I_CODEC=y
# --- FS ---
CONFIG_EXT4_FS=y
CONFIG_VFAT_FS=y
CONFIG_NLS_CODEPAGE_437=y
CONFIG_NLS_ISO8859_1=y
CONFIG_NLS_UTF8=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
EOF

make olddefconfig
echo "=== BUILDING zImage + dtbs ==="
make -j"$(nproc)" zImage dtbs modules 2>&1 | tail -30
ls -l arch/arm/boot/zImage arch/arm/boot/dts/allwinner/sun4i-a10-topwise-a721.dtb
echo KERNEL_BUILD_DONE
