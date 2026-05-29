#!/bin/bash
# dev-install-test.sh — wipe, build custom GOW Fedora images, patch Wolf, fix mounts, verify.
#
# Typical clean test on Unraid:
#   1. Configure GPU + library paths in Settings → Games on Whales, then Install once.
#   2. Run:  bash /boot/config/plugins/gow/scripts/dev-install-test.sh --wipe --build --post-install
#      (or split: --wipe --build first, Install via UI, then --post-install only)
#
# Environment:
#   GOW_SRC   Path to gow repo (default: /mnt/user/appdata/gow-src)

set -euo pipefail

source "$(dirname "$0")/vars.sh"

err()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "WARN:  $*" >&2; }

usage() {
    cat <<'EOF'
Usage: dev-install-test.sh [OPTIONS]

Wipe, build local Fedora app images from GOW_SRC, patch config.toml, and verify mounts.

Options:
  --wipe              Run wipe-full.sh before other steps
  --remove-plugin     Pass --remove-plugin to wipe-full.sh
  --build             Build gow/<app>-fedora:TAG images (needs GOW_SRC)
  --post-install      Patch images, run fix-all, repair ES-DE, verify mounts + health
  --patch-images      Only patch runner.image in config.toml (implies post-install subset)
  --fix-all           Run fix-all.sh
  --repair-esde       Run repair-esde.sh
  --verify            Run verify-session-mounts.sh and health-check.sh
  --gow-src PATH      Gow repo root (default: /mnt/user/appdata/gow-src)
  --tag TAG           Docker tag (default: unraid-test)
  --apps LIST         Comma-separated apps (default: es-de,steam,lutris,retroarch,pegasus)
  --base-image REF    BASE_APP_IMAGE build-arg (default: ghcr.io/games-on-whales/base-app:fedora)
  -h, --help          Show this help

Examples:
  # Full clean cycle (install plugin + UI Install first if not deployed):
  dev-install-test.sh --wipe --build --post-install

  # After UI Install, only swap images and re-apply mounts:
  dev-install-test.sh --build --post-install

  # Build only:
  GOW_SRC=/mnt/user/appdata/gow-src dev-install-test.sh --build
EOF
    exit 0
}

[[ $EUID -eq 0 ]] || err "Must run as root"

DO_WIPE=false
REMOVE_PLUGIN=false
DO_BUILD=false
DO_PATCH=false
DO_FIX_ALL=false
DO_REPAIR_ESDE=false
DO_VERIFY=false
DO_POST_INSTALL=false

GOW_SRC="${GOW_SRC:-/mnt/user/appdata/gow-src}"
IMAGE_TAG="${IMAGE_TAG:-unraid-test}"
BASE_APP_IMAGE="${BASE_APP_IMAGE:-ghcr.io/games-on-whales/base-app:fedora}"
APPS_CSV="${APPS_CSV:-es-de,steam,lutris,retroarch,pegasus}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --wipe) DO_WIPE=true ;;
        --remove-plugin) REMOVE_PLUGIN=true ;;
        --build) DO_BUILD=true ;;
        --patch-images) DO_PATCH=true ;;
        --fix-all) DO_FIX_ALL=true ;;
        --repair-esde) DO_REPAIR_ESDE=true ;;
        --verify) DO_VERIFY=true ;;
        --post-install) DO_POST_INSTALL=true ;;
        --gow-src) GOW_SRC="$2"; shift ;;
        --tag) IMAGE_TAG="$2"; shift ;;
        --apps) APPS_CSV="$2"; shift ;;
        --base-image) BASE_APP_IMAGE="$2"; shift ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1 (try --help)" ;;
    esac
    shift
done

if [[ "$DO_POST_INSTALL" == true ]]; then
    DO_PATCH=true
    DO_FIX_ALL=true
    DO_REPAIR_ESDE=true
    DO_VERIFY=true
fi

SCRIPT_DIR="$(dirname "$0")"
WIPE="${SCRIPT_DIR}/wipe-full.sh"

if [[ "$DO_WIPE" == true ]]; then
    [[ -x "$WIPE" ]] || err "Missing ${WIPE}"
    info "Wiping GoW stack and appdata"
    if [[ "$REMOVE_PLUGIN" == true ]]; then
        bash "$WIPE" --remove-plugin
    else
        bash "$WIPE"
    fi
    if [[ "$DO_BUILD" == false && "$DO_PATCH" == false ]]; then
        cat <<EOF

