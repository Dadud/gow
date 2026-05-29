#!/usr/bin/env python3
"""Set runner.image for mount-test apps in Wolf config.toml."""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Wolf app title -> docker image repository name (without tag)
TITLE_TO_IMAGE: dict[str, str] = {
    "EmulationStation": "es-de",
    "Steam": "steam",
    "Lutris": "lutris",
    "Retroarch": "retroarch",
    "Pegasus": "pegasus",
    "Kodi": "kodi",
    "Prism Launcher": "prismlauncher",
    "Plex": "plex",
    "Emby": "emby",
    "Heroic": "heroic-games-launcher",
    "Desktop (xfce)": "xfce",
}


def patch_block(block: str, image_ref: str) -> tuple[str, bool]:
    if not re.search(r'^\s*image\s*=', block, flags=re.MULTILINE):
        return block, False
    new_block, n = re.subn(
        r'^(\s*image\s*=\s*)["\'][^"\']*["\']',
        rf'\1"{image_ref}"',
        block,
        count=1,
        flags=re.MULTILINE,
    )
    return new_block, n > 0


def main() -> int:
    if len(sys.argv) < 4:
        print(
            "Usage: patch-dev-images.py CONFIG TAG APP [APP ...]\n"
            "  Example: patch-dev-images.py config.toml unraid-test es-de steam",
            file=sys.stderr,
        )
        return 2

    cfg_path = Path(sys.argv[1])
    tag = sys.argv[2]
    apps = {a.replace("-fedora", "") for a in sys.argv[3:]}

    title_for_app = {v: k for k, v in TITLE_TO_IMAGE.items() if v in apps}
    if not title_for_app:
        print("No known app names in argument list", file=sys.stderr)
        return 1

    text = cfg_path.read_text(encoding="utf-8")
    parts = re.split(r"(?=^\[\[profiles\.apps\]\])", text, flags=re.MULTILINE)
    out: list[str] = []
    updated = 0

    for block in parts:
        if not block.strip() or not block.lstrip().startswith("[[profiles.apps]]"):
            out.append(block)
            continue
        title_match = re.search(r'^title\s*=\s*["\']([^"\']+)["\']', block, flags=re.MULTILINE)
        if not title_match:
            out.append(block)
            continue
        title = title_match.group(1)
        app = TITLE_TO_IMAGE.get(title)
        if not app or app not in apps:
            out.append(block)
            continue
        image_ref = f"gow/{app}-fedora:{tag}"
        new_block, changed = patch_block(block, image_ref)
        if changed:
            updated += 1
            print(f"Patched {title} -> {image_ref}")
        out.append(new_block)

    if updated:
        cfg_path.write_text("".join(out), encoding="utf-8")
        print(f"Updated {updated} app runner image(s) in {cfg_path}")
    else:
        print("No matching app runners found to patch", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
