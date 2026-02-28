# ==============================================================================
# Chrome-Unnamed: Operator Provisioning
# ==============================================================================
# Injects the software payload, configures human-interface authorization (users),
# and establishes the user's terminal and desktop environment.
# ==============================================================================

set -e
source "modules/00_helpers.sh"

# 1. USER PROMPTS
# Collect all credentials before entering the long-running execution phase.
while true; do
  ROOT_PASS=$(gum input --password --placeholder "Set Root password")
  ROOT_PASS_CONFIRM=$(gum input --password --placeholder "Confirm Root password")
  if [ "$ROOT_PASS" == "$ROOT_PASS_CONFIRM" ] && [ -n "$ROOT_PASS" ]; then
    break
  else
    gum style --foreground 15 "Passwords do not match or are empty. Please retry."
  fi
done

USERNAME=$(gum input --placeholder "Enter Username (e.g. grewstad)")
if [ -z "$USERNAME" ]; then USERNAME="user"; fi

while true; do
  USER_PASS=$(gum input --password --placeholder "Set password for user $USERNAME")
  USER_PASS_CONFIRM=$(gum input --password --placeholder "Confirm password for user $USERNAME")
  if [ "$USER_PASS" == "$USER_PASS_CONFIRM" ] && [ -n "$USER_PASS" ]; then
    break
  else
    gum style --foreground 9 " [!] Passwords do not match or are empty. Please retry."
  fi
done

gum style --foreground 10 " [OK] Operator credentials validated."

SUDO_ACCESS=$(gum confirm "Grant $USERNAME administrative (sudo) privileges?" && echo "yes" || echo "no")

# 2. APPLICATION PAYLOAD
APPS="hyprland hyprpaper rofi ghostty zsh git firefox waybar fastfetch base-devel pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber reflector zsh-autosuggestions zsh-syntax-highlighting"

gum spin --title "Ingesting production-grade packages... [Developer-Focused Omakase]" -- \
  pacstrap -K /mnt "$APPS" --noconfirm

gum style --foreground 10 " [OK] Software payload deployed."

# 2b. SERVICE INITIALIZATION
gum spin --title "Initializing background services..." -- bash -c "
  arch-chroot /mnt systemctl enable systemd-timesyncd &>/dev/null
  arch-chroot /mnt systemctl enable reflector.timer &>/dev/null
"

# 3. USER ACCOUNT SETUP
gum spin --title "Configuring user accounts..." -- bash -c '
  # Pass passwords via stdin to chpasswd to avoid exposure in process lists
  printf "root:%s\n" "$1" | arch-chroot /mnt chpasswd
  arch-chroot /mnt useradd -m -s /usr/bin/zsh "$2"
  printf "%s:%s\n" "$2" "$3" | arch-chroot /mnt chpasswd
' _ "$ROOT_PASS" "$USERNAME" "$USER_PASS"

gum style --foreground 10 " [OK] Operator accounts configured and secured."

# 4. PRIVILEGE ESCALATION
if [ "$SUDO_ACCESS" == "yes" ]; then
  gum spin --title "Configuring administrative access (sudo)..." -- bash -c "
    arch-chroot /mnt usermod -aG wheel ${USERNAME}
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers
  "
fi

# 5. DESKTOP CONFIGURATIONS (DOTFILES)
REPO_URL="https://github.com/grewstad/chrome-unnamed.git"
gum spin --title "Downloading desktop configurations..." -- bash -c '
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

gum style --foreground 10 " [OK] User account $USERNAME fully initialized."
