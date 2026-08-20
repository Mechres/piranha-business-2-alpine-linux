# Donanım Keşif Sonuçları (script.bin + Android sysfs'ten doğrulandı)

> Tarihsel not: Bu dosyanın ilk bölümleri keşif aşamasındaki GT811 adını
> kullanır. Linux portunda gerçek çalışan cihaz sürücüsü `gt827` olarak
> adlandırılmıştır; Android vendor modülünün adı `gt811_ts-827-fz` idi.

Kaynak: `fex/tablet.fex` (script.bin v1.2, 75 bölüm) + `docs/recon.log` (canlı Android sysfs)

## ⚠️ Kullanıcının ilk bilgisine göre DÜZELTMELER

| Konu | Sen demiştin | Gerçek (doğrulanmış) | Kanıt |
|---|---|---|---|
| Dokunmatik | Goodix **GT827** | **Goodix GT827** @ i2c-2, 0x5D | Android vendor adı `gt811_ts-827-fz`; Linux probe ID `0x27`, input `Goodix GT827 Touchscreen` |
| Ekran | (belirtilmedi) | **800×480** RGB paralel (24-bit, PD00–PD27) | fex `lcd_x=800 lcd_y=480`, fb0 `U:800x480p-59` |
| RAM | MT.Mosel | **512 MB DDR3**, 432 MHz, 1 rank, 32-bit bus | fex `dram_size=512 dram_type=3 dram_clk=432` |

GT811, mainline `goodix.c`'nin desteklediği GT9xx serisinde **DEĞİL**. Bu projenin en büyük teknik riski (aşağıda).

## Kart kimliği
- `ro.product.board` = **crane** · `ro.product.device` = **crane-a702jhorange**
- script.bin `machine` = `A10-EVB-V1.1` · `Hardware: sun4i`
- Android 2.3/4.0 çağı çekirdeği (sun4i-3.0/3.4 fork), `ro.board.platform=exDroid`

## Panel — `[lcd0_para]` → DTS timing çevrimi
```
lcd_x=800  lcd_y=480          → hactive=800  vactive=480
lcd_dclk_freq=33 (MHz)        → clock-frequency = 33000000
lcd_ht=1055  lcd_hbp=46       → hsync+hbp=46, htotal=1055+1=1056  ⇒ hfront = 1056-800-46 = 210
lcd_vt=1050  lcd_vbp=23       → vsync+vbp=23, vtotal=1050/2=525    ⇒ vfront = 525-480-23  = 22
lcd_hv_hspw=0  lcd_hv_vspw=0  → hsync-len=1, vsync-len=1 (fex 0 = "1 saat" demek)
lcd_if=0, lcd_hv_if=0         → paralel RGB (HV sync), 24-bit
```
DTS `panel-timing` (türetilmiş, ilk denemede kullanılacak):
```
clock-frequency = <33000000>;
hactive = <800>; hfront-porch = <210>; hback-porch = <45>; hsync-len = <1>;
vactive = <480>; vfront-porch = <22>; vback-porch = <22>;  vsync-len = <1>;
```
> Not: fex'te hbp = hsync+hback olduğu için hback = 46−1 = 45, vback = 23−1 = 22.

Panel GPIO'ları:
| İşlev | GPIO | fex |
|---|---|---|
| Backlight enable | **PH7** (active high) | `lcd_bl_en = port:PH07<1><0><default><1>` |
| Panel power | **PH8** (active high) | `lcd_power = port:PH08<1><0><default><1>` |
| Backlight PWM | **PB2** (PWM0, 1 kHz, pol=1) | `lcd_pwm = port:PB02<2>` |
| Veri | PD0–PD23, CLK=PD24, DE=PD25, HSYNC=PD26, VSYNC=PD27 | |

## DRAM — U-Boot defconfig için
```
dram_clk=432   dram_type=3 (DDR3)   dram_rank_num=1
dram_chip_density=2048   dram_io_width=16   dram_bus_width=32
dram_cas=6   dram_zq=0x7b   dram_odt_en=0   dram_size=512
dram_tpr0=0x30926692  dram_tpr1=0x1090  dram_tpr2=0x1a0c8
dram_emr1=0x4  dram_emr2=0x8  dram_emr3=0x0
```
→ `CONFIG_DRAM_CLK=432`, `CONFIG_DRAM_ZQ=123` (0x7b), `CONFIG_DRAM_EMR1=4`

