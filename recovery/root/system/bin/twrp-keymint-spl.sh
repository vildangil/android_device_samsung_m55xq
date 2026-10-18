#!/system/bin/sh
# Experimental dynamic Samsung KeyMint SPL setup for Galaxy M55/F55.
# TWRP creates logical system/vendor block nodes after init starts recovery.
# Wait for those nodes, read the REAL Android build.props read-only, update
# KeyMint-facing properties, then (and only then) start KeyMint.
# Do not read/write any /data, /metadata, EFS or Weaver state.

LOG=/tmp/twrp-keymint-spl.log
SYS=/mnt/twrp_stock_system_spl
VEN=/mnt/twrp_stock_vendor_spl
SYSD=/dev/block/bootdevice/by-name/system
VEND=/dev/block/bootdevice/by-name/vendor
BOOT=/dev/block/bootdevice/by-name/boot
RESETPROP=/system/bin/resetprop
SETPROP=/system/bin/setprop
KEYMINT=vendor.keymint-default

say() {
    printf '%s\n' "$*" >> "$LOG"
    printf 'TWRP_SPL: %s\n' "$*" > /dev/kmsg 2>/dev/null || true
}

read_prop() {
    k="$1"; shift
    for p in "$@"; do
        [ -r "$p" ] || continue
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                "$k="*)
                    value="${line#*=}"
                    value="${value%%#*}"
                    value="$(printf '%s' "$value" | /system/bin/tr -d '\r\t ')"
                    [ -n "$value" ] || continue
                    printf '%s\n' "$value"
                    return 0
                    ;;
            esac
        done < "$p"
    done
    return 1
}

read_boot_spl() {
    # Android boot image header v0/v1/v2 has a packed os_version at offset
    # 44. This field records the signed boot image patch YEAR+MONTH.
    # Never inspect metadata key blobs or EFS to determine an SPL.
    [ -b "$BOOT" ] || return 1
    [ "$(/system/bin/dd if="$BOOT" bs=8 count=1 2>/dev/null)" = "ANDROID!" ] || return 1
    raw=$(/system/bin/od -An -tu4 -j44 -N4 "$BOOT" 2>/dev/null) || return 1
    set -- $raw
    word="${1:-}"
    case "$word" in
        ''|*[!0-9]*) return 1;;
    esac
    year=$((2000 + ((word >> 4) & 127)))
    month=$((word & 15))
    if [ "$year" -ge 2020 ] && [ "$year" -le 2099 ] &&
       [ "$month" -ge 1 ] && [ "$month" -le 12 ]; then
        printf '%04d-%02d-01\n' "$year" "$month"
        return 0
    fi
    return 1
}

valid_spl() {
    case "$1" in
        20[2-9][0-9]-0[1-9]-0[1-9]|20[2-9][0-9]-0[1-9]-[12][0-9]|20[2-9][0-9]-0[1-9]-3[01]|20[2-9][0-9]-1[012]-0[1-9]|20[2-9][0-9]-1[012]-[12][0-9]|20[2-9][0-9]-1[012]-3[01]) return 0;;
    esac
    return 1
}

mount_stock_ro() {
    dev="$1"; dir="$2"
    mkdir -p "$dir" || return 1
    /system/bin/mount -t erofs -o ro,nosuid,nodev "$dev" "$dir" >/dev/null 2>&1 && return 0
    /system/bin/mount -t ext4 -o ro,noload,nosuid,nodev "$dev" "$dir" >/dev/null 2>&1 && return 0
    /system/bin/mount -t f2fs -o ro,nosuid,nodev "$dev" "$dir" >/dev/null 2>&1 && return 0
    return 1
}

finish() {
    # Only read-only temporary mounts were used.
    /system/bin/umount "$SYS" >/dev/null 2>&1 || true
    /system/bin/umount "$VEN" >/dev/null 2>&1 || true
    say "Starting $KEYMINT; SPL mode: $1"
    "$SETPROP" recovery.keymint_spl.mode "$1"
    "$SETPROP" ctl.start "$KEYMINT"
}

: > "$LOG"
say "Waiting for TWRP-created logical system and vendor devices"
i=0
# TWRP creates these mappings immediately after it starts, while the
# KeyMint TEE itself needs almost one second to initialize on this SoC.
# Poll frequently to give KeyMint time before TWRP's first metadata unwrap.
while [ "$i" -lt 200 ]; do
    if [ -b "$SYSD" ] && [ -b "$VEND" ]; then
        break
    fi
    i=$((i + 1))
    /system/bin/sleep 0.2
done
if [ ! -b "$SYSD" ] || [ ! -b "$VEND" ]; then
    say "Could not find both system/vendor logical block devices (40 s timeout)"
    finish fallback
    exit 1
fi

if ! mount_stock_ro "$SYSD" "$SYS"; then
    say "Could not read-only mount installed system ($SYSD)"
    finish fallback
    exit 1
fi
if ! mount_stock_ro "$VEND" "$VEN"; then
    say "Could not read-only mount installed vendor ($VEND)"
    finish fallback
    exit 1
fi

# system-as-root layouts may have system/build.prop rather than build.prop.
sys_props="$SYS/system/build.prop $SYS/build.prop $SYS/system/etc/prop.default"
vendor_props="$VEN/build.prop $VEN/etc/build.prop"

os_spl=$(read_prop ro.build.version.security_patch $sys_props)
if ! valid_spl "$os_spl"; then
    os_spl=$(read_prop ro.system.build.version.security_patch $sys_props)
fi
ven_spl=$(read_prop ro.vendor.build.security_patch $vendor_props)
if ! valid_spl "$ven_spl"; then
    ven_spl=$(read_prop ro.build.version.security_patch $vendor_props)
fi
os_release=$(read_prop ro.build.version.release $sys_props)
if [ -z "$os_release" ]; then
    os_release=$(read_prop ro.system.build.version.release $sys_props)
fi
case "$os_release" in
    12|12.1|13|14|15|16) ;;
    *) say "Unsupported or missing system Android release [$os_release]";
       finish fallback; exit 1;;
esac

if ! valid_spl "$os_spl" || ! valid_spl "$ven_spl"; then
    say "Missing/invalid stock SPL: system=[$os_spl], vendor=[$ven_spl]"
    finish fallback
    exit 1
fi

boot_spl=$(read_boot_spl)
if valid_spl "$boot_spl"; then
    say "Installed boot image SPL $boot_spl (Android boot header)"
else
    say "Stock boot image SPL unknown; leaving bootimage property unchanged"
fi

say "Installed Android $os_release, system SPL $os_spl, vendor SPL $ven_spl"
# KeyMint is still stopped. Do NOT set these after its TEE init!
if ! "$RESETPROP" ro.build.version.release "$os_release" ||
   ! "$RESETPROP" ro.build.version.security_patch "$os_spl" ||
   ! "$RESETPROP" ro.vendor.build.security_patch "$ven_spl"; then
    say "resetprop failed; launch baseline KeyMint for diagnostics"
    finish fallback
    exit 1
fi
if valid_spl "$boot_spl"; then
    # Only a verified stock Android boot header may set the boot patch.
    "$RESETPROP" ro.bootimage.build.version.security_patch "$boot_spl" || \
        say "Could not update optional bootimage SPL property"
    "$SETPROP" recovery.keymint_spl.boot "$boot_spl"
fi
"$SETPROP" recovery.keymint_spl.system "$os_spl"
"$SETPROP" recovery.keymint_spl.vendor "$ven_spl"
finish detected
exit 0
