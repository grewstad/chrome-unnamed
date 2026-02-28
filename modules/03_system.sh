# ==============================================================================
# Chrome-Unnamed: Core System Injection
# ==============================================================================
# Injects the base Arch Linux system, configures essential hardware chronometrics,
# and firmly establishes the Limine EFI bootloader sequence.
# ==============================================================================

set -e
source "modules/00_helpers.sh"

# 1. BASE SYSTEM DEPLOYMENT (PACSTRAP)
gum spin --title "Deploying base operating system components..." -- \
  pacstrap -K /mnt base linux-zen linux-firmware intel-ucode amd-ucode \
    btrfs-progs limine networkmanager nvim sudo efibootmgr --noconfirm

# 2. FILESYSTEM MAPPING (FSTAB)
gum spin --title "Mapping filesystem structure (fstab)..." -- bash -c "genfstab -U /mnt >> /mnt/etc/fstab"

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

  echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
  echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
  echo "KEYMAP=$2" > /mnt/etc/vconsole.conf

  ln -sf /usr/share/zoneinfo/UTC /mnt/etc/localtime
  arch-chroot /mnt hwclock --systohc
  arch-chroot /mnt locale-gen &>/dev/null
  arch-chroot /mnt mkinitcpio -P &>/dev/null
  arch-chroot /mnt systemctl enable NetworkManager &>/dev/null
' _ "$HOSTNAME" "$KEYMAP"

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
# Resolve where the kernel files live
# Chain-booting: Kernels are usually in /boot on the ROOT partition.
KERNEL_PART=$(findmnt -vno SOURCE /mnt/boot 2>/dev/null || findmnt -vno SOURCE /mnt)
if [ -z "$KERNEL_PART" ]; then 
    gum style --foreground 15 "[SYS] FATAL: Kernel vector not located."
    exit 1
fi

KERNEL_UUID=$(lsblk -no UUID "$KERNEL_PART")
ROOT_PART=$(findmnt -vno SOURCE /mnt)
ROOT_UUID=$(lsblk -no UUID "$ROOT_PART")

# Detect CPU for microcode
UCODE=""
# Use -m 1 to avoid multiple lines if CPU has many cores
if grep -qi "Intel" /proc/cpuinfo; then
    UCODE="MODULE_PATH=uuid(${KERNEL_UUID}):/boot/intel-ucode.img"
    if findmnt /mnt/boot &>/dev/null; then UCODE="MODULE_PATH=uuid(${KERNEL_UUID}):/intel-ucode.img"; fi
elif grep -qi "AMD" /proc/cpuinfo; then
    UCODE="MODULE_PATH=uuid(${KERNEL_UUID}):/boot/amd-ucode.img"
    if findmnt /mnt/boot &>/dev/null; then UCODE="MODULE_PATH=uuid(${KERNEL_UUID}):/amd-ucode.img"; fi
fi

if findmnt /mnt/boot &>/dev/null; then
  K_PATH="/vmlinuz-linux-zen"
  I_PATH="/initramfs-linux-zen.img"
else
  K_PATH="/boot/vmlinuz-linux-zen"
  I_PATH="/boot/initramfs-linux-zen.img"
fi

arch-chroot /mnt bash -c 'cat <<EOF > /etc/limine.conf
TIMEOUT=5

:Chrome-Unnamed (Zen Kernel)
    PROTOCOL=linux
    KERNEL_PATH=uuid(${1}):${2}
    ${3}
    MODULE_PATH=uuid(${1}):${4}
    CMDLINE=root=UUID=${5} rw loglevel=3 quiet btrfs_subvolume=@
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

gum style --foreground 15 "[SYS] Limine bootloader installed. System is autonomous."
