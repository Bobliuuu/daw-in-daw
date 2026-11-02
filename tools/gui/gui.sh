#!/bin/bash
# helper functions for real-GUI tests. source this file.
GUI_DIR="$HOME/daw-in-reaper/tools/gui"
export DAW_OUT="${DAW_OUT:-$HOME/daw-in-reaper/out}"
EVT="$GUI_DIR/evt"
state() { cat "$DAW_OUT/state.txt" 2>/dev/null; }
sget() { state | awk -v k="$1" '$1==k{ $1=""; sub(/^ /,""); print; exit }'; }
# widget rect: reg <id> -> "x y w h" (logical, client coords)
reg() { state | awk -v id="$1" '$1=="reg" && $2==id {print $3,$4,$5,$6; exit}'; }
rect() { state | awk -v id="$1" '$1=="rect" && $2==id {print $3,$4,$5,$6; exit}'; }
# client logical -> screen coords
# REAPER/SWELL reports screen coords with a bottom-left origin; CGEvent wants top-left => y_cg = H - oy + y
SCREEN_H="${SCREEN_H:-$("$GUI_DIR/scr" | awk 'NR==1{print $4}')}"
to_screen() { # x y
  read ox oy < <(sget origin)
  python3 -c "print(f'{$ox+$1:.1f} {$SCREEN_H-$oy+$2:.1f}')"
}
click_at() { read sx sy < <(to_screen "$1" "$2"); "$EVT" click $sx $sy; sleep 0.25; }
rclick_at() { read sx sy < <(to_screen "$1" "$2"); "$EVT" rclick $sx $sy; sleep 0.25; }
dclick_at() { read sx sy < <(to_screen "$1" "$2"); "$EVT" dclick $sx $sy; sleep 0.35; }
drag_at() { read sx1 sy1 < <(to_screen "$1" "$2"); read sx2 sy2 < <(to_screen "$3" "$4"); "$EVT" drag $sx1 $sy1 $sx2 $sy2 ${5:-14}; sleep 0.3; }
click_id() { read x y w h < <(reg "$1"); [ -z "$x" ] && { echo "NO WIDGET $1"; return 1; }; click_at $(python3 -c "print($x+$w/2, $y+$h/2)"); }
key() { "$EVT" key "$@"; sleep 0.25; }
launch() { # [project]
  pkill -x REAPER 2>/dev/null; sleep 1.5
  rm -f "$DAW_OUT/state.txt" "$DAW_OUT/errors.txt"
  (DAW_DEBUG_DIR="$DAW_OUT" nohup /Applications/REAPER.app/Contents/MacOS/REAPER -nosplash -newinst $1 "$HOME/daw-in-reaper/daw.lua" >"$DAW_OUT/gui_stdout.txt" 2>&1 &)
  for i in $(seq 1 40); do [ -f "$DAW_OUT/state.txt" ] && break; sleep 0.5; done
  sleep 1
}
