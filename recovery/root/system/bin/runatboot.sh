#!/system/bin/sh

LOG="/tmp/recovery.log"
VENDOR="/vendor"
VENDOR_MNT="$VENDOR"
PREBUILT_MODULES_DIR="/system/etc/prebuilt_modules"
MODULES_DIR="/tmp/lib/modules"
SLOT="$(getprop ro.boot.slot_suffix)"
[ -n "$SLOT" ] || SLOT="_a"
VENDOR_MOUNTED=0
MODULE_SOURCE=""
LOAD_STACK=""

log() {
    echo "[OF-MODULES] $1" >> "$LOG"
}

START_MARKER="/tmp/.runatboot.started"
if [ -f "$START_MARKER" ]; then
    log "Duplicate start ignored"
    exit 0
fi
: > "$START_MARKER" 2>/dev/null || true

mount_vendor_dev() {
    local dev="$1"
    local target="$2"
    local fs

    for fs in erofs ext4; do
        if mount -t "$fs" -o ro "$dev" "$target" 2>>"$LOG"; then
            log "Mounted $dev on $target as $fs"
            return 0
        fi
    done

    if mount -o ro "$dev" "$target" 2>>"$LOG"; then
        log "Mounted $dev on $target"
        return 0
    fi

    return 1
}

find_vendor_device() {
    local part
    local dev
    local out
    local dm

    for dev in \
        "/dev/block/mapper/vendor${SLOT}" \
        "/dev/block/mapper/vendor" \
        "/dev/block/by-name/vendor${SLOT}" \
        "/dev/block/by-name/vendor" \
        "/dev/block/bootdevice/by-name/vendor${SLOT}" \
        "/dev/block/bootdevice/by-name/vendor"
    do
        [ -b "$dev" ] && { echo "$dev"; return 0; }
    done

    if command -v lptools >/dev/null 2>&1; then
        for part in "vendor${SLOT}" "vendor"; do
            out="$(lptools map "$part" 2>&1)"
            log "$out"
            dev="$(printf '%s\n' "$out" | sed -n 's/.* at \(\/dev\/block\/dm-[0-9][0-9]*\).*/\1/p' | tail -n 1)"

            if [ -z "$dev" ]; then
                for dm in /sys/block/dm-*; do
                    [ "$(cat "$dm/dm/name" 2>/dev/null)" = "$part" ] || continue
                    dev="/dev/block/${dm##*/}"
                    break
                done
            fi

            [ -n "$dev" ] && { echo "$dev"; return 0; }
        done
    fi

    return 1
}

copy_modules_from() {
    local src="$1"
    local f

    log "Copying modules from $src"
    if [ -f "$src/modules.load" ]; then
        for f in "$src"/*.ko "$src"/modules.*; do
            [ -f "$f" ] || continue
            if ! cp -aL "$f" "$MODULES_DIR"/ >> "$LOG" 2>&1; then
                log "ERROR: copy failed for $f"
                return 1
            fi
        done
    else
        find "$src" -type f -name '*.ko' \
            -exec cp -aL {} "$MODULES_DIR"/ \; >> "$LOG" 2>&1
        for f in "$src"/modules.*; do
            [ -f "$f" ] || continue
            cp -aL "$f" "$MODULES_DIR"/ >> "$LOG" 2>&1
        done
    fi

    find "$MODULES_DIR" -type f -name '*.ko' -print | grep -q '\.ko$'
}

probe_vendor_module() {
    local name="$1"
    local sysname path out rc

    sysname="$(printf '%s' "$name" | tr '-' '_')"
    if [ -d "/sys/module/$sysname" ]; then
        log "Vendor probe skipped (already loaded/built-in): $name"
        return 3
    fi

    path="$MODULES_DIR/$name.ko"
    [ -f "$path" ] || return 1

    out="$(insmod "$path" 2>&1)"
    rc=$?
    [ -n "$out" ] && printf '%s\n' "$out" >> "$LOG"

    if [ "$rc" -eq 0 ]; then
        log "Vendor probe OK: $name"
        return 0
    fi

    if printf '%s' "$out" | grep -qiE 'exec format|invalid module format|vermagic'; then
        log "Vendor probe vermagic mismatch: $name"
        return 2
    fi

    log "Vendor probe failed: $name"
    return 1
}

probe_vendor_modules() {
    local line path name rc
    local ok=0 tried=0 already=0

    if [ -s "$MODULES_DIR/modules.load" ]; then
        while IFS= read -r line; do
            line="${line%%#*}"
            line="$(printf '%s' "$line" | tr -d '[:space:]')"
            [ -n "$line" ] || continue
            line="${line##*/}"
            line="${line%.ko}"
            probe_vendor_module "$line"
            rc=$?
            case "$rc" in
                0) ok=1; break ;;
                2) return 1 ;;
                3) already=$((already + 1)) ;;
                *) tried=$((tried + 1)) ;;
            esac
        done < "$MODULES_DIR/modules.load"
    else
        for path in "$MODULES_DIR"/*.ko; do
            [ -f "$path" ] || continue
            name="${path##*/}"
            name="${name%.ko}"
            probe_vendor_module "$name"
            rc=$?
            case "$rc" in
                0) ok=1; break ;;
                2) return 1 ;;
                3) already=$((already + 1)) ;;
                *) tried=$((tried + 1)) ;;
            esac
        done
    fi

    if [ "$ok" -eq 1 ]; then
        log "Vendor modules match the running kernel"
        return 0
    fi

    if [ "$tried" -eq 0 ] && [ "$already" -gt 0 ]; then
        log "All vendor probe candidates already loaded; assuming vendor modules"
        return 0
    fi

    return 1
}

