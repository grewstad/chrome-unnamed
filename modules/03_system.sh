# chrome-unnamed: System Module

# 1. PACSTRAP
gum spin --title "Installing base system (this may take a few minutes)..." -- \
  pacstrap -K /mnt base linux-zen linux-firmware intel-ucode amd-ucode \
    btrfs-progs limine networkmanager nvim sudo efibootmgr --noconfirm

# 2. FSTAB
gum spin --title "Generating fstab..." -- bash -c "genfstab -U /mnt >> /mnt/etc/fstab"

# 3. SYSTEM CONFIGURATION
HOSTNAME=$(gum input --placeholder "Enter hostname (e.g. archterra)")
if [ -z "$HOSTNAME" ]; then HOSTNAME="archterra"; fi

gum spin --title "Configuring basic system settings..." -- bash -c '
  echo "$1" > /mnt/etc/hostname
  {
    echo "127.0.0.1 localhost"
    echo "::1       localhost"
    echo "127.0.1.1 $1.localdomain $1"
  } > /mnt/etc/hosts

  echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
  echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
  echo "KEYMAP=$2" > /mnt/etc/vconsole.conf

  ln -sf /usr/share/zoneinfo/UTC /mnt/etc/localtime
  arch-chroot /mnt hwclock --systohc
  arch-chroot /mnt locale-gen &>/dev/null
  arch-chroot /mnt mkinitcpio -P &>/dev/null
  arch-chroot /mnt systemctl enable NetworkManager &>/dev/null
' _ "$HOSTNAME" "$KEYMAP"

# 4. LIMINE BOOTLOADER
# Determine which disk the EFI partition is on (needed for efibootmgr)
EFI_SOURCE=$(findmnt -no SOURCE /mnt/efi)
EFI_PART_NUM=$(lsblk -no PARTN "$EFI_SOURCE")
TARGET_DISK="/dev/$(lsblk -no PKNAME "$EFI_SOURCE")"

gum spin --title "Installing Limine EFI files..." -- bash -c "
  mkdir -p /mnt/efi/EFI/BOOT
  mkdir -p /mnt/efi/EFI/Limine

  # Copy the EFI binary to both fallback and named locations
  cp /usr/share/limine/BOOTX64.EFI /mnt/efi/EFI/BOOT/BOOTX64.EFI
  cp /usr/share/limine/BOOTX64.EFI /mnt/efi/EFI/Limine/BOOTX64.EFI
"

# 4b. LIMINE CONFIGURATION
# Resolve where the kernel files live (separate /boot vs. root /boot dir)
# Using -v ensures Btrfs subvolumes don't append bracketed paths like /dev/sda3[/@]
KERNEL_PART=$(findmnt -vno SOURCE /mnt/boot 2>/dev/null || findmnt -vno SOURCE /mnt)
if [ -z "$KERNEL_PART" ]; then echo "ERROR: Could not find kernel partition (mounting failed?)."; exit 1; fi

KERNEL_UUID=$(lsblk -no UUID "$KERNEL_PART")
ROOT_PART=$(findmnt -vno SOURCE /mnt)
if [ -z "$ROOT_PART" ]; then echo "ERROR: Could not find root partition."; exit 1; fi
ROOT_UUID=$(lsblk -no UUID "$ROOT_PART")

if findmnt /mnt/boot &>/dev/null; then
  K_PATH="/vmlinuz-linux-zen"
  INITRAMFS_PATH="/initramfs-linux-zen.img"
  INTEL_UCODE_PATH="/intel-ucode.img"
  AMD_UCODE_PATH="/amd-ucode.img"
else
  K_PATH="/boot/vmlinuz-linux-zen"
  INITRAMFS_PATH="/boot/initramfs-linux-zen.img"
  INTEL_UCODE_PATH="/boot/intel-ucode.img"
  AMD_UCODE_PATH="/boot/amd-ucode.img"
fi

gum spin --title "Writing Limine configuration..." -- bash -c "true"

# Write the config directly (NOT inside bash -c) so all shell variables expand correctly.
cat > /mnt/efi/limine.conf << EOF
TIMEOUT=3
SERIAL=no

:Chrome-Unnamed (Arch Zen)
    PROTOCOL=linux
    KERNEL_PATH=uuid(${KERNEL_UUID}):${K_PATH}
    MODULE_PATH=uuid(${KERNEL_UUID}):${INTEL_UCODE_PATH}
    MODULE_PATH=uuid(${KERNEL_UUID}):${AMD_UCODE_PATH}
    MODULE_PATH=uuid(${KERNEL_UUID}):${INITRAMFS_PATH}
    CMDLINE=root=UUID=${ROOT_UUID} rw rootflags=subvol=@
EOF

# 4c. REGISTER UEFI BOOT ENTRY
# Without this step, the bootloader file exists but firmware doesn't know about it.
gum spin --title "Registering UEFI boot entry..." -- \
  efibootmgr --create \
    --disk "$TARGET_DISK" \
    --part "$EFI_PART_NUM" \
    --loader '/EFI/Limine/BOOTX64.EFI' \
    --label 'Chrome-Unnamed (Limine)' \
    --unicode

gum style --foreground 82 "Limine installed and registered in UEFI firmware successfully."
