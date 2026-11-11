# Running AI coding agents on the phone

Claude Code sessions run on the phone in tmux, as the normal account `user`. Left to themselves on an unusual system they kept hitting the same walls, so three things were added: a way to get root without a password, a notes file they all read, and a few storage rules.

## What the agents reported

After a few days two agent sessions were asked what got in their way. The list, shortened:

- No root: every package install, service change and cleanup stopped and waited for the owner.
- The system is not what they assume: no `apt`, no `systemd`, musl instead of glibc, BusyBox tools, an old kernel without user namespaces or an audio loopback.
- The 5 GB system disk filled up, because caches and global installs land there by default.
- A load average of 11 on an idle machine sent them looking for a problem that wasn't there.
- A project folder was reachable under two paths (a convenience symlink), and Claude Code keeps separate memory per path, so one project looked like two.

Most of this was fixed at the source ([kernel v2](kernel-v2.md), caches moved to `/srv`, the symlink removed). The rest is handled by the two pieces below.

## Root access: the gatekeeper

Folder: [`gatekeeper/`](../gatekeeper/).

```
sudo /usr/local/sbin/s10-sudo apk add chromium
```

- One sudo rule lets `user` run exactly this program as root without a password. Nothing else is passwordless.
- The program checks the command against fixed rules and runs it directly (no shell), or refuses with a reason and exit code 77.
- `--list` prints the rules; `--check` gives the verdict without running anything.

**How the design got there.** The first idea was to hand agents the sudo password: simple, and it gives away everything. The second was a separate "reviewer" AI that approves each command: built, tested for its failure modes, and dropped before it was ever switched on: the owner preferred fixed rules that give the same answer every time. What stayed is the boring version.

**Why an allow list.** A list of forbidden commands doesn't hold. Refuse `sh` and the next attempt is `busybox sh`, `env sh`, `find -exec`, an editor's shell escape, and so on; an agent that is merely being resourceful finds these without meaning any harm. So everything is refused unless it matches an allowed form:

| Area | Allowed |
|---|---|
| Packages | `apk add` from the configured repositories, except packages about access or the system base; `apk del/upgrade/fix` only for packages added after the gate was installed |
| Services | `status` for everything; `start/stop/restart` and `rc-update` only for services added later |
| Looking | `cat`, `tail`, `ls`, `grep` (not recursive), `dmesg`, `ps`, `ss`, `ip … show`, `iptables-legacy -S`, … with a filter for secrets (`/etc/shadow`, sudo rules, keys, Wi-Fi passwords, `/dev`) applied after resolving symlinks |
| Files | `mkdir`, `chown user:user`, `rm` under `/srv` only; `install` of a new program name into `/usr/local/bin` |

"Added later" is decided by two baseline lists (services and packages present at install time), so the agents can manage what they brought in and can't touch what the system needs to stay reachable.

**Tests.** [`test-cases.sh`](../gatekeeper/test-cases.sh) runs 136 decisions through `--check` (it never executes the refused ones) plus real runs, including a symlink pointing at `/etc/shadow` that must be neither readable nor re-owned. The suite found two bugs in the first version.

**Limits.** It guards against mistakes by a cooperative agent. It is not a sandbox, and it is not proof against someone racing it on purpose.

## The shared notes file

File: [`agents/CLAUDE.md`](../agents/CLAUDE.md), installed as `~/.claude/CLAUDE.md`, the user-level file every Claude Code session loads.

It says what the machine is, how to get root, where big things go, which path projects live under, how sound works and what not to touch, and that a missing package means "build it from source", not "give up". Notes like these only work in the one file that is always loaded; side files get skipped.

## Storage and tools

- apk and npm caches live in `/srv/cache` (`/etc/apk/cache` symlink, `cache=` in `.npmrc`), with fallback folders on the root disk underneath the `/srv` mount point so installs still work if `/srv` fails to mount.
- `npm install -g` goes to `/srv/npm-global` (`prefix=` in `~/.npmrc`, on the PATH from `~/.bashrc`), so Node tools need no root.
- Claude Code itself is a global npm package. npm now blocks packages' install scripts by default, and Claude Code needs its script to place the real binary: an update without it leaves a program that says "native binary not installed". `npm config set allow-scripts=@anthropic-ai/claude-code --location=global` fixes it for good.

## Sound is off-limits

Agents can play into the audio loopback and nothing else. The DSP config that drives the speakers and the DSP binary are owner-only, and the gatekeeper refuses everything audio. See [`audio/`](../audio/).
