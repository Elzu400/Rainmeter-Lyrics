-- Copyright (C) 2026 Elzu400
-- SPDX-License-Identifier: GPL-3.0-or-later
-- This file is part of RainmeterLyrics, free software under the GNU GPL v3 or later (see LICENSE).

-- Headless harness for lyrics.lua: fake Rainmeter API driven by the generated ini.
-- usage: texlua mock_main.lua <tree> <classic|slim> [seconds] [verbose]
local tree, preset, seconds, verbose = arg[1], arg[2] or 'classic', tonumber(arg[3] or 80), arg[4] == 'v'

local function readFile(p) local f = assert(io.open(p, 'rb')); local s = f:read('*a'); f:close(); return s end

-- ---------- variables from Settings.inc (+ preset overrides) ----------
local VARS = {}
for line in readFile(tree .. '/RainmeterLyrics/@Resources/Settings.inc'):gmatch('[^\r\n]+') do
  local k, v = line:match('^([%w_]+)=(.*)$')
  if k then VARS[k] = v end
end
local PRESETS = {
  slim = { PillWidth = '780', PillHeight = '52', CornerRadius = '24', CoverSize = '34', CoverRadius = '11',
    Padding = '8', CoverGap = '10', FontSize = '13', ProgressHeight = '3', ProgressBottom = '5', TextNudgeY = '2',
    VisBarWidth = '3', VisGap = '3', VisHeight = '18', PillRadius = '8', PillPadX = '8', WordSpacing = '6',
    LineGap = '20', FadeZone = '60', FocusPos = '38' },
  classic = { PillWidth = '520', PillHeight = '74', CornerRadius = '20', CoverSize = '48', CoverRadius = '10',
    Padding = '13', CoverGap = '14', FontSize = '15', ProgressHeight = '3', ProgressBottom = '13', TextNudgeY = '4',
    VisBarWidth = '4', VisGap = '3', VisHeight = '28', PillRadius = '10', PillPadX = '10', WordSpacing = '6',
    LineGap = '24', FadeZone = '50', FocusPos = '40' },
}
for k, v in pairs(PRESETS[preset] or {}) do VARS[k] = v end
if os.getenv('MOCK_WORDS') then VARS.PillWords = os.getenv('MOCK_WORDS') end
if os.getenv('MOCK_DEBUG') then VARS.Debug = '1' end
if os.getenv('MOCK_ORDER') then VARS.LyricsOrder = os.getenv('MOCK_ORDER') end
if os.getenv('MOCK_WALL') then VARS.ColorMode = 'wallpaper' end
if os.getenv('MOCK_STYLE') then VARS.PillStyle = os.getenv('MOCK_STYLE') end
if os.getenv('MOCK_RIGHT') then VARS.RightPanel = os.getenv('MOCK_RIGHT') end
if os.getenv('MOCK_MODE') then VARS.LyricMode = os.getenv('MOCK_MODE') end

-- ---------- meters / measures from the ini ----------
local meters, measures, order = {}, {}, {}
do
  local ini = readFile(tree .. '/RainmeterLyrics/Lyrics/RainmeterLyrics.ini')
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
local searchRaw = ''
local provRaw = {}                    -- responses of the KuGou / NetEase measures
local band = { 0, 0, 0, 0, 0, 0, 0, 0 }

local snap = { nextS = 0.2, val = 0, k = 0 }
local function reportedPos()
  if os.getenv('MOCK_JITTER') ~= '1' then return songT end
  if songT < snap.val - 0.5 or songT > snap.val + 3 then          -- seek or pause: resync at once
    snap.val, snap.nextS = math.floor(songT), songT + 0.5
  end
  while songT >= snap.nextS do
    snap.k = snap.k + 1
    snap.val = math.floor(snap.nextS)
    local noise = math.abs((math.sin(snap.k * 12.9898) * 43758.5453) % 1)
    snap.nextS = snap.nextS + 1 + 0.4 * (noise * 2 - 1)           -- the player is polled at irregular intervals
  end
  return snap.val
end

local function mm(t) return string.format('%02d:%02d', math.floor(t / 60), math.floor(t % 60)) end

local function mk(getS, getV)
  return { GetStringValue = function() return getS() end, GetValue = function() return getV() end }
