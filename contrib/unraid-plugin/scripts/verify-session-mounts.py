#!/usr/bin/env python3
"""Verify Wolf config.toml app runners expose libraries at expected container paths."""

from __future__ import annotations

import re
import sys
from pathlib import Path

# title -> list of (env key, container path) — must match apply-mount-presets.py
EXPECTED: dict[str, list[tuple[str, str]]] = {
    "Retroarch": [("ROMS", "/ROMs")],
    "Pegasus": [("ROMS", "/ROMs"), ("BIOS", "/bioses")],
    "EmulationStation": [
        ("ROMS", "/ROMs"),
        ("BIOS", "/bioses"),
        ("MEDIA", "/media"),
    ],
    "Steam": [("STEAM", "/home/retro/.local/share/Steam")],
    "Lutris": [("LUTRIS", "/var/lutris")],
    "Prism Launcher": [("GAMES", "/games")],
    "Kodi": [("MEDIA", "/media")],
    "Desktop (xfce)": [("GAMES", "/games")],
    "Heroic": [("GAMES", "/games")],
    "Heroic Games Launcher": [("GAMES", "/games")],
    "Plex": [("MEDIA", "/media")],
    "Emby": [("MEDIA", "/media")],
}

HOME_ALIASES: dict[str, list[str]] = {
    "Retroarch": ["/home/retro/bioses"],
    "Pegasus": ["/home/retro/bioses"],
    "EmulationStation": ["/home/retro/bioses", "/home/retro/ROMs"],
}

BAD_DEST_PREFIXES = ("/etc/wolf/",)


def parse_mount_line(line: str) -> tuple[str, str, str] | None:
    line = line.strip().strip(",").strip('"').strip("'")
    if not line:
        return None
    parts = line.split(":")
    if len(parts) < 2:
        return None
    mode = parts[2] if len(parts) >= 3 else "rw"
    return parts[0], parts[1], mode


def parse_mounts_array(text: str) -> list[tuple[str, str, str]]:
    mounts: list[tuple[str, str, str]] = []
    for raw in re.findall(r'"([^"]+)"', text):
        parsed = parse_mount_line(raw)
        if parsed:
            mounts.append(parsed)
    return mounts


def find_bracket_array(block: str, key: str) -> tuple[int, int] | None:
    match = re.search(rf"^\s*{re.escape(key)}\s*=\s*", block, flags=re.MULTILINE)
    if not match:
        return None
    idx = match.end()
    while idx < len(block) and block[idx] in " \t\n\r":
        idx += 1
    if idx >= len(block) or block[idx] != "[":
        return None
    depth = 0
    start = idx
    for pos in range(idx, len(block)):
        char = block[pos]
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return start, pos + 1
    return None


def load_paths(argv: list[str]) -> dict[str, str]:
    keys = ["ROMS", "BIOS", "MEDIA", "STEAM", "GAMES", "LUTRIS"]
    out: dict[str, str] = {}
    for key, value in zip(keys, argv):
        value = value.strip()
        if value:
            out[key] = value.rstrip("/")
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: verify-session-mounts.py CONFIG [ROMS BIOS MEDIA STEAM GAMES LUTRIS]", file=sys.stderr)
        return 2

    cfg_path = Path(sys.argv[1])
    paths = load_paths(sys.argv[2:])
    text = cfg_path.read_text(encoding="utf-8")

    failures: list[str] = []
    checked = 0
    skipped = 0

    blocks = re.split(r"(?=^\[\[profiles\.apps\]\])", text, flags=re.MULTILINE)
    for block in blocks:
        if not block.strip() or not block.lstrip().startswith("[[profiles.apps]]"):
            continue
        title_match = re.search(r'^title\s*=\s*["\']([^"\']+)["\']', block, flags=re.MULTILINE)
        if not title_match:
            continue
        title = title_match.group(1)
        expected_entries = EXPECTED.get(title)
        if not expected_entries:
            continue

        mounts_span = find_bracket_array(block, "mounts")
        if not mounts_span:
            failures.append(f"{title}: missing mounts array")
            checked += 1
            continue

        start, end = mounts_span
        mounts = parse_mounts_array(block[start:end])
        by_dest = {dst: src for src, dst, _ in mounts}

        for cfg_key, dest in expected_entries:
            host = paths.get(cfg_key, "")
            if not host:
                skipped += 1
                continue
            checked += 1
            src = by_dest.get(dest, "")
            if not src:
                failures.append(f"{title}: missing mount for {dest} (library {cfg_key} is set)")
            elif src.startswith(BAD_DEST_PREFIXES):
                failures.append(f"{title}: {dest} still points at Wolf-only path {src}")
            elif Path(src).resolve() != Path(host).resolve() and src.rstrip("/") != host.rstrip("/"):
                # Allow appdata symlink canonical paths
                if not (src.startswith("/mnt/") and host.startswith("/mnt/")):
                    failures.append(
                        f"{title}: {dest} host {src!r} does not match gow.cfg {host!r}"
                    )

        for alias_dest in HOME_ALIASES.get(title, []):
            if not paths.get("BIOS" if "bioses" in alias_dest else "ROMS", "") and "ROMs" in alias_dest:
                if not paths.get("ROMS"):
                    continue
            if alias_dest in by_dest:
                checked += 1

        for src, dst, _ in mounts:
            if dst.startswith(BAD_DEST_PREFIXES):
                failures.append(f"{title}: deprecated mount {src}:{dst}")
            if dst == "/var/lutris" and src == "lutris":
                failures.append(
                    f"{title}: still using anonymous Docker volume lutris:/var/lutris — run Fix mounts"
                )

    print(f"Checked {checked} mount expectation(s) ({skipped} skipped — library unset in gow.cfg)")

    for title in ("EmulationStation", "Steam", "Lutris", "Retroarch", "Pegasus", "Kodi", "Plex", "Emby"):
        if title not in EXPECTED:
            continue
        if not any(f.startswith(f"{title}:") for f in failures):
            block_found = bool(
                re.search(
                    rf'^\[\[profiles\.apps\]\].*?^title\s*=\s*["\']' + re.escape(title) + r'["\']',
                    text,
                    flags=re.MULTILINE | re.DOTALL,
                )
            )
            if block_found:
                print(f"  OK   {title}")

    if failures:
        print("\nFailures:")
        for line in failures:
            print(f"  FAIL {line}")
        return 2

    if checked == 0:
        print("WARN: no libraries configured in gow.cfg — set paths in plugin setup and run fix-all.sh")
        return 2

    print("\nAll configured session mounts look correct.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
