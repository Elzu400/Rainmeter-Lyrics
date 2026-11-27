-- Copyright (C) 2026 Elzu400
-- SPDX-License-Identifier: GPL-3.0-or-later
-- This file is part of RainmeterLyrics, free software under the GNU GPL v3 or later (see LICENSE).

-- Rainmeter Lyrics - per-song timing offsets (Lua 5.1, ASCII only).
-- A script measure of the lyrics skin: its value is the timing offset (seconds) of the song that
-- is playing, which lyrics.lua adds to the global offset. Offsets live in @Resources\SongOffsets.txt
-- (one song per line: key <TAB> seconds <TAB> artist - title). The quick settings skin changes
-- them through Preview() / Set() and learns about the current song through Quick.inc.

local floor, abs = math.floor, math.abs

local file, quickFile
local offs, names = {}, {}
local key, cur, label = '', 0, ''
local lastTitle, lastArtist = nil, nil
local mTitle, mArtist
local quickConfig = 'RainmeterLyrics\\Quick'

local function norm(s)
  s = tostring(s or ''):lower()
  s = s:gsub('%s*[%(%[].-[%)%]]', '')          -- "(Remastered)", "[Live]" ... do not make a new song
  return (s:gsub('[%c%p%s]', ''))
end

local function makeKey(artist, title)
  if norm(title) == '' then return '' end
  return norm(artist) .. '|' .. norm(title)
end

-- seconds, rounded to milliseconds
local function round3(v)
  if v < 0 then return -floor(-v * 1000 + 0.5) / 1000 end
  return floor(v * 1000 + 0.5) / 1000
end

local function fmt(v)
  local s = string.format('%.3f', v):gsub('0+$', ''):gsub('%.$', '')
  if s == '-0' or s == '' then s = '0' end
  return s
end

local function load()
  offs, names = {}, {}
  local f = io.open(file, 'r')
  if not f then return end
  for line in f:lines() do
    local k, v, n = line:match('^([^\t]+)\t([^\t]+)\t?(.*)$')
    v = tonumber(v)
    if k and v then
      offs[k] = v
      names[k] = n
    end
  end
  f:close()
end

local function save()
  local f = io.open(file, 'w')
  if not f then return false end
  local keys = {}
  for k in pairs(offs) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    f:write(k, '\t', fmt(offs[k]), '\t', names[k] or '', '\n')
  end
  f:close()
  return true
end

-- text that is safe inside a Rainmeter variable
local function safe(s)
  return (tostring(s or ''):gsub('[%c"#%%]', ' '))
end

-- what the quick settings skin reads: the song, its offset and where to open
local function writeQuick()
  local f = io.open(quickFile, 'w')
  if not f then return end
  local x = tonumber(SKIN:ReplaceVariables('#CURRENTCONFIGX#')) or 0
  local y = tonumber(SKIN:ReplaceVariables('#CURRENTCONFIGY#')) or 0
  local h = tonumber(SKIN:ReplaceVariables('#CURRENTCONFIGHEIGHT#')) or 60
  local sh = tonumber(SKIN:ReplaceVariables('#SCREENAREAHEIGHT#')) or 1080
  local qy = y + h + 8
  if qy + 262 > sh then qy = math.max(0, y - 262 - 8) end
  f:write('QKey=', safe(key), '\n')
  f:write('QName=', safe(label), '\n')
  f:write('QOffset=', fmt(cur), '\n')
  f:write('QX=', floor(x), '\n')
  f:write('QY=', floor(qy), '\n')
  f:close()
end

function Initialize()
  file = SKIN:ReplaceVariables('#@#SongOffsets.txt')
  quickFile = SKIN:ReplaceVariables('#@#Quick.txt')
  local main = SKIN:GetVariable('QuickConfig', '')
  if main ~= nil and main ~= '' then quickConfig = main end
  mTitle = SKIN:GetMeasure('mTitle')
  mArtist = SKIN:GetMeasure('mArtist')
  load()
end

function Update()
  local title = mTitle and mTitle:GetStringValue() or ''
  local artist = mArtist and mArtist:GetStringValue() or ''
  if title ~= lastTitle or artist ~= lastArtist then        -- only when the song changes
    lastTitle, lastArtist = title, artist
    local k = makeKey(artist, title)
    if k ~= key then
      key = k
      label = (artist ~= '' and (artist .. ' - ') or '') .. title
      cur = offs[k] or 0
      writeQuick()
    end
  end
  return cur
end

-- live preview from the slider: applies at once, nothing is saved yet
function Preview(v)
  v = tonumber(v)
  if not v or key == '' then return end
  cur = round3(v)
end

-- final value (slider released, number typed): applies and remembers it for the next time
function Set(v)
  v = tonumber(v)
  if not v or key == '' then return end
  cur = round3(v)
  if abs(cur) < 0.0005 then
    cur = 0
    offs[key], names[key] = nil, nil
  else
    offs[key], names[key] = cur, safe(label)
  end
  save()
  writeQuick()
end

-- the cover button: opens the quick settings next to the lyrics (or closes them again)
function Open()
  writeQuick()
  SKIN:Bang('!ToggleConfig', quickConfig, 'RainmeterLyricsQuick.ini')
end
