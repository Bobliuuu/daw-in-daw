-- integration: complete song workflow through the REAL UI frame loop (synthetic mouse/keyboard events).
-- modes: ui_build (compose + save + export)  /  ui_verify (reopen in fresh REAPER, resume editing, re-export)
local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness") T.setup(root)
local D = require("ui_driver")
local TL = require("timeline")
local OUT = T.out
local SHOTS = OUT .. "/shots"
os.execute('mkdir -p "' .. SHOTS .. '"')

local A, P, C, S, G, R
local function refresh() P.refresh(true) R = require("ui.layout").compute(G.W, G.H, S) end
local function shot(name) D.snapshot(SHOTS .. "/" .. name .. ".ppm", 1) end

-- ---------- coordinate helpers (production layout math) ----------
local function lane_xy(ti, beat, dy)
  D.frames(1) R = A.R
  local v = S.arr.view
  local x = TL.beat_to_x(v, beat, R.arr_lanes[1])
  local y = R.arr_lanes[2] + (ti - 1) * S.arr.track_h - S.arr.scroll_y + (dy or S.arr.track_h * 0.65)
  return x, y
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
  end
end
local function note_at(clip_id, pitch, start)
  for _, n in ipairs(P.notes(P.clip(clip_id))) do if n.pitch == pitch and math.abs(n.s - start) < 0.01 then return n end end
end
local function click_note(clip_id, pitch, beat)
  ensure_pitch_visible(pitch)
  local x, y = roll_xy(pitch, beat + 0.05)
  D.click(x, y)
end
local function track_by_name(n) for _, t in ipairs(P.snap.tracks) do if t.name == n then return t end end end
local function click_tab(name) D.click_id("tab_" .. name) end

