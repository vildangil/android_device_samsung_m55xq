#!/usr/bin/env python3
"""AERA aera-16.0 link fix: build the credentials implementation without WLAN.

Upstream bootable/recovery/Android.mk adds aera_secrets/aera_secrets.cpp
only inside 'ifeq ($(OF_ENABLE_WLAN),1)', but libaera_recovery_host uses
AeraSecrets::UsePrimaryWlan and ::SetNasPrivateKey unconditionally. Without
OF_ENABLE_WLAN, recovery fails to link. Relocate that ONE translation unit
to the unconditionally compiled LOCAL_SRC_FILES list.

Keep all other WLAN / NAS modules gated, so this does not enable Wi-Fi,
touch stored credentials, or change any Android runtime encryption logic.
Fail closed if upstream layout changes; never silently produce a partial
or duplicate source list.
"""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[3]
mk = root / "bootable" / "recovery" / "Android.mk"
if not mk.is_file():
    sys.exit(f"AERA patch: missing upstream Android.mk: {mk}")
content = mk.read_text(encoding="utf-8")

unconditional = (
    "    aera_remote/input.cpp \\\n"
    "    aeraui/features/plugin_api/operations.cpp \\\n"
)
unconditional_patched = (
    "    aera_remote/input.cpp \\\n"
    "    aera_secrets/aera_secrets.cpp \\\n"
    "    aeraui/features/plugin_api/operations.cpp \\\n"
)
conditional = (
    "    aera_adbd.cpp \\\n"
    "    aera_secrets/aera_secrets.cpp \\\n"
    "    nas/NasManager.cpp"
)
conditional_patched = (
    "    aera_adbd.cpp \\\n"
    "    nas/NasManager.cpp"
)

# AERA may fix the regression upstream; do not reapply on a corrected tree.
if content.count("aera_secrets/aera_secrets.cpp") != 1:
    sys.exit("AERA patch: expected exactly one reference to aera_secrets.cpp")
if content.count(unconditional) != 1 or content.count(conditional) != 1:
    sys.exit("AERA patch: upstream Android.mk source blocks changed; manual review needed")

result = content.replace(unconditional, unconditional_patched, 1)
result = result.replace(conditional, conditional_patched, 1)
if result.count("aera_secrets/aera_secrets.cpp") != 1:
    sys.exit("AERA patch: relocation produced duplicate or missing source")
if result.find("aera_secrets/aera_secrets.cpp") > result.find("ifeq ($(OF_ENABLE_WLAN),1)"):
    sys.exit("AERA patch: secrets must be outside the WLAN conditional")
mk.write_text(result, encoding="utf-8")
print("AERA patch applied: AeraSecrets compiled even with OF_ENABLE_WLAN disabled")
