#!/bin/bash
clear
cat << EOF
PocketTTS

This will configure the PocketTTS (Text-to-Speech) service.

PocketTTS generates custom voices from samples and supports both CPU and GPU inference.

Options:
* CPU = Runs on CPU only. Best choice for AMD cards or systems without NVIDIA GPU.
* GPU = Runs on NVIDIA GPU (CUDA). Faster on large models (24-layer variants).

EOF

if [ ! -d /home/dwemer/pocket-tts ]; then
        echo "Error: PocketTTS not installed"
        exit 1
fi

source venv/bin/activate

# Show CUDA availability
if python3 -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
    GPU_INFO=$(python3 -c "import torch; p=torch.cuda.get_device_properties(0); print(f'{p.name} ({p.total_memory//1024**2} MB VRAM)')" 2>/dev/null)
    echo "  GPU detected: $GPU_INFO"
else
    echo "  No CUDA GPU detected (option 2 will not work)"
fi
echo

echo "Select an option from the list:"
echo
echo "1. Enable service (CPU)"
echo "2. Enable service (GPU / CUDA)"
echo "0. Disable service"
echo

read -p "Select an option by picking the matching number: " selection

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

if [ "$selection" -eq "2" ]; then
    ln -sf /home/dwemer/pocket-tts/start-gpu.sh /home/dwemer/pocket-tts/start.sh
    echo "✓ PocketTTS enabled with GPU mode"
    exit 0
fi

echo "Invalid selection."
exit 1

