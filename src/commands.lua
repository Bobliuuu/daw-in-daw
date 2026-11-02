-- commands.lua : every editing operation of the inner DAW. Each command runs inside ONE native REAPER undo
-- block (or joins the enclosing gesture, e.g. a drag), mutates real REAPER objects, then refreshes the read model.
local r = reaper
local H = require("host")
local P = require("project")
local U = require("util")
local I = require("audio.instruments")
local E = require("audio.effects")
local TL = require("timeline")

local C = {}
C.assets_dir = H.script_dir() .. "/assets"

local PALETTE = { { 255, 99, 99 }, { 255, 170, 60 }, { 240, 220, 80 }, { 110, 210, 120 }, { 70, 200, 220 }, { 100, 140, 255 }, { 180, 120, 255 }, { 240, 110, 200 } }

-- MIDI API writes are invisible to REAPER's undo system unless the item is flagged dirty (verified empirically)
local function mark(c) r.MarkTrackItemsDirty(c.track.ptr, c.ptr) r.UpdateItemInProject(c.ptr) end

local function mutate(label, fn, ...)
  local a, b = H.run(label, fn, ...)
  P.touch()
  if not H.in_gesture() then P.refresh(true) end
  return a, b
end

local function trk(id)
  local t = P.track(id)
  if not t or not H.valid(t.ptr, "MediaTrack*") then error("track no longer exists: " .. tostring(id), 0) end
  return t, t.ptr
end
local function clp(id)
  local c = P.clip(id)
  if not c or not H.valid(c.ptr, "MediaItem*") then error("clip no longer exists: " .. tostring(id), 0) end
  return c, c.ptr
end

-- gestures for drags: many frames of edits => one undo point
function C.begin_gesture(label) H.begin(label) end
function C.end_gesture(label) H.finish(label) P.touch() P.refresh(true) end
function C.undo() H.undo() P.touch() P.refresh(true) end
function C.redo() H.redo() P.touch() P.refresh(true) end

----------------------------------------------------------------------------- project
function C.new_project(name)
  return mutate("New DAW project", function()
    P.ensure_root()
    r.SetProjExtState(0, "daw_in_daw", "name", name or "Untitled")
    r.SetProjExtState(0, "daw_in_daw", "schema", tostring(P.SCHEMA))
    P.normalize_folder()
  end)
end

-- removes ONLY tracks owned by the inner DAW. UI must confirm first.
function C.clear_project()
  return mutate("Clear DAW project", function()
    local kids, root = P.child_tracks()
    for i = #kids, 1, -1 do r.DeleteTrack(kids[i]) end
    if root then r.DeleteTrack(root) end
  end)
end

function C.set_name(name) return mutate("Rename project", function() r.SetProjExtState(0, "daw_in_daw", "name", name) end) end
function C.set_bpm(bpm) return mutate("Set tempo", function() return H.set_bpm(bpm) end) end
function C.set_timesig(n, d) return mutate("Set time signature", function() H.set_timesig(n, d) end) end

