#!/usr/bin/env python3
# Copyright (C) 2026 Elzu400
# SPDX-License-Identifier: GPL-3.0-or-later (see LICENSE)
"""Builds the RainmeterLyrics skin folder (and a test tree with ASCII Lua) from templates."""
import os, re, shutil, sys, zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, 'src')
OUT = os.path.join(ROOT, 'out')            # final package tree (Lua saved as UTF-16LE)
TEST = os.path.join(ROOT, 'test_tree')     # same tree but ASCII Lua, for texlua tests

# ---------------------------------------------------------------- settings data
CLASSIC = {
    'PillWidth': '520', 'PillHeight': '74', 'CornerRadius': '20',
    'ShowCover': '1', 'CoverSize': '48', 'CoverRadius': '10', 'Padding': '13', 'CoverGap': '14',
    'FontSize': '15', 'ProgressHeight': '3', 'ProgressBottom': '13', 'TextNudgeY': '4',
    'VisBarWidth': '4', 'VisGap': '3', 'VisHeight': '28',
    'PillRadius': '10', 'PillPadX': '10', 'WordSpacing': '6', 'LineGap': '24',
    'FadeZone': '50', 'FocusPos': '40',
}
SLIM = {
    'PillWidth': '780', 'PillHeight': '52', 'CornerRadius': '24',
    'ShowCover': '1', 'CoverSize': '34', 'CoverRadius': '11', 'Padding': '8', 'CoverGap': '10',
    'FontSize': '13', 'ProgressHeight': '3', 'ProgressBottom': '5', 'TextNudgeY': '2',
    'VisBarWidth': '3', 'VisGap': '3', 'VisHeight': '18',
    'PillRadius': '8', 'PillPadX': '8', 'WordSpacing': '6', 'LineGap': '20',
    'FadeZone': '60', 'FocusPos': '38',
}
COMMON = {
    'ShowProgress': '1', 'RightPanel': 'combined', 'CtlHold': '500', 'FontFace': 'Segoe UI', 'FontWeight': '700',
    'LyricMode': 'paged', 'PageWords': '1', 'PillWords': '1', 'PillStyle': '1', 'PillPadY': '2',
    'CamSmooth': '250', 'PillSpeed': '100', 'LyricsOffset': '0', 'PositionUnit': '1',
    'FPS': '60', 'VisSensitivity': '50', 'Debug': '0', 'LyricsOrder': 'lrclib,kugou,netease',
    'ColorMode': 'manual', 'BgColor': '20,18,28', 'BgAlpha': '166', 'TextColor': '255,255,255',
    'AccentColor': '255,100,160', 'PillAlpha': '107',
    'WallMinSat': '45', 'WallTintBg': '1', 'WallRefreshMin': '0',
}
PALETTE = [(150, 110, 255), (90, 150, 255), (60, 200, 220), (80, 200, 130),
           (230, 190, 70), (255, 140, 70), (255, 100, 160), (200, 200, 215)]

DEFAULTS = {}
DEFAULTS.update(SLIM)                          # the out-of-the-box look is the Slim preset
DEFAULTS.update(COMMON)
ORDER = sorted(DEFAULTS)                      # WallAvg is written only by the lyrics skin


