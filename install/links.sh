#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:?DOTFILES_DIR is not set}"

backup_target() {
    local target="$1"
    local backup

    backup="${target}.backup.$(date +%Y%m%d-%H%M%S)"

    echo "[INFO] Existing file/directory found:"
    echo "       $target"
    echo "[INFO] Moving it to:"
    echo "       $backup"

    mv "$target" "$backup"
}

link_item() {
    local source="$1"
    local target="$2"

    mkdir -p "$(dirname "$target")"

    # Already linked correctly
    if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$(readlink -f "$source")" ]]; then
        echo "[ OK ] $target already linked"
        return
    fi

    # Wrong/broken symlink
    if [[ -L "$target" ]]; then
        echo "[INFO] Replacing existing symlink: $target"
        rm "$target"

    # Real file/directory already exists
    elif [[ -e "$target" ]]; then
        backup_target "$target"
    fi

    ln -s "$source" "$target"
    echo "[ OK ] Linked $target"
}

echo
echo "Linking workstation configuration..."
echo

# Hyprland
link_item \
    "$DOTFILES_DIR/hypr" \
    "$HOME/.config/hypr"

# Alacritty
link_item \
    "$DOTFILES_DIR/alacritty" \
    "$HOME/.config/alacritty"

# Helper commands
link_item \
    "$DOTFILES_DIR/scripts/comfy" \
    "$HOME/.local/bin/comfy"

link_item \
    "$DOTFILES_DIR/scripts/comfylogs-toggle" \
    "$HOME/.local/bin/comfylogs-toggle"

echo
echo "[ OK ] Dotfile linking complete."
