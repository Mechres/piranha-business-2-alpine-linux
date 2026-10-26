# Hardware Findings (verified from script.bin and Android sysfs)

> Historical note: the early sections of this file use the name GT811 from the recon phase. The working Linux driver is called `gt827`; the Android vendor module was named `gt811_ts-827-fz`.

Sources: `fex/tablet.fex` (script.bin v1.2, 75 sections) and `docs/recon.log` (live Android sysfs dump).

## Corrections to the initial assumptions

| Topic | Initial assumption | Verified fact | Evidence |
|---|---|---|---|
| Touch controller | Goodix **GT827** | **Goodix GT827** @ i2c-2, 0x5D | Android vendor module `gt811_ts-827-fz`; Linux probe ID `0x27`, input device `Goodix GT827 Touchscreen` |
| Display | not specified | **800×480** parallel RGB (24-bit, PD00–PD27) | fex `lcd_x=800 lcd_y=480`, fb0 `U:800x480p-59` |
| RAM | MT.Mosel | **1 GB DDR3**, up to 1.4 GHz CPU configuration | hardware/runtime report; the extracted FEX contains an older `dram_size=512` value |

The GT811 family is **not** covered by mainline `goodix.c`, which supports the GT9xx series. That was the biggest technical risk of the project (see `03-gt827-driver-port.md`).

## Board identity
- `ro.product.board` = **crane**, `ro.product.device` = **crane-a702jhorange**
- script.bin `machine` = `A10-EVB-V1.1`, `Hardware: sun4i`
- Android 2.3/4.0-era kernel (sun4i-3.0/3.4 fork), `ro.board.platform=exDroid`

## Panel — `[lcd0_para]` → DTS timing
```
lcd_x=800  lcd_y=480          → hactive=800  vactive=480
lcd_dclk_freq=33 (MHz)        → clock-frequency = 33000000
lcd_ht=1055  lcd_hbp=46       → hsync+hbp=46, htotal=1055+1=1056  ⇒ hfront = 1056-800-46 = 210
lcd_vt=1050  lcd_vbp=23       → vsync+vbp=23, vtotal=1050/2=525    ⇒ vfront = 525-480-23  = 22
lcd_hv_hspw=0  lcd_hv_vspw=0  → hsync-len=1, vsync-len=1 (a fex value of 0 means "1 clock")
lcd_if=0, lcd_hv_if=0         → parallel RGB (HV sync), 24-bit
```
DTS `panel-timing` (derived, used for the first attempt):
```
clock-frequency = <33000000>;
hactive = <800>; hfront-porch = <210>; hback-porch = <45>; hsync-len = <1>;
vactive = <480>; vfront-porch = <22>; vback-porch = <22>;  vsync-len = <1>;
```
> Note: in the fex, hbp = hsync + hback, so hback = 46 − 1 = 45 and vback = 23 − 1 = 22.

Panel GPIOs:
| Function | GPIO | fex |
|---|---|---|
| Backlight enable | **PH7** (active high) | `lcd_bl_en = port:PH07<1><0><default><1>` |
| Panel power | **PH8** (active high) | `lcd_power = port:PH08<1><0><default><1>` |
| Backlight PWM | **PB2** (PWM0, 1 kHz, pol=1) | `lcd_pwm = port:PB02<2>` |
| Data | PD0–PD23, CLK=PD24, DE=PD25, HSYNC=PD26, VSYNC=PD27 | |

## DRAM — for the U-Boot defconfig
```
dram_clk=432   dram_type=3 (DDR3)   dram_rank_num=1
dram_chip_density=2048   dram_io_width=16   dram_bus_width=32
dram_cas=6   dram_zq=0x7b   dram_odt_en=0   dram_size=512
dram_tpr0=0x30926692  dram_tpr1=0x1090  dram_tpr2=0x1a0c8
dram_emr1=0x4  dram_emr2=0x8  dram_emr3=0x0
```
→ `CONFIG_DRAM_CLK=432`, `CONFIG_DRAM_ZQ=123` (0x7b), `CONFIG_DRAM_EMR1=4`

