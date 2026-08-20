# Piranha Business 2 Tab 9 - Alpine kurulum araçları

Bu klasör, projeyi başka bir bilgisayarda veya başka bir kullanıcıyla
tekrarlanabilir şekilde kurmak için hazırlanmış giriş noktalarını içerir.

## Gereksinimler

- Linux host
- `podman`, `qemu-user-static-binfmt`
- ARM toolchain ve derlenmiş kernel/U-Boot
- Yazılabilir bir microSD kart

Scriptler proje kökünü kendi konumlarından bulur; `$HOME` veya sabit kullanıcı
yollarına bağlı değildir.

## Önerilen akış

```bash
cd /path/to/piranha-a10

# Rootfs hazırlığı; ilk adım sudo istemez
bash scripts/alpine-public/build-rootfs-stage1.sh

# Paketler, OpenRC servisleri ve kernel modülleri
sudo bash scripts/alpine-public/build-rootfs-stage2.sh

# DEV'i lsblk ile doğrula; bu işlem kartı siler
lsblk -o NAME,SIZE,RM,MODEL,MOUNTPOINTS
sudo bash scripts/alpine-public/write-sdcard.sh /dev/sdX
```

SD açıldıktan sonra USB Ethernet için host bilgisayarda:

```bash
sudo bash scripts/alpine-public/setup-usb-network.sh enp15s0f3u1
ssh piranha@10.0.0.2
```

Wi-Fi otomatik başlatma servisini tablete kurmak için dosyayı USB SSH veya
Wi-Fi SSH üzerinden gönder:

```bash
scp scripts/alpine-public/wifi-service.sh piranha@10.0.0.2:/tmp/
ssh -t piranha@10.0.0.2 'sudo sh /tmp/wifi-service.sh'
```

Wi-Fi SSID ve şifresi tablette şu dosyada bulunur:
`/etc/wpa_supplicant/wpa_supplicant.conf`.

## Hafif masaüstü

JWM + XTerm + PCManFM kurulumu için tablet üzerinde:

```bash
scp scripts/alpine-public/desktop-setup.sh piranha@10.0.0.2:/tmp/
ssh -t piranha@10.0.0.2 'sudo sh /tmp/desktop-setup.sh'
```

USB klavye ile tablette `piranha` kullanıcısı olarak giriş yaptıktan sonra
grafik oturumunu test etmek için:

```bash
startx
```

## Güvenlik

`write-sdcard.sh` hedef diskteki tüm veriyi siler ve kendi onayını ister.
Hedef aygıtı her zaman `lsblk` ile doğrula. Varsayılan parolaları ilk açılıştan
sonra değiştir.

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
