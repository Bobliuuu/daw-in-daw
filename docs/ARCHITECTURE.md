# Architecture

> **Principle: one project, two interfaces.** REAPER owns all musical state and all audio. The inner DAW is an alternate
> *editing environment* over the same objects - not a separate application with its own model, engine or file format.

## 1. Mapping to REAPER primitives

| Inner DAW object | REAPER representation | Identity |
|---|---|---|
| Project | project ext-state `daw_in_daw` (`schema`, `name`, `ui`) + one **root folder track** tagged `P_EXT:daw_in_daw:role=root` | - |
| Track | child track of the root folder, tagged `role=track`, `kind=midi\|audio`, `inst`, `inst_count` | track `GUID` |
| MIDI clip | MIDI media item + take (`B_LOOPSRC=0`, `C_BEATATTACHMODE=1` "beats" timebase) | item `GUID` |
| Audio clip | media item + take with a `PCM_Source` (`C_BEATATTACHMODE=2`) | item `GUID` |
| Note | MIDI note event; **selection = REAPER's own note-select flag** | event index (ephemeral, refreshed) |
| Instrument | track FX: ReaSynth preset *or* 6 × ReaSamplOmatic5000 (drum kit) at the head of the chain | FX index < `inst_count` |
| Effect | track FX after the instrument slots | FX index |
| Volume / pan / mute / solo | `D_VOL`, `D_PAN`, `B_MUTE`, `I_SOLO` | - |
| Timeline | quarter-note "beats" (REAPER QN) everywhere in app code; seconds only inside `host.lua` | - |
| Transport | `OnPlayButton/Stop/Pause`, edit cursor, loop points, repeat | - |
| Export | REAPER's render pipeline (`Main_OnCommand(42230)` with project render settings), then analysed | - |

**Ownership boundary.** The DAW only reads/writes tracks inside its root folder (found by tag, not by index). Foreign tracks are
never touched - verified by a test that creates a user track, resets the DAW project, and checks the user track's GUID and
volume are unchanged. Ids are GUIDs, so external reordering, renaming or deleting doesn't break references; the UI re-validates
its selection every frame and clears ids that no longer resolve. Deleted resources are *not* silently recreated.

## 2. Event loop

`daw.lua → app.start()` opens a `gfx` window (HiDPI via `gfx.ext_retina`) and runs `A.step()` from `reaper.defer`. One frame:

```
G.begin_frame()         poll mouse/keys into one input struct; edge-detect press/release/double-click
P.refresh()             rebuild the project snapshot only if REAPER's change counter moved, a command called touch(), or 1 s elapsed
update_meters()         real Track_GetPeakInfo values -> smoothing/hold (single consumer: the call resets REAPER's peak)
handle_keys()           global shortcuts, then the focused panel's keys
draw panels             immediate mode: each panel draws AND hit-tests with the same rects (layout.lua is pure geometry)
G.end_frame()           popups / modal dialogs / tooltip (they receive input; layers beneath saw `blocked=true`)
gfx.update()
```

## 3. UI toolkit (`src/ui/gx.lua`)

`gfx` has no clipping, no widgets and no HiDPI abstraction, so the toolkit provides: a **clip-rect stack** applied in software to
every rect/text; logical-pixel coordinates scaled by `K`; **id-based mouse capture** (`G.active`) so a drag keeps its target;
hit testing that respects clipping and modal blocking; widgets (button, slider, scrollbar, popup menu, text prompt, confirm,
generic dialog, tooltip); and a widget registry (`G.reg`) so tests click controls by id. Drag logic (clip move/resize,
note move/resize/draw, marquee, velocity) lives in the panel modules as small state machines, *not* in the widget layer.

Layout (`ui/layout.lua`) is pure: `compute(W, H, state) -> rects`. It is unit-tested at six window sizes (tiling, bounds,
minimum sizes). The transport bar reserves its right-hand action cluster first and drops low-priority items on narrow windows.

## 4. State: persistent vs transient

* **Persistent** (musical): lives in REAPER objects only. `project.lua` builds a read-only *snapshot* (tracks, clips, FX chains,
  notes on demand) from them. Never mutated directly.
* **Transient** (`ui/state.lua`): selection, open clip, scroll/zoom, snap, drag state, clipboard (an item state chunk).
  A few UI prefs (zoom, snap, tab, panel height) are saved to project ext-state on save/exit.