## I2C haritası (canlı sysfs — kesin)
| Bus | Adres | Çip | Mainline sürücü |
|---|---|---|---|
| i2c-0 (PB0/PB1) | 0x34 | **AXP209** PMIC | ✅ `axp20x` |
| i2c-1 (PB18/PB19) | 0x18 / 0x1C | dmt / dmard06 ivmeölçer | ✅ `dmard06` |
| i2c-1 | 0x4C | mma7660 ivmeölçer | ✅ `mma7660` |
| i2c-1 | 0x21 / 0x3C | gc0308 / gc0309 kamera | ⚠️ kısmi |
| i2c-2 (PB20/PB21) | **0x5D** | **Goodix GT827 dokunmatik** | ✅ out-of-tree `gt827` sürücüsü |

GT811 kesme/reset (fex `ctp_*_b`): INT = **PH21**, RESET/wakeup = **PB13**
Dokunmatik eksen düzeltmesi: `revert_y=1`, `exchange_x_y=1` → DTS'de `touchscreen-swapped-x-y` + `touchscreen-inverted-y`

## SD kart
- **mmc0** = harici microSD: PF0–PF5, kart algılama **PH1** → boot buradan olacak ✅
- mmc3 = dahili (PI4–PI9, det PH11) — SDIO WiFi olabilir; RTL8188CUS USB dediğin için muhtemelen kullanılmıyor

## AXP209 regülatörleri (fex `[target]` + `[pmu_para]`)
```
dcdc2 = 1400 mV (VDD-CPU)   dcdc3 = 1250 mV (VDD-INT/DLL)
ldo2  = 3000 mV (AVCC)      ldo3 = 2800 mV   ldo4 = 2800 mV
boot_clock = 1008 MHz       pll4/pll6 = 960 MHz
Pil: 4500 mAh, şarj 4.2 V, kapatma 3.3 V, açılma 2.9 V
AC algılama GPIO: PH2
```

## Depolama notu
- `/proc/mtd` YOK → Android NAND'ı blok aygıt olarak sunuyor (`nanda`…`nandj`, major 93) — Allwinner tescilli FTL.
- `/dev/block/nand` (ham aygıt) yok → ham NAND yedeği ADB'den alınamaz.
- **Yedeklenen:** `backup/nanda.img` (16 MB, FAT16 boot bölümü — script.bin, boot.axf, sprite dahil). En kıymetli olan bu; onu aldık.
- Sonuç: **NAND'a asla yazma.** Hynix H27UCG8 = MLC, mainline MTD desteği güvenilmez. Kalıcı olarak SD'den çalışacağız.

## Risk sıralaması (gerçekçi)
1. 🟢 **GT827 dokunmatik** — out-of-tree sürücüsü çalışıyor; başka panel varyantları için config blob ve kalibrasyon uyarlaması gerekebilir.
2. 🟡 **Panel timing** — türetildi ama denenmedi. Yanlışsa kaymış/boş ekran; hfront/vfront ayarıyla düzelir.
3. 🟢 DRAM/U-Boot — parametreler net, düşük risk.
4. 🟢 WiFi (rtl8192cu), AXP209, SD, Mali/Lima, ALSA sun4i-codec — doğrulandı.

## Beklenti ayarı
800×480 + A10 (tek çekirdek Cortex-A8 @1 GHz) + 512 MB RAM. Bu bir masaüstü değil,
**kiosk sınıfı** bir cihaz. Xfce ağır kalır. Hedef: X11 + **Openbox/JWM** ya da wayland+labwc,
tarayıcı olarak netsurf/dillo. Chromium/Firefox bu RAM'de kullanılabilir olmaz.

## Uygulama sonrası doğrulanan durum (2026-08-20)

- Alpine 3.20 armv7 + OpenRC microSD'den boot ediyor.
- `rtl8192cu` Wi-Fi modülü, `g_ether` USB Ethernet ve SSH çalışıyor.
- GT827 sürücüsü `evtest` üzerinden gerçek multitouch olayları üretiyor.
- `sun4i-codec` ALSA kartı `card 0` olarak oluşuyor ve `speaker-test` PCM akışı
  çalışıyor.
- Android FEX'teki `audio_pa_ctrl = port:PA10` bilgisi Linux DTS'e
  `allwinner,pa-gpios = <&pio 0 10 GPIO_ACTIVE_HIGH>` olarak eklendi; dahili
  hoparlör bu tanımdan sonra çalıştı.
- Kernel loglarında Lima Mali-400 ve Cedrus video decoder kayıtlıdır.
- Cedrus kernel aygıtı hazır olsa da mevcut Alpine FFmpeg/mpv paketi stateless
  V4L2 Request API ile donanım dekoderini kullanmamaktadır.
