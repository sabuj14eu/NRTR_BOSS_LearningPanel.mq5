#!/usr/bin/env python3
"""The five-question plan is ONE piece of code in three files. The engine
block (NB_FQ_BEGIN..NB_FQ_END) and the terminal block (NB_FQT_BEGIN..
NB_FQT_END) must be byte-identical in the gold/silver panel and both twins;
only the small adapters outside the blocks may differ per file. Anything
else means one copy was edited without the others."""
import sys

FILES = ["NRTR_BOSS_LearningPanel.mq5", "NRTR_BOSS_Crypto_NYTrap.mq5", "NRTR_BOSS_Forex_NYTrap.mq5"]
BLOCKS = [("//=== NB_FQ_BEGIN ===", "//=== NB_FQ_END ==="), ("//=== NB_FQT_BEGIN ===", "//=== NB_FQT_END ===")]


def main() -> int:
    bad = 0
    for b, e in BLOCKS:
        texts = []
        for f in FILES:
            t = open(f, encoding="ascii").read()
            if t.count(b) != 1 or t.count(e) != 1 or t.index(b) > t.index(e):
                print(f"  FAIL {f}: block {b} not found exactly once")
                bad += 1
                texts.append(None)
                continue
            texts.append(t[t.index(b):t.index(e) + len(e)])
        ref = texts[0]
        for f, x in zip(FILES[1:], texts[1:]):
            if ref is not None and x is not None and x != ref:
                la, lb = ref.splitlines(), x.splitlines()
                k = next((i for i, (p, q) in enumerate(zip(la, lb)) if p != q), min(len(la), len(lb)))
                print(f"  FAIL {b} differs in {f} at block line {k + 1}")
                bad += 1
        if ref is not None:
            print(f"  {b.strip('/= ').replace('_BEGIN', ''):>7}: {len(ref.splitlines())} lines")
    if bad:
        print(f"FQ BLOCK CHECK: FAIL ({bad} problems)")
        return 1
    print("FQ BLOCK CHECK: PASS - engine and terminal blocks identical in all three files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
