#!/bin/bash
# chrome-unnamed: Disk Module (Opinionated Btrfs + Chain-Booting)

# 1. MODE SELECTION
MODE=$(gum choose "Pre-partitioned (Select existing partitions)" "Manual Partitioning (Run cfdisk)")

if [ "$MODE" == "Manual Partitioning (Run cfdisk)" ]; then
  DISK_LIST=$(lsblk -dno NAME,SIZE,MODEL | grep -v "loop" | grep -v "sr")
  SELECTED_DISK_LINE=$(echo "$DISK_LIST" | gum choose --header "Select Disk for Partitioning")
  SELECTED_DISK=$(echo "$SELECTED_DISK_LINE" | awk '{print $1}' | sed 's|^[^/]*||')

  if [ -n "$SELECTED_DISK" ]; then
    cfdisk "$SELECTED_DISK"
  fi
fi

# 2. SELECTION CORE
PART_LIST=$(lsblk -plno NAME,SIZE,TYPE,FSTYPE,LABEL | grep "part")

if [ -z "$PART_LIST" ]; then
  gum style --foreground 15 "No partitions found. Please partition your disk first."
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
  # Format output to a usable drive name by stripping tree characters (|- or └─)
  selected=$(echo "$selected_raw" | awk '{print $1}' | sed 's|^[^/]*||')

  if [ -n "$selected" ]; then
    USED_PARTS+=("$selected")
    echo "$selected"
  fi
}

# 3. FLASHING INSTRUCTIONS
ISO=$(find out/ -maxdepth 1 -name "*.iso" -print -quit)
if [ -z "$ISO" ]; then
    echo "Error: No ISO found in out/"
    exit 1
fi

# --- MANDATORY SELECTION ---
PART_ROOT=$(select_partition "Select ROOT (/) partition")
if [ -z "$PART_ROOT" ]; then return 1; fi
MOUNTS["$PART_ROOT"]="/"

PART_EFI=$(select_partition "Select EFI partition (usually vfat, 100MB–512MB)")
if [ -z "$PART_EFI" ]; then
  gum style --foreground 15 "ERROR: No EFI partition selected. Aborting."
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

# Note: /boot is NOT a separate partition by default to support chain-booting kernels from root Btrfs.
# But we allow a manual boot partition if the user really wants it.
if gum confirm "Use a separate /boot partition? (Not recommended for simple chain-booting)"; then
  if select_partition "Select /boot partition" > /dev/null; then
     # We already selected it via select_partition, but we don't actually need the variable if we rely on MOUNTS
     echo "Separate /boot partition added."
  fi
fi

# --- SWAP DETECTION ---
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
  else
    # Opinionated: Always use Btrfs for everything else
    gum style --foreground 15 "Enforcing Btrfs for $mnt to ensure a clean wipe..."
    if gum confirm "Wipe and format $part as Btrfs for $mnt? (WARNING: total data loss)"; then
      gum spin --title "Formatting $part as Btrfs..." -- mkfs.btrfs -f "$part"
    fi
  fi
done

udevadm settle

# 4. EXECUTION: MOUNTING
# Mount root first, then create Btrfs subvolumes.
gum spin --title "Mounting root filesystem..." -- bash -c '
  set -e
  mount "$1" /mnt

  # Force Btrfs subvolume layout
  btrfs subvolume create /mnt/@ &>/dev/null || true
  if [ "$2" != "true" ]; then
    btrfs subvolume create /mnt/@home &>/dev/null || true
  fi
  
  umount /mnt
  udevadm settle
  
  # Re-mount with @ subvolume
  mount -o compress=zstd:3,noatime,autodefrag,subvol=@ "$1" /mnt
  
  if [ "$2" != "true" ]; then
    mkdir -p /mnt/home
    mount -o compress=zstd:3,noatime,autodefrag,subvol=@home "$1" /mnt/home
  fi
' _ "$PART_ROOT" "$HAS_MANUAL_HOME"

# Mount EFI and optional Boot
for part in "${!MOUNTS[@]}"; do
  mnt="${MOUNTS[$part]}"
  if [ "$mnt" == "/" ] || { [ "$mnt" == "/home" ] && [ "$HAS_MANUAL_HOME" != "true" ]; }; then
    continue 
  fi

  gum spin --title "Mounting $part -> $mnt..." -- bash -c '
    mkdir -p /mnt"$2"
    mount "$1" /mnt"$2"
  ' _ "$part" "$mnt"
done

# Enable swap
if [ "$ENABLE_SWAP" == "true" ]; then
  gum spin --title "Enabling swap ($SWAP_PART)..." -- swapon "$SWAP_PART"
fi

gum style --foreground 15 "Mounting complete. Using chain-booting compatible layout."