* **Synchronisation.** The snapshot is a cache with explicit invalidation: `GetProjectStateChangeCount` (REAPER-side edits, undo),
  `touch()` (every command), and a 1 s poll for MIDI edits made elsewhere (REAPER does not bump the counter for MIDI-API writes).
  Native pointers (`MediaTrack*`, `MediaItem*`, takes) are never held across snapshots and are validated (`ValidatePtr2`)
  before use. Commands create ids *inside* an open gesture: lookup misses trigger a refresh.

## 5. Commands, gestures, undo/redo

`commands.lua` is the only writer. Each command runs in **one `Undo_BeginBlock2/EndBlock2`**; `begin_gesture/end_gesture`
nest, so a drag of 100 frames is exactly one undo point (test: *"whole drag = one undo step"*). Undo/redo are REAPER's native
`40029/40030` followed by an immediate snapshot refresh (otherwise the rest of the frame draws destroyed pointers).
Two empirically-found rules: MIDI-API edits are invisible to undo unless the item is flagged with `MarkTrackItemsDirty` +
`UpdateItemInProject`; and edits made *outside* an undo point revert on undo (REAPER semantics).

Time is handled as QN: clips use the *beats* timebase, so changing tempo keeps clips musically in place; positions are converted
to seconds only at the REAPER boundary (`host.lua`), notes via `MIDI_GetPPQPosFromProjQN` (never by assuming an item starts at 0).

## 6. Instruments, effects, audio

* **Presets** (ReaSynth) are sets of `name -> value`; **every parameter index is resolved by name at runtime** against the live
  plugin (`param_index`). Plugins are identified by `fx_name` even when the instance is renamed ("Kick" is a ReaSamplOmatic5000).
* **Drum Kit**: six RS5k instances, each with one procedurally generated sample (`audio/drumgen.lua`, original, no external
  assets) mapped to one MIDI note (kick 36, snare 38, clap 39, hats 42/46, tom 45). Missing sample files are re-linked on open.
* **Audio import** uses `PCM_Source_CreateFromFile` (WAV/FLAC/MP3/OGG/AIFF verified); waveforms are decoded through a take
  audio accessor (the peak-cache API returns nothing through Lua on 7.39) and cached per zoom.
* **Audition**: notes are sent with `StuffMIDIMessage` to the track via the virtual keyboard input; because undo restores track
  arming and arming is applied asynchronously, the app re-checks arming each time and delays the first note by ~120 ms.

## 7. Persistence

Everything musical is saved by REAPER in the `.rpp`. Inner metadata is `P_EXT` on tracks (role/kind/inst) and project ext-state
(schema version, name, UI prefs). Re-running the script is idempotent (`ensure_root`), reopening resumes (tested in a fresh
process, including editing and undo after reopen), and a toggle (`daw.lua` run twice) closes the running instance.

## 8. Export

`audio/export.lua` saves the project's render settings, sets master-mix / bounds / 44.1 kHz stereo / 16-bit WAV / 1.5 s tail
(`RENDER_TAILFLAG=15`; the flag is a bit-mask per bounds type), renders with the *most recent settings* action, restores the
settings, then parses the WAV itself: duration, peak, RMS, format, per-half-second peaks. A silent render is reported as a failure.
Paths never overwrite (`name_2.wav`...).

## Performance

Measured by `tests/it_extra.lua` (16 tracks, 102 clips, 1,000 notes, 1280×800, REAPER 7.39, Apple M-series, REAPER unfocused):

| scenario | UI work / frame (mean · p95) |
|---|---|
| idle | 1.5 ms · 1.8 ms |
| dragging a clip (live REAPER edits + snapshot rebuild each frame) | 2.3 ms · 2.4 ms |
| playback (meters + playhead + 16 tracks) | 3.7 ms · 8.1 ms |

Frame *work* is ~9-20× under a 33 ms budget. The achieved cadence is set by REAPER's `defer` scheduler, not by the app: the
final run measured 34 fps idle / 33 fps during playback, while earlier runs of identical code measured 21-22 fps (REAPER was an
unfocused background process in all of them; the cause of the variation was not investigated). It was never measured with a
human-focused window.
Techniques that keep frames cheap: cached snapshot, notes cached per snapshot version and drawn only when visible, waveform
cache, no per-frame object scans, `PreventUIRefresh` around bulk edits.

## Why Lua ReaScript + `gfx`

It is the only UI route that satisfies "built-in only": no extension, no second process, runs wherever REAPER runs, and the
script has direct, synchronous access to the project. ReaImGui would give nicer widgets but is a third-party extension.
The cost is the toolkit in section 3 and the lessons recorded in [ARTICLE_OUTLINE.md](ARTICLE_OUTLINE.md).
