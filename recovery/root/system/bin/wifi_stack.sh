#!/system/bin/sh

LOG="/tmp/recovery.log"

log() {
    echo "[OF-WIFI] $1" >> "$LOG"
}

wait_prop() {
    key="$1"
    value="$2"
    timeout="$3"
    i=0
    while [ "$(getprop "$key")" != "$value" ] && [ "$i" -lt "$timeout" ]; do
        sleep 1
        i=$((i + 1))
    done
}

wait_prop init.svc.vendor.qrtr-ns running 20

# tftp_server serves the modem's RFS requests from /vendor/rfs/msm/mpss and
# resolves "readonly/..." against the host root. Without this tree wlan_pd
# cannot fetch wlanmdsp.mbn and never boots. Create it before CNSS starts;
# init's mkdir builtin cannot create the parent directories at on boot.
mkdir -p /vendor/rfs/msm/mpss
ln -sfn / /vendor/rfs/msm/mpss/readonly
log "RFS tree ready"

# The QMI stack must not start before the ADSP has finished booting.
i=0
adsp_online=0
while [ "$i" -lt 30 ]; do
    for d in /sys/bus/msm_subsys/devices/*/; do
        [ "$(cat "$d/name" 2>/dev/null)" = "adsp" ] || continue
        [ "$(cat "$d/state" 2>/dev/null)" = "ONLINE" ] && adsp_online=1
    done
    [ "$adsp_online" = "1" ] && break
    sleep 1
    i=$((i + 1))
done
log "ADSP online=$adsp_online after ${i}s"

setprop ctl.start vendor.per_mgr
wait_prop init.svc.vendor.per_mgr running 10

# per_proxy is started by the init trigger once per_mgr is running.
wait_prop init.svc.vendor.per_proxy running 10

setprop ctl.start cnss-daemon
