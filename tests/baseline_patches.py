#!/usr/bin/env python3
"""Declared behaviour fixes applied to the v1.04 BASELINE before the
"existing panel unchanged" comparison, so that comparison keeps proving
that NOTHING ELSE changed. Each patch is the same text change as in the
current file, must match exactly once, and is listed in CHANGELOG.md.

usage: baseline_patches.py <tag> <baseline.mq5>   (patches in place; tag gold only)"""
import sys

PATCHES = {
    "gold": [
        # v1.10 audit #3: the first NRTR-ready bar is not a flip
        ("      bool flipHere = (ad != prevAd);",
         "      bool flipHere = (prevAd != 0 && ad != prevAd);   // v1.10: the first NRTR-ready bar is not a flip"),
        # v1.10 audit #1: the live-price CLICK wording (the TOO FAR state has no baseline equivalent: it shows as a difference)
        ('      st = NbSymUp() + "  CLICK BUY";', '      st = NbSymUp() + "  READY - CLICK BUY";'),
        ('      st = NbSymDown() + "  CLICK SELL";', '      st = NbSymDown() + "  READY - CLICK SELL";'),
        # v1.10 audit #4: no "---" pending line when the 5M is against the boss
        ('''      if(m15 == NB_BUY)
      {
         pLim = "BUY LIMIT near 5M NRTR stop "''', '''      if(m15 == NB_BUY && d5 <= 0)
      {
         pLim = "5M AGAINST - WAIT FOR 5M BULLISH RE-ALIGNMENT";   // v1.10: no limit price without a bullish 5M
         pStp = "BUY STOP above 15M channel " + NbPx(up15) + "  (breakout)";
      }
      else if(m15 == NB_SELL && d5 >= 0)
      {
         pLim = "5M AGAINST - WAIT FOR 5M BEARISH RE-ALIGNMENT";
         pStp = "SELL STOP below 15M channel " + NbPx(lo15) + "  (breakout)";
      }
      else if(m15 == NB_BUY)
      {
         pLim = "BUY LIMIT near 5M NRTR stop "'''),
    ],
}


def main() -> int:
    tag, path = sys.argv[1], sys.argv[2]
    patches = PATCHES.get(tag, [])
    if not patches:
        return 0
    s = open(path, encoding="utf-8", errors="replace").read()
    for old, new in patches:
        if s.count(old) != 1:
            print(f"BASELINE PATCH: anchor not found exactly once in {path}: {old[:60]!r}")
            return 1
        s = s.replace(old, new)
    open(path, "w", encoding="utf-8").write(s)
    print(f"BASELINE PATCHES ({tag}): {len(patches)} declared v1.10 fixes applied to the v1.04 baseline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
