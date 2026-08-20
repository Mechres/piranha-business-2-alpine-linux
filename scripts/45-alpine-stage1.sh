#!/usr/bin/env bash
# ADIM 5b-STAGE1 (Alpine, sudo'suz): podman export + config dosyalari
# Bu kisim ROOT ISTEMEZ — Hermes tarafindan calistirilir.
# Stage2 (sudo ile chroot apk + rc-update + modules_install) ayri script.
set -euo pipefail
PRJ_DERIVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRJ="$PRJ_DERIVED"
ALP_REL=3.20
RFS="$PRJ/rootfs/alpine"
CTR=piranha-alpine

command -v podman >/dev/null || { echo "HATA: podman gerekli"; exit 1; }
ls /proc/sys/fs/binfmt_misc/qemu-arm >/dev/null 2>&1 || {
  echo "HATA: qemu-arm binfmt kayitli degil."; exit 1; }

echo ">>> eski konteyner temizligi"
podman rm -f "$CTR" 2>/dev/null || true
rm -rf "$RFS" 2>/dev/null || sudo rm -rf "$RFS"
mkdir -p "$RFS"

echo ">>> alpine:$ALP_REL arm/v7 konteyner"
podman run --name "$CTR" --platform linux/arm/v7 -d \
  docker.io/library/alpine:"$ALP_REL" sleep infinity

echo ">>> konteyner -> rootfs extract (sudo'suz, rootless podman)"
podman export "$CTR" | tar -x -C "$RFS"
podman rm -f "$CTR"

echo ">>> apk repositories + DNS (sudo'suz, mechres sahibinde)"
cat > "$RFS/etc/apk/repositories" <<EOF
http://dl-cdn.alpinelinux.org/alpine/v$ALP_REL/main
http://dl-cdn.alpinelinux.org/alpine/v$ALP_REL/community
EOF
cat > "$RFS/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

echo ">>> config dosyalari (sudo'suz, kendi dizinimiz)"
# hostname
echo piranha > "$RFS/etc/hostname"
# hosts
cat > "$RFS/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	piranha
::1		localhost ip6-localhost ip6-loopback
EOF
# fstab
cat > "$RFS/etc/fstab" <<'EOF'
/dev/mmcblk0p1	/boot	vfat	ro,defaults	0 2
/dev/mmcblk0p2	/	ext4	defaults,noatime	0 1
EOF
# keymap TR
mkdir -p "$RFS/etc/conf.d"
cat > "$RFS/etc/conf.d/keymaps" <<'EOF'
keymap="trq"
EOF
# USB Ethernet g_ether modules-load
mkdir -p "$RFS/etc/modules-load.d"
echo "g_ether" > "$RFS/etc/modules-load.d/g_ether.conf"
# GT827 module
echo "gt827" > "$RFS/etc/modules-load.d/gt827.conf"
# net.usb0 statik IP
mkdir -p "$RFS/etc/conf.d"
cat > "$RFS/etc/conf.d/net.usb0" <<'EOF'
config_usb0="10.0.0.2/24"
EOF
# WiFi firmware (gercek blob)
mkdir -p "$RFS/lib/firmware/rtlwifi"
cp "$PRJ/rootfs/firmware/"*.bin "$RFS/lib/firmware/rtlwifi/" 2>/dev/null || echo "UYARI: firmware bin yok"
# wifi manuel baglanti scripti
mkdir -p "$RFS/usr/local/bin" "$RFS/etc/wpa_supplicant"
cat > "$RFS/usr/local/bin/wifi-connect.sh" <<'EOF'
#!/bin/sh
modprobe rtl8192cu 2>/dev/null
sleep 2
ip link set wlan0 up
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
udhcpc -i wlan0
EOF
chmod +x "$RFS/usr/local/bin/wifi-connect.sh"
# wpa_supplicant.conf (bos, kullanici dolduracak)
cat > "$RFS/etc/wpa_supplicant/wpa_supplicant.conf" <<'EOF'
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=1
country=TR

network={
    ssid="BURAYA_SSID"
    psk="BURAYA_SIFRE"
}
EOF
chmod 600 "$RFS/etc/wpa_supplicant/wpa_supplicant.conf"
# X11 / JWM
cat > "$RFS/root/.xinitrc" <<'EOF'
#!/bin/sh
exec jwm
EOF
cp "$RFS/root/.xinitrc" "$RFS/home/piranha/.xinitrc" 2>/dev/null || mkdir -p "$RFS/home/piranha" && cp "$RFS/root/.xinitrc" "$RFS/home/piranha/.xinitrc"
chmod +x "$RFS/root/.xinitrc" "$RFS/home/piranha/.xinitrc" 2>/dev/null || true

echo "STAGE1_DONE: $RFS"
du -sh "$RFS"
echo ">>> Simdi DC calistirmali: sudo bash scripts/45-alpine-stage2.sh"
