#!/bin/bash
# RUN ON THE PC after connecting the tablet over USB.
# Finds the interface name automatically (usb0 / enpXsXuX / ...).
# Usage:  sudo bash setup-pc-usb0.sh
set -e
# The tablet's USB Ethernet gadget: a newly appeared link without an IP address
DEV=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|eth0|wlan|^enp.*f[0-9]' | grep -E '^enp|^usb|^eth' | head -1)
[ -n "$DEV" ] || DEV=$(ip -o link show | awk -F': ' 'NR>1{print $2}' | grep -vE 'lo:|@|vbox|docker|br-' | while read d; do
  ip addr show "$d" 2>/dev/null | grep -q 'inet ' || echo "$d"
done | grep -E 'enp|usb|eth' | head -1)
[ -n "$DEV" ] || { echo "Tablet USB interface not found. Check the output of 'ip link show'."; exit 1; }
echo "Interface: $DEV"
ip link set "$DEV" up
ip addr add 10.0.0.1/24 dev "$DEV"
echo "PC: 10.0.0.1/24  ($DEV)"
echo "Tablet: 10.0.0.2"
echo
echo "SSH:"
echo "  ssh piranha@10.0.0.2"
echo
echo "Test:"
ping -c1 10.0.0.2 && echo "CONNECTION OK" || echo "Ping failed - make sure usb0 is up on the tablet"
