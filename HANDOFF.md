# Piranha A10 — Engineering Notes

Last updated: 2026-08-20 (Alpine + GT827 + Wi-Fi + audio complete). These notes record decisions, pitfalls and the working procedure for anyone picking the project up. See [README.md](README.md) for the overview.

## Goal

Mainline Linux on the Allwinner A10 "Piranha Business II Tab": a light touchscreen desktop (X11 + JWM) with **working networking** (USB Ethernet via `g_ether` first, the RTL8188CUS Wi-Fi second). Boot from SD, never write to the NAND.

## Hardware (confirmed)

- SoC: Allwinner A10 (sun4i), Cortex-A8 @ 1.4 GHz, 1 GB RAM
- PMIC: AXP209 · Panel: 800×480 (starry/kr070pe2t) · DRM: sun4i-drm + LCDC
- Touch: **Goodix GT827** on i2c-2 / 0x5d, INT = PH21, RST = PB13
- Wi-Fi: **RTL8188CUS** (0bda:8176), a USB device soldered inside the tablet, not a dongle
- 2× USB: one OTG (micro-USB, gadget), one host (USB-A, keyboard)
- No UART found, so diagnosis uses the screen and the SD card logs

## What works

- [x] U-Boot: `u-boot-sunxi-with-spl.bin` (565 KB), written to sector 8; does not touch the NAND
- [x] Mainline kernel 7.2.0 built with the Bootlin armv7-eabihf GCC 13.3 toolchain
- [x] **GT827 touchscreen driver** (`gt827.c` + `gt827_cfg.h`, in the separate repository). It embeds the real device config blob (`gt811/android-ko/cfg_A.bin`, 114 B), `compatible = "goodix,gt827"`, built as `gt827.ko`.
- [x] **DTS** `dts/sun4i-a10-piranha.dts` uses `goodix,gt827`; the DTB builds.
- [x] **Wi-Fi**: `CONFIG_WLAN=y`, `CONFIG_CFG80211=y`, `CONFIG_MAC80211=y`, `CONFIG_RTL8192CU=m` plus the related RTLWIFI options. Firmware in `rootfs/firmware/rtl8192cufw*.bin`.
- [x] **USB Ethernet**: `CONFIG_USB_ETH=m` → `g_ether.ko`.
- [x] **Alpine 3.20 armv7 rootfs** (OpenRC, musl) built by `scripts/45-alpine-stage1.sh` and `45-alpine-stage2.sh`: X11 + JWM, openssh, wpa_supplicant, evtest/libinput, Turkish Q keymap.
- [x] **OpenRC services** enabled: sshd, net.usb0 (static 10.0.0.2/24), keymaps (`trq`), modules (`g_ether` + `gt827` at boot), networking, local, wifi.
- [x] **SD writer for Alpine**: `scripts/50-sdcard-alpine.sh` (no systemd; OpenRC runlevel symlinks are preserved).
- [x] The earlier Debian 12 bookworm armhf rootfs booted too, but was dropped in favour of Alpine.

## Open issues and notes

1. **Cedrus userspace**: the kernel `cedrus` driver registers `/dev/video0`, but the Alpine FFmpeg/mpv build does not use stateless V4L2 Request decoding. This is the main remaining gap.
2. **Systemd worker lock-up (historical)**: seen with the Debian image only. Alpine + OpenRC has no rc.local/systemd-worker trap; the static IP comes from the `net.usb0` OpenRC service.
3. **Wi-Fi** works with the options listed above. `80-update-kernel.sh` must generate the dependency files with a host-side `depmod -b`.
4. **USB Ethernet route conflict (known fix)**: the PC's USB interface (`enp15s0f3u1`) and its onboard NIC (`enp10s0`) can end up on the same `10.0.0.0/24` network. If `ip route get 10.0.0.2` shows the wrong interface, ping/SSH will not go over USB. Fix:
   ```bash
   sudo ip addr replace 10.0.0.1/24 dev enp15s0f3u1
   sudo ip route replace 10.0.0.2/32 dev enp15s0f3u1 src 10.0.0.1
   ip route get 10.0.0.2
   ```
   The last command must show `dev enp15s0f3u1`. A lasting fix is to avoid using `10.0.0.0/24` on the onboard NIC, or to pick another subnet for the USB link. The tablet side is `usb0 = 10.0.0.2/24`, the PC USB interface `10.0.0.1/24`.
5. **Audio**: `sun4i-codec` and speaker playback work. The external amplifier GPIO (PA10) is in the DTS; the mixer settings are in the README.
6. **Keyboard layout**: the Alpine `keymaps` service with `trq` handles the Turkish Q layout.

## Key decisions

- **Debian → Alpine**: Alpine (OpenRC, musl) is lighter and fits this device better. Done.
- Wi-Fi starts automatically at boot through an Alpine OpenRC `wifi` service.
- GT811 → GT827: the driver was written as `gt827.c`; `gt811.c` was removed from the kernel tree. `gt811/gt811.c` in this repository is an early prototype.

