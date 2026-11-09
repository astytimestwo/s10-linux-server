# pmaports patches

Four commits on top of pmaports `main` (as of 7 Nov 2026, Nura's pmaports), for `device/archived/device-samsung-beyond1lte-downstream` and `device/archived/linux-samsung-beyond1lte-downstream`. Apply with `git am` in pmbootstrap's pmaports checkout.

| Patch | What | Why |
|---|---|---|
| 0001 | Rename the kernel config to `config-samsung-beyond1lte-downstream.aarch64`; `os_patch_level` 2023-03 | Workaround: `devicepkg-dev`'s `downstreamkernel_prepare.sh` has an inverted test (`if ! [ -z "$_config" ]`) that ignores `_config` and forces `config-${pkgname#linux-}.$arch`, breaking the build of this kernel and, by our count of pmaports at the time, about 50 other archived downstream kernels that set `_config`. The test came in with pmaports MR !9347. The proper upstream fix is one line in that script (`if [ -z "$_config" ]`); this patch is the local workaround. The patch-level bump is cosmetic. |
| 0002 | `deviceinfo_initfs_compression="gzip"` (+ extra) | Kernel has `RD_GZIP`/`RD_LZ4` only; mkinitfs now defaults to zstd → panic "Unable to mount root fs". |
| 0003 | Kernel: apply `LOOP_CONFIGURE`'s `block_size` (`loop-configure-apply-block-size.patch`) | The Android backport of `loop_configure()` validates but never applies the block size, so the 4096-byte-sector rootfs image showed no partitions and the initramfs couldn't mount root. Matches upstream 5.8+ behaviour. |
| 0004 | USB gadget ID `1D6B:0104` | The default `18D1:D001` gets grabbed on Windows by vendor ADB drivers, so the network function never loads. |

The kernel patch (inside 0003) is a change to the Linux kernel and is GPL-2.0-only like the kernel. The pmaports packaging changes follow pmaports' license.
