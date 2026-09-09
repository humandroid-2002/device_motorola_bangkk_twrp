#
# Copyright (C) 2022 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Device
DEVICE_PATH := device/motorola/bangkk

# Architecture
TARGET_ARCH                := arm64
TARGET_ARCH_VARIANT        := armv8-a
TARGET_CPU_ABI             := arm64-v8a
TARGET_CPU_ABI2            :=
TARGET_CPU_VARIANT         := generic
TARGET_CPU_VARIANT_RUNTIME := kryo300

TARGET_2ND_ARCH                := arm
TARGET_2ND_ARCH_VARIANT        := armv8-a
TARGET_2ND_CPU_ABI             := armeabi-v7a
TARGET_2ND_CPU_ABI2            := armeabi
TARGET_2ND_CPU_VARIANT         := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a75

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := bangkk
TARGET_NO_BOOTLOADER         := true
TARGET_USES_UEFI             := true

# Platform
BOARD_USES_QCOM_HARDWARE           := true
TARGET_USES_HARDWARE_QCOM_BOOTCTRL := true
QCOM_BOARD_PLATFORMS               += holi
TARGET_BOARD_PLATFORM              := holi
TARGET_BOARD_PLATFORM_GPU          := qcom-adreno619
TARGET_USES_64_BIT_BINDER          := true
TARGET_SUPPORTS_64_BIT_APPS        := true
BUILD_BROKEN_DUP_RULES             := true
TARGET_USES_QCOM_BSP               := true
ENABLE_CPUSETS                     := true
ENABLE_SCHEDBOOST                  := true
BOARD_PROVIDES_GPTUTILS            := true

# Kernel
BOARD_BOOT_HEADER_VERSION := 3
BOARD_MKBOOTIMG_ARGS      += --cmdline "twrpfastboot=1"
BOARD_KERNEL_CMDLINE      += androidboot.selinux=permissive
BOARD_KERNEL_CMDLINE      += androidboot.hab.product=bangkk
BOARD_KERNEL_CMDLINE      += firmware_class.path=/vendor/firmware_mnt/image
BOARD_KERNEL_IMAGE_NAME   := Image
BOARD_KERNEL_PAGESIZE     := 4096
BOARD_MKBOOTIMG_ARGS      += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_RAMDISK_USE_LZ4     := true
TARGET_KERNEL_ARCH        := arm64
TARGET_NO_KERNEL          := false
TARGET_PREBUILT_KERNEL    := $(DEVICE_PATH)/prebuilt/Image

# Assert
BOARD_ROOT_EXTRA_SYMLINKS := \
    /vendor/fsg:/fsg
TARGET_OTA_ASSERT_DEVICE := bangkk, bangkk_retcn

# Partitions
BOARD_BOOTIMAGE_PARTITION_SIZE         := 100663296
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE   := 100663296
BOARD_SYSTEMIMAGE_JOURNAL_SIZE         := 0
BOARD_SYSTEMIMAGE_EXTFS_INODE_COUNT    := 4096
BOARD_FLASH_BLOCK_SIZE                 := 262144 # (BOARD_KERNEL_PAGESIZE * 64)
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE        := ext4
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE     := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE    := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USES_PRODUCTIMAGE                := true
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE  := 100663296
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE     := ext4

TARGET_COPY_OUT_ODM        := odm
TARGET_COPY_OUT_PRODUCT    := product
TARGET_COPY_OUT_SYSTEM     := system
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_VENDOR     := vendor

TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# Dynamic Partitions
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST   := product system system_ext vendor
BOARD_PARTITION_LIST                          := product system system_ext vendor
TREBLE_PARTITIONS                             := vendor
BOARD_USERDATAIMAGE_PARTITION_SIZE            := 246543265792
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE             := 6706692096 # BOARD_SUPER_PARTITION_SIZE - 4MB
BOARD_SUPER_PARTITION_GROUPS                  := qti_dynamic_partitions
BOARD_SUPER_PARTITION_SIZE                    := 6710886400
BOARD_SYSTEM_EXTIMAGE_PARTITION_RESERVED_SIZE := 765304832
BOARD_PRODUCTIMAGE_PARTITION_RESERVED_SIZE    := 2630414336
BOARD_SYSTEMIMAGE_PARTITION_RESERVED_SIZE     := 634920960
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE          := f2fs
BOARD_SYSTEMIMAGE_PARTITION_TYPE              := ext4

# Properties
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# Security / Encryption / AVB
BOARD_AVB_ENABLE                                := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS                += --flags 3
BOARD_AVB_VBMETA_SYSTEM                         := system system_ext product
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM               := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH                := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX          := 22
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 2
BOARD_USES_QCOM_FBE_DECRYPTION                  := true
PLATFORM_SECURITY_PATCH                         := 2099-12-31
PLATFORM_VERSION                                := 99.87.36
PLATFORM_VERSION_LAST_STABLE                    := $(PLATFORM_VERSION)
VENDOR_SECURITY_PATCH                           := $(PLATFORM_SECURITY_PATCH)

