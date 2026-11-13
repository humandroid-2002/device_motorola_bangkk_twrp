#!/system/bin/sh

# Copyright (C) 2026 OrangeFox Recovery Project
# SPDX-License-Identifier: GPL-3.0-only

LOGMSG() {
    echo "I:$1" >> /tmp/recovery.log;
}

# Determine the currently running slot and the slot to activate after the ROM flash.
CURRENT_SLOT=$(/system/bin/bootctl get-current-slot 2>/dev/null)
case "$CURRENT_SLOT" in
    0) NEW_SLOT=1 ;;
    1) NEW_SLOT=0 ;;
    *)
        SUFFIX=$(getprop ro.boot.slot_suffix 2>/dev/null)
        case "$SUFFIX" in
            _a|a) NEW_SLOT=1 ;;
            _b|b) NEW_SLOT=0 ;;
            *) NEW_SLOT=1 ;;
        esac
        ;;
esac

LOGMSG "post_rom_flash_completion: will reflash OrangeFox and activate slot ${NEW_SLOT}"

# The recovery operation is still in progress while this script runs, so
# calling fox directly here fails with "operation in progress". Defer the
# exact "Flash current OrangeFox" action until the operation has finished.
nohup /system/bin/sh -c "sleep 8; /system/bin/fox reflash run; /system/bin/bootctl set-active-boot-slot ${NEW_SLOT}" \
    >/tmp/post_rom_flash_completion.log 2>&1 &

exit 0
