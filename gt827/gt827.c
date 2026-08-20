// SPDX-License-Identifier: GPL-2.0-only
/*
 * gt827.c — Goodix GT827 touchscreen driver for mainline Linux
 *
 * Piranha Business II Tab (Allwinner A10 / sun4i), i2c-2 @ 0x5d.
 * INT = PH21 (falling edge), RST = PB13.
 *
 * Ported from the vendor GT82x reference (gt82x.c, GPLv2) to the modern
 * mainline input/Touch-API. The wire protocol (0x0F80 config write + 114B
 * blob, 0x8000 read, per-finger 5-byte coordinate frame, checksum) and the
 * device init blob are taken verbatim from the real working Android module
 * (gt811_ts-827-fz.ko) pulled off this exact tablet — see gt827_cfg_a.h.
 *
 * NOT a GT9xx chip: the mainline goodix.c driver does NOT support it, so an
 * out-of-tree module is required.
 */

#include <linux/module.h>
#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/input/mt.h>
#include <linux/interrupt.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/of.h>
#include <linux/property.h>
#include <linux/workqueue.h>
#include <linux/regulator/consumer.h>
#include <linux/slab.h>

#include "gt827_cfg_a.h"

#define GT827_NAME		"gt827"
#define GT827_MAX_FINGERS	5

/* wire addresses */
#define GT827_REG_CMD_H		0x0f
#define GT827_REG_CMD_L		0x80	/* "write config" cmd base */
#define GT827_READ_TOUCH_H	0x0f
#define GT827_READ_TOUCH_L	0x40

/* chip id read: 0x0f 0x7d -> byte[2] is the id (0x13/0x27/0x28 family) */
static const u8 gt827_read_id[] = {0x0f, 0x7d};

struct gt827_data {
	struct i2c_client	*client;
	struct input_dev	*input;
	struct gpio_desc	*rst_gpio;
	struct regulator	*vcc;
	struct work_struct	work;
	struct workqueue_struct	*wq;
	u32			max_x;
	u32			max_y;
	bool			swap_xy;
	bool			invert_x;
	bool			invert_y;
};

/* ------------------------------------------------------------------ */
/* low-level i2c helpers                                              */
/* ------------------------------------------------------------------ */

/* write buf[0..1] = address, then buf[2..len-1] = data (2-message xfer) */
static int gt827_i2c_write(struct i2c_client *client, const u8 *data, u16 len)
{
	struct i2c_msg msg = {
		.addr	= client->addr,
		.flags	= 0,
		.len	= len,
		.buf	= (u8 *)data,
	};
	return i2c_transfer(client->adapter, &msg, 1);
}

/* read len bytes starting at 16-bit address (buf[0]=addrH, buf[1]=addrL) */
static int gt827_i2c_read(struct i2c_client *client, u8 *buf, u16 len)
{
	struct i2c_msg msgs[2] = {
		{
			.addr	= client->addr,
			.flags	= 0,
			.len	= 2,
			.buf	= buf,
		},
		{
			.addr	= client->addr,
			.flags	= I2C_M_RD,
			.len	= len - 2,
			.buf	= buf + 2,
		},
	};
	return i2c_transfer(client->adapter, msgs, 2);
}

static int gt827_end_cmd(struct gt827_data *ts)
{
	u8 end[2] = {0x80, 0x00};
	return gt827_i2c_write(ts->client, end, 2);
}

/* ------------------------------------------------------------------ */
/* panel init: write the real device config blob                     */
/* ------------------------------------------------------------------ */

static int gt827_init_panel(struct gt827_data *ts)
{
	int ret;
	u8 cfg[116];
	u8 rd[114];

	/* 0x0F 0x80 + 114-byte config blob (real device data) */
	cfg[0] = GT827_REG_CMD_H;
	cfg[1] = GT827_REG_CMD_L;
	memcpy(&cfg[2], gt811_android_ko_cfg_A_bin,
	       gt811_android_ko_cfg_A_bin_len);

	ret = gt827_i2c_write(ts->client, cfg,
			      2 + gt811_android_ko_cfg_A_bin_len);
	if (ret < 0) {
		dev_err(&ts->client->dev, "config write failed: %d\n", ret);
		return ret;
	}
	gt827_end_cmd(ts);
	msleep(10);

	/* read back to confirm the chip accepted it */
	rd[0] = GT827_REG_CMD_H;
	rd[1] = GT827_REG_CMD_L;
	ret = gt827_i2c_read(ts->client, rd, 114);
	if (ret < 0)
		dev_warn(&ts->client->dev, "config readback failed: %d\n", ret);

	msleep(10);
	return 0;
}

static int gt827_read_chip_id(struct gt827_data *ts)
{
	u8 buf[5];
	int ret;

	buf[0] = gt827_read_id[0];
	buf[1] = gt827_read_id[1];
	ret = gt827_i2c_read(ts->client, buf, 5);
	gt827_end_cmd(ts);
	if (ret < 0) {
		dev_err(&ts->client->dev, "chip id read failed: %d\n", ret);
		return ret;
	}
	dev_info(&ts->client->dev, "GT827 PID:0x%02x VID:%02x%02x\n",
		 buf[2], buf[3], buf[4]);
	return 0;
}

