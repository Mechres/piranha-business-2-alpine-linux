// SPDX-License-Identifier: GPL-2.0+
/*
 * Goodix GT811 touchscreen driver (mainline port)
 *
 * Piranha Business II Tab / Softwinners "crane" — Allwinner A10
 *
 * Mainline'daki goodix.c GT9xx ailesini destekler; GT811 FARKLI bir protokol
 * kullanır (2-byte register adresi, 114-byte config blob, farklı veri düzeni),
 * bu yüzden ayrı sürücü gerekiyor.
 *
 * Protokol kaynağı: allwinner-zh/linux-3.4-sunxi drivers/input/touchscreen/gt82x.c
 * Config blob: cihazda çalışan /system/vendor/modules/gt811_ts-827-fz.ko içinden
 *              çıkarıldı (bkz. gt811_cfg.h) — tahmin değil, cihazın kendi verisi.
 *
 * Modernizasyon: earlysuspend -> dev_pm_ops, init-input.h kaldırıldı,
 * platform data -> device tree, tek dokunuş -> MT-B (slot) protokolü.
 */

#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/input/mt.h>
#include <linux/input/touchscreen.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>
#include <linux/slab.h>

#include "gt811_cfg.h"

#define GT811_MAX_CONTACTS	5

/* register adresleri (big-endian, 2 byte) */
#define GT811_REG_DATA		0x8000	/* dokunma verisi */
#define GT811_REG_VERSION	0x0f7d	/* chip id / sürüm (gt82x.c: read_chip_value={0x0f,0x7d}) */

/* okuma düzeni: 2 adres + 2 durum + 5*parmak + 1 checksum */
#define GT811_HEAD_LEN		4	/* adres echo(2) + finger(1) + key(1) */
#define GT811_CONTACT_SIZE	5	/* x_h x_l y_h y_l w */

/* finger byte bitleri */
#define GT811_STAT_READY	0x80
#define GT811_STAT_MASK		0xc0

/* GT811 ailesinin bilinen chip id'leri (gt82x.c chip_id_value[]) */
static const u8 gt811_chip_ids[] = { 0x13, 0x27, 0x28 };

struct gt811_ts {
	struct i2c_client *client;
	struct input_dev *input;
	struct touchscreen_properties prop;
	struct gpio_desc *gpiod_rst;
	struct regulator *vcc;
	u16 abs_x_max;
	u16 abs_y_max;
	u8 cfg[GT811_CFG_LEN];
};

/*
 * GT811 2-byte big-endian register adresi kullanır.
 * Okuma: [addr_h addr_l] yaz, ardından veri oku (tek i2c_transfer, iki mesaj).
 */
static int gt811_read_reg(struct gt811_ts *ts, u16 reg, u8 *buf, int len)
{
	u8 addr[2] = { reg >> 8, reg & 0xff };
	struct i2c_msg msgs[2] = {
		{ .addr = ts->client->addr, .flags = 0,
		  .len = sizeof(addr), .buf = addr },
		{ .addr = ts->client->addr, .flags = I2C_M_RD,
		  .len = len, .buf = buf },
	};
	int ret;

	ret = i2c_transfer(ts->client->adapter, msgs, 2);
	if (ret != 2)
		return ret < 0 ? ret : -EIO;
	return 0;
}

/* Yazma: blob'un ilk 2 baytı zaten register adresi (0x0F80) */
static int gt811_write_raw(struct gt811_ts *ts, const u8 *data, int len)
{
	struct i2c_msg msg = {
		.addr = ts->client->addr, .flags = 0,
		.len = len, .buf = (u8 *)data,
	};
	int ret;

	ret = i2c_transfer(ts->client->adapter, &msg, 1);
	if (ret != 1)
		return ret < 0 ? ret : -EIO;
	return 0;
}

/*
 * Okuma sonu komutu. gt82x.c i2c_end_cmd(): sadece 2 bayt
 * (register adresi 0x8000) yazılır — veri baytı yok.
 */
static int gt811_end_cmd(struct gt811_ts *ts)
{
	u8 cmd[2] = { GT811_REG_DATA >> 8, GT811_REG_DATA & 0xff };

	return gt811_write_raw(ts, cmd, sizeof(cmd));
}

static void gt811_reset(struct gt811_ts *ts)
{
	if (!ts->gpiod_rst)
		return;

	/* aktif reset -> bekle -> bırak; gt82x.c 20ms/100ms kullanıyor */
	gpiod_set_value_cansleep(ts->gpiod_rst, 1);
	msleep(20);
	gpiod_set_value_cansleep(ts->gpiod_rst, 0);
	msleep(100);
}

