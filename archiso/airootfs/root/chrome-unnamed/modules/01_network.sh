# ==============================================================================
# Chrome-Unnamed: Network Subsystem
# ==============================================================================
# Orchestrates connectivity. The live ISO environment initializes NetworkManager
# automatically, but this module forces an explicit state check and provides
# an interactive uplink selection interface.
# ==============================================================================

set -e
source "modules/00_helpers.sh"

# 1. PRE-FLIGHT CHECK
if ping -c 1 1.1.1.1 &>/dev/null; then
  gum style --foreground 15 "[NET] Connection established. System is online."
  return 0
fi

# 2. HARDWARE INITIALIZATION
# Unblock wireless radios and trigger an explicit scan.
gum spin --title "Initializing network hardware..." -- bash -c "
  rfkill unblock all
  nmcli networking on
  nmcli dev wifi rescan 2>/dev/null
  sleep 4
"

# 3. UPLINK SELECTION
while true; do
  CONNECTION=$(gum choose "Wi-Fi" "Ethernet" "Skip (Air-gapped Mode)")

  case $CONNECTION in
  "Wi-Fi")
    while true; do
      NETWORKS=$(nmcli -t -f SSID dev wifi list 2>/dev/null | grep -v '^$' | sort -u)

      if [ -z "$NETWORKS" ]; then
        gum style --foreground 15 "[NET] No access points found."
        CHOICE=$(gum choose "Rescan" "Abort")
        if [ "$CHOICE" == "Rescan" ]; then
          gum spin --title "Rescanning..." -- bash -c "nmcli dev wifi rescan && sleep 3"
          continue
        else
          break # Exit Wi-Fi loop
        fi
      fi

      SSID=$(echo "$NETWORKS" | gum choose --header "Select target uplink")
      if [ -z "$SSID" ]; then
        break
      fi

      PASS=$(gum input --password --placeholder "Enter Wi-Fi password (blank if open)")
      if gum spin --title "Connecting to $SSID..." -- nmcli dev wifi connect "$SSID" password "$PASS"; then
        break 2 # Connected!
      else
        gum style --foreground 15 "[NET] Connection failed. Incorrect password?"
        CHOICE=$(gum choose "Retry" "Abort")
        if [ "$CHOICE" == "Abort" ]; then
          break
        fi
      fi
    done
    ;;

  "Ethernet")
    gum spin --title "Acquiring IPv4 lease..." -- sleep 5
    break
    ;;

  "Skip (Air-gapped Mode)")
    gum style --foreground 15 "[NET] Warning: Entering air-gapped mode. Proceeding offline."
    return 0
    ;;
  esac
done

# 4. CONNECTION VERIFICATION
if ! ping -c 1 1.1.1.1 &>/dev/null; then
  gum style --foreground 15 "[NET] FATAL: Connection lost. Verify hardware."
  return 1
fi

gum style --foreground 15 "[NET] Network connection established. Online."
