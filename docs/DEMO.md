# Demo

`docs/demo/daw-in-daw-demo.mp4` (≈59 s, 1280×800) is generated, not screen-recorded:

1. `tests/demo_session.lua` runs the real app and composes the song through the real UI (mouse glides, clicks, drags, Cmd+D …)
   with a caption bar and a drawn cursor overlay (synthetic input has no OS cursor). After every UI step the app's **own
   framebuffer** is read back with `gfx.getpixel` (de-duplicated, ~870 unique frames).
2. At the end of each composition stage (drums → +bass → +lead/audio → +mix) the script renders the project with the app's
   export engine; those **real renders** loop under the video as it builds up. The playback scene runs REAPER's real transport
   (play button, moving playhead, live meters) and plays the real final mix.
3. `tools/make_demo.py` time-compresses motion frames (not text holds, not the playback scene) and muxes video + audio with ffmpeg.

Reproduce: `DAW_MODE=demo tools/run_reaper.sh $PWD/tests/demo_session.lua && python3 tools/make_demo.py`.

Storyboard (what the video shows): REAPER-hosted app opens → New project → 4 tracks (Drum Kit, Bass, Lead, Audio) → draw a drum
pattern → move/resize notes → duplicate across 8 bars → bass clip stretched to 4 bars → copy/paste → melody + velocity → import
audio through the in-app browser, trim/move/duplicate → mixer faders/pan/mute/solo → instrument parameter + Reverb/Delay/EQ → loop
region → **play** → Export WAV (analysed result card) → Save → closing caption: *every track, clip, note, fader and effect is a real
REAPER object; no extensions; pure Lua.*
Honest note: the audio under the *composition* scenes is the project's real render at that stage, not a live capture of audition clicks.