end
local MS = {
  mTitle = mk(function() return title end, function() return 0 end),
  mArtist = mk(function() return artist end, function() return 0 end),
  -- MOCK_JITTER=1: the player reports whole seconds, each one arriving up to 0.4 s late and by a
  -- different amount every second (like a real media session), so the skin's estimate wobbles.
  mPosition = mk(function() return mm(reportedPos()) end, function() return math.floor(reportedPos()) end),
  mDuration = mk(function() return '03:30' end, function() return 210 end),
  mState = mk(function() return playing and '1' or '0' end, function() return playing and 1 or 0 end),
  mProgress = mk(function() return tostring(songT / 210 * 100) end, function() return songT / 210 * 100 end),
  mCover = mk(function() return '' end, function() return 0 end),
  mLyrics = mk(function() return lyricsRaw end, function() return 0 end),
  mSearch = mk(function() return searchRaw end, function() return 0 end),
  mKgS = mk(function() return provRaw.mKgS or '' end, function() return 0 end),
  mKgL = mk(function() return provRaw.mKgL or '' end, function() return 0 end),
  mNeS = mk(function() return provRaw.mNeS or '' end, function() return 0 end),
  mNeL = mk(function() return provRaw.mNeL or '' end, function() return 0 end),
  mWall = mk(function() return '40,90,160' end, function() return 0 end),
}
for i = 1, 8 do MS['mBand' .. i] = mk(function() return '' end, function() return band[i] end) end

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

