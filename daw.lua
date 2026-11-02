-- daw.lua : "DAW inside a DAW" go/no-go prototype for REAPER (ReaScript/Lua, no extensions needed)
--
-- Interactive:  run from Actions > Show action list > ReaScript: Run... (or load as action)
--   * opens dockable gfx window "DAW" (right-click title bar / drag to dock; dock state remembered)
--   * creates 2 real tracks (DAW Lead, DAW Bass) each with ReaSynth + a 2-bar MIDI clip
--   * piano roll: left-click empty cell = add note, right-click note = delete,
--     click track tab or press 1/2 = switch track, SPACE = play/stop, [ ] = note length, S = save, ESC = close
--
-- Self-test (headless-ish):  DAW_SELFTEST=build|verify DAW_OUT=<dir> reaper <proj.rpp> daw.lua

local r = reaper
local MODE   = os.getenv("DAW_SELFTEST")
local OUTDIR = os.getenv("DAW_OUT") or (os.getenv("HOME") .. "/daw-in-reaper/out")

----------------------------------------------------------------- model
local S = {
  tracks = { {name = "DAW Lead", color = {90, 170, 255}}, {name = "DAW Bass", color = {255, 150, 70}} },
  beats = 8, pitch_lo = 48, pitch_hi = 72, step = 0.25, len = 1.0, cur = 1,
}
local L = { hdr = 32, keyw = 48, beat_w = 100, row_h = 14, foot = 22 }
L.grid_w = S.beats * L.beat_w
L.grid_h = (S.pitch_hi - S.pitch_lo + 1) * L.row_h
L.win_w  = L.keyw + L.grid_w + 4
L.win_h  = L.hdr + L.grid_h + L.foot

local function find_track(name)
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local _, n = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if n == name then return tr end
  end
end

local function ensure_track(i)
  local t = S.tracks[i]
  local tr = find_track(t.name)
  if not tr then
    r.InsertTrackAtIndex(r.CountTracks(0), true)
    tr = r.GetTrack(0, r.CountTracks(0) - 1)
    r.GetSetMediaTrackInfo_String(tr, "P_NAME", t.name, true)
    r.SetTrackColor(tr, r.ColorToNative(t.color[1], t.color[2], t.color[3]) | 0x1000000)
  end
  if r.TrackFX_GetByName(tr, "ReaSynth", false) < 0 then
    r.TrackFX_AddByName(tr, "ReaSynth", false, -1)
  end
  -- MIDI clip
  local item
  for k = 0, r.CountTrackMediaItems(tr) - 1 do
    local it = r.GetTrackMediaItem(tr, k)
    local tk = r.GetActiveTake(it)
    if tk and r.TakeIsMIDI(tk) then item = it break end
  end
  if not item then
    item = r.CreateNewMIDIItemInProj(tr, 0, r.TimeMap2_QNToTime(0, S.beats), false)
  end
  t.track, t.item, t.take = tr, item, r.GetActiveTake(item)
  return t
end

local function setup_project()
  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()
  for i = 1, #S.tracks do ensure_track(i) end
  r.Undo_EndBlock("DAW: setup tracks", -1)
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
end

local function list_notes(take)
  local out = {}
  local _, n = r.MIDI_CountEvts(take)
  for i = 0, n - 1 do
    local ok, _, _, s, e, _, p, v = r.MIDI_GetNote(take, i)
    if ok then
      out[#out + 1] = { idx = i, pitch = p, vel = v,
        s = r.MIDI_GetProjQNFromPPQPos(take, s), e = r.MIDI_GetProjQNFromPPQPos(take, e) }
    end
  end
  return out
end

local function add_note(ti, pitch, qn)
  local t = S.tracks[ti]
  local e = math.min(qn + S.len, S.beats)
  if e <= qn then return false end
  r.Undo_BeginBlock()
  r.MIDI_InsertNote(t.take, false, false,
    r.MIDI_GetPPQPosFromProjQN(t.take, qn), r.MIDI_GetPPQPosFromProjQN(t.take, e), 0, pitch, 100, false)
  r.MIDI_Sort(t.take)
  r.Undo_EndBlock("DAW: add note", -1)
  r.UpdateArrange()
  return true
end

