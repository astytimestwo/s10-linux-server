#!/bin/bash
# Run inside WSL by s10-usb.ps1: bring up the phone's USB network and SSH in (phone = 172.16.42.1).
# Set KEY to your SSH private key for the phone (a Windows path under /mnt/c works).
KEY=${KEY:-/mnt/c/Users/YOUR_WINDOWS_USER/.ssh/id_ed25519_s10}
set -e
ifc=$(ls /sys/class/net | grep '^enx' | head -1)
[ -n "$ifc" ] || { echo "No USB network in WSL. Is the phone plugged in and booted?"; exit 1; }
sudo ip link set "$ifc" up
sudo ip addr replace 172.16.42.2/24 dev "$ifc"
# ssh refuses keys on /mnt/c (wrong permissions), so use a private temp copy and delete it afterwards
tmpkey=$(mktemp)
trap 'rm -f "$tmpkey"' EXIT
install -m 600 "$KEY" "$tmpkey"
echo "Connecting to the phone over USB via $ifc ..."
ssh -i "$tmpkey" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1 "$@"