static int gt811_check_chip(struct gt811_ts *ts)
{
	u8 id;
	int ret, i;

	/*
	 * gt82x.c: read_chip_value[3] = {0x0f,0x7d,0} -> i2c_read_bytes(...,3)
	 * yani 2 bayt adres + 1 bayt veri; chip id read_chip_value[2].
	 */
	ret = gt811_read_reg(ts, GT811_REG_VERSION, &id, 1);
	if (ret) {
		dev_err(&ts->client->dev, "chip id okunamadı: %d\n", ret);
		return ret;
	}
	gt811_end_cmd(ts);

	dev_info(&ts->client->dev, "GT811 chip id: 0x%02x\n", id);

	for (i = 0; i < ARRAY_SIZE(gt811_chip_ids); i++)
		if (id == gt811_chip_ids[i])
			return 0;

	/*
	 * Chip id listede yoksa uyar ama devam et: farklı revizyonlar
	 * aynı protokolü konuşuyor ve cihazımızda Android sürücüsü
	 * çalıştığı için protokol doğru.
	 */
	dev_warn(&ts->client->dev,
		 "bilinmeyen chip id 0x%02x, yine de deniyorum\n", id);
	return 0;
}

static int gt811_send_cfg(struct gt811_ts *ts)
{
	int ret;

	/* çözünürlüğü DT'den gelen değerlerle güncelle (blob 800x480 taşıyor) */
	ts->cfg[GT811_CFG_OFF_XMAX]     = ts->abs_x_max >> 8;
	ts->cfg[GT811_CFG_OFF_XMAX + 1] = ts->abs_x_max & 0xff;
	ts->cfg[GT811_CFG_OFF_YMAX]     = ts->abs_y_max >> 8;
	ts->cfg[GT811_CFG_OFF_YMAX + 1] = ts->abs_y_max & 0xff;

	ret = gt811_write_raw(ts, ts->cfg, GT811_CFG_LEN);
	if (ret) {
		dev_err(&ts->client->dev, "config yazılamadı: %d\n", ret);
		return ret;
	}

	/* gt82x.c goodix_init_panel() sırası: end_cmd, 10ms, 100ms */
	gt811_end_cmd(ts);
	msleep(10);
	msleep(100);
	return 0;
}

static void gt811_report(struct gt811_ts *ts, const u8 *coor, u8 finger)
{
	int i, pos = 0;

	for (i = 0; i < GT811_MAX_CONTACTS; i++) {
		bool down = finger & BIT(i);
		int x, y, w;

		input_mt_slot(ts->input, i);

		if (!down) {
			input_mt_report_slot_inactive(ts->input);
			continue;
		}

		x = (coor[pos] << 8) | coor[pos + 1];
		y = (coor[pos + 2] << 8) | coor[pos + 3];
		w = coor[pos + 4];
		pos += GT811_CONTACT_SIZE;

		input_mt_report_slot_state(ts->input, MT_TOOL_FINGER, true);
		/*
		 * touchscreen_report_pos DT'deki swapped-x-y / inverted-x/y
		 * özelliklerini uygular — fex'te revert_y=1, exchange_x_y=1.
		 */
		touchscreen_report_pos(ts->input, &ts->prop, x, y, true);
		input_report_abs(ts->input, ABS_MT_TOUCH_MAJOR, w);
	}

	input_mt_sync_frame(ts->input);
	input_sync(ts->input);
}

static irqreturn_t gt811_irq(int irq, void *dev_id)
{
	struct gt811_ts *ts = dev_id;
	u8 buf[GT811_HEAD_LEN + GT811_CONTACT_SIZE * GT811_MAX_CONTACTS + 1];
	u8 finger, touch_num, checksum = 0;
	const u8 *coor;
	int i, ret, need;

	/* önce baş kısım + ilk parmak: 2 durum + 5 = 7 bayt yeter */
	ret = gt811_read_reg(ts, GT811_REG_DATA, buf, 2 + GT811_CONTACT_SIZE + 1);
	if (ret)
		goto out;

	finger = buf[0];

	if ((finger & GT811_STAT_MASK) != GT811_STAT_READY) {
		/* veri hazır değil — sessizce çık */
		goto out;
	}

	touch_num = hweight8(finger & GENMASK(GT811_MAX_CONTACTS - 1, 0));

	if (touch_num > GT811_MAX_CONTACTS)
		goto out;

	if (touch_num > 1) {
		/* kalan parmakları da oku */
		need = 2 + GT811_CONTACT_SIZE * touch_num + 1;
		ret = gt811_read_reg(ts, GT811_REG_DATA, buf, need);
		if (ret)
			goto out;
		finger = buf[0];
	}

	coor = &buf[2];

	if (touch_num) {
		for (i = 0; i < GT811_CONTACT_SIZE * touch_num; i++)
			checksum += coor[i];

		if (checksum != coor[GT811_CONTACT_SIZE * touch_num]) {
			dev_dbg(&ts->client->dev, "checksum hatası\n");
			goto out;
		}
	}

	gt811_report(ts, coor, finger);

out:
	gt811_end_cmd(ts);
	return IRQ_HANDLED;
}

