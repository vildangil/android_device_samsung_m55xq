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


## Telegram status messages

The workflow can report start, source-sync completion, compilation start, and
success/failure (including elapsed time and the GitHub Actions run URL) to Telegram.
Notifications are best-effort: Telegram failures do not fail the recovery build.

This follows the pattern used by the `vildangil/kernel_builder` workflow, but
uses a separate helper at `.github/scripts/telegram-notify.sh`.

**One-time setup for this repository:**

1. Open repository **Settings → Secrets and variables → Actions**.
2. Create a **repository secret** named `BOT_TOKEN` with the token for your Telegram bot.
3. Create a **repository secret** named `CHAT_ID` with the group/channel ID or private chat ID. Add the bot to the target group/channel and grant posting permissions if necessary.
4. Start a **new** Build TWRP workflow run from the `android-12.1` branch.

GitHub secrets are scoped per repository: values in `kernel_builder` are **not**
automatically available here. Do not put the bot token into the YAML file, a
workflow input, a commit, or a shared build log. Do not send the bot token in chat.

Without both secrets, the recovery build still runs but notification steps skip
sending messages. The workflow only sends build status and a link to the GitHub
Actions artifacts, **not** the recovery image itself.

Already running workflows use their original workflow snapshot and will not
gain notifications retroactively.
