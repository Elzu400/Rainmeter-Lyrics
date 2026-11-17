-- Copyright (C) 2026 the SonoraLyrics authors
-- SPDX-License-Identifier: GPL-3.0-or-later
-- This file is part of SonoraLyrics, free software under the GNU GPL v3 or later (see LICENSE).

-- Headless harness for lyrics.lua: fake Rainmeter API driven by the generated ini.
-- usage: texlua mock_main.lua <tree> <classic|slim> [seconds] [verbose]
local tree, preset, seconds, verbose = arg[1], arg[2] or 'classic', tonumber(arg[3] or 80), arg[4] == 'v'

local function readFile(p) local f = assert(io.open(p, 'rb')); local s = f:read('*a'); f:close(); return s end

-- ---------- variables from Settings.inc (+ preset overrides) ----------
local VARS = {}
for line in readFile(tree .. '/SonoraLyrics/@Resources/Settings.inc'):gmatch('[^\r\n]+') do
  local k, v = line:match('^([%w_]+)=(.*)$')
  if k then VARS[k] = v end
end
if preset == 'slim' then
  local SLIM = { PillWidth = '780', PillHeight = '44', CornerRadius = '22', CoverSize = '30', CoverRadius = '9',
    Padding = '8', CoverGap = '10', FontSize = '13', ProgressHeight = '2', ProgressBottom = '5', TextNudgeY = '2',
    VisBarWidth = '3', VisGap = '3', VisHeight = '18', PillRadius = '8', PillPadX = '8', WordSpacing = '5',
    LineGap = '20', FadeZone = '60', FocusPos = '38' }
  for k, v in pairs(SLIM) do VARS[k] = v end
end
if os.getenv('MOCK_WORDS') then VARS.PillWords = os.getenv('MOCK_WORDS') end
if os.getenv('MOCK_DEBUG') then VARS.Debug = '1' end
if os.getenv('MOCK_WALL') then VARS.ColorMode = 'wallpaper' end
if os.getenv('MOCK_STYLE') then VARS.PillStyle = os.getenv('MOCK_STYLE') end
if os.getenv('MOCK_MODE') then VARS.LyricMode = os.getenv('MOCK_MODE') end

