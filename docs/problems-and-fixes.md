# Problems and fixes

Everything that went wrong between "flash the image" and "runs unattended for days", in order. Each one has the symptom, how it was found, and the fix. Most were found by reading `last_kmsg` / pstore logs from TWRP after a failed boot.

## 1. Bootloop: "junk in compressed archive"

**Symptom:** Samsung logo, warning screen, logo, warning… forever.
**Found:** TWRP `/proc/reset_reason` = `KPON` (kernel panic); `last_kmsg`: `rootfs image is not initramfs (junk in compressed archive)` then `Unable to mount root fs`.
**Cause:** current mkinitfs compresses the initramfs with **zstd**, but this old kernel only supports gzip and lz4. The port's `deviceinfo` never said which to use.
**Fix:** `deviceinfo_initfs_compression="gzip"` (+ `_extra_`) → patch [0002](../pmaports-patches/0002-device-samsung-beyond1lte-downstream-force-gzip-init.patch).

## 2. Hang at the logo: "failed to mount subpartitions"

**Symptom:** logo frozen, nothing on USB for 10 minutes.
**Found:** the initramfs console in pstore (`pmsg-ramoops-0`): `Mount subpartitions of /dev/sda25` ×12 → `ERROR: failed to mount subpartitions!`. Reproduced in TWRP with the initramfs's own `losetup`: the loop device stayed at 512-byte sectors and found 0 partitions.
**Cause:** the rootfs image uses 4096-byte sectors. New util-linux sets that through the `LOOP_CONFIGURE` ioctl. This kernel's Android backport of `loop_configure()` **checks** `block_size` but **never applies it** (upstream Linux 5.8+ does). Older initramfs versions used a different path, which is why the port used to boot.
**Fix:** a 13-line kernel patch applying the block size to the queue before the partition scan → patch [0003](../pmaports-patches/0003-linux-samsung-beyond1lte-downstream-apply-LOOP_CONFI.patch).

## 3. Linux up, but Windows sees "Android ADB Interface"

**Found:** the gadget enumerated as `18D1:D001`, and on our PC a leftover vendor ADB driver (from a vivo phone) claimed that ID, so Windows never loaded its USB networking driver. Any PC with such a driver installed hits the same thing.
**Fix:** use the Linux Foundation composite-gadget ID `1D6B:0104` → patch [0004](../pmaports-patches/0004-device-samsung-beyond1lte-downstream-use-1d6b-0104-U.patch).

## 4. USB networking to Windows doesn't work at all

**Found:** phone-side dmesg: every packet from Windows rejected with `Wrong NDP SIGN` / `ncm_unwrap_ntb Dropped`. The 4.14 NCM gadget doesn't understand Windows' NCM framing.
**Workaround:** Wi-Fi for normal use; for emergencies, pass the USB device into WSL (Linux's NCM host driver is fine) with usbipd: [`scripts/s10-usb.ps1`](../scripts/s10-usb.ps1). Proper fix would be an RNDIS gadget or a backported f_ncm (not done).

## 5. zram silently off

`zramstart` failed: the default algorithm zstd isn't in the kernel, and `modprobe zram` failed (it's built in). Fix: [`etc/deviceinfo`](../rootfs/etc/deviceinfo) with lz4.

## 6. Locked out by my own firewall

**Symptom:** after loading the firewall, SSH and ping were gone (and USB networking from Windows never worked, see 4). The auto-undo timer didn't bring it back.
**Cause:** `iptables-legacy` without the `iptables` package has no xtables plug-ins. Some rules loaded, then the rest (including the ones allowing SSH and USB) failed, with the DROP policy already set.
**Recovery:** TWRP → mount the root fs → rename the boot script → reboot.
**Fix:** install `iptables` (the plug-ins), load rules with `iptables-legacy-restore` (all-or-nothing), refuse to load if the plug-ins are missing, test live with an undo timer started detached ([setup.md §5](setup.md)).

## 7. Three-minute boot

**Symptom:** SSH only reachable ~3 minutes after power-on; at first it looked like Wi-Fi was broken.
**Found:** dmesg showed firmware requests for `mfc_fw.bin` timing out at 66, 127 and 187 s; NetworkManager started at 188 s.
**Cause:** udev's `v4l_id` probes the MFC video codec, which asks for firmware that isn't there; each request waits 60 s and udev settle waits for all of them.
**Fix:** empty override [`60-persistent-v4l.rules`](../rootfs/etc/udev/rules.d/60-persistent-v4l.rules). SSH now comes back 35–45 s after a reboot.

## 8. "Connected" to Wi-Fi but unreachable

**Symptom:** after a reboot the phone was gone: not on the LAN, offline in Tailscale. Pressing the power button just rebooted it into the same state. With no screen, "off" and "running but offline" look identical.
**Found (over USB via WSL):** NetworkManager said connected, DHCP worked, but the router's ARP entry stayed `incomplete` and the gateway didn't answer. The router had started broadcasting the same SSID on **5 GHz**, and after the reboot the phone joined that band, where unicast didn't work.
**First fix that didn't hold:** pinning NetworkManager to 2.4 GHz (`802-11-wireless.band bg`). The Broadcom firmware picks the band itself and later moved back to 5 GHz anyway (where it then worked fine, ~155 Mbit/s).
**Real fix:** keep 5 GHz for speed, and let [`s10-netwatch`](../rootfs/usr/local/sbin/s10-netwatch) lock the profile to the 2.4 GHz access point's BSSID if 5 GHz stops answering for ~4 minutes (a BSSID lock *is* respected). A daily retry drops the lock. Tested live with a simulated outage (the trigger forced, the switching real): reachable on 2.4 GHz 23 s after the switch, back on 5 GHz 33 s after the retry. Plus boot buzz signals ([`s10-bootsignal.start`](../rootfs/etc/local.d/s10-bootsignal.start)) so you can feel whether it booted and got online.

## 9. aria2 dead after every reboot

`failed to bind TCP port 6800 … Name has no usable address`: it started before Wi-Fi had an address. Fix: `supervisor=supervise-daemon` with respawn in [`etc/conf.d/aria2`](../rootfs/etc/conf.d/aria2).

## 10. Logs that go nowhere

`logger` messages never show up in the system log on this image (logbookd). Every script here writes its own log file in `/var/log/` as well.

## 11. Spotify blocks librespot

The Spotify account link works, then every track fails with `error audio key 0 1` and the app sits on "connecting…". Spotify-side change: accounts created after roughly 2024/2025 can't get audio keys through librespot; all versions affected, no workaround ([librespot#1649](https://github.com/librespot-org/librespot/issues/1649)). Not fixable on the phone.

## Smaller ones

- The first `apk add` of some packages ran the mkinitfs trigger and rewrote `/boot/boot.img`. Harmless here: on this device boot-deploy only writes files in `/boot`; the BOOT partition is only changed by flashing.
- The kernel and device packages built locally exist only in the phone's apk database (not in any repo), so `apk upgrade` can't replace the patched kernel by accident.
- Plain `ssh` failed with "Host key verification failed" because the host key was saved in a separate known_hosts file; an `~/.ssh/config` entry fixed it.
