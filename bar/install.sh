#!/usr/bin/env bash
# Link the bar plugin into the Omarchy shell and switch it on. The source
# stays here, next to the daemon it talks to; the shell only sees symlinks.
# Run it again after editing the plugin: the shell watches its own plugin
# folder and does not notice an edit made through the links.
set -euo pipefail

id=steveng.bromodachi
src="$(cd "$(dirname "$0")" && pwd)/$id"
dst="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$id"

mkdir -p "$dst"
for f in "$src"/*; do
  ln -sfn "$f" "$dst/$(basename "$f")"
done

# a rescan reloads every plugin and can keep the shell busy for a few seconds
export OMARCHY_SHELL_IPC_TIMEOUT=15s
omarchy-shell shell rescanPlugins
omarchy plugin enable "$id" --after steveng.gitea
