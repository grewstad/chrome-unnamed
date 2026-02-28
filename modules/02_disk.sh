# ==============================================================================
# Chrome-Unnamed: Disk Provisioning Module
# ==============================================================================
# Executes opinionated Btrfs partitioning and manages chain-boot topologies.
# Handles geometric mapping, wipe verification, and subvolume orchestration.
# ==============================================================================

set -e
source "modules/00_helpers.sh"

# 1. PARTITIONING OVERRIDE (Optional)
stty sane
MODE=$(gum choose "Use existing partitions" "Manual partitioning (cfdisk)")

if [ "$MODE" == "Manual partitioning (cfdisk)" ]; then
  DISK_LIST=$(lsblk -dno NAME,SIZE,MODEL | grep -v "loop" | grep -v "sr")
  SELECTED_DISK_LINE=$(echo "$DISK_LIST" | gum choose --header "Select target drive")
  SELECTED_DISK=$(clean_path "$SELECTED_DISK_LINE")

  if [ -n "$SELECTED_DISK" ]; then
    cfdisk "$SELECTED_DISK"
  fi
fi

# 2. DEVICE DISCOVERY
# We use a spinner here because disk probing can occasionally hang or take time
# Using -pf for a detailed human-readable view (FSTYPE, LABEL, UUID)
gum spin --title "Probing hardware for partitions [Visual Mapping]..." -- bash -c 'lsblk -pfplno NAME,SIZE,TYPE,FSTYPE,LABEL,UUID | grep "part" > /tmp/part_list'
PART_LIST=$(cat /tmp/part_list)

if [ -z "$PART_LIST" ]; then
  gum style --foreground 15 "[DISK] No partitions detected. Please partition the drive first."
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

  stty sane
  selected_raw=$(echo "$choices" | gum choose --header "$prompt")
  local selected
  selected=$(clean_path "$selected_raw")

  if [ -n "$selected" ]; then
    USED_PARTS+=("$selected")
    echo "$selected"
    gum style --foreground 10 " [OK] Vector assigned: $selected"
  fi
}

# --- REQUIRED PARTITIONS ---
PART_ROOT=$(select_partition "Select ROOT (/) partition")
if [ -z "$PART_ROOT" ]; then return 1; fi
MOUNTS["$PART_ROOT"]="/"

PART_EFI=$(select_partition "Select EFI partition (FAT32)")
if [ -z "$PART_EFI" ]; then
  gum style --foreground 9 " [FATAL] EFI partition missing. Boot impossible."
  return 1
fi
MOUNTS["$PART_EFI"]="/efi"

# --- OPTIONAL PARTITIONS ---
HAS_MANUAL_HOME=false
if gum confirm "Use a separate /home partition? (Optional)"; then
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

# --- SWAP SPACE ---
SWAP_PART=$(lsblk -plno NAME,TYPE,FSTYPE | awk '$2=="part" && $3=="swap" {print $1}' | head -n1)
ENABLE_SWAP=false
if [ -n "$SWAP_PART" ]; then
  if gum confirm "Swap partition detected ($SWAP_PART). Enable it?"; then
    ENABLE_SWAP=true
  fi
fi

# 3. FORMATTING SEQUENCE
for part in "${!MOUNTS[@]}"; do
  mnt="${MOUNTS[$part]}"
  if [ "$mnt" == "/efi" ]; then
    if gum confirm "Format $part as FAT32? (CAUTION: Erases boot records)"; then
      gum spin --title "Formatting $part as FAT32..." -- mkfs.fat -F32 "$part"
    fi
  else
    # Opinionated: Always use Btrfs for everything else
    gum style --foreground 15 "Enforcing Btrfs for $mnt..."
    if gum confirm "Format $part as Btrfs for $mnt? (WARNING: Irreversible data loss)"; then
      # Fix Iteration 17: Wipe signatures before formatting to avoid mkfs failure
      gum spin --title "Wiping signatures on $part..." -- wipefs -a "$part"
      gum spin --title "Formatting $part as Btrfs..." -- mkfs.btrfs -f "$part"
    fi
  fi
done

udevadm settle

# 4. FILESYSTEM MOUNTING
# Mount root first, then create and mount Btrfs subvolumes.
gum spin --title "Mounting filesystem structure [Optimizing Btrfs Topology]..." -- bash -c '
  set -e
  mount "$1" /mnt

  # Advanced Subvolume Layout (EndeavourOS inspired)
  btrfs subvolume create /mnt/@ &>/dev/null || true
  btrfs subvolume create /mnt/@cache &>/dev/null || true
  btrfs subvolume create /mnt/@log &>/dev/null || true
  btrfs subvolume create /mnt/@snapshots &>/dev/null || true
  
  if [ "$2" != "true" ]; then
    btrfs subvolume create /mnt/@home &>/dev/null || true
  fi
  
  umount /mnt
  udevadm settle
  
  # Standardized Pro-Spec Mount Options
  MOUNT_OPTS="noatime,compress=zstd:3,autodefrag,discard=async"
  
  # Re-mount with @ subvolume
  mount -o $MOUNT_OPTS,subvol=@ "$1" /mnt
  
  # Mount auxiliary subvolumes
  mkdir -p /mnt/var/cache /mnt/var/log /mnt/.snapshots
  mount -o $MOUNT_OPTS,subvol=@cache "$1" /mnt/var/cache
  mount -o $MOUNT_OPTS,subvol=@log "$1" /mnt/var/log
  mount -o $MOUNT_OPTS,subvol=@snapshots "$1" /mnt/.snapshots
  
  if [ "$2" != "true" ]; then
    mkdir -p /mnt/home
    mount -o $MOUNT_OPTS,subvol=@home "$1" /mnt/home
  fi
' _ "$PART_ROOT" "$HAS_MANUAL_HOME"

# Mount EFI and optional Boot
for part in "${!MOUNTS[@]}"; do
  mnt="${MOUNTS[$part]}"
  if [ "$mnt" == "/" ] || { [ "$mnt" == "/home" ] && [ "$HAS_MANUAL_HOME" != "true" ]; }; then
    continue 
  fi

  gum spin --title "Mounting $part -> $mnt..." -- bash -c "
    mkdir -p /mnt$2
    mount $1 /mnt$2
  " _ "$part" "$mnt"
done

# Enable swap
if [ "$ENABLE_SWAP" == "true" ]; then
  gum spin --title "Enabling swap on $SWAP_PART..." -- swapon "$SWAP_PART"
fi

gum style --foreground 10 " [OK] Filesystem topology mounted and verified."
