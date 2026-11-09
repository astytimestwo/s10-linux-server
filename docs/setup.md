# Setup after the first boot

The phone has no working screen under Linux, so every step happens over the network. Paths below refer to [`../rootfs/`](../rootfs/), which mirrors where each file goes on the phone. The login user is the one you chose in `pmbootstrap init` (`user` here); `doas` is the `sudo` equivalent.

> Files copied from a Windows checkout lose their executable bit. After copying any script (`*.start`, `etc/init.d/*`, `usr/local/sbin/*`, `usr/local/bin/*`) run `doas chmod +x` on it, or OpenRC silently skips it.

## 1. Get a network connection without a screen

Two ways in:

- **Wi-Fi profile from TWRP (easiest).** Mount the Nura root fs in TWRP (see the end of [build-and-flash.md](build-and-flash.md)), then, with `/mnt/nura` as the mount point:
  ```sh
  cp HomeWiFi.nmconnection.example /mnt/nura/etc/NetworkManager/system-connections/HomeWiFi.nmconnection
  # edit SSID + password in it, then:
  chmod 600 /mnt/nura/etc/NetworkManager/system-connections/HomeWiFi.nmconnection
  ln -sf /etc/init.d/networkmanager /mnt/nura/etc/runlevels/default/networkmanager   # wasn't enabled on our image
  ```
  (Example file: [`HomeWiFi.nmconnection.example`](../rootfs/etc/NetworkManager/system-connections/HomeWiFi.nmconnection.example). The symlink target is the path *inside* Nura, so `/etc/init.d/...` without the prefix is correct.)
- **USB cable.** The phone is `172.16.42.1` over USB networking. From **Linux** this just works. From **Windows** it doesn't: this kernel's NCM gadget rejects every packet from Windows' driver ("Wrong NDP SIGN"). Workaround: pass the USB device to WSL with usbipd and SSH from there, see [`scripts/s10-usb.ps1`](../scripts/s10-usb.ps1). Unplug and replug the cable ~1 min after power-on; the USB controller only starts device mode on a cable attach event.

Find the phone's Wi-Fi address in your router's list of connected devices (hostname from `pmbootstrap init`), then:

```bash
ssh user@<s10-lan-ip>
```

Give it a fixed address (DHCP reservation) in the router so it doesn't move.

## 2. Basics

```sh
doas apk add iptables iptables-legacy iw tmux htop curl logrotate
doas rc-update add ntpd default; doas rc-update add crond default
```

- **zram:** copy [`etc/deviceinfo`](../rootfs/etc/deviceinfo) to `/etc/deviceinfo` (lz4, 50 %). The default zstd isn't in this kernel, so zram silently failed.
- **Faster boot:** copy [`60-persistent-v4l.rules`](../rootfs/etc/udev/rules.d/60-persistent-v4l.rules) to `/etc/udev/rules.d/`. Without it boot takes ~3 minutes (firmware timeouts, see problems-and-fixes).
- **Wi-Fi keeps retrying:** `autoconnect-retries=0` in the Wi-Fi profile (already in the example). Otherwise, if the router is down at boot, NetworkManager gives up for good.
- **NM leaves the USB gadget alone:** [`10-s10-unmanaged.conf`](../rootfs/etc/NetworkManager/conf.d/10-s10-unmanaged.conf) to `/etc/NetworkManager/conf.d/`.
- **Keys-only SSH:** first confirm you can log in with your key, then copy [`10-keys-only.conf`](../rootfs/etc/ssh/sshd_config.d/10-keys-only.conf) to `/etc/ssh/sshd_config.d/`, check it took effect with `doas sshd -T | grep -i passwordauthentication` (should say `no`; on Alpine the `Include` line comes before any other setting, so the drop-in wins) and `doas rc-service sshd restart`. Keep the SSH session open while you test a second login.
- **Bash as the login shell:** `doas apk add bash shadow && doas chsh -s /bin/bash user`, then copy [`.bashrc`](../rootfs/home/user/.bashrc), [`.bash_profile`](../rootfs/home/user/.bash_profile) and [`.tmux.conf`](../rootfs/home/user/.tmux.conf) to your home folder (`t` = start or re-attach the main tmux session; health line on SSH login; temperatures in the tmux status bar).

## 3. Phone tuning: charge cap, screen off, watchdog

[`etc/local.d/s10-tune.start`](../rootfs/etc/local.d/s10-tune.start) (+ [`etc/conf.d/s10-tune`](../rootfs/etc/conf.d/s10-tune)), run at boot by OpenRC's `local` service:

- **80 % charge cap** via Samsung's `batt_full_capacity` (it resets on every boot, hence the script). The phone stops charging at 80 % and runs straight off the charger; it resumes at ~78 %. Good for a battery that's plugged in forever (see the safety note in the README).
- Screen blanked, Wi-Fi power save off.
- **Hardware watchdog** (`/dev/watchdog`, s3c2410), **off by default**. Test by hand first: `doas watchdog -t 10 -T 60 /dev/watchdog`, then `doas killall -9 watchdog`; the phone should reboot about 60 s later (ours: 63 s). Only then set `ENABLE_WATCHDOG=1` in `/etc/conf.d/s10-tune`. Kernel panics already reboot after 120 s on this kernel (`sysctl kernel.panic` → 120); check yours.

```sh
doas install -m 755 s10-tune.start /etc/local.d/
doas install -m 644 s10-tune /etc/conf.d/s10-tune        # the conf.d file from rootfs/etc/conf.d/
doas rc-update add local default
```

