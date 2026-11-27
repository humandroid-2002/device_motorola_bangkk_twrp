#
# AERA Recovery build-time variables for bangkk (Motorola Moto G84 5G).
# Copyright (C) 2025-2026 humandroid-2002
# SPDX-License-Identifier: GPL-3.0-only

FDEVICE="bangkk"

# Local ramdisk callbacks run through AERA_LOCAL_CALLBACK_SCRIPT.
if [ "$2" = "--first-call" ] && [ -n "$1" ] && [ -d "$1" ]; then
    _aera_precompress_ramdisk() {
        local ramdisk="$1" upx_bin="" min=32768 dir f sz cb_dir=""
        cb_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)"
        for c in \
            "${AERA_VENDOR_PATH:+$AERA_VENDOR_PATH/tools/upx}" \
            "${ANDROID_BUILD_TOP:+$ANDROID_BUILD_TOP/vendor/recovery/tools/upx}" \
            "$PWD/vendor/recovery/tools/upx" \
            "vendor/recovery/tools/upx" \
            "${cb_dir:+$cb_dir/../../../../vendor/recovery/tools/upx}"; do
            [ -n "$c" ] && [ -x "$c" ] && { upx_bin="$c"; break; }
        done
        if [ ! -x "$upx_bin" ]; then
            echo "-- upx not found, skipping 32 KB threshold pass"
            return 0
        fi

        echo "-- compressing ARM ELF binaries > ${min} bytes (32 KB threshold) with $upx_bin"
        for dir in "$ramdisk/sbin" "$ramdisk/system/bin"; do
            [ -d "$dir" ] || continue
            for f in "$dir"/*; do
                [ -f "$f" ] && [ -x "$f" ] || continue
                sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
                [ "$sz" -gt "$min" ] || continue
                info="$(file "$f" 2>/dev/null)"
                printf '%s\n' "$info" | grep -q "ELF" || continue
                printf '%s\n' "$info" | grep -qiE "ARM|aarch64" || continue
                chmod 0755 "$f"
                b=$(basename "$f")
                if [ "$b" = "recovery" ]; then
                    # The recovery binary needs libdmctl.so as a DT_NEEDED
                    # shim (AERA_USE_DMCTL), which upx would otherwise strip.
                    if "$upx_bin" -t "$f" >/dev/null 2>&1; then
                        "$upx_bin" -d "$f" >/dev/null 2>&1 || continue
                        echo "-- decompressed $b for DT_NEEDED patch"
                    fi
                    patchelf_bin="$(command -v patchelf 2>/dev/null)"
                    if [ -z "$patchelf_bin" ] && [ -x "$ramdisk/sbin/patchelf" ]; then
                        patchelf_bin="$ramdisk/sbin/patchelf"
                        echo "-- using bundled patchelf from ramdisk"
                    fi
                    if [ -z "$patchelf_bin" ]; then
                        echo "-- WARNING: patchelf missing; leaving $b uncompressed"
                        continue
                    fi
                    if ! "$patchelf_bin" --print-needed "$f" 2>/dev/null | grep -qx 'libdmctl.so'; then
                        "$patchelf_bin" --add-needed libdmctl.so "$f" && \
                            echo "-- linked libdmctl.so as first DT_NEEDED of $b"
                    fi
                    "$upx_bin" --lzma "$f" >/dev/null 2>&1 && echo "-- compressed $b (shim as DT_NEEDED)"
                    continue
                fi
                if "$upx_bin" --lzma "$f" >/dev/null 2>&1; then
                    echo "-- compressing $b"
                elif "$upx_bin" -t "$f" >/dev/null 2>&1; then
                    echo "-- $b already packed"
                fi
            done
        done
    }

    _aera_prune_fonts() {
        local ramdisk="$1" font_dir="$1/twres/fonts" f
        [ -d "$font_dir" ] || return 0
        for f in "$font_dir"/*; do
            [ -f "$f" ] || continue
            [ "$(basename "$f")" = "Roboto-Regular.ttf" ] && continue
            rm -f "$f"
        done
    }

    _fox_remove_fastbootd() {
        local ramdisk="$1"
        rm -f "$ramdisk/system/bin/fastbootd" \
              "$ramdisk/system/lib64/android.hardware.fastboot@1.0.so" \
              "$ramdisk/system/lib64/android.hardware.fastboot@1.1.so" \
              "$ramdisk/system/lib64/fastboot-V1-ndk.so" \
              "$ramdisk/res/images/fastbootd.png"
    }

    # ICU libs are bind-mounted from the cache by /system/bin/mount_rom_icu.sh.
    _aera_remove_icu() {
        local ramdisk="$1"
        rm -f "$ramdisk/system/lib64/libandroidicu.so" \
              "$ramdisk/system/lib64/libicui18n.so" \
              "$ramdisk/system/lib64/libicuuc.so"
    }

    # wpa_supplicant are provided by /system/bin/runatboot.sh 
    # tzdata are provided by         /system/bin/mount_rom_icu.sh 
    _aera_remove_tools() {
        rm -f "$ramdisk/system/usr/share/zoneinfo/tzdata" \
              "$ramdisk/sbin/gnused" \
              "$ramdisk/sbin/gnutar" \  
    }

    _fox_remove_fastbootd "$1"
    _aera_prune_fonts "$1"
    _fox_remove_tools "$1"
    _aera_remove_icu "$1"
    _aera_precompress_ramdisk "$1"
    return 0 2>/dev/null || exit 0
fi
[ "$2" = "--last-call" ] && { return 0 2>/dev/null || exit 0; }

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

clone_if_missing https://github.com/LineageOS/android_hardware_qcom_bootctrl.git lineage-19.1-caf hardware/qcom-caf/bootctrl

# Only export bangkk settings when this file is the one being sourced.
_aera_src=""
if [ -n "$ZSH_VERSION" ]; then
    _aera_src="${(%):-%x}"
elif [ -n "$BASH_VERSION" ]; then
    _aera_src="${BASH_SOURCE[0]}"
else
    _aera_src="$0"
fi

case "$_aera_src" in
    device/motorola/$FDEVICE/*|*/device/motorola/$FDEVICE/*) AERA_BUILD_DEVICE="$FDEVICE" ;;
esac
[ "$1" = "$FDEVICE" ] && AERA_BUILD_DEVICE="$FDEVICE"
unset _aera_src

if [ "$AERA_BUILD_DEVICE" = "$FDEVICE" ]; then

	# A/B, virtual A/B, recovery
	export AERA_AB_DEVICE=1
	export AERA_VIRTUAL_AB_DEVICE=1
	export AERA_RECOVERY_SYSTEM_PARTITION="/dev/block/mapper/system"
	export AERA_RECOVERY_VENDOR_PARTITION="/dev/block/mapper/vendor"

	# Compression Binaries & Tools
	export AERA_USE_TAR_BINARY=1
	export AERA_USE_LZ4_BINARY=1
	export AERA_USE_SED_BINARY=1
	export AERA_USE_XZ_UTILS=1
	export AERA_USE_ZSTD_BINARY=1
	export AERA_REMOVE_AAPT=1
	export AERA_USE_BUSYBOX_BINARY=1
	export AERA_USE_GREP_BINARY=1
	export AERA_USE_DATE_BINARY=1
	export AERA_USE_FSCK_EROFS_BINARY=1
	export AERA_REPLACE_TOOLBOX_GETPROP=1

	# patchelf
	export AERA_USE_PATCHELF_BINARY=1
	# Disabled due recovery size issue
	export AERA_USE_UPDATED_MAGISKBOOT=0

	# Release identity
	export AERA_PRODUCT_PREFIX=AERA
	export AERA_BUILD_TYPE=Beta
	export AERA_BUILD_STATUS=Unofficial

	export LC_ALL="C"
	export ALLOW_MISSING_DEPENDENCIES=true

	# ccache
	export USE_CCACHE=1
	export CCACHE_EXEC="/usr/bin/ccache"
	export CCACHE_MAXSIZE="50G"
	export CCACHE_DIR="/home/yama/.ccache"
	export TMPDIR="/home/yama/.tmp"

    if [ $USE_CCACHE = 1 ] && [ ! -d ${CCACHE_DIR} ];
     then
       echo "W: CCACHE Directory/Partition is not mounted at \"${CCACHE_DIR}\""
       echo "W: Please edit the CCACHE_DIR build variable or mount the directory."
    fi

    # Local callback registration
    _aera_vendorsetup_src="${BASH_SOURCE[0]:-$0}"
    if [ -n "$_aera_vendorsetup_src" ] && [ -f "$_aera_vendorsetup_src" ]; then
        export AERA_LOCAL_CALLBACK_SCRIPT="$(cd "$(dirname "$_aera_vendorsetup_src")" && pwd)/$(basename "$_aera_vendorsetup_src")"
    elif [ -f "device/motorola/${FDEVICE}/vendorsetup.sh" ]; then
        export AERA_LOCAL_CALLBACK_SCRIPT="$(pwd)/device/motorola/${FDEVICE}/vendorsetup.sh"
    fi
    unset _aera_vendorsetup_src
fi
