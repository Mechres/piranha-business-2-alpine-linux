# Prior Research: Who Tried Before Us and What We Learned

## Key finding: the Topwise A721 is nearly our tablet

`sun4i-a10-topwise-a721.dts` exists in mainline (Pascal Roeleven, 2021) and overlaps strikingly with this board. Comparison with the values derived from the fex:

| Item | Our fex (crane) | Topwise A721 DTS | Match |
|---|---|---|---|
| Panel | 800×480, 33 MHz, hbp46/vbp23, hfront 210/vfront 22 | `starry,kr070pe2t` = 33 MHz, hfront **209**, hback **45**, vfront **22**, vback **22** | ✅ nearly identical |
| Backlight enable | PH7 | `<&pio 7 7>` PH7 | ✅ |
| LCD power | PH8 | `<&pio 7 8>` PH8 | ✅ |
| PWM | PB2 (pol=1) | `pwm 0 ... PWM_POLARITY_INVERTED` (pwm0_pin = PB2) | ✅ |
| AXP209 | i2c0 @0x34 | `pmic@34` on `&i2c0` | ✅ |
| mma7660 | i2c1 @0x4C | `accelerometer@4c` on `&i2c1` | ✅ |
| SD card detect | PH1 | `cd-gpios = <&pio 7 1 ACTIVE_LOW>` | ✅ |
| dcdc2/dcdc3/ldo2 | 1400/1250/3000 mV | 1400/1250/3000 mV | ✅ |
| USB OTG ID/VBUS detect | PH4/PH5 (dtsi) | PH4/PH5 | ✅ |
| **Touchscreen** | **GT827** @ i2c2 **0x5D** (Android vendor name GT811) | `edt,edt-ft5406` @ **0x38** | ❌ **the only difference** |

Conclusion: take the A721 DTS as the base and change **only the touchscreen node**. No separate panel work is needed; `starry,kr070pe2t` works directly.

> Note: the fex contains both `ctp_name = "ft5x_ts" @0x38` (primary) and `ctp_name_b = "gt811_ts" @0x5D` (secondary), because the Allwinner reference design carries two touchscreen options. Live sysfs proves that the controller actually fitted is the Goodix one (`2-005d`, input event2). The A721 has an FT5406 soldered; this tablet has the Goodix. Same board, different touchscreen stock.

## Earlier attempt: `Softwinners_crane` (Shivam Gupta, 2025)

Armbian forum thread #52328 and Unix SE #796123. **The same `crane` board.** Results:

### Proven to work ✅
- U-Boot boots from SD.
- **Linux really boots**: the silence after "Starting kernel..." was caused by the missing display node, not by a crash (after soldering a UART a login prompt appeared).
- **HDMI works** (on an archived Cubieboard image).
- SSH and the serial console work.

### Problems encountered and their causes ⚠️
| Problem | Root cause / fix |
|---|---|
| Nothing after "Starting kernel..." | No display node → **flying blind without UART or HDMI**. Critical in our case. |
| `BUG: Bad page state`, kernel panic, instability | **DRAM clock too high.** Their fex said 384, they had built with 432. Our fex says `dram_clk=432`, which is the right value for us, but **it is the first thing to lower** if instability shows up. |
| USB keyboard/mouse not working | **USB OTG role.** `dr_mode = "otg"` relies on ID-pin detection, which does not work. Fix: force `dr_mode = "host"`. |
| 1 GB RAM (A088 board) | The `dram_size=512` value in the FEX does not match the real RAM; the Piranha hardware was verified to have 1 GB. |

### Lessons that became actions for us
1. **Set `dr_mode = "host"`** so a USB keyboard/mouse works on the first boot (no UART, so input is essential).
2. **Start DRAM at 432**, and step down 408 → 384 if unstable (our fex says 432, their board needed 384; we trust our value but keep plan B ready).
3. **Enable the HDMI nodes** so HDMI is a fallback output if the panel fails. With no UART this is **our only diagnostic channel**.
4. Get display output early: `CONFIG_FRAMEBUFFER_CONSOLE` + `LOGO`, and keep boot logs on the SD card, so the card can be read on a PC for diagnosis.
5. Prefer a **normal Class 10 / A1 SD card, not A2** (A2 cards are problematic with these old MMC controllers).

## GT811 status (leg C)
- Mainline `goodix.c` supports only GT9xx (GT911/928/9271...). There is no GT811 support and no DT binding.
- The GT811 uses a different protocol from the GT9xx (different register layout, different init).
- Result: after studying the sunxi-3.4-era vendor driver, the out-of-tree `gt827` module was written and runs on Alpine.

## Current result

This note is the historical port plan. The GT827 driver, Wi-Fi, ALSA audio, the PA10 speaker amplifier, the Lima GPU and the Cedrus kernel driver are all verified now.

## Sources
- linux-sunxi crane page: https://linux-sunxi.org/Softwinners_crane
- crane fex (PR): https://github.com/linux-sunxi/sunxi-boards/pull/72/files
- Armbian thread: https://forum.armbian.com/topic/52328-
- A721 DTS patch: https://lkml.iu.edu/hypermail/linux/kernel/2102.2/00521.html
