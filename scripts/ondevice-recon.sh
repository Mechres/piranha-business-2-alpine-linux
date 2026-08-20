#!/system/bin/sh
# Cihaz üzerinde root olarak çalışır. Tek dosya => eski su ile uyumlu.
echo "=== id ==="; id
echo "=== version ==="; cat /proc/version
echo "=== cpuinfo ==="; cat /proc/cpuinfo
echo "=== mtd ==="; cat /proc/mtd
echo "=== block ==="; ls -l /dev/block/
echo "=== i2c ==="; ls /sys/bus/i2c/devices/
echo "=== i2c-names ==="; for d in /sys/bus/i2c/devices/*; do echo "$d -> $(cat $d/name 2>/dev/null)"; done
echo "=== input ==="; cat /proc/bus/input/devices
echo "=== fb0 ==="; cat /sys/class/graphics/fb0/modes; cat /sys/class/graphics/fb0/virtual_size
echo "=== disp ==="; ls /sys/class/disp 2>/dev/null; ls /sys/devices/platform
echo "=== power ==="; ls /sys/class/power_supply/; cat /sys/class/power_supply/*/uevent
echo "=== props ==="; getprop
echo "=== script.bin adayları ==="
ls -l /boot/script.bin /system/vendor/script.bin /data/script.bin /mnt/sdcard/script.bin 2>/dev/null
echo "=== /boot içeriği ==="; ls -l /boot 2>/dev/null
echo "=== nanda mount denemesi ==="
mkdir -p /data/local/tmp/na
mount -t vfat /dev/block/nanda /data/local/tmp/na 2>&1 || mount -o ro /dev/block/nanda /data/local/tmp/na 2>&1
ls -l /data/local/tmp/na
echo "=== DUMP: nanda ==="
dd if=/dev/block/nanda of=/data/local/tmp/nanda.img bs=65536 2>&1
echo "=== DUMP: script.bin (mount üzerinden) ==="
cp /data/local/tmp/na/script.bin /data/local/tmp/script.bin 2>&1
cp /boot/script.bin /data/local/tmp/script.bin 2>&1
ls -l /data/local/tmp/script.bin
echo "=== DUMP: nand ilk 32MB ==="
dd if=/dev/block/nand of=/data/local/tmp/nand-first32M.img bs=65536 count=512 2>&1
echo "=== izinler ==="
chmod 666 /data/local/tmp/*.img /data/local/tmp/script.bin 2>/dev/null
ls -l /data/local/tmp/
echo "=== BITTI ==="
