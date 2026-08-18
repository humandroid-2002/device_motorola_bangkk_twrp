#!/system/bin/sh

set -u

LPT="/system/bin/lptools"
E2FSCK="/system/bin/e2fsck"
RESIZE2FS="/system/bin/resize2fs"
TUNE2FS="/system/bin/tune2fs"
LPDUMP="/system/bin/lpdump"

GROW_BYTES=$((40 * 1024 * 1024))
GROW_KB=$((40 * 1024))
MIN_PRODUCT_FREE_KB=$((60 * 1024))
MIN_LP_FREE_BYTES=$GROW_BYTES
BLOCK_SIZE=4096

log() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

fail() {
    echo
    echo "!!! ERRORE: $1"
    echo "!!! OPERAZIONE INTERROTTA."
    exit 1
}

fsck_fix() {
    FSCK_DEV="$1"
    FSCK_NAME="$2"

    "$E2FSCK" -f -y "$FSCK_DEV"
    FSCK_RC=$?

    case "$FSCK_RC" in
        0|1|2)
            echo "$FSCK_NAME: e2fsck completato (rc=$FSCK_RC)"
            ;;
        *)
            fail "$FSCK_NAME: e2fsck fallito con codice $FSCK_RC"
            ;;
    esac
}

get_blocks() {
    "$TUNE2FS" -l "$1" 2>/dev/null |
        sed -n 's/^Block count:[[:space:]]*//p' |
        head -n 1
}

SLOT="$(getprop ro.boot.slot_suffix)"

case "$SLOT" in
    _a|_b)
        ;;
    *)
        fail "Slot non riconosciuto: $SLOT"
        ;;
esac

PRODUCT="product${SLOT}"
VENDOR="vendor${SLOT}"

PRODUCT_DEV="/dev/block/by-name/product"
VENDOR_DEV="/dev/block/by-name/vendor"
SUPER="/dev/block/by-name/super"
VENDOR_MAPPER="/dev/block/mapper/$VENDOR"

echo "Slot attivo : $SLOT"
echo "LP product  : $PRODUCT"
echo "LP vendor   : $VENDOR"

for TOOL in "$LPT" "$E2FSCK" "$RESIZE2FS" "$TUNE2FS" "$LPDUMP"; do
    [ -x "$TOOL" ] || fail "Tool mancante: $TOOL"
done

[ -e "$SUPER" ] || fail "$SUPER non esiste"
[ -e "$PRODUCT_DEV" ] || fail "$PRODUCT_DEV non esiste"
[ -e "$VENDOR_DEV" ] || fail "$VENDOR_DEV non esiste"

# ==================================================
# CONTROLLO SPAZIO PRODUCT
# ==================================================

log "CONTROLLO SPAZIO LIBERO PRODUCT"

# Product deve essere smontato prima del controllo.
mount | grep ' /product ' >/dev/null 2>&1 &&
    umount /product || true

mount | grep ' /product ' >/dev/null 2>&1 &&
    fail "/product ancora montato"

# Montaggio temporaneo RO.
mount -t ext4 -o ro,seclabel "$PRODUCT_DEV" /product ||
    fail "Impossibile montare /product in sola lettura"

PRODUCT_FREE_KB="$(df -k /product 2>/dev/null |
    awk 'NR==2 {print $4}')"

umount /product ||
    fail "Impossibile smontare /product"

case "$PRODUCT_FREE_KB" in
    ''|*[!0-9]*)
        fail "Impossibile determinare spazio libero /product"
        ;;
esac

echo
echo "Spazio libero product : ${PRODUCT_FREE_KB} KiB"
echo "Minimo richiesto      : ${MIN_PRODUCT_FREE_KB} KiB"
echo "Da trasferire         : ${GROW_KB} KiB"

# ==================================================
# RAMO A: PRODUCT HA ALMENO 60 MiB LIBERI
# ==================================================

