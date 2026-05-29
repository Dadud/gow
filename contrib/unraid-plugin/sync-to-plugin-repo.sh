#!/bin/bash
# Copy mount-script export from gow into a local unraid-plugin clone, then commit.
set -euo pipefail

PLUGIN_REPO="${1:?Usage: $0 /path/to/unraid-plugin [branch]}"
BRANCH="${2:-cursor/unraid-dev-install-mounts-8e3e}"
GOW_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXPORT_DIR="$GOW_ROOT/contrib/unraid-plugin"

[[ -d "$PLUGIN_REPO/.git" ]] || { echo "Not a git repo: $PLUGIN_REPO" >&2; exit 1; }
[[ -d "$EXPORT_DIR/scripts" ]] || { echo "Missing $EXPORT_DIR/scripts (run from gow repo)" >&2; exit 1; }

cd "$PLUGIN_REPO"
git checkout -B "$BRANCH"

rsync -av "$EXPORT_DIR/scripts/" scripts/
chmod +x scripts/dev-install-test.sh scripts/verify-session-mounts.sh \
    scripts/test-mount-verification.sh scripts/patch-dev-images.py 2>/dev/null || true

if [[ -f "$EXPORT_DIR/DEVELOPING.snippet.md" ]]; then
  MARKER="## Clean install with custom GOW images"
  if grep -qF "$MARKER" DEVELOPING.md 2>/dev/null; then
    echo "DEVELOPING.md already contains mount dev section; update manually if needed"
  else
    cat "$EXPORT_DIR/DEVELOPING.snippet.md" >> DEVELOPING.md
  fi
fi

git add scripts/ DEVELOPING.md
if git diff --cached --quiet; then
  echo "No changes to commit"
  exit 0
fi

git commit -m "feat(scripts): dev install test flow and mount verification

Sync from Dadud/gow export/unraid-plugin-mounts.
Extend apply-mount-presets for Plex, Emby, and Heroic; normalize mount
destinations and replace anonymous Lutris volumes when host library is set."

echo "Committed on $BRANCH. Push with:"
echo "  git push -u origin $BRANCH"
