#!/usr/bin/env python3
"""Make TWRP metadata decrypt wait for the M55 auto-SPL KeyMint initializer.

Usage: wait_for_auto_spl.py <TWRP bootable/recovery/partitionmanager.cpp>

This is applied ONLY for the experimental test/twrp-auto-spl device tree.
Do not change the normal TWRP recovery decryption logic in other builds.
"""
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: wait_for_auto_spl.py <partitionmanager.cpp>")

source = Path(sys.argv[1])
text = source.read_text()
marker = "M55_AUTO_SPL_PREDECRYPT_WAIT"
if marker in text:
    print("M55 auto-SPL predecrypt wait already applied")
    raise SystemExit(0)

# TWRP Setup_Fstab_Partitions() calls Decrypt_Data() synchronously, after
# mapping logical partitions. Our background init service needs that mapping
# before it can read the installed OS/vendor SPL and launch KeyMint. Without
# this wait the metadata key is opened with TWRP's stale built-in SPL.
pattern = re.compile(
    r'(?P<indent>^[ \t]*)DataManager::SetValue\(TW_IS_ENCRYPTED, 1\);\s*\n'
    r'(?P=indent)Decrypt_Data\(\);',
    re.MULTILINE,
)
matches = list(pattern.finditer(text))
if len(matches) != 1:
    raise SystemExit(
        f"ERROR: expected one Setup_Fstab_Partitions decryption site, got {len(matches)}"
    )

indent = matches[0].group("indent")
block = """// M55_AUTO_SPL_PREDECRYPT_WAIT
// The worker is started by init, but it cannot read the real SPL until
// recovery maps the logical system/vendor partitions. Do not ask KeyMint
// to unwrap metadata with the recovery build-time (older) patch level.
{
    bool ready = false;
    for (int attempt = 0; attempt < 250; ++attempt) {
        const std::string mode =
            android::base::GetProperty("recovery.keymint_spl.mode", "");
        const std::string service =
            android::base::GetProperty("init.svc.vendor.keymint-default", "");
        if (!mode.empty() && service == "running") {
            LOGINFO("M55 auto-SPL: worker=%s, KeyMint=%s, "
                    "system=%s, vendor=%s\\n",
                    mode.c_str(), service.c_str(),
                    android::base::GetProperty(
                        "ro.build.version.security_patch", "").c_str(),
                    android::base::GetProperty(
                        "ro.vendor.build.security_patch", "").c_str());
            // 'running' is set as soon as init forks the process. On M55
            // the secure-world SKeyMint initialization takes ~1 second.
            usleep(2000000);
            ready = true;
            break;
        }
        usleep(200000);
    }
    if (!ready) {
        LOGERR("M55 auto-SPL: timed out waiting for the SPL worker "
               "and KeyMint; continuing with diagnostic metadata decrypt\\n");
    }
}
""".rstrip()

# Preserve upstream indentation and EOLs.
indented = "\n".join(indent + line if line else "" for line in block.splitlines())
replacement = (
    indent + "DataManager::SetValue(TW_IS_ENCRYPTED, 1);\n"
    + indented + "\n"
    + indent + "Decrypt_Data();"
)
updated = pattern.sub(lambda match: replacement, text, count=1)
if updated == text:
    raise SystemExit("ERROR: patch had no effect")
source.write_text(updated)
print(f"Applied M55 auto-SPL KeyMint synchronization to {source}")
