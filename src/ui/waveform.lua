-- waveform.lua : REAL waveform min/max columns decoded from the take through REAPER's audio accessor.
-- (GetMediaItemTake_Peaks returns nothing in REAPER 7.39's Lua binding, so we decode at a reduced rate instead.)
local r = reaper
local W = { cache = {} }

-- returns { n, max = {}, min = {} } covering the whole item with n columns, or nil
function W.get(clip, pps)
  local take = clip.take
  if not take or clip.kind ~= "audio" then return nil end
  local secs = clip.time_len
  local n = math.max(8, math.min(3000, math.floor(secs * pps)))
  local key = string.format("%d|%.4f|%.4f|%.4f", n, clip.time_len, clip.offs, clip.rate)
  local c = W.cache[clip.id]
  if c and c.key == key then return c end
  local acc = r.CreateTakeAudioAccessor(take)
  if not acc then return nil end
  local sr = math.max(4000, math.min(16000, math.floor(n / secs * 6)))
  local total = math.floor(secs * sr)
  local per_col = math.max(1, total / n)
  local out = { key = key, n = n, max = {}, min = {} }
  for i = 1, n do out.max[i] = -1 out.min[i] = 1 end
  local BLOCK = 8192
  local buf = r.new_array(BLOCK)
  local done = 0
  while done < total do
    local cnt = math.min(BLOCK, total - done)
    local ok = r.GetAudioAccessorSamples(acc, sr, 1, done / sr, cnt, buf)
    if ok <= 0 then break end
    for i = 1, cnt do
      local v = buf[i]
      local col = math.floor((done + i - 1) / per_col) + 1
      if col > n then col = n end
      if v > out.max[col] then out.max[col] = v end
      if v < out.min[col] then out.min[col] = v end
    end
    done = done + cnt
  end
  r.DestroyAudioAccessor(acc)
  for i = 1, n do if out.max[i] < out.min[i] then out.max[i], out.min[i] = 0, 0 end end
  W.cache[clip.id] = out
  return out
end
return W
