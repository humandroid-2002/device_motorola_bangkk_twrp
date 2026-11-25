#!/system/bin/sh

export PATH=/system/bin:/sbin:/vendor/bin

LOG=/tmp/recovery.log
TAG=bringup_gpu
ROOT=/tmp/gpu_bringup
ROMVEN="$ROOT/vendor"
ROMSYS="$ROOT/system"
MARKER="$ROOT/.started"

log() {
    echo "I:$TAG: $1" >> "$LOG" 2>/dev/null
}

loge() {
    echo "E:$TAG: $1" >> "$LOG" 2>/dev/null
}

mkdir -p "$ROOT" "$ROMVEN" "$ROMSYS" /vendor/lib64/egl /vendor/lib64 /system/lib64 2>/dev/null

[ -f "$MARKER" ] && exit 0
: > "$MARKER" 2>/dev/null

SLOT="$(getprop ro.boot.slot_suffix 2>/dev/null)"
[ -n "$SLOT" ] || SLOT="_a"

wait_path() {
    n=0
    while [ ! -e "$1" ] && [ "$n" -lt 25 ]; do
        sleep 0.2
        n=$((n + 1))
    done
    [ -e "$1" ]
}

mount_vendor() {
    mountpoint -q "$ROMVEN" && return 0
    for dev in \
        "/dev/block/by-name/vendor${SLOT}" \
        "/dev/block/bootdevice/by-name/vendor${SLOT}" \
        "/dev/block/mapper/vendor${SLOT}" \
        "/dev/block/by-name/vendor" \
        "/dev/block/bootdevice/by-name/vendor" \
        "/dev/block/mapper/vendor"
    do
        [ -e "$dev" ] || continue
        if mount -o ro "$dev" "$ROMVEN" >> "$LOG" 2>&1; then
            log "mounted ROM vendor from $dev"
            return 0
        fi
    done
    loge "cannot mount ROM vendor"
    return 1
}

mount_system() {
    mountpoint -q "$ROMSYS" && return 0
    SUPER=/dev/block/by-name/super
    [ -e "$SUPER" ] || SUPER=/dev/block/bootdevice/by-name/super
    [ -e "$SUPER" ] || {
        loge "super partition not found"
        return 1
    }
    for name in "system${SLOT}" system_a system_b system; do
        out="$(/system/bin/lptools map "$name" 2>&1)"
        dev="$(printf '%s\n' "$out" | sed -n 's/.* at \(\/dev\/block\/dm-[0-9][0-9]*\).*/\1/p')"
        [ -n "$dev" ] || dev="/dev/block/mapper/$name"
        [ -e "$dev" ] || continue
        if mount -o ro "$dev" "$ROMSYS" >> "$LOG" 2>&1; then
            log "mounted ROM system from $dev"
            return 0
        fi
    done
    loge "cannot mount ROM system"
    return 1
}

GPU_CACHE="$ROOT/cache"

bind_file() {
    src="$1"
    dst="$2"
    [ -f "$src" ] || return 1
    mkdir -p "$GPU_CACHE" 2>/dev/null || return 1
    cached="$GPU_CACHE/${dst##*/}"
    if [ ! -s "$cached" ]; then
        rm -f "$cached.tmp" 2>/dev/null || true
        cp -L "$src" "$cached.tmp" >> "$LOG" 2>&1 || return 1
        mv -f "$cached.tmp" "$cached" >> "$LOG" 2>&1 || return 1
    fi
    if [ ! -e "$dst" ]; then
        touch "$dst" 2>/dev/null || return 1
    fi
    mountpoint -q "$dst" && return 0
    mount -o bind "$cached" "$dst" >> "$LOG" 2>&1 && return 0
    return 1
}

release_staging() {
    umount "$ROMVEN" >> "$LOG" 2>&1 || umount -l "$ROMVEN" >> "$LOG" 2>&1 || true
    umount "$ROMSYS" >> "$LOG" 2>&1 || umount -l "$ROMSYS" >> "$LOG" 2>&1 || true
}

stage_egl() {
    failed=0
    for lib in libEGL_adreno.so libGLESv2_adreno.so eglSubDriverAndroid.so; do
        if bind_file "$ROMVEN/lib64/egl/$lib" "/vendor/lib64/egl/$lib"; then
            log "bound egl/$lib"
        else
            loge "missing egl/$lib"
            failed=1
        fi
    done
    for lib in libgsl.so libadreno_utils.so libllvm-glnext.so; do
        if bind_file "$ROMVEN/lib64/$lib" "/vendor/lib64/$lib"; then
            log "bound $lib"
        else
            loge "missing $lib"
            failed=1
        fi
    done
    return $failed
}

