#!/bin/bash

BASE_DIR="/home/dwemer"
REPO_URL="https://github.com/Dwemer-Dynamics/pocket-tts"
REPO_DIR="$BASE_DIR/pocket-tts"
VENV_DIR="$REPO_DIR/venv"

cd "$REPO_DIR"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate
export POCKETTTS_HOST="${POCKETTTS_HOST:-0.0.0.0}"
if [ -z "${POCKETTTS_PORT:-}" ] && [ -f "$REPO_DIR/.dwemerdistro-port" ]; then
    POCKETTTS_PORT="$(tr -d '[:space:]' < "$REPO_DIR/.dwemerdistro-port")"
fi
case "${POCKETTTS_PORT:-}" in
    ''|*[!0-9]*) POCKETTTS_PORT=8020 ;;
esac
export POCKETTTS_PORT
# Launch the service on GPU
python3 bridge_api.py --device cuda &> log.txt &
