# chrome-unnamed: Network Module

# 1. PRE-FLIGHT CHECK
# If we already have a ping, don't annoy the user.
if ping -c 1 1.1.1.1 &>/dev/null; then
  gum style --foreground 82 "System is already online."
  return 0
fi

# 2. MASTER SWITCH (HARDWARE WAKE-UP)
# Forces networking on and triggers an explicit rescan.
gum spin --title "Waking up network hardware..." -- bash -c "nmcli networking on && nmcli dev wifi rescan && sleep 2"

# 3. SELECTION TUI
# Use gum to create a clean interface for choosing the connection.
CONNECTION=$(gum choose "Wi-Fi" "Ethernet" "Skip (Offline Mode)")

case $CONNECTION in
"Wi-Fi")
  # nmcli scans for nearby SSIDs.
  # grep -v '^$' removes hidden/empty network names.
  NETWORKS=$(nmcli -t -f SSID dev wifi | grep -v '^$' | sort -u)

  if [ -z "$NETWORKS" ]; then
    gum style --foreground 196 "No networks found after rescan. Check hardware switches."
    return 1
  fi

  SSID=$(echo "$NETWORKS" | gum choose --header "Select Network")

  if [ -z "$SSID" ]; then
    gum style --foreground 196 "No network selected."
    return 1
  fi

  PASS=$(gum input --password --placeholder "Enter Wi-Fi Password")

  # The spinner keeps the UI active while the hardware handshakes.
  gum spin --title "Connecting to $SSID..." -- nmcli dev wifi connect "$SSID" password "$PASS"
  ;;

"Ethernet")
  # Ethernet is usually plug-and-play, just needs a moment for DHCP.
  gum spin --title "Waiting for DHCP..." -- sleep 5
  ;;

"Skip (Offline Mode)")
  gum style --foreground 214 "⚠ Warning: You are proceeding without a network."
  return 0
  ;;
esac

# 4. VERIFICATION
# One last ping to ensure the bridge to GitHub is open.
if ! ping -c 1 1.1.1.1 &>/dev/null; then
  gum style --foreground 196 "Connection failed. Verify credentials and hardware."
  return 1
else
  gum style --foreground 82 "Handshake Successful."
fi

