#!/usr/bin/env bash
set -o pipefail

CACHE_FILE="/tmp/waybar-updates-cache"
LOCK_DIR="/tmp/waybar-updates.lock"
CACHE_TIME=330  # 5.5 minutes

cleanup() {
    rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Clean up stale locks older than 10 seconds
if [ -d "$LOCK_DIR" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_DIR") ))
    if [ "$LOCK_AGE" -gt 10 ]; then
        rmdir "$LOCK_DIR" 2>/dev/null
    fi
fi

# Use cache if fresh
if [ -f "$CACHE_FILE" ]; then
    CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    if [ "$CACHE_AGE" -lt "$CACHE_TIME" ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Try to acquire lock
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    # Another instance is working – wait for its result
    for i in {1..25}; do
        if [ -f "$CACHE_FILE" ]; then
            cat "$CACHE_FILE"
            exit 0
        fi
        sleep 0.2
    done
    echo '{"text":"...","tooltip":"Checking for updates","class":"pending"}'
    exit 0
fi

# Actually check for updates
updates_raw=$(checkupdates 2>/dev/null)
status=$?

if [ "$status" -eq 1 ]; then
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
    else
        echo '{"text":"?","tooltip":"Unable to check updates","class":"error"}'
    fi
    exit 0
fi

updates=$(printf "%s\n" "$updates_raw" | sed '/^\s*$/d' | wc -l)

if [ "$updates" -eq 0 ]; then
    output='{"text":"0","tooltip":"System is up to date","class":"updated"}'
else
    output=$(printf '{"text":"%d","tooltip":"%d updates available","class":"pending"}' "$updates" "$updates")
fi

echo "$output" | tee "$CACHE_FILE"