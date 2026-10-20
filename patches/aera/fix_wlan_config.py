#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Point AERA recovery Wi-Fi at a writable, RAM-backed supplicant config."""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: fix_wlan_config.py <wlan.cpp>")

path = Path(sys.argv[1])
source = path.read_text()
marker = "M55_RECOVERY_WRITABLE_SUPPLICANT_CONF"
if marker in source:
    print("M55 writable supplicant config already selected")
    raise SystemExit(0)

old = 'static const char* DEFAULT_SUPP_CONF  = "/vendor/etc/wifi/wpa_supplicant.conf";'
new = 'static const char* DEFAULT_SUPP_CONF  = "/tmp/wpa_supplicant.conf"; // M55_RECOVERY_WRITABLE_SUPPLICANT_CONF'
if source.count(old) != 1:
    raise SystemExit(
        "unexpected upstream AERA WLAN config anchor count="
        + str(source.count(old))
    )
path.write_text(source.replace(old, new, 1))
print("M55 recovery WLAN uses writable /tmp/wpa_supplicant.conf")
