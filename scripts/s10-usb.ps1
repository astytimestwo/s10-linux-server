# s10-usb.ps1: SSH into the phone over the USB cable when Wi-Fi/Tailscale can't reach it.
# Windows can't talk to this kernel's USB network (it drops packets), so the cable is passed
# to WSL, whose Linux driver works.
#
# One-time setup:
#   1. Install usbipd-win (https://github.com/dorssel/usbipd-win, 4.x or newer) and a WSL distro.
#   2. Plug in the phone, run `usbipd list`, find the line "1d6b:0104  UsbNcm Host Device",
#      then in an ADMIN PowerShell:  usbipd bind --busid <that BUSID>
#   3. Edit $repo and $distro below. In s10-usb.sh set the path to your SSH private key.
#
# Usage (normal PowerShell, phone plugged in and booted):
#   powershell -ExecutionPolicy Bypass -File scripts\s10-usb.ps1
$ErrorActionPreference = 'Continue'   # usbipd prints info on stderr; PowerShell 5.1 would treat it as an error
$distro = 'Debian'
$repo   = '/mnt/c/path/to/s10-linux-server'   # this repo, as seen from WSL

# 1. Keep WSL running while we work (usbipd can only attach to a running WSL)
Start-Process wsl.exe -ArgumentList "-d $distro -- sleep 3600" -WindowStyle Hidden
Start-Sleep -Seconds 4

# 2. Pass the phone's USB device to WSL ("already attached" is fine)
usbipd attach --wsl --hardware-id 1d6b:0104
Start-Sleep -Seconds 4

# 3. Bring up the link inside WSL and SSH in
wsl.exe -d $distro -- bash "$repo/scripts/s10-usb.sh" @args
exit $LASTEXITCODE