local function delete_note_at(ti, pitch, qn)
  local t = S.tracks[ti]
  for _, n in ipairs(list_notes(t.take)) do
    if n.pitch == pitch and qn >= n.s - 1e-6 and qn < n.e - 1e-6 then
      r.Undo_BeginBlock()
      r.MIDI_DeleteNote(t.take, n.idx)
      r.MIDI_Sort(t.take)
      r.Undo_EndBlock("DAW: delete note", -1)
      r.UpdateArrange()
      return true
    end
  end
  return false
end

----------------------------------------------------------------- layout / hit test (pure math)
local function tab_rect(i) return 8 + (i - 1) * 110, 5, 100, 22 end
local function xy_to_cell(x, y)
  if x < L.keyw or x >= L.keyw + L.grid_w or y < L.hdr or y >= L.hdr + L.grid_h then return end
  local qn = math.floor(((x - L.keyw) / L.beat_w) / S.step) * S.step
  local pitch = S.pitch_hi - math.floor((y - L.hdr) / L.row_h)
  return pitch, qn
end
local function cell_to_xy(pitch, qn)
  return L.keyw + qn * L.beat_w + 2, L.hdr + (S.pitch_hi - pitch) * L.row_h + 2
end

local function on_click(x, y, btn) -- btn: 1 left, 2 right
  for i = 1, #S.tracks do
    local tx, ty, tw, th = tab_rect(i)
    if btn == 1 and x >= tx and x < tx + tw and y >= ty and y < ty + th then S.cur = i return "tab" end
  end
  local pitch, qn = xy_to_cell(x, y)
  if not pitch then return end
  if btn == 1 then
    -- clicking on an existing note does nothing (use right-click to delete)
    for _, n in ipairs(list_notes(S.tracks[S.cur].take)) do
      if n.pitch == pitch and qn >= n.s - 1e-6 and qn < n.e - 1e-6 then return "hit" end
    end
    return add_note(S.cur, pitch, qn) and "add"
  elseif btn == 2 then
    return delete_note_at(S.cur, pitch, qn) and "del"
  end
end

local function toggle_play()
  if r.GetPlayState() & 1 ~= 0 then r.OnStopButton()
  else r.SetEditCurPos(0, true, false) r.OnPlayButton() end
end

----------------------------------------------------------------- drawing
local NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local function col(rr, gg, bb, a) gfx.set(rr / 255, gg / 255, bb / 255, a or 1) end

