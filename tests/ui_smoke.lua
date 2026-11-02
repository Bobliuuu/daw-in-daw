local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$")
package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local T = require("harness") T.setup(root)
local D = require("ui_driver")
T.run(function()
  D.start()
  local ok, err = pcall(D.frames, 3)
  T.check("3 frames render without error", ok, err)
  if ok then
    D.snapshot(T.out .. "/smoke_welcome.ppm", 2)
    T.info("snapshot written")
  end
  T.finish()
end)
