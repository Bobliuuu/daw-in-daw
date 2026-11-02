-- integration: the shipped example project opens from a clean checkout path, repairs missing resources, and renders.
-- mode: example   (REAPER must be started with examples/neon_drive.rpp)
local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness") T.setup(root)
local P, C, X = require("project"), require("commands"), require("audio.export")
local W = require("wavio")
T.run(function()
  T.wait_until(12, function() return r.CountTracks(0) > 0 end, function()
    P.refresh(true)
    T.check("example opens: DAW project recognised", P.snap.has_root and P.snap.name == "Neon Drive", P.snap.name)
    T.eq("example: tracks", #P.snap.tracks, 4)
    T.check("example: 13 clips", #P.snap.clips == 13, #P.snap.clips)
    local total = 0 for _, c in ipairs(P.snap.clips) do if c.kind == "midi" then total = total + #P.notes(c) end end
    T.check("example: >100 MIDI notes", total > 100, total)
    local audio_ok = true for _, c in ipairs(P.snap.clips) do if c.kind == "audio" and c.offline then audio_ok = false end end
    T.check("example: relative audio path resolves (no offline clips)", audio_ok)
    local fixed = C.repair_project()
    T.info("drum samples re-linked on open: " .. tostring(fixed))
    local res = X.render { dir = T.out .. "/export", name = "example_render", region = "project", tail_ms = 1500, overwrite = true }
    T.check("example renders", res.ok, res.err)
    local ref = W.analyze(root .. "/docs/demo/neon_drive_export.wav")
    if res.analysis and ref then
      T.eq("render duration equals shipped export", res.analysis.secs, ref.secs, 0.05)
      T.check("render level close to shipped export (peak +-0.5 dB, rms +-1 dB)", math.abs(20 * math.log(res.analysis.peak / ref.peak, 10)) < 0.5 and math.abs(20 * math.log(res.analysis.rms / ref.rms, 10)) < 1.0,
        string.format("peak %.3f vs %.3f, rms %.3f vs %.3f", res.analysis.peak, ref.peak, res.analysis.rms, ref.rms))
    end
    T.finish()
  end)
end)
