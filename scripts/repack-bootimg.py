#!/usr/bin/env python3
"""Swap the kernel inside an Android boot image (header v0/v1), keeping everything else.

  repack-bootimg.py info  OLD.img
  repack-bootimg.py swap  OLD.img NEW_KERNEL OUT.img
  repack-bootimg.py selftest OLD.img          rebuild OLD.img from its own parts; must be identical

Used for the S10 (Samsung, header v1 + "SEANDROIDENFORCE" trailer): the initramfs, command line,
load addresses and trailer stay byte-identical to the image that is known to boot; only the
kernel and the header's size + checksum fields change.
"""
import hashlib
import struct
import sys

HDR = struct.Struct("<8s10I16s512s32s1024s")        # v0 part: 1632 bytes
V1 = struct.Struct("<IQI")                          # recovery_dtbo_size, recovery_dtbo_offset, header_size


def pages(n, ps):
    return (n + ps - 1) // ps * ps


def parse(data):
    (magic, ksize, kaddr, rsize, raddr, ssize, saddr, tags, ps, hver, osver,
     name, cmdline, hid, extra) = HDR.unpack_from(data, 0)
    if magic != b"ANDROID!":
        sys.exit("not an Android boot image")
    if hver > 1:
        sys.exit(f"header version {hver} is not supported by this tool")
    dsize = doff = hsize = 0
    if hver == 1:
        dsize, doff, hsize = V1.unpack_from(data, HDR.size)
    off = ps
    kernel = data[off:off + ksize]; off += pages(ksize, ps)
    ramdisk = data[off:off + rsize]; off += pages(rsize, ps)
    second = data[off:off + ssize]; off += pages(ssize, ps)
    dtbo = data[off:off + dsize]; off += pages(dsize, ps)
    return dict(ksize=ksize, kaddr=kaddr, rsize=rsize, raddr=raddr, ssize=ssize, saddr=saddr,
                tags=tags, ps=ps, hver=hver, osver=osver, name=name, cmdline=cmdline, hid=hid,
                extra=extra, dsize=dsize, doff=doff, hsize=hsize, kernel=kernel, ramdisk=ramdisk,
                second=second, dtbo=dtbo, trailer=data[off:], header_page=data[:ps])


def image_id(p, kernel):
    h = hashlib.sha1()
    for blob in (kernel, p["ramdisk"], p["second"]):
        h.update(blob); h.update(struct.pack("<I", len(blob)))
    if p["hver"] > 0:
        h.update(p["dtbo"]); h.update(struct.pack("<I", len(p["dtbo"])))
    return h.digest().ljust(32, b"\0")


def build(p, kernel):
    ps = p["ps"]
    hdr = bytearray(p["header_page"])               # keep any bytes we don't interpret
    hid = image_id(p, kernel)
    HDR.pack_into(hdr, 0, b"ANDROID!", len(kernel), p["kaddr"], p["rsize"], p["raddr"], p["ssize"],
                  p["saddr"], p["tags"], ps, p["hver"], p["osver"], p["name"], p["cmdline"], hid,
                  p["extra"])
    if p["hver"] == 1:
        doff = 0
        if p["dsize"]:
            doff = ps + pages(len(kernel), ps) + pages(p["rsize"], ps) + pages(p["ssize"], ps)
        V1.pack_into(hdr, HDR.size, p["dsize"], doff if p["dsize"] else p["doff"], p["hsize"])
    out = bytearray(hdr)
    for blob in (kernel, p["ramdisk"], p["second"], p["dtbo"]):
        out += blob
        out += b"\0" * (pages(len(blob), ps) - len(blob))
    out += p["trailer"]
    return bytes(out)


def info(p, label):
    print(f"{label}: header v{p['hver']}, page {p['ps']}, kernel {p['ksize']} @0x{p['kaddr']:08x}, "
          f"ramdisk {p['rsize']} @0x{p['raddr']:08x}, second {p['ssize']}, dtbo {p['dsize']}")
    print(f"  cmdline: {p['cmdline'].rstrip(bytes(1)).decode(errors='replace')!r}")
    print(f"  ramdisk magic: {p['ramdisk'][:4].hex()}  trailer: {p['trailer'][:20]!r} ({len(p['trailer'])} bytes)")
    print(f"  id ok: {p['hid'] == image_id(p, p['kernel'])}")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    mode = sys.argv[1]
    old = open(sys.argv[2], "rb").read()
    p = parse(old)
    if mode == "info":
        info(p, sys.argv[2])
    elif mode == "selftest":
        same = build(p, p["kernel"]) == old
        print("selftest: rebuilt image is", "IDENTICAL to the original" if same else "DIFFERENT")
        sys.exit(0 if same else 1)
    elif mode == "swap" and len(sys.argv) == 5:
        if build(p, p["kernel"]) != old:
            sys.exit("refusing: this tool can't reproduce the original image byte for byte")
        kernel = open(sys.argv[3], "rb").read()
        new = build(p, kernel)
        open(sys.argv[4], "wb").write(new)
        info(parse(new), sys.argv[4])
        print(f"  size {len(new)} bytes, sha256 {hashlib.sha256(new).hexdigest()}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
