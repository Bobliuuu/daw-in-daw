#!/bin/bash
# usage: tools/shot.sh <out.png> [step]   -- asks a running DAW-in-DAW (started with DAW_DEBUG_DIR=$DAW_OUT) for a framebuffer dump
DIR="${DAW_OUT:-$HOME/daw-in-reaper/out}"
OUT="$1"; STEP="${2:-2}"
rm -f "$OUT.ppm" "$OUT.ppm.done"
printf '%s\n%s\n' "$OUT.ppm" "$STEP" > "$DIR/snap_request"
for i in $(seq 1 120); do [ -f "$OUT.ppm.done" ] && break; sleep 0.5; done
python3 - "$OUT" <<'PY'
import sys
from PIL import Image
p=sys.argv[1]
Image.open(p+".ppm").save(p)
PY
rm -f "$OUT.ppm" "$OUT.ppm.done"
echo "$OUT"