prepare_prebuilt_modules() {
    if [ ! -d "$PREBUILT_MODULES_DIR" ]; then
        return 1
    fi

    rm -rf "$MODULES_DIR"
    mkdir -p "$MODULES_DIR" || return 1
    if copy_modules_from "$PREBUILT_MODULES_DIR"; then
        MODULE_SOURCE="prebuilt"
        log "Using prebuilt modules"
        return 0
    fi

    return 1
}

prepare_stock_modules() {
    if ! mountpoint -q "$VENDOR"; then
        log "Mounting $VENDOR..."
        if mount "$VENDOR" >> "$LOG" 2>&1; then
            VENDOR_MNT="$VENDOR"
            VENDOR_MOUNTED=1
        else
            vendor_dev="$(find_vendor_device)"
            if [ -n "$vendor_dev" ]; then
                if mount_vendor_dev "$vendor_dev" "$VENDOR"; then
                    VENDOR_MNT="$VENDOR"
                    VENDOR_MOUNTED=1
                else
                    mkdir -p /tmp/vendor
                    if mount_vendor_dev "$vendor_dev" "/tmp/vendor"; then
                        VENDOR_MNT="/tmp/vendor"
                        VENDOR_MOUNTED=1
                    else
                        log "WARNING: cannot mount $vendor_dev"
                    fi
                fi
            else
                log "WARNING: vendor partition not found"
            fi
        fi
    else
        VENDOR_MNT="$VENDOR"
    fi

    if [ -d "$VENDOR_MNT/lib/modules" ]; then
        rm -rf "$MODULES_DIR"
        mkdir -p "$MODULES_DIR" || return 1
        if copy_modules_from "$VENDOR_MNT/lib/modules"; then
            if probe_vendor_modules; then
                MODULE_SOURCE="stock"
                log "Using vendor modules"
                return 0
            fi
        fi
    fi

    log "Vendor modules do not match the running kernel"
    return 1
}

mkdir -p /tmp/lib
rm -rf "$MODULES_DIR"
mkdir -p "$MODULES_DIR" || {
    log "ERROR: cannot create $MODULES_DIR"
    exit 1
}

if ! prepare_stock_modules; then
    if ! prepare_prebuilt_modules; then
        log "WARNING: no usable modules found"
    fi
fi

if [ "$VENDOR_MOUNTED" = "1" ] && mountpoint -q "$VENDOR_MNT"; then
    log "Unmounting $VENDOR_MNT..."
    if umount "$VENDOR_MNT" >> "$LOG" 2>&1 || umount -l "$VENDOR_MNT" >> "$LOG" 2>&1; then
        log "$VENDOR_MNT detached successfully"
    else
        log "WARNING: cannot unmount $VENDOR_MNT"
    fi
