#!/system/bin/sh

CONFIG="${FOX_NAS_CONFIG:-/data/media/0/Fox/nas/rclone.conf}"
REMOTE="${FOX_NAS_REMOTE:-nas}"
REMOTE_PATH="${FOX_NAS_REMOTE_PATH:-}"
MOUNT="${FOX_NAS_MOUNT:-/mnt/nas}"
LOG_DIR="/tmp/of_nas"
LOG="$LOG_DIR/nas_mount.log"
PATH="/system/bin:/sbin:/vendor/bin:/system/xbin:$PATH"
LD_LIBRARY_PATH="/system/lib64:/vendor/lib64:/sbin"
HOME="$LOG_DIR"
export PATH LD_LIBRARY_PATH HOME

mkdir -p "$LOG_DIR" "$MOUNT"
exec >>"$LOG" 2>&1

i=0
while [ "$i" -lt 300 ]; do
    [ -f "$CONFIG" ] && break
    sleep 1
    i=$((i + 1))
done

if [ ! -f "$CONFIG" ]; then
    echo "NAS config not found: $CONFIG"
    exit 0
fi

i=0
while [ "$i" -lt 120 ]; do
    ip="$(getprop dhcp.wlan0.ipaddress 2>/dev/null)"
    [ -z "$ip" ] && ip="$(getprop dhcp.eth0.ipaddress 2>/dev/null)"
    [ -n "$ip" ] && [ "$ip" != "0.0.0.0" ] && break
    sleep 1
    i=$((i + 1))
done

if [ ! -x /system/bin/rclone ] || [ ! -x /system/bin/fusermount3 ]; then
    echo "rclone or fusermount3 is missing"
    exit 0
fi

if grep -q " $MOUNT " /proc/mounts; then
    echo "NAS already mounted at $MOUNT"
    exit 0
fi

if [ -d /data/media/0 ]; then
    CACHE_DIR="/data/media/0/Fox/NASCache"
else
    CACHE_DIR="$LOG_DIR/cache"
fi
mkdir -p "$CACHE_DIR"

if [ -n "$REMOTE_PATH" ]; then
    REMOTE_SPEC="$REMOTE:$REMOTE_PATH"
else
    REMOTE_SPEC="$REMOTE:"
fi

echo "Mounting $REMOTE_SPEC at $MOUNT"
exec /system/bin/rclone mount "$REMOTE_SPEC" "$MOUNT" \
    --config "$CONFIG" \
    --uid 0 \
    --gid 0 \
    --umask 000 \
    --vfs-cache-mode writes \
    --cache-dir "$CACHE_DIR" \
    --vfs-cache-max-size 25G \
    --vfs-cache-min-free-space 1G \
    --vfs-write-back 1s \
    --vfs-cache-max-age 30m \
    --vfs-cache-poll-interval 10s \
    --dir-cache-time 5m \
    --attr-timeout 1s \
    --buffer-size 64M \
    --log-file "$LOG" \
    --log-level INFO
