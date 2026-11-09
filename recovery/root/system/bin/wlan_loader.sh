#!/system/bin/sh

LOG="/tmp/recovery.log"
MODULE="/tmp/lib/modules/wlan.ko"
SLOT="$(getprop ro.boot.slot_suffix)"
MODEM="/dev/block/bootdevice/by-name/modem${SLOT}"

log() {
    echo "[OF-WLAN] $1" >> "$LOG"
}

setprop sys.fox.wlan.driver 0

# The modem partition is ext4 and is mounted by init at /firmware. Mount it
# here too if init lost the race with ueventd.
i=0
while [ ! -e /firmware/image/bdwlan.bin ] && [ "$i" -lt 10 ]; do
    log "firmware not mounted, mounting $MODEM at /firmware"
    mount ext4 "$MODEM" /firmware ro >> "$LOG" 2>&1
    sleep 1
    i=$((i + 1))
done
if [ ! -e /firmware/image/bdwlan.bin ]; then
    log "ERROR: firmware image not available"
fi

i=0
while [ "$(getprop init.svc.cnss-daemon)" != "running" ] && [ "$i" -lt 20 ]; do
    sleep 1
    i=$((i + 1))
done

i=0
while [ ! -f "$MODULE" ] && [ "$i" -lt 30 ]; do
    sleep 1
    i=$((i + 1))
done
if [ ! -f "$MODULE" ]; then
    log "ERROR: $MODULE missing"
    exit 1
fi

if [ ! -d /sys/module/wlan ]; then
    # runatboot.sh loads wlan.ko early; this is only a fallback.
    log "wlan not loaded, insmod fallback"
    insmod "$MODULE" >> "$LOG" 2>&1
else
    log "driver already loaded"
fi

# The host driver stays idle until userspace writes to its state device
# (/dev/wlan, char driver "qcwlanstate"). The stock framework does this
# from the WiFi HAL once the firmware is running: the driver then waits
# for WLAN FW readiness and creates wlan0. ueventd normally provides the
# node; recreate it from /proc/devices if it is missing.
i=0
while [ "$i" -lt 45 ]; do
    dmesg | grep -q "WLAN FW is ready" && break
    sleep 1
    i=$((i + 1))
done
log "firmware ready after ${i}s"

if [ ! -e /dev/wlan ]; then
    major="$(awk '/qcwlanstate/ { print $1 }' /proc/devices)"
    if [ -n "$major" ] && mknod /dev/wlan c "$major" 0; then
        chmod 660 /dev/wlan
        chown wifi:wifi /dev/wlan 2>/dev/null
        log "created /dev/wlan (major $major)"
    else
        log "ERROR: cannot create /dev/wlan"
    fi
fi

attempt=0
while [ ! -e /sys/class/net/wlan0 ] && [ "$attempt" -lt 3 ]; do
    if [ -c /dev/wlan ]; then
        printf ON > /dev/wlan 2>>"$LOG"
        log "sent WLAN ON to /dev/wlan"
    fi
    attempt=$((attempt + 1))
    i=0
    while [ ! -e /sys/class/net/wlan0 ] && [ "$i" -lt 8 ]; do
        sleep 1
        i=$((i + 1))
    done
done

if [ -e /sys/class/net/wlan0 ]; then
    ifconfig wlan0 up >> "$LOG" 2>&1
    setprop sys.fox.wlan.driver 1
    log "wlan0 is up"
else
    log "ERROR: wlan0 was not created"
fi

if [ "$(getprop sys.fox.wlan.supplicant_pending)" = "1" ]; then
    setprop sys.fox.wlan.supplicant_pending 0
    setprop ctl.start wpa_supplicant
    log "starting wpa_supplicant"
fi
