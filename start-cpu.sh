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
if [ -f /etc/dwemerdistro_services.conf ]; then
    # shellcheck disable=SC1091
    source /etc/dwemerdistro_services.conf
fi
export POCKETTTS_HOST="${POCKETTTS_HOST:-0.0.0.0}"
export POCKETTTS_PORT="${POCKETTTS_PORT:-8024}"
# Launch the service
python3 bridge_api.py &> log.txt &
