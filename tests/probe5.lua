local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness") T.setup(root)
local P, C = require("project"), require("commands")
T.run(function()
  C.new_project("x") local t = C.create_track("midi","A","Lead Synth") local d = C.create_track("midi","D","Drum Kit")
  for _, id in ipairs{t, d} do
    local tr = P.track(id).ptr
    local _, n = r.TrackFX_GetFXName(tr, 0, "")
    T.info("GetFXName: " .. n)
    for _, k in ipairs{"fx_type","fx_ident","fx_name","original_name","renamed_name","vst_chunk_len","fx_type_name","parm_count"} do
      local ok, v = r.TrackFX_GetNamedConfigParm(tr, 0, k)
      T.info(string.format("  %-14s ok=%s v=%s", k, tostring(ok), tostring(v):sub(1,60)))
    end
  end
  T.finish()
end)
