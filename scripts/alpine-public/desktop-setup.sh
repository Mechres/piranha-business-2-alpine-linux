#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || {
    echo "Bu script tablette root olarak calismali: sudo sh $0"
    exit 1
}

# The generated minimal rootfs may not contain Alpine's CA bundle yet.
# Use the official mirror over HTTP for this bootstrap package install;
# subsequent image builds should include ca-certificates.
cat > /etc/apk/repositories <<'EOF'
http://dl-cdn.alpinelinux.org/alpine/v3.20/main
http://dl-cdn.alpinelinux.org/alpine/v3.20/community
EOF

apk add --no-cache ca-certificates pcmanfm jwm xinit xterm xf86-video-fbdev xf86-input-libinput

cat > /home/piranha/.xinitrc <<'EOF'
#!/bin/sh
if command -v pcmanfm >/dev/null 2>&1; then
    pcmanfm --desktop >/tmp/pcmanfm-desktop.log 2>&1 &
fi
exec jwm
EOF

cp /home/piranha/.xinitrc /root/.xinitrc
chown piranha:piranha /home/piranha/.xinitrc
chmod 755 /home/piranha/.xinitrc /root/.xinitrc

echo "Masaustu hazir. USB klavye ile piranha olarak girip 'startx' calistir."
