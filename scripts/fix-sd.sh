#!/usr/bin/env bash
# SD karttaki tablet rootfs'inde iki sorunu düzeltir (host'ta sudo ile çalıştır):
#   1) piranha/root sudo şifresini PAM'ı atlayarak yeniden yazar
#      (podman icindeki chpasswd PAM hatasi vermisti)
#   2) boot journal'ini /tmp/piranha-journal/ icine cikarir (Hermes okusun)
#
# KULLANIM:  sudo bash fix-sd.sh
set -euo pipefail

SD="${1:-/dev/sdc}"
P2="${SD}2"
M=$(mktemp -d)
mount "$P2" "$M"

echo ">>> shadow hash yenileniyor (PAM atlanir)"
HASH=$(openssl passwd -6 piranha)
python3 - "$M/etc/shadow" "$HASH" <<'PY'
import sys
path, nhash = sys.argv[1], sys.argv[2]
out=[]
for l in open(path).read().splitlines():
    u=l.split(":")[0]
    if u in ("root","piranha"):
        p=l.split(":"); p[1]=nhash; l=":".join(p)
    out.append(l)
open(path,"w").write("\n".join(out)+"\n")
print("  root+piranha -> piranha sifresi (yescrypt)")
PY

echo ">>> sudoers dogrula"
if command -v visudo >/dev/null; then
  visudo -cf "$M/etc/sudoers" && echo "  sudoers OK" || echo "  sudoers HATA"
  visudo -cf "$M/etc/sudoers.d/piranha" 2>/dev/null && echo "  sudoers.d/piranha OK" || echo "  sudoers.d/piranha HATA"
fi

echo ">>> boot journal cikariliyor"
JOUT=/tmp/piranha-journal
rm -rf "$JOUT"; mkdir -p "$JOUT"
cp -a "$M/var/log/journal/"* "$JOUT/" 2>/dev/null || echo "  journal kopyalanamadi"
echo "  journal: $(du -sh "$JOUT" 2>/dev/null | cut -f1)"

sync; umount "$M"; rmdir "$M"
echo "TAMAM. SD'yi tablete tak, sudo artik piranha olmali."
echo "Journal Hermes'te: $JOUT"
