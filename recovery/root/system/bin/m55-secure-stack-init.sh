#!/system/bin/sh
# Mount stock vendor after hwservicemanager has read the recovery VINTF manifest,
# then restore the vendor properties and start the Qualcomm secure stack in order.
LOG=/tmp/m55-secure-stack.log
log() { echo "[m55-secure-stack] $*" >> "$LOG"; }

mount_ro_if_needed() {
    target="$1"
    device="$2"
    if grep -q " $target " /proc/mounts; then
        log "$target already mounted"
        return 0
    fi
    for fs in erofs ext4 f2fs; do
        if mount -t "$fs" -o ro "$device" "$target" >> "$LOG" 2>&1; then
            log "mounted $device at $target as $fs (read-only)"
            return 0
        fi
    done
    log "WARNING: unable to mount $device at $target"
    return 1
}

wait_service() {
    name="$1"
    limit="$2"
    attempt=0
    while [ "$attempt" -lt "$limit" ]; do
        state="$(/system/bin/getprop "init.svc.$name")"
        if [ "$state" = "running" ]; then
            # Catch fast registerAsService() failures that immediately exit.
            sleep 1
            state="$(/system/bin/getprop "init.svc.$name")"
            [ "$state" = "running" ] && return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    log "ERROR: service $name did not stay running (state=$(/system/bin/getprop "init.svc.$name"))"
    return 1
}

# Recovery creates logical partition aliases after init has already started.
attempt=0
while [ "$attempt" -lt 25 ] && [ ! -b /dev/block/by-name/vendor ]; do
    sleep 1
    attempt=$((attempt + 1))
done
if [ ! -b /dev/block/by-name/vendor ]; then
    log "WARNING: /dev/block/by-name/vendor not available yet"
else
    mkdir -p /vendor
    mount_ro_if_needed /vendor /dev/block/by-name/vendor || true
fi

# The stock vendor build.prop carries QTI KeyMint properties that are not in
# the minimal recovery ramdisk. Keep Android 16 ro.build.* values untouched.
if [ -r /vendor/build.prop ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ""|#*) continue ;;
            *=*)
                key="${line%%=*}"
                value="${line#*=}"
                case "$key" in
                    ro.vendor.*|ro.hardware.*|ro.product.vendor.*|ro.arch)
                        /system/bin/resetprop "$key" "$value" >/dev/null 2>&1 || true
                        ;;
                esac
                ;;
        esac
    done < /vendor/build.prop
    log "loaded ro.vendor.*, ro.hardware.*, ro.product.vendor.* and ro.arch from vendor/build.prop"
else
    log "WARNING: /vendor/build.prop unavailable; continuing with recovery properties"
fi

# qseecomd needs the stock vendor libraries. The HAL service RCs are disabled
# and started explicitly below so they cannot race the vendor mount.
 /system/bin/setprop ctl.start qseecomd
wait_service qseecomd 10 || exit 1

/system/bin/setprop ctl.start qteeconnector-hal-1-0
wait_service qteeconnector-hal-1-0 10 || exit 1

/system/bin/setprop ctl.start qseecom-service
wait_service qseecom-service 10 || exit 1

/system/bin/setprop ctl.start vendor.keymint-default
wait_service vendor.keymint-default 10 || exit 1

log "QSEECom, QTEEConnector and KeyMint are running"
exit 0