def lua_str(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"


def lua_table(d):
    return '{ ' + ', '.join('%s = %s' % (k, lua_str(v)) for k, v in sorted(d.items())) + ' }'


def lua_data():
    lines = ['local DEFAULTS = ' + lua_table(DEFAULTS),
             'local ORDER = { ' + ', '.join(lua_str(k) for k in ORDER) + ' }',
             'local PRESETS = {',
             '  Classic = ' + lua_table(CLASSIC) + ',',
             '  Slim = ' + lua_table(SLIM) + ',',
             '}',
             "local PRESET_ORDER = { 'Classic', 'Slim' }",
             'local PALETTE = { ' + ', '.join('{ %d, %d, %d }' % c for c in PALETTE) + ' }']
    return '\n'.join(lines)


# ---------------------------------------------------------------- Settings.inc
def settings_inc():
    out = ['[Variables]', '; Written by the Rainmeter Lyrics settings skin. Safe to edit by hand,',
           '; then refresh the lyrics skin.']
    for k in ORDER:
        out.append('%s=%s' % (k, DEFAULTS[k]))
    out.append('; Cached by the lyrics skin (average wallpaper colour)')
    out.append('WallAvg=')
    return '\n'.join(out) + '\n'


# ---------------------------------------------------------------- main skin ini
def main_ini():
    o = []
    a = o.append
    a('''[Rainmeter]
Update=(1000 / #FPS#)
AccurateText=1
DynamicWindowSize=1
ContextTitle=Rainmeter Lyrics settings
ContextAction=[!ActivateConfig "RainmeterLyrics\\Settings" "RainmeterLyricsSettings.ini"]

[Metadata]
Name=Rainmeter Lyrics
Author=Custom
Version=5.0
Information=Pill lyrics for Sonora (LRCLIB + MediaPlayer). Right-click the skin and choose "Rainmeter Lyrics settings".

[Variables]
@Include=#@#Settings.inc
; set at runtime by lyrics.lua
LyricsURL=https://lrclib.net/api/get
LyricsSearchURL=https://lrclib.net/api/search
KgSearchURL=https://lyrics.kugou.com/search
KgLyricsURL=https://lyrics.kugou.com/download
NeSearchURL=https://music.163.com/api/search/get/web
NeLyricsURL=https://music.163.com/api/song/lyric
DimColor=175,175,195,165

; ====================== MEASURES ======================

[mTitle]
Measure=Plugin
Plugin=MediaPlayer.dll
PlayerType=Title
UpdateDivider=10

[mArtist]
Measure=Plugin
Plugin=MediaPlayer.dll
PlayerType=Artist
UpdateDivider=10

[mCover]
Measure=Plugin
Plugin=MediaPlayer.dll
PlayerType=Cover
UpdateDivider=10

[mProgress]
Measure=Plugin
Plugin=MediaPlayer.dll
PlayerType=Progress
UpdateDivider=3

[mPosition]
Measure=Plugin
Plugin=MediaPlayer.dll
PlayerType=Position
UpdateDivider=3

[mDuration]
Measure=Plugin
Plugin=MediaPlayer.dll
PlayerType=Duration
UpdateDivider=10

[mState]
Measure=Plugin
Plugin=MediaPlayer.dll
PlayerType=State
UpdateDivider=3

; ---- audio visualizer (4 bands) ----
[mAudio]
Measure=Plugin
Plugin=AudioLevel
Port=Output
FFTSize=1024
FFTOverlap=512
FFTAttack=40
FFTDecay=220
Bands=8
FreqMin=60
FreqMax=9000
Sensitivity=#VisSensitivity#
''')
    for i in range(8):
        a('''[mBand%d]
Measure=Plugin
Plugin=AudioLevel
Parent=mAudio
Type=Band
BandIdx=%d
''' % (i + 1, i))
    a('''; ---- lyrics download (started by lyrics.lua on every track change) ----
[mLyrics]
Measure=WebParser
URL=#LyricsURL#
UserAgent=RainmeterLyrics (https://github.com/Elzu400/rainmeter-lyrics)
RegExp=(?s)"syncedLyrics":"((?:[^"\\\\]|\\\\.)*)"
StringIndex=1
UpdateRate=-1
DynamicVariables=1
Disabled=1
FinishAction=[!CommandMeasure mScript "OnFetched()"]
OnConnectErrorAction=[!CommandMeasure mScript "OnFailed()"]
OnRegExpErrorAction=[!CommandMeasure mScript "OnFailed()"]
OnDownloadErrorAction=[!CommandMeasure mScript "OnFailed()"]

; ---- fallback: LRCLIB search, used when the exact lookup above finds nothing ----
[mSearch]
Measure=WebParser
URL=#LyricsSearchURL#
UserAgent=RainmeterLyrics (https://github.com/Elzu400/rainmeter-lyrics)
UpdateRate=-1
DynamicVariables=1
Disabled=1
FinishAction=[!CommandMeasure mScript "OnSearched()"]
OnConnectErrorAction=[!CommandMeasure mScript "OnSearchFailed()"]
OnRegExpErrorAction=[!CommandMeasure mScript "OnSearchFailed()"]
OnDownloadErrorAction=[!CommandMeasure mScript "OnSearchFailed()"]

; ---- fallback providers: KuGou (search, download) and NetEase (search, lyric) ----
[mKgS]
Measure=WebParser
URL=#KgSearchURL#
UserAgent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36
UpdateRate=-1
DynamicVariables=1
Disabled=1
FinishAction=[!CommandMeasure mScript "OnKgSearched()"]
OnConnectErrorAction=[!CommandMeasure mScript "OnKgFailed()"]
OnRegExpErrorAction=[!CommandMeasure mScript "OnKgFailed()"]
OnDownloadErrorAction=[!CommandMeasure mScript "OnKgFailed()"]

[mKgL]
Measure=WebParser
URL=#KgLyricsURL#
UserAgent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36
UpdateRate=-1
DynamicVariables=1
Disabled=1
FinishAction=[!CommandMeasure mScript "OnKgLyrics()"]
OnConnectErrorAction=[!CommandMeasure mScript "OnKgFailed()"]
OnRegExpErrorAction=[!CommandMeasure mScript "OnKgFailed()"]
OnDownloadErrorAction=[!CommandMeasure mScript "OnKgFailed()"]

[mNeS]
Measure=WebParser
URL=#NeSearchURL#
UserAgent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36
UpdateRate=-1
DynamicVariables=1
Disabled=1
FinishAction=[!CommandMeasure mScript "OnNeSearched()"]
OnConnectErrorAction=[!CommandMeasure mScript "OnNeFailed()"]
OnRegExpErrorAction=[!CommandMeasure mScript "OnNeFailed()"]
OnDownloadErrorAction=[!CommandMeasure mScript "OnNeFailed()"]

[mNeL]
Measure=WebParser
URL=#NeLyricsURL#
UserAgent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36
UpdateRate=-1
DynamicVariables=1
Disabled=1
FinishAction=[!CommandMeasure mScript "OnNeLyrics()"]
OnConnectErrorAction=[!CommandMeasure mScript "OnNeFailed()"]
OnRegExpErrorAction=[!CommandMeasure mScript "OnNeFailed()"]
OnDownloadErrorAction=[!CommandMeasure mScript "OnNeFailed()"]

; ---- average wallpaper colour (only run when Color source = Wallpaper) ----
[mWall]
Measure=Plugin
Plugin=RunCommand
Program=PowerShell
Parameter=-NoProfile -ExecutionPolicy Bypass -File "#@#wallcolor.ps1"
State=Hide
OutputType=ANSI
Timeout=20000
FinishAction=[!CommandMeasure mScript "OnWallpaper()"]

; ---- everything visual is driven from here ----
[mScript]
Measure=Script
ScriptFile=#@#lyrics.lua

; ====================== METERS ======================

[Background]
Meter=Shape
Shape=Rectangle 0,0,520,74,20 | Fill Color 20,18,28,190 | StrokeWidth 0

; The cover is masked by CoverMask (a rounded rectangle), which is not drawn itself.
[CoverMask]
Meter=Shape
X=13
Y=13
Shape=Rectangle 0,0,48,48,10 | Fill Color 0,0,0,255 | StrokeWidth 0

[Cover]
Meter=Image
MeasureName=mCover
Container=CoverMask
X=0
Y=0
W=48
H=48
PreserveAspectRatio=2
SolidColor=40,35,55,80
DynamicVariables=1

; ---- fallback: title + artist when no synced lyrics are available ----
[TitleText]
Meter=String
MeasureName=mTitle
MeasureName2=mArtist
Text=%1
X=75
Y=8
W=393
H=24
FontFace=#FontFace#
FontSize=14
FontColor=#TextColor#
ClipString=1
AntiAlias=1
UpdateDivider=10
DynamicVariables=1

[ArtistText]
Meter=String
MeasureName=mArtist
X=75
Y=34
W=393
H=19
FontFace=#FontFace#
FontSize=11
FontColor=#DimColor#
ClipString=1
AntiAlias=1
UpdateDivider=10
DynamicVariables=1

; ---- progress bar (positions and sizes are set by lyrics.lua) ----
[ProgressBg]
Meter=Shape
X=75
Y=58
Shape=Rectangle 0,0,393,3,1.5 | Fill Color 255,255,255,28 | StrokeWidth 0

[ProgressFill]
Meter=Shape
X=75
Y=58
Shape=Rectangle 0,0,0.01,3,1.5 | Fill Color 200,170,255 | StrokeWidth 0

; ---- highlight (a squircle path, rewritten every frame by lyrics.lua) ----
[Pill]
Meter=Shape
X=75
Y=18
Shape=Path PillPath | Fill Color 150,110,255,0 | StrokeWidth 0
PillPath=0,0 | LineTo 10,0 | LineTo 10,10 | LineTo 0,10 | ClosePath 1
Group=Lyr
Hidden=1
''')
    for m in range(1, 41):
        a('''[S%d]
Meter=String
Group=Lyr
Hidden=1
X=75
Y=33
FontFace=#FontFace#
FontSize=#FontSize#
FontWeight=#FontWeight#
FontColor=255,255,255,0
StringAlign=LeftCenter
AntiAlias=1
Text=
''' % m)
    a('''; ---- 4 band visualizer ----
[Vis]
Meter=Shape
X=482
Y=23
Shape=Rectangle 0,12,4,3,2 | Fill Color 200,170,255,230 | StrokeWidth 0
Shape2=Rectangle 7,12,4,3,2 | Fill Color 200,170,255,230 | StrokeWidth 0
Shape3=Rectangle 14,12,4,3,2 | Fill Color 200,170,255,230 | StrokeWidth 0
Shape4=Rectangle 21,12,4,3,2 | Fill Color 200,170,255,230 | StrokeWidth 0
Shape5=Rectangle 0,0,0.1,0.1,0 | Fill Color 0,0,0,0 | StrokeWidth 0
Shape6=Rectangle 0,0,0.1,0.1,0 | Fill Color 0,0,0,0 | StrokeWidth 0
Shape7=Rectangle 0,0,0.1,0.1,0 | Fill Color 0,0,0,0 | StrokeWidth 0
Shape8=Rectangle 0,0,0.1,0.1,0 | Fill Color 0,0,0,0 | StrokeWidth 0

; ---- playback buttons (slim layout; Right side = Controls in Settings > Layout) ----
; hover area for the combined visualizer/controls panel
[CtlZone]
Meter=Shape
Hidden=1
X=0
Y=0
Shape=Rectangle 0,0,88,44 | Fill Color 255,255,255,1 | StrokeWidth 0
SolidColor=0,0,0,1
MouseOverAction=[!CommandMeasure mScript "Hover('zone')"]
MouseLeaveAction=[!CommandMeasure mScript "Hover('')"]

[BtnPrev]
Meter=Shape
Group=Ctl
Hidden=1
X=0
Y=0
Shape=Rectangle 0,0,26,26,8 | Fill Color 255,255,255,1 | StrokeWidth 0
SolidColor=0,0,0,1
LeftMouseUpAction=[!CommandMeasure mState "Previous"]
MouseOverAction=[!CommandMeasure mScript "Hover('prev')"]
MouseLeaveAction=[!CommandMeasure mScript "Hover('')"]

[BtnPlay]
Meter=Shape
Group=Ctl
Hidden=1
X=0
Y=0
Shape=Rectangle 0,0,26,26,8 | Fill Color 255,255,255,1 | StrokeWidth 0
SolidColor=0,0,0,1
LeftMouseUpAction=[!CommandMeasure mState "PlayPause"]
MouseOverAction=[!CommandMeasure mScript "Hover('play')"]
MouseLeaveAction=[!CommandMeasure mScript "Hover('')"]

[BtnNext]
Meter=Shape
Group=Ctl
Hidden=1
X=0
Y=0
Shape=Rectangle 0,0,26,26,8 | Fill Color 255,255,255,1 | StrokeWidth 0
SolidColor=0,0,0,1
LeftMouseUpAction=[!CommandMeasure mState "Next"]
MouseOverAction=[!CommandMeasure mScript "Hover('next')"]
MouseLeaveAction=[!CommandMeasure mScript "Hover('')"]

; ---- troubleshooting (Debug=1 in Settings > Motion) ----
[DebugText]
Meter=String
MeasureName=mPosition
MeasureName2=mState
X=0
Y=80
FontFace=Consolas
FontSize=12
FontColor=255,170,170
SolidColor=0,0,0,220
Padding=8,6,8,6
Text=pos: %1 | state: %2
Hidden=1
UpdateDivider=3
''')
    return '\n'.join(o)


SETTINGS_ROWS = 12


# ---------------------------------------------------------------- settings skin ini
def settings_ini():
    W, H = 460, 517
    ROWS = SETTINGS_ROWS
    Y0, DY = 96, 31
    o = []
    a = o.append
    a('''[Rainmeter]
Update=100
AccurateText=1
DynamicWindowSize=1

[Metadata]
Name=Rainmeter Lyrics Settings
Author=Custom
Version=5.0
Information=Settings for the Rainmeter Lyrics skin. Changes apply automatically.

[Variables]
@Include=#@#Settings.inc
MainConfig=RainmeterLyrics\\Lyrics
TxtColor=232,232,242
DimTxt=150,150,170

[mSet]
Measure=Script
ScriptFile=#@#settings.lua
''')
    for key in ('AccentColor', 'BgColor', 'TextColor'):
        a('''[mIn%s]
Measure=Plugin
Plugin=InputText
X=24
Y=400
W=412
H=32
FontFace=Segoe UI
FontSize=13
FontColor=255,255,255
SolidColor=40,36,56
DefaultValue=#RRGGBB
Command1=[!CommandMeasure mSet "SetHex('%s','$UserInput$')"]
''' % (key, key))

    a('''[Bg]
Meter=Shape
Shape=Rectangle 0,0,%d,%d,16 | Fill Color 24,22,32,248 | StrokeWidth 1 | Stroke Color 255,255,255,25

[Title]
Meter=String
X=24
Y=22
FontFace=Segoe UI
FontSize=13
FontWeight=700
FontColor=#TxtColor#
AntiAlias=1
Text=Rainmeter Lyrics - Settings

[CloseBtn]
Meter=Shape
X=%d
Y=14
Shape=Rectangle 0,0,26,26,8 | Fill Color 255,255,255,18 | StrokeWidth 0
LeftMouseUpAction=[!DeactivateConfig]

[CloseTxt]
Meter=String
X=%d
Y=28
FontFace=Segoe UI
FontSize=11
FontColor=#TxtColor#
StringAlign=CenterCenter
AntiAlias=1
Text=x
''' % (W, H, W - 38, W - 25))

    tabs = ['Layout', 'Lyrics', 'Colors', 'Motion']
    for i, name in enumerate(tabs, 1):
        x = 20 + (i - 1) * 106
        a('''[Tab%d]
Meter=Shape
X=%d
Y=48
Shape=Rectangle 0,0,100,26,8 | Fill Color 255,255,255,18 | StrokeWidth 0
LeftMouseUpAction=[!CommandMeasure mSet "Tab(%d)"]

[TabT%d]
Meter=String
X=%d
Y=62
FontFace=Segoe UI
FontSize=10
FontColor=#TxtColor#
StringAlign=CenterCenter
AntiAlias=1
Text=%s
''' % (i, x, i, i, x + 50, name))

    for i in range(1, ROWS + 1):
        y = Y0 + (i - 1) * DY
        a('''[L%(i)d]
Meter=String
X=24
Y=%(yc)d
FontFace=Segoe UI
FontSize=10
FontColor=#TxtColor#
StringAlign=LeftCenter
AntiAlias=1
Group=Row%(i)d
Hidden=1
Text=

[Bv%(i)d]
Meter=Shape
X=312
Y=%(y1)d
Shape=Rectangle 0,0,96,26,7 | Fill Color 255,255,255,16 | StrokeWidth 0
LeftMouseUpAction=[!CommandMeasure mSet "Edit(%(i)d)"]
Group=Chip%(i)d
Hidden=1

[V%(i)d]
Meter=String
X=360
Y=%(yc)d
FontFace=Segoe UI
FontSize=10
FontColor=#TxtColor#
StringAlign=CenterCenter
AntiAlias=1
LeftMouseUpAction=[!CommandMeasure mSet "Edit(%(i)d)"]
Group=Row%(i)d
Hidden=1
Text=

[Bm%(i)d]
Meter=Shape
X=282
Y=%(y1)d
Shape=Rectangle 0,0,24,26,7 | Fill Color 255,255,255,22 | StrokeWidth 0
LeftMouseUpAction=[!CommandMeasure mSet "Step(%(i)d,-1)"]
Group=Btn%(i)d
Hidden=1

[Tm%(i)d]
Meter=String
X=294
Y=%(yc)d
FontFace=Segoe UI
FontSize=12
FontColor=#TxtColor#
StringAlign=CenterCenter
AntiAlias=1
Group=Btn%(i)d
Hidden=1
Text=-

[Bp%(i)d]
Meter=Shape
X=414
Y=%(y1)d
Shape=Rectangle 0,0,24,26,7 | Fill Color 255,255,255,22 | StrokeWidth 0
LeftMouseUpAction=[!CommandMeasure mSet "Step(%(i)d,1)"]
Group=Btn%(i)d
Hidden=1

[Tp%(i)d]
Meter=String
X=426
Y=%(yc)d
FontFace=Segoe UI
FontSize=12
FontColor=#TxtColor#
StringAlign=CenterCenter
AntiAlias=1
Group=Btn%(i)d
Hidden=1
Text=+

[Sw%(i)d]
Meter=Shape
X=296
Y=%(y2)d
Shape=Rectangle 0,0,56,22,6 | Fill Color 150,110,255,255 | StrokeWidth 1 | Stroke Color 255,255,255,90
LeftMouseUpAction=[!CommandMeasure mSet "Edit(%(i)d)"]
Group=Sw%(i)d
Hidden=1
''' % {'i': i, 'y1': y + 1, 'y2': y + 3, 'yc': y + 14})

    ypal = Y0 + 9 * DY       # palette sits in row 10 on the Colors tab
    for j, (r, g, b) in enumerate(PALETTE, 1):
        a('''[P%d]
Meter=Shape
X=%d
Y=%d
Shape=Rectangle 0,0,26,26,7 | Fill Color %d,%d,%d,255 | StrokeWidth 1 | Stroke Color 255,255,255,70
LeftMouseUpAction=[!CommandMeasure mSet "Palette(%d)"]
Group=Pal
Hidden=1
''' % (j, 170 + (j - 1) * 32, ypal + 1, r, g, b, j))

    a('''[Status]
Meter=String
X=24
Y=%d
FontFace=Segoe UI
FontSize=9
FontColor=#DimTxt#
AntiAlias=1
Text=Changes apply automatically

[ResetBtn]
Meter=Shape
X=336
Y=%d
Shape=Rectangle 0,0,100,26,8 | Fill Color 255,255,255,18 | StrokeWidth 0
LeftMouseUpAction=[!CommandMeasure mSet "Reset()"]

[ResetTxt]
Meter=String
X=386
Y=%d
FontFace=Segoe UI
FontSize=10
FontColor=#TxtColor#
StringAlign=CenterCenter
AntiAlias=1
Text=Reset all
''' % (H - 36, H - 44, H - 31))
    return '\n'.join(o)


WALLCOLOR = r'''# Prints the average colour of the current desktop wallpaper as "R,G,B".
# Used by the Rainmeter Lyrics skin (Color source = Wallpaper). Prints nothing on failure.
try {
    Add-Type -AssemblyName System.Drawing
    $files = @()
    $t = Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'
    if (Test-Path $t) { $files += $t }
    $reg = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).WallPaper
    if ($reg -and (Test-Path $reg)) { $files += $reg }
    foreach ($f in $files) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($f)
            $ms = New-Object System.IO.MemoryStream(, $bytes)
            $img = [System.Drawing.Image]::FromStream($ms)
            $bmp = New-Object System.Drawing.Bitmap 48, 27
            $gfx = [System.Drawing.Graphics]::FromImage($bmp)
            $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $gfx.DrawImage($img, 0, 0, 48, 27)
            $gfx.Dispose(); $img.Dispose(); $ms.Dispose()
            $sr = 0; $sg = 0; $sb = 0; $n = 0
            for ($y = 0; $y -lt 27; $y++) {
                for ($x = 0; $x -lt 48; $x++) {
                    $c = $bmp.GetPixel($x, $y)
                    $sr += $c.R; $sg += $c.G; $sb += $c.B; $n++
                }
            }
            $bmp.Dispose()
            '{0},{1},{2}' -f [int]($sr / $n), [int]($sg / $n), [int]($sb / $n)
            exit 0
        } catch { continue }
    }
} catch { }
exit 1
'''

README = '''SONORA LYRICS 5.0
=================

INSTALL
  1. Unload any older "Rainmeter Lyrics" skin in the Rainmeter manager.
  2. Copy the whole RainmeterLyrics folder into  Documents\\Rainmeter\\Skins\\
     (keep the folder name "RainmeterLyrics").
  3. In the Rainmeter manager press "Refresh all", then load
         RainmeterLyrics\\Lyrics\\RainmeterLyrics.ini

SETTINGS
  Right-click the skin > "Rainmeter Lyrics settings"  (or load RainmeterLyrics\\Settings\\RainmeterLyricsSettings.ini).
  Changes apply by themselves about a second after your last click.
    Layout : presets (Classic / Slim), size, cover, right side (visualizer / controls / combined), progress bar
    Lyrics : lyric style (Paged = calm, default / Scrolling = the old continuous scroll),
             font, words per highlight, highlight position/shape, spacing, timing offset
    Colors : manual colors or the average color of your wallpaper
    Motion : frame rate (default 60), smoothness, visualizer sensitivity, debug overlay

LYRIC STYLES
  Paged (default): one lyric line sits still; a ~2 word highlight glides across it.
    The line only shifts a little when it is too long for the bar, and lines
    cross-fade into each other. Words per highlight sets the highlight width.
  Scrolling (legacy): the previous behaviour, text scrolls continuously.
    Words per highlight and Focus position apply to this style.

FILES
  @Resources\\Settings.inc   all settings (written by the settings skin)
  @Resources\\lyrics.lua     the lyric strip, highlight, progress bar, visualizer
  @Resources\\settings.lua   the settings window logic
  @Resources\\wallcolor.ps1  reads the average wallpaper color (PowerShell, no install needed)
'''


def write(path, text, encoding='utf-8'):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding=encoding, newline='\n') as f:
        f.write(text)


