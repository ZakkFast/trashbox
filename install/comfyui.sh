#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:?DOTFILES_DIR is not set}"
GPU_VENDOR="${GPU_VENDOR:-unknown}"

COMFY_DIR="$HOME/AI/ComfyUI"
VENV_DIR="$COMFY_DIR/.venv"
SYSTEMD_DIR="$HOME/.config/systemd/user"

echo
echo "Configuring ComfyUI..."
echo

# --------------------------------------------------
# Validate supported GPU
# --------------------------------------------------

case "$GPU_VENDOR" in
    amd)
        echo "[INFO] AMD GPU detected"
        ;;
    nvidia)
        echo "[INFO] NVIDIA GPU detected"

        if ! command -v nvidia-smi >/dev/null 2>&1; then
            echo "[FAIL] NVIDIA GPU detected but nvidia-smi is unavailable."
            echo "[FAIL] Install/fix the NVIDIA driver before configuring ComfyUI."
            exit 1
        fi
        ;;
    *)
        echo "[FAIL] Unsupported GPU vendor: $GPU_VENDOR"
        exit 1
        ;;
esac

# --------------------------------------------------
# Clone / update ComfyUI
# --------------------------------------------------

mkdir -p "$HOME/AI"

if [[ -d "$COMFY_DIR/.git" ]]; then
    echo "[INFO] Existing ComfyUI installation found"
    echo "[INFO] Updating repository..."

    git -C "$COMFY_DIR" pull --ff-only
else
    echo "[INFO] Cloning ComfyUI..."

    git clone \
        https://github.com/Comfy-Org/ComfyUI.git \
        "$COMFY_DIR"
fi

# --------------------------------------------------
# Python 3.13 virtual environment
# --------------------------------------------------

if [[ -x "$VENV_DIR/bin/python" ]]; then
    CURRENT_PYTHON="$("$VENV_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

    if [[ "$CURRENT_PYTHON" != "3.13" ]]; then
        BACKUP="$COMFY_DIR/.venv.backup.$(date +%Y%m%d-%H%M%S)"

        echo "[INFO] Existing ComfyUI venv uses Python $CURRENT_PYTHON"
        echo "[INFO] Moving it to $BACKUP"

        mv "$VENV_DIR" "$BACKUP"
    fi
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "[INFO] Creating Python 3.13 environment..."

    uv venv \
        --python 3.13 \
        "$VENV_DIR"
else
    echo "[ OK ] Python 3.13 environment already exists"
fi

PYTHON="$VENV_DIR/bin/python"

# --------------------------------------------------
# PyTorch
# --------------------------------------------------

install_amd_torch() {
    echo "[INFO] Installing RDNA4 ROCm PyTorch..."

    uv pip install \
        --python "$PYTHON" \
        --pre \
        torch \
        torchvision \
        torchaudio \
        --index-url https://rocm.nightlies.amd.com/v2/gfx120X-all/
}

install_nvidia_torch() {
    echo "[INFO] Installing NVIDIA CUDA PyTorch..."

    uv pip install \
        --python "$PYTHON" \
        torch \
        torchvision \
        torchaudio \
        --extra-index-url https://download.pytorch.org/whl/cu130
}

TORCH_OK=false

if "$PYTHON" -c 'import torch' >/dev/null 2>&1; then
    case "$GPU_VENDOR" in
        amd)
            if "$PYTHON" -c 'import torch, sys; sys.exit(0 if torch.version.hip else 1)' >/dev/null 2>&1; then
                TORCH_OK=true
            fi
            ;;

        nvidia)
            if "$PYTHON" -c 'import torch, sys; sys.exit(0 if torch.version.cuda else 1)' >/dev/null 2>&1; then
                TORCH_OK=true
            fi
            ;;
    esac
fi

if [[ "$TORCH_OK" == true ]]; then
    echo "[ OK ] Compatible PyTorch installation already exists"
else
    case "$GPU_VENDOR" in
        amd)
            install_amd_torch
            ;;
        nvidia)
            install_nvidia_torch
            ;;
    esac
fi

# --------------------------------------------------
# ComfyUI dependencies
# --------------------------------------------------

echo "[INFO] Installing ComfyUI dependencies..."

uv pip install \
    --python "$PYTHON" \
    -r "$COMFY_DIR/requirements.txt"

# --------------------------------------------------
# Built-in ComfyUI Manager
# --------------------------------------------------

echo "[INFO] Configuring built-in ComfyUI Manager..."

uv pip install \
    --python "$PYTHON" \
    -r "$COMFY_DIR/manager_requirements.txt"

# Disable legacy standalone Manager if one exists.
# Preserve it instead of deleting it.

LEGACY_MANAGER="$COMFY_DIR/custom_nodes/comfyui-manager"

if [[ -d "$LEGACY_MANAGER" ]]; then
    BACKUP="$COMFY_DIR/custom_nodes/comfyui-manager.disabled.$(date +%Y%m%d-%H%M%S)"

    echo "[INFO] Legacy standalone ComfyUI-Manager detected"
    echo "[INFO] Moving it to:"
    echo "       $BACKUP"

    mv "$LEGACY_MANAGER" "$BACKUP"
fi

# --------------------------------------------------
# Generate GPU-specific backend service
# --------------------------------------------------

mkdir -p "$SYSTEMD_DIR"

COMFY_ARGS="--enable-manager"

if [[ "$GPU_VENDOR" == "amd" ]]; then
    COMFY_ARGS+=" --lowvram"
    COMFY_ARGS+=" --disable-pinned-memory"
    COMFY_ARGS+=" --disable-async-offload"
    COMFY_ARGS+=" --disable-smart-memory"
    COMFY_ARGS+=" --disable-dynamic-vram"
    COMFY_ARGS+=" --reserve-vram 2"
fi

cat > "$SYSTEMD_DIR/comfyui.service" <<EOF
[Unit]
Description=ComfyUI Backend
After=graphical-session.target

[Service]
Type=simple
WorkingDirectory=%h/AI/ComfyUI
ExecStart=%h/AI/ComfyUI/.venv/bin/python %h/AI/ComfyUI/main.py $COMFY_ARGS
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

echo "[ OK ] Generated $GPU_VENDOR ComfyUI backend service"

# --------------------------------------------------
# Chromium app service
# --------------------------------------------------

ln -sfn \
    "$DOTFILES_DIR/systemd/user/comfyui-window.service" \
    "$SYSTEMD_DIR/comfyui-window.service"

echo "[ OK ] Linked ComfyUI window service"

# --------------------------------------------------
# systemd
# --------------------------------------------------

systemctl --user daemon-reload

# Deliberately NOT enabled at login.
systemctl --user disable comfyui.service >/dev/null 2>&1 || true
systemctl --user disable comfyui-window.service >/dev/null 2>&1 || true

echo
echo "[ OK ] ComfyUI configured"
echo "[ OK ] ComfyUI will NOT launch automatically at login"
echo
echo "Use:"
echo "  comfy -start"
echo "  comfy -stop"
echo "  comfy -restart"
echo "  comfy -toggle"
echo