local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness") T.setup(root)
local P, C = require("project"), require("commands")
local function probe(label, c)
  local acc = r.CreateTakeAudioAccessor(c.take)
  local buf = r.new_array(4096)
  local rv = r.GetAudioAccessorSamples(acc, 8000, 1, 0.0, 1000, buf)
  local mx = 0 for i = 1, 1000 do mx = math.max(mx, math.abs(buf[i])) end
  T.info(string.format("%s: retval=%s bufmax=%.3f", label, tostring(rv), mx))
  r.DestroyAudioAccessor(acc)
end
local c
r.defer(function()
  C.new_project("x") local t = C.create_track("audio","A")
  local id = C.import_audio(t, root.."/examples/demo_loop.wav", 0)
  c = P.clip(id)
  probe("plain defer (immediately)", c)
  local n = 0
  local function later()
    n = n + 1
    if n < 20 then r.defer(later) return end
    probe("plain defer (later)", c)
    local co = coroutine.wrap(function() probe("inside coroutine", c) end)
    co()
    T.finish()
  end
  r.defer(later)
end)
