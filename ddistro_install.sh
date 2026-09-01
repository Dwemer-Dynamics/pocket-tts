#!/bin/bash

set -e  # Exit immediately if a command fails

export PIP_NO_CACHE_DIR=1
export PIP_DISABLE_PIP_VERSION_CHECK=1

BASE_DIR="/home/dwemer"
REPO_URL="https://github.com/Dwemer-Dynamics/pocket-tts"
REPO_DIR="$BASE_DIR/pocket-tts"
VENV_DIR="$REPO_DIR/venv"
PORT_FILE="$REPO_DIR/.dwemerdistro-port"
FRESH_INSTALL=0

if [ ! -d "$VENV_DIR" ]; then
    FRESH_INSTALL=1
fi

echo "=== CHIM pocket-tts setup ==="

# Ensure base directory exists
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

# Clone or update repository
if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning pocket-tts repository..."
    git clone --depth 1 "$REPO_URL"
else
    echo "Repository already exists, pulling latest changes..."
    cd "$REPO_DIR"
    git pull
fi

cd "$REPO_DIR"

# Existing installs retain 8020. Fresh installs receive the dedicated port.
if [ ! -f "$PORT_FILE" ]; then
    if [ "$FRESH_INSTALL" -eq 1 ]; then
        printf '8024\n' > "$PORT_FILE"
    else
        printf '8020\n' > "$PORT_FILE"
    fi
fi
export POCKETTTS_HOST="${POCKETTTS_HOST:-0.0.0.0}"
POCKETTTS_PORT="${POCKETTTS_PORT:-$(tr -d '[:space:]' < "$PORT_FILE")}"
case "$POCKETTTS_PORT" in
    ''|*[!0-9]*) POCKETTTS_PORT=8020 ;;
esac
export POCKETTTS_PORT

echo ""
echo "PocketTTS Python will use port $POCKETTTS_PORT."
echo "XTTS remains on 8020; dedicated Chatterbox uses 8023."
echo ""

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
else
    echo "Virtual environment already exists."
fi

# Activate virtual environment
source venv/bin/activate

echo
echo "=== Hugging Face Authentication ==="
echo
echo "Custom voice generation uses the gated PocketTTS model."
echo "Before entering your token, please:"
echo "  1. Go to: https://huggingface.co/kyutai/pocket-tts"
echo "  2. Click 'Agree and access repository'"
echo "  3. Get your token from: https://huggingface.co/settings/tokens"
echo
echo "Type 'skip' to continue without custom voice generation."
echo

if [ -f ~/.cache/huggingface/token ] && [ -s ~/.cache/huggingface/token ]; then
    echo "A Hugging Face token is already configured."
    read -r -p "Press ENTER to keep it, or paste a new token: " HF_TOKEN_INPUT

    if [ -n "$HF_TOKEN_INPUT" ]; then
        mkdir -p ~/.cache/huggingface
        printf '%s\n' "$HF_TOKEN_INPUT" > ~/.cache/huggingface/token
        chmod 600 ~/.cache/huggingface/token
        echo
        echo "[OK] Hugging Face token updated."
    else
        echo
        echo "[OK] Keeping the existing Hugging Face token."
    fi
else
    while true; do
        read -r -p "Hugging Face token: " HF_TOKEN_INPUT

        if [ "$HF_TOKEN_INPUT" = "skip" ]; then
            echo
            echo "[WARN] Skipping Hugging Face login."
            echo "  You can set it up later by running this installer again."
            echo "  Without custom voices, you can only use built-in voices:"
            echo "  alba, marius, javert, jean, fantine, cosette, eponine, azelma"
            break
        fi

        if [ -z "$HF_TOKEN_INPUT" ]; then
            echo "No token entered. Paste a token or type 'skip'."
            continue
        fi

        mkdir -p ~/.cache/huggingface
        printf '%s\n' "$HF_TOKEN_INPUT" > ~/.cache/huggingface/token
        chmod 600 ~/.cache/huggingface/token
        echo
        echo "[OK] Hugging Face token saved."
        break
    done
fi

echo
echo "Select how PocketTTS should be enabled."
bash ./conf.sh

if [ ! -f "$REPO_DIR/start.sh" ]; then
    echo
    echo "PocketTTS was left disabled."
    exit 0
fi

# Use DwemerDistro's validated CUDA selection only when GPU mode was requested.
pytorch_gpu_available() {
    local cuda_home

    [ -r /var/lib/dwemerdistro/cuda-selection.env ] || return 1
    grep -qx 'CUDA_PYTORCH_SUPPORTED=1' /var/lib/dwemerdistro/cuda-selection.env || return 1
    cuda_home="$(sed -n 's|^CUDA_HOME=\(/usr/local/cuda-\(12\.8\|13\.0\)\)$|\1|p' /var/lib/dwemerdistro/cuda-selection.env | head -n 1)"
    [ -n "$cuda_home" ] && [ -x "$cuda_home/bin/nvcc" ]
}

remove_gpu_python_packages() {
    local -a packages

    mapfile -t packages < <(
        python -m pip list --format=freeze |
            sed -n 's/^\(cuda-bindings\|cuda-pathfinder\|cuda-toolkit\|nvidia-[^=]*\|triton\)==.*$/\1/p'
    )
    if [ "${#packages[@]}" -gt 0 ]; then
        python -m pip uninstall -y "${packages[@]}"
    fi
}

START_TARGET="$(readlink -f "$REPO_DIR/start.sh")"

echo "Installing dependencies..."
python -m pip install --no-cache-dir --upgrade pip setuptools wheel
if [ "$START_TARGET" = "$REPO_DIR/start-gpu.sh" ]; then
    if ! pytorch_gpu_available; then
        echo "PocketTTS GPU mode requires a supported DwemerDistro CUDA installation."
        echo "Run the CUDA installer, or run this setup again and select CPU mode."
        rm -f "$REPO_DIR/start.sh"
        exit 2
    fi
    if ! python -c 'import torch; raise SystemExit(0 if torch.version.cuda == "12.8" else 1)' 2>/dev/null; then
        python -m pip uninstall -y torch || true
        remove_gpu_python_packages
        python -m pip install --no-cache-dir torch==2.11.0+cu128 --index-url https://download.pytorch.org/whl/cu128
    fi
else
    if python -c 'import torch; raise SystemExit(0 if torch.version.cuda else 1)' 2>/dev/null; then
        python -m pip uninstall -y torch
        remove_gpu_python_packages
    fi
    python -m pip install --no-cache-dir --upgrade torch --index-url https://download.pytorch.org/whl/cpu
fi
python -m pip install --no-cache-dir -e .

echo
echo "This will start CHIM pocket-tts to download the selected model"
echo "Wait for the message:"
echo "  'Uvicorn running on http://$POCKETTTS_HOST:$POCKETTTS_PORT (Press CTRL+C to quit)'"
echo "Then close this window."
echo
echo "Press ENTER to continue"
read

if [ "$START_TARGET" = "$REPO_DIR/start-gpu.sh" ]; then
    echo "[OK] Starting PocketTTS in GPU / CUDA mode"
    python3 bridge_api.py --device cuda
else
    echo "[OK] Starting PocketTTS in CPU mode"
    python3 bridge_api.py
fi
