-- arrangement.lua : multitrack timeline (ruler, loop strip, track headers, clips, playhead, scrollbars).
-- All edits go through commands.lua (real REAPER items); the view reads the cached project snapshot.
local G = require("ui.gx")
local TL = require("timeline")
local U = require("util")
local WF = require("ui.waveform")
local L = require("ui.layout")

local Arr = {}
local D = nil            -- active drag: { kind, ... }
local EDGE = 6

local function bpb(A) return TL.beats_per_bar(A.P.snap.num, A.P.snap.den) end

local function row_at(A, R, y)
  local S = A.S
  local idx = math.floor((y - R.arr_lanes[2] + S.arr.scroll_y) / S.arr.track_h) + 1
  return A.P.snap.tracks[idx], idx
end

local function clip_hit(A, R, x, y)
  local S = A.S
  local t = row_at(A, R, y)
  if not t then return end
  local v = S.arr.view
  for i = #t.clips, 1, -1 do
    local c = t.clips[i]
    local x0 = TL.beat_to_x(v, c.start, R.arr_lanes[1])
    local x1 = TL.beat_to_x(v, c.start + c.len, R.arr_lanes[1])
    if x >= x0 and x <= x1 then
      local zone = "body"
      if x1 - x0 > EDGE * 3 then
        if x >= x1 - EDGE then zone = "right" elseif x <= x0 + EDGE and c.kind == "audio" then zone = "left" end
      end
      return c, zone, t
    end
  end
  return nil, nil, t
end

----------------------------------------------------------------------------- drawing helpers
local function draw_midi_preview(A, c, x0, y0, w, h, col)
  local notes = A.P.notes(c)
  if #notes == 0 then return end
  local lo, hi = 127, 0
  for _, n in ipairs(notes) do if n.pitch < lo then lo = n.pitch end if n.pitch > hi then hi = n.pitch end end
  local span = math.max(11, hi - lo + 1)
  local v = A.S.arr.view
  local rh = math.max(1.5, math.min(4, h / span))
  local lane_x = A.R.arr_lanes[1]
  for _, n in ipairs(notes) do
    if n.e > c.start and n.s < c.start + c.len then
      local nx = TL.beat_to_x(v, math.max(n.s, c.start), lane_x)
      local nx2 = TL.beat_to_x(v, math.min(n.e, c.start + c.len), lane_x)
      local ny = y0 + h - (n.pitch - lo + 1) / span * h
      G.rect(nx, ny, math.max(1.5, nx2 - nx - 0.5), rh, col, 0.95)
    end
  end
end

local function draw_waveform(A, c, x0, y0, w, h, col)
  local ppb = A.S.arr.view.ppb
  local pps = ppb * A.P.snap.bpm / 60
  local wf = WF.get(c, pps)
  if not wf then return end
  local mid = y0 + h / 2
  local lane = A.R.arr_lanes
  local first = math.max(0, math.floor(lane[1] - x0))
  local last = math.min(w, lane[1] + lane[3] - x0)
  local step = 1
  for px = math.floor(first), math.floor(last), step do
    local i = math.floor(px / w * wf.n) + 1
    if i >= 1 and i <= wf.n then
      local mx, mn = wf.max[i], wf.min[i]
      local top = mid - math.max(0.5, mx * h * 0.5)
      local bot = mid - math.min(-0.5, mn * h * 0.5)
      G.rect(x0 + px, top, 1, math.max(1, bot - top), col, 0.9)
    end
  end
end

