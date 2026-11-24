#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 humandroid-2002

export PATH=/system/bin:/sbin:/vendor/bin
ROOT=/romicu
LOG=/tmp/recovery.log
TAG=mount_rom_icu
CACHE_IMG="/firmware/aera_cache.img"
CACHE_MNT="$ROOT/cache"
CACHE_LIBS="$CACHE_MNT/icu/lib64"
ICU_LIBS="libandroidicu.so libicui18n.so libicuuc.so"

mkdir -p "$ROOT"

log() {
    echo "I:$TAG: $1" >> "$ROOT/mount_rom_icu.log" 2>/dev/null
    echo "I:$TAG: $1" >> "$LOG" 2>/dev/null
}

log_err() {
    echo "E:$TAG: $1" >> "$ROOT/mount_rom_icu.log" 2>/dev/null
    echo "E:$TAG: $1" >> "$LOG" 2>/dev/null
}

CACHE_WRITABLE=0

cache_complete() {
    for lib in $ICU_LIBS; do
        [ -f "$CACHE_LIBS/$lib" ] || return 1
    done
    return 0
}

setup_cache() {
    n=0
    while [ ! -d /firmware ] && [ "$n" -lt 10 ]; do
        sleep 1
        n=$((n + 1))
    done

    if [ ! -d /firmware ]; then
        log_err "/firmware not available; ICU cache disabled"
        return 1
    fi

    mkdir -p "$CACHE_MNT"

    if mountpoint -q "$CACHE_MNT"; then
        if ! cache_complete; then
            mount -o remount,rw /firmware >> "$LOG" 2>&1 || log_err "cannot remount /firmware rw"
            mount -o remount,rw "$CACHE_MNT" >> "$LOG" 2>&1 || return 1
            mkdir -p "$CACHE_LIBS" >> "$LOG" 2>&1 || return 1
            CACHE_WRITABLE=1
        fi
        return 0
    fi

    if [ -f "$CACHE_IMG" ]; then
        if mount -o loop,ro "$CACHE_IMG" "$CACHE_MNT" >> "$LOG" 2>&1; then
            if cache_complete; then
                log "mounted ICU cache $CACHE_IMG read-only on $CACHE_MNT"
                return 0
            fi
            umount "$CACHE_MNT" 2>/dev/null || true
        fi
    fi

    mount -o remount,rw /firmware >> "$LOG" 2>&1 || {
        log_err "cannot remount /firmware rw"
        return 1
    }

    if [ ! -f "$CACHE_IMG" ]; then
        if ! truncate -s 8M "$CACHE_IMG" >> "$LOG" 2>&1; then
            dd if=/dev/zero of="$CACHE_IMG" bs=1048576 count=8 >> "$LOG" 2>&1 || {
                log_err "cannot create $CACHE_IMG"
                return 1
            }
        fi
        mkfs.ext4 -F -I 256 "$CACHE_IMG" >> "$LOG" 2>&1 || {
            log_err "cannot format $CACHE_IMG"
            return 1
        }
        log "created 8MB ICU cache image $CACHE_IMG"
    fi

    LOOP="$(losetup -f 2>/dev/null)"
    if [ -n "$LOOP" ] && losetup "$LOOP" "$CACHE_IMG" >> "$LOG" 2>&1 && mount -o rw "$LOOP" "$CACHE_MNT" >> "$LOG" 2>&1; then
        log "mounted ICU cache $CACHE_IMG on $CACHE_MNT via $LOOP"
    elif mount -o loop,rw "$CACHE_IMG" "$CACHE_MNT" >> "$LOG" 2>&1; then
        log "mounted ICU cache $CACHE_IMG on $CACHE_MNT"
    else
        log_err "cannot mount ICU cache"
        return 1
    fi

    mkdir -p "$CACHE_LIBS" >> "$LOG" 2>&1 || return 1
    CACHE_WRITABLE=1
    return 0
}

