#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fix AERA 16 recovery's missing boot-slot property on Samsung m55xq.

Samsung M55 reports ro.build.ab_update=true, but in recovery there are
neither ro.boot.slot_suffix nor ro.boot.slot properties. AERA silently
assigns slot B in that case, then tries to mount system_b, vendor_b, etc.
The device's logical super metadata uses the unsuffixed partition names.

Keep A/B handling for devices WITH an explicit boot slot, but use the
unsuffixed partitions and metadata slot 0 when the bootloader supplied no
slot. Read/mapper operations only; never rewrite on-device super metadata.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: fix_premapped_super.py <AERA partitionmanager.cpp>")
target = Path(sys.argv[1])
source = target.read_text()
marker = "M55_SLOTLESS_SUPER_COMPAT"
if marker in source:
    print("M55 slotless A/B super compatibility already applied")
    raise SystemExit(0)


def replace_exact(before: str, after: str, name: str) -> None:
    global source
    count = source.count(before)
    if count != 1:
        raise SystemExit(
            f"ERROR: upstream AERA {name} changed (expected 1, got {count})"
        )
    source = source.replace(before, after, 1)


replace_exact(
    '''string TWPartitionManager::Get_Active_Slot_Suffix() {
	if (Active_Slot_Display == "A")
		return "_a";
	return "_b";
}''',
    '''string TWPartitionManager::Get_Active_Slot_Suffix() {
    // M55_SLOTLESS_SUPER_COMPAT
    // Android A/B OTA support does not imply suffixed super partition names.
    // This bootloader exports neither ro.boot.slot_suffix nor ro.boot.slot.
    // Do not invent "_b" when its slot was never reported.
    const std::string boot_slot = android::base::GetProperty(
        "ro.boot.slot_suffix",
        android::base::GetProperty("ro.boot.slot", ""));
    if (boot_slot.empty()) {
        return "";
    }
    return Active_Slot_Display == "A" ? "_a" : "_b";
}''',
    "Get_Active_Slot_Suffix",
)

replace_exact(
    '''std::string TWPartitionManager::Get_Super_Partition() {
	int slot_number = Get_Active_Slot_Display() == "A" ? 0 : 1;
	std::string super_device = fs_mgr_get_super_partition_name(slot_number);
	return "/dev/block/by-name/" + super_device;
}''',
    '''std::string TWPartitionManager::Get_Super_Partition() {
    const std::string slot_suffix = Get_Active_Slot_Suffix();
    const int slot_number = slot_suffix == "_b" ? 1 : 0;
    const std::string preferred =
        "/dev/block/by-name/" + fs_mgr_get_super_partition_name(slot_number);
    if (access(preferred.c_str(), F_OK) == 0)
        return preferred;
    // Samsung's bootloader may not expose a boot slot, even when Android
    // advertises A/B OTA support. Use the *existing* physical super node.
    const std::string stock = "/dev/block/by-name/super";
    if (slot_suffix.empty() && access(stock.c_str(), F_OK) == 0)
        return stock;
    return preferred;
}''',
    "Get_Super_Partition",
)

replace_exact(
    '''#ifdef AB_OTA_UPDATER
	blk_device_partition = bare_partition_name + PartitionManager.Get_Active_Slot_Suffix();
#else
	blk_device_partition = bare_partition_name;
#endif''',
    '''#ifdef AB_OTA_UPDATER
    // An empty boot slot suffix is legitimate on the m55xq. The A/B
    // build flag remains enabled; only logical lookup avoids inventing B.
    blk_device_partition = bare_partition_name + Get_Active_Slot_Suffix();
#else
    blk_device_partition = bare_partition_name;
#endif''',
    "Prepare_Super_Volume",
)

replace_exact(
    '''    if (!fs_mgr_update_logical_partition(&fstabEntry)) {
        LOGINFO("unable to update logical partition: %s\\n", twrpPart->Get_Mount_Point().c_str());
        return false;
    }''',
    '''    if (!fs_mgr_update_logical_partition(&fstabEntry)) {
        // Tolerate an existing mapper for partitions prepared earlier in
        // recovery, but never accept paths that are not block devices.
        const std::string mapped = "/dev/block/mapper/" + blk_device_partition;
        struct stat st = {};
        if (stat(mapped.c_str(), &st) == 0 && S_ISBLK(st.st_mode)) {
            fstabEntry.blk_device = mapped;
            LOGINFO("M55: reusing mapped partition %s -> %s\\n",
                    bare_partition_name.c_str(), mapped.c_str());
        } else {
            LOGINFO("unable to update logical partition: %s; "
                    "existing mapper device also unavailable\\n",
                    twrpPart->Get_Mount_Point().c_str());
            return false;
        }
    }''',
    "existing mapper fallback",
)

target.write_text(source)
print(f"Patched M55 slotless logical partitions (A/B retained): {target}")
