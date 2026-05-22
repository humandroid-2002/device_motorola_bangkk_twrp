#!/system/bin/sh

i=0
timeout=6
elapsed=0

echo "Starting mount_vendor.sh...." | tee /dev/kmsg > /dev/null

while true; do

    keycheck

    if [ $? -eq 42 ]; then
        i=$((i + 1))
        echo "Volume up detected, $i" | tee /dev/kmsg > /dev/null
    fi

    # Double volume up trigger
    if [ "$i" -ge 2 ]; then
        echo "mount_vendor triggered by keycheck..." | tee /dev/kmsg > /dev/null
        break
    fi

    # Timeout fallback
    elapsed=$((elapsed + 1))

    if [ "$elapsed" -ge "$timeout" ]; then
        echo "mount_vendor triggered by timeout..." | tee /dev/kmsg > /dev/null
        break
    fi

    sleep 1
done

twrp mount /vendor
