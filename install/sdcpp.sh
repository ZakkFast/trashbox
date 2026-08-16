#!/usr/bin/env bash
set -Eeuo pipefail

SDCPP_DIR="${SDCPP_DIR:-$HOME/AI/stable-diffusion.cpp}"
BUILD_DIR="${SDCPP_BUILD_DIR:-$SDCPP_DIR/build-vulkan}"
COMFY_DIR="${COMFY_DIR:-$HOME/AI/ComfyUI}"
MODEL_ROOT="${SDCPP_MODEL_ROOT:-$COMFY_DIR/models}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sdcpp"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sdcpp"
BIN_DIR="$HOME/.local/bin"
OUTPUT_DIR="${SDCPP_OUTPUT_DIR:-$HOME/AI/sdcpp-output}"
CONFIG_FILE="$CONFIG_DIR/config"
WRAPPER="$BIN_DIR/sdcpp"

VRAM_GB="${SDCPP_VRAM_GB:-14}"
SERVER_PORT="${SDCPP_SERVER_PORT:-1234}"

WAN_T5_NAME="umt5-xxl-encoder-Q5_K_M.gguf"
WAN_T5_PATH="$MODEL_ROOT/text_encoders/$WAN_T5_NAME"
WAN_T5_URL="https://huggingface.co/city96/umt5-xxl-encoder-gguf/resolve/main/$WAN_T5_NAME?download=true"
WAN_T5_SHA256="eaea358bb438c5d211721a4feecc162000e3636e9cb96f51e216f1f44ebd12ce"

CURRENT_STAGE="preflight"

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

on_error() {
    local exit_code="$1"
    local line_no="$2"
    local command="$3"
    printf '\n' >&2
    printf '\033[1;31m[FAIL]\033[0m Setup failed during: %s\n' "$CURRENT_STAGE" >&2
    printf '\033[1;31m[FAIL]\033[0m Command: %s\n' "$command" >&2
    printf '\033[1;31m[FAIL]\033[0m Exit code: %s (line %s)\n' "$exit_code" "$line_no" >&2
    exit "$exit_code"
}
trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

printf '\n'
printf '╭──────────────────────────────────────────────────────╮\n'
printf '│ stable-diffusion.cpp — Bebop Vulkan setup           │\n'
printf '╰──────────────────────────────────────────────────────╯\n\n'

CURRENT_STAGE="platform checks"
[[ -f /etc/arch-release ]] || fail "This installer is written for Bebop's Arch/CachyOS installation."
command -v pacman >/dev/null 2>&1 || fail "pacman was not found."
command -v sudo >/dev/null 2>&1 || fail "sudo was not found."
command -v lspci >/dev/null 2>&1 || fail "lspci was not found."

PCI_DEVICES="$(lspci -nnk)"
if [[ "$PCI_DEVICES" != *"[1002:7550]"* ]]; then
    fail "RX 9070 XT (PCI ID 1002:7550) was not found by lspci."
fi
ok "RX 9070 XT detected"

info "Installing Vulkan/build dependencies (safe to rerun)..."
CURRENT_STAGE="package installation"
sudo -v
sudo pacman -S --needed --noconfirm \
    base-devel \
    git \
    cmake \
    ninja \
    vulkan-radeon \
    vulkan-tools \
    vulkan-headers \
    shaderc \
    spirv-headers \
    nodejs \
    pnpm \
    curl \
    ffmpeg

CURRENT_STAGE="Vulkan validation"
command -v vulkaninfo >/dev/null 2>&1 || fail "vulkaninfo is unavailable after package installation."
VULKAN_SUMMARY="$(vulkaninfo --summary 2>&1 || true)"
printf '%s\n' "$VULKAN_SUMMARY" | grep -Eiq 'AMD|Radeon' || {
    printf '%s\n' "$VULKAN_SUMMARY"
    fail "Vulkan is installed, but no AMD/Radeon Vulkan device was detected."
}
ok "AMD Vulkan device detected"

CURRENT_STAGE="source checkout"
mkdir -p "$HOME/AI"
if [[ -d "$SDCPP_DIR/.git" ]]; then
    info "Updating existing stable-diffusion.cpp checkout..."
    git -C "$SDCPP_DIR" fetch origin master
    git -C "$SDCPP_DIR" switch master
    git -C "$SDCPP_DIR" pull --ff-only origin master
    git -C "$SDCPP_DIR" submodule sync --recursive
    git -C "$SDCPP_DIR" submodule update --init --recursive
