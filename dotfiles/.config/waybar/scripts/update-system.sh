#!/usr/bin/env bash

# Use your preferred terminal
TERMINAL="${TERMINAL:-ghostty}"

$TERMINAL -e bash -lc '
  echo "Updating system..."
  echo ""
  
  sudo pacman -Syu
  
  # Clear cache and refresh Waybar
  rm -f /tmp/waybar-updates-cache
  pkill -SIGRTMIN+8 waybar
  
  echo ""
  echo "Update complete! Press Enter to close..."
  read
'