if [ "$PRODUCT_FREE_KB" -ge "$MIN_PRODUCT_FREE_KB" ]; then

    echo
    echo "Product ha abbastanza spazio libero."
    echo "Verranno trasferiti 40 MiB da product a vendor."

    PRODUCT_BEFORE="$(blockdev --getsize64 "$PRODUCT_DEV")" ||
        fail "Impossibile leggere product"

    VENDOR_BEFORE="$(blockdev --getsize64 "$VENDOR_DEV")" ||
        fail "Impossibile leggere vendor"

    PRODUCT_TARGET=$((PRODUCT_BEFORE - GROW_BYTES))
    VENDOR_TARGET=$((VENDOR_BEFORE + GROW_BYTES))

    echo
    echo "Product attuale : $PRODUCT_BEFORE bytes"
    echo "Vendor attuale  : $VENDOR_BEFORE bytes"
    echo "Spostamento     : $GROW_BYTES bytes"
    echo "Product target  : $PRODUCT_TARGET bytes"
    echo "Vendor target   : $VENDOR_TARGET bytes"

    [ "$PRODUCT_BEFORE" -gt "$GROW_BYTES" ] ||
        fail "Product LP troppo piccolo per sottrarre 40 MiB"

    # --------------------------------------------------
    # CONTROLLO FILESYSTEM PRODUCT
    # --------------------------------------------------

    log "CONTROLLO FILESYSTEM PRODUCT"

    mount | grep ' /product ' >/dev/null 2>&1 &&
        umount /product || true

    mount | grep ' /vendor ' >/dev/null 2>&1 &&
        umount /vendor || true

    mount | grep ' /product ' >/dev/null 2>&1 &&
        fail "/product ancora montato"

    mount | grep ' /vendor ' >/dev/null 2>&1 &&
        fail "/vendor ancora montato"

    fsck_fix "$PRODUCT_DEV" "product"

    PRODUCT_FS_BLOCKS="$(get_blocks "$PRODUCT_DEV")"

    [ -n "$PRODUCT_FS_BLOCKS" ] ||
        fail "Impossibile leggere Block count product"

    PRODUCT_TARGET_BLOCKS=$((PRODUCT_TARGET / BLOCK_SIZE))

    echo "Product filesystem : $PRODUCT_FS_BLOCKS blocchi"
    echo "Product FS target  : $PRODUCT_TARGET_BLOCKS blocchi"

    [ "$PRODUCT_FS_BLOCKS" -gt "$PRODUCT_TARGET_BLOCKS" ] ||
        fail "Il filesystem product non può essere ridotto a questo target"

    # --------------------------------------------------
    # RIDUZIONE FILESYSTEM PRODUCT
    # --------------------------------------------------

    log "RIDUZIONE FILESYSTEM PRODUCT"

    "$RESIZE2FS" "$PRODUCT_DEV" "$PRODUCT_TARGET_BLOCKS" ||
        fail "resize2fs product fallito"

    "$E2FSCK" -f -n "$PRODUCT_DEV"
    PRODUCT_CHECK_RC=$?

    case "$PRODUCT_CHECK_RC" in
        0|1|2)
            echo "Controllo product dopo resize completato (rc=$PRODUCT_CHECK_RC)"
            ;;
        *)
            fail "Controllo product dopo resize fallito"
            ;;
    esac

    PRODUCT_FS_AFTER="$(get_blocks "$PRODUCT_DEV")"

    echo "Product FS dopo : $PRODUCT_FS_AFTER blocchi"

    [ "$PRODUCT_FS_AFTER" -eq "$PRODUCT_TARGET_BLOCKS" ] ||
        fail "Filesystem product non ha raggiunto il target"

    # --------------------------------------------------
    # RIDUZIONE LP PRODUCT
    # --------------------------------------------------

    log "UNMAP PRODUCT"

    "$LPT" unmap "$PRODUCT" >/dev/null 2>&1 || true

    log "RIDUZIONE LOGICAL PARTITION PRODUCT"

    "$LPT" resize "$PRODUCT" "$PRODUCT_TARGET" ||
        fail "Impossibile ridurre $PRODUCT"

    "$LPT" map "$PRODUCT" >/dev/null 2>&1 ||
        fail "Impossibile rimappare $PRODUCT"

    PRODUCT_AFTER="$(blockdev --getsize64 "$PRODUCT_DEV")" ||
        fail "Impossibile rileggere product"

    echo "Product LP dopo : $PRODUCT_AFTER bytes"

    [ "$PRODUCT_AFTER" -eq "$PRODUCT_TARGET" ] ||
        fail "Product LP non ha raggiunto il target"

    "$LPT" unmap "$PRODUCT" >/dev/null 2>&1 || true

