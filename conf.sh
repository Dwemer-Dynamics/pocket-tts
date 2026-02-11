#!/bin/bash
clear
cat << EOF
PocketTTS

This will configure the PocketTTS (Text-to-Speech) service.

PocketTTS is a CPU-based TTS engine that generates custom voices from samples.
Perfect for AMD systems or CPU-only setups. No GPU required.

Options:
* CPU = Runs on CPU only. Best choice for AMD cards or systems without NVIDIA GPU.

PocketTTS is designed for CPU usage and does not require a GPU.

EOF

if [ ! -d /home/dwemer/pocket-tts ]; then
        echo "Error: PocketTTS not installed"
        exit 1
fi

echo "Select an option from the list:"
echo
echo "1. Enable service (CPU)"
echo "0. Disable service"
echo

# Prompt the user to make a selection
read -p "Select an option by picking the matching number: " selection

# Validate the input

if [ "$selection" -eq "0" ]; then
    echo "Disabling service. Run this again to enable it"
    rm /home/dwemer/pocket-tts/start.sh &>/dev/null
    exit 0
fi

if [ "$selection" -eq "1" ]; then
    ln -sf /home/dwemer/pocket-tts/start-cpu.sh /home/dwemer/pocket-tts/start.sh
    echo "✓ PocketTTS enabled with CPU mode"
    exit 0
fi

echo "Invalid selection."
exit 1

