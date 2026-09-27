#!/usr/bin/env python3
"""The safety scan can fail: plant forbidden file / network / trade code
into COPIES of the crypto file and check that tests/check_safety.py
rejects every one. (The v1.07 bridge opened the door to file writes; this
proves the door only opens where it should.)"""
import os
import subprocess
import sys

SRC = "NRTR_BOSS_Crypto_NYTrap.mq5"
CASES = [
    ("write to a folder outside NRTR_BRIDGE",
     'string tmp = "NRTR_BRIDGE\\\\" + g_sym + ".tmp";', 'string tmp = "..\\\\" + g_sym + ".tmp";'),
    ("open a file for READING",
     "FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON)", "FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON)"),
    ("a file call outside the bridge block",
     "void NbPwRecompute()\n{", 'void NbX() { int h = FileOpen("x.txt", FILE_WRITE); }\nvoid NbPwRecompute()\n{'),
    ("delete a file inside the bridge block",
     "   FileClose(h);\n   if(w == 0)", '   FileClose(h);\n   FileDelete(fin);\n   if(w == 0)'),
    ("WebRequest inside the bridge block",
     "   FileClose(h);\n   if(w == 0)", '   FileClose(h);\n   char d[]; char r[]; string hd; WebRequest("POST", "https://x", "", 5, d, r, hd);\n   if(w == 0)'),
    ("an order inside the bridge block",
     "   FileClose(h);\n   if(w == 0)", '   FileClose(h);\n   MqlTradeRequest q;\n   if(w == 0)'),
    ("bridge markers removed",
     "//=== NB_BR_END ===", "//=== NB_BR_ENDS ==="),
]


def main() -> int:
    os.chdir(os.path.dirname(os.path.abspath(__file__)) + "/..")
    text = open(SRC, encoding="ascii").read()
    os.makedirs("build", exist_ok=True)
    bad = 0
    for name, old, new in CASES:
        if text.count(old) != 1:
            print(f"  NOT RUNNABLE - anchor not found exactly once: {name}")
            bad += 1
            continue
        path = os.path.join("build", "safety_neg.mq5")
        open(path, "w", encoding="ascii").write(text.replace(old, new))
        r = subprocess.run([sys.executable, "tests/check_safety.py", path], stdout=subprocess.PIPE, text=True)
        ok = r.returncode != 0
        print(f"  {'REJECTED' if ok else 'ACCEPTED (BAD)'}: {name}")
        if not ok:
            bad += 1
    print(f"SAFETY SCAN NEGATIVE CHECKS: {len(CASES) - bad} of {len(CASES)} planted violations rejected")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
