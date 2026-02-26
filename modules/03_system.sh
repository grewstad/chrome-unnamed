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

# 5. LIMINE CONFIGURATION
# We tell Limine to boot linux-zen from the Btrfs root subvolume (@).
# Limine can find the Btrfs partition by searching for the label or UUID.
gum spin --title "Creating Limine configuration..." -- bash -c "
cat <<EOF > /mnt/efi/limine.conf
TIMEOUT=3
SERIAL=no

:Arch Linux (Zen)
    PROTOCOL=linux
    # Use partition label to find the Btrfs partition
    KERNEL_PATH=boot://2/boot/vmlinuz-linux-zen
    MODULE_PATH=boot://2/boot/initramfs-linux-zen.img
    CMDLINE=root=LABEL=ARCH_TERRA rw rootflags=subvol=@
EOF
"
# NOTE: boot://2 refers to the second partition on the boot drive (our Btrfs partition).
# Since we know the layout (1: EFI, 2: BTRFS), this is safe.

gum style --foreground 82 "System installation and Limine configuration complete."

