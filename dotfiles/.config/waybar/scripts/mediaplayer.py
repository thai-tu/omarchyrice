#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
from typing import List, Optional

STATE_FILE = "/tmp/waybar_mpris_state.json"


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


def load_last_player() -> Optional[str]:
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data.get("player") or None
    except Exception:
        return None


def save_last_player(name: str) -> None:
    try:
        with open(STATE_FILE, "w", encoding="utf-8") as f:
            json.dump({"player": name}, f)
    except Exception:
        # Not critical if this fails
        pass


def choose_player(selected: Optional[str], excluded: List[str]) -> Optional[str]:
    """
    Pick the active player with memory:

      - Prefer a currently Playing player.
          - If the last active player is also Playing, keep it.
      - If nobody is Playing:
          - If the last active player still exists and is Paused/Playing, keep it.
          - Otherwise prefer a Paused player.
          - Otherwise fall back to the first available.
    """
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

    last_player = load_last_player()
    if last_player not in names:
        last_player = None

    # Cache statuses once
    statuses = {name: run_playerctl(["--player", name, "status"]) for name in names}

    playing = [n for n in names if statuses.get(n) == "Playing"]
    paused = [n for n in names if statuses.get(n) == "Paused"]

    chosen: Optional[str] = None

    if playing:
        # If the last player is still Playing, keep it
        if last_player and statuses.get(last_player) == "Playing":
            chosen = last_player
        else:
            # New media started → pick the first Playing
            chosen = playing[0]
    else:
        # No Playing players
        if last_player and statuses.get(last_player) in ("Playing", "Paused"):
            # Stay on the previous media while it's at least Paused
            chosen = last_player
        elif paused:
            chosen = paused[0]
        else:
            chosen = names[0]

    if chosen:
        save_last_player(chosen)

    return chosen


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

    # Normalise status
    normalized_status = status
    if status == "Stopped":
        normalized_status = "Paused"

    # Only show while Playing or Paused
    if normalized_status not in ("Playing", "Paused"):
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
    if normalized_status == "Playing":
        icon = ""
    elif normalized_status == "Paused":
        icon = ""
    else:
        icon = ""

    # If somehow we have no icon and no text, hide the module
    if not icon and not track_info:
        sys.stdout.write("\n")
        sys.stdout.flush()
        sys.exit(0)

    text = f"{icon}  {track_info}" if track_info else icon

    css_class = (
        f"custom-{player_name} {normalized_status.lower()}"
        if normalized_status
        else f"custom-{player_name}"
    )

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
