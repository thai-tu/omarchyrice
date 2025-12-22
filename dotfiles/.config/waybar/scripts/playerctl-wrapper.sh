#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import subprocess
import sys
import time
from typing import Dict, List, Optional

STATE_FILE = os.path.expanduser("~/.cache/waybar/mpris_state.json")


def run_playerctl(args: List[str]) -> str:
    """Run playerctl with absolute path to avoid PATH issues."""
    try:
        # Use absolute path to playerctl
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
    """Persist last chosen player with file locking."""
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, "w", encoding="utf-8") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            json.dump({"player": name}, f)
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except Exception:
        pass


def normalize_player_name(name: str) -> str:
    """Strip instance numbers for better matching."""
    return name.split('.')[0] if '.' in name else name


def list_players() -> List[str]:
    names_str = run_playerctl(["--list-all"])
    if not names_str:
        return []
    return [n.strip() for n in names_str.splitlines() if n.strip()]


def statuses_for(players: List[str]) -> Dict[str, str]:
    return {p: run_playerctl(["--player", p, "status"]) for p in players}


def choose_player(
    selected: Optional[str] = None,
    excluded: Optional[List[str]] = None,
    debug: bool = False,
) -> Optional[str]:
    """
    Sticky selection (same logic as mediaplayer.py).
    Uses the saved last-player as a preference.
    """
    excluded = excluded or []
    excluded_set = set(p for p in excluded if p)

    names = list_players()
    if debug:
        print(f"[debug] players (raw): {names}", file=sys.stderr)

    if not names:
        return None

    if selected:
        names = [n for n in names if normalize_player_name(n) == normalize_player_name(selected)]
        if debug:
            print(f"[debug] players (forced={selected}): {names}", file=sys.stderr)
    else:
        names = [n for n in names if normalize_player_name(n) not in excluded_set]
        if debug and excluded_set:
            print(f"[debug] players (excluded={sorted(excluded_set)}): {names}", file=sys.stderr)

    if not names:
        return None

    last_player = load_last_player()
    # Match by normalized name
    if last_player:
        last_normalized = normalize_player_name(last_player)
        matching = [n for n in names if normalize_player_name(n) == last_normalized]
        last_player = matching[0] if matching else None
    
    if debug:
        print(f"[debug] last_player (valid): {last_player}", file=sys.stderr)

    statuses = statuses_for(names)
    if debug:
        print(f"[debug] statuses: {statuses}", file=sys.stderr)

    playing = [n for n in names if statuses.get(n) == "Playing"]
    paused = [n for n in names if statuses.get(n) == "Paused"]

    if playing:
        if last_player and statuses.get(last_player) == "Playing":
            return last_player
        return playing[0]

    if last_player and statuses.get(last_player) in ("Playing", "Paused"):
        return last_player

    if paused:
        return paused[0]

    return names[0]


def try_command(player: str, cmd_args: List[str], debug: bool = False) -> int:
    """
    Run a playerctl command for a specific player, returning the exit code.
    """
    try:
        # Use absolute path to playerctl
        playerctl_bin = "/usr/bin/playerctl"
        if not os.path.exists(playerctl_bin):
            playerctl_bin = "playerctl"
        
        res = subprocess.run(
            [playerctl_bin, "--player", player] + cmd_args,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        if debug:
            err = (res.stderr or "").strip()
            if err:
                print(f"[debug] playerctl stderr ({player}): {err}", file=sys.stderr)
            print(f"[debug] exit={res.returncode} player={player} cmd={cmd_args}", file=sys.stderr)
        return res.returncode
    except FileNotFoundError:
        if debug:
            print(f"[debug] playerctl not found", file=sys.stderr)
        return 127


def wait_for_playing(player: str, max_wait: float = 1.0, debug: bool = False) -> bool:
    """
    Poll player status until it reaches Playing state or timeout.
    Returns True if Playing was reached, False otherwise.
    """
    start = time.time()
    while time.time() - start < max_wait:
        status = run_playerctl(["--player", player, "status"])
        if status == "Playing":
            if debug:
                elapsed = time.time() - start
                print(f"[debug] player reached Playing state in {elapsed:.2f}s", file=sys.stderr)
            return True
        time.sleep(0.1)
    
    if debug:
        print(f"[debug] timeout waiting for Playing state after {max_wait}s", file=sys.stderr)
    return False


def maybe_resume_before_skip(
    player: str,
    status: Optional[str],
    cmd_args: List[str],
    debug: bool,
) -> None:
    """
    Spotify (and some players) return exit=0 for next/previous while paused,
    but won't actually change tracks. If paused and asked to next/previous, play first.
    Then wait for the player to transition before we send next/previous.
    """
    if status != "Paused":
        return
    if not cmd_args:
        return
    if cmd_args[0] not in ("next", "previous"):
        return

    if debug:
        print(f"[debug] resuming before {cmd_args[0]}", file=sys.stderr)

    try:
        playerctl_bin = "/usr/bin/playerctl"
        if not os.path.exists(playerctl_bin):
            playerctl_bin = "playerctl"
        
        subprocess.run(
            [playerctl_bin, "--player", player, "play"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        # Wait for player to reach Playing state
        wait_for_playing(player, max_wait=1.0, debug=debug)
        
    except FileNotFoundError:
        if debug:
            print(f"[debug] playerctl not found during resume", file=sys.stderr)


def parse_args():
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--player", help="Force a specific player")
    p.add_argument(
        "-x",
        "--exclude",
        default="",
        help="Comma-separated list of players to ignore",
    )
    p.add_argument("--debug", action="store_true", help="Print debug info to stderr")
    # Everything after `--` is treated as the playerctl command
    p.add_argument("cmd", nargs=argparse.REMAINDER, help="Command to pass to playerctl")
    return p.parse_args()


def main():
    args = parse_args()
    excluded = [s.strip() for s in args.exclude.split(",") if s.strip()]

    # Default action is play-pause if no command args provided
    cmd_args = [c for c in args.cmd if c != "--"]  # tolerate accidental `--`
    if not cmd_args:
        cmd_args = ["play-pause"]

    player = choose_player(selected=args.player, excluded=excluded, debug=args.debug)
    if not player:
        if args.debug:
            print("[debug] no player found", file=sys.stderr)
        sys.exit(0)

    # If we're about to next/previous while paused, resume first (fixes Spotify)
    status = statuses_for([player]).get(player)
    if args.debug:
        print(f"[debug] target player: {player}, status: {status}", file=sys.stderr)
    maybe_resume_before_skip(player, status, cmd_args, debug=args.debug)

    # Try chosen player first
    rc = try_command(player, cmd_args, debug=args.debug)
    if rc == 0:
        sys.exit(0)

    # Fallback: try other active players if the chosen one fails
    candidates = [p for p in list_players() if p != player and normalize_player_name(p) not in set(excluded)]
    if args.debug:
        print(f"[debug] fallback candidates: {candidates}", file=sys.stderr)

    for p in candidates:
        rc2 = try_command(p, cmd_args, debug=args.debug)
        if rc2 == 0:
            # Update state file to reflect the player that actually worked
            save_last_player(p)
            if args.debug:
                print(f"[debug] fallback succeeded with {p}", file=sys.stderr)
            sys.exit(0)

    if args.debug:
        print(f"[debug] all attempts failed", file=sys.stderr)
    
    sys.exit(0)


if __name__ == "__main__":
    main()
