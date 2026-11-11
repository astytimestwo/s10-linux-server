#!/bin/sh
# Remove the s10-sudo gatekeeper (run as root). The sudo rule goes first.
# Keeps the log and the baselines unless called with --purge.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
rm -f /etc/sudoers.d/s10-sudo
rm -f /usr/local/sbin/s10-sudo
[ "$1" = "--purge" ] && rm -rf /etc/s10-sudo /var/log/s10-sudo.log
echo "s10-sudo removed."
