#!/bin/sh
# Copies every small, device-unique partition (EFS, sec_efs, modem/CP, param,
# persist, ...) into $OUT with sha256 sums. Read-only on the partitions: only
# `dd if=<partition>` is used.
#
# Two places it can run (as root):
#   TWRP (preferred, before the rootfs is written):
#       adb push backup-partitions.sh /tmp/ && adb shell "OUT=/tmp/partition-backup sh /tmp/backup-partitions.sh"
#   Nura first boot (fallback):
#       doas sh backup-partitions.sh          -> /home/user/partition-backup
# Afterwards copy the folder to the PC and verify the sums there (docs/build-and-flash.md).
set -eu

OUT=${OUT:-/home/user/partition-backup}
MAX_MB=512          # skip anything bigger (system, userdata, vendor, ...)
mkdir -p "$OUT"
cd "$OUT"

echo "# partition list $(date)" > partitions.txt
for u in /sys/class/block/*/uevent; do
	name=$(sed -n 's/^PARTNAME=//p' "$u")
	[ -n "$name" ] || continue
	dev=$(sed -n 's/^DEVNAME=//p' "$u")
	sectors=$(cat "$(dirname "$u")/size")
	mb=$((sectors / 2048))      # 512-byte sectors -> MiB; no 32-bit overflow in TWRP's shell
	echo "$dev $name ${mb}MB" >> partitions.txt
	case "$name" in
		SYSTEM|USERDATA|userdata|system|VENDOR|vendor|CACHE|cache) continue ;;
	esac
	if [ "$mb" -gt "$MAX_MB" ]; then
		echo "skip $name (${mb} MB)"
		continue
	fi
	echo "dump $name ($dev, ${mb} MB)"
	out="$name.img"; [ -e "$out" ] && out="$name-$dev.img"     # duplicate names on different LUNs
	dd if="/dev/block/$dev" of="$out" bs=1048576 2>/dev/null || dd if="/dev/$dev" of="$out" bs=1048576 2>/dev/null \
		|| { echo "FAILED to read $name ($dev), skipped"; rm -f "$out"; }
done

sha256sum ./*.img > SHA256SUMS
if id user >/dev/null 2>&1; then chown -R user:user "$OUT"; fi
echo "Done: $(ls ./*.img | wc -l) partitions in $OUT"
du -sh "$OUT"
