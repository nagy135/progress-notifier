#!/usr/bin/env python3
"""Refresh the offline Lucide SVG catalog from its pinned official npm package."""
import io
import json
from pathlib import Path
import tarfile
import urllib.request

VERSION = "1.61.0"
destination = Path(__file__).resolve().parents[1] / "Sources/ProgressNotifier/Resources"
destination.mkdir(parents=True, exist_ok=True)
with urllib.request.urlopen(f"https://registry.npmjs.org/lucide-static/-/lucide-static-{VERSION}.tgz") as response:
    archive = tarfile.open(fileobj=io.BytesIO(response.read()), mode="r:gz")
icons = {}
with archive:
    for member in archive.getmembers():
        if member.name.startswith("package/icons/") and member.name.endswith(".svg"):
            icons[Path(member.name).stem] = archive.extractfile(member).read().decode()
        if member.name == "package/LICENSE":
            (destination / "Lucide-LICENSE.txt").write_bytes(archive.extractfile(member).read())
assert "layers" in icons and "snowflake" in icons
(destination / "lucide-icons.json").write_text(json.dumps(icons, sort_keys=True, separators=(",", ":")))
print(f"Vendored {len(icons)} Lucide {VERSION} SVGs")
