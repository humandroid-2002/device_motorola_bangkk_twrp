#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/motorola/bangkk

# A/B
AB_OTA_POSTINSTALL_CONFIG += \
    RUN_POSTINSTALL_system=true \
    POSTINSTALL_PATH_system=system/bin/otapreopt_script \
    FILESYSTEM_TYPE_system=ext4 \
    POSTINSTALL_OPTIONAL_system=true

AB_OTA_POSTINSTALL_CONFIG += \
    RUN_POSTINSTALL_vendor=true \
    POSTINSTALL_PATH_vendor=bin/checkpoint_gc \
    FILESYSTEM_TYPE_vendor=ext4 \
    POSTINSTALL_OPTIONAL_vendor=true

# Update engine
PRODUCT_PACKAGES += \
    update_engine \
    update_engine_sideload \
    update_verifier \
    otapreopt_script \
    cppreopts.sh \
    checkpoint_gc

# Boot control HAL
PRODUCT_PACKAGES += \
    android.hardware.boot@1.1-impl-qti.recovery \
    bootctrl.holi

# Recovery
TARGET_RECOVERY_DEVICE_MODULES += \
    libion \
    libxml2 \
    display.config@2.0 \
    vendor.display.config@2.0

# Decrypt
PRODUCT_PACKAGES += \
    qcom_decrypt \
    qcom_decrypt_fbe \
    android.system.keystore2

# Product
PRODUCT_SHIPPING_API_LEVEL     := 30
PRODUCT_TARGET_VNDK_VERSION    := 30
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# Copy for recovery prebuilt kernel modules 2026-07-17
PRODUCT_COPY_FILES += $(call find-copy-subdir-files,*.ko,$(LOCAL_PATH)/prebuilt/modules,$(TARGET_COPY_OUT_RECOVERY)/root/vendor/lib/modules/1.1)
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)
