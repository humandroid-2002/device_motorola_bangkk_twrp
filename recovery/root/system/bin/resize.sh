#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 humandroid-2002
# standalone vendor resize helper only for motorola g84 device
# If vendor is erofs, this script hands off to /system/bin/erofs.sh.
# resize.sh execution time 3sec or less on ext4 file system

LOG="/tmp/resize.log"
FIFO="/tmp/resize.log.fifo"

rm -f "$LOG" "$FIFO"
mkfifo "$FIFO" || exit 1

tee "$LOG" < "$FIFO" &
exec > "$FIFO" 2>&1

ADD=94371840
TARGET_DEVICE="bangkk"
LOOPDEV=""

section() {
    printf '\n%s\n' "$1"
}

error() {
    printf '\nERROR: %s\n' "$1"
    if [ -n "$LOOPDEV" ]; then
        losetup -d "$LOOPDEV" >/dev/null 2>&1 || true
    fi
    exit 1
}

ok() {
    printf '[ OK ] %s\n' "$1"
}

warn() {
    printf '[ WARN ] %s\n' "$1"
}

is_uint() {
    case "$1" in
    '' | *[!0-9]*) return 1 ;;
    *) return 0 ;;
    esac
}

ge() {
    awk -v a="$1" -v b="$2" 'BEGIN { exit (a >= b ? 0 : 1) }'
}

calc() {
    awk -v a="$1" -v op="$2" -v b="$3" 'BEGIN {
        if (op == "+") printf "%.0f\n", a + b
        else if (op == "-") printf "%.0f\n", a - b
        else if (op == "*") printf "%.0f\n", a * b
        else if (op == "/") printf "%.0f\n", int(a / b)
    }'
}

partition_size_from_lpdump() {
    "$LPDUMP" "$SUPER" 2>/dev/null |
        awk -v name="$1" '
            $1 == "Name:" { current = $2; next }
            current == name && $2 == ".." { total += $3 - $1 + 1 }
            END { print total * 512 }
        '
}

partition_extents() {
    "$LPDUMP" "$SUPER" 2>/dev/null |
        awk -v name="$1" '
            $1 == "Name:" { inpart = ($2 == name); inext = 0; next }
            inpart && $1 == "Extents:" { inext = 1; next }
            inpart && inext && $2 == ".." && $4 == "linear" {
                print $1, ($3 - $1 + 1), $6
            }
        '
}

printf '\nBANGKK VENDOR RESIZE\n'
printf 'Target expansion: %s bytes (90 MiB)\n' "$ADD"

if [ "$(id -u)" != "0" ]; then
    error "Root richiesto."
fi

ok "Root access"

section "UNMOUNT VENDOR (EARLY)"

umount -f -l /vendor 2>/dev/null || true
ok "/vendor smontato (force lazy)"

section "ENVIRONMENT CHECK"

LPTOOLS=$(command -v lptools 2>/dev/null)
LPDUMP=$(command -v lpdump 2>/dev/null)
E2FSCK=$(command -v e2fsck 2>/dev/null)
RESIZE2FS=$(command -v resize2fs 2>/dev/null)
TUNE2FS=$(command -v tune2fs 2>/dev/null)
BLOCKDEV=$(command -v blockdev 2>/dev/null)
DMCTL=$(command -v dmctl 2>/dev/null)

[ -n "$LPTOOLS" ] || LPTOOLS="/system/bin/lptools"
[ -n "$LPDUMP" ] || LPDUMP="/system/bin/lpdump"
[ -n "$E2FSCK" ] || E2FSCK="/system/bin/e2fsck"
[ -n "$RESIZE2FS" ] || RESIZE2FS="/system/bin/resize2fs"
[ -n "$TUNE2FS" ] || TUNE2FS="/system/bin/tune2fs"
[ -n "$BLOCKDEV" ] || BLOCKDEV="/system/bin/blockdev"
[ -n "$DMCTL" ] || DMCTL="/system/bin/dmctl"

for TOOL in "$LPTOOLS" "$LPDUMP" "$E2FSCK" "$RESIZE2FS" "$TUNE2FS" "$BLOCKDEV"; do
    [ -x "$TOOL" ] || error "Tool mancante: $TOOL"
done

echo "lptools   : OK"
echo "lpdump    : OK"
echo "e2fsck    : OK"
echo "resize2fs : OK"
echo "tune2fs   : OK"
echo "blockdev  : OK"

if [ -x "$DMCTL" ]; then
    echo "dmctl     : OK (fallback)"
