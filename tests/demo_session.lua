-- demo_session.lua : composes a song through the REAL inner-DAW UI at "human" pace and records the app's own
-- framebuffer (no screen recorder). Audio comes from real renders of the project at each stage.
-- mode: demo    ->  out/demo/frames.txt (ffconcat), out/demo/stages.txt, out/demo/final.wav, out/demo/neon_drive.rpp
local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness") T.setup(root)
local D = require("ui_driver")
local TL = require("timeline")
local U = require("util")
local OUT = T.out
local DEMO = OUT .. "/demo"
os.execute('rm -rf "' .. DEMO .. '" && mkdir -p "' .. DEMO .. '/frames" "' .. DEMO .. '/stages"')

local A, P, C, S, G, X, TR
local frames, total_t, last_str = {}, 0, nil
local stages = {}
local cur = { x = 640, y = 400 }

----------------------------------------------------------------------------- recording
local function capture(dur)
  D.frames(1)
  local str = A.snapshot_str(1)
  if str == last_str and #frames > 0 then frames[#frames].dur = frames[#frames].dur + dur
  else
    local f = string.format("%s/frames/f%05d.ppm", DEMO, #frames + 1)
    local h = io.open(f, "wb") h:write(str) h:close()
    frames[#frames + 1] = { file = f, dur = dur }
    last_str = str
  end
  total_t = total_t + dur
end
local function hold(sec) local n = math.max(1, math.floor(sec / 0.25)) for _ = 1, n do capture(sec / n) end end
local function caption(text) A.overlay.caption = text end

local function glide(x, y, steps, dt)
  steps = steps or 6
  local sx, sy = cur.x, cur.y
  for i = 1, steps do
    local t = i / steps
    t = t * t * (3 - 2 * t) -- ease in/out
    cur.x, cur.y = sx + (x - sx) * t, sy + (y - sy) * t
    D.move(cur.x, cur.y) capture(dt or 0.05)
  end
end
local function click(x, y, btn, pause)
  glide(x, y, 5)
  D.press(btn) capture(0.08) D.release(btn) capture(pause or 0.14)
end
local function dblclick(x, y)
  glide(x, y, 5)
  D.press() D.release() D.press() D.release() -- real-time double click (<0.35 s)
  capture(0.25)
end
local function drag(x1, y1, x2, y2, steps)
  glide(x1, y1, 5)
  D.press() capture(0.1)
  steps = steps or 8
  for i = 1, steps do cur.x, cur.y = x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps D.move(cur.x, cur.y) capture(0.07) end
  D.release() capture(0.18)
end
local function key(k, mods, pause) D.key(k, mods) capture(pause or 0.15) end
local function click_id(id, btn, pause) local w = G.reg[id] click(w[1] + w[3] / 2, w[2] + w[4] / 2, btn, pause) end
local function click_popup(label) capture(0.3) click_id("popup:" .. label) end

----------------------------------------------------------------------------- geometry helpers (same math as production)
local R
local function refresh() P.refresh(true) end
local function lane_xy(ti, beat, dy)
  D.frames(1) R = A.R
  return TL.beat_to_x(S.arr.view, beat, R.arr_lanes[1]), R.arr_lanes[2] + (ti - 1) * S.arr.track_h - S.arr.scroll_y + (dy or S.arr.track_h * 0.65)
end
local function roll_xy(pitch, beat)
  D.frames(1) R = A.R
  local gr = R.roll_grid
  return TL.beat_to_x(S.roll.view, beat, gr[1]), TL.pitch_to_y(S.roll.pv, pitch, gr[2]) + S.roll.pv.row_h / 2
end
local function ensure_pitch_visible(p)
  for _ = 1, 40 do
    D.frames(1) R = A.R
    local rows = R.roll_grid[4] / S.roll.pv.row_h
    local lo, hi = S.roll.pv.top - rows + 2, S.roll.pv.top - 1
    if p >= lo and p <= hi then return end
    local gr = R.roll_grid
    D.wheel(gr[1] + 100, gr[2] + 50, p < lo and -120 or 120)
    capture(0.05)
  end
end
local function note(pitch, beat, pause)
  ensure_pitch_visible(pitch)
  local x, y = roll_xy(pitch, beat + 0.05)
  click(x, y, nil, pause or 0.12)
end

local function stage_render(name, beats)
  local res = X.render { dir = DEMO .. "/stages", name = name, region = { s = 0, e = beats }, tail_ms = 0, overwrite = true }
  stages[#stages + 1] = { wav = res.path, t = total_t, beats = beats, ok = res.ok }
  D.frames(1)
end

----------------------------------------------------------------------------- the song
local function part_a()
  D.start({ w = 1280, h = 800 })
  A, P, C, S, G = D.A, require("project"), require("commands"), require("ui.state"), D.G
  X, TR = require("audio.export"), require("audio.transport")
  A.overlay.cursor = true
  S.bottom_h = 330
  refresh()
  caption("DAW in DAW  -  a complete DAW running inside REAPER, in pure Lua")
  hold(2.6)

  -- project + tracks
  click_id("welcome_new", nil, 0.3)
  click_id("pname", nil, 0.3) D.key("backspace") capture(0.1) for ch in ("Neon Drive"):gmatch(".") do D.key(ch) end capture(0.4) D.key("enter") capture(0.3)
  caption("Real REAPER tracks, one folder, stable IDs") hold(0.6)
  local function add(label) click_id("addtrk", nil, 0.3) click_popup(label) refresh() hold(0.2) end
  add("Drum Kit (sampler)") add("Bass Synth") add("Lead Synth") add("Audio track")
  hold(0.5)

  -- drums
  caption("Draw MIDI with the mouse - every note is a real MIDI event")
  S.snap_idx = 4
  dblclick(lane_xy(1, 0.3)) refresh()
  local dclip = P.snap.tracks[1].clips[1]
  hold(0.4)
  for _, b in ipairs { 0, 1.5, 2 } do note(36, b) end
  for _, b in ipairs { 1, 3 } do note(38, b) end
  for i = 0, 7 do note(42, i * 0.5, 0.06) end
  hold(0.5)
  caption("Drag to move, drag the edge to resize, right-click deletes")
  ensure_pitch_visible(36)
  local x1, y1 = roll_xy(36, 1.6) local x2 = roll_xy(36, 1.85)
  drag(x1, y1, x2, y1, 5)
  hold(0.5)

  caption("Duplicate and arrange clips  (Cmd+D)")
  click(lane_xy(1, 0.3)) hold(0.2)
  for _ = 1, 7 do key("d", { cmd = true }, 0.18) end
  hold(0.5)
  stage_render("stage1_drums", 16)

  -- bass
  caption("Bass: new clip, stretch to 4 bars, write the line in the piano roll")
  dblclick(lane_xy(2, 0.3)) refresh()
  local ex, ey = lane_xy(2, 4 - 0.05)
  drag(ex, ey, (lane_xy(2, 16 - 0.01)), ey, 8) refresh()
  local bclip = P.snap.tracks[2].clips[1]
  dblclick(lane_xy(2, 8)) refresh()
  hold(0.3)
  for bar, root_note in ipairs { 33, 29, 36, 31 } do
    note(root_note, (bar - 1) * 4) note(root_note, (bar - 1) * 4 + 2.5)
  end
  hold(0.4)
  caption("Copy / paste clips across the arrangement")
  click(lane_xy(2, 1)) key("c", { cmd = true }) r.SetEditCurPos(r.TimeMap2_QNToTime(0, 16), true, false)
  key("v", { cmd = true }, 0.4)
  hold(0.4)
  stage_render("stage2_bass", 16)

  -- lead
  caption("Melody on a second instrument (Lead Synth preset of ReaSynth)")
  dblclick(lane_xy(3, 16.3)) refresh()
  local ex2, ey2 = lane_xy(3, 20 - 0.05)
  drag(ex2, ey2, (lane_xy(3, 32 - 0.01)), ey2, 8) refresh()
  dblclick(lane_xy(3, 24)) refresh()
  S.roll.note_len = 1
  local lclip = P.snap.tracks[3].clips[1]
  for _, m in ipairs { { 69, 0 }, { 72, 1 }, { 76, 2 }, { 74, 3 }, { 72, 4 }, { 69, 5 }, { 67, 6 }, { 65, 8 }, { 69, 9 }, { 72, 10 }, { 71, 12 }, { 67, 13 }, { 64, 14 }, { 62, 15 } } do
    note(m[1], 16 + m[2], 0.08)
  end
  hold(0.4)
  caption("Velocity lane: drag a bar to change how hard a note hits")
  R = A.R local vr = R.roll_vel
  local vx = TL.beat_to_x(S.roll.view, 16 + 4, vr[1]) + 2
  drag(vx, vr[2] + 8, vx, vr[2] + vr[4] - 18, 4)
  hold(0.4)

  -- audio
  caption("Import audio - decoded and drawn from the real file")
  key("home", nil, 0.2)
  click_id("import", nil, 0.5)
  click_id("lnkExamples", nil, 0.4) hold(0.3)
  local row = G.reg["row:demo_loop.wav"]
  dblclick(row[1] + row[3] / 2, row[2] + row[4] / 2) refresh()
  hold(0.5)
  caption("Trim, move and duplicate audio clips")
  local lx, ly = lane_xy(4, 0.05)
  drag(lx, ly, (lane_xy(4, 4)), ly, 8) refresh()
  drag((lane_xy(4, 8)), (select(2, lane_xy(4, 8))), (lane_xy(4, 4)), (select(2, lane_xy(4, 8))), 6) refresh()
  key("d", { cmd = true }, 0.4)
  hold(0.4)
  stage_render("stage3_full", 32)
end

local function part_b()
  -- mixer on the track headers
  caption("Mixer: volume, pan, mute, solo - all real track parameters")
  local function set_vol(tid, db)
    local w = G.reg["vol" .. tid]
    local t = (db + 60) / 72
    drag(w[1] + 3, w[2] + 9, w[1] + 2 + (w[3] - 4) * t, w[2] + 9, 5)
  end
  set_vol(P.snap.tracks[1].id, -9) set_vol(P.snap.tracks[2].id, -8) set_vol(P.snap.tracks[3].id, -12) set_vol(P.snap.tracks[4].id, -10)
  local pw = G.reg["pan" .. P.snap.tracks[3].id]
  drag(pw[1] + pw[3] / 2, pw[2] + 9, pw[1] + pw[3] * 0.8, pw[2] + 9, 4)
  click_id("mute" .. P.snap.tracks[2].id) hold(0.3) click_id("mute" .. P.snap.tracks[2].id)
  click_id("solo" .. P.snap.tracks[1].id) hold(0.3) click_id("solo" .. P.snap.tracks[1].id)
  click_id("tab_mixer", nil, 0.5)
  caption("Faders, pan and real peak meters")
  local fw = G.reg["mvol" .. P.snap.tracks[2].id]
  drag(fw[1] + 13, fw[2] + fw[4] * 0.45, fw[1] + 13, fw[2] + fw[4] * 0.38, 4)
  hold(0.6)

  -- effects
  caption("Effects: REAPER's own Reverb, Delay and EQ - add, reorder, edit")
  click(30, A.R.arr_headers[2] + 2 * S.arr.track_h + 10)
  click_id("tab_devices", nil, 0.4)
  click_id("addfx") click_popup("Reverb  (ReaVerbate)") refresh()
  D.frames(2)
  local slider
  for id, w in pairs(G.reg) do if id:match("^fxp1_") and id:match("_0$") then slider = w end end
  if slider then drag(slider[1] + 5, slider[2] + 10, slider[1] + slider[3] * 0.45, slider[2] + 10, 5) end
  hold(0.5)
  caption("Instrument parameters too: ReaSynth, edited live")
  click(A.R.content[1] + 80, A.R.content[2] + 32 + 11)
  D.frames(2)
  local E = require("audio.effects")
  for _, p in ipairs(E.params(P.snap.tracks[3].ptr, 0)) do
    if p.name == "Saw mix" then
      local sw = G.reg["fxp0_" .. p.idx]
      if sw then drag(sw[1] + 4, sw[2] + 10, sw[1] + sw[3] * 0.8, sw[2] + 10, 5) end
    end
  end
  hold(0.5)
  caption("Effects: REAPER's own Reverb, Delay and EQ - add, reorder, edit")
  click(30, A.R.arr_headers[2] + 1 * S.arr.track_h + 10)
  click_id("addfx") click_popup("Delay  (ReaDelay)") refresh() hold(0.4)
  click(30, A.R.arr_headers[2] + 0 * S.arr.track_h + 10)
  click_id("addfx") click_popup("EQ  (ReaEQ)") refresh() hold(0.4)
  click_id("tab_roll", nil, 0.4)

  -- loop + play
  caption("Drag the strip above the ruler to set a loop region")
  local rr = A.R.arr_ruler
  drag(TL.beat_to_x(S.arr.view, 0, rr[1]) + 1, rr[2] + 6, TL.beat_to_x(S.arr.view, 8, rr[1]), rr[2] + 6, 6)
  hold(0.4)
  click_id("loop", nil, 0.3) -- toggle loop off again so the whole song plays
  S.sel_clip = nil
  TR.set_loop_enabled(false)
  stage_render("stage4_final_mix", 32)
  -- final mix render to be used while the real transport plays
  local fin = X.render { dir = DEMO, name = "final", region = "project", tail_ms = 1500, overwrite = true }
  T.check("final mix render ok", fin.ok, fin.err)
  stages[#stages + 1] = { wav = fin.path, t = total_t, beats = 0, final = true }

  caption("Play: REAPER's own audio engine, driven from the inner transport")
  hold(0.5)
  glide(A.R.arr_lanes[1] + 500, A.R.arr_lanes[2] + 300, 6)   -- park the cursor away from tooltips
  key("home", nil, 0.2)
  key("space", nil, 0.1)
  stages[#stages + 1] = { wav = "", t = total_t, beats = 0, playstart = true }
  local t0 = r.time_precise()
  local last = t0
  T.poll(11.5, function()
    local now = r.time_precise()
    capture(now - last)
    last = now
  end, function() part_c() end)
end

function part_c()
  key("space", nil, 0.2)
  caption("Export WAV (Cmd+E): rendered by REAPER, then analysed for duration and level")
  hold(0.4)
  S.export.dir = DEMO .. "/export" S.export.name = "neon_drive_export"
  key("e", { cmd = true }, 0.6)
  click_id("ex_go", nil, 0.3)
  hold(2.2)
  local last = S.export.last
  T.check("demo export ok", last and last.ok, last and last.err)
  click_id("ex_close", nil, 0.3)
  caption("Save: the arrangement is a normal REAPER .rpp - tracks, items, notes, FX")
  S.browser.dir = DEMO
  click_id("save", nil, 0.4)
  click_id("sv_name", nil, 0.3) D.key("backspace") capture(0.1) for ch in ("neon_drive"):gmatch(".") do D.key(ch) end capture(0.4) D.key("enter") capture(0.3)
  click_id("sv_go", nil, 0.5)
  hold(1.0)
  caption("Every track, clip, note, fader and effect is a real REAPER object.  No extensions.  Pure Lua.")
  hold(3.2)
  caption(nil)
  hold(0.4)
  -- write metadata for the assembler
  local f = io.open(DEMO .. "/frames.txt", "w")
  f:write("ffconcat version 1.0\n")
  for _, fr in ipairs(frames) do f:write(string.format("file '%s'\nduration %.3f\n", fr.file:gsub("%.ppm$", ".png"), fr.dur)) end
  f:write(string.format("file '%s'\n", frames[#frames].file:gsub("%.ppm$", ".png")))
  f:close()
  local sf = io.open(DEMO .. "/stages.txt", "w")
  for _, st in ipairs(stages) do sf:write(string.format("%s %.3f %d %s\n", st.wav ~= "" and st.wav or "-", st.t, st.beats, st.playstart and "playstart" or (st.final and "final" or "stage"))) end
  sf:write(string.format("TOTAL %.3f %d frames\n", total_t, #frames))
  sf:close()
  T.info(string.format("recorded %d unique frames, %.1f s of video", #frames, total_t))
  D.stop()
  T.finish()
end

T.run(function() part_a() part_b() end)
