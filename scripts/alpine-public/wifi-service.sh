#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || {
    echo "Bu script tablette root olarak calismali: sudo sh $0"
    exit 1
}

cat > /etc/init.d/wifi <<'EOF'
#!/sbin/openrc-run
description="Connect to configured Wi-Fi"

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

chmod 755 /etc/init.d/wifi
rc-update add wifi default
rc-service wifi restart
echo "Wi-Fi OpenRC servisi kuruldu."
