#
# Copyright (C) 2022 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Local Path
LOCAL_PATH := $(call my-dir)

# Include (Device-specific)
ifeq ($(TARGET_DEVICE),bangkk)
    include $(call all-makefiles-under,$(LOCAL_PATH))
endif
