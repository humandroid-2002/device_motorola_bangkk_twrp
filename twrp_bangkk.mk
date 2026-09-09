#
# Copyright (C) 2022 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit base
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)

# TWRP Common
$(call inherit-product, vendor/twrp/config/common.mk)

# Device
$(call inherit-product, device/motorola/bangkk/device.mk)

# Shrp
$(call inherit-product, device/motorola/bangkk/shrp.mk)

# Ofox
$(call inherit-product, device/motorola/bangkk/ofox.mk)

# Pbrp
$(call inherit-product, device/motorola/bangkk/pbrp.mk)

# Must come after all inclusions
PRODUCT_BRAND        := motorola
PRODUCT_DEVICE       := bangkk
PRODUCT_MANUFACTURER := motorola
PRODUCT_MODEL        := moto g84 5G
PRODUCT_NAME         := twrp_bangkk