# ==================================================
# RAMO B: PRODUCT TROPPO PIENO
# FALLBACK: SPAZIO LIBERO DEL GRUPPO LP
# ==================================================

else

    log "FALLBACK SPAZIO LIBERO LP"

    echo
    echo "Product ha solo ${PRODUCT_FREE_KB} KiB liberi."
    echo "Minimo richiesto: ${MIN_PRODUCT_FREE_KB} KiB"
    echo
    echo "Product NON verrà modificato."
    echo "Controllo lo spazio libero del gruppo LP..."

    LP_FREE_BYTES="$("$LPT" free 2>/dev/null |
        sed -n 's/.*Free space:[[:space:]]*\([0-9][0-9]*\).*/\1/p' |
        head -n 1)"

    case "$LP_FREE_BYTES" in
        ''|*[!0-9]*)
            fail "Impossibile determinare lo spazio libero del gruppo LP"
            ;;
    esac

    echo
    echo "Spazio libero LP : $LP_FREE_BYTES bytes"
    echo "Richiesto        : $MIN_LP_FREE_BYTES bytes"

    [ "$LP_FREE_BYTES" -ge "$MIN_LP_FREE_BYTES" ] ||
        fail "Spazio libero LP insufficiente: $LP_FREE_BYTES bytes"

    echo
    echo "Spazio LP sufficiente."
    echo "Verranno presi direttamente 40 MiB dal gruppo LP."
    echo "Product non verrà toccato."

    VENDOR_BEFORE="$(blockdev --getsize64 "$VENDOR_DEV")" ||
        fail "Impossibile leggere vendor"

    VENDOR_TARGET=$((VENDOR_BEFORE + GROW_BYTES))

    echo
    echo "Vendor attuale : $VENDOR_BEFORE bytes"
    echo "Vendor target  : $VENDOR_TARGET bytes"

fi

# ==================================================
# ESPANSIONE LOGICAL PARTITION VENDOR
# ==================================================

log "ESPANSIONE LOGICAL PARTITION VENDOR"

# Se vendor è montato, lo smontiamo prima del resize/map.
mount | grep ' /vendor ' >/dev/null 2>&1 &&
    umount /vendor || true

mount | grep ' /vendor ' >/dev/null 2>&1 &&
    fail "/vendor ancora montato"

# Nel ramo product abbiamo già calcolato VENDOR_TARGET.
# Nel ramo LP fallback lo abbiamo calcolato sopra.

"$LPT" resize "$VENDOR" "$VENDOR_TARGET" ||
    fail "Impossibile espandere $VENDOR"

# ==================================================
# MAP VENDOR
# ==================================================

log "MAP VENDOR"

# Prima prova.
if "$LPT" map "$VENDOR"; then

    echo "Prima mappatura vendor riuscita."

else

    echo
    echo "Prima mappatura vendor fallita."
    echo "Eseguo unmap e riprovo la mappatura..."

    "$LPT" unmap "$VENDOR" >/dev/null 2>&1 || true

    "$LPT" map "$VENDOR" ||
        fail "Impossibile mappare $VENDOR anche al secondo tentativo"

fi