local function draw_clip(A, c, t, row_y)
  local S, T = A.S, G.theme
  local R = A.R
  local v = S.arr.view
  local lane = R.arr_lanes
  local x0 = TL.beat_to_x(v, c.start, lane[1])
  local x1 = TL.beat_to_x(v, c.start + c.len, lane[1])
  if x1 < lane[1] or x0 > lane[1] + lane[3] then return end
  local th = S.arr.track_h
  local y0, h = row_y + 3, th - 6
  local w = math.max(2, x1 - x0)
  local col = t.color
  local sel = (S.sel_clip == c.id)
  G.rect(x0, y0, w, h, col, sel and 0.55 or 0.32)
  G.rect(x0, y0, w, 15, col, sel and 0.95 or 0.75)
  local body_y, body_h = y0 + 16, h - 17
  if c.kind == "midi" then draw_midi_preview(A, c, x0, body_y, w, body_h, sel and { 255, 255, 255 } or col)
  else draw_waveform(A, c, x0, body_y, w, body_h, sel and { 255, 255, 255 } or col) end
  G.frame(x0, y0, w, h, sel and { 255, 255, 255 } or col, sel and 1 or 0.9)
  if sel then G.frame(x0 + 1, y0 + 1, w - 2, h - 2, { 255, 255, 255 }, 0.5) end
  G.text(c.name ~= "" and c.name or (c.kind == "midi" and "MIDI" or "audio"), x0 + 4, y0 + 1, { 12, 12, 14 }, 11, "l", w - 6)
  if c.offline then
    G.rect(x0, body_y, w, body_h, { 120, 20, 20 }, 0.55)
    G.text("OFFLINE - file missing", x0 + 6, body_y + body_h / 2 - 6, { 255, 200, 200 }, 11, "l", w - 8)
  end
  if A.S.edit_clip == c.id then G.rect(x0, y0 + h - 3, w, 3, T.accent) end
end

----------------------------------------------------------------------------- headers
local function draw_header(A, t, y)
  local S, T, C = A.S, G.theme, A.C
  local th, hw = S.arr.track_h, A.R.arr_headers[3]
  local sel = (S.sel_track == t.id)
  G.rect(0, y, hw, th - 1, sel and T.panel3 or T.panel2)
  G.rect(0, y, 5, th - 1, t.color)
  G.hline(0, y + th - 1, hw, T.line)
  G.text(t.name, 12, y + 5, T.text, 13, "l", hw - 70)
  local sub = t.kind == "audio" and "audio" or (t.inst ~= "" and t.inst or "midi")
  local nfx = #t.fx - t.inst_count
  G.text(sub .. (nfx > 0 and ("  +" .. nfx .. " fx") or ""), 12, y + 21, T.dim, 11, "l", hw - 70)
  -- meter (real peak values)
  local m = A.meter(t.id)
  local mx = hw - 8
  G.rect(mx, y + 4, 4, th - 9, T.bg)
  local function lvl(l) return U.clamp((U.lin_to_db(l) + 60) / 66, 0, 1) end
  local ml, mr = lvl(m.l), lvl(m.r)
  G.rect(mx, y + 4 + (th - 9) * (1 - ml), 2, (th - 9) * ml, ml > 0.9 and T.red or T.green)
  G.rect(mx + 2, y + 4 + (th - 9) * (1 - mr), 2, (th - 9) * mr, mr > 0.9 and T.red or T.green)
  -- M S vol pan
  local by = y + th - 24
  if G.button("mute" .. t.id, 10, by, 22, 18, "M", { on = t.mute, on_color = T.yellow, tip = "Mute (real track mute)" }) then C.set_mute(t.id, not t.mute) end
  if G.button("solo" .. t.id, 36, by, 22, 18, "S", { on = t.solo, on_color = T.accent2, tip = "Solo" }) then C.set_solo(t.id, not t.solo) end
  local volw = hw - 64 - 70
  local db = U.lin_to_db(t.vol)
  local tv = U.clamp((db + 60) / 72, 0, 1)
  local nt, ph = G.slider("vol" .. t.id, 64, by, volw, 18, tv, { default = 60 / 72 + 0, tip = "Volume (dbl-click = 0 dB)", value_text = string.format("%.1f dB", db), color = t.color })
  if ph == "begin" then C.begin_gesture("Volume") end
  if ph then C.set_volume(t.id, nt <= 0.001 and 0 or U.db_to_lin(nt * 72 - 60)) end
  if ph == "end" then C.end_gesture() end
  local np, ph2 = G.slider("pan" .. t.id, hw - 64 - 0, by, 52, 18, (t.pan + 1) / 2, { center = true, default = 0.5, tip = "Pan (dbl-click = center)", color = T.dim })
  if ph2 == "begin" then C.begin_gesture("Pan") end
  if ph2 then C.set_pan(t.id, (np * 2 - 1)) end
  if ph2 == "end" then C.end_gesture() end
