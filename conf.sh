#!/bin/bash

REPO_DIR="/home/dwemer/pocket-tts"

clear
cat << EOF
PocketTTS

This will configure the PocketTTS (Text-to-Speech) service.

PocketTTS generates custom voices from samples and supports both CPU and GPU inference.

Options:
* CPU = Runs on CPU only. Best choice for AMD cards or systems without NVIDIA GPU.
* GPU = Runs on NVIDIA GPU (CUDA). Faster on large models (24-layer variants).

EOF

if [ ! -d "$REPO_DIR" ]; then
        echo "Error: PocketTTS not installed"
        exit 1
fi

while true; do
    echo "Select an option from the list:"
    echo
    echo "1. Enable service (CPU)"
    echo "2. Enable service (GPU / CUDA)"
    echo "0. Disable service"
    echo

    read -r -p "Select an option by picking the matching number: " selection

    case "$selection" in
        0)
            echo "Disabling service. Run this again to enable it"
            rm "$REPO_DIR/start.sh" &>/dev/null
            exit 0
            ;;
        1)
            ln -sf "$REPO_DIR/start-cpu.sh" "$REPO_DIR/start.sh"
            echo "[OK] PocketTTS enabled with CPU mode"
            exit 0
            ;;
        2)
            ln -sf "$REPO_DIR/start-gpu.sh" "$REPO_DIR/start.sh"
            echo "[OK] PocketTTS enabled with GPU mode"
            exit 0
            ;;
        *)
            echo "Invalid selection. Enter 0, 1, or 2."
            echo
            ;;
    esac
done
