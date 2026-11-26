#!/system/bin/sh

export PATH=/system/bin:/sbin:/vendor/bin

LOG=/tmp/recovery.log
TAG=bringup_audio
ROOT=/tmp/audio_bringup
ROMVEN="$ROOT/vendor"
CACHE="$ROOT/cache"
MARKER="$ROOT/.started"
DONE="$ROOT/.done"

log() {
    echo "I:$TAG: $1" >> "$LOG" 2>/dev/null
}

loge() {
    echo "E:$TAG: $1" >> "$LOG" 2>/dev/null
}

mkdir -p "$ROOT" "$ROMVEN" "$CACHE" /vendor/lib64 2>/dev/null

[ -f "$MARKER" ] && exit 0
: > "$MARKER" 2>/dev/null

SLOT="$(getprop ro.boot.slot_suffix 2>/dev/null)"
[ -n "$SLOT" ] || SLOT="_a"

wait_path() {
    n=0
    while [ ! -e "$1" ] && [ "$n" -lt "${2:-25}" ]; do
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
        for fs in erofs ext4; do
            if mount -t "$fs" -o ro "$dev" "$ROMVEN" >> "$LOG" 2>&1; then
                log "mounted ROM vendor from $dev as $fs"
                return 0
            fi
        done
        if mount -o ro "$dev" "$ROMVEN" >> "$LOG" 2>&1; then
            log "mounted ROM vendor from $dev"
            return 0
        fi
    done
    loge "cannot mount ROM vendor"
    return 1
}

bind_file() {
    src="$1"
    dst="$2"
    [ -f "$src" ] || return 1
    cached="$CACHE/${dst##*/}"
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
}

stage_tinyalsa() {
    if bind_file "$ROMVEN/lib64/libtinyalsa.so" \
        "/vendor/lib64/libtinyalsa.so"; then
        log "bound libtinyalsa.so from the installed ROM"
        return 0
    fi
    loge "libtinyalsa.so not found on the installed ROM"
    return 1
}

audio_modules_ready() {
    missing=0
    for mod in q6_dlkm machine_dlkm aw87xxx_dlkm wcd937x_dlkm; do
        if ! grep -q "^$mod " /proc/modules 2>/dev/null; then
            loge "module not loaded: $mod"
            missing=$((missing + 1))
        fi
    done
    [ "$missing" -eq 0 ]
}

card_ready() {
    grep -qE 'aw87xxx|holi' /proc/asound/cards 2>/dev/null || return 1
    for pcm in /dev/snd/pcmC*D*p; do
        [ -e "$pcm" ] && return 0
    done
    return 1
}

wait_card() {
    n=0
    while [ "$n" -lt 100 ]; do
        card_ready && return 0
        sleep 0.2
        n=$((n + 1))
    done
    return 1
}

if ! wait_path /sys/kernel/boot_adsp/boot 25; then
    loge "ADSP boot control unavailable"
fi

if [ ! -f /firmware/image/adsp.mdt ] &&
    [ ! -f /vendor/firmware_mnt/image/adsp.mdt ]; then
    loge "ADSP firmware images not mounted under /firmware/image"
fi

if [ ! -f /vendor/firmware/aw87xxx_acf.bin ]; then
    loge "aw87xxx firmware missing from /vendor/firmware"
fi

if ! mount_vendor; then
    loge "audio library staging failed"
    exit 1
fi

stage_tinyalsa || true
release_staging

if audio_modules_ready; then
    log "audio kernel modules present"
fi

if wait_card; then
    log "sound card and playback PCM are ready"
else
    loge "sound card did not appear; the bridge will keep retrying"
fi

: > "$DONE" 2>/dev/null
log "audio bringup complete"

exit 0
