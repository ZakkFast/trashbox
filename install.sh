#!/usr/bin/env bash

set -Eeuo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTNAME="$(hostname)"
USER_NAME="$(whoami)"
CURRENT_STAGE="preflight"
SUDO_KEEPALIVE_PID=""

# ---------- colors / output ----------

RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'
MAGENTA=$'\033[1;35m'
CYAN=$'\033[1;36m'

info() {
    printf '%b[INFO]%b %s\n' "$BLUE" "$RESET" "$1"
}

success() {
    printf '%b[ OK ]%b %s\n' "$GREEN" "$RESET" "$1"
}

warn() {
    printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$1"
}

error() {
    printf '%b[FAIL]%b %s\n' "$RED" "$RESET" "$1" >&2
}

banner() {
    local title="$1"

    echo
    printf '%b╭──────────────────────────────────────────────╮%b\n' "$MAGENTA" "$RESET"
    printf '%b│%b %-44s %b│%b\n' "$MAGENTA" "$RESET" "$title" "$MAGENTA" "$RESET"
    printf '%b╰──────────────────────────────────────────────╯%b\n' "$MAGENTA" "$RESET"
    echo
}

section() {
    printf '\n%b◆ %s%b\n' "$CYAN" "$1" "$RESET"
}

# ---------- cleanup / error handling ----------

cleanup() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}

handle_error() {
    local exit_code="$1"
    local line_no="$2"
    local command="$3"

    trap - ERR

    echo
    error "Bootstrap failed during: $CURRENT_STAGE"
    error "Command: $command"
    error "Exit code: $exit_code (line $line_no)"
    echo
    error "Fix the issue, then rerun the installer. Completed stages are safe to run again."

    exit "$exit_code"
}

trap cleanup EXIT
trap 'handle_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

# ---------- prompt helpers ----------

prompt_yes_no() {
    local -n target="$1"
    local label="$2"
    local default="${3:-yes}"
    local hint answer

    if [[ "$default" == "yes" ]]; then
        hint="Y/n"
    else
        hint="y/N"
    fi

    printf '%b  ◆%b %-39s %b[%s]%b ' "$CYAN" "$RESET" "$label" "$DIM" "$hint" "$RESET"
    IFS= read -r answer

    if [[ "$default" == "yes" ]]; then
        if [[ "$answer" =~ ^[Nn]$ ]]; then
            target="no"
        else
            target="yes"
        fi
    else
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            target="yes"
        else
            target="no"
        fi
    fi
}

choice_enabled() {
    [[ "$1" == "yes" ]]
}

plan_item() {
    local label="$1"
    local choice="$2"

    if choice_enabled "$choice"; then
        printf '  %-34s %bRUN%b\n' "$label" "$GREEN" "$RESET"
    else
        printf '  %-34s %bSKIP%b\n' "$label" "$YELLOW" "$RESET"
    fi
}

run_stage() {
    local label="$1"
    local choice="$2"
    local script="$3"

    if choice_enabled "$choice"; then
        CURRENT_STAGE="$label"
        section "$label"
        bash "$script"
        success "$label complete"
    else
        info "Skipping $label"
    fi
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

if ! command -v sudo >/dev/null 2>&1; then
    error "sudo was not found."
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

banner "System Bootstrap"

printf '%bMachine%b\n' "$BOLD" "$RESET"
printf '  User:      %s\n' "$USER_NAME"
printf '  Host:      %s\n' "$HOSTNAME"
printf '  GPU:       %s\n' "$GPU_VENDOR"
printf '  Dotfiles:  %s\n' "$DOTFILES_DIR"

echo
success "Arch-based system detected"
success "Host profile found"
success "GPU detection complete"

export DOTFILES_DIR
export HOSTNAME
export USER_NAME
export GPU_VENDOR

# ---------- bootstrap choices ----------

section "Installation Menu"
printf '%bChoose everything up front, then the installer can run unattended.%b\n\n' "$DIM" "$RESET"

prompt_yes_no install_packages "Install/update workstation packages?" yes
prompt_yes_no install_links "Link workstation configuration?" yes
prompt_yes_no install_runtimes "Configure development runtimes?" yes
prompt_yes_no install_services "Configure system services?" yes
prompt_yes_no install_noctalia "Configure Noctalia?" yes
prompt_yes_no install_comfyui "Install/configure ComfyUI?" yes

section "Install Plan"
plan_item "Workstation packages" "$install_packages"
plan_item "Configuration links" "$install_links"
plan_item "Development runtimes" "$install_runtimes"
plan_item "System services" "$install_services"
plan_item "Noctalia" "$install_noctalia"
plan_item "ComfyUI" "$install_comfyui"

echo
info "Selections recorded. Authenticating sudo before the unattended run..."

# ---------- sudo ----------

CURRENT_STAGE="sudo authentication"
sudo -v
success "sudo credentials cached"

# Keep sudo alive during long package / ComfyUI installs so later privileged
# stages do not unexpectedly stop for another password prompt.
(
    while true; do
        sleep 60
        sudo -n true >/dev/null 2>&1 || exit 0
    done
) &
SUDO_KEEPALIVE_PID=$!

info "Starting bootstrap. You can walk away now."

# ---------- install ----------

run_stage "Workstation packages" "$install_packages" "$DOTFILES_DIR/install/packages.sh"
run_stage "Configuration links" "$install_links" "$DOTFILES_DIR/install/links.sh"
run_stage "Development runtimes" "$install_runtimes" "$DOTFILES_DIR/install/runtimes.sh"
run_stage "System services" "$install_services" "$DOTFILES_DIR/install/services.sh"
run_stage "Noctalia" "$install_noctalia" "$DOTFILES_DIR/install/noctalia.sh"
run_stage "ComfyUI" "$install_comfyui" "$DOTFILES_DIR/install/comfyui.sh"

# ---------- refresh desktop ----------

CURRENT_STAGE="Hyprland reload"
section "Desktop Refresh"

if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    info "Reloading Hyprland configuration..."

    if hyprctl reload >/dev/null 2>&1; then
        success "Hyprland configuration reloaded"
    else
        warn "Hyprland reload failed; changes will apply after reboot/login"
    fi
else
    info "No active Hyprland session detected; skipping reload"
fi

# ---------- complete ----------

CURRENT_STAGE="complete"
banner "Bootstrap Complete"
success "Workstation configuration finished"

echo
prompt_yes_no reboot_now "Reboot now?" no

if choice_enabled "$reboot_now"; then
    info "Rebooting..."
    sudo systemctl reboot
else
    info "Reboot skipped"
fi
