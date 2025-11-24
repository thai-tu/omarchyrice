#!/bin/bash

CACHE_FILE="/tmp/waybar-updates-cache"
LOCK_FILE="/tmp/waybar-updates.lock"
CACHE_TIME=330  # 5.5 minutes (longer than the 300s interval)

# Function to cleanup lock on exit
cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# Check if cache exists and is fresh
if [ -f "$CACHE_FILE" ]; then
    CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE")))
    if [ $CACHE_AGE -lt $CACHE_TIME ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Try to acquire lock
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    sleep 1
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
    else
        echo '{"text":"...","tooltip":"Checking for updates"}'
    fi
    exit 0
fi

# Check for updates
updates=$(checkupdates 2>/dev/null | wc -l)
total=$updates

# Format output
if [ $total -eq 0 ]; then
    output='{"text":"0","tooltip":"System is up to date","class":"updated"}'
else
    output='{"text":"'$total'","tooltip":"'$total' updates available","class":"pending"}'
fi

# Save and output
echo "$output" | tee "$CACHE_FILE"