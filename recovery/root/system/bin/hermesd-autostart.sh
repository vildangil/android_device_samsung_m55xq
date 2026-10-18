#!/system/bin/sh
# Galaxy M55 TWRP: start Samsung Hermes once /data is actually usable.
# Run as an init-managed oneshot service so waiting never blocks init.
# crypto.ready=1 signals TEE setup, NOT completion of FBE DE key install.
# Do not create/replace gatekeeper files and never alter Weaver slots.

attempt=0
while [ "$attempt" -lt 180 ]; do
    data_mounted=0
    while read -r source target fstype options rest; do
        if [ "$target" = /data ] && [ "$fstype" = f2fs ]; then
            data_mounted=1
            break
        fi
    done < /proc/mounts

    # The existing stock directory becomes addressable only after the
    # Android FBE DE keys have been installed for /data.
    if [ "$data_mounted" -eq 1 ] && [ -d /data/vendor/gatekeeper ]; then
        /system/bin/setprop ctl.start hermesd
        exit $?
    fi

    attempt=$((attempt + 1))
    /system/bin/sleep 1
done

# /data might be corrupt or unavailable. Do not create any fallback keys.
exit 1
