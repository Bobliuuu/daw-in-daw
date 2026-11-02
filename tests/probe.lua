local r = reaper
local OUT = os.getenv("DAW_OUT")
local L = {}
local function p(...) local t = {} for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end L[#L+1]=table.concat(t," ") end
local function dump_params(tr, fx)
  local _, nm = r.TrackFX_GetFXName(tr, fx, "")
  p("FX", fx, nm, "nparams", r.TrackFX_GetNumParams(tr, fx))
  for i = 0, r.TrackFX_GetNumParams(tr, fx) - 1 do
    local _, n = r.TrackFX_GetParamName(tr, fx, i, "")
    local v, mn, mx = r.TrackFX_GetParam(tr, fx, i)
    local _, f = r.TrackFX_GetFormattedParamValue(tr, fx, i, "")
    p(string.format("  [%d] %s = %.3f (%s) range %.2f..%.2f", i, n, v, f, mn, mx))
  end
end
local function go()
  r.InsertTrackAtIndex(0, true) local tr = r.GetTrack(0, 0)
  for _, n in ipairs{"ReaSynth","ReaVerbate","ReaDelay","ReaEQ","ReaComp","ReSamplOmatic5000","ReaSamplOmatic5000"} do
    local i = r.TrackFX_AddByName(tr, n, false, -1)
    p("add", n, i)
  end
  for i = 0, r.TrackFX_GetCount(tr) - 1 do dump_params(tr, i) end
  -- timebase / tempo
  p("bpm", r.Master_GetTempo(), "APIs:", tostring(r.APIExists("SetCurrentBPM")), tostring(r.APIExists("Main_SaveProjectEx")), tostring(r.APIExists("MIDI_SetItemExtents")), tostring(r.APIExists("GetProjectStateChangeCount")))
  local it = r.CreateNewMIDIItemInProj(tr, 2, 4, false)
  p("item timebase", r.GetMediaItemInfo_Value(it, "C_BEATATTACHMODE"), "loopsrc", r.GetMediaItemInfo_Value(it, "B_LOOPSRC"))
  local sc = r.GetProjectStateChangeCount(0)
  local tk = r.GetActiveTake(it)
  r.MIDI_InsertNote(tk, false, false, 0, 480, 0, 60, 100, false)
  p("statechange after note", sc, r.GetProjectStateChangeCount(0))
  r.SetMediaItemInfo_Value(it, "C_BEATATTACHMODE", 1)
  r.SetCurrentBPM(0, 90, false)
  p("after bpm90: item pos", r.GetMediaItemInfo_Value(it, "D_POSITION"), "len", r.GetMediaItemInfo_Value(it, "D_LENGTH"), "bpm", r.Master_GetTempo())
  p("ppq of qn 0 in take", r.MIDI_GetPPQPosFromProjQN(tk, 0), "qn of item start", r.TimeMap2_timeToQN(0, r.GetMediaItemInfo_Value(it,"D_POSITION")))
  local ok = r.GetUserFileNameForRead and "hasfiledlg" or "nofiledlg"
  p(ok, r.GetResourcePath(), r.GetProjectPath and r.GetProjectPath() or "")
  local f = io.open(OUT.."/probe.txt","w") f:write(table.concat(L,"\n"),"\n") f:close()
  local d = io.open(OUT.."/DONE_probe","w") d:write("ok") d:close()
  r.Main_OnCommand(40004,0)
end
r.defer(go)
