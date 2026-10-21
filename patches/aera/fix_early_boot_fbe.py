#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Samsung M55 AERA: don't deadlock fstab init on unavailable KeyMint/Keystore2.

Apply only to the ephemeral AERA source checkout. Does not decrypt, format,
wipe, or write to /data. Also clears stale recovery BCB *before* risky fstab.
"""
from pathlib import Path
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: fix_early_boot_fbe.py <partitionmanager.cpp> <twrp.cpp>")

pm = Path(sys.argv[1])
tw = Path(sys.argv[2])
partition_src = pm.read_text()
twrp_src = tw.read_text()
marker = "M55_EARLY_KEYMINT_FBE_GUARD"
if marker in partition_src:
    assert "M55_EARLY_BCB_CLEAR" in twrp_src, "only one source patched"
    print("M55 early boot guard already present")
    raise SystemExit(0)

old_pm = "\t\tDataManager::SetValue(TW_IS_ENCRYPTED, 1);\n\t\tDecrypt_Data();"
new_pm = """        DataManager::SetValue(TW_IS_ENCRYPTED, 1);
        // M55_EARLY_KEYMINT_FBE_GUARD: Process_Fstab calls Decrypt_Data()
        // synchronously, before the GUI exists. With Samsung KeyMint/QSEE
        // restarting, MetadataCrypt::retrieveKey() waits indefinitely for
        // Keystore2, leaving recovery at its splash and its BCB uncleared.
        // Keep userdata encrypted; continue booting the UI. Do not interpret
        // this as successful decryption. Normal decryption is still enabled
        // as soon as the secure HAL stack is functional.
        const bool m55_early_boot =
            android::base::GetProperty("ro.product.device", "") == "m55xq";
        std::string m55_keymint;
        std::string m55_qsee;
        std::string m55_qtee;
        std::string m55_gatekeeper;
        bool m55_secure_ready = !m55_early_boot;
        // M55_EARLY_FBE_WAIT: give init time to mount vendor and bring up
        // qseecomd, QTEEConnector, QSEECom and KeyMint. A single property
        // snapshot at Process_Fstab entry races these services on cold boot.
        // Keep the wait bounded: a broken HAL must not hang recovery forever.
        if (m55_early_boot) {
            for (int m55_wait = 0; m55_wait < 75; ++m55_wait) {
                m55_keymint =
                    android::base::GetProperty("init.svc.vendor.keymint-default", "");
                m55_qsee =
                    android::base::GetProperty("init.svc.qseecom-service", "");
                m55_qtee =
                    android::base::GetProperty("init.svc.qteeconnector-hal-1-0", "");
                m55_gatekeeper =
                    android::base::GetProperty("init.svc.gatekeeper-1-0", "");
                if (m55_keymint == "running" &&
                    m55_qsee == "running" &&
                    m55_qtee == "running" &&
                    m55_gatekeeper == "running") {
                    m55_secure_ready = true;
                    break;
                }
                // Do not wait out all 75 seconds if the one-shot helper
                // has already failed to start the secure stack.
                if (m55_wait >= 5 &&
                    android::base::GetProperty(
                        "init.svc.m55-secure-stack-init", "") == "stopped") {
                    LOGINFO("M55: secure-stack helper finished without all HALs; "
                            "skip the remaining FBE startup wait\\n");
                    break;
                }
                sleep(1);
            }
        }
        if (m55_early_boot && !m55_secure_ready) {
            LOGINFO("M55 early FBE deferred after bounded wait (KeyMint=%s, QSEE=%s, QTEE=%s, Gatekeeper=%s):"
                    " continue recovery UI with encrypted /data\\n",
                    m55_keymint.c_str(), m55_qsee.c_str(), m55_qtee.c_str(),
                    m55_gatekeeper.c_str());
        } else {
            LOGINFO("M55 early FBE: secure services ready or non-M55; trying /data\\n");
            Decrypt_Data();
        }"""
if partition_src.count(old_pm) != 1:
    raise SystemExit(f"unexpected upstream Decrypt_Data call count={partition_src.count(old_pm)}")

old_tw = """\tprintf("=> Processing %s\\n", fstab_filename.c_str());
\tif (!PartitionManager.Process_Fstab(fstab_filename, 1, !startup.Get_Fastboot_Mode())) {"""
new_tw = """    printf("=> Processing %s\\n", fstab_filename.c_str());
    // M55_EARLY_BCB_CLEAR: upstream recovery writes boot-recovery into misc
    // on entry. If the fstab/metadata-decryption step hangs, the late normal
    // Clear_Bootloader_Message() never executes; all reboots return here.
    // Clear only the bootloader message, never format or wipe misc.
    if (android::base::GetProperty("ro.product.device", "") == "m55xq") {
        LOGINFO("M55: clearing recovery BCB before fstab/decryption\\n");
        TWFunc::Clear_Bootloader_Message();
    }
    if (!PartitionManager.Process_Fstab(fstab_filename, 1, !startup.Get_Fastboot_Mode())) {"""
if twrp_src.count(old_tw) != 1:
    raise SystemExit(f"unexpected upstream Process_Fstab call count={twrp_src.count(old_tw)}")

pm.write_text(partition_src.replace(old_pm, new_pm, 1))
tw.write_text(twrp_src.replace(old_tw, new_tw, 1))
print("M55 early KeyMint FBE guard and early BCB cleanup applied")
