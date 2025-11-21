#!/usr/bin/env bash
# Waybar updates module
# Requires:
#   pacman-contrib  (for checkupdates)
# Optional:
#   yay or paru     (for AUR updates)

set -o pipefail

repo_updates=0
aur_updates=0

# --- Official repo updates (pacman) ---
if command -v checkupdates &>/dev/null; then
    # checkupdates returns 2 if no updates, 0 if updates, 1 on error
    mapfile -t repo_list < <(checkupdates 2>/dev/null)
    repo_updates=${#repo_list[@]}
fi

# --- AUR updates (yay / paru, first found) ---
if command -v yay &>/dev/null; then
    aur_updates=$(yay -Qua 2>/dev/null | wc -l)
elif command -v paru &>/dev/null; then
    aur_updates=$(paru -Qua 2>/dev/null | wc -l)
fi

total=$((repo_updates + aur_updates))

if (( total > 0 )); then
    echo "{\"text\":\"$total\",\"class\":\"updates-available\"}"
else
    echo "{\"text\":\"0\",\"class\":\"updates-none\"}"
fi

# Signal all waybar instances to refresh this module
pkill -RTMIN+8 waybar