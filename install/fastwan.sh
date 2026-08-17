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

FASTWAN_TAE_NAME="taew2_2.safetensors"
FASTWAN_TAE="$VAE_DIR/$FASTWAN_TAE_NAME"
FASTWAN_TAE_URL="https://huggingface.co/lightx2v/Autoencoders/resolve/main/$FASTWAN_TAE_NAME?download=true"
FASTWAN_TAE_SHA256="5243c5c9d77ecf2d74800d672bac3678c0d72462899f1b3b10aa1bbc11eae461"

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
download_verified "Wan 2.2 TAEHV" "$FASTWAN_TAE_URL" "$FASTWAN_TAE" "$FASTWAN_TAE_SHA256"

cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="\${XDG_CONFIG_HOME:-\$HOME/.config}/sdcpp/config"
[[ -r "\$CONFIG_FILE" ]] || { echo "[FAIL] sdcpp config missing" >&2; exit 1; }
# shellcheck disable=SC1090
source "\$CONFIG_FILE"

MODEL='$FASTWAN_MODEL'
TAE='$FASTWAN_TAE'
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
    local mode="\${1:-fast}"
    [[ -f "\$MODEL" ]] || die "FastWan model missing: \$MODEL"
    [[ -f "\$TAE" ]] || die "TAE missing: \$TAE"
    [[ -f "\$T5" ]] || die "T5 missing: \$T5"

    if running; then
        stop_server
    fi

    : > "\$LOG_FILE"

    local -a memory_args
    if [[ "\$mode" == "lowmem" ]]; then
        memory_args=(
            --backend "diffusion=\$GPU_BACKEND,te=cpu,vae=\$GPU_BACKEND"
            --params-backend "diffusion=cpu,te=cpu,vae=\$GPU_BACKEND"
            --max-vram -1
            --stream-layers
        )
        echo "Memory mode: LOWMEM (CPU-streamed diffusion weights)"
    else
        memory_args=(
            --backend "diffusion=\$GPU_BACKEND,te=cpu,vae=\$GPU_BACKEND"
            --params-backend "diffusion=\$GPU_BACKEND,te=cpu,vae=\$GPU_BACKEND"
            --max-vram -1
        )
        echo "Memory mode: FAST (Q8 diffusion weights resident on GPU)"
    fi

    echo "Model: \$MODEL"
    echo "TAE:   \$TAE"
    echo "T5:    \$T5"
    echo "Preset: \${W}x\${H} / \${FRAMES} frames / \${FPS} fps / \${STEPS} steps / CFG \${CFG} / Euler + \${SCHEDULER} / shift \${FLOW_SHIFT}"
    echo "GPU: \$GPU_BACKEND"
    echo "Log: \$LOG_FILE"

    nohup "\$SD_SERVER" \\
        --listen-ip 127.0.0.1 \\
        --listen-port "\$PORT" \\
        --diffusion-model "\$MODEL" \\
        --tae "\$TAE" \\
        --t5xxl "\$T5" \\
        "\${memory_args[@]}" \\
        --diffusion-fa \\
        --vae-conv-direct \\
        -W "\$W" \\
        -H "\$H" \\
        --video-frames "\$FRAMES" \\
        --fps "\$FPS" \\
        --cfg-scale "\$CFG" \\
        --sampling-method euler \\
        --scheduler "\$SCHEDULER" \\
        --steps "\$STEPS" \\
        --flow-shift "\$FLOW_SHIFT" \\
        -v \\
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

case "\${1:-server}" in
    server|fast)
        start_server fast
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
  sdcpp-fastwan           # fast GPU-resident Q8 mode
  sdcpp-fastwan lowmem    # CPU streaming fallback
  sdcpp-fastwan logs
  sdcpp-fastwan status
  sdcpp-fastwan stop

Defaults are intentionally a short 832x480 / 33-frame validation clip.
For the eventual 5-second 720p target, once the short test is clean:

  S D C P P_FASTWAN_W=1280 ...

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
EOF

# Fix the deliberately spaced example in help so shellcheck/heredoc expansion stays simple.
sed -i 's/S D C P P_FASTWAN_W/SDCPP_FASTWAN_W/' "$WRAPPER"
chmod 755 "$WRAPPER"

printf '\n[ OK ] FastWan installed.\n'
printf 'Model: %s\n' "$FASTWAN_MODEL"
printf 'TAE:   %s\n' "$FASTWAN_TAE"
printf '\nRun:\n  sdcpp-fastwan\n\n'
printf 'Watch progress:\n  sdcpp-fastwan logs\n'
