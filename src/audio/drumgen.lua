-- drumgen.lua : original, procedurally generated drum one-shots + a demo audio loop (public domain; no external samples)
local W = require("wavio")
local G = {}
local SR = 44100

local function rng(seed) local s = seed or 12345 return function() s = (s * 1103515245 + 12345) % 2147483648 return s / 1073741824 - 1 end end

local function render(secs, fn)
  local n = math.floor(secs * SR) local out = {}
  for i = 1, n do out[i] = fn((i - 1) / SR, i) end
  return out
end

local function kick() local ph = 0 return render(0.45, function(t)
  local f = 45 + 110 * math.exp(-t * 28) ph = ph + 2 * math.pi * f / SR
  return math.tanh(1.8 * math.sin(ph) * math.exp(-t * 7)) * 0.95 end) end

local function snare() local r, ph = rng(1), 0 return render(0.3, function(t)
  ph = ph + 2 * math.pi * (180 - 40 * t) / SR
  return (r() * 0.7 * math.exp(-t * 18) + math.sin(ph) * 0.5 * math.exp(-t * 25)) * 0.9 end) end

local function hat(decay, seed) local r, p1 = rng(seed), 0 return render(decay * 3, function(t)
  local x = r() local y = x - p1 p1 = x   -- crude high-pass
  return y * 0.6 * math.exp(-t / decay) end) end

local function clap() local r = rng(7) return render(0.3, function(t)
  local env = 0
  for _, off in ipairs { 0, 0.012, 0.024 } do if t >= off then env = env + math.exp(-(t - off) * 70) * 0.5 end end
  env = env + math.exp(-t * 14) * 0.35
  return r() * env * 0.8 end) end

local function tom() local ph = 0 return render(0.4, function(t)
  ph = ph + 2 * math.pi * (95 + 90 * math.exp(-t * 14)) / SR
  return math.sin(ph) * math.exp(-t * 9) * 0.9 end) end

-- kit definition: name, midi note, generator
G.KIT = {
  { name = "Kick",       note = 36, file = "kick.wav",   gen = kick },
  { name = "Snare",      note = 38, file = "snare.wav",  gen = snare },
  { name = "Clap",       note = 39, file = "clap.wav",   gen = clap },
  { name = "Closed Hat", note = 42, file = "hat_c.wav",  gen = function() return hat(0.025, 3) end },
  { name = "Open Hat",   note = 46, file = "hat_o.wav",  gen = function() return hat(0.16, 5) end },
  { name = "Tom",        note = 45, file = "tom.wav",    gen = tom },
}

function G.ensure_kit(dir)
  os.execute(string.format('mkdir -p "%s"', dir))
  local paths = {}
  for _, v in ipairs(G.KIT) do
    local p = dir .. "/" .. v.file
    local f = io.open(p, "rb")
    if f then f:close() else W.write16(p, v.gen(), SR, 1) end
    paths[#paths + 1] = p
  end
  return paths
end

-- 8-second stereo-free demo loop: a plucked chord arpeggio with a soft pad (120 bpm, 4 bars)
function G.demo_loop(path, bpm)
  bpm = bpm or 120
  local beat = 60 / bpm
  local chords = { { 57, 60, 64 }, { 53, 57, 60 }, { 48, 52, 55 }, { 55, 59, 62 } } -- Am F C G
  local total = 16 * beat
  local n = math.floor(total * SR)
  local out = {}
  for i = 1, n do out[i] = 0 end
  local function f(p) return 440 * 2 ^ ((p - 69) / 12) end
  for bar = 0, 3 do
    local ch = chords[bar + 1]
    for step = 0, 7 do -- eighth-note arpeggio
      local t0 = (bar * 4 + step * 0.5) * beat
      local p = ch[(step % 3) + 1] + (step % 2 == 0 and 12 or 0)
      local ph, i0 = 0, math.floor(t0 * SR)
      for k = 0, math.floor(0.5 * SR) do
        local t = k / SR
        ph = ph + 2 * math.pi * f(p) / SR
        local v = (math.sin(ph) + 0.4 * math.sin(2 * ph) + 0.2 * math.sin(3 * ph)) * math.exp(-t * 6) * 0.22
        local idx = i0 + k + 1
        if idx <= n then out[idx] = out[idx] + v end
      end
    end
    -- pad
    local i0 = math.floor(bar * 4 * beat * SR)
    local len = math.floor(4 * beat * SR)
    for _, p in ipairs(ch) do
      local ph = 0
      for k = 0, len - 1 do
        ph = ph + 2 * math.pi * f(p - 12) / SR
        local env = math.min(1, k / (0.3 * SR)) * math.min(1, (len - k) / (0.3 * SR))
        local idx = i0 + k + 1
        if idx <= n then out[idx] = out[idx] + math.sin(ph) * 0.08 * env end
      end
    end
  end
  W.write16(path, out, SR, 1)
  return path
end

return G
