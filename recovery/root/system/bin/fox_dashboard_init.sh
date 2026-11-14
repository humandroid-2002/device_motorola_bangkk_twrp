#!/system/bin/sh

# This script initializes the missing OrangeFox dashboard stamp
# so "Flash current OrangeFox" never fails because
# /ramdisk-files.txt include system/etc/fox/.dashboard.stamp

LOGMSG() {
    echo "I:fix_missing_ramdisk_file: $1" >> /tmp/recovery.log
}

if [ -d /system/etc/fox/dashboard ] && [ ! -e /system/etc/fox/.dashboard.stamp ]; then
    touch /system/etc/fox/.dashboard.stamp
    LOGMSG "created /system/etc/fox/.dashboard.stamp"
fi

exit 0