stage_nativewindow() {
    base="$ROMSYS"
    [ -d "$base/system/lib64" ] && base="$base/system"
    failed=0
    for lib in libnativewindow.so libui.so libbinder.so libbinder_ndk.so libutils.so libc++.so android.hardware.graphics.common@1.1.so; do
        if bind_file "$base/lib64/$lib" "/system/lib64/$lib"; then
            log "bound system/$lib"
        else
            loge "missing system/$lib"
            failed=1
        fi
    done
    return $failed
}

stage_allocator() {
    svc="vendor.qti.hardware.display.allocator-service"
    src="$ROMVEN/bin/hw/$svc"
    [ -x "$src" ] || {
        loge "allocator service not found"
        return 1
    }
    mkdir -p /vendor/bin/hw /vendor/lib64/hw 2>/dev/null
    if bind_file "$src" "/vendor/bin/hw/$svc"; then
        log "bound $svc"
    else
        loge "cannot bind $svc"
        return 1
    fi
    for lib in libgrallocutils.so libgralloccore.so libgralloctypes.so libgralloc.qti.so \
        libqdMetaData.so android.hardware.graphics.allocator@4.0.so \
        android.hardware.graphics.allocator@2.0.so android.hardware.graphics.allocator-V2-ndk.so \
        android.hardware.graphics.allocator@3.0.so android.hardware.graphics.mapper@4.0.so \
        android.hardware.graphics.mapper@3.0.so android.hardware.graphics.mapper@2.1.so \
        android.hardware.graphics.mapper@2.0.so \
        android.hardware.graphics.common@1.0.so android.hardware.graphics.common@1.2.so \
        android.hardware.graphics.common-V7-ndk.so \
        vendor.qti.hardware.display.allocator@4.0.so \
        vendor.qti.hardware.display.allocator@3.0.so vendor.qti.hardware.display.mapper@4.0.so \
        vendor.qti.hardware.display.mapper@3.0.so vendor.qti.hardware.display.mapper@2.0.so \
        vendor.qti.hardware.display.mapperextensions@1.0.so \
        vendor.qti.hardware.display.mapperextensions@1.1.so \
        vendor.qti.hardware.display.mapperextensions@1.2.so \
        libdisplaydebug.so; do
        bind_file "$ROMVEN/lib64/$lib" "/vendor/lib64/$lib" >> "$LOG" 2>&1 || loge "missing gralloc $lib"
    done
    for lib in android.hardware.graphics.mapper@4.0-impl-qti-display.so \
        android.hardware.graphics.mapper@3.0-impl-qti-display.so gralloc.default.so; do
        bind_file "$ROMVEN/lib64/hw/$lib" "/vendor/lib64/hw/$lib" >> "$LOG" 2>&1 || loge "missing gralloc hw $lib"
    done
    return 0
}

start_allocator() {
    [ -x /vendor/bin/hw/vendor.qti.hardware.display.allocator-service ] || return 1
    killall vendor.qti.hardware.display.allocator-service 2>/dev/null || true
    sleep 1
    LD_LIBRARY_PATH=/vendor/lib64:/vendor/lib64/hw:/system/lib64 \
        setsid /vendor/bin/hw/vendor.qti.hardware.display.allocator-service \
        >/dev/null 2>&1 </dev/null &
    sleep 2
    if ps -A 2>/dev/null | grep -q "vendor.qti.hardware.display.allocator-service"; then
        log "allocator service registered"
        return 0
    fi
    loge "allocator service failed to register"
    return 1
}

if ! wait_path /dev/kgsl-3d0; then
    loge "KGSL device node unavailable"
fi

if ! mount_vendor; then
    exit 1
fi

egl_status=0
stage_egl || egl_status=1

if mount_system && stage_nativewindow; then
    log "native-window runtime staged"
else
    loge "native-window runtime unavailable"
fi

if stage_allocator; then
    start_allocator || loge "allocator service failed to start"
fi

if [ "$egl_status" -eq 0 ]; then
    log "Adreno EGL/GLES staged; GPU renderer can initialize"
else
    loge "GPU staging incomplete; AERA will fall back to software rendering"
fi

release_staging

exit 0
