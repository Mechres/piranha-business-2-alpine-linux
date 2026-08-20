#!/usr/bin/env bash
# ADIM 1: Android üzerinden keşif + yedek. Tablet USB'de, ADB açık, ROOT gerekli.
# Hiçbir şeyi YAZMAZ. Sadece okur ve ~/projeler/piranha-a10/backup içine çeker.
set -uo pipefail
# PRJ'yi script'in KENDI konumundan turet ($HOME sudo altinda /root olur)
PRJ_DERIVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRJ="$PRJ_DERIVED"
BK="$PRJ/backup"; FEX="$PRJ/fex"; DOC="$PRJ/docs"
mkdir -p "$BK" "$FEX" "$DOC"
L="$DOC/recon.log"; : > "$L"
say(){ echo -e "\n### $*" | tee -a "$L"; }
adbsh(){ adb shell "su -c '$*'" 2>&1; }

say "adb cihaz listesi"; adb devices | tee -a "$L"
adb wait-for-device || exit 1

say "root testi"; adbsh id | tee -a "$L"
say "kernel";      adbsh cat /proc/version | tee -a "$L"
say "cpuinfo";     adbsh cat /proc/cpuinfo | tee -a "$L"
say "mtd";         adbsh cat /proc/mtd | tee -a "$L"
say "blok aygıtlar"; adbsh 'ls -l /dev/block/' | tee -a "$L"
say "mount";       adbsh mount | tee -a "$L"
say "i2c aygıtları (dokunmatik adresi)"; adbsh 'ls /sys/bus/i2c/devices/' | tee -a "$L"
say "input aygıtları"; adbsh cat /proc/bus/input/devices | tee -a "$L"
say "framebuffer / panel"; adbsh 'cat /sys/class/graphics/fb0/modes; cat /sys/class/graphics/fb0/virtual_size' | tee -a "$L"
say "disp / lcd sysfs"; adbsh 'ls /sys/class/disp 2>/dev/null; ls /sys/devices/platform | head -50' | tee -a "$L"
say "AXP209 pil"; adbsh 'ls /sys/class/power_supply/; cat /sys/class/power_supply/*/uevent' | tee -a "$L"
say "build props"; adbsh 'getprop | grep -Ei "model|board|device|manufac|hardware"' | tee -a "$L"

say "script.bin adaylarını arıyorum"
adbsh 'ls -l /boot/script.bin /system/vendor/script.bin /data/script.bin 2>/dev/null' | tee -a "$L"

say "nanda (bölüm 1) çekiliyor — script.bin buradadır"
adbsh 'dd if=/dev/block/nanda of=/data/local/tmp/nanda.img bs=1M' | tee -a "$L"
adb pull /data/local/tmp/nanda.img "$BK/nanda.img" 2>&1 | tee -a "$L"

say "boot bölgesi (ilk 32MB ham NAND) yedeği"
adbsh 'dd if=/dev/block/nand of=/data/local/tmp/nand-first32M.img bs=1M count=32' | tee -a "$L"
adb pull /data/local/tmp/nand-first32M.img "$BK/nand-first32M.img" 2>&1 | tee -a "$L"

say "script.bin doğrudan denemesi"
for p in /boot/script.bin /system/vendor/script.bin; do
  adb shell "su -c 'cat $p'" > "$FEX/script.bin.try" 2>/dev/null
  if [ -s "$FEX/script.bin.try" ]; then mv "$FEX/script.bin.try" "$FEX/script.bin"; echo "buldum: $p" | tee -a "$L"; break; fi
done
rm -f "$FEX/script.bin.try"

say "tablette geçici dosyaları sil"
adbsh 'rm -f /data/local/tmp/nanda.img /data/local/tmp/nand-first32M.img'

say "SONUÇ"; ls -lh "$BK" "$FEX" | tee -a "$L"
echo -e "\nLog: $L"
