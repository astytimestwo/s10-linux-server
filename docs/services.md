# Services

Versions as installed in November 2026 (Nura edge = Alpine edge): tailscale 1.104.4, samba 4.23.10, aria2 1.37.0, NetworkManager 1.58.1, OpenRC 0.63.2. (AdGuard Home 0.107.79 and librespot 0.8.0 were installed for a few days and removed again; see below.) Everything comes from the official Alpine repos unless noted.

> Alpine uses **musl**, not glibc. Prebuilt "Linux ARM64" binaries from project websites are usually glibc-linked and won't start. Prefer `apk` packages, or build from source.

## Tailscale (remote access)

```sh
doas apk add tailscale tailscale-openrc && doas rc-update add tailscale default && doas rc-service tailscale start
doas tailscale up --netfilter-mode=off --accept-dns=false --hostname=s10
```

- `--netfilter-mode=off`: Tailscale's firewall integration wants nf_tables, which this kernel lacks. Our own firewall already accepts everything on `tailscale0`.
- Connects **directly** (UDP 41641 is open in the firewall), not through relays; ~100 ms from a 5G hotspot across the country.
- Add [`etc/logrotate.d/tailscale`](../rootfs/etc/logrotate.d/tailscale): tailscaled's log otherwise grows forever.

## Samba (files in Windows Explorer)

```sh
doas apk add samba
doas cp smb.conf /etc/samba/smb.conf        # rootfs/etc/samba/smb.conf; keep the original as a backup
echo 'daemon_list="smbd"' | doas tee -a /etc/conf.d/samba
doas smbpasswd -a user                        # Samba has its own password
doas rc-update add samba default && doas rc-service samba start
```

[`smb.conf`](../rootfs/etc/samba/smb.conf): SMB2+ only, NetBIOS off (port 445 only), no printers, Windows/macOS-friendly VFS modules; shares `srv` (`/srv`) and `home` (with `~/.ssh` hidden). In Explorer: `\\<s10-tailscale-ip>\srv` works from anywhere, `\\<s10-lan-ip>\srv` at home is a bit faster (no Tailscale encryption).

Speed over Wi-Fi with both devices on 5 GHz: ~14–19 MB/s (every byte crosses the air twice). Wired Ethernet on the phone should be faster but isn't tested yet.

## aria2 + AriaNg (download station)

Paste a link from any device; the phone downloads it to `/srv/files/downloads` and keeps going while your laptop sleeps.

```sh
doas apk add aria2 aria2-daemon busybox-extras-openrc
# on the PC: download AriaNg-<version>-AllInOne.zip from https://github.com/mayswind/AriaNg/releases
# copy to the phone's /tmp: aria2.conf (rootfs/etc/aria2.conf), the unzipped AriaNg folder as /tmp/ariang/,
# and a random secret (letters and digits) in /tmp/aria2.secret, for example:
head -c 24 /dev/urandom | base64 | tr -dc A-Za-z0-9 > /tmp/aria2.secret
doas sh aria2-install.sh                      # scripts/aria2-install.sh
```

- Config: [`etc/aria2.conf`](../rootfs/etc/aria2.conf) + [`etc/conf.d/aria2`](../rootfs/etc/conf.d/aria2); the installer writes the secret into the config (root and `user` can read it) and deletes `/tmp/aria2.secret`. Keep a copy of the secret somewhere private: you paste it into AriaNg once (Settings → RPC → Secret Token).
- The Alpine package's default config has `rpc-secret=top-secret`; the installer replaces that file.
- Web UI: `http://<s10-tailscale-ip>:6880` (AriaNg served by busybox `httpd`). Reachable over Tailscale only; there's no LAN firewall rule for 6800/6880.
- Runs as `user` under `supervise-daemon`: at boot aria2 can start before Wi-Fi has an address and exits ("failed to bind TCP port 6800"); the supervisor restarts it.
- `required_dirs=/srv/files`: won't start if the data partition isn't mounted, so it can never fill the root filesystem.
- 4 connections per server, not 8: some servers answer `429 Too Many Requests` to more.

## AdGuard Home (DNS ad blocking): tried, removed

Installed on day two (`apk add adguardhome adguardhome-openrc`, setup wizard on port 3000), never configured, and removed three days later: a service that runs unconfigured with ports open is worse than no service. If you set it up, two things to know:

- It runs as a non-root user, so it can't bind DNS port 53 until you allow it, for example `doas setcap cap_net_bind_service=+ep /usr/bin/AdGuardHome` (check the binary path with `apk info -L adguardhome`).
- ⚠ If you point your **router's** DNS at the phone and the phone goes down, every device at home loses DNS ("no internet"). Set a second DNS server in the router as a fallback, or point only some devices at it.

## Claude Code and development

- `doas apk add nodejs npm`, then `npm install -g @anthropic-ai/claude-code`. It works on Alpine (musl). npm blocks packages' install scripts by default, and Claude Code needs its script to put the real binary in place, so allow it once and for all: `npm config set allow-scripts=@anthropic-ai/claude-code --location=global`. Without that an update leaves a `claude` that only says "native binary not installed" (fix: run `node install.cjs` in the package folder).
- `doas apk add github-cli`, then `gh auth login --web` (device-code flow, nothing typed on the phone) and `gh auth setup-git`.
- Projects live in `/srv/code`, under that one path. Typical use: `ssh s10`, `t` (tmux), `claude`, close the laptop, come back later.
- Agents get root through the rule-based gatekeeper and read a shared notes file: [agents.md](agents.md).
- Keep npm off the small system disk: [`~/.npmrc`](../rootfs/home/user/.npmrc) sends the cache to `/srv/cache/npm` and global installs to `/srv/npm-global` (on the PATH from [`.bashrc`](../rootfs/home/user/.bashrc)), so `npm install -g` needs no root.

## Audio: loopback → CamillaDSP → USB sound card

Everything is in [`audio/`](../audio/), with its own README. In short:

- A cheap C-Media USB sound card (`0d8c:0102`) shows up as an ALSA card via `snd-usb-audio` (16-bit, 44.1/48 kHz, up to 8 channels). Samsung's abox USB-offload hooks also attach to it; whether that interferes with playback isn't tested yet.
- **CamillaDSP** isn't packaged for Alpine and the official aarch64 binary is glibc-linked. Built from source in ~4 minutes:
  ```sh
  doas apk add rust cargo alsa-lib-dev
  git clone --branch v4.1.3 https://github.com/HEnquist/camilladsp && cd camilladsp
  cargo build --release && doas install -m 755 target/release/camilladsp /usr/local/bin/
  ```
  The build runs the CPU at 83 °C (throttling, expected).
- With [kernel v2](kernel-v2.md) there is an ALSA loopback card. Programs play into it, CamillaDSP (an OpenRC service under its own account) reads the other end and is the only thing allowed to open a real sound card. That matters when CamillaDSP is the crossover for the speakers: sound that bypasses it can destroy tweeters.
- Tested without a sound card: a tone played by a normal user into `hw:Loopback,0,0` came out of CamillaDSP unchanged. Not tested yet: the same with the real USB sound card.
- **librespot (Spotify Connect): tried, removed.** The account link works, then every track fails: Spotify refuses to send decryption keys to librespot for accounts created after roughly 2024/2025 (`error audio key 0 1`; upstream issue [librespot#1649](https://github.com/librespot-org/librespot/issues/1649), no workaround). An older account should work.
