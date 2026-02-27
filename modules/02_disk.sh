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
PART_LIST=$(lsblk -plno NAME,SIZE,TYPE,FSTYPE,LABEL | grep "part")

if [ -z "$PART_LIST" ]; then
  gum style --foreground 196 "No partitions found. Please partition your disk first."
  return 1
fi

declare -A MOUNTS
USED_PARTS=()

select_partition() {
  local prompt="$1"
  local filter="$2"

  local choices
  if [ -n "$filter" ]; then
    choices=$(echo "$PART_LIST" | grep "$filter")
  else
    choices="$PART_LIST"
  fi

  # Remove already used partitions
  for p in "${USED_PARTS[@]}"; do
    choices=$(echo "$choices" | grep -v "$p")
  done

  if [ -z "$choices" ]; then
    return 1
  fi

  local selected_raw
  selected_raw=$(echo "$choices" | gum choose --header "$prompt")
  local selected
  selected=$(echo "$selected_raw" | awk '{print $1}')

  if [ -n "$selected" ]; then
    USED_PARTS+=("$selected")
    echo "$selected"
  fi
}

# --- MANDATORY SELECTION ---
PART_ROOT=$(select_partition "Select ROOT (/) partition")
if [ -z "$PART_ROOT" ]; then return 1; fi
MOUNTS["$PART_ROOT"]="/"

PART_EFI=$(select_partition "Select EFI partition (usually vfat, 100MB–512MB)")
if [ -z "$PART_EFI" ]; then
  gum style --foreground 196 "ERROR: No EFI partition selected. Aborting."
  return 1
fi
MOUNTS["$PART_EFI"]="/efi"

# --- OPTIONAL SELECTION ---
HAS_MANUAL_HOME=false
if gum confirm "Use a separate /home partition?"; then
  PART_HOME=$(select_partition "Select /home partition")
  if [ -n "$PART_HOME" ]; then
    MOUNTS["$PART_HOME"]="/home"
    HAS_MANUAL_HOME=true
  fi
fi

HAS_MANUAL_BOOT=false
if gum confirm "Use a separate /boot partition? (Recommended for complex setups)"; then
  PART_BOOT=$(select_partition "Select /boot partition")
  if [ -n "$PART_BOOT" ]; then
    MOUNTS["$PART_BOOT"]="/boot"
    HAS_MANUAL_BOOT=true
  fi
fi

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

# --- SWAP DETECTION ---
# Do this BEFORE formatting/mounting so the user can confirm via TUI.
SWAP_PART=$(lsblk -plno NAME,TYPE,FSTYPE | awk '$2=="part" && $3=="swap" {print $1}' | head -n1)
ENABLE_SWAP=false
if [ -n "$SWAP_PART" ]; then
  if gum confirm "Swap partition detected ($SWAP_PART). Enable it?"; then
    ENABLE_SWAP=true
  fi
fi

# 3. FORMATTING DECISIONS
for part in "${!MOUNTS[@]}"; do
  mnt="${MOUNTS[$part]}"
  if [ "$mnt" == "/efi" ]; then
    if gum confirm "Format $part as FAT32? (CAUTION: this erases existing bootloaders)"; then
      gum spin --title "Formatting $part as FAT32..." -- mkfs.fat -F32 "$part"
    fi
  elif [ "$mnt" == "/" ] || [ "$mnt" == "/boot" ]; then
    gum style --foreground 214 "Enforcing Btrfs for $mnt to ensure a clean wipe..."
    if gum confirm "Wipe and format $part as btrfs for $mnt? (WARNING: total data loss)"; then
      gum spin --title "Formatting $part as btrfs..." -- mkfs.btrfs -f "$part"
    fi
  else
    if gum confirm "Format $part for $mnt? (WARNING: data loss)"; then
      FS=$(gum choose "btrfs" "ext4" "xfs")
      gum spin --title "Formatting $part as $FS..." -- mkfs."$FS" -f "$part"
    fi
  fi
done

udevadm settle

# 4. EXECUTION: MOUNTING
# Mount root first, then create Btrfs subvolumes if needed.
# We pass variables as positional parameters to bash -c to avoid premature expansion.
gum spin --title "Mounting root filesystem..." -- bash -c '
  set -e
  mount "$1" /mnt

  # Check filesystem AFTER mounting to avoid premature expansion issues
  if lsblk -no FSTYPE "$1" | grep -q "btrfs"; then
    btrfs subvolume create /mnt/@ &>/dev/null || true
    btrfs subvolume create /mnt/@home &>/dev/null || true
    umount /mnt
    udevadm settle
    mount -o compress=zstd:3,noatime,autodefrag,subvol=@ "$1" /mnt
    mkdir -p /mnt/home
    # Only mount internal @home if a separate partition was NOT chosen
    if [ "$2" != "true" ]; then
      mount -o compress=zstd:3,noatime,autodefrag,subvol=@home "$1" /mnt/home
    fi
  fi
' _ "$PART_ROOT" "$HAS_MANUAL_HOME"

# Mount other partitions in a safe order
# (EFI and BOOT should be mounted after ROOT)
for part in "${!MOUNTS[@]}"; do
  mnt="${MOUNTS[$part]}"
  if [ "$mnt" == "/" ]; then continue; fi
  if [ "$mnt" == "/home" ] && lsblk -no FSTYPE "$PART_ROOT" | grep -q "btrfs" && [ "$HAS_MANUAL_HOME" != "true" ]; then
     # Skip as it was handled above
     continue
  fi

  gum spin --title "Mounting $part → $mnt..." -- bash -c '
    mkdir -p /mnt"$2"
    mount "$1" /mnt"$2"
  ' _ "$part" "$mnt"
done

# Enable swap now that TUI prompts are done
if [ "$ENABLE_SWAP" == "true" ]; then
  gum spin --title "Enabling swap ($SWAP_PART)..." -- swapon "$SWAP_PART"
fi

gum style --foreground 82 "Mounting complete. All partitions mapped and secured."