# Metadata
BOARD_USES_METADATA_PARTITION := true
TW_EXCLUDE_APEX               := true

# Recovery
BOARD_HAS_LARGE_FILESYSTEM  := true
BOARD_HAS_NO_SELECT_BUTTON  := true
BOARD_SUPPRESS_SECURE_ERASE := true
BOARD_USES_RECOVERY_AS_BOOT := true
TARGET_NO_RECOVERY          := true
RECOVERY_LIBRARY_SOURCE_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/libion.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libxml2.so \
    $(TARGET_OUT_SYSTEM_EXT_SHARED_LIBRARIES)/vendor.display.config@2.0.so
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
TARGET_USES_MKE2FS    := true

# TWRP Config
TW_THEME                                     := portrait_hdpi
TARGET_RECOVERY_PIXEL_FORMAT                 := RGBX_8888
TARGET_RECOVERY_QCOM_RTC_FIX                 := true
TARGET_USE_CUSTOM_LUN_FILE_PATH              := /config/usb_gadget/g1/functions/mass_storage.0/lun.%d/file
TW_BRIGHTNESS_PATH                           := "/sys/class/backlight/panel0-backlight/brightness"
TW_CUSTOM_CPU_TEMP_PATH                      := "/sys/class/thermal/thermal_zone28/temp" # CPU-0-0-USR
TW_EXCLUDE_DEFAULT_USB_INIT                  := true
TW_EXTRA_LANGUAGES                           := false
TW_INCLUDE_CRYPTO                            := true
TW_INCLUDE_CRYPTO_FBE                        := true
TW_INCLUDE_FBE_METADATA_DECRYPT              := true
TW_EXCLUDE_TWRPAPP                           := true
TW_INCLUDE_FB2PNG                            := true
TW_INCLUDE_REPACKTOOLS                       := true
TW_INCLUDE_RESETPROP                         := true
TW_NO_EXFAT_FUSE                             := true
TW_DEFAULT_TIME_ZONE                         := UTC+1
TW_DEFAULT_TIME_ZONE_GUISEL                  := Europe/Rome
TW_DEFAULT_TIME_ZONE_GUIOFFSET               := 60
TW_DEFAULT_TIME_ZONE_GUIDST                  := 60
TW_QCOM_ATS_OFFSET                           := 1621580431500
TW_CUSTOM_BATTERY_POS                        := 830
TW_CUSTOM_CLOCK_POS                          := 50
TW_CUSTOM_CPU_POS                            := 280
TW_DEFAULT_BRIGHTNESS                        := 1650
TW_DEVICE_VERSION                            := bangkk
TW_FRAMERATE                                 := 120
TW_HAS_FLASHLIGHT                            := true
TW_INCLUDE_NTFS_3G                           := true
TW_MAX_BRIGHTNESS                            := 1650
TW_STATUS_ICONS_ALIGN                        := center
TW_USE_LEGACY_BATTERY_SERVICES               := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
TW_LOAD_PREBUILT_MODULES_AT_FIRST            := true
TW_LOAD_VENDOR_BOOT_MODULES                  := true
TW_LOAD_VENDOR_MODULES                       := "mmi_relay.ko mmi_info.ko mmi_annotate.ko sensors_class.ko exfat.ko touchscreen_mmi.ko focaltech_v3.ko goodix_brl_mmi.ko bq25980_mmi_iio.ko mmi-smbcharger-iio.ko mmi_parallel_charger_iio.ko ldo_vibrator_mmi.ko"

# Debug
RECOVERY_BINARY_SOURCE_FILES   += $(TARGET_OUT_EXECUTABLES)/debuggerd
RECOVERY_BINARY_SOURCE_FILES   += $(TARGET_OUT_EXECUTABLES)/strace
TARGET_RECOVERY_DEVICE_MODULES += debuggerd
TARGET_RECOVERY_DEVICE_MODULES += strace
TARGET_USES_LOGD               := true
TWRP_INCLUDE_LOGCAT            := true
TW_HAS_EDL_MODE                := true
TW_INCLUDE_FASTBOOTD           := true

# Misc
FIXED_HAPTICS := true

ifeq ($(FIXED_HAPTICS),true)
   TW_SUPPORT_INPUT_AIDL_HAPTICS         := true
   TW_SUPPORT_INPUT_AIDL_HAPTICS_FQNAME  := "IVibrator/default"
   TW_SUPPORT_INPUT_AIDL_HAPTICS_FIX_OFF := true
else
   TW_NO_HAPTICS := true
endif

# Network
BUILD_BROKEN_USES_NETWORK := true
