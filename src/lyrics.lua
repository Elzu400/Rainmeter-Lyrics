-- Copyright (C) 2026 Elzu400
-- SPDX-License-Identifier: GPL-3.0-or-later
-- This file is part of RainmeterLyrics, free software under the GNU GPL v3 or later (see LICENSE).

-- Rainmeter Lyrics v5 - main script (Lua 5.1, as embedded in Rainmeter)
--
-- Keep this file ASCII. The packager saves it as UTF-16LE with a BOM, which is what
-- makes Rainmeter treat every string (titles, lyrics, the note symbol) as Unicode.
--
-- How the lyric strip works
--   * Every lyric line is split into words, each word gets an estimated start time.
--   * All words sit on one long horizontal "world" line (lines separated by a larger gap).
--   * A "camera" glides along that line, following the current word continuously
--     (critically damped spring), so the text never steps or jumps.
--   * The highlight pill is a second spring that follows the current word/group.
--   * Words are drawn by a ring of N text meters; each word fades in as it enters from the
--     right edge and fades out at the left edge, so no clipping is needed.

local N = 40                         -- text meters S1..SN, used as a ring
local NOTE = '\226\153\172'          -- U+266C (beamed notes), as UTF-8 bytes
local floor, ceil, min, max, exp, abs = math.floor, math.ceil, math.min, math.max, math.exp, math.abs

local PAST_ALPHA, FUTURE_ALPHA = 105, 190

local C, L, K = {}, {}, {}           -- settings, computed layout, colours
local ready, frame, lastFrame = false, 0, nil

local mTitle, mArtist, mPosition, mDuration, mState, mProgress, mLyrics, mWall
local bandM, segM, S = {}, {}, {}

-- lyric model
local words, wx, ww, wg = {}, {}, {}, {}   -- words, world x, measured width, group index
local gFirst, gLast, gT0 = {}, {}, {}      -- highlight groups
local act = {}                              -- per-word highlight amount 0..1
local nw = 0
local dirty = false

-- camera / pill springs
local cam, camV = nil, 0
local pillL, pillR, pillLv, pillRv = 0, 0, 0, 0
local appear, startClock, lastGi = 0, 0, nil
local lastPill, lastFill = nil, nil

-- paged mode: one lyric line ("page") at a time
local pF, pL = {}, {}                 -- first / last word index of the page each word belongs to
local curPage, pgFade, pgStart, pgReady, pgSnap = nil, 0, 0, false, true
local pgScreenR, pgScreenL = nil, nil  -- on-screen position of the pill's edges last frame
local PAGE_PAST, PAGE_FUTURE = 235, 125
local OUT_MAX, IN_MAX = 0.14, 0.22    -- longest cross-fade seconds between lines (shorter for fast lines)

-- lyrics download
local waiting, lastRaw = false, nil
local curTitle, curArtist = nil, nil
local seenSince, fetchPending, waitSince = 0, false, 0
local trigF, trigM, updF, updM, enabledOnce = nil, 'mLyrics', nil, nil, {}
local Q = { stage = 0, title = '', artist = '', dur = 0, src = '-', pick = '' }   -- current lyrics request

-- player time
local lastPos, lastClock, disp, firstTime, wasPlaying = -1, 0, 0, true, false
local lastProg = nil
local curMode = nil                  -- true = lyric strip, false = title/artist

-- wallpaper colour
local wall, lastWallRun = nil, nil

-- visualizer
local vis = { h = { 0, 0, 0, 0, 0, 0, 0, 0 }, key = nil }

-- playback buttons (slim layout only); each is a Shape meter that the ini defines
local BTN = { 'BtnPrev', 'BtnPlay', 'BtnNext' }
local ctl = { key = nil, hover = nil, a = 0, seen = -1e9, on = nil }   -- a: 0 = hidden .. 1 = fully shown

-- debug
local lastDbg, dbgCur = 0, '-'

-- ---------- small helpers ----------

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end
local function round(v) return floor(v + 0.5) end
local function smooth01(u)
  u = clamp(u, 0, 1)
  return u * u * (3 - 2 * u)
end

local function var(name, default)
  local v = SKIN:GetVariable(name, default)
  if v == nil or v == '' then return default end
  return v
end
local function num(name, default)
  return tonumber(var(name, tostring(default))) or default
end

