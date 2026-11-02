# Testing

| Layer | Where | How to run | What it proves |
|---|---|---|---|
| Unit (pure Lua) | `tests/unit.lua` | `lua tests/unit.lua` | coordinate conversion, zoom invariants, bars/beats for 4/4 3/4 6/8 7/8, grid lines, pitch↔row mapping (every pitch), note hit testing/edge zones, overlap, snap/quantize math, layout at 6 window sizes, WAV writer/analyser, drum-sample generator, id uniqueness |
| Engine integration | `tests/it_engine.lua` | in REAPER | real tracks/clips/notes/FX/volume/pan/mute/solo/transport; tempo keeps clips musical; native undo/redo incl. "one drag = one undo"; instrument param inspection; FLAC/MP3/OGG/AIFF import; export + save + **reopen in a fresh process** + re-export |
| UI workflow | `tests/it_ui_flow.lua` | in REAPER | the 25-step MVP song, driven through the **real frame loop** with synthetic mouse/keyboard events: welcome → project → tracks → draw/move/resize/delete notes → velocity → duplicate/copy/paste → import audio through the in-app browser → trim/move → mixer → effects → loop/play → undo/redo → save-as → export → reopen → resume editing → re-export |
| Robustness | `tests/it_extra.lua` (`extra_robust`) | in REAPER | foreign tracks untouched; external reorder/rename/delete; missing audio (flagged offline) and drum samples (re-linked); confirmations; ruler seek, wheel zoom/scroll; Dock/Undock; audition produces audio |
| Sizes | `extra_sizes` | in REAPER | window re-created at 640×400 … 1920×1080: size took effect + layout valid; screenshots saved |
| Performance | `extra_perf` | in REAPER | 16 tracks / 102 clips / 1,000 notes: idle, drag and playback frame cost + cadence |
| Shipped example | `tests/it_example.lua` | in REAPER | `examples/neon_drive.rpp` opens from a relative path and renders the same peak/RMS as the shipped WAV |
| Legacy prototype | `tests/legacy/daw_prototype.lua` | in REAPER | the original five go/no-go checks (dockable window, 2 tracks + MIDI clip, notes, ReaSynth playback, save/reopen) |
| **Real OS events** | `tools/gui/gui_test.sh` | macOS + Accessibility permission | genuine `CGEvent` mouse/keyboard events into the REAPER window, verified via the app's published state |

Run everything: `tools/run_all_tests.sh` (≈6 min) → writes [TEST_RESULTS.md](TEST_RESULTS.md).

## How the in-REAPER tests work

`tools/run_reaper.sh` starts a fresh REAPER (`-nosplash -newinst`), runs a test script via the command line, waits for a `DONE`
file and makes sure REAPER exits. Scripts write `out/result_<mode>.txt`. Two phases per scenario (`build` / `verify`) are run in
*separate* REAPER processes to prove persistence. `tests/ui_driver.lua` replaces only the **input source** (`G.input_source`);
everything below it - hit testing, widgets, dialogs, commands, REAPER edits, drawing - is the production path. Frames are
inspected by `A.snapshot()`, which reads the framebuffer back with `gfx.getpixel` and writes a PPM (→ PNG with Pillow), so
tests and humans can look at exactly what was rendered (screenshots in `docs/screenshots/`).

Gotchas learned the hard way (all encoded in the harness):
* Do not run REAPER array-argument APIs (audio accessors, peaks) inside a Lua **coroutine** - they silently do nothing. Tests use `T.poll`/`T.wait_until` (defer callbacks) instead.
* A busy-wait loop starves REAPER's main thread: transport position and meters don't advance. Poll via `defer`.
* `Track_GetPeakInfo` is read-and-reset; only one consumer (the app's meter service) may call it.
* Audio engine start-up takes ~2.5 s after REAPER launches; playback assertions wait for it.

## Real GUI testing (OS-level events)

`tools/gui/gui_test.sh` launches REAPER with `DAW_DEBUG_DIR` set (the app then publishes its window origin, widget rectangles
and project counters to `out/state.txt`), posts genuine macOS input events with `tools/gui/evt` (a small Swift `CGEvent`
tool) and verifies results from the state file: new project, track menu, double-click clip, drawing 4 notes, Cmd+Z / Cmd+Shift+Z,
Space play/stop, loop drag on the ruler, typing a project name, Dock/Undock.

**Prerequisite:** macOS only delivers posted events if the launching app is trusted: *System Settings → Privacy & Security →
Accessibility* (and Input Monitoring) for your terminal. Without it events are dropped silently; the script probes for this
first and exits with code **2** ("BLOCKED") instead of reporting a pass. In the environment this project was built in the permission was
not available, so this layer is **written but unexecuted**; everything else above ran. To run it:

```bash
# 1. grant Accessibility to your terminal, 2. then
tools/gui/gui_test.sh      # exit 0 = all real-event checks passed;   results in out/result_gui.txt
```
