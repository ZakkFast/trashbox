#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sdcpp/config"
[[ -r "$CONFIG_FILE" ]] || {
    echo "[FAIL] sdcpp is not configured. Run ~/dotfiles/install/sdcpp.sh first." >&2
    exit 1
}
# shellcheck disable=SC1090
source "$CONFIG_FILE"

FASTWAN_MODEL_NAME="FastWan2.2-TI2V-5B-q8_0.gguf"
FASTWAN_MODEL="$DIFFUSION_DIR/$FASTWAN_MODEL_NAME"
FASTWAN_MODEL_URL="https://huggingface.co/Green-Sky/FastWan2.2-TI2V-5B-FullAttn-GGUF/resolve/main/$FASTWAN_MODEL_NAME?download=true"
FASTWAN_MODEL_SHA256="b62f50ff87c4dfa2910c6883d45015e05b709366581698b302e259e7f25c9208"

PREVIEW_TAE_NAME="taew2_2.safetensors"
PREVIEW_TAE="$VAE_DIR/$PREVIEW_TAE_NAME"
PREVIEW_TAE_URL="https://huggingface.co/lightx2v/Autoencoders/resolve/main/$PREVIEW_TAE_NAME?download=true"
PREVIEW_TAE_SHA256="5243c5c9d77ecf2d74800d672bac3678c0d72462899f1b3b10aa1bbc11eae461"

BALANCED_TAE_NAME="lighttaew2_2.safetensors"
BALANCED_TAE="$VAE_DIR/$BALANCED_TAE_NAME"
BALANCED_TAE_URL="https://huggingface.co/lightx2v/Autoencoders/resolve/main/$BALANCED_TAE_NAME?download=true"
BALANCED_TAE_SHA256="10124099e0c9864db4e6bcd0f09d822282753e553d344fcf2748cf50140ba16a"

QUALITY_VAE_NAME="wan2.2_vae.safetensors"
QUALITY_VAE="$VAE_DIR/$QUALITY_VAE_NAME"
QUALITY_VAE_URL="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/$QUALITY_VAE_NAME?download=true"
QUALITY_VAE_SHA256="e40321bd36b9709991dae2530eb4ac303dd168276980d3e9bc4b6e2b75fed156"

WRAPPER="$HOME/.local/bin/sdcpp-fastwan"
FASTWAN_PORT="${SDCPP_FASTWAN_PORT:-1235}"

mkdir -p "$DIFFUSION_DIR" "$VAE_DIR" "$HOME/.local/bin"

download_verified() {
    local label="$1"
    local url="$2"
    local dst="$3"
    local sha="$4"

    if [[ -f "$dst" ]]; then
        echo "[INFO] $label already exists; verifying checksum..."
        printf '%s  %s\n' "$sha" "$dst" | sha256sum -c -
        return 0
    fi

    local part="${dst}.part"
    echo "[INFO] Downloading $label..."
    curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --continue-at - \
        --output "$part" \
        "$url"

    printf '%s  %s\n' "$sha" "$part" | sha256sum -c -
    mv "$part" "$dst"
    echo "[ OK ] $label downloaded and verified"
}

download_verified "FastWan 2.2 TI2V 5B Q8" "$FASTWAN_MODEL_URL" "$FASTWAN_MODEL" "$FASTWAN_MODEL_SHA256"
download_verified "Wan 2.2 preview TAE" "$PREVIEW_TAE_URL" "$PREVIEW_TAE" "$PREVIEW_TAE_SHA256"
download_verified "Wan 2.2 LightTAE" "$BALANCED_TAE_URL" "$BALANCED_TAE" "$BALANCED_TAE_SHA256"
download_verified "Wan 2.2 full VAE" "$QUALITY_VAE_URL" "$QUALITY_VAE" "$QUALITY_VAE_SHA256"

cat > "$WRAPPER" <<EOF_WRAPPER
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="\${XDG_CONFIG_HOME:-\$HOME/.config}/sdcpp/config"
[[ -r "\$CONFIG_FILE" ]] || { echo "[FAIL] sdcpp config missing" >&2; exit 1; }
# shellcheck disable=SC1090
source "\$CONFIG_FILE"

