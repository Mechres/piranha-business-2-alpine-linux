#!/usr/bin/env bash
# ADIM 5b-STAGE2 (Alpine): podman container icinde apk + rc-update,
# sonra export -> rootfs. modules_install sudo ile (cross-compile).
#
# ONEMLI: Alpine musl oldugu icin duz `chroot` + qemu-arm binfmt guvenilmez
# (PATH/loader sorunlari). Bunun yerine podman container icinde apk calistir.
#
# KULLANIM: sudo bash scripts/45-alpine-stage2.sh
# Onkosul: 45-alpine-stage1.sh ile rootfs/alpine (base + config) hazir.
set -euo pipefail
PRJ_DERIVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRJ="$PRJ_DERIVED"
ALP_REL=3.20
RFS="$PRJ/rootfs/alpine"
CTR=piranha-alpine-apk

[ -d "$RFS" ] || { echo "HATA: $RFS yok. Once 45-alpine-stage1.sh calistir."; exit 1; }

command -v podman >/dev/null || { echo "HATA: podman gerekli"; exit 1; }
ls /proc/sys/fs/binfmt_misc/qemu-arm >/dev/null 2>&1 || {
  echo "HATA: qemu-arm binfmt kayitli degil."; exit 1; }

echo ">>> stage1 rootfs -> gecici container'a yukle (import)"
# Mevcut rootfs'i bir image'e cevirip container'da apk calistiralim.
# Yontem: rootfs'i bir dizin olarak bind mount'lu container ile degil,
# podman image import edip calistir.
TAR=/tmp/piranha-alpine-stage1.tar
echo ">>> rootfs tar'laniyor (image import icin)"
sudo tar -C "$RFS" -c -f "$TAR" . 2>/dev/null || tar -C "$RFS" -c -f "$TAR" .
echo ">>> tar -> alpine image import (local, ID ile referans)"
podman rm -f "$CTR" 2>/dev/null || true
IMG=$(podman import "$TAR")
echo ">>> import edilen image: $IMG"
# localhost/ registry'ye push/pull yapmamak icin dogrudan image ID kullan
# Host CA bundle'ini mount et (container'da /etc/ssl/certs bos oldugu icin
# HTTPS repo 'temporary error' veriyordu). CachyOS'ta /etc/ssl/certs altindaki
# hash'ler /etc/ca-certificates/extracted/cadir altina goreli symlink'tir;
# yalnizca /etc/ssl/certs'i baglamak bu linkleri kirar.
# --network=host: rootless slirp4netns container DNS/MTU'su host'tan izole
#   patladigi icin (podman update sonrasi reboot edilmemis olabilir) host
#   agini dogrudan paylasiyoruz. Boylece apk repo erisimi host ile ayni olur.
HOST_CA=/etc/ssl/certs
HOST_CA_ROOT=/etc/ca-certificates
PODMAN_CA_ARGS=()
[ -d "$HOST_CA" ] && PODMAN_CA_ARGS+=( -v "$HOST_CA:/etc/ssl/certs:ro" )
[ -d "$HOST_CA_ROOT" ] && PODMAN_CA_ARGS+=( -v "$HOST_CA_ROOT:/etc/ca-certificates:ro" )
podman run --name "$CTR" --platform linux/arm/v7 --network=host -d \
  "${PODMAN_CA_ARGS[@]}" "$IMG" sleep infinity

echo ">>> CA bundle kontrol (mount sonrasi)"
podman exec "$CTR" /bin/sh -c 'ls -l /etc/ssl/certs 2>/dev/null | head -3 || echo "CA DIZINI YOK"'

echo ">>> repositories: https + http(uk) fallback (CA mount ile https calisir)"
podman exec "$CTR" /bin/sh -c '
set -e
cat > /etc/apk/repositories <<EOF
https://dl-cdn.alpinelinux.org/alpine/v3.20/main
https://dl-cdn.alpinelinux.org/alpine/v3.20/community
http://uk.alpinelinux.org/alpine/v3.20/main
http://uk.alpinelinux.org/alpine/v3.20/community
EOF
'

echo ">>> container icinde apk paket kurulumu (qemu emulasyonu)"
podman exec "$CTR" /bin/sh -c '
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
apk update || echo "WARN: apk update kismen basarisiz (main reset verdi), devam"
apk add --no-cache \
  openrc alpine-base \
  openssh sudo \
  wpa_supplicant wireless-tools iw \
  iproute2 net-tools \
  udev eudev || true
# The group above is intentionally allowed to continue because some optional
# networking packages differ between Alpine releases.  These base packages
# are mandatory; install them separately so a failure cannot be hidden.
apk add --no-cache openrc alpine-base openssh sudo ca-certificates
apk add --no-cache \
  xorg-server xf86-video-fbdev xf86-input-libinput \
  xinit jwm xterm pcmanfm \
  libinput evtest \
  font-terminus tzdata kbd \
  util-linux pciutils usbutils nano less htop
echo "apk tamam"
'

