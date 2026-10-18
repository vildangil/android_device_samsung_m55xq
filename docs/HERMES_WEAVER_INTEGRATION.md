# Galaxy M55 TWRP — Samsung Hermes / HIDL Weaver 1.0

## Confirmed on this device

- Stock Android 16 registers `android.hardware.weaver@1.0::IWeaver/default`.
- Its real executable is `/vendor/bin/hermesd /data/vendor/gatekeeper`,
  running as UID `system`.
- Stock init uses `socket hermes_secnvm stream 660 system system`,
  group `system 5678`, and `WAKE_ALARM`.
- On 2026-10-18 the device owner confirmed that manually running
  `adb shell setprop ctl.start hermesd` results in `init.svc.hermesd=running`
  and that **TWRP then successfully decrypts user data with the correct PIN**.
  Before Hermes, the PIN prompt failed at `Get_Weaver_Data` ->
  `Failed to get weaver service`.
- Working functionality to preserve: automatic ADSP battery initialization,
  Qualcomm DMA heap permissions, KeyMint version binding, metadata decrypt,
  /data F2FS mount, system-wide and per-boot DE keys.

## Experiment design

In the **isolated** `fix/twrp-weaver-hermes` branch:

1. `recovery/root/vendor/etc/vintf/manifest/iweaver_v1_manifest.xml`
   advertises the exact stock HIDL Weaver 1.0 endpoint.
2. `recovery/root/vendor/etc/init/hermesd.rc` declares the stock daemon
   (with `seclabel u:r:recovery:s0` for TWRP init) **disabled by default**,
   and an init-managed, nonblocking `hermesd-autostart` helper service.
   Its trigger is `crypto.ready=1 && hwservicemanager.ready=true`, but
   **the trigger starts only the helper**, not the Hermes daemon itself.
   `recovery/root/system/bin/hermesd-autostart.sh` waits (up to 180 s)
   for a real F2FS `/data` mount and for the existing DE
   `/data/vendor/gatekeeper` directory to become accessible, then
   issues `setprop ctl.start hermesd`. It never creates files or writes
   credentials. This order matters: stock `post-fs-data` and early
   `crypto.ready=1` happen before the TWRP DE keys are fully installed.
   This automatic-start change **has not yet been validated on device**.
3. `recovery/root/ueventd.qcom.rc` grants stock `system:system 0660`
   access to /dev/k250a and /dev/ssp.
4. The original Galaxy M55 `hermesd`, eight vendor libraries and **three
   exact SecNVM firmware images** have been supplied by the device owner
   and deliberately pushed to the **public** experimental branch
   in commit `4dd7c991c7e2d9eb8584b9a06410918878d443be`.
   The 3 firmware files are referenced as literal paths by the stock
   `hermesd` binary:
   - `/vendor/etc/secnvm/k250a_47000301_0.img`
   - `/vendor/etc/secnvm/k250a_47000305_c.img`
   - `/vendor/etc/secnvm/k250a_47000306_1.img`
   Only obtain them read-only from the matching stock ROM, not from
   other devices and not from /data, EFS or Keystore.
5. GitHub Actions fails early if the selected experimental branch lacks
   the expected vendor payload, rather than producing a non-functional
   Weaver recovery.

## Bundle + deployment

The conversation artifact `m55xq-hermes-weaver-patch.zip` contains
the exact owner-provided 64-bit `hermesd` binary and eight matching
libraries, plus text configuration and `install-weaver.cmd`.

After booting **normal Android** with USB debugging and extracting the
archive, running `install-weaver.cmd` pulls only the three public vendor
firmware files from stock, makes a fresh checkout of this experimental
branch, overlays the blobs and asks explicitly before committing and pushing
vendor proprietary files to the user's GitHub repository.

The complete payload is present in the experiment branch.
The auto-start patch must be rebuilt to test it; do not wipe, format,
reset Weaver slots or read secrets.

## Validation (TWRP, after test build)

```bat
adb shell ls -ld /data/vendor/gatekeeper
adb shell getprop init.svc.hermesd-autostart
adb shell getprop init.svc.hermesd
adb shell ls -l /vendor/bin/hermesd /dev/k250a /dev/ssp
adb shell "lshal 2>/dev/null | grep -i weaver"
adb shell ls -ld /data /data/vendor/gatekeeper /data/media/0
adb pull /tmp/recovery.log twrp-hermes-recovery.log
adb logcat -b all -d > twrp-hermes-logcat.txt
```

Success criteria after automatic startup: `init.svc.hermesd=running`, HIDL
`IWeaver/default` registered, then a known correct PIN unlocks user 0
credential-encrypted (CE) keys. If these fail, inspect the logs *before*
considering further changes to key handling; no guarantee that merely
starting Hermes completes CE decrypt.

**Never** upload actual PINs, `/data/vendor/gatekeeper` contents,
hardware Weaver slots, locksettings database, encrypted key blobs or EFS.

## Fallback if automatic startup does not work

After TWRP fully boots, check:

```bat
adb shell getprop crypto.ready
adb shell getprop hwservicemanager.ready
adb shell getprop init.svc.hermesd-autostart
adb shell getprop init.svc.hermesd
adb shell "cat /proc/mounts | grep ' /data '"
adb shell ls -ld /data/vendor/gatekeeper
adb logcat -b all -d > twrp-hermes-autostart-logcat.txt
```

Manual fallback is still available:
`adb shell setprop ctl.start hermesd`.
If the daemon is already running, there is no need to restart it.
Do not diagnose a second PIN failure until it is confirmed that the
HIDL Weaver service is registered in recovery.

**No factory reset or user credential changes are required.**


## Recovery fstab additions (2026-10-18)

The device has **two** TWRP partition-definition inputs:
`recovery.fstab` (main fs_mgr file) and
`recovery/root/system/etc/twrp.flags` (additional UI partitions).
Previous TWRP logs show /cache was **already present in twrp.flags**
but mount failed on `/dev/block/sda31` with
`EXT4-fs: Can't find ext4 filesystem`. This cannot be solved merely by
adding or moving a fstab entry; do not format it without identifying
what the stock partition currently contains.

This experiment explicitly declares the stock-confirmed partitions in
`recovery.fstab`:
- `/cache` -> `/dev/block/bootdevice/by-name/cache` (ext4 expected;
  only a mount declaration, not a formatting operation).
- `/mnt/vendor/persist` ->
  `/dev/block/bootdevice/by-name/persist` (ext4, **read-only**,
  no format/wipe/flash flags, calibration-sensitive).

The duplicate /cache line was removed from `twrp.flags` to retain
one authoritative entry. All pre-existing data/metadata/KeyMint/Weaver/
battery settings remain unchanged. The ext4 layout is based on the
M55 device fstab in `SavedByLight-WIP/lineage_device_samsung_m55xq`
(`rootdir/etc/fstab.qcom`, `lineage-23.2`). Exact current stock
filesystem signatures still require device verification.

Read-only stock Android verification:

```bat
adb shell su -c "ls -l /dev/block/bootdevice/by-name/cache /dev/block/bootdevice/by-name/persist"
adb shell su -c "blkid /dev/block/bootdevice/by-name/cache /dev/block/bootdevice/by-name/persist"
adb shell su -c "cat /proc/mounts | grep -E ' /cache | /mnt/vendor/persist '"
```

Never format or wipe `/persist`, EFS, metadata or unknown cache contents.
