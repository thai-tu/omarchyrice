#!/usr/bin/env python3
import json
import subprocess
import sys
from typing import List, Optional

STATE_FILE = "/tmp/waybar_mpris_state.json"


def run_playerctl(args: List[str]) -> str:
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


def choose_player(selected: Optional[str] = None, excluded: List[str] = None) -> Optional[str]:
    """
    Use the same sticky logic as mediaplayer.py,
    but without re-saving state (display script already does that).
    """
    if excluded is None:
        excluded = []

    excluded_set = set(p for p in excluded if p)

    names_str = run_playerctl(["--list-all"])
    if not names_str:
        return None

    names = [n.strip() for n in names_str.splitlines() if n.strip()]

    if selected:
        names = [n for n in names if n == selected]
    else:
        names = [n for n in names if n not in excluded_set]

    if not names:
        return None

    last_player = load_last_player()
    if last_player not in names:
        last_player = None

    statuses = {name: run_playerctl(["--player", name, "status"]) for name in names}

    playing = [n for n in names if statuses.get(n) == "Playing"]
    paused = [n for n in names if statuses.get(n) == "Paused"]

    chosen: Optional[str] = None

    if playing:
        if last_player and statuses.get(last_player) == "Playing":
            chosen = last_player
        else:
            chosen = playing[0]
    else:
        if last_player and statuses.get(last_player) in ("Playing", "Paused"):
            chosen = last_player
        elif paused:
            chosen = paused[0]
        else:
            chosen = names[0]

    return chosen


def main():
    # Default action is play-pause if no args are passed
    cmd_args = sys.argv[1:] or ["play-pause"]
    excluded: List[str] = []  # e.g. ["chromium"] if you want to ignore browser players

    player = choose_player(excluded=excluded)
    if not player:
        sys.exit(0)

    try:
        subprocess.call(["playerctl", "--player", player] + cmd_args)
    except FileNotFoundError:
        sys.exit(0)


if __name__ == "__main__":
    main()
