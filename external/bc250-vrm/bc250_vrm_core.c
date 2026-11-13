// bc250_vrm.c - Kernel hwmon driver for AMD BC-250 VRM telemetry
#include <linux/module.h>
#include <linux/init.h>
#include <linux/i2c.h>
#include <linux/hwmon.h>
#include <linux/delay.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/dmi.h>
#include <linux/string.h>

#include "nct6687_smbus.h"

#define PMBUS_PAGE                0x00
#define PMBUS_IOUT_OC_FAULT_LIMIT 0x46
#define PMBUS_OT_FAULT_LIMIT      0x4F
#define PMBUS_OT_WARN_LIMIT       0x51
#define PMBUS_READ_VIN            0x88
#define PMBUS_READ_VOUT           0x8B
#define PMBUS_READ_IOUT           0x8C
#define PMBUS_READ_TEMP1          0x8D
#define PMBUS_REVISION            0x98

#define TEMP_MASK 0x07FF

/* Driver configuration constants */
#define BC250_VRM_PAGE_VIN        0x00
#define BC250_VRM_DELAY_MIN_US    4000
#define BC250_VRM_DELAY_MAX_US    5000
#define BC250_VRM_MAX_IOUT        2500

struct bc250_vrm_data {
	struct i2c_client *client;
	struct mutex lock;
};

static struct i2c_adapter *bc250_smbus;
static struct i2c_client *bc250_vrm_client;

static const char * const bc250_vrm_in_labels[] = {
	"VIN (12V Input)",
	"CPU Voltage",
	"GPU Core Voltage",
};

static const char * const bc250_vrm_curr_labels[] = {
	"CPU Current",
	"GPU Current",
};

static const char * const bc250_vrm_temp_labels[] = {
	"CPU VRM Temp",
	"GPU VRM Temp",
};

static const char * const bc250_vrm_power_labels[] = {
	"CPU Power",
	"GPU Power",
};

static umode_t bc250_vrm_is_visible(const void *data, enum hwmon_sensor_types type,
				    u32 attr, int channel)
{
	switch (type) {
	case hwmon_in:
		if ((attr == hwmon_in_input || attr == hwmon_in_label) &&
		    channel >= 0 && channel < ARRAY_SIZE(bc250_vrm_in_labels))
			return 0444;
		break;
	case hwmon_curr:
		if ((attr == hwmon_curr_input || attr == hwmon_curr_label ||
		     attr == hwmon_curr_crit) &&
		    channel >= 0 && channel < ARRAY_SIZE(bc250_vrm_curr_labels))
			return 0444;
		break;
	case hwmon_temp:
		if ((attr == hwmon_temp_input || attr == hwmon_temp_label ||
		     attr == hwmon_temp_max || attr == hwmon_temp_crit) &&
		    channel >= 0 && channel < ARRAY_SIZE(bc250_vrm_temp_labels))
			return 0444;
		break;
	case hwmon_power:
		if ((attr == hwmon_power_input || attr == hwmon_power_label) &&
		    channel >= 0 && channel < ARRAY_SIZE(bc250_vrm_power_labels))
			return 0444;
		break;
	default:
		break;
	}
	return 0;
}

static s32 bc250_vrm_read_word(struct i2c_client *client, u8 page, u8 reg)
{
	int ret;

	ret = i2c_smbus_write_byte_data(client, PMBUS_PAGE, page);
	if (ret < 0)
		return ret;

	usleep_range(BC250_VRM_DELAY_MIN_US, BC250_VRM_DELAY_MAX_US);
	return i2c_smbus_read_word_data(client, reg);
}

