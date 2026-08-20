#!/bin/sh
# Tablet uzerinde CALISTIR (ssh yokken, klavye zorlarsa kopyala-yapistir):
#   sh /boot/diag.sh
# Tum teşhis logunu /diag.txt'e yazar. SD'yi PC'ye alip Hermes okur.
LOG=/diag.txt
: > "$LOG"
echo "=== PIRANHA DIAG $(date) ===" >> "$LOG"
echo "--- uname ---" >> "$LOG"
uname -a >> "$LOG" 2>&1
echo "--- dr_mode (DTB) ---" >> "$LOG"
cat /proc/device-tree/soc@1c00000/usb@1c19000/dr_mode 2>/dev/null | tr -d '\0'; echo >> "$LOG"
echo "--- /sys/class/udc ---" >> "$LOG"
ls /sys/class/udc/ 2>&1 >> "$LOG"
echo "--- lsmod (usb/gadget) ---" >> "$LOG"
lsmod 2>/dev/null | grep -iE 'g_ether|libcomposite|musb|udc|usb' >> "$LOG"
echo "--- g_ether modprobe test ---" >> "$LOG"
modprobe g_ether 2>&1 >> "$LOG"
sleep 2
ls /sys/class/udc/ 2>&1 >> "$LOG"
ip addr show usb0 2>&1 >> "$LOG"
echo "--- dmesg (usb/musb/gadget/udc) ---" >> "$LOG"
dmesg 2>/dev/null | grep -iE 'musb|udc|gadget|usb0|sunxi.*usb|eth' | tail -40 >> "$LOG"
echo "--- GT811 ---" >> "$LOG"
dmesg 2>/dev/null | grep -i gt811 >> "$LOG"
echo "DONE -> $LOG" >> "$LOG"
echo "DIAG YAZILDI: $LOG"
