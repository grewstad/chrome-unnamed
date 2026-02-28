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
  # 1. Grab first segment (awk skips leading spaces)
  # 2. Remove tree decorators (characters like ├, ─, └)
  # 3. Ensure it starts with /dev/ and remove double slashes
  echo "$input" | awk '{print $1}' | sed 's/^[[:punct:][:space:]]*//' | sed -E 's|^(/dev/)?|/dev/|; s|^/dev//dev/|/dev/|' | tr -d ' \n\r\t'
}

# Export these so subshells can find them if needed
export -f clean_path
export -f log
export -f profile_hardware
