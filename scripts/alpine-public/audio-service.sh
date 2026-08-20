#!/bin/sh
# Enable the A10 sun4i-codec speaker path at boot.
# Run on the tablet as root: sudo sh audio-service.sh
set -eu

install -d -m 755 /etc/init.d

cat > /etc/init.d/audio <<'EOF'
#!/sbin/openrc-run

name="sun4i-codec mixer"
description="Enable the Piranha speaker mixer path"

depend() {
	after modules
}

start() {
	local n

	for n in $(seq 1 20); do
		[ -e /dev/snd/controlC0 ] && break
		sleep 1
	done

	command -v amixer >/dev/null 2>&1 || return 0
	[ -e /dev/snd/controlC0 ] || return 0

	amixer -c 0 cset numid=1 63 >/dev/null
	amixer -c 0 cset numid=8 1 >/dev/null
	amixer -c 0 cset numid=13 1 >/dev/null
	amixer -c 0 cset numid=14 1 >/dev/null
	amixer -c 0 cset numid=15 1 >/dev/null
	amixer -c 0 cset numid=16 1 >/dev/null
	amixer -c 0 cset numid=17 1 >/dev/null
}
EOF

chmod 755 /etc/init.d/audio
rc-update add audio default
rc-service audio restart
echo "Audio mixer service installed and enabled."
