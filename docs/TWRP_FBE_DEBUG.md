# TWRP FBE decryption: non-destructive diagnostics (Galaxy M55 / m55xq)

This tree contains an initial, **untested** FBE preflight fix. It does **not** prove
that Samsung/Qualcomm hardware-wrapped key decryption works in TWRP.

## Before testing

- Verify the device is **m55xq** (Galaxy M55 SM-M556B) and retain a copy of a known-good recovery image.
- Do not format or wipe `/data` or `/metadata`; doing so would destroy access to existing encrypted data.
- Do not disable encryption, flash a DFE package, or replace `wrappedkey_v0` flags as a decryption workaround.
- Boot the newly built TWRP and capture the following over ADB **before rebooting**.

## Windows CMD / PowerShell

```cmd
adb devices
adb pull /tmp/recovery.log
adb shell getprop ro.crypto.state
adb shell getprop ro.crypto.type
adb shell getprop ro.boot.dynamic_partitions
adb shell getprop ro.product.first_api_level
adb shell getprop ro.build.version.sdk
adb shell getprop init.svc.vendor.keymint-default
adb shell getprop init.svc.qseecomd
adb shell getprop init.svc.qseecom-service
adb shell getprop init.svc.gatekeeper-1-0
adb shell ls -l /dev/block/bootdevice/by-name/userdata
adb shell ls -l /dev/block/bootdevice/by-name/metadata
adb shell cat /proc/mounts
adb logcat -b all -d > twrp-crypto-logcat.txt
```

These checks do not try to mount, format, or decrypt the userdata partition.

When sharing logs, redact device serials, account identifiers, tokens, personal
file names and other private details. Never share the screen unlock PIN/password.

## Next step

If `/metadata` doesn't mount, troubleshoot fstab/kernel/filesystem first.
If it mounts but `/data` is still inaccessible, investigate the dm-default-key
setup and Samsung KeyMint/Gatekeeper services, including whether the prebuilts
can load all their library dependencies. Compare the stock ROM's effective fstab
and encryption properties before changing any encryption flag.
