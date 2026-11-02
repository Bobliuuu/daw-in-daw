# "I Built a DAW Inside a DAW" - article outline

**Hook (≈150 words).** Neovim-in-Neovim as the mental model: don't make a plugin, make an *application* whose only host is the
editor's scripting API. 59 seconds of video: tracks, a drum pattern, a bassline, an imported loop, reverb, play, export - all drawn
by a Lua script inside REAPER, all stored as ordinary REAPER objects. Then: "the song you hear was edited by software that never
touched REAPER's own editors".

**1. The go/no-go test (the prototype).** Five questions before writing an app: can a script open a dockable window, create real
tracks, edit MIDI, make a native instrument sing, and survive save/reopen? A 150-line `daw.lua` answered yes - and its own test
harness (a headless REAPER launched from the command line) became the spine of everything after.

**2. One project, two interfaces.** The design decision that shaped the rest: no second model, no second engine. Ownership by a
folder track; stable GUIDs instead of indices; why a *read-model snapshot* beats scanning REAPER every frame; why musical state is
never mutated outside commands. What you gain: open the `.rpp` in REAPER's own UI and it just *is* a normal project.

**3. Building a UI toolkit out of `gfx`.** No clipping, no widgets, no layout. A clip-rect stack in pure Lua; HiDPI scale factor;
immediate-mode widgets with id-based mouse capture; modals that block the layers beneath; the transport bar that drops low-priority
buttons when the window shrinks (found by *looking at a screenshot at 800×520*).

**4. Surprising constraints (the fun part - each is a real bug I hit).**
* MIDI API edits are invisible to REAPER's undo until you `MarkTrackItemsDirty` - my first "undo" undid the *wrong thing*.
* `GetProjectStateChangeCount` doesn't move when you add a note.
* Array-argument APIs (audio accessor, peaks) silently return nothing **inside a Lua coroutine** - my test harness broke the very feature it tested.
* `GetMediaItemTake_Peaks` returns nothing at all in 7.39 → draw waveforms by decoding through an audio accessor.
* `Track_GetPeakInfo` is read-and-reset: two consumers = a meter that lies.
* Undo restores track *arming*, silently killing note audition; arming is async, so the first note after re-arming vanishes.
* `RENDER_TAILFLAG` is a bit-mask per bounds type - my export had no reverb tail until I read the numbers (16.00 s vs 17.50 s).
* A pitch row off-by-one (`floor` vs `ceil`) put every note one semitone low - visible only in a screenshot (36 labelled "B1").
* Busy-waiting starves REAPER's main thread, so transport position stays at 0.
* `getpixel` reads at `gfx.x/gfx.y`, not at its arguments - my first screenshots were uniformly grey.

**5. Testing an application you can't screenshot.** macOS blocked screen capture and synthetic input in the sandbox. So: read the
framebuffer back with `gfx.getpixel` (0.1 s for a full frame), drive the production frame loop with scripted input, assert on the
REAPER project afterwards, and keep the genuine-OS-event test as a script that *refuses to pass* when events are dropped. 580+ checks;
the same machinery records the demo.

**6. Making it sound like music.** Procedurally generated drum kit loaded into six sampler instances; instrument/effect parameters
resolved by *name* because indices are not a contract; why a 1.5 s render tail matters; comparing exports across a save/reopen cycle.

**7. What a DAW actually is.** Lessons: a DAW is mostly *time* (QN vs seconds vs PPQ, item timebases, tempo changes) and *state
ownership* (who may mutate what, when is a pointer dead); drag-gestures-as-single-undo; why REAPER being scriptable at this depth is
unusual; what's still missing (tempo maps, automation, recording) and why a custom UI over a real engine is a promising pattern.

**Assets:** demo video · screenshots (`docs/screenshots`) · the unedited test output (`docs/TEST_RESULTS.md`) · the exported song.
**Call to action:** clone, run `./run.sh examples/neon_drive.rpp`, hit Space.
