// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * nct6687_smbus.c - Nuvoton NCT6686/NCT6687 Super I/O Hardware SMBus Master Driver
 *
 * Implements a Linux I2C/SMBus adapter driving the hardware SMBus Master block
 * on Nuvoton NCT6686 / NCT6687 series Super I/O chips via the on-chip Embedded
 * Controller (EC) Space Page 4 mailbox protocol.
 */
#include <linux/module.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/i2c.h>
#include <linux/delay.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/string.h>

#include "nct6687_smbus.h"

/* Super I/O Registers */
#define SIO_REG_PORT              0x2E
#define SIO_DATA_PORT             0x2F
#define SIO_LDN_SEL               0x07
#define SIO_LDN_EC                0x0B
#define SIO_REG_ACTIVATE          0x30
#define SIO_REG_ADDR_HIGH         0x60
#define SIO_REG_ADDR_LOW          0x61
#define SIO_REG_DEVID             0x20

/* Embedded Controller Space (Port 0) */
#define NCT6687_EC_BASE_DEFAULT   0x0A20
#define NCT6687_EC_PORT_LEN       4

#define EC_PAGE_REG_OFFSET        0
#define EC_INDEX_REG_OFFSET       1
#define EC_DATA_REG_OFFSET        2
#define EC_PAGE_SELECT            0xFF

/* EC Space Page 4: SMBus Master Registers */
#define EC_PAGE_SMBUS             4
#define EC_REG_STATUS             0x60
#define EC_REG_BUS_CFG1           0x61
#define EC_REG_BUS_CFG2           0x62
#define EC_REG_PROTOCOL           0x63
#define EC_REG_SLAVE_ADDR         0x65
#define EC_REG_CMD                0x66
#define EC_REG_DATA_IN0           0x70
#define EC_REG_DATA_IN1           0x71
#define EC_REG_DATA_OUT0          0xB0
#define EC_REG_DATA_OUT1          0xB1

#define EC_CMD_START              0xC0
#define EC_CMD_RESET              0x08
#define EC_STATUS_BUSY            0x40
#define EC_STATUS_SUCCESS         0x80

#define EC_PROTO_WRITE_BYTE       0x02
#define EC_PROTO_WRITE_WORD       0x03
#define EC_PROTO_READ_BYTE        0x82
#define EC_PROTO_READ_WORD        0x83

static DEFINE_MUTEX(nct6687_smbus_lock);
static u16 nct6687_ec_base = NCT6687_EC_BASE_DEFAULT;

static inline void nct6687_ec_write(u8 page, u8 index, u8 val)
{
	outb(EC_PAGE_SELECT, nct6687_ec_base + EC_PAGE_REG_OFFSET);
	outb(page, nct6687_ec_base + EC_PAGE_REG_OFFSET);
	outb(index, nct6687_ec_base + EC_INDEX_REG_OFFSET);
	outb(val, nct6687_ec_base + EC_DATA_REG_OFFSET);
	outb(EC_PAGE_SELECT, nct6687_ec_base + EC_PAGE_REG_OFFSET);
}

static inline u8 nct6687_ec_read(u8 page, u8 index)
{
	u8 val;
	outb(EC_PAGE_SELECT, nct6687_ec_base + EC_PAGE_REG_OFFSET);
	outb(page, nct6687_ec_base + EC_PAGE_REG_OFFSET);
	outb(index, nct6687_ec_base + EC_INDEX_REG_OFFSET);
	val = inb(nct6687_ec_base + EC_DATA_REG_OFFSET);
	outb(EC_PAGE_SELECT, nct6687_ec_base + EC_PAGE_REG_OFFSET);
	return val;
}

static int nct6687_smbus_poll(void)
{
	int timeout = 100;
	u8 status;

	while (timeout-- > 0) {
		usleep_range(400, 600);
		status = nct6687_ec_read(EC_PAGE_SMBUS, EC_REG_STATUS);
		if (!(status & EC_STATUS_BUSY)) {
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_STATUS, EC_CMD_RESET);
			return (status & EC_STATUS_SUCCESS) ? 0 : -ENXIO;
		}
	}
	nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_STATUS, EC_CMD_RESET);
	return -ETIMEDOUT;
}

static s32 nct6687_smbus_xfer(struct i2c_adapter *adapter, u16 addr,
			      unsigned short flags, char read_write,
			      u8 command, int size,
			      union i2c_smbus_data *data)
{
	int ret = 0;

	mutex_lock(&nct6687_smbus_lock);