else
    DMCTL=""
    echo "dmctl     : NON DISPONIBILE"
fi

SUPER=""

for X in /dev/block/by-name/super /dev/block/bootdevice/by-name/super; do
    if [ -e "$X" ]; then
        SUPER="$X"
        break
    fi
done

[ -n "$SUPER" ] || error "Super partition non trovata."

echo "super     : $SUPER"

section "DEVICE DETECTION"

PROP_BUILD_PRODUCT=$(getprop ro.build.product)
PROP_SKU=$(getprop ro.boot.product.hardware.sku)
PROP_HARDWARE=$(getprop ro.boot.product.hardware)
PROP_DEVICE=$(getprop ro.product.device)

echo "ro.build.product             = $PROP_BUILD_PRODUCT"
echo "ro.boot.product.hardware.sku = $PROP_SKU"
echo "ro.boot.product.hardware     = $PROP_HARDWARE"
echo "ro.product.device            = $PROP_DEVICE"

DEVICE_OK=0

for X in "$PROP_BUILD_PRODUCT" "$PROP_SKU" "$PROP_HARDWARE" "$PROP_DEVICE"; do
    if [ "$X" = "$TARGET_DEVICE" ]; then
        DEVICE_OK=1
    fi
done

[ "$DEVICE_OK" -eq 1 ] || error "Questo script è destinato a bangkk."

echo "Device verificato: bangkk"

section "RECOVERY DETECTION"

RECOVERY="UNKNOWN"
BUILD_ID=$(getprop ro.build.display.id)
BUILD_DESC=$(getprop ro.build.description)

case "$(echo "$BUILD_ID $BUILD_DESC" | tr '[:upper:]' '[:lower:]')" in
*orangefox*) RECOVERY="OrangeFox" ;;
*twrp*) RECOVERY="TWRP" ;;
esac

echo "Recovery detected: $RECOVERY"

section "ROM / LAYOUT DETECTION"

DISPLAY_ID=$(getprop ro.build.display.id)
DESCRIPTION=$(getprop ro.build.description)
INCREMENTAL=$(getprop ro.build.version.incremental)

echo "ro.build.display.id          = $DISPLAY_ID"
echo "ro.build.description         = $DESCRIPTION"
echo "ro.build.version.incremental = $INCREMENTAL"

ROM="UNKNOWN"
ALL_PROPS=$(getprop)

case "$(echo "$ALL_PROPS" | tr '[:upper:]' '[:lower:]')" in
*lineage*) ROM="LineageOS" ;;
*lunaris*) ROM="Lunaris OS" ;;
esac

echo "ROM detected: $ROM"

section "SLOT DETECTION"

SLOT=$(getprop ro.boot.slot_suffix)

if [ -z "$SLOT" ]; then
    SLOT_RAW=$(getprop ro.boot.slot)

    case "$SLOT_RAW" in
    a) SLOT="_a" ;;
    b) SLOT="_b" ;;
    esac
fi

case "$SLOT" in
_a | _b) ;;
*) error "Slot attivo non rilevato." ;;
esac

VENDOR_NAME="vendor$SLOT"
VENDOR="/dev/block/mapper/$VENDOR_NAME"

echo "Active slot       : $SLOT"
echo "Logical partition : $VENDOR_NAME"
echo "Mapper device     : $VENDOR"

[ -e "$VENDOR" ] || error "Mapper vendor non trovato: $VENDOR"

section "PARTITION CHECK"

OLD=$("$BLOCKDEV" --getsize64 "$VENDOR" 2>/dev/null)

is_uint "$OLD" || error "Impossibile leggere la dimensione di vendor."

NEW=$(calc "$OLD" + "$ADD")

echo "Old vendor size : $OLD bytes"
echo "Add size        : $ADD bytes"
echo "New vendor size : $NEW bytes"

section "EXT4 CHECK"

EXT4_INFO=$("$TUNE2FS" -l "$VENDOR" 2>&1)

echo "$EXT4_INFO" | grep -E \
    "Filesystem magic number|Filesystem state|Block count|Free blocks|Block size"

MAGIC=$(echo "$EXT4_INFO" | grep "Filesystem magic number" | awk '{print $NF}' | tr -d '[:space:]')
BLOCK_SIZE=$(echo "$EXT4_INFO" | grep "^Block size:" | awk '{print $NF}' | tr -d '[:space:]')
BLOCK_COUNT=$(echo "$EXT4_INFO" | grep "^Block count:" | awk '{print $NF}' | tr -d '[:space:]')
FREE_BLOCKS=$(echo "$EXT4_INFO" | grep "^Free blocks:" | awk '{print $NF}' | tr -d '[:space:]')

