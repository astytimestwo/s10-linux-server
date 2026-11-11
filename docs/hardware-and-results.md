# Hardware status and measurements

Phone: Galaxy S10 SM-G973F (Exynos 9820: 2× M4 2.73 GHz, 2× A75, 4× A55; 8 GB RAM; 128 GB UFS 2.1). Kernel: `samsung-beyond1lte-downstream` 4.14.316 + the patches in this repo. Distro: Nura edge (postmarketOS, Alpine), OpenRC.

## What works

| Part | Status | Notes |
|---|---|---|
| Wi-Fi (Broadcom BCM4375, bcmdhd) | ✅ | 2.4 + 5 GHz; firmware roams between bands by itself and ignores NetworkManager's band setting (a BSSID lock works) |
| USB host | ✅ | USB audio class DAC detected; USB storage; RTL8152/8153 and AX88179 Ethernet drivers in the kernel config (not tested with hardware yet) |
| USB gadget (to a PC) | ⚠ | NCM works from Linux/WSL, **not from Windows** (packets dropped) |
| Charging + charge cap | ✅ | `batt_full_capacity` = 80 → holds at 80 %, runs off the charger. 5 V only so far (no fast-charge handshake seen), plenty for a server |
| Battery reporting | ✅ | capacity, temperature, current, health; fuel gauge says 74 % of design capacity on this unit |
| Hardware watchdog | ✅ | s3c2410; reboot 63 s after the daemon is killed |
| Thermal | ✅ | throttles cleanly, holds 83 °C under full load |
| Vibration motor | ✅ | `/sys/class/timed_output/vibrator/enable` (ms) |
| Rear flash LED | ✅ | `/sys/class/leds/torch-sec1/brightness` (0–15) |
| Hardware RNG | ✅ | `crng init done` at ~1 s, no entropy wait |
| zram | ✅ | after switching to lz4 |
| Display | ❌ | panel driver fails (`failed to write seqtbl`); stays black |
| Built-in speaker/mic | ❌ | Samsung abox audio has no ALSA card (firmware missing) |
| Cameras, modem/SIM, sensors (sensor hub), NFC, Bluetooth | ❓ | not tested |
| ALSA loopback, overlayfs, multi-port firewall rules, unprivileged user namespaces | ✅ | since [kernel v2](kernel-v2.md) |
| nf_tables | ❌ | left off on purpose (a known local-root surface together with user namespaces on 4.14) |
| CIFS client, zstd initramfs, in-kernel WireGuard, loadable modules | ❌ | not in the kernel config |

## Measurements

**Thermal (stress-ng, 8× matrix multiply, 5 min, on battery):** CPU clusters settle at 83 °C, clocks throttle (big 2.60→1.56 GHz, mid 2.31→1.90, little 1.95→1.46); GPU 64 °C; battery 30→38 °C. No errors; back to 55 °C within seconds. Idle: CPU ~33–36 °C, battery ~27–30 °C (overnight log, ~16 h, plugged in at the 80 % cap).

**Storage:** `/srv` (ext4 on UFS) 204 MB/s write (1 GiB, fsync), 631 MB/s read; root fs write 186 MB/s.

**Network:**
- Internet through a 100 Mbit/s line: 89 Mbit/s download (4 connections, server in Mumbai).
- LAN, phone and PC both on 5 GHz: 19.4 MB/s phone → PC, 13.8 MB/s PC → phone (over SSH). Two Wi-Fi hops share the channel, so ~25–35 MB/s is the realistic ceiling on Wi-Fi; wired USB Ethernet on the phone should get past that (not tested yet).
- Boot to SSH: 35–47 s.

**Load average:** ~11 on an idle system with the original kernel (eleven TrustZone driver threads counted as load), ~0.3 one minute after boot with kernel v2.

**Power:** roughly 2 W at idle (estimate; not measured with a meter). The battery doubles as a small UPS when the charger is unplugged or the power goes out.

**Reliability (tested so far):** hardware watchdog reboot (63 s), two manual reboot tests (back in 47 s), a live 5 GHz → 2.4 GHz fallback, a kernel swap flashed from the running system (back in 55 s), a real overnight run (~16 h, no errors). The router-outage handling (Wi-Fi retries forever, netwatch reboot after 30 min) was only dry-run with simulated failures. Long-term uptime is still being measured.
