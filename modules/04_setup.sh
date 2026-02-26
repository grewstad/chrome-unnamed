# chrome-unnamed: Setup Module

# 1. INTERACTIVE PROMPTS
ROOT_PASS=$(gum input --password --placeholder "Set Root Password")

USERNAME=$(gum input --placeholder "Enter Username (e.g. grewstad)")
if [ -z "$USERNAME" ]; then USERNAME="user"; fi

USER_PASS=$(gum input --password --placeholder "Set Password for $USERNAME")

SUDO_ACCESS=$(gum confirm "Give $USERNAME sudo (wheel) access?" && echo "yes" || echo "no")

# 2. APPLICATION INSTALLATION
# Installing opinionated apps and requirements for the configs.
APPS="hyprland hyprpaper rofi ghostty zsh git firefox waybar fastfetch base-devel"

gum spin --title "Installing applications..." -- \
  pacstrap -K /mnt $APPS --noconfirm

# 3. USER CREATION & PASSWORDS
gum spin --title "Setting up user accounts..." -- bash -c "
  # Root password
  echo 'root:$ROOT_PASS' | arch-chroot /mnt chpasswd
  
  # User creation
  arch-chroot /mnt useradd -m -s /usr/bin/zsh $USERNAME
  echo '$USERNAME:$USER_PASS' | arch-chroot /mnt chpasswd
"

# 4. SUDOERS CONFIGURATION
if [ "$SUDO_ACCESS" == "yes" ]; then
  gum spin --title "Configuring sudoers..." -- bash -c "
    arch-chroot /mnt usermod -aG wheel $USERNAME
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers
  "
fi

# 5. DOTFILES & PAYLOAD DEPLOYMENT
gum spin --title "Deploying configuration (payload)..." -- bash -c "
  # Copy local payload to target user home
  mkdir -p /mnt/home/$USERNAME/.config
  cp -r payload/.config/* /mnt/home/$USERNAME/.config/
  
  # Set ownership
  arch-chroot /mnt chown -R $USERNAME:$USERNAME /home/$USERNAME/
"

# 6. SHELL POLISH
# Create a basic .zshrc if it doesn't exist to avoid the first-run wizard
gum spin --title "Finalizing shell settings..." -- bash -c "
  if [ ! -f /mnt/home/$USERNAME/.zshrc ]; then
    touch /mnt/home/$USERNAME/.zshrc
  fi
  arch-chroot /mnt chown $USERNAME:$USERNAME /home/$USERNAME/.zshrc
"

gum style --foreground 82 "Setup complete. User $USERNAME created with Zsh and custom dotfiles."
