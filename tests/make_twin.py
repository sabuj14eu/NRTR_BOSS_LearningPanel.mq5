#!/usr/bin/env python3
"""Regenerate the forex twin from the crypto file: every line is copied
from crypto except the lines tests/check_twins.py allows to differ (the
header filename line, the #property description lines, the NB_MARKET
define), which keep the forex file's own text, in order.

usage: python3 tests/make_twin.py   (from the repository root)"""
import re
import sys

A, B = "NRTR_BOSS_Crypto_NYTrap.mq5", "NRTR_BOSS_Forex_NYTrap.mq5"
ALLOWED = [re.compile(r"^//\|\s+NRTR_BOSS_\w+\.mq5 \|$"), re.compile(r"^#property description "),
           re.compile(r"^#define NB_MARKET NB_MKT_(CRYPTO|FOREX)$")]


def allowed(line):
    return any(p.match(line) for p in ALLOWED)


def main() -> int:
    a = open(A, encoding="ascii").read().split("\n")
    b = open(B, encoding="ascii").read().split("\n")
    own = [l for l in b if allowed(l)]
    slots = [i for i, l in enumerate(a) if allowed(l)]
    if len(own) != len(slots):
        print(f"MAKE TWIN: FAIL - {len(slots)} allowed lines in {A}, {len(own)} in {B}")
        return 1
    for i, l in zip(slots, own):
        a[i] = l
    open(B, "w", encoding="ascii").write("\n".join(a))
    print(f"MAKE TWIN: {B} regenerated from {A} ({len(slots)} own lines kept)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
