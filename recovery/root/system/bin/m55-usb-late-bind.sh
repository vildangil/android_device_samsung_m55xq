#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Galaxy M55: the physical a600000.dwc3 UDC can appear several seconds
# after AERA init first tries to bind the recovery configfs gadget.
# Do not block init waiting for the controller. Re-apply the existing
# USB mode once, only if ADB is enabled and the gadget remains unbound.
# No /data, userdata, key or EFS access.
#
tag=m55-usb
controller="$(getprop ro.boot.usbcontroller)"
[ -n "$controller" ] || exit 0

udc="/sys/class/udc/$controller"
gadget="/config/usb_gadget/g1"

i=0
while [ "$i" -lt 40 ]; do
    if [ -e "$udc" ] && [ -e "$gadget/UDC" ] &&
       [ "$(getprop sys.usb.configfs)" = "1" ]; then

        # A service may already have bound successfully. Never disturb
        # a working gadget, or fastboot / MTP-only modes.
        bound="$(cat "$gadget/UDC" 2>/dev/null)"
        [ -z "$bound" ] || exit 0

        mode="$(getprop sys.usb.config)"
        case "$mode" in
            adb|mtp,adb)
                # Avoid toggling USB while FunctionFS endpoints are unready.
                if [ "$(getprop sys.usb.ffs.ready)" != "1" ]; then
                    sleep 1
                    i=$((i + 1))
                    continue
                fi
                # The stock recovery init actions will rebuild configfs
                # links and set UDC when sys.usb.config changes.
                setprop sys.usb.config none
                sleep 1
                setprop sys.usb.config "$mode"
                exit 0
                ;;
            fastboot|mtp|sideload|mass_storage*)
                exit 0
                ;;
        esac
    fi
    sleep 1
    i=$((i + 1))
done
exit 0
