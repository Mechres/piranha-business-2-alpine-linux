#!/bin/bash
# Tablet ACILISTA WiFi'ye baglanir (builtin rtl8192cu)
# KULLANICI DUZENLER: WIFI_SSID ve WIFI_PASS
#
# Kurulum (rootfs'e kopyala):
#   cp wifi-connect.sh /run/media/.../pirroot/etc/network/if-up.d/  (veya systemd servisi)
#
# Basit yol: /etc/rc.local ...[truncated]