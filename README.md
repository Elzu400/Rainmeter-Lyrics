# Rainmeter Lyrics

A Rainmeter skin that shows **synced lyrics** for whatever is playing in the
Sonora music player (or any player that Windows exposes through its
media controls). It sits on your desktop as a rounded pill with the album cover, the
current lyric line, a progress bar and a small 4-band audio visualizer.

<img width="842" height="63" alt="RainmeterLyrics" src="https://github.com/user-attachments/assets/54bcd47e-33c3-4e06-bb48-57ace9e1fdc6" />

## Features

- Synced lyrics from [LRCLIB](https://lrclib.net). If the exact lookup finds nothing, it tries
  LRCLIB's search (tolerant of "feat.", "- Live" and spelling differences, and matched by song
  length so the wrong version is rejected). If LRCLIB has nothing it tries **KuGou**,
  and finally shows the song title and artist. Each step is only used when the previous one
  found nothing, and a hit must match the song's title and length.
- **Word-synced lyrics:** when LRCLIB has a word-by-word version of a song (its "lyricsfile"),
  the highlight follows the real words. If the first match is only line-synced, the skin
  shows it straight away and looks for a word-synced version in the background, swapping it in
  if one is found. A swap only happens for the same artist and a similar number of lines, so a
  same-named song by someone else is ignored. Otherwise (and for KuGou) the words are spread over each line automatically.
- **Quick settings and per-song timing:** hover the album cover and a small button fades in
  (same fade and hide delay as the playback buttons). Click it for a menu with a timing slider
  for the current song (-2 to +2 s, snapping to 0.1 s) and a box for any value (like `-1` or `3.4`,
  no limit). The offset is saved per song in `@Resources\SongOffsets.txt` and used again the next
  time that song plays. It adds to the global timing offset in Settings > Lyrics. The menu also has
  a shortcut to the full settings. More quick settings will live there later.
- **Testing the lyric sources:** in Settings > Lyrics, "Lyric sources (testing)" sets the
  order, or limits the skin to one source (e.g. "KuGou only"). Turn on Settings > Motion >
  "Debug overlay" and the overlay lists, per song, what each source answered: request failed,
  answered with no match (and how many bytes / results came back), or lyrics loaded. The same
  lines go to Rainmeter's log. Set a source to "only" and play a song that LRCLIB has: if lyrics
  appear, that source works.
- **Paged lyric style (default):** one line stays still while a highlight glides across
  its words. Long lines shift only as much as needed; lines cross-fade into each other.
  Calm, with no constant scrolling.
- **Scrolling (legacy) style:** the original continuously scrolling strip, one switch away.
- A music note for instrumental gaps and pauses.
- Optional **playback controls** (previous, play/pause, next) in place of the visualizer, for the Slim layout.
- **Combined** mode (Slim): shows the visualizer, (8 bars, sized to fill the space the buttons use) swaps to the controls while the mouse is over it, and goes back after a short delay (adjustable on the Motion tab).
- Smooth progress bar and a 4-band visualizer.
- A built-in settings window: size, presets (**Slim** is the default, **Classic** is the original taller look), fonts, highlight
  shape, timing offset, colors, frame rate (60 fps by default).
- Colors: choose them by hand, or average them from your wallpaper.

## Requirements

