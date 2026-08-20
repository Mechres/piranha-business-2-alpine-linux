#!/usr/bin/env bash
# ADIM 2: script.bin -> okunabilir .fex ; panel/dokunmatik/DRAM parametrelerini süz.
set -euo pipefail
# PRJ'yi script'in KENDI konumundan turet ($HOME sudo altinda /root olur)
PRJ_DERIVED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRJ="$PRJ_DERIVED"
FEX="$PRJ/fex"; DOC="$PRJ/docs"
mkdir -p "$PRJ/tools"

if [ ! -x "$PRJ/tools/sunxi-tools/sunxi-fexc" ]; then
  echo ">> sunxi-tools derleniyor"
  git -C "$PRJ/tools" clone --depth1 https://github.com/linux-sunxi/sunxi-tools 2>/dev/null || true
  make -C "$PRJ/tools/sunxi-tools"
fi
FEXC="$PRJ/tools/sunxi-tools/sunxi-fexc"

# script.bin yoksa nanda.img içinden çıkarmayı dene
if [ ! -s "$FEX/script.bin" ]; then
  echo ">> script.bin yok, nanda.img montajı deneniyor"
  mkdir -p /tmp/nanda && sudo mount -o loop,ro "$PRJ/backup/nanda.img" /tmp/nanda \
    && sudo cp /tmp/nanda/script.bin "$FEX/" && sudo umount /tmp/nanda
  sudo chown "$USER" "$FEX/script.bin"
fi

"$FEXC" -I bin -O fex "$FEX/script.bin" > "$FEX/tablet.fex"
echo ">> $FEX/tablet.fex yazıldı ($(wc -l < "$FEX/tablet.fex") satır)"

# Kritik blokları ayıkla
awk '/^\[(lcd0_para|ctp_para|ctp_list_para|pmu_para|dram_para|target|product|tkey_para|gpio_para|usbc0|usbc1|usbc2|twi0_para|twi1_para|twi2_para|pwm_para|backlight)\]/{f=1} /^\[/{if(!match($0,/lcd0_para|ctp_para|ctp_list_para|pmu_para|dram_para|target|product|tkey_para|gpio_para|usbc0|usbc1|usbc2|twi0_para|twi1_para|twi2_para|pwm_para|backlight/))f=0} f' \
  "$FEX/tablet.fex" > "$DOC/kritik-parametreler.txt"
echo ">> $DOC/kritik-parametreler.txt"
cat "$DOC/kritik-parametreler.txt"
