#!/usr/bin/env python3
"""The FOREX EA is its own file (its asset layer is written for forex), but its
ENGINE block must stay byte-identical to the metal EA's apart from the asset
detector, its defines and the one reason string that names the asset class.
This check proves it, so a change to the metal engine is a visible DRIFT here
and is ported by hand, never silently.

usage: check_forex_engine.py            exit 0 = identical
"""
import re
import sys

METAL = "NRTR_QML_MetalScalper.mq5"
FOREX = "NRTR_QML_ForexScalper.mq5"


def engine_core(text: str, which: str) -> str:
    a, b = text.index("//=== NB_ENGINE_BEGIN ==="), text.index("//=== NB_ENGINE_END ===")
    core = text[a:b]
    if which == "metal":
        core = re.sub(r"// supported metals\n(#define NQ_METAL_\w+\s+\d\n)+", "", core)
        i, j = core.index("//--- Gold / Silver only."), core.index("//--- text helpers")
    else:
        core = re.sub(r"// supported pair classes[^\n]*\n(#define NQ_PAIR_\w+\s+\d\n)+", "", core)
        i, j = core.index("//--- FOREX only:"), core.index("//--- text helpers")
    core = core[:i] + core[j:]
    return re.sub(r'case NQ_R_UNSUPPORTED:\s+return "[^"]*";', 'case NQ_R_UNSUPPORTED: return "<asset>";', core)


def main() -> int:
    metal = open(METAL, encoding="ascii").read()
    forex = open(FOREX, encoding="ascii").read()
    forex.encode("ascii")
    m, f = engine_core(metal, "metal"), engine_core(forex, "forex")
    if m != f:
        ml, fl = m.splitlines(), f.splitlines()
        for k, (x, y) in enumerate(zip(ml, fl)):
            if x != y:
                print(f"ENGINE DRIFT at engine line {k + 1}:\n  metal: {x[:100]}\n  forex: {y[:100]}")
                break
        else:
            print(f"ENGINE DRIFT: lengths differ ({len(ml)} vs {len(fl)} lines)")
        print("forex EA: DRIFT - port the metal engine change by hand and re-run")
        return 1
    for bad in ("NQ_METAL", "NqMetalOf", "GOLD / SILVER", "InpMacroSymbol", "g_macroDir", "InpMaxSpreadPoints"):
        if bad in forex:
            print(f"forex EA: leftover metal token {bad}")
            return 1
    print("forex EA: engine block identical to the metal EA apart from the asset detector")
    return 0


if __name__ == "__main__":
    sys.exit(main())
