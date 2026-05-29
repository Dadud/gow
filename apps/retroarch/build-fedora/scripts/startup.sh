#!/bin/bash
set -e

source /opt/gow/bash-lib/utils.sh

# Link bind-mount paths into $HOME without nesting inside existing directories.
_link_host_mount() {
    local target=$1 link=$2
    if [[ -L "$link" ]] || [[ ! -e "$link" ]]; then
        ln -sfn "$target" "$link"
    elif [[ -d "$link" ]] && [[ -z "$(ls -A "$link" 2>/dev/null)" ]]; then
        rmdir "$link" && ln -sfn "$target" "$link"
    else
        gow_log "WARN: ${link} is a non-empty directory; remove or merge into ${target} so host mounts work"
    fi
}

gow_log "Starting RetroArch"

if [[ -d /ROMs ]] && [[ -z "$(ls -A /ROMs 2>/dev/null)" ]]; then
    gow_log "WARN: /ROMs is empty — configure ROMs library in the plugin and run Fix mounts"
fi
_link_host_mount /ROMs "${HOME}/ROMs"

CFG_DIR=$HOME/.config/retroarch

# Copying config in case it's the first time we mount from the host
mkdir -p "$CFG_DIR/cores/"

cp -u /cfg/retroarch.cfg "$CFG_DIR/retroarch.cfg"

# Copy pre-installed cores from the retroarch ppa
# shellcheck disable=SC2046
# cp -u /usr/lib/$(uname -m)-linux-gnu/libretro/* "$CFG_DIR/cores/"

# if there are no assets, manually download them
if [ ! -d "$CFG_DIR/assets" ]; then
    gow_log "Missing assets, downloading..."
    wget -q --show-progress -P /tmp https://buildbot.libretro.com/assets/frontend/assets.zip
    7z x /tmp/assets.zip -bso0 -bse0 -bsp1 -o"$CFG_DIR/assets"
    rm /tmp/assets.zip
fi

# Add the base autoconfig profile so that it'll pickup joypads automatically
if [ ! -d "$CFG_DIR/autoconfig" ]; then
    gow_log "Missing autoconfig, downloading..."
    wget -q --show-progress -P /tmp https://buildbot.libretro.com/assets/frontend/autoconfig.zip
    7z x /tmp/autoconfig.zip -bso0 -bse0 -bsp1 -o"$CFG_DIR/autoconfig"
    rm /tmp/autoconfig.zip
fi

source /opt/gow/launch-comp.sh
launcher /usr/bin/retroarch
