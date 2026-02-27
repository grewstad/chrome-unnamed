#!/usr/bin/env bash

options=" Shutdown\n Reboot\n Logout\n Suspend"

choice=$(echo -e "$options" | rofi -dmenu -i -theme ~/.config/rofi/menu.rasi -no-custom -p "")

case "$choice" in
    " Shutdown") systemctl poweroff ;;
    " Reboot") systemctl reboot ;;
    " Logout") hyprctl dispatch exit ;;
    " Suspend") systemctl suspend ;;
esac