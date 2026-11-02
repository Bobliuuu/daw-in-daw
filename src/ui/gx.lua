-- gx.lua : tiny immediate-mode UI toolkit on top of REAPER's gfx API (pure Lua).
--   * logical pixel coordinates; HiDPI scale K applied inside every primitive
--   * software clip-rect stack (gfx has none)
--   * one input model: per-frame mouse/key state, id-based mouse capture, modal/popup layers that block lower widgets
--   * widgets: button, toggle, slider, scrollbar, popup menu, text prompt, confirm dialog, tooltip
local U = require("util")
local G = { K = 1, W = 800, H = 600 }

----------------------------------------------------------------------------- theme
G.theme = {
  bg = { 22, 23, 27 }, panel = { 30, 32, 38 }, panel2 = { 38, 40, 48 }, panel3 = { 46, 49, 58 },
  line = { 58, 62, 72 }, line2 = { 74, 79, 92 }, text = { 222, 225, 232 }, dim = { 140, 146, 158 }, faint = { 92, 97, 108 },
  accent = { 255, 140, 66 }, accent2 = { 90, 200, 190 }, red = { 235, 80, 80 }, green = { 110, 210, 120 }, yellow = { 240, 200, 70 },
  black_key = { 28, 29, 34 }, white_key = { 50, 53, 62 },
}

----------------------------------------------------------------------------- state
G.m = { x = -1, y = -1, down = false, rdown = false, pressed = false, released = false, rpressed = false, rreleased = false,
  dbl = false, wheel = 0, hwheel = 0, shift = false, cmd = false, alt = false, moved = false, mdown = false }
G.keys = {}
G.active = nil
G.reg = {}
G.modal = nil
G.popup_ = nil
G.now = 0
G.tip_text, G.tip_since, G.tip_pos = nil, 0, { 0, 0 }
G.cursor_req = nil

local clip_stack, cur = {}, nil
local last_press_t, last_press_x, last_press_y = 0, 0, 0
local pm = { x = -1, y = -1, down = false, rdown = false }

-- test hook: replace to feed synthetic input (fn(m, keys) must fill G.m and G.keys; return false to close)
G.input_source = nil

local SPECIAL = {
  [8] = "backspace", [13] = "enter", [27] = "esc", [9] = "tab", [32] = "space", [127] = "backspace",
  [1818584692] = "left", [1919379572] = "right", [30064] = "up", [1685026670] = "down",
  [1752132965] = "home", [6647396] = "end", [1885824110] = "pageup", [1936611694] = "pagedown", [6579564] = "delete",
}