## 4. Storage: the old Android userdata as /srv

USERDATA (~110 GB, 107 GB usable after formatting) is unused by Nura.

> ⚠ `mkfs` erases the partition you give it. Identify it carefully: it's the **largest** partition, named `userdata` in `/dev/block/by-name/` or in `partitions.txt` from the backup. Check with `ls -l /dev/block/by-name/userdata` and `lsblk` before formatting. Formatting the wrong one (EFS, SYSTEM) can brick the phone or erase Linux.

```sh
doas mkfs.ext4 -L srv /dev/<userdata-device>     # label "srv" is required by the mount service
doas blkid /dev/<userdata-device>                 # note the UUID
echo 'UUID=<uuid> /srv ext4 defaults,noatime,noauto,nofail 0 0' | doas tee -a /etc/fstab
doas mkdir -p /srv
doas install -m 755 s10-srv /etc/init.d/s10-srv && doas rc-update add s10-srv boot && doas rc-service s10-srv start
```

[`etc/init.d/s10-srv`](../rootfs/etc/init.d/s10-srv) finds the partition by its label, runs `e2fsck -p` and mounts it. If the check fails, it logs and skips the mount; it never blocks the boot (on a headless box, SSH coming up matters more than /srv). On this image `fsck` and `localmount` aren't in any runlevel, which is why this is a separate service.

Measured: 204 MB/s write, 631 MB/s read.

## 5. Firewall (read this whole section before loading anything)

The kernel has conntrack but **no nf_tables and no `xt_multiport`**, so: iptables-**legacy**, one rule per port.

> ⚠ The rules load at **every boot** and allow SSH over Wi-Fi only from the subnet written in them (`192.168.1.0/24`). If your home network uses another subnet, you lose SSH over Wi-Fi; only USB and Tailscale stay open, and without those the fix is TWRP (see problem 6 in problems-and-fixes). **Edit the subnet first.**

1. Install the **`iptables`** package, not just `iptables-legacy`. The legacy binaries without the xtables plug-ins load *some* rules and then fail, which locked us out for a night.
2. Check the rules: [`rules.v4`](../rootfs/etc/s10-firewall/rules.v4) and [`rules.v6`](../rootfs/etc/s10-firewall/rules.v6). Inbound is dropped except loopback, established connections, USB networking and Tailscale (always), ICMP, DHCP renewals, Tailscale's UDP port, and the commented service ports from the home LAN only. Remove ports for services you don't run.
3. Test live with a safety net. This undo timer runs detached, so it survives your SSH session dying:
   ```sh
   doas mkdir -p /etc/s10-firewall && doas cp rules.v4 rules.v6 /etc/s10-firewall/
   cat > /tmp/fw-undo.sh <<'EOF'
   sleep 120
   for t in iptables-legacy ip6tables-legacy; do $t -P INPUT ACCEPT; $t -F INPUT; done
   EOF
   doas start-stop-daemon --start --background --exec /bin/sh -- /tmp/fw-undo.sh
   doas iptables-legacy-restore < /etc/s10-firewall/rules.v4 && doas ip6tables-legacy-restore < /etc/s10-firewall/rules.v6
   ```
   Open a **new** SSH session within 2 minutes. If it works, cancel the undo: find its PID with `ps | grep fw-undo` and `doas kill <pid>`. (Don't use `pkill -f fw-undo` from a doas shell; the pattern also matches your own shell's command line.) If it doesn't work, wait 2 minutes and the rules are gone.
4. Make it permanent: `doas install -m 755 firewall.start /etc/local.d/` ([`firewall.start`](../rootfs/etc/local.d/firewall.start); needs the `local` service from §3). It uses `iptables-legacy-restore`, which is **all or nothing**: a bad rule means nothing changes, not half a firewall, and it refuses to run if the plug-ins are missing.

## 6. Monitoring and self-healing

| Script | What it does |
|---|---|
| [`s10-templog`](../rootfs/usr/local/sbin/s10-templog) (cron, 5 min) | CSV of CPU/GPU/battery/charger temperatures, battery %, current, load, throttling; alert log at battery ≥ 40 °C, CPU ≥ 70 °C or throttling |
| [`s10-netwatch`](../rootfs/usr/local/sbin/s10-netwatch) (cron, 2 min) | if the router stops answering: 4 min → on 5 GHz lock to the 2.4 GHz access point (BSSID), else reconnect; 10 and 20 min → Wi-Fi radio restart; 30 min → reboot (at most once per 6 h). Daily `retry5` drops the 2.4 GHz lock. **Set `CON`, `SSID` and `BSSID24_DEFAULT` at the top** (`nmcli -f BSSID,FREQ,SSID dev wifi list` shows your router's BSSIDs) |
| [`s10-signal`](../rootfs/usr/local/sbin/s10-signal) + [`s10-bootsignal.start`](../rootfs/etc/local.d/s10-bootsignal.start) | no screen, so the phone vibrates: 1 buzz = booted, 2 buzzes + flash = online, 3 long = no network after 5 min |
| [`s10-status`](../rootfs/usr/local/bin/s10-status) | one-line health summary; `-t` short form for the tmux status bar |

```sh
doas install -m 755 s10-templog s10-netwatch s10-signal /usr/local/sbin/
doas install -m 755 s10-status /usr/local/bin/
doas install -m 755 s10-bootsignal.start /etc/local.d/
doas vi /etc/crontabs/root        # add the lines from rootfs/etc/crontabs/root.example
```

Note: on this image `logger` messages never reach the system log (logbookd), so each script also writes its own log file in `/var/log/`.
