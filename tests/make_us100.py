#!/usr/bin/env python3
"""Generate NRTR_BOSS_US100.mq5 from the crypto file plus a DECLARED list of
US changes, so every difference from the proven file is reviewable here and
the shared engine / bridge / terminal text stays byte-identical.

Each patch anchor must match EXACTLY ONCE, or nothing is written (an
ambiguous anchor aborts - never a guess). The US-only code lives in us100/.

usage: python3 tests/make_us100.py           regenerate the file
       python3 tests/make_us100.py --check   exit 1 if the committed file differs (drift)
"""
import sys

SRC, DST = "NRTR_BOSS_Crypto_NYTrap.mq5", "NRTR_BOSS_US100.mq5"


def frag(name):
    return open("us100/" + name, encoding="ascii").read()


HEADER = """//+------------------------------------------------------------------+
//|                                               NRTR_BOSS_US100.mq5 |
//|      US INDEX learning panel (US100 / USTEC) - v1.11              |
//|                                                                  |
//|  MARKET DATA -> DIRECTION -> LEVELS -> REACTION -> CONFIRMATION  |
//|  -> RISK / R:R -> WAIT or SETUP                                  |
//|  15M = BOSS / DIRECTION   (NRTR + EMA200 + confirmed structure)  |
//|   5M = TIMING             (CLOSED candles only; forming = never) |
//|  US SESSION MAP = reference levels in NEW YORK time: previous    |
//|  regular session H/L/close, overnight and PRE-MARKET H/L (kept   |
//|  apart from the regular session), the 09:30 open, opening range  |
//|  5/15/30, regular session so far, the GAP (filled / open).       |
//|  Sessions (open, first 5/15/30 min, lunch, final hour, close)    |
//|  are CONTEXT LABELS: they change no rule. A level is never a     |
//|  BUY or SELL by itself. News (MT5 calendar) is a label whose     |
//|  direction is always UNKNOWN; an empty calendar is UNKNOWN.      |
//|                                                                  |
//|  Built from NRTR_BOSS_Crypto_NYTrap.mq5 by tests/make_us100.py:  |
//|  the engine, the bridge and the shared blocks are the same text; |
//|  the differences are declared there. The NY TRAP module is OFF   |
//|  here (the US levels replace it). The 5-question plan uses PDH / |
//|  PDL = previous regular session, PRE-MARKET H/L and the opening  |
//|  range, and a level the price GAPPED over is never a sweep or a  |
//|  breakout. Starting values = the crypto file's, NOT validated    |
//|  for US100: READ-ONLY -> RECORD -> SHADOW -> TEST -> VALIDATE.   |
//|                                                                  |
//|  VISUAL ONLY. This indicator never sends, modifies or closes an  |
//|  order or position (MT5 also blocks trade functions inside       |
//|  indicators). It writes a data file a separate script may post   |
//|  to Telegram; MT5 itself uses no network. No self-modification.  |
//|  "READY - CLICK" means the defined conditions are aligned for    |
//|  the educational setup. It is NOT a profit guarantee.            |
//+------------------------------------------------------------------+
"""

