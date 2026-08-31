#!/system/bin/sh
# RO2RW vendor-only - Recovery standalone variant
# Expected invocation: /tmp/erofs-recovery.sh
# Optional: /tmp/config.txt

DEBUG=/tmp/erofs-debug.log

rm -f "$DEBUG"

echo "========== EROFS DEBUG ==========" >> "$DEBUG"
echo "SCRIPT STARTED PID=$$ UID=$(id -u)" >> "$DEBUG"

echo "Waiting for /data..." >> "$DEBUG"

DATA_READY=false

for i in $(seq 1 30); do
    if mountpoint -q /data; then
        DATA_READY=true
        echo "/data mounted after ${i}s" >> "$DEBUG"
        break
    fi

    sleep 1
done

if [ "$DATA_READY" != "true" ]; then
    echo "ERROR: /data not mounted" >> "$DEBUG"
    exit 75
fi

TMP_NEO=/data/local/tmp/RO2RW_RECOVERY
TMP_IMGS=$TMP_NEO/imgs
NEO_LOGS=/tmp/NEO.LOGS
OUT_SUPER_DIR=/data/media/0/RO2RW_SUPER

mkdir -p "$TMP_NEO" "$TMP_IMGS" "$NEO_LOGS" || {
    echo "ERROR: cannot create RO2RW directories" >> "$DEBUG"
    exit 75
}

LOG=$TMP_NEO/log.file.txt

echo "RO2RW START" > "$LOG"

CONFIG_FILE="/system/bin/config.txt"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: $CONFIG_FILE not found" >> "$DEBUG"
    exit 75
fi

cp -f "$CONFIG_FILE" "$TMP_NEO/config.txt" || {
    echo "ERROR: cannot copy config.txt" >> "$DEBUG"
    exit 75
}

cp -f "$TMP_NEO/config.txt" "$TMP_NEO/config.sh" || {
    echo "ERROR: cannot create config.sh" >> "$DEBUG"
    exit 75
}

. "$TMP_NEO/config.sh" || {
    echo "ERROR: cannot source config.sh" >> "$DEBUG"
    exit 75
}

echo "CONFIG LOADED" >> "$DEBUG"

arg1="$1"
arg2="$2"
arg3="$3"
VER="RECOVERY-VENDOR"
RSTATUS="RECOVERY"
arch="recovery"

# Recovery tool paths: this device has the required tools in /system/bin.
export PATH=/system/bin:/system/xbin:/sbin:$PATH

# This variant is intended to run directly from Android custom recovery.
# Recovery UI output goes to stdout; menus still use Volume Up/Down.
terminal_on=false
boot_on=false

ui_print() {
    echo -e "$*"
    [ -z "$LOG" ] || echo -e "ui_print: $*" >>"$LOG"
}

