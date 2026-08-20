# Öncül Araştırma: Bizden Önce Kim Denedi, Ne Öğrendik

## Altın bulgu: Topwise A721 ≈ bizim tablet

`sun4i-a10-topwise-a721.dts` mainline'da mevcut (Pascal Roeleven, 2021) ve bizim kartla
şaşırtıcı derecede örtüşüyor. **fex'ten türettiğim değerlerle karşılaştırma:**

| Öğe | Bizim fex (crane) | Topwise A721 DTS | Eşleşme |
|---|---|---|---|
| Panel | 800×480, 33 MHz, hbp46/vbp23, hfront 210/vfront 22 | `starry,kr070pe2t` = 33 MHz, hfront **209**, hback **45**, vfront **22**, vback **22** | ✅ ~birebir |
| Backlight EN | PH7 | `<&pio 7 7>` PH7 | ✅ |
| LCD power | PH8 | `<&pio 7 8>` PH8 | ✅ |
| PWM | PB2 (pol=1) | `pwm 0 ... PWM_POLARITY_INVERTED` (pwm0_pin = PB2) | ✅ |
| AXP209 | i2c0 @0x34 | `pmic@34` on `&i2c0` | ✅ |
| mma7660 | i2c1 @0x4C | `accelerometer@4c` on `&i2c1` | ✅ |
| SD kart algılama | PH1 | `cd-gpios = <&pio 7 1 ACTIVE_LOW>` | ✅ |
| dcdc2/dcdc3/ldo2 | 1400/1250/3000 mV | 1400/1250/3000 mV | ✅ |
| USB OTG ID/VBUS det | PH4/PH5 (dtsi) | PH4/PH5 | ✅ |
| **Dokunmatik** | **GT827** @ i2c2 **0x5D** (Android vendor adı GT811) | `edt,edt-ft5406` @ **0x38** | ❌ **TEK FARK** |

Sonuç: A721 DTS'i temel alıp **sadece dokunmatik düğümünü** değiştirmek yeterli.
Panel için ayrı iş yok — `starry,kr070pe2t` doğrudan çalışıyor.

> Not: fex'te `ctp_name = "ft5x_ts" @0x38` (birincil) ve `ctp_name_b = "gt811_ts" @0x5D` (ikincil)
> ikisi de var — Allwinner referans tasarımı iki dokunmatik seçeneği taşıyor. Canlı sysfs
> **gerçekte takılı olanın GT811 olduğunu** kanıtlıyor (`2-005d`, input event2). A721'de
> FT5406 lehimlenmiş, bizde GT811. Aynı kart, farklı dokunmatik stoğu.

## Bizden önce deneyen kişi: `Softwinners_crane` (Shivam Gupta, 2025)

Armbian forum konusu #52328 + Unix SE #796123. **Aynı `crane` kartı.** Sonuçları:

### Neyin çalıştığı kanıtlanmış ✅
- U-Boot SD'den boot ediyor
- **Linux gerçekten boot ediyor** — "Starting kernel..." sonrası sessizlik ekran yokluğundandı, çöküş değil (UART lehimleyince login prompt'u gördü)
- **HDMI çalışıyor** (arşiv Cubieboard imajında)
- SSH + seri konsol çalışıyor

### Karşılaştığı sorunlar ve nedenleri ⚠️
| Sorun | Kök neden / çözüm |
|---|---|
| "Starting kernel..." sonrası hiçbir şey | Ekran düğümü yok → **UART veya HDMI olmadan kör uçuş**. Bizim durumda kritik. |
| `BUG: Bad page state`, kernel panic, kararsızlık | **DRAM saati fazla yüksek.** Onun fex'i 384 diyordu, o 432 ile derlemişti. Bizim fex `dram_clk=432` — bizim için doğru olan bu, ama kararsızlık görürsek **ilk düşürülecek şey budur.** |
| USB klavye/mouse çalışmıyor | **USB OTG rolü**. `dr_mode = "otg"` ID-pin algılamasına güveniyor, çalışmıyor. Çözüm: `dr_mode = "host"` zorla. |
| RAM 1 GB (A088 kartı) | **Bizden farklı**: onun kartı 1 GB, bizim `dram_size=512`. Farklı varyant — onun DRAM sonuçlarını bize birebir uygulamayalım. |

### Bizim için doğrudan aksiyona dönüşen dersler
1. **`dr_mode = "host"` yap** → USB klavye/mouse ilk boot'ta çalışsın (UART yok, girdi şart).
2. **DRAM 432'de başla**, kararsızlık olursa 408 → 384 diye düş. (fex'imiz 432 diyor, onun kartı 384'tü — bizim değerimize güveniyoruz ama plan B hazır.)
3. **HDMI düğümlerini de aç** → panel çalışmazsa HDMI yedek çıkış olur. UART'ımız olmadığı için bu **bizim tek teşhis kanalımız**.
4. Ekran çıkışını erken al: `CONFIG_FRAMEBUFFER_CONSOLE` + `LOGO`, ve boot log'unu SD'ye yaz (rootfs'te kalıcı journal) → kartı PC'de okuyup teşhis edebilelim.
5. **A2 değil, normal Class 10 / A1 SD** tercih et (A2 kartlar bu eski MMC denetleyicilerde sorunlu).

## GT811 durumu (C ayağı)
- Mainline `goodix.c`: sadece GT9xx (GT911/928/9271...). GT811 **yok**, DT binding'i de yok.
- GT811, GT9xx'ten farklı protokol (farklı register düzeni, farklı init).
- Sonuç: sunxi-3.4 çağı vendor sürücüsü incelenerek `gt827` out-of-tree modülü
  yazıldı ve Alpine üzerinde çalıştırıldı.

## Güncel sonuç

Bu araştırma notu tarihsel port planıdır. GT827 sürücüsü, Wi-Fi, ALSA ses,
PA10 hoparlör amplifikatörü, Lima GPU ve Cedrus kernel sürücüsü artık doğrulandı.
- Zamanlama: ekran+boot çalıştıktan sonra. USB klavye/mouse ile bu arada cihaz kullanılabilir.

## Kaynaklar
- linux-sunxi crane sayfası: https://linux-sunxi.org/Softwinners_crane
- crane fex (PR): https://github.com/linux-sunxi/sunxi-boards/pull/72/files
- Armbian konu: https://forum.armbian.com/topic/52328-
- A721 DTS patch: https://lkml.iu.edu/hypermail/linux/kernel/2102.2/00521.html
