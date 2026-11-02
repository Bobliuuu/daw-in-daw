-- host.lua : thin adapter over REAPER primitives (time map, undo gestures, pointer validation).
-- Musical time everywhere in the app = quarter-note "beats" (REAPER QN). Seconds only appear at this boundary.
local r = reaper
local H = {}

function H.qn_to_time(qn) return r.TimeMap2_QNToTime(0, qn) end
function H.time_to_qn(t) return r.TimeMap2_timeToQN(0, t) end
function H.bpm() local _, _, bpm = r.TimeMap_GetTimeSigAtTime(0, 0) return bpm end
function H.timesig() local num, den = r.TimeMap_GetTimeSigAtTime(0, 0) return num, den end

function H.set_bpm(bpm)
  bpm = math.max(20, math.min(300, bpm))
  r.SetCurrentBPM(0, bpm, false)
  return bpm
end

function H.set_timesig(num, den)
  local bpm = H.bpm()
  local n = r.CountTempoTimeSigMarkers(0)
  if n > 0 then
    r.SetTempoTimeSigMarker(0, 0, -1, -1, -1, bpm, num, den, false)
  else
    r.SetTempoTimeSigMarker(0, -1, 0, -1, -1, bpm, num, den, false)
  end
  r.UpdateTimeline()
end

function H.valid(ptr, kind) return ptr ~= nil and r.ValidatePtr2(0, ptr, kind) end

-- Undo gestures: nested begin/finish collapse to ONE native undo point (e.g. a 100-frame drag = 1 entry).
local depth, label_, changed_ = 0, nil, false
function H.begin(label)
  if depth == 0 then r.Undo_BeginBlock2(0) label_ = label end
  depth = depth + 1
end
function H.finish(label)
  depth = depth - 1
  if depth == 0 then
    r.Undo_EndBlock2(0, label or label_ or "DAW edit", -1)
    r.UpdateArrange()
  end
end
function H.in_gesture() return depth > 0 end
function H.run(label, fn, ...)
  H.begin(label)
  local ok, a, b = pcall(fn, ...)
  H.finish(label)
  if not ok then error(a, 0) end
  return a, b
end

function H.undo() if depth == 0 then r.Main_OnCommand(40029, 0) end end
function H.redo() if depth == 0 then r.Main_OnCommand(40030, 0) end end
function H.undo_label() return r.Undo_CanUndo2(0) end
function H.redo_label() return r.Undo_CanRedo2(0) end

function H.script_dir()
  local src = debug.getinfo(1, "S").source:gsub("^@", "")
  return (src:match("^(.*)/src/[^/]*$")) or "."
end

return H
