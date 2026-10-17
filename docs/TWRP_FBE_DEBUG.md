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


## Galaxy M55 Android 16 KeyMint preflight (2026-10-17)

Build #4 booted successfully, but its ramdisk had `ro.build.version.release=12`
(and `ro.build.version.security_patch=2099-12-31`) while the installed
Android metadata key came from Android 16. Logcat reported
`key_os_version(160000) > vl->os_version(120000)` and `upgradeKey: ret -38`.
The prepdecrypt script changed the live value to 16 only **after** the first
metadata decryption attempt failed. Samsung KeyMint also tried to access
`/mnt/vendor/efs/DAK` before the EFS partition had been mounted there.

**Patch on this branch:** `init.recovery.qcom.rc` uses the existing
`/system/bin/resetprop` executable during init to set the Android version 16
and the stock system/vendor security patch of 2025-12-01, prior to the KeyMint
service startup. The same rc file mounts Samsung EFS at `/mnt/vendor/efs`
in read-only mode during `on fs` so KeyMint can read keys/provisioning.
No partition formatting, key deletion, or chmod on GAK keys is performed.

**Test after a NEW build:** Boot recovery and, before rebooting, run:

```bat
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.security_patch
adb shell getprop ro.vendor.build.security_patch
adb shell cat /proc/mounts
adb shell ls -ld /mnt/vendor/efs /mnt/vendor/efs/DAK
adb pull /tmp/recovery.log twrp-recovery-new.log
adb logcat -b all -d > twrp-logcat-new.txt
adb shell dmesg > twrp-dmesg-new.txt
```

Expected: Android release `16` and SPL `2025-12-01` visible immediately.
Confirm `/mnt/vendor/efs` is mounted before KeyMint initialization.
Actual `/data` mount and CE user data access must be verified separately.
The logs also contain Samsung KeyMint fuse warnings and Qualcomm QSEECom
listener failures; they may require additional work even after OS version
is corrected. Do not format `/data` or `/metadata` to debug FBE.
Do not share the contents of EFS or `/metadata/vold` (cryptographic secrets).
