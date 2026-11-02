local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness") T.setup(root)
local P, C = require("project"), require("commands")
local variants = {
  { "mode0 rec+mon, input VKB(6080)", function(tr) r.SetMediaTrackInfo_Value(tr,"I_RECINPUT",6080) r.SetMediaTrackInfo_Value(tr,"I_RECARM",1) r.SetMediaTrackInfo_Value(tr,"I_RECMON",1) r.StuffMIDIMessage(0,0x90,69,110) end },
  { "mode1 (VKB current chan)", function(tr) r.StuffMIDIMessage(1,0x90,69,110) end },
  { "mode0 with recmode=2 (output midi?)", function(tr) r.SetMediaTrackInfo_Value(tr,"I_RECMODE",0) r.StuffMIDIMessage(0,0x90,72,110) end },
  { "mode0 note 0x91 chan2", function(tr) r.StuffMIDIMessage(0,0x91,69,110) end },
  { "input all MIDI(4096+63*32)", function(tr) r.SetMediaTrackInfo_Value(tr,"I_RECINPUT",4096+63*32) r.StuffMIDIMessage(0,0x90,69,110) end },
  { "mode2 control", function(tr) r.StuffMIDIMessage(2,0x90,69,110) end },
}
local idx, cur = 0, nil
T.run(function()
  C.new_project("x") local id = C.create_track("midi","A","Lead Synth") local tr = P.track(id).ptr
  T.info(string.format("audio device? GetNumAudioInputs=%d outputs=%d  is_running=%s", r.GetNumAudioInputs(), r.GetNumAudioOutputs(), tostring(r.Audio_IsRunning())))
  local function nextv()
    idx = idx + 1
    if idx > #variants then T.finish() return end
    local v = variants[idx]
    v[2](tr)
    local mx = 0
    T.poll(0.9, function() mx = math.max(mx, r.Track_GetPeakInfo(tr,0)) end, function()
      r.StuffMIDIMessage(0,0x80,69,0) r.StuffMIDIMessage(0,0x80,72,0)
      T.info(string.format("%-40s peak=%.3f  (arm=%d mon=%d in=%d)", v[1], mx, r.GetMediaTrackInfo_Value(tr,"I_RECARM"), r.GetMediaTrackInfo_Value(tr,"I_RECMON"), r.GetMediaTrackInfo_Value(tr,"I_RECINPUT")))
      T.poll(0.4, nil, nextv)
    end)
  end
  nextv()
end)
