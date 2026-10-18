# Experimental automatic Samsung KeyMint SPL — M55/F55

## Why this branch exists

The stock Samsung KeyMint TEE binds metadata-encryption keys to OS,
vendor and boot patch levels. In TWRP, compiled-in Android 12.1
properties used to initialize the Samsung KeyMint service before
`prepdecrypt` discovers the installed Android system and vendor patches.

A tester's Samsung Galaxy F55 (SM-E556B, bootloader E556BXXS4BYH2)
on 2026-10-18 showed metadata key patch levels:
- key OS patch: `202605`
- key vendor patch: `20260505`
- key boot patch: `20260501`

With KeyMint running under December 2025 recovery props, the TA
returned `km_check_key_os_version_patchlevels failed`, the /data
metadata unwrap failed and TWRP never displayed a PIN prompt.

Manually swapping BoardConfig SPL for each firmware revision does not
scale. This branch implements read-only **runtime stock patch detection**.

## Implementation

- Git branch: `test/twrp-auto-spl`, based on
  `fix/twrp-weaver-hermes`. The working TWRP and fixed-May test branch
  remain unchanged.
- `recovery/root/init.recovery.qcom.rc`: retains early Android 16
  release override, removes the December 2025 runtime patch override,
  starts `twrp-keymint-spl` in the boot stage INSTEAD OF starting
  `vendor.keymint-default` immediately.
- `recovery/root/system/bin/twrp-keymint-spl.sh`: after TWRP creates
  the logical /dev/block/bootdevice/by-name/{system,vendor} mappings,
  the init-managed oneshot worker mounts both partition block devices
  temporarily **read-only**, checks known system-as-root and vendor
  `build.prop` paths and parses:
  `ro.build.version.release` / `ro.build.version.security_patch`
  and `ro.vendor.build.security_patch`.
- It separately inspects the **stock /boot** Android boot image header
  (read-only, signature `ANDROID!`, version field at byte 40):
  packed `os_version` is at byte 44 for headers v0-v2 and byte 16
  for Android/GKI headers v3-v4. The patch month is formatted
  `YYYY-MM-01`. Only if this check passes does the script set
  `ro.bootimage.build.version.security_patch`.
- It validates the dates, updates the live props with resetprop
  **before** the KeyMint TEE service is started, then starts that
  service exactly once via `ctl.start`.
- On mount/parse errors or 40-second mapping timeout, it starts the
  baseline (December 2025) KeyMint service to avoid deadlocks and logs
  `recovery.keymint_spl.mode=fallback`. It never guesses the patch,
  accesses encrypted data or resets credentials.

## Why this is separate from the working build

**Untested on actual M55 and F55 hardware.** A race is possible:
the TWRP recovery binary creates dynamic mappings concurrently and
can attempt metadata decryption before the detector starts KeyMint.
If that happens, the helper may resolve the correct SPLs while the
initial automatic decrypt attempt has already failed. Examine the
TWRP and logcat timelines before attempting any change to FBE logic.
The boot key patch may still differ from all reported properties.
The Android boot-header parser now supports **v0-v4**.
If the header is unsupported, missing or inconsistent, the boot patch
is not guessed. Verify the KeyMint trace; do not infer that matching system
and vendor properties always fixes boot patch-level mismatches.

The detector does NOT alter the built-in BoardConfig December 2025
fallback SPL or patch release values. It only changes runtime props
based on verified installed partition data. The TWRP recovery image
is still built with TWRP 12.1 and carries the same vendor stock Hermes
libraries and decrypt logic from the working test branch.

## Running a hardware trial

In GitHub Actions on `android-12.1`, launch
`Build TWRP` with `tree_ref=test/twrp-auto-spl`. Keep your known-good
TWRP recovery image safe for quick restore.

After the first boot, do not manually change KeyMint props. Collect:

```bat
adb shell getprop recovery.keymint_spl.mode
adb shell getprop recovery.keymint_spl.system
adb shell getprop recovery.keymint_spl.vendor
adb shell getprop recovery.keymint_spl.boot
adb shell getprop ro.bootimage.build.version.security_patch
adb shell getprop ro.build.version.security_patch
adb shell getprop ro.vendor.build.security_patch
adb shell getprop init.svc.vendor.keymint-default
adb shell cat /tmp/twrp-keymint-spl.log
adb shell getprop init.svc.hermesd
adb shell "cat /proc/mounts | grep ' /data '"
adb logcat -b all -d > twrp-autospl-logcat.txt
adb shell cat /tmp/recovery.log > twrp-autospl-recovery.log
```

Expected: `mode=detected`, OS/vendor SPL dates match the running
installed Android, `init.svc.vendor.keymint-default=running`, metadata
unencrypted mapping succeeds, /data F2FS mounts, and (if the phone has
a user credential) the normal PIN/pattern prompt is displayed.
If it fails, report logs without any PIN, raw keyblob, gatekeeper
or EFS contents. `fallback` indicates stock build.prop could not be
read; it is not success for a May 2026 device.

**Never** format /data, wipe /metadata, reset Gatekeeper/Weaver slots or
modify EFS as part of this experiment.

## F55 October 18 test: root cause of missing prompt in auto-SPL v1

The tester's logcat showed the previous detection mode and OS/vendor
props already correct, but Samsung KeyMint still rejected the metadata
key because the **boot** patch remained on December 2025:

```text
swd_configure: os_patchlevel       : 202605
swd_configure: vendor_patchlevel   : 20260505
swd_configure: boot_patchlevel     : 20251201
km_check_key_os_version_patchlevels: key_boot_patchlevel(20260501)
                                      > vl->boot_patchlevel(20251201)
keystore2: Error::Km(ErrorCode(-33))
```

Kernel dmesg also recorded: `Stock boot image SPL unknown; leaving
bootimage property unchanged`.

**Fix:** the earlier parser always used the **old v0-v2 offset 44**.
Android 16/GKI v3-v4 images use **offset 16**. The updated
`read_boot_spl` inspects header version at offset 40 and selects the
appropriate offset before launching KeyMint. This is a distinct
code-level fix, not a per-firmware SPL hardcode. Actual boot header
version on this F55 has not yet been read from the physical partition;
the change is **not yet hardware-tested**.

Read-only on-device header inspection, if still needed:

```bat
adb shell "od -An -tu4 -j40 -N4 /dev/block/bootdevice/by-name/boot"
adb shell "od -An -tu4 -j16 -N4 /dev/block/bootdevice/by-name/boot"
adb shell "od -An -tu4 -j44 -N4 /dev/block/bootdevice/by-name/boot"
adb shell cat /tmp/twrp-keymint-spl.log
```

No format, metadata wipe or keyblob changes are required.