MODEL='$FASTWAN_MODEL'
PREVIEW_TAE='$PREVIEW_TAE'
BALANCED_TAE='$BALANCED_TAE'
QUALITY_VAE='$QUALITY_VAE'
T5="\$TEXT_ENCODER_DIR/\$WAN_T5_NAME"
PORT="\${SDCPP_FASTWAN_PORT:-$FASTWAN_PORT}"
STATE="\$STATE_DIR/fastwan"
PID_FILE="\$STATE/server.pid"
LOG_FILE="\$STATE/server.log"
URL="http://127.0.0.1:\$PORT/"
W="\${SDCPP_FASTWAN_W:-832}"
H="\${SDCPP_FASTWAN_H:-480}"
FRAMES="\${SDCPP_FASTWAN_FRAMES:-33}"
FPS="\${SDCPP_FASTWAN_FPS:-16}"
STEPS="\${SDCPP_FASTWAN_STEPS:-3}"
CFG="\${SDCPP_FASTWAN_CFG:-1.0}"
FLOW_SHIFT="\${SDCPP_FASTWAN_FLOW_SHIFT:-3.0}"
SCHEDULER="\${SDCPP_FASTWAN_SCHEDULER:-lcm}"

if [[ -n "\${RADV_ICD:-}" && -f "\$RADV_ICD" ]]; then
    export VK_DRIVER_FILES="\$RADV_ICD"
fi

mkdir -p "\$STATE"

die() { printf '[FAIL] %s\\n' "\$*" >&2; exit 1; }

running() {
    [[ -f "\$PID_FILE" ]] || return 1
    local pid
    pid="\$(cat "\$PID_FILE" 2>/dev/null || true)"
    [[ -n "\$pid" ]] && kill -0 "\$pid" 2>/dev/null
}

stop_server() {
    if ! running; then
        rm -f "\$PID_FILE"
        echo "FastWan server is not running."
        return
    fi

    local pid
    pid="\$(cat "\$PID_FILE")"
    echo "Stopping FastWan server (PID \$pid)..."
    kill "\$pid" 2>/dev/null || true
    for _ in {1..30}; do
        if ! kill -0 "\$pid" 2>/dev/null; then
            rm -f "\$PID_FILE"
            echo "Stopped."
            return
        fi
        sleep 0.2
    done

    kill -9 "\$pid" 2>/dev/null || true
    rm -f "\$PID_FILE"
    echo "Stopped with SIGKILL."
}

start_server() {
    local profile="\${1:-balanced}"
    [[ -f "\$MODEL" ]] || die "FastWan model missing: \$MODEL"
    [[ -f "\$T5" ]] || die "T5 missing: \$T5"

    local decoder_label
    local -a decoder_args backend_args

    case "\$profile" in
        preview|fast)
            [[ -f "\$PREVIEW_TAE" ]] || die "Preview TAE missing: \$PREVIEW_TAE"
            decoder_label="Preview TAE (fastest, lowest reconstruction quality)"
            decoder_args=(--tae "\$PREVIEW_TAE")
            backend_args=(
                --backend "diffusion=\$GPU_BACKEND,te=cpu,vae=\$GPU_BACKEND"
                --params-backend "diffusion=\$GPU_BACKEND,te=cpu,vae=\$GPU_BACKEND"
                --max-vram -1
            )
            ;;
        balanced)
            [[ -f "\$BALANCED_TAE" ]] || die "LightTAE missing: \$BALANCED_TAE"
            decoder_label="LightTAE (fast, higher reconstruction quality)"
            decoder_args=(--tae "\$BALANCED_TAE")
            backend_args=(
                --backend "diffusion=\$GPU_BACKEND,te=cpu,vae=\$GPU_BACKEND"
                --params-backend "diffusion=\$GPU_BACKEND,te=cpu,vae=\$GPU_BACKEND"
                --max-vram -1
            )
            ;;
        quality)
            [[ -f "\$QUALITY_VAE" ]] || die "Full Wan 2.2 VAE missing: \$QUALITY_VAE"
            decoder_label="Full Wan 2.2 VAE (highest reconstruction quality, slow CPU decode)"
            decoder_args=(--vae "\$QUALITY_VAE")
            backend_args=(
                --backend "diffusion=\$GPU_BACKEND,te=cpu,vae=cpu"
                --params-backend "diffusion=\$GPU_BACKEND,te=cpu,vae=cpu"
                --max-vram -1
            )
            ;;
        lowmem)
            [[ -f "\$BALANCED_TAE" ]] || die "LightTAE missing: \$BALANCED_TAE"
            decoder_label="LightTAE + CPU-streamed diffusion weights"
            decoder_args=(--tae "\$BALANCED_TAE")
            backend_args=(
                --backend "diffusion=\$GPU_BACKEND,te=cpu,vae=\$GPU_BACKEND"
                --params-backend "diffusion=cpu,te=cpu,vae=\$GPU_BACKEND"
                --max-vram -1
                --stream-layers
            )
            ;;
        *)
            die "Unknown profile: \$profile"
            ;;
    esac

    if running; then
        stop_server
    fi

    : > "\$LOG_FILE"

    echo "Profile: \$profile"
    echo "Model:   \$MODEL"
    echo "Decoder: \$decoder_label"
    echo "T5:      \$T5"
    echo "Preset:  \${W}x\${H} / \${FRAMES} frames / \${FPS} fps / \${STEPS} steps / CFG \${CFG} / Euler + \${SCHEDULER} / shift \${FLOW_SHIFT}"
    echo "GPU:     \$GPU_BACKEND"
    echo "Log:     \$LOG_FILE"

    nohup "\$SD_SERVER" \
        --listen-ip 127.0.0.1 \
        --listen-port "\$PORT" \
        --diffusion-model "\$MODEL" \
        "\${decoder_args[@]}" \
        --t5xxl "\$T5" \
        "\${backend_args[@]}" \
        --diffusion-fa \
        --vae-conv-direct \
        -W "\$W" \
        -H "\$H" \
        --video-frames "\$FRAMES" \
        --fps "\$FPS" \
        --cfg-scale "\$CFG" \
        --sampling-method euler \
        --scheduler "\$SCHEDULER" \
        --steps "\$STEPS" \
        --flow-shift "\$FLOW_SHIFT" \
        -v \
        >"\$LOG_FILE" 2>&1 &

    local pid=\$!
    printf '%s\\n' "\$pid" > "\$PID_FILE"

    for _ in {1..120}; do
        if ! kill -0 "\$pid" 2>/dev/null; then
            echo "--- FastWan startup log ---" >&2
            tail -n 120 "\$LOG_FILE" >&2 || true
            rm -f "\$PID_FILE"
            die "FastWan server exited during startup"
        fi
        if curl -fsS "\$URL" >/dev/null 2>&1; then
            echo "Ready: \$URL"
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "\$URL" >/dev/null 2>&1 || true
            fi
            return
        fi
        sleep 1
    done

    echo "Server is still starting. Follow with: sdcpp-fastwan logs"
}

