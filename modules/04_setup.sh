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

# Nvidia Driver Support (Omarchy-Spec Advanced Probing)
if lspci | grep -qi "nvidia"; then
  gum style --foreground 13 " [!] Nvidia GPU detected."
  # Detect Turing+ architecture (16xx, 20xx, 30xx, 40xx)
  # Turing/Ampere/Ada started with device IDs like 1e, 1f, 21, 22, 24, 25, 26, 27, 28
  GPU_ID=$(lspci -n | grep "0300: 10de" | cut -d':' -f4 | cut -d' ' -f2)
  if [[ "$GPU_ID" =~ ^(1e|1f|21|22|24|25|26|27|28) ]]; then
    G_MSG="[Modern GPU Detected] Recommending Nvidia-Open-DKMS"
    DEF_CHOICE="Nvidia-Open (Turing+)"
  else
    G_MSG="[Legacy/Pascal Detected] Recommending Nvidia-Proprietary"
    DEF_CHOICE="Nvidia Proprietary"
  fi
  
  gum style --foreground 15 "$G_MSG"
  NV_CHOICE=$(gum choose "$DEF_CHOICE" "Nvidia Proprietary" "Nvidia-Open (Turing+)" "Nouveau (Open Source)" "Skip")
  
  case "$NV_CHOICE" in
    "Nvidia-Open"*)
      APPS="$APPS nvidia-open-dkms nvidia-utils libva-nvidia-driver"
      IS_NVIDIA=true
      ;;
    "Nvidia Proprietary"*)
      APPS="$APPS nvidia-dkms nvidia-utils libva-nvidia-driver"
      IS_NVIDIA=true
      ;;
    "Nouveau"*)
      APPS="$APPS xf86-video-nouveau"
      IS_NVIDIA=false
      ;;
  esac
fi

# Laptop Detection: Add TLP if battery exists
if [ -d /sys/class/power_supply ] && ls /sys/class/power_supply/BAT* &>/dev/null; then
  APPS="$APPS tlp"
  HAS_BATTERY=true
else
  HAS_BATTERY=false
fi

gum spin --title "Ingesting production-grade packages... [Developer-Focused Omakase]" -- \
  pacstrap -K /mnt "$APPS" --noconfirm

gum style --foreground 10 " [OK] Software payload deployed."

# 2a. LAPTOP OPTIMIZATIONS
if [ "$HAS_BATTERY" == "true" ]; then
  gum spin --title "Optimizing for mobile hardware (TLP)..." -- \
    arch-chroot /mnt systemctl enable tlp >> /mnt/root/chrome-unnamed/install.log 2>&1
  gum style --foreground 10 " [OK] Laptop power management profile active."
fi

# 2b. SERVICE INITIALIZATION
gum spin --title "Initializing background services..." -- bash -c "
  arch-chroot /mnt systemctl enable systemd-timesyncd &>/dev/null
  arch-chroot /mnt systemctl enable reflector.timer &>/dev/null
"

# 3. USER ACCOUNT SETUP
gum spin --title "Configuring user accounts..." -- bash -c '
  # Pass passwords via stdin to chpasswd to avoid exposure in process lists
  printf "root:%s\n" "$1" | arch-chroot /mnt chpasswd
  
  # FIX: Check if user exists before creation to prevent crash on retry
  if ! arch-chroot /mnt id "$2" &>/dev/null; then
    arch-chroot /mnt useradd -m -s /usr/bin/zsh "$2"
  fi
  
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
  
  # Nvidia Hyprland environment variables
  if [ \"$IS_NVIDIA\" == \"true\" ]; then
    {
      echo 'export LIBVA_DRIVER_NAME=nvidia'
      echo 'export XDG_SESSION_TYPE=wayland'
      echo 'export GBM_BACKEND=nvidia-drm'
      echo 'export __GLX_VENDOR_LIBRARY_NAME=nvidia'
      echo 'export WLR_NO_HARDWARE_CURSORS=1'
    } >> /mnt/home/${USERNAME}/.zshrc
  fi
  
  arch-chroot /mnt chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.zshrc
"

gum style --foreground 10 " [OK] User account $USERNAME fully initialized."
