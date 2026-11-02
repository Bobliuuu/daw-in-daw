#!/bin/bash
# Registers daw.lua as a REAPER action ("DAW in DAW") by appending to reaper-kb.ini. Close REAPER first.
DIR="$(cd "$(dirname "$0")/.." && pwd)"
case "$(uname)" in Darwin) KB="$HOME/Library/Application Support/REAPER/reaper-kb.ini" ;; *) KB="$HOME/.config/REAPER/reaper-kb.ini" ;; esac
pgrep -x REAPER >/dev/null && { echo "Close REAPER first."; exit 1; }
grep -q "$DIR/daw.lua" "$KB" 2>/dev/null && { echo "already registered"; exit 0; }
printf 'SCR 4 0 RS_dawindaw "Custom: DAW in DAW" "%s/daw.lua"\n' "$DIR" >> "$KB"
echo "Registered. In REAPER: Actions > Show action list > search 'DAW in DAW' (assign a shortcut or toolbar button if you like)."
