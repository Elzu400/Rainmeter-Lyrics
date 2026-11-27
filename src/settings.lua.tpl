-- Copyright (C) 2026 Elzu400
-- SPDX-License-Identifier: GPL-3.0-or-later
-- This file is part of RainmeterLyrics, free software under the GNU GPL v3 or later (see LICENSE).

-- Rainmeter Lyrics - settings script (Lua 5.1, ASCII only).
-- Edits Settings.inc (shared with the lyrics skin) and refreshes the lyrics skin.

--@@DATA@@

local ROWS = 12                      -- must match SETTINGS_ROWS in build.py
local floor, max, min = math.floor, math.max, math.min

local cfg, written = {}, {}
local tab, started = 1, false
local pending, dirtyAt = false, 0
local status = 'Changes apply automatically'
local mainConfig = 'RainmeterLyrics\\Lyrics'

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

local function fmt(v)
  return string.format('%g', floor(v * 100 + 0.5) / 100)
end

local function same(a, b)
  local x, y = tonumber(a), tonumber(b)
  if x and y then return x == y end
  return tostring(a) == tostring(b)
end

-- ---------- tabs and rows ----------

local TABS = { 'Layout', 'Lyrics', 'Colors', 'Motion' }

local ONOFF = { on = '1', off = '0' }

