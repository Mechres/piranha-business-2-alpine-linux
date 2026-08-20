# Piranha A10 — Handoff (sıradaki session için)

**Tarih:** 2026-08-20 (güncelleme: Alpine + GT827 + Wi-Fi + ses TAMAMLANDI)
**Kullanıcı:** Yağız (mechres), Türkçe yanıt istiyor, klavye eziyeti çekiyor (TR layout).

---

## HEDEF
Allwinner A10 "Piranha Business II Tab" tablete mainline Linux. Hafif dokunmatik+ekranlı masaüstü (X11+JWM) + **çalışan ağ** (USB Ethernet g_ether öncelik, WiFi RTL8188CUS ikincil). SD'den boot, NAND'a asla yazma.

## ANA DONANIM (kesin)
- SoC: Allwinner A10 (sun4i), Cortex-A8 1GHz, 512MB RAM
- PMIC: AXP209 | Panel: 800x480 (starry/kr070pe2t) | DRM: sun4i-drm + LCDC
- Touch: **goodix GT827** i2c-2 / 0x5d, INT=PH21 RST=PB13
- WiFi: **RTL8188CUS** (0bda:8176) — tablet İÇİNDE gömülü USB (dongle DEĞİL)
- 2x USB: biri OTG (microUSB, gadget), biri host (USB-A, klavye)
- SD: /dev/sdc (host'ta, her takışta değişebilir)
- UART bulunamadı → ekran + SD journal ile teşhis

## NE YAPILDI (çalışıyor)
- [x] U-Boot: `u-boot-sunxi-with-spl.bin` (565K) — sektör 8'e yazar, NAND'a dokunmaz
- [x] Kernel 7.2.0 mainline derlendi (zImage 6.7MB), toolchain: bootlin armv7-eabihf gcc 13.3
- [x] **GT827 dokunmatik sürücüsü YAZILDI + DERLENDİ**: `kernel/linux/drivers/input/touchscreen/gt827.c` + `gt827_cfg.h`. Gerçek cihaz config blob'u (`gt811/android-ko/cfg_A.bin`, 114B) gömülü. `compatible="goodix,gt827"`. `make modules` ile `gt827.ko` üretildi (vermagic 7.2.0-gcb8a75eec087-dirty — kernel ile eşleşiyor).
- [x] **DTS GT827'ye çevrildi**: `dts/sun4i-a10-piranha.dts` + kernel ağacı kopyası `compatible="goodix,gt827"`. dtbs derlendi (`sun4i-a10-piranha.dtb`, 24KB).
- [x] **WiFi modülü RTL8192CU derlendi**: `.config`'e `CONFIG_WLAN=y`, `CONFIG_CFG80211=y`, `CONFIG_MAC80211=y`, `CONFIG_RTL8192CU=m` ve ilgili RTLWIFI seçenekleri eklendi. Firmware `rootfs/firmware/rtl8192cufw*.bin` hazır.
- [x] **g_ether (USB ETH) modülü hazır**: `CONFIG_USB_ETH=m` (zaten vardı) → `g_ether.ko`.
- [x] Debian 12 bookworm armhf rootfs BOOT EDİYOR (eski; Alpine lehine terk edildi).
- [x] **Alpine 3.20 armhf (armv7) rootfs kuruldu**: `scripts/45-alpine-rootfs.sh` (OpenRC + musl). X11+JWM, openssh, wpa_supplicant, evtest/libinput, TR keymap. `rootfs/alpine/`.
- [x] **OpenRC servisleri enable**: sshd, net.usb0 (statik 10.0.0.2/24), keymaps (trq), modules (g_ether + gt827 bootta), networking, local.
- [x] **Alpine SD yazma scripti**: `scripts/50-sdcard-alpine.sh` (systemd yok, OpenRC runlevel symlink'leri korunur).
- [x] sudo şifresi düzeltildi (fix-sd.sh ile shadow hash PAM'sız yenilendi)

## BROKEN / ÇÖZÜLMEYEN
**Güncel durum:** Temel sistem artık çalışıyor. Bilinen ana eksik, Cedrus stateless V4L2 Request API'sini kullanan FFmpeg/mpv kullanıcı alanı desteğidir.
1. **Cedrus kullanıcı alanı entegrasyonu** — kernel `cedrus` sürücüsü `/dev/video0` olarak kayıtlıdır; Alpine FFmpeg/mpv mevcut haliyle stateless V4L2 Request decode kullanmıyor.
2. **Systemd worker kilitlenmesi (GEÇMİŞTE kaldı)**: Alpine+OpenRC ile rc.local/systemd-worker TUZAĞI YOK. net.usb0 OpenRC servisiyle statik IP.
3. **Wi-Fi**: `CONFIG_WLAN`, `CONFIG_CFG80211`, `CONFIG_MAC80211` ve `CONFIG_RTL8192CU=m` ile kernel modülü çalışıyor. `80-update-kernel.sh` host-side `depmod -b` ile bağımlılık dosyalarını üretmelidir.
4. **USB Ethernet rota çakışması (ÇÖZÜMÜ BİLİNİYOR)**: PC'deki `enp15s0f3u1` USB arayüzü ve `enp10s0` aynı `10.0.0.0/24` ağıyla çakışabiliyor. `ip route get 10.0.0.2` yanlışlıkla `enp10s0` gösterirse ping/SSH USB üzerinden gitmez. Çözüm:
   ```bash
   sudo ip addr replace 10.0.0.1/24 dev enp15s0f3u1
   sudo ip route replace 10.0.0.2/32 dev enp15s0f3u1 src 10.0.0.1
   ip route get 10.0.0.2
   ```
   Son komut `dev enp15s0f3u1` göstermeli. Kalıcı çözüm, `enp10s0` üzerinde `10.0.0.0/24` kullanmamak veya USB ağı için farklı bir subnet seçmektir. Tablet tarafı `usb0=10.0.0.2/24`, PC USB arayüzü `10.0.0.1/24`.
5. **Ses**: `sun4i-codec` ve hoparlör playback çalışıyor. Harici amplifikatör PA10 GPIO'su DTS'te tanımlı; mixer ayarları README'de yer alıyor.
6. **Klavye TR layout**: Alpine `keymaps` servisi `trq` ile çözüldü.

## KRİTİK KARARLAR
- **Debian → Alpine GEÇİLDİ**: 512MB RAM + systemd A10'da sürekli wedge. Alpine (OpenRC, musl) çok daha hafif. YAPILDI.
- WiFi: Alpine OpenRC `wifi` servisi ile bootta otomatik başlıyor.
- GT811 → GT827: sürücü `gt827.c` olarak YAZILDI (gt811.c kernel ağacından SİLİNDİ).

## DOSYA YAPISI (~/projeler/piranha-a10/)
- `kernel/linux/` → mainline kernel ağacı (patched .config, DTS kopyası, **gt827.c/gt827_cfg.h touchscreen altında**)
- `uboot/u-boot/` → U-Boot (u-boot-sunxi-with-spl.bin hazır)
- `dts/sun4i-a10-piranha.dts` → KAYNAK DTS (ARTIK DERLENİYOR, GT827 compatible)
- GT827 sürücüsü → ayrı repo: https://github.com/Mechres/gt827-linux-driver
- `gt811/android-ko/` → orijinal Android modül + cfg_*.bin/fw_gt811.bin (ALTIN DEĞER, gerçek cihaz verisi)
- `scripts/00-env.sh` → CROSS_COMPILE, PRJ (sudo altında $HOME tuzağı, PRJ BASH_SOURCE'ten)
- `scripts/30-kernel-build.sh` → kernel derleme
- `scripts/80-update-kernel.sh` → zImage, DTB, modüller ve host-side depmod
- `scripts/45-alpine-rootfs.sh` → **YENİ** Alpine rootfs (OpenRC)
- `scripts/50-sdcard-alpine.sh` → **YENİ** SD yazma (Alpine)
- `scripts/40-rootfs.sh` (eski Debian), `50-sdcard.sh` (eski Debian) — ARTık kullanılmaz
- `scripts/70-network.sh` `90-wifi-setup.sh` (eski Debian) — Alpine'da gerekmez
- `rootfs/firmware/` → rtl8192cufw*.bin (4 dosya, RTL8188CUS firmware)
- `rootfs/alpine/` → **YENİ** Alpine rootfs (modules_install SONRASI hazır)
- `backup/` → Android nanda.img (boot bölümü yedeği)

## KERNEL DERLEME (gerekirse tekrar)
```bash
cd ~/projeler/piranha-a10/kernel/linux
source ~/projeler/piranha-a10/scripts/00-env.sh
make ARCH=arm CROSS_COMPILE=arm-buildroot-linux-gnueabihf- zImage dtbs modules -j$(nproc)
# GT827/RTL8192CU/g_ether modülleri:
#   drivers/input/touchscreen/gt827.ko
#   drivers/net/wireless/realtek/rtlwifi/rtl8192cu/rtl8192cu.ko
#   drivers/usb/gadget/legacy/g_ether.ko
```

Önerilen güncel yol:

```bash
sudo bash scripts/30-kernel-build.sh
sudo bash scripts/80-update-kernel.sh /dev/sdX
```

`30-kernel-build.sh` proje yolunu script konumundan türetir; `sudo` altında
`/root/projeler/...` hatası vermemelidir. Wi-Fi bağımlılıkları kernel config'e
eklenmiştir. Ses için kernel DTS'te `allwinner,pa-gpios` PA10 tanımı bulunur.

## DC ÇALIŞTIRACAK ADIMLAR (sudo gerekir)
```bash
# 1) Kernel modüllerini Alpine rootfs'a kopyala (Hermes sudo yapamaz)
cd ~/projeler/piranha-a10
source scripts/00-env.sh
cd kernel/linux
sudo make ARCH=arm CROSS_COMPILE=$CROSS_COMPILE INSTALL_MOD_PATH=../rootfs/alpine modules_install

# 2) SD'ye yaz (DEV=/dev/sdX — her seferinde lsblk ile doğrula!)
sudo bash scripts/50-sdcard-alpine.sh /dev/sdX

# 3) Tablette test:
#   dmesg | grep -E 'gt827|rtl|g_ether|usb0'
#   ssh piranha@10.0.0.2   (PC: ip addr add 10.0.0.1/24 dev enp15s0f3u1)
#   WiFi: sudo wifi-connect.sh  (sonra /etc/wpa_supplicant/wpa_supplicant.conf doldur)
```

## HOST ORTAMI
- CachyOS/Arch, mechres. Sudo şifresi bilinmiyor (kullanıcı sudo YAPABİLİYOR, ben yapamıyorum).
- SD rootfs (ext4) root-owned → ben sudo'suz yazamam, kullanıcı `sudo bash script.sh` çalıştırır.
- Boot bölümü (FAT16) udisks ile mechres sahipli mount ediliyor → ben yazabiliyorum.
- USB Ethernet PC tarafı: `enp15s0f3u1` (tablet takınca belirir), `enp10s0` = kendi Ethernet'in.

## KULLANICI NOTLARI
- SD kart çıkar-tak + tablet aç döngüsünden nefret ediyor → uzaktan (SSH) çözüm şart.
- Klavye TR → Alpine `keymaps` (trq) ile çözüldü.
- "Tableti kırıp atmama az kaldı" → sabırsız, net ve çalışan adım ister, tahmin istemez.
- Çıktıları SD'ye `/diag.txt` yazıp ben okuyabiliyorum (en iyi teşhis yolu).