fi

ensure_firmware_path() {
    local path="$1"
    local target="$2"

    if [ -d "$path" ] && [ -n "$(ls -A "$path" 2>/dev/null)" ]; then
        log "Keeping $path"
        return 0
    fi

    if [ -e "$path" ] || [ -L "$path" ]; then
        rm -rf "$path" >> "$LOG" 2>&1
    fi

    if ln -s "$target" "$path" >> "$LOG" 2>&1; then
        log "Linked $path -> $target"
    else
        log "WARNING: cannot link $path -> $target"
    fi
}

ensure_firmware_path "$VENDOR/firmware" "/firmware"
ensure_firmware_path "$VENDOR/firmware_mnt" "/firmware_mnt"

load_mod() {
    local mod="$1"
    local sysname
    local path

    sysname="$(printf '%s' "$mod" | tr '-' '_')"

    if [ "$mod" = "qca_cld3_wlan" ] && [ -d /sys/module/wlan ]; then
        log "Already loaded: $mod"
        return 0
    fi

    if [ -d "/sys/module/$sysname" ] || grep -q "^$sysname " /proc/modules 2>/dev/null; then
        log "Already loaded: $mod"
        return 0
    fi

    path="$MODULES_DIR/$mod.ko"
    if [ ! -f "$path" ]; then
        path="$(find "$MODULES_DIR" -type f -name "$mod.ko" -print -quit 2>/dev/null)"
    fi

    if [ -n "$path" ] && [ -f "$path" ] && insmod "$path" >> "$LOG" 2>&1; then
        log "Loaded $mod"
    else
        log "Failed to load $mod"
    fi
}

module_deps() {
    local mod="$1"

    if [ -f "$MODULES_DIR/modules.dep" ]; then
        awk -v m="/$mod.ko:" 'index($0, m) { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' \
            "$MODULES_DIR/modules.dep"
    elif command -v modinfo >/dev/null 2>&1; then
        modinfo -F depends "$MODULES_DIR/$mod.ko" 2>/dev/null | tr ',' ' '
    fi
}

module_softdeps() {
    local mod="$1"
    local phase="$2"

    [ -f "$MODULES_DIR/modules.softdep" ] || return 0
    awk -v m="$mod" -v p="$phase" '
        $1 == "softdep" && $2 == m {
            for (i = 3; i <= NF; i++) {
                if ($i == p) {
                    for (j = i + 1; j <= NF; j++)
                        print $j
                    break
                }
            }
        }' "$MODULES_DIR/modules.softdep"
}

load_with_deps() {
    local mod="$1"
    local dep

    case " $LOAD_STACK " in
        *" $mod "*) return 0 ;;
    esac
    LOAD_STACK="$LOAD_STACK $mod"

    for dep in $(module_softdeps "$mod" "pre:"); do
        dep="${dep##*/}"
        dep="${dep%.ko}"
        load_with_deps "$dep"
    done

    for dep in $(module_deps "$mod"); do
        dep="${dep##*/}"
        dep="${dep%.ko}"
        load_with_deps "$dep"
    done

    load_mod "$mod"

    for dep in $(module_softdeps "$mod" "post:"); do
        dep="${dep##*/}"
        dep="${dep%.ko}"
        load_with_deps "$dep"
    done
}

if [ -s "$MODULES_DIR/modules.load" ]; then
    log "Loading modules in modules.load order"

    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(printf '%s' "$line" | tr -d '[:space:]')"
        [ -n "$line" ] || continue
        line="${line##*/}"
        line="${line%.ko}"
        load_with_deps "$line"
    done < "$MODULES_DIR/modules.load"
else
    log "No modules.load; loading all copied modules"

    for path in "$MODULES_DIR"/*.ko; do
        [ -f "$path" ] || continue
        mod="${path##*/}"
        mod="${mod%.ko}"
        load_with_deps "$mod"
    done
fi

setprop twrp.modules.loaded true
log "Kernel module loading complete ($MODULE_SOURCE)"

exit 0
