CONFIG_AIC_LOADFW_SUPPORT := m
CONFIG_AIC8800_WLAN_SUPPORT := m

obj-$(CONFIG_AIC_LOADFW_SUPPORT)    += aic_load_fw/
obj-$(CONFIG_AIC8800_WLAN_SUPPORT) += aic8800_fdrv/

########## config option ##########
export CONFIG_USE_FW_REQUEST = n
export CONFIG_PREALLOC_RX_SKB = y
export CONFIG_PREALLOC_TXQ = y
export CONFIG_WOWLAN = n
###################################

########## platform support list ##########
export CONFIG_PLATFORM_ROCKCHIP = n
export CONFIG_PLATFORM_ALLWINNER = n
export CONFIG_PLATFORM_AMLOGIC = n
export CONFIG_PLATFORM_HI = n
export CONFIG_PLATFORM_UBUNTU = y

ifeq ($(CONFIG_PLATFORM_ROCKCHIP), y)
ARCH = arm64
KDIR = /home/yaya/E/Rockchip/3566/firefly/Android11.0/Firefly-RK356X_Android11.0_git_20210824/RK356X_Android11.0/kernel
CROSS_COMPILE = /home/yaya/E/Rockchip/3566/firefly/Android11.0/Firefly-RK356X_Android11.0_git_20210824/RK356X_Android11.0/prebuilts/gcc/linux-x86/aarch64/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
ccflags-y += -DANDROID_PLATFORM
endif

ifeq ($(CONFIG_PLATFORM_ALLWINNER), y)
KDIR  = /home/yaya/E/Allwinner/R818/R818/AndroidQ/lichee/kernel/linux-4.9
ARCH = arm64
CROSS_COMPILE = /home/yaya/E/Allwinner/R818/R818/AndroidQ/lichee/out/gcc-linaro-5.3.1-2016.05-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
ccflags-y += -DANDROID_PLATFORM
endif

ifeq ($(CONFIG_PLATFORM_AMLOGIC), y)
ccflags-y += -DANDROID_PLATFORM
ARCH = arm
CROSS_COMPILE = /home/yaya/D/Workspace/CyberQuantum/JinHaoYue/amls905x3/SDK/20191101-0tt-asop/android9.0/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androidkernel-
KDIR = /home/yaya/D/Workspace/CyberQuantum/JinHaoYue/amls905x3/SDK/20191101-0tt-asop/android9.0/out/target/product/u202/obj/KERNEL_OBJ/
endif

ifeq ($(CONFIG_PLATFORM_HI), y)
ccflags-y += -DANDROID_PLATFORM
ARCH = arm
CROSS_COMPILE = /home/yaya/D/Workspace/CyberQuantum/JinHaoYue/amls905x3/SDK/20191101-0tt-asop/android9.0/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androidkernel-
KDIR = /home/yaya/D/Workspace/CyberQuantum/JinHaoYue/amls905x3/SDK/20191101-0tt-asop/android9.0/out/target/product/u202/obj/KERNEL_OBJ/
endif

ifeq ($(CONFIG_PLATFORM_UBUNTU), y)
PWD     = $(shell pwd)
UNAME_R = $(shell uname -r)
# Kernel headers lookup order:
#   1. headers matching the running kernel (normal distro case)
#   2. headers unpacked locally by `make steamos-headers` (SteamOS rootfs is
#      read-only, so headers live in ./steamos-headers instead of /usr)
#   3. newest headers found anywhere - version may not match the running
#      kernel, in which case the build prints a warning
KDIR ?= $(firstword \
	$(wildcard /lib/modules/$(UNAME_R)/build) \
	$(wildcard $(PWD)/steamos-headers/usr/lib/modules/$(UNAME_R)/build) \
	$(shell ls -dv /usr/lib/modules/*/build $(PWD)/steamos-headers/usr/lib/modules/*/build 2>/dev/null | tail -n 1))
