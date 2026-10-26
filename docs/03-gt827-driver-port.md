# GT827 (GT811) Driver Port

> Status: **completed** (2026-08-20). The first half of this document is the original port analysis; the outcome is at the end. The Android module is named `gt811_ts-827-fz` (historical vendor name); the Linux driver is called `gt827`.

## Extracted from the real device

The `gt811_ts-827-fz.ko` that runs on the device (module `gt811_ts_827_fz_di`, loaded in `lsmod`) was pulled to `gt811/android-ko/gt811_ts-827-fz.ko` (202499 B, **not stripped, with debug_info**).

Symbols found with `readelf`:
- `goodix_gt811_firmware` (3844 B) → `fw_gt811.bin` (device-specific firmware/checksum table)
- `C.55/59/63` → 3× `cfg_A/B/C.bin` (114 B config blobs), **identical to `data_info0/1` in `gt82x.c`**
- `gpio_int_info` and `goodix_ts_id` are present as well

**Verification:** `cfg_A.bin` = `0f 80 00 0f 01 10 02 11 03 12 ...` is byte-for-byte the same as the `data_info1[]` array of `gt82x.c`. The protocol match is proven.

So when porting `gt82x.c` to the mainline input API, the device-specific 114-byte config blob can be taken directly from `fw_gt811.bin` / `cfg_*.bin`. No guessing or deriving: it is the device's own data.

## Module information
- vermagic: `3.0.8+ preempt mod_unload modversions ARMv7` (Android 4.0.4 kernel)
- Vendor/product ID reported on the input device: `Bus=0018 Vendor=dead Product=beef` (0x18 = I2C, 0xdeadbeef = the standard Goodix placeholder)

## Protocol (verified against `gt82x.c` and the real blob)
- I2C address: 0x5d (`<0x5d>` in the DTS)
- Init: config write with the `0F 80` command + 114 B blob (3 times, different offsets)
- Data: `80 00` → read 10 B; finger bitmask in point_data[2], x/y/width 5 B per finger
- Checksum: sum of bytes[4..] equals the last byte
- Axis correction: `touchscreen-inverted-y` + `touchscreen-swapped-x-y` (in the DTS)
- INT: PH21 (falling edge), RST: PB13

## Porting plan (as originally written)
Reference: `gt811/android-ko`; base: `gt82x.c` (964 lines). Modernisation:
earlysuspend → PM ops, init-input → removed, i2c → regmap, gpio/irq → DT, input_dev → MT (ABS_MT_*), Kconfig/Makefile, DT compatible `goodix,gt811` (later `goodix,gt827`).

The config blob is embedded in the driver (convert with `xxd -i fw_gt811.bin > gt811_fw.h`).

## Outcome

The plan is done and the driver works as `gt827`.

- Sources: `drivers/gt827/gt827.c` and `gt827_cfg.h` (in the separate repository <https://github.com/Mechres/gt827-linux-driver>).
- Kernel copies live under `kernel/linux/drivers/input/touchscreen/`.
- The panel variant is selected automatically from register `0x0ff5`.
- Piranha calibration is roughly raw Y `30..600`.
- `ABS_MT_POSITION_X/Y` and `BTN_TOUCH` events were verified in `evtest`.
- The driver can be loaded at boot through `modules-load.d`.

For new hardware the remaining work is only adapting the config blob, GPIOs and axis calibration.

The `gt811/` directory in this repository holds an early prototype (`gt811.c`) and the original vendor module data; it is kept for reference.