static int gt811_input_init(struct gt811_ts *ts)
{
	struct input_dev *input;
	int ret;

	input = devm_input_allocate_device(&ts->client->dev);
	if (!input)
		return -ENOMEM;

	ts->input = input;
	input->name = "Goodix GT811 Touchscreen";
	input->phys = "input/ts";
	input->id.bustype = BUS_I2C;
	input->id.vendor  = 0x0416;	/* Goodix */
	input->id.product = 0x0811;
	input->id.version = 0x0100;

	input_set_abs_params(input, ABS_MT_POSITION_X, 0, ts->abs_x_max, 0, 0);
	input_set_abs_params(input, ABS_MT_POSITION_Y, 0, ts->abs_y_max, 0, 0);
	input_set_abs_params(input, ABS_MT_TOUCH_MAJOR, 0, 255, 0, 0);

	/* DT'den swapped-x-y / inverted-y oku (fex: exchange_x_y=1, revert_y=1) */
	touchscreen_parse_properties(input, true, &ts->prop);

	ret = input_mt_init_slots(input, GT811_MAX_CONTACTS,
				  INPUT_MT_DIRECT | INPUT_MT_DROP_UNUSED);
	if (ret)
		return ret;

	return input_register_device(input);
}

static int gt811_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct gt811_ts *ts;
	int ret;

	if (!i2c_check_functionality(client->adapter, I2C_FUNC_I2C))
		return -ENXIO;

	ts = devm_kzalloc(dev, sizeof(*ts), GFP_KERNEL);
	if (!ts)
		return -ENOMEM;

	ts->client = client;
	i2c_set_clientdata(client, ts);
	memcpy(ts->cfg, gt811_cfg_800x480, GT811_CFG_LEN);

	/* varsayılan: blob'daki değerler; DT ile geçersiz kılınabilir */
	ts->abs_x_max = 800;
	ts->abs_y_max = 480;
	device_property_read_u32(dev, "touchscreen-size-x", (u32 *)&ts->abs_x_max);
	device_property_read_u32(dev, "touchscreen-size-y", (u32 *)&ts->abs_y_max);

	ts->vcc = devm_regulator_get_optional(dev, "vcc");
	if (IS_ERR(ts->vcc)) {
		if (PTR_ERR(ts->vcc) != -ENODEV)
			return dev_err_probe(dev, PTR_ERR(ts->vcc),
					     "vcc alınamadı\n");
		ts->vcc = NULL;
	}
	if (ts->vcc) {
		ret = regulator_enable(ts->vcc);
		if (ret)
			return dev_err_probe(dev, ret, "vcc açılamadı\n");
	}

	ts->gpiod_rst = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(ts->gpiod_rst))
		return dev_err_probe(dev, PTR_ERR(ts->gpiod_rst),
				     "reset gpio alınamadı\n");

	gt811_reset(ts);

	ret = gt811_check_chip(ts);
	if (ret)
		return dev_err_probe(dev, ret, "GT811 bulunamadı\n");

	ret = gt811_send_cfg(ts);
	if (ret)
		return ret;

	ret = gt811_input_init(ts);
	if (ret)
		return dev_err_probe(dev, ret, "input kaydı başarısız\n");

	ret = devm_request_threaded_irq(dev, client->irq, NULL, gt811_irq,
					IRQF_ONESHOT, client->name, ts);
	if (ret)
		return dev_err_probe(dev, ret, "irq %d alınamadı\n", client->irq);

	dev_info(dev, "GT811 hazır: %ux%u, irq %d\n",
		 ts->abs_x_max, ts->abs_y_max, client->irq);
	return 0;
}

static void gt811_remove(struct i2c_client *client)
{
	struct gt811_ts *ts = i2c_get_clientdata(client);

	if (ts->vcc)
		regulator_disable(ts->vcc);
}

static int gt811_suspend(struct device *dev)
{
	struct gt811_ts *ts = i2c_get_clientdata(to_i2c_client(dev));

	disable_irq(ts->client->irq);
	return 0;
}

static int gt811_resume(struct device *dev)
{
	struct gt811_ts *ts = i2c_get_clientdata(to_i2c_client(dev));

	gt811_reset(ts);
	gt811_send_cfg(ts);
	enable_irq(ts->client->irq);
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(gt811_pm_ops, gt811_suspend, gt811_resume);

static const struct i2c_device_id gt811_id[] = {
	{ "gt811", 0 },
	{ }
};
MODULE_DEVICE_TABLE(i2c, gt811_id);

static const struct of_device_id gt811_of_match[] = {
	{ .compatible = "goodix,gt811" },
	{ }
};
MODULE_DEVICE_TABLE(of, gt811_of_match);

static struct i2c_driver gt811_driver = {
	.probe    = gt811_probe,
	.remove   = gt811_remove,
	.id_table = gt811_id,
	.driver = {
		.name = "gt811",
		.of_match_table = gt811_of_match,
		.pm = pm_sleep_ptr(&gt811_pm_ops),
	},
};
module_i2c_driver(gt811_driver);

MODULE_DESCRIPTION("Goodix GT811 touchscreen driver");
MODULE_LICENSE("GPL");
