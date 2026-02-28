#!/bin/bash
# Chrome-Unnamed ISO Build Helper
set -e

# 1. PREREQUISITES
TARGET_ARG="$1"

if ! command -v mkarchiso &>/dev/null; then
    echo "Installing archiso..."
    sudo pacman -S archiso --noconfirm
fi

# 2. BUILD
echo "Starting ISO build process..."
echo "PRE-FLIGHT: Syncing latest scripts to ISO root (sudo required)..."
mkdir -p archiso/airootfs/root/chrome-unnamed/modules/
cp -f install.sh archiso/airootfs/root/chrome-unnamed/
cp -f modules/*.sh archiso/airootfs/root/chrome-unnamed/modules/

echo "PRE-FLIGHT: Ensuring clean workspace..."
sudo rm -rf out/ work/

# Check for disk space (need ~10GB for a safe build)
SPACE=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$SPACE" -lt 10 ]; then
    echo "WARNING: You only have ${SPACE}GB free. archiso usually needs ~10GB."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

sudo mkarchiso -v -w work/ -o out/ archiso/

# 3. AUTO-FLASH
ISO=$(ls out/*.iso | head -n 1)
echo "--------------------------------------------------"
echo "BUILD COMPLETE: $ISO"
echo "--------------------------------------------------"

# Determine Target Device
if [ -n "$TARGET_ARG" ]; then
    if [ -b "$TARGET_ARG" ]; then
        echo "Command-line target detected: $TARGET_ARG"
        gum style --foreground 15 --bold "FLASHING: Writing to $TARGET_ARG. All data will be destroyed."
        sudo dd if="$ISO" of="$TARGET_ARG" bs=4M status=progress oflag=sync
        echo "--------------------------------------------------"
        echo "FLASH COMPLETE. You can now boot from $TARGET_ARG"
        echo "--------------------------------------------------"
    else
        echo "Error: Argument '$TARGET_ARG' is not a valid block device."
        exit 1
    fi
else
    echo "To flash later, run: sudo dd if=$ISO of=/dev/sdX bs=4M status=progress oflag=sync"
fi
