#!/usr/bin/env python3
"""Mechanically translate NRTR_BOSS_LearningPanel.mq5 into C++ so the test
suite compiles and runs the REAL source text, not a hand-written port.

Only syntax is rewritten, never logic:
  #property lines / `input group` lines  -> removed
  input / sinput                         -> const   (inputs are read-only)
  T &name[]   (array parameter)          -> std::vector<T> &name
  T name[];   (dynamic array)            -> std::vector<T> name;

usage: mql2cpp.py <src.mq5> <out.cpp> engine|full
"""
import re
import sys

BEGIN = "//=== NB_ENGINE_BEGIN ==="
END = "//=== NB_ENGINE_END ==="


def translate(text: str) -> str:
    out = []
    for line in text.splitlines():
        if re.match(r"^\s*#property\b", line) or re.match(r"^\s*input\s+group\b", line):
            out.append("// " + line)
            continue
        line = re.sub(r"^(\s*)(?:input|sinput)\s+", r"\1const ", line)
        line = re.sub(r"(const\s+)?\b(\w+)\s*&\s*(\w+)\s*\[\s*\]", r"\1std::vector<\2> &\3", line)
        line = re.sub(r"^(\s*)(static\s+)?(\w+)\s+(\w+)\s*\[\s*\]\s*;", r"\1\2std::vector<\3> \4;", line)
        out.append(line)
    return "\n".join(out) + "\n"


def main() -> int:
    src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
    raw = open(src, "rb").read()
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as e:
        print(f"FAIL: {src} is not pure ASCII ({e})")
        return 1
    if mode == "engine":
        a, b = text.find(BEGIN), text.find(END)
        if a < 0 or b < a:
            print("FAIL: engine markers not found")
            return 1
        text = text[a:b]
    with open(dst, "w") as f:
        f.write(f"// GENERATED from {src} by mql2cpp.py ({mode}) - do not edit\n")
        f.write(translate(text))
    return 0


if __name__ == "__main__":
    sys.exit(main())
