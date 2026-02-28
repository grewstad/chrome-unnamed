# ==============================================================================
# Chrome-Unnamed: Core System Injection
# ==============================================================================
# Injects the base Arch Linux system, configures essential hardware chronometrics,
# and firmly establishes the Limine EFI bootloader sequence.
# ==============================================================================

set -e
source "modules/00_helpers.sh"

# 1. BASE SYSTEM DEPLOYMENT (PACSTRAP)
# Omarchy Pattern: Injecting 'kernel-modules-hook' to prevent breakage after kernel updates
gum spin --title "Injecting Arch Linux Zen Core... [Optimizing for low-latency workloads]" -- \
  pacstrap -K /mnt base linux-zen linux-firmware intel-ucode amd-ucode \
    btrfs-progs limine networkmanager nvim sudo efibootmgr zram-generator \
    bash-completion zsh-completions kernel-modules-hook --noconfirm

gum style --foreground 10 " [OK] Base system components successfully injected."

# 2. FILESYSTEM MAPPING (FSTAB)
# FIX: Use authoritative redirection (>) instead of append (>>) to prevent duplicates on retry
gum spin --title "Mapping filesystem structure (fstab)..." -- bash -c "genfstab -U /mnt > /mnt/etc/fstab"

# 3. LOCALE & HOSTNAME
HOSTNAME=$(gum input --placeholder "Enter system hostname (e.g. archterra)")
if [ -z "$HOSTNAME" ]; then HOSTNAME="archterra"; fi

gum spin --title "Configuring locale and timezone..." -- bash -c '
  echo "$1" > /mnt/etc/hostname
  {
    echo "127.0.0.1 localhost"
    echo "::1       localhost"
    echo "127.0.1.1 $1.localdomain $1"
  } > /mnt/etc/hosts

  # Persistence: Locales, Keyboard, Time
  echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
  echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
  echo "KEYMAP=$2" > /mnt/etc/vconsole.conf

  # 3. MAINTENANCE & IDENTITY
  # Enable Pacman Color and Parallel Downloads for a premium QOL experience
  sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /mnt/etc/pacman.conf
  sed -i 's/^#Color/Color/' /mnt/etc/pacman.conf

  ln -sf /usr/share/zoneinfo/UTC /mnt/etc/localtime
  arch-chroot /mnt hwclock --systohc
  arch-chroot /mnt locale-gen &>/dev/null

  # Add Btrfs hook to mkinitcpio for faster/reliable boot
  sed -i "s/^HOOKS=(base udev/HOOKS=(base udev btrfs/" /mnt/etc/mkinitcpio.conf

  # Mkinitcpio: Ensure Btrfs hooks are active for the zen kernel
  # FIX: Redirect to install.log for transparency instead of /dev/null
  arch-chroot /mnt mkinitcpio -P >> /mnt/root/chrome-unnamed/install.log 2>&1
  arch-chroot /mnt systemctl enable NetworkManager >> /mnt/root/chrome-unnamed/install.log 2>&1

  # ZRAM Strategy (50% of RAM, zstd compression)
  # FIX: Idempotent configuration check
  if [ ! -f /mnt/etc/systemd/zram-generator.conf ]; then
    cat <<EOF > /mnt/etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
  fi

  # Modern Btrfs Swap (Linux 6.1+ Pattern)
  # Instead of old dd/truncate, we use the specific Btrfs mkswapfile command
  if [ ! -f /mnt/swap/swapfile ]; then
    mkdir -p /mnt/swap
    arch-chroot /mnt btrfs filesystem mkswapfile --size 4G /swap/swapfile >> /mnt/root/chrome-unnamed/install.log 2>&1
    arch-chroot /mnt swapon /swap/swapfile
    echo "/swap/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
  fi

  # Enable the Kernel Module Hook for reliability
  arch-chroot /mnt systemctl enable linux-modules-cleanup.service >> /mnt/root/chrome-unnamed/install.log 2>&1
' _ "$HOSTNAME" "$KEYMAP"