/* ------------------------------------------------------------------ */
/* coordinate reporting                                               */
/* ------------------------------------------------------------------ */

static void gt827_touch_down(struct gt827_data *ts, s32 id, s32 x, s32 y, s32 w)
{
	if (ts->swap_xy)
		swap(x, y);
	if (ts->invert_x)
		x = ts->max_x - x;
	if (ts->invert_y)
		y = ts->max_y - y;

	input_mt_slot(ts->input, id);
	input_mt_report_slot_state(ts->input, MT_TOOL_FINGER, true);
	input_report_abs(ts->input, ABS_MT_POSITION_X, x);
	input_report_abs(ts->input, ABS_MT_POSITION_Y, y);
	input_report_abs(ts->input, ABS_MT_TOUCH_MAJOR, w);
	input_report_abs(ts->input, ABS_MT_WIDTH_MAJOR, w);
}

static void gt827_touch_up(struct gt827_data *ts, s32 id)
{
	input_mt_slot(ts->input, id);
	input_mt_report_slot_state(ts->input, MT_TOOL_FINGER, false);
}

static void gt827_work_func(struct work_struct *work)
{
	struct gt827_data *ts = container_of(work, struct gt827_data, work);
	u8 point_data[2 + 2 + 5 * GT827_MAX_FINGERS + 1];
	u8 coor_data[5 * GT827_MAX_FINGERS];
	u8 finger, touch_num, check_sum, idx;
	s32 input_x, input_y, input_w, pos, ret;
	u8 *b;

	ret = gt827_i2c_read(ts->client, point_data, 10);
	finger = point_data[2];
	touch_num = (finger & 0x01) + !!(finger & 0x02) + !!(finger & 0x04) +
		    !!(finger & 0x08) + !!(finger & 0x10);

	if (touch_num > 1) {
		u8 buf[25];
		buf[0] = GT827_READ_TOUCH_H;
		buf[1] = GT827_READ_TOUCH_L + 8;
		ret = gt827_i2c_read(ts->client, buf,
				     5 * (touch_num - 1) + 2);
		memcpy(&point_data[10], &buf[2], 5 * (touch_num - 1));
	}
	gt827_end_cmd(ts);

	if (ret <= 0) {
		dev_err(&ts->client->dev, "i2c read error\n");
		return;
	}
	if ((finger & 0xC0) != 0x80)	/* data not ready */
		return;

	/* touch-key combo 0x0f means "reload config" on this chip */
	if ((point_data[3] & 0x0f) == 0x0f) {
		gt827_init_panel(ts);
		return;
	}

	b = &point_data[4];
	check_sum = 0;
	for (idx = 0; idx < 5 * touch_num; idx++)
		check_sum += b[idx];
	if (check_sum != b[5 * touch_num]) {
		dev_err(&ts->client->dev, "checksum error\n");
		return;
	}

	pos = 0;
	for (idx = 0; idx < GT827_MAX_FINGERS; idx++) {
		if (!(finger & (0x01 << idx)))
			continue;
		input_x  = b[pos] << 8;
		input_x |= b[pos + 1];
		input_y  = b[pos + 2] << 8;
		input_y |= b[pos + 3];
		input_w  = b[pos + 4];
		pos += 5;
		gt827_touch_down(ts, idx, input_x, input_y, input_w);
	}

	/* release slots that are no longer reported */
	for (idx = 0; idx < GT827_MAX_FINGERS; idx++)
		if (!(finger & (0x01 << idx)))
			gt827_touch_up(ts, idx);

	input_mt_report_pointer_emulation(ts->input, true);
	input_sync(ts->input);
}

static irqreturn_t gt827_irq_handler(int irq, void *dev_id)
{
	struct gt827_data *ts = dev_id;
	queue_work(ts->wq, &ts->work);
	return IRQ_HANDLED;
}

/* ------------------------------------------------------------------ */
/* reset / power                                                      */
/* ------------------------------------------------------------------ */

static void gt827_reset(struct gt827_data *ts)
{
	if (!ts->rst_gpio)
		return;
	/* RST is active-high on this board: pulse low->high to wake */
	gpiod_set_value_cansleep(ts->rst_gpio, 0);
	msleep(30);
	gpiod_set_value_cansleep(ts->rst_gpio, 1);
	msleep(100);
}

/* ------------------------------------------------------------------ */
/* probe / remove                                                     */
/* ------------------------------------------------------------------ */

