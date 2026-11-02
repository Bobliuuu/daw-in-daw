#!/bin/bash
# usage: tools/run_reaper.sh <script.lua> [project.rpp] ; env DAW_OUT, DAW_MODE passed through
# Launches a fresh REAPER instance, waits for $DAW_OUT/DONE_<DAW_MODE>, then ensures REAPER exited.
set -e
SCRIPT="$1"; PROJ="$2"
export DAW_OUT="${DAW_OUT:-$HOME/daw-in-reaper/out}"
export DAW_MODE="${DAW_MODE:-run}"
mkdir -p "$DAW_OUT"; rm -f "$DAW_OUT/DONE_$DAW_MODE"
for i in $(seq 1 20); do pgrep -x REAPER >/dev/null || break; sleep 1; done
(nohup /Applications/REAPER.app/Contents/MacOS/REAPER -nosplash -newinst $PROJ "$SCRIPT" >"$DAW_OUT/reaper_stdout.txt" 2>&1 &)
for i in $(seq 1 ${TIMEOUT:-120}); do [ -f "$DAW_OUT/DONE_$DAW_MODE" ] && break; sleep 1; done
for i in $(seq 1 10); do pgrep -x REAPER >/dev/null || break; sleep 1; done
pgrep -x REAPER >/dev/null && pkill -x REAPER
[ -f "$DAW_OUT/DONE_$DAW_MODE" ] && cat "$DAW_OUT/DONE_$DAW_MODE" || echo TIMEOUT
