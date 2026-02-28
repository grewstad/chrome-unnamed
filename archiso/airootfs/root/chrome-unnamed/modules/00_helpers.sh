#!/bin/bash
# ==============================================================================
# Chrome-Unnamed: Global Helper Infrastructure (Shared Functions)
# ==============================================================================

set -e

# --- GLOBAL TELEMETRY ---
LOG_FILE="/root/chrome-unnamed/install.log"

# Unified logging function for non-TUI output
log() {
  local msg="$1"
  echo "[$(date +'%H:%M:%S')] $msg" >> "$LOG_FILE"
}

# Profile hardware for the log
profile_hardware() {
  log "--- HARDWARE PROFILE ---"
  log "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
  log "RAM: $(free -h | awk '/^Mem:/ {print $2}')"
  log "UEFI: $([ -d /sys/firmware/efi ] && echo "YES" || echo "NO")"
  log "------------------------"
}

# Advanced device path sanitation
clean_path() {
  local input="$1"
  # 1. Grab first segment
  # 2. Extract only the path part (e.g., /dev/sda1) or just the name (sda1)
  # 3. Ensure it starts with /dev/ and remove double slashes
  local name
  name=$(echo "$input" | awk '{print $1}' | sed 's/.*[[:punct:]]//g; s/.*└//; s/.*├//; s/.*─//')
  # If it doesn't start with /dev/, prepend it. 
  if [[ ! "$name" =~ ^/dev/ ]]; then
    name="/dev/$name"
  fi
  echo "$name" | sed 's|^/dev//dev/|/dev/|' | tr -d ' \n\r\t'
}

# Export these so subshells can find them if needed
export -f clean_path
export -f log
export -f profile_hardware
