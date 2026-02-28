#!/bin/bash
# Chrome-Unnamed First-Flight Onboarding
# This script runs on the first user login to finalize the environment.

set -e

# Load helpers if available
[ -f modules/00_helpers.sh ] && source modules/00_helpers.sh

clear
gum style --foreground 15 --border double --padding "1 2" --align center --width 60 \
    "Welcome to CHROME-UNNAMED" "Your Pro-Grade Arch Linux Environment is ready."

# 1. GIT IDENTITY
if gum confirm "Would you like to configure your Git identity now?"; then
    G_NAME=$(gum input --placeholder "Full Name (e.g., John Doe)")
    G_EMAIL=$(gum input --placeholder "Email (e.g., john@example.com)")
    git config --global user.name "$G_NAME"
    git config --global user.email "$G_EMAIL"
    gum style --foreground 10 " [OK] Git identity mapped."
fi

# 2. SSH KEYS
if gum confirm "Would you like to generate a new Ed25519 SSH key?"; then
    ssh-keygen -t ed25519 -C "chrome-unnamed-$(date +%F)" -f ~/.ssh/id_ed25519 -N ""
    gum style --foreground 10 " [OK] SSH key generated. Public key is in ~/.ssh/id_ed25519.pub"
fi

# 3. AESTHETIC FLAVOR
gum style --foreground 15 "Choose your Hyprland aesthetic 'Flavor':"
FLAVOR=$(gum choose "Glassmorphism (Translucent/Blur)" "Midnight (Deep Dark/Static)" "Vibrant (Pop/High-Contrast)")
echo "export CHROME_FLAVOR='$FLAVOR'" >> ~/.zshrc

# 4. FINALIZATION
touch ~/.chrome_unnamed_onboarded
gum style --foreground 10 --bold "First-Flight Completed. Enjoy your new system!"
sleep 2
