# Galaxy S10 → 24/7 Linux home server

An old Samsung Galaxy S10 (Exynos 9820, 8 GB RAM) running real Linux instead of Android, as a silent, always-on home server that draws roughly 2 W (estimate). No screen, no Android: the phone boots [Nura](https://nura.eco) (the renamed postmarketOS, with Alpine Linux underneath) on a patched downstream 4.14 kernel, and everything is reached over SSH and the network.

This repo has everything that was needed to get there: the kernel and device-package patches that made an abandoned port boot again, the configs and scripts running on the phone, and notes on every problem hit along the way and how it was fixed.

> **Status:** set up on 7–8 Nov 2026 and running since. Tested so far: recovery from reboots (watchdog-triggered and manual), a simulated 5 GHz Wi-Fi failure (automatic fallback to 2.4 GHz), and a quiet night of ~16 h idling at ~33 °C. Longer-term reliability is still being measured.

## What it does

| Job | How |
|---|---|
| Remote shell + coding agent | SSH (keys only) + tmux; Claude Code runs on the phone and keeps working with the laptop closed |
| Reach it from anywhere | Tailscale (direct connection, no port forwarding) |
| File server | Samba share for Windows Explorer, on a 107 GB ext4 partition (old Android userdata) |
| Download station | aria2 + AriaNg web UI: paste a link from any device, the phone finishes it |
| Ad blocking | AdGuard Home (installed, not configured yet) |
| Audio | USB DAC detected (ALSA), CamillaDSP 4.1.3 built from source for musl |
| Looking after itself | firewall, hardware watchdog, Wi-Fi watchdog with 5 GHz → 2.4 GHz fallback, temperature logger, vibration signals at boot |

## Hardware status on this kernel

| Works | Doesn't work | Untested |
|---|---|---|
| Wi-Fi 2.4 + 5 GHz (bcmdhd) | Display (panel driver fails, screen stays black) | USB Ethernet adapters (drivers are in the kernel) |
| USB host: DAC, storage | Built-in speaker/mic (no ALSA card) | Cameras, modem/SIM, sensors, NFC, Bluetooth |
| Charging with an 80 % cap | USB networking to **Windows** (works from Linux/WSL) | Fast charging |
| Hardware watchdog | nf_tables, iptables multiport (not in the kernel config) | |
| Vibration motor, rear flash LED | | |
| Thermal throttling (holds 83 °C under full load) | | |

Details and numbers: [docs/hardware-and-results.md](docs/hardware-and-results.md).

## ⚠ Safety

A lithium battery on a charger 24/7 deserves some care:
- Keep the phone uncovered with air around it, not in a drawer or on a heater. Idle it runs ~30 °C; a sustained full load reaches 83 °C at the CPU.
- Use the 80 % charge cap (in `s10-tune.start`); sitting at 100 % is what makes batteries swell.
- If the back starts to bulge, the battery is swelling: unplug it and stop using it.

## Repo layout

```
pmaports-patches/   4 patches on top of pmaports (kernel + device package); the port doesn't boot without them
rootfs/             files as they sit on the phone (etc/, usr/local/, home/user/)
scripts/            helpers: partition backup, aria2 install, SSH over USB via WSL
docs/               build + flash, setup, services, problems and fixes, hardware + results
```

## Read next

1. [docs/build-and-flash.md](docs/build-and-flash.md): building the image with pmbootstrap and flashing it with Odin + TWRP
2. [docs/setup.md](docs/setup.md): first boot without a screen, Wi-Fi, storage, firewall, watchdog
3. [docs/services.md](docs/services.md): Tailscale, Samba, aria2, AdGuard, Claude Code, audio
4. [docs/problems-and-fixes.md](docs/problems-and-fixes.md): bootloops, a firewall lockout, a 3-minute boot, "connected but unreachable" Wi-Fi, Spotify blocking librespot
5. [docs/hardware-and-results.md](docs/hardware-and-results.md): what works, thermals, storage and network speed

## Is this for you?

You need a **Galaxy S10 (SM-G973F, Exynos)**, a **Windows PC** (the flashing guide uses Odin; on Linux you'd use Heimdall, not covered here) with WSL for building, and comfort with a terminal. Flashing wipes the phone, trips Knox permanently, and may cost you a few evenings in recovery mode. The device port is archived upstream, so a future pmaports change may break it; the patches here are tested against pmaports as of November 2026 and kernel 4.14.316.

## Glossary

- **postmarketOS / Nura**: a Linux distribution for phones (Nura is its new name); based on Alpine Linux.
- **pmaports / pmbootstrap**: postmarketOS's package recipes, and the tool that builds an image from them.
- **Downstream kernel**: the phone maker's (here LineageOS's) old Android kernel, as opposed to mainline Linux.
- **Odin**: Samsung's Windows flashing tool. **Download mode**: the bootloader mode Odin talks to.
- **TWRP**: a custom recovery (a tiny Linux with a touchscreen UI) used for backups and writing partitions.
- **vbmeta**: Android Verified Boot data; flashing a "verification disabled" one lets the phone boot a custom kernel.
- **Knox**: Samsung's security flag; unlocking trips it permanently (Samsung Pay etc. stop working forever).
- **OpenRC**: the init system (starts services). **doas**: a smaller `sudo`. **musl**: Alpine's C library (glibc binaries don't run).
- **BSSID**: the hardware address of one Wi-Fi access point/band. **pstore**: kernel logs kept in RAM across a reboot.

## Credits

- [postmarketOS / Nura](https://nura.eco) and the original `samsung-beyond1lte-downstream` port maintainers
- LineageOS for the Exynos 9820 kernel the port is based on
- TWRP, Tailscale, aria2 + AriaNg, CamillaDSP, Samba, AdGuard Home

## License

MIT for everything written here (see [LICENSE](LICENSE)). The files in `pmaports-patches/` modify pmaports and the Linux kernel and fall under those projects' licenses (the kernel patch is GPL-2.0).