PATCHES = [
    # ---- identity ----
    ('#property version     "1.10"', '#property version     "1.11"'),
    ('#property description "Crypto NRTR BOSS learning panel: 15M direction, 5M timing, NY-open trap. CUSTOM ATR-NRTR."',
     '#property description "US100 / USTEC NRTR BOSS learning panel: 15M direction, 5M timing, US session map. CUSTOM ATR-NRTR."'),
    ('#property description "BTC ETH SOL LTC XRP BNB ADA DOGE AVAX DOT LINK BCH vs USD/USDT/USDC."',
     '#property description "USTEC US100 NAS100 NDX (individual stocks: phase 2, after US100 is validated)."'),
    ('#define NB_MKT_FOREX  2\n', '#define NB_MKT_FOREX  2\n#define NB_MKT_US     3   // v1.11: the US index file (NRTR_BOSS_US100.mq5)\n'),
    ('#define NB_MARKET NB_MKT_CRYPTO', '#define NB_MARKET NB_MKT_US'),
    ('#define NB_BR_VERSION "1.10"', '#define NB_BR_VERSION "1.11"'),
    # ---- engine: the US map + the five-question plan on US levels ----
    ('//=== NB_FQ_BEGIN ===', frag("nb_us_engine.mqh") + "\n//=== NB_FQ_BEGIN ==="),
    ('   double   confirmAtr;    // v1.06: the confirmation close must pass by this x 5M ATR (0; silver: stronger)\n',
     '   double   confirmAtr;    // v1.06: the confirmation close must pass by this x 5M ATR (0; silver: stronger)\n'
     '   int      usMode;        // US100: NB_CLK_AUTO / NB_CLK_MANUAL (the NY clock)\n'
     '   int      usOpenSec;     // US100 MANUAL: 09:30 NY as seconds of the server day\n'
     '   double   usGapAtr;      // US100: |open - previous close| below this x 15M ATR = NO GAP\n'
     '   int      usOrMin;       // US100: the opening range the map uses (5 / 15 / 30)\n'
     '   long     usOffBase;     // US100: the server\'s WINTER offset (witnesses now, less its DST hour)\n'
     '   int      usSrvDst;      // US100: the server clock\'s DST rule (NB_SRVDST_*)\n'),
    ('   NbFqSessions(s5.t, s5.h, s5.l, n, s5.sec, C, fq);\n   int nEvalFq',
     '   // US100 (v1.11): the map runs on US levels - PDH / PDL = the previous\n'
     '   // regular session, the Asia slot = PRE-MARKET H/L, the London slot =\n'
     '   // the chosen opening range. Same causality as the session levels.\n'
     '   NbUsBar usm[];\n'
     '   NbRunUs(s5, s15, lastClosed, C.clockOk, C.usMode, C.usOffBase, C.usSrvDst, C.usOpenSec, C.usGapAtr, usm);\n'
     '   for(int u = 0; u < n; u++)\n'
     '   {\n'
     '      fq[u].pdh = usm[u].pdh;\n'
     '      fq[u].pdl = usm[u].pdl;\n'
     '      fq[u].ash = usm[u].pmh;\n'
     '      fq[u].asl = usm[u].pml;\n'
     '      fq[u].loh = (C.usOrMin == 5) ? usm[u].or5h : ((C.usOrMin == 30) ? usm[u].or30h : usm[u].or15h);\n'
     '      fq[u].lol = (C.usOrMin == 5) ? usm[u].or5l : ((C.usOrMin == 30) ? usm[u].or30l : usm[u].or15l);\n'
     '   }\n'
     '   int nEvalFq'),
    ('            bool pierce = (tr > 0) ? (s5.l[j] < L && s5.c[j - 1] > L) : (s5.h[j] > L && s5.c[j - 1] < L);\n',
     '            bool pierce = (tr > 0) ? (s5.l[j] < L && s5.c[j - 1] > L) : (s5.h[j] > L && s5.c[j - 1] < L);\n'
     '            if(pierce && NbUsGapped(s5.c[j - 1], s5.o[j], L))\n'
     '               pierce = false;   // US100: the price GAPPED over the level - nothing traded there, not a sweep\n'),
    ('               bool cross = (tr > 0) ? (s5.c[j] > L && s5.c[j - 1] <= L) : (s5.c[j] < L && s5.c[j - 1] >= L);\n'
     '               if(!cross)\n                  continue;\n',
     '               bool cross = (tr > 0) ? (s5.c[j] > L && s5.c[j - 1] <= L) : (s5.c[j] < L && s5.c[j - 1] >= L);\n'
     '               if(!cross)\n                  continue;\n'
     '               if(NbUsGapped(s5.c[j - 1], s5.o[j], L))\n'
     '                  continue;   // US100: a gap over the level is not a breakout close\n'),
    # level names (the slots keep their engine role; the words are US)
    ('" + ") + "LONDON HIGH";', '" + ") + "OPENING RANGE HIGH";'),
    ('" + ") + "LONDON LOW";', '" + ") + "OPENING RANGE LOW";'),
    ('" + ") + "ASIA HIGH";', '" + ") + "PRE-MARKET HIGH";'),
    ('" + ") + "ASIA LOW";', '" + ") + "PRE-MARKET LOW";'),
    ('"+") + "LDN H";', '"+") + "ORH";'),
    ('"+") + "LDN L";', '"+") + "ORL";'),
    ('"+") + "ASIA H";', '"+") + "PMH";'),
    ('"+") + "ASIA L";', '"+") + "PML";'),
    # ---- symbol filter ----
    ('//--- Accepted symbol -> short label ("BTC", "EURUSD"); "" = rejected.',
     '//--- US100: the broker names of the Nasdaq-100 CFD. US500 / US30 / stocks\n'
     '//    are rejected (stocks: phase 2, own parameters and earnings rules).\n'
     'string NbUsLabel(string u)\n'
     '{\n'
     '   if(StringFind(u, "USTEC") == 0 || StringFind(u, "US100") == 0 || StringFind(u, "NAS100") == 0 ||\n'
     '      StringFind(u, "NASDAQ") == 0 || StringFind(u, "NDX") == 0 || StringFind(u, "NQ100") == 0 ||\n'
     '      StringFind(u, "USTECH") == 0)\n'
     '      return "US100";\n'
     '   return "";\n'
     '}\n\n'
     '//--- Accepted symbol -> short label ("BTC", "EURUSD"); "" = rejected.'),
    ('   StringToUpper(q);\n   if(NB_MARKET == NB_MKT_CRYPTO)\n',
     '   StringToUpper(q);\n   if(NB_MARKET == NB_MKT_US)\n      return NbUsLabel(u);\n   if(NB_MARKET == NB_MKT_CRYPTO)\n'),
    ('string NbMarketOnlyText()\n{\n',
     'string NbMarketOnlyText()\n{\n   if(NB_MARKET == NB_MKT_US)\n      return "US100 ONLY (USTEC US100 NAS100)";\n'),
    # ---- inputs ----
    ('input group "NY session - the wildlife"',
     'enum ENUM_NB_US_SRVDST\n{\n   NB_US_SRVDST_US = 0,   // US DST (server = NY close, UTC+2 / +3)\n'
     '   NB_US_SRVDST_EU = 1,   // EU DST (last Sunday of March / October)\n'
     '   NB_US_SRVDST_NONE = 2  // never (fixed server offset)\n};\n\n'
     'input group "US SESSION CLOCK (NY time, converted per bar)"'),
    ('input int            InpNyOpenHour      = 16;          // MANUAL only: NY open hour (broker server time)',
     'input int            InpNyOpenHour      = 16;          // MANUAL only: 09:30 NY in broker server time (hour)'),
    ('input int            InpPreNyRangeHours = 4;', 'const int            InpPreNyRangeHours = 4;  // (US100: the NY trap is OFF)'),
    ('input int            InpNyWindowMinutes = 90;', 'const int            InpNyWindowMinutes = 90;'),
    ('input int            InpMinRangeBars    = 12;', 'const int            InpMinRangeBars    = 12;'),
    ('input bool           InpNyPauseFlow     = true;', 'const bool           InpNyPauseFlow     = false;'),
    ('input bool           InpNyAlert         = true;        // MT5 pop-up + sound at the NY open (local only)\n',
     'input bool           InpNyAlert         = true;        // MT5 pop-up + sound at the 09:30 NY open (local only)\n'
     'input ENUM_NB_US_SRVDST InpUsServerDst  = NB_US_SRVDST_US; // Broker server clock changes with (MT5 NY-close brokers: US)\n'
     'input int            InpUsOrMinutes     = 15;          // Opening range the 5-question map uses (5 / 15 / 30 min)\n'
     'input double         InpUsGapAtr        = 0.3;         // Open vs previous close below this x 15M ATR = NO GAP\n'
     'input bool           InpUsNews          = true;        // Read MT5 economic calendar (USD high impact) - a label, never a direction\n'
     'input int            InpUsNewsMinutes   = 30;          // News window: minutes before / after the event\n'),
    ('input int            InpFqAsiaStartUtc  = 0; ', 'const int            InpFqAsiaStartUtc  = 0; '),
    ('input int            InpFqAsiaEndUtc    = 7; ', 'const int            InpFqAsiaEndUtc    = 7; '),
    ('input int            InpFqLondonStartUtc = 7;', 'const int            InpFqLondonStartUtc = 7;'),
    ('input int            InpFqLondonEndUtc  = 12;', 'const int            InpFqLondonEndUtc  = 12;'),
    ('InpFqLondonStartUtc >= InpFqLondonEndUtc || InpFqLondonEndUtc > 24 || InpFqBottomY < 0)',
     'InpFqLondonStartUtc >= InpFqLondonEndUtc || InpFqLondonEndUtc > 24 || InpFqBottomY < 0 ||\n'
     '      (InpUsOrMinutes != 5 && InpUsOrMinutes != 15 && InpUsOrMinutes != 30) || InpUsGapAtr < 0.0 || InpUsGapAtr > 5.0 ||\n'
     '      InpUsNewsMinutes < 5 || InpUsNewsMinutes > 240)'),
    # ---- state ----
    ('NbSessCfg g_S;\n', 'NbSessCfg g_S;\nNbSessCfg g_Seng;       // US100: the engine\'s copy with the NY trap OFF\nNbUsBar   g_us[];       // US100: the US map, one per closed 5M bar\n' + frag("nb_us_state.mqh")),
    ('string NbClockText();\n', 'string NbClockText();\n// US100 prototypes (defined with the bridge adapters)\nstring NbUsClockText();\nstring NbUsNowText();\nvoid   NbUsNewsRead(datetime now);\nstring NbUsHL(double h, double l);\nstring NbUsGapText(const NbUsBar &b);\n'),
    ('   NbRun5(g_s5, g_piv5, g_s15, true, g_P, g_S, g_sigs, g_nSig);\n',
     '   g_Seng = g_S;              // US100: the NY-trap module is OFF (the US map replaces it)\n'
     '   g_Seng.clockOk = false;\n'
     '   NbRun5(g_s5, g_piv5, g_s15, true, g_P, g_Seng, g_sigs, g_nSig);\n'),
    ('   NbFqRecompute();\n   NbFqDrawChart();\n',
     '   NbFqRecompute();\n'
     '   NbRunUs(g_s5, g_s15, true, g_C.clockOk, g_C.usMode, g_C.usOffBase, g_C.usSrvDst, g_C.usOpenSec, g_C.usGapAtr, g_us);\n'
     '   NbFqDrawChart();\n'),
    ('      ArrayResize(g_rp, 0);\n      ArrayResize(g_rpRec, 0);\n      g_nRp = 0;\n      g_rpInv = 0;\n      return;\n',
     '      ArrayResize(g_rp, 0);\n      ArrayResize(g_rpRec, 0);\n      g_nRp = 0;\n      g_rpInv = 0;\n      ArrayResize(g_us, 0);\n      return;\n'),
    ('   g_nyAlertDay = -1;\n',
     '   g_nyAlertDay = -1;\n   g_usNewsAt = 0;          // US100: read the calendar afresh after a restart\n'
     '   g_usNewsState = NB_NEWS_UNKNOWN;\n   g_usNewsTxt = "UNKNOWN - CALENDAR NOT READ YET";\n   ArrayResize(g_us, 0);\n'),
    # ---- the NY-open pop-up says what this file does at the open ----
    ('   string msg = "NRTR BOSS " + g_sym + ": NEW YORK OPEN (" + TimeToString(open, TIME_MINUTES) + " broker time). Next " +\n'
     '                IntegerToString(g_S.winMin) + " min: structure flow paused, watching the pre-NY range for a sweep. You decide.";',
     '   string msg = "NRTR BOSS " + g_sym + ": US REGULAR SESSION OPEN 09:30 NY (" + TimeToString(open, TIME_MINUTES) +\n'
     '                " broker time). Opening range builds 5 / 15 / 30 min. Levels are reference only. You decide.";'),
    # ---- panel ----
    ('   color cMkt = (NB_MARKET == NB_MKT_CRYPTO) ? NB_RGB(247, 147, 26) : NB_RGB(52, 152, 219);\n   color cKey',
     '   color cMkt = NB_RGB(0, 188, 212);   // US100 accent\n   color cKey'),
    ('   int rows = 70;\n', '   int rows = 74;   // US100: the US map has 4 more rows than the NY trap block\n'),
    ('   title = title + ((NB_MARKET == NB_MKT_CRYPTO) ? "  (CRYPTO + NY TRAP)" : "  (FOREX + NY TRAP)");',
     '   title = title + "  (US INDEX)";'),
    ('   string nyTxt = (g_label == "") ? "---" : NbNyText(TimeTradeServer());\n'
     '   color nyC = cVal;\n'
     '   if(StringFind(nyTxt, "NY OPEN - WINDOW") == 0)\n'
     '      nyC = cNy;\n'
     '   NbRow("ks", "vs", ox + kx, ox + vx, y, "NEW YORK OPEN", nyTxt, nyC, cKey, fs);\n',
     '   string nyTxt = (g_label == "") ? "---" : NbUsNowText();\n'
     '   color nyC = cVal;\n'
     '   if(StringFind(nyTxt, "OPEN - ") == 0)\n'
     '      nyC = cNy;\n'
     '   NbUsNewsRead(TimeTradeServer());\n'
     '   NbRow("ks", "vs", ox + kx, ox + vx, y, "US SESSION (CONTEXT)", nyTxt, nyC, cKey, fs);\n'),
    ('SEGMENT:   // NY session\n', '   // learning levels\n', frag("panel_rows.mqh") + "\n"),
    # ---- legend lines: MT5 cuts label text at 63 characters (the twins' longer lines are an OPEN ITEM) ----
    ('"NRTR CHANNEL: thick stop line. Green under price = BULLISH, red over = BEARISH."', '"NRTR: stop line. Green under = BULLISH, red over = BEARISH."'),
    ('"ZIGZAG (blue): confirmed swings. HH+HL = up, LH+LL = down. Shown " + IntegerToString(InpSwingStrength) + " bars late, never moves."',
     '"ZIGZAG: confirmed swings, HH+HL up, LH+LL down, " + IntegerToString(InpSwingStrength) + " bars late."'),
    ('"EMA200 (blue line): filter. Close above = BUY side only, below = SELL side only."', '"EMA200 (blue): close above = BUY side only, below = SELL only."'),
    ('"ARROW = NRTR flip on a CLOSED candle (bright = with 15M boss). Yellow ? = preview only."', '"ARROW = NRTR flip on a CLOSED candle. Yellow ? = preview only."'),
    ('"NY TRAP (purple): pre-NY range (dashed) swept, then a 5M close back inside. Purple marker = trap."', '"US MAP: PDH/PDL, PRE-MARKET, OPENING RANGE lines = reference."'),
    ('"Learning tool. Aligned conditions, not a profit promise. Count the markers."', '"Learning tool. Aligned conditions, not a profit promise."'),
    ('"LIVE BOX  -  BOTH SIDES FROM THE SAME RULES  -  THE GATE DECIDES"', '"LIVE BOX  -  BOTH SIDES, SAME RULES  -  THE GATE DECIDES"'),
    ('"tick > " + IntegerToString(InpMaxTickAgeSec) + "s  or  forming bar > 2 bars old  or  clock skew > " + IntegerToString(InpMaxClockSkewSec) + "s"',
     '"tick > " + IntegerToString(InpMaxTickAgeSec) + "s or bar > 2 bars old or skew > " + IntegerToString(InpMaxClockSkewSec) + "s"'),
    # ---- five-question table / adapters ----
    ('color NbFqAccent()\n{\n   return (NB_MARKET == NB_MKT_CRYPTO) ? NB_RGB(247, 147, 26) : NB_RGB(52, 152, 219);\n}',
     'color NbFqAccent()\n{\n   return NB_RGB(0, 188, 212);\n}'),
    ('//--- Asia / London hours need UTC: the twins\' two-witness session clock\n'
     'void NbFqClock(bool &ok, long &offset)\n{\n'
     '   ok = (g_S.clockMode == NB_CLK_AUTO && g_S.clockOk);\n'
     '   offset = ok ? g_S.offset : 0;\n}',
     '//--- US100: the US map needs the NY clock (AUTO two witnesses, or the\n'
     '//    typed 09:30 NY). It also hands the US settings to the map config.\n'
     'void NbFqClock(bool &ok, long &offset)\n{\n'
     '   ok = g_S.clockOk;\n'
     '   offset = (g_S.clockMode == NB_CLK_AUTO && g_S.clockOk) ? g_S.offset : 0;\n'
     '   g_C.usMode = g_S.clockMode;\n'
     '   g_C.usOpenSec = g_S.manualOpenSec;\n'
     '   g_C.usGapAtr = InpUsGapAtr;\n'
     '   g_C.usOrMin = InpUsOrMinutes;\n'
     '   g_C.usSrvDst = (int)InpUsServerDst;\n'
     '   g_C.usOffBase = NbSrvBase(g_S.offset, (long)TimeTradeServer() - g_S.offset, g_C.usSrvDst);\n}'),
    ('         mapR = "ASIA " + NbPx(g_fq[i].ash) + " / " + NbPx(g_fq[i].asl) + "   LDN " + NbPx(g_fq[i].loh) + " / " + NbPx(g_fq[i].lol);',
     '         mapR = "PMH " + NbPx(g_fq[i].ash) + " PML " + NbPx(g_fq[i].asl) + "  OR" + IntegerToString(InpUsOrMinutes) + " " + NbPx(g_fq[i].loh) +\n'
     '                "/" + NbPx(g_fq[i].lol);'),
    ('         mapR = "ASIA / LONDON: UTC offset unknown - not shown";',
     '         mapR = "PRE-MARKET / OR: NY clock unknown - not shown";'),
    # ---- bridge adapters ----
    ('SEGMENT://--- per-file bridge adapters (the twins: identical text, NB_MARKET decides)\n',
     '//--- v1.09 bridge adapters (twins)', frag("nb_us_terminal.mqh") + "\n"),
]


