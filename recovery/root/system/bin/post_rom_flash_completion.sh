#!/system/bin/sh

# Copyright (C) 2026 humandroid-2002
# SPDX-License-Identifier: GPL-3.0-only
#
# Called by the AERA recovery core after a ROM flash (see aera_core.cpp:
# AERA_AFTER_ROM_FLASH_SCRIPT / post_rom_flash_completion.sh).
#
# AERA has no "flash current recovery" command (aeracli reports reflash as
# reserved but unsupported), so this only activates the slot the ROM was
# written to. Reboot into the new slot from the AERA reboot menu.

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

LOGMSG "post_rom_flash_completion: activating slot ${NEW_SLOT}"

# The recovery operation is still in progress while this script runs, so the
# slot switch is deferred until the operation has finished.
nohup /system/bin/sh -c "sleep 3; /system/bin/bootctl set-active-boot-slot ${NEW_SLOT}" \
    >/tmp/post_rom_flash_completion.log 2>&1 &

exit 0