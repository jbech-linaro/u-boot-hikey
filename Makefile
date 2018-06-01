DEBUG ?= 1
SHELL := bash
BASH ?= bash

CCACHE ?= $(shell which ccache) # Don't remove this comment (space is needed)

################################################################################
# Paths to git projects and various binaries
################################################################################
ROOT			?= $(shell pwd)
OUT_PATH		?= $(ROOT)/out

ARM_TF_PATH		?= $(ROOT)/arm-trusted-firmware
BURN_BOOT_PATH		?= $(ROOT)/burn-boot
EDK2_PATH		?= $(ROOT)/edk2
LLOADER_PATH		?= $(ROOT)/l-loader
UBOOT_PATH		?= $(ROOT)/u-boot
OPTEE_PATH		?= $(ROOT)/optee_os

NVME_HTTPS		?= https://releases.linaro.org/96boards/archive/reference-platform/debian/hikey/16.06/bootloader/nvme.img
BL1_BIN			?= $(ARM_TF_PATH)/build/hikey/debug/bl1.bin
FIP_BIN			?= $(ARM_TF_PATH)/build/hikey/debug/fip.bin
LLOADER_BIN		?= $(LLOADER_PATH)/l-loader.bin
# https://github.com/96boards/edk2/raw/hikey/HisiPkg/HiKeyPkg/NonFree/mcuimage.bin
MCU_HTTPS		?= https://github.com/96boards-hikey/OpenPlatformPkg/raw/hikey970_v1.0/Platforms/Hisilicon/HiKey/Binary/mcuimage.bin
MCU_BIN			?= $(OUT_PATH)/mcuimage.bin
NVME_BIN		?= $(OUT_PATH)/nvme.img
# Change this according to the size of flash on your device
PTABLE_BIN		?= $(LLOADER_PATH)/ptable-linux-8g.img
UBOOT_BIN		?= $(UBOOT_PATH)/u-boot.bin

OPTEE_BIN		?= $(OPTEE_PATH)/out/arm-plat-hikey/core/tee.bin
OPTEE_BIN_EXTRA1	?= $(OPTEE_PATH)/out/arm-plat-hikey/core/tee-pager.bin
OPTEE_BIN_EXTRA2	?= $(OPTEE_PATH)/out/arm-plat-hikey/core/tee-pageable.bin


################################################################################
# Targets
################################################################################
.PHONY: all
all: u-boot arm-tf l-loader nvme mcuimage | toolchains

.PHONY: clean
clean: u-boot-clean arm-tf-clean l-loader-clean nvme-clean mcuimage-clean

################################################################################
# Toolchain
################################################################################
include toolchain.mk

################################################################################
# Folders
################################################################################
$(OUT_PATH):
	@mkdir -p $@

################################################################################
# NVME
################################################################################
.PHONY: nvme
nvme: $(OUT_PATH)
ifeq ($(wildcard $(NVME_BIN)),)
	@wget -P $(OUT_PATH) $(NVME_HTTPS)
endif

.PHONY: nvme-clean
nvme-clean:
	rm -f $(NVME_BIN)

################################################################################
# MCUIMAGE
################################################################################
.PHONY: mcuimage
mcuimage: $(OUT_PATH)
ifeq ($(wildcard $(MCU_BIN)),)
	@wget -P $(OUT_PATH) $(MCU_HTTPS)
endif

.PHONY: mcuimage-clean
mcuimage-clean:
	rm -f $(MCU_BIN)

################################################################################
# U-Boot
################################################################################
.PHONY: u-boot-config
u-boot-config:
ifeq ($(wildcard $(UBOOT_PATH)/.config),)
	$(MAKE) -C $(UBOOT_PATH) CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) hikey_config
endif

.PHONY: u-boot-menuconfig
u-boot-menuconfig: u-boot-config
	$(MAKE) -C $(UBOOT_PATH) CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) menuconfig

.PHONY: u-boot
u-boot: u-boot-config
	$(MAKE) -C $(UBOOT_PATH) CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" DTC=$(ROOT)/dtc

.PHONY: u-boot-clean
u-boot-clean:
	$(MAKE) -C $(UBOOT_PATH) distclean

################################################################################
# ARM Trusted Firmware
################################################################################
.PHONY: arm-tf
arm-tf: u-boot optee-os mcuimage
	$(MAKE) -C $(ARM_TF_PATH) CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" all fip \
		BL30=$(MCU_BIN) \
		BL33=$(UBOOT_BIN) \
		DEBUG=1 \
		DISABLE_PEDANTIC=1 \
		BL32=$(OPTEE_BIN) \
		PLAT=hikey SPD=opteed

	ORIG_SIZE=$$(stat --printf="%s" $(FIP_BIN)); \
	echo $$ORIG_SIZE; \
	SIZE_ADD=$$(( (($$ORIG_SIZE + 511) / 512) * 512 - $$ORIG_SIZE )); \
	truncate -s +$$SIZE_ADD $(FIP_BIN)

.PHONY: arm-tf-clean optee-os-clean
arm-tf-clean:
	cd $(ARM_TF_PATH) && git clean -xdf

################################################################################
# l-loader
################################################################################
l-loader: arm-tf
	$(MAKE) -C $(LLOADER_PATH) CROSS_COMPILE=$(AARCH32_CROSS_COMPILE) BL1=$(BL1_BIN) PTABLE_LST=linux-8g all

.PHONY: l-loader-clean
l-loader-clean:
	cd $(LLOADER_PATH) && git clean -xdf

################################################################################
# OP-TEE OS
################################################################################
.PHONY: optee-os
optee-os:
	$(MAKE) -C $(OPTEE_PATH) PLATFORM=hikey CFG_ARM64_core=y \
		CROSS_COMPILE="$(AARCH32_CROSS_COMPILE)" \
		CROSS_COMPILE_core="$(AARCH64_CROSS_COMPILE)" \
		CROSS_COMPILE_ta_arm64="$(AARCH64_CROSS_COMPILE)" \
		CROSS_COMPILE_ta_arm32="$(AARCH32_CROSS_COMPILE)" \
		CFG_TEE_CORE_LOG_LEVEL=4

.PHONY: optee-os-clean
optee-os-clean:
	$(MAKE) -C $(OPTEE_PATH) clean


################################################################################
# flash
################################################################################
.PHONY: flash
flash:
	@read -r -p "Put HiKey in recovery and turn on power (press enter to continue)" dummy
	$(BURN_BOOT_PATH)/hisi-idt.py --img1=$(LLOADER_BIN)
	@echo "Flashing: $(PTABLE_BIN)"
	fastboot flash ptable $(PTABLE_BIN)
	@echo "Flashing: $(FIP_BIN)"
	fastboot flash fastboot $(FIP_BIN)
	@echo "Flashing: $(NVME_BIN)"
	fastboot flash nvme $(NVME_BIN)

.PHONY: flash-fip
flash-fip:
	@read -r -p "Put HiKey in recovery and turn on power (press enter to continue)" dummy
	$(BURN_BOOT_PATH)/hisi-idt.py --img1=$(LLOADER_BIN)
	fastboot flash fastboot $(FIP_BIN)
