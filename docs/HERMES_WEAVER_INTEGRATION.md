# Galaxy M55 TWRP — Samsung Hermes / HIDL Weaver 1.0

## Confirmed on this device

- Stock Android 16 registers `android.hardware.weaver@1.0::IWeaver/default`.
- Its real executable is `/vendor/bin/hermesd /data/vendor/gatekeeper`,
  running as UID `system`.
- Stock init uses `socket hermes_secnvm stream 660 system system`,
  group `system 5678`, and `WAKE_ALARM`.
- In the existing TWRP build, the PIN prompt fails before credential validation:
  `Get_Weaver_Data` -> `Failed to get weaver service`.
- Working functionality to preserve: automatic ADSP battery initialization,
  Qualcomm DMA heap permissions, KeyMint version binding, metadata decrypt,
  /data F2FS mount, system-wide and per-boot DE keys.

## Experiment design

In the **isolated** `fix/twrp-weaver-hermes` branch:

1. `recovery/root/vendor/etc/vintf/manifest/iweaver_v1_manifest.xml`
   advertises the exact stock HIDL Weaver 1.0 endpoint.
2. `recovery/root/vendor/etc/init/hermesd.rc` declares the stock daemon
   (with `seclabel u:r:recovery:s0` for TWRP init) **disabled by default**.
   It starts on `crypto.ready=1` together with
   `hwservicemanager.ready=true`, after prepdecrypt mounted /data.
   This avoids stock `post-fs-data`, which is too early in TWRP.
3. `recovery/root/ueventd.qcom.rc` grants stock `system:system 0660`
   access to /dev/k250a and /dev/ssp.
4. The original Galaxy M55 `hermesd`, eight vendor libraries and **three
   exact SecNVM firmware images** need to be supplied by the device owner.
   They are intentionally not checked into the public tree by this analysis.
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

Do not build the experiment until the required payload is present.
This does not wipe, format, change the phone, reset Weaver slots or
read secrets.

## Validation (TWRP, after test build)

```bat
adb shell getprop init.svc.hermesd
adb shell ls -l /vendor/bin/hermesd /dev/k250a /dev/ssp
adb shell "lshal 2>/dev/null | grep -i weaver"
adb shell ls -ld /data /data/vendor/gatekeeper /data/media/0
adb pull /tmp/recovery.log twrp-hermes-recovery.log
adb logcat -b all -d > twrp-hermes-logcat.txt
```

Success criteria: `init.svc.hermesd=running`, HIDL
`IWeaver/default` registered, then a known correct PIN unlocks user 0
credential-encrypted (CE) keys. If these fail, inspect the logs *before*
considering further changes to key handling; no guarantee that merely
starting Hermes completes CE decrypt.

**Never** upload actual PINs, `/data/vendor/gatekeeper` contents,
hardware Weaver slots, locksettings database, encrypted key blobs or EFS.