----------------------------------------------------------------------------- tracks
function C.create_track(kind, name, inst)
  return mutate("Add track", function()
    local root, ri = P.ensure_root()
    local kids = P.child_tracks()
    local at = ri + #kids + 1
    r.InsertTrackAtIndex(at, true)
    local tr = r.GetTrack(0, at)
    r.GetSetMediaTrackInfo_String(tr, "P_NAME", name or (kind == "audio" and "Audio" or inst or "MIDI"), true)
    P.tset(tr, "role", "track")
    P.tset(tr, "kind", kind)
    local pc = PALETTE[(#kids % #PALETTE) + 1]
    r.SetTrackColor(tr, r.ColorToNative(pc[1], pc[2], pc[3]) | 0x1000000)
    local n, err = 0, nil
    if kind == "midi" then
      n, err = I.install(tr, inst or "Lead Synth", C.assets_dir)
      P.tset(tr, "inst", inst or "Lead Synth")
    end
    P.tset(tr, "inst_count", tostring(n))
    P.normalize_folder()
    if err then error(err, 0) end
    return P.track_guid(tr)
  end)
end

function C.delete_track(id)
  return mutate("Delete track", function()
    local _, tr = trk(id)
    r.DeleteTrack(tr)
    P.normalize_folder()
  end)
end

function C.rename_track(id, name)
  return mutate("Rename track", function() local _, tr = trk(id) r.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true) end)
end

function C.set_track_color(id, rgb)
  return mutate("Track color", function() local _, tr = trk(id) r.SetTrackColor(tr, r.ColorToNative(rgb[1], rgb[2], rgb[3]) | 0x1000000) end)
end

function C.set_volume(id, lin)
  return mutate("Set volume", function() local _, tr = trk(id) r.SetMediaTrackInfo_Value(tr, "D_VOL", U.clamp(lin, 0, 4)) end)
end
function C.set_pan(id, pan)
  return mutate("Set pan", function() local _, tr = trk(id) r.SetMediaTrackInfo_Value(tr, "D_PAN", U.clamp(pan, -1, 1)) end)
end
function C.set_mute(id, on)
  return mutate("Mute", function() local _, tr = trk(id) r.SetMediaTrackInfo_Value(tr, "B_MUTE", on and 1 or 0) end)
end
function C.set_solo(id, on)
  return mutate("Solo", function() local _, tr = trk(id) r.SetMediaTrackInfo_Value(tr, "I_SOLO", on and 2 or 0) end)
end

function C.set_master_volume(lin) return mutate("Master volume", function() r.SetMediaTrackInfo_Value(r.GetMasterTrack(0), "D_VOL", U.clamp(lin, 0, 4)) end) end

-- swap a ReaSynth instrument preset (instrument selection for synth tracks)
function C.set_preset(id, preset)
  return mutate("Instrument preset", function()
    local t, tr = trk(id)
    if t.kind ~= "midi" or t.inst == "Drum Kit" then return false end
    for name, v in pairs(I.PRESETS[preset] or {}) do I.set_named(tr, 0, name, v) end
    r.TrackFX_SetNamedConfigParm(tr, 0, "renamed_name", preset)
    P.tset(tr, "inst", preset)
    return true
  end)
end

----------------------------------------------------------------------------- clips
local function overlaps(track, s, e, ignore_id)
  for _, c in ipairs(track.clips) do
    if c.id ~= ignore_id and s < c.start + c.len - 1e-6 and e > c.start + 1e-6 then return c end
  end
end
C.overlaps = overlaps

function C.create_clip(track_id, start, len, name)
  return mutate("Add MIDI clip", function()
    local t, tr = trk(track_id)
    if t.kind ~= "midi" then error("not a MIDI track", 0) end
    if overlaps(t, start, start + len) then error("clip would overlap an existing clip", 0) end
    local it = r.CreateNewMIDIItemInProj(tr, H.qn_to_time(start), H.qn_to_time(start + len), false)
    r.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
    r.SetMediaItemInfo_Value(it, "C_BEATATTACHMODE", 1)
    local take = r.GetActiveTake(it)
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name or "Pattern", true)
    return P.item_guid(it)
  end)
end

function C.move_clip(id, new_start, new_track_id)
  return mutate("Move clip", function()
    local c, it = clp(id)
    new_start = math.max(0, new_start)
    local dst = c.track
    if new_track_id and new_track_id ~= c.track_id then
      local t2 = trk(new_track_id)
      if t2.kind ~= c.track.kind then return false end
      dst = t2
    end
    if overlaps(dst, new_start, new_start + c.len, c.id) then return false end
    if dst ~= c.track then r.MoveMediaItemToTrack(it, dst.ptr) end
    r.SetMediaItemInfo_Value(it, "D_POSITION", H.qn_to_time(new_start))
    return true
  end)
end

function C.resize_clip(id, new_len)
  return mutate("Resize clip", function()
    local c, it = clp(id)
    new_len = math.max(0.25, new_len)
    if overlaps(c.track, c.start, c.start + new_len, c.id) then return false end
    local t1 = H.qn_to_time(c.start + new_len)
    if c.kind == "audio" then
      local max_t = (c.src_len - c.offs) / math.max(c.rate, 1e-6)
      t1 = math.min(t1, c.time_pos + max_t)
    end
    r.SetMediaItemInfo_Value(it, "D_LENGTH", t1 - c.time_pos)
    if c.kind == "midi" and new_len > c.len then r.MIDI_SetItemExtents(it, c.start, c.start + new_len) mark(c) end
    return true
  end)
end

