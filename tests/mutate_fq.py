#!/usr/bin/env python3
"""The tests can fail: plant one realistic bug at a time into a COPY of a
source file and check that the five-question suites catch it.

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

BASELINE = "3f046ef"
FLAGS = ["-std=c++17", "-O1", "-Wall", "-Wextra", "-Wno-unused-parameter", "-Werror"]
TARGETS = {   # tag: (source file, NB_TEST_MARKET, engine inc name, full inc name)
    "crypto": ("NRTR_BOSS_Crypto_NYTrap.mq5", "1", "engine_crypto.inc", "full_crypto.inc"),
    "gold": ("NRTR_BOSS_LearningPanel.mq5", "0", "engine.inc", "full.inc"),
}

MUTATIONS = [
    ("crypto", "sweep confirmation skipped (READY without the close beyond the sweep candle)",
     "         if(conf < 0)\n         {\n            fq[i].status = NB_FQ_SETUP;",
     "         if(false)\n         {\n            fq[i].status = NB_FQ_SETUP;"),
    ("crypto", "reward gate removed (any R is READY)",
     "      if(fq[i].rr1 < C.minRR)", "      if(fq[i].rr1 < 0.0)"),
    ("crypto", "trend gate removed (plans without a 15M structure)",
     "      if(tr == 0)\n      {\n         fq[i].why = (s15.st[k15] == NB_ST_MIXED)",
     "      if(false)\n      {\n         fq[i].why = (s15.st[k15] == NB_ST_MIXED)"),
    ("crypto", "Asia / London range published one hour before the window ends",
     "   if(!pub && (long)t + sec >= (long)wEnd)", "   if(!pub && (long)t + sec >= (long)wEnd - 3600)"),
    ("crypto", "SL on the fill candle ignored",
     "         g.fillIdx = k;\n         bool stop = (g.dir > 0) ? (lo <= g.sl) : (hi >= g.sl);",
     "         g.fillIdx = k;\n         bool stop = false;"),
    ("crypto", "forming 5M candle evaluated",
     "   int nEvalFq = lastClosed ? n : n - 1;", "   int nEvalFq = n;"),
    ("crypto", "15M swings used 3 bars before they are confirmed (look-ahead)",
     "      while(k15 >= 0 && pc < np15 && piv15[pc].confirmIdx <= k15)",
     "      while(k15 >= 0 && pc < np15 && piv15[pc].confirmIdx <= k15 + 3)"),
    ("crypto", "stale-data gate removed from the table",
     "   bool gate = ok && g_fresh;", "   bool gate = ok;"),
    ("crypto", "sweep anchored at the LATEST pierce (the stop moves up on a re-dip)",
     "         for(int j = j0; j <= i; j++)", "         for(int j = i; j >= j0; j--)"),
    ("crypto", "pending plan not cancelled when the 15M structure turns",
     "      if(cur >= 0 && pl[cur].status == NB_PO_PENDING && tr != pl[cur].dir)",
     "      if(cur >= 0 && pl[cur].status == NB_PO_PENDING && tr != pl[cur].dir && false)"),
    ("crypto", "table no longer steps aside for the main panel",
     "      if(ox < InpPanelX + pw + 8)\n         ox = InpPanelX + pw + 8;",
     "      if(false)\n         ox = InpPanelX + pw + 8;"),
    ("crypto", "live plan lines left on the chart when the data goes stale",
     "      if(!gate && drawn)", "      if(false && drawn)"),
    ("crypto", "counter-trend: breakdowns allowed as SELL plans in a bullish 15M",
     "         if((tr > 0 && !(L < cl)) || (tr < 0 && !(L > cl)))\n            continue;",
     "         if(false)\n            continue;"),
    ("crypto", "EXISTING main panel touched (one extra space in its REASON row)",
     'NbLabel("r1", ox + kx, y, "REASON: " + r1', 'NbLabel("r1", ox + kx, y, "REASON:  " + r1'),
    ("crypto", "v1.06: a table row longer than MT5's 63-character label limit",
     'NbQLabel("mapL", ox + pad, y, mapL,', 'NbQLabel("mapL", ox + pad, y, mapL + "   |   " + mapR,'),
    ("crypto", "v1.06: chart markers drawn in the foreground again (they cover the panels)",
     "   NbText(name, t, price, txt, clr, size, anchor, tip);\n   ObjectSetInteger(0, name, OBJPROP_BACK, true);",
     "   NbText(name, t, price, txt, clr, size, anchor, tip);"),
    ("crypto", "v1.06: table not recreated after the chart markers (markers on top of it)",
     "   ObjectsDeleteAll(0, NB_PFX_Q);\n   if(!InpFqDraw", "   if(!InpFqDraw"),
    ("gold", "metals: silver wider stop ignored",
     "      slMult = InpFqSilverSlMult;", "      slMult = 1.0;"),
    ("gold", "metals: silver stronger confirmation ignored",
     "      confirmAtr = InpFqSilverConfirmAtr;", "      confirmAtr = 0.0;"),
    ("gold", "metals: broker clock assumed (UTC offset 0) instead of two witnesses",
     "   ok = NbFqWitnessClock(TimeTradeServer(), TimeGMT(), offset);", "   ok = true;\n   offset = 0;"),
    ("gold", "metals: EXISTING gold panel touched (one extra space in its REASON row)",
     'NbLabel("r1", ox + kx, y, "REASON: " + r1', 'NbLabel("r1", ox + kx, y, "REASON:  " + r1'),
    ("gold", "metals: stale-data gate removed from the table",
     "   bool gate = ok && g_fresh;", "   bool gate = ok;"),
]


def run(cmd, **kw):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, **kw)


def build_and_test(target, src_text, tag):
    src, mk, eng, full = TARGETS[target]
    d = os.path.join("build", "mut", tag)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, src)
    with open(path, "w", encoding="ascii") as f:
        f.write(src_text)
    for mode, name in (("engine", eng), ("full", full)):
        r = run([sys.executable, "tests/mql2cpp.py", path, os.path.join(d, name), mode])
        if r.returncode != 0:
            return {"translate": False}
    res = {}
    for test in ("test_fq_engine", "test_fq_indicator"):
        exe = os.path.join(d, test)
        r = run(["g++"] + FLAGS + ["-I" + d, "-DNB_TEST_MARKET=" + mk, "tests/%s.cpp" % test, "-o", exe])
        res[test] = (r.returncode == 0) and run([exe]).returncode == 0
    exe = os.path.join(d, "dump_new")
    r = run(["g++"] + FLAGS + ["-I" + d, "-DNB_TEST_MARKET=" + mk, '-DDUMP_INC="%s"' % full, "tests/dump_objects.cpp", "-o", exe])
    same = False
    if r.returncode == 0:
        out = run([exe]).stdout
        same = out == open(os.path.join("build", "mut", "dump_base_%s.txt" % target)).read()
    res["unchanged_dump"] = same
    return res


def baseline(target):
    src, mk, eng, full = TARGETS[target]
    base = run(["git", "show", "%s:%s" % (BASELINE, src)])
    if base.returncode != 0:
        return "baseline commit %s not available (%s)" % (BASELINE, base.stdout.strip())
    bd = os.path.join("build", "mut", "base_" + target)
    os.makedirs(bd, exist_ok=True)
    open(os.path.join(bd, src), "w").write(base.stdout)
    run([sys.executable, "tests/mql2cpp.py", os.path.join(bd, src), os.path.join(bd, full), "full"])
    r = run(["g++"] + FLAGS + ["-I" + bd, "-DNB_TEST_MARKET=" + mk, '-DDUMP_INC="%s"' % full, "tests/dump_objects.cpp",
             "-o", os.path.join(bd, "dump")])
    if r.returncode != 0:
        return "baseline dump does not build\n" + r.stdout
    open(os.path.join("build", "mut", "dump_base_%s.txt" % target), "w").write(run([os.path.join(bd, "dump")]).stdout)
    return ""


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)) + "/..")
    os.makedirs(os.path.join("build", "mut"), exist_ok=True)
    texts = {}
    for t in TARGETS:
        err = baseline(t)
        if err:
            print("NOT RUNNABLE (%s): %s" % (t, err))
            return 2
        texts[t] = open(TARGETS[t][0], encoding="ascii").read()
        clean = build_and_test(t, texts[t], "clean_" + t)
        if not all(clean.values()):
            print("NOT RUNNABLE: the UNMUTATED %s file does not pass (%s)" % (t, clean))
            return 2
        print("unmutated %-6s: engine PASS, indicator PASS, existing panel unchanged PASS" % t)
    escaped = 0
    for k, (t, name, old, new) in enumerate(MUTATIONS, 1):
        text = texts[t]
        if text.count(old) != 1:
            print("M%02d NOT RUNNABLE - anchor not found exactly once in %s: %s" % (k, t, name))
            escaped += 1
            continue
        res = build_and_test(t, text.replace(old, new), "m%02d" % k)
        failed = [x for x, ok in res.items() if not ok]
        verdict = "CAUGHT by " + ", ".join(failed) if failed else "ESCAPED"
        if not failed:
            escaped += 1
        print("M%02d [%-6s] %-72s %s" % (k, t, name, verdict))
    print("MUTATION TESTS: %d planted, %d caught, %d escaped / not runnable" % (len(MUTATIONS), len(MUTATIONS) - escaped, escaped))
    return 0 if escaped == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
