#!/usr/bin/env bash
# ADIM 5 (v2): Debian armhf rootfs — podman + qemu-arm binfmt ile
#
# NEDEN podman: Arch'ta dpkg kurulu olmadığı için debootstrap host mimarisini
# tanıyamıyor ("Unknown architecture: x86_64"). Podman resmi debian:bookworm
# armhf imajını kullanmak hem daha temiz hem daha hızlı.
#
# NOTLAR:
#  - firmware-realtek bookworm'ta non-free'da; RTL firmware kartın Android'inden
#    de alınabilir, bu yüzden atlanabilir (--no-install-recommends ile).
#  - container'da systemd ÇALIŞMIYOR -> systemctl yok. enable yerine manuel symlink.
set -euo pipefail
# PRJ'yi script'in KENDI konumundan turet ($HOME sudo altinda /root olur)
PRJ_DERIVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRJ="$PRJ_DERIVED"
RFS="$PRJ/rootfs/debian"
CTR=piranha-rootfs

command -v podman >/dev/null || { echo "HATA: podman gerekli"; exit 1; }
ls /proc/sys/fs/binfmt_misc/qemu-arm >/dev/null 2>&1 || {
  echo "HATA: qemu-arm binfmt kayıtlı değil. Kur: sudo pacman -S qemu-user-static-binfmt"; exit 1; }

# NOT: Bu script NORMAL kullanıcı olarak çalıştırılmalı (sudo bash DEĞİL).
# podman rootless kalsın diye. Sadece export/modules_install adımları sudo
# kullanır ve o an şifre sorar.
if [ "$(id -u)" = "0" ]; then
  echo "HATA: bu scripti sudo ile çalıştırma. Düz çalıştır:"
  echo "  bash scripts/40-rootfs.sh"
  echo "(export adımında sudo şifresi soracak)"
  exit 1
fi

echo ">>> eski konteyner temizliği"
podman rm -f "$CTR" 2>/dev/null || true

echo ">>> armhf debian:bookworm konteyner başlat"
podman run --name "$CTR" --platform linux/arm/v7 -d \
  docker.io/library/debian:bookworm sleep infinity

echo ">>> mimari doğrula (armv7l olmalı)"
ARCH=$(podman exec "$CTR" uname -m)
echo "konteyner mimarisi: $ARCH"
case "$ARCH" in armv7l|armv8l|arm*) ;; *) echo "HATA: armhf değil ($ARCH)"; exit 1;; esac

echo ">>> paketler kuruluyor (uzun sürer, qemu emülasyonu)"
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

echo ">>> sistem yapılandırması"
podman exec "$CTR" bash -c '
cat > /etc/fstab <<EOF
/dev/mmcblk0p2  /       ext4  defaults,noatime  0 1
/dev/mmcblk0p1  /boot   vfat  defaults          0 2
/swapfile       none    swap    sw               0 0
EOF
echo piranha > /etc/hostname
printf "127.0.0.1 localhost\n127.0.1.1 piranha\n" > /etc/hosts

# grupları oluştur (useradd -G patlar yoksa)
for g in sudo video input audio dialout netdev; do
  getent group "$g" >/dev/null || groupadd "$g"
done

echo "root:piranha" | chpasswd
id piranha >/dev/null 2>&1 || useradd -m -s /bin/bash piranha
usermod -aG sudo,video,input,audio,dialout,netdev piranha
echo "piranha:piranha" | chpasswd

# systemd servisleri (containerda systemctl yok -> manuel symlink)
mkdir -p /etc/systemd/system/getty.target.wants \
         /etc/systemd/system/multi-user.target.wants
ln -sf /lib/systemd/system/serial-getty@.service \
       /etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service
ln -sf /lib/systemd/system/ssh.service \
       /etc/systemd/system/multi-user.target.wants/ssh.service

# KRİTİK: UART yok -> kalıcı journal + konsola aktar (SD karttan okuyabilelim)
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

# sudo izni
echo "%sudo ALL=(ALL:ALL) ALL" > /etc/sudoers.d/piranha
chmod 440 /etc/sudoers.d/piranha

# swap (1GB RAM icin; Alpine akışında bu eski Debian scripti kullanılmaz)
dd if=/dev/zero of=/swapfile bs=1M count=256 status=none
chmod 600 /swapfile
mkswap /swapfile >/dev/null

# locale
sed -i "s/^# *en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen 2>/dev/null || true
'

echo ">>> rootfs dışa aktarılıyor"
sudo rm -rf "$RFS"; sudo mkdir -p "$RFS"
podman export "$CTR" | sudo tar -x -C "$RFS"

echo ">>> konteyner temizliği"
podman rm -f "$CTR"

echo ">>> kernel modülleri kuruluyor"
source "$PRJ/scripts/00-env.sh"
cd "$PRJ/kernel/linux"
sudo make ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$RFS" modules_install 2>&1 | tail -3

# --- podman export artıklarını düzelt ---
# podman /etc/hostname, /etc/hosts, /etc/resolv.conf'u bind-mount eder;
# export sırasında konteyner değerleri döner ya da dosya boşalır.
echo ">>> konteyner artıkları düzeltiliyor"
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
echo "Kontrol: $(sudo cat "$RFS/etc/os-release" | head -2 | tr '\n' ' ')"
echo "GT811 modülü: $(sudo test -f "$RFS/lib/modules/"*/kernel/drivers/input/touchscreen/gt811.ko && echo VAR || echo YOK)"
