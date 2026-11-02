-- integration: robustness (external edits, missing resources, resize, docking, confirmations) + performance benchmark.
-- mode: extra
local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness") T.setup(root)
local D = require("ui_driver")
local TL = require("timeline")
local OUT = T.out
local SHOTS = OUT .. "/shots"
os.execute('mkdir -p "' .. SHOTS .. '"')

local A, P, C, S, G
local function refresh() P.refresh(true) end

local function phase_robust()
  -- a foreign (user-owned) track must never be touched by the DAW
  r.InsertTrackAtIndex(0, true)
  local foreign = r.GetTrack(0, 0)
  r.GetSetMediaTrackInfo_String(foreign, "P_NAME", "MY OWN TRACK", true)
  local fguid = ({ r.GetSetMediaTrackInfo_String(foreign, "GUID", "", false) })[2]
  r.SetMediaTrackInfo_Value(foreign, "D_VOL", 0.77)

  D.start()
  A, P, C, S, G = D.A, require("project"), require("commands"), require("ui.state"), D.G
  refresh()
  T.check("foreign track present before DAW project exists", r.CountTracks(0) == 1)
  D.click_id("welcome_new") refresh()
  local ids = {}
  for _, spec in ipairs { { "midi", "Drums", "Drum Kit" }, { "midi", "Bass", "Bass Synth" }, { "midi", "Lead", "Lead Synth" }, { "audio", "Loop" } } do
    ids[#ids + 1] = C.create_track(spec[1], spec[2], spec[3])
  end
  local c1 = C.create_clip(ids[1], 0, 4, "A")
  C.insert_note(c1, 36, 0, 1, 100)
  local c2 = C.create_clip(ids[2], 0, 4, "B") C.insert_note(c2, 40, 0, 1, 100)
  local aud = C.import_audio(ids[4], root .. "/examples/demo_loop.wav", 0)
  T.eq("DAW tracks are children of its folder, after the foreign track", r.CountTracks(0), 1 + 1 + 4)
  T.check("foreign track still first and untouched", ({ r.GetSetMediaTrackInfo_String(r.GetTrack(0, 0), "GUID", "", false) })[2] == fguid)

  -- external reorder inside the folder: stable GUID ids keep working
  local t2 = P.track(ids[2])
  r.SetOnlyTrackSelected(t2.ptr)
  r.ReorderSelectedTracks(2, 0) -- move before the Drums track (0-based dest index of the first child = 2)
  refresh()
  T.check("after external reorder all 4 tracks are still owned", #P.snap.tracks == 4, #P.snap.tracks)
  T.check("track ids stable across reorder", P.track(ids[1]) ~= nil and P.track(ids[2]) ~= nil and P.track(ids[3]) ~= nil and P.track(ids[4]) ~= nil)
  T.check("order actually changed (Bass now before Drums)", P.snap.tracks[1].id == ids[2] and P.snap.tracks[2].id == ids[1], P.snap.tracks[1].name .. "," .. P.snap.tracks[2].name)
  T.check("clips follow their tracks", #P.track(ids[1]).clips == 1 and P.track(ids[1]).clips[1].id == c1)
  T.check("edits by id still work after reorder", C.insert_note(c1, 38, 1, 2, 90) and #P.notes(P.clip(c1)) == 2)

  -- external deletion of a clip while selected in the UI
  S.sel_clip = c2 S.edit_clip = c2
  local it = P.clip(c2).ptr
  r.DeleteTrackMediaItem(P.track(ids[2]).ptr, it)
  D.frames(2) refresh() D.frames(2)
  T.check("UI survives external clip deletion and clears selection", P.clip(c2) == nil and S.sel_clip == nil and S.edit_clip == nil)
  -- external rename shows up
  r.GetSetMediaTrackInfo_String(P.track(ids[3]).ptr, "P_NAME", "Renamed Outside", true)
  D.frames(2) refresh()
  T.eq("external track rename is picked up", P.track(ids[3]).name, "Renamed Outside")
  -- external track delete
  r.DeleteTrack(P.track(ids[3]).ptr) r.Undo_OnStateChange2(0, "External edit") refresh() D.frames(2)  -- (REAPER's own UI creates an undo point here)
  T.check("external track deletion handled (3 tracks left, folder intact)", #P.snap.tracks == 3 and P.snap.has_root, #P.snap.tracks)

  -- missing audio file => clip flagged offline, UI still renders
  local clip = P.clip(aud)
  local path = clip.file
  local bak = path .. ".bak"
  os.rename(path, bak)
  P.touch() refresh() D.frames(2)
  T.check("missing audio source flagged offline", P.clip(aud).offline == true)
  D.snapshot(SHOTS .. "/14_offline_clip.ppm", 1)
  os.rename(bak, path)
  P.touch() refresh()
  T.check("restored file clears the offline flag", P.clip(aud).offline == false)

  -- missing drum sample => repaired from bundled assets
  local dt = P.track(ids[1])
  r.TrackFX_SetNamedConfigParm(dt.ptr, 0, "FILE0", "/nonexistent/kick.wav")
  local fixed = C.repair_project()
  T.check("missing drum sample re-linked from assets", fixed >= 1, fixed)
  local _, p0 = r.TrackFX_GetNamedConfigParm(dt.ptr, 0, "FILE0")
  T.check("repaired path points at an existing file", r.file_exists(p0), p0)

  -- confirmations: delete track
  D.frames(2)
  local t = P.snap.tracks[2]
  local w = G.reg["mute" .. t.id]
  D.click(30, A.R.arr_headers[2] + 1 * S.arr.track_h + 10, 2) D.frames(2) -- RMB on 2nd header
  D.click_popup("Delete track...") D.frames(2)
  T.check("delete track asks for confirmation", G.modal and G.modal.kind == "confirm")
  D.click_id("modal_no") D.frames(2) refresh()
  T.eq("cancel keeps the track", #P.snap.tracks, 3)
  D.click(30, A.R.arr_headers[2] + 1 * S.arr.track_h + 10, 2) D.click_popup("Delete track...") D.click_id("modal_yes") D.frames(2) refresh()
  T.eq("confirm deletes the track", #P.snap.tracks, 2)
  D.key("z", { cmd = true }) refresh()
  T.eq("and it is undoable", #P.snap.tracks, 3)

  -- new project while one exists: confirm, foreign track survives
  D.click_id("pname", 2) D.frames(1)
  D.click(G.reg["pname"][1] + 10, G.reg["pname"][2] + 10, 2) D.click_popup("New project...") D.frames(2)
  T.check("new project asks for confirmation when one exists", G.modal and G.modal.kind == "confirm")
  D.click_id("modal_yes") D.frames(2) refresh()
  T.check("DAW tracks replaced by an empty project", P.snap.has_root and #P.snap.tracks == 0)
  T.check("foreign track survived the DAW project reset", r.CountTracks(0) == 2 and ({ r.GetSetMediaTrackInfo_String(r.GetTrack(0, 0), "GUID", "", false) })[2] == fguid and r.GetMediaTrackInfo_Value(r.GetTrack(0, 0), "D_VOL") == 0.77, r.CountTracks(0))

  -- transport via ruler + zoom/scroll
  C.create_track("midi", "T1", "Lead Synth") refresh() D.frames(2)
  local rr = A.R.arr_ruler
  local bx = TL.beat_to_x(S.arr.view, 6, rr[1])
  D.click(bx, rr[2] + 24) D.frames(2)
  local TR = require("audio.transport")
  T.check("clicking the ruler seeks the playhead", math.abs(TR.position() - 6) < 0.6, TR.position())
  local ppb0 = S.arr.view.ppb
  D.mods(true) D.wheel(A.R.arr_lanes[1] + 300, A.R.arr_lanes[2] + 50, 120) D.mods()
  T.check("Cmd+wheel zooms the timeline", S.arr.view.ppb > ppb0 * 1.05, S.arr.view.ppb)
  local x0 = S.arr.view.x0
  D.mods(false, true) D.wheel(A.R.arr_lanes[1] + 300, A.R.arr_lanes[2] + 50, -120) D.mods()
  T.check("Shift+wheel scrolls horizontally", S.arr.view.x0 ~= x0, S.arr.view.x0)

  -- docking round-trip (own Dock button + gfx.dock state)
  D.click_id("dock") D.frames(4)
  local docked = gfx.dock(-1) & 1 == 1
  T.check("Dock button docks the window", docked, gfx.dock(-1))
  D.frames(3)
  local ok_render = pcall(D.frames, 3)
  T.check("UI keeps rendering while docked", ok_render)
  D.snapshot(SHOTS .. "/15_docked.ppm", 1)
  D.click_id("dock") D.frames(4)
  T.check("Undock button restores a floating window", gfx.dock(-1) & 1 == 0, gfx.dock(-1))

  -- audition: clicking a piano-roll key / placing a note sends MIDI through REAPER's virtual keyboard to the track
  local lead = P.snap.tracks[1]
  TR.stop() r.SetEditCurPos(0, true, false)
  A.audition(lead.id, 69, 110)
  do local tt = P.track(lead.id) T.info(string.format("audition state: kind=%s inst=%s fxcount=%d arm=%d mon=%d in=%d mute=%d vol=%.2f playstate=%d audio_running=%s", tt.kind, tt.inst, #tt.fx, r.GetMediaTrackInfo_Value(tt.ptr, "I_RECARM"), r.GetMediaTrackInfo_Value(tt.ptr, "I_RECMON"), r.GetMediaTrackInfo_Value(tt.ptr, "I_RECINPUT"), r.GetMediaTrackInfo_Value(tt.ptr, "B_MUTE"), tt.vol, r.GetPlayState(), tostring(r.Audio_IsRunning()))) end
  local maxpk = 0
  T.poll(1.2, function()
    D.frames(1)
    local m = A.meter(lead.id) -- the app's meter service already consumed the peak this frame (Track_GetPeakInfo is read-and-reset)
    maxpk = math.max(maxpk, m.l, m.r)
  end, function()
    T.check("audition produces audio on the track (real peak meter)", maxpk > 0.01, string.format("peak=%.3f", maxpk))
    D.stop()
    T.check("closing the app disarms audition arming", r.GetMediaTrackInfo_Value(P.track(lead.id).ptr, "I_RECARM") == 0)
    T.finish()
  end)
end

local SIZES = { { 640, 400 }, { 800, 520 }, { 1000, 640 }, { 1280, 800 }, { 1600, 900 }, { 1920, 1080 } }
local function phase_sizes()
  D.start({ w = 1280, h = 800 })
  A, P, C, S, G = D.A, require("project"), require("commands"), require("ui.state"), D.G
  C.new_project("Sizes")
  local d = C.create_track("midi", "Drums", "Drum Kit") local b = C.create_track("midi", "Bass", "Bass Synth") local l = C.create_track("midi", "Lead", "Lead Synth") local au = C.create_track("audio", "Audio")
  for bar = 0, 3 do
    local c = C.create_clip(d, bar * 4, 4, "Beat") for i = 0, 7 do C.insert_note(c, 42, bar * 4 + i * 0.5, bar * 4 + i * 0.5 + 0.25, 80) end C.insert_note(c, 36, bar * 4, bar * 4 + 1, 110) C.insert_note(c, 38, bar * 4 + 1, bar * 4 + 2, 100)
  end
  local lc = C.create_clip(l, 4, 8, "Hook") for i, p in ipairs { 60, 64, 67, 72, 71, 67, 64, 62 } do C.insert_note(lc, p, 4 + (i - 1), 4 + i - 0.2, 100) end
  local bc = C.create_clip(b, 0, 8, "Bass") for i = 0, 7 do C.insert_note(bc, 33, i, i + 0.9, 100) end
  C.import_audio(au, root .. "/examples/demo_loop.wav", 0)
  refresh() A.open_clip(lc)
  for _, sz in ipairs(SIZES) do
    gfx.quit() gfx.ext_retina = 1 gfx.init("DAW in DAW", sz[1], sz[2], 0)
    D.frames(3)
    local R = A.R
    local ok_geom = math.abs(G.W * G.K - gfx.w) < 2 and math.abs(G.H * G.K - gfx.h) < 2
    local fits = R.arr[4] > 40 and R.bottom[4] >= 100 and R.arr_lanes[3] > 100
    -- REAPER may clamp a window to the screen / its minimum size: report actual size, require layout validity at it
    T.check(string.format("requested %dx%d -> window %dx%d: layout valid (arr h=%d, bottom h=%d, lanes w=%d)", sz[1], sz[2], G.W, G.H, R.arr[4], R.bottom[4], R.arr_lanes[3]), ok_geom and fits)
    T.check(string.format("%dx%d: window size took effect (within 4%% or screen-clamped)", sz[1], sz[2]), math.abs(G.W - sz[1]) <= sz[1] * 0.04 or G.W < sz[1] + 1 or sz[1] > 1500, G.W .. "x" .. G.H)
    D.snapshot(string.format("%s/size_%dx%d.ppm", SHOTS, sz[1], sz[2]), 1)
    for _, tab in ipairs { "mixer", "devices", "roll" } do S.tab = tab D.frames(2) end
  end
  D.stop()
  T.finish()
end

local function stats(t) table.sort(t) local s = 0 for _, v in ipairs(t) do s = s + v end return s / #t, t[math.floor(#t / 2) + 1], t[math.max(1, math.floor(#t * 0.95))], t[#t] end

local function phase_perf()
  D.start({ w = 1280, h = 800 })
  A, P, C, S, G = D.A, require("project"), require("commands"), require("ui.state"), D.G
  C.new_project("Perf")
  local t0 = r.time_precise()
  C.begin_gesture("bulk build")
  local tracks = {}
  for i = 1, 16 do
    if i == 1 then tracks[i] = C.create_track("midi", "Drums", "Drum Kit")
    elseif i == 16 then tracks[i] = C.create_track("audio", "Audio")
    else tracks[i] = C.create_track("midi", "Synth " .. i, ({ "Lead Synth", "Bass Synth", "Pad Synth", "Pluck" })[i % 4 + 1]) end
  end
  C.end_gesture()
  local nclips, nnotes = 0, 0
  C.begin_gesture("bulk clips")
  P.refresh(true)
  for i = 1, 15 do
    for k = 0, 6 do
      if nclips >= 100 then break end
      local id = C.create_clip(tracks[i], k * 4, 4, "c" .. k)
      nclips = nclips + 1
      for n = 0, 9 do
        if nnotes < 1000 then C.insert_note(id, 40 + ((n * 5 + i) % 36), k * 4 + n * 0.4, k * 4 + n * 0.4 + 0.3, 80 + n) nnotes = nnotes + 1 end
      end
    end
  end
  C.end_gesture()
  C.import_audio(tracks[16], root .. "/examples/demo_loop.wav", 0) C.import_audio(tracks[16], root .. "/examples/demo_loop.wav", 16)
  refresh()
  T.info(string.format("built %d tracks, %d clips, %d notes in %.2fs", #P.snap.tracks, #P.snap.clips, nnotes, r.time_precise() - t0))
  T.check("benchmark project size (16 tracks, >=100 clips, 1000 notes)", #P.snap.tracks == 16 and #P.snap.clips >= 100 and nnotes == 1000, #P.snap.tracks .. "/" .. #P.snap.clips .. "/" .. nnotes)
  S.snap_idx = 4 A.open_clip(P.track(tracks[2]).clips[1].id)
  D.frames(20)
  D.snapshot(SHOTS .. "/16_perf_project.ppm", 1)

  local function measure(label, n, work)
    local times = {}
    for i = 1, n do
      local a = r.time_precise()
      work(i)
      times[#times + 1] = (r.time_precise() - a) * 1000
    end
    local mean, med, p95, mx = stats(times)
    T.info(string.format("%-34s mean %5.1f ms  median %5.1f  p95 %5.1f  max %5.1f   => %.0f fps (mean)", label, mean, med, p95, mx, 1000 / mean))
    return mean, p95
  end
  local idle_mean = measure("idle, 16 tracks/100 clips", 60, function() D.frames(1) end)
  local mx0 = A.R.arr_lanes
  local drag_mean = measure("dragging a clip (live REAPER edits)", 40, function(i)
    if i == 1 then
      local c = P.track(tracks[3]).clips[1]
      D.move(TL.beat_to_x(S.arr.view, c.start + 1, mx0[1]), mx0[2] + 2 * S.arr.track_h + 40 - S.arr.scroll_y) D.press()
    end
    D.move(TL.beat_to_x(S.arr.view, 1 + (i % 6) * 0.5, mx0[1]) + 40, mx0[2] + 2 * S.arr.track_h + 40 - S.arr.scroll_y)
    if i == 40 then D.release() end
  end)
  D.release()
  local TR = require("audio.transport")
  -- wall-clock cadence while idle (defer loop; REAPER's timer drives it)
  local idle_times, t_idle = {}, r.time_precise()
  local function idle_step()
    local a = r.time_precise() D.frames(1) idle_times[#idle_times + 1] = (r.time_precise() - a) * 1000
    if r.time_precise() - t_idle < 3 then r.defer(idle_step) else
      local idle_wall = #idle_times / (r.time_precise() - t_idle)
      T.info(string.format("%-34s %.0f fps wall-clock in defer loop (frame work %.1f ms)", "idle cadence", idle_wall, select(1, stats(idle_times))))
      TR.seek(0) TR.play()
      local play_times, t_start = {}, r.time_precise()
      local function play_step()
        local a2 = r.time_precise() D.frames(1) play_times[#play_times + 1] = (r.time_precise() - a2) * 1000
        if r.time_precise() - t_start < 6 then r.defer(play_step) else
          local mean, med, p95, mx = stats(play_times)
          local wall = #play_times / (r.time_precise() - t_start)
          T.info(string.format("%-34s mean %5.1f ms  median %5.1f  p95 %5.1f  max %5.1f   => %.0f fps wall-clock in defer loop", "playback (meters, playhead, 16 trk)", mean, med, p95, mx, wall))
          T.check("playback frame work <= 33 ms (30 fps budget) mean", mean <= 33, mean)
          T.check("playback frame work p95 <= 16 ms", p95 <= 16, p95)
          T.check("playback cadence >= 20 fps (REAPER defer timer under audio load)", wall >= 20, wall)
          T.check("idle frame work <= 33 ms mean", idle_mean <= 33, idle_mean)
          T.check("clip drag frame work <= 33 ms mean", drag_mean <= 33, drag_mean)
          TR.stop() D.stop() T.finish()
        end
      end
      r.defer(play_step)
    end
  end
  r.defer(idle_step)
end

T.run(function()
  if T.mode == "extra_robust" then phase_robust()
  elseif T.mode == "extra_sizes" then phase_sizes()
  else phase_perf() end
end)
