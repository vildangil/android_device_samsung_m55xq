# Build TWRP for Galaxy M55 on GitHub Actions

Workflow: [Build TWRP (Galaxy M55)](../.github/workflows/build-twrp.yml)

## Run

1. Open **Actions** in this repository and select **Build TWRP (Galaxy M55)**.
2. Click **Run workflow**. Keep the workflow ref at `android-12.1` (the branch containing the workflow).
3. Choose the device tree `tree_ref`:
   - `fix/twrp-fbe-preflight` (default): preliminary non-destructive fstab/API fix for encryption testing.
   - `android-12.1`: original device tree, without that experimental fix.
4. Click **Run workflow** again to start the build.
5. If it succeeds, download the `twrp-m55xq-<run-number>` artifact ZIP at the bottom of the run page. It contains:
   - `recovery.img`
   - `twrp-m55xq-odin.tar` (TAR packaging for Odin; not tested on hardware)
   - `SHA256SUMS`
6. On failure, read the failed step and download `twrp-m55xq-failure-<run-number>`, if available.

## Performance

The workflow uses the Android 12.1 **minimal** TWRP manifest, shallow `repo` checkout, parallel sync/compilation, space reclamation, and a 2 GiB GitHub Actions `ccache` cache.

The **first build starts with an empty cache** and can still take roughly an hour or longer on a shared GitHub runner. Subsequent successful builds may be faster. A firm sub-hour build time is not guaranteed; for consistently shorter builds, a more powerful self-hosted/paid runner is needed.

Source manifest: https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp/tree/twrp-12.1

## Testing and data safety

This workflow has not been validated by a successful run yet. A successful compilation does **not** establish that the image boots or can decrypt Samsung FBE. Verify the firmware/partition layout before flashing. Keep a known-good recovery image and a backup.

Do **not** format `/data` or `/metadata` to make an encrypted volume mount. Formatting can permanently destroy access to your files.

No phone files are necessary to start the build. If decryption still fails, provide a sanitized `/tmp/recovery.log` and `adb logcat -b all -d` from the running recovery, plus Android / One UI versions. Do not share screen unlock credentials or private encryption keys.


## Telegram progress (kernel_builder style)

The Telegram integration mirrors the `vildangil/kernel_builder` notification flow.
It reports:

- Workflow start, selected device tree and optional **NOTES**.
- Environment initialization, host/CPU/free disk (when **VERBOSE** is enabled).
- Source sync start and duration.
- Device tree branch/commit and compilation start.
- Successful image compilation, timing, SHA256 and upload progress.
- Final success/failure with total duration, failing stage and GitHub Actions link.
- The failure build log (`twrp-build.log.gz`) is sent automatically if available.
- Optionally, the **Odin TAR** and `SHA256SUMS` are sent directly to the chat.

The Telegram helper lives at `.github/scripts/telegram-notify.sh` and supports
`msg`, `up` (document upload), and `escape` commands. Notifications are
best-effort and do not mark the recovery build as failed if Telegram is down.

### Configure

Open repository **Settings → Secrets and variables → Actions**, and set:

- `BOT_TOKEN`: the same bot token used in the kernel_builder project.
- `CHAT_ID`: the default Telegram group/channel/chat destination.

These must be configured **again in this repository**, as repository secrets
are not shared automatically. Never commit or send the bot token in chat.

When you click **Run workflow**, you can set these optional inputs:

| Input | Default | Meaning |
| --- | --- | --- |
| `NOTES` | empty | Optional comment sent to the chat (first 650 chars) |
| `TG_RECIPENT` | empty | Override `CHAT_ID` for this run; same spelling as kernel_builder |
| `VERBOSE` | true | Include environment/device metadata |
| `TG_UPLOAD` | true | Send recovery Odin TAR and SHA256SUMS to Telegram |

For file transfer the hosted Telegram Bot API has a file size limit. If
`twrp-m55xq-odin.tar` exceeds 49 MB, the helper splits it into 45 MB
pieces and sends all the parts. Download every part and reconstruct the
archive in filename order with:

```bash
cat twrp-m55xq-odin.tar.part-* > twrp-m55xq-odin.tar
sha256sum -c SHA256SUMS
```

The complete `recovery.img`, Odin TAR, and checksums remain available in the
GitHub Actions artifact regardless of Telegram upload success. A file sent
to Telegram is still **untested**, not guaranteed bootable or decrypt-capable.

Already-running jobs do not receive new notification steps retroactively;
start a **new** build from the `android-12.1` workflow branch to use this.
