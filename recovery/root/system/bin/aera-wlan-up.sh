#!/system/bin/sh
# Load the stock M55 QCA6490 WLAN driver from vendor_dlkm without inflating
# recovery.img with a second 25 MiB copy of the proprietary module.
LOG=/tmp/aera-wlan-up.log
MODULE_NAME=qca_cld3_qca6490
log() { echo "[aera-wlan] $*" >> "$LOG"; }

mkdir -p /tmp/recovery /tmp/recovery/sockets /vendor_dlkm

mount_ro_if_needed() {
    target="$1"
    device="$2"
    if grep -q " $target " /proc/mounts; then
        return 0
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

driver="$(find_driver 2>/dev/null || true)"
if [ -z "$driver" ]; then
    mount_ro_if_needed /vendor_dlkm /dev/block/by-name/vendor_dlkm || true
    driver="$(find_driver 2>/dev/null || true)"
fi
if [ -z "$driver" ]; then
    mount_ro_if_needed /vendor /dev/block/by-name/vendor || true
    driver="$(find_driver 2>/dev/null || true)"
fi
if [ -z "$driver" ]; then
    log "ERROR: $MODULE_NAME.ko not found in vendor_dlkm/vendor"
    exit 1
fi
log "using WLAN driver $driver"

if ! grep -q "^$MODULE_NAME " /proc/modules; then
    if ! /system/bin/insmod "$driver" >> "$LOG" 2>&1; then
        log "ERROR: insmod failed for $driver"
        exit 1
    fi
    log "loaded $MODULE_NAME"
else
    log "$MODULE_NAME already loaded"
fi

# Qualcomm CNSS will not finish firmware bring-up until fs_ready is set.
# Search dynamically so the script works with the stock CNSS platform node.
ready=""
attempt=0
while [ "$attempt" -lt 20 ]; do
    for candidate in /sys/devices/platform/soc/*cnss*/fs_ready; do
        [ -e "$candidate" ] || continue
        ready="$candidate"
        break
    done
    [ -n "$ready" ] && break
    sleep 1
    attempt=$((attempt + 1))
done
if [ -z "$ready" ]; then
    log "ERROR: no CNSS fs_ready node appeared after driver load"
    exit 1
fi
chmod 222 "$ready" >> "$LOG" 2>&1 || true
if ! echo 1 > "$ready" 2>> "$LOG"; then
    log "ERROR: failed to set $ready"
    exit 1
fi
log "set $ready to 1"

# Wait for the firmware/QMI cold-start to publish wlan0 before starting
# supplicant. Keep the UI informed with a clear log if the device never appears.
attempt=0
while [ "$attempt" -lt 20 ]; do
    [ -d /sys/class/net/wlan0 ] && break
    sleep 1
    attempt=$((attempt + 1))
done
if [ ! -d /sys/class/net/wlan0 ]; then
    log "ERROR: wlan0 did not appear within 20 seconds"
    exit 1
fi

if [ ! -r /vendor/etc/wifi/wpa_supplicant.conf ]; then
    mount_ro_if_needed /vendor /dev/block/by-name/vendor || true
fi
if [ ! -r /vendor/etc/wifi/wpa_supplicant.conf ]; then
    log "ERROR: /vendor/etc/wifi/wpa_supplicant.conf is missing"
    exit 1
fi

chmod 0777 /tmp/recovery /tmp/recovery/sockets
/system/bin/setprop ctl.start wpa_supplicant
log "requested wpa_supplicant start"
exit 0
