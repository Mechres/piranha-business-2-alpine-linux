#!/usr/bin/env bash
# [LEGACY - Debian flow, superseded by the Alpine scripts 45-alpine-stage1.sh / 45-alpine-stage2.sh]
# STEP 5 (v2): Debian armhf rootfs — via podman + qemu-arm binfmt
#
# WHY podman: Arch has no dpkg installed, so debootstrap cannot recognise the host
# architecture ("Unknown architecture: x86_64"). Using the official debian:bookworm
# armhf image through podman is both cleaner and faster.
#
# NOTES:
#  - firmware-realtek is in non-free on bookworm; the RTL firmware can also be taken from the
#    board's Android, so it can be skipped (--no-install-recommends).
#  - systemd does NOT run in the container -> no systemctl. Create the symlinks by hand instead of `enable`.
set -euo pipefail
# Derive PRJ from the script's own location ($HOME is /root under sudo)
PRJ_DERIVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRJ="$PRJ_DERIVED"
RFS="$PRJ/rootfs/debian"
CTR=piranha-rootfs

command -v podman >/dev/null || { echo "ERROR: podman is required"; exit 1; }
ls /proc/sys/fs/binfmt_misc/qemu-arm >/dev/null 2>&1 || {
  echo "ERROR: qemu-arm binfmt is not registered. Install: sudo pacman -S qemu-user-static-binfmt"; exit 1; }

# NOTE: Run this script as a NORMAL user (NOT with sudo).
# so that podman stays rootless. Only the export/modules_install steps use sudo
# and ask for the password at that point.
if [ "$(id -u)" = "0" ]; then
  echo "ERROR: do not run this script with sudo. Run it plainly:"
  echo "  bash scripts/40-rootfs.sh"
  echo "(it will ask for the sudo password during the export step)"
  exit 1
fi

echo ">>> cleaning up the old container"
podman rm -f "$CTR" 2>/dev/null || true

echo ">>> starting the armhf debian:bookworm container"
podman run --name "$CTR" --platform linux/arm/v7 -d \
  docker.io/library/debian:bookworm sleep infinity

echo ">>> verifying the architecture (must be armv7l)"
ARCH=$(podman exec "$CTR" uname -m)
echo "container architecture: $ARCH"
case "$ARCH" in armv7l|armv8l|arm*) ;; *) echo "ERROR: not armhf ($ARCH)"; exit 1;; esac

echo ">>> installing packages (takes long, qemu emulation)"
podman exec "$CTR" bash -c 'export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  systemd systemd-sysv udev dbus \
  openssh-server sudo net-tools iproute2 iw wireless-tools wpasupplicant \
  xserver-xorg-core xserver-xorg-video-fbdev xserver-xorg-input-libinput \
  xinit jwm xterm pcmanfm \
  libinput-tools evtest i2c-tools usbutils \
  nano less htop ca-certificates kmod initramfs-tools
apt-get clean
rm -rf /var/lib/apt/lists/*'

echo ">>> system configuration"
podman exec "$CTR" bash -c '
cat > /etc/fstab <<EOF
/dev/mmcblk0p2  /       ext4  defaults,noatime  0 1
/dev/mmcblk0p1  /boot   vfat  defaults          0 2
/swapfile       none    swap    sw               0 0
EOF
echo piranha > /etc/hostname
printf "127.0.0.1 localhost\n127.0.1.1 piranha\n" > /etc/hosts

# create the groups (useradd -G fails if they do not exist)
for g in sudo video input audio dialout netdev; do
  getent group "$g" >/dev/null || groupadd "$g"
done

echo "root:piranha" | chpasswd
id piranha >/dev/null 2>&1 || useradd -m -s /bin/bash piranha
usermod -aG sudo,video,input,audio,dialout,netdev piranha
echo "piranha:piranha" | chpasswd

# systemd services (no systemctl in the container -> manual symlinks)
mkdir -p /etc/systemd/system/getty.target.wants \
         /etc/systemd/system/multi-user.target.wants
ln -sf /lib/systemd/system/serial-getty@.service \
       /etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service
ln -sf /lib/systemd/system/ssh.service \
       /etc/systemd/system/multi-user.target.wants/ssh.service

# CRITICAL: no UART -> persistent journal + forward to the console (so it can be read from the SD card)
mkdir -p /var/log/journal /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/persist.conf <<EOF
[Journal]
Storage=persistent
ForwardToConsole=yes
TTYPath=/dev/tty1
MaxLevelConsole=info
EOF

# X11 / JWM
printf "#!/bin/sh\nexec jwm\n" > /root/.xinitrc
cp /root/.xinitrc /home/piranha/.xinitrc
chown piranha:piranha /home/piranha/.xinitrc
chmod +x /root/.xinitrc /home/piranha/.xinitrc

# DHCP (ethernet/usb)
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/20-wired.network <<EOF
[Match]
Name=en* eth*
[Network]
DHCP=yes
EOF

# sudo permission
echo "%sudo ALL=(ALL:ALL) ALL" > /etc/sudoers.d/piranha
chmod 440 /etc/sudoers.d/piranha

# swap (for 1 GB RAM; this old Debian script is not used in the Alpine flow)
dd if=/dev/zero of=/swapfile bs=1M count=256 status=none
chmod 600 /swapfile
mkswap /swapfile >/dev/null

# locale
sed -i "s/^# *en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen 2>/dev/null || true
'

echo ">>> exporting the rootfs"
sudo rm -rf "$RFS"; sudo mkdir -p "$RFS"
podman export "$CTR" | sudo tar -x -C "$RFS"

echo ">>> cleaning up the container"
podman rm -f "$CTR"

echo ">>> installing the kernel modules"
source "$PRJ/scripts/00-env.sh"
cd "$PRJ/kernel/linux"
sudo make ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$RFS" modules_install 2>&1 | tail -3

# --- fix leftovers from the podman export ---
# podman bind-mounts /etc/hostname, /etc/hosts and /etc/resolv.conf;
# during the export the container values come back or the files end up empty.
echo ">>> fixing the container leftovers"
echo piranha | sudo tee "$RFS/etc/hostname" >/dev/null
sudo tee "$RFS/etc/hosts" >/dev/null <<'EOF'
127.0.0.1	localhost
127.0.1.1	piranha
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF
sudo tee "$RFS/etc/resolv.conf" >/dev/null <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
sudo rm -f "$RFS/.dockerenv" "$RFS/run/.containerenv" 2>/dev/null || true

echo
echo "ROOTFS_DONE: $RFS"
sudo du -sh "$RFS"
echo "Check: $(sudo cat "$RFS/etc/os-release" | head -2 | tr '\n' ' ')"
echo "GT811 module: $(sudo test -f "$RFS/lib/modules/"*/kernel/drivers/input/touchscreen/gt811.ko && echo present || echo MISSING)"
