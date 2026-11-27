# Third-party software and services

Rainmeter Lyrics is licensed under the GNU GPL v3 or later (see `LICENSE`).
It builds on the following. None of their source code is part of this repository.

## Rainmeter plugin: MediaPlayer

- Project: https://github.com/i2002/RainmeterMediaPlayer
- License: GPL-3.0 (see the license file in that repository)
- Used for: song title, artist, cover art, position, duration and play state.

If you distribute a release package that includes `MediaPlayer.dll`:

1. Include the plugin's license text next to it (for example `LICENSE-MediaPlayer.txt`).
2. Say where its source code can be obtained: the repository above, and the version you
   bundled.
3. Do not alter the DLL and present it as the original.

## Rainmeter plugins that ship with Rainmeter

WebParser, AudioLevel, RunCommand, InputText and the Script (Lua) measure are part of
Rainmeter itself (https://www.rainmeter.net, GPL-2.0). Nothing from them is bundled here.

## LRCLIB (lyrics)

- https://lrclib.net
- Synced lyrics are fetched from its public API at runtime. No lyrics are stored in or
  shipped with this repository. Lyrics are the property of their respective rights
  holders. Please be considerate with request volume; the skin only asks once per track.
