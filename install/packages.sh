#!/usr/bin/env bash

set -euo pipefail

GPU_VENDOR="${GPU_VENDOR:-unknown}"

PACMAN_PACKAGES=(
    # Desktop / shell
    firefox
    chromium
    dolphin
    kitty
    alacritty
    fish
    uwsm
    noctalia
    hyprpicker
    satty
    wl-clipboard
    pavucontrol
    playerctl
    imv
    gnome-text-editor
    gnome-calculator
    xorg-xhost
    ttf-jetbrains-mono-nerd

    # Development
    git
    github-cli
    base-devel
    cmake
    ninja
    clang
    gdb
    lldb
    make
    pkgconf
    openssh
    curl
    wget
    rsync
    jq
    yq
    ripgrep
    fd
    fzf
    bat
    eza
    tree
    7zip
    unzip
    mise
    uv
    jre21-openjdk

    # System tools
    btop
    fastfetch
    paru

    # Containers
    docker
    docker-compose
    docker-buildx

    # Database
    dbeaver

    # Gaming
    steam
    gamemode
    lib32-gamemode
    mangohud
    lib32-mangohud
    gamescope
    goverlay
    lutris
    wine-staging
    winetricks
    umu-launcher
    wine-gecko
    wine-mono

    # Media
    mpv
    vlc
    ffmpeg

    # Networking / sync
    networkmanager
    proton-vpn-gtk-app
    gnome-keyring
    syncthing

    # Other
    qbittorrent
)

AUR_PACKAGES=(
    visual-studio-code-bin
    vesktop-bin
)

# GPU-specific workstation packages
case "$GPU_VENDOR" in
    amd)
        PACMAN_PACKAGES+=(
            vulkan-radeon
            lib32-vulkan-radeon
        )
        ;;
    nvidia)
        # Driver handling comes later.
        # We don't blindly install NVIDIA kernel drivers here.
        ;;
    *)
        echo "[WARN] Unknown GPU vendor; skipping GPU-specific packages."
        ;;
esac

echo
echo "Installing repository packages..."
echo

sudo pacman -Syu --needed "${PACMAN_PACKAGES[@]}"

echo
echo "Installing AUR packages..."
echo

if ! command -v paru >/dev/null 2>&1; then
    echo "[FAIL] paru was not installed successfully."
    exit 1
fi

paru -S --needed "${AUR_PACKAGES[@]}"

echo
echo "[ OK ] Package installation complete."
