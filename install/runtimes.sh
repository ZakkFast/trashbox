#!/usr/bin/env bash

set -euo pipefail

echo
echo "Configuring development runtimes..."
echo

if ! command -v mise >/dev/null 2>&1; then
    echo "[FAIL] mise is not installed."
    exit 1
fi

mkdir -p "$HOME/.config/fish/conf.d"
mkdir -p "$HOME/.local/bin"

# Fish environment
cat > "$HOME/.config/fish/conf.d/workstation.fish" <<'EOF'
# User binaries
if not contains "$HOME/.local/bin" $PATH
    set -gx PATH "$HOME/.local/bin" $PATH
end

# mise runtime manager
mise activate fish | source
EOF

echo "[ OK ] Fish runtime environment configured"

# Allow projects using .nvmrc / .node-version etc. to work naturally
mise settings add idiomatic_version_file_enable_tools node >/dev/null

echo "[INFO] Installing global runtimes..."

mise use --global \
    python@3.14 \
    node@24 \
    go@1.26 \
    java@temurin-21 \
    pnpm@latest

echo
echo "[ OK ] Development runtimes configured"
echo

mise current