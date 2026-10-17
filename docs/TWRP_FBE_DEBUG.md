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


## 2026-10-17: Multi-Android compatibility and battery findings

### Log evidence (TWRP 3.7.1_12-VildanG-5c3d206a)

- The phone is Qualcomm **m55xq / taro**. Recovery `/sys/class/power_supply`
  has **zero entries**. `pmic_glink.ko`, `gxy_glink_main.ko`,
  `qti_battery_charger_main.ko` load, but no power_supply device registers.
  `TW_USE_LEGACY_BATTERY_SERVICES := true` was already enabled: it cannot
  display real capacity without a working kernel sysfs provider. Do not fake
  the battery level or change the TWRP sysfs path while the class is empty.
- EFS is mounted read-only at `/mnt/vendor/efs`; `/metadata` mounts ext4.
  `/data` remains unmounted with wrapped-key FBE.
- During KeyMint startup: `os_version=120000`,
  `os_patchlevel=209912`, `key_os_version(160000) > vl->os_version(120000)`.
  Kernel log shows the three old `exec -- /system/bin/resetprop` commands
  failed due to absent SELinux domain transition. A newer device-tree commit
  switches to `exec u:r:recovery:s0 root root -- ...` and stock SPL,
  **but this recovery image does not contain those new changes**.
- `prepdecrypt` already detects the *installed* Android 16 and 2025-12-01 SPL
  from the real `/system` and `/vendor` partitions, and updates live props;
  however it runs **after** the first FBE attempt and after KeyMint startup.

### Safe future strategy for Android 15 + 16

Android's KeyMint keys are version-bound. Do not hardcode Android 16 when
booted on an Android 15 ROM, do not use an artificial 2099 patch level,
and never downgrade/upgrade protected key blobs merely to test recovery.

The multi-version implementation should reuse the QCOM TWRP common
`prepdecrypt` behavior: obtain exact OS release + system/vendor SPL from the
**installed ROM's** build properties, validate each field, then configure
KeyMint **before** its first use and only then attempt metadata decryption.
Check init trigger ordering, especially this tree's unconditional
`on boot: start vendor.keymint-default`. Do not move that service or change
recovery startup until testing confirms that early partition mapping and
property setup can complete; changing the order blindly can regress FBE
or boot. On missing/invalid ROM properties, fail closed with useful logs;
never silently fall back to 16/2099. Existing encrypted Android 16 keys
cannot be assumed to work after a downgrade to Android 15, even if recovery
supports both installed ROM versions.

References: AOSP 'Metadata encryption', AOSP 'Version binding', TeamWin
'android_device_qcom_twrp-common' README. This section is diagnostic only:
**no runtime multi-version change has been made**.
