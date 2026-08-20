#!/usr/bin/env bash
# ADIM 7: Tablette ag + SSH kurulumu
#
# Tablet USB OTG -> PC (veya USB-Ethernet adaptoru) baglandiginda:
#   - g_ether modulu yuklenir (usb0 arayuzu)
#   - statik IP 10.0.0.2/24
#   - ssh servisi dinler
# Boylece PC'den:  ssh piranha@10.0.0.2  ile Hermes kontrol eder.
#
# KULLANIM:
#   rootfs'e kur (podman icinde):  bash scripts/70-network.sh
#   SD'ye yazildiktan sonra tablette:  sudo modprobe g_ether; sudo systemctl start usbnet
#
# NOT: Bu script PODMAN ICINDE calistirilir (rootfs hazirken),
#      ya da SD rootfs'e dogrudan (sudo ile) uygulanir.
set -euo pipefail
PRJ="${PRJ:-$HOME/projeler/piranha-a10}"
RFS="${1:-$PRJ/rootfs/debian}"
[ -d "$RFS" ] || { echo "HATA: rootfs yok: $RFS"; exit 1; }

echo ">>> ag yapilandirmasi: $RFS"

# 1) g_ether modulunu otomatik yukle
mkdir -p "$RFS/etc/modules-load.d"
echo "g_ether" > "$RFS/etc/modules-load.d/g_ether.conf"

# 2) usb0 icin statik IP (systemd-networkd)
mkdir -p "$RFS/etc/systemd/network"
cat > "$RFS/etc/systemd/network/30-usb0.network" <<'EOF'
[Match]
Name=usb0

[Network]
Address=10.0.0.2/24
EOF

# 3) SSH servisi zaten kurulu (openssh-server). Sadece izinleri sagla.
mkdir -p "$RFS/etc/ssh"
chmod 644 "$RFS/etc/ssh/ssh_config" 2>/dev/null || true

# 4) root ssh kapat (guvenlik), sadece piranha
if [ -f "$RFS/etc/ssh/sshd_config" ]; then
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$RFS/etc/ssh/sshd_config"
  grep -q '^PermitRootLogin' "$RFS/etc/ssh/sshd_config" || echo "PermitRootLogin no" >> "$RFS/etc/ssh/sshd_config"
fi

# 5) ssh servisini enable et (manuel symlink, podman icinde systemctl yok)
mkdir -p "$RFS/etc/systemd/system/multi-user.target.wants"
ln -sf /lib/systemd/system/ssh.service "$RFS/etc/systemd/system/multi-user.target.wants/ssh.service" 2>/dev/null || true

# 6) kolay baglanti icin PC tarafinda calistirilacak script ornegi
mkdir -p "$RFS/root"
cat > "$RFS/root/setup-pc-usb0.sh" <<'EOF'
#!/bin/bash
# TABLET PC'YE BAGLIYKEN PC TARAFINDA calistir:
#   sudo bash /root/setup-pc-usb0.sh
# Tablet (10.0.0.2) ile PC (10.0.0.1) arasinda link kurar.
ip link set usb0 up 2>/dev/null || { echo "usb0 yok - tableti bagla"; exit 1; }
ip addr add 10.0.0.1/24 dev usb0
echo "PC: 10.0.0.1  |  Tablet: 10.0.0.2"
echo "Baglan:  ssh piranha@10.0.0.2"
EOF
chmod +x "$RFS/root/setup-pc-usb0.sh" 2>/dev/null || true

echo "TAMAM. Ag yapilandirmasi hazir."
echo "  Tablet usb0: 10.0.0.2"
echo "  PC'den: ssh piranha@10.0.0.2"
