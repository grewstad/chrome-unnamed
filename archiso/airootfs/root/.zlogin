# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

# Chrome-Unnamed Auto-Starter
if [ -d /root/chrome-unnamed ] && [ -f /root/chrome-unnamed/install.sh ]; then
    gum style --foreground 15 --border-foreground 15 --border double \
        --align center --width 50 --margin "1 2" --padding "2 4" \
        "CHROME-UNNAMED" "Live ISO Environment"
    
    if gum confirm "Would you like to start the Arch Linux installer now?"; then
        cd /root/chrome-unnamed || exit 1
        # Ensure it's executable just in case
        chmod +x install.sh modules/*.sh
        ./install.sh
    fi
fi

# Fallback to default automated script if it exists and we skip
if [ -f ~/.automated_script.sh ]; then
    ~/.automated_script.sh
fi
