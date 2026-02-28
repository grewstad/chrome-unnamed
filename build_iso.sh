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

# Increment to V17 for Hardening refactor
LOCAL_VER="17"
sed -i "s/BUILD_ITERATION=\".*\"/BUILD_ITERATION=\"$LOCAL_VER\"/" install.sh

# Define targets
TARGET_DIR="archiso/airootfs/root/chrome-unnamed"
mkdir -p "$TARGET_DIR/modules"

echo "PRE-FLIGHT: Forcefully syncing latest scripts to ISO (sudo used)..."
# Wipe target first to ensure no stale files persist
sudo rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR/modules"

# Copy fresh
cp -f install.sh "$TARGET_DIR/"
cp -f modules/*.sh "$TARGET_DIR/modules/"

# --- FRESHNESS GUARANTEE ---
ISO_VER=$(grep "BUILD_ITERATION=" "$TARGET_DIR/install.sh" | cut -d'"' -f2)

if [ "$LOCAL_VER" != "$ISO_VER" ]; then
    echo "ERROR: Synchronization failed! Local version ($LOCAL_VER) != ISO version ($ISO_VER)"
    exit 1
fi
echo "SYNC VERIFIED: Building Iteration $ISO_VER"

echo "PRE-FLIGHT: Ensuring clean workspace..."
# Clean up build.log if it exists and is owned by root
[ -f build.log ] && sudo rm -f build.log
sudo rm -rf out/ work/

# Check for disk space (need ~10GB for a safe build)
SPACE=$(df -P . | awk 'NR==2 {print $4}')
if [ "$SPACE" -lt 10485760 ]; then
    echo "WARNING: You have less than 10GB free. archiso usually needs ~10GB."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

echo "BUILDING: Executing mkarchiso (check build.log for logs)..."
# Use 'tee' with sudo to allow writing to build.log even if script is run by user
sudo mkarchiso -v -w work/ -o out/ archiso/ 2>&1 | sudo tee build.log > /dev/null

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
