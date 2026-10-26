#!/usr/bin/env bash
set -euo pipefail

DEV="${1:-}"
[ -n "$DEV" ] || {
    echo "Usage: sudo $0 <usb-network-interface>"
    echo "Example: sudo $0 enp15s0f3u1"
    exit 2
}

ip link show "$DEV" >/dev/null 2>&1 || {
    echo "ERROR: interface not found: $DEV"
    exit 1
}

ip link set "$DEV" up
ip addr replace 10.0.0.1/24 dev "$DEV"
# If another host interface uses the same subnet, force the route over the USB interface.
ip route replace 10.0.0.2/32 dev "$DEV" src 10.0.0.1

echo "USB network: $DEV -> 10.0.0.1/24"
ip route get 10.0.0.2
ping -c 1 10.0.0.2
echo "SSH: ssh piranha@10.0.0.2"