def build_tree(base, utf16):
    shutil.rmtree(base, ignore_errors=True)
    skin = os.path.join(base, 'RainmeterLyrics')
    res = os.path.join(skin, '@Resources')
    enc = 'utf-16' if utf16 else 'utf-8'     # python's utf-16 writes a BOM + little endian

    with open(os.path.join(SRC, 'lyrics.lua'), encoding='utf-8') as f:
        lyrics = f.read()
    with open(os.path.join(SRC, 'settings.lua.tpl'), encoding='utf-8') as f:
        settings = f.read().replace('--@@DATA@@', lua_data())

    # every settings tab must fit the rows the settings skin has (extra rows are silently dropped)
    tabs = re.split(r'(?m)^  \{ -- ', settings.split('local DEFS = {', 1)[1].split('\n}\n', 1)[0])[1:]
    for t in tabs:
        n = len(re.findall(r'(?m)^    \{ label = ', t))
        if n > SETTINGS_ROWS:
            raise SystemExit('settings tab "%s" has %d rows, the settings skin only has %d' % (t.split()[0], n, SETTINGS_ROWS))

    for name, text in (('lyrics.lua', lyrics), ('settings.lua', settings)):
        if utf16:
            text.encode('ascii')             # sources must stay ASCII
        write(os.path.join(res, name), text, enc)
    write(os.path.join(res, 'Settings.inc'), settings_inc())
    write(os.path.join(res, 'wallcolor.ps1'), WALLCOLOR)
    lic = os.path.join(ROOT, 'LICENSE')
    if os.path.exists(lic):
        shutil.copyfile(lic, os.path.join(skin, 'LICENSE.txt'))
    write(os.path.join(skin, 'Lyrics', 'RainmeterLyrics.ini'), main_ini())
    write(os.path.join(skin, 'Settings', 'RainmeterLyricsSettings.ini'), settings_ini())
    write(os.path.join(skin, 'README.txt'), README)
    for root, _, files in os.walk(skin):
        for fn in files:
            if fn.endswith(('.ini', '.inc')):
                with open(os.path.join(root, fn), 'rb') as f:
                    f.read().decode('ascii')    # ini/inc must be plain ASCII
    return skin


if __name__ == '__main__':
    build_tree(TEST, utf16=False)
    skin = build_tree(OUT, utf16=True)
    zpath = os.path.join(ROOT, 'RainmeterLyrics.zip')
    if os.path.exists(zpath):
        os.remove(zpath)
    with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(skin):
            for fn in sorted(files):
                full = os.path.join(root, fn)
                z.write(full, os.path.relpath(full, OUT))
    print('built', zpath)
