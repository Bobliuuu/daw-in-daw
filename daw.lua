-- DAW in DAW : a multitrack DAW implemented inside REAPER with nothing but built-in Lua (ReaScript) + gfx.
-- Run:  Actions > Show action list > New action > Load ReaScript... > daw.lua   (run again to close)
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/[^/]*$") or "."
package.path = root .. "/src/?.lua;" .. package.path
-- fresh module state on every launch (handy while developing, harmless otherwise)
for name in pairs(package.loaded) do
  if name:match("^ui%.") or name:match("^audio%.") or name == "app" or name == "util" or name == "timeline" or name == "host"
    or name == "project" or name == "commands" or name == "wavio" then package.loaded[name] = nil end
end
require("app").start()