local function poll_gfx(m, keys)
  m.x, m.y = gfx.mouse_x / G.K, gfx.mouse_y / G.K
  local cap = gfx.mouse_cap
  m.down, m.rdown, m.mdown = cap & 1 ~= 0, cap & 2 ~= 0, cap & 64 ~= 0
  m.cmd, m.shift, m.alt = cap & 4 ~= 0, cap & 8 ~= 0, cap & 16 ~= 0
  m.ctrl = cap & 32 ~= 0
  m.wheel, m.hwheel = gfx.mouse_wheel, gfx.mouse_hwheel
  gfx.mouse_wheel, gfx.mouse_hwheel = 0, 0
  while true do
    local c = gfx.getchar()
    if c == -1 then return false end
    if c == 0 then break end
    local k = { code = c, name = SPECIAL[c], cmd = m.cmd, shift = m.shift, alt = m.alt }
    if not k.name and c >= 32 and c < 0x110000 then
      k.ch = utf8.char(c)
      k.lower = k.ch:lower()
    elseif not k.name and c >= 1 and c <= 26 then -- ctrl+letter on some platforms
      k.cmd = true k.lower = string.char(96 + c) k.ch = k.lower
    end
    keys[#keys + 1] = k
  end
  return true
end

-- returns false if the window was closed
function G.begin_frame()
  G.now = reaper.time_precise()
  local m = G.m
  pm.x, pm.y, pm.down, pm.rdown = m.x, m.y, m.down, m.rdown
  G.keys = {}
  local alive
  if G.input_source then alive = G.input_source(m, G.keys) ~= false else alive = poll_gfx(m, G.keys) end
  m.pressed = m.down and not pm.down
  m.released = not m.down and pm.down
  m.rpressed = m.rdown and not pm.rdown
  m.rreleased = not m.rdown and pm.rdown
  m.moved = (m.x ~= pm.x or m.y ~= pm.y)
  m.dbl = false
  if m.pressed then
    if G.now - last_press_t < 0.35 and math.abs(m.x - last_press_x) < 5 and math.abs(m.y - last_press_y) < 5 then m.dbl = true last_press_t = 0
    else last_press_t = G.now end
    last_press_x, last_press_y = m.x, m.y
  end
  if m.moved then G.tip_since = G.now end
  G.tip_text = nil
  G.blocked = (G.modal ~= nil or G.popup_ ~= nil)
  clip_stack, cur = {}, { 0, 0, G.W, G.H }
  G.cursor_req = nil
  return alive
end

function G.resize()
  G.K = (gfx.ext_retina and gfx.ext_retina > 0) and gfx.ext_retina or 1
  G.W, G.H = gfx.w / G.K, gfx.h / G.K
end

----------------------------------------------------------------------------- drawing primitives
local function setc(c, a) gfx.set(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end
G.setc = setc

function G.push_clip(x, y, w, h)
  clip_stack[#clip_stack + 1] = cur
  local x2, y2 = x + w, y + h
  cur = { math.max(cur[1], x), math.max(cur[2], y), math.min(cur[3], x2), math.min(cur[4], y2) }
end
function G.pop_clip() cur = table.remove(clip_stack) or { 0, 0, G.W, G.H } end
function G.clip_rect() return cur end

function G.rect(x, y, w, h, c, a)
  local x1, y1, x2, y2 = math.max(x, cur[1]), math.max(y, cur[2]), math.min(x + w, cur[3]), math.min(y + h, cur[4])
  if x2 <= x1 or y2 <= y1 then return end
  setc(c, a)
  local K = G.K
  gfx.rect(math.floor(x1 * K + 0.5), math.floor(y1 * K + 0.5), math.max(1, math.floor((x2 - x1) * K + 0.5)), math.max(1, math.floor((y2 - y1) * K + 0.5)), 1)
end
function G.frame(x, y, w, h, c, a)
  G.rect(x, y, w, 1, c, a) G.rect(x, y + h - 1, w, 1, c, a)
  G.rect(x, y, 1, h, c, a) G.rect(x + w - 1, y, 1, h, c, a)
end
function G.hline(x, y, w, c, a) G.rect(x, y, w, 1, c, a) end
function G.vline(x, y, h, c, a) G.rect(x, y, 1, h, c, a) end
function G.tri(x1, y1, x2, y2, x3, y3, c, a)
  setc(c, a) local K = G.K
  gfx.triangle(x1 * K, y1 * K, x2 * K, y2 * K, x3 * K, y3 * K)
end

local font_slots, cur_font, nslots = {}, nil, 0
local function use_font(size)
  local key = size
  local slot = font_slots[key]
  if not slot then nslots = nslots + 1 slot = nslots font_slots[key] = slot gfx.setfont(slot, "Arial", math.floor(size * G.K + 0.5)) end
  if cur_font ~= slot or true then gfx.setfont(slot) cur_font = slot end
end
function G.reset_fonts() font_slots, cur_font, nslots = {}, nil, 0 end

function G.text_w(s, size) use_font(size or 12) local w = gfx.measurestr(s) return w / G.K end
-- align: "l" | "c" | "r" ; maxw optional clip width
function G.text(s, x, y, c, size, align, maxw, a)
  size = size or 12
  if s == nil or s == "" then return end
  s = tostring(s)
  use_font(size)
  local tw, th = gfx.measurestr(s) tw = tw / G.K th = th / G.K
  local bx = x
  if align == "c" and maxw then bx = x + (maxw - tw) / 2 elseif align == "r" and maxw then bx = x + maxw - tw end
  if bx < cur[1] or y < cur[2] or y > cur[4] or bx > cur[3] then return end
  local right = cur[3]
  if maxw then right = math.min(right, x + maxw) end
  setc(c or G.theme.text, a)
  gfx.x, gfx.y = math.floor(bx * G.K + 0.5), math.floor(y * G.K + 0.5)
  gfx.drawstr(s, 0, math.floor(right * G.K), math.floor(cur[4] * G.K))
end

----------------------------------------------------------------------------- hit testing / capture
function G.inside(x, y, w, h, px, py)
  px, py = px or G.m.x, py or G.m.y
  return px >= x and px < x + w and py >= y and py < y + h
end
-- true when the mouse is over the rect AND over the visible (clipped) part AND no modal blocks it
function G.over(x, y, w, h)
  if G.blocked then return false end
  local m = G.m
  if not G.inside(x, y, w, h) then return false end
  return m.x >= cur[1] and m.x < cur[3] and m.y >= cur[2] and m.y < cur[4]
end
function G.capture(id) G.active = id end
function G.release() G.active = nil end
function G.is_active(id) return G.active == id end
function G.tip(s) if s and G.tip_text == nil then G.tip_text = s end end
function G.want_cursor(name) G.cursor_req = name end

----------------------------------------------------------------------------- widgets
function G.button(id, x, y, w, h, label, o)
  o = o or {}
  G.reg[id] = { x, y, w, h }
  local m, T = G.m, G.theme
  local hov = (not o.disabled) and G.over(x, y, w, h)
  local act = G.active == id
  local bg = o.bg or T.panel3
  if o.on then bg = o.on_color or T.accent end
  if o.disabled then bg = T.panel2
  elseif act and hov then bg = T.line2
  elseif hov then bg = { math.min(255, bg[1] + 18), math.min(255, bg[2] + 18), math.min(255, bg[3] + 18) } end
  G.rect(x, y, w, h, bg)
  if o.border then G.frame(x, y, w, h, T.line2) end
  local tc = o.disabled and T.faint or (o.on and (o.on_text or { 20, 20, 24 }) or (o.color or T.text))
  if o.draw then o.draw(x, y, w, h, tc, hov) elseif label then G.text(label, x, y + (h - (o.size or 12)) / 2 - 1, tc, o.size or 12, "c", w) end
  if hov then G.tip(o.tip) end
  if hov and m.pressed and not o.disabled then G.active = id end
  if G.active == id and m.released then
    G.active = nil
    return hov and not o.disabled
  end
  return false
end

-- normalized slider. returns newT, phase ("begin" | "drag" | "end" | nil)
function G.slider(id, x, y, w, h, t, o)
  o = o or {}
  G.reg[id] = { x, y, w, h }
  local m, T = G.m, G.theme
  local vertical = o.vertical
  local hov = G.over(x, y, w, h)
  local phase
  if hov and m.pressed then
    G.active = id phase = "begin"
    if o.default and m.dbl then t = o.default phase = "begin" end
  end
  if G.active == id then
    if m.down or phase == "begin" then
      local nt
      if vertical then nt = 1 - (m.y - y - 2) / math.max(1, h - 4) else nt = (m.x - x - 2) / math.max(1, w - 4) end
      if not (o.default and m.dbl) then
        if m.shift and o.fine_ref then nt = o.fine_ref + (nt - o.fine_ref) * 0.2 end
        t = U.clamp(nt, 0, 1)
      end
      phase = phase or "drag"
    end
    if m.released then G.active = nil phase = "end" end
  end
  -- draw
  local fill = o.color or T.accent
  G.rect(x, y, w, h, o.bg or T.panel2)
  if vertical then
    local fh = (h - 2) * t
    G.rect(x + 1, y + h - 1 - fh, w - 2, fh, fill, 0.9)
    G.rect(x, y + h - 1 - fh - 1, w, 3, T.text)
  else
    if o.center then
      local cx = x + w / 2
      local px = x + 1 + (w - 2) * t
      G.rect(math.min(cx, px), y + 1, math.abs(px - cx), h - 2, fill, 0.9)
      G.rect(px - 1, y, 2, h, T.text)
    else
      G.rect(x + 1, y + 1, (w - 2) * t, h - 2, fill, 0.9)
      G.rect(x + 1 + (w - 2) * t - 1, y, 2, h, T.text)
    end
  end
  if o.label then G.text(o.label, x + 4, y + (h - 11) / 2 - 1, T.text, 11, "l", w - 8) end
  if o.value_text then G.text(o.value_text, x, y + (h - 11) / 2 - 1, T.text, 11, "r", w - 4) end
  if hov then G.tip(o.tip) end
  return t, phase
end

-- scrollbar: pos/view/content in content units. returns new pos
function G.scrollbar(id, x, y, w, h, vertical, pos, view, content)
  local T, m = G.theme, G.m
  G.rect(x, y, w, h, T.panel2)
  if content <= view + 1e-6 then return 0 end
  local len = vertical and h or w
  local thumb = math.max(16, len * view / content)
  local range = len - thumb
  local maxpos = content - view
  pos = U.clamp(pos, 0, maxpos)
  local tp = range * pos / maxpos
  local tx, ty, tw, th
  if vertical then tx, ty, tw, th = x, y + tp, w, thumb else tx, ty, tw, th = x + tp, y, thumb, h end
  local hov = G.over(tx, ty, tw, th)
  if (hov or G.over(x, y, w, h)) and m.pressed then
    G.active = id
    if not hov then -- jump
      local c = vertical and (m.y - y - thumb / 2) or (m.x - x - thumb / 2)
      pos = U.clamp(c / range * maxpos, 0, maxpos)
      tp = range * pos / maxpos
    end
    G.sb_grab = (vertical and m.y or m.x) - (vertical and y or x) - tp
  end
  if G.active == id then
    if m.down then
      local c = (vertical and m.y or m.x) - (vertical and y or x) - (G.sb_grab or 0)
      pos = U.clamp(c / range * maxpos, 0, maxpos)
      tp = range * pos / maxpos
    else G.active = nil end
  end
  if vertical then ty = y + tp else tx = x + tp end
  G.rect(tx + 1, ty + 1, tw - 2, th - 2, (G.active == id or hov) and T.line2 or T.line)
  return pos
end

----------------------------------------------------------------------------- overlays: popup / prompt / confirm / tooltip
-- items: { {label=, fn=, disabled=, sep=true, checked=} ... }
function G.popup(items, x, y)
  G.popup_ = { items = items, x = x, y = y, born = G.now }
  G.active = nil
end
function G.close_popup() G.popup_ = nil end

function G.prompt(title, initial, on_ok, o)
  initial = initial or ""
  G.modal = { kind = "prompt", title = title, text = initial, cur = #initial, on_ok = on_ok, sel_all = true, hint = o and o.hint, numeric = o and o.numeric }
  G.active = nil
end
function G.confirm(msg, on_yes, yes_label)
  G.modal = { kind = "confirm", msg = msg, on_yes = on_yes, yes = yes_label or "OK" }
  G.active = nil
end
-- custom modal: draw(x,y,w,h) called each frame inside the dialog box; handle returns "close" to dismiss
function G.dialog(title, w, h, draw, on_key)
  G.modal = { kind = "dialog", title = title, w = w, h = h, draw = draw, on_key = on_key }
  G.active = nil
end
function G.close_modal() G.modal = nil end

local function draw_popup()
  local p, T, m = G.popup_, G.theme, G.m
  local iw, ih = 0, 22
  for _, it in ipairs(p.items) do iw = math.max(iw, G.text_w(it.label or "", 12) + 36) end
  iw = math.max(iw, 140)
  local total = 0
  for _, it in ipairs(p.items) do total = total + (it.sep and 7 or ih) end
  local x, y = math.min(p.x, G.W - iw - 4), math.min(p.y, G.H - total - 4)
  G.rect(x + 2, y + 2, iw, total, { 0, 0, 0 }, 0.35)
  G.rect(x, y, iw, total, T.panel3) G.frame(x, y, iw, total, T.line2)
  local cy, picked = y, nil
  local inside = G.inside(x, y, iw, total)
  for _, it in ipairs(p.items) do
    if it.sep then G.hline(x + 6, cy + 3, iw - 12, T.line2) cy = cy + 7
    else
      G.reg["popup:" .. (it.label or "")] = { x, cy, iw, ih }
      local hov = inside and G.inside(x, cy, iw, ih) and not it.disabled
      if hov then G.rect(x + 1, cy, iw - 2, ih, T.accent, 0.9) end
      G.text((it.checked and "x  " or "") .. it.label, x + 12, cy + 5, it.disabled and T.faint or (hov and { 20, 20, 24 } or T.text), 12, "l", iw - 16)
      if hov and m.pressed then picked = it end
      cy = cy + ih
    end
  end
  if picked then G.popup_ = nil if picked.fn then picked.fn() end
  elseif (m.pressed or m.rpressed) and not inside and G.now - p.born > 0.05 then G.popup_ = nil
  else
    for _, k in ipairs(G.keys) do if k.name == "esc" then G.popup_ = nil end end
  end
end

local function draw_modal()
  local d, T, m = G.modal, G.theme, G.m
  G.rect(0, 0, G.W, G.H, { 0, 0, 0 }, 0.55)
  if d.kind == "prompt" then
    local w, h = 380, 130
    local x, y = (G.W - w) / 2, (G.H - h) / 2 - 40
    G.rect(x, y, w, h, T.panel2) G.frame(x, y, w, h, T.line2)
    G.text(d.title, x + 16, y + 14, T.text, 14)
    if d.hint then G.text(d.hint, x + 16, y + 34, T.dim, 11, "l", w - 32) end
    G.rect(x + 16, y + 56, w - 32, 28, T.bg) G.frame(x + 16, y + 56, w - 32, 28, T.accent)
    local shown = d.text
    if d.sel_all and shown ~= "" then G.rect(x + 20, y + 60, G.text_w(shown, 13) + 2, 20, T.accent, 0.35) end
    G.text(shown, x + 21, y + 62, T.text, 13)
    local cx = x + 21 + G.text_w(shown:sub(1, d.cur), 13)
    if math.floor(G.now * 2) % 2 == 0 then G.rect(cx, y + 61, 1, 18, T.text) end
    local ok = G.button("modal_ok", x + w - 190, y + h - 36, 80, 26, "OK", { bg = T.accent, color = { 20, 20, 24 } })
    local cancel = G.button("modal_cancel", x + w - 100, y + h - 36, 84, 26, "Cancel")
    local submit = ok
    for _, k in ipairs(G.keys) do
      if k.name == "enter" then submit = true
      elseif k.name == "esc" then G.modal = nil return
      elseif k.name == "backspace" then
        if d.sel_all then d.text = "" d.cur = 0 d.sel_all = false
        elseif d.cur > 0 then d.text = d.text:sub(1, d.cur - 1) .. d.text:sub(d.cur + 1) d.cur = d.cur - 1 end
      elseif k.name == "delete" then d.text = d.text:sub(1, d.cur) .. d.text:sub(d.cur + 2)
      elseif k.name == "left" then d.cur = math.max(0, d.cur - 1) d.sel_all = false
      elseif k.name == "right" then d.cur = math.min(#d.text, d.cur + 1) d.sel_all = false
      elseif k.name == "home" then d.cur = 0 d.sel_all = false
      elseif k.name == "end" then d.cur = #d.text d.sel_all = false
      elseif k.ch and not k.cmd and #k.ch == 1 then
        if not d.numeric or k.ch:match("[%d%.%-]") then
          if d.sel_all then d.text = "" d.cur = 0 d.sel_all = false end
          d.text = d.text:sub(1, d.cur) .. k.ch .. d.text:sub(d.cur + 1) d.cur = d.cur + 1
        end
      end
    end
    if cancel then G.modal = nil return end
    if submit then local cb, txt = d.on_ok, d.text G.modal = nil if cb then cb(txt) end end
  elseif d.kind == "confirm" then
    local w, h = 400, 120
    local x, y = (G.W - w) / 2, (G.H - h) / 2 - 40
    G.rect(x, y, w, h, T.panel2) G.frame(x, y, w, h, T.line2)
    G.text(d.msg, x + 16, y + 18, T.text, 13, "l", w - 32)
    local yes = G.button("modal_yes", x + w - 190, y + h - 40, 100, 28, d.yes, { bg = T.red, color = { 255, 255, 255 } })
    local no = G.button("modal_no", x + w - 84, y + h - 40, 68, 28, "Cancel")
    for _, k in ipairs(G.keys) do if k.name == "esc" then no = true end end
    if no then G.modal = nil elseif yes then local cb = d.on_yes G.modal = nil if cb then cb() end end
  else -- dialog
    local w, h = d.w, d.h
    local x, y = (G.W - w) / 2, math.max(8, (G.H - h) / 2 - 20)
    G.rect(x, y, w, h, T.panel2) G.frame(x, y, w, h, T.line2)
    G.rect(x, y, w, 30, T.panel3)
    G.text(d.title, x + 14, y + 8, T.text, 13, "l", w - 60)
    if G.button("dlg_close", x + w - 30, y + 3, 24, 24, "x") then G.modal = nil return end
    G.push_clip(x, y + 30, w, h - 30)
    local res = d.draw(x, y + 30, w, h - 30)
    G.pop_clip()
    for _, k in ipairs(G.keys) do
      if k.name == "esc" then G.modal = nil return end
      if d.on_key then d.on_key(k) end
    end
    if res == "close" then G.modal = nil end
  end
end

function G.end_frame()
  local m = G.m
  -- overlays are processed with the raw input; lower layers saw blocked=true
  G.blocked = false
  if G.modal then draw_modal() end
  if G.popup_ then draw_popup() end
  if G.tip_text and G.now - G.tip_since > 0.5 and not G.modal and not G.popup_ then
    local s = G.tip_text
    local w = G.text_w(s, 11) + 12
    local x, y = math.min(m.x + 12, G.W - w - 4), math.min(m.y + 18, G.H - 24)
    G.rect(x, y, w, 20, { 12, 12, 14 }) G.frame(x, y, w, 20, G.theme.line2)
    G.text(s, x + 6, y + 4, G.theme.text, 11)
  end
end

return G
