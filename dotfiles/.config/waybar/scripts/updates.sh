#!/usr/bin/env bash

CACHE_FILE="/tmp/waybar-updates-cache"
CACHE_DURATION=300

check_updates() {
    local official=0
    local aur=0
    
    # Check official repos
    if command -v checkupdates &> /dev/null; then
        official=$(checkupdates 2>/dev/null | wc -l)
    fi
    
    # Check AUR
    if command -v paru &> /dev/null; then
        aur=$(paru -Qua 2>/dev/null | wc -l)
    elif command -v yay &> /dev/null; then
        aur=$(yay -Qua 2>/dev/null | wc -l)
    fi
    
    echo "$((official + aur))"
}

# Use cache if valid
if [[ -f "$CACHE_FILE" ]]; then
    cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
    if [[ $cache_age -lt $CACHE_DURATION ]]; then
        updates=$(cat "$CACHE_FILE")
    else
        updates=$(check_updates)
        echo "$updates" > "$CACHE_FILE"
    fi
else
    updates=$(check_updates)
    echo "$updates" > "$CACHE_FILE"
fi

# Output JSON - always show the number
if [[ "$updates" -gt 0 ]]; then
    echo "{\"text\":\"$updates\",\"tooltip\":\"$updates update(s) available\",\"class\":\"pending\"}"
else
    echo "{\"text\":\"0\",\"tooltip\":\"System up to date\",\"class\":\"updated\"}"
fi