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

Notifications now use the **same message format** as `vildangil/kernel_builder`:
every line starts with `gh <run_number>_<attempt>:`, multiple lines are passed
as `%nl`, and the ordinary status messages are not wrapped in bold headers.

Representative sequence:

```text
gh 5_1: workflow started
gh 5_1: build env initialized
gh 5_1: host: "Ubuntu 22.04.5 LTS"
gh 5_1: free disk space: 77000M
gh 5_1: cloning recovery source
gh 5_1: repo: https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp
gh 5_1: branch: twrp-12.1
gh 5_1: recovery name: TWRP
gh 5_1: recovery ver: 12.1
gh 5_1: recovery head commit: <hash>
gh 5_1: device: m55xq
gh 5_1: running compilation script(s): recoveryimage
gh 5_1: workflow ended in 35m, 10s
```

Values above are examples, not an actual successful build. On failure,
the final message uses `gh 5_1: workflow failed in 35m, 10s`.

Successful Telegram Odin TAR upload uses a caption modeled on the kernel
builder's `.info` file: compilation duration, `md5: <code>...</code>`,
and recovery version/device. `SHA256SUMS` is also uploaded. If the
recovery build or source sync fails, a compressed log is sent instead.
**Large archives are not split anymore.** The previous Odin TAR from build #4 is
112,070,656 bytes (around 107 MiB), larger than the hosted Telegram Bot API's
50 MB `sendDocument` limit. To send the **original .tar as one Telegram file**,
the workflow now supports Telegram MTProto via Telethon.

Add two additional repository Actions secrets (get the values from
https://my.telegram.org, under API development tools):

- `TG_API_ID`: your Telegram application API ID.
- `TG_API_HASH`: its matching API hash.

The build uses the existing `BOT_TOKEN` to log in **as the bot**, not as your
personal Telegram account. MTProto credentials are loaded only in the Telegram
upload step; bot authorization uses an in-memory session. The workflow
does not persist a Telegram session file or print the credentials.

When the API credentials are configured, the Telegram helper attempts to
send the whole `twrp-m55xq-odin.tar` as **one document** (no parts).
`SHA256SUMS` remains a separate tiny document.

Without those extra secrets, or if MTProto access to the destination chat
fails, no large upload is attempted through the hosted Bot API. Instead, the
chat receives a link to the GitHub Actions artifact containing the complete
unmodified TAR and `recovery.img`. A bot in a private channel/supergroup
may require a resolvable public `@username` or appropriate chat access
for MTProto; the fallback link is preserved if the upload cannot be made.

Existing workflow runs are unaffected. New Telegram behavior takes effect
on the next run from `android-12.1`.

### Configuration

Configure these **repository Actions secrets**:

- `BOT_TOKEN`: Telegram bot token (same as kernel_builder if desired).
- `CHAT_ID`: default chat or channel ID.

They are **not automatically shared** from kernel_builder. Never place tokens
in the workflow YAML or send them in chat.

Manual workflow inputs:

| Input | Default | Meaning |
| --- | --- | --- |
| `NOTES` | empty | Plain-text note sent with the build's gh prefix |
| `TG_RECIPENT` | empty | Optional chat ID override (same spelling as kernel_builder) |
| `VERBOSE` | true | Send the environment and source details |
| `TG_UPLOAD` | true | Upload Odin TAR and SHA256SUMS to Telegram |

The helper `.github/scripts/telegram-notify.sh` accepts `msg`, `up`,
`upload`, and `escape`; it uses Telegram HTML parse mode and translates
`%nl` for the message text and document captions, as in kernel_builder.

GitHub Actions artifacts remain the reliable download source. Telegram
errors are nonfatal and do not affect compilation. Running workflows retain
their original snapshot: start a **new** run after these changes.
