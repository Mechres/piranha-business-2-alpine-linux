# Piranha Business II Tab — Mainline Linux & Alpine Bring-up

[![SoC: Allwinner A10](https://img.shields.io/badge/SoC-Allwinner%20A10%20(sun4i)-blue.svg)](#hardware-specifications)
[![Kernel: Linux 7.2](https://img.shields.io/badge/Kernel-Mainline%20Linux%207.2-green.svg)](#hardware-support-status)
[![OS: Alpine Linux 3.20](https://img.shields.io/badge/OS-Alpine%20Linux%203.20%20ARMv7-purple.svg)](#quick-start)

Standalone bring-up project and reproducible build tree for running modern mainline Linux and Alpine Linux on the **Piranha Business II Tab**, a single-core Allwinner A10 tablet (Softwinners `crane` / `crane-a702jhorange`).

The internal NAND remains completely untouched; the entire system boots from an external microSD card. Removing the SD card restores the factory Android system (A10 BROM boot order: SD → NAND → FEL).

The touchscreen is a Goodix **GT827**, which mainline `goodix.c` does not support. The out-of-tree driver lives in its own repository: [gt827-linux-driver](https://github.com/Mechres/gt827-linux-driver).

---

## Hardware Specifications

| Component | Specification | Details / Bus |
| :--- | :--- | :--- |
| **SoC** | Allwinner A10 (`sun4i`) | Single-core ARM Cortex-A8 @ 1.4 GHz |
| **RAM** | 1 GB DDR3 | `dram_clk=432` from the FEX (the FEX also contains an older, incorrect `dram_size=512`) |
| **PMIC** | X-Powers AXP209 | I2C0 @ 0x34 |
| **Display** | 800×480 parallel RGB | Matches mainline `starry,kr070pe2t`; backlight enable PH7, panel power PH8, PWM0 on PB2 |
| **Touchscreen** | Goodix GT827 | I2C2 @ **0x5d** (INT = PH21, RST = PB13); Android vendor module is named `gt811_ts-827-fz` |
| **Storage** | MicroSD (`mmc0`) | PF0–PF5, card detect PH1; Hynix H27UCG8 MLC NAND is never written |
| **USB** | OTG + host | Micro-USB OTG (gadget), USB-A host |
| **Accelerometer** | dmard06 / mma7660 | I2C1 @ 0x1c / 0x4c |
| **Wireless** | Realtek RTL8188CUS | USB `0bda:8176`, soldered inside the tablet (not a dongle) |
| **Audio** | `sun4i-codec` | External speaker amplifier on PA10 |
| **Debug Port** | none found | Diagnosis relies on the screen, HDMI and the SD card logs |

---

## Hardware Support Status

| Subsystem | Driver / Mechanism | Status | Notes |
| :--- | :--- | :--- | :--- |
| **BROM & SPL** | Allwinner BROM / U-Boot SPL | **Working** | Boots from microSD, written at sector 8 |
| **U-Boot** | Mainline U-Boot | **Working** | `uboot/piranha_a10_defconfig` |
| **PMIC** | `axp20x` | **Working** | AXP209 on I2C0 |
| **MicroSD Storage** | `sunxi-mmc` (`mmc0`) | **Working** | Rootfs on partition 2 |
| **USB Gadget** | `musb-sunxi` + `g_ether` (`usb0`) | **Working** | CDC Ethernet, tablet side 10.0.0.2/24 |
| **SSH Server** | OpenSSH on Alpine Linux | **Working** | Over USB Ethernet or Wi-Fi |
| **Wi-Fi** | `rtl8192cu` (`wlan0`) | **Working** | Firmware from `rootfs/firmware/` |
| **Touchscreen** | out-of-tree `gt827` | **Working** | Multitouch verified with `evtest`; config blob taken from the vendor module |
| **Display (LCD)** | `sun4i-drm` + fbdev | **Working** | 800×480; HDMI enabled as a fallback output |
| **Audio** | `sun4i-codec` (ALSA) | **Working** | Speaker amplifier enabled via `allwinner,pa-gpios` (PA10) |
| **GPU** | Lima (Mali-400) | **Working** | Kernel driver registers |
| **Video decoder** | Cedrus (`/dev/video0`) | **Partial** | Kernel driver works; Alpine FFmpeg/mpv do not use stateless V4L2 Request decoding yet |
| **Camera** | gc0308 / gc0309 | **Not supported** | No mainline support worked out |

---

## Boot Architecture

```
[BROM] → [SPL] (microSD sector 8)
           ↓
[U-Boot] (u-boot-sunxi-with-spl.bin)
  └── Loads zImage + sun4i-a10-piranha.dtb from the FAT boot partition
        ↓
[Linux Kernel 7.2 Mainline]
  ├── AXP209 PMIC, sunxi-mmc root mount, sun4i-drm display
  ├── gt827 touchscreen (I2C2 0x5d), sun4i-codec audio
  └── modules-load: g_ether (usb0), gt827, rtl8192cu (wlan0)
        ↓
[Alpine Linux 3.20 (ARMv7, OpenRC)]
  ├── sshd, net.usb0 (10.0.0.2/24), wifi, keymaps (trq)
  └── X11 + JWM, XTerm, PCManFM
```

A single Cortex-A8 with 1 GB RAM and 800×480 puts this in the light desktop / kiosk class. Chromium and Firefox are not usable; consider NetSurf or Dillo.

---

## Quick Start

All scripts derive the project root from their own location, so they also work under `sudo`.

### 0. Host Requirements
- Linux x86_64 workstation with `git`, `make`, `gcc`, `bison`, `flex`, `swig`, `python3`, `bc`, `libssl-dev`, `curl`, `xz`
- `podman` and `qemu-user-static` with the `qemu-arm` binfmt handler registered (for the Alpine rootfs)
- `sunxi-tools` is built automatically by `20-fex-decode.sh` if you want to re-decode `script.bin`

### 1. Build Everything
```bash
# Download the toolchain (Bootlin), mainline Linux (pinned commit) and U-Boot.
# Skip the toolchain with SKIP_TOOLCHAIN=1 if you use your own (TOOLCHAIN_DIR / CROSS_COMPILE).
bash scripts/fetch-sources.sh

# U-Boot (also produces tools/mkimage used by the SD card script)
bash scripts/25-uboot-build.sh

# Linux kernel, DTB (the script installs dts/sun4i-a10-piranha.dts into the tree) and modules,
# plus the out-of-tree GT827 touchscreen module from gt827/
bash scripts/30-kernel-build.sh

# Alpine rootfs (stage 1 needs no root; stage 2 installs packages, services, modules)
bash scripts/45-alpine-stage1.sh
sudo bash scripts/45-alpine-stage2.sh
```

### 2. Flash to MicroSD Card
```bash
# Verify the device with lsblk first: this ERASES it.
# The script asks you to type WRITE and refuses non-removable disks.
lsblk -o NAME,SIZE,RM,MODEL,MOUNTPOINTS
sudo bash scripts/50-sdcard-alpine.sh /dev/sdX
```

To update only the kernel, DTB and modules on an existing card:
```bash
sudo bash scripts/80-update-kernel.sh /dev/sdX
```

### 3. Connect via USB Networking & SSH
Once booted with the USB cable connected to your PC:
```bash
sudo ip addr add 10.0.0.1/24 dev enp15s0f3u1   # use your own interface name
ssh piranha@10.0.0.2
```

Default accounts are `root:piranha` and `piranha:piranha`. **Change both passwords after the first boot.** If ping or SSH does not go over USB, see the route-conflict note in [HANDOFF.md](HANDOFF.md).

### 4. Audio
The `piranha` user must be in the `audio` group. To enable the speaker path at boot:
```bash
scp scripts/alpine-public/audio-service.sh piranha@10.0.0.2:/tmp/
ssh -t piranha@10.0.0.2 'sudo sh /tmp/audio-service.sh'
```
The mixer controls it sets are listed in [scripts/alpine-public/README.md](scripts/alpine-public/README.md).

---

## Debugging Without a UART

There is no serial port, so diagnosis works like this:

1. **Panel works:** the boot log appears on tty1 (fbcon).
2. **Panel stays dark:** connect HDMI.
3. **Neither:** put the SD card into a PC and read the logs. Run `scripts/diag.sh` on the tablet to write a full report to `/diag.txt`.

## Recovery

1. Remove the SD card: Android boots again.
2. If nothing boots at all, remove the card and connect USB: the tablet enters FEL mode (`lsusb` shows `1f3a:efe8`); check with `sunxi-fel version`.
3. For instability or `BUG: Bad page state`, lower the DRAM clock: in `uboot/piranha_a10_defconfig` change `CONFIG_DRAM_CLK=432` to `408`, then `384`, rebuild U-Boot and rewrite only sector 8.

> There is no bit-exact Android restore image: Android exposes the NAND through Allwinner's proprietary FTL (`nanda`…`nandj`), so only the boot partition (`backup/nanda.img`) is backed up. Since nothing is ever written to the NAND, the practical risk is nil.

---

## Repository Layout

```
backup/nanda.img               Android boot partition backup (16 MB FAT16) — do not touch
fex/script.bin, tablet.fex     script.bin and its decoded form
dts/sun4i-a10-piranha.dts      the device tree (based on Topwise A721)
uboot/piranha_a10_defconfig    U-Boot configuration
gt811/                         early driver prototype and the vendor module data
scripts/                       numbered step scripts
scripts/alpine-public/         portable Alpine flow and on-tablet helpers
docs/                          hardware findings, prior research, driver port notes
```

Kernel, U-Boot, toolchain, rootfs and build outputs are excluded by `.gitignore`.

**Legacy (Debian/systemd flow, superseded by Alpine):** `40-rootfs.sh`, `50-sdcard.sh`, `70-network.sh`, `90-wifi-setup.sh`. They are marked as such in their headers.

### DTS differences from the Topwise A721

The DTS is based on the Topwise A721 (Pascal Roeleven, 2020). Changes:

1. **GT827 @ 0x5D** instead of the FT5406 @ 0x38; swapped X/Y and calibrated axes.
2. **`dr_mode = "host"`:** the A721's `otg` did not work here because of the ID pin; a USB keyboard was essential on the first boot. The `g_ether` module forces the gadget side for USB Ethernet.
3. **HDMI enabled** as a fallback output.
4. **Speaker amplifier:** `audio_pa_ctrl = PA10` in the Android FEX is described as `allwinner,pa-gpios`.

---

## Documentation

- [docs/01-hardware-findings.md](docs/01-hardware-findings.md) — Full hardware map and the FEX → DTS translation.
- [docs/02-prior-research.md](docs/02-prior-research.md) — Lessons from earlier attempts by others.
- [docs/03-gt827-driver-port.md](docs/03-gt827-driver-port.md) — How the touchscreen driver was ported.
- [HANDOFF.md](HANDOFF.md) — Engineering notes: decisions, pitfalls, working procedure.
- [scripts/alpine-public/README.md](scripts/alpine-public/README.md) — Portable Alpine flow, audio mixer, kernel/Wi-Fi notes.

