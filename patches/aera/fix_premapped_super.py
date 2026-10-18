#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Reuse early-mapped super partitions in AERA's partition manager.

AERA's Android 16 recovery startup creates /dev/block/dm-0 .. dm-5 via
CreateLogicalPartitions() before Parse_Fstab()/Prepare_Super_Volume(). On
the Galaxy M55, fs_mgr_update_logical_partition() can fail when asked to
create those devices again. Preserve the existing verified block-device
mapping rather than discarding the entire /system and /vendor entries.

This changes only a build checkout, not the phone's super metadata.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: fix_premapped_super.py <AERA partitionmanager.cpp>")
target = Path(sys.argv[1])
source = target.read_text()
marker = "M55_PREMAPPED_SUPER_RECOVERY"
if marker in source:
    print("AERA pre-mapped super fix already applied")
    raise SystemExit(0)

original = """    if (!fs_mgr_update_logical_partition(&fstabEntry)) {
        LOGINFO("unable to update logical partition: %s\\n", twrpPart->Get_Mount_Point().c_str());
        return false;
    }
"""
replacement = """    if (!fs_mgr_update_logical_partition(&fstabEntry)) {
        // M55_PREMAPPED_SUPER_RECOVERY
        // Init/recovery already mapped all six logical partitions. Android
        // 16 libfs_mgr may refuse the duplicate CreateLogicalPartition()
        // request even though the existing mapper device is usable.
        // Never modify Super metadata or fabricate a block device.
        const std::string already_mapped = "/dev/block/mapper/" + blk_device_partition;
        struct stat mapper_stat = {};
        if (stat(already_mapped.c_str(), &mapper_stat) == 0 &&
            S_ISBLK(mapper_stat.st_mode)) {
            fstabEntry.blk_device = already_mapped;
            LOGINFO("M55: reusing already mapped logical partition %s -> %s\\n",
                    bare_partition_name.c_str(), already_mapped.c_str());
        } else {
            LOGINFO("unable to update logical partition: %s; "
                    "existing mapper device also unavailable\\n",
                    twrpPart->Get_Mount_Point().c_str());
            return false;
        }
    }
"""
if source.count(original) != 1:
    raise SystemExit(f"Upstream AERA logical partition call changed; expected one site, got {source.count(original)}")
target.write_text(source.replace(original, replacement, 1))
print(f"Patched AERA pre-mapped super handling: {target}")
