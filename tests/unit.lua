-- unit tests for the pure-Lua modules. Run:  lua tests/unit.lua   (no REAPER needed)
local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$") or "."
package.path = root .. "/src/?.lua;" .. package.path
local U, TL, L, W = require("util"), require("timeline"), require("ui.layout"), require("wavio")
local passes, fails = 0, {}
local function ok(name, cond, detail) if cond then passes = passes + 1 else fails[#fails + 1] = name .. (detail and (" :: " .. tostring(detail)) or "") end end
local function eq(name, a, b, tol) ok(name, (type(a) == "number" and type(b) == "number") and math.abs(a - b) <= (tol or 1e-9) or a == b, string.format("got %s want %s", tostring(a), tostring(b))) end

-- ---- util
eq("clamp low", U.clamp(-5, 0, 10), 0) eq("clamp high", U.clamp(50, 0, 10), 10) eq("clamp mid", U.clamp(5, 0, 10), 5)
eq("snap 1/4", U.snap(1.13, 0.25), 1.25) eq("snap down", U.snap(1.12, 0.25), 1.0) eq("snap off", U.snap(1.13, 0), 1.13)
eq("snap_floor", U.snap_floor(1.99, 0.5), 1.5) eq("snap_floor exact", U.snap_floor(2.0, 0.5), 2.0)
eq("snap negative", U.snap(-0.3, 0.25), -0.25)
eq("note name C4", U.note_name(60), "C4") eq("note name A0", U.note_name(21), "A0") eq("note name F#2", U.note_name(42), "F#2") eq("note 0", U.note_name(0), "C-1") eq("note 127", U.note_name(127), "G9")
ok("black keys", U.is_black(61) and U.is_black(70) and not U.is_black(60) and not U.is_black(64))
eq("db->lin 0", U.db_to_lin(0), 1) eq("db->lin -6", U.db_to_lin(-6.0206), 0.5, 1e-4) eq("lin->db 1", U.lin_to_db(1), 0) eq("lin->db 0", U.lin_to_db(0), -150)
eq("db roundtrip", U.lin_to_db(U.db_to_lin(-13.7)), -13.7, 1e-9)
eq("basename", U.basename("/a/b/c.wav"), "c.wav") eq("dirname", U.dirname("/a/b/c.wav"), "/a/b") eq("ext", U.ext("X.WAV"), "wav") eq("strip_ext", U.strip_ext("/a/b/c.d.wav"), "/a/b/c.d")
eq("fmt_time", U.fmt_time(65.5), "1:05.50")
local ids = {} for i = 1, 500 do ids[U.uid()] = true end
local n = 0 for _ in pairs(ids) do n = n + 1 end
ok("uids are unique (500)", n == 500, n)

-- ---- timeline: coordinate conversion
local v = TL.new_view(40) v.x0 = 3
eq("beat->x", TL.beat_to_x(v, 5, 100), 100 + 2 * 40) eq("x->beat", TL.x_to_beat(v, 180, 100), 5)
for _, b in ipairs { 0, 0.25, 7.125, 100 } do eq("x/beat roundtrip " .. b, TL.x_to_beat(v, TL.beat_to_x(v, b, 77), 77), b, 1e-9) end
-- zoom keeps the anchor beat fixed
local zv = TL.new_view(40) zv.x0 = 8
local before = TL.x_to_beat(zv, 300, 50)
TL.zoom(zv, 2, 300, 50)
eq("zoom anchor stays put", TL.x_to_beat(zv, 300, 50), before, 1e-9) eq("zoom doubles ppb", zv.ppb, 80)
TL.zoom(zv, 1000, 300, 50) eq("zoom clamps max", zv.ppb, TL.MAX_PPB)
TL.zoom(zv, 1e-6, 300, 50) eq("zoom clamps min", zv.ppb, TL.MIN_PPB)
local sv = TL.new_view(40) TL.scroll(sv, -5) eq("scroll cannot go negative", sv.x0, 0) TL.scroll(sv, 4.5) eq("scroll", sv.x0, 4.5)
-- bars / signatures
eq("bpb 4/4", TL.beats_per_bar(4, 4), 4) eq("bpb 3/4", TL.beats_per_bar(3, 4), 3) eq("bpb 6/8", TL.beats_per_bar(6, 8), 3) eq("bpb 7/8", TL.beats_per_bar(7, 8), 3.5) eq("bpb 5/4", TL.beats_per_bar(5, 4), 5)
local b, bt, fr = TL.bar_beat(0, 4, 4) ok("bar_beat origin", b == 1 and bt == 1 and fr == 0)
b, bt, fr = TL.bar_beat(5.5, 4, 4) ok("bar_beat 5.5 in 4/4 => 2.2.50", b == 2 and bt == 2 and math.abs(fr - 0.5) < 1e-9, b .. "." .. bt .. "." .. fr)
b, bt = TL.bar_beat(9, 3, 4) ok("bar_beat 9 in 3/4 => bar 4 beat 1", b == 4 and bt == 1, b .. "." .. bt)
b, bt = TL.bar_beat(3.5, 6, 8) ok("bar_beat 6/8: 3.5 QN = bar 2, 2nd eighth", b == 2 and bt == 2, b .. "." .. bt)
b, bt = TL.bar_beat(3.99, 4, 4) ok("bar_beat just before the barline stays in bar 1", b == 1 and bt == 4, b .. "." .. bt)
b, bt = TL.bar_beat(3.9999999999, 4, 4) ok("bar_beat float noise at the barline counts as the next bar", b == 2 and bt == 1, b .. "." .. bt)
-- grid lines
local gv = TL.new_view(40)
local lines = TL.grid_lines(gv, 640, 4, 4)
local bars, beats = 0, 0 for _, l in ipairs(lines) do if l.kind == "bar" then bars = bars + 1 elseif l.kind == "beat" then beats = beats + 1 end end
ok("grid 640px @40ppb: 16 beats => 5 bar lines (0,4,8,12,16)", bars >= 4 and bars <= 5, bars) ok("grid has beat lines", beats >= 10, beats)
local far = TL.new_view(4) local fl = TL.grid_lines(far, 640, 4, 4) local fb = 0 for _, l in ipairs(fl) do if l.kind == "beat" then fb = fb + 1 end end
eq("zoomed far out hides beat lines", fb, 0)
-- piano roll geometry
local pv = { top = 84, row_h = 14 }
for p = 20, 90 do eq("pitch<->y roundtrip " .. p, TL.y_to_pitch(pv, TL.pitch_to_y(pv, p, 10) + 7, 10), p) end
for p = 20, 90 do eq("row top edge belongs to its own pitch " .. p, TL.y_to_pitch(pv, TL.pitch_to_y(pv, p, 0) + 0.01, 0), p) end
local pv2 = { top = 70.5, row_h = 14 } eq("fractional scroll maps rows consistently", TL.y_to_pitch(pv2, TL.pitch_to_y(pv2, 60, 0) + 7, 0), 60)
-- hit testing
local notes = { { pitch = 60, s = 1, e = 2 }, { pitch = 62, s = 1, e = 1.5 }, { pitch = 60, s = 4, e = 4.1 } }
local hv = { x0 = 0, ppb = 100 } local hp = { top = 70, row_h = 14 }
local function nx(b) return TL.beat_to_x(hv, b, 0) end local function ny(p) return TL.pitch_to_y(hp, p, 0) + 7 end
local i, z = TL.hit_note(notes, hv, hp, nx(1.5), ny(60), 0, 0) ok("hit note body", i == 1 and z == "body", tostring(i) .. tostring(z))
i, z = TL.hit_note(notes, hv, hp, nx(2) - 2, ny(60), 0, 0) ok("hit note right edge", i == 1 and z == "right", tostring(i) .. tostring(z))
i, z = TL.hit_note(notes, hv, hp, nx(1) + 2, ny(60), 0, 0) ok("hit note left edge", i == 1 and z == "left", tostring(i) .. tostring(z))
i = TL.hit_note(notes, hv, hp, nx(3), ny(60), 0, 0) ok("miss empty space", i == nil)
i = TL.hit_note(notes, hv, hp, nx(1.2), ny(61), 0, 0) ok("miss neighbouring row", i == nil)
i, z = TL.hit_note(notes, hv, hp, nx(4.05), ny(60), 0, 0) ok("tiny note is body-only (no edge zones)", i == 3 and z == "body", tostring(i) .. tostring(z))
-- overlap
ok("overlap partial", TL.overlaps(0, 4, 3, 7)) ok("overlap contained", TL.overlaps(0, 8, 2, 3)) ok("touching clips do not overlap", not TL.overlaps(0, 4, 4, 8))
ok("disjoint", not TL.overlaps(0, 1, 2, 3)) ok("float noise at the seam is tolerated", not TL.overlaps(0, 4.0000000001, 4, 8))

-- ---- layout at several window sizes
local S = { bottom_h = 310, arr = { header_w = 214 } }
for _, sz in ipairs { { 800, 520 }, { 1000, 640 }, { 1280, 800 }, { 1920, 1080 }, { 640, 400 } } do
  local W_, H_ = sz[1], sz[2]
  local R = L.compute(W_, H_, S)
  local tag = W_ .. "x" .. H_
  local function inside(r) return r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= W_ + 1e-6 and r[2] + r[4] <= H_ + 1e-6 and r[3] >= 0 and r[4] >= 0 end
  for name, r in pairs(R) do ok(tag .. " rect inside window: " .. name, inside(r), table.concat(r, ",")) end
  eq(tag .. " transport at top", R.transport[2], 0) eq(tag .. " status at bottom", R.status[2] + R.status[4], H_)
  eq(tag .. " arrangement/split/bottom tile vertically", R.arr[4] + R.split[4] + R.bottom[4] + R.status[4] + R.transport[4], H_, 1e-6)
  ok(tag .. " arrangement keeps usable height", R.arr[4] >= 60, R.arr[4])
  ok(tag .. " lanes right of headers", R.arr_lanes[1] >= R.arr_headers[3] - 1e-6)
  ok(tag .. " roll grid right of keys", R.roll_grid[1] >= R.roll_keys[3])
end
local Rbig = L.compute(1280, 800, { bottom_h = 9999, arr = { header_w = 214 } })
ok("bottom panel height is clamped so the arrangement survives", Rbig.arr[4] >= L.MIN_ARR_H - 1)
local Rsmall = L.compute(1280, 800, { bottom_h = 1, arr = { header_w = 214 } })
ok("bottom panel height has a minimum", Rsmall.bottom[4] >= L.MIN_BOTTOM_H)

-- ---- state helpers
local ST = require("ui.state")
ST.snap_idx = 4 eq("snap 1/16", ST.snap(), 0.25) eq("arrangement never snaps finer than a beat", ST.arr_snap(4), 1)
ST.snap_idx = 1 eq("Bar snap uses the bar length (3/4)", ST.arr_snap(3), 3) ST.snap_idx = 6 eq("snap off", ST.arr_snap(4), 0)

-- ---- wavio roundtrip
local path = os.tmpname() .. ".wav"
local smp = {} for k = 1, 22050 do smp[k] = 0.5 * math.sin(2 * math.pi * 440 * k / 44100) end
W.write16(path, smp, 44100, 1)
local a = W.analyze(path)
ok("wav analyze ok", a ~= nil) if a then
  eq("wav duration", a.secs, 0.5, 1e-3) eq("wav peak", a.peak, 0.5, 2e-3) eq("wav rms (sine)", a.rms, 0.5 / math.sqrt(2), 2e-3) eq("wav sr", a.sr, 44100) eq("wav bits", a.bits, 16) eq("wav channels", a.channels, 1)
end
os.remove(path)
local bad = W.analyze("/nonexistent/x.wav") ok("analyze rejects missing file", bad == nil)
local g = io.open(path, "wb") g:write("not a wav at all") g:close()
local bad2, err = W.analyze(path) ok("analyze rejects garbage", bad2 == nil and err ~= nil) os.remove(path)

-- ---- generated drum kit
local G = require("audio.drumgen")
local dir = os.tmpname() .. "_kit"
local paths = G.ensure_kit(dir)
eq("kit has 6 voices", #paths, 6)
for _, vv in ipairs(G.KIT) do
  local an = W.analyze(dir .. "/" .. vv.file)
  ok("drum sample '" .. vv.name .. "' is audible and within range", an and an.peak > 0.2 and an.peak <= 1.0 and an.secs > 0.03, an and an.peak)
  ok("drum note '" .. vv.name .. "' is in MIDI range", vv.note >= 0 and vv.note <= 127)
end
os.execute('rm -rf "' .. dir .. '"')

print(string.format("unit tests: %d passed, %d failed", passes, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
os.exit(#fails == 0 and 0 or 1)
