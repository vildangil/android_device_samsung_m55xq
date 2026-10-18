# TWRP FBE May 2026 trial — Samsung F55 (SM-E556B)

**Experimental branch**: `test/twrp-f55-may2026-spl` (based on the
known-good `fix/twrp-weaver-hermes` branch). Do not apply this patch to
other firmware without validating its real keyblob security patch levels.

## Confirmed from one tester's Oct 18 2026 logs

- Recovery bootloader `ro.boot.bootloader=E556BXXS4BYH2` and
  `ro.boot.em.model=SM-E556B`: tester has the Galaxy F55 rather than
  the M55 retail model in the recovery default build props.
- Samsung KeyMint initially runs with OS patch `202512`, vendor and
  boot patch `20251201`.
- The metadata encryption key in `/metadata/vold/metadata_encryption/key`
  is bound to OS patch `202605`, vendor `20260505`, boot `20260501`.
- It fails with `km_check_key_os_version_patchlevels failed` and
  `Error::Km(ErrorCode(-33))`; TWRP reports `Unable to decrypt metadata
  encryption`, cannot probe raw F2FS /data, and does not show an initial
  PIN prompt.
- `prepdecrypt` changes ro.build / ro.vendor security patches to
  `2026-05-05` **after** the KeyMint service has initialized and the
  initial metadata decryption failed. That is too late to repair the
  KeyMint configuration for the current service instance.
- The subsequent manual decrypt attempt falls back to legacy FDE, with
  `cryptfs_check_passwd not valid for file encryption` and SIGABRT;
  do not interpret this as a PIN failure or try formatting data.

## Change in this isolated branch

- `BoardConfig.mk`: `PLATFORM_SECURITY_PATCH := 2026-05-05`,
  `VENDOR_SECURITY_PATCH := 2026-05-05`.
- `init.recovery.qcom.rc`: set Android 16 + May 05 2026
  `ro.build.version.security_patch` and
  `ro.vendor.build.security_patch` **synchronously in `on init`**
  before `vendor.keymint-default` starts in `on boot`.
- Everything else inherited unchanged, including Hermes and its
  existing manual fallback command, battery startup, metadata fstab,
  encrypted data settings and stock vendor binaries.

## Expected verification after flashing the test recovery

1. Observe automatic metadata key retrieval without KeyMint -33.
2. Confirm that `/data` opens as F2FS via dm-default-key mapping.
3. Confirm that the normal TWRP PIN/pattern prompt appears, if the
   installed Android has a user credential; for no lock credential there
   might be no PIN prompt.
4. Verify HIDL Weaver is running before entering the PIN; if the
   existing Hermes autostart fails, run
   `adb shell setprop ctl.start hermesd` only **after** /data mounts.
5. After PIN, confirm CE decrypt works without key resets or format.

Read-only commands:

```bat
adb shell getprop ro.boot.em.model
adb shell getprop ro.boot.bootloader
adb shell getprop ro.build.version.security_patch
adb shell getprop ro.vendor.build.security_patch
adb shell getprop init.svc.vendor.keymint-default
adb shell getprop init.svc.hermesd
adb shell "cat /proc/mounts | grep ' /data '"
adb shell "ls -ld /data/vendor/gatekeeper"
adb logcat -b all -d > f55-twrp-may2026-logcat.txt
adb shell cat /tmp/recovery.log > f55-twrp-may2026-recovery.log
```

**Do not** format /data, wipe /metadata, delete keyblob, reset Weaver
slots, erase EFS, downgrade the firmware or send actual PINs/keys.
Back up a known-good recovery image before flashing. If other testers
have older (e.g. December 2025) firmware, continue using the original
`fix/twrp-weaver-hermes` branch instead.

Future task: support different SPLs dynamically by loading the real
installed system/vendor/boot SPL before KeyMint initialization, then
make TWRP reattempt metadata decryption as appropriate. This isolated
hardcode is a diagnostic test, **not** a universal replacement.