def build():
    text = open(SRC, encoding="ascii").read()
    a = text.index("#property copyright")
    text = HEADER + text[a:]
    for p in PATCHES:
        if len(p) == 3:   # SEGMENT: replace from the start anchor up to (not including) the end anchor
            start, end, new = p[0][len("SEGMENT:"):], p[1], p[2]
            if text.count(start) != 1:
                raise SystemExit("MAKE US100: FAIL - segment start not found exactly once: %r" % start[:60])
            i = text.index(start)
            j = text.find(end, i)
            if j < 0 or text.count(end, i) < 1:
                raise SystemExit("MAKE US100: FAIL - segment end not found: %r" % end[:60])
            text = text[:i] + new + text[j:]
            continue
        old, new = p
        if text.count(old) != 1:
            raise SystemExit("MAKE US100: FAIL - anchor found %d times (must be 1): %r" % (text.count(old), old[:70]))
        text = text.replace(old, new)
    text.encode("ascii")
    return text


def main():
    text = build()
    if "--check" in sys.argv:
        cur = open(DST, encoding="ascii").read()
        if cur != text:
            print("MAKE US100: FAIL - %s differs from crypto + the declared patches (run tests/make_us100.py)" % DST)
            return 1
        print("MAKE US100: PASS - %s = crypto + %d declared patches" % (DST, len(PATCHES)))
        return 0
    open(DST, "w", encoding="ascii").write(text)
    print("MAKE US100: %s written from %s + %d declared patches" % (DST, SRC, len(PATCHES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
