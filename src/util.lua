-- util.lua : small pure helpers (no reaper dependency)
local U = {}
function U.clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function U.round(x) return math.floor(x + 0.5) end
function U.snap(x, g) if not g or g <= 0 then return x end return math.floor(x / g + 0.5) * g end
function U.snap_floor(x, g) if not g or g <= 0 then return x end return math.floor(x / g + 1e-9) * g end
function U.near(a, b, e) return math.abs(a - b) <= (e or 1e-6) end
function U.lerp(a, b, t) return a + (b - a) * t end
function U.copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
function U.db_to_lin(db) if db <= -150 then return 0 end return 10 ^ (db / 20) end
function U.lin_to_db(l) if l <= 1e-7 then return -150 end return 20 * math.log(l, 10) end
local NOTE = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
function U.note_name(p) return NOTE[p % 12 + 1] .. (p // 12 - 1) end
function U.is_black(p) return ({ [1] = true, [3] = true, [6] = true, [8] = true, [10] = true })[p % 12] == true end
function U.pt_in(x, y, rx, ry, rw, rh) return x >= rx and x < rx + rw and y >= ry and y < ry + rh end
function U.basename(p) return (p:gsub("^.*[/\\]", "")) end
function U.dirname(p) return (p:match("^(.*)[/\\][^/\\]*$")) or "." end
function U.strip_ext(p) return (p:gsub("%.[^./\\]*$", "")) end
function U.ext(p) return (p:match("%.([^./\\]*)$") or ""):lower() end
local seeded = false
function U.uid()
  if reaper and reaper.genGuid then return reaper.genGuid("") end
  if not seeded then math.randomseed(os.time()) seeded = true end
  return string.format("%08x-%04x", math.random(0, 0x7fffffff), math.random(0, 0xffff))
end
function U.fmt_time(sec)
  local m = math.floor(sec / 60)
  return string.format("%d:%05.2f", m, sec - m * 60)
end
return U
