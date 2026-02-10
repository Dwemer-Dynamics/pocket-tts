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
# Launch the service
python3 bridge_api.py &> log.txt &
