#!/usr/bin/env bash

set -euo pipefail

USER_NAME="${USER_NAME:-$(whoami)}"

echo
echo "Configuring system services..."
echo

# ---------- Docker ----------

echo "[INFO] Configuring Docker"

sudo systemctl enable --now docker.service

if id -nG "$USER_NAME" | grep -qw docker; then
    echo "[ OK ] $USER_NAME is already in the docker group"
else
    sudo usermod -aG docker "$USER_NAME"
    echo "[ OK ] Added $USER_NAME to the docker group"
    echo "[INFO] Docker group membership will apply after logout/reboot"
fi

if systemctl is-active --quiet docker.service; then
    echo "[ OK ] Docker is running"
else
    echo "[FAIL] Docker failed to start"
    exit 1
fi

echo
echo "[ OK ] Shared services configured"