static int bc250_vrm_read(struct device *dev, enum hwmon_sensor_types type,
			  u32 attr, int channel, long *val)
{
	struct bc250_vrm_data *data = dev_get_drvdata(dev);
	struct i2c_client *client = data->client;
	int ret = 0;
	s32 res, vout, iout;
	u8 page;

	mutex_lock(&data->lock);

	switch (type) {
	case hwmon_in:
		if (channel == 0) {
			res = bc250_vrm_read_word(client, BC250_VRM_PAGE_VIN, PMBUS_READ_VIN);
			if (res < 0) { ret = res; goto unlock; }
			*val = (long)res * 10;
		} else {
			page = (u8)(channel - 1);
			res = bc250_vrm_read_word(client, page, PMBUS_READ_VOUT);
			if (res < 0) { ret = res; goto unlock; }
			*val = (long)res;
		}
		break;

	case hwmon_curr:
		if (attr == hwmon_curr_crit) {
			res = bc250_vrm_read_word(client, (u8)channel, PMBUS_IOUT_OC_FAULT_LIMIT);
			if (res < 0) { ret = res; goto unlock; }
			*val = (long)res * 100;
		} else {
			res = bc250_vrm_read_word(client, (u8)channel, PMBUS_READ_IOUT);
			if (res < 0) { ret = res; goto unlock; }
			if ((s16)res > BC250_VRM_MAX_IOUT || (s16)res < -50) { ret = -EIO; goto unlock; }
			*val = (s16)res < 0 ? 0 : (long)(s16)res * 100;
		}
		break;

	case hwmon_temp:
		if (attr == hwmon_temp_max) {
			res = bc250_vrm_read_word(client, (u8)channel, PMBUS_OT_WARN_LIMIT);
		} else if (attr == hwmon_temp_crit) {
			res = bc250_vrm_read_word(client, (u8)channel, PMBUS_OT_FAULT_LIMIT);
		} else {
			res = bc250_vrm_read_word(client, (u8)channel, PMBUS_READ_TEMP1);
		}
		if (res < 0) { ret = res; goto unlock; }
		*val = (long)(res & TEMP_MASK) * 1000;
		break;

	case hwmon_power:
		page = (u8)channel;
		vout = bc250_vrm_read_word(client, page, PMBUS_READ_VOUT);
		if (vout < 0) { ret = vout; goto unlock; }
		iout = bc250_vrm_read_word(client, page, PMBUS_READ_IOUT);
		if (iout < 0) { ret = iout; goto unlock; }
		if ((s16)iout > BC250_VRM_MAX_IOUT || (s16)iout < -50) { ret = -EIO; goto unlock; }
		if ((s16)iout < 0)
			*val = 0;
		else
			*val = (long)vout * (long)(s16)iout * 100;
		break;

	default:
		ret = -EOPNOTSUPP;
		break;
	}

unlock:
	mutex_unlock(&data->lock);
	return ret;
}

static int bc250_vrm_read_string(struct device *dev, enum hwmon_sensor_types type,
				 u32 attr, int channel, const char **str)
{
	switch (type) {
	case hwmon_in:
		if (channel >= 0 && channel < ARRAY_SIZE(bc250_vrm_in_labels)) {
			*str = bc250_vrm_in_labels[channel];
			return 0;
		}
		break;
	case hwmon_curr:
		if (channel >= 0 && channel < ARRAY_SIZE(bc250_vrm_curr_labels)) {
			*str = bc250_vrm_curr_labels[channel];
			return 0;
		}
		break;
	case hwmon_temp:
		if (channel >= 0 && channel < ARRAY_SIZE(bc250_vrm_temp_labels)) {
			*str = bc250_vrm_temp_labels[channel];
			return 0;
		}
		break;
	case hwmon_power:
		if (channel >= 0 && channel < ARRAY_SIZE(bc250_vrm_power_labels)) {
			*str = bc250_vrm_power_labels[channel];
			return 0;
		}
		break;
	default:
		break;
	}
	return -EOPNOTSUPP;
}

static const struct hwmon_channel_info * const bc250_vrm_info[] = {
	HWMON_CHANNEL_INFO(in,
			   HWMON_I_INPUT | HWMON_I_LABEL,  /* in0 */
			   HWMON_I_INPUT | HWMON_I_LABEL,  /* in1 */
			   HWMON_I_INPUT | HWMON_I_LABEL), /* in2 */
	HWMON_CHANNEL_INFO(curr,
			   HWMON_C_INPUT | HWMON_C_LABEL | HWMON_C_CRIT, /* curr0 */
			   HWMON_C_INPUT | HWMON_C_LABEL | HWMON_C_CRIT),/* curr1 */
	HWMON_CHANNEL_INFO(temp,
			   HWMON_T_INPUT | HWMON_T_LABEL | HWMON_T_MAX | HWMON_T_CRIT, /* temp0 */
			   HWMON_T_INPUT | HWMON_T_LABEL | HWMON_T_MAX | HWMON_T_CRIT),/* temp1 */
	HWMON_CHANNEL_INFO(power,
			   HWMON_P_INPUT | HWMON_P_LABEL,  /* power0 */
			   HWMON_P_INPUT | HWMON_P_LABEL), /* power1 */
	NULL
};

