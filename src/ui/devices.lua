-- devices.lua : instrument + FX chain of the selected track; every slider writes a real FX parameter.
local G = require("ui.gx")
local E = require("audio.effects")
local I = require("audio.instruments")
local U = require("util")
local r = reaper
local Dv = {}
local scroll = 0

function Dv.draw(A, R)
  local c = R.content
  local S, P, C, T = A.S, A.P, A.C, G.theme
  G.push_clip(c[1], c[2], c[3], c[4])
  G.rect(c[1], c[2], c[3], c[4], T.bg)
  local t = S.sel_track and P.track(S.sel_track)
  if not t then
    G.text("Select a track to see its instrument and effects.", c[1] + 20, c[2] + 20, T.dim, 13)
    G.pop_clip() return
  end
  local lw = 250
  G.rect(c[1], c[2], lw, c[4], T.panel)
  G.text(t.name, c[1] + 10, c[2] + 8, T.text, 13, "l", lw - 20)
  G.rect(c[1], c[2], 4, 30, t.color)
  -- chain list
  local y = c[2] + 32
  local rowh = 22
  local avail = c[4] - 32 - 34
  G.push_clip(c[1], y, lw, avail)
  for i, fx in ipairs(t.fx) do
    local ry = y + (i - 1) * rowh - scroll
    local sel = S.fx_sel == fx.idx
    G.rect(c[1] + 4, ry, lw - 8, rowh - 2, sel and T.panel3 or T.panel2)
    if sel then G.rect(c[1] + 4, ry, 3, rowh - 2, T.accent) end
    local on = fx.enabled
    if G.button("fxon" .. fx.idx, c[1] + 10, ry + 3, 16, 14, nil, { on = on, on_color = T.green, tip = on and "Bypass" or "Enable", draw = function(x, yy, w, h) end }) then C.toggle_fx(t.id, fx.idx) end
    G.text((fx.is_inst and "" or "") .. fx.name, c[1] + 32, ry + 4, on and T.text or T.faint, 12, "l", fx.is_inst and (lw - 50) or (lw - 112))
    if G.over(c[1] + 30, ry, lw - 120, rowh - 2) and G.m.pressed then S.fx_sel = fx.idx end
    if not fx.is_inst then
      local bx = c[1] + lw - 78
      if G.button("fxup" .. fx.idx, bx, ry + 2, 20, 18, nil, { tip = "Move up", draw = function(x, yy, w, h, col) G.tri(x + 5, yy + 12, x + 15, yy + 12, x + 10, yy + 5, col) end }) then C.move_fx(t.id, fx.idx, -1) end
      if G.button("fxdn" .. fx.idx, bx + 24, ry + 2, 20, 18, nil, { tip = "Move down", draw = function(x, yy, w, h, col) G.tri(x + 5, yy + 6, x + 15, yy + 6, x + 10, yy + 13, col) end }) then C.move_fx(t.id, fx.idx, 1) end
      if G.button("fxdel" .. fx.idx, bx + 48, ry + 2, 20, 18, "x", { tip = "Remove effect", color = T.red }) then C.remove_fx(t.id, fx.idx) if S.fx_sel == fx.idx then S.fx_sel = nil end end
    end
  end
  G.pop_clip()
  -- add effect
  if G.button("addfx", c[1] + 8, c[2] + c[4] - 30, 110, 24, "+ Effect", { bg = T.accent, color = { 20, 20, 24 } }) then
    local items = {}
    for _, e in ipairs(E.CATALOG) do items[#items + 1] = { label = e.label .. "  (" .. e.plugin .. ")", fn = function() A.safe(C.add_effect, t.id, e.id) S.fx_sel = #t.fx end } end
    G.popup(items, c[1] + 8, c[2] + c[4] - 30 - #items * 22 - 8)
  end
  if t.kind == "midi" and t.inst ~= "Drum Kit" then
    if G.button("preset", c[1] + 124, c[2] + c[4] - 30, 118, 24, "Preset: " .. (t.inst ~= "" and t.inst or "?"), { size = 11 }) then
      local items = {}
      for _, nm in ipairs(I.CATALOG) do if nm ~= "Drum Kit" then items[#items + 1] = { label = nm, checked = nm == t.inst, fn = function() C.set_preset(t.id, nm) end } end end
      G.popup(items, c[1] + 124, c[2] + c[4] - 30 - #items * 22 - 8)
    end
  end
  -- params of selected fx
  local px = c[1] + lw + 16
  local fxsel = S.fx_sel
  if (fxsel == nil or fxsel >= #t.fx) and #t.fx > 0 then fxsel = (t.inst_count < #t.fx) and t.inst_count or 0 end
  if #t.fx == 0 then G.text(t.kind == "audio" and "Audio track: add effects with + Effect." or "No devices.", px, c[2] + 14, T.dim, 13) G.pop_clip() return end
  local fx = t.fx[(fxsel or 0) + 1]
  if fx then
    G.text(fx.name .. "   (" .. fx.plugin .. ")", px, c[2] + 8, T.text, 13)
    local params = E.params(t.ptr, fx.idx)
    local colw, rh = 270, 26
    local per_col = math.max(1, math.floor((c[4] - 40) / rh))
    for i, p in ipairs(params) do
      local col = math.floor((i - 1) / per_col)
      local row = (i - 1) % per_col
      local x = px + col * (colw + 12)
      local y2 = c[2] + 34 + row * rh
      if x + colw < c[1] + c[3] then
        local tn = (p.max - p.min) > 0 and (p.value - p.min) / (p.max - p.min) or 0
        local nt, ph = G.slider("fxp" .. fx.idx .. "_" .. p.idx, x, y2, colw, 20, tn, { label = p.name, value_text = p.text, color = T.accent2, tip = "Drag to edit (Shift = fine)", fine_ref = tn })
        if ph == "begin" then C.begin_gesture("Edit effect") end
        if ph then C.set_fx_param(t.id, fx.idx, p.idx, p.min + nt * (p.max - p.min)) end
        if ph == "end" then C.end_gesture() end
      end
    end
  end
  G.pop_clip()
end
return Dv
