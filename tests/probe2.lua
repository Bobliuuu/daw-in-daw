local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness") T.setup(root)
local P, C, H = require("project"), require("commands"), require("host")
T.run(function()
  C.new_project("x") local t = C.create_track("midi","A","Lead Synth") local c = C.create_clip(t,0,4)
  local function n() return #P.notes(P.clip(c)) end
  T.info("n0 "..n().." canundo="..tostring(r.Undo_CanUndo2(0)))
  local cc=P.clip(c) H.begin("Add note") r.MIDI_InsertNote(cc.take,false,false,0,960,0,60,100,false) r.MarkTrackItemsDirty(cc.track.ptr, cc.ptr) r.UpdateItemInProject(cc.ptr) H.finish("Add note") P.touch() P.refresh(true) T.info("after insert "..n().." undo='"..tostring(r.Undo_CanUndo2(0)).."' redo='"..tostring(r.Undo_CanRedo2(0)).."'")
  r.Main_OnCommand(40029,0) P.refresh(true) T.info("after undo "..n().." undo='"..tostring(r.Undo_CanUndo2(0)).."' redo='"..tostring(r.Undo_CanRedo2(0)).."'")
  r.Main_OnCommand(40030,0) P.refresh(true) T.info("after redo(40030) "..n().." redo='"..tostring(r.Undo_CanRedo2(0)).."'")
  r.Main_OnCommand(40029,0) P.refresh(true) T.info("undo again "..n())
  r.Undo_DoRedo2(0) P.refresh(true) T.info("after Undo_DoRedo2 "..n())
  r.Undo_DoUndo2(0) P.refresh(true) T.info("after Undo_DoUndo2 "..n())
  r.Undo_DoRedo2(0) P.refresh(true) T.info("after Undo_DoRedo2 again "..n())
  T.finish()
end)
