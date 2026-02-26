# chrome-unnamed: Disk Module

# 1. DISK SELECTION
# List disks excluding loop and rom devices.
DISK_LIST=$(lsblk -dno NAME,SIZE,MODEL | grep -v "loop" | grep -v "sr")

if [ -z "$DISK_LIST" ]; then
  gum style --foreground 196 "No suitable disks found."
  return 1
fi

SELECTED_DISK_LINE=$(echo "$DISK_LIST" | gum choose --header "Select Target Disk (WARNING: ALL DATA WILL BE LOST)")
SELECTED_DISK="/dev/$(echo "$SELECTED_DISK_LINE" | awk '{print $1}')"

if [ -z "$SELECTED_DISK" ]; then
  gum style --foreground 196 "No disk selected."
  return 1
fi

gum confirm "Are you sure you want to wipe $SELECTED_DISK? This cannot be undone." || return 1

# 2. PARTITIONING
# 100MB EFI, 25GB Btrfs
gum spin --title "Partitioning $SELECTED_DISK..." -- bash -c "
  sgdisk -Z $SELECTED_DISK
  sgdisk -n 1:0:+100M -t 1:ef00 -c 1:'EFI' $SELECTED_DISK
  sgdisk -n 2:0:+25G -t 2:8300 -c 2:'ARCH' $SELECTED_DISK
"

# Determine partition paths (handling nvme/mmcblk naming)
if [[ $SELECTED_DISK == *"/dev/nvme"* ]] || [[ $SELECTED_DISK == *"/dev/mmcblk"* ]]; then
  PART_EFI="${SELECTED_DISK}p1"
  PART_ROOT="${SELECTED_DISK}p2"
else
  PART_EFI="${SELECTED_DISK}1"
  PART_ROOT="${SELECTED_DISK}2"
fi

# 3. FILESYSTEM SETUP
gum spin --title "Formatting partitions..." -- bash -c "
  mkfs.fat -F32 $PART_EFI &>/dev/null
  mkfs.btrfs -f -L 'ARCH_TERRA' $PART_ROOT &>/dev/null
"

# 4. SUBVOLUMES
gum spin --title "Creating Btrfs subvolumes..." -- bash -c "
  mount $PART_ROOT /mnt
  btrfs subvolume create /mnt/@ &>/dev/null
  btrfs subvolume create /mnt/@home &>/dev/null
  umount /mnt
"

# 5. MOUNTING
gum spin --title "Mounting filesystems..." -- bash -c "
  mount -o compress=zstd:3,subvol=@ $PART_ROOT /mnt
  mkdir -p /mnt/home
  mount -o compress=zstd:3,subvol=@home $PART_ROOT /mnt/home
  mkdir -p /mnt/efi
  mount $PART_EFI /mnt/efi
"

gum style --foreground 82 "Disk setup complete. Subvolumes @ and @home mounted with zstd compression."
