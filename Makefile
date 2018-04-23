DEBUG ?= 1
SHELL := bash
BASH ?= bash

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

NVME_HTTPS		?= https://releases.linaro.org/96boards/archive/reference-platform/debian/hikey/16.06/bootloader/nvme.img
BL1_BIN			?= $(ARM_TF_PATH)/build/hikey/debug/bl1.bin
FIP_BIN			?= $(ARM_TF_PATH)/build/hikey/debug/fip.bin
LLOADER_BIN		?= $(LLOADER_PATH)/l-loader.bin
# https://github.com/96boards/edk2/raw/hikey/HisiPkg/HiKeyPkg/NonFree/mcuimage.bin
MCU_BIN			?= $(EDK2_PATH)/HisiPkg/HiKeyPkg/NonFree/mcuimage.bin
NVME_BIN		?= $(OUT_PATH)/nvme.img
# Change this according to the size of flash on your device
PTABLE_BIN		?= $(LLOADER_PATH)/ptable-linux-8g.img
UBOOT_BIN		?= $(UBOOT_PATH)/u-boot.bin

################################################################################
# Targets
################################################################################
.PHONY: all
all: u-boot arm-tf l-loader nvme | toolchains

.PHONY: clean
clean: u-boot-clean arm-tf-clean l-loader-clean nvme-clean

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
# U-Boot
################################################################################
.PHONY: u-boot
u-boot:
	$(MAKE) -C $(UBOOT_PATH) CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) hikey_config && \
	$(MAKE) -C $(UBOOT_PATH) CROSS_COMPILE=$(AARCH64_CROSS_COMPILE)

.PHONY: u-boot-clean
u-boot-clean:
	cd $(UBOOT_PATH) && git clean -xdf

################################################################################
# ARM Trusted Firmware
################################################################################
.PHONY: arm-tf
arm-tf: u-boot
	$(MAKE) -C $(ARM_TF_PATH) CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) all fip \
		BL30=$(MCU_BIN) \
		BL33=$(UBOOT_BIN) \
		DEBUG=1 \
		PLAT=hikey

.PHONY: arm-tf-clean
arm-tf-clean:
	cd $(ARM_TF_PATH) && git clean -xdf

################################################################################
# l-loader
################################################################################
l-loader: arm-tf
	$(MAKE) -C $(LLOADER_PATH) BL1=$(BL1_BIN) PTABLE_LST=linux-8g all

.PHONY: l-loader-clean
l-loader-clean:
	cd $(LLOADER_PATH) && git clean -xdf

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
