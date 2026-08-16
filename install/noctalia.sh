#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:?DOTFILES_DIR is not set}"
HOSTNAME="${HOSTNAME:-$(hostname)}"
USER_NAME="${USER_NAME:-$(whoami)}"

HOST_PROFILE="$DOTFILES_DIR/hypr/hosts/$HOSTNAME.lua"
TEMPLATE="$DOTFILES_DIR/noctalia/config.toml.template"
NOCTALIA_DIR="$HOME/.config/noctalia"
TARGET="$NOCTALIA_DIR/config.toml"

echo
echo "Configuring Noctalia..."
echo

# --------------------------------------------------
# Host profile
# --------------------------------------------------

if [[ ! -f "$HOST_PROFILE" ]]; then
    echo "[FAIL] Missing host profile:"
    echo "       $HOST_PROFILE"
    exit 1
fi

PRIMARY_MONITOR="$(
    sed -n \
        's/^[[:space:]]*primary_monitor[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$HOST_PROFILE" |
        head -n1
)"

if [[ -z "$PRIMARY_MONITOR" ]]; then
    echo "[FAIL] Could not determine primary monitor from:"
    echo "       $HOST_PROFILE"
    exit 1
fi

echo "[INFO] Host:    $HOSTNAME"
echo "[INFO] Monitor: $PRIMARY_MONITOR"

# --------------------------------------------------
# Wallpaper fallback
# --------------------------------------------------

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
DEFAULT_WALLPAPER="$WALLPAPER_DIR/lofi-girl-dreams-3840x2160-14891.jpeg"

if [[ ! -f "$DEFAULT_WALLPAPER" ]]; then
    mkdir -p "$WALLPAPER_DIR"

    echo "[INFO] Preferred wallpaper not found; creating a neutral fallback"

    base64 -d > "$DEFAULT_WALLPAPER" <<'EOF'
/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD82qKKKAP/2Q==
EOF

    echo "[ OK ] Created fallback wallpaper"
fi

# --------------------------------------------------
# Remove old whole-directory symlink
# --------------------------------------------------

if [[ -L "$NOCTALIA_DIR" ]]; then
    echo "[INFO] Removing old Noctalia directory symlink"
    rm "$NOCTALIA_DIR"
fi

mkdir -p "$NOCTALIA_DIR"

# --------------------------------------------------
# Generate machine-local configuration
# --------------------------------------------------

if [[ ! -f "$TEMPLATE" ]]; then
    echo "[FAIL] Noctalia template not found:"
    echo "       $TEMPLATE"
    exit 1
fi

sed \
    -e "s|__HOME__|$HOME|g" \
    -e "s|__PRIMARY_MONITOR__|$PRIMARY_MONITOR|g" \
    "$TEMPLATE" > "$TARGET"

echo "[ OK ] Generated Noctalia configuration"

# --------------------------------------------------
# Greeter appearance sync permission
# --------------------------------------------------

GREETER_HELPER="/usr/bin/noctalia-greeter-apply-appearance"

if [[ -x "$GREETER_HELPER" ]]; then
    USER_UID="$(id -u)"
    SUDOERS_FILE="/etc/sudoers.d/noctalia-greeter-$USER_NAME"

    RULE="$USER_NAME ALL=(root) NOPASSWD: $GREETER_HELPER /run/user/$USER_UID/noctalia-greeter-sync"

    TMPFILE="$(mktemp)"
    printf '%s\n' "$RULE" > "$TMPFILE"

    sudo visudo -cf "$TMPFILE" >/dev/null
    sudo install -m 0440 "$TMPFILE" "$SUDOERS_FILE"

    rm "$TMPFILE"

    echo "[ OK ] Noctalia greeter sync permission configured"
else
    echo "[WARN] Noctalia greeter helper not found; skipping greeter sync permission"
fi

echo
echo "[ OK ] Noctalia configured for $HOSTNAME"
