-- harness.lua : tiny test harness for scripts run inside REAPER (results -> $DAW_OUT/result_<mode>.txt)
local r = reaper
local T = { log = {}, fails = 0, passes = 0 }
T.out = os.getenv("DAW_OUT") or (os.getenv("HOME") .. "/daw-in-reaper/out")
T.mode = os.getenv("DAW_MODE") or "run"
function T.root()
  return debug.getinfo(2, "S").source:match("^@(.*)/tests/[^/]*$")
end
function T.setup(root) package.path = root .. "/src/?.lua;" .. root .. "/tests/?.lua;" .. package.path T.root_dir = root end
function T.check(name, ok, detail)
  if ok then T.passes = T.passes + 1 else T.fails = T.fails + 1 end
  T.log[#T.log + 1] = string.format("%s  %-52s %s", ok and "PASS" or "FAIL", name, detail ~= nil and tostring(detail) or "")
end
function T.info(msg) T.log[#T.log + 1] = "info  " .. tostring(msg) end
function T.eq(name, a, b, tol)
  local ok
  if type(a) == "number" and type(b) == "number" then ok = math.abs(a - b) <= (tol or 1e-6) else ok = a == b end
  T.check(name, ok, string.format("got=%s want=%s", tostring(a), tostring(b)))
end
function T.finish(quit)
  T.log[#T.log + 1] = string.format("== %s: %d passed, %d failed", T.mode, T.passes, T.fails)
  local f = io.open(T.out .. "/result_" .. T.mode .. ".txt", "w") f:write(table.concat(T.log, "\n"), "\n") f:close()
  local d = io.open(T.out .. "/DONE_" .. T.mode, "w") d:write(T.fails == 0 and "ok" or "FAIL") d:close()
  if quit ~= false then r.Main_OnCommand(40004, 0) end
end
-- run fn in a deferred context with pcall so a crash is reported instead of hanging the runner
function T.run(fn)
  r.defer(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then T.check("TEST CRASHED", false, err) T.finish() end
  end)
end
-- wait helper for multi-frame steps: poll(fn) is called each defer until it returns true or timeout
function T.wait(secs, cond, done)
  local t0 = r.time_precise()
  local function step()
    if cond() or r.time_precise() - t0 > secs then done(cond()) return end
    r.defer(step)
  end
  step()
end
return T
