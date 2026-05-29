#!/bin/bash
# verify-session-mounts.sh — confirm Wolf app runners have expected session bind mounts.
#
# Run on Unraid after deploy + fix-all (or dev-install-test.sh --verify).
# Exit 0 if all checked apps match expectations; 1 if config missing; 2 if mismatches.

set -euo pipefail

source "$(dirname "$0")/vars.sh"

err()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "WARN:  $*" >&2; }

[[ $EUID -eq 0 ]] || err "Must run as root"
[[ -f "$GOW_CFG" ]] || err "Config not found at ${GOW_CFG}"
source "$GOW_CFG"

APPDATA="${APPDATA:-${DEFAULT_APPDATA}}"
CFG_FILE="${APPDATA}/cfg/config.toml"
[[ -f "$CFG_FILE" ]] || err "Wolf config not found: ${CFG_FILE}"

VERIFY_PY="$(dirname "$0")/verify-session-mounts.py"
[[ -f "$VERIFY_PY" ]] || err "Missing ${VERIFY_PY}"

info "Verifying session mounts in ${CFG_FILE}"
python3 "$VERIFY_PY" "$CFG_FILE" "${ROMS_LIBRARY:-}" "${BIOS_LIBRARY:-}" "${MEDIA_LIBRARY:-}" \
    "${STEAM_LIBRARY:-}" "${GAMES_LIBRARY:-}" "${LUTRIS_LIBRARY:-}"
exit $?
