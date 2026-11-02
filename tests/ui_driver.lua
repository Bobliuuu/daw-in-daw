-- ui_driver.lua : drives the REAL app frame loop (App A.step) with synthetic mouse/keyboard input.
-- Everything below the input layer (hit testing, widgets, dialogs, commands, REAPER edits) is the production code path.
local r = reaper
local D = {}
local G, A, App

local st = { x = 0, y = 0, down = false, rdown = false, cmd = false, shift = false, alt = false, wheel = 0, hwheel = 0 }
local keyq = {}

local function source(m, keys)
  m.x, m.y, m.down, m.rdown = st.x, st.y, st.down, st.rdown
  m.cmd, m.shift, m.alt = st.cmd, st.shift, st.alt
  m.wheel, m.hwheel = st.wheel, st.hwheel
  st.wheel, st.hwheel = 0, 0
  for _, k in ipairs(keyq) do keys[#keys + 1] = k end
  keyq = {}
  return true
end

function D.start(opts)
  opts = opts or {}
  App = require("app")
  G = require("ui.gx")
  G.input_source = source
  A = App.start({ w = opts.w or 1280, h = opts.h or 800, no_singleton = true, headless = true })
  D.A, D.G = A, G
  D.frames(2) -- first frames populate layout + widget registry
  return A
end

function D.frames(n)
  for _ = 1, n or 1 do
    local ok, alive = xpcall(A.step, debug.traceback)
    if not ok then error(alive, 0) end
  end
end

function D.move(x, y) st.x, st.y = x, y D.frames(1) end
function D.press(btn) if btn == 2 then st.rdown = true else st.down = true end D.frames(1) end
function D.release(btn) if btn == 2 then st.rdown = false else st.down = false end D.frames(1) end
function D.mods(cmd, shift, alt) st.cmd, st.shift, st.alt = cmd or false, shift or false, alt or false end
function D.click(x, y, btn)
  D.move(x, y) D.press(btn) D.release(btn)
end
function D.dblclick(x, y) D.click(x, y) D.click(x, y) end
function D.drag(x1, y1, x2, y2, steps, btn)
  steps = steps or 8
  D.move(x1, y1) D.press(btn)
  for i = 1, steps do D.move(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps) end
  D.release(btn)
end
function D.wheel(x, y, dy, dx) D.move(x, y) st.wheel, st.hwheel = dy or 0, dx or 0 D.frames(1) end

local NAMES = { space = 32, enter = 13, esc = 27, backspace = 8, delete = 127, left = 1818584692, right = 1919379572, up = 30064, down = 1685026670, home = 1752132965 }
-- key("space") / key("z", {cmd=true}) / key("S")
function D.key(k, mods)
  mods = mods or {}
  local e = { cmd = mods.cmd or false, shift = mods.shift or false, alt = mods.alt or false }
  if NAMES[k] then e.name = k e.code = NAMES[k]
  else e.ch = k e.lower = k:lower() e.code = k:byte() end
  keyq[#keyq + 1] = e
  D.frames(1)
end
function D.type(s) for ch in s:gmatch(".") do D.key(ch) end end

function D.widget(id) local w = G.reg[id] return w end
function D.click_id(id, btn)
  local w = G.reg[id]
  if not w then error("no widget registered with id '" .. tostring(id) .. "'", 0) end
  D.click(w[1] + w[3] / 2, w[2] + w[4] / 2, btn)
end
function D.click_popup(label)
  D.click_id("popup:" .. label)
end

function D.snapshot(path, step)
  D.frames(1)
  return A.snapshot(path, step or 2)
end

function D.stop() if A then A.shutdown() end end
return D
