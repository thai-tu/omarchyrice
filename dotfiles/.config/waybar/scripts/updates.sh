#!/bin/bash

# Repo updates via pacman
repo_count=$(pacman -Qu --quiet 2>/dev/null | wc -l)

# AUR updates via yay/paru (if installed)
if command -v yay &>/dev/null; then
    aur_count=$(yay -Qu --aur --quiet 2>/dev/null | wc -l)
elif command -v paru &>/dev/null; then
    aur_count=$(paru -Qu --aur --quiet 2>/dev/null | wc -l)
else
    aur_count=0
fi

total=$((repo_count + aur_count))

if [ "$total" -gt 0 ]; then
    echo "{\"text\": \"$total\", \"class\": \"updates-available\"}"
else
    echo "{\"text\": \"0\", \"class\": \"updates-none\"}"
fi

