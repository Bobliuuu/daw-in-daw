local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness") T.setup(root)
local D = require("ui_driver")
local P, C = require("project"), require("commands")
T.run(function()
  D.start()
  local A = D.A
  C.new_project("x") local id = C.create_track("midi","A","Lead Synth") P.refresh(true)
  local tr = P.track(id).ptr
  local variants = {
    { "baseline audition", function() A.audition(id, 69, 110) end },
    { "undo/redo churn then audition", function() C.set_volume(id, 0.8) D.key("z", { cmd = true }) D.key("z", { cmd = true, shift = true }) P.refresh(true) tr = P.track(id).ptr A.audition(id, 72, 110) end },
    { "second audition (same state)", function() A.audition(id, 74, 110) end },
    { "disarm/arm cycle", function() tr = P.track(id).ptr r.SetMediaTrackInfo_Value(tr, "I_RECARM", 0) r.SetMediaTrackInfo_Value(tr, "I_RECARM", 1) r.StuffMIDIMessage(0, 0x90, 76, 110) end },
    { "recinput reset", function() tr = P.track(id).ptr r.SetMediaTrackInfo_Value(tr, "I_RECINPUT", 4096 + 63 * 32) r.SetMediaTrackInfo_Value(tr, "I_RECINPUT", 6080) r.StuffMIDIMessage(0, 0x90, 77, 110) end },
    { "fx count / enabled", function() tr = P.track(id).ptr T.info("fxcount="..r.TrackFX_GetCount(tr).." enabled="..tostring(r.TrackFX_GetEnabled(tr,0)).." instr="..r.TrackFX_GetInstrument(tr).." recmode="..r.GetMediaTrackInfo_Value(tr,"I_RECMODE").." vol="..r.GetMediaTrackInfo_Value(tr,"D_VOL").." mute="..r.GetMediaTrackInfo_Value(tr,"B_MUTE")) r.StuffMIDIMessage(0, 0x90, 79, 110) end },
  }
  local idx = 0
  local function nextv()
    idx = idx + 1
    if idx > #variants then D.stop() T.finish() return end
    local v = variants[idx]
    v[2]()
    local mx = 0
    T.poll(1.0, function() D.frames(1) local m = A.meter(id) mx = math.max(mx, m.l, m.r) end, function()
      T.info(string.format("%-36s meter peak=%.3f", v[1], mx))
      for _, n in ipairs{69,72,74,76,77,79} do r.StuffMIDIMessage(0, 0x80, n, 0) end
      T.poll(0.5, function() D.frames(1) end, nextv)
    end)
  end
  nextv()
end)
