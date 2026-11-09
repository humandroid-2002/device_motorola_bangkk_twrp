#!/system/bin/sh

# Start cnss-daemon with its user socket on a private tmpfs.
#
# The daemon binds /data/vendor/wifi/sockets/cnss_user_server and never
# unlinks it. If the recovery dies without stopping the service, that stale
# root-owned socket makes the normal system's cnss-daemon fail with
# "Address already in use" and crash-loop. A tmpfs inside the service's
# private mount namespace keeps the socket out of persistent storage.

LOG="/tmp/recovery.log"
SOCK_DIR="/data/vendor/wifi/sockets"

log() {
    echo "[OF-CNSS] $1" >> "$LOG"
}

mkdir -p "$SOCK_DIR" 2>/dev/null
if mount -t tmpfs -o mode=0770 tmpfs "$SOCK_DIR" 2>>"$LOG"; then
    chown wifi:wifi "$SOCK_DIR" 2>/dev/null
    log "user socket directory is tmpfs"
else
    log "WARNING: cannot mount tmpfs over $SOCK_DIR"
fi

exec /system/bin/cnss-daemon "$@"
