# SonoraLyrics

A Rainmeter skin that shows **synced lyrics** for whatever is playing in the
Sonora music player (or any player that Windows exposes through its
media controls). It sits on your desktop as a rounded pill with the album cover, the
current lyric line, a progress bar and a small 4-band audio visualizer.

> Add a screenshot or GIF here: put it in `docs/` and link it, e.g. `![preview](docs/preview.png)`.

## Features

- Synced lyrics from [LRCLIB](https://lrclib.net), falling back to the song title and
  artist when no lyrics are found.
- **Paged lyric style (default):** one line stays still while a highlight glides across
  its words. Long lines shift only as much as needed; lines cross-fade into each other.
  Calm, with no constant scrolling.
- **Scrolling (legacy) style:** the original continuously scrolling strip, one switch away.
- A music note for instrumental gaps and pauses.
- Smooth progress bar and a 4-band visualizer.
- A built-in settings window: size, presets (**Classic** and **Slim**), fonts, highlight
  shape, timing offset, colors, frame rate (60 fps by default).
- Colors: choose them by hand, or average them from your wallpaper.

## Requirements

- Windows 10 or 11 and a recent [Rainmeter](https://www.rainmeter.net/).
- The [MediaPlayer plugin](https://github.com/i2002/RainmeterMediaPlayer) (`MediaPlayer.dll`)
  in your Rainmeter `Plugins` folder. Release packages may already include it.
- An internet connection for fetching lyrics.

## Installation

1. Download the latest `.rmskin` from the [Releases](../../releases) page and open it.
   Rainmeter installs it for you.
2. In Rainmeter's manager load `SonoraLyrics\Lyrics\SonoraLyrics.ini`.
3. Right-click the skin and choose the settings entry, or load
   `SonoraLyrics\Settings\SonoraSettings.ini`, to adjust it.

Settings are saved to `@Resources\Settings.inc`. Changes apply about a second after your
last click.

## Settings overview

| Tab | What it controls |
| --- | --- |
| Layout | Presets, width/height, album cover, visualizer, progress bar |
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

This creates `out/SonoraLyrics/` (the finished skin folder) and `SonoraLyrics.zip`.
To make a `.rmskin`, follow Rainmeter's packaging steps with the `out/SonoraLyrics`
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
```

These tests catch logic errors, but they cannot reproduce real Rainmeter rendering. Please
report anything that looks off on a real desktop.

## Contributing

Issues and pull requests are welcome. Please keep `src/*.lua` ASCII-only, run the tests
above before opening a pull request, and say which Rainmeter and plugin versions you used.
By contributing you agree that your contribution is licensed under the same license as
the project.

## License

Copyright (C) 2026 the SonoraLyrics authors. Licensed under the
**GNU General Public License v3.0 or later**. See [LICENSE](LICENSE).
In short: you can use, change and share it, but if you distribute a modified version it
must stay open source under the same license.

Third-party components and services (MediaPlayer plugin, LRCLIB) are listed in
[THIRD_PARTY.md](THIRD_PARTY.md).

## Credits

- Lyrics: [LRCLIB](https://lrclib.net)
- Media information: [RainmeterMediaPlayer](https://github.com/i2002/RainmeterMediaPlayer) by i2002
- [Rainmeter](https://www.rainmeter.net)