-- ---------- meters / measures from the ini ----------
local meters, measures, order = {}, {}, {}
do
  local ini = readFile(tree .. '/SonoraLyrics/Lyrics/SonoraLyrics.ini')
  local cur
  for line in ini:gmatch('[^\r\n]+') do
    local sec = line:match('^%[(.-)%]$')
    if sec then cur = { name = sec, opts = {} }
    elseif cur then
      local k, v = line:match('^([%w_]+)=(.*)$')
      if k then
        cur.opts[k] = v
        if k == 'Meter' then
          cur.kind = 'meter'; meters[cur.name] = cur; order[#order + 1] = cur.name
        elseif k == 'Measure' then
          cur.kind = 'measure'; measures[cur.name] = cur
        end
      end
    end
  end
  for _, m in pairs(meters) do
    m.hidden = (m.opts.Hidden == '1')
    m.group = m.opts.Group
    m.W = 0
  end
end

-- ---------- clock + errors ----------
local clock = 0
os.clock = function() return clock end
local errors = {}
local function err(msg) errors[#errors + 1] = msg; if #errors < 15 then io.stderr:write('ERROR: ' .. msg .. '\n') end end

-- ---------- player simulation ----------
local songT, playing = 0, true
local title, artist = 'Midnight Drive', 'The Testers'
local lyricsRaw = ''
local band = { 0, 0, 0, 0 }

local function mm(t) return string.format('%02d:%02d', math.floor(t / 60), math.floor(t % 60)) end

local function mk(getS, getV)
  return { GetStringValue = function() return getS() end, GetValue = function() return getV() end }
end
local MS = {
  mTitle = mk(function() return title end, function() return 0 end),
  mArtist = mk(function() return artist end, function() return 0 end),
  mPosition = mk(function() return mm(songT) end, function() return math.floor(songT) end),
  mDuration = mk(function() return '03:30' end, function() return 210 end),
  mState = mk(function() return playing and '1' or '0' end, function() return playing and 1 or 0 end),
  mProgress = mk(function() return tostring(songT / 210 * 100) end, function() return songT / 210 * 100 end),
  mCover = mk(function() return '' end, function() return 0 end),
  mLyrics = mk(function() return lyricsRaw end, function() return 0 end),
  mWall = mk(function() return '40,90,160' end, function() return 0 end),
}
for i = 1, 4 do MS['mBand' .. i] = mk(function() return '' end, function() return band[i] end) end

SKIN = {}
function SKIN:GetVariable(name, default)
  local v = VARS[name]
  if v == nil then return default end
  return v
end
function SKIN:ReplaceVariables(s) return (s:gsub('#@#', '/res/')) end
function SKIN:GetMeasure(name)
  if not measures[name] then return nil end
  return MS[name]
end
function SKIN:GetMeter(name)
  local m = meters[name]
  if not m then return nil end
  return { GetW = function() return m.W end, GetX = function() return tonumber(m.opts.X) or 0 end }
end

-- ---------- bang queue ----------
local queue, bangCount = {}, 0
function SKIN:Bang(...)
  local a = { ... }
  if #a == 1 then queue[#queue + 1] = a[1] else
    local parts = { a[1] }
    for i = 2, #a do parts[#parts + 1] = '"' .. tostring(a[i]) .. '"' end
    queue[#queue + 1] = table.concat(parts, ' ')
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

local pendingFetch, pendingWall = nil, nil
local frame = 0
local writes = {}

local function runBang(cmd)
  bangCount = bangCount + 1
  local t = tokenize(cmd)
  local b = t[1]
  if b == '!SetOption' then
    local m = meters[t[2]]
    if not m then
      if measures[t[2]] then return end
      err('SetOption on unknown meter ' .. tostring(t[2])); return
    end
    if t[4] == nil then err('SetOption without value: ' .. cmd:sub(1, 60)) end
    m.opts[t[3]] = t[4]
    if t[3] == 'Text' then m.textDirty = true end
  elseif b == '!ShowMeter' or b == '!HideMeter' then
    local m = meters[t[2]]
    if not m then err(b .. ' on unknown meter ' .. tostring(t[2])); return end
    m.hidden = (b == '!HideMeter')
  elseif b == '!ShowMeterGroup' or b == '!HideMeterGroup' then
    for _, m in pairs(meters) do
      if m.group == t[2] then m.hidden = (b == '!HideMeterGroup') end
    end
  elseif b == '!UpdateMeter' or b == '!UpdateMeterGroup' or b == '!Redraw' then
    -- no-op
  elseif b == '!SetVariable' then
    VARS[t[2]] = t[3]
  elseif b == '!EnableMeasure' or b == '!DisableMeasure' then
    if not measures[t[2]] then err('unknown measure ' .. tostring(t[2])) end
  elseif b == '!CommandMeasure' then
    if t[2] == 'mLyrics' and t[3] == 'Update' then pendingFetch = frame + 20
    elseif t[2] == 'mWall' and t[3] == 'Run' then pendingWall = frame + 10
    else err('unexpected CommandMeasure ' .. cmd) end
  elseif b == '!WriteKeyValue' then
    writes[#writes + 1] = cmd
  else
    err('unknown bang ' .. tostring(b))
  end
end

local function flush()
  local q = queue
  queue = {}
  for _, s in ipairs(q) do
    if s:sub(1, 1) == '[' then
      local rest = s
      -- split "[...][...]" into commands
      for cmd in s:gmatch('%[(.-)%]') do runBang(cmd) end
      local stripped = s:gsub('%[.-%]', '')
      if stripped ~= '' then err('stray text outside brackets: ' .. stripped:sub(1, 60)) end
    else
      runBang(s)
    end
  end
  -- meters re-measure after being drawn
  for _, m in pairs(meters) do
    if m.opts.Text ~= nil and m.kind == 'meter' then
      if m.hidden then m.W = 0 else m.W = (#m.opts.Text) * 10.5 + 2 end
    end
  end
end

-- ---------- sample lyrics ----------
local LRC = {
  { 8.4,  "I'm driving through the midnight rain" },
  { 12.9, 'Headlights painting stripes on the road' },
  { 17.6, 'Every mile a little farther from the pain' },
  { 22.5, "And I don't know where I'm going but I go" },
  { 28.0, '' },
  { 36.0, '\\u266a' },
  { 44.0, "Hold on tight, the city's burning bright" },
  { 49.5, '\\"Never look back,\\" that\\u0027s what I said' },
  { 55.0, 'Singing loud to the radio tonight' },
  { 59.0, 'Extraordinarily long words in a short quick burst' },
  { 61.2, 'Go' },
  { 62.5, 'Oh oh oh oh oh oh oh oh' },
  { 70.0, 'And when the morning comes around again' },
  { 76.0, 'We will still be here' },
}
local parts = {}
for _, l in ipairs(LRC) do
  parts[#parts + 1] = string.format('[%02d:%05.2f] %s', math.floor(l[1] / 60), l[1] % 60, l[2])
end
local SYNCED = table.concat(parts, '\\n')   -- the literal backslash-n JSON form

dofile(tree .. '/SonoraLyrics/@Resources/lyrics.lua')

-- ---------- metrics ----------
local function parsePill(path)
  if not path then return nil end
  local xs = {}
  for x in path:gmatch('([%-%d%.]+),[%-%d%.]+') do xs[#xs + 1] = tonumber(x) end
  if #xs == 0 then return nil end
  local lo, hi = math.huge, -math.huge
  for _, x in ipairs(xs) do lo = math.min(lo, x); hi = math.max(hi, x) end
  return lo, hi
end

local function alphaOf(m)
  local a = (m.opts.FontColor or ''):match('^%d+,%d+,%d+,(%d+)$')
  return tonumber(a) or 0
end

local function snapshot()
  local vis = {}
  for i = 1, 40 do
    local m = meters['S' .. i]
    if m and not m.hidden and alphaOf(m) > 0 then
      vis[#vis + 1] = { text = m.opts.Text, x = tonumber(m.opts.X), a = alphaOf(m), w = m.W, id = 'S' .. i }
    end
  end
  table.sort(vis, function(a, b) return a.x < b.x end)
  return vis
end

local barX = tonumber(VARS.Padding) + (VARS.ShowCover == '1' and tonumber(VARS.CoverSize) + tonumber(VARS.CoverGap) or 0)

local lastPa
local stats = { frames = 0, maxPillStep = 0, maxWordStep = 0, sumVis = 0, maxVis = 0, pillOut = 0, cmds = 0, maxCmds = 0, snaps = 0 }
local lastPillL, lastWordX, trackedWord = nil, nil, nil
local shots = {}
local events = {}
local totalFrames = math.floor(seconds * 60)

-- events: seek back at 50s (frame), pause at 30s for 2s, track change (no lyrics) at 74s
local function atTime(t) return math.floor(t * 60) end

local waitFetchFailed = false
local startSong = 0
for f = 1, totalFrames + 200 do
  frame = f
  clock = f / 60
  if playing then songT = songT + 1 / 60 end
  local simT = songT

  if os.getenv('MOCK_EVENTS') ~= '0' then
    if f == atTime(30) then playing = false end
    if f == atTime(32) then playing = true end
    if f == atTime(52) then songT = 20.0 end                 -- seek backwards
    if f == atTime(60) then songT = 44.0 end                 -- seek forwards
    if f == atTime(74) then title, artist, songT, lyricsRaw = 'No Lyrics Here', 'Nobody', 0, '' ; waitFetchFailed = true end
  end
  band = { 0.5 + 0.5 * math.sin(clock * 3), 0.4 + 0.4 * math.sin(clock * 5), 0.3 + 0.3 * math.sin(clock * 7), 0.2 + 0.2 * math.sin(clock * 9) }

  local ok, e = pcall(Update)
  if not ok then err('Update crashed at frame ' .. f .. ': ' .. tostring(e)); break end
  local n0 = bangCount
  flush()

  if pendingFetch and f >= pendingFetch then
    pendingFetch = nil
    if waitFetchFailed then lyricsRaw = ''; ok, e = pcall(OnFailed) else lyricsRaw = SYNCED; ok, e = pcall(OnFetched) end
    if not ok then err('OnFetched crashed: ' .. tostring(e)) end
    flush()
  end
  if pendingWall and f >= pendingWall then
    pendingWall = nil
    ok, e = pcall(OnWallpaper)
    if not ok then err('OnWallpaper crashed: ' .. tostring(e)) end
    flush()
  end

  local cmds = bangCount - n0
  stats.cmds = stats.cmds + cmds
  stats.maxCmds = math.max(stats.maxCmds, cmds)
  stats.frames = stats.frames + 1

  local pill = meters.Pill
  local pl, pr = parsePill(pill.opts.PillPath)
  local vis = snapshot()
  local settled = (songT > 12 and not pill.hidden and pl)
  if settled then
    stats.sumVis = stats.sumVis + #vis
    stats.maxVis = math.max(stats.maxVis, #vis)
    -- track pill motion (only while no seek happened this frame)
    local seekFrame = (f == atTime(52) or f == atTime(60) or f == atTime(74))
    local pa = tonumber((pill.opts.Shape or ''):match('Fill Color %d+,%d+,%d+,(%d+)')) or 0
    if lastPillL and not seekFrame and pa >= 200 and (lastPa or 0) >= 200 then
      stats.maxPillStep = math.max(stats.maxPillStep, math.abs(pl - lastPillL))
    end
    lastPillL, lastPa = pl, pa
    -- track one word's x
    if not trackedWord or f % 600 == 0 then trackedWord = nil end
    local barW = tonumber(VARS._barW) or 0
  else
    lastPillL = nil
  end

  -- word smoothness: the same text meter holding the same word in consecutive frames
  local seekNow = (f == atTime(52) or f == atTime(60) or f == atTime(74))
  if settled and lastWordX and not seekNow then
    for _, v in ipairs(vis) do
      local p = lastWordX[v.id]
      if p and p.text == v.text then
        local d = math.abs(v.x - p.x)
        stats.maxWordStep = math.max(stats.maxWordStep, d)
        if d > 6 then stats.bigSteps = (stats.bigSteps or 0) + 1; if stats.bigSteps < 4 then print(string.format('  big word step %.0f at t=%.2f (%s)', d, songT, v.text)) end end
      end
    end
  end
  if settled then local byId = {} for _, v in ipairs(vis) do byId[v.id] = v end lastWordX = byId else lastWordX = nil end

  -- ASCII screenshots
  if verbose and (f % 240 == 0) then
    local line = {}
    for _, v in ipairs(vis) do line[#line + 1] = string.format('%s@%d:%d', v.text, v.x - barX, v.a) end
    shots[#shots + 1] = string.format('t=%5.1f pill=[%s..%s] mode=%s title=%s | %s', songT,
      pl and string.format('%.0f', pl) or '-', pr and string.format('%.0f', pr) or '-',
      tostring(not meters.TitleText.hidden and 'fallback' or 'lyrics'),
      title, table.concat(line, ' '))
  end
end

for _, s in ipairs(shots) do print(s) end
print(string.format('frames=%d avgVisibleWords=%.1f maxVisible=%d', stats.frames, stats.sumVis / math.max(1, stats.frames), stats.maxVis))
print(string.format('max pill step/frame=%.2f px   max word step/frame=%.2f px', stats.maxPillStep, stats.maxWordStep))
print(string.format('bangs/frame avg=%.1f max=%d', stats.cmds / math.max(1, stats.frames), stats.maxCmds))
print('writes:', #writes, writes[1] and writes[1]:sub(1, 90) or '')
print('errors:', #errors)
local fin = {}
for _, k in ipairs({ 'TitleText', 'ArtistText', 'Pill', 'Background', 'CoverMask', 'Cover', 'ProgressFill', 'Vis' }) do
  local m = meters[k]
  fin[#fin + 1] = k .. '=' .. (m.hidden and 'hidden' or 'shown')
end
print(table.concat(fin, ' '))
for _, k in ipairs({ 'Background', 'CoverMask', 'Cover', 'TitleText', 'ArtistText', 'ProgressBg', 'Vis' }) do
  local m = meters[k]
  print(k, 'X=' .. tostring(m.opts.X), 'Y=' .. tostring(m.opts.Y), 'W=' .. tostring(m.opts.W), 'Shape=' .. tostring(m.opts.Shape))
end
print('TitleText Text =', meters.TitleText.opts.Text)
print('Pill Shape     =', meters.Pill.opts.Shape)
print('Pill Path      =', meters.Pill.opts.PillPath)
print('Progress fill  =', meters.ProgressFill.opts.Shape)
print('Debug text     =', (meters.DebugText.opts.Text or ''):gsub('#CRLF#', ' / '))
for i = 1, #writes do if writes[i]:find('WallAvg') then print('write:', writes[i]) end end
os.exit(#errors == 0 and 0 or 1)
