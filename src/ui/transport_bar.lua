-- transport_bar.lua : top bar owned by the inner DAW. Drives REAPER's native transport and project actions.
local G = require("ui.gx")
local TL = require("timeline")
local U = require("util")
local H = require("host")
local TB = {}

local function icon_play(x, y, w, h, c) G.tri(x + w / 2 - 5, y + h / 2 - 7, x + w / 2 - 5, y + h / 2 + 7, x + w / 2 + 7, y + h / 2, c) end
local function icon_pause(x, y, w, h, c) G.rect(x + w / 2 - 6, y + h / 2 - 7, 4, 14, c) G.rect(x + w / 2 + 2, y + h / 2 - 7, 4, 14, c) end
local function icon_stop(x, y, w, h, c) G.rect(x + w / 2 - 6, y + h / 2 - 6, 12, 12, c) end
local function icon_rew(x, y, w, h, c) G.rect(x + w / 2 - 7, y + h / 2 - 6, 2, 12, c) G.tri(x + w / 2 + 6, y + h / 2 - 6, x + w / 2 + 6, y + h / 2 + 6, x + w / 2 - 4, y + h / 2, c) end

function TB.draw(A, R)
  local rect = R.transport
  local S, P, C, TR, T = A.S, A.P, A.C, A.TR, G.theme
  local snap = P.snap
  G.rect(rect[1], rect[2], rect[3], rect[4], T.panel)
  G.hline(0, rect[4] - 1, rect[3], T.line)
  local y, h = 8, 32
  local x = 10
  local playing = TR.is_playing() and not TR.is_paused()

  -- project name
  local pname = snap.has_root and snap.name or "(no project)"
  if G.button("pname", x, y, 150, h, pname, { bg = T.panel2, size = 13, tip = "Click to rename project", disabled = not snap.has_root }) then
    G.prompt("Project name", snap.name, function(s) if s ~= "" then C.set_name(s) end end)
  end
  x = x + 160

  -- transport buttons
  if G.button("rew", x, y, 34, h, nil, { draw = icon_rew, tip = "Go to start (Home)" }) then TR.seek(0) end
  x = x + 38
  if G.button("play", x, y, 44, h, nil, { draw = playing and icon_pause or icon_play, on = playing, on_color = T.green, tip = "Play / pause (Space)" }) then
    if playing then TR.pause() else TR.play() end
  end
  x = x + 48
  if G.button("stop", x, y, 34, h, nil, { draw = icon_stop, tip = "Stop" }) then TR.stop() end
  x = x + 38
  local loop_on = TR.loop_enabled()
  if G.button("loop", x, y, 50, h, "LOOP", { on = loop_on, on_color = T.accent, tip = "Loop region (L). Drag the strip above the ruler to set it." }) then
    local ls, le = TR.loop()
    if le <= ls then TR.set_loop(0, TL.beats_per_bar(snap.num, snap.den) * 4) end
    TR.set_loop_enabled(not loop_on)
  end
  x = x + 60

  -- position readout
  local pos = TR.position()
  local bar, beat, frac = TL.bar_beat(pos, snap.num, snap.den)
  G.rect(x, y, 170, h, T.bg) G.frame(x, y, 170, h, T.line)
  G.text(string.format("%03d.%d.%02d", bar, beat, math.floor(frac * 100)), x + 10, y + 7, T.accent, 16)
  G.text(U.fmt_time(H.qn_to_time(pos)), x + 98, y + 10, T.dim, 12)
  x = x + 180

  -- tempo
  G.text("BPM", x, y + 1, T.faint, 9)
  if G.button("bpm", x, y + 9, 64, 23, string.format("%.1f", snap.bpm), { bg = T.panel2, size = 14, tip = "Click to type a tempo. Wheel = +/-1" }) then
    G.prompt("Tempo (BPM)", string.format("%g", snap.bpm), function(s) local v = tonumber(s) if v then A.safe(C.set_bpm, v) end end, { numeric = true, hint = "20 - 300" })
  end
  if G.over(x, y, 64, h) and G.m.wheel ~= 0 then C.set_bpm(snap.bpm + (G.m.wheel > 0 and 1 or -1)) end
  x = x + 72
  G.text("SIG", x, y + 1, T.faint, 9)
  if G.button("sig", x, y + 9, 46, 23, snap.num .. "/" .. snap.den, { bg = T.panel2, size = 13, tip = "Time signature" }) then
    local items = {}
    for _, s in ipairs { { 4, 4 }, { 3, 4 }, { 2, 4 }, { 5, 4 }, { 6, 8 }, { 7, 8 } } do
      items[#items + 1] = { label = s[1] .. "/" .. s[2], checked = (s[1] == snap.num and s[2] == snap.den), fn = function() C.set_timesig(s[1], s[2]) end }
    end
    G.popup(items, x, y + h)
  end
  x = x + 56
  G.text("SNAP", x, y + 1, T.faint, 9)
  if G.button("snap", x, y + 9, 54, 23, S.snap_label(), { bg = T.panel2, size = 12, tip = "Grid snap" }) then
    local items = {}
    for i, s in ipairs(S.SNAPS) do items[#items + 1] = { label = s[1], checked = (i == S.snap_idx), fn = function() S.snap_idx = i end } end
    G.popup(items, x, y + h)
  end
  x = x + 64

  -- undo/redo
  local ul, rl = H.undo_label(), H.redo_label()
  if G.button("undo", x, y, 48, h, "Undo", { disabled = not ul, tip = ul and ("Undo: " .. ul .. " (Cmd+Z)") or "Nothing to undo" }) then C.undo() end
  x = x + 52
  if G.button("redo", x, y, 48, h, "Redo", { disabled = not rl, tip = rl and ("Redo: " .. rl .. " (Cmd+Shift+Z)") or "Nothing to redo" }) then C.redo() end
  x = x + 58

  -- zoom
  if G.button("zout", x, y, 28, h, "-", { size = 16, tip = "Zoom out" }) then TL.zoom(S.arr.view, 1 / 1.3, R.arr_lanes[3] / 2, 0) end
  if G.button("zin", x + 32, y, 28, h, "+", { size = 16, tip = "Zoom in" }) then TL.zoom(S.arr.view, 1.3, R.arr_lanes[3] / 2, 0) end
  x = x + 72

  -- right-aligned action cluster (items that do not fit are simply omitted; all have keyboard shortcuts)
  local rx = rect[3] - 10
  local function rbtn(id, label, w, o, fn)
    rx = rx - w
    if rx < x then return end
    if G.button(id, rx, y, w, h, label, o) then fn() end
    rx = rx - 6
  end
  local ml, mr = TR.master_peak()
  if rx - 56 > x then
    rx = rx - 50
    local function lv(v) return U.clamp((U.lin_to_db(v) + 60) / 66, 0, 1) end
    G.rect(rx, y + 4, 50, 10, T.bg) G.rect(rx, y + 4, 50 * lv(ml), 10, lv(ml) > 0.92 and T.red or T.green)
    G.rect(rx, y + 18, 50, 10, T.bg) G.rect(rx, y + 18, 50 * lv(mr), 10, lv(mr) > 0.92 and T.red or T.green)
    rx = rx - 8
  end
  rbtn("export", "Export", 64, { bg = T.accent, color = { 20, 20, 24 }, tip = "Render the arrangement to WAV (Cmd+E)", disabled = not snap.has_root }, function() A.open_export() end)
  rbtn("save", "Save", 52, { tip = "Save project (Cmd+S)" }, function() A.save() end)
  rbtn("import", "Import", 60, { tip = "Import audio file onto an audio track (Cmd+I)", disabled = not snap.has_root }, function() A.import_audio_dialog() end)
  rbtn("addtrk", "+ Track", 70, { tip = "Add a track (Cmd+T)", disabled = not snap.has_root }, function() A.add_track_menu(rx, y + h) end)
end
return TB
