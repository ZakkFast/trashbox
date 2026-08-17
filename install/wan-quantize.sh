#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sdcpp/config"

usage() {
    cat <<USAGE
Usage:
  bash install/wan-quantize.sh [q5_0|q5_1|q4_0|q4_1|q8_0]

Default:
  q5_0

Converts the working SmoothMix Wan 2.2 LOW/HIGH safetensors into
stable-diffusion.cpp-native GGUF files so we can stop using the very slow
F16 + disk-backed parameter path.
USAGE
}

TYPE="${1:-q5_0}"
case "$TYPE" in
    q8_0|q5_0|q5_1|q4_0|q4_1) ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        echo "[FAIL] Unsupported quantization type: $TYPE" >&2
        usage >&2
        exit 1
        ;;
esac

[[ -r "$CONFIG_FILE" ]] || {
    echo "[FAIL] $CONFIG_FILE was not found. Run ~/dotfiles/install/sdcpp.sh first." >&2
    exit 1
}
# shellcheck disable=SC1090
source "$CONFIG_FILE"

[[ -x "$SD_CLI" ]] || {
    echo "[FAIL] sd-cli not found: $SD_CLI" >&2
    exit 1
}

PYTHON_BIN="$(command -v python3 || command -v python || true)"
[[ -n "$PYTHON_BIN" ]] || {
    echo "[FAIL] python3/python was not found." >&2
    exit 1
}

FIXER="$SCRIPT_DIR/fix-sdcpp-wan-metadata.py"
[[ -f "$FIXER" ]] || {
    echo "[FAIL] Missing fixer script: $FIXER" >&2
    exit 1
}

LOW_SRC="$MODEL_ROOT/diffusion_models/smoothMixWan2214BI2V_i2vV20Low.safetensors"
HIGH_SRC="$MODEL_ROOT/diffusion_models/smoothMixWan2214BI2V_i2vV20High.safetensors"
LOW_OUT="$MODEL_ROOT/diffusion_models/smoothMixWan2214BI2V_i2vV20Low.$TYPE.gguf"
HIGH_OUT="$MODEL_ROOT/diffusion_models/smoothMixWan2214BI2V_i2vV20High.$TYPE.gguf"

[[ -f "$LOW_SRC" ]] || { echo "[FAIL] Missing LOW safetensors: $LOW_SRC" >&2; exit 1; }
[[ -f "$HIGH_SRC" ]] || { echo "[FAIL] Missing HIGH safetensors: $HIGH_SRC" >&2; exit 1; }

printf 'Quantization target: %s\n' "$TYPE"
printf 'LOW source:         %s\n' "$LOW_SRC"
printf 'HIGH source:        %s\n\n' "$HIGH_SRC"

"$PYTHON_BIN" "$FIXER" "$LOW_SRC" "$HIGH_SRC"

convert_one() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [[ -f "$dst" ]]; then
        printf '[SKIP] %s already exists: %s\n' "$label" "$dst"
        return 0
    fi

    printf '[INFO] Converting %s -> %s\n' "$label" "$dst"
    "$SD_CLI" -M convert -m "$src" -o "$dst" -v --type "$TYPE"
    printf '[ OK ] %s ready: %s\n' "$label" "$dst"
}

convert_one "$LOW_SRC" "$LOW_OUT" "LOW"
convert_one "$HIGH_SRC" "$HIGH_OUT" "HIGH"

printf '\n[ OK ] SmoothMix %s conversion complete.\n' "$TYPE"
printf 'Keep the original safetensors until the GGUF pair has produced a verified good clip.\n'
