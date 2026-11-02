-- wavio.lua : minimal PCM WAV writer + analyzer (pure Lua; used by sample generation, export validation and tests)
local W = {}

function W.write16(path, samples, sr, channels)
  channels = channels or 1
  local n = #samples
  local parts = {}
  for i = 1, n do
    local v = math.max(-1, math.min(1, samples[i]))
    parts[i] = string.pack("<i2", math.floor(v * 32767 + 0.5))
  end
  local data = table.concat(parts)
  local f = assert(io.open(path, "wb"))
  f:write("RIFF", string.pack("<I4", 36 + #data), "WAVEfmt ", string.pack("<I4I2I2I4I4I2I2", 16, 1, channels, sr, sr * channels * 2, channels * 2, 16))
  f:write("data", string.pack("<I4", #data), data)
  f:close()
end

-- returns { peak, secs, sr, bits, channels, fmt, buckets = {peak per bucket_secs}, rms }
function W.analyze(path, bucket_secs)
  local f = io.open(path, "rb")
  if not f then return nil, "no file at " .. tostring(path) end
  local d = f:read("a") f:close()
  if d:sub(1, 4) ~= "RIFF" or d:sub(9, 12) ~= "WAVE" then return nil, "not a RIFF/WAVE file" end
  local pos, fmt, ch, bits, sr = 13
  while pos + 8 <= #d + 1 do
    local id = d:sub(pos, pos + 3)
    local sz = string.unpack("<I4", d, pos + 4)
    if id == "fmt " then
      fmt, ch, sr = string.unpack("<I2I2I4", d, pos + 8)
      bits = string.unpack("<I2", d, pos + 8 + 14)
    elseif id == "data" then
      if not fmt then return nil, "data before fmt" end
      local b = bits // 8
      local n = math.min(sz, #d - (pos + 7)) // (b * ch)
      local per = math.max(1, math.floor(sr * (bucket_secs or 0.5)))
      local peak, buckets, sumsq = 0, {}, 0
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
        local a = math.abs(v)
        if a > peak then peak = a end
        sumsq = sumsq + v * v
        local bk = i // per + 1
        if a > (buckets[bk] or 0) then buckets[bk] = a end
      end
      return { peak = peak, secs = n / sr, sr = sr, bits = bits, channels = ch, fmt = fmt, buckets = buckets,
        rms = n > 0 and math.sqrt(sumsq / n) or 0, frames = n }
    end
    pos = pos + 8 + sz + (sz % 2)
  end
  return nil, "no data chunk"
end

return W
