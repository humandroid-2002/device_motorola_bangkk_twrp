#!/system/bin/sh

export PATH=/system/bin:/sbin:/vendor/bin

LOG=/tmp/recovery.log
TAG=bringup_audio
ROOT=/tmp/audio_bringup
MARKER="$ROOT/.started"
DONE="$ROOT/.done"

log() {
    echo "I:$TAG: $1" >> "$LOG" 2>/dev/null
}

loge() {
    echo "E:$TAG: $1" >> "$LOG" 2>/dev/null
}

mkdir -p "$ROOT" /vendor/lib64 2>/dev/null

[ -f "$MARKER" ] && exit 0
: > "$MARKER" 2>/dev/null

wait_path() {
    n=0
    while [ ! -e "$1" ] && [ "$n" -lt "${2:-25}" ]; do
        sleep 0.2
        n=$((n + 1))
    done
    [ -e "$1" ]
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

# The boot_adsp node is created by adsp_loader_dlkm and can appear after this
# service starts. Retry without blocking init/UI: the write happens as soon as
# the node exists, so ADSP comes online early enough for WLAN too.
n=0
booted=0
while [ "$n" -lt 150 ]; do
    if [ -e /sys/kernel/boot_adsp/boot ] && \
        printf '1' > /sys/kernel/boot_adsp/boot 2>/dev/null; then
        log "ADSP firmware boot requested (retry $n)"
        booted=1
        break
    fi
    sleep 0.2
    n=$((n + 1))
done
[ "$booted" -eq 1 ] || loge "ADSP boot control unavailable"

if [ ! -f /firmware/image/adsp.mdt ] &&
    [ ! -f /vendor/firmware_mnt/image/adsp.mdt ]; then
    loge "ADSP firmware images not mounted under /firmware/image"
fi

if [ ! -f /vendor/firmware/aw87xxx_acf.bin ]; then
    loge "aw87xxx firmware missing from /vendor/firmware"
fi

# libtinyalsa.so is built into the recovery ramdisk; no ROM staging needed.
if [ ! -f /vendor/lib64/libtinyalsa.so ]; then
    loge "libtinyalsa.so missing from ramdisk"
fi

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