echo ">>> kullanici + sifre (piranha/piranha)"
podman exec "$CTR" /bin/sh -c '
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo root:piranha | chpasswd
id piranha >/dev/null 2>&1 || adduser -D -s /bin/sh piranha
echo piranha:piranha | chpasswd
for g in wheel video input audio dialout netdev; do
  getent group "$g" >/dev/null || addgroup "$g"
addgroup piranha "$g" 2>/dev/null || true
done
mkdir -p /etc/sudoers.d
mkdir -p /var/empty
chown root:root /var/empty
chmod 755 /var/empty
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
'

echo ">>> SSH + OpenRC runlevel servisleri"
podman exec "$CTR" /bin/sh -c '
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
mkdir -p /etc/init.d
command -v rc-update >/dev/null
test -x /etc/init.d/sshd
cat > /etc/init.d/net.usb0 <<"EOF"
#!/sbin/openrc-run
description="Configure the USB Ethernet gadget interface"

depend() {
    need localmount
    after modules bootmisc
}

start() {
    ebegin "Configuring usb0"
    ip link set usb0 up 2>/dev/null || true
    ip addr replace 10.0.0.2/24 dev usb0 2>/dev/null || true
    eend 0
}

stop() {
    ebegin "Stopping usb0"
    ip addr flush dev usb0 2>/dev/null || true
    ip link set usb0 down 2>/dev/null || true
    eend 0
}
EOF
chmod +x /etc/init.d/net.usb0
cat > /etc/init.d/wifi <<"EOF"
#!/sbin/openrc-run
description="Connect to the configured Wi-Fi network"

depend() {
    need localmount
    after modules networking
}

start() {
    ebegin "Starting Wi-Fi"
    modprobe rtl8192cu 2>/dev/null || true
    sleep 2
    ip link set wlan0 up 2>/dev/null || { eend 1; return 1; }
    mkdir -p /run/wpa_supplicant
    killall wpa_supplicant 2>/dev/null || true
    wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
    udhcpc -b -q -i wlan0
    eend 0
}

stop() {
    ebegin "Stopping Wi-Fi"
    killall wpa_supplicant 2>/dev/null || true
    killall udhcpc 2>/dev/null || true
    ip link set wlan0 down 2>/dev/null || true
    eend 0
}
EOF
chmod +x /etc/init.d/wifi
rc-update add sshd default 2>/dev/null || true
sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
grep -q "^PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin no" >> /etc/ssh/sshd_config
rc-update add devfs sysinit 2>/dev/null || true
rc-update add dmesg sysinit 2>/dev/null || true
rc-update add udev sysinit 2>/dev/null || true
rc-update add udev-trigger sysinit 2>/dev/null || true
rc-update add hwclock boot 2>/dev/null || true
rc-update add modules boot 2>/dev/null || true
rc-update add sysctl boot 2>/dev/null || true
rc-update add bootmisc boot 2>/dev/null || true
rc-update add keymaps boot 2>/dev/null || true
rc-update add networking default 2>/dev/null || true
rc-update add net.usb0 default 2>/dev/null || true
rc-update add wifi default 2>/dev/null || true
rc-update add local default 2>/dev/null || true
'

echo ">>> container -> rootfs export (uzerine yaz)"
rm -rf "$RFS" 2>/dev/null || sudo rm -rf "$RFS"
mkdir -p "$RFS"
podman export "$CTR" | tar -x -C "$RFS"
podman rm -f "$CTR"
# stage1 config'leri export sonrasi tekrar uygula (export temizler mi? hayir,
# ama emin olalim: net.usb0 keymaps modules-load zaten image'de kalici)
# Eger eksikse stage1'i tekrar calistir.

echo ">>> kernel modulleri kopyalaniyor (cross-compile, sudo)"
source "$PRJ/scripts/00-env.sh"
cd "$PRJ/kernel/linux"
sudo make ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$RFS" modules_install 2>&1 | tail -3

echo
echo "ROOTFS_DONE: $RFS"
sudo du -sh "$RFS" 2>/dev/null || du -sh "$RFS"
echo "GT827 modulu: $(sudo test -f "$RFS/lib/modules/"*/kernel/drivers/input/touchscreen/gt827.ko && echo VAR || echo YOK)"
echo "RTL8192CU:    $(sudo test -f "$RFS/lib/modules/"*/kernel/drivers/net/wireless/realtek/rtlwifi/rtl8192cu/rtl8192cu.ko && echo VAR || echo YOK)"
echo "g_ether:      $(sudo test -f "$RFS/lib/modules/"*/kernel/drivers/usb/gadget/legacy/g_ether.ko && echo VAR || echo YOK)"
echo "runlevel net.usb0: $(ls "$RFS/etc/runlevels/default/net.usb0" 2>/dev/null && echo OK || echo YOK)"
echo "runlevel sshd:     $(ls "$RFS/etc/runlevels/default/sshd" 2>/dev/null && echo OK || echo YOK)"
