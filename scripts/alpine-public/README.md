# Piranha Business II Tab — Alpine setup tools

This folder holds portable entry points for reproducing the project on another computer or with another user.

## Requirements

- Linux host
- `podman`, `qemu-user-static-binfmt`
- ARM toolchain and a built kernel/U-Boot
- A writable microSD card

The scripts find the project root from their own location; they do not depend on `$HOME` or hard-coded user paths.

## Recommended flow

```bash
cd /path/to/piranha-a10

# Rootfs preparation; the first step does not need sudo
bash scripts/alpine-public/build-rootfs-stage1.sh

# Packages, OpenRC services and kernel modules
sudo bash scripts/alpine-public/build-rootfs-stage2.sh

# Verify DEV with lsblk; this ERASES the card
lsblk -o NAME,SIZE,RM,MODEL,MOUNTPOINTS
sudo bash scripts/alpine-public/write-sdcard.sh /dev/sdX
```

After the card has booted, set up USB Ethernet on the host computer:

```bash
sudo bash scripts/alpine-public/setup-usb-network.sh enp15s0f3u1
ssh piranha@10.0.0.2
```

To install the Wi-Fi autostart service on the tablet, copy the script over USB SSH or Wi-Fi SSH:

```bash
scp scripts/alpine-public/wifi-service.sh piranha@10.0.0.2:/tmp/
ssh -t piranha@10.0.0.2 'sudo sh /tmp/wifi-service.sh'
```

The Wi-Fi SSID and password are stored on the tablet in `/etc/wpa_supplicant/wpa_supplicant.conf`.

## Light desktop

To install JWM + XTerm + PCManFM, run on the tablet:

```bash
scp scripts/alpine-public/desktop-setup.sh piranha@10.0.0.2:/tmp/
ssh -t piranha@10.0.0.2 'sudo sh /tmp/desktop-setup.sh'
```

After logging in as `piranha` with a USB keyboard on the tablet, test the graphical session with:

```bash
startx
```

## Safety

`write-sdcard.sh` erases all data on the target disk and asks for its own confirmation. Always verify the target device with `lsblk`. Change the default passwords after the first boot.

## Kernel updates and Wi-Fi

For a kernel or Device Tree change, build and update the SD card from the host:

```bash
sudo bash scripts/30-kernel-build.sh
sudo bash scripts/80-update-kernel.sh /dev/sdX
```

The kernel configuration must include the Wi-Fi dependencies as well as the
driver:

```text
CONFIG_WLAN=y
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_RTL8192CU=m
```

`80-update-kernel.sh` generates `modules.dep` with host-side `depmod -b`; an
ARM `chroot depmod` is not required.

## Audio

The A10 `sun4i-codec` ALSA card is enabled by the Piranha Device Tree. The
external speaker amplifier is controlled by PA10, identified from the Android
FEX and represented in the DTS as:

```dts
allwinner,pa-gpios = <&pio 0 10 GPIO_ACTIVE_HIGH>;
```

On the tablet, add the user to the audio group and re-login:

```sh
sudo addgroup piranha audio
aplay -l
```

The speaker mixer can be enabled with:

```sh
amixer -c 0 cset numid=1 63
amixer -c 0 cset numid=8 1
amixer -c 0 cset numid=13 1
amixer -c 0 cset numid=14 1
amixer -c 0 cset numid=15 1
amixer -c 0 cset numid=16 1
amixer -c 0 cset numid=17 1
speaker-test -D hw:0,0 -c 2 -r 44100 -F S16_LE -t sine
```

To apply the mixer settings automatically at boot, install the OpenRC service:

```bash
scp scripts/alpine-public/audio-service.sh piranha@10.0.0.2:/tmp/
ssh -t piranha@10.0.0.2 'sudo sh /tmp/audio-service.sh'
```

The service waits for `/dev/snd/controlC0`, enables the speaker mixer path and
is added to the default runlevel.

## Graphics and video acceleration

The kernel registers Lima for the Mali-400 GPU and Cedrus as `/dev/video0`.
The current Alpine FFmpeg/mpv userland does not yet provide working stateless
Cedrus V4L2 Request decoding, so VPU support is present in the kernel but is
not automatically used by mpv.

## GT827 driver

The touchscreen driver is maintained separately:

<https://github.com/Mechres/gt827-linux-driver>

Clone it beside this project when building or adapting the touchscreen driver.
The Piranha-specific Device Tree still belongs in this repository because it
also contains the board's GPIO, display, audio and power definitions.
