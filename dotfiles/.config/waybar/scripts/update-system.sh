#!/usr/bin/env bash
TERMINAL="${TERMINAL:-ghostty}"

$TERMINAL -e bash -lc '
  echo "=== System Update ==="
  echo ""
  
  # Update official repos
  sudo pacman -Syu
  
  # Update AUR if yay is available
  if command -v yay &> /dev/null; then
    echo ""
    echo "=== Updating AUR packages ==="
    yay -Sua
  fi
  
  # Clear cache and refresh Waybar
  rm -f /tmp/waybar-updates-cache
  pkill -RTMIN+8 waybar
  
  echo ""
  echo "Update complete! Press Enter to close..."
  read
'