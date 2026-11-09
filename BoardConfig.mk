#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/motorola/bangkk

# Build Rules
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_MISSING_REQUIRED_MODULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

BUILD_BROKEN_NINJA_USES_ENV_VARS += RTIC_MPGEN
BUILD_BROKEN_PLUGIN_VALIDATION   := soong-libaosprecovery_defaults soong-libguitwrp_defaults soong-libminuitwrp_defaults soong-vold_defaults

# A/B
AB_OTA_UPDATER := true

AB_OTA_PARTITIONS := \
    boot \
    vendor_boot \
    dtbo \
    vbmeta \
    vbmeta_system \
    system \
    system_ext \
    product \
    vendor \
    vendor_dlkm \
    odm

# Architecture
TARGET_ARCH                    := arm64
TARGET_ARCH_VARIANT            := armv8-a
TARGET_CPU_ABI                 := arm64-v8a
TARGET_CPU_ABI2                :=
TARGET_CPU_VARIANT             := generic
TARGET_CPU_VARIANT_RUNTIME     := kryo300

TARGET_2ND_ARCH                := arm
TARGET_2ND_ARCH_VARIANT        := armv7-a-neon
TARGET_2ND_CPU_ABI             := armeabi-v7a
TARGET_2ND_CPU_ABI2            := armeabi
TARGET_2ND_CPU_VARIANT         := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a75

# Bootloader
TARGET_BOARD_PLATFORM_GPU          := qcom-adreno619
TARGET_BOOTLOADER_BOARD_NAME       := bangkk
TW_DEVICE_VERSION                  := bangkk
TARGET_BOARD_PLATFORM              := holi
QCOM_BOARD_PLATFORMS               += holi
TARGET_USES_HARDWARE_QCOM_BOOTCTRL := true
BOARD_USES_RECOVERY_AS_BOOT        := true
TARGET_NO_BOOTLOADER               := true
BOARD_PROVIDES_GPTUTILS            := true
BOARD_USES_QCOM_HARDWARE           := true
TARGET_USES_UEFI                   := true
TARGET_NO_RECOVERY                 := true
TARGET_USES_QCOM_BSP               := true
ENABLE_CPUSETS                     := true
ENABLE_SCHEDBOOST                  := true

# Kernel
BOARD_BOOT_HEADER_VERSION := 3

BOARD_MKBOOTIMG_ARGS += --cmdline "twrpfastboot=1"
BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive
BOARD_KERNEL_CMDLINE += androidboot.hab.product=bangkk

BOARD_KERNEL_IMAGE_NAME := Image
BOARD_RAMDISK_USE_LZ4   := true

# Keep only required modules; we're almost on size limit (Touch,Battery and Haptics)
TW_LOAD_VENDOR_MODULES := "focaltech_v3.ko"
# WLAN
#TW_LOAD_VENDOR_MODULES := 

BOARD_KERNEL_PAGESIZE      := 4096
BOARD_FLASH_BLOCK_SIZE     := 262144 # (BOARD_KERNEL_PAGESIZE * 64)

# offset
BOARD_KERNEL_BASE          := 0x00000000
BOARD_DTB_OFFSET           := 0x01f00000
BOARD_KERNEL_TAGS_OFFSET   := 0x00000100
BOARD_KERNEL_OFFSET        := 0x00008000
BOARD_KERNEL_SECOND_OFFSET := 0x00000000
BOARD_RAMDISK_OFFSET       := 0x01000000

BOARD_MKBOOTIMG_ARGS += --kernel_offset $(BOARD_KERNEL_OFFSET)
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
BOARD_MKBOOTIMG_ARGS += --dtb $(TARGET_PREBUILT_DTB)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --base $(BOARD_KERNEL_BASE)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)
BOARD_MKBOOTIMG_ARGS += --second_offset $(BOARD_KERNEL_SECOND_OFFSET)

# prebuilt
TARGET_FORCE_PREBUILT       := true
ifeq ($(TARGET_FORCE_PREBUILT),true)
TARGET_PREBUILT_KERNEL      := $(DEVICE_PATH)/prebuilt/Image.gz
TARGET_PREBUILT_DTB         := $(DEVICE_PATH)/prebuilt/dtb
else
TARGET_KERNEL_SOURCE := kernel/motorola/sm6375
TARGET_KERNEL_CONFIG := vendor/holi-qgki_defconfig vendor/ext_config/lineage_moto-holi.config
TARGET_KERNEL_CONFIG += vendor/ext_config/moto-holi-bangkk.config
endif

# Partition
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
TARGET_SYSTEM_PROP    += $(DEVICE_PATH)/system.prop
BOARD_ROOT_EXTRA_SYMLINKS := \
    /vendor/fsg:/fsg

BOARD_BOOTIMAGE_PARTITION_SIZE        := 100663296
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296

# A device can set up BOARD_SYSTEMIMAGE_JOURNAL_SIZE (number of journal blocks)
# in its BoardConfig.mk.
# To disable journaling, set "BOARD_SYSTEMIMAGE_JOURNAL_SIZE := 0".
# BOARD_VENDORIMAGE_JOURNAL_SIZE and BOARD_OEMIMAGE_JOURNAL_SIZE work in
# similar way.
BOARD_SYSTEMIMAGE_JOURNAL_SIZE        := 0
BOARD_VENDORIMAGE_JOURNAL_SIZE        := 0
BOARD_OEMIMAGE_JOURNAL_SIZE           := 0

TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USES_MKE2FS         := true

BOARD_SUPER_PARTITION_SIZE                  := 9126805504 # TODO: Fix hardcoded value
BOARD_SUPER_PARTITION_GROUPS                := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE           := 9122611200 # TODO: Fix hardcoded value
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext product vendor vendor_dlkm odm

BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE   := f2fs
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE    := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE     := ext4
BOARD_SYSTEMIMAGE_PARTITION_TYPE       := ext4
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE        := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE     := ext4
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE      := ext4

TARGET_COPY_OUT_PRODUCT    := product
TARGET_COPY_OUT_SYSTEM     := system
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_ODM        := odm
TARGET_COPY_OUT_VENDOR     := vendor

BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true
BOARD_USES_PRODUCTIMAGE                := true

# Crypto
FIXED_DECRYPT                   := true
TW_INCLUDE_CRYPTO               := $(FIXED_DECRYPT)
TW_INCLUDE_CRYPTO_FBE           := $(FIXED_DECRYPT)
TW_INCLUDE_FBE_METADATA_DECRYPT := $(FIXED_DECRYPT)
BOARD_USES_QCOM_FBE_DECRYPTION  := $(FIXED_DECRYPT)
BOARD_USES_METADATA_PARTITION   := true

# Hack: prevent anti rollback
PLATFORM_VERSION             := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH      := 2099-12-31
VENDOR_SECURITY_PATCH        := $(PLATFORM_SECURITY_PATCH)
BOOT_SECURITY_PATCH          := $(PLATFORM_SECURITY_PATCH)

# Verified Boot
BOARD_AVB_ENABLE                                := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS                += --flags 3
BOARD_AVB_VBMETA_SYSTEM                         := system system_ext product
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM               := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH                := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX          := 22
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 2

# TWRP Configuration
TW_THEME                        := portrait_hdpi
TARGET_RECOVERY_PIXEL_FORMAT    := RGBX_8888
TARGET_USE_CUSTOM_LUN_FILE_PATH := /config/usb_gadget/g1/functions/mass_storage.0/lun.%d/file
TW_INPUT_BLACKLIST              := "hbtp_vm"
TW_BRIGHTNESS_PATH              := "/sys/class/backlight/panel0-backlight/brightness"
TW_CUSTOM_CPU_TEMP_PATH         := "/sys/class/thermal/thermal_zone28/temp" # CPU-0-0-USR
TW_CUSTOM_BATTERY_PATH          := "/sys/class/power_supply/qcom_battery"
TW_HAS_FLASHLIGHT               := false
RECOVERY_SDCARD_ON_DATA         := true
TW_MAX_BRIGHTNESS               := 1650
TW_DEFAULT_BRIGHTNESS           := 1300
TW_DEFAULT_TIME_ZONE            := UTC+1
TW_DEFAULT_TIME_ZONE_GUISEL     := Europe/Rome
TW_DEFAULT_TIME_ZONE_GUIOFFSET  := 60
TW_DEFAULT_TIME_ZONE_GUIDST     := 60
TW_FRAMERATE                    := 120
TW_CUSTOM_BATTERY_POS           := 810
TW_CUSTOM_CLOCK_POS             := 50
TW_CUSTOM_CPU_POS               := 280
TW_STATUS_ICONS_ALIGN           := center
TW_EXCLUDE_DEFAULT_USB_INIT     := true
TW_NO_SCREEN_BLANK              := true
TW_EXTRA_LANGUAGES              := false
TWRP_INCLUDE_LOGCAT             := true
TARGET_USES_LOGD                := true
# Battery
TW_USE_LEGACY_BATTERY_SERVICES  := true
TARGET_RECOVERY_QCOM_RTC_FIX    := true

# Recovery modules
TARGET_RECOVERY_DEVICE_MODULES += \
    debuggerd \
    strace

# Recovery binaries
RECOVERY_BINARY_SOURCE_FILES += \
    $(TARGET_OUT_EXECUTABLES)/debuggerd \
    $(TARGET_OUT_EXECUTABLES)/strace

# Recovery libraries
RECOVERY_LIBRARY_SOURCE_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/libion.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libxml2.so \
    $(TARGET_OUT_SYSTEM_EXT_SHARED_LIBRARIES)/display.config@2.0.so \
    $(TARGET_OUT_SYSTEM_EXT_SHARED_LIBRARIES)/vendor.display.config@2.0.so

# Misc
FIXED_HAPTICS := true

ifeq ($(FIXED_HAPTICS),true)
   TW_SUPPORT_INPUT_AIDL_HAPTICS := true
   TW_SUPPORT_INPUT_AIDL_HAPTICS_FQNAME := "IVibrator/default"
   TW_SUPPORT_INPUT_AIDL_HAPTICS_FIX_OFF := true
else
   TW_NO_HAPTICS := true
endif

# Set to 1 to include WLAN features
OF_ENABLE_WLAN := 1
