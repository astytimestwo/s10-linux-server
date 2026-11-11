#!/bin/sh
# Install the S10 audio lock (D2). Run as root on the phone from the folder holding:
#   70-s10-sound.rules  asound.conf  camilladsp.initd  s10-camilla-activate  s10-dac-test  README.md
# Safe to run again. Does not enable or start CamillaDSP (no active config yet).
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set -e
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
D=$(cd "$(dirname "$0")" && pwd)
for f in 70-s10-sound.rules asound.conf camilladsp.initd s10-camilla-activate s10-dac-test README.md; do
	[ -f "$D/$f" ] || { echo "missing $D/$f"; exit 1; }
done
sh -n "$D/s10-camilla-activate"; sh -n "$D/s10-dac-test"; sh -n "$D/camilladsp.initd"
[ -x /usr/local/bin/camilladsp ] || { echo "/usr/local/bin/camilladsp is missing"; exit 1; }

# 1. Groups and the service account
grep -q '^loopback:' /etc/group || addgroup -S loopback
grep -q '^camilladsp:' /etc/group || addgroup -S camilladsp
id camilladsp >/dev/null 2>&1 || adduser -S -D -H -h /var/lib/camilladsp -s /sbin/nologin -G camilladsp -g "CamillaDSP service" camilladsp
for g in audio loopback; do id -nG camilladsp | tr ' ' '\n' | grep -qx "$g" || addgroup camilladsp "$g"; done
id -nG user | tr ' ' '\n' | grep -qx loopback || addgroup user loopback
# "user" must NOT be in audio
if id -nG user | tr ' ' '\n' | grep -qx audio; then echo "WARNING: user is in group audio; that defeats the lock"; fi

# 2. Folders
install -d -o root -g root -m 755 /etc/camilladsp
install -d -o camilladsp -g camilladsp -m 750 /var/log/camilladsp /var/lib/camilladsp
install -o root -g root -m 644 "$D/README.md" /etc/camilladsp/README

# 3. Device rule, default device, service, owner helpers
install -o root -g root -m 644 "$D/70-s10-sound.rules" /etc/udev/rules.d/70-s10-sound.rules
[ -f /etc/asound.conf ] && [ ! -f /etc/asound.conf.orig ] && cp -p /etc/asound.conf /etc/asound.conf.orig
install -o root -g root -m 644 "$D/asound.conf" /etc/asound.conf
install -o root -g root -m 755 "$D/camilladsp.initd" /etc/init.d/camilladsp
install -o root -g root -m 755 "$D/s10-camilla-activate" "$D/s10-dac-test" /usr/local/sbin/

# 4. Apply the device rule now
udevadm control --reload-rules
udevadm trigger --subsystem-match=sound --action=change
udevadm settle --timeout=10 || true

# 5. The gatekeeper treats camilladsp as a base service (status only for agents)
if [ -f /etc/s10-sudo/baseline-services ] && ! grep -qx camilladsp /etc/s10-sudo/baseline-services; then
	echo camilladsp >> /etc/s10-sudo/baseline-services
fi
echo "audio lock installed:"
ls -l /dev/snd/ | awk 'NR>1{print $4}' | sort | uniq -c
