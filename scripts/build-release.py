#!/usr/bin/env python3
"""Build TenUI's release ZIP from the checkout. Requires Python 3.9+."""
import argparse
import os
from pathlib import Path, PurePosixPath
import re
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "TenUI"
DOCS = ("README.md", "CHANGELOG.md", "LICENSE")
SUFFIXES = {".lua", ".xml", ".toc", ".png", ".tga", ".ttf", ".txt"}
ZIP_DATE = (1980, 1, 1, 0, 0, 0)


def release_files():
    files = {}
    for path in sorted(ADDON.rglob("*")):
        relative = path.relative_to(ADDON)
        if (
            path.suffix.lower() in SUFFIXES
            and path.is_file()
            and not any(part.startswith(".") for part in relative.parts)
        ):
            if path.is_symlink():
                raise ValueError(f"Symlink in addon payload: {relative}")
            files[relative.as_posix()] = path.read_bytes()
    for name in DOCS:
        files[name] = (ROOT / name).read_bytes()
    return files


def validate_manifest(files):
    def require(parent, raw):
        target = (PurePosixPath(parent).parent / raw.replace("\\", "/")).as_posix()
        if target not in files:
            raise ValueError(f"{parent} references missing file {target}")

    for name, content in files.items():
        if name.endswith(".toc"):
            for line in content.decode("utf-8-sig").splitlines():
                entry = line.strip()
                if entry and not entry.startswith("#"):
                    require(name, entry)
        elif name.endswith(".xml"):
            for node in ET.fromstring(content).iter():
                if node.tag.rsplit("}", 1)[-1] in {"Include", "Script"} and "file" in node.attrib:
                    require(name, node.attrib["file"])


def write_release(destination, files):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as temp:
        scratch = Path(temp.name)
    try:
        # Stored entries keep the same bytes across platforms and zlib versions.
        with zipfile.ZipFile(scratch, "w", compression=zipfile.ZIP_STORED) as archive:
            for name, content in sorted(files.items()):
                entry = zipfile.ZipInfo(f"TenUI/{name}", ZIP_DATE)
                entry.create_system = 3
                entry.external_attr = 0o100644 << 16
                archive.writestr(entry, content)
        with zipfile.ZipFile(scratch) as archive:
            if len(archive.infolist()) != len(files) or any(
                archive.read(f"TenUI/{name}") != content for name, content in files.items()
            ):
                raise ValueError("ZIP validation failed")
        scratch.chmod(0o644)
        os.replace(scratch, destination)
    finally:
        scratch.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Override the output ZIP path")
    args = parser.parse_args()
    files = release_files()
    match = re.search(rb"^## Version: (\d+\.\d+\.\d+)\s*$", files["TenUI.toc"], re.M)
    if not match:
        parser.error("Missing release version in TenUI.toc")
    version = match[1].decode()
    destination = args.output or ROOT / "releases" / f"TenUI-{version}.zip"
    validate_manifest(files)
    write_release(destination, files)
    print(destination.resolve())


if __name__ == "__main__":
    main()
