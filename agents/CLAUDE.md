# S10 server notes (shared by every Claude session on this phone)

This is `/home/user/.claude/CLAUDE.md`, the user-level file every session loads. It is maintained by the owner (this repo keeps a copy as `agents/CLAUDE.md`). Last updated 2026-11-11.

## What this machine is

- A Samsung Galaxy S10 (Exynos 9820, 8 cores, 8 GB RAM, ARM64 / `aarch64`) used as a headless home server, hostname `s10`. The screen doesn't work under Linux; it is reached only over Wi-Fi and Tailscale SSH.
- The system is **Nura edge**, the renamed postmarketOS, which is **Alpine Linux edge** underneath. It is not Debian or Ubuntu: there is no `apt`, no `systemd`, no `glibc`.
  - Packages: `apk` (repositories: postmarketOS main, Alpine edge main, community and testing).
  - Services: OpenRC (`rc-service <name> status`, `rc-update`, `rc-status`), not `systemctl`.
  - C library: musl. Programs built for glibc ("Linux ARM64" downloads from project websites) usually won't start.
  - `/bin/sh` is BusyBox ash, and many basic tools are the BusyBox versions with fewer options. Your login shell is bash.
- Kernel: 4.14.316, an old Samsung/LineageOS vendor kernel, rebuilt on 2026-11-11 ("kernel v2", `uname -v` shows `#3-postmarketOS`). Since then it has the ALSA loopback card, overlayfs, unprivileged user namespaces (`unshare -r` works, so rootless sandboxes work) and multi-port firewall rules. It still has no nf_tables on purpose (the firewall uses `iptables-legacy`), and no kernel modules can be loaded. A missing kernel feature means a new kernel build and flash by the owner.
- Sound cards are numbered differently since kernel v2: `Loopback` is card 0, the phone's own (unusable) cards are 1 to 3, and a USB sound card comes after them. Always name a card (`hw:Loopback`, `hw:Device`), never its number.
- Already installed: git, gh, Node 24 + npm, Python 3.14 + pip, Rust 1.99 + cargo, gcc, pkg-config, tmux, curl, wget, jq. Not installed: make, cmake, g++, go (get them with `apk add build-base cmake` and so on through the gatekeeper).
- Running services: sshd, Tailscale, NetworkManager, Samba, aria2 (downloads to `/srv/files/downloads`), crond, ntpd.

## Root access

- You don't have the sudo password. For root, use the gatekeeper: `sudo /usr/local/sbin/s10-sudo <command> [args...]`. It needs no password and runs ONE plain command as root if its fixed rules allow it. Pipes, redirects and `&&` stay outside it and run as `user`.
- `/usr/local/sbin/s10-sudo --list` shows what is allowed (package installs, your own services, read-only looks at the system, folders under `/srv`, installing a program into `/usr/local/bin`). `/usr/local/sbin/s10-sudo --check <command>` tells you the answer without running anything.
- Exit code 77 means refused. Don't look for another route around a refusal: stop and give the owner the exact command and the reason. The same goes for anything the list doesn't cover.
- Claude Code itself is installed system-wide in `/usr/local` and is owned by root. Leave its updates to the owner.

## When something is missing or doesn't work: build it yourself

Don't stop and don't report "not available on this system" until you have tried these, in order:

1. `apk search <name>`, then `sudo /usr/local/sbin/s10-sudo apk add <package>`. Development headers are in `<name>-dev` packages.
2. If there is no package, or a downloaded binary fails to start (a glibc build on a musl system shows up as "not found" or a loader error), **build it from source** for this machine. Work in `/srv/code/build/<name>`. Install build tools through the gatekeeper as you need them. Rust and C projects build fine here (CamillaDSP was built this way in about 4 minutes).
3. For language tools, install as `user` without root: Python in a virtual environment under `/srv` (`python3 -m venv`); Node tools with plain `npm install -g <name>` (it installs into `/srv/npm-global`, which is on your PATH in login shells; never use sudo for npm); Rust with `cargo install` (set `CARGO_HOME` under `/srv`).
4. Put the finished program in `/usr/local/bin` with `sudo /usr/local/sbin/s10-sudo install -m 755 <file> /usr/local/bin/<name>`, or just run it from `/srv`.

