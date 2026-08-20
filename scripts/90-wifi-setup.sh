#!/usr/bin/env bash
# ADIM 9: WiFi kurulumu (SD rootfs'e firmware + otomatik baglanti)
# KULLANIM: sudo bash scripts/90-wifi-setup.sh /dev/sdc "SSID" "SIFRE"
# Boot bolumune DOKUNMAZ (zImage/dtb zaten hazir).
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV="${1:-/dev/sdc}"; SSID="${2:-}"; PASS="${3:-}"
[ -n "$SSID" ] || { echo "Kullanim: $0 /dev/sdc SSID SIFRE"; exit 1; }
[ -b "$DEV" ] || { echo "HATA: $DEV yok"; exit 1; }

ROOTP="${DEV}p2"
# SD kart /dev/sdX ise partition /dev/sdX2 (p yok); mmcblk/nvme ise p2
case "$DEV" in
  /dev/mmcblk*|/dev/nvme*) ROOTP="${DEV}p2" ;;
  *) ROOTP="${DEV}2" ;;
esac
M=$(mktemp -d)
echo ">>> rootfs baglaniyor ($ROOTP)"
mount "$ROOTP" "$M"

echo ">>> firmware kopyalaniyor"
mkdir -p "$M/lib/firmware/rtlwifi"
cp "$PRJ/rootfs/firmware/"*.bin "$M/lib/firmware/rtlwifi/" 2>/dev/null || {
  echo "HATA: $PRJ/rootfs/firmware/*.bin yok. Once firmware alinmali."; umount "$M"; exit 1; }

echo ">>> wpa_supplicant yapilandirmasi"
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

echo ">>> baglanti scripti"
cat > "$M/usr/local/bin/wifi-connect.sh" <<'EOF'
#!/bin/bash
# wlan0 cikana kadar bekle (en fazla 15 sn)
for i in $(seq 1 15); do
  ip link show wlan0 >/dev/null 2>&1 && break
  sleep 1
done
ip link set wlan0 up
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
sleep 3
# IP al (dhclient yoksa udhcpc)
if command -v dhclient >/dev/null; then
  dhclient wlan0
elif command -v udhcpc >/dev/null; then
  udhcpc -i wlan0
fi
EOF
chmod +x "$M/usr/local/bin/wifi-connect.sh"

echo ">>> systemd servisi"
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

echo ">>> SSH servisi (zaten acik olmali, emin olalim)"
ln -sf /lib/systemd/system/ssh.service "$M/etc/systemd/system/multi-user.target.wants/ssh.service" 2>/dev/null || true

sync; umount "$M"; rmdir "$M"
echo "TAMAM. WiFi ayarlari SD'de: SSID='$SSID'"
echo "Tableti tak, ac -> AP'ye baglanir -> 'ip addr show wlan0' ile IP ogren"
echo "Sonra: ssh piranha@<tablet_ip>"
