#!/bin/bash
# ==============================================================================
# Chrome-Unnamed: Core Deployment Orchestrator
# ==============================================================================
# This script serves as the primary entry point for the Chrome-Unnamed OS
# installation. It initializes the deployment environment, enforces critical
# constraints, establishes global telemetry, and executes module payloads.
# ==============================================================================

set -e
trap 'gum style --foreground 15 "FATAL: Deployment failed in $(basename "$0") at line $LINENO. Check $LOG_FILE for details." ; exit 1' ERR

# --- GLOBAL TELEMETRY & HELPERS ---
source "modules/00_helpers.sh"
# LOG_FILE is defined in modules/00_helpers.sh as /root/chrome-unnamed/install.log

echo "[INIT] Chrome-Unnamed Installation Suite Started at $(date)" > "$LOG_FILE"
profile_hardware

# --- BUILD VERIFICATION ---
BUILD_ITERATION="7"

# DEBUG STATUS
gum style --border normal --padding "1 4" --border-foreground 15 --foreground 15 --bold \
  "CHROME-UNNAMED HARDENED ISO (2026-02-28) - V$BUILD_ITERATION [STABLE]"

# 1. DEPENDENCY INJECTION
# Ensure the TUI rendering engine (gum) is present in the live environment.
if ! command -v gum &>/dev/null; then
  echo "[INIT] Resolving UI dependencies (gum)..."
  pacman -Sy gum --noconfirm --needed &>/dev/null
fi

# 1b. CORE UTILITY AUDIT
# Verify that all essential system tools are available before proceeding.
for tool in reflector lsblk awk grep findmnt; do
    if ! command -v "$tool" &>/dev/null; then
        gum style --foreground 15 "FATAL: Required binary '$tool' is missing from the live filesystem."
        exit 1
    fi
done

# --- HELPER FUNCTIONS ---
# Functions are now sourced from modules/00_helpers.sh

# 2. PREREQUISITES & UEFI VALIDATION
# Chrome-Unnamed strictly enforces modern UEFI paradigms. Legacy BIOS is not supported.
if [ ! -d "/sys/firmware/efi/efivars" ]; then
    gum style --foreground 15 "FATAL: Motherboard firmware is not exposing UEFI variables. Legacy BIOS boot detected. Aborting sequence."
    exit 1
fi

# 3. INITIALIZATION & NETWORK HANDSHAKE
gum style \
	--foreground 15 --border-foreground 15 --border double --bold \
	--align center --width 50 --margin "1 2" --padding "2 4" \
	"CHROME-UNNAMED" "Automated Installer"

echo "[CORE] Starting network discovery..."
source "modules/01_network.sh"

if gum confirm "Optimize repository mirrors with Reflector? (Recommended)"; then
    if nm-online -t 15 >/dev/null; then
        gum spin --title "Optimizing mirrors for maximum throughput..." -- \
            bash -c "reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist >> \"$LOG_FILE\" 2>&1"
    else
        gum style --foreground 15 "Warning: Network offline. Skipping mirror optimization."
    fi
fi

# 4. KEYBOARD LAYOUT INJECTION
KEYMAPS=$(localectl list-keymaps)
KEYMAP=$(echo -e "us\n$KEYMAPS" | gum filter --placeholder "Select your weapon (Keyboard Layout, default: us)")
if [ -z "$KEYMAP" ]; then KEYMAP="us"; fi
export KEYMAP
gum spin --title "Applying keyboard layout: $KEYMAP..." -- loadkeys "$KEYMAP"

# 5. MODULE EXECUTION PIPELINE
# The installer is modularly segmented for maintainability.
# Expanding the execution array allows for dynamic workflows.
modules=(
  "modules/02_disk.sh"
  "modules/03_system.sh"
  "modules/04_setup.sh"
)

for module in "${modules[@]}"; do
  if [ -f "$module" ]; then
    echo "[PIPELINE] Running $module..."
    # 'set -e' is preserved inside modules to ensure immediate failure on error.
    # shellcheck source=/dev/null
    source "$module"
  else
    gum style --foreground 15 "FATAL: Pipeline module missing -> $module"
    exit 1
  fi
done

# 6. TELEMETRY PERSISTENCE & FINALIZE
echo "[CORE] Persisting installation logs to the local device..."
# /mnt is active if module 02/03 succeeded
if mountpoint -q /mnt; then
    mkdir -p /mnt/var/log/
    cp "$LOG_FILE" /mnt/var/log/chrome-unnamed-install.log 2>/dev/null || true
    # Also copy to the user's home for immediate visibility
    if [ -d "/mnt/home/$USERNAME" ]; then
        cp "$LOG_FILE" "/mnt/home/$USERNAME/install.log" 2>/dev/null || true
    fi
fi

gum confirm "Deployment successful. System is primed. Reboot now?" && reboot
