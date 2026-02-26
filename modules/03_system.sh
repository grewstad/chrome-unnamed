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

# 4. BOOTLOADER SELECTION
BOOTLOADER=$(gum choose "Install Limine (Minimalist)" "Skip Bootloader (I'll use my existing GRUB/systemd-boot)")

if [ "$BOOTLOADER" == "Install Limine (Minimalist)" ]; then
  # 4a. LIMINE INSTALLATION
  # Limine is opinionated: 100MB EFI is empty, kernels are on Btrfs.
  gum spin --title "Installing Limine bootloader..." -- bash -c "
    # Install limine binaries to the EFI partition
    mkdir -p /mnt/efi/EFI/BOOT
    
    # Deploy limine to the drive MBR/GPT
    TARGET_DISK=\$(lsblk -no PKNAME \$(findmnt -no SOURCE /mnt/efi))
    limine bios-install /dev/\$TARGET_DISK
    
    # Copy the EFI executable
    cp /usr/share/limine/BOOTX64.EFI /mnt/efi/EFI/BOOT/BOOTX64.EFI
  "

  # 4b. LIMINE CONFIGURATION
  # Detect where kernels live (/boot partition vs root partition)
  KERNEL_PART=$(findmnt -no SOURCE /mnt/boot || findmnt -no SOURCE /mnt)
  KERNEL_UUID=$(lsblk -no UUID "$KERNEL_PART")
  ROOT_UUID=$(lsblk -no UUID $(findmnt -no SOURCE /mnt))
  
  # Determine path within the partition
  # If it's a separate boot partition, path is /vmlinuz...
  # If it's root, path is /boot/vmlinuz... (unless it's Btrfs subvol @)
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
    # Search for the partition containing kernels
    KERNEL_PATH=boot://uuid($KERNEL_UUID)$K_PATH
    MODULE_PATH=boot://uuid($KERNEL_UUID)$M_PATH
    CMDLINE=root=UUID=$ROOT_UUID rw rootflags=subvol=@
EOF
"
fi

gum style --foreground 82 "System installation finished. Mode: $BOOTLOADER"



