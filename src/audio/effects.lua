-- effects.lua : FX catalog using REAPER's bundled effects. Exposed parameters are looked up BY NAME at runtime.
local r = reaper
local I = require("audio.instruments")
local E = {}

E.CATALOG = {
  { id = "reverb", label = "Reverb", plugin = "ReaVerbate",
    params = { "Wet", "Dry", "Room size", "Dampening" },
    defaults = { ["Wet"] = 0.35, ["Room size"] = 0.7 } },
  { id = "delay", label = "Delay", plugin = "ReaDelay",
    params = { "Wet", "Dry", "1: Length (musical)", "1: Feedback" },
    defaults = { ["Wet"] = 0.3, ["1: Feedback"] = 0.5 } },
  { id = "eq", label = "EQ", plugin = "ReaEQ",
    params = { "Gain-Low Shelf", "Gain-Band 2", "Freq-Band 2", "Gain-Band 3", "Freq-Band 3", "Gain-High Shelf 4" },
    defaults = {} },
  { id = "comp", label = "Compressor", plugin = "ReaComp",
    params = { "Threshold", "Ratio", "Attack", "Release" },
    defaults = { ["Threshold"] = 0.5, ["Ratio"] = 0.12 } },
}
function E.by_id(id) for _, e in ipairs(E.CATALOG) do if e.id == id then return e end end end

local function clean_name(n) return (n:gsub("^%a+i?: ", ""):gsub(" %(Cockos%)", "")) end
-- original plugin name, even when the FX instance has been renamed (e.g. "Kick" is a ReaSamplOmatic5000)
local function plugin_name(tr, fx)
  local ok, n = r.TrackFX_GetNamedConfigParm(tr, fx, "fx_name")
  if ok and n ~= "" then return n end
  local _, gn = r.TrackFX_GetFXName(tr, fx, "")
  return gn
end

function E.add(tr, id)
  local def = E.by_id(id)
  if not def then return nil, "unknown effect " .. tostring(id) end
  local fx = r.TrackFX_AddByName(tr, def.plugin, false, -1)
  if fx < 0 then return nil, def.plugin .. " not installed" end
  for name, v in pairs(def.defaults) do I.set_named(tr, fx, name, v) end
  return fx
end

-- list of FX on the track: {idx, name, enabled, is_inst}
function E.chain(tr, inst_count)
  local out = {}
  for i = 0, r.TrackFX_GetCount(tr) - 1 do
    local n = plugin_name(tr, i)
    local _, rn = r.TrackFX_GetNamedConfigParm(tr, i, "renamed_name")
    out[#out + 1] = { idx = i, name = (rn and rn ~= "" and rn) or clean_name(n), plugin = clean_name(n),
      enabled = r.TrackFX_GetEnabled(tr, i), is_inst = i < (inst_count or 0) }
  end
  return out
end

-- parameters worth showing for an FX instance: validated names only
function E.params(tr, fx, plugin_hint)
  local n = plugin_name(tr, fx)
  local want
  for _, e in ipairs(E.CATALOG) do if n:find(e.plugin, 1, true) then want = e.params end end
  if not want and n:find("ReaSynth", 1, true) then want = { "Volume", "Attack", "Decay", "Sustain", "Release", "Saw mix", "Square mix", "Triangle mix" } end
  if not want and n:find("ReaSamplOmatic5000", 1, true) then want = { "Volume", "Pan", "Pitch adjust", "Attack", "Release" } end
  local out = {}
  for _, name in ipairs(want or {}) do
    local i = I.param_index(tr, fx, name)
    if i then
      local v, mn, mx = r.TrackFX_GetParam(tr, fx, i)
      local _, txt = r.TrackFX_GetFormattedParamValue(tr, fx, i, "")
      out[#out + 1] = { idx = i, name = name, value = v, min = mn, max = mx, text = txt }
    end
  end
  return out
end

function E.set(tr, fx, idx, v) return r.TrackFX_SetParam(tr, fx, idx, v) end
function E.set_enabled(tr, fx, on) r.TrackFX_SetEnabled(tr, fx, on) end
function E.remove(tr, fx) return r.TrackFX_Delete(tr, fx) end
-- move within the same track chain by delta positions
function E.move(tr, fx, delta, min_idx)
  local dst = fx + delta
  if dst < (min_idx or 0) or dst >= r.TrackFX_GetCount(tr) then return false end
  r.TrackFX_CopyToTrack(tr, fx, tr, dst, true)
  return true
end

return E