end

----------------------------------------------------------------------------- interaction
local function to_beat(A, R, x, snap)
  local b = TL.x_to_beat(A.S.arr.view, x, R.arr_lanes[1])
  if snap and snap > 0 then b = U.snap(b, snap) end
  return math.max(0, b)
end

local function context_menu_clip(A, c)
  local C, TR = A.C, A.TR
  local items = {
    { label = "Open in editor", fn = function() A.open_clip(c.id) end, disabled = c.kind ~= "midi" },
    { label = "Duplicate (Cmd+D)", fn = function() A.duplicate_selected() end },
    { label = "Split at playhead (S)", fn = function() local ok = C.split_clip(c.id, TR.position()) if not ok then A.msg("Playhead is not inside this clip", "warn") end end },
    { label = "Quantize notes (Q)", fn = function() C.quantize_notes(c.id, A.S.snap() > 0 and A.S.snap() or 0.25, false) end, disabled = c.kind ~= "midi" },
    { label = "Rename...", fn = function() G.prompt("Rename clip", c.name, function(s) if s ~= "" then C.rename_clip(c.id, s) end end) end },
    { sep = true },
    { label = "Delete (Del)", fn = function() C.delete_clip(c.id) if A.S.sel_clip == c.id then A.S.sel_clip = nil end if A.S.edit_clip == c.id then A.S.edit_clip = nil end end },
  }
  G.popup(items, G.m.x, G.m.y)
end

