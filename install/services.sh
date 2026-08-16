#!/usr/bin/env bash

set -euo pipefail

USER_NAME="${USER_NAME:-$(whoami)}"
HOSTNAME="${HOSTNAME:-$(hostname)}"

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

# ---------- TrashBox SSH ----------

if [[ "$HOSTNAME" == "trashbox" ]]; then
    echo
    echo "[INFO] Configuring TrashBox SSH"

    sudo systemctl enable --now sshd.service

    if command -v ufw >/dev/null 2>&1; then
        sudo ufw allow 22/tcp >/dev/null

        if sudo ufw status | grep -q '^Status: active'; then
            sudo ufw reload >/dev/null
            echo "[ OK ] UFW allows SSH on TCP/22"
        else
            echo "[INFO] UFW is inactive; SSH rule saved for when it is enabled"
        fi
    else
        echo "[WARN] UFW not found; skipping firewall rule"
    fi

    if systemctl is-active --quiet sshd.service; then
        echo "[ OK ] SSH is running"
    else
        echo "[FAIL] SSH failed to start"
        exit 1
    fi
fi

echo
echo "[ OK ] Shared services configured"