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

# Advanced device path sanitation
# Cleans variety of lsblk outputs (raw, tree-prefixed, etc.) into absolute paths.
clean_path() {
  local input="$1"
  # 1. Grab first column
  # 2. Strip any non-slash prefix stuff (tree artifacts)
  # 3. Ensure it starts with /dev/
  echo "$input" | head -n1 | awk '{print $1}' | sed -E 's|^[^/]*(/dev/)?|/dev/|; s|^/dev//dev/|/dev/|' | tr -d ' \n\r\t'
}

# Export these so subshells can find them if needed
export -f clean_path
export -f log
