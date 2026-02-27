#!/bin/bash
# Chrome-Unnamed: Main Installer Entry Point

# 1. BOOTSTRAP
# Ensure gum is installed for the TUI.
if ! command -v gum &> /dev/null; then
  echo "Installing gum (TUI helper)..."
  pacman -Sy gum --noconfirm &>/dev/null
fi

# 2. WELCOME
gum style \
	--foreground 212 --border-foreground 212 --border double \
	--align center --width 50 --margin "1 2" --padding "2 4" \
	"CHROME-UNNAMED" "Arch Linux Installer"

# 3. KEYBOARD LAYOUT
# Prompt for keyboard layout, default to US.
KEYMAP=$(localectl list-keymaps | gum filter --placeholder "Select keyboard layout (default: us)")
if [ -z "$KEYMAP" ]; then KEYMAP="us"; fi

gum spin --title "Applying keymap $KEYMAP..." -- loadkeys "$KEYMAP"

# 4. EXECUTION
# Run modules in order.
modules=(
  "modules/01_network.sh"
  "modules/02_disk.sh"
  "modules/03_system.sh"
  "modules/04_setup.sh"
)

for module in "${modules[@]}"; do
  if [ -f "$module" ]; then
    source "$module"
    if [ $? -ne 0 ]; then
      gum style --foreground 196 "Module $module failed. Aborting."
      exit 1
    fi
  else
    echo "Error: $module not found."
    exit 1
  fi
done

# 4. FINISH
gum confirm "Installation complete! Would you like to reboot now?" && reboot
