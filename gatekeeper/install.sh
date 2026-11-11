#!/bin/sh
# Install the rule-based s10-sudo gatekeeper. Run as root on the S10 from the folder holding
#   s10-sudo  sudoers-s10-sudo
# Safe to run again. Also removes the earlier reviewer-based version if it is there.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set -e
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
D=$(cd "$(dirname "$0")" && pwd)
for f in s10-sudo sudoers-s10-sudo; do [ -f "$D/$f" ] || { echo "missing $D/$f"; exit 1; }; done
sh -n "$D/s10-sudo"

# 1. Remove the reviewer-based version (account, login helper, policy, config)
rm -f /usr/local/sbin/s10-reviewer-login /etc/s10-sudo/reviewer-prompt.md /etc/s10-sudo/config /etc/s10-sudo/reviewer.env
if id s10-reviewer >/dev/null 2>&1; then deluser s10-reviewer 2>/dev/null || true; fi
rm -rf /var/lib/s10-reviewer

# 2. Baselines: what counts as "the base system". Written once and never overwritten, so
#    services and packages added later stay manageable through the gate.
install -d -o root -g root -m 755 /etc/s10-sudo
[ -s /etc/s10-sudo/baseline-services ] || ls /etc/init.d > /etc/s10-sudo/baseline-services
# installed packages plus the names in apk's "world" list (apk del acts on those names)
[ -s /etc/s10-sudo/baseline-packages ] || { apk info 2>/dev/null; sed 's/[<>=~].*$//' /etc/apk/world 2>/dev/null; } | sort -u > /etc/s10-sudo/baseline-packages
chown root:root /etc/s10-sudo/baseline-services /etc/s10-sudo/baseline-packages
chmod 644 /etc/s10-sudo/baseline-services /etc/s10-sudo/baseline-packages

# 3. The gatekeeper and its log
install -o root -g root -m 755 "$D/s10-sudo" /usr/local/sbin/s10-sudo
[ -e /var/log/s10-sudo.log ] || { : > /var/log/s10-sudo.log; chmod 644 /var/log/s10-sudo.log; }

# 4. sudo rule, installed only if it validates. A broken sudoers file would lock root out
#    of a phone with no screen, so check before and after, and undo on any doubt.
T=$(mktemp /run/s10-sudoers.XXXXXX)
cp "$D/sudoers-s10-sudo" "$T"
if ! visudo -cf "$T" >/dev/null 2>&1; then
	rm -f "$T"
	echo "ERROR: the sudo rule failed validation. NOT installed."
	exit 2
fi
install -o root -g root -m 440 "$T" /etc/sudoers.d/s10-sudo
rm -f "$T"
if ! visudo -c >/dev/null 2>&1; then
	rm -f /etc/sudoers.d/s10-sudo
	echo "ERROR: sudo's full configuration failed validation with the new rule. Rule REMOVED again."
	exit 2
fi
echo "s10-sudo (rule-based) installed: $(wc -l < /etc/s10-sudo/baseline-services) base services, $(wc -l < /etc/s10-sudo/baseline-packages) base packages."
