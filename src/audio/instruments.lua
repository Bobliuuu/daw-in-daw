-- instruments.lua : instrument catalog built on REAPER's bundled plugins (ReaSynth, ReaSamplOmatic5000).
local r = reaper
local G = require("audio.drumgen")
local I = {}

-- find a parameter by exact name (validated against the live plugin, never a hardcoded index)
function I.param_index(tr, fx, name)
  for i = 0, r.TrackFX_GetNumParams(tr, fx) - 1 do
    local _, n = r.TrackFX_GetParamName(tr, fx, i, "")
    if n == name then return i end
  end
end
function I.set_named(tr, fx, name, v)
  local i = I.param_index(tr, fx, name)
  if not i then return false end
  r.TrackFX_SetParam(tr, fx, i, v) return true
end

-- ReaSynth presets (raw param values; names validated at runtime)
I.PRESETS = {
  ["Lead Synth"] = { ["Saw mix"] = 0.55, ["Square mix"] = 0.3, ["Release"] = 0.04, ["Volume"] = 0.5 },
  ["Bass Synth"] = { ["Triangle mix"] = 0.8, ["Saw mix"] = 0.15, ["Release"] = 0.02, ["Volume"] = 0.7 },
  ["Pad Synth"]  = { ["Saw mix"] = 0.3, ["Triangle mix"] = 0.4, ["Attack"] = 0.4, ["Release"] = 0.25, ["Volume"] = 0.4 },
  ["Pluck"]      = { ["Square mix"] = 0.4, ["Sustain"] = 0.0, ["Decay"] = 0.15, ["Release"] = 0.02, ["Volume"] = 0.5 },
}
I.CATALOG = { "Lead Synth", "Bass Synth", "Pad Synth", "Pluck", "Drum Kit" }

local function add_rs5k(tr, path, name, note)
  local fx = r.TrackFX_AddByName(tr, "ReaSamplOmatic5000", false, -1)
  if fx < 0 then return nil, "ReaSamplOmatic5000 not available" end
  r.TrackFX_SetNamedConfigParm(tr, fx, "FILE0", path)
  r.TrackFX_SetNamedConfigParm(tr, fx, "DONE", "")
  I.set_named(tr, fx, "Note range start", note / 127)
  I.set_named(tr, fx, "Note range end", note / 127)
  I.set_named(tr, fx, "Pitch for start note", 0.5)
  I.set_named(tr, fx, "Pitch for end note", 0.5)
  I.set_named(tr, fx, "Obey note-offs", 0)
  I.set_named(tr, fx, "Max voices", 0.25)
  r.TrackFX_SetNamedConfigParm(tr, fx, "renamed_name", name)
  return fx
end

-- installs instrument FX at the front of the chain. returns number of FX added (instrument slot count)
function I.install(tr, inst, asset_dir)
  if inst == "Drum Kit" then
    local dir = asset_dir .. "/drums"
    G.ensure_kit(dir)
    local n = 0
    for _, v in ipairs(G.KIT) do
      local fx, err = add_rs5k(tr, dir .. "/" .. v.file, v.name, v.note)
      if not fx then return n, err end
      n = n + 1
    end
    return n
  end
  local fx = r.TrackFX_AddByName(tr, "ReaSynth", false, -1)
  if fx < 0 then return 0, "ReaSynth not available" end
  for name, v in pairs(I.PRESETS[inst] or {}) do I.set_named(tr, fx, name, v) end
  r.TrackFX_SetNamedConfigParm(tr, fx, "renamed_name", inst)
  return 1
end


-- Re-link drum-kit voices whose sample file went missing (project moved to another machine, file deleted...).
-- Returns the number of voices restored. Never touches tracks it does not own.
function I.repair_kit(tr, asset_dir, inst_count)
  local fixed = 0
  for i = 0, inst_count - 1 do
    local _, name = r.TrackFX_GetNamedConfigParm(tr, i, "renamed_name")
    local _, path = r.TrackFX_GetNamedConfigParm(tr, i, "FILE0")
    for _, v in ipairs(G.KIT) do
      if v.name == name and (path == nil or path == "" or not r.file_exists(path)) then
        r.TrackFX_SetNamedConfigParm(tr, i, "FILE0", asset_dir .. "/drums/" .. v.file)
        r.TrackFX_SetNamedConfigParm(tr, i, "DONE", "")
        fixed = fixed + 1
      end
    end
  end
  return fixed
end

return I
