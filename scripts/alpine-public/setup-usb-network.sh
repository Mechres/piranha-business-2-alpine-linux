#!/usr/bin/env bash
set -euo pipefail

DEV="${1:-}"
[ -n "$DEV" ] || {
    echo "Kullanim: sudo $0 <usb-network-interface>"
    echo "Ornek:  sudo $0 enp15s0f3u1"
    exit 2
}

ip link show "$DEV" >/dev/null 2>&1 || {
    echo "HATA: arayuz bulunamadi: $DEV"
    exit 1
}

ip link set "$DEV" up
ip addr replace 10.0.0.1/24 dev "$DEV"
# Host'ta başka bir arayüz aynı subnet'i kullanıyorsa USB'yi kesin seç.
ip route replace 10.0.0.2/32 dev "$DEV" src 10.0.0.1

echo "USB agi: $DEV -> 10.0.0.1/24"
ip route get 10.0.0.2
ping -c 1 10.0.0.2
echo "SSH: ssh piranha@10.0.0.2"
