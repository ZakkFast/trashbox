#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTNAME="$(hostname)"
USER_NAME="$(whoami)"

# ---------- output helpers ----------

info() {
    printf '\033[1;34m[INFO]\033[0m %s\n' "$1"
}

success() {
    printf '\033[1;32m[ OK ]\033[0m %s\n' "$1"
}

error() {
    printf '\033[1;31m[FAIL]\033[0m %s\n' "$1" >&2
}

# ---------- environment checks ----------

if [[ ! -f /etc/arch-release ]]; then
    error "This installer currently supports Arch-based systems only."
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
    error "pacman was not found."
    exit 1
fi

# ---------- GPU detection ----------

GPU_VENDOR="unknown"

if lspci | grep -Ei 'VGA|3D|Display' | grep -qi 'NVIDIA'; then
    GPU_VENDOR="nvidia"
elif lspci | grep -Ei 'VGA|3D|Display' | grep -Eqi 'AMD|ATI'; then
    GPU_VENDOR="amd"
elif lspci | grep -Ei 'VGA|3D|Display' | grep -qi 'Intel'; then
    GPU_VENDOR="intel"
fi

# ---------- host validation ----------

HOST_PROFILE="$DOTFILES_DIR/hypr/hosts/$HOSTNAME.lua"

if [[ ! -f "$HOST_PROFILE" ]]; then
    error "No host profile found:"
    error "$HOST_PROFILE"
    echo
    echo "Create a host profile before continuing."
    exit 1
fi

# ---------- summary ----------

echo
echo "======================================"
echo "        System Bootstrap"
echo "======================================"
echo

info "User:      $USER_NAME"
info "Host:      $HOSTNAME"
info "GPU:       $GPU_VENDOR"
info "Dotfiles:  $DOTFILES_DIR"

echo

success "Arch-based system detected"
success "Host profile found"
success "GPU detection complete"

export DOTFILES_DIR
export HOSTNAME
export USER_NAME
export GPU_VENDOR


echo
echo "Bootstrap preflight passed."
echo

echo
read -rp "Install/update workstation packages? [Y/n] " install_packages

if [[ ! "$install_packages" =~ ^[Nn]$ ]]; then
    bash "$DOTFILES_DIR/install/packages.sh"
else
    info "Skipping package installation"
fi

echo
read -rp "Link workstation configuration? [Y/n] " install_links

if [[ ! "$install_links" =~ ^[Nn]$ ]]; then
    bash "$DOTFILES_DIR/install/links.sh"
else
    info "Skipping configuration links"
fi

echo
read -rp "Configure development runtimes? [Y/n] " install_runtimes

if [[ ! "$install_runtimes" =~ ^[Nn]$ ]]; then
    bash "$DOTFILES_DIR/install/runtimes.sh"
else
    info "Skipping development runtimes"
fi

echo
read -rp "Configure system services? [Y/n] " install_services

if [[ ! "$install_services" =~ ^[Nn]$ ]]; then
    bash "$DOTFILES_DIR/install/services.sh"
else
    info "Skipping system services"
fi

echo
read -rp "Configure Noctalia? [Y/n] " install_noctalia

if [[ ! "$install_noctalia" =~ ^[Nn]$ ]]; then
    bash "$DOTFILES_DIR/install/noctalia.sh"
else
    info "Skipping Noctalia"
fi

echo
read -rp "Install/configure ComfyUI? [Y/n] " install_comfyui

if [[ ! "$install_comfyui" =~ ^[Nn]$ ]]; then
    bash "$DOTFILES_DIR/install/comfyui.sh"
else
    info "Skipping ComfyUI"
fi

echo
echo "======================================"
echo "       Bootstrap Complete"
echo "======================================"
echo

success "Workstation configuration finished"

echo
read -rp "Reboot now? [y/N] " reboot_now

if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
    info "Rebooting..."
    sudo systemctl reboot
else
    info "Reboot skipped"
fi