if [ "$MAGIC" != "0xEF53" ]; then
    echo "Vendor EROFS detected"
    echo "[$(date)] RESIZE -> STARTING RO2RW" >> /tmp/erofs-debug.log

    /system/bin/erofs.sh >> /tmp/erofs-debug.log 2>&1
    EROFS_RC=$?

    echo "[$(date)] RO2RW FINISHED rc=$EROFS_RC" >> /tmp/erofs-debug.log
    exit "$EROFS_RC"
fi

is_uint "$BLOCK_SIZE" || error "Block size EXT4 non rilevato."
is_uint "$BLOCK_COUNT" || error "Block count EXT4 non rilevato."
is_uint "$FREE_BLOCKS" || error "Free blocks EXT4 non rilevati."

ok "Filesystem EXT4 verificato"

echo
echo "Parsed values:"
echo "Block size  : $BLOCK_SIZE"
echo "Block count : $BLOCK_COUNT"
echo "Free blocks : $FREE_BLOCKS"

section "RESIZE NECESSITY CHECK"

FREE_BYTES=$(calc "$FREE_BLOCKS" '*' "$BLOCK_SIZE")
MIN_FREE=52428800

echo "Vendor free space : $FREE_BYTES bytes"
echo "Minimum required  : $MIN_FREE bytes (50 MiB)"

if ge "$FREE_BYTES" "$MIN_FREE"; then
    echo
    echo "RESIZE NOT NECESSARY"
    echo "Vendor ha gia almeno 50 MiB di spazio libero."
    echo "Free space: $FREE_BYTES bytes"
    echo
    echo "Nessun resize necessario. Uscita."
    exit 0
fi

ok "Vendor ha meno di 50 MiB liberi."
ok "Resize necessario. Continuazione dello script..."

section "CURRENT LOGICAL PARTITION LAYOUT"

"$LPDUMP" "$SUPER" || error "lpdump fallito."

section "COW DETECTION"

COW_FOUND=0
COW_PARTITION=""
COW_SIZE=0

COW_NAME="${VENDOR_NAME}-cow"
COW_DEVICE="/dev/block/mapper/$COW_NAME"

if [ -e "$COW_DEVICE" ]; then
    echo "COW rilevato direttamente per vendor:"
    echo "COW name   : $COW_NAME"
    echo "COW device : $COW_DEVICE"

    COW_SIZE=$("$BLOCKDEV" --getsize64 "$COW_DEVICE" 2>/dev/null)
    echo "COW size   : $COW_SIZE bytes"

    COW_FOUND=1
    COW_PARTITION="$COW_NAME"
else
    echo "Nessun COW associato direttamente a $VENDOR_NAME."
    echo
    echo "Ricerca COW disponibili nello slot $SLOT..."

    for BASE in product system system_ext odm vendor; do
        TEST_COW="${BASE}${SLOT}-cow"

        if "$LPDUMP" "$SUPER" 2>/dev/null | grep -q "Name: $TEST_COW"; then
            echo "COW trovato nel metadata:"
            echo "COW name: $TEST_COW"

            COW_PARTITION="$TEST_COW"
            TEST_DEVICE="/dev/block/mapper/$TEST_COW"

            if [ -e "$TEST_DEVICE" ]; then
                COW_SIZE=$("$BLOCKDEV" --getsize64 "$TEST_DEVICE" 2>/dev/null)
            else
                COW_SIZE=$(partition_size_from_lpdump "$TEST_COW")
            fi

            is_uint "$COW_SIZE" || COW_SIZE=0

            echo "COW size: $COW_SIZE bytes"

            COW_FOUND=1
            break
        fi
    done
fi

if [ "$COW_FOUND" -eq 1 ]; then
    ok "COW disponibile: $COW_PARTITION"
else
    warn "Nessun COW utilizzabile rilevato."
fi

section "FREE SPACE CHECK"

"$LPTOOLS" free

FREE=$("$LPTOOLS" free 2>/dev/null | awk '/Free space:/ { print $3; exit }' | tr -d '\r\n ')

echo
echo "Detected free space: $FREE bytes"
echo "Requested expansion: $ADD bytes"

[ -n "$FREE" ] || error "Impossibile rilevare lo spazio libero."
is_uint "$FREE" || error "Valore FREE non numerico: [$FREE]"
is_uint "$ADD" || error "Valore ADD non numerico: [$ADD]"

