-- Copyright (C) 2026 Elzu400
-- SPDX-License-Identifier: GPL-3.0-or-later
-- This file is part of RainmeterLyrics, free software under the GNU GPL v3 or later (see LICENSE).

-- Rainmeter Lyrics - quick settings window (Lua 5.1, ASCII only).
-- Timing offset of the current song: a slider (-2..+2 s in 0.1 s steps) and a box for any value.
-- The lyrics skin keeps the offsets (offsets.lua); this window only sends values to it and
-- reads the current song from Quick.txt, which offsets.lua keeps up to date.

local floor, abs, max, min = math.floor, math.abs, math.max, math.min

local X0, SPAN, MID = 28, 304, 180             -- slider track: left edge, width, middle (0 s)
local ACCENT = '150,110,255'

local mainConfig = 'RainmeterLyrics\\Lyrics'
local settingsConfig = 'RainmeterLyrics\\Settings'
local file
local state = { key = '', name = '', offset = 0, x = nil, y = nil }
local drag, leaving = false, nil
local status = ''
local ticks, moved = 0, false

local function fmt(v)
  local s = string.format('%.3f', v):gsub('0+$', ''):gsub('%.$', '')
  if s == '-0' or s == '' then s = '0' end
  return s
end

local function signed(v)
  local s = fmt(v)
  if v > 0 then s = '+' .. s end
  return s .. ' s'
end

local function readState()
  local f = io.open(file, 'r')
  if not f then return nil end
  local t = {}
  for line in f:lines() do
    local k, v = line:match('^(%w+)=(.*)$')
    if k then t[k] = v end
  end
  f:close()
  return t
end

-- keep text on one short line and out of the way of Rainmeter's own syntax
local function plain(s)
  return (tostring(s or ''):gsub('[%c"#%[%]]', ' '))
end

local function render()
  local v = state.offset
  local t = max(-2, min(2, v))
  local tx = X0 + (t + 2) / 4 * SPAN
  local segX, segW = min(MID, tx), abs(tx - MID)
  local sl = {
    string.format('[!SetOption Slide Shape "Rectangle %d,15,%d,4,2 | Fill Color 255,255,255,40 | StrokeWidth 0"]', X0, SPAN),
    string.format('[!SetOption Slide Shape2 "Rectangle %d,9,2,16,1 | Fill Color 255,255,255,80 | StrokeWidth 0"]', MID - 1),
    string.format('[!SetOption Slide Shape3 "Rectangle %.1f,15,%.1f,4,2 | Fill Color %s,255 | StrokeWidth 0"]', segX, max(0.1, segW), ACCENT),
    string.format('[!SetOption Slide Shape4 "Ellipse %.1f,17,8 | Fill Color 232,232,242,255 | StrokeWidth 2 | Stroke Color %s,255"]', tx, ACCENT),
  }
  local b = table.concat(sl)
  b = b .. '[!SetOption Song Text "' .. (state.key ~= '' and plain(state.name) or 'Nothing is playing') .. '"]'
  b = b .. '[!SetOption V Text "' .. signed(v) .. '"]'
  b = b .. '[!SetOption Status Text "' .. plain(status) .. '"]'
  b = b .. '[!UpdateMeter *][!Redraw]'
  SKIN:Bang(b)
end

-- tell the lyrics skin about a value; final = remember it for next time
local function send(v, final)
  state.offset = v
  SKIN:Bang('!CommandMeasure', 'mOffsets', string.format('%s(%.3f)', final and 'Set' or 'Preview', v), mainConfig)
end

function Initialize()
  file = SKIN:ReplaceVariables('#@#Quick.txt')
  local m = SKIN:GetVariable('MainConfig', '')
  if m ~= nil and m ~= '' then mainConfig = m end
  local s = SKIN:GetVariable('SettingsConfig', '')
  if s ~= nil and s ~= '' then settingsConfig = s end
  local t = readState()
  if t then
    state.key, state.name, state.offset = t.QKey or '', t.QName or '', tonumber(t.QOffset) or 0
    state.x, state.y = tonumber(t.QX), tonumber(t.QY)
  end
end

function Update()
  if not moved and state.x then
    moved = true
    SKIN:Bang('!Move', floor(state.x), floor(state.y))
  end
  if ticks == 0 then
    ticks = 1
    render()
  end
  if drag and leaving and os.clock() - leaving > 0.25 then Up() end      -- let go outside the slider
  ticks = ticks + 1
  if ticks % 5 == 0 and not drag then
    local t = readState()
    if t then
      local o = tonumber(t.QOffset) or 0
      if (t.QKey or '') ~= state.key or o ~= state.offset then
        state.key, state.name, state.offset = t.QKey or '', t.QName or '', o
        status = ''
        render()
      end
    end
  end
  return 0
end

-- ---------- the slider: one hit zone per 0.1 s (i = 0..40) ----------

function Down(i)
  if state.key == '' then return end
  drag, leaving = true, nil
  send((tonumber(i) - 20) / 10, false)
  status = ''
  render()
end

function Over(i)
  leaving = nil
  if not drag then return end
  local v = (tonumber(i) - 20) / 10
  if v ~= state.offset then
    send(v, false)
    render()
  end
end

function Leave()
  if drag then leaving = os.clock() end
end

function Up()
  if not drag then return end
  drag, leaving = false, nil
  send(state.offset, true)
  status = 'Saved for this song'
  render()
end

-- ---------- the number box ----------

function Edit()
  if state.key == '' then return end
  SKIN:Bang('!SetVariable', 'QOffText', fmt(state.offset))
  SKIN:Bang('!UpdateMeasure', 'mInOff')
  SKIN:Bang('!CommandMeasure', 'mInOff', 'ExecuteBatch 1')
end

-- any number of seconds, no limit ("2", "-1.5", "+0,3 s")
function Typed(text)
  local s = tostring(text or ''):gsub(',', '.')
  local n = tonumber(s:match('^%s*([%+%-]?%d*%.?%d+)%s*s?%s*$'))
  if not n or state.key == '' then
    status = 'Type a number of seconds, like -1 or 2.1'
    render()
    return
  end
  if n < 0 then n = -floor(-n * 1000 + 0.5) / 1000 else n = floor(n * 1000 + 0.5) / 1000 end
  send(n, true)
  status = 'Saved for this song'
  render()
end

-- ---------- shortcuts ----------

function OpenSettings()
  SKIN:Bang('!ActivateConfig', settingsConfig, 'RainmeterLyricsSettings.ini')
  SKIN:Bang('!DeactivateConfig', SKIN:GetVariable('CURRENTCONFIG', 'RainmeterLyrics\\Quick'))
end
