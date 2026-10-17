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


## 2026-10-17: metadata decryption now works, fscrypt per-boot key still fails

After rebuilding with explicit `exec u:r:recovery:s0 root root -- resetprop`
and Android 16 / 2025-12-01 SPL:

- The three early init resetprop invocations now exit status 0 *before*
  KeyMint service startup; KeyMint reports OS_VERSION 160000 and SPL 202512.
- Metadata encryption **works**: TWRP prints
  `Successfully decrypted metadata encrypted data partition`,
  `/dev/block/dm-6` mounts at `/data` (F2FS).
- File-based encryption remains **locked**: `fscrypt_initialize_systemwide_keys`
  installs the existing system DE key from `/data/unencrypted/key`
  (and writes its reference), then fails on the next, *per-boot*, wrapped
  key generation step. TWRP retries 3 times. **Do not infer that
  /data/media/0 or credential-encrypted (CE) files are unlocked merely
  because /data is mounted.**
- KeyMint `tz_generate_fbe_key` fails with `-49` on every generation
  attempt, exposed by keystore2 as `generateKey ... -49`. AOSP
  `ErrorCode.aidl` names `-49` **SECURE_HW_COMMUNICATION_FAILED**.
  Existing key conversion `convertStorageKeyToEphemeral` succeeds.
- `qseecomd` fails to register multiple trusted listeners (including
  RPMB/GPFS) with `No ion heap of name qcom,qseecom exists` and
  `DMA-Buf allocation failed ... errno = 13`. Separate Qualcomm
  `qseecom-service` and `qteeconnector` repeatedly exit. These are
  plausible causes of KeyMint hardware communication failure, but not
  yet proven.
- Samsung KeyMint logs missing `/mnt/vendor/efs/DAK/gakkeybox` and
  empty `prov_data/dev_root`; EFS is mounted **read-only**, preserve
  that and do not attempt to recreate provisioning keys or expose EFS
  files as diagnostics.
- The `/sys/class/power_supply` directory has **no entries** in
  recovery even though battery-related kernel modules load. The
  recovery Health HAL prints `No battery devices found`.
  `TW_USE_LEGACY_BATTERY_SERVICES` alone cannot fix it.

### Next non-destructive investigation

In **recovery**, examine *existence and names only* (do not dump key
material, encrypted blobs, EFS data or private user files):

```sh
adb shell 'ls -ld /dev/ion /dev/dma_heap /dev/dma_heap/* 2>&1'
adb shell 'ls -la /sys/class/power_supply /sys/class/remoteproc 2>&1'
adb shell 'ls -ld /data/media /data/media/0 /data/unencrypted 2>&1'
adb shell 'ls -ld /mnt/vendor/efs/DAK /mnt/vendor/efs/prov_data 2>&1'
```

After rebooting into the **working normal Android system**, capture the
equivalent `ls` output from `/dev/dma_heap`,
`/sys/class/power_supply` and, where root access allows, relevant
kernel lines for `pmic_glink`, `battery`, `qseecom`, `dma_heap`
and `remoteproc`. Compare device-node names and registered drivers
rather than editing/formatting partitions. If there is no trusted
non-destructive fix for the Qualcomm listener, leave wrapped FBE
unchanged; do not fake a per-boot key or remove `wrappedkey_v0`.

Reference: AOSP hardware-wrapped keys documentation,
`https://source.android.com/docs/security/features/encryption/hw-wrapped-keys`;
AOSP KeyMint ErrorCode.aidl. This is **diagnosis**, not a code fix
for CE/media or power_supply.


## 2026-10-17: ADSP boot is confirmed to restore battery in TWRP

On stock Android, remoteproc0 (ADSP), remoteproc1 (CDSP), remoteproc2
(MSS) and remoteproc3 (WPSS) are all `running`; recovery leaves all
four `offline`. Recovery's `/sys/class/power_supply` is empty.

**Validated manually on the actual M55:** in recovery, issuing

```sh
echo start > /sys/class/remoteproc/remoteproc0/state
```

temporarily interrupted ADB but then `remoteproc0/state` became
`running` and six supply entries appeared: `ac`, `battery`,
`otg`, `ucsi-source-psy-...`, `usb`, `wireless`. The kernel log
showed repeated `[GXY_PSY]gxy_bat_calc_time_to_full` with SOC ~74
in that session. This confirms the ADSP/PMIC GLINK dependency.

**Recovery-only patch:** `init.recovery.qcom.rc` has a single
`on boot` `wait .../remoteproc0/state 2` and `write .../state start`
*after* the original KeyMint startup command, and firmware partition is
already mounted in `on fs`. No other remoteproc is started. Existing
working metadata FBE and read-only EFS handling are unchanged.

**Still to validate in a fresh build:** that the init builtin write
succeeds, ADB reconnects, battery percentage appears in the TWRP UI,
and metadata FBE remains mountable. If TWRP UI reports no battery
despite sysfs registration, inspect legacy battery reader separately;
the post-ADSP dmesg still showed `healthd: battery none chg=`.
Do not restart all remoteprocs or alter wrapped-key flags.

Commands after boot:
```cmd
adb shell cat /sys/class/remoteproc/remoteproc0/state
adb shell ls -la /sys/class/power_supply
adb shell cat /sys/class/power_supply/battery/capacity
adb shell cat /sys/class/power_supply/battery/status
adb shell ls -l /dev/dma_heap/qcom,qseecom
adb shell ls -ld /data /data/media /data/media/0
adb pull /tmp/recovery.log twrp-recovery-adsp.log
adb shell dmesg > twrp-dmesg-adsp.txt
```