local build_part2
local function build()
  D.start()
  A, P, C, S, G = D.A, require("project"), require("commands"), require("ui.state"), D.G
  S.bottom_h = 330
  refresh()
  T.check("welcome shown when no project", not P.snap.has_root)
  shot("01_welcome")

  -- 1-2. new project
  D.click_id("welcome_new") refresh()
  T.check("1 new project created via UI", P.snap.has_root and P.snap.name == "Untitled")
  D.click_id("pname") D.frames(2)
  T.check("rename prompt opens", G.modal ~= nil and G.modal.kind == "prompt")
  D.key("backspace") D.type("Neon Drive") D.key("enter") refresh()
  T.eq("project renamed through prompt", P.snap.name, "Neon Drive")

  -- 3-5. tracks
  local function add(label) D.click_id("addtrk") D.click_popup(label) refresh() end
  add("Drum Kit (sampler)") add("Bass Synth") add("Lead Synth") add("Audio track")
  T.eq("4 tracks created via menu", #P.snap.tracks, 4)
  T.eq("track kinds", P.snap.tracks[1].kind .. P.snap.tracks[2].kind .. P.snap.tracks[3].kind .. P.snap.tracks[4].kind, "midimidimidiaudio")
  T.eq("drum kit = 6 sampler voices", P.snap.tracks[1].inst_count, 6)
  local drums, bass, lead, aud = P.snap.tracks[1], P.snap.tracks[2], P.snap.tracks[3], P.snap.tracks[4]

  -- zoom so 8 bars (32 beats) fit: use the zoom buttons
  D.click_id("zout") D.click_id("zin") S.arr.view.x0 = 0  -- exercise zoom buttons, then scroll back to bar 1
  refresh()

  -- 6-7. drum clip + pattern (double-click lane creates a 1-bar clip and opens the piano roll)
  local x, y = lane_xy(1, 0.3)
  D.dblclick(x, y) refresh()
  drums = P.snap.tracks[1]
  T.eq("6 drum clip created by double-click", #drums.clips, 1)
  local dclip = drums.clips[1]
  T.check("clip opened in piano roll", S.edit_clip == dclip.id and S.tab == "roll")
  shot("02_empty_clip")
  S.snap_idx = 4 -- 1/16
  -- kick on 0, 1.5, 2 ; snare 1, 3 ; hats every half beat
  local function note(p, b) click_note(dclip.id, p, b) end
  for _, b in ipairs { 0, 1.5, 2 } do note(36, b) end
  for _, b in ipairs { 1, 3 } do note(38, b) end
  for i = 0, 7 do note(42, i * 0.5) end
  refresh()
  T.eq("7 drum pattern drawn with mouse clicks (13 notes)", #P.notes(P.clip(dclip.id)), 13)
  shot("03_drum_pattern")
  -- edit: drag a hat up an octave? no - move kick at 1.5 to 1.75 (drag), shorten snare (resize), delete a hat (RMB), velocity
  ensure_pitch_visible(36)
  local x1, y1 = roll_xy(36, 1.5 + 0.1)
  local x2 = roll_xy(36, 1.75 + 0.1)
  D.drag(x1, y1, x2, y1)
  refresh()
  T.check("note moved by dragging", note_at(dclip.id, 36, 1.75) ~= nil and note_at(dclip.id, 36, 1.5) == nil)
  T.check("whole drag = one undo step", (function() local u = r.Undo_CanUndo2(0) return u == "Move notes" end)(), r.Undo_CanUndo2(0))
  local sx, sy = roll_xy(38, 1.5 - 0.02)   -- right edge of the snare at 1..1.5
  D.drag(sx, sy, sx - (0.25 * S.roll.view.ppb), sy)
  refresh()
  local sn = note_at(dclip.id, 38, 1)
  T.check("note resized by dragging right edge", sn and math.abs((sn.e - sn.s) - 0.25) < 0.01, sn and (sn.e - sn.s))
  local hx, hy = roll_xy(42, 3.5 + 0.1)
  ensure_pitch_visible(42)
  hx, hy = roll_xy(42, 3.5 + 0.1)
  D.click(hx, hy, 2) refresh()
  T.check("note deleted by right-click", note_at(dclip.id, 42, 3.5) == nil and #P.notes(P.clip(dclip.id)) == 12)
  D.click(hx, hy) refresh() -- re-add it
  T.eq("re-added", #P.notes(P.clip(dclip.id)), 13)
  -- velocity lane: lower the velocity of hat at beat 0.5
  R = A.R
  local vr = R.roll_vel
  local vx = TL.beat_to_x(S.roll.view, 0.5, vr[1]) + 2
  D.drag(vx, vr[2] + 6, vx, vr[2] + vr[4] - 14)
  refresh()
  local hv = note_at(dclip.id, 42, 0.5)
  T.check("velocity edited in velocity lane", hv and hv.vel < 70, hv and hv.vel)
  -- marquee select + transpose then undo
  local mx0, my0 = roll_xy(44, -0.1)
  D.mods(false, true, false) -- shift
  local gr = A.R.roll_grid
  D.drag(gr[1] + 5, my0 - 40, gr[1] + 5 + 6 * S.roll.view.ppb, my0 + 120)
  D.mods()
  refresh()
  local nsel = 0 for _, n in ipairs(P.notes(P.clip(dclip.id))) do if n.sel then nsel = nsel + 1 end end
  T.check("shift-drag marquee selects notes", nsel > 0, nsel)
  local before = {} for _, n in ipairs(P.notes(P.clip(dclip.id))) do before[#before + 1] = n.pitch end
  D.key("up") refresh()
  local moved = 0 for i, n in ipairs(P.notes(P.clip(dclip.id))) do if n.pitch == before[i] + 1 then moved = moved + 1 end end
  T.eq("arrow key transposes the selection", moved, nsel)
  D.key("z", { cmd = true }) refresh()
  local same = true for i, n in ipairs(P.notes(P.clip(dclip.id))) do if n.pitch ~= before[i] then same = false end end
  T.check("Cmd+Z undoes transpose", same)
  D.key("z", { cmd = true, shift = true }) refresh()
  D.key("z", { cmd = true }) refresh()
  -- quantize check not needed here

  -- arrangement: duplicate drum clip across bars 2..8 (Cmd+D)
  D.click(lane_xy(1, 0.3))
  refresh()
  T.check("clip selected by click", S.sel_clip == dclip.id)
  for _ = 1, 7 do D.key("d", { cmd = true }) end
  refresh()
  T.eq("7 duplicates via Cmd+D => 8 drum clips", #P.snap.tracks[1].clips, 8)
  shot("04_drums_arranged")

  -- 8-9. bass clip: create, stretch to 4 bars by dragging the right edge, write notes
  x, y = lane_xy(2, 0.3)
  D.dblclick(x, y) refresh()
  bass = P.snap.tracks[2]
  local bclip = bass.clips[1]
  local ex, ey = lane_xy(2, 4 - 0.05)
  local nx = lane_xy(2, 16 - 0.01)
  D.drag(ex, ey, nx, ey) refresh()
  bclip = P.snap.tracks[2].clips[1]
  T.check("clip resized by dragging its edge (4 bars)", math.abs(bclip.len - 16) < 0.01, bclip.len)
  D.dblclick(lane_xy(2, 8)) refresh() -- open in roll
  T.check("double-click opens clip in piano roll", S.edit_clip == bclip.id)
  local roots = { 33, 29, 36, 31 } -- A F C G
  for bar = 0, 3 do
    click_note(bclip.id, roots[bar + 1], bar * 4)
    click_note(bclip.id, roots[bar + 1], bar * 4 + 2.5)
  end
  refresh()
  T.eq("9 bassline notes", #P.notes(P.clip(bclip.id)), 8)
  -- copy/paste bass clip (Cmd+C / Cmd+V) to bars 5-8
  D.click(lane_xy(2, 1)) D.key("c", { cmd = true })
  D.frames(1)
  r.SetEditCurPos(r.TimeMap2_QNToTime(0, 16), true, false) refresh()
  D.key("v", { cmd = true }) refresh()
  T.eq("copy+paste produced second bass clip", #P.snap.tracks[2].clips, 2)
  shot("05_bass")

  -- 10. melody on lead track, bars 5-8
  x, y = lane_xy(3, 16.3)
  D.dblclick(x, y) refresh()
  lead = P.snap.tracks[3]
  local lclip = lead.clips[1]
  T.check("lead clip at bar 5", math.abs(lclip.start - 16) < 0.01, lclip.start)
  local ex2, ey2 = lane_xy(3, 20 - 0.05)
  D.drag(ex2, ey2, (lane_xy(3, 32 - 0.01)), ey2) refresh()
  lclip = P.snap.tracks[3].clips[1]
  T.check("lead clip resized to 4 bars", math.abs(lclip.len - 16) < 0.01, lclip.len)
  D.dblclick(lane_xy(3, 24)) refresh()
  S.roll.note_len = 1
  local mel = { { 69, 0 }, { 72, 1 }, { 76, 2 }, { 74, 3 }, { 72, 4 }, { 69, 5 }, { 67, 6 }, { 65, 8 }, { 69, 9 }, { 72, 10 }, { 71, 12 }, { 67, 13 }, { 64, 14 }, { 62, 15 } }
  for _, m in ipairs(mel) do click_note(lclip.id, m[1], 16 + m[2]) end
  refresh()
  T.eq("10 melody drawn", #P.notes(P.clip(lclip.id)), #mel)
  shot("06_melody")

  -- 11-13. audio: import through the in-app file browser, trim, move
  D.key("home") D.click_id("import") D.frames(2)
  T.check("import dialog opens", G.modal and G.modal.kind == "dialog")
  -- navigate: Examples quick link, then double-click demo_loop.wav
  D.click_id("lnkExamples") D.frames(2)
  local row = G.reg["row:demo_loop.wav"]
  T.check("file browser lists demo_loop.wav", row ~= nil)
  shot("07a_import_dialog")
  D.dblclick(row[1] + row[3] / 2, row[2] + row[4] / 2) refresh()
  aud = P.snap.tracks[4]
  T.eq("12 audio imported (clip on audio track)", #aud.clips, 1)
  local aclip = aud.clips[1]
  T.check("audio clip is real media (source file + 16 beats)", aclip.kind == "audio" and aclip.file:find("demo_loop") and math.abs(aclip.len - 16) < 0.05, aclip.len)
  shot("07_audio")
  -- trim: drag left edge forward by 1 bar; then move back to bar 1
  local lx, ly = lane_xy(4, 0.0 + 0.05)
  D.drag(lx, ly, (lane_xy(4, 4.0)), ly) refresh()
  aclip = P.snap.tracks[4].clips[1]
  T.check("13 audio trimmed from the left (offset > 0)", aclip.offs > 1.5 and math.abs(aclip.start - 4) < 0.01, string.format("offs=%.2f start=%.2f", aclip.offs, aclip.start))
  D.drag(lane_xy(4, 8), (select(2, lane_xy(4, 8))), (lane_xy(4, 4)), (select(2, lane_xy(4, 8)))) refresh()
  aclip = P.snap.tracks[4].clips[1]
  T.check("audio moved by dragging", math.abs(aclip.start - 0) < 0.01 or aclip.start < 4, aclip.start)
  -- resize audio right edge back and duplicate
  D.key("d", { cmd = true }) refresh()
  T.check("audio clip duplicated", #P.snap.tracks[4].clips == 2, #P.snap.tracks[4].clips)

  -- 14-15. mixer on headers: volume, pan, mute, solo
  local function set_vol(tid, db)
    local w = G.reg["vol" .. tid]
    local t = (db + 60) / 72
    D.drag(w[1] + 3, w[2] + 9, w[1] + 2 + (w[3] - 4) * t, w[2] + 9, 4)
  end
  D.frames(2)
  set_vol(P.snap.tracks[1].id, -9) set_vol(P.snap.tracks[2].id, -8) set_vol(P.snap.tracks[3].id, -12) set_vol(P.snap.tracks[4].id, -10)
  refresh()
  T.check("14 header volume slider changes real track volume", math.abs(r.GetMediaTrackInfo_Value(P.snap.tracks[1].ptr, "D_VOL") - 10 ^ (-9 / 20)) < 0.03, r.GetMediaTrackInfo_Value(P.snap.tracks[1].ptr, "D_VOL"))
  local pw = G.reg["pan" .. P.snap.tracks[3].id]
  D.drag(pw[1] + pw[3] / 2, pw[2] + 9, pw[1] + pw[3] * 0.75, pw[2] + 9, 3) refresh()
  T.check("pan slider changes real pan", r.GetMediaTrackInfo_Value(P.snap.tracks[3].ptr, "D_PAN") > 0.2, r.GetMediaTrackInfo_Value(P.snap.tracks[3].ptr, "D_PAN"))
  D.click_id("mute" .. P.snap.tracks[2].id) refresh()
  T.check("15 mute button mutes real track", r.GetMediaTrackInfo_Value(P.snap.tracks[2].ptr, "B_MUTE") == 1)
  D.click_id("mute" .. P.snap.tracks[2].id) refresh()
  T.check("unmute", r.GetMediaTrackInfo_Value(P.snap.tracks[2].ptr, "B_MUTE") == 0)
  D.click_id("solo" .. P.snap.tracks[1].id) refresh()
  T.check("solo button solos real track", r.GetMediaTrackInfo_Value(P.snap.tracks[1].ptr, "I_SOLO") > 0)
  D.click_id("solo" .. P.snap.tracks[1].id) refresh()
  -- mixer tab: fader drag
  click_tab("mixer") D.frames(2)
  local fw = G.reg["mvol" .. P.snap.tracks[2].id]
  D.drag(fw[1] + 13, fw[2] + fw[4] * 0.5, fw[1] + 13, fw[2] + fw[4] * 0.35, 4) refresh()
  T.check("mixer fader moves real volume", math.abs(P.snap.tracks[2].vol - 10 ^ (-8 / 20)) > 0.01, P.snap.tracks[2].vol)
  shot("08_mixer")

  -- 16-17. effects via Devices tab
  D.click(100, A.R.arr_headers[2] + 2 * S.arr.track_h + 10) -- select lead track header
  click_tab("devices") D.frames(2)
  D.click_id("addfx") D.click_popup("Reverb  (ReaVerbate)") refresh()
  T.check("16 reverb added to lead", #P.snap.tracks[3].fx == 2)
  D.frames(2)
  local pw0, pw1
  local slider
  for id, w in pairs(G.reg) do if id:match("^fxp1_") then slider = slider or w if id:match("_0$") then slider = w end end end
  local wetbefore = require("audio.effects").params(P.snap.tracks[3].ptr, 1)[1].value
  D.drag(slider[1] + 5, slider[2] + 10, slider[1] + slider[3] * 0.4, slider[2] + 10, 4) refresh()
  local wetafter = require("audio.effects").params(P.snap.tracks[3].ptr, 1)[1].value
  T.check("17 effect parameter edited with slider", math.abs(wetafter - wetbefore) > 0.05, string.format("%.3f -> %.3f", wetbefore, wetafter))
  D.click(100, A.R.arr_headers[2] + 1 * S.arr.track_h + 10) D.frames(2) -- bass track
  D.click_id("addfx") D.click_popup("Delay  (ReaDelay)") refresh()
  D.click(100, A.R.arr_headers[2] + 0 * S.arr.track_h + 10) D.frames(2) -- drums
  D.click_id("addfx") D.click_popup("EQ  (ReaEQ)") refresh()
  T.check("delay on bass, EQ on drums", #P.snap.tracks[2].fx == 2 and #P.snap.tracks[1].fx == 7)
  shot("09_devices")
  click_tab("roll")

  -- 18-19. transport + loop
  D.drag(lane_xy(1, 0.0 + 0.0), A.R.arr_ruler[2] + 6, (lane_xy(1, 8)), A.R.arr_ruler[2] + 6, 5)
  -- the drag above used lane_xy for x only; re-do with explicit coordinates
  local rx0 = TL.beat_to_x(S.arr.view, 0, A.R.arr_ruler[1]) + 1
  local rx1 = TL.beat_to_x(S.arr.view, 8, A.R.arr_ruler[1])
  D.drag(rx0, A.R.arr_ruler[2] + 6, rx1, A.R.arr_ruler[2] + 6, 5)
  local TR = require("audio.transport")
  local ls, le = TR.loop()
  T.check("19 loop region set by dragging ruler strip", math.abs(ls - 0) < 0.6 and math.abs(le - 8) < 0.6 and TR.loop_enabled(), string.format("%.2f..%.2f en=%s", ls, le, tostring(TR.loop_enabled())))
  D.key("home") D.key("space")
  local maxpos, wrapped, lastpos = 0, false, 0
  T.poll(9.5, function()
    D.frames(1)
    local p = TR.position()
    if p < lastpos - 2 then wrapped = true end
    lastpos = p maxpos = math.max(maxpos, p)
  end, function() build_part2(TR, maxpos, wrapped) end)
end

build_part2 = function(TR, maxpos, wrapped)
  shot("10_playing")
  T.check("18 Space starts native transport", TR.is_playing())
  T.check("19 playback loops inside region (>=1 wrap, never past loop end)", wrapped and maxpos <= 8.5, string.format("max=%.2f wrapped=%s", maxpos, tostring(wrapped)))
  local mm = A.meter("master")
  T.info(string.format("master meter during playback: l=%.3f r=%.3f hold=%.3f", mm.l, mm.r, mm.hold))
  D.key("space") D.frames(2)
  T.check("Space stops transport", not TR.is_playing())
  D.key("l") -- loop off
  T.check("L toggles loop off", not TR.loop_enabled())

  -- 20. undo / redo through keyboard on a structural change
  local nclips = #P.snap.tracks[1].clips
  D.click(lane_xy(1, 28.5)) D.key("delete") refresh()
  T.eq("Delete removes the selected clip", #P.snap.tracks[1].clips, nclips - 1)
  D.key("z", { cmd = true }) refresh()
  T.eq("Cmd+Z restores it", #P.snap.tracks[1].clips, nclips)
  D.key("z", { cmd = true, shift = true }) refresh()
  T.eq("Cmd+Shift+Z deletes again", #P.snap.tracks[1].clips, nclips - 1)
  D.key("z", { cmd = true }) refresh()

  -- 21. save (project is untitled => in-app save-as dialog)
  S.browser.dir = OUT
  D.click_id("save") D.frames(2)
  T.check("save-as dialog opens for untitled project", G.modal and G.modal.kind == "dialog")
  D.click_id("sv_name") D.key("backspace") D.type("neon_drive") D.key("enter") D.frames(2)
  D.click_id("sv_go") D.frames(2)
  local f = io.open(OUT .. "/neon_drive.rpp", "rb")
  T.check("21 project saved to .rpp via inner dialog", f ~= nil)
  if f then f:close() end

  -- 24-25. export through the inner export dialog
  S.export.dir = OUT .. "/export" S.export.name = "neon_drive"
  os.execute('rm -rf "' .. OUT .. '/export"')
  D.key("e", { cmd = true }) D.frames(2)
  T.check("export dialog opens (Cmd+E)", G.modal and G.modal.kind == "dialog")
  shot("11_export_dialog")
  D.click_id("ex_go") D.frames(3)
  local last = S.export.last
  T.check("24 export succeeded", last and last.ok, last and last.err)
  if last and last.analysis then
    local a = last.analysis
    T.info(string.format("export: %s  %.2fs  peak=%.3f rms=%.3f", last.path, a.secs, a.peak, a.rms))
    T.check("export is audible, not clipping", a.peak > 0.05 and a.peak <= 1.0)
    T.check("export covers 8 bars + 1.5 s effect tail (17.5 s at 120 BPM)", math.abs(a.secs - 17.5) < 0.1, a.secs)
    local b = {} for i = 1, 35 do b[#b + 1] = string.format("%.2f", a.buckets[i] or 0) end
    T.info("per-0.5s peaks: " .. table.concat(b, " "))
    -- arrangement check: bars 1-4 have drums+bass+audio, bars 5-8 add lead; nothing silent in the middle
    local silent = 0 for i = 1, 32 do if (a.buckets[i] or 0) < 0.01 then silent = silent + 1 end end
    T.check("no silent gaps inside the arrangement", silent == 0, silent .. " silent half-seconds")
  end
  D.click_id("ex_close") D.frames(2)
  -- manifest for verify phase
  local snap = P.snap
  local m = { "name=" .. snap.name, "tracks=" .. #snap.tracks, "clips=" .. #snap.clips }
  local total = 0 for _, c in ipairs(snap.clips) do if c.kind == "midi" then total = total + #P.notes(c) end end
  m[#m + 1] = "notes=" .. total
  m[#m + 1] = "peak=" .. (last and last.analysis and last.analysis.peak or 0)
  m[#m + 1] = "rms=" .. (last and last.analysis and last.analysis.rms or 0)
  m[#m + 1] = "secs=" .. (last and last.analysis and last.analysis.secs or 0)
  m[#m + 1] = "undo_label_at_end=" .. tostring(r.Undo_CanUndo2(0))
  local mf = io.open(OUT .. "/ui_manifest.txt", "w") mf:write(table.concat(m, "\n"), "\n") mf:close()
  D.click_id("save") D.frames(2)
  shot("12_final")
  D.stop()
  T.finish()
end

local function verify()
  T.wait_until(12, function() return r.CountTracks(0) > 0 end, function()
    D.start()
    A, P, C, S, G = D.A, require("project"), require("commands"), require("ui.state"), D.G
    S.bottom_h = 330
    refresh()
    local man = {} for line in io.lines(OUT .. "/ui_manifest.txt") do local k, v = line:match("^([%w_]+)=(.*)$") man[k] = tonumber(v) or v end
    T.check("22-23 reopened: DAW recognises its project (no welcome screen)", P.snap.has_root and P.snap.name == man.name, P.snap.name)
    T.eq("reopened: tracks", #P.snap.tracks, man.tracks)
    T.eq("reopened: clips", #P.snap.clips, man.clips)
    local total = 0 for _, c in ipairs(P.snap.clips) do if c.kind == "midi" then total = total + #P.notes(c) end end
    T.eq("reopened: every note present", total, man.notes)
    D.frames(3)
    shot("13_reopened")
    -- resume editing through the UI: open the lead clip, add a note, undo it
    local lead = P.snap.tracks[3]
    D.dblclick(TL.beat_to_x(S.arr.view, 24, A.R.arr_lanes[1]), A.R.arr_lanes[2] + 2 * S.arr.track_h + 40) refresh()
    T.check("resume: double-click opens clip in roll", S.edit_clip == lead.clips[1].id)
    local n0 = #P.notes(P.clip(lead.clips[1].id))
    D.mods() S.roll.note_len = 0.5
    local px, py
    for _ = 1, 30 do D.frames(1) local gr = A.R.roll_grid local rows = gr[4] / S.roll.pv.row_h if 80 > S.roll.pv.top - 1 or 80 < S.roll.pv.top - rows then D.wheel(gr[1] + 100, gr[2] + 50, 120) else break end end
    px, py = (function() local gr = A.R.roll_grid return TL.beat_to_x(S.roll.view, 30.05, gr[1]), TL.pitch_to_y(S.roll.pv, 80, gr[2]) + 7 end)()
    D.click(px, py) refresh()
    T.eq("resume: new note added in reopened project", #P.notes(P.clip(lead.clips[1].id)), n0 + 1)
    D.key("z", { cmd = true }) refresh()
    T.eq("resume: undo works after reopen", #P.notes(P.clip(lead.clips[1].id)), n0)
    -- re-export through the UI and compare with the original export
    S.export.dir = OUT .. "/export" S.export.name = "neon_drive_reopened"
    D.key("e", { cmd = true }) D.frames(2) D.click_id("ex_go") D.frames(3)
    local last = S.export.last
    T.check("re-export after reopen ok", last and last.ok, last and last.err)
    if last and last.analysis then
      local a = last.analysis
      T.eq("re-export duration identical", a.secs, tonumber(man.secs), 0.05)
      T.eq("re-export peak within 2%", a.peak, tonumber(man.peak), tonumber(man.peak) * 0.02 + 1e-4)
      T.eq("re-export RMS within 3%", a.rms, tonumber(man.rms), tonumber(man.rms) * 0.03 + 1e-4)
    end
    D.click_id("ex_close") D.frames(2)
    D.stop()
    T.finish()
  end)
end

T.run(function() if T.mode == "ui_build" then build() else verify() end end)