-- trim the left edge (audio): moves start forward/back while keeping audio in place
function C.trim_clip_left(id, new_start)
  return mutate("Trim clip", function()
    local c, it = clp(id)
    if c.kind ~= "audio" then return false end
    local nt = H.qn_to_time(new_start)
    local d = nt - c.time_pos
    local noffs = c.offs + d * c.rate
    if noffs < 0 then d = -c.offs / c.rate noffs = 0 end
    if c.time_len - d < 0.05 then return false end
    r.SetMediaItemInfo_Value(it, "D_POSITION", c.time_pos + d)
    r.SetMediaItemInfo_Value(it, "D_LENGTH", c.time_len - d)
    r.SetMediaItemTakeInfo_Value(c.take, "D_STARTOFFS", noffs)
    return true
  end)
end

function C.delete_clip(id)
  return mutate("Delete clip", function()
    local c, it = clp(id)
    r.DeleteTrackMediaItem(c.track.ptr, it)
  end)
end

local function regenerate_guids(chunk)
  return (chunk:gsub("{%x+%-%x+%-%x+%-%x+%-%x+}", function() return r.genGuid("") end))
end

-- duplicate (or paste) a clip: copies the real item state (MIDI data / audio source ref) with new GUIDs
function C.duplicate_clip(id, dest_start, dest_track_id)
  return mutate("Duplicate clip", function()
    local c, it = clp(id)
    local dt = dest_track_id and trk(dest_track_id) or c.track
    if dt.kind ~= c.track.kind then error("track type mismatch", 0) end
    dest_start = dest_start or (c.start + c.len)
    if overlaps(dt, dest_start, dest_start + c.len) then error("destination overlaps an existing clip", 0) end
    local _, chunk = r.GetItemStateChunk(it, "", false)
    local new = r.AddMediaItemToTrack(dt.ptr)
    r.SetItemStateChunk(new, regenerate_guids(chunk), false)
    r.SetMediaItemInfo_Value(new, "D_POSITION", H.qn_to_time(dest_start))
    return P.item_guid(new)
  end)
end

function C.copy_chunk(id)
  local c, it = clp(id)
  local _, chunk = r.GetItemStateChunk(it, "", false)
  return { chunk = chunk, kind = c.kind, len = c.len }
end
function C.paste_chunk(clipboard, track_id, at)
  return mutate("Paste clip", function()
    local t, tr = trk(track_id)
    if t.kind ~= clipboard.kind then error("track type mismatch", 0) end
    if overlaps(t, at, at + clipboard.len) then error("destination overlaps an existing clip", 0) end
    local new = r.AddMediaItemToTrack(tr)
    r.SetItemStateChunk(new, regenerate_guids(clipboard.chunk), false)
    r.SetMediaItemInfo_Value(new, "D_POSITION", H.qn_to_time(at))
    return P.item_guid(new)
  end)
end

function C.split_clip(id, at)
  return mutate("Split clip", function()
    local c, it = clp(id)
    if at <= c.start + 0.01 or at >= c.start + c.len - 0.01 then return nil end
    local right = r.SplitMediaItem(it, H.qn_to_time(at))
    return right and P.item_guid(right)
  end)
end

function C.import_audio(track_id, path, start)
  return mutate("Import audio", function()
    local t, tr = trk(track_id)
    if t.kind ~= "audio" then error("not an audio track", 0) end
    local src = r.PCM_Source_CreateFromFile(path)
    if not src then error("REAPER cannot decode this file: " .. path, 0) end
    local len = r.GetMediaSourceLength(src)
    if len <= 0 then r.PCM_Source_Destroy(src) error("empty or undecodable audio: " .. path, 0) end
    if overlaps(t, start, start + H.time_to_qn(H.qn_to_time(start) + len) - start) then
      r.PCM_Source_Destroy(src) error("audio would overlap an existing clip", 0)
    end
    local it = r.AddMediaItemToTrack(tr)
    local take = r.AddTakeToMediaItem(it)
    r.SetMediaItemTake_Source(take, src)
    r.SetMediaItemInfo_Value(it, "D_POSITION", H.qn_to_time(start))
    r.SetMediaItemInfo_Value(it, "D_LENGTH", len)
    r.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
    r.SetMediaItemInfo_Value(it, "C_BEATATTACHMODE", 2)
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", U.basename(path), true)
    r.UpdateItemInProject(it)
    return P.item_guid(it)
  end)
end

