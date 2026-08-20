# GT811 Sürücü Portu — GÜNCEL DURUM (2026-08-20)

## ✅ ÇIKANLAR (gerçek cihazdan)

Cihazda çalışan `gt811_ts-827-fz.ko` (modül `gt811_ts_827_fz_di`, lsmod'da yüklü)
pull edildi: `gt811/android-ko/gt811_ts-827-fz.ko` (202499 B, **not stripped, debug_info**).

`readelf` ile çıkarılan semboller:
- `goodix_gt811_firmware` (3844 B) → `fw_gt811.bin` (cihaza özgü firmware/checksum tablosu)
- `C.55/59/63` → 3× `cfg_A/B/C.bin` (114 B config blob) — **gt82x.c data_info0/1 ile birebir**
- `gpio_int_info`, `goodix_ts_id` da var

**Doğrulama:** `cfg_A.bin` = `0f 80 00 0f 01 10 02 11 03 12 ...` →
kaynak `gt82x.c`'nin `data_info1[]` dizisiyle **birebir aynı**. Protokol eşleşmesi kanıtlandı.

→ Artık gt82x.c'yi temel alıp mainline input API'sine port ederken, **cihaza özgü
  114-byte config blob'unu doğrudan `fw_gt811.bin`/`cfg_*.bin` içinden kullanabiliriz.**
  Tahmin/türetme yok — cihazın kendi inited verisi.

## Modül bilgisi
- vermagic: `3.0.8+ preempt mod_unload modversions ARMv7` (Android 4.0.4 çekirdeği)
- Vendor/Product ID: input'ta `Bus=0018 Vendor=dead Product=beef`
  (0x18=I2C, 0xdeadbeef = standart Goodix placeholder)

## Protokol (gt82x.c + gerçek blob ile doğrulandı)
- I2C addr: 0x5d (DTS'te `<0x5d>`)
- Init: config yazma `0F 80` komutu + 114B blob (3 kez, farklı offset)
- Veri: `80 00` → 10B oku; parmak bitmask point_data[2], x/y/width 5B/parmak
- Checksum: byte[4..] toplamı == son byte
- Eksen düzeltme: `touchscreen-inverted-y` + `touchscreen-swapped-x-y` (DTS'te var)
- INT: PH21 (falling edge), RST: PB13

## SONRAKİ ADIM: mainline port kodu yaz
`gt811/android-ko` referans; `gt82x.c` (964 satır) temel. Yeni dosya:
`kernel/linux/drivers/input/touchscreen/gt811.c`

Modernizasyon (bkz. 03-gt811-port-plani.md 8 madde):
earlysuspend→PM, init-input→kaldır, i2c→regmap, gpio/irq→DT,
input_dev→MT (ABS_MT_*), Kconfig/Makefile, DT compatible "goodix,gt811".

Config blob: `gt811_send_cfg()` içine `fw_gt811.bin` verisi gömülü olarak yazılacak.
(Blob'u .c dizisine çevirmek için: `xxd -i fw_gt811.bin > gt811_fw.h`).

## Bu ayağın durumu
- [x] Kaynak sürücü (gt82x.c) bulundu
- [x] Gerçek cihaz modülü + config blob'u çıkarıldı (ALTIN DEĞER)
- [x] Protokol doğrulandı
- [ ] mainline `gt811.c` yazılacak  ← boot sonrası
- [ ] Kconfig/Makefile
- [ ] `make M=drivers/input/touchscreen` ile modül derle
- [ ] tablette insmod + evtest

## Güncel sonuç

Plan tamamlandı ve sürücü artık `gt827` adıyla çalışıyor. Android modülünün
`gt811_ts-827-fz` adı tarihsel vendor adıdır; Linux sürücüsü GT827 protokolünü
ve panel config blob'larını kullanır.

- `drivers/gt827/gt827.c` ve `gt827_cfg.h` kaynakları mevcut.
- Kernel kopyaları `kernel/linux/drivers/input/touchscreen/` altındadır.
- Panel varyantı `0x0ff5` register'ından otomatik seçilir.
- Piranha kalibrasyonu yaklaşık raw Y `30..600` aralığındadır.
- `evtest` üzerinde `ABS_MT_POSITION_X/Y` ve `BTN_TOUCH` olayları doğrulandı.
- Sürücü `modules-load.d` üzerinden boot sırasında yüklenebilir.

Bu nedenle yukarıdaki “sonraki adım” listesi tarihsel port planıdır; yeni
donanımlarda yapılacak işler yalnızca config blob, GPIO ve eksen kalibrasyonu
uyarlamasıdır.
