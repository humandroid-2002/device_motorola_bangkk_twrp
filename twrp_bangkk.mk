#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

# Configure base.mk
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)

# Configure core_64_bit_only.mk
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)

# Configure emulated_storage.mk
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)

# Configure twrp common.mk
$(call inherit-product, vendor/twrp/config/common.mk)

# Inherit from bangkk device
$(call inherit-product, device/motorola/bangkk/device.mk)

# Inherit from fox
$(call inherit-product, device/motorola/bangkk/fox.mk)

PRODUCT_ENABLE_UFFD_GC := true
PRODUCT_DEVICE         := bangkk
PRODUCT_NAME           := twrp_bangkk
PRODUCT_BRAND          := motorola
PRODUCT_MODEL          := HelloMoto
PRODUCT_MANUFACTURER   := motorola

#PRODUCT_BUILD_PROP_OVERRIDES += \
#    PRIVATE_BUILD_DESC="bangkk_g-user 11 V1TCS35H.88-16-6 9ef38 release-keys"

#BUILD_FINGERPRINT := motorola/bangkk_g/bangkk:11/V1TCS35H.88-16-6/9ef38:user/release-keys