function C.set_clip_gain(id, lin)
  return mutate("Clip gain", function() local _, it = clp(id) r.SetMediaItemInfo_Value(it, "D_VOL", U.clamp(lin, 0, 4)) end)
end
function C.rename_clip(id, name)
  return mutate("Rename clip", function() local c = clp(id) if c.take then r.GetSetMediaItemTakeInfo_String(c.take, "P_NAME", name, true) end end)
end

----------------------------------------------------------------------------- notes
local function clip_bounds(c) return c.start, c.start + c.len end

function C.insert_note(clip_id, pitch, s, e, vel)
  return mutate("Add note", function()
    local c = clp(clip_id)
    local cs, ce = clip_bounds(c)
    s = U.clamp(s, cs, ce) e = U.clamp(e, cs, ce)
    if e - s < 1e-4 then return false end
    pitch = U.clamp(pitch, 0, 127)
    c.take = c.take
    r.MIDI_InsertNote(c.take, false, false, r.MIDI_GetPPQPosFromProjQN(c.take, s), r.MIDI_GetPPQPosFromProjQN(c.take, e), 0, pitch, U.clamp(vel or 100, 1, 127), false)
    mark(c)
    return true
  end)
end

function C.delete_notes(clip_id, idxs)
  return mutate("Delete notes", function()
    local c = clp(clip_id)
    table.sort(idxs, function(a, b) return a > b end)
    for _, i in ipairs(idxs) do r.MIDI_DeleteNote(c.take, i) end
    r.MIDI_Sort(c.take)
    mark(c)
  end)
end

-- fields: s,e,pitch,vel,sel (any may be nil). nosort=true keeps event indices stable during drags.
function C.set_note(clip_id, idx, f, nosort)
  local c = clp(clip_id)
  local sp = f.s and r.MIDI_GetPPQPosFromProjQN(c.take, f.s) or nil
  local ep = f.e and r.MIDI_GetPPQPosFromProjQN(c.take, f.e) or nil
  r.MIDI_SetNote(c.take, idx, f.sel, nil, sp, ep, nil, f.pitch and U.clamp(f.pitch, 0, 127) or nil, f.vel and U.clamp(f.vel, 1, 127) or nil, nosort and true or false)
  mark(c)
  P.touch()
end
function C.sort_notes(clip_id) local c = clp(clip_id) r.MIDI_Sort(c.take) mark(c) P.touch() end

function C.select_notes(clip_id, sel_set) -- sel_set: idx -> true; all others deselected
  local c = clp(clip_id)
  local _, n = r.MIDI_CountEvts(c.take)
  for i = 0, n - 1 do r.MIDI_SetNote(c.take, i, sel_set[i] and true or false, nil, nil, nil, nil, nil, nil, true) end
  P.touch()
end

function C.quantize_notes(clip_id, grid, only_selected)
  return mutate("Quantize", function()
    local c = clp(clip_id)
    local cs, ce = clip_bounds(c)
    for _, n in ipairs(P.notes(c)) do
      if not only_selected or n.sel then
        local s2 = U.clamp(U.snap(n.s, grid), cs, ce)
        local e2 = math.max(s2 + grid, U.snap(n.e, grid))
        C.set_note(c.id, n.idx, { s = s2, e = math.min(e2, ce) }, true)
      end
    end
    r.MIDI_Sort(c.take)
  end)
end

----------------------------------------------------------------------------- FX
function C.add_effect(track_id, effect_id)
  return mutate("Add effect", function()
    local _, tr = trk(track_id)
    local fx, err = E.add(tr, effect_id)
    if not fx then error(err, 0) end
    return fx
  end)
end
function C.remove_fx(track_id, fx) return mutate("Remove effect", function() local t, tr = trk(track_id) if fx >= t.inst_count then E.remove(tr, fx) end end) end
function C.toggle_fx(track_id, fx) return mutate("Toggle effect", function() local _, tr = trk(track_id) E.set_enabled(tr, fx, not r.TrackFX_GetEnabled(tr, fx)) end) end
function C.move_fx(track_id, fx, d) return mutate("Move effect", function() local t, tr = trk(track_id) return E.move(tr, fx, d, t.inst_count) end) end
function C.set_fx_param(track_id, fx, idx, v)
  local _, tr = trk(track_id)
  E.set(tr, fx, idx, v)
  P.touch()
end

return C
