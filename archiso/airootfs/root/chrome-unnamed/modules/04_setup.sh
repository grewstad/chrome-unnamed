# ==============================================================================
# Chrome-Unnamed: Operator Provisioning
# ==============================================================================
# Injects the software payload, configures human-interface authorization (users),
# and establishes the user's terminal and desktop environment.
# ==============================================================================

set -e

# 1. AUTHORIZATION PROMPTS
# Collect all credentials before entering the long-running execution phase.
ROOT_PASS=$(gum input --password --placeholder "Establish Overseer (Root) passphrase")
if [ -z "$ROOT_PASS" ]; then
  gum style --foreground 15 "[SEC] FATAL: Overseer passphrase required. Authorization failure."
  return 1
fi

USERNAME=$(gum input --placeholder "Designate Operator handle (Username, e.g. grewstad)")
if [ -z "$USERNAME" ]; then USERNAME="user"; fi

USER_PASS=$(gum input --password --placeholder "Establish passphrase for Operator $USERNAME")
if [ -z "$USER_PASS" ]; then
  gum style --foreground 15 "[SEC] FATAL: Operator passphrase required. Authorization failure."
  return 1
fi

SUDO_ACCESS=$(gum confirm "Grant Operator $USERNAME elevated (wheel) privileges?" && echo "yes" || echo "no")

# 2. APPLICATION PAYLOAD
APPS="hyprland hyprpaper rofi ghostty zsh git firefox waybar fastfetch base-devel pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber reflector"

gum spin --title "Downloading software payload matrix..." -- \
  pacstrap -K /mnt "$APPS" --noconfirm

# 2b. DAEMON ACTIVATION
gum spin --title "Activating background daemons..." -- bash -c "
  arch-chroot /mnt systemctl enable systemd-timesyncd &>/dev/null
  arch-chroot /mnt systemctl enable reflector.timer &>/dev/null
"

# 3. IDENTITY FORGING (CRENDENTIALS)
gum spin --title "Forging Operator credentials in shadow file..." -- bash -c '
  # Pass passwords via stdin to chpasswd to avoid exposure in process lists
  printf "root:%s\n" "$1" | arch-chroot /mnt chpasswd
  arch-chroot /mnt useradd -m -s /usr/bin/zsh "$2"
  printf "%s:%s\n" "$2" "$3" | arch-chroot /mnt chpasswd
' _ "$ROOT_PASS" "$USERNAME" "$USER_PASS"

# 4. PRIVILEGE ESCALATION
if [ "$SUDO_ACCESS" == "yes" ]; then
  gum spin --title "Injecting privilege escalation vectors (sudoers)..." -- bash -c "
    arch-chroot /mnt usermod -aG wheel ${USERNAME}
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers
  "
fi

# 5. GEOMETRIC SYNC (DOTFILES)
REPO_URL="https://github.com/grewstad/chrome-unnamed.git"
gum spin --title "Synchronizing geometric configurations from origin..." -- bash -c '
  rm -rf /tmp/payload_repo
  git clone --depth 1 "$1" /tmp/payload_repo &>/dev/null
  if [ -d "/tmp/payload_repo/payload/.config" ]; then
    mkdir -p /mnt/home/"$2"/.config
    cp -rn /tmp/payload_repo/payload/.config/* /mnt/home/"$2"/.config/
  fi
  arch-chroot /mnt chown -R "$2":"$2" /home/"$2"/
  rm -rf /tmp/payload_repo
' _ "$REPO_URL" "$USERNAME"

# 6. TERMINAL INITIALIZATION
gum spin --title "Initializing terminal interface..." -- bash -c "
  [ ! -f /mnt/home/${USERNAME}/.zshrc ] && touch /mnt/home/${USERNAME}/.zshrc
  arch-chroot /mnt chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.zshrc
"

gum style --foreground 15 "[SYS] Operator ${USERNAME} successfully initialized in the matrix."
