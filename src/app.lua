-- app.lua : the inner DAW application. Owns the frame loop, layout, input dispatch, shortcuts and dialogs.
-- Architecture: immediate-mode UI (ui/*) reads the cached project snapshot (project.lua) and mutates REAPER
-- exclusively through commands.lua. REAPER remains the single source of truth for all musical state.
local r = reaper
local G = require("ui.gx")
local L = require("ui.layout")
local S = require("ui.state")
local TL = require("timeline")
local U = require("util")
local H = require("host")
local P = require("project")
local C = require("commands")
local I = require("audio.instruments")
local TR = require("audio.transport")
local X = require("audio.export")
local TB = require("ui.transport_bar")
local Arr = require("ui.arrangement")
local PR = require("ui.piano_roll")
local Mix = require("ui.mixer")
local Dev = require("ui.devices")
local B = require("ui.browser")

local App = { VERSION = "1.0.0" }
local A = { P = P, C = C, S = S, TR = TR, G = G, H = H, running = false }
App.A = A

----------------------------------------------------------------------------- helpers exposed to panels
function A.msg(text, kind) S.msg, S.msg_kind, S.msg_t = text, kind or "info", G.now end
function A.safe(fn, ...)
  local ok, a, b = pcall(fn, ...)
  if not ok then A.msg(tostring(a), "error") return nil end
  return a, b
end

local meters = {}
function A.meter(id) return meters[id] or { l = 0, r = 0, hold = 0 } end
local function update_meters()
  local snap = P.snap
  local function upd(id, tr)
    local m = meters[id] or { l = 0, r = 0, hold = 0, ht = 0 }
    local l, rr = r.Track_GetPeakInfo(tr, 0), r.Track_GetPeakInfo(tr, 1)
    m.l = math.max(l, m.l * 0.86) m.r = math.max(rr, m.r * 0.86)
    local pk = math.max(l, rr)
    if pk >= m.hold or G.now - m.ht > 1.2 then m.hold = math.max(pk, m.hold * 0.93) if pk >= m.hold then m.ht = G.now end end
    meters[id] = m
  end
  for _, t in ipairs(snap.tracks) do if r.ValidatePtr2(0, t.ptr, "MediaTrack*") then upd(t.id, t.ptr) end end
  upd("master", r.GetMasterTrack(0))
end

----------------------------------------------------------------------------- MIDI audition through the virtual keyboard
local armed, pending_off = nil, {}
local VKB_INPUT = 4096 + 62 * 32   -- MIDI input: Virtual MIDI Keyboard, all channels
function A.audition(track_id, pitch, vel)
  local t = P.track(track_id)
  if not t or t.kind ~= "midi" or not r.ValidatePtr2(0, t.ptr, "MediaTrack*") then return end
  if armed ~= track_id then
    if armed then local o = P.track(armed) if o and r.ValidatePtr2(0, o.ptr, "MediaTrack*") then r.SetMediaTrackInfo_Value(o.ptr, "I_RECARM", 0) r.SetMediaTrackInfo_Value(o.ptr, "I_RECMON", 0) end end
    r.SetMediaTrackInfo_Value(t.ptr, "I_RECINPUT", VKB_INPUT)
    r.SetMediaTrackInfo_Value(t.ptr, "I_RECARM", 1)
    r.SetMediaTrackInfo_Value(t.ptr, "I_RECMON", 1)
    armed = track_id
  end
  r.StuffMIDIMessage(0, 0x90, pitch, vel or 100)
  pending_off[#pending_off + 1] = { pitch = pitch, t = G.now + 0.25 }
end
local function service_audition()
  for i = #pending_off, 1, -1 do
    if G.now >= pending_off[i].t then r.StuffMIDIMessage(0, 0x80, pending_off[i].pitch, 0) table.remove(pending_off, i) end
  end
end
local function disarm_all()
  if armed then local o = P.track(armed) if o and r.ValidatePtr2(0, o.ptr, "MediaTrack*") then r.SetMediaTrackInfo_Value(o.ptr, "I_RECARM", 0) r.SetMediaTrackInfo_Value(o.ptr, "I_RECMON", 0) end armed = nil end
end

----------------------------------------------------------------------------- high-level actions
function A.open_clip(id)
  local c = P.clip(id)
  if c and c.kind == "midi" then PR.open(A, c) end
end

function A.select_clip(id) local c = P.clip(id) if c then S.sel_clip, S.sel_track = c.id, c.track_id end end

local function first_free_slot(track, start, len, bpb)
  local s = start
  for _ = 1, 256 do
    if not C.overlaps(track, s, s + len) then return s end
    s = s + bpb
  end
end

function A.new_clip_at(track_id, beat)
  local t = P.track(track_id)
  if not t then return end
  local bpb = TL.beats_per_bar(P.snap.num, P.snap.den)
  local start = math.floor((beat or TR.position()) / bpb + 1e-9) * bpb
  start = first_free_slot(t, start, bpb, bpb)
  if not start then A.msg("No free space for a clip", "warn") return end
  local id = A.safe(C.create_clip, track_id, start, bpb, "Pattern")
  if id then S.sel_track = track_id A.open_clip(id) end
  return id
end

function A.duplicate_selected()
  local c = S.sel_clip and P.clip(S.sel_clip)
  if not c then A.msg("Select a clip first", "warn") return end
  local bpb = TL.beats_per_bar(P.snap.num, P.snap.den)
  local dest = first_free_slot(c.track, c.start + c.len, c.len, bpb)
  local id = dest and A.safe(C.duplicate_clip, c.id, dest)
  if id then S.sel_clip = id end
end

function A.copy_selected()
  local c = S.sel_clip and P.clip(S.sel_clip)
  if c then S.clipboard = C.copy_chunk(c.id) A.msg("Copied clip") end
end
function A.paste_at(track_id, beat)
  if not S.clipboard then return end
  track_id = track_id or S.sel_track
  if not track_id then A.msg("Select a track to paste into", "warn") return end
  local id = A.safe(C.paste_chunk, S.clipboard, track_id, beat or TR.position())
  if id then S.sel_clip = id end
end

function A.add_track_menu(x, y)
  local items = {
    { label = "Drum Kit (sampler)", fn = function() A.add_track("midi", "Drums", "Drum Kit") end },
    { label = "Bass Synth", fn = function() A.add_track("midi", "Bass", "Bass Synth") end },
    { label = "Lead Synth", fn = function() A.add_track("midi", "Lead", "Lead Synth") end },
    { label = "Pad Synth", fn = function() A.add_track("midi", "Pad", "Pad Synth") end },
    { label = "Pluck", fn = function() A.add_track("midi", "Pluck", "Pluck") end },
    { sep = true },
    { label = "Audio track", fn = function() A.add_track("audio", "Audio") end },
  }
  G.popup(items, x or 100, y or 50)
end
function A.add_track(kind, name, inst)
  local id = A.safe(C.create_track, kind, name, inst)
  if id then S.sel_track = id A.msg("Added track " .. name) end
  return id
end

function A.import_audio_dialog(track_id, beat)
  local t = track_id and P.track(track_id) or (S.sel_track and P.track(S.sel_track))
  if not t or t.kind ~= "audio" then
    for _, tt in ipairs(P.snap.tracks) do if tt.kind == "audio" then t = tt break end end
  end
  local dir = S.browser.dir or (H.script_dir() .. "/examples")
  B.pick(A, { mode = "file", dir = dir, title = "Import audio", on_pick = function(path)
    local tr = t
    if not tr then
      local id = A.add_track("audio", "Audio")
      tr = id and P.track(id)
    end
    if not tr then return end
    local at = beat or TR.position()
    at = U.snap(at, TL.beats_per_bar(P.snap.num, P.snap.den))
    local id = A.safe(C.import_audio, tr.id, path, at)
    if id then S.sel_clip, S.sel_track = id, tr.id A.msg("Imported " .. U.basename(path)) end
  end })
end

function A.has_path() local _, fn = r.EnumProjects(-1) return fn and fn ~= "" and fn or nil end
function A.save()
  A.save_prefs()
  if A.has_path() then r.Main_SaveProject(0, false) A.msg("Saved " .. U.basename(A.has_path()))
  else B.save_as(A) end
end

function A.open_export() B.export(A) end
function A.export_now(opts)
  if TR.is_playing() then TR.stop() end
  local ok, res = pcall(X.render, opts)
  if not ok then res = { ok = false, err = tostring(res) } end
  if res.ok then A.msg("Exported " .. res.path) else A.msg("Export failed: " .. tostring(res.err), "error") end
  return res
end

function A.new_project()
  local function go() A.safe(C.new_project, "Untitled") S.sel_track, S.sel_clip, S.edit_clip = nil, nil, nil end
  go()
end

----------------------------------------------------------------------------- prefs (project ext-state)
function A.save_prefs()
  if not P.snap or not P.snap.has_root then return end
  local v = string.format("ppb=%.2f;snap=%d;tab=%s;bh=%d;th=%d", S.arr.view.ppb, S.snap_idx, S.tab, S.bottom_h, S.arr.track_h)
  local _, cur = r.GetProjExtState(0, "daw_in_daw", "ui")
  if cur ~= v then r.SetProjExtState(0, "daw_in_daw", "ui", v) end
end
function A.load_prefs()
  local _, v = r.GetProjExtState(0, "daw_in_daw", "ui")
  if v == "" then return end
  local t = {} for k, val in v:gmatch("(%w+)=([^;]+)") do t[k] = val end
  S.arr.view.ppb = U.clamp(tonumber(t.ppb) or S.arr.view.ppb, TL.MIN_PPB, TL.MAX_PPB)
  S.snap_idx = U.clamp(tonumber(t.snap) or S.snap_idx, 1, #S.SNAPS)
  if t.tab == "roll" or t.tab == "mixer" or t.tab == "devices" then S.tab = t.tab end
  S.bottom_h = tonumber(t.bh) or S.bottom_h
  S.arr.track_h = tonumber(t.th) or S.arr.track_h
end

----------------------------------------------------------------------------- keyboard
local function handle_keys()
  if G.modal or G.popup_ then return end
  for _, k in ipairs(G.keys) do
    local handled = false
    if k.name == "space" then TR.toggle() handled = true
    elseif k.cmd and k.lower == "z" and not k.shift then C.undo() handled = true
    elseif k.cmd and ((k.lower == "z" and k.shift) or k.lower == "y") then C.redo() handled = true
    elseif k.cmd and k.lower == "s" then A.save() handled = true
    elseif k.cmd and k.lower == "d" then A.duplicate_selected() handled = true
    elseif k.cmd and k.lower == "c" then A.copy_selected() handled = true
    elseif k.cmd and k.lower == "x" then A.copy_selected() if S.sel_clip then C.delete_clip(S.sel_clip) S.sel_clip = nil end handled = true
    elseif k.cmd and k.lower == "v" then A.paste_at(S.sel_track, TR.position()) handled = true
    elseif k.cmd and k.lower == "e" then A.open_export() handled = true
    elseif k.cmd and k.lower == "i" then A.import_audio_dialog() handled = true
    elseif k.cmd and k.lower == "t" then A.add_track_menu(120, 50) handled = true
    elseif k.name == "home" then TR.seek(0) handled = true
    elseif k.name == "esc" then S.sel_clip = nil handled = true
    end
    if not handled and S.focus == "roll" and S.tab == "roll" then handled = PR.key(A, k) end
    if not handled and not k.cmd then
      if k.name == "backspace" or k.name == "delete" then
        if S.sel_clip then
          local id = S.sel_clip
          C.delete_clip(id) if S.edit_clip == id then S.edit_clip = nil end S.sel_clip = nil handled = true
        end
      elseif k.lower == "l" then
        local ls, le = TR.loop()
        if le <= ls then TR.set_loop(0, TL.beats_per_bar(P.snap.num, P.snap.den) * 4) end
        TR.set_loop_enabled(not TR.loop_enabled()) handled = true
      elseif k.lower == "s" and not k.shift then
        if S.sel_clip then
          local ok = A.safe(C.split_clip, S.sel_clip, TR.position())
          if not ok then A.msg("Place the playhead inside the selected clip to split", "warn") end
        end
        handled = true
      elseif k.lower == "s" and k.shift and S.sel_track then local t = P.track(S.sel_track) if t then C.set_solo(t.id, not t.solo) end handled = true
      elseif k.lower == "m" and S.sel_track then local t = P.track(S.sel_track) if t then C.set_mute(t.id, not t.mute) end handled = true
      elseif k.ch == "1" then S.tab = "roll" handled = true
      elseif k.ch == "2" then S.tab = "mixer" handled = true
      elseif k.ch == "3" then S.tab = "devices" handled = true
      elseif k.ch == "=" or k.ch == "+" then TL.zoom(S.arr.view, 1.25, (A.R and A.R.arr_lanes[3] or 800) / 2, 0) handled = true
      elseif k.ch == "-" then TL.zoom(S.arr.view, 1 / 1.25, (A.R and A.R.arr_lanes[3] or 800) / 2, 0) handled = true
      elseif k.ch == "[" then S.snap_idx = math.max(1, S.snap_idx - 1) handled = true
      elseif k.ch == "]" then S.snap_idx = math.min(#S.SNAPS, S.snap_idx + 1) handled = true
      end
    end
  end
end

----------------------------------------------------------------------------- panels: tabs, welcome, status
local function draw_tabs(R)
  local T = G.theme
  local tr = R.tabs
  G.rect(tr[1], tr[2], tr[3], tr[4], T.panel)
  G.hline(0, tr[2], tr[3], T.line)
  local x = 8
  for _, tab in ipairs { { "roll", "Piano Roll" }, { "mixer", "Mixer" }, { "devices", "Devices" } } do
    local w = 96
    if G.button("tab_" .. tab[1], x, tr[2] + 2, w, 22, tab[2], { on = S.tab == tab[1], on_color = T.panel3, on_text = T.accent, size = 12, bg = T.panel }) then S.tab = tab[1] end
    if S.tab == tab[1] then G.rect(x, tr[2] + 23, w, 2, T.accent) end
    x = x + w + 2
  end
  if S.tab == "roll" then
    local c = S.edit_clip and P.clip(S.edit_clip)
    if c then
      G.text(string.format("%s  -  %s   (%d notes)   note length %.3g   snap %s", c.track.name, c.name ~= "" and c.name or "clip", #P.notes(c), S.roll.note_len, S.snap_label()), x + 16, tr[2] + 6, T.dim, 11, "l", tr[3] - x - 300)
    end
    G.text("LMB draw / drag  -  RMB delete  -  Shift-drag select  -  Q quantize  -  arrows move", tr[3] - 480, tr[2] + 6, T.faint, 11, "r", 470)
  end
end

local function draw_welcome(R)
  local T = G.theme
  local a = R.arr
  G.rect(0, a[2], a[3], R.bottom[2] + R.bottom[4] - a[2], T.bg)
  local w, h = 520, 250
  local x, y = (G.W - w) / 2, a[2] + math.max(20, (R.status[2] - a[2] - h) / 2 - 30)
  G.rect(x, y, w, h, T.panel2) G.frame(x, y, w, h, T.line2)
  G.text("DAW in DAW", x + 30, y + 26, T.accent, 28)
  G.text("A multitrack DAW running inside REAPER, written in Lua.", x + 30, y + 66, T.text, 13, "l", w - 60)
  G.text("Every track, clip, note, fader and effect is a real REAPER object.", x + 30, y + 86, T.dim, 12, "l", w - 60)
  if G.button("welcome_new", x + 30, y + 130, 190, 40, "New project", { bg = T.accent, color = { 20, 20, 24 }, size = 14 }) then A.new_project() end
  G.text("Your existing REAPER tracks are never touched:\nthe DAW works only inside its own folder track.", x + 30, y + 190, T.faint, 11, "l", w - 60)
end

local function draw_status(R)
  local T = G.theme
  local s = R.status
  G.rect(s[1], s[2], s[3], s[4], T.panel)
  G.hline(0, s[2], s[3], T.line)
  local snap = P.snap
  local msg = S.msg
  if msg and G.now - S.msg_t < 8 then
    local c = S.msg_kind == "error" and T.red or (S.msg_kind == "warn" and T.yellow or T.dim)
    G.text(msg, 10, s[2] + 5, c, 11, "l", s[3] - 420)
  else
    G.text("Space play/stop  -  Cmd+Z undo  -  Cmd+D duplicate  -  S split  -  L loop  -  Cmd+E export", 10, s[2] + 5, T.faint, 11, "l", s[3] - 420)
  end
  local nn = 0
  for _, c in ipairs(snap.clips) do if c.kind == "midi" then nn = nn + 1 end end
  local right = string.format("%d tracks  %d clips%s", #snap.tracks, #snap.clips, S.show_perf and string.format("   %.0f fps  %.1f ms", S.perf.fps, S.perf.frame_ms) or "")
  G.text(right, s[3] - 330, s[2] + 5, T.dim, 11, "r", 320)
end

local function handle_splitter(R)
  local sp = R.split
  local T = G.theme
  local hov = G.over(sp[1], sp[2] - 2, sp[3], sp[4] + 4)
  G.rect(sp[1], sp[2], sp[3], sp[4], (hov or G.active == "split") and T.accent or T.line, (hov or G.active == "split") and 0.7 or 1)
  if hov and G.m.pressed then G.capture("split") end
  if G.active == "split" then
    if G.m.down then S.bottom_h = U.clamp(G.H - L.STATUS_H - G.m.y - 3, L.MIN_BOTTOM_H, G.H - L.TRANSPORT_H - L.STATUS_H - L.MIN_ARR_H - L.SPLIT_H)
    else G.release() end
  end
end

----------------------------------------------------------------------------- framebuffer snapshot (visual inspection / regression)
-- gfx.getpixel readback -> binary PPM. step=1 captures every device pixel; step=2 halves resolution on retina.
function A.snapshot(path, step)
  step = step or 1
  local w, h = math.floor(gfx.w), math.floor(gfx.h)
  local ow, oh = w // step, h // step
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(string.format("P6\n%d %d\n255\n", ow, oh))
  local char, getpixel = string.char, gfx.getpixel
  for y = 0, oh - 1 do
    local row = {}
    for x = 0, ow - 1 do
      gfx.x, gfx.y = x * step, y * step
      local rr, gg, bb = getpixel()
      row[#row + 1] = char(math.floor(rr * 255 + 0.5), math.floor(gg * 255 + 0.5), math.floor(bb * 255 + 0.5))
    end
    f:write(table.concat(row))
  end
  f:close()
  return true
end

local DEBUG_DIR = os.getenv("DAW_DEBUG_DIR")
local function service_debug()
  if not DEBUG_DIR then return end
  local f = io.open(DEBUG_DIR .. "/snap_request", "r")
  if f then
    local path = f:read("l") local step = tonumber(f:read("l") or "") or 2
    f:close() os.remove(DEBUG_DIR .. "/snap_request")
    if path then A.snapshot(path, step) local d = io.open(path .. ".done", "w") d:write("ok") d:close() end
  end
end

----------------------------------------------------------------------------- frame
local frame_times = {}
function A.step()
  local t0 = r.time_precise()
  G.resize()
  local alive = G.begin_frame()
  if not alive then return false end
  P.refresh()
  update_meters()
  service_audition()
  -- validate selection against the (possibly externally edited) project
  if S.sel_clip and not P.clip(S.sel_clip) then S.sel_clip = nil end
  if S.edit_clip and not P.clip(S.edit_clip) then S.edit_clip = nil end
  if S.sel_track and not P.track(S.sel_track) then S.sel_track = nil end
  if not S.sel_track and #P.snap.tracks > 0 then S.sel_track = P.snap.tracks[1].id end

  local R = L.compute(G.W, G.H, S)
  A.R = R
  G.rect(0, 0, G.W, G.H, G.theme.bg)
  handle_keys()
  if P.snap.has_root then
    TB.draw(A, R)
    Arr.draw(A, R)
    handle_splitter(R)
    draw_tabs(R)
    if S.tab == "roll" then PR.draw(A, R) elseif S.tab == "mixer" then Mix.draw(A, R) else Dev.draw(A, R) end
  else
    TB.draw(A, R)
    draw_welcome(R)
  end
  draw_status(R)
  G.end_frame()
  service_debug()
  gfx.update()
  local dt = r.time_precise() - t0
  frame_times[#frame_times + 1] = dt
  if #frame_times > 30 then table.remove(frame_times, 1) end
  local sum = 0 for _, v in ipairs(frame_times) do sum = sum + v end
  S.perf.frame_ms = sum / #frame_times * 1000
  S.perf.fps = 1000 / math.max(0.1, S.perf.frame_ms)
  return true
end

function A.shutdown()
  if not A.running then return end
  A.running = false
  A.save_prefs()
  disarm_all()
  r.SetExtState("daw_in_reaper", "dock", tostring(gfx.dock(-1)), true)
  r.SetExtState("daw_in_reaper", "hb", "0", false)
  gfx.quit()
end

local function loop()
  if not A.running then return end
  if r.GetExtState("daw_in_reaper", "quit") == "1" then r.SetExtState("daw_in_reaper", "quit", "0", false) A.shutdown() return end
  r.SetExtState("daw_in_reaper", "hb", string.format("%.3f", r.time_precise()), false)
  local ok, alive = xpcall(A.step, debug.traceback)
  if not ok then
    A.msg("UI error: " .. tostring(alive):sub(1, 200), "error")
    r.ShowConsoleMsg("[DAW-in-DAW] " .. tostring(alive) .. "\n")
    if DEBUG_DIR then local ef = io.open(DEBUG_DIR .. "/errors.txt", "a") if ef then ef:write(tostring(alive), "\n") ef:close() end end
    gfx.update()
  elseif not alive then A.shutdown() return end
  r.defer(loop)
end

-- opts: w,h (logical px), no_singleton, headless (do not start the defer loop)
function App.start(opts)
  opts = opts or {}
  if not opts.no_singleton then
    local hb = tonumber(r.GetExtState("daw_in_reaper", "hb")) or 0
    if r.time_precise() - hb < 1.0 and hb > 0 then
      r.SetExtState("daw_in_reaper", "quit", "1", false) -- running instance: toggle it off
      return nil
    end
  end
  gfx.ext_retina = 1
  local dock = tonumber(r.GetExtState("daw_in_reaper", "dock")) or 0
  if opts.dock then dock = opts.dock end
  local rv = gfx.init("DAW in DAW", opts.w or 1280, opts.h or 800, dock)
  if rv == 0 then r.ShowConsoleMsg("[DAW-in-DAW] gfx.init failed\n") return nil end
  G.resize()
  A.running = true
  P.refresh(true)
  A.load_prefs()
  r.atexit(function() if A.running then A.shutdown() end end)
  if not opts.headless then r.defer(loop) end
  return A
end

return App
