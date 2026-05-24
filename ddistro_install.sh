#!/bin/bash

set -e  # Exit immediately if a command fails

BASE_DIR="/home/dwemer"
REPO_URL="https://github.com/Dwemer-Dynamics/pocket-tts"
REPO_DIR="$BASE_DIR/pocket-tts"
VENV_DIR="$REPO_DIR/venv"

echo "=== CHIM pocket-tts setup ==="
echo ""
echo "NOTE: pocket-tts and CHIM XTTS/Chatterbox use the same port (8020)."
echo "      Only one can be enabled at a time."
echo ""

# Ensure base directory exists
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

# Clone or update repository
if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning pocket-tts repository..."
    git clone "$REPO_URL"
else
    echo "Repository already exists, pulling latest changes..."
    cd "$REPO_DIR"
    git pull
fi

cd "$REPO_DIR"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
else
    echo "Virtual environment already exists."
fi

# Activate virtual environment
source venv/bin/activate

# Upgrade pip and install dependencies
echo "Installing dependencies..."
pip install pocket_tts uvicorn fastapi

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
./conf.sh

if [ ! -f "$REPO_DIR/start.sh" ]; then
    echo
    echo "PocketTTS was left disabled."
    exit 0
fi

echo
echo "This will start CHIM pocket-tts to download the selected model"
echo "Wait for the message:"
echo "  'Uvicorn running on http://0.0.0.0:8020 (Press CTRL+C to quit)'"
echo "Then close this window."
echo
echo "Press ENTER to continue"
read

START_TARGET="$(readlink -f "$REPO_DIR/start.sh")"

if [ "$START_TARGET" = "$REPO_DIR/start-gpu.sh" ]; then
    python3 bridge_api.py --device cuda
else
    python3 bridge_api.py
fi