local function context_menu_lane(A, t, beat)
  local C = A.C
  local items = {}
  if t.kind == "midi" then
    items[#items + 1] = { label = "New MIDI clip here (1 bar)", fn = function() A.new_clip_at(t.id, beat) end }
  else
    items[#items + 1] = { label = "Import audio here...", fn = function() A.import_audio_dialog(t.id, beat) end }
  end
  items[#items + 1] = { label = "Paste clip (Cmd+V)", fn = function() A.paste_at(t.id, beat) end, disabled = A.S.clipboard == nil }
  G.popup(items, G.m.x, G.m.y)
end

local function context_menu_track(A, t)
  local C = A.C
  local items = {
    { label = "Rename...", fn = function() G.prompt("Rename track", t.name, function(s) if s ~= "" then C.rename_track(t.id, s) end end) end },
    { label = "Devices / effects", fn = function() A.S.sel_track = t.id A.S.tab = "devices" end },
    { label = "Add effect: Reverb", fn = function() A.safe(C.add_effect, t.id, "reverb") end },
    { label = "Add effect: Delay", fn = function() A.safe(C.add_effect, t.id, "delay") end },
    { label = "Add effect: EQ", fn = function() A.safe(C.add_effect, t.id, "eq") end },
    { label = "Color: next", fn = function()
      local pal = { { 255, 99, 99 }, { 255, 170, 60 }, { 240, 220, 80 }, { 110, 210, 120 }, { 70, 200, 220 }, { 100, 140, 255 }, { 180, 120, 255 }, { 240, 110, 200 } }
      local best, bd = 1, 1e9
      for i, c in ipairs(pal) do local d = math.abs(c[1] - t.color[1]) + math.abs(c[2] - t.color[2]) + math.abs(c[3] - t.color[3]) if d < bd then best, bd = i, d end end
      C.set_track_color(t.id, pal[best % #pal + 1])
    end },
    { sep = true },
    { label = "Delete track...", fn = function()
      G.confirm("Delete track '" .. t.name .. "' and its clips?", function() C.delete_track(t.id) if A.S.sel_track == t.id then A.S.sel_track = nil end end, "Delete")
    end },
  }
  G.popup(items, G.m.x, G.m.y)
end

local function handle_lanes(A, R)
  local S, m, C, TR = A.S, G.m, A.C, A.TR
  local lane = R.arr_lanes
  local v = S.arr.view
  local snap = S.arr_snap(bpb(A))
  local inside = G.over(lane[1], lane[2], lane[3], lane[4])

  -- wheel: vertical scroll / horizontal scroll / zoom
  if inside or G.over(R.arr_headers[1], R.arr_headers[2], R.arr_headers[3], R.arr_headers[4]) or G.over(R.arr_ruler[1], R.arr_ruler[2], R.arr_ruler[3], R.arr_ruler[4]) then
    if m.wheel ~= 0 or m.hwheel ~= 0 then
      if m.cmd or m.alt then TL.zoom(v, m.wheel > 0 and 1.15 or 1 / 1.15, m.x, lane[1])
      else
        if m.hwheel ~= 0 or m.shift then TL.scroll(v, -(m.hwheel ~= 0 and m.hwheel or m.wheel) / 120 * 60 / v.ppb)
        else S.arr.scroll_y = S.arr.scroll_y - m.wheel / 120 * 48 end
      end
    end
  end

  -- active drag
  if D then
    local c = A.P.clip(D.clip_id)
    if not c then D = nil G.release() return end
    if not D.began and (math.abs(m.x - D.mx) > 3 or math.abs(m.y - D.my) > 3) then
      D.began = true C.begin_gesture(D.kind == "move" and "Move clip" or (D.kind == "resize" and "Resize clip" or "Trim clip"))
    end
    if D.began then
      if D.kind == "move" then
        local nb = U.snap(TL.x_to_beat(v, m.x, lane[1]) - D.grab, snap)
        nb = math.max(0, nb)
        local tgt = row_at(A, R, m.y)
        local tid = (tgt and tgt.kind == c.track.kind) and tgt.id or c.track_id
        if math.abs(nb - c.start) > 1e-6 or tid ~= c.track_id then C.move_clip(c.id, nb, tid) end
      elseif D.kind == "resize" then
        local e = to_beat(A, R, m.x, snap)
        local nl = math.max(snap > 0 and snap or 0.25, e - c.start)
        if math.abs(nl - c.len) > 1e-6 then C.resize_clip(c.id, nl) end
      elseif D.kind == "trim" then
        local ns = to_beat(A, R, m.x, snap)
        ns = math.min(ns, c.start + c.len - 0.25)
        if math.abs(ns - c.start) > 1e-6 then C.trim_clip_left(c.id, ns) end
      end
    end
    if m.released then
      if D.began then C.end_gesture() end
      D = nil G.release()
    end
    return
  end

  if not inside then return end
  if m.pressed or m.rpressed then S.focus = "arr" end
  local c, zone, t = clip_hit(A, R, m.x, m.y)
  if c then
    if zone == "right" then G.want_cursor("resize") elseif zone == "left" then G.want_cursor("resize") end
  end
  if m.pressed then
    if c then
      S.sel_clip, S.sel_track = c.id, c.track_id
      if c.kind == "midi" and m.dbl then A.open_clip(c.id) end
      local kind = zone == "right" and "resize" or (zone == "left" and "trim" or "move")
      D = { kind = kind, clip_id = c.id, mx = m.x, my = m.y, began = false,
        grab = TL.x_to_beat(v, m.x, lane[1]) - c.start }
      G.capture("arr_drag")
    else
      if t then S.sel_track = t.id end
      S.sel_clip = nil
      if m.dbl and t and t.kind == "midi" then A.new_clip_at(t.id, to_beat(A, R, m.x, 0)) end
    end
  elseif m.rpressed then
    if c then S.sel_clip, S.sel_track = c.id, c.track_id context_menu_clip(A, c)
    elseif t then S.sel_track = t.id context_menu_lane(A, t, to_beat(A, R, m.x, snap)) end
  end
end

local function handle_ruler(A, R)
  local S, m, TR = A.S, G.m, A.TR
  local rr = R.arr_ruler
  local v = S.arr.view
  local snap = S.arr_snap(bpb(A))
  local strip_h = 14
  local in_strip = G.over(rr[1], rr[2], rr[3], strip_h)
  local in_bar = G.over(rr[1], rr[2] + strip_h, rr[3], rr[4] - strip_h)
  if m.pressed and in_strip then
    local b = to_beat(A, R, m.x, snap)
    D = D -- (loop drag uses its own capture)
    A._loop_drag = { a = b, b = b, began = false, mx = m.x }
    G.capture("loop_drag")
  end
  if A._loop_drag and G.active == "loop_drag" then
    local ld = A._loop_drag
    if m.down then
      ld.b = to_beat(A, R, m.x, snap)
      if math.abs(m.x - ld.mx) > 3 then ld.began = true end
      if ld.began and math.abs(ld.b - ld.a) > 1e-6 then TR.set_loop(ld.a, ld.b) TR.set_loop_enabled(true) end
    else
      G.release()
      if not ld.began then TR.set_loop_enabled(not TR.loop_enabled()) end -- click on strip toggles loop
      A._loop_drag = nil
    end
  end
  if m.pressed and in_bar then
    TR.seek(to_beat(A, R, m.x, snap > 0 and snap or 0))
    G.capture("seek_drag")
  end
  if G.active == "seek_drag" then
    if m.down then TR.seek(to_beat(A, R, m.x, snap > 0 and snap or 0)) else G.release() end
  end
end

----------------------------------------------------------------------------- main draw
function Arr.draw(A, R)
  local S, T, P = A.S, G.theme, A.P
  local snap = P.snap
  local ax, ay, aw, ah = table.unpack(R.arr)
  A.R = R
  G.rect(ax, ay, aw, ah, T.bg)
  local v = S.arr.view
  local lane = R.arr_lanes
  local th = S.arr.track_h
  local ntracks = #snap.tracks
  local content_h = ntracks * th
  local max_scroll = math.max(0, content_h - lane[4])
  S.arr.scroll_y = U.clamp(S.arr.scroll_y, 0, max_scroll)

  -- ruler
  local rr = R.arr_ruler
  G.rect(rr[1], rr[2], rr[3], rr[4], T.panel)
  G.rect(R.arr_corner[1], R.arr_corner[2], R.arr_corner[3], R.arr_corner[4], T.panel)
  G.text("TRACKS", 12, R.arr_corner[2] + 14, T.faint, 10)
  G.push_clip(rr[1], rr[2], rr[3], rr[4])
  local lines = TL.grid_lines(v, rr[3], snap.num, snap.den)
  local bp = TL.beats_per_bar(snap.num, snap.den)
  for _, l in ipairs(lines) do
    local x = rr[1] + l.x
    if l.kind == "bar" then
      G.vline(x, rr[2] + 14, rr[4] - 14, T.line2)
      G.text(tostring(math.floor(l.beat / bp + 0.5) + 1), x + 4, rr[2] + 19, T.dim, 11)
    elseif l.kind == "beat" then G.vline(x, rr[2] + 28, rr[4] - 28, T.line) end
  end
  -- loop strip
  G.rect(rr[1], rr[2], rr[3], 14, T.panel2)
  local ls, le = A.TR.loop()
  if le > ls then
    local lx0, lx1 = TL.beat_to_x(v, ls, rr[1]), TL.beat_to_x(v, le, rr[1])
    local on = A.TR.loop_enabled()
    G.rect(lx0, rr[2], lx1 - lx0, 14, on and T.accent or T.line2, on and 0.85 or 0.5)
    G.text("loop", lx0 + 4, rr[2] + 1, on and { 20, 20, 24 } or T.dim, 10)
  end
  G.pop_clip()
  handle_ruler(A, R)

  -- headers + lanes
  local hdr = R.arr_headers
  G.push_clip(hdr[1], hdr[2], hdr[3], hdr[4])
  G.rect(hdr[1], hdr[2], hdr[3], hdr[4], T.panel2)
  local first = math.max(1, math.floor(S.arr.scroll_y / th) + 1)
  local last = math.min(ntracks, math.ceil((S.arr.scroll_y + lane[4]) / th) + 1)
  for i = first, last do
    local t = snap.tracks[i]
    local y = hdr[2] + (i - 1) * th - S.arr.scroll_y
    draw_header(A, t, y)
    if G.over(0, y, hdr[3] - 90, 36) then
      if G.m.pressed then S.sel_track = t.id S.focus = "arr" if G.m.dbl then G.prompt("Rename track", t.name, function(s) if s ~= "" then A.C.rename_track(t.id, s) end end) end end
      if G.m.rpressed then S.sel_track = t.id context_menu_track(A, t) end
    end
  end
  G.pop_clip()

  G.push_clip(lane[1], lane[2], lane[3], lane[4])
  G.rect(lane[1], lane[2], lane[3], lane[4], T.bg)
  for i = first, last do
    local t = snap.tracks[i]
    local y = lane[2] + (i - 1) * th - S.arr.scroll_y
    G.rect(lane[1], y, lane[3], th - 1, (S.sel_track == t.id) and T.panel2 or T.panel, 1)
    G.hline(lane[1], y + th - 1, lane[3], T.line)
  end
  for _, l in ipairs(TL.grid_lines(v, lane[3], snap.num, snap.den)) do
    local x = lane[1] + l.x
    G.vline(x, lane[2], lane[4], l.kind == "bar" and T.line2 or T.line, l.kind == "bar" and 0.9 or 0.45)
  end
  -- loop region overlay
  if le > ls then
    local lx0, lx1 = TL.beat_to_x(v, ls, lane[1]), TL.beat_to_x(v, le, lane[1])
    G.rect(lx0, lane[2], lx1 - lx0, lane[4], A.TR.loop_enabled() and T.accent or T.line2, 0.1)
    G.vline(lx0, lane[2], lane[4], T.accent, 0.6) G.vline(lx1, lane[2], lane[4], T.accent, 0.6)
  end
  for i = first, last do
    local t = snap.tracks[i]
    local y = lane[2] + (i - 1) * th - S.arr.scroll_y
    for _, c in ipairs(t.clips) do draw_clip(A, c, t, y) end
  end
  -- playhead
  local pos = A.TR.position()
  local px = TL.beat_to_x(v, pos, lane[1])
  if px >= lane[1] and px <= lane[1] + lane[3] then
    G.vline(px, lane[2], lane[4], T.red)
  end
  if ntracks == 0 then
    G.text("No tracks yet. Use  + Track  in the top bar to add a Drum Kit, Bass, Lead or Audio track.", lane[1] + 24, lane[2] + 30, T.dim, 13)
  end
  G.pop_clip()
  -- playhead marker in ruler
  G.push_clip(rr[1], rr[2], rr[3], rr[4])
  local rx = TL.beat_to_x(v, pos, rr[1])
  G.vline(rx, rr[2], rr[4], T.red)
  G.tri(rx - 5, rr[2] + 14, rx + 5, rr[2] + 14, rx, rr[2] + 22, T.red)
  G.pop_clip()

  handle_lanes(A, R)

  -- scrollbars
  local total_beats = math.max(snap.end_beat + 16, 32, v.x0 + lane[3] / v.ppb)
  local vis_beats = lane[3] / v.ppb
  local hs = R.arr_hsb
  local nx = G.scrollbar("arr_hsb", hs[1], hs[2], hs[3], hs[4], false, v.x0, vis_beats, total_beats)
  if G.active == "arr_hsb" then v.x0 = nx end
  local vs = R.arr_vsb
  local ny = G.scrollbar("arr_vsb", vs[1], vs[2], vs[3], vs[4], true, S.arr.scroll_y, lane[4], math.max(content_h, lane[4]))
  if G.active == "arr_vsb" then S.arr.scroll_y = ny end
  G.rect(R.arr_hsb[1] - R.arr_headers[3], R.arr_hsb[2], R.arr_headers[3], R.arr_hsb[4], T.panel)
  G.rect(vs[1], R.arr_ruler[2], vs[3], R.arr_ruler[4], T.panel)
  G.rect(vs[1], hs[2], vs[3], hs[4], T.panel)
end

function Arr.dragging() return D ~= nil end
return Arr
