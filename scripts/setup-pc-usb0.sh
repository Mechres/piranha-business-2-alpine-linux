#!/bin/bash
# PC TARAFINDA: tableti USB ile bagladiktan sonra calistir.
# Arayuz adini otomatik bulur (usb0 / enpXsXuX / vs).
# Kullanim:  sudo bash setup-pc-usb0.sh
set -e
# Tablet bagli USB-Ethernet gadget'i: yeni cikan, IP'siz link
DEV=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|eth0|wlan|^enp.*f[0-9]' | grep -E '^enp|^usb|^eth' | head -1)
[ -n "$DEV" ] || DEV=$(ip -o link show | awk -F': ' 'NR>1{print $2}' | grep -vE 'lo:|@|vbox|docker|br-' | while read d; do
  ip addr show "$d" 2>/dev/null | grep -q 'inet ' || echo "$d"
done | grep -E 'enp|usb|eth' | head -1)
[ -n "$DEV" ] || { echo "Tablet USB arayuzu bulunamadi. 'ip link show' ciktisini getir."; exit 1; }
echo "Arayuz: $DEV"
ip link set "$DEV" up
ip addr add 10.0.0.1/24 dev "$DEV"
echo "PC: 10.0.0.1/24  ($DEV)"
echo "Tablet: 10.0.0.2"
echo
echo "SSH:"
echo "  ssh piranha@10.0.0.2"
echo
echo "Test:"
ping -c1 10.0.0.2 && echo "BAGLANTI OK" || echo "Ping basarisiz - tablette usb0 up oldugundan emin ol"
