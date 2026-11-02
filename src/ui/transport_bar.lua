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

-- Responsive layout: the right-hand action cluster (Export/Save/Import/+Track) is reserved first and always shown;
-- left-hand items flow in priority order and low-priority ones (zoom, redo, undo, snap, sig) drop out when space runs short.
function TB.draw(A, R)
  local rect = R.transport
  local S, P, C, TR, T = A.S, A.P, A.C, A.TR, G.theme
  local snap = P.snap
  local W = rect[3]
  local compact = W < 1180
  G.rect(rect[1], rect[2], rect[3], rect[4], T.panel)
  G.hline(0, rect[4] - 1, rect[3], T.line)
  local y, h = 8, 32
  local playing = TR.is_playing() and not TR.is_paused()

  -- ---- right cluster (reserved first)
  local rx = W - 10
  local function rbtn(id, label, w, o, fn)
    rx = rx - w
    if G.button(id, rx, y, w, h, label, o) then fn() end
    rx = rx - 6
  end
  local bw = compact and { 58, 46, 56, 66 } or { 64, 52, 60, 70 }
  rbtn("export", "Export", bw[1], { bg = T.accent, color = { 20, 20, 24 }, tip = "Render the arrangement to WAV (Cmd+E)", disabled = not snap.has_root }, function() A.open_export() end)
  rbtn("save", "Save", bw[2], { tip = "Save project (Cmd+S)" }, function() A.save() end)
  rbtn("import", "Import", bw[3], { tip = "Import audio file onto an audio track (Cmd+I)", disabled = not snap.has_root }, function() A.import_audio_dialog() end)
  rbtn("addtrk", "+ Track", bw[4], { tip = "Add a track (Cmd+T)", disabled = not snap.has_root }, function() A.add_track_menu(rx, y + h) end)
  local limit = rx - 4

  -- ---- left items, in priority order. each: w (width), draw(x)
  local pos = TR.position()
  local bar, beat, frac = TL.bar_beat(pos, snap.num, snap.den)
  local pname = snap.has_root and snap.name or "(no project)"
  local items = {
    { w = compact and 100 or 150, draw = function(x, w)
      if G.over(x, y, w, h) and G.m.rpressed then
        G.popup({
          { label = "Rename project...", fn = function() G.prompt("Project name", snap.name, function(s) if s ~= "" then C.set_name(s) end end) end, disabled = not snap.has_root },
          { label = "New project...", fn = function() A.new_project_menu() end },
          { label = "Save as...", fn = function() require("ui.browser").save_as(A) end },
        }, x, y + h)
      end
      if G.button("pname", x, y, w, h, pname, { bg = T.panel2, size = 13, tip = "Click to rename project, right-click for more", disabled = not snap.has_root }) then
        G.prompt("Project name", snap.name, function(s) if s ~= "" then C.set_name(s) end end)
      end
    end },
    { w = 34, draw = function(x, w) if G.button("rew", x, y, w, h, nil, { draw = icon_rew, tip = "Go to start (Home)" }) then TR.seek(0) end end },
    { w = 44, draw = function(x, w)
      if G.button("play", x, y, w, h, nil, { draw = playing and icon_pause or icon_play, on = playing, on_color = T.green, tip = "Play / pause (Space)" }) then
        if playing then TR.pause() else TR.play() end
      end
    end },
    { w = 34, draw = function(x, w) if G.button("stop", x, y, w, h, nil, { draw = icon_stop, tip = "Stop" }) then TR.stop() end end },
    { w = 50, draw = function(x, w)
      local loop_on = TR.loop_enabled()
      if G.button("loop", x, y, w, h, "LOOP", { on = loop_on, on_color = T.accent, tip = "Loop region (L). Drag the strip above the ruler to set it." }) then
        local ls, le = TR.loop()
        if le <= ls then TR.set_loop(0, TL.beats_per_bar(snap.num, snap.den) * 4) end
        TR.set_loop_enabled(not loop_on)
      end
    end },
    { w = compact and 118 or 170, gap = 8, draw = function(x, w)
      G.rect(x, y, w, h, T.bg) G.frame(x, y, w, h, T.line)
      G.text(string.format("%03d.%d.%02d", bar, beat, math.floor(frac * 100)), x + 10, y + 7, T.accent, compact and 15 or 16)
      if not compact then G.text(U.fmt_time(H.qn_to_time(pos)), x + 98, y + 10, T.dim, 12) end
    end },
    { w = compact and 58 or 64, drop = 6, draw = function(x, w)
      G.text("BPM", x, y + 1, T.faint, 9)
      if G.button("bpm", x, y + 9, w, 23, string.format("%.1f", snap.bpm), { bg = T.panel2, size = 14, tip = "Click to type a tempo. Wheel = +/-1" }) then
        G.prompt("Tempo (BPM)", string.format("%g", snap.bpm), function(s) local v = tonumber(s) if v then A.safe(C.set_bpm, v) end end, { numeric = true, hint = "20 - 300" })
      end
      if G.over(x, y, w, h) and G.m.wheel ~= 0 then C.set_bpm(snap.bpm + (G.m.wheel > 0 and 1 or -1)) end
    end },
    { w = 46, drop = 1, draw = function(x, w)
      G.text("SIG", x, y + 1, T.faint, 9)
      if G.button("sig", x, y + 9, w, 23, snap.num .. "/" .. snap.den, { bg = T.panel2, size = 13, tip = "Time signature" }) then
        local its = {}
        for _, sg in ipairs { { 4, 4 }, { 3, 4 }, { 2, 4 }, { 5, 4 }, { 6, 8 }, { 7, 8 } } do
          its[#its + 1] = { label = sg[1] .. "/" .. sg[2], checked = (sg[1] == snap.num and sg[2] == snap.den), fn = function() C.set_timesig(sg[1], sg[2]) end }
        end
        G.popup(its, x, y + h)
      end
    end },
    { w = 54, drop = 2, draw = function(x, w)
      G.text("SNAP", x, y + 1, T.faint, 9)
      if G.button("snap", x, y + 9, w, 23, S.snap_label(), { bg = T.panel2, size = 12, tip = "Grid snap ([ and ] change it)" }) then
        local its = {}
        for i, sn in ipairs(S.SNAPS) do its[#its + 1] = { label = sn[1], checked = (i == S.snap_idx), fn = function() S.snap_idx = i end } end
        G.popup(its, x, y + h)
      end
    end },
    { w = 48, drop = 3, draw = function(x, w)
      local ul = H.undo_label()
      if G.button("undo", x, y, w, h, "Undo", { disabled = not ul, tip = ul and ("Undo: " .. ul .. " (Cmd+Z)") or "Nothing to undo" }) then C.undo() end
    end },
    { w = 48, drop = 4, draw = function(x, w)
      local rl = H.redo_label()
      if G.button("redo", x, y, w, h, "Redo", { disabled = not rl, tip = rl and ("Redo: " .. rl .. " (Cmd+Shift+Z)") or "Nothing to redo" }) then C.redo() end
    end },
    { w = 60, drop = 5, draw = function(x, w)
      if G.button("zout", x, y, 28, h, "-", { size = 16, tip = "Zoom out" }) then TL.zoom(S.arr.view, 1 / 1.3, R.arr_lanes[3] / 2, 0) end
      if G.button("zin", x + 32, y, 28, h, "+", { size = 16, tip = "Zoom in" }) then TL.zoom(S.arr.view, 1.3, R.arr_lanes[3] / 2, 0) end
    end },
  }
  -- decide which droppable items fit (drop highest `drop` first... lowest priority = highest drop number)
  local GAP = 6
  local function total(skip)
    local t = 10
    for _, it in ipairs(items) do if not (it.drop and skip[it.drop]) then t = t + it.w + (it.gap or GAP) + (it.drop and 6 or 0) end end
    return t
  end
  local skip = {}
  for d = 6, 1, -1 do if total(skip) > limit then skip[d] = true end end
  local x = 10
  for _, it in ipairs(items) do
    if not (it.drop and skip[it.drop]) then it.draw(x, it.w) x = x + it.w + (it.gap or GAP) + (it.drop and 6 or 0) end
  end
  -- master meter if there is room
  if limit - x > 66 then
    local ml, mr = TR.master_peak()
    local mx = limit - 54
    local function lv(v) return U.clamp((U.lin_to_db(v) + 60) / 66, 0, 1) end
    G.rect(mx, y + 4, 50, 10, T.bg) G.rect(mx, y + 4, 50 * lv(ml), 10, lv(ml) > 0.92 and T.red or T.green)
    G.rect(mx, y + 18, 50, 10, T.bg) G.rect(mx, y + 18, 50 * lv(mr), 10, lv(mr) > 0.92 and T.red or T.green)
  end
end
return TB