static int gt827_probe(struct i2c_client *client)
{
	struct gt827_data *ts;
	struct device *dev = &client->dev;
	int ret, i;
	u32 val;

	if (!i2c_check_functionality(client->adapter, I2C_FUNC_I2C)) {
		dev_err(dev, "I2C_FUNC_I2C not supported\n");
		return -ENODEV;
	}

	ts = devm_kzalloc(dev, sizeof(*ts), GFP_KERNEL);
	if (!ts)
		return -ENOMEM;

	ts->client = client;
	ts->max_x = 800;
	ts->max_y = 480;

	/* optional regulator (vcc-supply in DT) */
	ts->vcc = devm_regulator_get_optional(dev, "vcc");
	if (!IS_ERR(ts->vcc)) {
		ret = regulator_enable(ts->vcc);
		if (ret)
			dev_warn(dev, "vcc enable failed: %d\n", ret);
		msleep(20);
	}

	ts->rst_gpio = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(ts->rst_gpio))
		return dev_err_probe(dev, PTR_ERR(ts->rst_gpio),
				     "failed to get reset gpio\n");

	/* orientation from DT */
	if (!device_property_read_u32(dev, "touchscreen-size-x", &val))
		ts->max_x = val;
	if (!device_property_read_u32(dev, "touchscreen-size-y", &val))
		ts->max_y = val;
	ts->swap_xy   = device_property_read_bool(dev, "touchscreen-swapped-x-y");
	ts->invert_x  = device_property_read_bool(dev, "touchscreen-inverted-x");
	ts->invert_y  = device_property_read_bool(dev, "touchscreen-inverted-y");

	gt827_reset(ts);

	ret = gt827_read_chip_id(ts);
	if (ret < 0)
		return ret;

	ts->input = devm_input_allocate_device(dev);
	if (!ts->input)
		return -ENOMEM;

	ts->input->name = "GT827 Touchscreen";
	ts->input->id.bustype = BUS_I2C;
	ts->input->id.vendor = 0xDEAD;
	ts->input->id.product = 0xBEEF;

	input_set_abs_params(ts->input, ABS_MT_POSITION_X, 0, ts->max_x, 0, 0);
	input_set_abs_params(ts->input, ABS_MT_POSITION_Y, 0, ts->max_y, 0, 0);
	input_set_abs_params(ts->input, ABS_MT_TOUCH_MAJOR, 0, 255, 0, 0);
	input_set_abs_params(ts->input, ABS_MT_WIDTH_MAJOR, 0, 255, 0, 0);
	input_set_abs_params(ts->input, ABS_MT_TRACKING_ID, 0,
			     GT827_MAX_FINGERS - 1, 0, 0);
	input_mt_init_slots(ts->input, GT827_MAX_FINGERS,
			    INPUT_MT_DIRECT | INPUT_MT_DROP_UNUSED);

	ret = input_register_device(ts->input);
	if (ret)
		return dev_err_probe(dev, ret, "input register failed\n");

	ts->wq = alloc_ordered_workqueue(GT827_NAME, 0);
	if (!ts->wq)
		return -ENOMEM;
	INIT_WORK(&ts->work, gt827_work_func);

	i2c_set_clientdata(client, ts);

	ret = gt827_init_panel(ts);
	if (ret < 0)
		goto err_wq;

	ret = devm_request_threaded_irq(dev, client->irq, NULL,
					gt827_irq_handler,
					IRQF_ONESHOT | IRQF_TRIGGER_FALLING,
					GT827_NAME, ts);
	if (ret)
		goto err_wq;

	dev_info(dev, "GT827 probed (max %ux%u)\n", ts->max_x, ts->max_y);
	return 0;

err_wq:
	destroy_workqueue(ts->wq);
	return ret;
}

static void gt827_remove(struct i2c_client *client)
{
	struct gt827_data *ts = i2c_get_clientdata(client);

	if (!ts)
		return;
	cancel_work_sync(&ts->work);
	destroy_workqueue(ts->wq);
	if (!IS_ERR_OR_NULL(ts->vcc))
		regulator_disable(ts->vcc);
}

#ifdef CONFIG_PM_SLEEP
static int gt827_suspend(struct device *dev)
{
	struct gt827_data *ts = i2c_get_clientdata(to_i2c_client(dev));
	u8 buf[3] = {0x0f, 0xf2, 0xc0}; /* suspend cmd */
	if (ts)
		gt827_i2c_write(ts->client, buf, 3);
	return 0;
}

static int gt827_resume(struct device *dev)
{
	struct gt827_data *ts = i2c_get_clientdata(to_i2c_client(dev));
	if (!ts)
		return 0;
	gt827_reset(ts);
	gt827_init_panel(ts);
	return 0;
}
#endif

static SIMPLE_DEV_PM_OPS(gt827_pm_ops, gt827_suspend, gt827_resume);

static const struct i2c_device_id gt827_id[] = {
	{ "gt827", 0 },
	{ }
};
MODULE_DEVICE_TABLE(i2c, gt827_id);

static const struct of_device_id gt827_of_match[] = {
	{ .compatible = "goodix,gt827" },
	{ }
};
MODULE_DEVICE_TABLE(of, gt827_of_match);

static struct i2c_driver gt827_driver = {
	.driver = {
		.name		= GT827_NAME,
		.of_match_table	= gt827_of_match,
		.pm		= &gt827_pm_ops,
	},
	.probe		= gt827_probe,
	.remove		= gt827_remove,
	.id_table	= gt827_id,
};
module_i2c_driver(gt827_driver);

MODULE_DESCRIPTION("Goodix GT827 touchscreen driver");
MODULE_AUTHOR("Mechres / ported from vendor gt82x.c");
MODULE_LICENSE("GPL v2");
