#!/bin/bash
# REAL-GUI test: posts genuine macOS input events (CGEvent) at the running REAPER window and verifies the result
# through the state file the app publishes (DAW_DEBUG_DIR). No synthetic calls into the app are involved.
#
# PREREQUISITE (macOS): grant your terminal app  System Settings > Privacy & Security > Accessibility  (and Input Monitoring).
# Without it macOS silently drops posted events; this script detects that and exits 2 instead of reporting a false pass.
#
# usage: tools/gui/gui_test.sh
cd "$(dirname "$0")/../.." || exit 1
export DAW_OUT="$PWD/out"; mkdir -p "$DAW_OUT"
source tools/gui/gui.sh
[ -x "$GUI_DIR/evt" ] || swiftc -O "$GUI_DIR/evt.swift" -o "$GUI_DIR/evt"
[ -x "$GUI_DIR/scr" ] || swiftc -O "$GUI_DIR/scr.swift" -o "$GUI_DIR/scr"
PASS=0; FAIL=0; LOG="$DAW_OUT/result_gui.txt"; : > "$LOG"
check() { # name cond(0=ok)
  if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "PASS  $1" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "FAIL  $1" | tee -a "$LOG"; fi
}
eqs() { [ "$1" == "$2" ]; echo $?; }
wait_for() { # key expected [secs]
  for i in $(seq 1 $(( ${3:-6} * 4 ))); do [ "$(sget $1)" == "$2" ] && return 0; sleep 0.25; done; return 1; }

launch
read ox oy < <(sget origin)
[ -z "$ox" ] && { echo "app did not start"; exit 1; }

# ---- permission probe: move the real mouse onto a known client point and see whether the app saw it
read sx sy < <(to_screen 600 400)
"$EVT" move $sx $sy; "$EVT" move $((${sx%.*}+3)) $((${sy%.*}+3)); sleep 0.6
read mx my md < <(sget mouse)
if [ "${mx%.*}" -lt 560 ] || [ "${mx%.*}" -gt 640 ]; then
  echo "BLOCKED: macOS dropped the synthetic OS events (app saw mouse at $mx,$my)."
  echo "Grant Accessibility to your terminal: System Settings > Privacy & Security > Accessibility, then re-run."
  pkill -x REAPER; exit 2
fi
check "OS-level mouse events reach the REAPER gfx window" 0

# ---- 1. new project through a real click
click_id welcome_new; wait_for project "1 Untitled" 4 ; check "click New project" $?

# ---- 2. add tracks through the real + Track menu
for item in "Drum_Kit_(sampler)" "Bass_Synth" "Audio_track"; do
  click_id addtrk; sleep 0.3; click_id "popup:${item//_/ }"; sleep 0.3
done
wait_for tracks 3 4; check "3 tracks created via real menu clicks" $?

# ---- 3. double-click lane => clip, then draw 4 notes with real clicks in the piano roll
read lx ly lw lh < <(rect lanes); read vx0 vppb vscroll vth < <(sget view | awk '{print $1,$2,$3,$4}')
dclick_at $(python3 -c "print($lx+$vppb*0.5, $ly+$vth*0.5)"); wait_for clips 1 3; check "double-click empty lane creates a clip" $?
sleep 0.5
read rx ry rw rh < <(rect roll); read rvx0 rvppb rtop rrow < <(sget rollview | awk '{print $1,$2,$3,$4}')
for pb in "69 0" "72 1" "76 2" "72 3"; do
  set -- $pb
  px=$(python3 -c "print($rx+($2-$rvx0)*$rvppb+6)"); py=$(python3 -c "import math; print($ry+($rtop-$1)*$rrow+$rrow/2)")
  click_at $px $py
done
wait_for notes 4 4; check "4 notes drawn with real mouse clicks" $?

# ---- 4. real keyboard: Cmd+Z undoes last note, Cmd+Shift+Z redoes
key 6 cmd; wait_for notes 3 3; check "Cmd+Z removes a note" $?
key 6 cmd shift; wait_for notes 4 3; check "Cmd+Shift+Z restores it" $?

# ---- 5. transport via real Space key
key 49; wait_for playing 1 6; check "Space starts playback" $?
key 49; wait_for playing 0 4; check "Space stops playback" $?

# ---- 6. loop region by real drag on the ruler strip
read ux uy uw uh < <(rect ruler)
drag_at $(python3 -c "print($ux+$vppb*0, $uy+6, $ux+$vppb*8, $uy+6)")
read l0 l1 le < <(sget loop); [ "$le" == "1" ]; check "dragging the ruler strip sets and enables a loop" $?

# ---- 7. real typing into a prompt (rename project)
click_id pname; sleep 0.4; "$EVT" key 51; "$EVT" type "GUI Test"; key 36; wait_for project "1 GUI Test" 4; check "type a new project name" $?

# ---- 8. docking by a real click
click_id dock; sleep 1; d=$(sget dock); [ "${d%.*}" == "257" ]; check "Dock button docks the window (dock=$d)" $?
click_id dock; sleep 1; d=$(sget dock); [ "${d%.*}" == "0" ]; check "Undock restores floating window" $?

pkill -x REAPER
echo "--- GUI tests: $PASS passed, $FAIL failed"
echo "== gui: $PASS passed, $FAIL failed" >> "$LOG"
[ $FAIL -eq 0 ]
