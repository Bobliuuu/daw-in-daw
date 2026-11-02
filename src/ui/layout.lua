-- layout.lua : pure geometry (unit-tested). All rects are {x, y, w, h} in logical pixels.
local U = require("util")
local L = {}
L.TRANSPORT_H, L.STATUS_H, L.SPLIT_H, L.RULER_H, L.SB = 48, 22, 6, 38, 12
L.MIN_ARR_H, L.MIN_BOTTOM_H = 140, 130

function L.compute(W, H, S)
  local R = {}
  R.transport = { 0, 0, W, L.TRANSPORT_H }
  R.status = { 0, H - L.STATUS_H, W, L.STATUS_H }
  local avail = H - L.TRANSPORT_H - L.STATUS_H
  local bh = U.clamp(S.bottom_h, L.MIN_BOTTOM_H, math.max(L.MIN_BOTTOM_H, avail - L.MIN_ARR_H - L.SPLIT_H))
  local ah = math.max(60, avail - bh - L.SPLIT_H)
  R.arr = { 0, L.TRANSPORT_H, W, ah }
  R.split = { 0, L.TRANSPORT_H + ah, W, L.SPLIT_H }
  R.bottom = { 0, L.TRANSPORT_H + ah + L.SPLIT_H, W, bh }
  -- arrangement internals
  local hw = math.min(S.arr.header_w, math.max(120, W * 0.3))
  local ax, ay, aw, ah2 = R.arr[1], R.arr[2], R.arr[3], R.arr[4]
  R.arr_ruler = { hw, ay, aw - hw - L.SB, L.RULER_H }
  R.arr_corner = { 0, ay, hw, L.RULER_H }
  R.arr_headers = { 0, ay + L.RULER_H, hw, ah2 - L.RULER_H - L.SB }
  R.arr_lanes = { hw, ay + L.RULER_H, aw - hw - L.SB, ah2 - L.RULER_H - L.SB }
  R.arr_vsb = { aw - L.SB, ay + L.RULER_H, L.SB, ah2 - L.RULER_H - L.SB }
  R.arr_hsb = { hw, ay + ah2 - L.SB, aw - hw - L.SB, L.SB }
  -- bottom panel: tab strip + content
  R.tabs = { 0, R.bottom[2], W, 26 }
  R.content = { 0, R.bottom[2] + 26, W, bh - 26 }
  -- piano roll internals
  local cx, cy, cw, ch = R.content[1], R.content[2], R.content[3], R.content[4]
  local keyw, velh = 56, math.min(70, math.max(40, ch * 0.22))
  R.roll_keys = { cx, cy, keyw, ch - velh - L.SB }
  R.roll_grid = { cx + keyw, cy, cw - keyw - L.SB, ch - velh - L.SB }
  R.roll_vsb = { cx + cw - L.SB, cy, L.SB, ch - velh - L.SB }
  R.roll_vel = { cx + keyw, cy + ch - velh - L.SB, cw - keyw - L.SB, velh }
  R.roll_hsb = { cx + keyw, cy + ch - L.SB, cw - keyw - L.SB, L.SB }
  return R
end

function L.contains(r, x, y) return x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] end
return L
