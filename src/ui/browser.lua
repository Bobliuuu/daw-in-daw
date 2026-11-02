-- browser.lua : inner-DAW dialogs: file browser (audio import / folder picker), export dialog, save-as dialog.
-- Directory listing uses REAPER's EnumerateFiles / EnumerateSubdirectories; no OS file dialog is needed.
local G = require("ui.gx")
local U = require("util")
local X = require("audio.export")
local H = require("host")
local r = reaper
local B = {}

local AUDIO_EXT = { wav = true, flac = true, mp3 = true, ogg = true, aif = true, aiff = true }
local HOME = os.getenv("HOME") or "/"

local function list_dir(dir, exts)
  local dirs, files = {}, {}
  local i = 0
  while true do local d = r.EnumerateSubdirectories(dir, i) if not d then break end if d:sub(1, 1) ~= "." then dirs[#dirs + 1] = d end i = i + 1 end
  i = 0
  while true do
    local f = r.EnumerateFiles(dir, i) if not f then break end
    if f:sub(1, 1) ~= "." and (not exts or exts[U.ext(f)]) then files[#files + 1] = f end
    i = i + 1
  end
  table.sort(dirs, function(a, b) return a:lower() < b:lower() end)
  table.sort(files, function(a, b) return a:lower() < b:lower() end)
  return dirs, files
end

local function parent(dir) local p = dir:match("^(.*)/[^/]+/?$") if p == nil or p == "" then return "/" end return p end

-- opens a modal listing `dir`. mode = "file" (pick audio) | "dir" (pick folder). on_pick(path)
function B.pick(A, o)
  local st = { dir = o.dir or HOME, sel = nil, scroll = 0, mode = o.mode or "file", cache = nil }
  local function reload() st.dirs, st.files = list_dir(st.dir, st.mode == "file" and AUDIO_EXT or {}) st.sel = nil st.scroll = 0 end
  reload()
  local T = G.theme
  local function go(d) st.dir = d reload() end
  local function choose(path) G.close_modal() A.S.browser.dir = st.mode == "file" and U.dirname(path) or path o.on_pick(path) end

  G.dialog(o.title or "Choose", 640, 470, function(x, y, w, h)
    local m = G.m
    -- quick links
    local links = { { "Home", HOME }, { "Desktop", HOME .. "/Desktop" }, { "Documents", HOME .. "/Documents" }, { "Music", HOME .. "/Music" },
      { "Examples", H.script_dir() .. "/examples" }, { "Project", (r.GetProjectPath and r.GetProjectPath() or "") } }
    local lx = x + 10
    for _, l in ipairs(links) do
      if l[2] ~= "" then
        local lw = G.text_w(l[1], 11) + 16
        if G.button("lnk" .. l[1], lx, y + 8, lw, 22, l[1], { size = 11 }) then go(l[2]) end
        lx = lx + lw + 4
      end
    end
    if G.button("up", x + 10, y + 38, 40, 24, "Up") then go(parent(st.dir)) end
    G.rect(x + 56, y + 38, w - 66, 24, T.bg) G.frame(x + 56, y + 38, w - 66, 24, T.line)
    G.text(st.dir, x + 62, y + 43, T.text, 12, "l", w - 80)
    -- list
    local ly, lh = y + 70, h - 70 - 54
    G.rect(x + 10, ly, w - 20, lh, T.bg) G.frame(x + 10, ly, w - 20, lh, T.line)
    local rowh = 22
    local n = #st.dirs + #st.files
    if G.over(x + 10, ly, w - 20, lh) and m.wheel ~= 0 then st.scroll = U.clamp(st.scroll - m.wheel / 120 * 66, 0, math.max(0, n * rowh - lh)) end
    G.push_clip(x + 11, ly + 1, w - 22, lh - 2)
    local picked_dir, picked_file
    for i = 1, n do
      local isdir = i <= #st.dirs
      local name = isdir and st.dirs[i] or st.files[i - #st.dirs]
      local ry = ly + (i - 1) * rowh - st.scroll
      if ry + rowh >= ly and ry <= ly + lh then
        G.reg["row:" .. name] = { x + 11, ry, w - 22, rowh }
        local hov = G.over(x + 11, ry, w - 22, rowh)
        local sel = st.sel == i
        if sel then G.rect(x + 11, ry, w - 22, rowh, T.accent, 0.35) elseif hov then G.rect(x + 11, ry, w - 22, rowh, T.panel3) end
        G.text((isdir and "[ " or "   ") .. name .. (isdir and " ]" or ""), x + 18, ry + 4, isdir and T.accent2 or T.text, 12, "l", w - 50)
        if hov and m.pressed then
          st.sel = i
          if m.dbl then if isdir then picked_dir = name else picked_file = name end end
        end
      end
    end
    G.pop_clip()
    if n == 0 then G.text(st.mode == "file" and "No audio files here (wav / flac / mp3 / ogg / aiff)." or "No subfolders.", x + 22, ly + 8, T.dim, 12) end
    if picked_dir then go(st.dir .. "/" .. picked_dir) end
    if picked_file then choose(st.dir .. "/" .. picked_file) return end
    -- footer
    local fy = y + h - 42
    local sel_name = st.sel and (st.sel <= #st.dirs and st.dirs[st.sel] or st.files[st.sel - #st.dirs])
    G.text(st.mode == "file" and (sel_name and not (st.sel <= #st.dirs) and sel_name or "Select an audio file (double-click to import)") or ("Folder: " .. st.dir), x + 12, fy + 6, T.dim, 12, "l", w - 280)
    if st.mode == "dir" then
      if G.button("usedir", x + w - 250, fy, 150, 28, "Use this folder", { bg = T.accent, color = { 20, 20, 24 } }) then choose(st.dir) return end
    else
      local ok_enabled = st.sel and st.sel > #st.dirs
      if G.button("pickf", x + w - 250, fy, 100, 28, "Import", { bg = T.accent, color = { 20, 20, 24 }, disabled = not ok_enabled }) then
        choose(st.dir .. "/" .. st.files[st.sel - #st.dirs]) return
      end
    end
    if G.button("native", x + w - 140, fy, 130, 28, "Native dialog...", { size = 11, tip = "REAPER's own file chooser" }) then
      if st.mode == "file" then
        local ok, path = r.GetUserFileNameForRead("", o.title or "Choose audio", "wav")
        if ok and path ~= "" then choose(path) return end
      end
    end
  end)
end

----------------------------------------------------------------------------- export dialog
function B.export(A)
  local S, C = A.S, A.C
  local E = S.export
  if not E.dir then E.dir = (HOME .. "/Music/DAW-in-DAW") end
  local T = G.theme
  local busy = false
  G.dialog("Export WAV", 560, 360, function(x, y, w, h)
    local snap = A.P.snap
    G.text("Folder", x + 20, y + 22, T.dim, 12)
    G.rect(x + 90, y + 16, w - 230, 26, T.bg) G.frame(x + 90, y + 16, w - 230, 26, T.line)
    G.text(E.dir, x + 96, y + 22, T.text, 12, "l", w - 242)
    if G.button("ex_browse", x + w - 130, y + 16, 110, 26, "Browse...") then
      B.pick(A, { mode = "dir", dir = E.dir, title = "Choose export folder", on_pick = function(p) E.dir = p B.export(A) end })
      return
    end
    G.text("File name", x + 20, y + 62, T.dim, 12)
    if G.button("ex_name", x + 90, y + 56, w - 230, 26, E.name .. ".wav", { bg = T.bg, border = true, tip = "Click to rename" }) then
      G.prompt("Export file name", E.name, function(s) s = U.strip_ext(s) if s ~= "" then E.name = s end B.export(A) end)
      return
    end
    G.text("Region", x + 20, y + 102, T.dim, 12)
    local ls, le = A.TR.loop()
    local has_loop = le > ls
    if G.button("ex_proj", x + 90, y + 96, 150, 26, "Whole project", { on = E.region == "project" }) then E.region = "project" end
    if G.button("ex_loop", x + 246, y + 96, 150, 26, "Loop region", { on = E.region == "loop", disabled = not has_loop, tip = has_loop and "" or "Set a loop region first" }) then E.region = "loop" end
    local len_beats = snap.end_beat
    G.text(string.format("Project length: %.1f beats (%s at %.1f BPM). A %.1fs tail captures reverb/delay.", len_beats, U.fmt_time(H.qn_to_time(len_beats)), snap.bpm, 1.5), x + 20, y + 140, T.dim, 11, "l", w - 40)
    local preview = X.free_path(E.dir, E.name)
    G.text("Will write: " .. preview, x + 20, y + 160, T.text, 11, "l", w - 40)
    G.text("WAV, 16-bit PCM, 44.1 kHz, stereo. Existing files are never overwritten.", x + 20, y + 178, T.faint, 11, "l", w - 40)
    -- result panel
    local last = E.last
    if last then
      G.rect(x + 20, y + 204, w - 40, 76, T.bg) G.frame(x + 20, y + 204, w - 40, 76, last.ok and T.green or T.red)
      if last.ok then
        local a = last.analysis
        G.text("Exported OK", x + 30, y + 212, T.green, 13)
        G.text(last.path, x + 30, y + 232, T.text, 11, "l", w - 60)
        G.text(string.format("%.2f s   peak %.1f dBFS   rms %.1f dBFS   %d-bit %d Hz %s", a.secs, U.lin_to_db(a.peak), U.lin_to_db(a.rms), a.bits, a.sr, a.channels == 2 and "stereo" or "mono"), x + 30, y + 252, T.dim, 11, "l", w - 60)
      else
        G.text("Export failed", x + 30, y + 212, T.red, 13)
        G.text(tostring(last.err), x + 30, y + 232, T.text, 11, "l", w - 60)
      end
    end
    if G.button("ex_go", x + w - 190, y + h - 44, 170, 32, busy and "Rendering..." or "Export WAV", { bg = T.accent, color = { 20, 20, 24 }, size = 13, disabled = busy or snap.end_beat <= 0, tip = snap.end_beat <= 0 and "Nothing to export yet" or nil }) then
      local region = E.region == "loop" and "loop" or "project"
      E.last = A.export_now({ dir = E.dir, name = E.name, region = region })
    end
    if G.button("ex_close", x + 20, y + h - 44, 90, 32, "Close") then return "close" end
  end)
end

----------------------------------------------------------------------------- save as
function B.save_as(A, on_done)
  local S = A.S
  S.saveas = S.saveas or { dir = S.browser.dir or (HOME .. "/Documents/DAW-in-DAW"), name = A.P.snap.name or "song" }
  local st = S.saveas   -- persists while nested prompts / folder pickers re-open this dialog
  local T = G.theme
  G.dialog("Save project", 560, 220, function(x, y, w, h)
    G.text("Folder", x + 20, y + 22, T.dim, 12)
    G.rect(x + 90, y + 16, w - 230, 26, T.bg) G.frame(x + 90, y + 16, w - 230, 26, T.line)
    G.text(st.dir, x + 96, y + 22, T.text, 12, "l", w - 242)
    if G.button("sv_browse", x + w - 130, y + 16, 110, 26, "Browse...") then
      B.pick(A, { mode = "dir", dir = st.dir, title = "Choose project folder", on_pick = function(p) S.browser.dir = p B.save_as(A, on_done) end })
      return
    end
    G.text("Name", x + 20, y + 62, T.dim, 12)
    if G.button("sv_name", x + 90, y + 56, w - 230, 26, st.name .. ".rpp", { bg = T.bg, border = true }) then
      G.prompt("Project file name", st.name, function(s) s = U.strip_ext(s) if s ~= "" then st.name = s end B.save_as(A, on_done) end)
      return
    end
    local path = st.dir .. "/" .. st.name .. ".rpp"
    local exists = io.open(path, "rb")
    if exists then exists:close() end
    G.text(exists and "A file with this name exists and will be replaced." or "New file: " .. path, x + 20, y + 100, exists and T.yellow or T.dim, 11, "l", w - 40)
    if G.button("sv_go", x + w - 150, y + h - 44, 130, 32, "Save", { bg = T.accent, color = { 20, 20, 24 } }) then
      os.execute(string.format('mkdir -p "%s"', st.dir))
      r.Main_SaveProjectEx(0, path, 0)
      A.msg("Saved " .. path)
      if on_done then on_done(path) end
      return "close"
    end
    if G.button("sv_cancel", x + 20, y + h - 44, 90, 32, "Cancel") then return "close" end
  end)
end

return B
