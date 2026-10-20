#!/usr/bin/env python3
"""Build AeraSecrets regardless of the optional AERA Wi-Fi build flag.

The AERA host UI unconditionally references AeraSecrets::UsePrimaryWlan and
AeraSecrets::SetNasPrivateKey. Their definitions live in aera_secrets.cpp,
which upstream includes in recovery only under OF_ENABLE_WLAN=1.
Relocate only this translation unit into the common LOCAL_SRC_FILES list.

Guard both source locations so changes to upstream Android.mk fail quickly.
Keep exactly one source entry regardless of WLAN configuration; do not alter KeyMint/FBE behavior.
"""
from pathlib import Path
import sys

mk = Path.cwd() / "bootable/recovery/Android.mk"
if not mk.is_file():
    sys.exit(f"AERA patch: run from Android source root; missing {mk}")

content = mk.read_text(encoding="utf-8")
lines = content.splitlines()
slash = chr(92)
secret_line = "    aera_secrets/aera_secrets.cpp " + slash
normal_anchor = "    aera_remote/input.cpp " + slash
conditional_anchor = "    aera_adbd.cpp " + slash
nas_line = "    nas/NasManager.cpp"
gate_line = "ifeq ($(OF_ENABLE_WLAN),1)"

for name, line in (
    ("AeraSecrets", secret_line),
    ("unconditional insertion", normal_anchor),
    ("WLAN block", conditional_anchor),
    ("NAS line", nas_line),
    ("WLAN gate", gate_line),
):
    if lines.count(line) != 1:
        sys.exit(f"AERA patch: expected exactly one {name} in Android.mk")

common_at = lines.index(normal_anchor)
gate_at = lines.index(gate_line)
secret_at = lines.index(secret_line)
conditional_at = lines.index(conditional_anchor)
nas_at = lines.index(nas_line)
if not (common_at < gate_at < conditional_at < secret_at < nas_at):
    sys.exit("AERA patch: upstream Android.mk ordering changed")
if secret_at != conditional_at + 1 or nas_at != secret_at + 1:
    sys.exit("AERA patch: WLAN conditional source list changed")

lines.pop(secret_at)
lines.insert(common_at + 1, secret_line)
patched = chr(10).join(lines) + chr(10)

if patched.count("aera_secrets/aera_secrets.cpp") != 1:
    sys.exit("AERA patch: duplicate or missing secrets source")
mk.write_text(patched, encoding="utf-8")
print("AERA patch: added aera_secrets.cpp to unconditional recovery sources")
