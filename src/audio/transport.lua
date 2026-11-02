-- transport.lua : REAPER's native transport, exposed in musical time.
local r = reaper
local H = require("host")
local T = {}
function T.is_playing() return r.GetPlayState() & 1 ~= 0 end
function T.is_paused() return r.GetPlayState() & 2 ~= 0 end
function T.play() r.OnPlayButton() end
function T.stop() r.OnStopButton() end
function T.pause() r.OnPauseButton() end
function T.toggle() if T.is_playing() and not T.is_paused() then T.stop() else T.play() end end
function T.position() -- beats
  local p = (T.is_playing() or T.is_paused()) and r.GetPlayPosition() or r.GetCursorPosition()
  return H.time_to_qn(p)
end
function T.seek(beat)
  beat = math.max(0, beat)
  r.SetEditCurPos(H.qn_to_time(beat), true, T.is_playing())
end
function T.loop_enabled() return r.GetSetRepeat(-1) == 1 end
function T.set_loop_enabled(on) r.GetSetRepeat(on and 1 or 0) end
function T.loop() local s, e = r.GetSet_LoopTimeRange(false, true, 0, 0, false) return H.time_to_qn(s), H.time_to_qn(e) end
function T.set_loop(sb, eb)
  if eb < sb then sb, eb = eb, sb end
  r.GetSet_LoopTimeRange(true, true, H.qn_to_time(sb), H.qn_to_time(eb), false)
end
function T.master_peak()
  local m = r.GetMasterTrack(0)
  return r.Track_GetPeakInfo(m, 0), r.Track_GetPeakInfo(m, 1)
end
return T
