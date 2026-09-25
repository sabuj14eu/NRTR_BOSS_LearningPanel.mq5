#!/usr/bin/env python3
"""The crypto and forex files are twins: identical text except the header
filename line, the #property description lines and the NB_MARKET define.
Anything else that differs is a bug (one twin was edited without the other)."""
import re
import sys

A = sys.argv[1] if len(sys.argv) > 1 else "NRTR_BOSS_Crypto_NYTrap.mq5"
B = sys.argv[2] if len(sys.argv) > 2 else "NRTR_BOSS_Forex_NYTrap.mq5"

ALLOWED = [
    re.compile(r"^//\|\s+NRTR_BOSS_\w+\.mq5 \|$"),
    re.compile(r"^#property description "),
    re.compile(r"^#define NB_MARKET NB_MKT_(CRYPTO|FOREX)$"),
]


def main() -> int:
    a = open(A, encoding="ascii").read().splitlines()
    b = open(B, encoding="ascii").read().splitlines()
    if len(a) != len(b):
        print(f"TWIN CHECK: FAIL - {A} has {len(a)} lines, {B} has {len(b)}")
        return 1
    diffs = 0
    bad = 0
    for i, (x, y) in enumerate(zip(a, b), 1):
        if x == y:
            continue
        diffs += 1
        if not (any(p.match(x) for p in ALLOWED) and any(p.match(y) for p in ALLOWED)):
            bad += 1
            print(f"  FAIL line {i} differs outside the allowed lines:\n    {x}\n    {y}")
    markets = [l for l in a if l.startswith("#define NB_MARKET ")], [l for l in b if l.startswith("#define NB_MARKET ")]
    if markets[0] != ["#define NB_MARKET NB_MKT_CRYPTO"] or markets[1] != ["#define NB_MARKET NB_MKT_FOREX"]:
        bad += 1
        print("  FAIL NB_MARKET define is not CRYPTO in the first file and FOREX in the second")
    if bad:
        print(f"TWIN CHECK: FAIL ({bad} problems)")
        return 1
    print(f"TWIN CHECK: PASS - {len(a)} lines, {diffs} differ, all of them header/description/NB_MARKET")
    return 0


if __name__ == "__main__":
    sys.exit(main())
