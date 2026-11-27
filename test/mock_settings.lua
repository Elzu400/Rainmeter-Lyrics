-- Copyright (C) 2026 Elzu400
-- SPDX-License-Identifier: GPL-3.0-or-later
-- This file is part of RainmeterLyrics, free software under the GNU GPL v3 or later (see LICENSE).

-- Headless harness for settings.lua. usage: texlua mock_settings.lua <tree>
local tree = arg[1]
local function readFile(p) local f = assert(io.open(p, 'rb')); local s = f:read('*a'); f:close(); return s end

local VARS = {}
for line in readFile(tree .. '/RainmeterLyrics/@Resources/Settings.inc'):gmatch('[^\r\n]+') do
  local k, v = line:match('^([%w_]+)=(.*)$')
  if k then VARS[k] = v end
end
VARS.MainConfig = 'RainmeterLyrics\\Lyrics'

local meters, measures = {}, {}
do
  local cur
  for line in readFile(tree .. '/RainmeterLyrics/Settings/RainmeterLyricsSettings.ini'):gmatch('[^\r\n]+') do
    local sec = line:match('^%[(.-)%]$')
    if sec then cur = { name = sec, opts = {} }
    elseif cur then
      local k, v = line:match('^([%w_]+)=(.*)$')
      if k then
        cur.opts[k] = v
        if k == 'Meter' then meters[cur.name] = cur elseif k == 'Measure' then measures[cur.name] = cur end
      end
    end
  end
  for _, m in pairs(meters) do m.hidden = (m.opts.Hidden == '1'); m.group = m.opts.Group end
end

local clock = 0
os.clock = function() return clock end
local errors, writes, refreshes, inputs = {}, {}, {}, {}
local function err(m) errors[#errors + 1] = m; io.stderr:write('ERROR: ' .. m .. '\n') end

SKIN = {}
function SKIN:GetVariable(n, d) local v = VARS[n]; if v == nil then return d end return v end
function SKIN:ReplaceVariables(s) return (s:gsub('#@#', '/res/')) end
local queue = {}
function SKIN:Bang(...)
  local a = { ... }
  if #a == 1 then queue[#queue + 1] = a[1] else
    local p = { a[1] }
    for i = 2, #a do p[#p + 1] = '"' .. tostring(a[i]) .. '"' end
    queue[#queue + 1] = table.concat(p, ' ')
  end
end

local function tokenize(cmd)
  local toks, i = {}, 1
  while i <= #cmd do
    local c = cmd:sub(i, i)
    if c:match('%s') then i = i + 1
    elseif c == '"' then
      local j = cmd:find('"', i + 1, true)
      if not j then err('unterminated quote: ' .. cmd:sub(1, 80)); return toks end
      toks[#toks + 1] = cmd:sub(i + 1, j - 1); i = j + 1
    else
      local j = cmd:find('%s', i) or (#cmd + 1)
      toks[#toks + 1] = cmd:sub(i, j - 1); i = j
    end
  end
  return toks
end

local function groupExists(g) for _, m in pairs(meters) do if m.group == g then return true end end return false end

local function runBang(cmd)
  local t = tokenize(cmd)
  local b = t[1]
  if b == '!SetOption' then
    local m = meters[t[2]]
    if not m then err('SetOption on unknown meter ' .. tostring(t[2])); return end
    m.opts[t[3]] = t[4]
  elseif b == '!ShowMeterGroup' or b == '!HideMeterGroup' then
    if not groupExists(t[2]) then err(b .. ' unknown group ' .. tostring(t[2])); return end
    for _, m in pairs(meters) do if m.group == t[2] then m.hidden = (b == '!HideMeterGroup') end end
  elseif b == '!UpdateMeter' or b == '!Redraw' then
  elseif b == '!WriteKeyValue' then writes[#writes + 1] = { key = t[3], val = t[4], file = t[5] }
  elseif b == '!Refresh' then refreshes[#refreshes + 1] = t[2]
  elseif b == '!CommandMeasure' then
    if not measures[t[2]] then err('CommandMeasure unknown measure ' .. tostring(t[2])) end
    inputs[#inputs + 1] = t[2] .. ':' .. tostring(t[3])
  else err('unknown bang ' .. tostring(b)) end
end
local function flush()
  local q = queue; queue = {}
  for _, s in ipairs(q) do
    if s:sub(1, 1) == '[' then
      for cmd in s:gmatch('%[(.-)%]') do runBang(cmd) end
      if s:gsub('%[.-%]', '') ~= '' then err('stray text outside brackets') end
    else runBang(s) end
  end
end
local function call(fn, ...)
  local ok, e = pcall(fn, ...)
  if not ok then err(tostring(e)) end
  flush()
end

dofile(tree .. '/RainmeterLyrics/@Resources/settings.lua')

local function visibleRows()
  local out = {}
  for i = 1, 11 do
    local l, v = meters['L' .. i], meters['V' .. i]
    if l and not l.hidden then out[#out + 1] = i .. ':' .. tostring(l.opts.Text) .. '=' .. tostring(v.opts.Text) end
  end
  return out
end
local function show(title)
  print('--- ' .. title)
  for _, r in ipairs(visibleRows()) do print('  ' .. r) end
end

call(Initialize)
call(Update)
show('Layout tab at start')
print('  tab1 fill:', meters.Tab1.opts.Shape)

-- walk every tab, click every row's - and + once, and Edit
for t = 1, 4 do
  call(Tab, t)
  local n = #visibleRows()
  for i = 1, n do
    call(Step, i, 1); call(Step, i, -1); call(Step, i, 1); call(Edit, i)
  end
  if t == 3 then show('Colors tab after poking every row') end
end

-- preset switching
call(Tab, 1)
call(Step, 1, 1)
show('after Preset +1')
call(Step, 1, 1)
call(Step, 1, -1)
call(Step, 2, 1)
local before = meters.V1.opts.Text
print('  preset after tweaking width ->', before)

-- hex input
call(Tab, 3)
call(SetHex, 'AccentColor', '#B48CFF')
call(SetHex, 'AccentColor', 'nonsense')
call(SetHex, 'BgColor', '20 30 40')
call(Palette, 3)
show('Colors after hex + palette')
print('  palette visible group:', meters.P1.hidden and 'hidden' or 'shown')

-- debounce + commit
clock = 0.5; call(Update)
print('writes before debounce expires:', #writes)
clock = 2.0; call(Update)
print('writes after commit:', #writes, 'refreshes:', #refreshes, refreshes[1])
for i = 1, math.min(5, #writes) do print('  ', writes[i].key, writes[i].val, writes[i].file) end
call(Reset)
clock = 4.0; call(Update)
print('after reset: writes total', #writes)

-- every Edit on a color row should have asked an InputText measure
print('input requests:', table.concat(inputs, ','))
print('errors:', #errors)
os.exit(#errors == 0 and 0 or 1)