save_cache_libs() {
    src="$1"
    lib=""

    if [ "$CACHE_WRITABLE" != "1" ]; then
        if ! mountpoint -q "$CACHE_MNT"; then
            setup_cache || return 1
        fi
        mount -o remount,rw /firmware >> "$LOG" 2>&1 || log_err "cannot remount /firmware rw"
        if mountpoint -q "$CACHE_MNT"; then
            mount -o remount,rw "$CACHE_MNT" >> "$LOG" 2>&1 || return 1
        fi
        CACHE_WRITABLE=1
    fi

    [ -d "$CACHE_LIBS" ] || mkdir -p "$CACHE_LIBS" >> "$LOG" 2>&1 || return 1

    for lib in $ICU_LIBS; do
        [ -f "$src/$lib" ] || return 1
    done

    for lib in $ICU_LIBS; do
        cp -f "$src/$lib" "$CACHE_LIBS/$lib" >> "$LOG" 2>&1 || return 1
    done

    log "cached ICU libs in $CACHE_LIBS"
    return 0
}

bind_icu_from() {
    src="$1"
    [ -d "$src" ] || return 1

    for lib in $ICU_LIBS; do
        [ -f "$src/$lib" ] || return 1
    done

    for lib in $ICU_LIBS; do
        dst="/system/lib64/$lib"
        if [ ! -e "$dst" ]; then
            touch "$dst" 2>/dev/null || return 1
        fi
        if ! mount -o bind "$src/$lib" "$dst" 2>/dev/null; then
            mount "$src/$lib" "$dst" 2>/dev/null || return 1
        fi
        log "bind-mounted $lib from $src"
    done

    return 0
}

wait_path() {
    n=0
    while [ ! -e "$1" ] && [ "$n" -lt 30 ]; do
        sleep 1
        n=$((n + 1))
    done
    [ -e "$1" ]
}

detect_fs_type() {
    img="$1"
    magic=$(od -An -tx1 -j 1024 -N 4 "$img" 2>/dev/null | tr -d ' \n')
    case "$magic" in
        e2e1f5e0|e0f5e1e2) echo erofs; return 0 ;;
    esac
    magic=$(od -An -tx1 -j 1080 -N 2 "$img" 2>/dev/null | tr -d ' \n')
    case "$magic" in
        53ef|ef53) echo ext4; return 0 ;;
    esac
    return 1
}

setup_cache || true

for src in "$CACHE_LIBS" /apex/com.android.i18n/lib64 /bootstrap-apex/com.android.i18n/lib64; do
    if bind_icu_from "$src"; then
        if [ "$src" != "$CACHE_LIBS" ]; then
            save_cache_libs "$src" || true
        fi
        log "using ICU libs from $src"
        exit 0
    fi
done

SUPER=/dev/block/by-name/super
if ! wait_path "$SUPER"; then
    SUPER=/dev/block/bootdevice/by-name/super
    if ! wait_path "$SUPER"; then
        log_err "super partition not found"
        exit 1
    fi
fi

SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)
if [ -z "$SLOT" ]; then
    SLOT=$(getprop ro.boot.slot 2>/dev/null)
fi
case "$SLOT" in
    _a|a) SLOT=_a; SLOT_NUM=0; OTHER_SLOT=_b; OTHER_SLOT_NUM=1 ;;
    _b|b) SLOT=_b; SLOT_NUM=1; OTHER_SLOT=_a; OTHER_SLOT_NUM=0 ;;
    *) SLOT=_a; SLOT_NUM=0; OTHER_SLOT=_b; OTHER_SLOT_NUM=1 ;;
esac

mkdir -p "$ROOT/romsystem"

