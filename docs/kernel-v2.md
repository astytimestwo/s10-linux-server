# Kernel v2: what a server needed from the kernel

Three days of running the phone as a server turned up four things only a kernel change could fix. They went into one rebuild and one flash (package release `r2`, patch [0005](../pmaports-patches/0005-linux-samsung-beyond1lte-downstream-kernel-v2-for-se.patch)).

| Problem | Cause | Fix |
|---|---|---|
| No way to put a DSP between audio players and the sound card | No ALSA loopback device | `CONFIG_SND_ALOOP=y` |
| Load average stuck at ~11 on an idle phone | 11 TrustZone driver threads sleeping "uninterruptible" | a 38-line patch: they sleep as "idle" |
| `unshare -r` → "Operation not permitted" for normal users | Samsung's "Linux on DeX" hardening | `CONFIG_LOD_SEC` off |
| One port per firewall rule, no overlayfs | Options not set | `NETFILTER_XT_MATCH_MULTIPORT=y`, `OVERLAY_FS=y` |

Also switched on while at it, to avoid another flash later: `FHANDLE` and `USB_NET_RNDIS_HOST` (an Android phone's USB tethering as an uplink).

## The load average of 11

`uptime` showed 11.5 with the CPU 97 % idle. Linux's load average counts runnable tasks **and** tasks in uninterruptible sleep (state `D`), and there were exactly eleven of those:

```
$ ps -eo stat,comm | awk '$1 ~ /^D/'
D ree_time
D scsi_srpmb_work
D tz_iwsock
D tz_worker_threa     (x8, one per CPU)
```

All belong to `tzdev`, Samsung's driver for the TrustZone "secure world". They wait forever for work with `wait_event()` / `TASK_UNINTERRUPTIBLE`. Since Linux 4.2 there is `TASK_IDLE` (uninterruptible, but not counted as load), and 4.17 added `wait_event_idle()` for exactly this. The patch gives `tz_iwsock.c` a local `tz_wait_event_idle()` built on `___wait_event(..., TASK_IDLE, ...)` and switches the worker pool's `prepare_to_wait()` to `TASK_IDLE`. Wake-ups use `TASK_NORMAL`, which still matches. Behaviour is unchanged; only the accounting is.

Result: the threads show state `I`, nothing is in `D`, and the load average is ~0.3 a minute after boot.

## User namespaces

The kernel log named the culprit as soon as anyone tried:

```
LOD: blocking USERNS from non-root PROC unshare PID 11075 UID 10000
```

`CONFIG_LOD_SEC` ("kernel security re-enforcement for Linux on DeX") adds a check in `kernel/user_namespace.c` that refuses new user namespaces unless the caller is root. With the option off, `unshare -U` and `unshare -r` work for normal users, so rootless sandboxes and containers do too.

## Why nf_tables stayed off

It was on the wish list. But a built-in nf_tables can be reached by any local program once that program can create a user namespace, and on a 4.14 kernel that path has known local-root exploits (CVE-2024-1086 is the famous one). Unprivileged user namespaces were wanted; nothing here needs nf_tables (the firewall uses `iptables-legacy`, Tailscale runs with `--netfilter-mode=off`). So: one or the other, and user namespaces won.

## Swapping only the kernel, from the running system

A fresh `pmbootstrap install` would have produced a new boot image, but also a new initramfs and, worse, new root/boot filesystem UUIDs baked into the kernel command line, which would not match the system already on the phone. So the boot image was not rebuilt. [`scripts/repack-bootimg.py`](../scripts/repack-bootimg.py) takes the image that is known to boot and replaces only the kernel:

```bash
python3 repack-bootimg.py selftest boot-v1.img          # must print IDENTICAL
python3 repack-bootimg.py swap boot-v1.img vmlinuz-r2 boot-v2.img
```

- The self-test rebuilds the old image from its own parts; if the result is not byte-identical, the tool refuses to do the swap.
- In the new image only the kernel, the kernel-size field and the header checksum differ. The initramfs, command line, load addresses and Samsung's `SEANDROIDENFORCE` trailer are untouched.

Checks before flashing:

1. The build log shows the patch being applied; the config embedded in both kernels (`scripts/extract-ikconfig`) differs only in the intended options.
2. The new image fits the boot partition (50.8 MB of 57.7 MB).
3. The phone's boot partition was dumped first (`dd if=/dev/sda14`) and compared with the known-good image: identical. That dump, the PC copy and the original Odin file are three ways back.

The flash itself ran on the phone, no Odin and no recovery mode:

```sh
dd if=boot-v2.img of=/dev/sda14 bs=4M conv=fsync     # sda14 = PARTNAME=boot on this phone, check yours
echo 3 > /proc/sys/vm/drop_caches
head -c <image size> /dev/sda14 | sha256sum           # must equal the image's checksum
reboot
```

The phone was back on the network 55 seconds later. Had it not been: TWRP (Vol Up + Bixby + Power), `adb push` the old image, `dd` it back.

> ⚠ Writing the wrong partition can brick the phone. Check `PARTNAME` in `/sys/class/block/<dev>/uevent`, the partition size and the image checksum before `dd`, and be next to the phone for the reboot.

## After the flash

- Sound cards are renumbered: the built-in `Loopback` card is card 0, so anything that addressed cards by number must use names (`hw:Loopback`, `hw:Device`).
- The loopback's device nodes belong to `root:audio` like every other sound device; see [`audio/`](../audio/) for how access is split.
- The package database on the phone still lists the old kernel release; nothing on the phone uses `/boot` for booting, so this is cosmetic. Don't flash the phone's own `/boot/boot.img`: its initramfs is regenerated on the device and has never been booted.
