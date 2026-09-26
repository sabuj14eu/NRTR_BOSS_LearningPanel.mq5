#!/usr/bin/env python3
"""The tests can fail: plant one realistic bug at a time into a COPY of the
crypto file and check that the v1.05 suites catch it.

For every mutation the copy is translated, the five-question engine tests,
the five-question indicator tests and the "existing panel unchanged" dump
are built against it and run. A mutation counts as CAUGHT when at least one
of them fails. Anything not caught is printed as ESCAPED and the script
exits non-zero.

usage: python3 tests/mutate_fq.py        (from the repository root; needs git + g++)
"""
import os
import subprocess
import sys

SRC = "NRTR_BOSS_Crypto_NYTrap.mq5"
BASELINE = "3f046ef"
FLAGS = ["-std=c++17", "-O1", "-Wall", "-Wextra", "-Wno-unused-parameter", "-Werror"]

MUTATIONS = [
    ("sweep confirmation skipped (READY without the close beyond the sweep candle)",
     "         if(conf < 0)\n         {\n            fq[i].status = NB_FQ_SETUP;",
     "         if(false)\n         {\n            fq[i].status = NB_FQ_SETUP;"),
    ("reward gate removed (any R is READY)",
     "      if(fq[i].rr1 < C.minRR)", "      if(fq[i].rr1 < 0.0)"),
    ("trend gate removed (plans without a 15M structure)",
     "      if(tr == 0)\n      {\n         fq[i].why = (s15.st[k15] == NB_ST_MIXED)",
     "      if(false)\n      {\n         fq[i].why = (s15.st[k15] == NB_ST_MIXED)"),
    ("Asia / London range published one hour before the window ends",
     "   if(!pub && (long)t + sec >= (long)wEnd)", "   if(!pub && (long)t + sec >= (long)wEnd - 3600)"),
    ("SL on the fill candle ignored",
     "         g.fillIdx = k;\n         bool stop = (g.dir > 0) ? (lo <= g.sl) : (hi >= g.sl);",
     "         g.fillIdx = k;\n         bool stop = false;"),
    ("forming 5M candle evaluated",
     "   int nEvalFq = lastClosed ? n : n - 1;", "   int nEvalFq = n;"),
    ("15M swings used 3 bars before they are confirmed (look-ahead)",
     "      while(k15 >= 0 && pc < np15 && piv15[pc].confirmIdx <= k15)",
     "      while(k15 >= 0 && pc < np15 && piv15[pc].confirmIdx <= k15 + 3)"),
    ("stale-data gate removed from the table",
     "   bool gate = ok && g_fresh;", "   bool gate = ok;"),
    ("sweep anchored at the LATEST pierce (the stop moves up on a re-dip)",
     "         for(int j = j0; j <= i; j++)", "         for(int j = i; j >= j0; j--)"),
    ("pending plan not cancelled when the 15M structure turns",
     "      if(cur >= 0 && pl[cur].status == NB_PO_PENDING && tr != pl[cur].dir)",
     "      if(cur >= 0 && pl[cur].status == NB_PO_PENDING && tr != pl[cur].dir && false)"),
    ("table no longer steps aside for the main panel",
     "      if(ox < InpPanelX + pw + 8)\n         ox = InpPanelX + pw + 8;",
     "      if(false)\n         ox = InpPanelX + pw + 8;"),
    ("live plan lines left on the chart when the data goes stale",
     "      if(!gate && drawn)", "      if(false && drawn)"),
    ("counter-trend: breakdowns allowed as SELL plans in a bullish 15M",
     "         if((tr > 0 && !(L < cl)) || (tr < 0 && !(L > cl)))\n            continue;",
     "         if(false)\n            continue;"),
    ("EXISTING main panel touched (one extra space in its REASON row)",
     'NbLabel("r1", ox + kx, y, "REASON: " + r1', 'NbLabel("r1", ox + kx, y, "REASON:  " + r1'),
]


def run(cmd, **kw):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, **kw)


def build_and_test(src_text, tag):
    d = os.path.join("build", "mut", tag)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, SRC)
    with open(path, "w", encoding="ascii") as f:
        f.write(src_text)
    for mode, name in (("engine", "engine_crypto.inc"), ("full", "full_crypto.inc")):
        r = run([sys.executable, "tests/mql2cpp.py", path, os.path.join(d, name), mode])
        if r.returncode != 0:
            return {"translate": False}
    res = {}
    for test in ("test_fq_engine", "test_fq_indicator"):
        exe = os.path.join(d, test)
        r = run(["g++"] + FLAGS + ["-I" + d, "-DNB_TEST_MARKET=1", "tests/%s.cpp" % test, "-o", exe])
        res[test] = (r.returncode == 0) and run([exe]).returncode == 0
    exe = os.path.join(d, "dump_new")
    r = run(["g++"] + FLAGS + ["-I" + d, "-DNB_TEST_MARKET=1", '-DDUMP_INC="full_crypto.inc"', "tests/dump_objects.cpp", "-o", exe])
    same = False
    if r.returncode == 0:
        out = run([exe]).stdout
        same = out == open(os.path.join("build", "mut", "dump_base.txt")).read()
    res["unchanged_dump"] = same
    return res


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)) + "/..")
    os.makedirs(os.path.join("build", "mut"), exist_ok=True)
    base = run(["git", "show", "%s:%s" % (BASELINE, SRC)])
    if base.returncode != 0:
        print("NOT RUNNABLE: baseline commit %s not available (%s)" % (BASELINE, base.stdout.strip()))
        return 2
    bd = os.path.join("build", "mut", "base")
    os.makedirs(bd, exist_ok=True)
    open(os.path.join(bd, SRC), "w").write(base.stdout)
    run([sys.executable, "tests/mql2cpp.py", os.path.join(bd, SRC), os.path.join(bd, "full_crypto.inc"), "full"])
    r = run(["g++"] + FLAGS + ["-I" + bd, "-DNB_TEST_MARKET=1", '-DDUMP_INC="full_crypto.inc"', "tests/dump_objects.cpp",
             "-o", os.path.join(bd, "dump")])
    if r.returncode != 0:
        print("NOT RUNNABLE: baseline dump does not build\n" + r.stdout)
        return 2
    open(os.path.join("build", "mut", "dump_base.txt"), "w").write(run([os.path.join(bd, "dump")]).stdout)

    text = open(SRC, encoding="ascii").read()
    clean = build_and_test(text, "clean")
    if not all(clean.values()):
        print("NOT RUNNABLE: the UNMUTATED file does not pass (%s)" % clean)
        return 2
    print("unmutated file: engine PASS, indicator PASS, existing panel unchanged PASS")
    escaped = 0
    for k, (name, old, new) in enumerate(MUTATIONS, 1):
        if text.count(old) != 1:
            print("M%02d NOT RUNNABLE - anchor not found exactly once: %s" % (k, name))
            escaped += 1
            continue
        res = build_and_test(text.replace(old, new), "m%02d" % k)
        failed = [t for t, ok in res.items() if not ok]
        verdict = "CAUGHT by " + ", ".join(failed) if failed else "ESCAPED"
        if not failed:
            escaped += 1
        print("M%02d %-78s %s" % (k, name, verdict))
    print("MUTATION TESTS: %d planted, %d caught, %d escaped / not runnable" % (len(MUTATIONS), len(MUTATIONS) - escaped, escaped))
    return 0 if escaped == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
