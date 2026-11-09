#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

clone_if_missing() {
    local REPO="$1"
    local BRANCH="$2"
    local DEST="$3"

    if [ ! -d "$DEST/.git" ]; then
        echo "Cloning $DEST..."
        mkdir -p "$(dirname "$DEST")"
        git clone --depth=1 -b "$BRANCH" "$REPO" "$DEST"
    fi
}

# Required repositories
clone_if_missing https://github.com/LineageOS/android_hardware_qcom_bootctrl.git lineage-19.1-caf hardware/qcom-caf/bootctrl
export LC_ALL="C"
export USE_CCACHE=1
export CCACHE_EXEC="/usr/bin/ccache"
export CCACHE_MAXSIZE="50G"
export CCACHE_DIR="/mnt/ccache"

# Warn if CCACHE_DIR is an invalid directory
if [ "$USE_CCACHE" = "1" ] && [ ! -d "${CCACHE_DIR}" ]; then
    echo "CCACHE Directory/Partition is not mounted at \"${CCACHE_DIR}\""
    echo "Please edit the CCACHE_DIR build variable or mount the directory."
fi

export FOX_DRASTIC_SIZE_REDUCTION=1
