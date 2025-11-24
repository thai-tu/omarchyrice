#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from typing import List, Optional


# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------
def run_playerctl(args: List[str]) -> str:
    """Run playerctl with given args, return stdout as string or empty on error."""
    try:
        out = subprocess.check_output(["playerctl"] + args, stderr=subprocess.DEVNULL)
        return out.decode("utf-8").strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def choose_player(selected: Optional[str], excluded: List[str]) -> Optional[str]:
    """Pick the best player name: playing > first available, honour filters."""
    excluded_set = set(p for p in excluded if p)

    names_str = run_playerctl(["--list-all"])
    if not names_str:
        return None

    names = [n.strip() for n in names_str.splitlines() if n.strip()]

    # Apply user filters
    if selected:
        names = [n for n in names if n == selected]
    else:
        names = [n for n in names if n not in excluded_set]

    if not names:
        return None

    # Prefer a player that is currently Playing
    for name in names:
        status = run_playerctl(["--player", name, "status"])
        if status == "Playing":
            return name

    # Otherwise first available
    return names[0]


def get_player_info(player_name: str):
    """
    Return (status, artist, title, trackid) for a given player.
    Uses a single metadata call that also includes status.
    """
    fmt = "{{status}}|||{{artist}}|||{{title}}|||{{mpris:trackid}}"
    meta = run_playerctl(["--player", player_name, "metadata", "--format", fmt])

    status, artist, title, trackid = None, None, None, None

    if meta:
        parts = meta.split("|||")
        if len(parts) >= 1:
            status = parts[0].strip() or None
        if len(parts) >= 2:
            artist = parts[1].strip() or None
        if len(parts) >= 3:
            title = parts[2].strip() or None
        if len(parts) >= 4:
            trackid = parts[3].strip() or None

    return status, artist, title, trackid


# ---------------------------------------------------------
# Build output for Waybar
# ---------------------------------------------------------
def build_output(
    player_name: Optional[str],
    status: Optional[str],
    artist: Optional[str],
    title: Optional[str],
    trackid: Optional[str],
):
    """Build the JSON payload Waybar expects."""

    # No player at all → hide module
    if not player_name:
        sys.stdout.write("\n")
        sys.stdout.flush()
        sys.exit(0)

    # If we don't have a useful status, or it's neither Playing nor Paused,
    # hide the module instead of showing a stop icon.
    if status not in ("Playing", "Paused"):
        sys.stdout.write("\n")
        sys.stdout.flush()
        sys.exit(0)

    # Spotify ad detection
    is_spotify_ad = (
        player_name.lower() == "spotify"
        and trackid is not None
        and ":ad:" in trackid
    )

    # Track text logic
    if is_spotify_ad:
        track_info = "Advertisement"
    elif artist and title:
        track_info = f"{title} - {artist}"
    elif title:
        track_info = title
    elif artist:
        track_info = artist
    else:
        track_info = ""

    # Icons (Nerd Font)
    if status == "Playing":
        icon = ""
    elif status == "Paused":
        icon = ""
    else:
        # We should not get here because of the earlier guard,
        # but keep a fallback just in case.
        icon = ""

    # If somehow we have no icon and no text, hide the module
    if not icon and not track_info:
        sys.stdout.write("\n")
        sys.stdout.flush()
        sys.exit(0)

    text = f"{icon}  {track_info}" if track_info else icon

    css_class = f"custom-{player_name} {status.lower()}" if status else f"custom-{player_name}"

    return {
        "text": text,
        "class": css_class.strip(),
        "alt": player_name,
    }


# ---------------------------------------------------------
# CLI and entry point
# ---------------------------------------------------------
def parse_args():
    parser = argparse.ArgumentParser(
        description="Waybar media player module (one-shot, polled)",
        add_help=False,
    )
    parser.add_argument("--player", help="Force a specific player name")
    parser.add_argument(
        "-x",
        "--exclude",
        default="",
        help="Comma-separated list of players to ignore",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    excluded = [p.strip() for p in args.exclude.split(",") if p.strip()]

    player_name = choose_player(args.player, excluded)

    # If we didn't find any suitable player, hide the module
    if not player_name:
        sys.stdout.write("\n")
        sys.stdout.flush()
        sys.exit(0)

    status, artist, title, trackid = get_player_info(player_name)
    output = build_output(player_name, status, artist, title, trackid)

    sys.stdout.write(json.dumps(output) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
