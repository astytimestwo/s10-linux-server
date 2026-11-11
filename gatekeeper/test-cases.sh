#!/bin/sh
# Test the s10-sudo rules. Run as "user" on the S10:  sh test-cases.sh
# Part 1 uses --check (decides, runs nothing). Part 2 really runs a few harmless commands.
G=/usr/local/sbin/s10-sudo
pass=0; fail=0
t() {   # $1 = want (ok|no), rest = command
	want=$1; shift
	$G --check "$@" >/dev/null 2>&1; rc=$?
	case "$want:$rc" in ok:0|no:77) pass=$((pass + 1)) ;; *) fail=$((fail + 1)); echo "FAIL want=$want rc=$rc : $*" ;; esac
}
# --- allowed ---
t ok apk add htop
t ok apk add -U chromium
t ok apk info -L busybox
t ok apk update
t ok rc-service sshd status
t ok rc-update show
t ok rc-status
t ok cat /etc/ssh/sshd_config
t ok tail -n 20 /var/log/s10-sudo.log
t ok ls -la /var/lib
t ok grep -i banner /etc/ssh/sshd_config.d/10-s10-keys-only.conf
t ok dmesg
t ok ss -tlnp
t ok ip addr show
t ok iw dev wlan0 link
t ok iptables-legacy -S INPUT
t ok iptables-legacy -nvL
t ok sshd.pam -T
t ok tailscale status
t ok aplay -l
t ok mount
t ok mkdir -p /srv/cache/pip
t ok chown -R user:user /srv/cache/pip
t ok rm -rf /srv/opt/alpine-root
t ok install -m 755 /srv/tmp/gate-src /usr/local/bin/s9-newtool-test
# --- refused: never-allowed commands ---
for c in sh bash busybox env su sudo python3 node npm vi sed awk tee cp mv ln chmod dd tar find xargs curl wget reboot poweroff adduser addgroup passwd visudo nmcli modprobe sysctl umount mkfs.ext4 crontab kill mpv speaker-test camilladsp amixer; do t no $c x; done
t no /srv/code/tool
t no /usr/local/bin/claude
t no ./script.sh
# --- refused: allowed commands used the wrong way ---
t no apk add sudo
t no apk add openssh-server
t no apk add --allow-untrusted foo
t no apk add -X http://example.com/repo foo
t no apk add ./evil.apk
t no apk add /tmp/evil.apk
t no apk del openssh
t no apk del busybox
t no apk upgrade
t no apk add -u samba
t no apk fix --root /srv/x foo
t no rc-service sshd stop
t no rc-service tailscale restart
t no rc-service networkmanager stop
t no rc-service nosuchservice start
t no rc-update del sshd default
t no rc-update add aria2 boot
t no cat /etc/shadow
t no cat /etc/sudoers.d/s10-sudo
t no head /root/.npmrc
t no cat /proc/1/environ
t no cat /proc/1/root/etc/shadow
t no cat /dev/sda14
t no cat /etc/NetworkManager/system-connections/HomeWiFi.nmconnection
t no cat /srv/../etc/shadow
t no grep -r root /etc
t no grep -ex /etc/shadow
t no grep root /etc/shadow
t no wc --files0-from=/etc/shadow
t no dmesg -c
t no ss -K dst 1.2.3.4
t no ss -tlnK
t no ip link set wlan0 down
t no ip route del default
t no ip netns exec x sh
t no iw dev wlan0 disconnect
t no iw reg set US
t no iptables-legacy -F
t no iptables-legacy -P INPUT ACCEPT
t no iptables-legacy -A INPUT -j ACCEPT
t no sshd.pam -D
t no sshd.pam -T -f /srv/x
t no tailscale down
t no tailscale up --ssh
t no tailscale set --exit-node=x
t no aplay /srv/files/test.wav
t no aplay -D hw:3,0 x.wav
t no mount /dev/sda25 /mnt
t no blkid -c /etc/passwd
t no mkdir -p /etc/newdir
t no mkdir -m 777 /srv/x
t no chown -R user:user /etc
t no chown root:root /srv/x
t no chown user:user /srv/../etc/passwd
t no rm -rf /srv
t no rm -rf /srv/code
t no rm -rf /etc/NetworkManager
t no rm -rf /srv/code/../../etc
t no install -m 4755 /srv/tmp/gate-src /usr/local/bin/foo
t no install -m 755 /srv/tmp/gate-src /usr/local/bin/ls
t no install -m 755 /srv/tmp/gate-src /usr/local/bin/claude
t no install -m 755 /srv/tmp/gate-src /usr/local/bin/s10-status
t no install -m 755 /srv/tmp/gate-src /usr/local/bin/camilladsp
t no rc-service camilladsp restart
t no rc-update del camilladsp default
t no install -m 755 /srv/tmp/gate-src /usr/local/bin/apk
t no install -m 755 /srv/tmp/gate-src /etc/local.d/x.start
t no install -m 755 /etc/shadow /usr/local/bin/foo
echo "part 1 (--check): passed $pass, failed $fail"

# --- part 2: real runs through sudo ---
r=0
bad() { echo "FAIL real: $1"; r=1; }
sudo -n $G apk info -e busybox >/dev/null 2>&1 || bad "apk info"
sudo -n $G mkdir -p /srv/tmp/gate-test/a || bad "mkdir"
[ "$(stat -c %U /srv/tmp/gate-test)" = root ] || bad "mkdir result not root-owned"
sudo -n $G chown -R user:user /srv/tmp/gate-test || bad "chown"
[ "$(stat -c %U /srv/tmp/gate-test/a)" = user ] || bad "chown did not apply"
ln -s /etc/shadow /srv/tmp/gate-test/link
sudo -n $G cat /srv/tmp/gate-test/link >/dev/null 2>&1
[ $? -eq 77 ] || bad "a symlink to a secret was readable"
sudo -n $G chown -R user:user /srv/tmp/gate-test >/dev/null 2>&1
[ "$(stat -c %U /etc/shadow)" = root ] || bad "chown followed a symlink to /etc/shadow"
sudo -n $G rm -rf /srv/tmp/gate-test || bad "rm"
[ ! -e /srv/tmp/gate-test ] || bad "rm left the folder"
rm -f /tmp/gate-proof
sudo -n $G sh -c "touch /tmp/gate-proof" >/dev/null 2>&1
[ $? -eq 77 ] && [ ! -e /tmp/gate-proof ] || bad "sh ran"
sudo -n $G cat /etc/hostname | grep -q . || bad "pipe after the gate"
sudo -n true 2>/dev/null && bad "sudo works without a password for other commands"
[ $r -eq 0 ] && echo "part 2 (real runs): all passed" || echo "part 2 (real runs): FAILURES above"
[ $fail -eq 0 ] && [ $r -eq 0 ]
