-- mixer.lua : channel strips bound to real track volume/pan/mute/solo, real peak meters, FX indicators.
local G = require("ui.gx")
local U = require("util")
local M = {}
local STRIP_W = 96

local function lvl(l) return U.clamp((U.lin_to_db(l) + 60) / 66, 0, 1) end

local function strip(A, t, x, y, w, h, is_master)
  local T, C = G.theme, A.C
  local id = is_master and "master" or t.id
  local sel = A.S.sel_track == id
  G.rect(x, y, w - 4, h, sel and T.panel3 or T.panel2)
  if not is_master then G.rect(x, y, w - 4, 4, t.color) else G.rect(x, y, w - 4, 4, T.line2) end
  if G.over(x, y, w - 4, 34) and G.m.pressed and not is_master then A.S.sel_track = t.id end
  G.text(is_master and "Master" or t.name, x + 6, y + 8, T.text, 12, "l", w - 16)
  local sub = is_master and "" or (t.kind == "audio" and "audio" or t.inst)
  G.text(sub, x + 6, y + 22, T.dim, 10, "l", w - 16)
  local cy = y + 38
  -- FX slots
  local fxh = 13
  local nslots = math.max(0, math.min(4, math.floor((h - 38 - 24 - 24 - 60) / fxh)))
  if not is_master then
    for i = 1, nslots do
      local fx = t.fx[t.inst_count + i]
      local fy = cy + (i - 1) * fxh
      if fx then
        local bg = fx.enabled and T.accent2 or T.line
        G.rect(x + 4, fy, w - 12, fxh - 2, bg, fx.enabled and 0.55 or 0.5)
        G.text(fx.name, x + 7, fy, fx.enabled and T.text or T.faint, 10, "l", w - 18)
        if G.over(x + 4, fy, w - 12, fxh - 2) then
          G.tip("Click: bypass " .. fx.name)
          if G.m.pressed then C.toggle_fx(t.id, fx.idx) end
        end
      else G.rect(x + 4, fy, w - 12, fxh - 2, T.bg, 0.5) end
    end
    local extra = #t.fx - t.inst_count - nslots
    if extra > 0 then G.text("+" .. extra .. " more", x + 6, cy + nslots * fxh, T.dim, 10) end
  end
  cy = cy + nslots * fxh + 6
  -- pan
  local pan = is_master and reaper.GetMediaTrackInfo_Value(reaper.GetMasterTrack(0), "D_PAN") or t.pan
  if not is_master then
    local np, ph = G.slider("mpan" .. id, x + 6, cy, w - 16, 14, (pan + 1) / 2, { center = true, default = 0.5, color = T.dim, value_text = string.format("%+d", math.floor(pan * 100 + 0.5)), tip = "Pan" })
    if ph == "begin" then C.begin_gesture("Pan") end
    if ph then C.set_pan(t.id, np * 2 - 1) end
    if ph == "end" then C.end_gesture() end
  end
  cy = cy + 20
  -- fader + meter
  local fh = h - (cy - y) - 52
  fh = math.max(40, fh)
  local vol = is_master and reaper.GetMediaTrackInfo_Value(reaper.GetMasterTrack(0), "D_VOL") or t.vol
  local db = U.lin_to_db(vol)
  local tv = U.clamp((db + 60) / 72, 0, 1)
  local fx0 = x + 14
  local nt, ph = G.slider("mvol" .. id, fx0, cy, 26, fh, tv, { vertical = true, default = 60 / 72, color = is_master and T.line2 or t.color, tip = "Volume (dbl-click = 0 dB)" })
  local function setvol(v) if is_master then C.set_master_volume(v) else C.set_volume(t.id, v) end end
  if ph == "begin" then C.begin_gesture("Volume") end
  if ph then setvol(nt <= 0.001 and 0 or U.db_to_lin(nt * 72 - 60)) end
  if ph == "end" then C.end_gesture() end
  -- dB ticks
  for _, d in ipairs { 12, 6, 0, -6, -12, -24, -48 } do
    local ty = cy + fh - (d + 60) / 72 * fh
    G.hline(fx0 + 27, ty, 4, T.line2)
    if d % 12 == 0 or d == 6 then G.text(tostring(d), fx0 + 32, ty - 6, T.faint, 9) end
  end
  -- meter (real)
  local mt = A.meter(id)
  local mx = x + w - 30
  G.rect(mx, cy, 10, fh, T.bg)
  for ch = 0, 1 do
    local l = lvl(ch == 0 and mt.l or mt.r)
    local bx = mx + ch * 5
    G.rect(bx, cy + fh * (1 - l), 4, fh * l, l > 0.92 and T.red or (l > 0.75 and T.yellow or T.green))
  end
  local hold = lvl(mt.hold or 0)
  G.rect(mx, cy + fh * (1 - hold), 10, 2, T.text)
  cy = cy + fh + 4
  G.text(string.format("%.1f dB", db), x + 4, cy, T.text, 11, "c", w - 12)
  cy = cy + 16
  if not is_master then
    if G.button("mm" .. id, x + 8, cy, 34, 18, "M", { on = t.mute, on_color = T.yellow }) then C.set_mute(t.id, not t.mute) end
    if G.button("ms" .. id, x + 46, cy, 34, 18, "S", { on = t.solo, on_color = T.accent2 }) then C.set_solo(t.id, not t.solo) end
  end
end

function M.draw(A, R)
  local c = R.content
  local T = G.theme
  G.push_clip(c[1], c[2], c[3], c[4])
  G.rect(c[1], c[2], c[3], c[4], T.bg)
  local tracks = A.P.snap.tracks
  local x = c[1] + 6
  local h = c[4] - 8
  for _, t in ipairs(tracks) do
    strip(A, t, x, c[2] + 4, STRIP_W, h, false)
    x = x + STRIP_W
  end
  if #tracks == 0 then G.text("No tracks yet.", c[1] + 20, c[2] + 20, T.dim, 13) end
  strip(A, nil, c[1] + c[3] - STRIP_W - 6, c[2] + 4, STRIP_W, h, true)
  G.pop_clip()
end
return M
