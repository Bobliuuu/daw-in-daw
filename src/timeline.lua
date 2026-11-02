-- timeline.lua : pure musical-time <-> screen geometry. Unit = quarter-note "beat" (REAPER QN).
-- view = { x0 = beat at left edge, ppb = pixels per beat }
local U = require("util")
local T = {}
T.MIN_PPB, T.MAX_PPB = 4, 600

function T.new_view(ppb) return { x0 = 0, ppb = ppb or 40 } end
function T.beat_to_x(v, beat, rx) return (rx or 0) + (beat - v.x0) * v.ppb end
function T.x_to_beat(v, x, rx) return v.x0 + (x - (rx or 0)) / v.ppb end
function T.beats_per_bar(num, den) return (num or 4) * 4 / (den or 4) end

-- 1-based bar, 1-based beat inside bar (in signature-denominator units), fractional remainder 0..1
function T.bar_beat(beat, num, den)
  local bpb = T.beats_per_bar(num, den)
  local bar = math.floor(beat / bpb + 1e-9)
  local inbar = beat - bar * bpb
  local unit = 4 / (den or 4)
  local b = math.floor(inbar / unit + 1e-9)
  return bar + 1, b + 1, (inbar - b * unit) / unit
end

function T.zoom(v, factor, anchor_x, rx)
  local ab = T.x_to_beat(v, anchor_x, rx)
  v.ppb = U.clamp(v.ppb * factor, T.MIN_PPB, T.MAX_PPB)
  v.x0 = ab - (anchor_x - (rx or 0)) / v.ppb
  if v.x0 < 0 then v.x0 = 0 end
end

function T.scroll(v, dbeats) v.x0 = math.max(0, v.x0 + dbeats) end
function T.visible(v, width) return v.x0, v.x0 + width / v.ppb end

-- grid lines for the visible width: returns list of { x, kind } kind = "bar"|"beat"|"sub"
function T.grid_lines(v, width, num, den, sub)
  local out = {}
  local bpb = T.beats_per_bar(num, den)
  local unit = 4 / (den or 4)
  local b0, b1 = T.visible(v, width)
  local step = unit
  if sub and sub > 0 and sub * v.ppb >= 8 then step = math.min(sub, unit) end
  local n0 = math.floor(b0 / step)
  local n1 = math.ceil(b1 / step)
  local show_beats = unit * v.ppb >= 12
  for n = n0, n1 do
    local beat = n * step
    local x = (beat - v.x0) * v.ppb
    if x >= 0 and x <= width then
      local on_bar = U.near((beat / bpb) % 1, 0, 1e-6) or U.near((beat / bpb) % 1, 1, 1e-6)
      local on_beat = U.near((beat / unit) % 1, 0, 1e-6) or U.near((beat / unit) % 1, 1, 1e-6)
      local kind = on_bar and "bar" or (on_beat and "beat" or "sub")
      if kind == "bar" or (kind == "beat" and show_beats) or kind == "sub" then out[#out + 1] = { x = x, kind = kind, beat = beat } end
    end
  end
  return out
end

-- piano roll vertical: pv = { top = highest visible pitch (float), row_h }
function T.pitch_to_y(pv, pitch, ry) return (ry or 0) + (pv.top - pitch) * pv.row_h end
function T.y_to_pitch(pv, y, ry) return math.floor(pv.top - (y - (ry or 0)) / pv.row_h) end
function T.clamp_pitch_view(pv, view_h)
  local rows = view_h / pv.row_h
  pv.top = U.clamp(pv.top, math.min(127, rows - 1), 127)
end

-- note hit test: notes = { {pitch, s, e} ... }, returns index, zone ("body"|"left"|"right")
function T.hit_note(notes, v, pv, x, y, rx, ry, edge_px)
  edge_px = edge_px or 5
  for i = #notes, 1, -1 do
    local n = notes[i]
    local nx = T.beat_to_x(v, n.s, rx)
    local nw = (n.e - n.s) * v.ppb
    local ny = T.pitch_to_y(pv, n.pitch, ry)
    if U.pt_in(x, y, nx, ny, nw, pv.row_h) then
      local zone = "body"
      if nw > edge_px * 2.5 then
        if x >= nx + nw - edge_px then zone = "right" elseif x <= nx + edge_px then zone = "left" end
      end
      return i, zone
    end
  end
end

return T
