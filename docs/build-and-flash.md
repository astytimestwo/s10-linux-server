# Build and flash

What was used: Windows 11 + WSL2 (Debian 13) for building, Odin 3.14.4 + TWRP for flashing, a Galaxy S10 **SM-G973F** on stock firmware `G973FXXSGHWC1` (bootloader binary **G**). From a wiped phone to SSH took one long evening, mostly spent on the three boot failures in [problems-and-fixes.md](problems-and-fixes.md).

> ⚠ **Before you start**
> - Unlocking the bootloader **wipes the phone** and trips Knox **permanently**.
> - Download the exact stock firmware for your phone and bootloader binary, plus Odin and Samsung's USB driver, and keep them **on the PC**. That's your only way back to Android.
> - Don't install Samsung updates afterwards: a newer bootloader binary can make older firmware unflashable.
> - Commands below marked *(PC)* run in **Git Bash or WSL** on Windows, not in `cmd`. `adb` comes from Android's platform-tools.

## 1. Build the image (WSL)

```bash
# pmbootstrap from Nura's GitLab (3.12.1 at the time)
git clone https://gitlab.nura.eco/nura/pmbootstrap ~/src/pmbootstrap
mkdir -p ~/.local/bin && ln -s ~/src/pmbootstrap/pmbootstrap.py ~/.local/bin/pmbootstrap   # so "pmbootstrap" works
pmbootstrap init
#   device: samsung-beyond1lte-downstream (it's in device/archived/)
#   UI: none, init: OpenRC, user name: user, SSH keys: yes (bakes your ~/.ssh/*.pub into the image)
#   extra packages, for example: tmux,iptables,iptables-legacy,networkmanager,networkmanager-wifi,iw
```

Apply the patches in [`../pmaports-patches/`](../pmaports-patches/) (0001–0004 make the port boot; 0005 is the optional [kernel v2](kernel-v2.md)) to the pmaports checkout pmbootstrap uses (`pmbootstrap config aports` prints its path). `git am` needs a git identity (`git config --global user.name/user.email`).

```bash
cd "$(pmbootstrap config aports)"
git am /path/to/s10-linux-server/pmaports-patches/*.patch
pmbootstrap build linux-samsung-beyond1lte-downstream --force   # ~35 min the first time (clang), ~6 min with ccache
pmbootstrap install
pmbootstrap export      # links boot.img and the rootfs image into /tmp/postmarketOS-export/
```

- `boot.img` must fit the BOOT partition (57,671,680 bytes); ours was 50.7 MB.
- The rootfs image (`samsung-beyond1lte-downstream.img` in the export folder; called `nura-rootfs.img` below) was 848 MB. SYSTEM is 5.98 GB; the root partition grows to fill it on first boot.

Make a **verification-disabled vbmeta** so the bootloader accepts the unsigned boot image:

```bash
avbtool make_vbmeta_image --flags 2 --padding_size 4096 --output vbmeta.img
```

(`avbtool` is in Debian's `avbtool` package, or `android-tools-avbtool` on Alpine.)

Pack two Odin files (plain `tar`, no compression; Odin wants the file names exactly `recovery.img`, `boot.img`, `vbmeta.img` inside):

| File | Contents | Odin slot |
|---|---|---|
| `1-AP-twrp-vbmeta.tar` | TWRP `recovery.img` (official 3.7.0_9-1 for beyond1lte) + `vbmeta.img` | AP |
| `2-AP-nura-boot-vbmeta.tar` | Nura `boot.img` + the same `vbmeta.img` | AP |

## 2. Flash

1. **Unlock** (wipes the phone): Settings → About phone → Software information → tap *Build number* 7× → Developer options → **OEM unlocking** on. (On some firmware the toggle only appears after the phone has been online for a while.) Power off, unplug, hold **Vol Down + Bixby** and plug in USB → warning screen → **long-press Vol Up** → unlock. Afterwards, set Android up once (skip accounts) and check OEM unlocking still says it's unlocked.
2. **TWRP:** Download mode again, Odin → AP = `1-AP-twrp-vbmeta.tar`, *Auto Reboot off* → Start. Then hold **Vol Down + Power** ~7 s and, the moment the screen goes black, switch to **Vol Up + Bixby + Power** until TWRP shows. (If Android boots first it can restore the stock recovery; redo the step.)
3. **Back up the phone's unique partitions** while TWRP runs as root *(PC)*. EFS holds the IMEI; without it the phone has no mobile network, ever.
   ```bash
   adb push scripts/backup-partitions.sh /tmp/
   adb shell "OUT=/tmp/partition-backup sh /tmp/backup-partitions.sh"
   adb pull /tmp/partition-backup .
   cd partition-backup && sha256sum -c SHA256SUMS      # every line must say OK
   ```
   Keep a second copy of that folder somewhere other than this PC.
4. **Rootfs → SYSTEM** *(PC)*. ⚠ `dd` overwrites whatever partition you name. Check the `by-name` listing first and make sure the target is **system** (the 5.98 GB one), not userdata or EFS.
   ```bash
   adb shell ls -l /dev/block/platform/13d60000.ufs/by-name/ | grep -i system
   adb shell "umount /system_root /system 2>/dev/null; true"
   adb push nura-rootfs.img /tmp/              # TWRP's /tmp is RAM; fine with 8 GB
   adb shell "dd if=/tmp/nura-rootfs.img of=/dev/block/platform/13d60000.ufs/by-name/system bs=4M && sync"
   # verify what actually landed on the partition, not just the file:
   size=$(stat -c %s nura-rootfs.img); sha256sum nura-rootfs.img
   adb shell "head -c $size /dev/block/platform/13d60000.ufs/by-name/system | sha256sum"   # must match
   adb reboot download
   ```
5. **Boot image last:** Odin → AP = `2-AP-nura-boot-vbmeta.tar`, Auto Reboot on.

The screen stays black (the panel driver doesn't work); that's normal. If the PC sees nothing on USB after a minute, unplug and replug the cable. Continue with [setup.md](setup.md).

## Recovery cheat sheet

| Situation | Keys / commands |
|---|---|
| Force restart | Vol Down + Power, ~7 s |
| TWRP | Vol Up + Bixby + Power, held through the restart |
| Download mode (Odin) | power off, unplug, Vol Down + Bixby while plugging in USB |
| Read Linux logs from TWRP | `/sys/fs/pstore/` and `/proc/last_kmsg` survive a reboot |
| Back to stock Android | Odin with the full stock firmware (BL + AP + CP + CSC) |

**Mounting the Nura root fs in TWRP** (to fix a config file, add Wi-Fi, disable a broken script): the rootfs image inside SYSTEM has its own partition table with 4096-byte sectors, so mount the root sub-partition by offset. The numbers below are from our image; get yours from `fdisk -l nura-rootfs.img` on the PC (start sector of partition 2 × 4096).

```sh
adb shell
mkdir -p /mnt/nura
losetup -o $((124928*4096)) /dev/block/loop7 /dev/block/platform/13d60000.ufs/by-name/system
mount -t ext4 /dev/block/loop7 /mnt/nura
# ... edit files under /mnt/nura/etc/... ...
umount /mnt/nura; losetup -d /dev/block/loop7
```
