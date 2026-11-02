#!/bin/bash
# Launch REAPER and run the inner DAW:  ./run.sh [project.rpp]
# (or in REAPER: Actions > Show action list > New action > Load ReaScript... > daw.lua ; run it again to close)
DIR="$(cd "$(dirname "$0")" && pwd)"
case "$(uname)" in
  Darwin) REAPER="${REAPER:-/Applications/REAPER.app/Contents/MacOS/REAPER}" ;;
  *)      REAPER="${REAPER:-reaper}" ;;
esac
exec "$REAPER" "$@" "$DIR/daw.lua"
