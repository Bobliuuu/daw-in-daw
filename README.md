# DAW in DAW

**A complete multitrack DAW, written in pure Lua, running inside [REAPER](https://www.reaper.fm).**
Think "Neovim inside Neovim": REAPER supplies the host primitives (audio engine, MIDI, file I/O, undo, render, save format);
this project supplies the *application* - its own arrangement view, piano roll, mixer, effects rack, transport, file browser,
export dialog, keyboard shortcuts and undo/redo workflow - drawn with REAPER's built-in `gfx` API. You can make, save and export a
song without touching REAPER's normal editors.

![the inner DAW, playing a finished song](docs/screenshots/08-playing-loop.png)

▶ **Demo (59 s, recorded from the app's own framebuffer; audio is real renders of the project):** [`docs/demo/daw-in-daw-demo.mp4`](docs/demo/daw-in-daw-demo.mp4)
🎧 **The song that was made with it:** [`docs/demo/neon_drive_export.wav`](docs/demo/neon_drive_export.wav) &nbsp;·&nbsp; project: [`examples/neon_drive.rpp`](examples/neon_drive.rpp)

## What makes it different from "a REAPER plugin"

* **One project, two interfaces.** The inner DAW does not keep a second model or a second audio engine. Every track, clip, note,
  fader and effect *is* a REAPER object. Open the same `.rpp` in REAPER's normal UI and you see ordinary tracks, items, MIDI
  notes and FX chains. Edits from either side show up in the other.
* **No dependencies.** Lua ReaScript + `gfx` only. No ReaImGui, SWS, JS_ReaScriptAPI, Python, Node, or external processes.
  Copy the folder, run `daw.lua`.
* **Owns the editing experience.** Its own toolkit (clip-rect stack, hit testing, mouse capture, popups, modal dialogs, text
  prompts, sliders, scrollbars) renders every pixel; REAPER only sees tracks and media items.

## Quick start

```bash
git clone https://github.com/Bobliuuu/daw-in-daw && cd daw-in-daw
./run.sh                         # launches REAPER and runs daw.lua   (macOS: /Applications/REAPER.app)
./run.sh examples/neon_drive.rpp # ...with the example song loaded
```
or inside REAPER: *Actions → Show action list → New action → Load ReaScript… → `daw.lua`* (run it again to close it).
`tools/install_action.sh` registers it as a named action. The window is a normal `gfx` window: dock it with the **Dock** button
(bottom-right, tested); REAPER's own docker also hosts script windows. Developed and tested on **REAPER 7.39, macOS 26, Apple Silicon** (older 6.x/7.x builds are untested).

## Features

| Area | What works (all of it drives real REAPER state) |
|---|---|
| **Project** | New project (one owned folder track; your other tracks are never touched), rename, save / save-as (own dialog), reopen & resume, schema-versioned metadata in project ext-state, stable GUID ids, UI prefs persisted |
| **Tracks** | MIDI and audio tracks; instruments: Lead / Bass / Pad / Pluck presets (ReaSynth) and a **6-voice Drum Kit** (ReaSamplOmatic5000 with *procedurally generated original samples*, auto re-linked if files go missing); colour, name, M/S, volume, pan, meters, delete (with confirmation) |
| **Arrangement** | Ruler with bars/beats, loop strip, 16+ bars, zoom/scroll both axes, clip move (across tracks) / resize / audio left-trim by dragging, double-click to create or open, duplicate, copy/cut/paste, split, delete, snap, real waveforms, playhead, loop region |
| **Piano roll** | Draw (click or drag-to-length), move, resize, pitch edit, velocity lane, marquee select (native selection flag), delete, arrow-key transpose/nudge, quantize, snap grid, zoom/scroll, out-of-clip shading, key audition via REAPER's virtual MIDI keyboard (tested: real audio on the track meter) |
| **Audio** | Import WAV / FLAC / MP3 / OGG / AIFF (all verified to decode in REAPER 7.39) via an in-app file browser; trim, move, duplicate, split; offline files are flagged |
| **Mixer** | Faders, pan, M/S, real peak meters (decay to silence when stopped), FX slots with bypass, master strip |
| **Effects** | Reverb (ReaVerbate), Delay (ReaDelay), EQ (ReaEQ), Compressor (ReaComp): add, remove, bypass, reorder, parameter sliders; instrument parameters too. Parameter indices are looked up **by name at runtime**, never hard-coded |
| **Transport** | Play / pause / stop / seek (REAPER's native transport), loop, tempo, time-signature, bar.beat.tick + time readout |
| **Undo / redo** | Native REAPER undo; every command is one undo point; a 100-frame drag is exactly **one** entry |
| **Export** | Own dialog: folder, name, whole project or loop region; REAPER's renderer; result **analysed** (duration, peak, RMS, format); never overwrites; render settings restored afterwards |

### Keyboard & mouse (⌘ = Cmd on macOS, Ctrl elsewhere - taken from REAPER's modifier bits)

| | |
|---|---|
| `Space` play / stop · `Home` start · `L` loop · `Esc` deselect | `⌘Z` undo · `⇧⌘Z` / `⌘Y` redo · `⌘S` save · `⌘E` export · `⌘I` import · `⌘T` add track |
| `⌘D` duplicate clip · `⌘C/X/V` copy/cut/paste · `S` split at playhead · `Del` delete · `M` / `⇧S` mute / solo | `1` `2` `3` piano roll / mixer / devices · `+` `-` zoom · `[` `]` snap |
| **Arrangement:** double-click lane = new 1-bar clip · double-click clip = open · drag body/edges · right-click menus · drag the strip above the ruler = loop · click ruler = seek | **Piano roll:** click or drag = draw note · drag = move · drag right edge = resize · right-click = delete · `⇧`-drag = select · `⌘A` · `↑↓` transpose (`⇧` octave) · `←→` nudge · `Q` quantize |
| Wheel scrolls · `⇧`+wheel horizontal · `⌘`/`Alt`+wheel zoom | Roll: wheel = pitch scroll · `Alt`+wheel = row height |

## Tests - 598 automated checks, all green

```bash
lua tests/unit.lua            # 354 pure-Lua unit tests, no REAPER needed
tools/run_all_tests.sh        # everything, incl. 244 integration checks inside real REAPER  ->  docs/TEST_RESULTS.md
tools/gui/gui_test.sh         # REAL OS mouse/keyboard events (needs macOS Accessibility permission, see docs/TESTING.md)
```
See [docs/TESTING.md](docs/TESTING.md) and the generated [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md). The original go/no-go prototype
checks (`tests/legacy/`) still pass. **Honest status of GUI testing:** the full song workflow (project → tracks → notes → arrangement → audio → mix → FX → loop/play → undo → save → export → reopen → resume), drags, keys, dialogs,
docking and window resizing are exercised through the app's real frame loop with synthetic input, and the rendered framebuffer
is inspected (screenshots below). Posting *OS-level* events needs a macOS permission that was not available in the build
environment, so `gui_test.sh` was written but **has not been run to completion** - it refuses to report success when events are dropped.

## Performance (measured, not assumed)

16 tracks · 102 clips · 1,000 MIDI notes, 1280×800: **UI work per frame 1.5 ms idle · 2.2 ms dragging a clip · 2.5 ms (p95 5.8 ms) during playback** (budget at 30 fps: 33 ms).
The snapshot of the project is rebuilt only when REAPER's state counter changes or a command runs; the renderer never scans REAPER per frame.
REAPER's `defer` scheduler delivered ~21–22 Hz in the headless run (REAPER unfocused) - see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#performance).

## Known limitations

* Developed and tested on **macOS 26 / REAPER 7.39 / Apple Silicon** only. Windows/Linux are untested (file listing uses REAPER APIs, but directory creation shells out to `mkdir -p`; modifier handling is written for Ctrl but unverified).
* OS-level GUI automation (`tools/gui/gui_test.sh`) not executed here - see above. Docking by hand-dragging the window onto a docker is not automated; the **Dock** button is tested.
* Single tempo/time-signature at the project start (changing tempo keeps clips musically in place because items use REAPER's *beats* timebase); no tempo map editing, no automation lanes, no audio recording, no MIDI-device input (audition goes through REAPER's virtual keyboard), no time-stretch, no track-reorder UI (external reordering is handled).
* MIDI clips: right-edge resize only (extends the source); overlapping clips are refused rather than layered.
* Export is REAPER's *master mix* - any non-DAW tracks in the same project are included. Edits made outside undo points revert on undo (REAPER semantics).
* `GetMediaItemTake_Peaks` returns nothing through the Lua binding on 7.39, so waveforms are decoded through a take audio accessor at a reduced rate (still real audio data, cached per zoom).
* `gfx` text is single-font Arial without unicode/emoji.

## Repository layout

```
daw.lua                 entry point (run this)
src/app.lua             frame loop, input dispatch, shortcuts, dialogs wiring
src/project.lua         read-model of the REAPER project: ownership, GUID ids, cached snapshot
src/commands.lua        every edit, one undo point each (+ gestures for drags)
src/host.lua            REAPER adapter: time map, undo gestures, pointer validation
src/timeline.lua        pure musical-time <-> pixel geometry        src/util.lua   pure helpers
src/audio/              instruments, effects, transport, export, drum-sample generator
src/ui/                 gx toolkit, layout, arrangement, piano roll, mixer, devices, transport bar, browser/dialogs
tests/                  unit + in-REAPER integration + UI-driver + legacy prototype      tools/   runners, demo recorder, GUI test
examples/               neon_drive.rpp (the demo song) + demo_loop.wav      docs/   architecture, testing, article outline, screenshots, demo
```

More: [Architecture](docs/ARCHITECTURE.md) · [Testing](docs/TESTING.md) · [Blog post outline](docs/ARTICLE_OUTLINE.md) · [Demo script](docs/DEMO.md)

## Screenshots

| | |
|---|---|
| ![](docs/screenshots/03-arrangement-duplicate.png) arrangement | ![](docs/screenshots/02-piano-roll-drums.png) piano roll (drum kit) |
| ![](docs/screenshots/06-mixer.png) mixer | ![](docs/screenshots/07-devices-effects.png) devices / effects |
| ![](docs/screenshots/09-export-dialog.png) export | ![](docs/screenshots/05-import-browser.png) audio import browser |
| ![](docs/screenshots/13-small-window-800x520.png) 800×520 | ![](docs/screenshots/14-large-window-1920x1080.png) 1920×1080 |

License: MIT.