- Windows 10 or 11 and a recent [Rainmeter](https://www.rainmeter.net/).
- The [MediaPlayer skin and plugin](https://github.com/i2002/RainmeterMediaPlayer) by i2002.
  Install its `media_player.rmskin` from that project's Releases page **before** Rainmeter Lyrics.
  The plugin is what reads the title, artist, cover and position from your player.
- An internet connection for fetching lyrics.

## Installation
1. Install the MediaPlayer skin/plugin (see Requirements) and restart Rainmeter once.
2. Download the latest `.rmskin` from the [Releases](../../releases) page and open it.
   Rainmeter installs it for you.
3. In Rainmeter's manager load `RainmeterLyrics\Lyrics\RainmeterLyrics.ini`.
4. Right-click the skin and choose the settings entry, or load
   `RainmeterLyrics\Settings\RainmeterLyricsSettings.ini`, to adjust it.

**Upgrading from the old `SonoraLyrics` skin?** Unload it in Rainmeter and delete the old
`SonoraLyrics` folder from `Documents\Rainmeter\Skins`; settings don't carry over.

**Title/lyrics don't show up?** Make sure the MediaPlayer skin from the link above is
installed. Rainmeter Lyrics needs its plugin.

Settings are saved to `@Resources\Settings.inc`. Changes apply about a second after your
last click.

## Settings overview

| Tab | What it controls |
| --- | --- |
| Layout | Presets, width/height, album cover, right side (visualizer / playback controls / combined / nothing), progress bar |
| Lyrics | Lyric style (Paged or Scrolling), font, words per highlight, highlight shape, spacing, timing offset |
| Colors | Manual colors or wallpaper average, opacity |
| Motion | Frame rate, smoothness, visualizer sensitivity, debug overlay |

If lyrics are early or late, adjust **Lyrics timing offset** on the Lyrics tab. For
troubleshooting, turn on **Debug overlay** on the Motion tab.

## Building from source

The skin is generated from the files in `src/` by a small Python script (Python 3, no
extra packages):

```
python build.py
```

This creates `out/RainmeterLyrics/` (the finished skin folder) and `RainmeterLyrics.zip`.
To make a `.rmskin`, follow Rainmeter's packaging steps with the `out/RainmeterLyrics`
folder.

**Important:** Rainmeter needs Lua scripts saved as UTF-16 (little endian, with BOM),
otherwise non-English lyrics and the music note show up garbled. That is why the Lua
sources in `src/` are kept pure ASCII and `build.py` converts them when packaging. Don't
copy the files from `src/` straight into your Rainmeter folder. Always use the output of
the build.

## Tests

The Lua logic is checked with a mock Rainmeter environment (needs `texlua` or any Lua 5.3):

```
python build.py
texlua test/mock_main.lua test_tree classic 90
texlua test/mock_main.lua test_tree slim 90
texlua test/mock_settings.lua test_tree
texlua test/mock_offsets.lua test_tree
python3 test/check_lua51.py test_tree/RainmeterLyrics/@Resources/*.lua
```

The last command checks the limits of Lua 5.1, the version Rainmeter embeds (for example at most 60
upvalues per function). A script over a limit fails to load in Rainmeter even though the mock tests,
which run on a newer Lua, pass. It needs `texluac` or `luac`.

These tests catch logic errors, but they cannot reproduce real Rainmeter rendering. Please
report anything that looks off on a real desktop.

## Contributing

Issues and pull requests are welcome. Please keep `src/*.lua` ASCII-only, run the tests
above before opening a pull request, and say which Rainmeter and plugin versions you used.
By contributing you agree that your contribution is licensed under the same license as
the project.

## License

Copyright (C) 2026 Elzu400. Rainmeter Lyrics is licensed under the
**GNU General Public License v3.0 or later**. See [LICENSE](LICENSE).
In short: you can use, change and share it, but if you distribute a modified version it
must stay open source under the same license.

Third-party components and services (MediaPlayer plugin, LRCLIB) are listed in
[THIRD_PARTY.md](THIRD_PARTY.md).

## Credits

- Lyrics: [LRCLIB](https://lrclib.net)
- Media information: [RainmeterMediaPlayer](https://github.com/i2002/RainmeterMediaPlayer) by i2002
- [Rainmeter](https://www.rainmeter.net)

## AI disclosure

This project was developed with substantial help from an AI assistant (Anthropic's Claude),
which wrote much of the code and documentation under my direction. I tested and reviewed
the result on my own setup, but it may contain mistakes. Please report any issues you find.
