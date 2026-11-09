#!/bin/sh
# S10 download station setup (run as root). Expects in /tmp:
#   aria2.conf    (rootfs/etc/aria2.conf, secret still a placeholder)
#   aria2.secret  (one line, the RPC secret; deleted after use)
#   ariang/       (unzipped AriaNg AllInOne: index.html)
# Packages first: apk add aria2 aria2-daemon busybox-extras-openrc
set -e

# 1. Config with the real secret (root:user 640 so only root and "user" can read it)
[ -f /etc/aria2.conf ] && [ ! -f /etc/aria2.conf.orig ] && cp /etc/aria2.conf /etc/aria2.conf.orig
secret=$(cat /tmp/aria2.secret)
case "$secret" in
	""|*[!A-Za-z0-9]*) echo "secret must be letters and digits only (e.g. head -c 24 /dev/urandom | base64 | tr -dc A-Za-z0-9)"; exit 1 ;;
esac
sed "s|RPC_SECRET_PLACEHOLDER|$secret|" /tmp/aria2.conf > /etc/aria2.conf
chown root:user /etc/aria2.conf
chmod 640 /etc/aria2.conf
rm -f /tmp/aria2.secret

# 2. Run as "user"; refuse to start if /srv isn't mounted (so it never fills the root fs)
cat > /etc/conf.d/aria2 <<'EOF'
# Configuration for /etc/init.d/aria2 (S10: run as user, files land in /srv/files/downloads)
command_user="user"
cfgfile="/etc/aria2.conf"
logfile="/var/log/aria2.log"
# /srv/files only exists when the /srv drive is mounted
required_dirs="/srv/files"
# At boot aria2 can start before Wi-Fi has an address and exit ("failed to bind TCP port 6800").
# supervise-daemon restarts it every 15 s until it stays up (and after any crash).
supervisor="supervise-daemon"
respawn_delay=15
respawn_max=0
EOF
mkdir -p /srv/files/downloads /var/lib/aria2
chown user:user /srv/files/downloads
chown -R user:user /var/lib/aria2
touch /var/log/aria2.log && chown user:user /var/log/aria2.log

# 3. AriaNg web page, served by busybox httpd on port 6880 as "user"
mkdir -p /usr/share/webapps/ariang
cp /tmp/ariang/index.html /usr/share/webapps/ariang/index.html
chmod 644 /usr/share/webapps/ariang/index.html
cat > /etc/conf.d/httpd <<'EOF'
# busybox httpd: serves the AriaNg page for aria2 (Tailscale only, firewall blocks 6880 on the LAN)
HTTPD_OPTS="-p 6880 -h /usr/share/webapps/ariang -u user"
EOF

# 4. Start now and on every boot
rc-update add aria2 default
rc-update add httpd default
rc-service aria2 restart
rc-service httpd restart
echo "aria2 + AriaNg installed"
