#!/usr/bin/env python3
"""v1.07: the data bridge and the counter-trend watch must not drift apart
between the files that carry them.
  NB_PW  (the watch engine)  identical text in crypto, forex and metals
  NB_BR  (the bridge)        crypto == forex; metals == crypto after exactly
                             the three adapter substitutions listed below
The crypto / forex files were kept as they are (user decision); the metals
file adapts through named functions instead of editing the shared text."""
import sys

FILES = {"crypto": "NRTR_BOSS_Crypto_NYTrap.mq5", "forex": "NRTR_BOSS_Forex_NYTrap.mq5", "metals": "NRTR_BOSS_LearningPanel.mq5"}
METALS_SUBS = [
    ("g_label", "NbBrLabel()"),
    ('NbJk("kind") + ((g_sigs[cur].kind == NB_K_TRAP) ? "\\"NY TRAP\\"" : "\\"FLOW\\"")', 'NbJk("kind") + NbBrSigKind(cur)'),
    ('NbJk("ny") + NbBrNy() + ",', 'NbJk("ny") + NbBrNy() + "," + NbJk("market_state") + NbBrMarketState() + ",'),
]


def block(text, name):
    b, e = f"//=== {name}_BEGIN ===", f"//=== {name}_END ==="
    if text.count(b) != 1 or text.count(e) != 1:
        return None
    return text[text.index(b):text.index(e) + len(e)]


def main() -> int:
    t = {k: open(v, encoding="ascii").read() for k, v in FILES.items()}
    bad = 0
    pw = {k: block(v, "NB_PW") for k, v in t.items()}
    if None in pw.values() or len(set(pw.values())) != 1:
        print("  FAIL NB_PW differs (or is missing) between the files")
        bad += 1
    br = {k: block(v, "NB_BR") for k, v in t.items()}
    if None in br.values():
        print("  FAIL NB_BR missing in a file")
        return 1
    if br["crypto"] != br["forex"]:
        print("  FAIL NB_BR crypto != forex")
        bad += 1
    want = br["crypto"]
    for a, b in METALS_SUBS:
        if want.count(a) < 1:
            print(f"  FAIL substitution anchor not in the crypto block: {a[:50]}")
            bad += 1
        want = want.replace(a, b)
    if want != br["metals"]:
        print("  FAIL metals NB_BR is not the crypto block + the three listed adapter substitutions")
        bad += 1
    if bad:
        print(f"BRIDGE BLOCK CHECK: FAIL ({bad})")
        return 1
    print(f"BRIDGE BLOCK CHECK: PASS - NB_PW identical in 3 files; NB_BR crypto == forex, metals = crypto + {len(METALS_SUBS)} named adapters")
    return 0


if __name__ == "__main__":
    sys.exit(main())
