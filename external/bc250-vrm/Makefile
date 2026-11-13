obj-m += bc250_vrm.o
bc250_vrm-y := bc250_vrm_core.o nct6687_smbus.o

KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	make -C $(KDIR) M=$(CURDIR)modules

clean:
	make -C $(KDIR) M=$(CURDIR) clean

reload: all
	-sudo rmmod bc250_vrm 2>/dev/null
	sudo insmod bc250_vrm.ko
