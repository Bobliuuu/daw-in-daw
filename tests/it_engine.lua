-- integration: engine layer (no GUI). modes: engine_build / engine_verify
local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness")
T.setup(root)
local P, C, H, X, E = require("project"), require("commands"), require("host"), require("audio.export"), require("audio.effects")
local W = require("wavio")
local OUT = T.out
local PROJ = OUT .. "/engine.rpp"

local function note_count(clip_id) return #P.notes(P.clip(clip_id)) end

local function build()
  os.execute(string.format('rm -rf "%s/export"', OUT))
  T.eq("starts empty", r.CountTracks(0), 0)
  C.new_project("Test Song")
  T.check("root folder created", P.snap.has_root and P.snap.name == "Test Song")
  local drums = C.create_track("midi", "Drums", "Drum Kit")
  local bass = C.create_track("midi", "Bass", "Bass Synth")
  local mel = C.create_track("midi", "Melody", "Lead Synth")
  local aud = C.create_track("audio", "Loop")
  T.eq("4 owned tracks", #P.snap.tracks, 4)
  T.eq("REAPER track count (root+4)", r.CountTracks(0), 5)
  T.eq("root is folder parent", r.GetMediaTrackInfo_Value(P.snap.root, "I_FOLDERDEPTH"), 1)
  T.eq("last child closes folder", r.GetMediaTrackInfo_Value(P.snap.tracks[4].ptr, "I_FOLDERDEPTH"), -1)
  T.eq("drum kit voices (RS5k x6)", P.track(drums).inst_count, 6)
  T.eq("drum track fx count", r.TrackFX_GetCount(P.track(drums).ptr), 6)
  T.eq("synth track inst_count", P.track(bass).inst_count, 1)

  -- drum pattern (1 bar x 4 beats)
  local dc = C.create_clip(drums, 0, 4, "Beat")
  for b = 0, 3 do C.insert_note(dc, 36, b, b + 0.25, 110) end
  C.insert_note(dc, 38, 1, 1.25, 105) C.insert_note(dc, 38, 3, 3.25, 105)
  for h = 0, 7 do C.insert_note(dc, 42, h * 0.5, h * 0.5 + 0.2, 80) end
  T.eq("drum clip notes (4 kick+2 snare+8 hat)", note_count(dc), 14)
  -- bass
  local bc = C.create_clip(bass, 0, 4, "Bassline")
  for i, p in ipairs { 33, 33, 36, 38 } do C.insert_note(bc, p, i - 1, i - 0.1, 100) end
  T.eq("bass notes", note_count(bc), 4)
  -- melody on bar 2..
  local mc = C.create_clip(mel, 4, 4, "Hook")
  for i, p in ipairs { 69, 72, 76, 72 } do C.insert_note(mc, p, 4 + (i - 1), 4 + i - 0.2, 100) end
  -- duplicate drum + bass clips across 4 bars
  local d2 = C.duplicate_clip(dc, 4) local d3 = C.duplicate_clip(dc, 8) local d4 = C.duplicate_clip(dc, 12)
  local b2 = C.duplicate_clip(bc, 4) C.duplicate_clip(bc, 8) C.duplicate_clip(bc, 12)
  T.eq("duplicated clip keeps notes", note_count(d2), 14)
  T.check("duplicate has new GUID", d2 ~= dc and d3 ~= d2)
  local ok = pcall(C.duplicate_clip, dc, 4)
  T.check("overlapping duplicate rejected", not ok)
  C.duplicate_clip(mc, 12)
  T.eq("drum track has 4 clips", #P.track(drums).clips, 4)

  -- audio import, trim, move
  local loop = root .. "/examples/demo_loop.wav"
  local ac = C.import_audio(aud, loop, 0)
  local a = P.clip(ac)
  T.eq("audio clip is audio", a.kind, "audio")
  T.eq("audio length = 16 beats", a.len, 16, 0.01)
  T.check("audio source file recorded", (a.file or ""):find("demo_loop.wav") ~= nil, a.file)
  T.check("trim left", C.trim_clip_left(ac, 4))
  a = P.clip(ac)
  T.eq("trim: start=4", a.start, 4, 0.01) T.eq("trim: len=12", a.len, 12, 0.01)
  T.eq("trim: source offset 2s", a.offs, 2.0, 0.01)
  T.check("resize audio shorter", C.resize_clip(ac, 8))
  T.check("move audio", C.move_clip(ac, 8))
  T.eq("audio now at beat 8", P.clip(ac).start, 8, 0.01)
  local bad = pcall(C.import_audio, P.track(bass).id, loop, 0)
  T.check("audio import to MIDI track rejected", not bad)
  local bad2 = pcall(C.import_audio, aud, root .. "/README_missing.wav", 0)
  T.check("import of missing file rejected", not bad2)

  -- mixer
  C.set_volume(drums, 0.5) C.set_pan(bass, -0.5) C.set_mute(mel, true) C.set_solo(bass, true)
  T.eq("volume applied", r.GetMediaTrackInfo_Value(P.track(drums).ptr, "D_VOL"), 0.5)
  T.eq("pan applied", r.GetMediaTrackInfo_Value(P.track(bass).ptr, "D_PAN"), -0.5)
  T.eq("mute applied", r.GetMediaTrackInfo_Value(P.track(mel).ptr, "B_MUTE"), 1)
  T.check("solo applied", r.GetMediaTrackInfo_Value(P.track(bass).ptr, "I_SOLO") > 0)
  C.set_solo(bass, false) C.set_mute(mel, false)
  C.set_volume(drums, 0.3) C.set_volume(bass, 0.25) C.set_volume(mel, 0.2) C.set_volume(aud, 0.2) C.set_pan(mel, 0.3)

  -- effects
  local fxr = C.add_effect(mel, "reverb") local fxd = C.add_effect(bass, "delay") C.add_effect(drums, "eq")
  T.eq("reverb is after instrument", fxr, 1)
  local mt = P.track(mel)
  T.check("fx chain lists reverb", mt.fx[2] and mt.fx[2].plugin:find("ReaVerbate") ~= nil, mt.fx[2] and mt.fx[2].plugin)
  local ps = E.params(mt.ptr, 1)
  T.check("reverb exposes named params", #ps >= 3, #ps .. " params")
  local wet = ps[1]
  C.set_fx_param(mel, 1, wet.idx, 0.6)
  local after = E.params(P.track(mel).ptr, 1)[1]
  T.eq("fx param edit persisted", after.value, 0.6, 1e-4)
  C.toggle_fx(mel, 1) T.check("fx disabled", not r.TrackFX_GetEnabled(mt.ptr, 1)) C.toggle_fx(mel, 1)
  C.add_effect(mel, "delay")
  T.check("fx reorder", C.move_fx(mel, 2, -1))
  T.check("cannot move FX before the instrument", not C.move_fx(mel, 0, -1))
  C.remove_fx(mel, 1) T.eq("fx removed", r.TrackFX_GetCount(P.track(mel).ptr), 2)
  C.remove_fx(mel, 0) T.eq("instrument slot is protected", r.TrackFX_GetCount(P.track(mel).ptr), 2)
  C.add_effect(mel, "reverb") C.set_fx_param(mel, 2, E.params(P.track(mel).ptr, 2)[1].idx, 0.5)

  -- tempo: clips keep musical positions
  local before_t = P.clip(d3).time_pos
  C.set_bpm(90)
  P.refresh(true)
  T.eq("bpm applied", H.bpm(), 90)
  T.eq("clip musical start unchanged after bpm", P.clip(d3).start, 8, 0.001)
  T.eq("clip seconds scaled with tempo", P.clip(d3).time_pos, before_t * 120 / 90, 0.001)
  C.set_bpm(120) P.refresh(true)

  -- undo / redo
  local n0 = note_count(dc)
  C.insert_note(dc, 60, 2, 3, 100)
  T.eq("note added", note_count(dc), n0 + 1)
  C.undo() P.refresh(true)
  T.eq("undo removes note", note_count(P.clip(dc) and dc), n0)
  C.redo() P.refresh(true)
  T.eq("redo restores note", note_count(dc), n0 + 1)
  C.undo() P.refresh(true)
  -- gesture = one undo point
  local s0 = P.clip(mc).start
  C.begin_gesture("Move clip")
  for i = 1, 20 do C.move_clip(mc, s0 + 0.0 + (i % 2) * 0, nil) end
  C.move_clip(mc, 6) 
  C.end_gesture()
  T.eq("gesture applied", P.clip(mc).start, 6, 0.001)
  C.undo() P.refresh(true)
  T.eq("one undo reverts the whole drag", P.clip(mc).start, s0, 0.001)
  -- note ops
  local nn = P.notes(P.clip(bc))
  C.set_note(bc, nn[1].idx, { pitch = 40, s = nn[1].s + 0.5, e = nn[1].e }, false)
  P.refresh(true)
  local moved = P.notes(P.clip(bc))
  local found = false for _, n in ipairs(moved) do if n.pitch == 40 and math.abs(n.s - 0.5) < 0.001 then found = true end end
  T.check("note move/pitch edit", found)
  C.quantize_notes(bc, 1, false) P.refresh(true)
  local q = true for _, n in ipairs(P.notes(P.clip(bc))) do if math.abs(n.s - math.floor(n.s + 0.5)) > 1e-3 then q = false end end
  T.check("quantize snaps note starts to grid", q)
  -- clamp inside clip bounds
  local cb = C.insert_note(bc, 50, 3.9, 6, 100)
  local clamped = true for _, n in ipairs(P.notes(P.clip(bc))) do if n.e > 4.0001 then clamped = false end end
  T.check("note clamped to clip end", clamped)

  -- split
  local right = C.split_clip(d4, 14)
  T.check("split clip", right ~= nil and P.clip(right) ~= nil and P.clip(d4).len < 2.1)

  -- transport sanity
  local TR = require("audio.transport")
  TR.seek(4) T.eq("seek", TR.position(), 4, 0.01)
  TR.set_loop(0, 8) TR.set_loop_enabled(true)
  local ls, le = TR.loop() T.eq("loop start", ls, 0, 0.01) T.eq("loop end", le, 8, 0.01) T.check("loop enabled", TR.loop_enabled())
  TR.set_loop_enabled(false) TR.seek(0)

  -- idempotent re-run: ensure_root does not duplicate
  P.ensure_root() P.refresh(true)
  T.eq("ensure_root idempotent", r.CountTracks(0), 5)

  -- export + analysis
  local res = X.render { dir = OUT .. "/export", name = "engine_a", region = "project", tail_ms = 1000 }
  T.check("export ok", res.ok, res.err)
  if res.analysis then
    local a2 = res.analysis
    T.info(string.format("export: %s %.2fs peak=%.3f rms=%.3f sr=%d bits=%d", res.path, a2.secs, a2.peak, a2.rms, a2.sr, a2.bits))
    T.check("export non-silent and not clipping", a2.peak > 0.05 and a2.peak < 0.999, a2.peak)
    T.check("export duration >= 8s (16 beats@120)", a2.secs >= 8.0, a2.secs)
    T.check("export is 16-bit stereo 44.1k", a2.bits == 16 and a2.channels == 2 and a2.sr == 44100)
    local b = {} for i = 1, 8 do b[#b + 1] = string.format("%.2f", a2.buckets[i] or 0) end
    T.info("per-0.5s peaks: " .. table.concat(b, " "))
  end
  local clash = X.free_path(OUT .. "/export", "engine_a")
  T.check("export never overwrites (free_path)", clash:find("engine_a_2") ~= nil, clash)
  if res.analysis then local bb = {} for i = 1, 8 do bb[#bb+1] = string.format("%.2f", res.analysis.buckets[i] or 0) end T.info("buckets "..table.concat(bb," ")) end
  -- manifest + save
  local m = {}
  m[#m + 1] = "tracks=" .. #P.snap.tracks
  m[#m + 1] = "clips=" .. #P.snap.clips
  local total = 0
  for _, c in ipairs(P.snap.clips) do if c.kind == "midi" then total = total + #P.notes(c) end end
  m[#m + 1] = "notes=" .. total
  m[#m + 1] = "peak=" .. (res.analysis and res.analysis.peak or 0)
  m[#m + 1] = "rms=" .. (res.analysis and res.analysis.rms or 0)
  m[#m + 1] = "secs=" .. (res.analysis and res.analysis.secs or 0)
  local f = io.open(OUT .. "/engine_manifest.txt", "w") f:write(table.concat(m, "\n"), "\n") f:close()
  r.Main_SaveProjectEx(0, PROJ, 0)
  T.check("project saved", io.open(PROJ, "rb") ~= nil)
  T.finish()
end

local function verify()
  T.wait_until(12, function() return r.CountTracks(0) > 0 end, function()
    local man = {}
    for line in io.lines(OUT .. "/engine_manifest.txt") do local k, v = line:match("^(%w+)=(.*)$") man[k] = tonumber(v) end
    P.refresh(true)
    T.check("reopened: root recognised", P.snap.has_root and P.snap.name == "Test Song", P.snap.name)
    T.eq("reopened: tracks", #P.snap.tracks, man.tracks)
    T.eq("reopened: clips", #P.snap.clips, man.clips)
    local total = 0 for _, c in ipairs(P.snap.clips) do if c.kind == "midi" then total = total + #P.notes(c) end end
    T.eq("reopened: notes identical in count", total, man.notes)
    T.check("reopened: instruments present", P.snap.tracks[1].inst == "Drum Kit" and P.snap.tracks[1].inst_count == 6)
    T.check("reopened: fx chain restored", #P.snap.tracks[3].fx >= 3, #P.snap.tracks[3].fx)
    local aud = P.snap.tracks[4].clips[1]
    T.check("reopened: audio clip trimmed state", aud and aud.offs > 1.9 and aud.start == 8, aud and (aud.offs .. " @" .. aud.start))
    -- re-run semantics: setup again must not duplicate
    P.ensure_root() T.eq("rerun: no duplicate root", r.CountTracks(0), 5)
    local res = X.render { dir = OUT .. "/export", name = "engine_b", region = "project", tail_ms = 1000 }
    T.check("re-export ok", res.ok, res.err)
    if res.analysis then
      T.eq("re-export duration matches", res.analysis.secs, man.secs, 0.05)
      T.eq("re-export peak matches (+-2%)", res.analysis.peak, man.peak, man.peak * 0.02)
      T.eq("re-export rms matches (+-3%)", res.analysis.rms, man.rms, man.rms * 0.03)
    end
    T.finish()
  end)
end

T.run(function() if T.mode == "engine_build" then build() else verify() end end)
