# s10-sudo: rule-based root access for the agents on the S10

Claude Code agents on the phone run as `user` and have no root password. With this they can run a fixed set of safe root commands by themselves. There is no AI in the gate, only rules. Anything not on the allowed list is refused, and the agent is told to ask the owner.

## How it works

1. The agent runs `sudo /usr/local/sbin/s10-sudo <command> [args...]`.
2. A sudo rule (`/etc/sudoers.d/s10-sudo`) lets `user` run exactly that program as root without a password. Nothing else is passwordless.
3. The gate checks the command and its arguments against its rules.
4. Allowed: it runs that one command directly as root (no shell, so pipes and redirects stay outside, as `user`). Refused: it prints why and exits 77.
5. Every request is logged in `/var/log/s10-sudo.log`.

`s10-sudo --list` prints the rules. `s10-sudo --check <command>` says what would happen without running anything (no sudo needed).

## What is allowed

- **Packages:** `apk add` of repository packages, except ones about access or the system base (sudo, openssh, kernel, busybox, ...). `apk del/upgrade/fix` only for packages installed after the gate was set up. `apk update/info/search/policy/list/version`.
- **Services:** `rc-service <name> status` for anything; `start/stop/restart/reload` and `rc-update add/del` only for services installed after the gate was set up.
- **Looking (read-only):** `cat head tail wc ls stat du df grep`, `dmesg ps free uptime id lsusb lsmod findmnt netstat blkid ss mount`, `ip ... show`, `iw ... link/info`, `iptables-legacy -S/-L`, `sshd.pam -T`, `tailscale status/ip/netcheck/version/ping/whois`, `aplay -l`. Secrets and raw devices can't be read (`/etc/shadow`, sudo rules, SSH host keys, `/root`, Wi-Fi passwords, Tailscale state, tokens, `/dev`).
- **Files:** `mkdir -p`, `chown [-R] user:user` and `rm [-r] [-f]` under `/srv` only (`rm` needs at least two levels, e.g. `/srv/opt/x`); `install -m 755 <file> /usr/local/bin/<new name>` for a program name that doesn't shadow a system command.

## What is always refused

Shells and interpreters, editors, `reboot`/`poweroff`, accounts, groups and passwords, sudo rules, SSH and Tailscale setup, firewall and network changes, disks and mounts, kernel modules and `sysctl`, root's cron, writing files outside `/srv`, downloading as root, and anything that plays sound or touches the sound card.

"Base system" means the services and packages that existed when the gate was installed (`/etc/s10-sudo/baseline-*`; here 91 services and 348 packages, plus `camilladsp`, which the owner added to the list by hand). Those files are written once and not overwritten on reinstall.

## Files on the phone

| Path | Owner, mode | What |
|---|---|---|
| `/usr/local/sbin/s10-sudo` | root 755 | the gate (all rules are in this one script) |
| `/etc/sudoers.d/s10-sudo` | root 440 | the one passwordless rule |
| `/etc/s10-sudo/baseline-services`, `baseline-packages` | root 644 | the base system lists |
| `/var/log/s10-sudo.log` | root 644 | requests, refusals, exit codes |

## Changing the rules (owner)

Edit `s10-sudo` in this folder, copy the folder to the phone, run `sudo sh install.sh`, then `sh test-cases.sh` as `user` (136 decision checks plus real runs; it must print 0 failed). To remove it: `sudo sh uninstall.sh`.

## Limits

- It guards against mistakes by a cooperative agent. It is not proof against someone deliberately racing it (for example swapping a folder for a symlink between the check and the command).
- Packages from the repositories are trusted. An installed package can bring its own services and programs.
- One plain command per call, nothing interactive (input is closed).
