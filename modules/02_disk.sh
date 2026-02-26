# chrome-unnamed: Disk Module (Robust Manual selection)

# 1. MODE SELECTION
MODE=$(gum choose "Pre-partitioned (Select existing partitions)" "Manual Partitioning (Run cfdisk)")

if [ "$MODE" == "Manual Partitioning (Run cfdisk)" ]; then
  DISK_LIST=$(lsblk -dno NAME,SIZE,MODEL | grep -v "loop" | grep -v "sr")
  SELECTED_DISK_LINE=$(echo "$DISK_LIST" | gum choose --header "Select Disk for Partitioning")
  SELECTED_DISK="/dev/$(echo "$SELECTED_DISK_LINE" | awk '{print $1}')"
  
  if [ -n "$SELECTED_DISK" ]; then
    cfdisk "$SELECTED_DISK"
  fi
fi

# 2. SELECTION CORE
PART_LIST=$(lsblk -pno NAME,SIZE,TYPE,FSTYPE,LABEL | grep "part" | grep -v "\[SWAP\]")

if [ -z "$PART_LIST" ]; then
  gum style --foreground 196 "No partitions found. Please partition your disk first."
  return 1
fi

declare -A MOUNTS
USED_PARTS=()

select_partition() {
  local prompt="$1"
  local filter="$2" # Optional filter for part type/fs
  
  local choices
  if [ -n "$filter" ]; then
    choices=$(echo "$PART_LIST" | grep "$filter")
  else
    choices="$PART_LIST"
  fi
  
  # Remove already used partitions from choices
  for p in "${USED_PARTS[@]}"; do
    choices=$(echo "$choices" | grep -v "$p")
  done

  if [ -z "$choices" ]; then
    return 1
  fi

  local selected_raw
  selected_raw=$(echo "$choices" | gum choose --header "$prompt")
  local selected=$(echo "$selected_raw" | awk '{print $1}')
  
  if [ -n "$selected" ]; then
    USED_PARTS+=("$selected")
    echo "$selected"
  fi
}

# --- MANDATORY SELECTION ---
# ROOT (/)
PART_ROOT=$(select_partition "Select ROOT (/) partition")
if [ -z "$PART_ROOT" ]; then return 1; fi
MOUNTS["$PART_ROOT"]="/"

# EFI (/efi)
# Precaution: Must be vfat/EFI
PART_EFI=$(select_partition "Select EFI partition (MUST be vfat/EFI system partition)" "vfat")
if [ -z "$PART_EFI" ]; then
  gum style --foreground 196 "ERROR: EFI partition must be vfat. Aborting."
  return 1
fi
MOUNTS["$PART_EFI"]="/efi"

# --- OPTIONAL SELECTION ---
# /boot
if gum confirm "Use a separate /boot partition? (Not needed for 'The Hack')"; then
  PART_BOOT=$(select_partition "Select /boot partition")
  if [ -n "$PART_BOOT" ]; then MOUNTS["$PART_BOOT"]="/boot"; fi
fi

# /home
if gum confirm "Use a separate /home partition?"; then
  PART_HOME=$(select_partition "Select /home partition")
  if [ -n "$PART_HOME" ]; then MOUNTS["$PART_HOME"]="/home"; fi
fi

# Additional Mounts Loop
while gum confirm "Add another custom mount point?"; do
  MNT_POINT=$(gum input --placeholder "Enter mount point (e.g. /data)")
  if [ -n "$MNT_POINT" ]; then
    PART_CUSTOM=$(select_partition "Select partition for $MNT_POINT")
    if [ -n "$PART_CUSTOM" ]; then
      MOUNTS["$PART_CUSTOM"]="$MNT_POINT"
    fi
  else
    break
  fi
done

# 3. FORMATTING DECISIONS
for part in "${!MOUNTS[@]}"; do
  mnt="${MOUNTS[$part]}"
  if [ "$mnt" == "/efi" ]; then
    if gum confirm "Format $part as FAT32? (CAUTION: Wipe your current bootloaders?)"; then
      gum spin --title "Formatting $part..." -- mkfs.fat -F32 "$part"
    fi
  else
    if gum confirm "Format $part for $mnt?"; then
      FS=$(gum choose "btrfs" "ext4" "xfs")
      gum spin --title "Formatting $part as $FS..." -- mkfs."$FS" -f "$part"
    fi
  fi
done

# 4. EXECUTION: MOUNTING
# Root first
gum spin --title "Mounting Root..." -- bash -c "
  mount $PART_ROOT /mnt
  # If Root is Btrfs, create subvolumes @ and @home if they don't exist
  if [ \"\$(lsblk -no FSTYPE $PART_ROOT)\" == \"btrfs\" ]; then
    btrfs subvolume create /mnt/@ &>/dev/null
    btrfs subvolume create /mnt/@home &>/dev/null
    umount /mnt
    mount -o compress=zstd:3,subvol=@ $PART_ROOT /mnt
    # Note: we only mount @home subvolume if user didn't pick a separate /home partition
    if [ -z \"${MOUNTS['/home']}\" ]; then
      mkdir -p /mnt/home
      mount -o compress=zstd:3,subvol=@home $PART_ROOT /mnt/home
    fi
  fi
"

# Other mounts
for part in "${!MOUNTS[@]}"; do
  mnt="${MOUNTS[$part]}"
  if [ "$mnt" == "/" ]; then continue; fi
  
  gum spin --title "Mounting $part to $mnt..." -- bash -c "
    mkdir -p /mnt$mnt
    mount $part /mnt$mnt
  "
done

gum style --foreground 82 "Mounting complete. All partitions mapped and secured."


