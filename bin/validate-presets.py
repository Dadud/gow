#!/usr/bin/env python3
"""Validate per-app Wolf presets (apps/*/assets/wolf.config.toml).

This guards the contract that wolf-den's DefaultAppLoader relies on: it reads
the runner keys ``devices``, ``env``, ``mounts`` and ``ports`` and throws if any
are missing. We therefore assert that every preset declares:

  * a top-level ``[[apps]]`` array with at least one entry;
  * for each app: ``title``, ``icon_png_path``, ``runner.name``, ``runner.image``;
  * for each app's runner: ``devices``, ``env``, ``mounts`` and ``ports`` present
    as arrays.

Exits non-zero and prints the offending file + key on any failure.

Requires Python 3.11+ (uses the stdlib ``tomllib`` parser).
"""

from __future__ import annotations

import glob
import os
import sys

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover - friendlier message on old Pythons
    sys.stderr.write(
        "error: this script requires Python 3.11+ (stdlib 'tomllib' not found)\n"
    )
    sys.exit(2)

# Scalar keys required on each app table.
REQUIRED_APP_KEYS = ("title", "icon_png_path")
# Scalar keys required on each app's runner table.
REQUIRED_RUNNER_KEYS = ("name", "image")
# Keys DefaultAppLoader reads as arrays; missing/non-array ones break wolf-den.
REQUIRED_RUNNER_ARRAYS = ("devices", "env", "mounts", "ports")

PRESET_GLOB = os.path.join("apps", "*", "assets", "wolf.config.toml")


def find_presets() -> list[str]:
    return sorted(glob.glob(PRESET_GLOB))


def validate_preset(path: str) -> list[str]:
    """Return a list of human-readable error strings for ``path`` (empty == OK)."""
    errors: list[str] = []

    try:
        with open(path, "rb") as fh:
            data = tomllib.load(fh)
    except tomllib.TOMLDecodeError as exc:
        return [f"{path}: invalid TOML: {exc}"]
    except OSError as exc:
        return [f"{path}: could not read file: {exc}"]

    apps = data.get("apps")
    if apps is None:
        return [f"{path}: missing top-level [[apps]] array"]
    if not isinstance(apps, list) or not apps:
        return [f"{path}: [[apps]] must be a non-empty array of tables"]

    for idx, app in enumerate(apps):
        where = f"{path}: apps[{idx}]"
        if not isinstance(app, dict):
            errors.append(f"{where} is not a table")
            continue

        for key in REQUIRED_APP_KEYS:
            if key not in app:
                errors.append(f"{where}.{key}: missing")

        runner = app.get("runner")
        if runner is None:
            errors.append(f"{where}.runner: missing [apps.runner] table")
            continue
        if not isinstance(runner, dict):
            errors.append(f"{where}.runner: must be a table")
            continue

        for key in REQUIRED_RUNNER_KEYS:
            if key not in runner:
                errors.append(f"{where}.runner.{key}: missing")

        for key in REQUIRED_RUNNER_ARRAYS:
            if key not in runner:
                errors.append(
                    f"{where}.runner.{key}: missing (wolf-den DefaultAppLoader "
                    f"requires this array)"
                )
            elif not isinstance(runner[key], list):
                errors.append(
                    f"{where}.runner.{key}: must be an array, got "
                    f"{type(runner[key]).__name__}"
                )

    return errors


def main() -> int:
    presets = find_presets()
    if not presets:
        sys.stderr.write(f"error: no presets matched '{PRESET_GLOB}'\n")
        return 2

    all_errors: list[str] = []
    for path in presets:
        # Normalize separators so output reads the same on every OS.
        display = path.replace(os.sep, "/")
        errors = [e.replace(path, display, 1) for e in validate_preset(path)]
        if errors:
            all_errors.extend(errors)
        else:
            print(f"OK   {display}")

    if all_errors:
        sys.stderr.write("\nPreset validation FAILED:\n")
        for err in all_errors:
            sys.stderr.write(f"  - {err}\n")
        sys.stderr.write(f"\n{len(all_errors)} problem(s) found.\n")
        return 1

    print(f"\nAll {len(presets)} preset(s) valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