## File layout

- `kernel/linux/`: mainline kernel tree (patched `.config`, DTS copy, **gt827.c / gt827_cfg.h under touchscreen**); not tracked
- `uboot/u-boot/`: U-Boot tree (`u-boot-sunxi-with-spl.bin` built); not tracked
- `dts/sun4i-a10-piranha.dts`: the source DTS (compiles, GT827 compatible)
- GT827 driver: separate repository <https://github.com/Mechres/gt827-linux-driver>
- `gt811/android-ko/`: the original Android module and `cfg_*.bin` / `fw_gt811.bin` (real device data, valuable)
- `scripts/00-env.sh`: `CROSS_COMPILE` and `PRJ`; `PRJ` is derived from `BASH_SOURCE` because `$HOME` becomes `/root` under sudo
- `scripts/30-kernel-build.sh`: kernel build
- `scripts/80-update-kernel.sh`: zImage, DTB and modules plus host-side depmod
- `scripts/45-alpine-stage1.sh`, `45-alpine-stage2.sh`: Alpine rootfs (OpenRC)
- `scripts/50-sdcard-alpine.sh`: SD writer for Alpine
- `scripts/40-rootfs.sh`, `50-sdcard.sh`: legacy Debian, no longer used
- `scripts/70-network.sh`, `90-wifi-setup.sh`: legacy Debian, not needed on Alpine
- `rootfs/firmware/`: `rtl8192cufw*.bin` (4 files, RTL8188CUS firmware)
- `rootfs/alpine/`: the Alpine rootfs (ready after `modules_install`)
- `backup/`: Android `nanda.img` (boot partition backup)

## Rebuilding the kernel

```bash
cd /path/to/piranha-a10/kernel/linux
source ../../scripts/00-env.sh
make ARCH=arm CROSS_COMPILE=arm-buildroot-linux-gnueabihf- zImage dtbs modules -j$(nproc)
# GT827 / RTL8192CU / g_ether modules:
#   drivers/input/touchscreen/gt827.ko
#   drivers/net/wireless/realtek/rtlwifi/rtl8192cu/rtl8192cu.ko
#   drivers/usb/gadget/legacy/g_ether.ko
```

Preferred route:

```bash
sudo bash scripts/30-kernel-build.sh
sudo bash scripts/80-update-kernel.sh /dev/sdX
```

`30-kernel-build.sh` derives the project path from the script location, so it works under `sudo` without `/root/...` path errors. The Wi-Fi dependencies are in the kernel config, and the DTS carries the PA10 `allwinner,pa-gpios` definition for audio.

## Steps that need sudo

```bash
# 1) Install the kernel modules into the Alpine rootfs
cd /path/to/piranha-a10
source scripts/00-env.sh
cd kernel/linux
sudo make ARCH=arm CROSS_COMPILE=$CROSS_COMPILE INSTALL_MOD_PATH=../rootfs/alpine modules_install

# 2) Write the SD card (DEV=/dev/sdX — verify with lsblk every time!)
sudo bash scripts/50-sdcard-alpine.sh /dev/sdX

# 3) Test on the tablet:
#   dmesg | grep -E 'gt827|rtl|g_ether|usb0'
#   ssh piranha@10.0.0.2   (PC: ip addr add 10.0.0.1/24 dev enp15s0f3u1)
#   Wi-Fi: sudo wifi-connect.sh, then fill in /etc/wpa_supplicant/wpa_supplicant.conf
```

## Host environment notes

- Developed on CachyOS/Arch.
- The SD card rootfs (ext4) is root-owned, so writing to it needs `sudo bash script.sh`.
- The boot partition (FAT16) is mounted by udisks with user ownership, so it can be written without root.
- USB Ethernet on the PC side: `enp15s0f3u1` (appears when the tablet is connected); `enp10s0` is the onboard Ethernet.

## Working tips

- The SD-card swap + reboot loop is slow, so prefer remote (SSH) workflows.
- When SSH is unavailable, run `scripts/diag.sh` on the tablet: it writes `/diag.txt` to the SD card, which can be read on the PC. This has been the most useful diagnostic route.

## Legacy Debian route: pitfalls

The first rootfs attempt used Debian bookworm armhf via podman + qemu-arm binfmt (superseded by Alpine):

- On Arch, `dpkg` is missing, so `debootstrap` fails with `Unknown architecture: x86_64`; podman with the official `debian:bookworm` armhf image avoids this.
- `--arch` and `--platform` cannot be combined; use only `--platform linux/arm/v7`.
- systemd does not run in the container, so units were enabled with manual symlinks.
- `useradd -G` fails if the group does not exist; run `groupadd` first.
- `firmware-realtek` is in non-free on bookworm; take the firmware from Android instead.
- podman bind-mounts `/etc/hostname`, `/etc/hosts` and `/etc/resolv.conf`, so an export yields hostname `debuerreotype` and an empty `hosts`; the legacy scripts repair this.
