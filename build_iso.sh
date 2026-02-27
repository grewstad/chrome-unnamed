#!/bin/bash
# Chrome-Unnamed ISO Build Helper
set -e

# 1. PREREQUISITES
if ! command -v mkarchiso &>/dev/null; then
    echo "Installing archiso..."
    sudo pacman -S archiso --noconfirm
fi

# 2. BUILD
echo "Starting ISO build process..."
rm -rf out/ work/
sudo mkarchiso -v -w work/ -o out/ archiso/

# 3. FLASHING INSTRUCTIONS
ISO=$(ls out/*.iso | head -n 1)
echo "--------------------------------------------------"
echo "BUILD COMPLETE: $ISO"
echo "--------------------------------------------------"
echo "To flash to /dev/sdb, run:"
echo "sudo dd if=$ISO of=/dev/sdb bs=4M status=progress oflag=sync"
echo "--------------------------------------------------"
