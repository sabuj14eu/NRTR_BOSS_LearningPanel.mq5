#!/usr/bin/env python3
"""The tests can fail: plant one realistic bug at a time into a COPY of a
source file and check that the five-question suites catch it.

For every mutation the copy is translated, the five-question engine tests,
the five-question indicator tests and the "existing panel unchanged" dump
are built against it and run. A mutation counts as CAUGHT when at least one
of them fails. Anything not caught is printed as ESCAPED and the script
exits non-zero.

usage: python3 tests/mutate_fq.py [N ...]   (from the repository root; needs git + g++;
       optional mutation numbers run only those)
"""
import os
import subprocess
import sys

BASELINE = "3f046ef"
FLAGS = ["-std=c++17", "-O1", "-Wall", "-Wextra", "-Wno-unused-parameter", "-Werror"]
TARGETS = {   # tag: (source file, NB_TEST_MARKET, engine inc name, full inc name)
    "crypto": ("NRTR_BOSS_Crypto_NYTrap.mq5", "1", "engine_crypto.inc", "full_crypto.inc"),
    "gold": ("NRTR_BOSS_LearningPanel.mq5", "0", "engine.inc", "full.inc"),
    "us100": ("NRTR_BOSS_US100.mq5", "3", "engine_us100.inc", "full_us100.inc"),   # v1.11: its own suite, no v1.04 baseline
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
     "   bool gate = ok && g_fresh;           // STALE DATA IS NEVER A PLAN", "   bool gate = ok;           // STALE DATA IS NEVER A PLAN"),
    ("crypto", "sweep anchored at the LATEST pierce (the stop moves up on a re-dip)",
     "         for(int j = j0; j <= i; j++)", "         for(int j = i; j >= j0; j--)"),
    ("crypto", "pending plan not cancelled when the 15M structure turns",
     "      if(cur >= 0 && pl[cur].status == NB_PO_PENDING && tr != pl[cur].dir)",
     "      if(cur >= 0 && pl[cur].status == NB_PO_PENDING && tr != pl[cur].dir && false)"),
    ("crypto", "table no longer steps aside for the main panel",
     "   int pw = (int)MathRound(430 * sc);   // the main panel's width (NbDrawPanel)\n   int ox = (cw - W) / 2;\n"
     "   if(InpPanelCorner == NB_TOP_LEFT || InpPanelCorner == NB_BOTTOM_LEFT)\n   {\n      if(ox < InpPanelX + pw + 8)",
     "   int pw = (int)MathRound(430 * sc);   // the main panel's width (NbDrawPanel)\n   int ox = (cw - W) / 2;\n"
     "   if(InpPanelCorner == NB_TOP_LEFT || InpPanelCorner == NB_BOTTOM_LEFT)\n   {\n      if(false)"),
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
     "   bool gate = ok && g_fresh;           // STALE DATA IS NEVER A PLAN", "   bool gate = ok;           // STALE DATA IS NEVER A PLAN"),
    # ---- v1.06 metals NY trap + decision ladder (caught by tests/test_nyt.cpp) ----
    ("gold", "v1.06 NY trap: trigger without a body (any close back inside counts)",
     "(c > s.level + need && c > o) : (c < s.level - need && c < o)", "(c > s.level + need) : (c < s.level - need)"),
    ("gold", "v1.06 NY trap: forming 5M candle evaluated",
     "   int nEvalNy = lastClosed ? n : n - 1;", "   int nEvalNy = n;"),
    ("gold", "v1.06 NY trap: silver wider stop ignored",
     "   g_N.slBufMult = slm;", "   g_N.slBufMult = 1.0;"),
    ("gold", "v1.06 NY trap: silver stronger close back inside ignored",
     "   g_N.confirmAtr = cfa;", "   g_N.confirmAtr = 0.0;"),
    ("gold", "v1.06 NY trap: TP1 checked before SL on the same candle",
     "         if(stop)\n         {\n            s.state = NB_NT_INVALID;\n            s.why = NB_NTW_SL;",
     "         if(stop && !tp)\n         {\n            s.state = NB_NT_INVALID;\n            s.why = NB_NTW_SL;"),
    ("gold", "v1.06 NY trap: runs at the weekend",
     "      int wd = (int)((day + 4) % 7);   // 1970-01-01 was a Thursday; 0 = Sunday, 6 = Saturday",
     "      int wd = 3;"),
    ("gold", "v1.06 NY trap: SL rounded inward (off the protective side of the tick grid)",
     "? NbRoundTick(s.sweep - buf, N.tick, N.digits, -1) : NbRoundTick(s.sweep + buf, N.tick, N.digits, 1);\n         double risk",
     "? NbRoundTick(s.sweep - buf, N.tick, N.digits, 1) : NbRoundTick(s.sweep + buf, N.tick, N.digits, -1);\n         double risk"),
    ("gold", "v1.06 ladder: NY trap AGAINST the 15M boss shown as VALID - CLICK",
     "      if(boss == tDir)\n      {\n         aDir = tDir;", "      if(boss == tDir || boss == -tDir)\n      {\n         aDir = tDir;"),
    ("gold", "v1.06 ladder: NY trap with the 15M boss in WAIT shown as VALID - CLICK",
     "      if(boss == tDir)\n      {\n         aDir = tDir;", "      if(boss != -tDir)\n      {\n         aDir = tDir;"),
    ("gold", "v1.06 ladder: 5-question plan against the 15M boss shown as PENDING ORDER PLAN",
     "      if(boss == fqDir)\n      {", "      if(true)\n      {"),
    ("gold", "v1.06 ladder: stale-data gate removed (NO TRADE never shown)",
     "   else if(!g_fresh)\n   {\n      act = \"NO TRADE\";", "   else if(false)\n   {\n      act = \"NO TRADE\";"),
    ("gold", "v1.06 ladder: money ignores the broker's tick value (1 per tick assumed)",
     "   return MathAbs(move) / g_tick * g_tickValue * lots;", "   return MathAbs(move) / g_tick * lots;"),
    ("gold", "v1.06 ladder: the forming candle's preview drives the timing row",
     "      if(g_final == NB_BUY || g_final == NB_SELL)\n      {\n         t2 = ",
     "      if(g_final == NB_BUY || g_final == NB_SELL || (bid > 0.0 && bid != g_s5.c[i5]))\n      {\n         t2 = "),
    # ---- v1.07 metals: NY rows on the table + PRE-NY / NY lines (caught by tests/test_nyt.cpp, default build) ----
    ("gold", "v1.07: the big ladder box back on by default (covers MT5's price scale)",
     "input bool           InpLadderShow      = false;", "input bool           InpLadderShow      = true; "),
    ("gold", "v1.07 NY rows: not docked on the table (drawn over it)",
     "      oy = ch - tableH - InpFqBottomY - H;", "      oy = ch - tableH - InpFqBottomY;"),
    ("gold", "v1.07 NY rows: stale-data gate removed (old trap prices shown as current)",
     "   bool gate = ok && g_fresh;   // STALE DATA IS NEVER A TRAP", "   bool gate = ok;   // STALE DATA IS NEVER A TRAP"),
    ("gold", "v1.07 NY rows: trap against the 15M boss not called CONFLICT",
     "   if(tDir != 0 && boss == -tDir)\n   {\n      vc = cExit;", "   if(false)\n   {\n      vc = cExit;"),
    ("gold", "v1.07 NY rows: a swept (not triggered) trap shown as VALID - CLICK",
     "   if(tDir != 0 && liveT && boss == tDir)\n   {\n      string tSide", "   if(tDir != 0 && boss == tDir)\n   {\n      string tSide"),
    ("gold", "v1.07 lines: SL / TP lines left on the chart after a side is INVALID",
     "   if(!(trig || s.state == NB_NT_VALID) || s.sl <= 0.0)\n      return;\n   color c = NbNytStateColor",
     "   if(s.state == NB_NT_OFF || s.sl <= 0.0)\n      return;\n   color c = NbNytStateColor"),
    # ---- v1.07 twins: data bridge + counter-trend watch (caught by tests/test_bridge.cpp + tests/test_bridge_py.py) ----
    ("crypto", "v1.07 watch: also fires WITH the 15M boss (becomes a trend signal)",
     "      if(flip[i] > 0 && boss[i] == NB_SELL)\n         dir = NB_BUY;", "      if(flip[i] > 0 && boss[i] != NB_WAIT)\n         dir = NB_BUY;"),
    ("crypto", "v1.07 watch: the forming 5M bar evaluated",
     "   int nEvalPw = lastClosed ? n : n - 1;", "   int nEvalPw = n;"),
    ("crypto", "v1.07 watch: TP1 checked before SL on the same candle",
     "         if(stopHit)\n            rec[open].status = NB_PW_SL;\n         else if(tpHit)\n            rec[open].status = NB_PW_TP1;",
     "         if(tpHit)\n            rec[open].status = NB_PW_TP1;\n         else if(stopHit)\n            rec[open].status = NB_PW_SL;"),
    ("crypto", "v1.07 watch: an open watch shown as CLICK in the bridge",
     "   else if(g_final == NB_BUY || g_final == NB_SELL)\n      action = NbBrAction(g_final);",
     "   else if(g_final == NB_BUY || g_final == NB_SELL || (g_pwCur >= 0 && g_pwCur < g_nPw))\n      action = NbBrAction((g_final != 0) ? g_final : g_pw[g_pwCur].dir);"),
    ("crypto", "v1.07 bridge: the forming candle counted as closed",
     "   int endClosed = hasForming ? last - 1 : last;", "   int endClosed = last;"),
    ("crypto", "v1.07 bridge: 19 closed candles instead of 18 (off by one)",
     "   int first = endClosed - want + 1;", "   int first = endClosed - want;"),
    ("crypto", "v1.07 bridge: stale data written as a live action",
     "   if(!g_fresh)\n      action = \"NO TRADE - DATA STALE / MARKET CLOSED\";",
     "   if(false)\n      action = \"NO TRADE - DATA STALE / MARKET CLOSED\";"),
    ("crypto", "v1.07 bridge: not rewritten when a 5M bar closes (only on the timer)",
     "   bool newBar = (g_seen5 != g_brBar);", "   bool newBar = false;"),
    ("crypto", "v1.07 bridge: 15M indicators taken from the wrong candle",
     "      int j = NbBrFind(s, r[k].time);", "      int j = NbBrFind(s, r[k].time) - 1;"),
    ("crypto", "v1.07 watch strip: not docked on the table",
     "   int oy = InpFqShow ? (ch - tableH - InpFqBottomY - H) : (ch - H - InpFqBottomY);",
     "   int oy = InpFqShow ? (ch - tableH - InpFqBottomY) : (ch - H - InpFqBottomY);"),
    # ---- v1.07 metals: AUTO NY clock, market state, bridge (caught by test_nyt / test_bridge / test_bridge_py) ----
    ("gold", "v1.07 clock: AUTO ignores the US DST calendar (an hour wrong in March / October)",
     "   long sec = (NbUsDst(day) ? (13 * 3600 + 1800) : (14 * 3600 + 1800)) + N.offset;", "   long sec = (13 * 3600 + 1800) + N.offset;"),
    ("gold", "v1.07 clock: the typed time used although AUTO is on",
     "   if(!N.autoClock)\n      return (datetime)(day * 86400 + N.openSec);", "   if(true)\n      return (datetime)(day * 86400 + N.openSec);"),
    ("gold", "v1.07 clock: the broker offset assumed when the witnesses disagree",
     "      g_N.openSec = ok ? 0 : -1;", "      g_N.openSec = (ok || true) ? 0 : -1;"),
    ("gold", "v1.07 clock: the main panel's NY row still on the typed time",
     "   datetime open = NbNyOpenToday(now);   // v1.07: the same clock as the NY trap (AUTO or typed)\n   if(open <= 0)\n      return \"NY CLOCK UNKNOWN",
     "   datetime open = (datetime)(((long)now / 86400) * 86400 + NbParseHHMM(InpNyOpenTime));\n   if(open <= 0)\n      return \"NY CLOCK UNKNOWN"),
    ("gold", "v1.07 NY rows: the PC time shifted the wrong way",
     "      when = when + \"  (PC \" + TimeToString(g_nt[i5].open + pcShift, TIME_MINUTES)", "      when = when + \"  (PC \" + TimeToString(g_nt[i5].open - pcShift, TIME_MINUTES)"),
    ("gold", "v1.07 market state: SUPER BULLISH even with NRTR flips in the last 6 h",
     "      return (dir5 > 0 && distAtr >= NB_MK_SUPER_ATR && flips == 0) ? NB_MK_SUPER_BULL : NB_MK_TREND_UP;",
     "      return (dir5 > 0 && distAtr >= NB_MK_SUPER_ATR) ? NB_MK_SUPER_BULL : NB_MK_TREND_UP;"),
    ("gold", "v1.07 market state: CHOP never named",
     "   if(flips >= NB_MK_CHOP_FLIPS)\n      return NB_MK_CHOP;", "   if(false)\n      return NB_MK_CHOP;"),
    ("gold", "v1.07 market state: shown from stale data",
     "   if(!g_fresh)\n   {\n      detail = \"data stale - no market state\";", "   if(false)\n   {\n      detail = \"data stale - no market state\";"),
    ("gold", "v1.07 bridge: NY trap SL written from the TP1 value",
     "NbJk(\"sl\") + (px ? NbJp(t.sl) : \"null\");", "NbJk(\"sl\") + (px ? NbJp(t.tp1) : \"null\");"),
    # ---- v1.09: regime pullback (metals) + the completed bridge schema (all three files; planted in crypto / gold) ----
    ("gold", "v1.09 pullback: a pull-up in a bearish regime recorded as a BUY",
     "               rec[nRec].dir = d;", "               rec[nRec].dir = -d;"),
    ("gold", "v1.09 pullback: the 4H ignored in the direction check",
     "      if(d240[i] < 0 && d60[i] < 0 && s5.boss[i] == NB_SELL)", "      if(d60[i] < 0 && s5.boss[i] == NB_SELL)"),
    ("gold", "v1.09 pullback: the forming 5M bar evaluated",
     "   int nEvalRp = lastClosed ? n : n - 1;", "   int nEvalRp = n;"),
    ("gold", "v1.09 pullback: a close beyond the structure does not invalidate the thesis",
     "      if((d < 0) ? (c > m.level) : (c < m.level))\n      {\n         m.state = NB_RP_INVALIDATED;",
     "      if(false)\n      {\n         m.state = NB_RP_INVALIDATED;"),
    ("gold", "v1.09 pullback: a candidate without location (not at structure, no sweep)",
     "         if(!m.atLoc && !m.swept)", "         if(false)"),
    ("gold", "v1.09 pullback: the minimum R:R ignored",
     "            if(risk <= C.tick * 0.5 || reward <= 0.0 || m.rr < C.minRR)", "            if(risk <= C.tick * 0.5 || reward <= 0.0)"),
    ("gold", "v1.09 pullback: a 15M swing used before it is confirmed (look-ahead)",
     "      while(k15 >= 0 && p15 < g_s15.np && g_piv15[p15].confirmIdx <= k15)", "      while(k15 >= 0 && p15 < g_s15.np && g_piv15[p15].idx <= k15)"),
    ("gold", "v1.09 pullback: stale data not suppressed in the bridge",
     "   if(!g_fresh)\n      return j + \",\" + NbJk(\"state\") + \"\\\"SUPPRESSED", "   if(false)\n      return j + \",\" + NbJk(\"state\") + \"\\\"SUPPRESSED"),
    ("crypto", "v1.09 bridge: the forming candle marked confirmed",
     "NbJk(\"forming\") + \"true,\" + NbJk(\"confirmed\") + \"false,\"", "NbJk(\"forming\") + \"false,\" + NbJk(\"confirmed\") + \"true,\""),
    ("crypto", "v1.09 bridge: a missing real volume written as 0",
     "   if(v <= 0)\n      return \"null\";\n   return IntegerToString(v);", "   if(v < 0)\n      return \"null\";\n   return IntegerToString(v);"),
    ("crypto", "v1.09 bridge: a missing ask - spread invented",
     "   bool quotes = (bidNow > 0.0 && askNow > 0.0 && askNow >= bidNow);", "   bool quotes = (bidNow > 0.0);"),
    ("crypto", "v1.09 bridge: written straight into the .json (not atomic)",
     "   int h = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);", "   int h = FileOpen(fin, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);"),
    # ---- v1.10 metals audit fixes ----
    ("gold", "v1.10 click guard: the proximity band ignored (READY however far the price went)",
     "   return (distR <= InpClickBandR + 1e-9) ? NB_CS_READY : NB_CS_FAR;", "   return NB_CS_READY;"),
    ("gold", "v1.10 click guard: no live price treated as READY",
     "   if(now <= 0.0)\n      return NB_CS_FAR;", "   if(now <= 0.0)\n      return NB_CS_READY;"),
    ("gold", "v1.10 click guard: the banner ignores it",
     "      st = NbSymUp() + ((cs == NB_CS_FAR) ? \"  BUY SETUP - PRICE TOO FAR\" : \"  READY - CLICK BUY\");",
     "      st = NbSymUp() + \"  READY - CLICK BUY\";"),
    ("gold", "v1.10 click guard: the bridge / Telegram ignores it",
     "   bool far = (NbClickState(n, d, r, a) == NB_CS_FAR);", "   bool far = (NbClickState(n, d, r, a) == -1);"),
    ("gold", "v1.10 lots: rounded to 2 decimals whatever the volume step (can round UP)",
     "   lots = NormalizeDouble(lots, vd);\n   if(volStep > 0.0 && lots * perLot > budget + 1e-9)   // floating guard: never above the budget\n      lots = NormalizeDouble(lots - volStep, vd);",
     "   lots = NormalizeDouble(lots, 2);"),
    ("gold", "v1.10 lots: the loss tick value ignored",
     "   if(tvLoss > g_tickValue)\n      g_tickValue = tvLoss;", "   if(false)\n      g_tickValue = tvLoss;"),
    ("gold", "v1.10 arrows: the first NRTR-ready bar marked as a flip again",
     "      bool flipHere = (prevAd != 0 && ad != prevAd);", "      bool flipHere = (ad != prevAd);"),
    ("gold", "v1.10 pending: a '---' limit line when the 5M is against the boss",
     "      if(m15 == NB_BUY && d5 <= 0)", "      if(false && m15 == NB_BUY && d5 <= 0)"),
    ("gold", "v1.07 lines: NY HIGH / LOW keep counting after the NY window",
     "      if(g_s5.t[k] >= g_nt[i].winEnd)\n         continue;\n", ""),    # ---- v1.10 twins: the metals fixes ported to crypto / forex ----
    ("crypto", "v1.10 twins click guard: the proximity band ignored",
     "   return (distR <= InpClickBandR + 1e-9) ? NB_CS_READY : NB_CS_FAR;", "   return NB_CS_READY;"),
    ("crypto", "v1.10 twins click guard: the banner ignores it (flow and trap)",
     "      st = NbSymUp() + ((cs == NB_CS_FAR) ? \"  BUY SETUP - PRICE TOO FAR\" : (liveTrap ? \"  READY - NY TRAP BUY\" : \"  READY - CLICK BUY\"));",
     "      st = NbSymUp() + (liveTrap ? \"  READY - NY TRAP BUY\" : \"  READY - CLICK BUY\");"),
    ("crypto", "v1.10 twins click guard: the TOO FAR reasons replaced by the trap reasons",
     "   if((g_final == NB_BUY || g_final == NB_SELL) && cs == NB_CS_FAR)\n   {\n      r1 = \"PRICE \"",
     "   if(false)\n   {\n      r1 = \"PRICE \""),
    ("crypto", "v1.10 twins click guard: the bridge / Telegram ignores it",
     "   bool far = (NbClickState(n, d, r, a) == NB_CS_FAR);", "   bool far = (NbClickState(n, d, r, a) == -1);"),
    ("crypto", "v1.10 twins lots: rounded to 2 decimals whatever the volume step",
     "   lots = NormalizeDouble(lots, vd);\n   if(volStep > 0.0 && lots * perLot > budget + 1e-9)   // floating guard: never above the budget\n      lots = NormalizeDouble(lots - volStep, vd);",
     "   lots = NormalizeDouble(lots, 2);"),
    ("crypto", "v1.10 twins lots: the loss tick value ignored",
     "   if(tvLoss > g_tickValue)\n      g_tickValue = tvLoss;", "   if(false)\n      g_tickValue = tvLoss;"),
    ("crypto", "v1.10 twins MARKET chip: shown on stale data",
     "   if(!g_fresh)\n   {\n      detail = \"data stale - no market state\";\n      return \"MARKET ---\";\n   }\n", ""),
    ("crypto", "v1.10 twins regime watch: missing 1H / 4H not said",
     "         st = (b.why == NB_RPW_NO_HTF) ? \"none - 1H / 4H data missing\" :", "         st = (false) ? \"none - 1H / 4H data missing\" :"),    # ---- v1.11 US100: its own rules ----
    ("us100", "v1.11 US: the first regular 5M bar labelled PRE-MARKET",
     "   if(mn < 9 * 60 + 30)\n      return NB_US_PRE;", "   if(mn < 9 * 60 + 35)\n      return NB_US_PRE;"),
    ("us100", "v1.11 US: LUNCH starts at 12:00 instead of 11:30",
     "   if(mn < 11 * 60 + 30)\n      return NB_US_MORNING;", "   if(mn < 12 * 60)\n      return NB_US_MORNING;"),
    ("us100", "v1.11 US: regular-session bars mixed into the pre-market range",
     "      if(ss == NB_US_PRE)\n      {\n         pmH", "      if(ss == NB_US_PRE || NbUsIsRth(ss))\n      {\n         pmH"),
    ("us100", "v1.11 US: a thin session (< 36 regular bars) becomes 'the previous day'",
     "         if(curDay >= 0 && rN >= NB_US_RTH_MIN_BARS)", "         if(curDay >= 0 && rN > 0)"),
    ("us100", "v1.11 US: opening range published with a bar missing",
     "            if(op > 0.0 && oN[q] == orMin[q] / 5)", "            if(op > 0.0 && oN[q] > 0)"),
    ("us100", "v1.11 US: opening range published one bar early",
     "         if(!oPub[q] && endEt >= base + 9 * 3600 + 1800 + orMin[q] * 60)", "         if(!oPub[q] && endEt >= base + 9 * 3600 + 1800 + orMin[q] * 60 - 300)"),
    ("us100", "v1.11 US: gap 'filled' measured against the open, not the previous close",
     "         if(gapDir > 0 && lo <= pcl)", "         if(gapDir > 0 && lo <= op)"),
    ("us100", "v1.11 US: a gap over a level counted as a SWEEP",
     "            if(pierce && NbUsGapped(s5.c[j - 1], s5.o[j], L))", "            if(false && pierce && NbUsGapped(s5.c[j - 1], s5.o[j], L))"),
    ("us100", "v1.11 US: a gap over a level counted as a BREAKOUT",
     "               if(NbUsGapped(s5.c[j - 1], s5.o[j], L))\n                  continue;", "               if(false)\n                  continue;"),
    ("us100", "v1.11 US: history converted with ONE scalar offset (the 2026-08-20 incident)",
     "   long utc = (long)t - offBase - 3600;      // try the summer hour first\n   if(!NbSrvDstOn(srvRule, utc))\n      utc = (long)t - offBase;",
     "   long utc = (long)t - offBase - (NbSrvDstOn(srvRule, (long)TimeTradeServer() - offBase) ? 3600 : 0);"),
    ("us100", "v1.11 US: the EU server DST switch on the wrong hour",
     "      return (d > lastSun) || (d == lastSun && hr >= 1);", "      return (d >= lastSun);"),
    ("us100", "v1.11 US: news given a direction in an event window",
     "NbJk(\"event\") + ((g_usNewsName != \"\") ? NbJs(g_usNewsName) : \"null\") + \",\" + NbJk(\"direction\") + \"\\\"UNKNOWN\\\",\"",
     "NbJk(\"event\") + ((g_usNewsName != \"\") ? NbJs(g_usNewsName) : \"null\") + \",\" + NbJk(\"direction\") + ((g_usNewsState == NB_NEWS_WINDOW) ? \"\\\"UP\\\",\" : \"\\\"UNKNOWN\\\",\")"),
    ("us100", "v1.11 US: an empty calendar read as 'no news'",
     "   if(hi == 0)\n   {\n      g_usNewsState = NB_NEWS_UNKNOWN;", "   if(false)\n   {\n      g_usNewsState = NB_NEWS_UNKNOWN;"),
    ("us100", "v1.11 US: the US map shown as live on stale data",
     "   if(ok && !g_fresh)\n      u2 = \"DATA STALE - NOT SHOWN AS LIVE\";\n   else if", "   if(false)\n      u2 = \"\";\n   else if"),
    ("us100", "v1.11 US: another symbol (NVDA) read as context for the gap row",
     "   if(b.pcl <= 0.0)\n      return \"--- (no previous regular close yet)\";",
     "   if(SymbolInfoDouble(\"NVDA\", SYMBOL_BID) > 0.0)\n      return \"NVDA UP\";\n   if(b.pcl <= 0.0)\n      return \"--- (no previous regular close yet)\";"),
    ("us100", "v1.11 US: the NY trap module switched back on",
     "   g_Seng.clockOk = false;", "   g_Seng.clockOk = g_S.clockOk;"),
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
    tests = [("test_fq_engine", []), ("test_fq_indicator", [])]
    if target == "us100":   # the US file has its own whole-indicator suite (and no v1.04 baseline to compare with)
        tests = [("test_us100", [])]
    if target == "gold":   # v1.06/v1.07 NY trap: metals only; the ladder build is the same source with InpLadderShow = true
        inc = open(os.path.join(d, full)).read()
        anchor = "const bool           InpLadderShow      = false;"
        on = "const bool           InpLadderShow      = true; "
        if inc.count(anchor) == 1:
            inc = inc.replace(anchor, on)
        elif inc.count(on) != 1:   # already on (a mutation may do that) = use as is; anything else = no build
            return {"BUILD": None}
        open(os.path.join(d, "full_ladder.inc"), "w").write(inc)
        tests += [("test_nyt", []), ("test_nyt_ladder", ["-DNYT_LADDER", '-DNYT_INC="full_ladder.inc"']), ("test_bridge", [])]
    if target == "crypto":   # v1.07 data bridge + counter-trend watch (twins)
        tests += [("test_bridge", []), ("test_session_indicator", [])]   # v1.10: the twin panel (click guard, chip, watch)
    for test, extra in tests:
        exe = os.path.join(d, test)
        srcf = "tests/test_nyt.cpp" if test.startswith("test_nyt") else "tests/%s.cpp" % test
        r = run(["g++"] + FLAGS + ["-I" + d, "-DNB_TEST_MARKET=" + mk] + extra + [srcf, "-o", exe])
        if r.returncode != 0:
            return {"BUILD": None}   # a mutation that does not compile proves nothing about the tests
        res[test] = run([exe]).returncode == 0
        if test == "test_bridge":   # it wrote build/bridge_*.json from the mutated file: check them too
            res["test_bridge_py"] = res[test] and run([sys.executable, "tests/test_bridge_py.py",
                                                      "gold" if target == "gold" else "crypto"]).returncode == 0
    if target == "us100":
        return res
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
    if run([sys.executable, "tests/baseline_patches.py", target, os.path.join(bd, src)]).returncode != 0:
        return "the declared baseline patches do not apply"
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
        err = baseline(t) if t != "us100" else ""
        if err:
            print("NOT RUNNABLE (%s): %s" % (t, err))
            return 2
        texts[t] = open(TARGETS[t][0], encoding="ascii").read()
        clean = build_and_test(t, texts[t], "clean_" + t)
        if not all(clean.values()):
            print("NOT RUNNABLE: the UNMUTATED %s file does not pass (%s)" % (t, clean))
            return 2
        print("unmutated %-6s: %s" % (t, "US100 suite PASS" if t == "us100" else "engine PASS, indicator PASS, existing panel unchanged PASS"))
    escaped = 0
    only = set(int(a) for a in sys.argv[1:])   # optional: mutation numbers to run, e.g. 22 36
    for k, (t, name, old, new) in enumerate(MUTATIONS, 1):
        if only and k not in only:
            continue
        text = texts[t]
        if text.count(old) != 1:
            print("M%02d NOT RUNNABLE - anchor not found exactly once in %s: %s" % (k, t, name))
            escaped += 1
            continue
        res = build_and_test(t, text.replace(old, new), "m%02d" % k)
        if "BUILD" in res or "translate" in res:
            print("M%02d [%-6s] %-72s NOT RUNNABLE - the mutated copy does not build" % (k, t, name))
            escaped += 1
            continue
        failed = [x for x, ok in res.items() if not ok]
        verdict = "CAUGHT by " + ", ".join(failed) if failed else "ESCAPED"
        if not failed:
            escaped += 1
        print("M%02d [%-6s] %-72s %s" % (k, t, name, verdict))
    planted = len(only) if only else len(MUTATIONS)
    print("MUTATION TESTS: %d planted, %d caught, %d escaped / not runnable" % (planted, planted - escaped, escaped))
    return 0 if escaped == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