## I2C map (live sysfs, definitive)
| Bus | Address | Chip | Mainline driver |
|---|---|---|---|
| i2c-0 (PB0/PB1) | 0x34 | **AXP209** PMIC | ✅ `axp20x` |
| i2c-1 (PB18/PB19) | 0x18 / 0x1C | dmt / dmard06 accelerometer | ✅ `dmard06` |
| i2c-1 | 0x4C | mma7660 accelerometer | ✅ `mma7660` |
| i2c-1 | 0x21 / 0x3C | gc0308 / gc0309 camera | ⚠️ partial |
| i2c-2 (PB20/PB21) | **0x5D** | **Goodix GT827 touchscreen** | ✅ out-of-tree `gt827` driver |

Touch interrupt/reset (fex `ctp_*_b`): INT = **PH21**, RESET/wakeup = **PB13**.
Axis correction: `revert_y=1`, `exchange_x_y=1` → `touchscreen-swapped-x-y` + `touchscreen-inverted-y` in the DTS.

## SD card
- **mmc0** = external microSD: PF0–PF5, card detect **PH1** → the system boots from here ✅
- mmc3 = internal (PI4–PI9, detect PH11) — could be SDIO Wi-Fi, but the RTL8188CUS is on USB, so it is probably unused.

## AXP209 regulators (fex `[target]` + `[pmu_para]`)
```
dcdc2 = 1400 mV (VDD-CPU)   dcdc3 = 1250 mV (VDD-INT/DLL)
ldo2  = 3000 mV (AVCC)      ldo3 = 2800 mV   ldo4 = 2800 mV
boot_clock = 1008 MHz       pll4/pll6 = 960 MHz
Battery: 4500 mAh, charge 4.2 V, shutdown 3.3 V, power-on 2.9 V
AC detect GPIO: PH2
```

## Storage notes
- No `/proc/mtd`: Android exposes the NAND as block devices (`nanda`…`nandj`, major 93) through Allwinner's proprietary FTL.
- No raw `/dev/block/nand`, so a raw NAND backup cannot be taken over ADB.
- **Backed up:** `backup/nanda.img` (16 MB FAT16 boot partition, including script.bin, boot.axf and sprite). This is the most valuable part.
- Conclusion: **never write to the NAND.** The Hynix H27UCG8 is MLC and mainline MTD support is unreliable; the system runs from the SD card permanently.

## Risk ranking (realistic)
1. 🟢 **GT827 touchscreen**: the out-of-tree driver works; other panel variants may need a different config blob and calibration.
2. 🟡 **Panel timing**: derived but not tried at the time. If wrong the picture is shifted or blank; fix by adjusting hfront/vfront.
3. 🟢 DRAM / U-Boot: parameters are clear, low risk.
4. 🟢 Wi-Fi (rtl8192cu), AXP209, SD, Mali/Lima, ALSA sun4i-codec: verified.

## Expectations
800×480 with an A10 (single Cortex-A8 @ 1.4 GHz) and 1 GB RAM is a light desktop / **kiosk-class** device. Xfce is still heavy. Target: X11 + Openbox/JWM, or Wayland + labwc, with NetSurf/Dillo as browsers. Chromium and Firefox are not usable with this RAM.

## Verified state after implementation (2026-08-20)

- Alpine 3.20 armv7 + OpenRC boots from the microSD card.
- The `rtl8192cu` Wi-Fi module, `g_ether` USB Ethernet and SSH work.
- The GT827 driver produces real multitouch events in `evtest`.
- The `sun4i-codec` ALSA card appears as `card 0` and `speaker-test` streams PCM.
- The Android FEX entry `audio_pa_ctrl = port:PA10` was added to the Linux DTS as `allwinner,pa-gpios = <&pio 0 10 GPIO_ACTIVE_HIGH>`; the internal speaker worked after that.
- The kernel log registers the Lima Mali-400 and the Cedrus video decoder.
- The Cedrus kernel device is ready, but the current Alpine FFmpeg/mpv packages do not use the hardware decoder through the stateless V4L2 Request API.