local pendingFetch, pendingWall, pendingSearch = nil, nil, nil
local pendingProv = {}
logs = {}
local PROV = { mKgS = 'OnKgSearched', mKgL = 'OnKgLyrics', mNeS = 'OnNeSearched', mNeL = 'OnNeLyrics' }
local PROV_FAIL = { mKgS = 'OnKgFailed', mKgL = 'OnKgFailed', mNeS = 'OnNeFailed', mNeL = 'OnNeFailed' }
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
    elseif t[2] == 'mSearch' and t[3] == 'Update' then pendingSearch = frame + 25
    elseif PROV[t[2]] and t[3] == 'Update' then pendingProv[#pendingProv + 1] = { m = t[2], at = frame + 22 }
    elseif t[2] == 'mWall' and t[3] == 'Run' then pendingWall = frame + 10
    else err('unexpected CommandMeasure ' .. cmd) end
  elseif b == '!Log' then
    logs[#logs + 1] = t[2]
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
if os.getenv('MOCK_FAST') then          -- a fast song: a new line every 1.1 s
  LRC = {}
  for n = 1, 60 do LRC[#LRC + 1] = { 8 + (n - 1) * 1.1, string.format('L%02dx beta gamma delta epsilon zeta', n) } end
end
local parts = {}
for _, l in ipairs(LRC) do
  parts[#parts + 1] = string.format('[%02d:%05.2f] %s', math.floor(l[1] / 60), l[1] % 60, l[2])
end
local SYNCED = table.concat(parts, '\\n')   -- the literal backslash-n JSON form

dofile(tree .. '/RainmeterLyrics/@Resources/lyrics.lua')

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
local stats = { backSteps = 0, backPx = 0, maxBack = 0, frames = 0, maxPillStep = 0, maxWordStep = 0, sumVis = 0, maxVis = 0, pillOut = 0, cmds = 0, maxCmds = 0, snaps = 0 }
local lastPillL, lastWordX, trackedWord = nil, nil, nil
local shots = {}
local events = {}
local totalFrames = math.floor(seconds * 60)

-- events: seek back at 50s (frame), pause at 30s for 2s, track change (no lyrics) at 74s
local function atTime(t) return math.floor(t * 60) end

local waitFetchFailed = false
local SEARCH_MODE = os.getenv('MOCK_SEARCH') or '1'      -- 1 = good results, 0 = empty list, e = request error
local function searchJson()
  return '[{"id":11,"trackName":"No Lyrics Here (Live)","artistName":"Nobody","duration":400.0,"instrumental":false,'
    .. '"plainLyrics":"x","syncedLyrics":"[00:01.00] wrong version"},'
    .. '{"id":22,"trackName":"No Lyrics Here","artistName":"Nobody","albumName":"A","duration":211.0,"instrumental":false,'
    .. '"plainLyrics":"x","syncedLyrics":"' .. SYNCED .. '\\n[03:25.00] extra line"},'
    .. '{"id":33,"trackName":"No Lyrics Here","artistName":"Nobody","duration":210.0,"instrumental":false,'
    .. '"plainLyrics":"p","syncedLyrics":null}]'
end
local function b64enc(d)
  local abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local out = {}
  for i = 1, #d, 3 do
    local a, b, c = d:byte(i, i + 2)
    local v = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = math.floor(v / 262144) % 64, math.floor(v / 4096) % 64, math.floor(v / 64) % 64, v % 64
    out[#out + 1] = abc:sub(c1 + 1, c1 + 1) .. abc:sub(c2 + 1, c2 + 1)
      .. (b and abc:sub(c3 + 1, c3 + 1) or '=') .. (c and abc:sub(c4 + 1, c4 + 1) or '=')
  end
  return table.concat(out)
end
-- MOCK_SRC = kugou | netease | yrc | none : which fallback provider "has" the lyrics
local SRC = os.getenv('MOCK_SRC') or 'none'
local YRC_LINES = {}
for i = 0, 11 do
  local t0 = i * 2000
  YRC_LINES[#YRC_LINES + 1] = string.format('[%d,1800](%d,400,0)Hel(%d,400,0)lo (%d,500,0)my (%d,400,0)dear (%d,500,0)friend',
    t0, t0, t0 + 400, t0 + 800, t0 + 1300, t0 + 1700)
end
local YRC = '{\\"t\\":0,\\"c\\":[{\\"tx\\":\\"credit: x\\"}]}\\n' .. table.concat(YRC_LINES, '\\n')
local function provResponse(m)
  if m == 'mKgS' then
    if SRC ~= 'kugou' then return '{"status":200,"info":"OK","candidates":[]}' end
    return '{"status":200,"info":"OK","errcode":200,"keyword":"x","candidates":[{"id":"111","product_from":"x","accesskey":"AAA",'
      .. '"singer":"' .. artist .. '","song":"' .. title .. ' (Live)","duration":400000,"score":50},'
      .. '{"id":"222","product_from":"y","accesskey":"B/B+","singer":"' .. artist .. '","song":"' .. title .. '","duration":210000,"score":40}]}'
  elseif m == 'mKgL' then
    local lrc = SYNCED:gsub('\\n', '\n')
    return '{"status":200,"content":"' .. b64enc('\239\187\191' .. lrc):gsub('/', '\\/') .. '","fmt":"lrc"}'
  elseif m == 'mNeS' then
    if SRC ~= 'netease' and SRC ~= 'yrc' then return '{"result":{"songs":[],"songCount":0},"code":200}' end
    return '{"result":{"songs":[{"id":900,"name":"Other Song","artists":[{"id":1,"name":"Nobody"}],"album":{"id":2,"name":"A"},"duration":300000},'
      .. '{"id":901,"name":"' .. title .. '","artists":[{"id":1,"name":"' .. artist .. '","picUrl":null}],"album":{"id":2,"name":"A"},"duration":210000}],"songCount":2},"code":200}'
  else
    if SRC == 'yrc' then
      return '{"sgc":false,"lrc":{"version":3,"lyric":"[00:00.00] fallback line"},"yrc":{"version":2,"lyric":"' .. YRC .. '"},"code":200}'
    end
    return '{"sgc":false,"lrc":{"version":3,"lyric":"' .. SYNCED .. '"},"code":200}'
  end
end
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
  band = {}
  for i = 1, 8 do band[i] = 0.5 + 0.45 * math.sin(clock * (2 + i)) end

  local ok, e = pcall(Update)
  if not ok then err('Update crashed at frame ' .. f .. ': ' .. tostring(e)); break end
  local n0 = bangCount
  flush()

  if pendingFetch and f >= pendingFetch then
    pendingFetch = nil
    if waitFetchFailed or os.getenv('MOCK_GET') == '0' then lyricsRaw = ''; ok, e = pcall(OnFailed) else lyricsRaw = SYNCED; ok, e = pcall(OnFetched) end
    if not ok then err('OnFetched crashed: ' .. tostring(e)) end
    flush()
  end
  if pendingSearch and f >= pendingSearch then
    pendingSearch = nil
    if SEARCH_MODE == 'e' then ok, e = pcall(OnSearchFailed)
    else
      searchRaw = (SEARCH_MODE == '0') and '[]' or searchJson()
      ok, e = pcall(OnSearched)
    end
    if not ok then err('OnSearched crashed: ' .. tostring(e)) end
    flush()
  end
  for i = #pendingProv, 1, -1 do
    local pp = pendingProv[i]
    if f >= pp.at then
      table.remove(pendingProv, i)
      provRaw[pp.m] = provResponse(pp.m)
      if SRC == 'err' then ok, e = pcall(_G[PROV_FAIL[pp.m]]) else ok, e = pcall(_G[PROV[pp.m]]) end
      if not ok then err(PROV[pp.m] .. ' crashed: ' .. tostring(e)) end
      flush()
    end
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
  if os.getenv('MOCK_FAST') and songT > 0 then
    for _, v in ipairs(vis) do
      local n = tonumber(v.text:match('^L(%d+)x$'))
      if n and n >= 2 then
        FAST = FAST or {}
        local r = FAST[n] or {}
        FAST[n] = r
        local rel = songT - (8 + (n - 1) * 1.1)
        if not r.first then r.first = rel end
        if not r.full and v.a >= 112 then r.full = rel end
      end
    end
  end
  local settled = (songT > 12 and not pill.hidden and pl)
  if settled then
    stats.sumVis = stats.sumVis + #vis
    stats.maxVis = math.max(stats.maxVis, #vis)
    -- track pill motion (only while no seek happened this frame)
    local seekFrame = (f == atTime(52) or f == atTime(60) or f == atTime(74))
    local pa = tonumber((pill.opts.Shape or ''):match('Fill Color %d+,%d+,%d+,(%d+)')) or 0
    if lastPillL and not seekFrame and pa >= 100 and (lastPa or 0) >= 100 then
      stats.maxPillStep = math.max(stats.maxPillStep, math.abs(pl - lastPillL))
      if pl < lastPillL - 0.05 then
        stats.backSteps = stats.backSteps + 1
        stats.backPx = stats.backPx + (lastPillL - pl)
        stats.maxBack = math.max(stats.maxBack, lastPillL - pl)
      end
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
if FAST then
  local f, u, c = {}, {}, 0
  for n, r in pairs(FAST) do if n < 50 and r.first and r.full then f[#f + 1] = r.first; u[#u + 1] = r.full end end
  table.sort(f); table.sort(u)
  if #f > 0 then
    print(string.format('fast lines (%d): new line first visible %.2fs (median) / %.2fs (worst) after its first word; fully visible %.2fs / %.2fs',
      #f, f[math.ceil(#f / 2)], f[#f], u[math.ceil(#u / 2)], u[#u]))
  end
end
print(string.format('pill moved backwards: %d frames, %.1f px total, worst %.2f px/frame', stats.backSteps, stats.backPx, stats.maxBack))
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
for _, l in ipairs(logs) do print('log: ' .. l) end
print('Debug text     =', (meters.DebugText.opts.Text or ''):gsub('#CRLF#', ' / '))
for i = 1, #writes do if writes[i]:find('WallAvg') then print('write:', writes[i]) end end
-- playback buttons
if os.getenv('MOCK_RIGHT') then
  local function btns()
    for _, k in ipairs({ 'BtnPrev', 'BtnPlay', 'BtnNext' }) do
      local m = meters[k]
      print(k, m.hidden and 'hidden' or 'shown', 'X=' .. tostring(m.opts.X), 'Y=' .. tostring(m.opts.Y),
        'bg=' .. tostring(m.opts.Shape), 'icon=' .. tostring(m.opts.Shape2):sub(1, 60))
    end
  end
  print('Right side =', VARS.RightPanel, ' Vis ' .. (meters.Vis.hidden and 'hidden' or 'shown'),
    ' progress bar W=' .. tostring(meters.ProgressBg.opts.Shape):match('Rectangle 0,0,(%d+)'))
  btns()
  Hover('play'); Update(); flush()
  print('after Hover(play):'); btns()
  Hover(''); Update(); flush()

  if os.getenv('MOCK_RIGHT') == 'combined' then
    local function run(sec) for _ = 1, math.floor(sec * 60) do clock = clock + 1 / 60; Update(); flush() end end
    local function st(tag)
      print(string.format('  %-24s Vis=%s zone=%s buttons=%s', tag, meters.Vis.hidden and 'hidden' or 'shown',
        meters.CtlZone.hidden and 'hidden' or 'shown', meters.BtnPlay.hidden and 'hidden' or 'shown'))
    end
    run(2.5); st('idle')
    Hover('zone'); run(0.5); st('hover zone 0.5s')
    Hover('next'); run(0.3); st('hover next')
    Hover(''); run(0.8); st('left 0.8s ago')
    run(1.5); st('left 2.3s ago')
    Hover('zone'); run(0.4); Hover(''); run(2.0); st('re-hover then leave')
    run(0.1)
    local maxR, n = 0, 0
    for i = 1, 8 do
      local sh = meters.Vis.opts[i == 1 and 'Shape' or ('Shape' .. i)]
      local x, w = tostring(sh):match('Rectangle (%d+),[%d%.]+,(%d+),')
      if x and tonumber(w) > 1 then n = n + 1; maxR = math.max(maxR, tonumber(x) + tonumber(w)) end
    end
    print('  visualizer bars=' .. n .. ' width=' .. maxR .. 'px  (button area ' .. (tonumber(meters.CtlZone.opts.Shape:match('Rectangle 0,0,(%d+)')) - 12) .. 'px)')
    print('  bar W=' .. tostring(meters.ProgressBg.opts.Shape):match('Rectangle 0,0,(%d+)'),
      'Vis X=' .. tostring(meters.Vis.opts.X), 'zone X=' .. tostring(meters.CtlZone.opts.X))
  end
end
os.exit(#errors == 0 and 0 or 1)
