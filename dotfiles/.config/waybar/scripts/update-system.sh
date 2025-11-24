#!/bin/bash
ghostty -e sudo pacman -Syu && for pid in $(pgrep waybar); do kill -RTMIN+8 $pid; done