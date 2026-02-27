#!/bin/bash
# Chrome-Unnamed: Main Installer Entry Point
set -e
trap 'gum style --foreground 196 "CRITICAL ERROR: Installer crashed or a command failed. Aborting." ; exit 1' ERR

# 1. BOOTSTRAP
if ! command -v gum &>/dev/null; then
  echo "Installing gum (TUI helper)..."
  pacman -Sy gum --noconfirm --needed &>/dev/null
fi

# 1b. TOOL CHECK
for tool in reflector lsblk awk grep findmnt; do
    if ! command -v "$tool" &>/dev/null; then
        echo "Error: Required tool '$tool' is missing."
        exit 1
    fi
done

# 2. PREREQUISITES & SAFETY CHECKS
if [ ! -d "/sys/firmware/efi/efivars" ]; then
    gum style --foreground 196 "ERROR: System not booted in UEFI mode. This installer requires UEFI."
    exit 1
fi

# 3. WELCOME & OPTIMIZATION
gum style \
	--foreground 212 --border-foreground 212 --border double \
	--align center --width 50 --margin "1 2" --padding "2 4" \
	"CHROME-UNNAMED" "Arch Linux Installer"

if gum confirm "Optimize mirrorlist before starting (Recommended)?"; then
    gum spin --title "Optimizing mirrors (reflector)..." -- \
        reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
fi

# 4. KEYBOARD LAYOUT
KEYMAPS=$(localectl list-keymaps)
KEYMAP=$(echo -e "us\n$KEYMAPS" | gum filter --placeholder "Select keyboard layout (default: us)")
if [ -z "$KEYMAP" ]; then KEYMAP="us"; fi
export KEYMAP
gum spin --title "Applying keymap $KEYMAP..." -- loadkeys "$KEYMAP"

# 5. EXECUTION
modules=(
  "modules/01_network.sh"
  "modules/02_disk.sh"
  "modules/03_system.sh"
  "modules/04_setup.sh"
)

for module in "${modules[@]}"; do
  if [ -f "$module" ]; then
    # We remove set +e here so failures crash the installer immediately.
    # shellcheck source=/dev/null
    source "$module"
  else
    echo "Error: $module not found."
    exit 1
  fi
done

# 6. FINISH
gum confirm "Installation complete! Reboot now?" && reboot
