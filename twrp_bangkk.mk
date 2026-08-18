#
# Copyright (C) 2022 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit (base first)
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)

ifneq ($(wildcard $(SRC_TARGET_DIR)/product/gsi_keys.mk),)
    $(call inherit-product, $(SRC_TARGET_DIR)/product/gsi_keys.mk)
endif

# Device
$(call inherit-product, device/motorola/bangkk/device.mk)

# TWRP Common
$(call inherit-product, vendor/twrp/config/common.mk)

# Must come after all inclusions
PRODUCT_BRAND := motorola
PRODUCT_DEVICE := bangkk
PRODUCT_MANUFACTURER := motorola
PRODUCT_MODEL := HelloMoto
PRODUCT_NAME := twrp_bangkk