if ! ge "$FREE" "$ADD"; then
    section "INSUFFICIENT SPACE - COW RECOVERY"

    echo "Spazio LP insufficiente per il resize."
    echo
    echo "Richiesti  : $ADD bytes"
    echo "Disponibili: $FREE bytes"
    echo

    [ "$COW_FOUND" -eq 1 ] || error "Spazio insufficiente e nessuna COW rilevata."
    is_uint "$COW_SIZE" || error "Dimensione COW non valida: [$COW_SIZE]"

    echo "COW selezionato: $COW_PARTITION"
    echo "COW size        : $COW_SIZE bytes"

    if ! ge "$COW_SIZE" "$ADD"; then
        error "Il COW $COW_PARTITION è troppo piccolo per liberare $ADD bytes."
    fi

    echo
    warn "Spazio insufficiente nel group."
    warn "Tentativo di recupero spazio dal COW:"
    echo
    echo "COW           : $COW_PARTITION"
    echo "COW attuale   : $COW_SIZE bytes"
    echo "Da liberare   : $ADD bytes"

    NEW_COW_SIZE=$(calc "$COW_SIZE" - "$ADD")

    echo "Nuova COW size: $NEW_COW_SIZE bytes"

    [ "$NEW_COW_SIZE" -gt 0 ] || error "Nuova dimensione COW non valida."

    echo
    echo "Ridimensionamento COW..."

    "$LPTOOLS" resize "$COW_PARTITION" "$NEW_COW_SIZE"
    RC=$?

    [ "$RC" -eq 0 ] || error "Impossibile ridimensionare $COW_PARTITION. Exit code: $RC"

    ok "COW ridimensionato"

    echo
    echo "Nuovo spazio libero:"
    "$LPTOOLS" free

    FREE=$("$LPTOOLS" free 2>/dev/null | awk '/Free space:/ { print $3; exit }' | tr -d '\r\n ')

    echo
    echo "Free space dopo COW recovery: $FREE bytes"

    [ -n "$FREE" ] || error "Impossibile rilevare lo spazio libero dopo COW recovery."
    is_uint "$FREE" || error "Valore FREE non numerico dopo COW recovery: [$FREE]"

    if ! ge "$FREE" "$ADD"; then
        error "Spazio ancora insufficiente dopo riduzione COW. Richiesti $ADD, disponibili $FREE."
    fi

    ok "Spazio recuperato dal COW."
fi

echo
ok "Spazio sufficiente."
echo "Disponibili: $FREE bytes"
echo "Richiesti  : $ADD bytes"

section "PRE-RESIZE SUMMARY"

echo "Vendor partition : $VENDOR_NAME"
echo "Mapper           : $VENDOR"
echo "Old size         : $OLD"
echo "Expansion        : $ADD"
echo "New size         : $NEW"
echo "Free LP space    : $FREE"

echo
echo "Procedura:"
echo "1. unmap $VENDOR_NAME (fallback: reload dm se EBUSY)"
echo "2. resize logical partition"
echo "3. map $VENDOR_NAME"
echo "4. unmount /vendor"
echo "5. prepare fs device (dm alias/loop)"
echo "6. e2fsck"
echo "7. resize2fs"
echo "8. verifica finale"

section "UNMAP $VENDOR_NAME"

UNMAPPED=0

"$LPTOOLS" unmap "$VENDOR_NAME"
RC=$?

if [ "$RC" -eq 0 ]; then
    [ ! -e "$VENDOR" ] || error "vendor risulta ancora mapped dopo unmap."
    ok "$VENDOR_NAME unmapped"
    UNMAPPED=1
else
    warn "unmap fallito: $VENDOR_NAME è in uso (EBUSY)."
    warn "Fallback attivo: resize online senza unmap (dmctl)."
fi

section "RESIZE LOGICAL PARTITION"

echo "New size: $NEW bytes"

"$LPTOOLS" resize "$VENDOR_NAME" "$NEW"
RC=$?

[ "$RC" -eq 0 ] || error "Resize logical partition fallito. Exit code: $RC"

echo
"$LPTOOLS" free

ok "Logical partition resized"

