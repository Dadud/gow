# Unraid plugin mount scripts (sync export)

These files mirror [Dadud/unraid-plugin](https://github.com/Dadud/unraid-plugin) branch
`cursor/unraid-dev-install-mounts-8e3e`. The Cloud Agent GitHub App can push to **Dadud/gow**
only; use one of the options below to land them on **Dadud/unraid-plugin**.

## Option A — Push from your machine (recommended)

```bash
git clone https://github.com/Dadud/unraid-plugin.git
cd unraid-plugin
git checkout -b cursor/unraid-dev-install-mounts-8e3e

# Copy from this gow branch
GOW_SRC=/path/to/gow   # clone Dadud/gow, branch export/unraid-plugin-mounts
rsync -av "$GOW_SRC/contrib/unraid-plugin/scripts/" scripts/
# Merge DEVELOPING.md section from contrib/unraid-plugin/DEVELOPING.snippet.md (bottom)

git add scripts/ DEVELOPING.md
git commit -m "feat(scripts): dev install test flow and mount verification"
git push -u origin cursor/unraid-dev-install-mounts-8e3e
```

## Option B — One-liner apply script

From a clone of **both** repos as siblings:

```bash
bash /path/to/gow/contrib/unraid-plugin/sync-to-plugin-repo.sh /path/to/unraid-plugin
cd /path/to/unraid-plugin && git push -u origin cursor/unraid-dev-install-mounts-8e3e
```

Requires your own `gh auth login` or SSH key with push access to Dadud/unraid-plugin.

## Option C — Grant Cursor push access on unraid-plugin

GitHub → **Dadud/unraid-plugin** → Settings → Integrations → GitHub Apps → **Cursor** →
configure access to include this repository (same as gow). Then the agent can push directly.

## Files in this export

- `scripts/dev-install-test.sh` — wipe, build, patch images, fix-all, verify
- `scripts/verify-session-mounts.sh` / `.py` — config.toml mount checks
- `scripts/patch-dev-images.py` — set `gow/*-fedora:<tag>` in Wolf config
- `scripts/test-mount-verification.sh` — offline self-test
- `scripts/apply-mount-presets.py` — Plex/Emby/Heroic + Lutris volume merge fix
