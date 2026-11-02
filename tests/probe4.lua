local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness") T.setup(root)
local D = require("ui_driver")
T.run(function()
  D.start({ w = 1280, h = 800 })
  local A = D.A
  local t0 = r.time_precise()
  local str = A.snapshot_str(1)
  T.info(string.format("snapshot_str 1280x800: %.3fs (%d bytes)", r.time_precise() - t0, #str))
  local f = io.open(T.out .. "/p4.ppm", "wb") f:write(str) f:close()
  t0 = r.time_precise() A.snapshot_str(1) T.info(string.format("again: %.3fs", r.time_precise() - t0))
  t0 = r.time_precise()
  A.snapshot(T.out .. "/p4.ppm", 2)
  T.info(string.format("half-res snapshot: %.2fs", r.time_precise() - t0))
  -- alternative: gfx.getimgdim/blit to image buffer then read? time getpixel only
  t0 = r.time_precise()
  local n = 0
  for i = 1, 200000 do gfx.x, gfx.y = i % 1280, i % 800 local a, b, c = gfx.getpixel() n = n + a end
  T.info(string.format("200k getpixel calls: %.2fs", r.time_precise() - t0))
  T.finish()
end)