if [ "$UNMAPPED" -eq 1 ]; then
    section "MAP $VENDOR_NAME"

    "$LPTOOLS" map "$VENDOR_NAME"
    RC=$?

    [ "$RC" -eq 0 ] || error "map fallito. Exit code: $RC"
    [ -e "$VENDOR" ] || error "Mapper vendor non creato dopo map."

    MAPPED_SIZE=$("$BLOCKDEV" --getsize64 "$VENDOR" 2>/dev/null)

    echo "Mapped vendor size: $MAPPED_SIZE bytes"

    [ "$MAPPED_SIZE" -eq "$NEW" ] || \
        error "Dimensione mapper non corretta. Atteso: $NEW, trovato: $MAPPED_SIZE"

    ok "Mapper verificato"
else
    section "RELOAD DM TABLE (FALLBACK)"

    [ -n "$DMCTL" ] || error "dmctl non disponibile per il fallback."

    NEW_SECTORS=$(calc "$NEW" / 512)

    EXTENTS=$(partition_extents "$VENDOR_NAME")

    [ -n "$EXTENTS" ] || error "Impossibile leggere gli extent di $VENDOR_NAME da lpdump."

    set --
    EXTENT_TOTAL=0

    while read -r PART_START EXT_LEN PHYS_START; do
        [ -n "$PART_START" ] || continue
        set -- "$@" linear "$PART_START" "$EXT_LEN" "$SUPER" "$PHYS_START"
        EXTENT_TOTAL=$(calc "$EXTENT_TOTAL" + "$EXT_LEN")
    done <<EOF
$EXTENTS
EOF

    echo "Extent totali : $EXTENT_TOTAL sectors"
    echo "Attesi        : $NEW_SECTORS sectors"

    [ "$EXTENT_TOTAL" -eq "$NEW_SECTORS" ] || \
        error "Extent non coerenti con la nuova dimensione."

    "$DMCTL" replace "$VENDOR_NAME" "$@"
    RC=$?

    if [ "$RC" -ne 0 ]; then
        warn "Reload dm fallito: ripristino dimensione metadata."
        "$LPTOOLS" resize "$VENDOR_NAME" "$OLD" >/dev/null 2>&1 || \
            warn "Rollback metadata fallito."
        error "Reload dm fallito. Exit code: $RC"
    fi

    [ -e "$VENDOR" ] || error "Mapper vendor non disponibile dopo il reload."

    MAPPED_SIZE=$("$BLOCKDEV" --getsize64 "$VENDOR" 2>/dev/null)

    echo "Mapped vendor size: $MAPPED_SIZE bytes"

    [ "$MAPPED_SIZE" -eq "$NEW" ] || \
        error "Dimensione mapper non corretta. Atteso: $NEW, trovato: $MAPPED_SIZE"

    ok "Mapper aggiornato senza unmap"
fi

section "UNMOUNT VENDOR"

umount -f -l /vendor 2>/dev/null || true
ok "/vendor smontato (force lazy)"

section "PREPARE FS DEVICE"

WORKDEV=""
RW_DEV=""

if [ -n "$DMCTL" ]; then
    set --
    while read -r PART_START EXT_LEN PHYS_START; do
        [ -n "$PART_START" ] || continue
        set -- "$@" linear "$PART_START" "$EXT_LEN" "$SUPER" "$PHYS_START"
    done <<EOF
$(partition_extents "$VENDOR_NAME")
EOF

    if [ "$#" -gt 0 ]; then
        RW_NAME="vendor_rw"

        if "$DMCTL" table "$RW_NAME" >/dev/null 2>&1; then
            "$DMCTL" replace "$RW_NAME" "$@" >/dev/null 2>&1 && \
                RW_DEV="/dev/block/mapper/$RW_NAME"
        else
            "$DMCTL" create "$RW_NAME" "$@" >/dev/null 2>&1 && \
                RW_DEV="/dev/block/mapper/$RW_NAME"
        fi
    fi
fi

if [ -n "$RW_DEV" ]; then
    I=0
    while [ "$I" -lt 20 ]; do
        [ -e "$RW_DEV" ] && break
        sleep 0.2
        I=$((I + 1))
    done

    if [ -e "$RW_DEV" ]; then
        RW_SIZE=$("$BLOCKDEV" --getsize64 "$RW_DEV" 2>/dev/null)

        if [ "$RW_SIZE" = "$NEW" ]; then
            WORKDEV="$RW_DEV"
        else
            warn "Alias dm non allineato: $RW_DEV ($RW_SIZE)."
        fi
    else
        warn "Symlink alias non comparso: $RW_DEV."
    fi
fi

