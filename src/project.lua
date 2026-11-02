-- project.lua : read model of the inner DAW project, derived from REAL REAPER objects.
--
-- Ownership boundary: a top-level folder track tagged P_EXT:daw_in_daw:role=root. Every track inside is a DAW track.
-- Stable IDs: REAPER GUIDs (tracks: "GUID", items: "GUID") - never indices or pointers.
-- The snapshot is rebuilt only when REAPER's project-state counter changes or a command calls touch(); the
-- renderer reads the snapshot, never scans REAPER objects per frame.
local r = reaper
local H = require("host")
local E = require("audio.effects")
local U = require("util")

local EXT = "P_EXT:daw_in_daw"
local P = { version = 0, snap = nil, _sc = -1, _dirty = true, _last_poll = 0 }
P.SCHEMA = 1
P.ROOT_NAME = "DAW-in-DAW"

----------------------------------------------------------------------------- low-level ext helpers
function P.tget(tr, key) local ok, v = r.GetSetMediaTrackInfo_String(tr, EXT .. ":" .. key, "", false) return ok and v or "" end
function P.tset(tr, key, val) r.GetSetMediaTrackInfo_String(tr, EXT .. ":" .. key, val, true) end
function P.track_guid(tr) local _, g = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false) return g end
function P.item_guid(it) local _, g = r.GetSetMediaItemInfo_String(it, "GUID", "", false) return g end

function P.find_root()
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if P.tget(tr, "role") == "root" then return tr, i end
  end
end

-- creates the owning folder if absent (caller wraps in an undo gesture)
function P.ensure_root()
  local tr, i = P.find_root()
  if tr then return tr, i end
  r.InsertTrackAtIndex(r.CountTracks(0), true)
  tr = r.GetTrack(0, r.CountTracks(0) - 1)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", P.ROOT_NAME, true)
  P.tset(tr, "role", "root")
  r.SetTrackColor(tr, r.ColorToNative(70, 70, 80) | 0x1000000)
  r.SetProjExtState(0, "daw_in_daw", "schema", tostring(P.SCHEMA))
  P.touch()
  return tr, r.CountTracks(0) - 1
end

-- children of the root = contiguous tracks after it tagged role=track
function P.child_tracks()
  local root, ri = P.find_root()
  local out = {}
  if not root then return out, nil end
  for i = ri + 1, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if P.tget(tr, "role") ~= "track" then break end
    out[#out + 1] = tr
  end
  return out, root
end

-- keep REAPER folder structure consistent: root opens a folder, last child closes it
function P.normalize_folder()
  local kids, root = P.child_tracks()
  if not root then return end
  for i, tr in ipairs(kids) do r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", (i == #kids) and -1 or 0) end
  r.SetMediaTrackInfo_Value(root, "I_FOLDERDEPTH", #kids > 0 and 1 or 0)
end

----------------------------------------------------------------------------- snapshot
local function color_of(tr)
  local c = r.GetTrackColor(tr)
  if c == 0 then return { 120, 120, 130 } end
  local rr, gg, bb = r.ColorFromNative(c)
  return { rr, gg, bb }
end

local function build()
  local s = { tracks = {}, by_id = {}, clips = {}, clip_by_id = {} }
  s.bpm = H.bpm()
  s.num, s.den = H.timesig()
  local kids, root = P.child_tracks()
  s.root = root
  s.has_root = root ~= nil
  if root then
    local _, rn = r.GetSetMediaTrackInfo_String(root, "P_NAME", "", false)
    s.name = rn
    local _, nm = r.GetProjExtState(0, "daw_in_daw", "name")
    if nm ~= "" then s.name = nm end
  end
  for idx, tr in ipairs(kids) do
    local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    local inst_count = tonumber(P.tget(tr, "inst_count")) or 0
    local t = {
      id = P.track_guid(tr), ptr = tr, index = idx, name = name, color = color_of(tr),
      kind = P.tget(tr, "kind"), inst = P.tget(tr, "inst"), inst_count = inst_count,
      vol = r.GetMediaTrackInfo_Value(tr, "D_VOL"), pan = r.GetMediaTrackInfo_Value(tr, "D_PAN"),
      mute = r.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1, solo = r.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0,
      fx = E.chain(tr, inst_count), clips = {},
    }
    for k = 0, r.CountTrackMediaItems(tr) - 1 do
      local it = r.GetTrackMediaItem(tr, k)
      local take = r.GetActiveTake(it)
      local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      local sq = H.time_to_qn(pos)
      local c = {
        id = P.item_guid(it), ptr = it, take = take, track_id = t.id, track = t,
        start = sq, len = H.time_to_qn(pos + len) - sq,
        kind = (take and r.TakeIsMIDI(take)) and "midi" or "audio",
        offs = take and r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0,
        rate = take and r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1,
        time_pos = pos, time_len = len, vol = r.GetMediaItemInfo_Value(it, "D_VOL"),
      }
      if take then
        local _, tn = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        c.name = tn
        if c.kind == "audio" then
          local src = r.GetMediaItemTake_Source(take)
          local a, b = r.GetMediaSourceFileName(src, "")
          c.file = (b and b ~= "") and b or a
          c.src_len = r.GetMediaSourceLength(src)
        end
      end
      t.clips[#t.clips + 1] = c
      s.clips[#s.clips + 1] = c
      s.clip_by_id[c.id] = c
    end
    table.sort(t.clips, function(a, b) return a.start < b.start end)
    s.tracks[idx] = t
    s.by_id[t.id] = t
  end
  local e = 0
  for _, c in ipairs(s.clips) do if c.start + c.len > e then e = c.start + c.len end end
  s.end_beat = e
  return s
end

function P.touch() P._dirty = true end

-- returns true if the snapshot was rebuilt
function P.refresh(force)
  local sc = r.GetProjectStateChangeCount(0)
  local now = r.time_precise()
  -- MIDI edits made outside our commands don't bump the counter; poll gently
  local poll = (now - P._last_poll) > 1.0
  if not force and not P._dirty and sc == P._sc and not poll then return false end
  P._sc, P._dirty, P._last_poll = sc, false, now
  P.snap = build()
  P.version = P.version + 1
  P.notes_cache = {}
  return true
end

function P.track(id) return P.snap and P.snap.by_id[id] end
function P.clip(id) return P.snap and P.snap.clip_by_id[id] end

----------------------------------------------------------------------------- notes
P.notes_cache = {}
-- all notes of a MIDI clip in absolute project beats. cached per snapshot version.
function P.notes(clip)
  if not clip or not clip.take or not r.ValidatePtr2(0, clip.take, "MediaItem_Take*") then return {} end
  local c = P.notes_cache[clip.id]
  if c then return c end
  local take = clip.take
  local _, n = r.MIDI_CountEvts(take)
  local out = {}
  for i = 0, n - 1 do
    local ok, sel, muted, sp, ep, chan, pitch, vel = r.MIDI_GetNote(take, i)
    if ok then
      out[#out + 1] = { idx = i, sel = sel, muted = muted, pitch = pitch, vel = vel, chan = chan,
        s = r.MIDI_GetProjQNFromPPQPos(take, sp), e = r.MIDI_GetProjQNFromPPQPos(take, ep) }
    end
  end
  P.notes_cache[clip.id] = out
  return out
end

return P
