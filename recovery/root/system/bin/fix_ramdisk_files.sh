#!/system/bin/sh

# This script only check /ramdisk-files.txt if corrupted repair
# so "Flash current OrangeFox" never fails because
# of missing entries.

LIST=/ramdisk-files.txt
BACKUP=/tmp/ramdisk-files.txt.bak
TMP=/tmp/ramdisk-files.txt.new
ERR=/tmp/ramdisk-check.err
OUT=/tmp/ramdisk-check.cpio

LOGMSG() {
    echo "I:fix_ramdisk_files: $1" >> /tmp/recovery.log
}

[ -f "$LIST" ] || {
    LOGMSG "missing $LIST"
    exit 1
}

if [ -d /system/etc/fox/dashboard ] && [ ! -e /system/etc/fox/.dashboard.stamp ]; then
    touch /system/etc/fox/.dashboard.stamp
    LOGMSG "created /system/etc/fox/.dashboard.stamp"
fi

[ -f "$BACKUP" ] || cp -f "$LIST" "$BACKUP"

cd / || exit 1

is_dir_entry() {
    grep -F -q "$1/" "$LIST" 2>/dev/null
}

attempt=0
while [ "$attempt" -lt 100 ]; do
    if /system/bin/cpio -H newc -o < "$LIST" > "$OUT" 2> "$ERR"; then
        rm -f "$OUT" "$ERR" "$TMP"
        LOGMSG "cpio check OK"
        exit 0
    fi

    missing=$(sed -n 's/^cpio: \(.*\): No such file or directory$/\1/p' "$ERR" | head -n 1)
    if [ -z "$missing" ]; then
        break
    fi

    case "$missing" in
        system/etc/fox/*)
            if is_dir_entry "$missing"; then
                mkdir -p "/$missing" 2>/dev/null
                LOGMSG "created missing directory: $missing"
            else
                mkdir -p "/$(dirname "$missing")" 2>/dev/null
                touch "/$missing" 2>/dev/null
                LOGMSG "created missing file: $missing"
            fi
            ;;
        *)
            if grep -F -x -v "$missing" "$LIST" > "$TMP" 2>/dev/null; then
                mv -f "$TMP" "$LIST"
                chmod 644 "$LIST" 2>/dev/null
                LOGMSG "removed missing entry: $missing"
            else
                LOGMSG "failed to remove missing entry: $missing"
                break
            fi
            ;;
    esac

    attempt=$((attempt + 1))
done

LOGMSG "cpio check FAILED: $(head -n 1 "$ERR" 2>/dev/null)"
rm -f "$OUT"
exit 1
