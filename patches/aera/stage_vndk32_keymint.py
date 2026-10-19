#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Stage the AOSP VNDK 32 KeyMint AIDL runtime for M55 recovery.

Samsung's stock KeyMint executable is carried into the ramdisk unchanged.
It requires the historical V1 -ndk_platform ABI, which modern Android 16
recovery doesn't package automatically. Supply the exact AOSP v32 snapshot
instead of substituting a V3 .so or changing Samsung's ELF NEEDED entries.
This script operates only on the ephemeral CI build checkout; it never reads
or modifies Android userdata, EFS or credential state.
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import shutil
import subprocess
import sys

# VNDK-core legacy AIDL interfaces from the Android 12L (VNDK v32) snapshot.
LEGACY_AIDL_LIBRARIES = (
    "android.hardware.security.keymint-V1-ndk_platform.so",
    "android.hardware.security.secureclock-V1-ndk_platform.so",
    "android.hardware.security.sharedsecret-V1-ndk_platform.so",
)


def needed_libraries(path: pathlib.Path) -> str:
    return subprocess.run(
        ["readelf", "-d", str(path)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_root", type=pathlib.Path,
                        help="AERA Android 16 source tree after repo sync")
    parser.add_argument("device_tree", type=pathlib.Path,
                        help="Staged Samsung M55 tree inside the source root")
    args = parser.parse_args()

    executable = args.device_tree / (
        "recovery/root/system/bin/android.hardware.security.keymint-service"
    )
    if not executable.is_file():
        parser.error(f"missing original Samsung KeyMint binary: {executable}")

    dependencies = needed_libraries(executable)
    required = LEGACY_AIDL_LIBRARIES[0]
    if required not in dependencies:
        parser.error(f"unexpected Samsung KeyMint ABI: no dependency on {required}")

    source = args.source_root / (
        "prebuilts/vndk/v32/arm64/arch-arm64-armv8-a/shared/vndk-core"
    )
    destination = args.device_tree / "recovery/root/system/lib64"
    destination.mkdir(parents=True, exist_ok=True)

    for name in LEGACY_AIDL_LIBRARIES:
        candidate = source / name
        if not candidate.is_file() or candidate.read_bytes()[:4] != b"\x7fELF":
            parser.error(
                f"missing or invalid AOSP arm64 VNDK32 prebuilt: {candidate}; "
                "do not substitute a newer -V3-ndk library"
            )
        # e_machine 183 = EM_AARCH64; little-endian ELF64 required.
        header = candidate.read_bytes()[:20]
        if header[4] != 2 or header[5] != 1 or int.from_bytes(header[18:20], "little") != 183:
            parser.error(f"not an ELF64 aarch64 shared library: {candidate}")

        staged = destination / name
        shutil.copy2(candidate, staged)
        digest = hashlib.sha256(staged.read_bytes()).hexdigest()
        print(f"staged AOSP VNDK32 {name}: sha256={digest}", flush=True)
    # Android 12L's libcrypto fixes Samsung's sk_delete but breaks Android 16's
    # libkeymaster_portable (OPENSSL_sk_new_null). NEVER override libcrypto.
    # Instead preload one tiny arm64 ABI trampoline into KeyMint alone.
    clang_candidates = sorted(
        (args.source_root / "prebuilts/clang/host/linux-x86").glob(
            "clang-r*/bin/clang"
        )
    )
    if not clang_candidates:
        parser.error("Android clang missing; cannot build KeyMint ABI shim")
    compat_dir = destination / "keymint-compat"
    compat_dir.mkdir(parents=True, exist_ok=True)
    source_file = compat_dir / "m55_keymint_compat.c"
    source_file.write_text(
        "#include <stddef.h>\\n"
        "extern void *OPENSSL_sk_delete(void *, size_t);\\n"
        "__attribute__((visibility(\\\"default\\\"))) "
        "void *sk_delete(void *stack, size_t index) { "
        "return OPENSSL_sk_delete(stack, index); }\\n"
    )
    compat = compat_dir / "libm55_keymint_compat.so"
    subprocess.run(
        [
            str(clang_candidates[-1]),
            "--target=aarch64-linux-android30",
            "-fPIC", "-shared", "-nostdlib", "-fuse-ld=lld",
            "-Wl,-soname,libm55_keymint_compat.so",
            "-o", str(compat), str(source_file),
        ],
        check=True,
    )
    symbols = subprocess.run(
        ["readelf", "-W", "--dyn-syms", str(compat)],
        check=True, capture_output=True, text=True,
    ).stdout
    if not any(
        (cols := row.split()) and len(cols) > 7 and cols[6] != "UND"
        and cols[7] == "sk_delete"
        for row in symbols.splitlines()
    ):
        parser.error("KeyMint shim has no exported sk_delete")
    if compat.read_bytes()[:6] != bytes.fromhex("7f454c460201"):
        parser.error("KeyMint shim has invalid ELF64 header")
    print(
        "staged private M55 sk_delete shim; Android 16 libcrypto untouched: "
        f"sha256={hashlib.sha256(compat.read_bytes()).hexdigest()}",
        flush=True,
    )

    print(
        "Legacy Samsung KeyMint ABI shim staged without replacing platform libcrypto. "
        "Full FBE/Keystore2/Hermes functionality still requires on-device testing.",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