local DEFS = {
  { -- Layout
    { label = 'Preset', kind = 'preset' },
    { label = 'Width', key = 'PillWidth', kind = 'num', min = 300, max = 1600, step = 20, unit = ' px' },
    { label = 'Height', key = 'PillHeight', kind = 'num', min = 30, max = 140, step = 2, unit = ' px' },
    { label = 'Corner radius', key = 'CornerRadius', kind = 'num', min = 0, max = 70, step = 2, unit = ' px' },
    { label = 'Show album cover', key = 'ShowCover', kind = 'toggle', on = '1', off = '0' },
    { label = 'Cover size', key = 'CoverSize', kind = 'num', min = 16, max = 90, step = 2, unit = ' px' },
    { label = 'Cover rounding', key = 'CoverRadius', kind = 'num', min = 0, max = 45, step = 1, unit = ' px' },
    { label = 'Edge padding', key = 'Padding', kind = 'num', min = 4, max = 30, step = 1, unit = ' px' },
    { label = 'Right side', key = 'RightPanel', kind = 'choice',
      choices = { { label = 'Visualizer', value = 'vis' }, { label = 'Controls (slim)', value = 'controls' }, { label = 'Combined (slim)', value = 'combined' }, { label = 'Nothing', value = 'off' } } },
    { label = 'Progress bar', key = 'ShowProgress', kind = 'toggle', on = '1', off = '0' },
    { label = 'Progress thickness', key = 'ProgressHeight', kind = 'num', min = 1, max = 8, step = 1, unit = ' px' },
  },
  { -- Lyrics
    { label = 'Lyric style', key = 'LyricMode', kind = 'choice',
      choices = { { label = 'Paged (calm)', value = 'paged' }, { label = 'Scrolling (legacy)', value = 'legacy' } } },
    { label = 'Font size', key = 'FontSize', kind = 'num', min = 9, max = 30, step = 1, unit = ' pt' },
    { label = 'Bold text', key = 'FontWeight', kind = 'toggle', on = '700', off = '400' },
    { label = 'Words per highlight', key = 'PageWords', legacyKey = 'PillWords', kind = 'num', min = 1, max = 4, step = 1 },
    { label = 'Focus position (scrolling)', key = 'FocusPos', kind = 'num', min = 15, max = 75, step = 1, unit = ' %' },
    { label = 'Highlight shape', key = 'PillStyle', kind = 'choice',
      choices = { { label = 'Squircle', value = '0' }, { label = 'Rounded', value = '1' }, { label = 'Capsule', value = '2' } } },
    { label = 'Highlight corner', key = 'PillRadius', kind = 'num', min = 0, max = 24, step = 1, unit = ' px' },
    { label = 'Highlight padding', key = 'PillPadX', kind = 'num', min = 2, max = 24, step = 1, unit = ' px' },
    { label = 'Word spacing', key = 'WordSpacing', kind = 'num', min = 2, max = 20, step = 1, unit = ' px' },
    { label = 'Edge fade', key = 'FadeZone', kind = 'num', min = 0, max = 150, step = 5, unit = ' px' },
    { label = 'Lyrics timing offset', key = 'LyricsOffset', kind = 'num', min = -5, max = 5, step = 0.1, unit = ' s' },
    { label = 'Lyric sources (testing)', key = 'LyricsOrder', kind = 'choice',
      choices = {
        { label = 'LRCLIB > KuGou > NetEase', value = 'lrclib,kugou,netease' },
        { label = 'KuGou > NetEase > LRCLIB', value = 'kugou,netease,lrclib' },
        { label = 'NetEase > KuGou > LRCLIB', value = 'netease,kugou,lrclib' },
        { label = 'LRCLIB only', value = 'lrclib' },
        { label = 'KuGou only', value = 'kugou' },
        { label = 'NetEase only', value = 'netease' } } },
  },
  { -- Colors
    { label = 'Color source', key = 'ColorMode', kind = 'choice',
      choices = { { label = 'Manual', value = 'manual' }, { label = 'Wallpaper', value = 'wallpaper' } } },
    { label = 'Accent (highlight)', key = 'AccentColor', kind = 'color' },
    { label = 'Background', key = 'BgColor', kind = 'color' },
    { label = 'Text', key = 'TextColor', kind = 'color' },
    { label = 'Background opacity', key = 'BgAlpha', kind = 'num', pct = true, min = 0, max = 100, step = 5, unit = ' %' },
    { label = 'Highlight opacity', key = 'PillAlpha', kind = 'num', pct = true, min = 20, max = 100, step = 5, unit = ' %' },
    { label = 'Wallpaper vibrancy', key = 'WallMinSat', kind = 'num', min = 0, max = 100, step = 5, unit = ' %' },
    { label = 'Tint background', key = 'WallTintBg', kind = 'toggle', on = '1', off = '0' },
    { label = 'Re-check wallpaper', key = 'WallRefreshMin', kind = 'num', min = 0, max = 180, step = 5, unit = ' min', zero = 'Never' },
    { label = 'Quick accent colors', kind = 'palette' },
  },
  { -- Motion
    { label = 'Frame rate', key = 'FPS', kind = 'choice',
      choices = { { label = '24 fps', value = '24' }, { label = '30 fps', value = '30' }, { label = '45 fps', value = '45' },
                  { label = '60 fps', value = '60' }, { label = '75 fps', value = '75' }, { label = '90 fps', value = '90' },
                  { label = '120 fps', value = '120' }, { label = '144 fps', value = '144' } } },
    { label = 'Scroll smoothness', key = 'CamSmooth', kind = 'num', min = 100, max = 1500, step = 50, unit = ' ms' },
    { label = 'Highlight glide', key = 'PillSpeed', kind = 'num', min = 40, max = 400, step = 10, unit = ' ms' },
    { label = 'Controls hide delay', key = 'CtlHold', kind = 'num', min = 0, max = 5000, step = 250, unit = ' ms' },
    { label = 'Visualizer sensitivity', key = 'VisSensitivity', kind = 'num', min = 10, max = 80, step = 5 },
    { label = 'Player position unit', key = 'PositionUnit', kind = 'choice',
      choices = { { label = 'Seconds', value = '1' }, { label = 'Milliseconds', value = '1000' } } },
    { label = 'Debug overlay', key = 'Debug', kind = 'toggle', on = '1', off = '0' },
  },
}

-- ---------- helpers ----------

