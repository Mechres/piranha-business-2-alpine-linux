#!/usr/bin/env bash
# [LEGACY - Debian/systemd flow; on Alpine use scripts/alpine-public/wifi-service.sh]
# STEP 9: Wi-Fi setup (firmware + automatic connection on the SD card rootfs)
# USAGE: sudo bash scripts/90-wifi-setup.sh /dev/sdX "SSID" "PASSWORD"
# Does NOT touch the boot partition (zImage/dtb are already there).
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV="${1:-/dev/sdc}"; SSID="${2:-}"; PASS="${3:-}"
[ -n "$SSID" ] || { echo "Usage: $0 /dev/sdX SSID PASSWORD"; exit 1; }
[ -b "$DEV" ] || { echo "ERROR: $DEV does not exist"; exit 1; }

ROOTP="${DEV}p2"
# For an SD card at /dev/sdX the partition is /dev/sdX2 (no 'p'); for mmcblk/nvme it is p2
case "$DEV" in
  /dev/mmcblk*|/dev/nvme*) ROOTP="${DEV}p2" ;;
  *) ROOTP="${DEV}2" ;;
esac
M=$(mktemp -d)
echo ">>> mounting the rootfs ($ROOTP)"
mount "$ROOTP" "$M"

echo ">>> copying the firmware"
mkdir -p "$M/lib/firmware/rtlwifi"
cp "$PRJ/rootfs/firmware/"*.bin "$M/lib/firmware/rtlwifi/" 2>/dev/null || {
  echo "ERROR: $PRJ/rootfs/firmware/*.bin missing. Obtain the firmware first."; umount "$M"; exit 1; }

echo ">>> wpa_supplicant configuration"
mkdir -p "$M/etc/wpa_supplicant"
cat > "$M/etc/wpa_supplicant/wpa_supplicant.conf" <<EOF
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=1
country=TR

network={
    ssid="$SSID"
    psk="$PASS"
}
EOF
chmod 600 "$M/etc/wpa_supplicant/wpa_supplicant.conf"

echo ">>> connection script"
cat > "$M/usr/local/bin/wifi-connect.sh" <<'EOF'
#!/bin/bash
# wait until wlan0 appears (at most 15 s)
for i in $(seq 1 15); do
  ip link show wlan0 >/dev/null 2>&1 && break
  sleep 1
done
ip link set wlan0 up
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
sleep 3
# get an IP address (udhcpc if there is no dhclient)
if command -v dhclient >/dev/null; then
  dhclient wlan0
elif command -v udhcpc >/dev/null; then
  udhcpc -i wlan0
fi
EOF
chmod +x "$M/usr/local/bin/wifi-connect.sh"

echo ">>> systemd service"
cat > "$M/etc/systemd/system/wifi-connect.service" <<'EOF'
[Unit]
Description=WiFi Connect (RTL8188CUS)
After=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/wifi-connect.sh
ExecStop=/usr/bin/killall wpa_supplicant

[Install]
WantedBy=multi-user.target
EOF
ln -sf /etc/systemd/system/wifi-connect.service "$M/etc/systemd/system/multi-user.target.wants/wifi-connect.service"

echo ">>> SSH service (should already be enabled, make sure)"
ln -sf /lib/systemd/system/ssh.service "$M/etc/systemd/system/multi-user.target.wants/ssh.service" 2>/dev/null || true

sync; umount "$M"; rmdir "$M"
echo "DONE. Wi-Fi settings are on the SD card: SSID='$SSID'"
echo "Insert it and power on -> it joins the access point -> find the IP with 'ip addr show wlan0'"
echo "Then: ssh piranha@<tablet_ip>"