Ask the owner only when the missing piece is in the kernel (a missing kernel feature can't be built from user space), needs something the gatekeeper refuses, or touches the sound card. Heavy builds push the CPU to about 83 °C and it slows itself down; that is expected.

## Storage

- The system disk (`/`) is only 5 GB and cannot grow. `/srv` has over 100 GB free.
- Put anything large on `/srv`: downloads, builds, datasets, browser installs, virtual environments, big `node_modules`.
- The npm and apk caches already live in `/srv/cache`, and npm's global folder is `/srv/npm-global`. Leave them there.
- `/tmp` is RAM (tmpfs) and is cleared on reboot. Large temporary files eat memory, so use `/srv/tmp` for those.

## Projects: one folder, one address

- Projects live in `/srv/code`, and `/srv/code/<project>` is the only path to use.
- Until 2026-11-11 there was a shortcut `~/code` pointing at the same folder, which made one project look like two. It has been removed. If old notes or commands mention `/home/user/code/...`, read that as `/srv/code/...`.
- Don't create new shortcuts (symlinks) to project folders: Claude Code keeps separate memory and history per path.

## Audio: how sound gets out, and the lock

```
your programs (user) --> hw:Loopback,0,N ==virtual cable==> hw:Loopback,1,N --> CamillaDSP (service) --> real sound card
```

- The speakers' crossover runs in CamillaDSP. Sound sent straight to the sound card bypasses it and can damage the tweeters. So the system is locked: only the service account `camilladsp` can open real sound cards. `user` is deliberately not in the `audio` group, and the gatekeeper refuses everything audio. Don't treat this as a bug and don't try to get around it.
- What you CAN open is the loopback card (`user` is in group `loopback`). The system default device (`/etc/asound.conf`) is the loopback too, so a program that plays to "default" feeds CamillaDSP. `aplay -l` shows you only the Loopback card; that is expected.
- CamillaDSP runs as the OpenRC service `camilladsp` with the root-owned config `/etc/camilladsp/active.yml` and no websocket port. You cannot change the active config, restart the service or replace `/usr/local/bin/camilladsp`. To get a config activated, write it in your project, validate it with `camilladsp --check <file>` (works as `user`, touches no hardware), and give the owner this command: `sudo s10-camilla-activate <file>`.
- Writing a config: capture from `hw:Loopback,1,0`; players write to `hw:Loopback,0,0` or "default". The loopback takes the rate and format of whichever side opens first, so with CamillaDSP running a player must deliver exactly its capture format, or use "default" (ALSA converts, lower quality). Sample formats are spelled `S16_LE`, `S24_3_LE`, `S24_4_LE`, `S32_LE`, `F32_LE`, `F64_LE`. Name cards (`hw:Loopback`, `hw:Device`), never number them.
- You can test a whole chain without any sound card: loopback substreams are pairs, so play into `hw:Loopback,0,0`, let a CamillaDSP config output to `hw:Loopback,0,1`, and record from `hw:Loopback,1,1`. (That needs the owner to activate the test config.)
- Testing a real USB sound card directly (channel order, rates) is only possible in a window the owner opens while present: `sudo s10-dac-test on [minutes]`. Ask for it; don't expect it otherwise. More detail: `/etc/camilladsp/README`.

## Known quirks

- The load average is trustworthy since kernel v2 (near 0 when idle). Before 2026-11-11 it sat at about 11 because of Samsung kernel threads; ignore old notes that say 11 is normal.
- SSH accepts keys only. The server binary is `/usr/sbin/sshd.pam`.
- `logger` messages don't reach any readable system log; scripts here write their own files in `/var/log`.
- `crontab`, `findmnt` and `ss` work for `user` (added 2026-11-11). AdGuard Home and librespot were removed the same day.