else
    if [[ -e "$SDCPP_DIR" ]]; then
        fail "$SDCPP_DIR exists but is not a Git checkout. Move it aside and rerun."
    fi
    info "Cloning stable-diffusion.cpp..."
    git clone --recursive https://github.com/leejet/stable-diffusion.cpp.git "$SDCPP_DIR"
fi

CURRENT_STAGE="Vulkan build"
info "Building a native Release binary for this machine..."
cmake -S "$SDCPP_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_NATIVE=ON \
    -DSD_VULKAN=ON \
    -DSD_SERVER_BUILD_FRONTEND=ON \
    -DSD_WEBP=ON \
    -DSD_WEBM=ON

cmake --build "$BUILD_DIR" --parallel "$(nproc)"

SD_CLI="$BUILD_DIR/bin/sd-cli"
SD_SERVER="$BUILD_DIR/bin/sd-server"
[[ -x "$SD_CLI" ]] || fail "Build finished but $SD_CLI is missing."
[[ -x "$SD_SERVER" ]] || fail "Build finished but $SD_SERVER is missing."
ok "Vulkan sd-cli and sd-server built"

CURRENT_STAGE="RX 9070 XT detection"
RADV_ICD=""
for candidate in \
    /usr/share/vulkan/icd.d/radeon_icd.x86_64.json \
    /usr/share/vulkan/icd.d/radeon_icd.i686.json
do
    if [[ -f "$candidate" ]]; then
        RADV_ICD="$candidate"
        break
    fi
done

if [[ -n "$RADV_ICD" ]]; then
    export VK_DRIVER_FILES="$RADV_ICD"
fi

DEVICE_OUTPUT="$("$SD_CLI" --list-devices 2>&1 || true)"
printf '%s\n' "$DEVICE_OUTPUT"

GPU_BACKEND="$(
    printf '%s\n' "$DEVICE_OUTPUT" \
        | grep -Ei 'RX[[:space:]]*9070|9070[[:space:]]*XT|gfx1201|Navi[[:space:]]*48' \
        | grep -Eio 'vulkan[0-9]+' \
        | head -n 1 \
        || true
)"

if [[ -z "$GPU_BACKEND" ]]; then
    mapfile -t VULKAN_BACKENDS < <(
        printf '%s\n' "$DEVICE_OUTPUT" \
            | grep -Eio 'vulkan[0-9]+' \
            | sort -u
    )

    if [[ "${#VULKAN_BACKENDS[@]}" -eq 1 ]]; then
        GPU_BACKEND="${VULKAN_BACKENDS[0]}"
        warn "Could not match the GPU name exactly; using the only Vulkan backend: $GPU_BACKEND"
    else
        fail "Could not uniquely identify the RX 9070 XT Vulkan backend. Device list is printed above."
    fi
fi
ok "Selected RX 9070 XT backend: $GPU_BACKEND"

CURRENT_STAGE="model directories"
mkdir -p \
    "$MODEL_ROOT/checkpoints" \
    "$MODEL_ROOT/diffusion_models" \
    "$MODEL_ROOT/text_encoders" \
    "$MODEL_ROOT/vae" \
    "$MODEL_ROOT/loras" \
    "$CONFIG_DIR" \
    "$STATE_DIR" \
    "$BIN_DIR" \
    "$OUTPUT_DIR"

CURRENT_STAGE="Wan T5 encoder"
if [[ -f "$WAN_T5_PATH" ]]; then
    info "Wan Q5_K_M T5 encoder already exists; verifying checksum..."
    printf '%s  %s\n' "$WAN_T5_SHA256" "$WAN_T5_PATH" | sha256sum -c -
else
    info "Downloading Wan Q5_K_M T5 encoder (~4.15 GB)..."
    PART="${WAN_T5_PATH}.part"
    curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --continue-at - \
        --output "$PART" \
        "$WAN_T5_URL"

    printf '%s  %s\n' "$WAN_T5_SHA256" "$PART" | sha256sum -c -
    mv "$PART" "$WAN_T5_PATH"
    ok "Wan T5 encoder downloaded and verified"
fi

CURRENT_STAGE="configuration"
cat > "$CONFIG_FILE" <<EOF
SDCPP_DIR='$SDCPP_DIR'
BUILD_DIR='$BUILD_DIR'
SD_CLI='$SD_CLI'
SD_SERVER='$SD_SERVER'
MODEL_ROOT='$MODEL_ROOT'
CHECKPOINT_DIR='$MODEL_ROOT/checkpoints'
DIFFUSION_DIR='$MODEL_ROOT/diffusion_models'
LEGACY_UNET_DIR='$MODEL_ROOT/unet'
TEXT_ENCODER_DIR='$MODEL_ROOT/text_encoders'
VAE_DIR='$MODEL_ROOT/vae'
LORA_DIR='$MODEL_ROOT/loras'
OUTPUT_DIR='$OUTPUT_DIR'
STATE_DIR='$STATE_DIR'
GPU_BACKEND='$GPU_BACKEND'
VRAM_GB='$VRAM_GB'
SERVER_PORT='$SERVER_PORT'
RADV_ICD='$RADV_ICD'
WAN_T5_NAME='$WAN_T5_NAME'
EOF
chmod 600 "$CONFIG_FILE"

