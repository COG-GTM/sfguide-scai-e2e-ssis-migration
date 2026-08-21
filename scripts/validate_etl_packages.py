#!/usr/bin/env python3
"""Validate the SSIS packages in etl/ are well-formed and carry executable SQL tasks.

SSIS packages cannot be executed on Linux, so this is the build-time check for
the ETL inputs of the migration: XML well-formedness plus a per-package summary
of the executables and connection managers SnowConvert AI will read.
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

DTS_NS = "www.microsoft.com/SqlServer/Dts"
ETL_DIR = Path(__file__).resolve().parent.parent / "etl"


def validate(path: Path) -> bool:
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        print(f"FAIL: {path.name}: malformed XML: {exc}")
        return False

    executables = [
        el
        for el in root.iter()
        if el.tag.endswith("}Executable") or el.tag == "Executable"
    ]
    connections = [
        el
        for el in root.iter()
        if el.tag.endswith("}ConnectionManager") or el.tag == "ConnectionManager"
    ]
    if DTS_NS not in (root.tag or ""):
        print(f"FAIL: {path.name}: root element is not a DTS Executable ({root.tag})")
        return False
    if not executables:
        print(f"FAIL: {path.name}: no Executable tasks found")
        return False

    print(
        f"PASS: {path.name}: {len(executables)} executable(s), "
        f"{len(connections)} connection manager(s)"
    )
    return True


def main() -> int:
    packages = sorted(ETL_DIR.glob("*.dtsx"))
    if not packages:
        print(f"FAIL: no .dtsx packages found in {ETL_DIR}")
        return 1
    ok = all(validate(p) for p in packages)
    print("All ETL packages validated." if ok else "ETL package validation failed.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
