#!/usr/bin/env bash
# [LEGACY - Debian/systemd flow; the Alpine rootfs sets up usb0 and sshd itself]
# STEP 7: Network + SSH setup on the tablet
#
# When the tablet is connected over USB OTG to a PC (or a USB Ethernet adapter):
#   - the g_ether module is loaded (usb0 interface)
#   - static IP 10.0.0.2/24
#   - the ssh service listens
# so that from the PC you can connect with:  ssh piranha@10.0.0.2
#
# USAGE:
#   install into the rootfs (inside podman):  bash scripts/70-network.sh
#   after writing the SD card, on the tablet:  sudo modprobe g_ether; sudo systemctl start usbnet
#
# NOTE: This script runs INSIDE PODMAN (while the rootfs is being prepared),
#      or is applied directly (with sudo) to the rootfs on the SD card.
set -euo pipefail
PRJ="${PRJ:-$HOME/projeler/piranha-a10}"
RFS="${1:-$PRJ/rootfs/debian}"
[ -d "$RFS" ] || { echo "ERROR: rootfs missing: $RFS"; exit 1; }

echo ">>> network configuration: $RFS"

# 1) load the g_ether module automatically
mkdir -p "$RFS/etc/modules-load.d"
echo "g_ether" > "$RFS/etc/modules-load.d/g_ether.conf"

# 2) static IP for usb0 (systemd-networkd)
mkdir -p "$RFS/etc/systemd/network"
cat > "$RFS/etc/systemd/network/30-usb0.network" <<'EOF'
[Match]
Name=usb0

[Network]
Address=10.0.0.2/24
EOF

# 3) the SSH service is already installed (openssh-server); only make sure the permissions are right.
mkdir -p "$RFS/etc/ssh"
chmod 644 "$RFS/etc/ssh/ssh_config" 2>/dev/null || true

# 4) disable root SSH login (security), only allow piranha
if [ -f "$RFS/etc/ssh/sshd_config" ]; then
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$RFS/etc/ssh/sshd_config"
  grep -q '^PermitRootLogin' "$RFS/etc/ssh/sshd_config" || echo "PermitRootLogin no" >> "$RFS/etc/ssh/sshd_config"
fi

# 5) enable the ssh service (manual symlink, there is no systemctl inside podman)
mkdir -p "$RFS/etc/systemd/system/multi-user.target.wants"
ln -sf /lib/systemd/system/ssh.service "$RFS/etc/systemd/system/multi-user.target.wants/ssh.service" 2>/dev/null || true

# 6) example script to run on the PC side for an easy connection
mkdir -p "$RFS/root"
cat > "$RFS/root/setup-pc-usb0.sh" <<'EOF'
#!/bin/bash
# RUN ON THE PC SIDE while the tablet is connected:
#   sudo bash /root/setup-pc-usb0.sh
# Sets up the link between the tablet (10.0.0.2) and the PC (10.0.0.1).
ip link set usb0 up 2>/dev/null || { echo "no usb0 - connect the tablet"; exit 1; }
ip addr add 10.0.0.1/24 dev usb0
echo "PC: 10.0.0.1  |  Tablet: 10.0.0.2"
echo "Connect:  ssh piranha@10.0.0.2"
EOF
chmod +x "$RFS/root/setup-pc-usb0.sh" 2>/dev/null || true

echo "DONE. Network configuration ready."
echo "  Tablet usb0: 10.0.0.2"
echo "  From the PC: ssh piranha@10.0.0.2"
