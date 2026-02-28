#!/bin/bash
# chrome-unnamed: Network Module
# NetworkManager starts automatically in the live ISO (enabled via airootfs).

# 1. PRE-FLIGHT CHECK
if ping -c 1 1.1.1.1 &>/dev/null; then
  gum style --foreground 15 "System is already online."
  return 0
fi

# 2. HARDWARE WAKE-UP
# Unblock radios and trigger an explicit Wi-Fi rescan, then wait for cards to respond.
gum spin --title "Waking up network hardware..." -- bash -c "
  rfkill unblock all
  nmcli networking on
  nmcli dev wifi rescan 2>/dev/null
  sleep 4
"

# 3. CONNECTION METHOD
while true; do
  CONNECTION=$(gum choose "Wi-Fi" "Ethernet" "Skip (Offline Mode)")

  case $CONNECTION in
  "Wi-Fi")
    while true; do
      NETWORKS=$(nmcli -t -f SSID dev wifi list 2>/dev/null | grep -v '^$' | sort -u)

      if [ -z "$NETWORKS" ]; then
        gum style --foreground 15 "No networks found."
        CHOICE=$(gum choose "Retry Scan" "Go Back")
        if [ "$CHOICE" == "Retry Scan" ]; then
          gum spin --title "Rescanning..." -- bash -c "nmcli dev wifi rescan && sleep 3"
          continue
        else
          break # Exit Wi-Fi loop to main connection menu
        fi
      fi

      SSID=$(echo "$NETWORKS" | gum choose --header "Select Network")
      if [ -z "$SSID" ]; then
        break # Exit Wi-Fi loop
      fi

      PASS=$(gum input --password --placeholder "Enter Wi-Fi Password (leave blank if open)")
      if gum spin --title "Connecting to $SSID..." -- nmcli dev wifi connect "$SSID" password "$PASS"; then
        break 2 # Connected! Exit both Wi-Fi and Main loops
      else
        gum style --foreground 15 "Connection failed. Wrong password?"
        CHOICE=$(gum choose "Retry" "Go Back")
        if [ "$CHOICE" == "Go Back" ]; then
          break # Exit Wi-Fi loop
        fi
      fi
    done
    ;;

  "Ethernet")
    gum spin --title "Waiting for DHCP..." -- sleep 5
    break
    ;;

  "Skip (Offline Mode)")
    gum style --foreground 15 "⚠  Warning: Proceeding without a network."
    return 0
    ;;
  esac
done

# 4. VERIFICATION
if ! ping -c 1 1.1.1.1 &>/dev/null; then
  gum style --foreground 15 "Connection failed. Please check credentials or hardware."
  return 1
fi

gum style --foreground 15 "Handshake Successful. Online."
