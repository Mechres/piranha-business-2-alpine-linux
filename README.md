# Piranha Business II Tab → Linux

**Cihaz:** Allwinner A10 (sun4i, Cortex-A8 @1GHz) · AXP209 · 512MB DDR3 · RTL8188CUS WiFi · Hynix H27UCG8 NAND (MLC) · **Goodix GT827** dokunmatik · 800×480 panel
**Kart kimliği:** Softwinners `crane` / `crane-a702jhorange` · script.bin `A10-EVB-V1.1`
**Hedef:** microSD'den boot eden, ekran + dokunmatik + ağ + ses çalışan çok hafif Alpine masaüstü (OpenRC + X11 + JWM)

## Altın kural
NAND'a **hiçbir şey yazılmıyor.** A10 BROM sırası: SD → NAND → FEL.
SD takılıysa SD'den boot eder, çıkarınca Android geri gelir.

## Güncel donanım durumu
- Dokunmatik Linux tarafında **GT827** olarak çalışıyor (@i2c2 0x5D); Android vendor modülü `gt811_ts-827-fz` adını kullanıyor.
- RAM: 512 MB DDR3 @432 MHz
- Panel: 800×480, mainline `starry,kr070pe2t` ile **birebir** eşleşiyor

GT827 sürücüsü ayrı bir repoda geliştirilmektedir:
<https://github.com/Mechres/gt827-linux-driver>

## Durum
- [x] 0. Host ortamı: bootlin armhf gcc 13.3, dtc, podman, qemu-user-static, sunxi-tools, adb
- [x] 1. Android keşif + `nanda.img` (16MB boot bölümü) yedeği + script.bin çıkarıldı
- [x] 2. script.bin → `fex/tablet.fex` (966 satır) → panel/DRAM/i2c/GPIO parametreleri
- [x] 3. **U-Boot derlendi** → `uboot/u-boot/u-boot-sunxi-with-spl.bin` (565 KB)
- [x] 4. **Kernel derlendi** → `kernel/linux/arch/arm/boot/zImage` (5.8 MB) + modüller
- [x] 5. **Özel DTS derlendi** → `sun4i-a10-piranha.dtb` (24 KB)
- [x] 6. **GT827 sürücüsü yazıldı + derlendi** → `gt827.ko`, panel config seçimi ve koordinat kalibrasyonu
- [x] 7. Alpine 3.20 armv7 rootfs, OpenRC, SSH, Wi-Fi ve X11/JWM hazır
- [x] 8. SD karttan Alpine boot edildi
- [x] 9. Wi-Fi, USB Ethernet ve SSH doğrulandı
- [x] 10. ALSA codec ve PA10 hoparlör amplifikatörü doğrulandı
- [x] 11. Lima GPU ve Cedrus VPU kernel sürücüleri doğrulandı

## Çalıştırma sırası
```bash
cd ~/projeler/piranha-a10

# Alpine rootfs
bash scripts/45-alpine-stage1.sh
sudo bash scripts/45-alpine-stage2.sh

# 2) SD karta yaz — 'YAZ' onayı ister, iç diskleri reddeder
sudo bash scripts/50-sdcard-alpine.sh /dev/sdX
```

## Podman/debootstrap notu (çözülmüş tuzak)
Arch'ta `dpkg` kurulu olmadığı için `debootstrap` host mimarisini tanıyamıyor
(`Unknown architecture: x86_64`). Çözüm: debootstrap yerine **podman + qemu-arm binfmt**
ile resmi `debian:bookworm` armhf imajı. Doğrulandı: `uname -m`=armv7l, `dpkg
--print-architecture`=armhf.

Dikkat edilecekler:
- `--arch` ile `--platform` birlikte kullanılamaz → sadece `--platform linux/arm/v7`
- Konteynerde systemd çalışmaz → `systemctl enable` yerine elle symlink
- `useradd -G` grup yoksa patlar → önce `groupadd`
- `firmware-realtek` bookworm main'de yok (non-free) → çıkarıldı; gerekirse Android'den alınır
- **podman `/etc/hostname`, `/etc/hosts`, `/etc/resolv.conf`'u bind-mount eder** →
  export'ta hostname `debuerreotype` döner, hosts boşalır. Scriptler bunları düzeltiyor.