# kernel release the modules are built for (may differ from uname -r)
KVER = $(shell cat $(KDIR)/include/config/kernel.release 2>/dev/null || uname -r)
MODDESTDIR = /usr/lib/modules/$(KVER)/updates/aic8800
SUBARCH = $(shell uname -m | sed -e s/i.86/i386/ -e s/armv.l/arm/ -e s/aarch64/arm64/ -e s/loongarch64/loongarch/ -e s/loong64/loongarch/)
ARCH ?= $(SUBARCH)
CROSS_COMPILE ?=
# The SteamOS kernel is built with CONFIG_DEBUG_INFO_BTF_MODULES, but the
# system ships no pahole, so module BTF generation would fail with
# "command not found". BTF is optional debug metadata - build without it.
ifeq ($(shell command -v pahole),)
BTF_OVERRIDE = CONFIG_DEBUG_INFO_BTF_MODULES=
endif
endif

###########################################

MAKEFLAGS +=-j$(shell nproc)

.PHONY: all modules steamos-headers install uninstall clean distclean

all: modules
modules:
	@if [ -z "$(KDIR)" ]; then \
		echo "ERROR: no kernel headers found for $(UNAME_R)."; \
		echo "  On SteamOS run:  make steamos-headers"; \
		echo "  (downloads matching headers into ./steamos-headers, no root needed)"; \
		exit 1; \
	fi
	@if [ "$(KVER)" != "$(UNAME_R)" ]; then \
		echo "WARNING: headers are for $(KVER) but the running kernel is $(UNAME_R)."; \
		echo "         The built modules will only load on kernel $(KVER)."; \
	fi
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(BTF_OVERRIDE) modules

# SteamOS: fetch the headers package that exactly matches the running kernel
# from Valve's package archive and unpack it next to the sources. This avoids
# both the read-only rootfs and the repo carrying a newer kernel than the one
# currently running.
STEAMOS_POOL = https://steamdeck-packages.steamos.cloud/archlinux-mirror/jupiter-main/os/x86_64
steamos-headers:
	@pkgbase=$$(cat /usr/lib/modules/$(UNAME_R)/pkgbase) || exit 1; \
	flavor=$${pkgbase#linux-}; \
	pkgver=$$(echo "$(UNAME_R)" | sed -e "s/-$$flavor-g[0-9a-f]*$$//" -e 's/-/./'); \
	pkg=$$pkgbase-headers-$$pkgver-x86_64.pkg.tar.zst; \
	echo "Fetching $$pkg ..."; \
	mkdir -p steamos-headers; \
	curl -f -L -o steamos-headers/$$pkg $(STEAMOS_POOL)/$$pkg && \
	tar --zstd -xf steamos-headers/$$pkg -C steamos-headers && \
	echo "Headers unpacked; now run: make"

install:
	@mkdir -p $(MODDESTDIR) 2>/dev/null || { \
		echo "ERROR: cannot create $(MODDESTDIR)."; \
		echo "  Run with sudo; on SteamOS first run: sudo steamos-readonly disable"; \
		echo "  (and re-enable it afterwards: sudo steamos-readonly enable)"; \
		exit 1; \
	}
	install -p -m 644 aic_load_fw/aic_load_fw.ko  $(MODDESTDIR)/
	install -p -m 644 aic8800_fdrv/aic8800_fdrv.ko  $(MODDESTDIR)/
	/sbin/depmod -a ${KVER}

uninstall:
	rm -rfv $(MODDESTDIR)/aic_load_fw.ko
	rm -rfv $(MODDESTDIR)/aic8800_fdrv.ko
	/sbin/depmod -a ${KVER}

clean:
	cd aic_load_fw/;make clean;cd ..
	cd aic8800_fdrv/;make clean;cd ..
	rm -rf modules.order Module.symvers .modules.order.cmd .Module.symvers.cmd .tmp_versions/

distclean: clean
	rm -rf steamos-headers/