[ -e "$VENDOR_MAPPER" ] ||
    fail "$VENDOR_MAPPER non esiste"

VENDOR_AFTER="$(blockdev --getsize64 "$VENDOR_MAPPER")" ||
    fail "Impossibile leggere vendor"

echo "Vendor LP dopo : $VENDOR_AFTER bytes"

[ "$VENDOR_AFTER" -eq "$VENDOR_TARGET" ] ||
    fail "Vendor LP non ha raggiunto il target"

# ==================================================
# CONTROLLO FILESYSTEM VENDOR
# ==================================================

log "CONTROLLO FILESYSTEM VENDOR"

fsck_fix "$VENDOR_MAPPER" "vendor"

VENDOR_FS_BLOCKS="$(get_blocks "$VENDOR_MAPPER")"

[ -n "$VENDOR_FS_BLOCKS" ] ||
    fail "Impossibile leggere Block count vendor"

VENDOR_TARGET_BLOCKS=$((VENDOR_TARGET / BLOCK_SIZE))

echo
echo "Vendor FS attuale : $VENDOR_FS_BLOCKS"
echo "Vendor FS target  : $VENDOR_TARGET_BLOCKS"

[ "$VENDOR_FS_BLOCKS" -lt "$VENDOR_TARGET_BLOCKS" ] ||
    fail "Filesystem vendor non deve essere espanso"

# ==================================================
# ESPANSIONE FILESYSTEM VENDOR
# ==================================================

log "ESPANSIONE FILESYSTEM VENDOR"

"$RESIZE2FS" "$VENDOR_MAPPER" "$VENDOR_TARGET_BLOCKS" ||
    fail "resize2fs vendor fallito"

"$E2FSCK" -f -n "$VENDOR_MAPPER"
VENDOR_CHECK_RC=$?

case "$VENDOR_CHECK_RC" in
    0|1|2)
        echo "Controllo vendor dopo resize completato (rc=$VENDOR_CHECK_RC)"
        ;;
    *)
        fail "Controllo vendor dopo resize fallito"
        ;;
esac

# ==================================================
# VERIFICA FINALE
# ==================================================

log "VERIFICA FINALE"

echo "=== SLOT ==="
echo "$SLOT"

echo
echo "=== PRODUCT ==="
blockdev --getsize64 "$PRODUCT_DEV"

"$TUNE2FS" -l "$PRODUCT_DEV" 2>/dev/null |
    grep -E 'Block count|Block size|Free blocks'

echo
echo "=== VENDOR ==="
blockdev --getsize64 "$VENDOR_MAPPER"

"$TUNE2FS" -l "$VENDOR_MAPPER" 2>/dev/null |
    grep -E 'Block count|Block size|Free blocks'

echo
echo "=== LP FREE ==="
"$LPT" free

echo
echo "=== LP LAYOUT ==="
"$LPDUMP" "$SUPER" 2>/dev/null |
    grep -A8 -B2 -E "Name: ($PRODUCT|$VENDOR)"

# ==================================================
# MOUNT VENDOR
# ==================================================

log "MOUNT VENDOR"

mount -t ext4 -o rw,seclabel "$VENDOR_MAPPER" /vendor ||
    fail "Impossibile montare /vendor"

# ==================================================
# RISULTATO
# ==================================================

echo
echo "=============================================="
echo " OPERAZIONE COMPLETATA"
echo "=============================================="

echo
echo "Slot:"
echo "$SLOT"

echo
echo "Product finale:"
blockdev --getsize64 "$PRODUCT_DEV"

echo
echo "Vendor finale:"
blockdev --getsize64 "$VENDOR_MAPPER"

echo
echo "Vendor filesystem:"
"$TUNE2FS" -l "$VENDOR_MAPPER" 2>/dev/null |
    grep -E 'Block count|Block size|Free blocks'

echo
echo "Vendor mount:"
df -h /vendor

echo
echo "Sono stati trasferiti $GROW_BYTES bytes da product a vendor."
echo

