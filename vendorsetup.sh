#
# OrangeFox build-time variables for bangkk motorola G84.
# Copyright (C) 2025-2026 OrangeFox Recovery Project
# Copyright (C) 2026 humandroid-2002
# SPDX-License-Identifier: GPL-3.0-only

# callback invoked by orangefox vendor scripts
if [ "$2" = "--first-call" ] && [ -n "$1" ] && [ -d "$1" ]; then
    _fox_precompress_ramdisk() {
        local ramdisk="$1" upx_bin="" min=32768 dir f sz cb_dir=""
        cb_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)"
        for c in \
            "${FOX_VENDOR_PATH:+$FOX_VENDOR_PATH/tools/upx}" \
            "${ANDROID_BUILD_TOP:+$ANDROID_BUILD_TOP/vendor/recovery/tools/upx}" \
            "$PWD/vendor/recovery/tools/upx" \
            "vendor/recovery/tools/upx" \
            "${cb_dir:+$cb_dir/../../../../vendor/recovery/tools/upx}"; do
            [ -n "$c" ] && [ -x "$c" ] && { upx_bin="$c"; break; }
        done
        if [ ! -x "$upx_bin" ]; then
            echo "-- upx not found, skipping 64 KB threshold pass"
            return 0
        fi

        echo "-- compressing ARM ELF binaries > ${min} bytes (32 KB threshold) with $upx_bin"
        for dir in "$ramdisk/sbin" "$ramdisk/system/bin"; do
            [ -d "$dir" ] || continue
            for f in "$dir"/*; do
                [ -f "$f" ] && [ -x "$f" ] || continue
                sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
                [ "$sz" -gt "$min" ] || continue
                file "$f" 2>/dev/null | grep -q "ARM" || continue
                file "$f" 2>/dev/null | grep -q "ELF" || continue
                chmod 0755 "$f"
                b=$(basename "$f")
                if "$upx_bin" --lzma "$f" >/dev/null 2>&1; then
                    echo "-- compressing $b"
                elif "$upx_bin" -t "$f" >/dev/null 2>&1; then
                    echo "-- $b already packed"
                fi
            done
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
    _fox_prune_languages() {
        local ramdisk="$1" f
        [ -d "$ramdisk/twres/languages" ] || return 0
        for f in "$ramdisk"/twres/languages/*.xml; do
            [ -f "$f" ] || continue
            case "$(basename "$f")" in
                en.xml|en_*.xml) ;;
                *) rm -f "$f" ;;
            esac
        done
    }
    _fox_prune_fonts() {
        local ramdisk="$1" twres="$1/twres" img="$1/twres/resources/images.xml" cust="$1/twres/pages/customization.xml" f n
        [ -d "$twres" ] || return 0
        echo "-- pruning extra fonts from ramdisk"
        [ -f "$twres/themes/font.xml" ] && sed -i -e 's/GoogleSans/Roboto/g' -e 's/InterDisplay/Roboto/g' -e 's/RobotoSlab/Roboto/g' "$twres/themes/font.xml"
        [ -f "$img" ] && sed -i -e 's/EuclidFlex/Roboto/g' -e 's/GoogleSans/Roboto/g' -e 's/FiraCode/Roboto/g' -e 's/InterDisplay/Roboto/g' -e 's/RobotoSlab/Roboto/g' "$img"
        [ -f "$twres/splash.xml" ] && sed -i -e 's/EuclidFlex/Roboto/g' -e 's/GoogleSans/Roboto/g' -e 's/FiraCode/Roboto/g' -e 's/InterDisplay/Roboto/g' -e 's/RobotoSlab/Roboto/g' "$twres/splash.xml"
        [ -f "$twres/themes/sed/splash.xml" ] && sed -i -e 's/EuclidFlex/Roboto/g' -e 's/InterDisplay/Roboto/g' -e 's/RobotoSlab/Roboto/g' "$twres/themes/sed/splash.xml"
        [ -f "$twres/themes/sed/splash_orig.xml" ] && sed -i -e 's/EuclidFlex/Roboto/g' -e 's/InterDisplay/Roboto/g' -e 's/RobotoSlab/Roboto/g' "$twres/themes/sed/splash_orig.xml"
        [ -f "$twres/pages/recovery.xml" ] && sed -i 's/GoogleSans/Roboto/g' "$twres/pages/recovery.xml"
        [ -f "$cust" ] && sed -i -e 's/GoogleSans/Roboto/g' -e 's/RobotoSlab/Roboto/g' "$cust"

        for f in Amatic Chococooky Exo2-Medium Exo2-Regular EuclidFlex-Medium EuclidFlex-Regular FiraCode-Medium FiraCode-Regular GoogleSans-Medium GoogleSans-Regular InterDisplay-Medium InterDisplay-Regular MILanPro-Medium MILanPro-Regular RobotoSlab; do
            rm -f "$twres/fonts/$f.ttf"
            [ -f "$img" ] && sed -i "/$f.ttf/d" "$img"
        done
        if [ -f "$cust" ]; then
            for n in 2 3 4 5 6 7 8 9; do
                sed -i "/font$n/I,+2 d" "$cust"
            done
        fi
    }
    _fox_remove_fastbootd "$1"
    _fox_prune_languages "$1"
    _fox_precompress_ramdisk "$1"
    _fox_prune_fonts "$1"
    return 0 2>/dev/null || exit 0
fi
[ "$2" = "--last-call" ] && { return 0 2>/dev/null || exit 0; }

# dependecies
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

FDEVICE="bangkk"

fox_get_target_device() {
    local src=""

    if [ -n "$ZSH_VERSION" ]; then
        src="${(%):-%x}"
    elif [ -n "$BASH_VERSION" ]; then
        src="${BASH_SOURCE[0]}"
    else
        src="$0"
    fi

    if echo "$src" | grep -q "$FDEVICE"; then
        FOX_BUILD_DEVICE="$FDEVICE"
    elif [ -n "$BASH_VERSION" ] && set | grep BASH_ARGV | grep -q -w "$FDEVICE"; then
        FOX_BUILD_DEVICE="$FDEVICE"
    elif echo "$* $0" | grep -q -w "$FDEVICE"; then
        FOX_BUILD_DEVICE="$FDEVICE"
    fi
}

if [ -z "$1" -a -z "$FOX_BUILD_DEVICE" ]; then
   fox_get_target_device
fi

if [ "$1" = "$FDEVICE" -o "$FOX_BUILD_DEVICE" = "$FDEVICE" ]; then

	# A/B, virtual A/B, recovery
	# keep va/b disabled for (OTA & ROM)
	export FOX_AB_DEVICE=1
	export FOX_VIRTUAL_AB_DEVICE=0
	export FOX_RECOVERY_SYSTEM_PARTITION="/dev/block/mapper/system"
	export FOX_RECOVERY_VENDOR_PARTITION="/dev/block/mapper/vendor"

	# Compression Binaries & Tools
	export FOX_USE_TAR_BINARY=1
	export FOX_USE_LZ4_BINARY=1
	export FOX_USE_SED_BINARY=1
	export FOX_USE_XZ_UTILS=1
	export FOX_USE_ZSTD_BINARY=1
	export FOX_DELETE_AROMAFM=1
	export FOX_REMOVE_AAPT=1
	export FOX_USE_BUSYBOX_BINARY=1
	export FOX_USE_GREP_BINARY=1
	export FOX_USE_DATE_BINARY=1
	export FOX_USE_FSCK_EROFS_BINARY=1
	export FOX_REPLACE_TOOLBOX_GETPROP=1

	# patchelf
	export FOX_USE_PATCHELF_BINARY=1

	# Wlan web UI
	export export FOX_REMOTE_DASHBOARD=1

	# Fox Settings
	export LC_ALL="C"
	export ALLOW_MISSING_DEPENDENCIES=true
    export FOX_COMPRESS_EXECUTABLES=1
	export FOX_BUILD_TYPE="Beta"
	export FOX_MAINTAINER_PATCH_VERSION="1"

	# ccache
	export USE_CCACHE=1
	export CCACHE_EXEC="/usr/bin/ccache"
	export CCACHE_MAXSIZE="50G"
	export CCACHE_DIR="/mnt/ccache"

    if [ $USE_CCACHE = 1 ] && [ ! -d ${CCACHE_DIR} ];
     then
       echo "W: CCACHE Directory/Partition is not mounted at \"${CCACHE_DIR}\""
       echo "W: Please edit the CCACHE_DIR build variable or mount the directory."
    fi

    # Local callback registration
    _fox_vendorsetup_src="${BASH_SOURCE[0]:-$0}"
    if [ -n "$_fox_vendorsetup_src" ] && [ -f "$_fox_vendorsetup_src" ]; then
        export FOX_LOCAL_CALLBACK_SCRIPT="$(cd "$(dirname "$_fox_vendorsetup_src")" && pwd)/$(basename "$_fox_vendorsetup_src")"
    elif [ -f "device/motorola/${FDEVICE}/vendorsetup.sh" ]; then
        export FOX_LOCAL_CALLBACK_SCRIPT="$(pwd)/device/motorola/${FDEVICE}/vendorsetup.sh"
    fi
    unset _fox_vendorsetup_src
else
	if [ -z "$FOX_BUILD_DEVICE" -a -z "$BASH_SOURCE" ]; then
		echo "I: This script requires bash. Not processing the $FDEVICE $(basename $0)"
	fi
fi

