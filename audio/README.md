# S10 audio path and its lock

```
your programs (user)  -->  hw:Loopback,0,N  ==virtual cable==>  hw:Loopback,1,N  -->  CamillaDSP (account camilladsp)  -->  real sound card
```

- Every sound device is `root:audio 0660`. Only the service account `camilladsp` is in `audio`, so only CamillaDSP can open a real sound card. `user` is not in `audio`, on purpose.
- The loopback card (kernel v2, `snd_aloop`) is `root:loopback 0660` through `/etc/udev/rules.d/70-s10-sound.rules`. `user` and `camilladsp` are in `loopback`.
- `/etc/asound.conf` makes the loopback the default device, so anything that plays to "default" goes into CamillaDSP.
- CamillaDSP runs as the OpenRC service `camilladsp` with the root-owned config `/etc/camilladsp/active.yml` and no websocket port. Nothing a normal program does can change what reaches the speakers.

## Owner commands (need the sudo password)

| Command | What |
|---|---|
| `sudo s10-camilla-activate <config.yml>` | check a config, show its devices, ask, then make it the active one, enable and restart the service (previous config kept as `active.yml.prev`) |
| `sudo s10-camilla-activate --off` | stop and disable the service |
| `sudo s10-dac-test on [minutes]` | supervised test window: stop CamillaDSP and let `user` open USB sound cards directly for N minutes (default 30). **This bypasses the crossover: amp volume down first.** |
| `sudo s10-dac-test off` | close the window now |

## For whoever writes the CamillaDSP config

- Capture from `hw:Loopback,1,0`. Players write to `hw:Loopback,0,0` (or "default").
- The loopback takes the sample rate and format of whichever side opens first. With CamillaDSP running, players must deliver exactly its capture format, or go through "default" (ALSA converts, lower quality).
- Validate without touching hardware: `camilladsp --check <config.yml>` (works as `user`).
- Address sound cards by name (`hw:Loopback`, `hw:Device`), not by number.
- Log: `/var/log/camilladsp/camilladsp_rCURRENT.log` (read it through the gatekeeper: `sudo /usr/local/sbin/s10-sudo tail /var/log/camilladsp/camilladsp_rCURRENT.log`).
- Sample formats in CamillaDSP 4 are written `S16_LE`, `S24_3_LE`, `S24_4_LE`, `S32_LE`, `F32_LE`, `F64_LE`.
- Tested 2026-11-11 without a sound card: a 440 Hz tone played by `user` into `hw:Loopback,0,0` went through CamillaDSP (capture `hw:Loopback,1,0`, 48 kHz, 2 channels, `S32_LE`) and came out unchanged at -20 dBFS.
