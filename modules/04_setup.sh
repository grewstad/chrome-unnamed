# chrome-unnamed: Setup Module

# 1. INTERACTIVE PROMPTS — collect everything before making changes
ROOT_PASS=$(gum input --password --placeholder "Set Root Password")
if [ -z "$ROOT_PASS" ]; then
  gum style --foreground 196 "Root password cannot be empty. Aborting."
  return 1
fi

USERNAME=$(gum input --placeholder "Enter Username (e.g. grewstad)")
if [ -z "$USERNAME" ]; then USERNAME="user"; fi

USER_PASS=$(gum input --password --placeholder "Set Password for $USERNAME")
if [ -z "$USER_PASS" ]; then
  gum style --foreground 196 "User password cannot be empty. Aborting."
  return 1
fi

SUDO_ACCESS=$(gum confirm "Give $USERNAME sudo (wheel) access?" && echo "yes" || echo "no")

# 2. APPLICATION INSTALLATION
APPS="hyprland hyprpaper rofi ghostty zsh git firefox waybar fastfetch base-devel pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber reflector"

gum spin --title "Installing applications..." -- \
  pacstrap -K /mnt $APPS --noconfirm

# 2b. POST-INSTALL SERVICE ENABLEMENT
gum spin --title "Enabling services..." -- bash -c "
  arch-chroot /mnt systemctl enable systemd-timesyncd &>/dev/null
  arch-chroot /mnt systemctl enable reflector.timer &>/dev/null
"

# 3. USER CREATION & PASSWORDS
# IMPORTANT: Variables must be in double-quoted strings so they expand correctly.
# Using printf instead of echo for password to handle special characters safely.
gum spin --title "Setting up user accounts..." -- bash -c '
  printf "%s\n" "root:$1" | arch-chroot /mnt chpasswd
  arch-chroot /mnt useradd -m -s /usr/bin/zsh "$2"
  printf "%s\n" "$2:$3" | arch-chroot /mnt chpasswd
' _ "$ROOT_PASS" "$USERNAME" "$USER_PASS"

# 4. SUDOERS CONFIGURATION
if [ "$SUDO_ACCESS" == "yes" ]; then
  gum spin --title "Configuring sudoers..." -- bash -c "
    arch-chroot /mnt usermod -aG wheel ${USERNAME}
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers
  "
fi

# 5. DOTFILES & PAYLOAD DEPLOYMENT
if [ -d "payload/.config" ]; then
  gum spin --title "Deploying configuration (payload)..." -- bash -c "
    mkdir -p /mnt/home/${USERNAME}/.config
    cp -r payload/.config/* /mnt/home/${USERNAME}/.config/
    arch-chroot /mnt chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/
  "
else
  gum style --foreground 214 "No payload/ directory found — skipping dotfile deployment."
fi

# 6. SHELL POLISH
gum spin --title "Finalizing shell settings..." -- bash -c "
  touch /mnt/home/${USERNAME}/.zshrc
  arch-chroot /mnt chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.zshrc
"

gum style --foreground 82 "Setup complete. User ${USERNAME} created with Zsh and custom dotfiles."