## Klasör düzeni
```
backup/nanda.img          Android boot bölümü yedeği (16MB FAT16) — DOKUNMA
fex/script.bin,tablet.fex script.bin + çözülmüş hali
docs/01-donanim-bulgulari.md   tüm donanım haritası + fex→DTS çevrimi
docs/02-oncul-arastirma.md     bizden önce deneyenlerin dersleri
docs/recon.log            canlı Android sysfs dökümü
dts/sun4i-a10-piranha.dts bizim device tree'miz
uboot/piranha_a10_defconfig    U-Boot yapılandırması
scripts/                  numaralı adım scriptleri
```

Kernel, U-Boot, toolchain, rootfs ve derleme çıktıları `.gitignore` ile ana
repo dışında tutulur. GT827 sürücüsü de ayrı reposundan alınmalıdır.

## DTS'te A721'den yaptığımız farklar
1. **GT827 @0x5D** (FT5406 @0x38 yerine) — INT=PH21, RST=PB13, swapped-x-y + calibrated axes
2. **`dr_mode = "host"`** — UART yok, USB klavye ilk boot'ta şart (A721'de "otg" idi ve çalışmıyordu)
3. **HDMI etkin** — panel çalışmazsa tek teşhis kanalı
4. **Ses amplifikatörü** — Android FEX'teki `audio_pa_ctrl = PA10`, DTS'te `allwinner,pa-gpios` olarak tanımlı

## Ses doğrulama

Tablette `piranha` kullanıcısı `audio` grubunda olmalıdır. Mixer ayarlarını
uygulayıp test etmek için:

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

## İlk boot: ne beklemeli
UART olmadığı için teşhis planı:
1. **Panel açılırsa** → tty1'de boot log'u göreceksin (`fbcon`, `ForwardToConsole=yes`)
2. **Panel açılmazsa** → HDMI'a bağla (arşiv imajlarda HDMI çalıştığı doğrulanmış)
3. **İkisi de yoksa** → SD'yi PC'ye tak, `/var/log/journal/` oku (kalıcı journal açık)
4. WiFi/ethernet gelirse → `ssh piranha@<ip>` (şifre: `piranha`)

Kullanıcılar: `root:piranha` ve `piranha:piranha` — **ilk boot sonrası değiştir.**

## Kurtarma
1. SD'yi çıkar → Android geri döner.
2. Boot hiç olmazsa: SD'yi çıkar, USB tak → FEL modu (`lsusb` 1f3a:efe8) → `sunxi-fel version`
3. Kararsızlık / `BUG: Bad page state` → DRAM saatini düşür: `uboot/piranha_a10_defconfig`'de
   `CONFIG_DRAM_CLK=432` → `408` → `384`, U-Boot'u yeniden derle ve sadece sektör 8'i yaz.

## Bilinen riskler
| Risk | Durum |
|---|---|
| 🟢 GT827 sürücüsü | Out-of-tree sürücü çalışıyor; başka paneller için config/kalibrasyon değişebilir. |
| 🟡 Panel timing | `starry,kr070pe2t` fex ile birebir eşleşti — risk düşük ama denenmedi |
| 🟡 DRAM 432 MHz kararlılığı | fex değeri; benzer kartta 384 gerekmişti. Plan B hazır. |
| 🟢 U-Boot / SD / AXP209 / WiFi / ALSA | Çalışıyor |

## Beklenti
Tek çekirdek A8 @1GHz + 512MB RAM + 800×480 = **kiosk sınıfı**.
JWM + pcmanfm + xterm kurulu. Chromium/Firefox kullanılabilir olmaz; netsurf/dillo düşün.
Lima GPU kernel'de çalışıyor. Cedrus VPU `/dev/video0` olarak kayıtlı; mevcut Alpine
FFmpeg/mpv kullanıcı alanı stateless Cedrus hızlandırmasını henüz kullanmıyor.

## Tam NAND yedeği hakkında dürüst not
Android NAND'ı Allwinner tescilli FTL üzerinden blok aygıt olarak sunuyor (`nanda`…`nandj`);
`/proc/mtd` ve ham `/dev/block/nand` yok. Yani **birebir Android geri-yükleme imajı elimizde değil** —
sadece boot bölümü (`nanda.img`) var. NAND'a yazmadığımız için pratik risk yok, ama bilinsin.