Wipe complete. Next steps:
  1. Install / open Settings → Games on Whales
  2. Set GPU, appdata, and library paths (ROMs, BIOS, Steam, Lutris, Media, …)
  3. Click Install
  4. Re-run:  dev-install-test.sh --build --post-install

EOF
        exit 0
    fi
fi

if [[ "$DO_BUILD" == true ]]; then
    [[ -d "$GOW_SRC" ]] || err "GOW_SRC not found: ${GOW_SRC}"
    IFS=',' read -r -a APPS <<< "$APPS_CSV"
    info "Building Fedora app images from ${GOW_SRC} (tag: ${IMAGE_TAG})"
    for app in "${APPS[@]}"; do
        app="${app// /}"
        [[ -n "$app" ]] || continue
        dockerfile="${GOW_SRC}/apps/${app}/build-fedora"
        [[ -d "$dockerfile" ]] || err "Missing ${dockerfile}"
        image="gow/${app}-fedora:${IMAGE_TAG}"
        info "docker build -t ${image} ${dockerfile}"
        docker build -t "$image" \
            --build-arg "BASE_APP_IMAGE=${BASE_APP_IMAGE}" \
            "$dockerfile"
    done
    info "Built ${#APPS[@]} image(s)"
fi

if [[ "$DO_PATCH" == true || "$DO_FIX_ALL" == true || "$DO_VERIFY" == true ]]; then
    [[ -f "$GOW_CFG" ]] || err "Plugin not configured (${GOW_CFG}). Install via Settings first."
    source "$GOW_CFG"
    APPDATA="${APPDATA:-${DEFAULT_APPDATA}}"
    CFG_FILE="${APPDATA}/cfg/config.toml"
    COMPOSE_FILE="${APPDATA}/docker-compose.yml"

    if [[ "$DO_PATCH" == true ]]; then
        [[ -f "$CFG_FILE" ]] || err "Wolf config missing: ${CFG_FILE} — complete plugin Install first"
        IFS=',' read -r -a APPS <<< "$APPS_CSV"
        app_args=()
        for app in "${APPS[@]}"; do
            app="${app// /}"
            [[ -n "$app" ]] && app_args+=("$app")
        done
        info "Patching runner images in ${CFG_FILE}"
        python3 "${SCRIPT_DIR}/patch-dev-images.py" "$CFG_FILE" "$IMAGE_TAG" "${app_args[@]}"
        if [[ -f "$COMPOSE_FILE" ]]; then
            info "Restarting Wolf to pick up image changes"
            docker compose -f "$COMPOSE_FILE" restart wolf >/dev/null 2>&1 \
                || warn "Could not restart Wolf"
        fi
    fi

    if [[ "$DO_FIX_ALL" == true ]]; then
        bash "${SCRIPT_DIR}/fix-all.sh"
    fi

    if [[ "$DO_REPAIR_ESDE" == true ]]; then
        if [[ -x "${SCRIPT_DIR}/repair-esde.sh" ]]; then
            bash "${SCRIPT_DIR}/repair-esde.sh" || warn "repair-esde.sh reported errors"
        fi
    fi

    if [[ "$DO_VERIFY" == true ]]; then
        info "Session mount verification"
        bash "${SCRIPT_DIR}/verify-session-mounts.sh" || verify_rc=$?
        verify_rc=${verify_rc:-0}
        info "Stack health check"
        bash "${SCRIPT_DIR}/health-check.sh" || health_rc=$?
        health_rc=${health_rc:-0}
        if [[ "$verify_rc" -ne 0 ]] || [[ "${health_rc:-0}" -eq 1 ]]; then
            err "Verification failed (mounts=${verify_rc}, health=${health_rc:-0})"
        fi
        [[ "${health_rc:-0}" -eq 2 ]] && warn "Health is degraded (warnings only)"
    fi
fi

if [[ "$DO_BUILD" == true && "$DO_PATCH" == false && "$DO_POST_INSTALL" == false ]]; then
    cat <<EOF

Images built. After plugin Install completes, run:
  bash ${SCRIPT_DIR}/dev-install-test.sh --post-install --gow-src ${GOW_SRC} --tag ${IMAGE_TAG}

EOF
fi

info "dev-install-test.sh finished."
exit 0
