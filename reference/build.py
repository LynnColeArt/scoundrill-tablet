#!/usr/bin/env python3
"""Build the headless oracle from hash-verified Krita source."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".oracle"


def main():
    pin = json.loads((ROOT / "reference/upstream.json").read_text())
    source = CACHE / "source"
    for relative, expected in pin["files"].items():
        path = source / relative
        if not path.exists():
            url = f"https://raw.githubusercontent.com/KDE/krita/{pin['revision']}/{relative}"
            with urllib.request.urlopen(url, timeout=30) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != expected:
                raise SystemExit(f"Hash mismatch for {relative}")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit(f"Hash mismatch for {path}")

    qt = os.environ.get("QT_CORE_PKG", "Qt5Core")
    flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", qt], text=True))
    eigen = os.environ.get("EIGEN_INCLUDE_DIR", "/usr/include/eigen3")
    subprocess.run([
        os.environ.get("CXX", "c++"), "-std=c++17", "-O2", "-fPIC",
        "-I", eigen, "-I", str(source / "libs/image"),
        "-I", str(ROOT / "reference/shims"),
        str(ROOT / "reference/pressure.cpp"),
        str(source / "libs/image/kis_cubic_curve.cpp"),
        "-o", str(CACHE / "krita-pressure"), *flags,
    ], check=True)


if __name__ == "__main__":
    main()
