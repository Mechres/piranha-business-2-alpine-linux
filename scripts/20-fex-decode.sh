#!/usr/bin/env bash
# STEP 2: script.bin -> readable .fex; filter out the panel/touch/DRAM parameters.
set -euo pipefail
# Derive PRJ from the script's own location ($HOME is /root under sudo)
PRJ_DERIVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRJ="$PRJ_DERIVED"
FEX="$PRJ/fex"; DOC="$PRJ/docs"
mkdir -p "$PRJ/tools"

if [ ! -x "$PRJ/tools/sunxi-tools/sunxi-fexc" ]; then
  echo ">> building sunxi-tools"
  git -C "$PRJ/tools" clone --depth1 https://github.com/linux-sunxi/sunxi-tools 2>/dev/null || true
  make -C "$PRJ/tools/sunxi-tools"
fi
FEXC="$PRJ/tools/sunxi-tools/sunxi-fexc"

# If script.bin is missing, try to extract it from nanda.img
if [ ! -s "$FEX/script.bin" ]; then
  echo ">> script.bin missing, trying to mount nanda.img"
  mkdir -p /tmp/nanda && sudo mount -o loop,ro "$PRJ/backup/nanda.img" /tmp/nanda \
    && sudo cp /tmp/nanda/script.bin "$FEX/" && sudo umount /tmp/nanda
  sudo chown "$USER" "$FEX/script.bin"
fi

"$FEXC" -I bin -O fex "$FEX/script.bin" > "$FEX/tablet.fex"
echo ">> wrote $FEX/tablet.fex ($(wc -l < "$FEX/tablet.fex") lines)"

# Extract the critical sections
awk '/^\[(lcd0_para|ctp_para|ctp_list_para|pmu_para|dram_para|target|product|tkey_para|gpio_para|usbc0|usbc1|usbc2|twi0_para|twi1_para|twi2_para|pwm_para|backlight)\]/{f=1} /^\[/{if(!match($0,/lcd0_para|ctp_para|ctp_list_para|pmu_para|dram_para|target|product|tkey_para|gpio_para|usbc0|usbc1|usbc2|twi0_para|twi1_para|twi2_para|pwm_para|backlight/))f=0} f' \
  "$FEX/tablet.fex" > "$DOC/critical-parameters.txt"
echo ">> $DOC/critical-parameters.txt"
cat "$DOC/critical-parameters.txt"