CURRENT_STAGE="helper command"
cat > "$WRAPPER" <<'WRAPPER'
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sdcpp/config"
[[ -r "$CONFIG_FILE" ]] || {
    echo "sdcpp is not configured. Run ~/dotfiles/install/sdcpp.sh first." >&2
    exit 1
}
# shellcheck disable=SC1090
source "$CONFIG_FILE"

PID_FILE="$STATE_DIR/server.pid"
LOG_FILE="$STATE_DIR/server.log"
URL="http://127.0.0.1:$SERVER_PORT/"

if [[ -n "${RADV_ICD:-}" && -f "$RADV_ICD" ]]; then
    export VK_DRIVER_FILES="$RADV_ICD"
fi

die() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

refresh_gpu_backend() {
    local output match
    output="$("$SD_CLI" --list-devices 2>&1 || true)"
    match="$(
        printf '%s\n' "$output" \
            | grep -Ei 'RX[[:space:]]*9070|9070[[:space:]]*XT|gfx1201|Navi[[:space:]]*48' \
            | grep -Eio 'vulkan[0-9]+' \
            | head -n 1 \
            || true
    )"

    if [[ -n "$match" ]]; then
        GPU_BACKEND="$match"
        return
    fi

    mapfile -t devices < <(
        printf '%s\n' "$output" \
            | grep -Eio 'vulkan[0-9]+' \
            | sort -u
    )
    if [[ "${#devices[@]}" -eq 1 ]]; then
        GPU_BACKEND="${devices[0]}"
        return
    fi

    printf '%s\n' "$output" >&2
    die "Could not uniquely identify the RX 9070 XT Vulkan backend."
}

server_running() {
    [[ -f "$PID_FILE" ]] || return 1
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

stop_server() {
    if ! server_running; then
        rm -f "$PID_FILE"
        echo "stable-diffusion.cpp server is not running."
        return
    fi

    local pid
    pid="$(cat "$PID_FILE")"
    echo "Stopping stable-diffusion.cpp server (PID $pid)..."
    kill "$pid" 2>/dev/null || true

    for _ in {1..30}; do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$PID_FILE"
            echo "Stopped."
            return
        fi
        sleep 0.2
    done

    echo "Server did not exit cleanly; sending SIGKILL."
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
}

port_in_use() {
    command -v ss >/dev/null 2>&1 || return 1
    ss -ltn "sport = :$SERVER_PORT" 2>/dev/null | grep -q LISTEN
}

start_server() {
    local label="$1"
    shift

    refresh_gpu_backend

    if server_running; then
        stop_server
    elif port_in_use; then
        die "Port $SERVER_PORT is already in use. Stop the process using it, or change SERVER_PORT in $CONFIG_FILE."
    fi

    mkdir -p "$STATE_DIR"
    : > "$LOG_FILE"

    echo "Starting $label"
    echo "GPU backend: $GPU_BACKEND"
    echo "VRAM budget: ${VRAM_GB} GiB of 16 GiB"
    echo "Log: $LOG_FILE"

    nohup "$SD_SERVER" \
        --listen-ip 127.0.0.1 \
        --listen-port "$SERVER_PORT" \
        "$@" \
        >"$LOG_FILE" 2>&1 &

    local pid=$!
    printf '%s\n' "$pid" > "$PID_FILE"

    for _ in {1..120}; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo
            tail -n 120 "$LOG_FILE" >&2 || true
            rm -f "$PID_FILE"
            die "$label exited during startup."
        fi

        if curl -fsS "$URL" >/dev/null 2>&1; then
            echo "Ready: $URL"
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$URL" >/dev/null 2>&1 || true
            fi
            return
        fi
        sleep 1
    done

    echo "Server is still starting. Follow it with: sdcpp logs"
}

find_first() {
    local dir="$1"
    shift
    [[ -d "$dir" ]] || return 1

    local pattern file
    for pattern in "$@"; do
        file="$(find "$dir" -maxdepth 1 -type f -iname "$pattern" -print 2>/dev/null | sort | head -n 1 || true)"
        if [[ -n "$file" ]]; then
            printf '%s\n' "$file"
            return 0
        fi
    done
    return 1
}

resolve_image_model() {
    local requested="${1:-}"
    local model=""

    if [[ -n "$requested" && -f "$requested" ]]; then
        printf '%s\n' "$requested"
        return
    fi

    case "${requested,,}" in
        pony)
            model="$(find_first "$CHECKPOINT_DIR" '*pony*.safetensors' '*pony*.gguf' || true)"
            ;;
        illustrious)
            model="$(find_first "$CHECKPOINT_DIR" '*illustrious*.safetensors' '*illustrious*.gguf' || true)"
            ;;
        *)
            die "Usage: sdcpp image <pony|illustrious|/path/to/checkpoint>"
            ;;
    esac

    [[ -n "$model" ]] || die "Could not find a $requested checkpoint in $CHECKPOINT_DIR."
    printf '%s\n' "$model"
}

