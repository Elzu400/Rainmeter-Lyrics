# Copyright (C) 2026 Elzu400
# SPDX-License-Identifier: GPL-3.0-or-later (see LICENSE)
"""Static checks for the limits of Lua 5.1, the version Rainmeter embeds.

The mock tests run on a newer Lua, which is more forgiving. A Lua 5.1 script that breaks
one of these limits fails to load in Rainmeter, and then nothing the script does works
(no lyrics, progress bar or visualizer) while plain meters such as title and cover still show.

usage: python3 test/check_lua51.py test_tree/RainmeterLyrics/@Resources/lyrics.lua [...]
needs `texluac` (TeX Live) or `luac`.
"""
import re
import shutil
import subprocess
import sys

MAX_UPVALUES = 55      # Lua 5.1 allows 60 per function; keep a margin
MAX_LOCALS = 180       # Lua 5.1 allows 200 per function
BANNED = [r'\bgoto\b', r'\btable\.unpack\b', r'\butf8\.', r'\bmath\.type\b', r'\bstring\.pack\b',
          r'\bbit32\.', r'\bmath\.tointeger\b', r'[^/]//[^/]']


def main(files):
    luac = shutil.which('texluac') or shutil.which('luac')
    if not luac:
        print('texluac/luac not found; cannot check limits')
        return 2
    bad = 0
    for f in files:
        out = subprocess.run([luac, '-l', '-p', '-o', '/dev/null', f], capture_output=True, text=True).stdout
        cur, worst_up, worst_loc = None, (0, ''), (0, '')
        for line in out.splitlines():
            m = re.match(r'(main|function) <[^:]*:(\d+),(\d+)>', line)
            if m:
                cur = '%s at line %s' % (m.group(1), m.group(2))
            m = re.match(r'\s*\d+\+? params?, \d+ slots?, (\d+) upvalues?, (\d+) locals?', line)
            if m and cur:
                up, loc = int(m.group(1)), int(m.group(2))
                if up > worst_up[0]: worst_up = (up, cur)
                if loc > worst_loc[0]: worst_loc = (loc, cur)
        print('%s: max upvalues %d (%s), max locals %d (%s)' % (f, worst_up[0], worst_up[1], worst_loc[0], worst_loc[1]))
        if worst_up[0] > MAX_UPVALUES or worst_loc[0] > MAX_LOCALS:
            print('  FAIL: over the Lua 5.1 safety limits')
            bad += 1
        code = re.sub(r'--[^\n]*', '', open(f, encoding='utf-8', errors='replace').read())
        code = re.sub(r"'(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\"", "''", code)
        for pat in BANNED:
            if re.search(pat, code):
                print('  FAIL: uses a Lua 5.2+ feature matching', pat)
                bad += 1
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
