#!/system/bin/sh

SRC_MODULES_DIR="/vendor/lib/modules"
MODULES_DIR="/tmp/lib/modules"
FW_DIR="/vendor/firmware"
LOG="/tmp/recovery.log"

log() {
    echo "[OF-MODULES] $1" >> "$LOG"
}

log "Mounting /vendor..."
mount /vendor >> "$LOG" 2>&1

# Attende che vendor sia effettivamente disponibile.
while [ ! -d "$SRC_MODULES_DIR" ]; do
    sleep 1
done

log "Vendor modules directory found: $SRC_MODULES_DIR"

mkdir -p /tmp/lib

rm -rf "$MODULES_DIR"

mkdir -p "$MODULES_DIR" || {
    log "ERROR: Cannot create $MODULES_DIR"
    exit 1
}

log "Starting complete modules copy..."

# -a conserva gli attributi; -L segue i link simbolici,
# così i file restano accessibili anche dopo lo smontaggio
# di /vendor.
if cp -aL "$SRC_MODULES_DIR"/. "$MODULES_DIR"/ >> "$LOG" 2>&1; then
    log "Modules copy completed successfully."
else
    log "ERROR: Modules copy failed; keeping /vendor mounted."
    exit 1
fi

# La copia è sincrona: a questo punto cp è terminato.
# Verifica che siano presenti file .ko nella destinazione.
if ! find "$MODULES_DIR" -type f -name '*.ko' -print | grep -q '\.ko$'; then
    log "ERROR: No .ko files found in $MODULES_DIR"
    exit 1
fi

log "Verified copied kernel modules."
if [ -d "$FW_DIR" ]; then
    log "Vendor firmware directory present before unmount."
else
    log "WARNING: Vendor firmware directory not found."
fi

log "Unmounting /vendor..."

if umount -l /vendor >> "$LOG" 2>&1; then
    log "/vendor detached successfully."
else
    log "WARNING: umount -l /vendor failed."
fi

load_mod() {
    local mod="$1"
    local path="$MODULES_DIR/$mod.ko"

    if [ -f "$path" ]; then
        if ! grep -q "^$mod " /proc/modules 2>/dev/null; then
            if insmod "$path"; then
                log "Loaded $mod from $path"
            else
                log "Failed to load $mod from $path"
            fi
        else
            log "Already loaded: $mod"
        fi
    else
        log "Missing copied module: $path"
    fi
}

for mod in \
    lzo_decompress \
    lzo_compress \
    lzo \
    lzo-rle
do
    load_mod "$mod"
done

for mod in \
    sensors_class \
    mmi_annotate \
    mmi_relay \
    mmi_info \
    touchscreen_mmi \
    focaltech_v3 \
    goodix_brl_mmi \
    sx937x_sar \
    awinic_sar \
    rbs_fod_mmi \
    mmi_sys_temp
do
    load_mod "$mod"
done

for mod in \
    q6_pdr_dlkm \
    snd_event_dlkm \
    q6_notifier_dlkm \
    apr_dlkm \
    q6_dlkm \
    swr_dlkm \
    wcd_core_dlkm \
    wcd9xxx_dlkm \
    mbhc_dlkm \
    bolero_cdc_dlkm \
    aw87xxx_dlkm \
    wcd937x_dlkm \
    wcd938x_dlkm \
    wcd937x_slave_dlkm \
    wcd938x_slave_dlkm \
    wsa881x_analog_dlkm \
    aw882xx_acf \
    aw882xx_k419 \
    swr_ctrl_dlkm \
    rx_macro_dlkm \
    tx_macro_dlkm \
    va_macro_dlkm \
    machine_dlkm \
    platform_dlkm \
    native_dlkm \
    adsp_loader_dlkm \
    pinctrl_lpi_dlkm
do
    load_mod "$mod"
done

for mod in \
    camera \
    cci_intf
do
    load_mod "$mod"
done

for mod in \
    rmnet_ctl \
    rmnet_core \
    rmnet_offload \
    rmnet_shs
do
    load_mod "$mod"
done

for mod in \
    btpower \
    bt_fm_slim
do
    load_mod "$mod"
done

for mod in \
    bq25980_mmi_iio \
    mmi_parallel_charger_iio \
    mmi-smbcharger-iio \
    qpnp_adaptive_charge \
    ldo_vibrator_mmi \
    stub_dlkm \
    utags \
    rdbg
do
    load_mod "$mod"
done

for mod in \
    wlan \
    zram \
    exfat \
    sec_nfc
do
    load_mod "$mod"
done

# Firmware check
if [ -d "$FW_DIR" ]; then
    log "Firmware presente"
fi

# Verifica moduli caricati
MODULES_OK=1

for mod in \
    lzo_decompress \
    lzo_compress \
    lzo \
    lzo-rle \
    sensors_class \
    mmi_annotate \
    mmi_relay \
    mmi_info \
    touchscreen_mmi \
    focaltech_v3 \
    goodix_brl_mmi \
    sx937x_sar \
    awinic_sar \
    rbs_fod_mmi \
    mmi_sys_temp \
    q6_pdr_dlkm \
    snd_event_dlkm \
    q6_notifier_dlkm \
    apr_dlkm \
    q6_dlkm \
    swr_dlkm \
    wcd_core_dlkm \
    wcd9xxx_dlkm \
    mbhc_dlkm \
    bolero_cdc_dlkm \
    aw87xxx_dlkm \
    wcd937x_dlkm \
    wcd938x_dlkm \
    wcd937x_slave_dlkm \
    wcd938x_slave_dlkm \
    wsa881x_analog_dlkm \
    aw882xx_acf \
    aw882xx_k419 \
    swr_ctrl_dlkm \
    rx_macro_dlkm \
    tx_macro_dlkm \
    va_macro_dlkm \
    machine_dlkm \
    platform_dlkm \
    native_dlkm \
    adsp_loader_dlkm \
    pinctrl_lpi_dlkm \
    camera \
    cci_intf \
    rmnet_ctl \
    rmnet_core \
    rmnet_offload \
    rmnet_shs \
    btpower \
    bt_fm_slim \
    bq25980_mmi_iio \
    mmi_parallel_charger_iio \
    mmi-smbcharger-iio \
    qpnp_adaptive_charge \
    ldo_vibrator_mmi \
    stub_dlkm \
    utags \
    rdbg \
    wlan \
    zram \
    exfat \
    sec_nfc
do
    if [ ! -d "/sys/module/$mod" ]; then
        log "Module missing: $mod"
        MODULES_OK=0
    fi
done

if [ "$MODULES_OK" -eq 1 ]; then
    setprop twrp.modules.loaded true
    log "All modules loaded successfully."
else
    setprop twrp.modules.loaded true
    log "Some modules failed to load."
fi

exit 0
