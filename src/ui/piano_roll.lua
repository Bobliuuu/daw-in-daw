-- piano_roll.lua : note editor for the MIDI clip open in the bottom panel. Edits real MIDI events through commands.
-- Native note selection flag is used for selection (so selection survives re-sorts and is REAPER-native).
local G = require("ui.gx")
local TL = require("timeline")
local U = require("util")

local PR = {}
local D = nil          -- active drag
local MIN_LEN = 0.0625

local function ctx_snap(A) local s = A.S.snap() return s end

local function selected_list(notes)
  local out = {}
  for _, n in ipairs(notes) do if n.sel then out[#out + 1] = n end end
  return out
end

function PR.open(A, clip)
  local S = A.S
  S.edit_clip, S.sel_clip, S.sel_track = clip.id, clip.id, clip.track_id
  S.tab = "roll"
  local R = A.R
  local gw = R and R.roll_grid[3] or 800
  local v = S.roll.view
  v.ppb = U.clamp((gw - 40) / math.max(1, clip.len + 1), 14, 220)
  v.x0 = math.max(0, clip.start - 0.5)
  local notes = A.P.notes(clip)
  local lo, hi = 127, 0
  for _, n in ipairs(notes) do lo = math.min(lo, n.pitch) hi = math.max(hi, n.pitch) end
  if hi < lo then lo, hi = 55, 72 end
  local gh = R and R.roll_grid[4] or 200
  local rows = gh / S.roll.pv.row_h
  S.roll.pv.top = U.clamp(math.floor((lo + hi) / 2 + rows / 2), math.floor(rows) - 1, 127)
end

local function pitch_at(S, R, y) return TL.y_to_pitch(S.roll.pv, y, R.roll_grid[2]) end
local function beat_at(S, R, x) return TL.x_to_beat(S.roll.view, x, R.roll_grid[1]) end

local function apply_move(A, clip, notes_orig, anchor, dB, dp)
  local C = A.C
  for _, o in ipairs(notes_orig) do
    C.set_note(clip.id, o.idx, { s = o.s + dB, e = o.e + dB, pitch = o.pitch + dp }, true)
  end
end

----------------------------------------------------------------------------- draw
function PR.draw(A, R)
  local S, P, T = A.S, A.P, G.theme
  local clip = S.edit_clip and P.clip(S.edit_clip)
  local gr, kr, vr = R.roll_grid, R.roll_keys, R.roll_vel
  G.rect(R.content[1], R.content[2], R.content[3], R.content[4], T.bg)
  if not clip or clip.kind ~= "midi" then
    G.text("Piano roll: double-click a MIDI clip in the arrangement (or right-click > Open in editor).", gr[1] + 20, gr[2] + 20, T.dim, 13)
    return
  end
  local snapv = P.snap
  local view, pv = S.roll.view, S.roll.pv
  local track = clip.track
  local col = track.color
  local notes = P.notes(clip)
  local m = G.m

  -- vertical clamp
  local rows = gr[4] / pv.row_h
  pv.top = U.clamp(pv.top, math.min(127, math.floor(rows) - 1), 127)

  -- ---- grid background
  G.push_clip(gr[1], gr[2], gr[3], gr[4])
  G.rect(gr[1], gr[2], gr[3], gr[4], T.bg)
  local top_pitch = math.floor(pv.top)
  local bottom_pitch = math.max(0, math.floor(pv.top - gr[4] / pv.row_h))
  for p = top_pitch, bottom_pitch, -1 do
    local y = TL.pitch_to_y(pv, p, gr[2])
    G.rect(gr[1], y, gr[3], pv.row_h, U.is_black(p) and T.black_key or T.white_key, 1)
    if p % 12 == 0 then G.hline(gr[1], y + pv.row_h - 1, gr[3], T.line2) end
  end
  -- out-of-clip shading
  local cx0, cx1 = TL.beat_to_x(view, clip.start, gr[1]), TL.beat_to_x(view, clip.start + clip.len, gr[1])
  G.rect(gr[1], gr[2], math.max(0, cx0 - gr[1]), gr[4], { 0, 0, 0 }, 0.45)
  G.rect(cx1, gr[2], math.max(0, gr[1] + gr[3] - cx1), gr[4], { 0, 0, 0 }, 0.45)
  -- grid lines
  local sn = S.snap()
  for _, l in ipairs(TL.grid_lines(view, gr[3], snapv.num, snapv.den, sn > 0 and sn or nil)) do
    local x = gr[1] + l.x
    G.vline(x, gr[2], gr[4], l.kind == "bar" and T.line2 or T.line, l.kind == "sub" and 0.3 or (l.kind == "bar" and 1 or 0.7))
  end
  G.vline(cx0, gr[2], gr[4], T.accent, 0.7) G.vline(cx1, gr[2], gr[4], T.accent, 0.7)

  -- ---- notes
  for i, n in ipairs(notes) do
    if n.pitch <= top_pitch + 1 and n.pitch >= bottom_pitch - 1 then
      local x0 = TL.beat_to_x(view, n.s, gr[1])
      local x1 = TL.beat_to_x(view, n.e, gr[1])
      if x1 >= gr[1] and x0 <= gr[1] + gr[3] then
        local y = TL.pitch_to_y(pv, n.pitch, gr[2])
        local br = 0.55 + 0.45 * (n.vel / 127)
        local c = { col[1] * br, col[2] * br, col[3] * br }
        local inside = n.s >= clip.start - 1e-6 and n.e <= clip.start + clip.len + 1e-6
        local w = math.max(2, x1 - x0 - 1)
        G.rect(x0, y + 1, w, pv.row_h - 2, c, inside and 1 or 0.35)
        if n.sel then G.frame(x0, y + 1, w, pv.row_h - 2, { 255, 255, 255 }) else G.frame(x0, y + 1, w, pv.row_h - 2, { 0, 0, 0 }, 0.5) end
        if w > 28 and pv.row_h >= 12 then G.text(U.note_name(n.pitch), x0 + 3, y + 1, { 10, 10, 12 }, 10, "l", w - 4) end
      end
    end
  end

  -- ---- ghost for draw drag / marquee
  if D and D.kind == "draw" and D.began then
    local e = math.max(D.s + (sn > 0 and sn or MIN_LEN), U.snap(beat_at(S, R, m.x), sn))
    local gx0, gx1 = TL.beat_to_x(view, D.s, gr[1]), TL.beat_to_x(view, e, gr[1])
    G.rect(gx0, TL.pitch_to_y(pv, D.pitch, gr[2]) + 1, gx1 - gx0, pv.row_h - 2, col, 0.6)
  elseif D and D.kind == "marquee" then
    local x0, y0 = math.min(D.mx, m.x), math.min(D.my, m.y)
    G.rect(x0, y0, math.abs(m.x - D.mx), math.abs(m.y - D.my), T.accent, 0.2)
    G.frame(x0, y0, math.abs(m.x - D.mx), math.abs(m.y - D.my), T.accent)
  end

  -- ---- playhead
  local px = TL.beat_to_x(view, A.TR.position(), gr[1])
  G.vline(px, gr[2], gr[4], T.red)
  G.pop_clip()

  -- ---- keys
  G.push_clip(kr[1], kr[2], kr[3], kr[4])
  for p = top_pitch, bottom_pitch, -1 do
    local y = TL.pitch_to_y(pv, p, kr[2])
    local blk = U.is_black(p)
    local hov = G.over(kr[1], y, kr[3], pv.row_h)
    G.rect(kr[1], y, blk and kr[3] * 0.62 or kr[3] - 1, pv.row_h - 1, blk and { 20, 20, 24 } or (hov and T.accent or { 214, 216, 222 }))
    if p % 12 == 0 then G.text(U.note_name(p), kr[1] + 4, y + 1, { 30, 30, 36 }, 10) end
    if hov and m.pressed then A.audition(track.id, p, 100) end
  end
  G.pop_clip()

  -- ---- velocity lane
  G.push_clip(vr[1], vr[2], vr[3], vr[4])
  G.rect(vr[1], vr[2], vr[3], vr[4], T.panel)
  G.text("VEL", kr[1] + 4, vr[2] + 4, T.faint, 10)
  for _, l in ipairs(TL.grid_lines(view, vr[3], snapv.num, snapv.den)) do G.vline(vr[1] + l.x, vr[2], vr[4], T.line, 0.6) end
  for _, n in ipairs(notes) do
    local x = TL.beat_to_x(view, n.s, vr[1])
    if x >= vr[1] - 4 and x <= vr[1] + vr[3] then
      local h = (vr[4] - 6) * n.vel / 127
      G.rect(x, vr[2] + vr[4] - 3 - h, 4, h, n.sel and { 255, 255, 255 } or col)
      G.rect(x - 1, vr[2] + vr[4] - 4 - h, 6, 3, n.sel and { 255, 255, 255 } or col)
    end
  end
  G.pop_clip()
  G.rect(kr[1], vr[2], kr[3], vr[4], T.panel)

  -- ---- scrollbars
  local total = math.max(snapv.end_beat + 8, clip.start + clip.len + 8)
  local nx = G.scrollbar("roll_hsb", R.roll_hsb[1], R.roll_hsb[2], R.roll_hsb[3], R.roll_hsb[4], false, view.x0, gr[3] / view.ppb, total)
  if G.active == "roll_hsb" then view.x0 = nx end
  local vs = R.roll_vsb
  local maxtop = 127
  local ny = G.scrollbar("roll_vsb", vs[1], vs[2], vs[3], vs[4], true, 127 - pv.top, rows, 128)
  if G.active == "roll_vsb" then pv.top = 127 - ny end

  PR.interact(A, R, clip, notes)
end

----------------------------------------------------------------------------- interaction
function PR.interact(A, R, clip, notes)
  local S, C, m, P = A.S, A.C, G.m, A.P
  local gr, vr = R.roll_grid, R.roll_vel
  local view, pv = S.roll.view, S.roll.pv
  local sn = S.snap()
  local track = clip.track
  local clip_end = clip.start + clip.len

  -- wheel
  if G.over(gr[1] - 56, gr[2], gr[3] + 56, gr[4] + vr[4]) and (m.wheel ~= 0 or m.hwheel ~= 0) then
    if m.cmd then TL.zoom(view, m.wheel > 0 and 1.15 or 1 / 1.15, m.x, gr[1])
    elseif m.alt then pv.row_h = U.clamp(pv.row_h * (m.wheel > 0 and 1.1 or 1 / 1.1), 8, 30)
    elseif m.hwheel ~= 0 or m.shift then TL.scroll(view, -(m.hwheel ~= 0 and m.hwheel or m.wheel) / 120 * 60 / view.ppb)
    else pv.top = U.clamp(pv.top + m.wheel / 120 * 3, 0, 127) end
  end

  if D then
    if D.kind == "vel" then
      if m.down then
        local vel = U.clamp(U.round((1 - (m.y - vr[2] - 3) / (vr[4] - 6)) * 127), 1, 127)
        if D.sel_group then
          local dv = vel - D.orig_vel
          for _, o in ipairs(D.group) do C.set_note(clip.id, o.idx, { vel = o.vel + dv }, true) end
        else C.set_note(clip.id, D.idx, { vel = vel }, true) end
      else C.sort_notes(clip.id) C.end_gesture() D = nil G.release() end
      return
    end
    if D.kind == "move" or D.kind == "resize" then
      if not D.began and (math.abs(m.x - D.mx) > 3 or math.abs(m.y - D.my) > 3) then
        D.began = true C.begin_gesture(D.kind == "move" and "Move notes" or "Resize notes")
      end
      if D.began then
        local b = beat_at(S, R, m.x)
        if D.kind == "move" then
          local newS = U.snap(D.anchor.s + (b - D.grab), sn)
          local dB = newS - D.anchor.s
          local dp = pitch_at(S, R, m.y) - D.grab_pitch
          -- clamp so the whole group stays inside the clip and MIDI range
          for _, o in ipairs(D.group) do
            dB = math.max(dB, clip.start - o.s) dB = math.min(dB, clip_end - o.e)
            dp = math.max(dp, -o.pitch) dp = math.min(dp, 127 - o.pitch)
          end
          if dB ~= D.last_dB or dp ~= D.last_dp then
            apply_move(A, clip, D.group, D.anchor, dB, dp)
            if dp ~= D.last_dp then A.audition(track.id, D.anchor.pitch + dp, 80) end
            D.last_dB, D.last_dp = dB, dp
          end
        else
          local newE = U.snap(b, sn)
          local dE = newE - D.anchor.e
          for _, o in ipairs(D.group) do
            local e = U.clamp(o.e + dE, o.s + (sn > 0 and sn or MIN_LEN), clip_end)
            if e ~= o.cur_e then C.set_note(clip.id, o.idx, { e = e }, true) o.cur_e = e end
          end
        end
      end
      if m.released then
        if D.began then
          C.sort_notes(clip.id) C.end_gesture()
          if D.kind == "resize" then
            local a = D.group[1]
            for _, o in ipairs(D.group) do if o.idx == D.anchor.idx then a = o end end
            if a.cur_e then S.roll.note_len = math.max(MIN_LEN, a.cur_e - a.s) end
          end
        end
        D = nil G.release()
      end
      return
    end
    if D.kind == "draw" then
      if not D.began and (math.abs(m.x - D.mx) > 4) then D.began = true end
      if m.released then
        local len
        if D.began then len = U.snap(beat_at(S, R, m.x), sn) - D.s else len = S.roll.note_len end
        if len < (sn > 0 and sn or MIN_LEN) then len = sn > 0 and sn or MIN_LEN end
        if D.began then S.roll.note_len = len end
        if C.insert_note(clip.id, D.pitch, D.s, D.s + len, D.vel or 100) then A.audition(track.id, D.pitch, D.vel or 100) end
        D = nil G.release()
      end
      return
    end
    if D.kind == "marquee" then
      if m.released then
        local x0, x1 = math.min(D.mx, m.x), math.max(D.mx, m.x)
        local y0, y1 = math.min(D.my, m.y), math.max(D.my, m.y)
        local set = {}
        if D.add then for _, n in ipairs(notes) do if n.sel then set[n.idx] = true end end end
        for _, n in ipairs(notes) do
          local nx0, nx1 = TL.beat_to_x(view, n.s, gr[1]), TL.beat_to_x(view, n.e, gr[1])
          local ny = TL.pitch_to_y(pv, n.pitch, gr[2])
          if nx1 >= x0 and nx0 <= x1 and ny + pv.row_h >= y0 and ny <= y1 then set[n.idx] = true end
        end
        C.select_notes(clip.id, set)
        D = nil G.release()
      end
      return
    end
  end

  -- ---- new interactions
  local in_grid = G.over(gr[1], gr[2], gr[3], gr[4])
  local in_vel = G.over(vr[1], vr[2], vr[3], vr[4])
  if (m.pressed or m.rpressed) and (in_grid or in_vel) then S.focus = "roll" end

  if in_grid then
    local hi, zone = TL.hit_note(notes, view, pv, m.x, m.y, gr[1], gr[2], 6)
    if hi and zone ~= "body" then G.want_cursor("resize") end
    if m.pressed then
      if hi then
        local n = notes[hi]
        if m.shift then
          local set = {} for _, q in ipairs(notes) do if q.sel then set[q.idx] = true end end
          set[n.idx] = (not n.sel) or nil
          C.select_notes(clip.id, set)
          return
        end
        if not n.sel then C.select_notes(clip.id, { [n.idx] = true }) P.touch() n.sel = true end
        local group = {}
        for _, q in ipairs(notes) do if q.sel or q.idx == n.idx then group[#group + 1] = { idx = q.idx, s = q.s, e = q.e, pitch = q.pitch, vel = q.vel } end end
        D = { kind = zone == "right" and "resize" or "move", mx = m.x, my = m.y, began = false, anchor = { idx = n.idx, s = n.s, e = n.e, pitch = n.pitch },
          grab = beat_at(S, R, m.x), grab_pitch = pitch_at(S, R, m.y), group = group, last_dB = 0, last_dp = 0 }
        if zone == "left" then D.kind = "move" end
        A.audition(track.id, n.pitch, n.vel)
        G.capture("roll_drag")
      else
        local pitch = pitch_at(S, R, m.y)
        if m.shift then
          D = { kind = "marquee", mx = m.x, my = m.y, add = false } G.capture("roll_drag")
        else
          C.select_notes(clip.id, {})
          local s = U.snap_floor(beat_at(S, R, m.x), sn > 0 and sn or MIN_LEN)
          if s >= clip.start - 1e-6 and s < clip_end - 1e-6 and pitch >= 0 and pitch <= 127 then
            D = { kind = "draw", mx = m.x, s = s, pitch = pitch, began = false, vel = 100 } G.capture("roll_drag")
          end
        end
      end
    elseif m.rpressed and hi then
      local n = notes[hi]
      local idxs = {}
      if n.sel then for _, q in ipairs(notes) do if q.sel then idxs[#idxs + 1] = q.idx end end else idxs[1] = n.idx end
      C.delete_notes(clip.id, idxs)
    end
  elseif in_vel and m.pressed then
    -- nearest note start within 6px
    local best, bd
    for _, n in ipairs(notes) do
      local x = TL.beat_to_x(view, n.s, vr[1])
      local d = math.abs(x + 2 - m.x)
      if d < 8 and (not bd or d < bd) then best, bd = n, d end
    end
    if best then
      local group = {}
      local sel_group = best.sel
      if sel_group then for _, q in ipairs(notes) do if q.sel then group[#group + 1] = { idx = q.idx, vel = q.vel } end end end
      C.begin_gesture("Edit velocity")
      D = { kind = "vel", idx = best.idx, sel_group = sel_group, group = group, orig_vel = best.vel }
      G.capture("roll_drag")
      local vel = U.clamp(U.round((1 - (m.y - vr[2] - 3) / (vr[4] - 6)) * 127), 1, 127)
      D.orig_vel = best.vel
      if sel_group then local dv = vel - best.vel for _, o in ipairs(group) do C.set_note(clip.id, o.idx, { vel = o.vel + dv }, true) end
      else C.set_note(clip.id, best.idx, { vel = vel }, true) end
    end
  end
end

-- keyboard (called by app when roll has focus). returns true if consumed
function PR.key(A, k)
  local S, C = A.S, A.C
  local clip = S.edit_clip and A.P.clip(S.edit_clip)
  if not clip or clip.kind ~= "midi" then return false end
  local notes = A.P.notes(clip)
  local sel = selected_list(notes)
  local sn = S.snap() > 0 and S.snap() or 0.25
  if k.name == "backspace" or k.name == "delete" then
    if #sel == 0 then return false end
    local idxs = {} for _, n in ipairs(sel) do idxs[#idxs + 1] = n.idx end
    C.delete_notes(clip.id, idxs) return true
  elseif k.cmd and k.lower == "a" then
    local set = {} for _, n in ipairs(notes) do set[n.idx] = true end
    C.select_notes(clip.id, set) return true
  elseif k.name == "up" or k.name == "down" then
    if #sel == 0 then return false end
    local d = (k.name == "up" and 1 or -1) * (k.shift and 12 or 1)
    C.begin_gesture("Transpose")
    for _, n in ipairs(sel) do C.set_note(clip.id, n.idx, { pitch = U.clamp(n.pitch + d, 0, 127) }, true) end
    C.sort_notes(clip.id) C.end_gesture() return true
  elseif (k.name == "left" or k.name == "right") and #sel > 0 then
    local d = (k.name == "right" and 1 or -1) * sn
    local lo = clip.start local hi = clip.start + clip.len
    for _, n in ipairs(sel) do if n.s + d < lo - 1e-6 or n.e + d > hi + 1e-6 then return true end end
    C.begin_gesture("Nudge notes")
    for _, n in ipairs(sel) do C.set_note(clip.id, n.idx, { s = n.s + d, e = n.e + d }, true) end
    C.sort_notes(clip.id) C.end_gesture() return true
  elseif k.lower == "q" and not k.cmd then
    C.quantize_notes(clip.id, sn, #sel > 0) return true
  end
  return false
end

function PR.dragging() return D ~= nil end
return PR