gum style --foreground 10 " [OK] Chronometrics and localization identity established."

# 4. BOOTLOADER SETUP (LIMINE)
# Determine which disk the EFI partition is on (needed for efibootmgr)
EFI_SOURCE=$(findmnt -no SOURCE /mnt/efi | head -n1)
EFI_PART_NUM=$(lsblk -n -o PARTN "$EFI_SOURCE" | head -n1)
TARGET_DISK="/dev/$(lsblk -n -o PKNAME "$EFI_SOURCE" | head -n1)"

gum spin --title "Installing Limine bootloader..." -- bash -c "
  mkdir -p /mnt/efi/EFI/BOOT
  mkdir -p /mnt/efi/EFI/Limine

  # Copy the EFI binary to both fallback and named locations
  cp /usr/share/limine/BOOTX64.EFI /mnt/efi/EFI/BOOT/BOOTX64.EFI
  cp /usr/share/limine/BOOTX64.EFI /mnt/efi/EFI/Limine/BOOTX64.EFI
"

# 4b. LIMINE CONFIGURATION
# Limine on Btrfs requires paths relative to the partition root.
# Since we use the @ subvolume, we MUST prepend /@ to all kernel/initramfs paths.
KERNEL_PART=$(findmnt -vno SOURCE /mnt/boot 2>/dev/null || findmnt -vno SOURCE /mnt)
KERNEL_UUID=$(lsblk -no UUID "$KERNEL_PART")
ROOT_PART=$(findmnt -vno SOURCE /mnt)
ROOT_UUID=$(lsblk -no UUID "$ROOT_PART")

# Detect CPU for microcode
UCODE=""
if grep -qi "Intel" /proc/cpuinfo; then
    UCODE="MODULE_PATH=uuid(${KERNEL_UUID}):/@/boot/intel-ucode.img"
    if findmnt /mnt/boot &>/dev/null; then UCODE="MODULE_PATH=uuid(${KERNEL_UUID}):/@/intel-ucode.img"; fi
elif grep -qi "AMD" /proc/cpuinfo; then
    UCODE="MODULE_PATH=uuid(${KERNEL_UUID}):/@/boot/amd-ucode.img"
    if findmnt /mnt/boot &>/dev/null; then UCODE="MODULE_PATH=uuid(${KERNEL_UUID}):/@/amd-ucode.img"; fi
fi

# Hardcoded Btrfs Layout Detection (Paths start with /@ for subvolume support)
# BUG FIX: Only prepend /@ if /boot is NOT a separate partition
K_PATH="/@/boot/vmlinuz-linux-zen"
I_PATH="/@/boot/initramfs-linux-zen.img"
if findmnt /mnt/boot &>/dev/null; then
  K_PATH="/vmlinuz-linux-zen"
  I_PATH="/initramfs-linux-zen.img"
fi

arch-chroot /mnt bash -c 'cat <<EOF > /etc/limine.conf
TIMEOUT=5

:Chrome-Unnamed (Zen Kernel)
    PROTOCOL=linux
    KERNEL_PATH=uuid(${1}):${2}
    ${3}
    MODULE_PATH=uuid(${1}):${4}
    # Fix: Explicitly mount the root subvolume for the kernel
    CMDLINE=root=UUID=${5} rw loglevel=3 quiet rootflags=subvol=@
EOF
' _ "$KERNEL_UUID" "$K_PATH" "$UCODE" "$I_PATH" "$ROOT_UUID"

# 4c. REGISTER UEFI BOOT ENTRY
# Without this step, the bootloader file exists but NVRAM firmware doesn't know about it.
gum spin --title "Registering UEFI boot entry in NVRAM..." -- \
  efibootmgr --create \
    --disk "$TARGET_DISK" \
    --part "$EFI_PART_NUM" \
    --loader '/EFI/Limine/BOOTX64.EFI' \
    --label 'Chrome-Unnamed (Limine)' \
    --unicode > /dev/null

gum style --foreground 10 " [OK] Limine bootloader installed. System is now autonomous."
