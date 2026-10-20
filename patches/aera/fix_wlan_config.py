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
timeout_marker = "M55_WLAN_SUPP_START_TIMEOUT"
if marker in source:
    if timeout_marker not in source:
        raise SystemExit("partial WLAN patch: writable config set but startup timeout not extended")
    print("M55 writable supplicant config and startup timeout already selected")
    raise SystemExit(0)

old = 'static const char* DEFAULT_SUPP_CONF  = "/vendor/etc/wifi/wpa_supplicant.conf";'
new = 'static const char* DEFAULT_SUPP_CONF  = "/tmp/wpa_supplicant.conf"; // M55_RECOVERY_WRITABLE_SUPPLICANT_CONF'
old_timeout = 'if (!WaitForProperty(WLAN_SUPP_SVC_PROP, "running", 20000)) {'
new_timeout = 'if (!WaitForProperty(WLAN_SUPP_SVC_PROP, "running", 60000)) { // M55_WLAN_SUPP_START_TIMEOUT'
if source.count(old) != 1:
    raise SystemExit(
        "unexpected upstream AERA WLAN config anchor count="
        + str(source.count(old))
    )
if source.count(old_timeout) != 1:
    raise SystemExit(
        "unexpected upstream AERA WLAN service timeout anchor count="
        + str(source.count(old_timeout))
    )
source = source.replace(old, new, 1).replace(old_timeout, new_timeout, 1)
path.write_text(source)
print("M55 recovery WLAN uses writable /tmp/wpa_supplicant.conf")