local function parseRGB(s, dr, dg, db)
  local r, g, b = tostring(s or ''):match('(%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
  if not r then return dr, dg, db end
  return clamp(tonumber(r), 0, 255), clamp(tonumber(g), 0, 255), clamp(tonumber(b), 0, 255)
end

local function rgb2hsl(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = max(r, g, b), min(r, g, b)
  local l = (mx + mn) / 2
  if mx == mn then return 0, 0, l end
  local d = mx - mn
  local s
  if l > 0.5 then s = d / (2 - mx - mn) else s = d / (mx + mn) end
  local h
  if mx == r then
    h = (g - b) / d
    if g < b then h = h + 6 end
  elseif mx == g then
    h = (b - r) / d + 2
  else
    h = (r - g) / d + 4
  end
  return h / 6, s, l
end

local function hue2rgb(p, q, t)
  if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
  if t < 1 / 6 then return p + (q - p) * 6 * t end
  if t < 1 / 2 then return q end
  if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
  return p
end

local function hsl2rgb(h, s, l)
  if s == 0 then
    local v = round(l * 255)
    return v, v, v
  end
  local q
  if l < 0.5 then q = l * (1 + s) else q = l + s - l * s end
  local p = 2 * l - q
  return round(hue2rgb(p, q, h + 1 / 3) * 255),
         round(hue2rgb(p, q, h) * 255),
         round(hue2rgb(p, q, h - 1 / 3) * 255)
end

local function luminance(r, g, b)
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
end

-- critically damped spring (same maths as Unity's SmoothDamp)
local function smoothDamp(cur, target, vel, smoothTime, dt)
  local omega = 2 / max(smoothTime, 0.0001)
  local x = omega * dt
  local e = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
  local change = cur - target
  local temp = (vel + omega * change) * dt
  vel = (vel - omega * temp) * e
  return target + (change + temp) * e, vel
end

-- number of characters in a UTF-8 string
local function nchars(s)
  local _, n = s:gsub('[^\128-\191]', '')
  return n
end

-- Safe to embed inside a Rainmeter bang
local function clean(text)
  text = text:gsub('"', "'"):gsub('%[', '('):gsub('%]', ')'):gsub('#', '')
  return text
end

local function urlenc(s)
  return (s:gsub('[^%w%-_%.~]', function(c) return string.format('%%%02X', c:byte()) end))
end

-- ---------- settings, layout, colours ----------

local function loadConfig()
  C.W           = num('PillWidth', 520)
  C.H           = num('PillHeight', 74)
  C.corner      = num('CornerRadius', 20)
  C.showCover   = num('ShowCover', 1) ~= 0
  C.coverSize   = num('CoverSize', 48)
  C.coverRadius = num('CoverRadius', 10)
  C.pad         = num('Padding', 13)
  C.coverGap    = num('CoverGap', 14)
  C.fontSize    = num('FontSize', 15)
  C.showProg    = num('ShowProgress', 1) ~= 0
  C.progH       = num('ProgressHeight', 3)
  C.progBottom  = num('ProgressBottom', 13)
  C.nudgeY      = num('TextNudgeY', 4)
  -- right-hand panel: 'vis' (visualizer), 'controls' (prev / play-pause / next) or 'off'.
  -- Controls need the slim layout; on a taller bar the visualizer is shown instead.
  -- 'combined' shows the visualizer and swaps to the controls while the mouse is over it.
  C.right       = var('RightPanel', (num('ShowVis', 1) ~= 0) and 'vis' or 'off')
  if C.right ~= 'controls' and C.right ~= 'combined' and C.right ~= 'off' then C.right = 'vis' end
  local slim    = C.H < 60
  C.combo       = (C.right == 'combined') and slim
  C.showCtl     = ((C.right == 'controls') or (C.right == 'combined')) and slim
  C.showVis     = (C.right == 'vis') or C.combo or ((C.right == 'controls' or C.right == 'combined') and not slim)
  C.ctlHold     = max(0, num('CtlHold', 1500) / 1000)
  C.ctlS        = min(26, max(16, C.H - 16))
  C.ctlGap      = 2
  C.visBarW     = num('VisBarWidth', 4)
  C.visGap      = num('VisGap', 3)
  C.visH        = num('VisHeight', 28)
  C.mode        = (var('LyricMode', 'paged') == 'legacy') and 'legacy' or 'paged'
  C.pageWords   = max(1, floor(num('PageWords', 2)))
  C.pillWords   = max(1, floor(num('PillWords', 1)))
  C.pillStyle   = floor(num('PillStyle', 0))
  C.pillRadius  = num('PillRadius', 10)
  C.padX        = num('PillPadX', 10)
  C.padY        = num('PillPadY', 2)
  C.spacing     = num('WordSpacing', 6)
  C.lineGap     = num('LineGap', 24)
  C.fade        = max(0, num('FadeZone', 50))
  C.focus       = clamp(num('FocusPos', 40), 10, 80) / 100
  C.camST       = max(0.05, num('CamSmooth', 450) / 1000)
  C.pillST      = max(0.02, num('PillSpeed', 110) / 1000)
  C.offset      = num('LyricsOffset', 0)
  C.posUnit     = num('PositionUnit', 1)
  if C.posUnit == 0 then C.posUnit = 1 end
  C.colorMode   = var('ColorMode', 'manual')
  C.wallSat     = clamp(num('WallMinSat', 45), 0, 100) / 100
  C.wallTint    = num('WallTintBg', 1) ~= 0
  C.wallEvery   = num('WallRefreshMin', 0) * 60
  C.debug       = num('Debug', 0) ~= 0
  C.estChar     = C.fontSize * 96 / 72 * 0.58   -- rough px per character until measured

  local r, g, b = tostring(var('WallAvg', '')):match('^(%d+),(%d+),(%d+)$')
  if r then wall = { tonumber(r), tonumber(g), tonumber(b) } end
end

local function computeLayout()
  L.W, L.H = C.W, C.H
  L.cover = C.showCover
  L.coverX = C.pad
  L.coverY = round((C.H - C.coverSize) / 2)
  L.barX = C.pad + (C.showCover and (C.coverSize + C.coverGap) or 0)
  L.ctlW = C.showCtl and (3 * C.ctlS + 2 * C.ctlGap) or 0
  -- visualizer bars: 4 normally; 8 thinner-spaced ones that fill the button area in combined mode
  L.visN, L.vBar, L.vGap = 4, C.visBarW, C.visGap
  if C.combo then
    L.visN = 8
    L.vGap = max(C.visGap, round(C.ctlS * 0.15))
    L.vBar = max(2, floor((L.ctlW - 7 * L.vGap) / 8))
  end
  L.visW = C.showVis and (L.visN * L.vBar + (L.visN - 1) * L.vGap) or 0
  L.visX = C.W - C.pad - L.visW
  L.ctlX = C.W - C.pad - L.ctlW
  L.ctlY = round(C.H / 2 - C.ctlS / 2)
  local right = C.W - C.pad
  if C.combo then
    L.visX = L.ctlX + round((L.ctlW - L.visW) / 2)     -- visualizer sits centred in the button area
    right = L.ctlX - 10
  elseif C.showVis then right = L.visX - 14
  elseif C.showCtl then right = L.ctlX - 10 end
  L.barW = max(80, right - L.barX)
  L.boxH = round(C.fontSize * 2)
  L.progY = C.H - C.progBottom - C.progH
  local regionBottom = C.showProg and L.progY or C.H
  L.boxY = round((regionBottom - L.boxH) / 2 + (C.showProg and C.nudgeY or 0))
  L.pillH = max(8, L.boxH - 2 * C.padY)
  L.visY = round(C.H / 2 - C.visH / 2)
  L.compact = C.H < 60
end

local function computeColors()
  local tr, tg, tb = parseRGB(var('TextColor', '255,255,255'), 255, 255, 255)
  local br, bg, bb = parseRGB(var('BgColor', '20,18,28'), 20, 18, 28)
  local ar, ag, ab = parseRGB(var('AccentColor', '150,110,255'), 150, 110, 255)

  if C.colorMode == 'wallpaper' and wall then
    local h, s, l = rgb2hsl(wall[1], wall[2], wall[3])
    if s > 0.06 then
      local s2 = max(s, C.wallSat)
      ar, ag, ab = hsl2rgb(h, s2, clamp(l, 0.42, 0.56))
      if C.wallTint then
        br, bg, bb = hsl2rgb(h, min(s2, 0.38), 0.09)
      end
    end
  end

  K.text = { tr, tg, tb }
  K.textStr = tr .. ',' .. tg .. ',' .. tb
  K.bg = br .. ',' .. bg .. ',' .. bb
  K.bgA = clamp(round(num('BgAlpha', 190)), 0, 255)
  K.accent = { ar, ag, ab }
  K.accentStr = ar .. ',' .. ag .. ',' .. ab
  K.pillA = clamp(round(num('PillAlpha', 235)), 0, 255)
  local lr = round(ar + (255 - ar) * 0.4)
  local lg = round(ag + (255 - ag) * 0.4)
  local lb = round(ab + (255 - ab) * 0.4)
  K.light = lr .. ',' .. lg .. ',' .. lb
  if luminance(ar, ag, ab) > 0.62 then
    K.active = { 24, 20, 34 }          -- dark text on a light pill
  else
    K.active = { tr, tg, tb }
  end
end

local function bgBang()
  return string.format(
    '[!SetOption Background Shape "Rectangle 0,0,%d,%d,%d | Fill Color %s,%d | StrokeWidth 0"]',
    L.W, L.H, C.corner, K.bg, K.bgA)
end

local function showFallback(show)
  local v = show and '!ShowMeter ' or '!HideMeter '
  local b = '[' .. v .. 'TitleText]'
  if show and not L.compact then
    b = b .. '[!ShowMeter ArtistText]'
  else
    b = b .. '[!HideMeter ArtistText]'
  end
  return b
end

local function applyLayout()
  local b = {}
  b[#b + 1] = bgBang()

  -- cover (rounded through a mask container)
  if L.cover then
    b[#b + 1] = string.format('[!ShowMeter CoverMask][!ShowMeter Cover][!SetOption CoverMask X %d][!SetOption CoverMask Y %d]',
      L.coverX, L.coverY)
    b[#b + 1] = string.format('[!SetOption CoverMask Shape "Rectangle 0,0,%d,%d,%d | Fill Color 0,0,0,255 | StrokeWidth 0"]',
      C.coverSize, C.coverSize, C.coverRadius)
    b[#b + 1] = string.format('[!SetOption Cover W %d][!SetOption Cover H %d]', C.coverSize, C.coverSize)
  else
    b[#b + 1] = '[!HideMeter CoverMask][!HideMeter Cover]'
  end

  -- title / artist fallback
  local regionBottom = C.showProg and L.progY or C.H
  if L.compact then
    b[#b + 1] = string.format(
      '[!SetOption TitleText X %d][!SetOption TitleText Y %d][!SetOption TitleText W %d][!SetOption TitleText H %d]' ..
      '[!SetOption TitleText StringAlign LeftCenter][!SetOption TitleText FontSize %d]' ..
      '[!SetOption TitleText Text "%%1  -  %%2"]',
      L.barX, L.boxY + round(L.boxH / 2), L.barW, L.boxH, max(9, round(C.fontSize - 1)))
  else
    local tfs = max(9, round(C.fontSize - 1))
    local afs = max(8, round(C.fontSize * 0.73))
    local th, ah = round(tfs * 1.75), round(afs * 1.75)
    local top = round((regionBottom - (th + 2 + ah)) / 2 + 3)
    b[#b + 1] = string.format(
      '[!SetOption TitleText X %d][!SetOption TitleText Y %d][!SetOption TitleText W %d][!SetOption TitleText H %d][!SetOption TitleText FontSize %d]',
      L.barX, top, L.barW, th, tfs)
    b[#b + 1] = string.format(
      '[!SetOption ArtistText X %d][!SetOption ArtistText Y %d][!SetOption ArtistText W %d][!SetOption ArtistText H %d][!SetOption ArtistText FontSize %d]',
      L.barX, top + th + 2, L.barW, ah, afs)
  end

  -- progress bar
  if C.showProg then
    b[#b + 1] = string.format(
      '[!ShowMeter ProgressBg][!ShowMeter ProgressFill][!SetOption ProgressBg X %d][!SetOption ProgressBg Y %d]' ..
      '[!SetOption ProgressFill X %d][!SetOption ProgressFill Y %d]',
      L.barX, L.progY, L.barX, L.progY)
    b[#b + 1] = string.format(
      '[!SetOption ProgressBg Shape "Rectangle 0,0,%d,%d,%.1f | Fill Color 255,255,255,28 | StrokeWidth 0"]',
      L.barW, C.progH, C.progH / 2)
  else
    b[#b + 1] = '[!HideMeter ProgressBg][!HideMeter ProgressFill]'
  end

  -- lyric strip meters
  b[#b + 1] = string.format('[!SetOption Pill X %d][!SetOption Pill Y %d]', L.barX, L.boxY)
  local ty = L.boxY + round(L.boxH / 2)
  for m = 1, N do
    b[#b + 1] = string.format('[!SetOption S%d Y %d]', m, ty)
  end

  -- visualizer
  if C.showVis then
    b[#b + 1] = string.format('[!ShowMeter Vis][!SetOption Vis X %d][!SetOption Vis Y %d]', L.visX, L.visY)
  else
    b[#b + 1] = '[!HideMeter Vis]'
  end

  -- playback buttons (in combined mode they appear on hover, see drawCtl)
  ctl.on = nil
  for i, name in ipairs(BTN) do
    if C.showCtl then
      b[#b + 1] = string.format('[!SetOption %s X %d][!SetOption %s Y %d]%s',
        name, L.ctlX + (i - 1) * (C.ctlS + C.ctlGap), name, L.ctlY,
        C.combo and ('[!HideMeter ' .. name .. ']') or ('[!ShowMeter ' .. name .. ']'))
    else
      b[#b + 1] = '[!HideMeter ' .. name .. ']'
    end
  end
  if C.combo then
    ctl.a = 0
    b[#b + 1] = string.format('[!SetOption CtlZone X %d][!SetOption CtlZone Y 0]', L.ctlX - 6)
    b[#b + 1] = string.format('[!SetOption CtlZone Shape "Rectangle 0,0,%d,%d | Fill Color 255,255,255,1 | StrokeWidth 0"]',
      L.ctlW + 12, C.H)
    b[#b + 1] = '[!ShowMeter CtlZone]'
  else
    ctl.a = C.showCtl and 1 or 0
    b[#b + 1] = '[!HideMeter CtlZone]'
  end
  vis.on = nil

  b[#b + 1] = string.format('[!SetOption DebugText Y %d]', C.H + 6)
  if C.debug then b[#b + 1] = '[!ShowMeter DebugText]' end
  b[#b + 1] = '[!UpdateMeter *][!Redraw]'
  SKIN:Bang(table.concat(b))
end

local function forceRedrawState()
  lastProg, lastPill, lastFill, vis.key = nil, nil, nil, nil
  ctl.key = nil
  for m = 1, N do if S[m] then S[m].col = nil end end
end

local function recolor()
  computeColors()
  forceRedrawState()
  SKIN:Bang(bgBang() .. '[!UpdateMeter Background][!Redraw]')
end

-- ---------- LRC parsing ----------

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + floor(cp / 64), 0x80 + cp % 64)
  else
    return string.char(0xE0 + floor(cp / 4096), 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
  end
end

local function unescape(s)
  -- surrogate pairs (emoji etc.) first, then plain \uXXXX
  s = s:gsub('\\u([dD][89abAB]%x%x)\\u([dD][c-fC-F]%x%x)', function(hi, lo)
    local cp = 0x10000 + (tonumber(hi, 16) - 0xD800) * 0x400 + (tonumber(lo, 16) - 0xDC00)
    return string.char(0xF0 + floor(cp / 262144),
                       0x80 + floor(cp / 4096) % 64,
                       0x80 + floor(cp / 64) % 64,
                       0x80 + cp % 64)
  end)
  s = s:gsub('\\u(%x%x%x%x)', function(h) return utf8char(tonumber(h, 16)) end)
  s = s:gsub('\\(.)', function(c)
    if c == 'n' then return '\n'
    elseif c == 'r' or c == 't' then return ' '
    else return c end
  end)
  return s
end

-- join word pieces into display words: a word ends at whitespace; pieces without any
-- (syllables, single CJK characters) are glued together until a few characters are collected
local function mergeToks(toks)
  local wt, cur, ct = {}, '', nil
  for _, k in ipairs(toks) do
    local str = k.s
    if cur ~= '' and str:find('^%s') then wt[#wt + 1] = { t = ct, text = cur }; cur, ct = '', nil end
    local core = (str:gsub('^%s+', ''):gsub('%s+$', ''))
    if core ~= '' then
      if not ct then ct = k.t end
      cur = cur .. core
    end
    if cur ~= '' and (str:find('%s$') or (cur:byte(1) >= 224 and nchars(cur) >= 3)) then
      wt[#wt + 1] = { t = ct, text = cur }; cur, ct = '', nil
    end
  end
  if cur ~= '' then wt[#wt + 1] = { t = ct, text = cur } end
  return wt
end

local function wtText(wt)
  local b = {}
  for i, w in ipairs(wt) do b[i] = w.text end
  return table.concat(b, ' ')
end

-- LRC text -> { {t=, text=, wt=optional word list}, ... }. Understands "enhanced" LRC word
-- tags (<mm:ss.xx>word). noEsc = the text is not JSON-escaped.
local function parseLRC(raw, noEsc)
  local out = {}
  local s = noEsc and raw or unescape(raw)
  s = s:gsub('^\239\187\191', '')
  for line in (s .. '\n'):gmatch('(.-)\n') do
    local times, text = {}, line
    while true do
      local m, sec, rest = text:match('^%s*%[(%d+):(%d+%.?%d*)%](.*)$')
      if not m then break end
      times[#times + 1] = tonumber(m) * 60 + tonumber(sec)
      text = rest
    end
    if #times > 0 then
      local wt
      if #times == 1 and text:find('<%d+:%d+%.?%d*>') then
        local toks = {}
        local pre = text:match('^([^<]*)')
        if pre and pre:find('%S') then toks[1] = { t = times[1], s = pre } end
        for a, b, w in text:gmatch('<(%d+):(%d+%.?%d*)>([^<]*)') do
          toks[#toks + 1] = { t = tonumber(a) * 60 + tonumber(b), s = w }
        end
        wt = mergeToks(toks)
        if #wt == 0 then wt = nil else text = wtText(wt) end
      end
      text = text:gsub('<%d+:%d+%.?%d*>', ''):gsub('^%s+', ''):gsub('%s+$', '')
      for _, t in ipairs(times) do out[#out + 1] = { t = t, text = text, wt = wt } end
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end

-- NetEase word-timed lyrics: [start_ms,dur_ms](start_ms,dur_ms,0)word(...)word ...
local function parseYRC(raw)
  local out = {}
  for line in (unescape(raw) .. '\n'):gmatch('(.-)\n') do
    local body = line:match('^%[%d+,%d+%](.*)$')
    if body then
      local toks = {}
      for st, w in body:gmatch('%((%d+),%d+,%-?%d+%)([^%(]*)') do
        toks[#toks + 1] = { t = tonumber(st) / 1000, s = w }
      end
      local wt = mergeToks(toks)
      if #wt > 0 then out[#out + 1] = { t = wt[1].t, text = wtText(wt), wt = wt } end
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end

-- true for empty lines and lines that are only note symbols / punctuation
local function isPause(text)
  local s = text:gsub('\226\153[\169-\172]', ''):gsub('[%s%p]', '')
  return s == ''
end

-- ---------- word model ----------

local function buildWords(parsed)
  local W = {}
  local function pushNote(t, line)
    local last = W[#W]
    if last and last.text == NOTE then return end
    W[#W + 1] = { t = t, text = NOTE, line = line }
  end

  if #parsed > 0 and parsed[1].t > 0.5 then pushNote(0, 0) end

  for i, ln in ipairs(parsed) do
    local nextT = parsed[i + 1] and parsed[i + 1].t or (ln.t + 6)
    local gap = nextT - ln.t
    if isPause(ln.text) then
      pushNote(ln.t, i)
    elseif ln.wt then
      for _, w in ipairs(ln.wt) do W[#W + 1] = { t = w.t, text = w.text, line = i } end
    else
      local ws, wt, total = {}, {}, 0
      for w in ln.text:gmatch('%S+') do
        ws[#ws + 1] = w
        local weight = nchars(w) + 1.5
        wt[#wt + 1] = weight
        total = total + weight
      end
      -- the words are spread over most of the gap, but not over very long instrumental gaps
      local D = max(0.25, min(gap - 0.12, #ws * 0.6 + 0.8))
      local acc = 0
      for j = 1, #ws do
        W[#W + 1] = { t = ln.t + D * acc / total, text = ws[j], line = i }
        acc = acc + wt[j]
      end
    end
  end

  for k = 2, #W do
    if W[k].t <= W[k - 1].t then W[k].t = W[k - 1].t + 0.02 end
  end
  return W
end

local function buildGroups()
  gFirst, gLast, gT0, wg = {}, {}, {}, {}
  local k = 1
  while k <= nw do
    local line = words[k].line
    local j = k
    while j < nw and words[j + 1].line == line do j = j + 1 end
    local count = j - k + 1
    local n = ceil(count / C.pillWords)
    local size = ceil(count / n)
    local s = k
    while s <= j do
      local e = min(s + size - 1, j)
      local g = #gFirst + 1
      gFirst[g], gLast[g], gT0[g] = s, e, words[s].t
      for q = s, e do wg[q] = g end
      s = e + 1
    end
    k = j + 1
  end
end

-- page = all words of one lyric line (a pause note is a page of its own)
local function buildPages()
  pF, pL = {}, {}
  local k = 1
  while k <= nw do
    local line = words[k].line
    local j = k
    while j < nw and words[j + 1].line == line do j = j + 1 end
    for q = k, j do pF[q], pL[q] = k, j end
    k = j + 1
  end
end

local function estW(k)
  return nchars(words[k].text) * C.estChar
end

local function relayout()
  dirty = false
  local x = 0
  for k = 1, nw do
    if k > 1 then
      if words[k].line == words[k - 1].line then x = x + C.spacing else x = x + C.lineGap end
    end
    wx[k] = x
    x = x + (ww[k] or estW(k))
  end
end

local function groupRect(g)
  local a, b = gFirst[g], gLast[g]
  return wx[a] - C.padX, wx[b] + (ww[b] or estW(b)) + C.padX
end

local function groupCenter(g)
  local a, b = gFirst[g], gLast[g]
  return (wx[a] + wx[b] + (ww[b] or estW(b))) / 2
end

local function findGroup(t)
  local lo, hi, idx = 1, #gT0, 1
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if gT0[mid] <= t then idx = mid; lo = mid + 1 else hi = mid - 1 end
  end
  return idx
end

-- index of the word being sung at time t
local function findWord(t)
  local lo, hi, idx = 1, nw, 1
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if words[mid].t <= t then idx = mid; lo = mid + 1 else hi = mid - 1 end
  end
  return idx
end

local function resetLayout()
  wx, ww, act = {}, {}, {}
  cam, camV, lastGi = nil, 0, nil
  curPage, pgFade, pgReady, pgSnap = nil, 0, false, true
  pgScreenR, pgScreenL = nil, nil
  appear, startClock = 0, os.clock()
  lastPill, lastFill = nil, nil
  for m = 1, N do S[m] = {} end
end

local function setMode(lyr)
  if curMode == lyr then return end
  curMode = lyr
  local verb = lyr and '!ShowMeter ' or '!HideMeter '
  local b = { '[', verb, 'Pill]' }
  for m = 1, N do
    b[#b + 1] = '[' .. verb .. 'S' .. m .. ']'
    if S[m] then S[m].vis = lyr end
  end
  b[#b + 1] = showFallback(not lyr)
  b[#b + 1] = '[!Redraw]'
  SKIN:Bang(table.concat(b))
end

local function loadWords(parsed)
  words = buildWords(parsed)
  nw = #words
  buildGroups()
  buildPages()
  resetLayout()
  dirty = true
end

local function clearWords()
  words, gFirst, gLast, gT0, wg = {}, {}, {}, {}, {}
  pF, pL = {}, {}
  nw = 0
  resetLayout()
end

-- ---------- pill + visualizer drawing ----------

local function pillPath(x, w)
  local y, h = C.padY, L.pillH
  local e, q
  if C.pillStyle == 2 then
    e, q = h / 2, 0.4477            -- capsule
  elseif C.pillStyle == 1 then
    e, q = C.pillRadius, 0.4477     -- ordinary rounded rectangle
  else
    e, q = C.pillRadius, 0.16       -- squircle: flatter sides, tighter corners
  end
  e = max(0, min(e, w / 2, h / 2))
  local c = e * q
  local x2, y2 = x + w, y + h
  local P = {}
  P[1]  = string.format('%.2f,%.2f', x + e, y)
  P[2]  = string.format('LineTo %.2f,%.2f', x2 - e, y)
  P[3]  = string.format('CurveTo %.2f,%.2f,%.2f,%.2f,%.2f,%.2f', x2, y + e, x2 - c, y, x2, y + c)
  P[4]  = string.format('LineTo %.2f,%.2f', x2, y2 - e)
  P[5]  = string.format('CurveTo %.2f,%.2f,%.2f,%.2f,%.2f,%.2f', x2 - e, y2, x2, y2 - c, x2 - c, y2)
  P[6]  = string.format('LineTo %.2f,%.2f', x + e, y2)
  P[7]  = string.format('CurveTo %.2f,%.2f,%.2f,%.2f,%.2f,%.2f', x, y2 - e, x + c, y2, x, y2 - c)
  P[8]  = string.format('LineTo %.2f,%.2f', x, y + e)
  P[9]  = string.format('CurveTo %.2f,%.2f,%.2f,%.2f,%.2f,%.2f', x + e, y, x, y + c, x + c, y)
  P[10] = 'ClosePath 1'
  return table.concat(P, ' | ')
end

local function updateVis(dt, cmd, playing)
  if not C.showVis then return end
  local va = C.combo and (1 - ctl.a) or 1          -- visualizer opacity (fades out while the controls show)
  local want = va > 0.01
  if vis.on ~= want then
    vis.on = want
    cmd[#cmd + 1] = want and '[!ShowMeter Vis]' or '[!HideMeter Vis]'
  end
  if not want then return end
  -- the audio measure always has 8 bands; with 4 bars each bar averages a pair of them
  local gains8 = { 1.0, 1.07, 1.15, 1.25, 1.35, 1.5, 1.7, 1.85 }
  local gains4 = { 1.0, 1.15, 1.35, 1.7 }
  local n = L.visN
  local maxH = C.visH
  local minH = max(3, L.vBar)
  local hs, parts = {}, {}
  for i = 1, n do
    local v = 0
    if playing then
      if n == 8 then
        if bandM[i] then v = clamp((bandM[i]:GetValue() or 0) * gains8[i], 0, 1) end
      elseif bandM[2 * i - 1] and bandM[2 * i] then
        v = clamp(((bandM[2 * i - 1]:GetValue() or 0) + (bandM[2 * i]:GetValue() or 0)) / 2 * gains4[i], 0, 1)
      end
    end
    local cur = vis.h[i] or 0
    local rate = (v > cur) and 30 or 7
    cur = cur + (v - cur) * (1 - exp(-dt * rate))
    vis.h[i] = cur
    local h = minH + (maxH - minH) * cur
    hs[i] = floor(h * 2 + 0.5) / 2
    parts[i] = hs[i]
  end
  local alpha = round(230 * va)
  local key = table.concat(parts, ':') .. '|' .. alpha
  if key ~= vis.key then
    vis.key = key
    for i = 1, n do
      local x = (i - 1) * (L.vBar + L.vGap)
      local y = (maxH - hs[i]) / 2
      local opt = (i == 1) and 'Shape' or ('Shape' .. i)
      cmd[#cmd + 1] = string.format(
        '[!SetOption Vis %s "Rectangle %d,%.1f,%d,%.1f,%.1f | Fill Color %s,%d | StrokeWidth 0"]',
        opt, x, y, L.vBar, hs[i], L.vBar / 2, K.light, alpha)
    end
  end
end

-- ---------- player state ----------

-- ---------- playback buttons ----------

-- called by the buttons' MouseOver / MouseLeave actions
function Hover(name)
  if name == nil or name == '' then ctl.hover = nil else ctl.hover = name end
  ctl.seen = os.clock()
end

-- combined mode: controls fade in while hovered and fade out again shortly after the mouse leaves
local function stepCtl(now, dt)
  if not C.combo then return end
  if ctl.hover then ctl.seen = now end
  local target = (ctl.hover or (now - ctl.seen) < C.ctlHold) and 1 or 0
  local step = dt / 0.18
  if ctl.a < target then ctl.a = min(target, ctl.a + step)
  elseif ctl.a > target then ctl.a = max(target, ctl.a - step) end
end

local function drawCtl(cmd, playing)
  if not C.showCtl then return end
  local hv = ctl.hover or '-'
  local fade = ctl.a
  local want = fade > 0.01
  if ctl.on ~= want then
    ctl.on = want
    for _, name in ipairs(BTN) do cmd[#cmd + 1] = (want and '[!ShowMeter ' or '[!HideMeter ') .. name .. ']' end
  end
  if not want then ctl.key = nil; return end
  local key = tostring(playing) .. hv .. K.textStr .. K.accentStr .. round(fade * 40)
  if key == ctl.key then return end
  ctl.key = key

  local s = C.ctlS
  local c = s / 2
  local h = max(4, s * 0.2)                       -- half the glyph height
  local rect = function(x, y, w, hh) return string.format('Rectangle %.1f,%.1f,%.1f,%.1f,1', x, y, w, hh) end
  local none = 'Rectangle 0,0,0.1,0.1,0'
  for i, name in ipairs(BTN) do
    local id = (i == 1) and 'prev' or ((i == 2) and 'play' or 'next')
    local hot = (hv == id)
    local bgA = max(1, round((hot and 70 or 1) * fade))
    local ia = round((hot and 255 or 225) * fade)
    local fill = ' | Fill Color ' .. K.textStr .. ',' .. ia .. ' | StrokeWidth 0'
    local s2, s3 = none .. fill, none .. fill
    if id == 'prev' then
      cmd[#cmd + 1] = string.format('[!SetOption %s IconPath "%.1f,%.1f | LineTo %.1f,%.1f | LineTo %.1f,%.1f | ClosePath 1"]',
        name, c + h, c - h, c - h + 3, c, c + h, c + h)
      s2 = 'Path IconPath' .. fill
      s3 = rect(c - h - 2, c - h, 2, 2 * h) .. fill
    elseif id == 'next' then
      cmd[#cmd + 1] = string.format('[!SetOption %s IconPath "%.1f,%.1f | LineTo %.1f,%.1f | LineTo %.1f,%.1f | ClosePath 1"]',
        name, c - h, c - h, c + h - 3, c, c - h, c + h)
      s2 = 'Path IconPath' .. fill
      s3 = rect(c + h, c - h, 2, 2 * h) .. fill
    elseif playing then
      s2 = rect(c - h * 0.8 - 1.5, c - h, 3, 2 * h) .. fill
      s3 = rect(c + h * 0.8 - 1.5, c - h, 3, 2 * h) .. fill
    else
      cmd[#cmd + 1] = string.format('[!SetOption %s IconPath "%.1f,%.1f | LineTo %.1f,%.1f | LineTo %.1f,%.1f | ClosePath 1"]',
        name, c - h * 0.7, c - h, c + h, c, c - h * 0.7, c + h)
      s2 = 'Path IconPath' .. fill
    end
    cmd[#cmd + 1] = string.format('[!SetOption %s Shape "Rectangle 0,0,%d,%d,%.1f | Fill Color %s,%d | StrokeWidth 0"]',
      name, s, s, s * 0.3, K.accentStr, bgA)
    cmd[#cmd + 1] = '[!SetOption ' .. name .. ' Shape2 "' .. s2 .. '"]'
    cmd[#cmd + 1] = '[!SetOption ' .. name .. ' Shape3 "' .. s3 .. '"]'
  end
end

local function readTime(m)
  local s = m:GetStringValue() or ''
  local h, mi, se = s:match('^(%d+):(%d+):(%d+)')
  if h then return tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(se) end
  mi, se = s:match('^(%d+):(%d+)')
  if mi then return tonumber(mi) * 60 + tonumber(se) end
  return (tonumber(s) or m:GetValue() or 0) / C.posUnit
end

local function isPlaying()
  local st = (mState:GetStringValue() or ''):lower()
  return st == '1' or st:find('play') ~= nil
end

-- ---------- lyrics request: LRCLIB exact lookup first, LRCLIB search as a fallback ----------

-- read one JSON string value out of a chunk of text; the result stays JSON-escaped
local function jstr(chunk, key)
  local _, e = chunk:find('"' .. key .. '"%s*:%s*"')
  if not e then return nil end
  local i = e + 1
  while true do
    local q = chunk:find('"', i, true)
    if not q then return nil end
    local bs, j = 0, q - 1
    while j >= i and chunk:byte(j) == 92 do bs = bs + 1; j = j - 1 end
    if bs % 2 == 0 then return chunk:sub(e + 1, q - 1) end
    i = q + 1
  end
end

local function jnum(chunk, key)
  return tonumber(chunk:match('"' .. key .. '":%s*(%-?[%d%.]+)'))
end

local function normName(x)
  return (unescape(x or ''):lower():gsub('[%s%p]', ''))
end

-- the objects of the JSON array that follows "key": as separate strings
local function splitObjs(raw, key)
  local out = {}
  local _, e = raw:find('"' .. key .. '"%s*:%s*%[')
  if not e then return out end
  local depth, inStr, esc, start = 0, false, false, nil
  for i = e + 1, #raw do
    local c = raw:byte(i)
    if inStr then
      if esc then esc = false elseif c == 92 then esc = true elseif c == 34 then inStr = false end
    elseif c == 34 then inStr = true
    elseif c == 123 then
      if depth == 0 then start = i end
      depth = depth + 1
    elseif c == 125 then
      depth = depth - 1
      if depth == 0 and start then out[#out + 1] = raw:sub(start, i); start = nil end
    elseif c == 93 and depth == 0 then break end
  end
  return out
end

local B64 = {}
do
  local abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  for i = 1, 64 do B64[abc:byte(i)] = i - 1 end
end
local function b64dec(str)
  str = str:gsub('[^%w%+/]', '')
  local out = {}
  for i = 1, #str, 4 do
    local c1, c2, c3, c4 = B64[str:byte(i)], B64[str:byte(i + 1)], B64[str:byte(i + 2)], B64[str:byte(i + 3)]
    if not (c1 and c2) then break end
    local v = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
    out[#out + 1] = string.char(floor(v / 65536) % 256)
    if c3 then out[#out + 1] = string.char(floor(v / 256) % 256) end
    if c4 then out[#out + 1] = string.char(v % 256) end
  end
  return table.concat(out)
end

-- how well a search hit (title, artist, duration in seconds) fits the current track; nil = no
local function matchScore(name, who, dur)
  local qt, qa = normName(Q.title:gsub('%s*[%(%[].-[%)%]]', '')), normName(Q.artist)
  if qt == '' then qt = normName(Q.title) end
  local nt, na = normName(name), normName(who)
  local diff = (dur and dur > 0 and Q.dur > 0) and math.abs(dur - Q.dur) or nil
  local titleOk = (nt ~= '' and qt ~= '') and (nt == qt or nt:find(qt, 1, true) or qt:find(nt, 1, true))
  if not titleOk or (diff and diff > 6) then return nil end
  local score = (nt == qt and 30 or 15)
  if na ~= '' and qa ~= '' and (na == qa or na:find(qa, 1, true) or qa:find(na, 1, true)) then score = score + 20 end
  if diff then score = score - diff * 3 end
  return score
end

local function fetch(title, artist)
  local t = (title:gsub('%s*[%(%[].-[%)%]]', ''))
  t = (t:gsub('%s+%-%s+[Rr]emaster.*$', ''))
  if t == '' then t = title end
  local url = 'https://lrclib.net/api/get?artist_name=' .. urlenc(artist)
              .. '&track_name=' .. urlenc(t)
  Q.stage, Q.title, Q.artist, Q.src, Q.pick = 1, title, artist, '-', ''
  Q.dur = readTime(mDuration)
  -- Set the URL now, trigger the download a few frames later so the measure has re-read
  -- its dynamic URL (starting it in the same instant used the old one).
  SKIN:Bang('!SetVariable', 'LyricsURL', url)
  trigF, trigM = frame + 3, 'mLyrics'
end

-- the exact lookup found nothing: ask LRCLIB's search, which tolerates different spellings
local function startSearch()
  Q.stage = 2
  local t = (Q.title:gsub('%s*[%(%[].-[%)%]]', ''))
  t = (t:gsub('%s+%-%s+.*$', ''))                     -- "Song - Live", "Song - Remix" ...
  t = (t:gsub('%s+[Ff]e?a?t%.?%s+.*$', ''))           -- "Song feat. X"
  if t == '' then t = Q.title end
  local a = Q.artist:gsub('%s*[,&;/].*$', ''):gsub('%s+[Ff]e?a?t%.?%s+.*$', '')
  if a == '' then a = Q.artist end
  SKIN:Bang('!SetVariable', 'LyricsSearchURL',
    'https://lrclib.net/api/search?track_name=' .. urlenc(t) .. '&artist_name=' .. urlenc(a))
  trigF, trigM = frame + 3, 'mSearch'
end

-- choose the best synced result of a search response (a JSON array); returns raw lyrics or nil
local function pickBest(raw)
  local starts = {}
  local init = 1
  while true do
    local p = raw:find('{"id":', init, true)
    if not p then break end
    starts[#starts + 1] = p
    init = p + 6
  end
  local qt, qa = normName(Q.title:gsub('%s*[%(%[].-[%)%]]', '')), normName(Q.artist)
  if qt == '' then qt = normName(Q.title) end
  local best, bestScore, bestId
  for i, p in ipairs(starts) do
    local chunk = raw:sub(p, (starts[i + 1] or (#raw + 1)) - 1)
    local synced = jstr(chunk, 'syncedLyrics')
    if synced and synced ~= '' and not chunk:find('"instrumental":true', 1, true) then
      local nt, na = normName(jstr(chunk, 'trackName')), normName(jstr(chunk, 'artistName'))
      local d = jnum(chunk, 'duration')
      local diff = (d and Q.dur > 0) and math.abs(d - Q.dur) or nil
      local titleOk = (nt ~= '' and qt ~= '') and (nt == qt or nt:find(qt, 1, true) or qt:find(nt, 1, true))
      if titleOk and (diff == nil or diff <= 6) then
        local score = (nt == qt and 30 or 15)
        if na ~= '' and qa ~= '' and (na == qa or na:find(qa, 1, true) or qa:find(na, 1, true)) then score = score + 20 end
        if diff then score = score - diff * 3 end
        if not bestScore or score > bestScore then
          best, bestScore, bestId = synced, score, jnum(chunk, 'id')
        end
      end
    end
  end
  Q.pick = tostring(bestId or '')
  return best
end

-- search keywords with the usual decorations removed
local function plainTitleArtist()
  local t = (Q.title:gsub('%s*[%(%[].-[%)%]]', ''))
  t = (t:gsub('%s+%-%s+.*$', ''))
  t = (t:gsub('%s+[Ff]e?a?t%.?%s+.*$', ''))
  if t == '' then t = Q.title end
  local a = Q.artist:gsub('%s*[,&;/].*$', ''):gsub('%s+[Ff]e?a?t%.?%s+.*$', '')
  if a == '' then a = Q.artist end
  return t, a
end

-- step 3: KuGou (search, then download the chosen lyric)
local function startKugou()
  Q.stage = 3
  local t, a = plainTitleArtist()
  SKIN:Bang('!SetVariable', 'KgSearchURL', 'https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword='
    .. urlenc(a .. ' - ' .. t) .. '&duration=' .. floor(Q.dur * 1000) .. '&hash=')
  trigF, trigM = frame + 3, 'mKgS'
end

-- step 5: NetEase Cloud Music (search, then fetch the lyric of the best match)
local function startNetease()
  Q.stage = 5
  local t, a = plainTitleArtist()
  SKIN:Bang('!SetVariable', 'NeSearchURL', 'https://music.163.com/api/search/get/web?csrf_token=&hlpretag=&hlposttag='
    .. '&s=' .. urlenc(t .. ' ' .. a) .. '&type=1&offset=0&total=true&limit=8')
  trigF, trigM = frame + 3, 'mNeS'
end

-- ---------- called by WebParser / RunCommand ----------

local function failFinal()
  lastRaw = nil
  if waiting then
    waiting = false
    clearWords()
    setMode(false)
  end
end

-- parsed = list of { t, text, wt }; key = something that changes when the lyrics do
local function acceptParsed(parsed, src, key, minLines)
  if not key or key == '' or key == lastRaw or #parsed < (minLines or 1) then return false end
  lastRaw = key
  waiting = false
  Q.src = src
  loadWords(parsed)
  setMode(true)
  return true
end

local function accept(raw, src)
  if raw == '' then return false end
  return acceptParsed(parseLRC(raw), src, raw)
end

local function measureText(name)
  return SKIN:GetMeasure(name):GetStringValue() or ''
end

-- one function per WebParser callback; a stale answer (wrong stage) is ignored
function OnFailed()
  if waiting and Q.stage == 1 then startSearch() end
end

function OnFetched()
  if not (waiting and Q.stage == 1) then return end
  if not accept(measureText('mLyrics'), 'lrclib') then startSearch() end
end

function OnSearched()
  if not (waiting and Q.stage == 2) then return end
  local best = pickBest(measureText('mSearch'))
  if not (best and accept(best, 'lrclib')) then startKugou() end
end

function OnSearchFailed()
  if waiting and Q.stage == 2 then startKugou() end
end

function OnKgSearched()
  if not (waiting and Q.stage == 3) then return end
  local raw = measureText('mKgS')
  local bestId, bestKey, bestScore
  for _, c in ipairs(splitObjs(raw, 'candidates')) do
    local id = c:match('"id"%s*:%s*"?(%w+)')
    local key = jstr(c, 'accesskey')
    local d = jnum(c, 'duration')
    if d and d > 1000 then d = d / 1000 end
    local sc = id and key and matchScore(unescape(jstr(c, 'song') or ''), unescape(jstr(c, 'singer') or ''), d)
    if sc and (not bestScore or sc > bestScore) then bestId, bestKey, bestScore = id, key, sc end
  end
  if not bestId then startNetease() return end
  Q.stage, Q.pick = 4, 'kg' .. bestId
  SKIN:Bang('!SetVariable', 'KgLyricsURL', 'https://lyrics.kugou.com/download?ver=1&client=pc&id=' .. urlenc(bestId)
    .. '&accesskey=' .. urlenc(bestKey) .. '&fmt=lrc&charset=utf8')
  trigF, trigM = frame + 3, 'mKgL'
end

function OnKgLyrics()
  if not (waiting and Q.stage == 4) then return end
  local content = jstr(measureText('mKgL'), 'content')
  local ok = content and content ~= '' and acceptParsed(parseLRC(b64dec(content), true), 'kugou', content, 3)
  if not ok then startNetease() end
end

function OnKgFailed()
  if waiting and (Q.stage == 3 or Q.stage == 4) then startNetease() end
end

function OnNeSearched()
  if not (waiting and Q.stage == 5) then return end
  local bestId, bestScore
  for _, o in ipairs(splitObjs(measureText('mNeS'), 'songs')) do
    local id = o:match('^{%s*"id"%s*:%s*(%d+)')
    local who = o:match('"artists"%s*:%s*%[%s*{.-"name"%s*:%s*"(.-)"') or ''
    local d = tonumber(o:match('"duration"%s*:%s*(%d+)'))
    local sc = id and matchScore(unescape(jstr(o, 'name') or ''), unescape(who), d and d / 1000)
    if sc and (not bestScore or sc > bestScore) then bestId, bestScore = id, sc end
  end
  if not bestId then failFinal() return end
  Q.stage, Q.pick = 6, 'ne' .. bestId
  SKIN:Bang('!SetVariable', 'NeLyricsURL', 'https://music.163.com/api/song/lyric?id=' .. bestId
    .. '&lv=-1&kv=-1&tv=-1&yv=-1')
  trigF, trigM = frame + 3, 'mNeL'
end

function OnNeLyrics()
  if not (waiting and Q.stage == 6) then return end
  local raw = measureText('mNeL')
  local function section(name)
    local _, e = raw:find('"' .. name .. '"%s*:%s*{')
    return e and jstr(raw:sub(e), 'lyric')
  end
  local yrc, lrc = section('yrc'), section('lrc')
  local ok = false
  if yrc and yrc ~= '' then ok = acceptParsed(parseYRC(yrc), 'netease', yrc, 3) end
  if not ok and lrc and lrc ~= '' then ok = acceptParsed(parseLRC(lrc), 'netease', lrc, 3) end
  if not ok then failFinal() end
end

function OnNeFailed()
  if waiting and (Q.stage == 5 or Q.stage == 6) then failFinal() end
end

function OnWallpaper()
  if not mWall then return end
  local s = mWall:GetStringValue() or ''
  local r, g, b = s:match('(%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
  if not r then return end
  r, g, b = tonumber(r), tonumber(g), tonumber(b)
  if wall and wall[1] == r and wall[2] == g and wall[3] == b then return end
  wall = { r, g, b }
  -- remember it so the next refresh starts with the right colours straight away
  local inc = SKIN:ReplaceVariables('#@#Settings.inc')
  SKIN:Bang('[!WriteKeyValue Variables "WallAvg" "' .. r .. ',' .. g .. ',' .. b .. '" "' .. inc .. '"]')
  if C.colorMode == 'wallpaper' then recolor() end
end

-- ---------- one frame of the lyric strip ----------

-- learn the real width of words once their meter has been drawn
local function learnWidths(now)
  for m = 1, N do
    local s = S[m]
    local k = s.k
    if k and not ww[k] and frame > s.setf then
      local w = segM[m] and segM[m]:GetW() or 0
      if w and w > 2 then
        ww[k] = w
        dirty = true
      elseif now - s.setT > 0.35 then
        ww[k] = estW(k)       -- measuring failed: use the estimate rather than staying invisible
        dirty = true
      end
    end
  end
  if dirty then relayout() end
end

-- the highlight, trimmed to the bar (pl/pr are x positions inside the lyric box)
local function emitPill(cmd, pl, pr, alpha)
  local boxW = L.barW
  local cl, cr = max(pl, 0), min(pr, boxW)
  local pw = cr - cl
  local pa = round(alpha)
  if pw < 6 then pa, pw = 0, 6 end
  local key = string.format('%.1f:%.1f:%d', cl, pw, pa)
  if key ~= lastPill then
    lastPill = key
    -- path and fill are always sent together so the shape is rebuilt from both
    cmd[#cmd + 1] = '[!SetOption Pill PillPath "' .. pillPath(cl, pw) .. '"]'
    cmd[#cmd + 1] = '[!SetOption Pill Shape "Path PillPath | Fill Color ' .. K.accentStr .. ',' .. pa .. ' | StrokeWidth 0"]'
  end
end

-- ---- legacy mode: one long line that scrolls continuously ----
local function lyricFrame(now, dt, t, cmd)
  if nw == 0 then return end
  local boxW = L.barW
  local focusX = C.focus * boxW
  local padX = C.padX

  learnWidths(now)

  local gi = findGroup(t)
  local first, last = gFirst[gi], gLast[gi]

  -- camera target: world x that should sit at the focus point.
  -- It moves continuously from the current group's centre to the next one's.
  local c0 = groupCenter(gi)
  local target = c0
  if gi < #gT0 then
    local tn = gT0[gi + 1]
    local span = min(tn - gT0[gi], 1.0)
    if span > 0.001 then
      local s = clamp((t - (tn - span)) / span, 0, 1)
      target = c0 + (groupCenter(gi + 1) - c0) * s
    end
  end

  local snap = (cam == nil) or (lastGi == nil) or (abs(gi - lastGi) > 3) or (appear <= 0)
  lastGi = gi
  local gl, gr = groupRect(gi)
  if snap then
    cam, camV = target, 0
    pillL, pillR, pillLv, pillRv = gl, gr, 0, 0
  else
    cam, camV = smoothDamp(cam, target, camV, C.camST, dt)
    -- leading edge a little quicker than the trailing edge: a soft stretch as it glides
    pillL, pillLv = smoothDamp(pillL, gl, pillLv, C.pillST * 1.15, dt)
    pillR, pillRv = smoothDamp(pillR, gr, pillRv, C.pillST * 0.85, dt)
  end

  -- fade the whole strip in once the words around the current one are measured
  if appear < 1 then
    local ok = true
    for k = first, last do if not ww[k] then ok = false end end
    if now - startClock > 0.8 then ok = true end
    if ok and now - startClock > 0.08 then appear = min(1, appear + dt * 4) end
  end

  local ox = focusX - cam      -- world x -> x inside the lyric box

  -- which words are on (or about to enter) the screen
  local kLo = first
  while kLo > 1 do
    local px = wx[kLo - 1] + ox + (ww[kLo - 1] or estW(kLo - 1))
    if px < -24 then break end
    kLo = kLo - 1
  end
  if last - kLo > N - 1 then kLo = last - (N - 1) end
  local kHi = last
  while kHi < nw and (kHi - kLo) < (N - 1) do
    if wx[kHi + 1] + ox > boxW + 140 then break end
    kHi = kHi + 1
  end

  local used = {}
  local tr, tg, tb = K.text[1], K.text[2], K.text[3]
  local ar, ag, ab = K.active[1], K.active[2], K.active[3]

  for k = kLo, kHi do
    local m = (k - 1) % N + 1
    used[m] = true
    local s = S[m]
    if s.k ~= k then
      s.k, s.setf, s.setT = k, frame, now
      s.x, s.a, s.col = nil, nil, nil
      cmd[#cmd + 1] = '[!SetOption S' .. m .. ' Text "' .. clean(words[k].text) .. '"]'
    end

    local w = ww[k]
    local x = 0
    local alpha = 0
    local col = K.textStr .. ',0'
    local wantVis = true

    if w then
      x = wx[k] + ox
      local tgt = (k >= first and k <= last) and 1 or 0
      local av = act[k]
      if av == nil then av = tgt end
      av = av + (tgt - av) * (1 - exp(-dt * 14))
      if abs(av - tgt) < 0.004 then av = tgt end
      act[k] = av

      local base = (wg[k] < gi) and PAST_ALPHA or FUTURE_ALPHA
      local a0 = base + (255 - base) * av

      local eL, eR
      if C.fade > 0 then
        eL = smooth01(x / C.fade)                    -- fades out towards the left edge
        eR = smooth01((boxW - (x + w)) / C.fade)     -- fades in as it enters from the right
      else
        eL = (x >= 0) and 1 or 0
        eR = (x + w <= boxW) and 1 or 0
      end
      alpha = round(a0 * eL * eR * appear)
      wantVis = alpha > 0
      col = string.format('%d,%d,%d,%d',
        round(tr + (ar - tr) * av), round(tg + (ag - tg) * av), round(tb + (ab - tb) * av), alpha)
      if k == first then dbgCur = 'S' .. m .. ' x' .. round(x) .. ' a' .. alpha end
    end

    if wantVis then
      local xi = round(x) + L.barX
      if s.x ~= xi then
        s.x = xi
        cmd[#cmd + 1] = '[!SetOption S' .. m .. ' X ' .. xi .. ']'
      end
      if s.col ~= col then
        s.col = col
        cmd[#cmd + 1] = '[!SetOption S' .. m .. ' FontColor "' .. col .. '"]'
      end
    end
    if s.vis ~= wantVis then
      s.vis = wantVis
      cmd[#cmd + 1] = (wantVis and '[!ShowMeter S' or '[!HideMeter S') .. m .. ']'
    end
  end

  for m = 1, N do
    if not used[m] then
      local s = S[m]
      s.k = nil
      if s.vis ~= false then
        s.vis = false
        cmd[#cmd + 1] = '[!HideMeter S' .. m .. ']'
      end
    end
  end

  emitPill(cmd, pillL + ox, pillR + ox, K.pillA * appear)
end

-- ---- paged mode: one static line, a highlight that glides across it ----
-- how long a line is on screen (start of its first word to the start of the next line)
local function pageDur(F)
  local nf = pL[F] + 1
  if nf <= nw then return max(0.2, words[nf].t - words[F].t) end
  return 3
end

-- fade times for the line being shown: a fraction of its length, so quick lines switch quickly
local function pageFades(F)
  local d = pageDur(F)
  return clamp(d * 0.08, 0.05, OUT_MAX), clamp(d * 0.12, 0.08, IN_MAX)
end

local function lyricFramePaged(now, dt, t, cmd)
  if nw == 0 then return end
  local boxW = L.barW
  local padX = C.padX

  learnWidths(now)

  -- which page should be on screen; cross-fade when it changes
  local kw = findWord(t)
  -- The next line starts fading in slightly *before* its first word, so it is already readable
  -- when the singing reaches it instead of appearing half way through.
  local tgt = pF[kw]
  if curPage then
    local outT, inT = pageFades(curPage)
    tgt = pF[findWord(t + min(0.18, outT + inT * 0.3))]
  end
  if curPage == nil then
    curPage, pgFade, pgReady, pgSnap, pgStart = tgt, 0, false, true, now
  elseif tgt ~= curPage then
    if not pgReady then
      curPage, pgFade, pgSnap, pgStart = tgt, 0, true, now
    else
      pgFade = pgFade - dt / (pageFades(curPage))
      if pgFade <= 0 then
        curPage, pgFade, pgReady, pgSnap, pgStart = tgt, 0, false, true, now
      end
    end
  end

  local F, Lw = curPage, pL[curPage]
  local top = min(Lw, F + N - 1)

  if not pgReady then
    local ok = true
    for k = F, top do if not ww[k] then ok = false end end
    if ok or now - pgStart > 0.8 then pgReady = true end
  end
  if pgReady and tgt == curPage then
    local _, inT = pageFades(curPage)
    pgFade = min(1, pgFade + dt / inT)
  end

  -- geometry relative to the start of the line
  local base0 = wx[F]
  local function relL(k) return wx[k] - base0 end
  local function relR(k) return wx[k] - base0 + (ww[k] or estW(k)) end
  local lineW = relR(top)

  local kp = clamp(kw, F, top)
  local n = C.pageWords
  local function win(kk)
    local a = max(F, min(kk, top - n + 1))
    local e = min(a + n - 1, top)
    return relL(a), relR(e) + 2 * padX
  end
  local l1, r1 = win(kp)
  local l2, r2 = l1, r1
  local f = 0
  if kp < top and kw < top then
    l2, r2 = win(kp + 1)
    local d = words[kp + 1].t - words[kp].t
    if d > 0.001 then f = clamp((t - words[kp].t) / d, 0, 1) end
  end
  local gl, gr = l1 + (l2 - l1) * f, r1 + (r2 - r1) * f

  -- scroll only when the line is wider than the bar
  local maxScroll = lineW + 2 * padX - boxW
  local scrollT = 0
  if maxScroll > 0.5 then
    scrollT = clamp(gr + 36 - (boxW - C.fade), 0, maxScroll)
  end

  if pgSnap then
    pillL, pillR, pillLv, pillRv = gl, gr, 0, 0
    cam, camV = scrollT, 0
    pgSnap = false
  else
    pillL, pillLv = smoothDamp(pillL, gl, pillLv, C.pillST * 0.5, dt)
    pillR, pillRv = smoothDamp(pillR, gr, pillRv, C.pillST * 0.5, dt)
    local oldCam = cam or 0
    cam, camV = smoothDamp(oldCam, scrollT, camV, C.camST, dt)
    -- The line scrolls with a spring, the pill advances at the speed of the words. When a fast
    -- word is followed by a slow one the spring can briefly outrun the pill, which then seems to
    -- slide backwards on screen. Cap the scroll so neither edge of the pill moves left.
    if pgScreenR and (pillR - cam < pgScreenR or pillL - cam < pgScreenL) then
      cam = max(oldCam, min(pillR - pgScreenR, pillL - pgScreenL))
      camV = (cam - oldCam) / dt
    end
  end
  pgScreenR, pgScreenL = pillR - cam, pillL - cam
  local ox = padX - cam
  local overflow = maxScroll > 0.5

  local used = {}
  local tr, tg, tb = K.text[1], K.text[2], K.text[3]
  local ar, ag, ab = K.active[1], K.active[2], K.active[3]

  for k = F, top do
    local m = (k - 1) % N + 1
    used[m] = true
    local s = S[m]
    if s.k ~= k then
      s.k, s.setf, s.setT = k, frame, now
      s.x, s.a, s.col = nil, nil, nil
      cmd[#cmd + 1] = '[!SetOption S' .. m .. ' Text "' .. clean(words[k].text) .. '"]'
    end

    local w = ww[k]
    local x, alpha, col, wantVis = 0, 0, K.textStr .. ',0', true

    if w then
      x = relL(k) + ox
      local tg1 = (k <= kw) and 1 or 0
      local h = act[k]
      if h == nil then h = tg1 end
      h = h + (tg1 - h) * (1 - exp(-dt * 14))
      if abs(h - tg1) < 0.004 then h = tg1 end
      act[k] = h
      local b = PAGE_FUTURE + (PAGE_PAST - PAGE_FUTURE) * h

      -- how much of this word the highlight covers
      local pl, pr = pillL - cam + padX, pillR - cam - padX
      local cov = clamp((min(x + w, pr) - max(x, pl)) / max(w, 1), 0, 1)
      local a0 = b + (255 - b) * cov

      local eL, eR = 1, 1
      if overflow then
        if C.fade > 0 then
          eL = smooth01(x / C.fade)
          eR = smooth01((boxW - (x + w)) / C.fade)
        else
          eL = (x >= 0) and 1 or 0
          eR = (x + w <= boxW) and 1 or 0
        end
      end
      alpha = round(a0 * eL * eR * pgFade)
      wantVis = alpha > 0
      col = string.format('%d,%d,%d,%d',
        round(tr + (ar - tr) * cov), round(tg + (ag - tg) * cov), round(tb + (ab - tb) * cov), alpha)
      if k == kp then dbgCur = 'S' .. m .. ' x' .. round(x) .. ' a' .. alpha end
    end

    if wantVis then
      local xi = round(x) + L.barX
      if s.x ~= xi then
        s.x = xi
        cmd[#cmd + 1] = '[!SetOption S' .. m .. ' X ' .. xi .. ']'
      end
      if s.col ~= col then
        s.col = col
        cmd[#cmd + 1] = '[!SetOption S' .. m .. ' FontColor "' .. col .. '"]'
      end
    end
    if s.vis ~= wantVis then
      s.vis = wantVis
      cmd[#cmd + 1] = (wantVis and '[!ShowMeter S' or '[!HideMeter S') .. m .. ']'
    end
  end

  -- Prepare the next line while this one is on screen: its words get their text and are measured
  -- (invisible), so the switch does not have to wait a frame or two for the widths.
  local nextF = Lw + 1
  if nextF <= nw then
    local ntop = min(pL[nextF], nextF + N - 1)
    if (top - F + 1) + (ntop - nextF + 1) <= N then
      for k = nextF, ntop do
        local m = (k - 1) % N + 1
        used[m] = true
        local s = S[m]
        if s.k ~= k then
          s.k, s.setf, s.setT = k, frame, now
          s.x, s.col, s.vis = nil, nil, nil
          cmd[#cmd + 1] = '[!SetOption S' .. m .. ' Text "' .. clean(words[k].text) .. '"]'
        end
        if ww[k] then
          if s.vis ~= false then
            s.vis = false
            cmd[#cmd + 1] = '[!HideMeter S' .. m .. ']'
          end
        elseif s.vis ~= true then
          s.vis = true
          s.col = K.textStr .. ',0'
          cmd[#cmd + 1] = '[!SetOption S' .. m .. ' FontColor "' .. s.col .. '"][!ShowMeter S' .. m .. ']'
        end
      end
    end
  end

  for m = 1, N do
    if not used[m] then
      local s = S[m]
      s.k = nil
      if s.vis ~= false then
        s.vis = false
        cmd[#cmd + 1] = '[!HideMeter S' .. m .. ']'
      end
    end
  end

  appear = pgFade
  emitPill(cmd, pillL - cam, pillR - cam, K.pillA * pgFade)
end

-- ---------- setup ----------

local function setup()
  mTitle    = SKIN:GetMeasure('mTitle')
  mArtist   = SKIN:GetMeasure('mArtist')
  mPosition = SKIN:GetMeasure('mPosition')
  mDuration = SKIN:GetMeasure('mDuration')
  mState    = SKIN:GetMeasure('mState')
  mProgress = SKIN:GetMeasure('mProgress')
  mLyrics   = SKIN:GetMeasure('mLyrics')
  mWall     = SKIN:GetMeasure('mWall')
  if not (mTitle and mArtist and mPosition and mDuration and mState and mProgress and mLyrics) then
    return false
  end
  for i = 1, 8 do bandM[i] = SKIN:GetMeasure('mBand' .. i) end
  for m = 1, N do
    segM[m] = SKIN:GetMeter('S' .. m)
    S[m] = {}
  end
  loadConfig()
  computeLayout()
  computeColors()
  applyLayout()
  curMode = false
  return true
end

-- ---------- main loop ----------

-- starts and drives the lyrics download. Kept out of Update() because Lua 5.1 (used by
-- Rainmeter) allows a function at most 60 upvalues and Update() was over the limit.
local function pumpRequests(now)
  -- wait until title/artist have stopped changing (the player can update them a moment
  -- apart), then request lyrics
  if fetchPending and now - seenSince > 0.7 then
    fetchPending = false
    waiting, waitSince = true, now
    fetch(curTitle, curArtist)
  end
  if trigF and frame >= trigF then
    trigF = nil
    if not enabledOnce[trigM] then
      enabledOnce[trigM] = true
      SKIN:Bang('!EnableMeasure', trigM)
      updF, updM = frame + 4, trigM
    else
      SKIN:Bang('!CommandMeasure', trigM, 'Update')
    end
  end
  if updF and frame >= updF then
    updF = nil
    SKIN:Bang('!CommandMeasure', updM, 'Update')
  end
  if waiting and now - waitSince > 30 then failFinal() end
end

local function trackTick(now)
  local title  = mTitle:GetStringValue() or ''
  local artist = mArtist:GetStringValue() or ''
  if title ~= curTitle or artist ~= curArtist then
    curTitle, curArtist = title, artist
    seenSince = now
    clearWords()
    lastPos = -1
    setMode(false)
    waiting, trigF, updF = false, nil, nil
    Q.stage = 0
    fetchPending = (title ~= '' and artist ~= '')
  end

end

local function wallTick(now)
  if C.colorMode == 'wallpaper' and mWall then
    if lastWallRun == nil and frame > 30 then
      lastWallRun = now
      SKIN:Bang('!CommandMeasure', 'mWall', 'Run')
    elseif lastWallRun and C.wallEvery > 0 and now - lastWallRun > C.wallEvery then
      lastWallRun = now
      SKIN:Bang('!CommandMeasure', 'mWall', 'Run')
    end
  end

end

local function progressTick(cmd)
  if C.showProg then
    local dur = readTime(mDuration)
    local frac
    if dur > 0 then frac = disp / dur else frac = (mProgress:GetValue() or 0) / 100 end
    frac = clamp(frac, 0, 1)
    if curTitle == '' then frac = 0 end
    local pw = floor(frac * L.barW * 10 + 0.5) / 10
    if pw ~= lastProg then
      lastProg = pw
      cmd[#cmd + 1] = string.format(
        '[!SetOption ProgressFill Shape "Rectangle 0,0,%.1f,%d,%.1f | Fill Color %s | StrokeWidth 0"]',
        max(pw, 0.01), C.progH, C.progH / 2, K.light)
    end
  end
end

local function debugTick(now, cmd)
  if C.debug and now - lastDbg > 0.5 then
    lastDbg = now
    local w1 = segM[1] and segM[1]:GetW() or -1
    local parts = {
      string.format('words:%d groups:%d mode:%s wait:%s src:%s %s', nw, #gT0, tostring(curMode), tostring(waiting), Q.src, Q.pick),
      string.format('t:%.1f appear:%.2f cam:%.0f style:%s page:%s', disp, appear, cam or -1, C.mode, tostring(curPage)),
      string.format('w1:%s pill:%s', tostring(w1), tostring(lastPill)),
      'current: ' .. tostring(dbgCur),
      'wall: ' .. (wall and (wall[1] .. ',' .. wall[2] .. ',' .. wall[3]) or 'none'),
    }
    for i = 1, #parts do parts[i] = clean(parts[i]) end
    cmd[#cmd + 1] = '[!SetOption DebugText Text "pos: %1 | state: %2#CRLF#' .. table.concat(parts, '#CRLF#') .. '"]'
    cmd[#cmd + 1] = '[!UpdateMeter DebugText]'
  end

end

function Update()
  if not ready then
    ready = setup()
    return 0
  end

  frame = frame + 1
  local now = os.clock()
  local dt = lastFrame and clamp(now - lastFrame, 0.001, 0.1) or 0.016
  lastFrame = now
  local cmd = {}

  trackTick(now)
  pumpRequests(now)
  wallTick(now)

  -- smoothed playback time: interpolates between the player's coarse updates
  local playing = isPlaying()
  local pos = readTime(mPosition)
  if pos ~= lastPos then lastPos, lastClock = pos, now end
  if not playing or not wasPlaying then lastClock = now end
  wasPlaying = playing
  local est = pos + (playing and min(now - lastClock, 1.2) or 0)
  if firstTime or abs(est - disp) > 1.5 then
    disp, firstTime = est, false
  elseif playing then
    -- The player reports its position coarsely and unevenly, so the estimate wobbles by a few
    -- tenths of a second. Never let the displayed time run backwards: when it is ahead of the
    -- estimate it simply waits (rate 0) and when it is behind it catches up (up to 2.5x).
    disp = disp + dt * clamp(1 + (est - disp) * 4, 0, 2.5)
  else
    disp = disp + (est - disp) * (1 - exp(-dt * 10))
  end

  progressTick(cmd)

  -- visualizer
  stepCtl(now, dt)
  updateVis(dt, cmd, playing)
  drawCtl(cmd, playing)

  -- lyrics
  if curMode and nw > 0 then
    if C.mode == 'legacy' then
      lyricFrame(now, dt, disp + C.offset, cmd)
    else
      lyricFramePaged(now, dt, disp + C.offset, cmd)
    end
  end

  debugTick(now, cmd)

  if #cmd > 0 then
    cmd[#cmd + 1] = '[!UpdateMeterGroup Lyr][!UpdateMeter ProgressFill][!UpdateMeter Vis][!Redraw]'
    SKIN:Bang(table.concat(cmd))
  end
  return 0
end