local function draw()
  col(30, 30, 34) gfx.rect(0, 0, gfx.w, gfx.h, 1)
  gfx.setfont(1, "Arial", 14)
  -- header: tabs
  for i, t in ipairs(S.tracks) do
    local x, y, w, h = tab_rect(i)
    if i == S.cur then col(t.color[1], t.color[2], t.color[3]) else col(60, 60, 68) end
    gfx.rect(x, y, w, h, 1)
    if i == S.cur then col(10, 10, 10) else col(210, 210, 210) end
    gfx.x, gfx.y = x + 8, y + 4 gfx.drawstr(i .. ": " .. t.name:gsub("^DAW ", ""))
  end
  col(180, 180, 180)
  gfx.x, gfx.y = 8 + #S.tracks * 110 + 10, 9
  gfx.drawstr(string.format("len %.2g beat   [ ] resize   SPACE play   S save   LMB add / RMB del", S.len))
  -- grid rows + keys
  for p = S.pitch_hi, S.pitch_lo, -1 do
    local y = L.hdr + (S.pitch_hi - p) * L.row_h
    local black = ({ [1] = 1, [3] = 1, [6] = 1, [8] = 1, [10] = 1 })[p % 12]
    if black then col(38, 38, 44) else col(46, 46, 52) end
    gfx.rect(L.keyw, y, L.grid_w, L.row_h, 1)
    if black then col(20, 20, 20) else col(225, 225, 225) end
    gfx.rect(0, y, L.keyw - 2, L.row_h - 1, 1)
    if p % 12 == 0 then col(0, 0, 0) gfx.x, gfx.y = 4, y + 1 gfx.drawstr("C" .. (p // 12 - 1)) end
  end
  -- beat lines
  for b = 0, S.beats do
    if b % 4 == 0 then col(120, 120, 130) else col(70, 70, 78) end
    local x = L.keyw + b * L.beat_w
    gfx.line(x, L.hdr, x, L.hdr + L.grid_h)
  end
  -- notes
  local t = S.tracks[S.cur]
  if t.take then
    col(t.color[1], t.color[2], t.color[3])
    for _, n in ipairs(list_notes(t.take)) do
      if n.pitch >= S.pitch_lo and n.pitch <= S.pitch_hi then
        local x, y = cell_to_xy(n.pitch, n.s)
        gfx.rect(x - 2, y - 2, (n.e - n.s) * L.beat_w - 1, L.row_h - 1, 1)
      end
    end
  end
  -- playhead
  local pos = (r.GetPlayState() & 1 ~= 0) and r.GetPlayPosition() or r.GetCursorPosition()
  local qn = r.TimeMap2_timeToQN(0, pos)
  if qn <= S.beats then col(255, 80, 80) local x = L.keyw + qn * L.beat_w gfx.line(x, L.hdr, x, L.hdr + L.grid_h) end
  -- footer
  col(150, 150, 150) gfx.x, gfx.y = 8, L.hdr + L.grid_h + 4
  gfx.drawstr(string.format("%s   notes: %d   %s", r.GetPlayState() & 1 ~= 0 and "PLAYING" or "stopped",
    t.take and #list_notes(t.take) or 0, ({r.GetProjectName(0, "")})[1] ~= "" and "" or "(unsaved project)"))
end

----------------------------------------------------------------- interactive loop
local last_cap = 0
local function loop()
  local c = gfx.getchar()
  if c == -1 or c == 27 then
    r.SetExtState("daw_in_reaper", "dock", tostring(gfx.dock(-1)), true)
    gfx.quit() return
  end
  if c == 32 then toggle_play()
  elseif c == string.byte("1") then S.cur = 1
  elseif c == string.byte("2") then S.cur = 2
  elseif c == string.byte("[") then S.len = math.max(S.step, S.len / 2)
  elseif c == string.byte("]") then S.len = math.min(S.beats, S.len * 2)
  elseif c == string.byte("s") or c == string.byte("S") then r.Main_OnCommand(40026, 0) end
  local cap = gfx.mouse_cap
  if cap & 1 ~= 0 and last_cap & 1 == 0 then on_click(gfx.mouse_x, gfx.mouse_y, 1) end
  if cap & 2 ~= 0 and last_cap & 2 == 0 then on_click(gfx.mouse_x, gfx.mouse_y, 2) end
  last_cap = cap
  draw()
  gfx.update()
  r.defer(loop)
end

local function open_ui()
  local dock = tonumber(r.GetExtState("daw_in_reaper", "dock")) or 0
  return gfx.init("DAW", L.win_w, L.win_h, dock)
end

----------------------------------------------------------------- self-test
local LOG, FAILS = {}, 0
local function check(name, ok, detail)
  if not ok then FAILS = FAILS + 1 end
  LOG[#LOG + 1] = string.format("%s  %-34s %s", ok and "PASS" or "FAIL", name, detail or "")
end
local function note(msg) LOG[#LOG + 1] = "info  " .. msg end
local function flush(name)
  local f = io.open(OUTDIR .. "/" .. name, "w")
  if f then f:write(table.concat(LOG, "\n"), "\n") f:close() end
end

local function wav_analyze(path)
  local f = io.open(path, "rb")
  if not f then return nil, "no file at " .. path end
  local d = f:read("a") f:close()
  local pos, fmt, ch, bits, sr = 13
  while pos + 8 <= #d + 1 do
    local id = d:sub(pos, pos + 3)
    local sz = string.unpack("<I4", d, pos + 4)
    if id == "fmt " then
      fmt, ch, sr = string.unpack("<I2I2I4", d, pos + 8)
      bits = string.unpack("<I2", d, pos + 8 + 14)
    elseif id == "data" then
      local b = bits // 8
      local n = math.min(sz, #d - (pos + 7)) // (b * ch)
      local peak, buckets = 0, {}
      local per = sr // 2 -- 0.5s = 1 beat @120bpm
      for i = 0, n - 1 do
        local o = pos + 8 + i * b * ch
        local v
        if fmt == 3 then v = string.unpack("<f", d, o)
        elseif bits == 16 then v = string.unpack("<i2", d, o) / 32768
        elseif bits == 24 then
          local b1, b2, b3 = d:byte(o, o + 2)
          v = b1 + b2 * 256 + b3 * 65536
          if v >= 8388608 then v = v - 16777216 end
          v = v / 8388608
        else v = string.unpack("<i4", d, o) / 2147483648 end
        v = math.abs(v)
        if v > peak then peak = v end
        local bk = i // per + 1
        if v > (buckets[bk] or 0) then buckets[bk] = v end
      end
      return { peak = peak, secs = n / sr, buckets = buckets, sr = sr, bits = bits, fmt = fmt }
    end
    pos = pos + 8 + sz + (sz % 2)
  end
  return nil, "no data chunk"
end

local function render_and_check(tag)
  local out = OUTDIR .. "/out.wav"
  os.remove(out)
  r.Main_OnCommand(42230, 0) -- render using most recent settings, auto-close
  local a, err = wav_analyze(out)
  if not a then check("render " .. tag, false, err) return end
  local bs = {}
  for i = 1, math.ceil(a.secs * 2) do bs[#bs + 1] = string.format("%.2f", a.buckets[i] or 0) end
  check("render " .. tag .. " audible", a.peak > 0.01, string.format("peak=%.3f len=%.2fs %dbit sr=%d", a.peak, a.secs, a.bits, a.sr))
  note("per-beat peaks: " .. table.concat(bs, " "))
end

local LEAD = { {60, 0}, {64, 1}, {67, 2}, {72, 3}, {71, 4}, {67, 5}, {64, 6}, {60, 7} } -- {pitch, beat}
local BASS = { {48, 0}, {48, 2}, {55, 4}, {43 + 12, 6} }

local function dump_notes()
  local lines = {}
  for i, t in ipairs(S.tracks) do
    for _, n in ipairs(list_notes(t.take)) do
      lines[#lines + 1] = string.format("%d %d %.4f %.4f %d", i, n.pitch, n.s, n.e, n.vel)
    end
  end
  return lines
end

local function quit_reaper()
  flush(MODE == "build" and "result_build.txt" or "result_verify.txt")
  local f = io.open(OUTDIR .. "/DONE_" .. MODE, "w") f:write(FAILS == 0 and "ok" or "fail") f:close()
  r.Main_OnCommand(40004, 0) -- File: Quit
end

local function selftest_build(projpath)
  check("project starts empty", r.CountTracks(0) == 0, "tracks=" .. r.CountTracks(0))
  -- (1) dockable UI
  local rv = open_ui()
  check("1 gfx window opens", rv ~= 0 and gfx.w > 0, "init=" .. tostring(rv) .. " size=" .. gfx.w .. "x" .. gfx.h)
  gfx.quit()
  local rv2 = gfx.init("DAW", L.win_w, L.win_h, 0x101)
  note("dock request 0x101 -> gfx.dock(-1)=" .. tostring(gfx.dock(-1)))
  gfx.quit()
  -- (2) tracks + clip
  setup_project()
  check("2 two real tracks", r.CountTracks(0) == 2, "tracks=" .. r.CountTracks(0))
  for i, t in ipairs(S.tracks) do
    check("2 MIDI clip on " .. t.name, t.take ~= nil and r.TakeIsMIDI(t.take), string.format("len=%.2fs", r.GetMediaItemInfo_Value(t.item, "D_LENGTH")))
    check("5 ReaSynth on " .. t.name, r.TrackFX_GetByName(t.track, "ReaSynth", false) >= 0)
  end
  -- (3) notes through the inner interface (synthetic clicks via hit-test path)
  S.len = 1.0
  local added = 0
  local function click_cell(ti, pitch, beat, btn)
    S.cur = ti
    -- click tab first (also tests tab hit-test)
    local tx, ty = tab_rect(ti)
    on_click(tx + 5, ty + 5, 1)
    local x, y = cell_to_xy(pitch, beat)
    return on_click(x + 1, y + 1, btn or 1)
  end
  for _, n in ipairs(LEAD) do if click_cell(1, n[1], n[2]) == "add" then added = added + 1 end end
  for _, n in ipairs(BASS) do if click_cell(2, n[1], n[2]) == "add" then added = added + 1 end end
  check("3 notes added by click", added == #LEAD + #BASS, added .. "/" .. (#LEAD + #BASS))
  -- right-click delete test: add stray then delete it
  click_cell(1, 70, 0.5)
  local n_before = #list_notes(S.tracks[1].take)
  local act = click_cell(1, 70, 0.5, 2)
  local n_after = #list_notes(S.tracks[1].take)
  check("3 right-click deletes", act == "del" and n_after == n_before - 1, n_before .. "->" .. n_after)
  -- draw one frame headless-ish
  open_ui() draw() gfx.update() gfx.quit()
  local expected = dump_notes()
  check("3 note counts", #expected == #LEAD + #BASS, "total=" .. #expected)
  local f = io.open(OUTDIR .. "/expected_notes.txt", "w") f:write(table.concat(expected, "\n"), "\n") f:close()
  -- render settings (persist in .rpp) then save
  r.GetSetProjectInfo(0, "RENDER_SETTINGS", 0, true)
  r.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true)
  r.GetSetProjectInfo(0, "RENDER_SRATE", 44100, true)
  r.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
  r.GetSetProjectInfo_String(0, "RENDER_FILE", OUTDIR, true)
  r.GetSetProjectInfo_String(0, "RENDER_PATTERN", "out", true)
  r.GetSetProjectInfo_String(0, "RENDER_FORMAT", "ZXZhdxAAAAA=", true) -- WAV 16-bit
  -- (4) live transport playback
  local t_boot, started = r.time_precise(), false
  local t0, maxpk, maxpos = 0, 0, 0
  local function watch()
    if not started then
      if r.time_precise() - t_boot < 2.5 then r.defer(watch) return end
      started = true t0 = r.time_precise()
      r.SetEditCurPos(0, true, false)
      r.OnPlayButton()
    end
    local pk = math.max(r.Track_GetPeakInfo(r.GetMasterTrack(0), 0), r.Track_GetPeakInfo(r.GetMasterTrack(0), 1))
    if pk > maxpk then maxpk = pk end
    maxpos = math.max(maxpos, r.GetPlayPosition())
    if r.time_precise() - t0 < 3.0 then r.defer(watch) return end
    local state = r.GetPlayState()
    r.OnStopButton()
    check("4 transport plays", maxpos > 1.0, string.format("playpos reached %.2fs, state=%d", maxpos, state))
    check("4 live meter shows audio", maxpk > 0.001, string.format("master peak=%.3f (needs audio device)", maxpk))
    render_and_check("(offline)")
    -- (5) save
    r.SetEditCurPos(0, true, false)
    local saved
    if r.APIExists("Main_SaveProjectEx") then r.Main_SaveProjectEx(0, projpath, 0) saved = true
    else r.Main_SaveProject(0, false) end
    local sz = io.open(projpath, "rb")
    check("5 project saved", sz ~= nil, projpath)
    if sz then sz:close() end
    quit_reaper()
  end
  r.defer(watch)
end

local function selftest_verify(projpath)
  -- wait for project to finish loading
  local t0 = r.time_precise()
  local function go()
    if r.CountTracks(0) == 0 and r.time_precise() - t0 < 12 then r.defer(go) return end
    check("6 reopened: 2 tracks", r.CountTracks(0) == 2, "tracks=" .. r.CountTracks(0))
    local _, pn = r.GetProjectName(0, "")
    note("project=" .. tostring(({r.EnumProjects(-1)})[2]))
    for i = 1, #S.tracks do
      local ok = find_track(S.tracks[i].name) ~= nil
      check("6 track present " .. S.tracks[i].name, ok)
      if ok then
        local t = ensure_track(i) -- reuses existing, must not duplicate
        check("6 ReaSynth kept " .. t.name, r.TrackFX_GetByName(t.track, "ReaSynth", false) >= 0)
        check("6 single clip " .. t.name, r.CountTrackMediaItems(t.track) == 1)
      end
    end
    check("6 no duplicate tracks after setup", r.CountTracks(0) == 2)
    local got = dump_notes()
    local want = {}
    for line in io.lines(OUTDIR .. "/expected_notes.txt") do want[#want + 1] = line end
    table.sort(got) table.sort(want)
    local same = #got == #want
    for i = 1, #want do if got[i] ~= want[i] then same = false break end end
    check("6 notes identical after reopen", same, string.format("%d vs %d notes", #got, #want))
    if not same then note("got:\n" .. table.concat(got, "\n") .. "\nwant:\n" .. table.concat(want, "\n")) end
    render_and_check("(after reopen)")
    quit_reaper()
  end
  r.defer(function() r.defer(go) end)
end

----------------------------------------------------------------- entry
if MODE == "build" then
  selftest_build(OUTDIR .. "/test_project.rpp")
elseif MODE == "verify" then
  selftest_verify()
else
  setup_project()
  if open_ui() ~= 0 then loop() end
end
