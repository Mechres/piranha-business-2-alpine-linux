#!/usr/bin/env bash
# STEP 1: Discovery and backup over Android. Tablet on USB, ADB enabled, ROOT required.
# Writes NOTHING to the device. It only reads and pulls the results into $PRJ/backup.
set -uo pipefail
# Derive PRJ from the script's own location ($HOME is /root under sudo)
PRJ_DERIVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRJ="$PRJ_DERIVED"
BK="$PRJ/backup"; FEX="$PRJ/fex"; DOC="$PRJ/docs"
mkdir -p "$BK" "$FEX" "$DOC"
L="$DOC/recon.log"; : > "$L"
say(){ echo -e "\n### $*" | tee -a "$L"; }
adbsh(){ adb shell "su -c '$*'" 2>&1; }

say "adb device list"; adb devices | tee -a "$L"
adb wait-for-device || exit 1

say "root test"; adbsh id | tee -a "$L"
say "kernel";      adbsh cat /proc/version | tee -a "$L"
say "cpuinfo";     adbsh cat /proc/cpuinfo | tee -a "$L"
say "mtd";         adbsh cat /proc/mtd | tee -a "$L"
say "block devices"; adbsh 'ls -l /dev/block/' | tee -a "$L"
say "mount";       adbsh mount | tee -a "$L"
say "i2c devices (touchscreen address)"; adbsh 'ls /sys/bus/i2c/devices/' | tee -a "$L"
say "input devices"; adbsh cat /proc/bus/input/devices | tee -a "$L"
say "framebuffer / panel"; adbsh 'cat /sys/class/graphics/fb0/modes; cat /sys/class/graphics/fb0/virtual_size' | tee -a "$L"
say "disp / lcd sysfs"; adbsh 'ls /sys/class/disp 2>/dev/null; ls /sys/devices/platform | head -50' | tee -a "$L"
say "AXP209 battery"; adbsh 'ls /sys/class/power_supply/; cat /sys/class/power_supply/*/uevent' | tee -a "$L"
say "build props"; adbsh 'getprop | grep -Ei "model|board|device|manufac|hardware"' | tee -a "$L"

say "looking for script.bin candidates"
adbsh 'ls -l /boot/script.bin /system/vendor/script.bin /data/script.bin 2>/dev/null' | tee -a "$L"

say "pulling nanda (partition 1) — script.bin lives here"
adbsh 'dd if=/dev/block/nanda of=/data/local/tmp/nanda.img bs=1M' | tee -a "$L"
adb pull /data/local/tmp/nanda.img "$BK/nanda.img" 2>&1 | tee -a "$L"

say "boot area backup (first 32 MB of raw NAND)"
adbsh 'dd if=/dev/block/nand of=/data/local/tmp/nand-first32M.img bs=1M count=32' | tee -a "$L"
adb pull /data/local/tmp/nand-first32M.img "$BK/nand-first32M.img" 2>&1 | tee -a "$L"

say "trying script.bin directly"
for p in /boot/script.bin /system/vendor/script.bin; do
  adb shell "su -c 'cat $p'" > "$FEX/script.bin.try" 2>/dev/null
  if [ -s "$FEX/script.bin.try" ]; then mv "$FEX/script.bin.try" "$FEX/script.bin"; echo "found: $p" | tee -a "$L"; break; fi
done
rm -f "$FEX/script.bin.try"

say "removing temporary files on the tablet"
adbsh 'rm -f /data/local/tmp/nanda.img /data/local/tmp/nand-first32M.img'

say "RESULT"; ls -lh "$BK" "$FEX" | tee -a "$L"
echo -e "\nLog: $L"
