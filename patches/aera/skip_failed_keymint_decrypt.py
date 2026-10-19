#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""M55 AERA early UI: do not block on a repeatedly crashing KeyMint HAL.

The user's encrypted /data is left untouched. Once KeyMint is truly running,
normal interactive decryption is still attempted. Emits logs around UI boot.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: skip_failed_keymint_decrypt.py <twrp.cpp>")

p = Path(sys.argv[1])
s = p.read_text()
marker = "M55_GUARD_BROKEN_KEYMINT_DECRYPT"
if marker in s:
    print("M55 KeyMint UI guard already applied")
    raise SystemExit(0)
old = "\tDecrypt_Page(skip_decryption, datamedia);"
assert s.count(old) == 1, "AERA upstream decryption call changed"
new = """    // M55_GUARD_BROKEN_KEYMINT_DECRYPT: never block the entire recovery
    // interface on a crashed KeyMint before the user can choose Reboot.
    // Do not format or alter /data; retry decryption on a later boot
    // after the KeyMint and QTEE dependencies are actually available.
    const bool m55 = android::base::GetProperty("ro.product.device", "") == "m55xq";
    const std::string keymint_state =
        android::base::GetProperty("init.svc.vendor.keymint-default", "");
    const std::string qsee_state =
        android::base::GetProperty("init.svc.qseecom-service", "");
    const std::string qtee_state =
        android::base::GetProperty("init.svc.qteeconnector-hal-1-0", "");
    const bool m55_skip_failed_hal = m55 &&
        (keymint_state != "running" || qsee_state != "running" ||
         qtee_state != "running");
    LOGINFO("M55 recovery: crypto services KeyMint=%s QSEE=%s QTEE=%s; skip=%d\\n",
            keymint_state.c_str(), qsee_state.c_str(), qtee_state.c_str(),
            static_cast<int>(skip_decryption || m55_skip_failed_hal));
    Decrypt_Page(skip_decryption || m55_skip_failed_hal, datamedia);
    LOGINFO("M55 recovery: decryption phase returned; continue UI startup\\n");"""
s = s.replace(old, new, 1)
p.write_text(s)
print("Installed M55 nonblocking boot guard for failed KeyMint HAL.")
