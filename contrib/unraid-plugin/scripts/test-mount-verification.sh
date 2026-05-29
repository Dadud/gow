#!/bin/bash
# Offline self-test for mount preset + verification scripts (run from repo root).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CFG="$TMPDIR/config.toml"
cat > "$CFG" <<'TOML'
[[profiles.apps]]
title = "EmulationStation"
[profiles.apps.runner]
image = "ghcr.io/games-on-whales/es-de:edge"
mounts = []

[[profiles.apps]]
title = "Lutris"
[profiles.apps.runner]
image = "ghcr.io/games-on-whales/lutris:edge"
mounts = ["lutris:/var/lutris/:rw"]
TOML

python3 "$ROOT/scripts/apply-mount-presets.py" "$CFG" \
    /mnt/user/roms /mnt/user/bioses /mnt/user/media /mnt/user/steam /mnt/user/games /mnt/user/lutris

if ! grep -q '/mnt/user/roms:/ROMs:rw' "$CFG"; then
    echo "FAIL: ES-DE ROM mount not applied" >&2
    exit 1
fi
if ! grep -q '/mnt/user/lutris:/var/lutris:rw' "$CFG"; then
    echo "FAIL: Lutris mount not applied" >&2
    exit 1
fi
if grep -q '"lutris:/var/lutris' "$CFG"; then
    echo "FAIL: anonymous lutris volume still present" >&2
    exit 1
fi

python3 "$ROOT/scripts/verify-session-mounts.py" "$CFG" \
    /mnt/user/roms /mnt/user/bioses /mnt/user/media /mnt/user/steam /mnt/user/games /mnt/user/lutris

python3 "$ROOT/scripts/patch-dev-images.py" "$CFG" test-tag es-de lutris
grep -q 'gow/es-de-fedora:test-tag' "$CFG" || { echo "FAIL: patch-dev-images"; exit 1; }

echo "OK: mount verification self-test passed"