if [ -z "$WORKDEV" ]; then
    for N in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        TEST_LOOP="/dev/block/loop$N"
        [ -e "$TEST_LOOP" ] || continue

        if losetup "$TEST_LOOP" "$VENDOR" >/dev/null 2>&1; then
            LOOPDEV="$TEST_LOOP"
            WORKDEV="$TEST_LOOP"
            break
        fi
    done
fi

[ -z "$WORKDEV" ] && WORKDEV="$VENDOR"

[ -e "$WORKDEV" ] || error "Nessun device utilizzabile per resize2fs."
echo "Filesystem device : $WORKDEV"

section "E2FSCK PRE-RESIZE"

"$E2FSCK" -fp "$WORKDEV"
RC=$?

if [ "$RC" -eq 8 ]; then
    warn "e2fsck: device occupato (exit 8). Retry in sola lettura."
    "$E2FSCK" -fn "$WORKDEV"
    RC=$?
fi

case "$RC" in
0 | 1 | 2) ok "e2fsck completato. Exit code: $RC" ;;
*) error "e2fsck fallito. Exit code: $RC" ;;
esac

section "RESIZE EXT4 FILESYSTEM"

echo "Expanding EXT4 to device size..."

"$RESIZE2FS" "$WORKDEV"
RC=$?

[ "$RC" -eq 0 ] || error "resize2fs fallito. Exit code: $RC"

ok "EXT4 filesystem expanded"

section "FINAL EXT4 CHECK"

FINAL_INFO=$("$TUNE2FS" -l "$WORKDEV" 2>&1)

echo "$FINAL_INFO" | grep -E \
    "Filesystem magic number|Filesystem state|Block count|Free blocks|Block size"

FINAL_MAGIC=$(echo "$FINAL_INFO" | grep "Filesystem magic number" | awk '{print $NF}' | tr -d '[:space:]')
FINAL_BLOCK_SIZE=$(echo "$FINAL_INFO" | grep "^Block size:" | awk '{print $NF}' | tr -d '[:space:]')
FINAL_BLOCK_COUNT=$(echo "$FINAL_INFO" | grep "^Block count:" | awk '{print $NF}' | tr -d '[:space:]')
FINAL_FREE_BLOCKS=$(echo "$FINAL_INFO" | grep "^Free blocks:" | awk '{print $NF}' | tr -d '[:space:]')
FINAL_SIZE=$("$BLOCKDEV" --getsize64 "$WORKDEV" 2>/dev/null)

EXPECTED_BLOCKS=$(calc "$FINAL_SIZE" / "$FINAL_BLOCK_SIZE")

echo
echo "Final device size : $FINAL_SIZE"
echo "Expected blocks   : $EXPECTED_BLOCKS"
echo "Actual blocks     : $FINAL_BLOCK_COUNT"
echo "Free blocks       : $FINAL_FREE_BLOCKS"

[ "$FINAL_MAGIC" = "0xEF53" ] || error "Filesystem finale non EXT4."
[ "$FINAL_SIZE" -eq "$NEW" ] || error "Dimensione finale errata."
[ "$FINAL_BLOCK_COUNT" -eq "$EXPECTED_BLOCKS" ] || \
    error "EXT4 non occupa l'intera nuova dimensione."

section "FINAL E2FSCK"

"$E2FSCK" -fn "$WORKDEV"
RC=$?

case "$RC" in
0 | 1) ok "Filesystem finale verificato. Exit code: $RC" ;;
*) error "Verifica finale e2fsck fallita. Exit code: $RC" ;;
esac

if [ -n "$LOOPDEV" ]; then
    losetup -d "$LOOPDEV" >/dev/null 2>&1 || true
    LOOPDEV=""
fi

section "FINAL LOGICAL PARTITION LAYOUT"

"$LPDUMP" "$SUPER" 2>&1 | grep -A6 -B1 "Name: $VENDOR_NAME"

echo
echo "SUCCESS"
echo "Device             : bangkk"
echo "Recovery           : $RECOVERY"
echo "ROM                : $ROM"
echo "Active slot        : $SLOT"
echo "Vendor             : $VENDOR_NAME"
echo "Old vendor size    : $OLD bytes"
echo "Added              : $ADD bytes"
echo "New vendor size    : $FINAL_SIZE bytes"
echo "EXT4 block size    : $FINAL_BLOCK_SIZE"
echo "EXT4 block count   : $FINAL_BLOCK_COUNT"
echo "EXT4 free blocks   : $FINAL_FREE_BLOCKS"

echo
echo "Vendor resize completed successfully."
