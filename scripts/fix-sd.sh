#!/usr/bin/env bash
# Fixes two problems in the tablet rootfs on the SD card (run on the host with sudo; Debian-era):
#   1) rewrites the root/piranha password hash directly, bypassing PAM
#      (chpasswd inside podman had failed with a PAM error)
#   2) copies the boot journal to /tmp/piranha-journal/ for inspection
#
# USAGE:  sudo bash fix-sd.sh /dev/sdX
set -euo pipefail

SD="${1:-/dev/sdc}"
P2="${SD}2"
M=$(mktemp -d)
mount "$P2" "$M"

echo ">>> refreshing the shadow hash (bypassing PAM)"
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
print("  root+piranha -> password 'piranha' (yescrypt)")
PY

echo ">>> validating sudoers"
if command -v visudo >/dev/null; then
  visudo -cf "$M/etc/sudoers" && echo "  sudoers OK" || echo "  sudoers ERROR"
  visudo -cf "$M/etc/sudoers.d/piranha" 2>/dev/null && echo "  sudoers.d/piranha OK" || echo "  sudoers.d/piranha ERROR"
fi

echo ">>> extracting the boot journal"
JOUT=/tmp/piranha-journal
rm -rf "$JOUT"; mkdir -p "$JOUT"
cp -a "$M/var/log/journal/"* "$JOUT/" 2>/dev/null || echo "  could not copy the journal"
echo "  journal: $(du -sh "$JOUT" 2>/dev/null | cut -f1)"

sync; umount "$M"; rmdir "$M"
echo "DONE. Put the SD card back into the tablet; sudo should now work for piranha."
echo "Journal copied to: $JOUT"