abortF() {
    [ -d $NEO_LOGS ] || mkdir -p $NEO_LOGS
    [ -z $LOG ] || echo "Error code $1: RO2RW internal error code $2" &>>$LOG
    logM="Fail-$VER-$(date +%T | sed 's|\:|-|g').txt"
    cat $LOG >$NEO_LOGS/$logM
    [ -f /tmp/recovery.log ] && {
        cat /tmp/recovery.log >>$NEO_LOGS/$logM
    }
    my_print "Output log: $NEO_LOGS/$logM"
    exit $1
}
abortS() {
    my_print "Complete"
    [ -d $NEO_LOGS ] || mkdir -p $NEO_LOGS &>>$LOG
    logM="Success-$VER-$(date +%T | sed 's|\:|-|g').txt"
    cat $LOG >$NEO_LOGS/$logM
    [ -f /tmp/recovery.log ] && {
        cat /tmp/recovery.log >>$NEO_LOGS/$logM
    }
    my_print "Output log $NEO_LOGS/$logM"
    rm -rf $TMP_NEO &>>/dev/null
    rm -rf $TMP_IMGS
    exit 0
}
calc_int() {
    echo "Calc_int: $*" &>>$LOG
    if [ "$(awk 'BEGIN{ if ( '$*' ) print "true" ; else print "false" }')" = "true" ]; then
        return 0
    else
        return 1
    fi
}
find_block() {
    for BLOCK in "$@"; do
        DEVICE=$(find /dev/block/ \( -type b -o -type c -o -type l \) -iname $BLOCK | head -n 1) 2>/dev/null
        if [ ! -z $DEVICE ]; then
            readlink -f $DEVICE
            echo "Finding $BLOCK to $(readlink -f $DEVICE)" &>>$LOG
            return 0
        fi
    done
    echo "Can't find:$*" &>>$LOG
    return 1
}
my_print() {
    text="$@"
    if [ "$1" = "selected" ]; then
        text="${text#*selected }"
        first_line=false
        new_line_comment=false
    elif [ "$1" = "commented" ]; then
        text="${text#*commented }"
        new_line_comment=true
        first_line=false
    else
        new_line_comment=false
        first_line=true
    fi
    all_char="${#text}"
    space_n=-1
    skipG="* "
    tmp_word=""
    tmp_word2=""
    tick=0
    { [ -z "$text" ] || [ "$text" = " " ]; } && first_line=false
    space="$(
        for i in $text; do space_n=$((space_n + 1)); done
        echo $space_n
    )"

    if (calc_int "$all_char>=43") && (calc_int "$space>=1"); then
        while (($tick < $space)); do
            tmp_word2="${text#$skipG}"
            tmp_word="${text%"$tmp_word2"*}"
            tick=$((tick + 1))
            if ((${#tmp_word} > 43)); then
                skipG="* "
                $first_line && {
                    $new_line_comment && ui_print "     $tmp_word" || ui_print "- $tmp_word"
                    first_line=false
                } || {
                    $new_line_comment && ui_print "     $tmp_word" || ui_print "  $tmp_word"
                }
                text="${text#*"$tmp_word"}"
            else
                skipG="${skipG}* "
                continue
            fi
        done
        $first_line && {
            $new_line_comment && ui_print "     $text" || ui_print "- $text"
            first_line=false
        } || {
            $new_line_comment && ui_print "     $text" || ui_print "  $text"
        }
    else $first_line && {
        $new_line_comment && ui_print "     $text" || ui_print "- $text"
        first_line=false
    } || {
        $new_line_comment && ui_print "     $text" || ui_print "  $text"
    }; fi
}

MYSELECT() {
    ui_print ""
    text_for_select=""
    text_select=""
    text_input=""
    text_commend=""
    main_text="$1"
    echo $main_text | grep -q ":EXIT:" && OUT_SELECT="EXIT" && main_text=${main_text%:EXIT:*} || OUT_SELECT="EXIT"
    [ -z "$main_text" ] || my_print "$main_text"
    ui_print ""
    tick_for=1
    for text_S in "$@"; do
        if ! [ "$text_S" = "$1" ]; then
            [ -z "$text_S" ] && break
            text_input=${text_S%:comment:*}
            text_select=${text_input#*:select:}
            text_input=${text_input%:select:*}
            text_commend=${text_S#*:comment:}

            my_print "selected" "${tick_for}) [$text_input]"
            if (echo "$text_S" | grep -q ':comment:'); then
                my_print "commented" "${text_commend}"
            fi
            [ -z "$text_for_select" ] &&
                text_for_select="${tick_for}) $text_select" ||
                text_for_select="${text_for_select}\n${tick_for}) ${text_select}"
            tick_for=$((tick_for + 1))
        fi
    done

    text_for_select="${text_for_select}\n${OUT_SELECT}"
    my_print "selected" "${tick_for}) [$OUT_SELECT]"
    tick_select=1
    all_ticks=$(echo -e $text_for_select | wc -l)
    $boot_on && {
        while true; do
            echo -n " - Select num: "
            read tick_select
            if (calc_int "$tick_for>=$tick_select") && (calc_int "$tick_select>=1"); then
                break
            else
                my_print "Enter a number from 1 to $tick_for"
            fi
        done
    } || {
        my_print "Use Volume Key (+) to switch. Use Volume key (-) to select"
        while true; do
            my_print "selected" "$tick_select)  > $(echo -e $text_for_select | head -n$tick_select | tail -n1 | sed 's|'$tick_select') ||') <"
            if chooseport 60; then
                tick_select=$((tick_select + 1))
            else
                break
            fi
            if [ $tick_select -gt $all_ticks ]; then
                tick_select=1
            fi
        done
    }
    my_print "selected" "$tick_select)  >[$(echo -e $text_for_select | head -n$tick_select | tail -n1 | sed 's|'$tick_select') ||')]<"
    ui_print " "
    ui_print "**==================================***"
    if [ "$(echo -e $text_for_select | head -n$tick_select | tail -n1)" = "${OUT_SELECT}" ]; then
        [ "$OUT_SELECT" = "EXIT" ] && abortF 0 214 || abortF 0 214.1 #main_menu
    fi
    if [ $all_ticks -le 3 ]; then
        [ $tick_select = 1 ] && return 1
        [ $tick_select = 2 ] && return 2
    else
        return $tick_select
    fi
}

chooseport() {
    # Original idea by chainfire and ianmacd @xda-developers
    [ "$1" ] && local delay=$1 || local delay=3
    local error=false
    while true; do
        local count=0
        while true; do
            timeout 0.5 getevent -lqc 1 2>&1 >$TMP_NEO/events &
            sleep 0.1
            count=$((count + 1))
            if (grep -q 'KEY_VOLUMEUP *DOWN' $TMP_NEO/events); then
                return 0
            elif (grep -q 'KEY_VOLUMEDOWN *DOWN' $TMP_NEO/events); then
                return 1
            fi
            [ $count -gt 100 ] && break
        done
        if $error && ! $REMOVE_TIMEOUT_KEY; then
            my_print "TimeOUT key"
            abortF 90 243
        else
            error=true
            ui_print " "
            my_print "TimeOUT"
        fi
    done
}

calc() {
    awk 'BEGIN{ print int('$1') }'
    echo -n "calc: $* = " &>>$LOG
    awk 'BEGIN{ print int('$1') }' &>>$LOG
}
calc_imgs() {
    pop=0
    for i in $TMP_IMGS/*.img; do
        pop=$(calc "$(stat -c%s "$i")+$pop")
        echo "Calculate: "$i", $(stat -c%s "$i"), all now:$pop" &>>$LOG
    done
    echo $pop
    echo "All size imgs:$pop" &>>$LOG
}
calc_sort() {
    case $1 in
    1 | 0)
        sort_max=20
        sort_min=10
        ;;
    2)
        sort_max=30
        sort_min=20
        ;;
    3)
        sort_max=40
        sort_min=30
        ;;
    4)
        sort_max=50
        sort_min=40
        ;;
    5)
        sort_max=70
        sort_min=50
        ;;
    6)
        sort_max=100
        sort_min=70
        ;;
    7)
        sort_max=150
        sort_min=100
        ;;
    8 | 9)
        sort_max=1000
        sort_min=150
        ;;
    esac
}
tabul="
"
DFE() {

    fstabp="$1"

    g=$(

        echo "fileencryption="
        echo "forcefdeorfbe="
        echo "encryptable="
        echo "forceencrypt="
        echo "metadata_encryption="
        echo "keydirectory="
        echo "avb="
        echo "avb_keys="

    )

    g2=$(

        echo "avb"
        echo "quota"
        echo "inlinecrypt"
        echo "wrappedkey"

    )
    my_print "Patching $(basename $fstabp) for DFE"
    while ($(
        for i in $g; do grep -q "$i" $fstabp && return 0; done
        return 1
    )); do
        fstabp_now=$(cat "$fstabp")
        for remove in $g; do
            grep -q "$remove" "$fstabp" && {
                remove_now="${fstabp_now#*"$remove"}"
                remove_now="${remove_now%%,*}"
                remove_now="${remove}${remove_now%%"$tabul"*}"
            } || {
                continue
            }
            grep -q ",$remove_now" "$fstabp" && {
                sed -i 's|,'$remove_now'||' $fstabp &>>$LOG
            }
            grep -q "$remove_now" "$fstabp" && {
                sed -i 's|'$remove_now'||' $fstabp &>>$LOG
            }
            echo " Remove $remove_now FLAG" &>>$LOG
        done
    done
    if ($(
        for i in $g2; do
            grep -q "$i" $fstabp && return 0
        done
        return 1
    )); then
        for remove in $g2; do
            grep -q ",$remove" $fstabp && sed -i 's|,'$remove'||g' $fstabp &>>$LOG
            grep -q "$remove," $fstabp && sed -i 's|'$remove',||g' $fstabp &>>$LOG
            grep -q "$remove" $fstabp && sed -i 's|'$remove'||g' $fstabp &>>$LOG
            echo "Remove $remove FLAG" &>>$LOG
        done
    fi
    #sed -i 's|/devices/platform/|#/devices/platform/|g' $fstabp
}

remove_list() {

    clear
    if (calc_int "$sort_size>8"); then
        sort_size=8
    elif (calc_int "$sort_size<1"); then
        sort_size=1
    fi
    #size_plus=$( if (( $size_plus > 200 )) ; then echo 100 ; elif (( $size_plus > 100 )) ; then echo 50 ; elif (( $size_plus > 50 )) ; then echo 20 ; elif (( $size_plus > 10 )) ; then echo 10 ; fi )

    calc_sort $sort_size
    MYSELECT "You need to remove something, Sorting apps list ${sort_min}Mb-${sort_max}Mb$([ "$1" = "Break" ] || echo ", need $(calc "($(calc_imgs)-$Ss-8388608)/1024/1024") mb free size:")" \
        $1 "Sort to $(
            calc_sort $(calc "$sort_size+1")
            echo "${sort_min}Mb-${sort_max}Mb"
        )" \
        "Sort to $(
            calc_sort $(calc "$sort_size-1")
            echo "${sort_min}Mb-${sort_max}Mb"
        )" \
        $(
            calc_sort $sort_size
            for filesss in $(find $TMP_IMGS/* -mindepth 1 -size +${sort_min}M -and -size -${sort_max}M -type f -name "*.apk") \
                $(find $TMP_IMGS/* -mindepth 1 -size +${sort_min}M -and -size -${sort_max}M -type f -name "*.zip"); do
                echo "$(du -sh "$(dirname $filesss)" | awk '{print $1}')-$(basename "$filesss"):comment:located:$(read_main_dir ${filesss#*"$TMP_IMGS"})"
            done
        )
    move_list=$?
    [ "$1" = "Break" ] && { move_list=$((move_list - 1)); }
    case $move_list in
    0) return 1 ;;
    1) sort_size=$(calc "$sort_size+1") ;;
    2) sort_size=$(calc "$sort_size-1") ;;
    *)
        f=$(echo -e $text_for_select | head -n$tick_select | tail -n1 | sed 's|'$tick_select') ||')
        FILE_REM=$(find "$TMP_IMGS"/ -name "*${f#*-}")
        MYSELECT "REMOVE "$(dirname ${FILE_REM#*"$TMP_IMGS/"})"?" "YES" "NO"
        [ $? = 1 ] && rm -rf $(dirname $FILE_REM)
        for filei in $TMP_IMGS/*.img; do
            force_umount "${filei%.img*}"
            rw_minimize "$filei"
            case $RW_SIZE_MOD in
            FIXED)
                rw_expand "$filei" "$(calc "$RW_SIZE*1024*1024")"
                ;;
            esac
            try_mount -w -t ext4 "$filei" "${filei%.img*}" || abortF 33 48266

        done

        ;;
    esac

}

calc_super() {

    my_print "Calculating free size for VENDOR only"

    Ss=$(for i in $($lpdump_bin --slot=$SLOT "$SUPER_PATH" |
        grep -F "Size:" |
        awk '{print $2}'); do
        (calc_int "$i>20") && echo $i && break
    done)

    vendor_img=""

    for filei in $TMP_IMGS/*.img; do
        case "$(basename "$filei")" in
            vendor.img|vendor_a.img|vendor_b.img)
                vendor_img="$filei"
                ;;
        esac
    done

    [ -n "$vendor_img" ] || abortF 92 4431

    # Only vendor is allowed to be resized.
    force_umount "${vendor_img%.img*}" 2>/dev/null

    # First make sure all non-vendor images remain untouched.
    all_size_img=0

    for filei in $TMP_IMGS/*.img; do
        case "$(basename "$filei")" in
            vendor.img|vendor_a.img|vendor_b.img)
                rw_minimize "$filei"
                ;;
            *)
                # NEVER resize non-vendor partitions.
                ;;
        esac
    done

    # Calculate the amount of free space in SUPER.
    all_size_img=$(calc_imgs)

    free_size=$(calc "$Ss-$all_size_img")

    # Leave room for SUPER metadata.
    if (calc_int "16777216<$free_size"); then
        free_size=$(calc "$free_size-16777216")
    elif (calc_int "8388608<$free_size"); then
        free_size=$(calc "$free_size-8388608")
    fi

    (calc_int "$free_size<0") && abortF 91 443

    case $RW_SIZE_MOD in

    MAX)
        # ALL available expandable space goes to vendor.
        rw_expand "$vendor_img" "$free_size"
        ;;

    FIXED)
        vendor_expand=$(calc "$RW_SIZE*1024*1024")

        (calc_int "$vendor_expand>$free_size") &&
            abortF 91 444

        rw_expand "$vendor_img" "$vendor_expand"
        ;;

    esac

    my_print "Vendor-only expansion completed"
}
tabul="
"
patch_vendor_fstab() {
    rwro=$1
    for x in vendor_boot$SLOT boot$SLOT; do
        find_block "$x" &>/dev/null && {
            BXF=$x
            x=$(find_block "$x")
            cd $TMP_NEO
            XF=$TMP_NEO/boot/$BXF
            my_print "Starting patching $BXF"

            mkdir -pv $XF/ram
            cd $XF

            magiskboot unpack $x &>$XF/log.unpack.boot
            if [ -f $XF/log.unpack.boot ] && [ -f $XF/ramdisk.cpio ]; then
                cat $XF/log.unpack.boot &>>$LOG
                raw_ram=false
                cat $XF/log.unpack.boot | grep "RAMDISK_FMT" | grep "raw" &>>$LOG && {
                    magiskboot decompress $XF/ramdisk.cpio $XF/ramdisk.d.cpio &>$XF/log.decompress
                    rm -f $XF/ramdisk.cpio
                    mv $XF/ramdisk.d.cpio $XF/ramdisk.cpio
                    raw_ram=true
                    compress_format=$(grep "Detected format:" $XF/log.decompress)
                    compress_format=${compress_format#*[}
                    compress_format=${compress_format%]*}
                }
                cd $XF/ram
                magiskboot cpio ../ramdisk.cpio extract && {
                    for fff in $(find ./ -name *fstab*); do
                        patch_avb() {
                            fstabp="$1"
                            g="avb= avb_keys="
                            g2="avb"
                            while grep -E "avb=|avb_keys=" $fstabp; do
                                fstabp_now=$(cat "$fstabp")
                                for remove in $g; do
                                    grep -q "$remove" "$fstabp" && {
                                        remove_now=$(grep "$remove" "$fstabp" | head -n1 | awk '{print $5}')
                                        remove_now="$remove${remove_now#*"$remove"}"
                                        remove_now="${remove_now%%\,*}"
                                    } || {
                                        continue
                                    }
                                    grep -q "$remove_now," "$fstabp" && {
                                        sed -i 's|'$remove_now',||' $fstabp &>>$LOG
                                    }
                                    grep -q ",$remove_now" "$fstabp" && {
                                        sed -i 's|,'$remove_now'||' $fstabp &>>$LOG
                                    }
                                    grep -q "$remove_now" "$fstabp" && {
                                        sed -i 's|'$remove_now'||' $fstabp &>>$LOG
                                    }
                                    echo " Remove $remove_now FLAG" #&>>$LOG
                                done
                            done
                            if grep avb $fstabp; then
                                for remove in $g2; do
                                    grep -q ",$remove" $fstabp && sed -i 's|,'$remove'||g' $fstabp &>>$LOG
                                    grep -q "$remove," $fstabp && sed -i 's|'$remove',||g' $fstabp &>>$LOG
                                    grep -q "$remove" $fstabp && sed -i 's|'$remove'||g' $fstabp &>>$LOG
                                    echo "Remove $remove FLAG" &>>$LOG
                                done
                            fi
                        }
                        # awk -v word="$partition" '$1 == word {print}'
                        grep "first_stage_mount" "$fff" | grep -w "system" && {
                            patch_avb $fff
                            for FS_TYPE in ext4 f2fs erofs; do
                                ext4_line=$(cat "$fff" | awk -v word="system" -v fstype="$FS_TYPE" '$1 == word && $3 == fstype {print $5}')
                                [ -n "$ext4_line" ] && break
                            done
                            for partititon in $(check_partition_lpdump); do
                                [ -z $SLOT ] || partititon=${partititon:0:${#partititon}-2}

                                [ -n "$partititon" ] && {
                                    original_line=""
                                    edit=""
                                    for FS_TYPE in ext4 f2fs erofs; do
                                        original_line=$(cat "$fff" | awk -v word="$partititon" -v fstype="$FS_TYPE" '$1 == word && $3 == fstype {print}')
                                        [ -n "$original_line" ] && break
                                    done
                                    [ -n "$original_line" ] && {
                                        while (("$(cat "$fff" | awk -v word="$partititon" '$1 == word {print}' | wc -l)" > 1)); do
                                            remove_line_part="$(cat "$fff" | awk -v word="$partititon" '$1 == word {print}' | tail -n1)"
                                            sed -i "\|$remove_line_part|d" $fff
                                        done
                                        edit=$(echo -e "$original_line" | awk '{print $1" "$2}')
                                        for FS_TYPE in ext4 f2fs erofs; do
                                            check_fs_line=$(cat "$fff" | awk -v word="$partititon" -v fstype="$FS_TYPE" '$1 == word && $3 == fstype {print}')
                                            [ -n "$check_fs_line" ] && {
                                                edit_ext4="$edit ext4 $rwro $ext4_line"
                                                edit_f2fs="$edit f2fs $rwro $ext4_line"
                                                edit_erofs="$edit erofs ro $ext4_line"
                                                sed -i 's|'"$check_fs_line"'|'"$edit_erofs\n$edit_ext4\n$edit_f2fs"'|' $fff && {
                                                    my_print "Add line ext4-$rwro f2fs-$rwro erofs-ro for $partititon"
                                                    cont_rep=true
                                                    break
                                                }
                                            }
                                        done
                                    }
                                }
                            done
                            magiskboot cpio ../ramdisk.cpio "add 750 ${fff#*\.\/} $fff"
                        }

                    done
                    cd $XF
                    $raw_ram && {
                        magiskboot compress=$compress_format ramdisk.cpio ramdisk.c.cpio
                        rm -f ramdisk.cpio
                        mv ramdisk.c.cpio ramdisk.cpio
                    }
                    magiskboot repack $x
                    cat new-boot.img >$x
                }
            else
                my_print "Skip $BXF"
            fi
        }
    done

}
check_free_data() {
    if (calc_int "$(df /$check_size_main_path/ | wc -l)==2"); then
        free_data=$(df /$check_size_main_path/ | tail -n1 | awk '{print int($4)}')
    elif (calc_int "$(df /$check_size_main_path/ | wc -l)==3"); then
        free_data=$(df /$check_size_main_path/ | tail -n1 | awk '{print int($3)}')
    else
        my_print "Can't calculate free size data"
        abortF 82 458
    fi
    calc_int "$(calc "$free_data/1024/1024")>$(calc "($Ss/1024/1024/1024)+1")" && {
        return 0
    } || {
        return 1
    }
}
run_backup_vbmeta() {
    for file_vbmeta in /dev/block/by-name/*vbmeta*$SLOT; do
        cat $file_vbmeta >$OUT_SUPER_DIR/$(basename $file_vbmeta).original.img
    done
}
rm_old_backup() {
    my_print "Please Wait, backing up super..."
    [ -d $OUT_SUPER_DIR ] && {
        rm -f $OUT_SUPER_DIR/super.backup.*img
    } || {
        mkdir $OUT_SUPER_DIR

    }
}
run_backup_sparse() {
    rm_old_backup
    img2simg "$SUPER_PATH" $OUT_SUPER_DIR/super-backup-sparse-fastboot$([ -z $SLOT ] || echo "-active-$SLOT").img
    my_print "Output file"
    my_print "$OUT_SUPER_DIR/super-backup-sparse-fastboot$([ -z $SLOT ] || echo "-active-$SLOT").img"
}

run_backup_row() {
    rm_old_backup
    cat "$SUPER_PATH" >$OUT_SUPER_DIR/super-backup-row-recovery$([ -z $SLOT ] || echo "-active-$SLOT").img
    my_print "Output file"
    my_print "$OUT_SUPER_DIR/super-backup-row-recovery$([ -z $SLOT ] || echo "-active-$SLOT").img"
}
bak_super_to() {

    $FORCE_START && {
        (check_free_data) || abortF 14 9123
        case $BACKUP_ORIGINAL_SUPER in
        "true:row" | "true:recovery")
            run_backup_row
            run_backup_vbmeta
            ;;
        "true:sparse" | "true:fastboot")
            run_backup_sparse
            run_backup_vbmeta
            ;;
        esac

    } || {
        MYSELECT "You want to make a backup of original super?" "YES" "NO"
        case $? in
        1)
            $terminal_on && {
                while ! (check_free_data); do
                    my_print "Still need $(calc "($Ss/1024/1024/1024)+1") GB+ internal storage memory for contiue"
                    ui_print "- Enter any key to continue:\n"
                    read ooooo
                done
            } || {
                ! (check_free_data) && {
                    my_print "There is not enough memory in the internal storage.  Continue without backup, or abort the operation?" "Continue" "Break"
                    case $? in
                    1) return 1 ;;
                    2) abortF 1 464 ;;
                    esac
                }
            }

            MYSELECT "Output Bak-super.img file for fastboot/sparse or recovery/row?" "FASTBOOT/SPARSE" "RECOVERY/ROW"
            case $? in
            1)
                run_backup_sparse
                ;;
            2)
                run_backup_row
                ;;

            esac
            run_backup_vbmeta
            ;;
        esac
    }
}

make_super() {
    # if $f2fs_re; then
    #     non_used1(){
    #         if [ $(getenforce) = "Enforcing" ]; then
    #             setenforce 0
    #             returnen=true
    #         else
    #             returnen=false
    #         fi

    #         plus_size_f2fs=$(calc "262143000/$(find $TMP_IMGS/*.img | wc -l)")
    #         for f2fsimg in $TMP_IMGS/*.img; do

    #             mkdir -p "$f2fsimg".ext4 &>>$LOG
    #             chcon u:object_r:media_rw_data_file:s0 "$f2fsimg" &>>$LOG
    #             try_mount -w -t ext4 "$f2fsimg" "$f2fsimg.ext4" || abortF 33 2312
    #             mkdir -p "$f2fsimg".f2fs &>>$LOG
    #             make_ext4fs -J -T 1230764400 -l $(calc "$(stat -c%s "$f2fsimg")+$plus_size_f2fs") "$f2fsimg".f2fs.img &>>$LOG
    #             if (type make.f2fs &>>$LOG); then
    #                 make.f2fs -O extra_attr,compression "$f2fsimg".f2fs.img &>>$LOG
    #             elif (type make_f2fs &>>$LOG); then
    #                 make_f2fs -O extra_attr,compression "$f2fsimg".f2fs.img &>>$LOG
    #             else
    #                 abortF 4 4123
    #             fi
    #             chcon u:object_r:media_rw_data_file:s0 "$f2fsimg".f2fs.img
    #             try_mount -w -t f2fs "$f2fsimg.f2fs.img" "$f2fsimg.f2fs" || abortF 36 12355

    #             cp -rp "$f2fsimg".ext4/* "$f2fsimg".f2fs/ &>>$LOG

    #             force_umount "$f2fsimg.ext4"
    #             force_umount "$f2fsimg.f2fs"

    #             rm -f "$f2fsimg" &>>$LOG
    #             mv "$f2fsimg".f2fs.img "$f2fsimg" &>>$LOG
    #         done

    #         $returnen && setenforce 1
    #     }
    # fi

    mslot=$(for i in $(grep -F "Metadata slot count:" $LPDUMP | awk '{print $4}'); do echo $i && break; done)
    Ss=$(for i in $(grep -F "Size:" $LPDUMP | awk '{print $2}'); do (calc_int "$i>20") && echo $i && break; done)
    gp=$(cat $LPDUMP | head -n$(grep -n "Maximum size:" $LPDUMP | awk '{ if ($4>20000000) print int($1-1)}' | head -n1) | tail -n1 | awk '{print $2}')
    [ -z $gp ] && gp="qti_partition$SLOT"
    part_s=$(for i in $TMP_IMGS/*.img; do echo "--partition $(basename "$i" | sed 's|.img||'):none:$(stat -c%s "$i"):$gp --image $(basename "$i" | sed 's|.img||')=$i"; done)
    bak_super_to
    if $terminal_on; then
        while ! (check_free_data) && $terminal_on; do
            my_print "Still need $(calc "($Ss/1024/1024/1024)+1") GB+ internal storage memory to continue"
            ui_print "- Enter any key:\n"
            read ooooo
        done
        MYSELECT "Output RW-super.img file for fastboot(SPARSE) or recovery(ROW)?" "FASTBOOT/SPARSE" "RECOVERY/ROW"
        case $? in
        1)
            my_print "Making new super and saving to"
            my_print "$OUT_SUPER_DIR/super.rw.sparse.fastboot.img"
            lp="--metadata-size 65536 --sparse --super-name super --metadata-slots $mslot --device super:$Ss --group $gp:$(calc "$Ss-6008608") $part_s --output $OUT_SUPER_DIR/super-rw-sparse-fastboot$([ -z $SLOT ] || echo "-active-$SLOT").img"
            ;;
        2)
            my_print "Making new super and saving to"
            my_print "$OUT_SUPER_DIR/super.rw.row.recovery.img"
            lp="--metadata-size 65536 --super-name super --metadata-slots $mslot --device super:$Ss --group $gp:$(calc "$Ss-6008608") $part_s --output $OUT_SUPER_DIR/super-rw-row-recovery$([ -z $SLOT ] || echo "-active-$SLOT").img"
            ;;
        esac

    else
        my_print "Making new super and writing in block "$SUPER_PATH""
        lp="--metadata-size 65536 --super-name super --metadata-slots $mslot --device super:$Ss --group $gp:$(calc "$Ss-6008608") $part_s --output "$SUPER_PATH""
    fi
    echo $lp &>>$LOG

    $terminal_on && {
        [ -d $OUT_SUPER_DIR/ ] || mkdir $OUT_SUPER_DIR
        rm -f $OUT_SUPER_DIR/super.rw.*.img
    }
    my_print "Please Wait..."
    lpmake $lp &>>$LOG || abortF 88 517

    #             for boot_rec in recovery recovery_a recovery_b ; do
    #             find /dev/block/ -name "$boot_rec" | grep "$boot_rec" && {
    #                 mkdir -pv $TMP_NEO/boot/$boot_rec/ram
    #                 magiskboot unpack /dev/block/by-name/$boot_rec &> $TMP_NEO/boot/$boot_rec/ram/log.unpack.boot
    #                 [ -f $TMP_NEO/boot/$boot_rec/ram/log.unpack.boot ] && {
    #                     raw_ram=false
    #                     cat $TMP_NEO/boot/$boot_rec/ram/log.unpack.boot | grep RAMDISK_FMT | grep raw && {
    #                         magiskboot decompress $TMP_NEO/boot/$boot_rec/ramdisk.cpio $TMP_NEO/boot/$boot_rec/ramdisk.d.cpio &> $TMP_NEO/boot/$boot_rec/log.decompress
    #                         rm -f $TMP_NEO/boot/$boot_rec/ramdisk.cpio
    #                         mv $TMP_NEO/boot/$boot_rec/ramdisk.d.cpio $TMP_NEO/boot/$boot_rec/ramdisk.cpio
    #                         compress_format=$(grep "Detected format:" $TMP_NEO/boot/$boot_rec/log.decompress)
    #                         compress_format=${compress_format#*\[} ; compress_format=${compress_format%]*}
    #                         raw_ram=true
    #                     }
    #                     [ -f $TMP_NEO/boot/$boot_rec/ramdisk.cpio ] && {
    #                         [ -z "$SLOT" ] && slot_sel="" || slot_sel=";slotselect"
    #                         cd $TMP_NEO/boot/$boot_rec/ram
    #                         magiskboot cpio $TMP_NEO/boot/$boot_rec/ramdisk.cpio extract
    #                             echo "system_root ext4 /dev/block/mapper/system flags=backup=1;flashimg$slot_sel;display=\"System RO2RW\"
    # /vendor ext4 /dev/block/mapper/vendor flags=backup=1;flashimg$slot_sel;display=\"Vendor RO2RW\"
    # /odm ext4 /dev/block/mapper/odm flags=backup=1;flashimg$slot_sel;display=\"Odm RO2RW\"
    # /system_ext ext4 /dev/block/mapper/system_ext flags=backup=1;flashimg$slot_sel;display=\"System_ext RO2RW\"
    # /product ext4 /dev/block/mapper/product flags=backup=1;flashimg$slot_sel;display=\"Product RO2RW\"" >> $TMP_NEO/boot/$boot_rec/ram/system/etc/twrp.flags
    #                             magiskboot cpio $TMP_NEO/boot/$boot_rec/ramdisk.cpio "add 750 system/etc/twrp.flags $TMP_NEO/boot/$boot_rec/ram/system/etc/twrp.flags"
    #                             cd $TMP_NEO/boot/$boot_rec
    #                             $raw_ram && {
    #                                 magiskboot compress="$compress_format" $TMP_NEO/boot/$boot_rec/ramdisk.cpio $TMP_NEO/boot/$boot_rec/ramdisk.c.cpio
    #                                 rm -f $TMP_NEO/boot/$boot_rec/ramdisk.cpio
    #                                 mv $TMP_NEO/boot/$boot_rec/ramdisk.c.cpio $TMP_NEO/boot/$boot_rec/ramdisk.cpio
    #                             }
    #                             magiskboot repack /dev/block/by-name/$boot_rec
    #                             cat $TMP_NEO/boot/$boot_rec/new-boot.img > /dev/block/by-name/$boot_rec

    #                     }
    #                 }
    #             }

    #             done

}

patch_fstab_ext4() {
    ext4_fstab="$1"

    grep "first_stage_mount" "$ext4_fstab" | grep -w "system" | grep "ext4" && {
        ext4_line=$(grep "first_stage_mount" "$ext4_fstab" | grep -w "system" | grep "ext4" | awk '{print $3" "$4" "$5}')
        for extpart in $(check_partition_lpdump); do

            if [ -z $SLOT ]; then
                fstab_name=$extpart
            else
                fstab_name=${extpart:0:${#extpart}-2}
            fi
            [ "$fstab_name" = "system" ] || {
                original=$(grep -w "$fstab_name" $ext4_fstab | grep "/$fstab_name" | grep -w "f2fs")
                if [ -n "$original" ]; then
                    edit=$(echo "$original" | awk '{print $1" "$2" '$ext4_line'"}')
                    sed -i 's|'"$original"'|'"$original\n$edit"'|' $ext4_fstab
                fi
            }

        done

        fstabp="$ext4_fstab"

        g=$(
            echo "avb="
            echo "avb_keys="
        )

        g2=$(

            echo "avb"

        )
        my_print "Patching $(basename $fstabp) for DFE"
        while ($(
            for i in $g; do grep -q "$i" $fstabp && return 0; done
            return 1
        )); do
            fstabp_now=$(cat "$fstabp")
            for remove in $g; do
                grep -q "$remove" "$fstabp" && {
                    remove_now="${fstabp_now#*"$remove"}"
                    remove_now="${remove_now%%,*}"
                    remove_now="${remove}${remove_now%%"$tabul"*}"
                } || {
                    continue
                }
                grep -q ",$remove_now" "$fstabp" && {
                    sed -i 's|,'$remove_now'||' $fstabp &>>$LOG
                }
                grep -q "$remove_now" "$fstabp" && {
                    sed -i 's|'$remove_now'||' $fstabp &>>$LOG
                }
                echo " Remove $remove_now FLAG" &>>$LOG
            done
        done
        if ($(
            for i in $g2; do
                grep -q "$i" $fstabp && return 0
            done
            return 1
        )); then
            for remove in $g2; do
                grep -q ",$remove" $fstabp && sed -i 's|,'$remove'||g' $fstabp &>>$LOG
                grep -q "$remove," $fstabp && sed -i 's|'$remove',||g' $fstabp &>>$LOG
                grep -q "$remove" $fstabp && sed -i 's|'$remove'||g' $fstabp &>>$LOG
                echo "Remove $remove FLAG" &>>$LOG
            done
        fi
    } || return 1

}

check_partition_lpdump() {
    [ -z "$SLOT" ] && {
        echo "${td%Super partition layout:*}" | grep Name: | awk '{print $2}'
    } || {
        echo "${td%Super partition layout:*}" | grep Name: | grep $SLOT | awk '{print $2}'
    }
}

force_umount_dm() {
    ticksss=0
    while (mount | grep "$1 " &>>$LOG); do
        umount -fl $1 &>>$LOG
        (($ticksss > 10)) && return 0 || ticksss=$((ticksss + 1))
    done
    return 0
}
make_img() {
    all_size_for_expand=8
    td=$(cat $LPDUMP)
    td="${td#*Partition table:}"
    [ -z "$td" ] && abortF 3 536
    my_print "Detected partitions: "$(check_partition_lpdump)
for part in $(check_partition_lpdump); do

    i=$(find_block $part ${part:0:${#part}-2})
    echo "$part $i" &>>$LOG

    case $part in
    *-cow*)
        echo "$part COW" &>>$LOG
        ;;

    vendor|vendor_a|vendor_b)
        $boot_on || force_umount_dm "$i"
        my_print "Processing ONLY $part"
        migrate_files "$i" "$part"

        case $RW_SIZE_MOD in
        FIXED)
            all_size_for_expand=$((all_size_for_expand + $RW_SIZE))
            ;;
        esac
        ;;

    *)
        # Keep every non-vendor partition completely untouched.
        my_print "Keeping $part unchanged"
        cat "$i" > "$TMP_IMGS/$part.img" || abortF 1 684

        # Do NOT minimize, resize, mount or convert it.
        ;;
    esac

done
    cd $TMP_NEO
    all_size_for_expand=$(calc "$all_size_for_expand*1024*1024")
}
rw_minimize() {
    echo "Minimize $1" &>>$LOG
    resize2fs -f $1 $(calc "$(stat -c%s $1)*1.25/512")s &>>$LOG
    e2fsck -y -E unshare_blocks $1 &>>$LOG
    resize2fs -f -M $1 &>>$LOG
    resize2fs -f -M $1 &>>$LOG
}
rw_expand() {
    echo "Resizing $1 + $2 Bytes to "$(calc "($(stat -c%s $1)+$2)")" Bytes" &>>$LOG
    resize2fs -f $1 "$(calc "($(stat -c%s $1)+$2)/512")"s &>>$LOG
}

erofs2ext4() {
    cd $TMP_IMGS
    mkdir $TMP_NEO/blocks &>>$LOG
    ln -s $1 $TMP_NEO/blocks/$3.img &>>$LOG
    erofs -i "$TMP_NEO/blocks/$3.img" -x -o ./ &>$TMP_NEO/LOG.EXTEACT.${3}.txt || {
        cat $TMP_NEO/LOG.EXTEACT.${3}.txt &>>$LOG
        rm -f $TMP_NEO/blocks/$3.img &>>$LOG
        rm -rf "$TMP_IMGS/$3" &>>$LOG
        return 1
    }
    grep -q "exception occurred while fetching" $TMP_NEO/LOG.EXTEACT.${3}.txt && {
        cat $TMP_NEO/LOG.EXTEACT.${3}.txt &>>$LOG
        rm -f $TMP_NEO/blocks/$3.img &>>$LOG
        rm -rf "$TMP_IMGS/$3" &>>$LOG
        return 1
    }
    cat $TMP_NEO/LOG.EXTEACT.${3}.txt &>>$LOG
    make_ext4fs -J -T 1230764400 \
        -S "$TMP_IMGS"/config/$3_file_contexts \
        -l "$(du -sb "$TMP_IMGS"/$3 | awk '{print int($1*2)}')" \
        -C "$TMP_IMGS"/config/$3_fs_config -a "$3" -L "$3" \
        "$TMP_IMGS"/$3.img "$TMP_IMGS"/$3 &>>$LOG
    rm -f $TMP_NEO/blocks/$3.img &>>$LOG
    rm -rf "$TMP_IMGS"/$3 &>>$LOG
    mkdir -p "$TMP_IMGS"/$2 &>>$LOG
    mv "$TMP_IMGS"/$3.img "$TMP_IMGS"/$2.img &>>$LOG
}

force_umount() {
    ticksss=0
    [ -d "$1" ] && {
        while (mountpoint -q "$1"); do
            umount -f -l "$1" &>>$LOG
            (($ticksss > 10)) && return 1 || ticksss=$((ticksss + 1))
        done
    }
    return 0

}
try_mount() {
    ticksss=0
    (grep -q "$(basename $5)" "$TMP_NEO/mount_problem.txt") && {
        return 0
    } || {
        while ! (mountpoint -q "$5"); do
            mount $1 $2 $3 "$4" "$5" &>>$LOG
            (($ticksss > 10)) && return 1 || ticksss=$((ticksss + 1))
        done
        return 0
    }
}

if_mount_problem_func() {
    force_umount ""$TMP_IMGS"/$2"
    force_umount ""$TMP_IMGS"/${2}_block"
    $ext4_img && {
        $FORCE_START && {
            $IF_EXT4_MOUNT_PROBLEM_CONTINUE && {
                echo "$2" >>$TMP_NEO/mount_problem.txt
                rm -rf "$TMP_IMGS"/${2}
                [ -f "$TMP_IMGS"/${2}_block.img ] && {
                    mv "$TMP_IMGS"/${2}_block.img "$TMP_IMGS"/${2}.img
                } || {
                    cat "$1" >"$TMP_IMGS"/${2}.img
                }
                return 22
            } || {
                abortF 72 9991
            }

        } || {
            MYSELECT "There are problems with mounting images $2, you can continue without checking the $2 images, in this case DFE will not be available if it vendor partition" \
                "Continue"
            echo "$2" >>$TMP_NEO/mount_problem.txt
            rm -rf "$TMP_IMGS"/${2}
            [ -f "$TMP_IMGS"/${2}_block.img ] && {
                mv "$TMP_IMGS"/${2}_block.img "$TMP_IMGS"/${2}.img
            } || {
                cat "$1" >"$TMP_IMGS"/${2}.img
            }
            return 22

        }

    } || {
        rm -f "$TMP_IMGS"/${2}_block.img &>>$LOG
        ui_print "\n\n"
        my_print "Failed to mount $2, try restarting the device and try again, this should help, otherwise save the log file and send it to one of the support branches"
        abortF 1 614
    }

}
mount2ext4() {

    mkdir -p "$TMP_IMGS"/${2}_block &>>$LOG
    $boot_on || { force_umount "$1" || abortF 22 1123; }
    tune2fs -l $1 &>>$LOG && tune2fs -c "20" $1 &>>$LOG
    try_mount -r -t $t_mount "$1" ""$TMP_IMGS"/${2}_block" || {
        my_print "Trying to copy a block of memory and mount a copy of the file. Waiting..."
        cat "$1" >"$TMP_IMGS"/${2}_block.img
        chcon u:object_r:media_rw_data_file:s0 "$TMP_IMGS"/${2}_block.img &>>$LOG
        tune2fs -l "$TMP_IMGS"/${2}_block.img &>>$LOG && tune2fs -c "20" "$TMP_IMGS"/${2}_block.img &>>$LOG
        try_mount -r -t $t_mount ""$TMP_IMGS"/${2}_block.img" ""$TMP_IMGS"/${2}_block" || {
            if_mount_problem_func "$1" "$2"
            return $?
        }
    }

    size_part_folser_du=$(du -bs ""$TMP_IMGS"/${2}_block" | awk '{print $1}')
    size_part_folser_wc=$(wc -c $1 | awk '{print $1}')
    (calc_int "$size_part_folser_du>$size_part_folser_wc") && size_part_folser=$size_part_folser_du || size_part_folser=$size_part_folser_wc
    echo $size_part_folser &>>$LOG
    # The stock package carried empty.img/emptyS.img. In recovery we create
    # a fresh EXT4 container when those templates are not present.
    if [ "$3" = "system" ]; then
        if [ -f "$TMP_NEO/emptyS.img" ]; then
            cp "$TMP_NEO/emptyS.img" "$TMP_IMGS/$2.img"
        else
            make_ext4fs -J -l "$(calc "$size_part_folser*2.5")" "$TMP_IMGS/$2.img" &>>$LOG || return 1
        fi
    else
        if [ -f "$TMP_NEO/empty.img" ]; then
            cp "$TMP_NEO/empty.img" "$TMP_IMGS/$2.img"
        else
            make_ext4fs -J -l "$(calc "$size_part_folser*2.5")" "$TMP_IMGS/$2.img" &>>$LOG || return 1
        fi
        tune2fs -c "20" -L "$3" "$TMP_IMGS/$2.img" &>>$LOG
    fi
    rw_expand "$TMP_IMGS"/$2.img "$(calc "$size_part_folser*2.5")"
    mkdir -p "$TMP_IMGS"/$2
    chcon u:object_r:media_rw_data_file:s0 "$TMP_IMGS"/$2.img

    try_mount -w -t ext4 ""$TMP_IMGS"/$2.img" ""$TMP_IMGS"/$2" || {
        if_mount_problem_func "$1" "$2"
        return $?
    }

    cp -rp "$TMP_IMGS"/${2}_block/* "$TMP_IMGS"/$2/ &>>$LOG

    force_umount ""$TMP_IMGS"/$2"
    force_umount ""$TMP_IMGS"/${2}_block"

    rm -f "$TMP_IMGS"/${2}_block.img &>>$LOG
    rm -rf "$TMP_IMGS"/${2}_block &>>$LOG

}

migrate_files() { # $1 path block , $2 part name lpdamp
    t_mount=auto
    part_name="$2"
    ext4_img=false
    [ -z $SLOT ] && {
        mount_part_name=$part_name
    } || {
        mount_part_name=${part_name:0:${#part_name}-2}
    }

    if [ $(getenforce) = "Enforcing" ]; then
        setenforce 0
        returnen=true
    else
        returnen=false
    fi

    erofs -i "$1" &>>$LOG && {
        t_mount=erofs
        f2fs_re=false
        my_print "Converting $2.erofs to new $2.ext4. Waiting..."
        erofs2ext4 "$1" "$2" "$mount_part_name" || {
            my_print "Oops, wrong extraction, dont worry, starting mount and migrating to new $2.ext4. Waiting..."
            mount2ext4 "$1" "$2" "$mount_part_name"
        }
    } || {
        tune2fs -l "$1" &>>$LOG && {
            f2fs_re=false
            my_print "Copy $2.ext4. Waiting..."
            cat "$1" >"$TMP_IMGS"/"$2".img
            tune2fs -c "20" "$TMP_IMGS"/$2.img &>>$LOG
            mkdir "$TMP_IMGS"/"$2" &>>$LOG
            chcon u:object_r:media_rw_data_file:s0 "$TMP_IMGS"/$2.img
            rw_minimize "$TMP_IMGS"/$2.img
            rw_expand "$TMP_IMGS"/$2.img $(calc "40*1024*1024")
            try_mount -w -t ext4 ""$TMP_IMGS"/$2.img" ""$TMP_IMGS"/$2" || {
                rm -f "$TMP_IMGS"/$2.img
                rm -rf "$TMP_IMGS"/"$2"
                my_print "Oops, something wrong with original $2.ext4, dont worry, starting mount $2 and migrating to new $2.ext4. Waiting..."
                t_mount=auto
                ext4_img=true
                mount2ext4 "$1" "$2" "$mount_part_name"
                case $? in
                22)
                    chcon u:object_r:media_rw_data_file:s0 "$TMP_IMGS"/$2.img
                    rw_minimize "$TMP_IMGS"/$2.img
                    ;;

                esac

            }

        } ||
            {
                my_print "Oops, wrong, this is not $2.ext4, maybe this F2FS or others file system, dont worry, starting mount and migrating to new $2.ext4. Waiting..."
                t_mount=f2fs
                mount2ext4 "$1" "$2" "$mount_part_name"
                f2fs_re2=true
                f2fs_re=flase
            }
    }
    mkdir "$TMP_IMGS"/"$2" &>>$LOG
    chcon u:object_r:media_rw_data_file:s0 "$TMP_IMGS"/$2.img
    rw_minimize "$TMP_IMGS"/$2.img
    rw_expand "$TMP_IMGS"/$2.img $(calc "40*1024*1024")
    try_mount -w -t ext4 ""$TMP_IMGS"/$2.img" ""$TMP_IMGS"/$2" || abortF 1 683
    for fstab in $(find "$TMP_IMGS"/$2/ -type f -name "*fstab*"); do
        if (grep -q -w "erofs" $fstab) || (grep -w "system" $fstab | grep -q "f2fs"); then
            my_print "Procedure for modifying $(basename $fstab) to accurately support EXT4"
            for extpart in $(check_partition_lpdump); do
                if [ -z $SLOT ]; then
                    fstab_name=$extpart
                else
                    fstab_name=${extpart:0:${#extpart}-2}
                fi
                original=$(grep -w "$fstab_name" $fstab | grep "/$fstab_name" | grep -w "erofs")
                if [ -z "$original" ]; then
                    edit=$(echo "$original" | sed 's|erofs|ext4|')
                    sed -i 's|'"$original"'|'"$edit"'|' $fstab
                fi
            done
        fi
        if $DFE_PATCH; then
            DFE "$fstab"
            echo '#'RO2RW $RSTATUS$VER included DFE'' >>$fstab
        fi
    done
    force_umount "$TMP_IMGS/$2"
    rw_minimize "$TMP_IMGS"/$2.img
    $returnen && setenforce 1
}

check_size() {

    if (calc_int "$(df $1 | wc -l)==2"); then
        df -h $1 | tail -n1 | awk '{print $4}'
    elif (calc_int "$(df $1 | wc -l)==3"); then
        df -h $1 | tail -n1 | awk '{print $3}'
    else
        my_print "Can't calculate free size data"
        abortF 82 458
    fi

}

mount_for_check() {
    mount -o rw,remount "$1" &>>$TMP_NEO/check.mnt.$2.txt
    grep -q "read-only" $TMP_NEO/check.mnt.$2.txt && {
        [ "$3" = "Check" ] &&
            my_print "$2 have RO  $(check_size $1) free size" ||
            my_print "$2 It was not possible to assign RW, you need to flash the full version of RO2RW"
    } || {
        my_print "$2 have RW and $(check_size $1) free size"
    }
    rm -f $TMP_NEO/check.mnt.$2.txt
}

read_main_dir() {

    full_path="$1"
    while true; do
        full_path="$(dirname "$full_path")"
        [ "$(dirname "$full_path")" = "." ] && break
        [ "$(dirname "$full_path")" = "/" ] && break
    done
    echo "$full_path"

}

set_config_for_expand() {
    . $TMP_NEO/config.sh
    MYSELECT "Choose the size to expand the partitions 'System=S' 'Product=P' 'System_ext=SE' 'Vendor=V' 'Other sections if any = OT'" \
        "Maximum expansion 1:select:Maximum 1:comment:S=50%, V=20%, P=10%, SE=10% OT=10%" \
        "Maximum expansion 2:select:Maximum 2:comment:S=30%, V=20%, P=20%, SE=20% OT=10%" \
        "Maximum expansion 3:select:Maximum 3:comment:S=30%, V=20%, P=10%, SE=10% OT=30%" \
        "Maximum expansion 4:select:Maximum 4:comment:S=30%, V=30%, P=20%, SE=20% OT=0%" \
        "enlarge each partition by 30Mb:select:+30Mb" \
        "enlarge each partition 50Mb:select:+50Mb" \
        "enlarge each partition 70Mb:select:+70Mb" \
        "enlarge each partition 100Mb:select:+100Mb" \
        "enlarge each partition 150Mb:select:+150Mb" \
        "enlarge each partition 200Mb:select:+200Mb" \
        "enlarge each partition 250Mb:select:+250Mb" \
        "Reading config.txt:select:CUSTOM:comment: Parameters $RW_SIZE_MOD $RW_SIZE" "$($terminal_on && echo "Set your own configuration now")"
    case $? in
    1)
        RW_SIZE_MOD="MAX"
        RW_SIZE="S=50% V=20% P=10% SE=10% OT=7%"
        ;;
    2)
        RW_SIZE_MOD="MAX"
        RW_SIZE="S=30% V=20% P=20% SE=20% OT=7%"
        ;;
    3)
        RW_SIZE_MOD="MAX"
        RW_SIZE="S=30% V=20% P=10% SE=10% OT=20%"
        ;;
    4)
        RW_SIZE_MOD="MAX"
        RW_SIZE="S=30% V=30% P=20% SE=20% OT=0%"
        ;;
    5)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="30"
        ;;
    6)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="50"
        ;;
    7)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="70"
        ;;
    8)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="100"
        ;;
    9)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="150"
        ;;
    10)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="200"
        ;;
    11)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="250"
        ;;
    13)
        MYSELECT "Distribute space by percentage, or a fixed size?" \
            "Percentage size" "Fixed size"
        case $? in
        1)
            my_print "Value hint: 'System=S' 'Product=P' 'System_ext=SE' 'Vendor=V' 'Other sections if any = OT'"
            free_procent=100
            RW_SIZE=""
            for part_short_name in S V P SE OT; do
                procent_size=101
                while true; do
                    ui_print " "
                    my_print "Available: ${free_procent}%"
                    my_print "Enter the percentage for the partition"
                    echo -n "- Enter % for ${part_short_name}="
                    read procent_size_read
                    procent_size=$procent_size_read
                    if $(calc_int "$procent_size<=$free_procent") && $(calc_int "$procent_size>=0"); then
                        free_procent=$(calc "$free_procent-$procent_size")
                        RW_SIZE="$RW_SIZE ${part_short_name}=${procent_size}%"
                        break
                    else
                        my_print "Enter a value from 0 to $free_procent"
                    fi
                done
            done
            RW_SIZE_MOD="MAX"
            ;;
        2)
            my_print "Enter the size of the increase in megabytes"
            echo -n "- Enter size MB:"
            read RW_SIZE
            RW_SIZE="$RW_SIZE"
            RW_SIZE_MOD="FIXED"
            ;;
        esac

        ;;
    esac
}
my_return() {
    return $1
}
check_rw_func() {
    for part in $(check_partition_lpdump); do

        i=$(find_block $part ${part:0:${#part}-2})

        case $part in
        *-cow*) echo "$part COW" &>>$LOG ;;
        *)
            $terminal_on && {
                mount_for_check "$i" "$part" "Check"
            } || {
                mount -r $i &>>$LOG && {
                    mount_for_check "$i" "$part" "Check"
                } || {
                    my_print "Can't mount $part. This partition is not listed in the fstab file, no mount point available"
                }
            }
            ;;
        esac

    done
}
f2fs_re2=false
chek_value() {
    case "$IF_EXT4_MOUNT_PROBLEM_CONTINUE" in
    true | false | 1 | 0)
        echo "IF_EXT4_MOUNT_PROBLEM_CONTINUE finde and have $IF_EXT4_MOUNT_PROBLEM_CONTINUE" &>>$LOG
        ;;
    *)
        my_print "IF_EXT4_MOUNT_PROBLEM_CONTINUE Has an incorrect value"
        return 1
        ;;
    esac
    case "$IF_NO_DATA_CONTINUE" in
    true | false | 1 | 0)
        echo "IF_NO_DATA_CONTINUE finde and have $IF_NO_DATA_CONTINUE" &>>$LOG
        ;;
    *)
        my_print "IF_NO_DATA_CONTINUE Has an incorrect value"
        return 1
        ;;
    esac
    case "$BACKUP_ORIGINAL_SUPER" in
    true:row | true:sparse | true:recovery | true:fastboot | false | 1)
        echo "BACKUP_ORIGINAL_SUPER finde and have $BACKUP_ORIGINAL_SUPER" &>>$LOG
        ;;
    *)
        my_print "BACKUP_ORIGINAL_SUPER Has an incorrect value"
        return 1
        ;;
    esac
    case "$DFE_PATCH" in
    true | false | 1 | 0)
        echo "DFE_PATCH finde and have $DFE_PATCH" &>>$LOG
        ;;
    *)
        my_print "DFE_PATCH Has an incorrect value"
        return 1
        ;;
    esac
    case "$WHAT_DO_SCRIPT" in
    fullrw | literw | checkrw)
        echo "WHAT_DO_SCRIPT finde and have $WHAT_DO_SCRIPT" &>>$LOG
        ;;
    *)
        my_print "WHAT_DO_SCRIPT Has an incorrect value"
        return 1
        ;;
    esac
    return 0
}
literw_func() {
    for part in $(check_partition_lpdump); do

        i=$(find_block $part ${part:0:${#part}-2})

        umount -f -l $i && umount -f -l $i && umount -f -l $i &&
            umount -f -l $i && umount -f -l $i && umount -f -l $i &&
            umount -f -l $i && umount -f -l $i && umount -f -l $i

        e2fsck -f $i
        blockdev --setrw $i
        e2fsck -E unshare_blocks -y -f $i
        resize2fs $i

        case $part in
        *-cow*) echo "$part COW" &>>$LOG ;;
        *)
            mount -r $i &>>$LOG && {
                mount_for_check "$i" "$part" "LiteRW"
            } || {
                my_print "Can't mount $part. This partition is not listed in the fstab file, no mount point available"
            }
            ;;
        esac

    done
}

# Keep the working tree on /data so large vendor/super images do not consume
# recovery tmpfs. The only user-supplied files needed are the script and config.
TMP_NEO=/data/local/tmp/RO2RW_RECOVERY
TMP_IMGS=$TMP_NEO/imgs
NEO_LOGS=/tmp/NEO.LOGS
check_size_main_path=/data
OUT_SUPER_DIR=/data/media/0/RO2RW_SUPER

mkdir -p "$TMP_NEO" "$TMP_IMGS" "$NEO_LOGS" || exit 75

# Recovery integrated configuration.
# config.txt is stored directly in /system/bin.
CONFIG_FILE="/system/bin/config.txt"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: $CONFIG_FILE not found" >> "$DEBUG"
    exit 75
fi

cp -f "$CONFIG_FILE" "$TMP_NEO/config.txt" || {
    echo "ERROR: cannot copy config.txt" >> "$DEBUG"
    exit 75
}

cp -f "$TMP_NEO/config.txt" "$TMP_NEO/config.sh" || {
    echo "ERROR: cannot create config.sh" >> "$DEBUG"
    exit 75
}

. "$TMP_NEO/config.sh" || {
    echo "ERROR: cannot source config.sh" >> "$DEBUG"
    exit 75
}

echo "CONFIG LOADED:" >> "$DEBUG"
echo "FORCE_START=$FORCE_START" >> "$DEBUG"
echo "IF_EXT4_MOUNT_PROBLEM_CONTINUE=$IF_EXT4_MOUNT_PROBLEM_CONTINUE" >> "$DEBUG"
echo "IF_NO_DATA_CONTINUE=$IF_NO_DATA_CONTINUE" >> "$DEBUG"
echo "BACKUP_ORIGINAL_SUPER=$BACKUP_ORIGINAL_SUPER" >> "$DEBUG"
echo "DFE_PATCH=$DFE_PATCH" >> "$DEBUG"
echo "WHAT_DO_SCRIPT=$WHAT_DO_SCRIPT" >> "$DEBUG"

LOG=$TMP_NEO/log.file.txt
echo "empty" > "$TMP_NEO/mount_problem.txt"
PATH=/system/bin:/system/xbin:/sbin:$PATH
export PATH
SLOT=$(bootctl get-suffix $(bootctl get-current-slot 2>/dev/null) 2>/dev/null)
[ -z "$SLOT" ] && SLOT=$(getprop ro.boot.slot_suffix)
LPDUMP="$TMP_NEO/LPDUMP.txt"

# Do not rename/delete the user's /tmp/config.txt. Work on a private copy.
cp -f "$TMP_NEO/config.txt" "$TMP_NEO/config.sh" || exit 75

REMOVE_TIMEOUT_KEY=false

. "$TMP_NEO/config.sh"

case "$FORCE_START" in
true | false | 1 | 0)
    echo "FORCE_START finde and have $FORCE_START" &>>$LOG
    ;;
*)
    my_print "FORCE_START Has an incorrect value"
    abortF 122 814
    ;;
esac

$terminal_on && {
    FORCE_START=false
}
ui_print " "
ui_print " "
ui_print " "
ui_print "*******************"
my_print "Welcome to Read Only to Read Write for android (RO2RW) | Converting SUPER \"system partitions\" to read/write mode"
ui_print "*******************"
my_print "Aka RO2RW/EROFS2RW/F2FS2RW"
ui_print "*******************"
my_print "$RSTATUS$VER" # prebuild for MFP NEO inbuild function with more functional"
ui_print "*******************"
my_print "By @LeeGarChat"
ui_print "*******************"
my_print "ARCH: $arch"
my_print "Active slot: $([ -z "$SLOT" ] && echo "A-only" || echo "$SLOT")"
my_print "Force start: $FORCE_START"
ui_print " "
my_print "Paths directories:"
my_print "TMP_NEO = $TMP_NEO"
my_print "TMP_IMGS = $TMP_IMGS"
my_print "NEO_OUT_LOGS = $NEO_LOGS"
my_print "Main_dir = $check_size_main_path"
my_print "OUT_SUPER_DIR = $OUT_SUPER_DIR"
ui_print " "
ui_print " "

$FORCE_START && {
    chek_value || {
        $IF_VALUE_WRONG && {
            MYSELECT "Which of the values was incorrect, do you want to continue in manual tuning mode?" \
                "Continue"
            FORCE_START=false
            REMOVE_TIMEOUT_KEY=false
        } || {
            abortF 200 11234
        }

    }
}

case $RW_SIZE_MOD in
MAX)
    sleep 0.1
    ;;
FIXED)
    sleep 0.1
    ;;
*)
    my_print "RW_SIZE_MOD Has an incorrect value"
    abortF 122 811
    ;;
esac

if (find_block super &>/dev/null); then
    my_print "Super found"
    SUPER_PATH=$(find_block super)
else
    my_print "Can't find super partitions. RO2RW only for devoces with super partitions"
    exit 124
fi

# fi

# Recovery: lpdump is supplied by /system/bin; do not require BusyBox,
# TMP_NEO/$arch/lpdump, or /bin/lpdump.
lpdump_bin=/system/bin/lpdump
if ! "$lpdump_bin" --slot="$SLOT" "$SUPER_PATH" >"$TMP_NEO/LPDUMP.txt" 2>>"$LOG"; then
    my_print "Can't read metadata super partition"
    abortF 55 759
fi

mkdir -p $TMP_IMGS &>>$LOG

Ss=$(for i in $($lpdump_bin --slot=$SLOT "$SUPER_PATH" | grep "Size:" | awk '{print $2}'); do $(calc_int "$i>20") && echo $i && break; done)
echo "Size max super:$Ss" &>>$LOG

if (check_free_data); then
    echo fine &>>$LOG
else
    my_print "Still need $(calc "($Ss/1024/1024/1024)+1") GB+ internal storage memory for contiue"
    abortF 55 772
fi
if (find_block "system" "system$SLOT" >>/dev/null); then
    my_print "Found system mapper block"
else
    my_print "Can't find mapper block"
    abortF 26 764
fi
ui_print " "
ui_print " "
td=$($lpdump_bin --slot=$SLOT "$SUPER_PATH")
td="${td#*Partition table:}"

$FORCE_START && {
    case $WHAT_DO_SCRIPT in
    literw | LITERW | LiteRW)
        echo "Starting LiteRW" &>>$LOG
        $terminal_on && {
            my_print "LiteRW is not available inside the running system"
            abortF 1 8123
        }
        literw_func
        abortS
        ;;
    FULLRW | FullRW | fullrw)
        echo "Starting FullRW" &>>$LOG
        ;;
    CHECKRW | CheckRW | checkrw)
        echo "Starting CheckRW" &>>$LOG
        literw_func
        abortS
        ;;
    *)
        my_print "Incorrect value FORCE_START"
        ;;

    esac

} || {
    MYSELECT "You want make/install new RW super or check RW and free size?" \
        "Make/Install" "Check free size" "Patch vendor_boot/boot for ext4 f2fs erofs support, and select RW or RO mount options by default" "$($terminal_on || echo "Run LiteRW for recovery only")"
    case $? in
    2)
        check_rw_func
        abortS
        ;;
    3)
        MYSELECT "Mount option default RO or RW" \
            "RW" "RO"
        case $? in
        1) patch_vendor_fstab "rw" ;;
        2) patch_vendor_fstab "ro" ;;
        esac
        abortS
        ;;
    4)
        literw_func
        abortS
        ;;
    esac

    set_config_for_expand
    while true; do
        MYSELECT "Confing for expand: $RW_SIZE_MOD $RW_SIZE" \
            "Continue" "Repartition"
        case $? in
        1)
            break
            ;;
        2)
            set_config_for_expand
            ;;
        esac
    done
}

case $RW_SIZE_MOD in
MAX)
    for i in $RW_SIZE; do
        i=${i%\%*}
        case "$i" in
        SE=*) RW_SIZE_SE=${i#*SE=} ;;
        S=*) RW_SIZE_S=${i#*S=} ;;
        P=*) RW_SIZE_P=${i#*P=} ;;
        V=*) RW_SIZE_V=${i#*V=} ;;
        OT=*) RW_SIZE_OT=${i#*OT=} ;;
        esac
    done
    (calc_int "$(calc "$RW_SIZE_SE+$RW_SIZE_S+$RW_SIZE_P+$RW_SIZE_V+$RW_SIZE_OT")>100") && abortF 22 866
    ;;
esac

rm -rf $OUT_SUPER_DIR

$FORCE_START && {

    case $DFE_PATCH in
    true | 0 | false | 1)
        echo "DFE PATCH $DFE_PATCH" &>>$LOG
        ;;
    *)
        my_print "Incorrect value DFE_PATCH"
        ;;
    esac
} || {
    MYSELECT "Do you also want to install the Disable Force Encryption (DFE) patch? WARNING: Only Use This if You Know What You're Doing. Else Press \"SKIP\"" \
        "SKIP" \
        "Yes:comment:If your data is encrypted you need to format data before running it into the system with new super" \
        "No:comment:If your data is not encrypted and you have used DFE before and the ROM is not patched with DFE (ROM is encrypted), you need to format data before running into the system with new super"
    case $? in
    2) DFE_PATCH=true ;;
    1 | 3) DFE_PATCH=false ;;
    esac
}
make_img
calc_super
make_super
patch_vendor_fstab ro

$terminal_on && {

    MYSELECT "You want to force disable verification and verity. or create vbmeta files for flashing?" \
        "Force disable" "Create vbmeta* imgs for flashing via recovery/fastboot"
    case $? in
    1)
        avbctl --force disable-verification &>>$LOG
        avbctl --force disable-verity &>>$LOG
        ;;
    2)
        mkdir $TMP_NEO/bak_vbmeta
        for file_vbmeta in /dev/block/by-name/*vbmeta*$SLOT; do
            cat "$file_vbmeta" >$TMP_NEO/bak_vbmeta/$(basename $file_vbmeta)
        done
        avbctl --force disable-verification &>>$LOG
        avbctl --force disable-verity &>>$LOG
        for file_vbmeta in /dev/block/by-name/*vbmeta*$SLOT; do
            cat "$file_vbmeta" >$OUT_SUPER_DIR/"$(basename "$file_vbmeta")".patched.img
            cat $TMP_NEO/bak_vbmeta/"$(basename $file_vbmeta)" >$file_vbmeta
        done
        ;;
    esac
} || {
    avbctl --force disable-verification &>>$LOG
    avbctl --force disable-verity &>>$LOG
}
$terminal_on || {
    my_print "If you see \"Failed to mount /part (Invalid-argument)\" then this is normal, you need to restart recovery so that the partitions are defined correctly"
}
abortS
exit 0
