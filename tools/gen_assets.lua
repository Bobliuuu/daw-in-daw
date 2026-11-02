-- run with system lua:  lua tools/gen_assets.lua   (regenerates assets/drums/*.wav and examples/demo_loop.wav)
package.path = "src/?.lua;" .. package.path
local G = require("audio.drumgen")
G.ensure_kit("assets/drums")
G.demo_loop("examples/demo_loop.wav", 120)
print("ok")
