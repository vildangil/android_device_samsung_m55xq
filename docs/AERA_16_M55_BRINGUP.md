# AERA Recovery 16.0 — Samsung Galaxy M55 5G (SM-M556B / m55xq)

## Status

**Initial device-tree port only. NOT built or boot-tested yet.**
The user's TWRP 12.1 branch `fix/twrp-weaver-hermes` is unchanged and
remains the reference for hardware testing. Do not replace a working
recovery before reviewing a successful AERA build and its contents.

- **AERA upstream:** https://github.com/AERA-Recovery/android_manifest
  (`aera-16.0`, Android 16).
- **AERA recovery engine:** https://github.com/AERA-Recovery/android_bootable_recovery
- **M55 AERA tree:** `port/aera-16.0-m55xq`.
- **Build workflow:** `android-12.1:.github/workflows/build-aera.yml`
  (independent of `build-twrp.yml`).
- **Build command:** `lunch twrp_m55xq-bp2a-eng && mka adbd recoveryimage`.

## Starting point carried over from working TWRP

- Prebuilt kernel, DTB/DTBO, recovery partition size (112070656 bytes).
- Display/touch/input settings, battery sysfs, ADSP remoteproc0 start.
- Qualcomm DMA heap, QSEECom permissions and KeyMint version/SPL fixes.
- Samsung EFS mounted **read-only** at /mnt/vendor/efs.
- FBE v2 / wrapped-key metadata encryption / Android 16-2025-12-01 SPL.
- Original vendor HIDL Weaver 1.0 `hermesd` and library/firmware payload.
- Hermes init service plus delayed autostart helper; TWRP tester confirmed
  that starting Hermes manually allows successful PIN decryption.
- `recovery.fstab` and additional `twrp.flags` physical/logical partitions.
- Cache filesystem signature is NOT confirmed; do not format it.

## AERA-specific edits on this branch

1. `BoardConfig.mk`: namespace moved to `AERA_*`, new AERA Android 16
   build allowances and FBE v2; no Android 12.1 SHRP/PBRP/OrangeFox overrides.
2. `twrp_m55xq.mk`: Android 16 `base.mk`, `core_64_bit_only.mk`, AERA
   vendor common; removed fabricated Android 12 build fingerprint.
3. `AndroidProducts.mk`: `twrp_m55xq-bp2a-eng` lunch choice.
4. `device.mk`: simplified recovery packages, preserved qcom FBE,
   health, ICU and VNDK32 dependencies.
5. Independent Android 16 manifest-based CI from official AERA sources,
   with hermes/FBE file preflight, image size check, Odin TAR and logs.
   **ccache disabled** for first clean build due the earlier TWRP runner
   cache failure; no swap (swap does not speed a healthy build).

## First build

1. In GitHub Actions on the repository default branch `android-12.1`,
   choose **Build AERA Recovery 16.0 (Galaxy M55)**.
2. Use `device_ref = port/aera-16.0-m55xq`.
3. If compilation fails, inspect the attached `aera-m55xq-failure-*`
   artifact; do not flash an unvalidated image.
4. If it succeeds, confirm the archive reports `m55xq`, matches
   SHA256SUMS, and that recovery.img is within 112070656 bytes.

## Hardware validation sequence after a successful compile

1. Confirm the Samsung recovery/Download Mode flashing path and preserve
   a known-good recovery image for restore (Samsung is not a device where
   one should assume `fastboot boot` is available).
2. Verify display/touch and USB ADB, battery/charger, and first-boot logs.
3. Validate /metadata decrypt, /data F2FS and DE keys, then HIDL Weaver
   registration and user CE decrypt using the device owner's PIN.
4. Verify mount/backup/restore behavior on disposable data only. Do
   **not** format/wipe /data, /metadata, /persist, EFS or real cache content.
5. Only then try fastbootd, MTP, sideload and advanced AERA features.
   Wi-Fi, GPU, OTA/update and AERA PC Connection need separate validation.

## Diagnostics

```bat
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.security_patch
adb shell getprop init.svc.hermesd
adb shell getprop init.svc.vendor.keymint-default
adb shell ls -ld /data /data/vendor/gatekeeper
adb shell "cat /proc/mounts | grep -E ' /data | /metadata | /cache '"
adb shell "ps -A | grep -E 'hermesd|keymint|gatekeeper|qseecom'"
adb shell "ls -l /sys/class/power_supply/battery/capacity"
adb logcat -b all -d > aera-m55-logcat.txt
adb shell dmesg > aera-m55-dmesg.txt
```

No credentials, EFS, Weaver slots, gatekeeper contents or key blobs
should be uploaded. Successful TWRP FBE is a reference, **not** proof
that AERA Android 16 has equivalent runtime FBE initialization.