case "\${1:-balanced}" in
    preview|fast)
        start_server preview
        ;;
    balanced)
        start_server balanced
        ;;
    quality)
        start_server quality
        ;;
    lowmem)
        start_server lowmem
        ;;
    logs)
        [[ -f "\$LOG_FILE" ]] || die "No FastWan log exists yet"
        tail -n 200 -f "\$LOG_FILE"
        ;;
    status)
        if running; then
            echo "FastWan: active (PID \$(cat "\$PID_FILE"))"
            echo "URL:     \$URL"
            echo "Log:     \$LOG_FILE"
        else
            echo "FastWan: inactive"
        fi
        ;;
    stop)
        stop_server
        ;;
    help|-h|--help)
        cat <<HELP
Usage:
  sdcpp-fastwan balanced   # default: LightTAE, fast with better decode quality
  sdcpp-fastwan preview    # original tiny TAE, fastest preview mode
  sdcpp-fastwan quality    # full Wan 2.2 VAE on CPU, slow reference-quality decode
  sdcpp-fastwan lowmem     # LightTAE + CPU-streamed diffusion weights
  sdcpp-fastwan logs
  sdcpp-fastwan status
  sdcpp-fastwan stop

Bare 'sdcpp-fastwan' starts balanced mode.

Default validation preset:
  832x480 / 33 frames / 16 fps / 3 steps / CFG 1 / Euler + LCM / flow shift 3

5-second 720p target (after 480p balanced is validated):
  SDCPP_FASTWAN_W=1280 SDCPP_FASTWAN_H=720 SDCPP_FASTWAN_FRAMES=81 sdcpp-fastwan balanced

Environment overrides:
  SDCPP_FASTWAN_W
  SDCPP_FASTWAN_H
  SDCPP_FASTWAN_FRAMES
  SDCPP_FASTWAN_FPS
  SDCPP_FASTWAN_STEPS
  SDCPP_FASTWAN_CFG
  SDCPP_FASTWAN_FLOW_SHIFT
  SDCPP_FASTWAN_SCHEDULER
HELP
        ;;
    *)
        die "Unknown command: \$1"
        ;;
esac
EOF_WRAPPER

chmod 755 "$WRAPPER"

printf '\n[ OK ] FastWan installed.\n'
printf 'Model:       %s\n' "$FASTWAN_MODEL"
printf 'Preview TAE: %s\n' "$PREVIEW_TAE"
printf 'LightTAE:    %s\n' "$BALANCED_TAE"
printf 'Full VAE:    %s\n' "$QUALITY_VAE"
printf '\nRecommended next test:\n  sdcpp-fastwan balanced\n\n'
printf 'Watch progress:\n  sdcpp-fastwan logs\n'