find_wan_model() {
    local kind="$1"
    local expected fallback

    case "$kind" in
        low)
            expected="SmoothMix_I2V_v2_Low-Q3_K_M.gguf"
            fallback='*SmoothMix*I2V*Low*.gguf'
            ;;
        high)
            expected="SmoothMix_I2V_v2_High-Q3_K_M.gguf"
            fallback='*SmoothMix*I2V*High*.gguf'
            ;;
        *)
            return 1
            ;;
    esac

    if [[ -f "$DIFFUSION_DIR/$expected" ]]; then
        printf '%s\n' "$DIFFUSION_DIR/$expected"
        return
    fi

    if [[ -d "$LEGACY_UNET_DIR" && -f "$LEGACY_UNET_DIR/$expected" ]]; then
        printf '%s\n' "$LEGACY_UNET_DIR/$expected"
        return
    fi

    find_first "$DIFFUSION_DIR" "$fallback" \
        || find_first "$LEGACY_UNET_DIR" "$fallback"
}

wan_paths() {
    WAN_LOW="$(find_wan_model low || true)"
    WAN_HIGH="$(find_wan_model high || true)"
    WAN_VAE="$VAE_DIR/wan_2.1_vae.safetensors"
    WAN_T5="$TEXT_ENCODER_DIR/$WAN_T5_NAME"

    [[ -n "$WAN_LOW" && -f "$WAN_LOW" ]] || die "SmoothMix LOW GGUF was not found in $DIFFUSION_DIR or $LEGACY_UNET_DIR."
    [[ -n "$WAN_HIGH" && -f "$WAN_HIGH" ]] || die "SmoothMix HIGH GGUF was not found in $DIFFUSION_DIR or $LEGACY_UNET_DIR."
    [[ -f "$WAN_VAE" ]] || die "Wan VAE was not found: $WAN_VAE"
    [[ -f "$WAN_T5" ]] || die "Wan T5 was not found: $WAN_T5"
}

start_image() {
    local model
    model="$(resolve_image_model "${1:-}")"
    echo "Model: $model"

    start_server "SDXL image server" \
        -m "$model" \
        --backend "$GPU_BACKEND" \
        --params-backend "$GPU_BACKEND" \
        --max-vram "$GPU_BACKEND=$VRAM_GB" \
        --vae-tiling \
        --lora-model-dir "$LORA_DIR" \
        -v
}

start_wan() {
    wan_paths

    echo "LOW:  $WAN_LOW"
    echo "HIGH: $WAN_HIGH"
    echo "VAE:  $WAN_VAE"
    echo "T5:   $WAN_T5"

    start_server "Wan 2.2 SmoothMix server" \
        -M vid_gen \
        --diffusion-model "$WAN_LOW" \
        --high-noise-diffusion-model "$WAN_HIGH" \
        --vae "$WAN_VAE" \
        --t5xxl "$WAN_T5" \
        --backend "diffusion=$GPU_BACKEND,te=cpu,vae=cpu" \
        --params-backend "diffusion=disk,te=cpu,vae=cpu" \
        --max-vram "$GPU_BACKEND=$VRAM_GB" \
        --cfg-scale 1.0 \
        --sampling-method euler \
        --steps 3 \
        --high-noise-cfg-scale 1.0 \
        --high-noise-sampling-method euler \
        --high-noise-steps 3 \
        --flow-shift 5.0 \
        --lora-model-dir "$LORA_DIR" \
        -v
}

