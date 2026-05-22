#
# Copyright (C) 2022 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# =========================================================
# Storage / Filesystem
# =========================================================

# Enable project quotas and casefolding for emulated storage without sdcardfs
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)

# =========================================================
# GSI
# =========================================================

# Installs gsi keys into ramdisk, to boot a GSI with verified boot.
ifneq ($(wildcard $(SRC_TARGET_DIR)/product/gsi_keys.mk),)
    $(call inherit-product, $(SRC_TARGET_DIR)/product/gsi_keys.mk)
endif

# =========================================================
# A/B OTA
# =========================================================

AB_OTA_PARTITIONS += \
    boot \
    dtbo \
    product \
    system \
    system_ext \
    vbmeta \
    vbmeta_system \
    vendor \
    vendor_boot

AB_OTA_POSTINSTALL_CONFIG += \
    FILESYSTEM_TYPE_system=ext4 \
    POSTINSTALL_OPTIONAL_system=true \
    POSTINSTALL_PATH_system=system/bin/otapreopt_script \
    RUN_POSTINSTALL_system=true

AB_OTA_POSTINSTALL_CONFIG += \
    FILESYSTEM_TYPE_vendor=ext4 \
    POSTINSTALL_OPTIONAL_vendor=true \
    POSTINSTALL_PATH_vendor=bin/checkpoint_gc \
    RUN_POSTINSTALL_vendor=true

AB_OTA_UPDATER := true
TARGET_ENFORCE_AB_OTA_PARTITION_LIST := true

# Enable virtual A/B OTA
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota.mk)

# =========================================================
# Boot Control / Fastboot
# =========================================================

PRODUCT_PACKAGES += \
    android.hardware.boot@1.1-impl-qti.recovery \
    bootctrl.holi.recovery

PRODUCT_PACKAGES += \
    android.hardware.fastboot@1.1-impl-mock \
    fastbootd

# =========================================================
# Recovery / Display
# =========================================================

TARGET_RECOVERY_DEVICE_MODULES += \
    libion \
    libxml2 \
    vendor.display.config@2.0

# =========================================================
# Partitions
# =========================================================

PRODUCT_USE_DYNAMIC_PARTITIONS := true

# =========================================================
# QCOM
# =========================================================

PRODUCT_PACKAGES += \
    qcom_decrypt \
    qcom_decrypt_fbe

# =========================================================
# Keystore
# =========================================================

PRODUCT_PACKAGES += \
    android.system.keystore2

# =========================================================
# Update Engine
# =========================================================

PRODUCT_PACKAGES += \
    checkpoint_gc \
    otapreopt_script

PRODUCT_PACKAGES += \
    update_engine \
    update_engine_sideload \
    update_verifier

# =========================================================
# Shipping / VNDK
# =========================================================

PRODUCT_SHIPPING_API_LEVEL := 30
PRODUCT_TARGET_VNDK_VERSION := 30

# =========================================================
# OEM Motorola otacert
# =========================================================

PRODUCT_EXTRA_RECOVERY_KEYS += \
    $(LOCAL_PATH)/security/ota

# =========================================================
# Soong
# =========================================================

PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)

# =========================================================
# Kernel Modules
# =========================================================

# Copy modules for depmod
PRODUCT_COPY_FILES += $(call find-copy-subdir-files,*.ko,$(LOCAL_PATH)/prebuilt/modules,$(TARGET_COPY_OUT_RECOVERY)/root/vendor/lib/modules/1.1)
