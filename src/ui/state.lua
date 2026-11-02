-- state.lua : TRANSIENT UI state (never persisted as music). Musical state lives in REAPER objects.
local TL = require("timeline")
local S = {
  tab = "roll",                 -- bottom panel: roll | mixer | devices
  sel_track = nil,              -- track id (GUID)
  sel_clip = nil,               -- clip id (GUID)
  edit_clip = nil,              -- clip open in the piano roll
  arr = { view = TL.new_view(28), scroll_y = 0, track_h = 64, header_w = 214 },
  roll = { view = TL.new_view(70), pv = { top = 84, row_h = 14 }, note_len = 0.5, focus_clip = nil },
  snap_idx = 4,
  focus = "arr",                -- keyboard focus area: arr | roll
  bottom_h = 310,
  msg = nil, msg_kind = "info", msg_t = 0,
  clipboard = nil,
  fx_sel = nil,                 -- selected fx index in Devices tab
  perf = { fps = 0, frame_ms = 0 },
  show_perf = false,
  export = { dir = nil, name = "song", region = "project", last = nil },
  browser = { dir = nil },
}
S.SNAPS = { { "Bar", 4 }, { "1/4", 1 }, { "1/8", 0.5 }, { "1/16", 0.25 }, { "1/32", 0.125 }, { "Off", 0 } }
function S.snap() return S.SNAPS[S.snap_idx][2] end
function S.snap_label() return S.SNAPS[S.snap_idx][1] end
-- arrangement never snaps finer than a beat (clips are bar/beat-scale objects)
function S.arr_snap(bpb)
  local v = S.snap()
  if v == 0 then return 0 end
  if v >= 4 then return bpb or 4 end
  return math.max(v, 1)
end
return S