static const struct hwmon_ops bc250_vrm_hwmon_ops = {
	.is_visible = bc250_vrm_is_visible,
	.read = bc250_vrm_read,
	.read_string = bc250_vrm_read_string,
};

static const struct hwmon_chip_info bc250_vrm_chip_info = {
	.ops = &bc250_vrm_hwmon_ops,
	.info = bc250_vrm_info,
};

static int bc250_vrm_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct bc250_vrm_data *data;
	struct device *hwmon_dev;

	/*
	 * The client at 0x60 is instantiated on every BC-250, but the VRM is only
	 * reachable with the SMBus hardware modification. Bind only if a PMBus
	 * device answers, so a board without the modification gets no hwmon
	 * device full of unreadable sensors.
	 */
	if (i2c_smbus_read_byte_data(client, PMBUS_REVISION) < 0)
		return -ENODEV;

	data = devm_kzalloc(dev, sizeof(*data), GFP_KERNEL);
	if (!data)
		return -ENOMEM;

	data->client = client;
	mutex_init(&data->lock);

	hwmon_dev = devm_hwmon_device_register_with_info(dev, "bc250_vrm",
							  data,
							  &bc250_vrm_chip_info,
							  NULL);
	return PTR_ERR_OR_ZERO(hwmon_dev);
}

static const struct i2c_device_id bc250_vrm_id[] = {
	{ "bc250_vrm", 0 },
	{ }
};
MODULE_DEVICE_TABLE(i2c, bc250_vrm_id);

static const struct dmi_system_id bc250_vrm_dmi_table[] = {
	{
		.matches = {
			DMI_MATCH(DMI_BOARD_NAME, "AMD BC-250"),
		},
	},
	{ }
};
MODULE_DEVICE_TABLE(dmi, bc250_vrm_dmi_table);

static struct i2c_driver bc250_vrm_driver = {
	.driver = {
		.name = "bc250_vrm",
	},
	.probe = bc250_vrm_probe,
	.id_table = bc250_vrm_id,
};

static int __init bc250_vrm_init(void)
{
	struct i2c_board_info info;
	int ret;

	if (!dmi_check_system(bc250_vrm_dmi_table))
		return -ENODEV;

	/* Initialize NCT6687 hardware SMBus master adapter */
	ret = nct6687_smbus_init(&bc250_smbus);
	if (ret)
		return ret;

	/* Register hwmon client driver */
	ret = i2c_add_driver(&bc250_vrm_driver);
	if (ret) {
		nct6687_smbus_exit(bc250_smbus);
		bc250_smbus = NULL;
		return ret;
	}

	/* Instantiate ISL69247 client at 0x60 on the SMBus adapter */
	memset(&info, 0, sizeof(info));
	strscpy(info.type, "bc250_vrm", I2C_NAME_SIZE);
	info.addr = 0x60;
	bc250_vrm_client = i2c_new_client_device(bc250_smbus, &info);
	if (IS_ERR(bc250_vrm_client)) {
		pr_warn("bc250_vrm: failed to instantiate device at 0x60\n");
		bc250_vrm_client = NULL;
	}

	return 0;
}

static void __exit bc250_vrm_exit(void)
{
	if (bc250_vrm_client) {
		i2c_unregister_device(bc250_vrm_client);
		bc250_vrm_client = NULL;
	}
	i2c_del_driver(&bc250_vrm_driver);

	if (bc250_smbus) {
		nct6687_smbus_exit(bc250_smbus);
		bc250_smbus = NULL;
	}
}

module_init(bc250_vrm_init);
module_exit(bc250_vrm_exit);

MODULE_AUTHOR("Liam McLoughlin <hexxeh@hexxeh.net>");
MODULE_DESCRIPTION("AMD BC-250 VRM hwmon driver");
MODULE_LICENSE("GPL");
MODULE_VERSION("1.1.0");
