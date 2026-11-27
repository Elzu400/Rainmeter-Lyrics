-- Tests offsets.lua (per-song offsets) and quick.lua (the quick settings window) with a fake Rainmeter.
-- Usage: texlua test/mock_offsets.lua test_tree
local tree = arg[1] or 'test_tree'
local res = tree .. '/RainmeterLyrics/@Resources/'
local tmp = os.tmpname() .. '_res/'
os.execute('mkdir -p ' .. tmp)

local fails, bangs = 0, {}
local function check(cond, msg)
  if not cond then fails = fails + 1; print('FAIL: ' .. msg) end
end

local title, artist = 'Ghost Party', 'overtonight'
local function newSkin(vars)
  local S = {}
  function S:ReplaceVariables(s)
    s = s:gsub('#@#', tmp)
    for k, v in pairs({ CURRENTCONFIGX = 100, CURRENTCONFIGY = 50, CURRENTCONFIGHEIGHT = 60, SCREENAREAHEIGHT = 1080 }) do
      s = s:gsub('#' .. k .. '#', tostring(v))
    end
    return s
  end
  function S:GetVariable(k, d) return (vars and vars[k]) or d end
  function S:GetMeasure(n)
    if n == 'mTitle' then return { GetStringValue = function() return title end } end
    if n == 'mArtist' then return { GetStringValue = function() return artist end } end
  end
  function S:Bang(...)
    local t = { ... }
    for i = 1, #t do t[i] = tostring(t[i]) end
    bangs[#bangs + 1] = table.concat(t, ' | ')
  end
  return S
end

local function load(file, vars)
  local env = setmetatable({}, { __index = _G })
  env.SKIN = newSkin(vars)
  local f = assert(loadfile(res .. file, 't', env))
  f()
  return env
end

local function readFile(p)
  local f = io.open(p, 'r'); if not f then return nil end
  local s = f:read('*a'); f:close(); return s
end

-- ---------------- offsets.lua ----------------
local o = load('offsets.lua')
o.Initialize()
check(o.Update() == 0, 'new song starts at 0')
local q = readFile(tmp .. 'Quick.txt')
check(q and q:find('QKey=overtonight|ghostparty', 1, true), 'Quick.txt has the song key')
check(q:find('QName=overtonight - Ghost Party', 1, true), 'Quick.txt has the name')
check(q:find('QX=100') and q:find('QY=118'), 'quick window goes below the lyrics: ' .. q:gsub('\n', ' '))

o.Preview('1.3')
check(o.Update() == 1.3, 'preview applies without saving')
check(readFile(tmp .. 'SongOffsets.txt') == nil, 'preview does not write the file')
o.Set('1.3')
local saved = readFile(tmp .. 'SongOffsets.txt')
check(saved and saved:find('overtonight|ghostparty\t1.3\tovertonight - Ghost Party', 1, true), 'Set writes the file: ' .. tostring(saved))

-- another song, then back; and a fresh start of the script reloads the file
title, artist = 'Other Song', 'Somebody'
check(o.Update() == 0, 'other song has its own offset')
o.Set('-2.75')
title, artist = 'Ghost Party (Remastered 2020)', 'Overtonight'
check(o.Update() == 1.3, 'same song with another case/suffix finds the saved offset')
local o2 = load('offsets.lua')
o2.Initialize()
check(o2.Update() == 1.3, 'offset survives a restart')
title = 'Other Song'; artist = 'Somebody'
check(o2.Update() == -2.75, 'second song restored too')
o2.Set('7.5')
check(o2.Update() == 7.5, 'values beyond the slider are fine')
o2.Set('0')
check(o2.Update() == 0, 'zero removes the entry')
check(not (readFile(tmp .. 'SongOffsets.txt') or ''):find('somebody|othersong', 1, true), 'zero line is gone from the file')

bangs = {}
o2.Open()
check(bangs[1] and bangs[1]:find('!ToggleConfig | RainmeterLyrics\\Quick | RainmeterLyricsQuick.ini', 1, true), 'Open toggles the quick skin: ' .. tostring(bangs[1]))

-- nothing playing
title, artist = '', ''
check(o2.Update() == 0, 'no song, no offset')
o2.Set('3')
check(o2.Update() == 0, 'cannot set an offset without a song')

-- ---------------- quick.lua ----------------
title, artist = 'Ghost Party', 'overtonight'
o2.Update()
local k = load('quick.lua', { MainConfig = 'RainmeterLyrics\\Lyrics' })
bangs = {}
k.Initialize()
k.Update()
local joined = table.concat(bangs, '\n')
check(joined:find('!Move | 100 | 118', 1, true), 'quick window moves next to the lyrics')
check(joined:find('Text "overtonight - Ghost Party"', 1, true), 'shows the song')
check(joined:find('V Text "+1.3 s"', 1, true), 'shows the saved offset')

bangs = {}
k.Down(30)                                   -- +1.0 s
check(table.concat(bangs, '\n'):find('!CommandMeasure | mOffsets | Preview(1.000) | RainmeterLyrics\\Lyrics', 1, true), 'pressing the slider previews 1.0')
bangs = {}
k.Over(35)
check(table.concat(bangs, '\n'):find('Preview(1.500)', 1, true), 'dragging snaps to 1.5')
bangs = {}
k.Over(35)
check(#bangs == 0, 'no repeat while on the same notch')
k.Over(0)
check(table.concat(bangs, '\n'):find('Preview(-2.000)', 1, true), 'left end is -2.0')
bangs = {}
k.Up()
check(table.concat(bangs, '\n'):find('Set(-2.000)', 1, true), 'letting go saves: ' .. table.concat(bangs, ' / '))
bangs = {}
k.Over(10)
check(#bangs == 0, 'moving without pressing does nothing')

-- dragging out of the window ends the drag after a short moment
k.Down(25); k.Leave()
bangs = {}
local t0 = os.clock()
while os.clock() - t0 < 0.3 do end
k.Update()
check(table.concat(bangs, '\n'):find('Set(0.500)', 1, true), 'leaving the slider while pressed saves at the last notch')

-- typed values, no limit
for _, c in ipairs({ { '-1', 'Set(-1.000)' }, { '2.1', 'Set(2.100)' }, { '+0,3 s', 'Set(0.300)' }, { '12.5', 'Set(12.500)' }, { '-30', 'Set(-30.000)' } }) do
  bangs = {}
  k.Typed(c[1])
  check(table.concat(bangs, '\n'):find(c[2], 1, true), 'typed "' .. c[1] .. '" -> ' .. c[2])
end
bangs = {}
k.Typed('abc')
check(not table.concat(bangs, '\n'):find('Set(', 1, true), 'rubbish is ignored')
check(table.concat(bangs, '\n'):find('Type a number', 1, true), 'rubbish gets a hint')

-- slider position beyond the ends stays on the track
bangs = {}
k.Typed('12.5')
check(table.concat(bangs, '\n'):find('Ellipse 332.0,17,8', 1, true), 'thumb stops at the right end for +12.5')
k.Typed('-30')
check(table.concat(bangs, '\n'):find('Ellipse 28.0,17,8', 1, true), 'thumb stops at the left end')

-- the song changes while the window is open
title, artist = 'Other Song', 'Somebody'
o2.Update()
bangs = {}
for _ = 1, 6 do k.Update() end
check(table.concat(bangs, '\n'):find('Somebody - Other Song', 1, true), 'window follows the playing song')

-- shortcut to the full settings
bangs = {}
k.OpenSettings()
local s = table.concat(bangs, '\n')
check(s:find('!ActivateConfig | RainmeterLyrics\\Settings | RainmeterLyricsSettings.ini', 1, true), 'opens the full settings')
check(s:find('!DeactivateConfig', 1, true), 'closes the quick window')

os.execute('rm -rf ' .. tmp)
print(fails == 0 and 'offsets/quick: all checks passed' or ('offsets/quick: ' .. fails .. ' FAILED'))
os.exit(fails == 0 and 0 or 1)