local function rgbToHex(s)
  local r, g, b = tostring(s):match('(%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
  if not r then return '?' end
  return string.format('#%02X%02X%02X', tonumber(r), tonumber(g), tonumber(b))
end

local function parseColor(input)
  input = tostring(input or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local r, g, b = input:match('^#?(%x%x)(%x%x)(%x%x)$')
  if r then return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) end
  local x, y, z = input:match('^(%d+)%D+(%d+)%D+(%d+)$')
  if x then
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x <= 255 and y <= 255 and z <= 255 then return x, y, z end
  end
  return nil
end

local function currentPreset()
  for _, name in ipairs(PRESET_ORDER) do
    local ok = true
    for k, v in pairs(PRESETS[name]) do
      if not same(cfg[k], v) then ok = false; break end
    end
    if ok then return name end
  end
  return 'Custom'
end

local function keyOf(d)
  if d.legacyKey and tostring(cfg.LyricMode) == 'legacy' then return d.legacyKey end
  return d.key
end

local function valueText(d)
  if d.kind == 'preset' then return currentPreset() end
  local raw = cfg[keyOf(d)]
  if d.kind == 'num' then
    local v = tonumber(raw) or 0
    if d.pct then v = floor(v / 2.55 + 0.5) end
    if d.zero and v == 0 then return d.zero end
    return fmt(v) .. (d.unit or '')
  elseif d.kind == 'toggle' then
    if same(raw, d.on) then return 'On' end
    return 'Off'
  elseif d.kind == 'choice' then
    for _, c in ipairs(d.choices) do
      if same(raw, c.value) then return c.label end
    end
    return tostring(raw)
  elseif d.kind == 'color' then
    return rgbToHex(raw)
  end
  return ''
end

local function statusBang()
  return '[!SetOption Status Text "' .. status .. '"]'
end

local function render()
  local b = {}
  local defs = DEFS[tab]
  for i = 1, ROWS do
    local d = defs[i]
    if d then
      b[#b + 1] = '[!ShowMeterGroup Row' .. i .. '][!SetOption L' .. i .. ' Text "' .. d.label .. '"]'
      if d.kind == 'palette' then
        b[#b + 1] = '[!HideMeterGroup Btn' .. i .. '][!HideMeterGroup Chip' .. i .. '][!HideMeterGroup Sw' .. i .. '][!SetOption V' .. i .. ' Text ""]'
      elseif d.kind == 'color' then
        b[#b + 1] = '[!HideMeterGroup Btn' .. i .. '][!HideMeterGroup Chip' .. i .. '][!ShowMeterGroup Sw' .. i .. ']'
        b[#b + 1] = '[!SetOption V' .. i .. ' X 396][!SetOption V' .. i .. ' Text "' .. valueText(d) .. '"]'
        local r, g, bl = tostring(cfg[keyOf(d)]):match('(%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
        b[#b + 1] = '[!SetOption Sw' .. i .. ' Shape "Rectangle 0,0,56,22,6 | Fill Color ' ..
                    (r or 0) .. ',' .. (g or 0) .. ',' .. (bl or 0) .. ',255 | StrokeWidth 1 | Stroke Color 255,255,255,90"]'
      else
        b[#b + 1] = '[!ShowMeterGroup Btn' .. i .. '][!ShowMeterGroup Chip' .. i .. '][!HideMeterGroup Sw' .. i .. ']'
        b[#b + 1] = '[!SetOption V' .. i .. ' X 360][!SetOption V' .. i .. ' Text "' .. valueText(d) .. '"]'
      end
    else
      b[#b + 1] = '[!HideMeterGroup Row' .. i .. '][!HideMeterGroup Btn' .. i .. '][!HideMeterGroup Chip' .. i ..
                  '][!HideMeterGroup Sw' .. i .. ']'
    end
  end

  -- quick colour palette is only shown on the Colors tab
  local palette = false
  for _, d in ipairs(defs) do if d.kind == 'palette' then palette = true end end
  b[#b + 1] = palette and '[!ShowMeterGroup Pal]' or '[!HideMeterGroup Pal]'

  for t = 1, #TABS do
    local fill = (t == tab) and '150,110,255,235' or '255,255,255,18'
    b[#b + 1] = '[!SetOption Tab' .. t .. ' Shape "Rectangle 0,0,100,26,8 | Fill Color ' .. fill .. ' | StrokeWidth 0"]'
  end
  b[#b + 1] = statusBang()
  b[#b + 1] = '[!UpdateMeter *][!Redraw]'
  SKIN:Bang(table.concat(b))
end

local function touch(note)
  pending = true
  dirtyAt = os.clock() + 0.9
  status = note or 'Applying in a moment...'
  render()
end

local function commit()
  pending = false
  local inc = SKIN:ReplaceVariables('#@#Settings.inc')
  local b = {}
  for _, key in ipairs(ORDER) do
    local v = tostring(cfg[key] or '')
    if v ~= written[key] then
      written[key] = v
      b[#b + 1] = '[!WriteKeyValue Variables "' .. key .. '" "' .. v .. '" "' .. inc .. '"]'
    end
  end
  if #b > 0 then
    b[#b + 1] = '[!Refresh "' .. mainConfig .. '"]'
    SKIN:Bang(table.concat(b))
    status = 'Applied'
  else
    status = 'Up to date'
  end
  SKIN:Bang(statusBang() .. '[!UpdateMeter Status][!Redraw]')
end

-- ---------- called from the skin ----------

function Initialize()
  for key, d in pairs(DEFAULTS) do
    local v = SKIN:GetVariable(key, d)
    if v == nil or v == '' then v = d end
    cfg[key] = tostring(v)
    written[key] = cfg[key]
  end
  local main = SKIN:GetVariable('MainConfig', '')
  if main == nil or main == '' then
    main = (SKIN:GetVariable('CURRENTCONFIG', ''):gsub('Settings$', 'Lyrics'))
  end
  if main ~= '' then mainConfig = main end
end

function Update()
  if not started then
    started = true
    render()
  end
  if pending and os.clock() >= dirtyAt then commit() end
  return 0
end

function Tab(n)
  tab = n
  render()
end

function Step(i, dir)
  local d = DEFS[tab][i]
  if not d then return end
  if d.kind == 'num' then
    local v = tonumber(cfg[keyOf(d)]) or 0
    if d.pct then
      local p = floor(v / 2.55 + 0.5) + dir * d.step
      p = clamp(p, d.min, d.max)
      v = floor(p * 2.55 + 0.5)
    else
      v = clamp(floor((v + dir * d.step) * 100 + 0.5) / 100, d.min, d.max)
    end
    cfg[keyOf(d)] = string.format('%g', v)
  elseif d.kind == 'toggle' then
    if same(cfg[keyOf(d)], d.on) then cfg[keyOf(d)] = d.off else cfg[keyOf(d)] = d.on end
  elseif d.kind == 'choice' then
    local idx = 1
    for n, c in ipairs(d.choices) do
      if same(cfg[keyOf(d)], c.value) then idx = n end
    end
    idx = (idx - 1 + dir) % #d.choices + 1
    cfg[keyOf(d)] = d.choices[idx].value
  elseif d.kind == 'preset' then
    local cur = currentPreset()
    local idx = 0
    for n, name in ipairs(PRESET_ORDER) do if name == cur then idx = n end end
    if idx == 0 then idx = (dir > 0) and 0 or 1 end
    idx = (idx - 1 + dir) % #PRESET_ORDER + 1
    for k, v in pairs(PRESETS[PRESET_ORDER[idx]]) do cfg[k] = v end
  else
    return
  end
  touch()
end

function Edit(i)
  local d = DEFS[tab][i]
  if not d then return end
  if d.kind == 'color' then
    status = 'Type a color like #B48CFF and press Enter'
    render()
    SKIN:Bang('!CommandMeasure', 'mIn' .. d.key, 'ExecuteBatch 1')
  elseif d.kind ~= 'palette' then
    Step(i, 1)
  end
end

function SetHex(key, input)
  local r, g, b = parseColor(input)
  if not r then
    status = 'Could not read that color. Use #RRGGBB'
    render()
    return
  end
  cfg[key] = r .. ',' .. g .. ',' .. b
  local note
  if key ~= 'TextColor' and cfg.ColorMode ~= 'manual' then
    cfg.ColorMode = 'manual'
    note = 'Switched to manual colors. Applying...'
  end
  touch(note)
end

function Palette(j)
  local c = PALETTE[j]
  if not c then return end
  cfg.AccentColor = c[1] .. ',' .. c[2] .. ',' .. c[3]
  cfg.ColorMode = 'manual'
  touch()
end

function Reset()
  for k, v in pairs(DEFAULTS) do cfg[k] = v end
  touch('Reset to the Classic preset and default colors')
end
