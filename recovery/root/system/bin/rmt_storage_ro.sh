#!/system/bin/sh

# Serve the modem EFS partitions to rmt_storage from RAM copies.
#
# The kernel on this device cannot read loop devices that are backed by a
# block device (reads fail with EIO), and running rmt_storage against the
# real EFS partitions can permanently corrupt calibration data. So the
# partitions are copied to tmpfs and exposed through read-write loop devices
# in a private mount namespace: the modem sees writable EFS, but every write
# stays in RAM and is lost on reboot.

LOG="/tmp/recovery.log"
BOOTDEVICE_DIR="/dev/block/bootdevice/by-name"
SLOT="$(getprop ro.boot.slot_suffix)"
EFS_DIR="/tmp/efs_rmtfs"

log() {
    echo "[OF-RMT] $1" >> "$LOG"
}

abort() {
    log "ERROR: $1"
    exit 1
}

# Never touch the global by-name directory. init gives services with
# "namespace mnt" a private namespace with / recursively made a slave; if
# that did not happen, mounting here would hide every partition from TWRP.
self_ns="$(readlink /proc/self/ns/mnt)"
init_ns="$(readlink /proc/1/ns/mnt)"
log "mount namespace self=$self_ns init=$init_ns"
[ -n "$self_ns" ] && [ "$self_ns" != "$init_ns" ] \
    || abort "not running in a private mount namespace"

i=0
while [ ! -d "$BOOTDEVICE_DIR" ] && [ "$i" -lt 10 ]; do
    sleep 1
    i=$((i + 1))
done
[ -d "$BOOTDEVICE_DIR" ] || abort "no $BOOTDEVICE_DIR"
[ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237 2>/dev/null

i=0
while [ ! -e /dev/uio0 ] && [ "$i" -lt 10 ]; do
    sleep 1
    i=$((i + 1))
done
if [ ! -e /dev/uio0 ] && [ -r /sys/class/uio/uio0/dev ]; then
    dev="$(cat /sys/class/uio/uio0/dev)"
    mknod /dev/uio0 c "${dev%:*}" "${dev#*:}" 2>/dev/null \
        && chmod 660 /dev/uio0 2>/dev/null \
        && log "created /dev/uio0 ($dev)"
fi
[ -e /dev/uio0 ] || log "WARNING: /dev/uio0 not available"

i=0
while [ "$(getprop init.svc.vendor.qrtr-ns)" != "running" ] && [ "$i" -lt 10 ]; do
    sleep 1
    i=$((i + 1))
done
[ "$(getprop init.svc.vendor.qrtr-ns)" = "running" ] || log "WARNING: qrtr-ns not running"

rm -rf "$EFS_DIR"
mkdir -p "$EFS_DIR" || abort "cannot create $EFS_DIR"
chmod 700 "$EFS_DIR"
mount -t tmpfs -o mode=0700 tmpfs "$EFS_DIR" 2>>"$LOG" \
    || log "WARNING: tmpfs mount failed, EFS copies stay on /tmp"

copy_part() {
    name="$1"
    src="$BOOTDEVICE_DIR/$name"
    dst="$EFS_DIR/$name.img"

    [ -e "$src" ] || abort "missing partition $src"
    rm -f "$dst"
    log "copying $name..."
    dd if="$src" of="$dst" bs=1M 2>>"$LOG" || abort "copy of $name failed"
    bytes="$(wc -c < "$dst" 2>/dev/null)"
    [ -n "$bytes" ] && [ "$bytes" -gt 0 ] || abort "empty copy of $name"
    log "copied $name ($bytes bytes)"
}

attach_loop() {
    img="$1"
    loop="$(losetup -fs "$img" 2>>"$LOG")"
    [ -n "$loop" ] || abort "cannot attach $img to a loop device"
    echo "$loop"
}

FSG_NAME="fsg${SLOT}"
[ -e "$BOOTDEVICE_DIR/$FSG_NAME" ] || FSG_NAME="fsg"

copy_part modemst1
copy_part modemst2
copy_part "$FSG_NAME"
copy_part fsc

L_MODEMST1="$(attach_loop "$EFS_DIR/modemst1.img")" || exit 1
L_MODEMST2="$(attach_loop "$EFS_DIR/modemst2.img")" || exit 1
L_FSG="$(attach_loop "$EFS_DIR/$FSG_NAME.img")" || exit 1
L_FSC="$(attach_loop "$EFS_DIR/fsc.img")" || exit 1

VIRTUAL_DIR="$EFS_DIR/by-name"
mkdir -p "$VIRTUAL_DIR" || abort "cannot create $VIRTUAL_DIR"

ln -sfn "$L_MODEMST1" "$VIRTUAL_DIR/modemst1"
ln -sfn "$L_MODEMST2" "$VIRTUAL_DIR/modemst2"
ln -sfn "$L_FSG" "$VIRTUAL_DIR/fsg"
[ -n "$SLOT" ] && ln -sfn "$L_FSG" "$VIRTUAL_DIR/fsg${SLOT}"
ln -sfn "$L_FSC" "$VIRTUAL_DIR/fsc"

mount -o bind "$VIRTUAL_DIR" "$BOOTDEVICE_DIR" || abort "bind mount failed"

for part in modemst1 modemst2 fsg "fsg${SLOT}" fsc; do
    real="$(readlink -f "$BOOTDEVICE_DIR/$part" 2>/dev/null)"
    case "$real" in
        /dev/block/loop*) ;;
        *) abort "$part is not backed by a loop device" ;;
    esac
done

detach_loops() {
    losetup -d "$L_MODEMST1" 2>/dev/null
    losetup -d "$L_MODEMST2" 2>/dev/null
    losetup -d "$L_FSG" 2>/dev/null
    losetup -d "$L_FSC" 2>/dev/null
}

log "EFS partitions mapped to RAM-backed loops, starting rmt_storage"
/system/bin/rmt_storage "$@" &
pid=$!
log "rmt_storage running as pid $pid"

term_handler() {
    log "stopping rmt_storage"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    detach_loops
    exit 0
}
trap 'term_handler' TERM INT

wait "$pid"
rc=$?
log "rmt_storage exited rc=$rc"
detach_loops
exit "$rc"
