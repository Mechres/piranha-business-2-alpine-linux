# Piranha Business II Tab → Alpine Linux

Mainline Linux (7.x) and Alpine on the Piranha Business II Tab, an Allwinner A10 tablet. The system boots from a microSD card; the internal NAND is never written, so removing the card brings Android back.

## Hardware

| | |
|---|---|
| SoC | Allwinner A10 (sun4i), single Cortex-A8 @ 1.4 GHz |
| RAM | 1 GB DDR3 (the extracted FEX reports an older, incorrect 512 MB boot configuration) |
| PMIC | AXP209 |
| Storage | Hynix H27UCG8 MLC NAND (untouched), microSD slot |
| Display | 800×480 LVDS panel, matches mainline `starry,kr070pe2t` exactly |
| Touch | Goodix **GT827** on i2c2 @ 0x5D (INT = PH21, RESET = PB13) |
| Wi-Fi | RTL8188CUS (USB `0bda:8176`), soldered inside the tablet, not a dongle |
| Audio | `sun4i-codec` + external speaker amplifier controlled by PA10 |
| Board ID | Softwinners `crane` / `crane-a702jhorange`, `script.bin` name `A10-EVB-V1.1` |

The Android vendor module for the touch controller is called `gt811_ts-827-fz`, but the chip is a GT827. The out-of-tree Linux driver lives in its own repository: <https://github.com/Mechres/gt827-linux-driver>.

## Golden rule

Nothing is written to the NAND. The A10 BROM boot order is SD → NAND → FEL, so with a card inserted the tablet boots from it, and without one it boots Android.

## Status

- [x] Host environment: Bootlin armhf GCC 13.3, dtc, podman, qemu-user-static, sunxi-tools, adb
- [x] Android recon, backup of the 16 MB boot partition (`nanda.img`), `script.bin` extracted
- [x] `script.bin` → `fex/tablet.fex` → panel / DRAM / i2c / GPIO parameters
- [x] U-Boot built (`u-boot-sunxi-with-spl.bin`, written to sector 8 of the SD card)
- [x] Mainline kernel and custom DTS (`sun4i-a10-piranha.dts`) built
- [x] GT827 touchscreen driver written, with the panel config blob taken from the vendor module
- [x] Alpine 3.20 armv7 rootfs: OpenRC, SSH, Wi-Fi, X11 + JWM
- [x] Boot from SD verified; Wi-Fi, USB Ethernet and SSH verified
- [x] ALSA codec and the PA10 speaker amplifier verified
- [x] Lima (Mali-400) GPU and Cedrus VPU kernel drivers verified

Known gap: the Cedrus VPU is registered as `/dev/video0`, but the Alpine FFmpeg/mpv userland does not yet use stateless V4L2 Request decoding, so video decoding is not hardware accelerated.

## Quick start

All scripts derive the project root from their own location, so they work under `sudo` as well.

```bash
cd /path/to/piranha-a10

# 1. Build the Alpine rootfs (stage 1 needs no root; stage 2 installs
#    packages, OpenRC services and the kernel modules)
bash scripts/45-alpine-stage1.sh
sudo bash scripts/45-alpine-stage2.sh

# 2. Write the SD card. Verify the device with lsblk first: this ERASES it.
#    The script asks you to type WRITE and refuses non-removable disks.
lsblk -o NAME,SIZE,RM,MODEL,MOUNTPOINTS
sudo bash scripts/50-sdcard-alpine.sh /dev/sdX
```

Kernel or Device Tree changes:

```bash
sudo bash scripts/30-kernel-build.sh
sudo bash scripts/80-update-kernel.sh /dev/sdX
```

`scripts/alpine-public/` contains a portable variant of the same flow plus on-tablet helpers (Wi-Fi service, audio service, desktop setup); see its [README](scripts/alpine-public/README.md).

## Repository layout

```
backup/nanda.img               Android boot partition backup (16 MB FAT16) — do not touch
fex/script.bin, tablet.fex     script.bin and its decoded form
docs/01-hardware-findings.md   full hardware map and the FEX → DTS translation
docs/02-prior-research.md      lessons from earlier attempts by others
docs/03-gt827-driver-port.md   how the touchscreen driver was ported
docs/critical-parameters.txt   key FEX parameters extracted by 20-fex-decode.sh
docs/recon.log                 live Android sysfs dump
dts/sun4i-a10-piranha.dts      the device tree
gt811/                         early driver prototype and the vendor module data
uboot/piranha_a10_defconfig    U-Boot configuration
scripts/                       numbered step scripts (see below)
HANDOFF.md                     engineering notes: decisions, pitfalls, workflow
```

Kernel, U-Boot, toolchain, rootfs and build outputs are excluded by `.gitignore`. The GT827 driver is taken from its own repository.

### Scripts

| Script | Purpose |
|---|---|
| `00-env.sh` | `CROSS_COMPILE` and `PRJ` (derived from the script location) |
| `10-android-recon.sh`, `ondevice-recon.sh` | Collect information from the running Android |
| `20-fex-decode.sh` | Decode `script.bin` into `fex/tablet.fex` and `docs/critical-parameters.txt` |
| `30-kernel-build.sh` | Build the kernel, DTB and modules |
| `45-alpine-stage1.sh`, `45-alpine-stage2.sh` | Build the Alpine rootfs |
| `50-sdcard-alpine.sh` | Partition and write the SD card |
| `80-update-kernel.sh` | Update zImage, DTB and modules on an existing card (host-side `depmod -b`) |
| `setup-pc-usb0.sh` | Configure the PC side of the USB Ethernet link |
| `diag.sh` | Run on the tablet when SSH is unavailable; writes `/diag.txt` |
| `fix-sd.sh` | Repair helper for a written card |

