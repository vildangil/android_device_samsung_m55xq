#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Samsung m55xq AERA 16: dispatch explicit kernel reboot reason and clear BCB.

The kernel loads qcom-reboot-reason and Samsung sec_reboot_cmd modules. Ensure
the bootloader is not left holding an earlier boot-recovery command for
system/poweroff/download/fastboot selections. This does not touch user data,
change PMIC registers directly, or force a hardware reset.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: fix_reboot_reasons.py <AERA twrp-functions.cpp>")

path = Path(sys.argv[1])
source = path.read_text()
marker = "M55_EXPLICIT_NORMAL_REBOOT"
if marker in source:
    print("M55 reboot reason patch already applied")
    raise SystemExit(0)


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 upstream match, got {count}")
    source = source.replace(old, new, 1)


replace_once(
    '''		const int result = property_set(ANDROID_RB_PROPERTY, value);
		if (result != 0)
			return result;''',
    '''		LOGINFO("M55 reboot request: sys.powerctl=%s\\n", value);
		const int result = property_set(ANDROID_RB_PROPERTY, value);
		if (result != 0) {
            LOGERR("M55: failed to request reboot mode (%s): %d\\n",
                    value, result);
			return result;
        }''',
    "power control logging",
)
replace_once(
    '''			return request_power_control("reboot,");''',
    '''            // M55_EXPLICIT_NORMAL_REBOOT: Samsung reboot-reason modules
            // must see an explicit normal reason rather than an empty one.
            return request_power_control("reboot,normal");''',
    "normal boot reason",
)
for name in ("rb_bootloader", "rb_poweroff", "rb_download", "rb_edl", "rb_fastboot"):
    old = f"\t\tcase {name}:\n"
    new = old + (
        "\t\t\t// Clear only pending recovery BCB; preserve all other misc data.\n"
        "\t\t\tClear_Bootloader_Message();\n"
        "\t\t\tsync();\n"
    )
    replace_once(old, new, f"BCB clear for {name}")


# AERA's pre-reboot AVB hook may block when Samsung's encrypted /data is
# unavailable. A cold bring-up must still be able to leave recovery safely.
replace_once(
    "TWFunc::Run_Before_Reboot();",
    '''if (android::base::GetProperty("ro.product.device", "") == "m55xq"
        && !PartitionManager.Is_Mounted_By_Path("/data")) {
        LOGINFO("M55: /data unavailable; skip pre-reboot AVB/settings hooks\\n");
    } else {
        TWFunc::Run_Before_Reboot();
    }''',
    "skip unsafe pre-reboot hooks when userdata unavailable",
)

# Android init normally consumes sys.powerctl. But on this Samsung bring-up
# recovery has occasionally remained on "Rebooting" indefinitely. Wait for init
# first, then fall back to the kernel reboot syscall with an EXPLICIT reason.
# This never writes to boot partitions, EFS, userdata, or the misc BCB directly.
replace_once(
    "#include <sys/reboot.h>",
    '''#include <sys/reboot.h>
#include <linux/reboot.h>
#include <sys/syscall.h>''',
    "kernel reboot syscall includes",
)
replace_once(
    '''		for (;;)
			pause();''',
    '''        // M55_PMIC_RESET_FALLBACK: allow init to shut services down.
        // If init never reaches the PMIC, use the native kernel restart2
        // handler, preserving normal/recovery/download reasons.
        for (int waited = 0; waited < 100; ++waited)
            usleep(100000);
        LOGERR("M55: init did not reboot after sys.powerctl=%s; kernel fallback\\n",
               value);
        if (strncmp(value, "shutdown", 8) == 0)
            return static_cast<int>(syscall(
                SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
                LINUX_REBOOT_CMD_POWER_OFF, nullptr));
        const char* requested = strncmp(value, "reboot,", 7) == 0
            ? value + 7 : "normal";
        if (*requested == '\\0')
            requested = "normal";
        return static_cast<int>(syscall(
            SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
            LINUX_REBOOT_CMD_RESTART2, requested));''',
    "bounded init shutdown and PMIC kernel fallback",
)

path.write_text(source)
print("Applied Samsung reboot reason/BCB handoff for AERA.")
