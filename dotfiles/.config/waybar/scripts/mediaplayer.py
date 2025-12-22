#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import subprocess
import sys
from typing import List, Optional, Tuple

STATE_FILE = os.path.expanduser("~/.cache/waybar/mpris_state.json")


# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------
def run_playerctl(args: List[str]) -> str:
    """Run playerctl with given args, return stdout as string or empty on error."""
    try:
        # Use absolute path to playerctl to avoid PATH issues
        playerctl_bin = "/usr/bin/playerctl"
        if not os.path.exists(playerctl_bin):
            # Fallback to PATH lookup
            playerctl_bin = "playerctl"
        
        out = subprocess.check_output([playerctl_bin] + args, stderr=subprocess.DEVNULL)
        return out.decode("utf-8").strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def load_last_player() -> Optional[str]:
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_SH)
            data = json.load(f)
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        return data.get("player") or None
    except Exception:
        return None


def save_last_player(name: str) -> None:
    """Persist last chosen player with an atomic write and file locking."""
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, "w", encoding="utf-8") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            json.dump({"player": name}, f)
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except Exception:
        # Not critical if this fails
        pass


def normalize_player_name(name: str) -> str:
    """Strip instance numbers for better matching (e.g., spotify.instance123 -> spotify)."""
    return name.split('.')[0] if '.' in name else name


def slugify_class(s: str) -> str:
    """Make a CSS-safe class token from a player name."""
    s = (s or "").lower()
    out = []
    for ch in s:
        out.append(ch if ch.isalnum() or ch == '.' else "_")
    token = "".join(out).strip("_.")
    return token or "player"


def choose_player(selected: Optional[str], excluded: List[str], debug: bool = False) -> Optional[str]:
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
        if debug:
            print("[debug] playerctl --list-all returned nothing", file=sys.stderr)
        return None

    names = [n.strip() for n in names_str.splitlines() if n.strip()]
    if debug:
        print(f"[debug] players (raw): {names}", file=sys.stderr)

    # Apply user filters
    if selected:
        names = [n for n in names if normalize_player_name(n) == normalize_player_name(selected)]
        if debug:
            print(f"[debug] players (forced={selected}): {names}", file=sys.stderr)
    else:
        names = [n for n in names if normalize_player_name(n) not in excluded_set]
        if debug and excluded_set:
            print(f"[debug] players (excluded={sorted(excluded_set)}): {names}", file=sys.stderr)

    if not names:
        if debug:
            print("[debug] no players after filtering", file=sys.stderr)
        return None

    last_player = load_last_player()
    # Match by normalized name for better instance handling
    if last_player:
        last_normalized = normalize_player_name(last_player)
        matching = [n for n in names if normalize_player_name(n) == last_normalized]
        last_player = matching[0] if matching else None
    
    if debug:
        print(f"[debug] last_player (valid): {last_player}", file=sys.stderr)

    # Cache statuses once
    statuses = {name: run_playerctl(["--player", name, "status"]) for name in names}
    if debug:
        print(f"[debug] statuses: {statuses}", file=sys.stderr)

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

    if chosen:
        save_last_player(chosen)

    if debug:
        print(f"[debug] chosen: {chosen}", file=sys.stderr)

    return chosen


def get_player_info(player_name: str) -> Tuple[Optional[str], Optional[str], Optional[str], Optional[str]]:
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
    """Build the JSON payload Waybar expects. Returns None if module should be hidden."""
    if not player_name:
        return None

    normalized_status = status
    if status == "Stopped":
        normalized_status = "Paused"

    if normalized_status not in ("Playing", "Paused"):
        return None

    is_spotify_ad = (
        normalize_player_name(player_name).lower() == "spotify"
        and trackid is not None
        and ":ad:" in trackid.lower()
    )

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

    # Nerd Font icons - play and pause
    icon = "󰐊" if normalized_status == "Playing" else "󰏤"

    if not icon and not track_info:
        return None

    text = f"{icon}  {track_info}" if track_info else icon

    # CSS-safe class tokens
    player_class = slugify_class(player_name)
    css_class = f"custom-{player_class} {normalized_status.lower()}"

    return {
        "text": text,
        "class": css_class.strip(),
        "alt": player_name,
    }


def hidden_payload():
    # Always emit valid JSON so Waybar never chokes
    return {"text": "", "alt": "", "class": "hidden"}


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
    parser.add_argument("--debug", action="store_true", help="Print debug info to stderr")
    return parser.parse_args()


def main():
    args = parse_args()
    
    try:
        excluded = [p.strip() for p in args.exclude.split(",") if p.strip()]

        player_name = choose_player(args.player, excluded, debug=args.debug)

        if not player_name:
            sys.stdout.write(json.dumps(hidden_payload()) + "\n")
            sys.stdout.flush()
            return

        status, artist, title, trackid = get_player_info(player_name)
        if args.debug:
            print(
                f"[debug] info: player={player_name!r} status={status!r} artist={artist!r} title={title!r} trackid={trackid!r}",
                file=sys.stderr,
            )

        output = build_output(player_name, status, artist, title, trackid)
        sys.stdout.write(json.dumps(output if output else hidden_payload()) + "\n")
        sys.stdout.flush()
    
    except Exception as e:
        if args.debug:
            print(f"[error] {e}", file=sys.stderr)
        sys.stdout.write(json.dumps(hidden_payload()) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()