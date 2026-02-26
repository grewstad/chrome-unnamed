# chrome-unnamed: System Module

# 1. PACSTRAP
# Installing base system, linux-zen kernel, and essential tools.
gum spin --title "Installing base system (this may take a few minutes)..." -- \
  pacstrap -K /mnt base linux-zen linux-firmware btrfs-progs limine networkmanager nvim sudo --noconfirm

# 2. FSTAB
# Generate fstab using UUIDs.
gum spin --title "Generating fstab..." -- bash -c "genfstab -U /mnt >> /mnt/etc/fstab"

# 3. SYSTEM CONFIGURATION
HOSTNAME=$(gum input --placeholder "Enter hostname (e.g. archterra)")
if [ -z "$HOSTNAME" ]; then HOSTNAME="archterra"; fi

gum spin --title "Configuring basic system settings..." -- bash -c "
  echo '$HOSTNAME' > /mnt/etc/hostname
  echo 'en_US.UTF-8 UTF-8' > /mnt/etc/locale.gen
  ln -sf /usr/share/zoneinfo/UTC /mnt/etc/localtime
  arch-chroot /mnt locale-gen &>/dev/null
"

# 4. LIMINE BOOTLOADER
# Limine is installed side-by-side. It lives in /efi/EFI/limine and /efi/limine.conf.
# This won't overwrite your GRUB or systemd-boot files.
gum spin --title "Installing Limine (Coexistence Mode)..." -- bash -c "
  # Create localized directories for Limine
  mkdir -p /mnt/efi/EFI/BOOT
  mkdir -p /mnt/efi/limine
  
  # Deploy limine to the drive MBR/GPT (Optional but recommended for BIOS)
  TARGET_DISK=\$(lsblk -no PKNAME \$(findmnt -no SOURCE /mnt/efi))
  limine bios-install /dev/\$TARGET_DISK
  
  # Copy the EFI executable to a specific location
  # Note: Keeping it in /EFI/BOOT/BOOTX64.EFI makes it a 'fallback' loader.
  cp /usr/share/limine/BOOTX64.EFI /mnt/efi/EFI/BOOT/BOOTX64.EFI
"

# 4b. LIMINE CONFIGURATION
# Detect where kernels live (/boot partition vs root partition)
KERNEL_PART=$(findmnt -no SOURCE /mnt/boot || findmnt -no SOURCE /mnt)
KERNEL_UUID=$(lsblk -no UUID "$KERNEL_PART")
ROOT_UUID=$(lsblk -no UUID $(findmnt -no SOURCE /mnt))

# Determine path within the partition
if findmnt /mnt/boot &>/dev/null; then
  K_PATH="/vmlinuz-linux-zen"
  M_PATH="/initramfs-linux-zen.img"
else
  K_PATH="/boot/vmlinuz-linux-zen"
  M_PATH="/boot/initramfs-linux-zen.img"
fi

gum spin --title "Creating Limine configuration..." -- bash -c "
cat <<EOF > /mnt/efi/limine.conf
TIMEOUT=3
SERIAL=no

:Arch Linux (Zen)
    PROTOCOL=linux
    KERNEL_PATH=boot://uuid($KERNEL_UUID)$K_PATH
    MODULE_PATH=boot://uuid($KERNEL_UUID)$M_PATH
    CMDLINE=root=UUID=$ROOT_UUID rw rootflags=subvol=@
EOF
"

gum style --foreground 82 "Limine installed successfully alongside your existing bootloaders."




