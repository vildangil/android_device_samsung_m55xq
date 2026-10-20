#!/system/bin/sh
# Load only the M55 QCA6750 WLAN driver from vendor_dlkm without inflating
# recovery.img with a second 25 MiB copy of the proprietary module.
LOG=/tmp/aera-wlan-up.log
MODULE_NAME=qca_cld3_qca6750
log() { echo "[aera-wlan] $*" >> "$LOG"; }

mkdir -p /tmp/recovery /tmp/recovery/sockets /vendor_dlkm

mount_ro_if_needed() {
    target="$1"
    partition="$2"
    if grep -q " $target " /proc/mounts; then
        return 0
    fi
    device=""
    for candidate in "/dev/block/mapper/$partition" "/dev/block/by-name/$partition" "/dev/block/bootdevice/by-name/$partition"; do
        if [ -b "$candidate" ]; then
            device="$candidate"
            break
        fi
    done
    if [ -z "$device" ]; then
        log "no block device for $partition"
        return 1
    fi
    for fs in erofs ext4 f2fs; do
        if mount -t "$fs" -o ro "$device" "$target" >> "$LOG" 2>&1; then
            log "mounted $device at $target as $fs (read-only)"
            return 0
        fi
    done
    log "could not mount $device at $target read-only"
    return 1
}

find_driver() {
    for candidate in \
        "/vendor_dlkm/lib/modules/$MODULE_NAME.ko" \
        "/vendor/lib/modules/$MODULE_NAME.ko" \
        "/vendor_dlkm/$MODULE_NAME.ko"; do
        if [ -s "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# The WLAN firmware config is in the stock vendor partition. Make it available
# before the driver signals fs_ready and starts its firmware/QMI sequence.
if [ ! -r /vendor/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini ]; then
    mount_ro_if_needed /vendor vendor || true
fi

driver="$(find_driver 2>/dev/null || true)"
if [ -z "$driver" ]; then
    mount_ro_if_needed /vendor_dlkm vendor_dlkm || true
    driver="$(find_driver 2>/dev/null || true)"
fi
if [ -z "$driver" ]; then
    mount_ro_if_needed /vendor vendor || true
    driver="$(find_driver 2>/dev/null || true)"
fi
if [ -z "$driver" ]; then
    log "ERROR: $MODULE_NAME.ko not found in vendor_dlkm/vendor"
    exit 1
fi
log "using WLAN driver $driver"

# QCA6750 is built on icnss2, not the QCA6490/kiwi CNSS path.
# Try Android's dependency-aware modprobe first, falling back to insmod.
# Stock modules.dep will load icnss2 and its dependencies automatically.
if ! grep -q "^$MODULE_NAME " /proc/modules; then
    loaded=0
    if command -v modprobe >/dev/null 2>&1; then
        for module_dir in /vendor_dlkm/lib/modules /vendor/lib/modules; do
            [ -f "$module_dir/modules.dep" ] || continue
            if modprobe -d "$module_dir" "$MODULE_NAME" >> "$LOG" 2>&1; then
                loaded=1
                log "loaded $MODULE_NAME via modprobe ($module_dir)"
                break
            fi
        done
    fi
    if [ "$loaded" != 1 ]; then
        # On recovery ramdisks without modprobe or a usable modules.dep,
        # most icnss dependencies may already have been loaded by init.
        # Attempt the platform module first, then the device WLAN module.
        if ! grep -q '^icnss2 ' /proc/modules; then
            for path in /vendor_dlkm/lib/modules/icnss2.ko /vendor/lib/modules/icnss2.ko; do
                [ -s "$path" ] || continue
                /system/bin/insmod "$path" >> "$LOG" 2>&1 && break
            done
        fi
        if ! /system/bin/insmod "$driver" >> "$LOG" 2>&1; then
            log "ERROR: qca6750 insmod failed; check icnss2 and modules.dep"
            exit 1
        fi
        log "loaded $MODULE_NAME via insmod"
    fi
else
    log "$MODULE_NAME already loaded"
fi

# Qualcomm CNSS will not finish firmware bring-up until fs_ready is set.
# Search dynamically so the script works with the stock CNSS platform node.
ready=""
attempt=0
while [ "$attempt" -lt 20 ]; do
    for candidate in /sys/devices/platform/soc/*cnss*/fs_ready /sys/devices/platform/soc/*qcom,cnss*/fs_ready /sys/kernel/cnss/fs_ready; do
        [ -e "$candidate" ] || continue
        ready="$candidate"
        break
    done
    [ -n "$ready" ] && break
    sleep 1
    attempt=$((attempt + 1))
done
if [ -n "$ready" ]; then
    # QCA6750/icnss2 may expose no CNSS fs_ready node. It is optional here.
    if echo 1 > "$ready" 2>> "$LOG"; then
        log "set $ready to 1"
    else
        log "WARNING: could not write $ready; waiting for wlan0 anyway"
    fi
else
    log "no CNSS fs_ready node; normal for some QCA6750/icnss2 setups"
fi

# Wait for the firmware/QMI cold-start to publish wlan0 before starting
# supplicant. Keep the UI informed with a clear log if the device never appears.
attempt=0
while [ "$attempt" -lt 60 ]; do
    [ -d /sys/class/net/wlan0 ] && break
    sleep 1
    attempt=$((attempt + 1))
done
if [ ! -d /sys/class/net/wlan0 ]; then
    log "ERROR: wlan0 did not appear within 60 seconds"
    exit 1
fi

if [ ! -s /tmp/wpa_supplicant.conf ]; then
    if [ -r /vendor/etc/wifi/wpa_supplicant.conf ]; then
        cp /vendor/etc/wifi/wpa_supplicant.conf /tmp/wpa_supplicant.conf
    else
        cat > /tmp/wpa_supplicant.conf <<'EOF'
ctrl_interface=/tmp/recovery/sockets
update_config=1
ap_scan=1
fast_reauth=1
pmf=1
EOF
    fi
fi
chmod 0600 /tmp/wpa_supplicant.conf
chmod 0777 /tmp/recovery /tmp/recovery/sockets
/system/bin/setprop ctl.start wpa_supplicant
log "requested wpa_supplicant start"
exit 0