APEX=""
for CANDIDATE in "${SLOT}:${SLOT_NUM}" "${OTHER_SLOT}:${OTHER_SLOT_NUM}"; do
    C_SLOT=${CANDIDATE%%:*}
    C_SLOT_NUM=${CANDIDATE##*:}
    PART="system${C_SLOT}"
    SYS_IMG="$ROOT/${PART}.img"
    rm -f "$SYS_IMG"
    log "lpunpack --slot=$C_SLOT_NUM --partition=$PART $SUPER $ROOT"
    /system/bin/lpunpack --slot="$C_SLOT_NUM" --partition="$PART" "$SUPER" "$ROOT" >/dev/null 2>&1
    if [ -s "$SYS_IMG" ]; then
        FS_TYPE=$(detect_fs_type "$SYS_IMG")
        if [ -z "$FS_TYPE" ]; then
            log_err "unknown filesystem for $PART image from lpunpack"
        elif mount -t "$FS_TYPE" -o ro,loop "$SYS_IMG" "$ROOT/romsystem" 2>/dev/null; then
            log "detected $FS_TYPE and mounted $PART image from lpunpack"
            for candidate in \
                "$ROOT/romsystem/system/apex/com.android.i18n.apex" \
                "$ROOT/romsystem/apex/com.android.i18n.apex"; do
                if [ -f "$candidate" ]; then
                    APEX="$candidate"
                    break
                fi
            done
        else
            log_err "failed to mount $PART image from lpunpack as $FS_TYPE"
        fi
        if [ -z "$APEX" ]; then
            umount "$ROOT/romsystem" 2>/dev/null || true
            log_err "failed to find i18n APEX in $PART image from lpunpack"
        fi
        rm -f "$SYS_IMG"
    else
        log_err "lpunpack failed for $PART"
    fi
    [ -n "$APEX" ] && break
done

if [ -z "$APEX" ]; then
    mkdir -p /dev/block/mapper
    for MAP_NAME in "system$SLOT" system_a system_b system; do
        SYS="/dev/block/mapper/$MAP_NAME"
        DM_DEV=""
        if [ ! -e "$SYS" ]; then
            MAP_OUT=$(/system/bin/lptools map "$MAP_NAME" 2>&1)
            log "lptools map $MAP_NAME: $MAP_OUT"
            DM_DEV=$(printf '%s\n' "$MAP_OUT" | sed -n 's/.* at \(\/dev\/block\/dm-[0-9][0-9]*\).*/\1/p')
        fi

        if [ -e "$SYS" ]; then
            SYS_DEV="$SYS"
        elif [ -n "$DM_DEV" ] && [ -e "$DM_DEV" ]; then
            SYS_DEV="$DM_DEV"
        else
            continue
        fi

        mount -o ro "$SYS_DEV" "$ROOT/romsystem" 2>/dev/null || continue

        for candidate in \
            "$ROOT/romsystem/system/apex/com.android.i18n.apex" \
            "$ROOT/romsystem/apex/com.android.i18n.apex" \
            /system/apex/com.android.i18n.apex; do
            if [ -f "$candidate" ]; then
                APEX="$candidate"
                break
            fi
        done

        [ -n "$APEX" ] && break
        umount "$ROOT/romsystem" 2>/dev/null || true
    done
fi

if [ -z "$APEX" ]; then
    log_err "i18n APEX not found"
    exit 1
fi

mkdir -p "$ROOT/i18n"
rm -f "$ROOT/i18n.img"
if [ -x /system/bin/unzip ]; then
    /system/bin/unzip -p "$APEX" apex_payload.img > "$ROOT/i18n.img" 2>/dev/null
else
    /system/bin/ziptool unzip -p "$APEX" apex_payload.img > "$ROOT/i18n.img" 2>/dev/null
fi

if [ ! -s "$ROOT/i18n.img" ]; then
    log_err "failed to extract apex_payload.img from $APEX"
    exit 1
fi

if ! mount -o ro "$ROOT/i18n.img" "$ROOT/i18n" 2>/dev/null; then
    if ! mount -o ro,loop "$ROOT/i18n.img" "$ROOT/i18n" 2>/dev/null; then
        LOOP=$(losetup -f 2>/dev/null)
        if [ -z "$LOOP" ] || ! losetup "$LOOP" "$ROOT/i18n.img" 2>/dev/null || ! mount -o ro "$LOOP" "$ROOT/i18n" 2>/dev/null; then
            log_err "failed to mount i18n payload"
            exit 1
        fi
    fi
fi

if bind_icu_from "$ROOT/i18n/lib64"; then
    save_cache_libs "$ROOT/i18n/lib64" || true
    log "using ROM i18n APEX at $APEX"
    exit 0
fi

log_err "ICU libraries not found in $APEX"
exit 1