wan_test() {
    local input="${1:-}"
    [[ -f "$input" ]] || die "Usage: sdcpp wan-test /path/to/input.png"

    wan_paths
    refresh_gpu_backend
    mkdir -p "$OUTPUT_DIR"

    local stamp output
    stamp="$(date +%Y%m%d-%H%M%S)"
    output="$OUTPUT_DIR/wan-test-$stamp.webm"

    echo "Running conservative Wan 2.2 I2V smoke test:"
    echo "  832x480, 33 frames, 16 fps"
    echo "  Q3 LOW/HIGH SmoothMix"
    echo "  GPU: $GPU_BACKEND with ${VRAM_GB} GiB budget"
    echo "  T5 + VAE: CPU"
    echo "  diffusion params: disk-backed"
    echo "  output: $output"

    "$SD_CLI" \
        -M vid_gen \
        --diffusion-model "$WAN_LOW" \
        --high-noise-diffusion-model "$WAN_HIGH" \
        --vae "$WAN_VAE" \
        --t5xxl "$WAN_T5" \
        -i "$input" \
        -p "Natural, coherent motion. The subject moves smoothly while preserving identity and appearance. Stable lighting, realistic detail, subtle cinematic camera movement." \
        -n "oversaturated, overexposed, static, frozen motion, blurry details, subtitles, watermark, low quality, jpeg artifacts, deformed hands, deformed face, malformed limbs, fused fingers, duplicate limbs, flicker" \
        -W 832 \
        -H 480 \
        --video-frames 33 \
        --fps 16 \
        --cfg-scale 1.0 \
        --sampling-method euler \
        --steps 3 \
        --high-noise-cfg-scale 1.0 \
        --high-noise-sampling-method euler \
        --high-noise-steps 3 \
        --flow-shift 5.0 \
        --backend "diffusion=$GPU_BACKEND,te=cpu,vae=cpu" \
        --params-backend "diffusion=disk,te=cpu,vae=cpu" \
        --max-vram "$GPU_BACKEND=$VRAM_GB" \
        -v \
        -o "$output"

    echo "Finished: $output"
}

show_devices() {
    "$SD_CLI" --list-devices
}

show_status() {
    if server_running; then
        local pid
        pid="$(cat "$PID_FILE")"
        echo "Server: active (PID $pid)"
        echo "URL:    $URL"
        echo "Log:    $LOG_FILE"
    else
        echo "Server: inactive"
    fi
    echo
    refresh_gpu_backend
    echo "Selected GPU: $GPU_BACKEND"
    echo "VRAM budget: ${VRAM_GB} GiB"
}

show_logs() {
    [[ -f "$LOG_FILE" ]] || die "No server log exists yet."
    tail -n 200 -f "$LOG_FILE"
}

show_help() {
    cat <<EOF
Usage:
  sdcpp devices
  sdcpp image pony
  sdcpp image illustrious
  sdcpp image /absolute/path/to/model.safetensors
  sdcpp wan
  sdcpp wan-test /path/to/input.png
  sdcpp status
  sdcpp logs
  sdcpp stop

Web UI:
  $URL

Model root:
  $MODEL_ROOT

Output:
  $OUTPUT_DIR
EOF
}

case "${1:-help}" in
    devices)
        show_devices
        ;;
    image)
        shift
        start_image "${1:-}"
        ;;
    wan)
        start_wan
        ;;
    wan-test)
        shift
        wan_test "${1:-}"
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    stop)
        stop_server
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
WRAPPER

chmod 755 "$WRAPPER"

CURRENT_STAGE="final validation"
"$WRAPPER" devices >/tmp/sdcpp-devices.txt 2>&1 || {
    cat /tmp/sdcpp-devices.txt
    fail "sdcpp helper could not list devices."
}
rm -f /tmp/sdcpp-devices.txt

printf '\n'
ok "stable-diffusion.cpp Vulkan setup complete"
printf '\n'
printf 'GPU:          %s (RX 9070 XT target)\n' "$GPU_BACKEND"
printf 'VRAM budget:  %s GiB / 16 GiB\n' "$VRAM_GB"
printf 'Backend:      Vulkan / Mesa RADV\n'
printf 'ROCm/PyTorch: untouched and not used by this stack\n'
printf 'Web UI port:  http://127.0.0.1:%s/\n' "$SERVER_PORT"
printf 'Models:       %s\n' "$MODEL_ROOT"
printf 'Output:       %s\n' "$OUTPUT_DIR"
printf '\nTry:\n'
printf '  sdcpp devices\n'
printf '  sdcpp image pony\n'
printf '  sdcpp image illustrious\n'
printf '  sdcpp wan\n'
printf '  sdcpp wan-test /path/to/input.png\n'
printf '  sdcpp logs\n'
printf '  sdcpp stop\n\n'

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    warn "$BIN_DIR is not currently in PATH. Open a new terminal or add it to PATH."
fi