**Legacy (Debian/systemd flow, superseded by Alpine):** `40-rootfs.sh`, `50-sdcard.sh`, `70-network.sh`, `90-wifi-setup.sh`. They are kept for reference and are marked as such in their headers.

## Differences from the Topwise A721 DTS

The DTS is based on the Topwise A721 (Pascal Roeleven, 2020). Changes:

1. **GT827 @ 0x5D** instead of the FT5406 @ 0x38; INT = PH21, RESET = PB13, swapped X/Y and calibrated axes.
2. **`dr_mode = "host"`**: there is no UART, so a USB keyboard was essential on the first boot. (The A721 used `otg`, which did not work here because of the ID pin.) The `g_ether` module forces the gadget side for USB Ethernet.
3. **HDMI enabled**: the only diagnostic channel if the panel does not come up.
4. **Speaker amplifier**: `audio_pa_ctrl = PA10` in the Android FEX is described in the DTS as `allwinner,pa-gpios`.

## Audio

The `piranha` user must be in the `audio` group. To enable the speaker path and test it:

```sh
aplay -l
amixer -c 0 cset numid=1 63
amixer -c 0 cset numid=8 1
amixer -c 0 cset numid=13 1
amixer -c 0 cset numid=14 1
amixer -c 0 cset numid=15 1
amixer -c 0 cset numid=16 1
amixer -c 0 cset numid=17 1
speaker-test -D hw:0,0 -c 2 -r 44100 -F S16_LE -t sine
```

To apply the mixer settings automatically at boot:

```bash
scp scripts/alpine-public/audio-service.sh piranha@10.0.0.2:/tmp/
ssh -t piranha@10.0.0.2 'sudo sh /tmp/audio-service.sh'
```

## First boot and access

There is no UART, so diagnosis relies on the screen and the SD card:

1. **Panel works**: the boot log appears on tty1 (fbcon).
2. **Panel stays dark**: connect HDMI (known to work on archive images).
3. **Neither**: put the card into a PC and read the logs; `scripts/diag.sh` writes a full report to `/diag.txt`.
4. **Network up**: `ssh piranha@<ip>`. USB Ethernet is `10.0.0.2/24` on the tablet and `10.0.0.1/24` on the PC (see the route-conflict note in [HANDOFF.md](HANDOFF.md)).

Default accounts are `root:piranha` and `piranha:piranha`. **Change both passwords after the first boot.**

## Recovery

1. Remove the SD card: Android boots again.
2. If nothing boots at all, remove the card and connect USB: the tablet enters FEL mode (`lsusb` shows `1f3a:efe8`); check with `sunxi-fel version`.
3. For instability or `BUG: Bad page state`, lower the DRAM clock: in `uboot/piranha_a10_defconfig` change `CONFIG_DRAM_CLK=432` to `408`, then `384`, rebuild U-Boot and rewrite only sector 8.

## Known risks

| Risk | Status |
|---|---|
| 🟢 GT827 driver | Out-of-tree driver works; other panels may need a different config blob or calibration |
| 🟡 Panel timing | `starry,kr070pe2t` matches the FEX exactly, so the risk is low |
| 🟡 DRAM @ 432 MHz | Value taken from the FEX; a similar board needed 384. Fallback described above |
| 🟢 U-Boot / SD / AXP209 / Wi-Fi / ALSA | Working |

## What to expect

A single Cortex-A8 at 1.4 GHz, 1 GB RAM and 800×480 put this in the light desktop / kiosk class. JWM, PCManFM and XTerm are installed. Chromium and Firefox are not usable; consider NetSurf or Dillo. The Lima GPU driver works in the kernel; hardware video decoding is the open item described above.

## Honest note on NAND backups

Android exposes the NAND through Allwinner's proprietary FTL as block devices (`nanda`…`nandj`); there is no `/proc/mtd` and no raw `/dev/block/nand`. Only the boot partition (`nanda.img`) is backed up, so **there is no bit-exact Android restore image**. Since nothing is ever written to the NAND, the practical risk is nil, but it is worth knowing.

## Legacy Debian notes

The first rootfs attempt used Debian bookworm armhf and is superseded by Alpine. Pitfalls found on the way:

- On Arch, `dpkg` is not installed, so `debootstrap` fails with `Unknown architecture: x86_64`. The fix was podman with qemu-arm binfmt and the official `debian:bookworm` armhf image.
- `--arch` and `--platform` cannot be combined; use only `--platform linux/arm/v7`.
- systemd does not run in the container, so units were enabled with manual symlinks.
- `useradd -G` fails if the group does not exist; run `groupadd` first.
- `firmware-realtek` is in non-free on bookworm; the firmware can be taken from Android instead.
- podman bind-mounts `/etc/hostname`, `/etc/hosts` and `/etc/resolv.conf`, so after an export the hostname comes back as `debuerreotype` and `hosts` is empty. The legacy scripts repair this.
