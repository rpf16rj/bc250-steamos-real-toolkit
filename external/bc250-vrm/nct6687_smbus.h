/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * nct6687_smbus.h - Nuvoton NCT6686/NCT6687 Super I/O Hardware SMBus Master Driver
 */
#ifndef _NCT6687_SMBUS_H_
#define _NCT6687_SMBUS_H_

#include <linux/i2c.h>

/**
 * nct6687_smbus_init - Initialize NCT6687 SIO and register the SMBus adapter
 * @adapter_out: Output pointer to receive the registered struct i2c_adapter pointer
 *
 * Returns 0 on success, or a negative error code on failure.
 */
int nct6687_smbus_init(struct i2c_adapter **adapter_out);

/**
 * nct6687_smbus_exit - Unregister the SMBus adapter and release I/O regions
 * @adapter: The registered struct i2c_adapter
 */
void nct6687_smbus_exit(struct i2c_adapter *adapter);

#endif /* _NCT6687_SMBUS_H_ */
