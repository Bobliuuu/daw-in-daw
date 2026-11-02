-- export.lua : render the arrangement to WAV using REAPER's native renderer; validates the result.
local r = reaper
local H = require("host")
local W = require("wavio")
local U = require("util")
local X = {}

local KEYS_NUM = { "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_CHANNELS", "RENDER_SRATE", "RENDER_STARTPOS", "RENDER_ENDPOS",
  "RENDER_TAILFLAG", "RENDER_TAILMS", "RENDER_ADDTOPROJ" }
local KEYS_STR = { "RENDER_FILE", "RENDER_PATTERN", "RENDER_FORMAT" }

local function save_cfg()
  local c = { n = {}, s = {} }
  for _, k in ipairs(KEYS_NUM) do c.n[k] = r.GetSetProjectInfo(0, k, 0, false) end
  for _, k in ipairs(KEYS_STR) do local _, v = r.GetSetProjectInfo_String(0, k, "", false) c.s[k] = v end
  return c
end
local function restore_cfg(c)
  for k, v in pairs(c.n) do r.GetSetProjectInfo(0, k, v, true) end
  for k, v in pairs(c.s) do r.GetSetProjectInfo_String(0, k, v, true) end
end

-- first free path: name.wav, name_2.wav, ...  (never silently overwrites)
function X.free_path(dir, name)
  local base = U.strip_ext(name)
  local p, n = dir .. "/" .. base .. ".wav", 1
  while io.open(p, "rb") do n = n + 1 p = string.format("%s/%s_%d.wav", dir, base, n) end
  return p
end

-- opts: dir, name, region = "project"|"loop"|{s=beat,e=beat}, tail_ms, overwrite
-- returns { ok, path, analysis, err }
function X.render(opts)
  local dir, name = opts.dir, opts.name or "song"
  local path
  if opts.overwrite then path = dir .. "/" .. U.strip_ext(name) .. ".wav" else path = X.free_path(dir, name) end
  os.execute(string.format('mkdir -p "%s"', dir))
  local cfg = save_cfg()
  local base = U.strip_ext(U.basename(path))
  os.remove(path)
  r.GetSetProjectInfo(0, "RENDER_SETTINGS", 0, true)       -- master mix
  r.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
  r.GetSetProjectInfo(0, "RENDER_SRATE", opts.srate or 44100, true)
  r.GetSetProjectInfo(0, "RENDER_ADDTOPROJ", 0, true)
  local region = opts.region or "project"
  if region == "project" then r.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true)
  elseif region == "loop" then r.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 2, true)
  else
    r.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 0, true)
    r.GetSetProjectInfo(0, "RENDER_STARTPOS", H.qn_to_time(region.s), true)
    r.GetSetProjectInfo(0, "RENDER_ENDPOS", H.qn_to_time(region.e), true)
  end
  local tail = opts.tail_ms or 1500
  r.GetSetProjectInfo(0, "RENDER_TAILFLAG", tail > 0 and 1 or 0, true)
  r.GetSetProjectInfo(0, "RENDER_TAILMS", tail, true)
  r.GetSetProjectInfo_String(0, "RENDER_FILE", dir, true)
  r.GetSetProjectInfo_String(0, "RENDER_PATTERN", base, true)
  r.GetSetProjectInfo_String(0, "RENDER_FORMAT", "ZXZhdxAAAAA=", true)   -- WAV, 16-bit PCM
  r.Main_OnCommand(42230, 0)                                              -- render w/ most recent settings, auto-close
  restore_cfg(cfg)
  local a, err = W.analyze(path)
  if not a then return { ok = false, path = path, err = err } end
  return { ok = a.peak > 0.0005, path = path, analysis = a, err = a.peak <= 0.0005 and "rendered file is silent" or nil }
end

-- end of last item (beats) among owned tracks; used to size exports
function X.project_end_beat()
  local e = 0
  for t = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, t)
    for k = 0, r.CountTrackMediaItems(tr) - 1 do
      local it = r.GetTrackMediaItem(tr, k)
      local ie = r.GetMediaItemInfo_Value(it, "D_POSITION") + r.GetMediaItemInfo_Value(it, "D_LENGTH")
      if ie > e then e = ie end
    end
  end
  return H.time_to_qn(e)
end

return X
