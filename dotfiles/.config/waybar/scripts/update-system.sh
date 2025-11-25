#!/usr/bin/env bash

ghostty -e bash -lc '
  # Do the actual update
  sudo pacman -Syu

  # Clear the Waybar cache so we don't reuse stale JSON
  rm -f /tmp/waybar-updates-cache

  # Tell Waybar to refresh the module (signal 8 -> SIGRTMIN+8)
  pkill -SIGRTMIN+8 waybar
'