	switch (size) {
	case I2C_SMBUS_QUICK:
		nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_SLAVE_ADDR, (u8)(addr << 1));
		nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_CMD, 0x00);
		nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_PROTOCOL, EC_PROTO_READ_BYTE);
		nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_STATUS, EC_CMD_START);
		ret = nct6687_smbus_poll();
		break;

	case I2C_SMBUS_BYTE:
		if (read_write == I2C_SMBUS_READ) {
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_SLAVE_ADDR, (u8)(addr << 1));
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_CMD, 0x00);
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_PROTOCOL, EC_PROTO_READ_BYTE);
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_STATUS, EC_CMD_START);
			ret = nct6687_smbus_poll();
			if (!ret)
				data->byte = nct6687_ec_read(EC_PAGE_SMBUS, EC_REG_DATA_OUT0);
		} else {
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_SLAVE_ADDR, (u8)(addr << 1));
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_CMD, command);
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_DATA_IN0, 0x00);
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_PROTOCOL, EC_PROTO_WRITE_BYTE);
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_STATUS, EC_CMD_START);
			ret = nct6687_smbus_poll();
		}
		break;

	case I2C_SMBUS_BYTE_DATA:
		nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_SLAVE_ADDR, (u8)(addr << 1));
		nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_CMD, command);
		if (read_write == I2C_SMBUS_READ) {
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_PROTOCOL, EC_PROTO_READ_BYTE);
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_STATUS, EC_CMD_START);
			ret = nct6687_smbus_poll();
			if (!ret)
				data->byte = nct6687_ec_read(EC_PAGE_SMBUS, EC_REG_DATA_OUT0);
		} else {
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_DATA_IN0, data->byte);
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_PROTOCOL, EC_PROTO_WRITE_BYTE);
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_STATUS, EC_CMD_START);
			ret = nct6687_smbus_poll();
		}
		break;

	case I2C_SMBUS_WORD_DATA:
		nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_SLAVE_ADDR, (u8)(addr << 1));
		nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_CMD, command);
		if (read_write == I2C_SMBUS_READ) {
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_PROTOCOL, EC_PROTO_READ_WORD);
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_STATUS, EC_CMD_START);
			ret = nct6687_smbus_poll();
			if (!ret) {
				u8 low = nct6687_ec_read(EC_PAGE_SMBUS, EC_REG_DATA_OUT0);
				u8 high = nct6687_ec_read(EC_PAGE_SMBUS, EC_REG_DATA_OUT1);
				data->word = ((u16)high << 8) | low;
			}
		} else {
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_DATA_IN0, (u8)(data->word & 0xFF));
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_DATA_IN1, (u8)((data->word >> 8) & 0xFF));
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_PROTOCOL, EC_PROTO_WRITE_WORD);
			nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_STATUS, EC_CMD_START);
			ret = nct6687_smbus_poll();
		}
		break;

	default:
		ret = -EOPNOTSUPP;
		break;
	}

	mutex_unlock(&nct6687_smbus_lock);
	return ret;
}

static u32 nct6687_smbus_func(struct i2c_adapter *adapter)
{
	return I2C_FUNC_SMBUS_BYTE_DATA | I2C_FUNC_SMBUS_WORD_DATA |
	       I2C_FUNC_SMBUS_BYTE | I2C_FUNC_SMBUS_QUICK;
}

static const struct i2c_algorithm nct6687_smbus_algorithm = {
	.smbus_xfer    = nct6687_smbus_xfer,
	.functionality = nct6687_smbus_func,
};

int nct6687_smbus_init(struct i2c_adapter **adapter_out)
{
	struct i2c_adapter *adapter;
	u16 base;
	int ret;

	/* Configure NCT6686 / NCT6687 Logical Device 0x0B (EC Space) */
	if (!request_muxed_region(SIO_REG_PORT, 2, "nct6687_smbus"))
		return -EBUSY;

	outb(0x87, SIO_REG_PORT);
	outb(0x87, SIO_REG_PORT);

	outb(SIO_LDN_SEL, SIO_REG_PORT);
	outb(SIO_LDN_EC, SIO_DATA_PORT);

	outb(SIO_REG_ACTIVATE, SIO_REG_PORT);
	outb(0x01, SIO_DATA_PORT);

	outb(SIO_REG_ADDR_HIGH, SIO_REG_PORT);
	base = (u16)inb(SIO_DATA_PORT) << 8;
	outb(SIO_REG_ADDR_LOW, SIO_REG_PORT);
	base |= (u16)inb(SIO_DATA_PORT);

	if (base == 0 || base == 0xFFFF) {
		base = NCT6687_EC_BASE_DEFAULT;
		outb(SIO_REG_ADDR_HIGH, SIO_REG_PORT);
		outb((base >> 8) & 0xFF, SIO_DATA_PORT);
		outb(SIO_REG_ADDR_LOW, SIO_REG_PORT);
		outb(base & 0xFF, SIO_DATA_PORT);
	}

	outb(0xAA, SIO_REG_PORT);
	release_region(SIO_REG_PORT, 2);

	nct6687_ec_base = base;

	/* Reserve EC Port 0 (base to base+3) */
	if (!request_region(nct6687_ec_base, NCT6687_EC_PORT_LEN, "nct6687_smbus")) {
		pr_err("nct6687_smbus: failed to request EC port 0x%04x\n", nct6687_ec_base);
		return -EBUSY;
	}

	/* Initialize EC Page 4 SMBus master clock & config */
	nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_BUS_CFG1, 0x00);
	nct6687_ec_write(EC_PAGE_SMBUS, EC_REG_BUS_CFG2, 0x03);

	adapter = kzalloc(sizeof(*adapter), GFP_KERNEL);
	if (!adapter) {
		release_region(nct6687_ec_base, NCT6687_EC_PORT_LEN);
		return -ENOMEM;
	}

	adapter->owner = THIS_MODULE;
	adapter->class = I2C_CLASS_HWMON;
	adapter->algo  = &nct6687_smbus_algorithm;
	strscpy(adapter->name, "nct6687 SMBus master 0", sizeof(adapter->name));

	/* Register the I2C adapter with Linux kernel */
	ret = i2c_add_adapter(adapter);
	if (ret) {
		pr_err("nct6687_smbus: failed to add I2C adapter (%d)\n", ret);
		kfree(adapter);
		release_region(nct6687_ec_base, NCT6687_EC_PORT_LEN);
		return ret;
	}

	*adapter_out = adapter;
	pr_info("nct6687_smbus: registered '%s' at I/O 0x%04x\n",
		adapter->name, nct6687_ec_base);
	return 0;
}

void nct6687_smbus_exit(struct i2c_adapter *adapter)
{
	if (adapter) {
		i2c_del_adapter(adapter);
		kfree(adapter);
	}

	release_region(nct6687_ec_base, NCT6687_EC_PORT_LEN);
}
