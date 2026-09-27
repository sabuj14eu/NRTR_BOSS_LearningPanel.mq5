#!/usr/bin/env python3
"""The data bridge and the counter-trend watch must not drift apart between
the three files (v1.09: one schema for all three).
  NB_PW  (the counter-trend watch engine)  identical text in crypto, forex, metals
  NB_BR  (the bridge: JSON schema + file write)  identical text in crypto, forex, metals
Each file differs only through its adapter functions (NbBrLabel, NbBrSigKind,
NbBrSource, NbBrMarket, NbBrNy, NbBrNyKey, NbBrMarketState, NbBrRegime,
NbBrRegimeKey), which must all exist in every file."""
import re
import sys

FILES = {"crypto": "NRTR_BOSS_Crypto_NYTrap.mq5", "forex": "NRTR_BOSS_Forex_NYTrap.mq5", "metals": "NRTR_BOSS_LearningPanel.mq5"}
ADAPTERS = ["NbBrLabel", "NbBrSigKind", "NbBrSource", "NbBrMarket", "NbBrNy", "NbBrNyKey", "NbBrMarketState", "NbBrRegime", "NbBrRegimeKey"]


def block(text, name):
    b, e = f"//=== {name}_BEGIN ===", f"//=== {name}_END ==="
    if text.count(b) != 1 or text.count(e) != 1:
        return None
    return text[text.index(b):text.index(e) + len(e)]


def main() -> int:
    t = {k: open(v, encoding="ascii").read() for k, v in FILES.items()}
    bad = 0
    for name in ("NB_PW", "NB_BR"):
        blocks = {k: block(v, name) for k, v in t.items()}
        if None in blocks.values():
            print(f"  FAIL {name} missing in {[k for k, v in blocks.items() if v is None]}")
            bad += 1
        elif len(set(blocks.values())) != 1:
            print(f"  FAIL {name} differs between the files")
            bad += 1
    for k, v in t.items():
        for a in ADAPTERS:
            if not re.search(r"^string\s+" + a + r"\(", v, re.M):
                print(f"  FAIL {k}: adapter {a}() not defined")
                bad += 1
    if bad:
        print(f"BRIDGE BLOCK CHECK: FAIL ({bad})")
        return 1
    print(f"BRIDGE BLOCK CHECK: PASS - NB_PW and NB_BR identical in all 3 files; {len(ADAPTERS)} adapters defined in each")
    return 0


if __name__ == "__main__":
    sys.exit(main())
