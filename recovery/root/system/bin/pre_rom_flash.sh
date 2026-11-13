#!/system/bin/sh

# Copyright (C) 2026 OrangeFox Recovery Project
# SPDX-License-Identifier: GPL-3.0-only

LOGMSG() {
    echo "I:$1" >> /tmp/recovery.log;
}

# Clean stale Virtual A/B snapshot state before flashing a ROM
LOGMSG "Cleaning stale Virtual A/B snapshots..."

/system/bin/bootctl set-snapshot-merge-status cancelled >/dev/null 2>&1 || true
/system/bin/lptools clear-cow >/dev/null 2>&1 || true
for _cow in product_a-cow product_b-cow system_a-cow system_b-cow; do
    /system/bin/dmctl delete "$_cow" >/dev/null 2>&1 || true
done

# Wipe stale Virtual A/B state on /metadata
LOGMSG "Wiping Virtual A/B state on /metadata..."

if mountpoint -q /metadata 2>/dev/null; then
    METADATA_MOUNTED=1
else
    METADATA_MOUNTED=0
    mount -t f2fs /dev/block/bootdevice/by-name/metadata /metadata 2>/dev/null || \
    mount -t ext4 /dev/block/bootdevice/by-name/metadata /metadata 2>/dev/null
fi

if mountpoint -q /metadata 2>/dev/null; then
    rm -rf /metadata/ota/* 2>/dev/null
    rm -rf /metadata/gsi/ota/* 2>/dev/null
    rm -f /metadata/boot_logcat.txt 2>/dev/null
    mkdir -p /metadata/ota/snapshots 2>/dev/null
    mkdir -p /metadata/gsi/ota 2>/dev/null
    chmod -R 0750 /metadata/ota 2>/dev/null
    chmod -R 0750 /metadata/gsi/ota 2>/dev/null
    sync
    umount /metadata 2>/dev/null || true
fi

/system/bin/bootctl set-snapshot-merge-status none >/dev/null 2>&1 || true

# Ensure /data/gsi/ota/ exists for COW image
LOGMSG "Ensuring /data is mounted for COW image overflow..."

DATA_MOUNTED=false
if mountpoint -q /data 2>/dev/null; then
    DATA_MOUNTED=true
else
    USERDATA_DEV=""
    for candidate in /dev/block/bootdevice/by-name/userdata /dev/block/by-name/userdata; do
        if [ -e "$candidate" ]; then
            USERDATA_DEV="$candidate"
            break
        fi
    done

    if [ -n "$USERDATA_DEV" ]; then
        if mount -t f2fs "$USERDATA_DEV" /data 2>/dev/null; then
            DATA_MOUNTED=true
        elif mount -t ext4 "$USERDATA_DEV" /data 2>/dev/null; then
            DATA_MOUNTED=true
        fi
    fi
fi

if [ "$DATA_MOUNTED" = "true" ]; then
    mkdir -p /data/gsi/ota 2>/dev/null
    chmod 0750 /data/gsi/ota 2>/dev/null
fi

do_sysfs_tune() {
    LOGMSG "Tuning sysfs parameters for performance..."

    # Lock every CPU to maximum frequency.
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        [ -d "$cpu" ] || continue
        [ -w "$cpu/cpufreq/scaling_governor" ] && echo performance > "$cpu/cpufreq/scaling_governor" 2>/dev/null
        if [ -r "$cpu/cpufreq/cpuinfo_max_freq" ]; then
            cat "$cpu/cpufreq/cpuinfo_max_freq" > "$cpu/cpufreq/scaling_min_freq" 2>/dev/null
            cat "$cpu/cpufreq/cpuinfo_max_freq" > "$cpu/cpufreq/scaling_max_freq" 2>/dev/null
        fi
    done

    # Disable CPU core control so no core is parked.
    for cc in /sys/devices/system/cpu/cpu*/core_ctl/enable; do
        [ -w "$cc" ] && echo 0 > "$cc" 2>/dev/null
    done

    # cpuset: allow every task on every CPU.
    for cs in /dev/cpuset/*/cpus; do
        [ -w "$cs" ] && echo 0-7 > "$cs" 2>/dev/null
    done

    # Disable UFS power-saving features.
    for ufs in /sys/bus/platform/devices/*.ufshc; do
        [ -d "$ufs" ] || continue
        echo 0 > "$ufs/auto_hibern8" 2>/dev/null
        echo 0 > "$ufs/clkgate_enable" 2>/dev/null
    done

    # I/O: fastest scheduler and large read-ahead.
    for q in /sys/block/*/queue; do
        [ -d "$q" ] || continue
        if grep -qw none "$q/scheduler" 2>/dev/null; then
            echo none > "$q/scheduler" 2>/dev/null
        elif grep -qw mq-deadline "$q/scheduler" 2>/dev/null; then
            echo mq-deadline > "$q/scheduler" 2>/dev/null
        fi
        echo 4096 > "$q/read_ahead_kb" 2>/dev/null
        echo 0 > "$q/rotational" 2>/dev/null
        echo 1024 > "$q/nr_requests" 2>/dev/null
        echo 0 > "$q/iostats" 2>/dev/null
    done

    # Scheduler and memory tuning for burst throughput.
    echo 0 > /proc/sys/kernel/sched_boost 2>/dev/null
    echo 0 > /proc/sys/kernel/sched_child_runs_first 2>/dev/null
    echo 1 > /proc/sys/vm/swappiness 2>/dev/null
    echo 5 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null
    echo 1 > /proc/sys/vm/dirty_background_ratio 2>/dev/null
    echo 5 > /proc/sys/vm/dirty_ratio 2>/dev/null
    echo 1 > /proc/sys/vm/kswapd_threads 2>/dev/null

    # Disable deep sleep LPM.
    echo N > /sys/module/lpm_levels/parameters/sleep_disabled 2>/dev/null

    # Disable BCL (battery current limiting) if present.
    for bcl in /sys/module/msm_bcl*/parameters/disable  /sys/devices/virtual/thermal/*/mode; do
        [ -w "$bcl" ] && echo 0 > "$bcl" 2>/dev/null
    done

    resetprop twrp.temp.cpu_governor performance
}

do_sysfs_tune;
sync;
exit 0
