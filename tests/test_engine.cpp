// Engine tests. build/engine.inc is the ENGINE block of the real .mq5,
// translated syntax-only by mql2cpp.py.
#include "../tests/mql_shim.h"
#include "engine.inc"
#include "../tests/synth.h"
#include <cstdio>
#include <functional>

static int g_pass = 0, g_fail = 0;
#define CHECK(cond, msg)                                                   \
   do {                                                                    \
      if(cond) g_pass++;                                                   \
      else { g_fail++; std::printf("    FAIL %s:%d  %s\n", __FILE__, __LINE__, msg); } \
   } while(0)

static int section_fail_before = 0;
static void begin(const char *name)
{
   section_fail_before = g_fail;
   std::printf("[ RUN  ] %s\n", name);
}
static void end(const char *name)
{
   std::printf("[ %s ] %s\n", g_fail == section_fail_before ? " OK " : "FAIL", name);
}

static NbParams params(double tick, int digits)
{
   NbParams P;
   P.atrPeriod = 14;
   P.nrtrMult = 2.0;
   P.emaPeriod = 200;
   P.swing = 3;
   P.slBufAtr = 0.10;
   P.tp1R = 1.0;
   P.tp2R = 2.0;
   P.validBars = 6;
   P.tick = tick;
   P.digits = digits;
   return P;
}

static bool near(double a, double b, double eps = 1e-9) { return std::fabs(a - b) <= eps; }

//--- hand-built 5M arrays for the trigger tests -------------------------
struct Crafted
{
   std::vector<double> o, h, l, c, atr;
   std::vector<int> dir, boss, bossR;
   std::vector<NbPivot> piv;
   int np = 0;
};

// dir=+1: bars bearish-bodied except `trigBar` (bullish), swing low at bar 10.
// dir=-1: mirror image.
static Crafted craft(int n, int dir, int boss5, int trigBar)
{
   Crafted k;
   for(int i = 0; i < n; i++)
   {
      bool trig = (i == trigBar);
      if(dir > 0)
      {
         k.o.push_back(trig ? 99.5 : 100.5);
         k.c.push_back(100.0);
         k.h.push_back(101.0);
         k.l.push_back(i == 10 ? 90.0 : 95.0);
      }
      else
      {
         k.o.push_back(trig ? 100.5 : 99.5);
         k.c.push_back(100.0);
         k.h.push_back(i == 10 ? 110.0 : 105.0);
         k.l.push_back(99.0);
      }
      k.atr.push_back(1.0);
      k.dir.push_back(boss5 == 0 ? dir : boss5);
      k.boss.push_back(dir);
      k.bossR.push_back(0);
   }
   k.np = NbFindPivots(k.h, k.l, n, 3, k.piv);
   return k;
}

struct TrigOut
{
   std::vector<int> state, reasons, sigOf;
   std::vector<NbSignal> sigs;
   int nSig = 0;
};
static TrigOut runTrig(Crafted &k, bool lastClosed, const NbParams &P)
{
   TrigOut t;
   int n = (int)k.c.size();
   NbRunTrigger(k.o, k.h, k.l, k.c, k.atr, k.dir, k.boss, k.bossR, k.piv, k.np, n, lastClosed, P, t.state,
                t.reasons, t.sigOf, t.sigs, t.nSig);
   return t;
}

//--- full pipeline over synthetic data ----------------------------------
struct Run
{
   NbSeries s15, s5;
   std::vector<NbPivot> p15, p5;
   std::vector<NbSignal> sigs;
   int nSig = 0;
};
static void fill(NbSeries &s, const std::vector<SBar> &v, int sec)
{
   NbSeriesResize(s, (int)v.size());
   s.sec = sec;
   for(size_t i = 0; i < v.size(); i++)
   {
      s.t[i] = v[i].t;
      s.o[i] = v[i].o;
      s.h[i] = v[i].h;
      s.l[i] = v[i].l;
      s.c[i] = v[i].c;
   }
}
// what the live indicator would hold right after 5M bar `last5` closed
static void runAt(Run &r, const std::vector<SBar> &m5, const std::vector<SBar> &m15, int first5, int last5,
                  long long first15t, const NbParams &P)
{
   std::vector<SBar> a(m5.begin() + first5, m5.begin() + last5 + 1);
   long long known = m5[(size_t)last5].t + 300;
   std::vector<SBar> b;
   for(const SBar &x : m15)
      if(x.t >= first15t && x.t + 900 <= known) b.push_back(x);
   fill(r.s5, a, 300);
   fill(r.s15, b, 900);
   NbRun15(r.s15, r.p15, P);
   NbRun5(r.s5, r.p5, r.s15, true, P, r.sigs, r.nSig);
}

static const long long T0 = 1788220800LL;   // a day boundary (UTC seconds)

int main()
{
   NbParams PG = params(0.01, 2);

   //------------------------------------------------------------------
   begin("01 15M bullish + 5M bullish -> CLICK BUY (with levels)");
   {
      Crafted k = craft(30, 1, 0, 20);
      TrigOut t = runTrig(k, true, PG);
      CHECK(t.state[19] == NB_WAIT && (t.reasons[19] & NB_R_5M_WAIT_CANDLE) != 0, "before trigger: waiting for candle");
      CHECK(t.state[20] == NB_BUY, "trigger bar is BUY");
      CHECK(t.nSig == 1 && t.sigs[0].idx == 20 && t.sigs[0].dir == NB_BUY, "one BUY signal at bar 20");
      CHECK(near(t.sigs[0].entry, 100.0), "entry = trigger close");
      CHECK(near(t.sigs[0].sl, 89.90), "SL = swing low 90 - 0.1*ATR, rounded DOWN to tick");
      CHECK(near(t.sigs[0].risk, 10.10), "risk = entry - SL");
      CHECK(near(t.sigs[0].tp1, 110.10) && near(t.sigs[0].tp2, 120.20), "TP1 = 1R, TP2 = 2R");
      CHECK(t.state[21] == NB_BUY && t.state[25] == NB_BUY, "stays clickable while valid");
      CHECK(t.state[26] == NB_WAIT && (t.reasons[26] & NB_R_SIG_EXPIRED) != 0, "expires after 6 bars");
      CHECK(t.nSig == 1, "no second signal in the same episode");
   }
   end("01");

   begin("02 15M bearish + 5M bearish -> CLICK SELL (with levels)");
   {
      Crafted k = craft(30, -1, 0, 20);
      TrigOut t = runTrig(k, true, PG);
      CHECK(t.state[20] == NB_SELL, "trigger bar is SELL");
      CHECK(t.nSig == 1 && t.sigs[0].dir == NB_SELL, "one SELL signal");
      CHECK(near(t.sigs[0].sl, 110.10), "SL = swing high 110 + 0.1*ATR, rounded UP");
      CHECK(near(t.sigs[0].tp1, 89.90) && near(t.sigs[0].tp2, 79.80), "TP1/TP2 below entry");
   }
   end("02");

   begin("03 15M bullish + 5M bearish -> WAIT (5M AGAINST 15M)");
   {
      Crafted k = craft(30, 1, -1, 20);
      TrigOut t = runTrig(k, true, PG);
      bool allWait = true;
      for(int s = 0; s < 30; s++) allWait = allWait && t.state[s] == NB_WAIT && (t.reasons[s] & NB_R_5M_AGAINST) != 0;
      CHECK(allWait, "every bar WAIT with 5M AGAINST 15M");
      CHECK(t.nSig == 0, "no signal");
      CHECK(NbReasonAt(t.reasons[20], 0) == "5M AGAINST 15M", "plain-English reason");
   }
   end("03");

   begin("04 15M bearish + 5M bullish -> WAIT (5M AGAINST 15M)");
   {
      Crafted k = craft(30, -1, 1, 20);
      TrigOut t = runTrig(k, true, PG);
      bool allWait = true;
      for(int s = 0; s < 30; s++) allWait = allWait && t.state[s] == NB_WAIT && (t.reasons[s] & NB_R_5M_AGAINST) != 0;
      CHECK(allWait, "every bar WAIT with 5M AGAINST 15M");
      CHECK(t.nSig == 0, "no signal");
   }
   end("04");

   begin("05 EMA conflict -> WAIT");
   {
      int r = 0;
      CHECK(NbBossDecision(1, 99.0, 100.0, NB_ST_BULL, r) == NB_WAIT && (r & NB_R_EMA_CONFLICT) != 0, "bull NRTR+structure, price below EMA");
      CHECK(NbBossDecision(-1, 101.0, 100.0, NB_ST_BEAR, r) == NB_WAIT && (r & NB_R_EMA_CONFLICT) != 0, "bear NRTR+structure, price above EMA");
      CHECK(NbBossDecision(1, 100.0, 100.0, NB_ST_BULL, r) == NB_WAIT && (r & NB_R_EMA_FLAT) != 0, "price exactly on EMA");
      CHECK(NbBossDecision(1, 99.0, 100.0, NB_ST_BEAR, r) == NB_WAIT && (r & NB_R_NRTR_CONFLICT) != 0, "NRTR is the odd one out");
      CHECK(NbBossDecision(1, 101.0, 100.0, NB_ST_BULL, r) == NB_BUY && r == 0, "all aligned bull -> BUY MODE");
      CHECK(NbBossDecision(-1, 99.0, 100.0, NB_ST_BEAR, r) == NB_SELL && r == 0, "all aligned bear -> SELL MODE");
      // the conflict propagates to the 5M panel state
      Crafted k = craft(30, 1, 0, 20);
      for(int s = 0; s < 30; s++) { k.boss[(size_t)s] = NB_WAIT; k.bossR[(size_t)s] = NB_R_EMA_CONFLICT; }
      TrigOut t = runTrig(k, true, PG);
      CHECK(t.state[20] == NB_WAIT && t.reasons[20] == NB_R_EMA_CONFLICT && t.nSig == 0, "5M bullish candle cannot override 15M WAIT");
   }
   end("05");

   begin("06 structure mixed / unconfirmed -> WAIT");
   {
      int r = 0;
      CHECK(NbBossDecision(1, 101.0, 100.0, NB_ST_MIXED, r) == NB_WAIT && (r & NB_R_STRUCT_MIXED) != 0, "mixed");
      CHECK(NbBossDecision(1, 101.0, 100.0, NB_ST_UNKNOWN, r) == NB_WAIT && (r & NB_R_STRUCT_UNCONF) != 0, "unconfirmed");
      // hand-built highs/lows: H1 L1 H2(higher) L2(higher) -> HH/HL
      //                idx: 0    1    2    3    4    5    6    7    8    9   10   11   12   13   14
      std::vector<double> h = {10, 11, 15, 11, 10, 11, 10.5, 11, 10, 11, 17, 12, 11, 12, 13};
      std::vector<double> l = {9, 8, 9, 5, 9, 10, 9, 10, 7, 10, 11, 10, 11, 12, 12};
      std::vector<NbPivot> piv;
      int np = NbFindPivots(h, l, 15, 2, piv);
      std::vector<int> st, hl, ll, lk;
      NbStructureSeries(piv, np, 15, st, hl, ll, lk);
      // swings: H@2(15) L@3(5) L@8(7) H@10(17)
      CHECK(np == 4, "four confirmed swings");
      CHECK(st[9] == NB_ST_UNKNOWN, "only one high confirmed at bar 9 -> UNKNOWN, never guessed");
      CHECK(st[11] == NB_ST_UNKNOWN, "H@10 needs 2 more bars: still UNKNOWN at bar 11");
      CHECK(st[12] == NB_ST_BULL, "HH + HL confirmed at bar 12");
      CHECK(NbStructText(st[12], hl[12], ll[12], lk[12]) == "HL " + NbSymArrow() + " HH", "text in time order");
      // make the second low lower -> HH + LL = MIXED
      l[8] = 4;
      np = NbFindPivots(h, l, 15, 2, piv);
      NbStructureSeries(piv, np, 15, st, hl, ll, lk);
      CHECK(st[12] == NB_ST_MIXED, "HH + LL = MIXED");
   }
   end("06");

   begin("07 unfinished candle -> WAIT (never evaluated)");
   {
      Crafted k = craft(21, 1, 0, 20);   // bar 20 = the bullish candle, still forming
      TrigOut t = runTrig(k, false, PG);
      CHECK(t.state[20] == NB_WAIT, "forming candle does not create CLICK BUY");
      CHECK((t.reasons[20] & NB_R_CANDLE_OPEN) != 0, "reason says candle not closed");
      CHECK(t.nSig == 0, "no signal from a forming candle");
   }
   end("07");

   begin("08 confirmed (closed) candle -> eligible");
   {
      Crafted k = craft(21, 1, 0, 20);
      TrigOut t = runTrig(k, true, PG);
      CHECK(t.state[20] == NB_BUY && t.nSig == 1, "same candle once closed -> CLICK BUY");
   }
   end("08");

   begin("09 BUY position: EXIT / PROTECT judged on the FULL 15M BOSS mode");
   {
      int why = 0;
      // the six-row truth table from the audit
      CHECK(NbExitAdvice(1, NB_BUY, NB_BUY, why) == NB_ADV_HOLD && why == NB_WHY_INTACT, "BUY + BOSS BUY = HOLD");
      CHECK(NbExitAdvice(1, NB_BUY, NB_SELL, why) == NB_ADV_EXIT && why == NB_WHY_INVALIDATED, "BUY + BOSS SELL = EXIT (invalidated)");
      CHECK(NbExitAdvice(1, NB_WAIT, NB_SELL, why) == NB_ADV_EXIT && why == NB_WHY_AGAINST, "BUY opened without the boss, BOSS SELL = EXIT (against)");
      CHECK(NbExitAdvice(1, NB_SELL, NB_SELL, why) == NB_ADV_EXIT && why == NB_WHY_AGAINST, "BUY opened against the boss = EXIT (against)");
      CHECK(NbExitAdvice(1, NB_BUY, NB_WAIT, why) == NB_ADV_UNKNOWN && why == NB_WHY_BOSS_WAIT, "BUY + BOSS WAIT = UNKNOWN / PROTECT, not EXIT");
      CHECK(NbExitAdvice(0, 0, NB_BUY, why) == NB_ADV_NONE, "no position");
      int r = 0;
      CHECK(NbFinalState(NB_BUY, 0, true, NB_ADV_EXIT, r) == NB_EXIT, "EXIT outranks a fresh CLICK signal");
      CHECK(NbFinalState(NB_WAIT, NB_R_STRUCT_MIXED, true, NB_ADV_UNKNOWN, r) == NB_WAIT && r == NB_R_STRUCT_MIXED,
            "UNKNOWN / PROTECT never becomes the EXIT banner");
      // a single 15M NRTR flip against a BUY, with EMA200 and structure still
      // bullish, moves the boss to WAIT - and WAIT is not EXIT
      int mr = 0;
      int modeAfterFlip = NbBossDecision(-1, 105.0, 100.0, NB_ST_BULL, mr);
      CHECK(modeAfterFlip == NB_WAIT && (mr & NB_R_NRTR_CONFLICT) != 0, "NRTR flip alone -> boss WAIT (NRTR CONFLICT)");
      CHECK(NbExitAdvice(1, NB_BUY, modeAfterFlip, why) == NB_ADV_UNKNOWN && why == NB_WHY_BOSS_WAIT,
            "NRTR flip alone can never generate EXIT");
      // full boss flip: NRTR bear + close below EMA + LH/LL structure -> EXIT
      int modeFull = NbBossDecision(-1, 95.0, 100.0, NB_ST_BEAR, mr);
      CHECK(modeFull == NB_SELL && NbExitAdvice(1, NB_BUY, modeFull, why) == NB_ADV_EXIT, "complete boss flip -> EXIT");
      // mode at open time uses only 15M bars CLOSED by then
      std::vector<datetime> t = {0, 900, 1800, 2700};
      std::vector<int> d = {NB_BUY, NB_BUY, NB_SELL, NB_SELL};
      CHECK(NbKnownAtTime(t, d, 4, 900, 1800) == NB_BUY, "at 00:30 only bars closed by 00:30 count");
      CHECK(NbKnownAtTime(t, d, 4, 900, 2699) == NB_BUY, "bar 1800 not closed until 2700");
      CHECK(NbKnownAtTime(t, d, 4, 900, 2700) == NB_SELL, "bar 1800 closed at 2700");
      CHECK(NbKnownAtTime(t, d, 4, 900, 100) == 0, "before any closed bar -> unknown");
   }
   end("09");

   begin("10 SELL position: EXIT / PROTECT judged on the FULL 15M BOSS mode");
   {
      int why = 0;
      CHECK(NbExitAdvice(-1, NB_SELL, NB_SELL, why) == NB_ADV_HOLD && why == NB_WHY_INTACT, "SELL + BOSS SELL = HOLD");
      CHECK(NbExitAdvice(-1, NB_SELL, NB_BUY, why) == NB_ADV_EXIT && why == NB_WHY_INVALIDATED, "SELL + BOSS BUY = EXIT (invalidated)");
      CHECK(NbExitAdvice(-1, NB_BUY, NB_BUY, why) == NB_ADV_EXIT && why == NB_WHY_AGAINST, "SELL opened against the boss = EXIT (against)");
      CHECK(NbExitAdvice(-1, NB_SELL, NB_WAIT, why) == NB_ADV_UNKNOWN && why == NB_WHY_BOSS_WAIT, "SELL + BOSS WAIT = UNKNOWN / PROTECT, not EXIT");
      int mr = 0;
      int modeAfterFlip = NbBossDecision(1, 95.0, 100.0, NB_ST_BEAR, mr);
      CHECK(modeAfterFlip == NB_WAIT && NbExitAdvice(-1, NB_SELL, modeAfterFlip, why) == NB_ADV_UNKNOWN,
            "NRTR flip alone against a SELL -> UNKNOWN / PROTECT, never EXIT");
   }
   end("10");

   //------------------------------------------------------------------
   // Synthetic history used by 11 and 14 (16 days of 5M gold bars)
   std::vector<SBar> m5 = gen5m(7, 16 * 288, T0, 2400.0, 0.01, 1.2);
   std::vector<SBar> m15 = agg(m5, 900);
   int N5 = (int)m5.size();

   begin("11 historical signals never repaint");
   {
      Run full;
      runAt(full, m5, m15, 0, N5 - 1, T0, PG);
      int buys = 0, sells = 0;
      for(int k = 0; k < full.nSig; k++) (full.sigs[(size_t)k].dir > 0 ? buys : sells)++;
      std::printf("    fixture: %d 5M bars, %d 15M bars, %d signals (%d BUY / %d SELL)\n", full.s5.n, full.s15.n,
                  full.nSig, buys, sells);
      CHECK(buys > 0 && sells > 0, "fixture exercises both BUY and SELL");
      int cuts = 0;
      bool same5 = true, same15 = true, sameSig = true;
      for(int cut = 300; cut < N5 - 1; cut += 37)
      {
         Run p;
         runAt(p, m5, m15, 0, cut, T0, PG);
         cuts++;
         for(int s = 0; s <= cut; s++)
            if(p.s5.state[(size_t)s] != full.s5.state[(size_t)s] || p.s5.reasons[(size_t)s] != full.s5.reasons[(size_t)s] ||
               p.s5.map[(size_t)s] != full.s5.map[(size_t)s] || p.s5.dir[(size_t)s] != full.s5.dir[(size_t)s] ||
               p.s5.stop[(size_t)s] != full.s5.stop[(size_t)s])
               same5 = false;
         for(int i = 0; i < p.s15.n; i++)
            if(p.s15.mode[(size_t)i] != full.s15.mode[(size_t)i] || p.s15.mr[(size_t)i] != full.s15.mr[(size_t)i] ||
               p.s15.dir[(size_t)i] != full.s15.dir[(size_t)i] || p.s15.ema[(size_t)i] != full.s15.ema[(size_t)i] ||
               p.s15.st[(size_t)i] != full.s15.st[(size_t)i] || p.s15.hl[(size_t)i] != full.s15.hl[(size_t)i] ||
               p.s15.ll[(size_t)i] != full.s15.ll[(size_t)i])
               same15 = false;
         int inFull = 0;
         for(int k = 0; k < full.nSig; k++) if(full.sigs[(size_t)k].idx <= cut) inFull++;
         if(inFull != p.nSig) sameSig = false;
         for(int k = 0; k < p.nSig && sameSig; k++)
         {
            const NbSignal &a = p.sigs[(size_t)k], &b = full.sigs[(size_t)k];
            if(a.idx != b.idx || a.dir != b.dir || a.entry != b.entry || a.sl != b.sl || a.tp1 != b.tp1 ||
               a.tp2 != b.tp2 || a.swingIdx != b.swingIdx)
               sameSig = false;
            if(a.status != NB_SIG_ACTIVE && (a.status != b.status || a.statusIdx != b.statusIdx)) sameSig = false;
         }
      }
      std::printf("    compared %d cut points against the full run\n", cuts);
      CHECK(same5, "every past 5M state/reason/NRTR identical at every cut");
      CHECK(same15, "every past 15M NRTR/EMA/structure/mode identical at every cut");
      CHECK(sameSig, "every past signal (bar, side, entry, SL, TPs) identical at every cut");

      // future candles replaced by a completely different path
      std::vector<SBar> alt = m5;
      std::vector<SBar> other = gen5m(99, N5, T0, 2400.0, 0.01, 3.0);
      int cut = N5 / 2;
      double shift = alt[(size_t)cut].c - other[(size_t)cut].c;
      for(int i = cut + 1; i < N5; i++)
      {
         SBar b = other[(size_t)i];
         alt[(size_t)i] = {m5[(size_t)i].t, b.o + shift, b.h + shift, b.l + shift, b.c + shift};
      }
      std::vector<SBar> alt15 = agg(alt, 900);
      Run r2;
      runAt(r2, alt, alt15, 0, N5 - 1, T0, PG);
      bool past = true;
      for(int s = 0; s <= cut; s++)
         if(r2.s5.state[(size_t)s] != full.s5.state[(size_t)s] || r2.s5.reasons[(size_t)s] != full.s5.reasons[(size_t)s])
            past = false;
      CHECK(past, "a different future leaves every past decision unchanged");
   }
   end("11");

   begin("12 digits / tick size taken from the symbol, never hard-coded");
   {
      CHECK(near(NbRoundTick(63.7249, 0.001, 3, -1), 63.724), "silver 3 digits, round down");
      CHECK(near(NbRoundTick(63.7241, 0.001, 3, 1), 63.725), "silver 3 digits, round up");
      CHECK(near(NbRoundTick(2401.237, 0.01, 2, 0), 2401.24), "gold 2 digits, nearest");
      CHECK(near(NbRoundTick(2401.237, 0.05, 2, -1), 2401.20), "gold with 0.05 tick, round down");
      CHECK(near(NbRoundTick(63.72, 0.001, 3, -1), 63.720), "exact grid value is not pushed a tick");
      CHECK(near(NbRoundTick(30.12345, 0.00001, 5, 1), 30.12345), "5-digit silver feed");
      struct Case { double tick; int digits; double price; double vol; const char *name; };
      Case cases[] = {{0.01, 2, 2400.0, 1.2, "XAUUSD 2dp"}, {0.001, 3, 30.0, 0.015, "XAGUSD 3dp"},
                      {0.00001, 5, 30.0, 0.015, "XAGUSD 5dp"}, {0.05, 2, 2400.0, 1.2, "gold 0.05 tick"}};
      for(const Case &cs : cases)
      {
         std::vector<SBar> a = gen5m(11, 12 * 288, T0, cs.price, cs.tick, cs.vol);
         std::vector<SBar> b = agg(a, 900);
         NbParams P = params(cs.tick, cs.digits);
         Run r;
         runAt(r, a, b, 0, (int)a.size() - 1, T0, P);
         bool onGrid = r.nSig > 0;
         for(int k = 0; k < r.nSig; k++)
         {
            const NbSignal &g = r.sigs[(size_t)k];
            double vals[] = {g.entry, g.sl, g.tp1, g.tp2, g.risk};
            for(double v : vals)
            {
               double q = v / cs.tick;
               if(std::fabs(q - std::round(q)) > 1e-6) onGrid = false;
            }
            if(g.dir > 0 && !(g.sl < g.entry && g.entry < g.tp1 && g.tp1 < g.tp2)) onGrid = false;
            if(g.dir < 0 && !(g.sl > g.entry && g.entry > g.tp1 && g.tp1 > g.tp2)) onGrid = false;
         }
         char msg[160];
         std::snprintf(msg, sizeof msg, "%s: %d signals, every level on the tick grid and correctly ordered", cs.name, r.nSig);
         CHECK(onGrid, msg);
      }
      CHECK(NbMetalOf("XAUUSD", "XAU", "USD") == NB_METAL_GOLD, "XAUUSD");
      CHECK(NbMetalOf("XAGUSD", "XAG", "USD") == NB_METAL_SILVER, "XAGUSD");
      CHECK(NbMetalOf("XAUUSD.m", "XAU", "USD") == NB_METAL_GOLD, "suffix");
      CHECK(NbMetalOf("#xagusd", "", "") == NB_METAL_SILVER, "prefix + lower case");
      CHECK(NbMetalOf("GOLD", "GOLD", "USD") == NB_METAL_GOLD, "GOLD");
      CHECK(NbMetalOf("SILVERm", "", "USD") == NB_METAL_SILVER, "SILVERm");
      CHECK(NbMetalOf("XAUEUR", "XAU", "EUR") == NB_METAL_NONE, "gold in EUR rejected");
      CHECK(NbMetalOf("EURUSD", "EUR", "USD") == NB_METAL_NONE, "FX rejected");
      CHECK(NbMetalOf("US100", "USD", "USD") == NB_METAL_NONE, "index rejected");
      CHECK(NbMetalOf("BTCUSD", "BTC", "USD") == NB_METAL_NONE, "crypto rejected");
   }
   end("12");

   begin("14 restart -> identical state");
   {
      Run a, b;
      runAt(a, m5, m15, 0, N5 - 1, T0, PG);
      runAt(b, m5, m15, 0, N5 - 1, T0, PG);
      bool same = a.nSig == b.nSig && a.s5.state == b.s5.state && a.s5.reasons == b.s5.reasons &&
                  a.s15.mode == b.s15.mode && a.s15.ema == b.s15.ema && a.s5.stop == b.s5.stop;
      CHECK(same, "same bars (same-day restart, same anchor) -> bit-identical output");
      // next-day restart: the window starts one day later (EMA/NRTR re-seed)
      Run c;
      runAt(c, m5, m15, 288, N5 - 1, T0 + 86400, PG);
      int off5 = 288;
      int lastDays = 4 * 288, agree = 0, total = 0;
      for(int s = N5 - lastDays; s < N5; s++)
      {
         total++;
         if(c.s5.state[(size_t)(s - off5)] == a.s5.state[(size_t)s]) agree++;
      }
      std::printf("    next-day restart: last 4 days of 5M states agree on %d / %d bars\n", agree, total);
      CHECK(c.s5.state.back() == a.s5.state.back() && c.s5.reasons.back() == a.s5.reasons.back(),
            "next-day restart: current state identical");
      CHECK(agree == total, "next-day restart: last 4 days of history identical");
   }
   end("14");

   begin("15 missing / incomplete data -> WAIT, never a guess");
   {
      Run r;
      r.s15.n = 0;
      std::vector<SBar> few(m5.begin(), m5.begin() + 60);
      std::vector<SBar> few15 = agg(few, 900);
      fill(r.s5, few, 300);
      fill(r.s15, few15, 900);
      NbRun15(r.s15, r.p15, PG);
      NbRun5(r.s5, r.p5, r.s15, true, PG, r.sigs, r.nSig);
      bool allWait = true;
      for(int s = 0; s < r.s5.n; s++) allWait = allWait && r.s5.state[(size_t)s] == NB_WAIT;
      CHECK(allWait && r.nSig == 0, "60 5M bars (20 15M bars): nothing but WAIT");
      CHECK((r.s15.mr.back() & NB_R_EMA_NOT_READY) != 0, "reason: EMA200 not ready");
      CHECK((r.s5.reasons[0] & NB_R_NO_15M_BAR) != 0, "first 5M bar has no closed 15M bar -> WAIT");
      NbSeries e15, e5;
      std::vector<NbPivot> pv;
      std::vector<NbSignal> sg;
      int ns = 0;
      NbSeriesResize(e15, 0);
      NbSeriesResize(e5, 0);
      e15.sec = 900;
      e5.sec = 300;
      NbRun15(e15, pv, PG);
      NbRun5(e5, pv, e15, true, PG, sg, ns);
      CHECK(ns == 0 && e5.state.empty(), "empty history: no crash, no signal");
      int out = 0;
      CHECK(NbFinalState(NB_BUY, 0, false, NB_ADV_NONE, out) == NB_WAIT && out == NB_R_STALE, "stale data can never show CLICK BUY");
      CHECK(NbFinalState(NB_WAIT, 0, true, NB_ADV_NONE, out) == NB_WAIT && out == NB_R_NO_DATA, "WAIT always carries a reason");
      CHECK(NbIsFresh(1000, 300, 900, 900, 1300 + 900), "fresh within window");
      CHECK(!NbIsFresh(1000, 300, 900, 900, 1300 + 901), "5M older than 3 bars -> stale");
      CHECK(!NbIsFresh(0, 300, 900, 900, 1000), "no bar -> stale");
   }
   end("15");

   begin("16 input contract + level invariants + pivot confirmation");
   {
      NbParams bad = PG;
      CHECK(NbParamsValid(PG), "defaults (TP1 1R, TP2 2R) are valid");
      bad.tp2R = bad.tp1R;
      CHECK(!NbParamsValid(bad), "TP2 == TP1 rejected");
      bad.tp2R = bad.tp1R - 0.1;
      CHECK(!NbParamsValid(bad), "TP2 < TP1 rejected");
      bad = PG;
      bad.tp2R = bad.tp1R + 0.01;
      CHECK(NbParamsValid(bad), "TP2 barely above TP1 accepted");
      bad = PG;
      bad.tp1R = 0.0;
      CHECK(!NbParamsValid(bad), "TP1 <= 0 rejected");
      // every learning signal in both fixtures respects the level order
      struct Fx { uint64_t seed; double price, tick, vol; int digits; };
      Fx fx[2] = {{7, 2400.0, 0.01, 1.2, 2}, {21, 30.0, 0.001, 0.015, 3}};
      int total = 0;
      bool okBuy = true, okSell = true, okStop = true, okTp = true;
      for(int f = 0; f < 2; f++)
      {
         NbParams P = params(fx[f].tick, fx[f].digits);
         std::vector<SBar> a = gen5m(fx[f].seed, 16 * 288, T0, fx[f].price, fx[f].tick, fx[f].vol);
         std::vector<SBar> b = agg(a, 900);
         Run r;
         runAt(r, a, b, 0, (int)a.size() - 1, T0, P);
         for(int k = 0; k < r.nSig; k++)
         {
            const NbSignal &g = r.sigs[(size_t)k];
            total++;
            if(g.dir > 0) okBuy = okBuy && g.sl < g.entry && g.entry < g.tp1 && g.tp1 < g.tp2;
            else okSell = okSell && g.tp2 < g.tp1 && g.tp1 < g.entry && g.entry < g.sl;
            okTp = okTp && near(g.tp2 - g.entry, 2.0 * (g.tp1 - g.entry), fx[f].tick * 0.51 + 1e-9);
            // the SL swing was confirmed (idx + swing) at or before the signal bar
            bool found = false;
            for(size_t q = 0; q < r.p5.size(); q++)
               if(r.p5[q].idx == g.swingIdx && r.p5[q].kind == -g.dir)
               {
                  found = true;
                  okStop = okStop && r.p5[q].confirmIdx <= g.idx;
               }
            okStop = okStop && found;
         }
      }
      std::printf("    %d signals checked across gold + silver fixtures\n", total);
      CHECK(total > 20, "enough signals to mean something");
      CHECK(okBuy, "BUY invariant: SL < Entry < TP1 < TP2 on every signal");
      CHECK(okSell, "SELL invariant: TP2 < TP1 < Entry < SL on every signal");
      CHECK(okTp, "TP2 = 2R and TP1 = 1R on every signal (to the tick)");
      CHECK(okStop, "every SL swing was CONFIRMED at or before the signal bar");
      // a swing that is confirmed only later is invisible to the stop search
      std::vector<NbPivot> pv(1);
      pv[0].idx = 10; pv[0].confirmIdx = 13; pv[0].kind = -1; pv[0].price = 90.0; pv[0].label = NB_L_HL;
      double sw = 0.0;
      CHECK(NbFindStopSwing(pv, 1, 12, 1, 100.0, 60, sw) < 0, "pivot not usable at bar 12 (confirms at 13)");
      CHECK(NbFindStopSwing(pv, 1, 13, 1, 100.0, 60, sw) == 0 && near(sw, 90.0), "pivot usable from its confirmation bar");
   }
   end("16");

   begin("17 same-candle rule: SL and TP1 touched in one candle -> SL (frozen)");
   {
      // BUY: signal at bar 20 (entry 100, SL 89.90, TP1 110.10). Bar 21 spans both.
      Crafted k = craft(30, 1, 0, 20);
      k.h[21] = 111.0;
      k.l[21] = 89.0;
      TrigOut t = runTrig(k, true, PG);
      CHECK(t.nSig == 1 && t.sigs[0].idx == 20, "signal exists");
      CHECK(t.sigs[0].status == NB_SIG_SL && t.sigs[0].statusIdx == 21, "BUY: both touched -> classified SL, on that bar");
      CHECK(t.state[21] == NB_WAIT && (t.reasons[21] & NB_R_SIG_SL) != 0, "panel says SETUP HIT ITS SL");
      // SELL mirror: entry 100, SL 110.10, TP1 89.90
      Crafted m = craft(30, -1, 0, 20);
      m.h[21] = 111.0;
      m.l[21] = 89.0;
      TrigOut u = runTrig(m, true, PG);
      CHECK(u.nSig == 1 && u.sigs[0].status == NB_SIG_SL && u.sigs[0].statusIdx == 21, "SELL: both touched -> SL");
      // TP1 alone (SL untouched) is still TP1, so the rule only bites on the tie
      Crafted w = craft(30, 1, 0, 20);
      w.h[21] = 111.0;
      TrigOut v = runTrig(w, true, PG);
      CHECK(v.nSig == 1 && v.sigs[0].status == NB_SIG_TP1, "TP1 alone -> TP1");
      // the entry candle itself is never judged
      Crafted z = craft(30, 1, 0, 20);
      z.h[20] = 111.0;
      z.l[20] = 89.0;
      TrigOut y = runTrig(z, true, PG);
      CHECK(y.nSig == 1 && y.state[21] == NB_BUY && y.sigs[0].status != NB_SIG_SL, "entry candle's own range does not judge the signal");
   }
   end("17");

   begin("18 NRTR definition: CUSTOM ATR-NRTR vs classic percentage NRTR (Kopyrkin)");
   {
      // Reference: the classic Nick Rypock Trailing Reverse as published for
      // MT4/MT5 (dynamic look-back on closes, percentage band K). If the panel
      // reproduced "the" NRTR, these would agree bar for bar. They do not,
      // which is why the panel is labelled CUSTOM ATR-NRTR.
      auto classic = [](const std::vector<double> &c, int period, double kPct, std::vector<int> &dir,
                        std::vector<double> &line) {
         int n = (int)c.size();
         dir.assign((size_t)n, 0);
         line.assign((size_t)n, 0.0);
         int trend = 0, dyn = 1;
         double price = 0.0, value = 0.0;
         for(int i = 0; i < n; i++)
         {
            if(trend == 0)
            {
               // seed the way the reference does: first bar sets an up-trend
               trend = 1; price = c[(size_t)i]; value = price * (1.0 - kPct / 100.0); dyn = 1;
            }
            else if(trend > 0)
            {
               int from = i - dyn + 1; if(from < 0) from = 0;
               price = c[(size_t)from];
               for(int j = from; j <= i; j++) if(c[(size_t)j] > price) price = c[(size_t)j];
               value = price * (1.0 - kPct / 100.0);
               if(c[(size_t)i] < value) { trend = -1; price = c[(size_t)i]; value = price * (1.0 + kPct / 100.0); dyn = 1; }
               else if(dyn < period) dyn++;
            }
            else
            {
               int from = i - dyn + 1; if(from < 0) from = 0;
               price = c[(size_t)from];
               for(int j = from; j <= i; j++) if(c[(size_t)j] < price) price = c[(size_t)j];
               value = price * (1.0 + kPct / 100.0);
               if(c[(size_t)i] > value) { trend = 1; price = c[(size_t)i]; value = price * (1.0 - kPct / 100.0); dyn = 1; }
               else if(dyn < period) dyn++;
            }
            dir[(size_t)i] = trend;
            line[(size_t)i] = value;
         }
      };
      struct Fx { const char *name; uint64_t seed; double price, tick, vol; double kPct; };
      // K chosen so the classic band is about 2 ATR on each fixture (fair comparison)
      Fx fx[2] = {{"XAUUSD", 7, 2400.0, 0.01, 1.2, 0.20}, {"XAGUSD", 21, 30.0, 0.001, 0.015, 0.20}};
      const int secs[2] = {900, 300};
      const char *tfn[2] = {"M15", "M5"};
      bool allIdentical = true;
      for(int f = 0; f < 2; f++)
      {
         std::vector<SBar> a = gen5m(fx[f].seed, 16 * 288, T0, fx[f].price, fx[f].tick, fx[f].vol);
         for(int tf = 0; tf < 2; tf++)
         {
            std::vector<SBar> v = (secs[tf] == 300) ? a : agg(a, secs[tf]);
            int n = (int)v.size();
            std::vector<double> h, l, c, atr, st, ex;
            std::vector<int> d, fl;
            for(const SBar &x : v) { h.push_back(x.h); l.push_back(x.l); c.push_back(x.c); }
            NbCalcATR(h, l, c, n, 14, atr);
            NbCalcNRTR(c, atr, n, 2.0, d, st, ex, fl);
            std::vector<int> rd;
            std::vector<double> rl;
            classic(c, 40, fx[f].kPct, rd, rl);
            int cmp = 0, dirDiff = 0, flipsA = 0, flipsB = 0, flipsSame = 0;
            double lineDiff = 0.0;
            for(int i = 200; i < n; i++)
            {
               cmp++;
               if(d[(size_t)i] != rd[(size_t)i]) dirDiff++;
               if(fl[(size_t)i] != 0) flipsA++;
               bool rflip = rd[(size_t)i] != rd[(size_t)i - 1];
               if(rflip) flipsB++;
               if(fl[(size_t)i] != 0 && rflip) flipsSame++;
               lineDiff += std::fabs(st[(size_t)i] - rl[(size_t)i]);
            }
            std::printf("    %s %s: %d bars | direction differs on %d (%.1f%%) | flips custom %d / classic %d, same bar %d | mean |line diff| %.4f\n",
                        fx[f].name, tfn[tf], cmp, dirDiff, 100.0 * dirDiff / cmp, flipsA, flipsB, flipsSame, lineDiff / cmp);
            if(dirDiff != 0 || flipsA != flipsSame || flipsB != flipsSame) allIdentical = false;
         }
      }
      CHECK(!allIdentical, "the two algorithms are NOT identical -> the CUSTOM ATR-NRTR label is required");
      // and the custom definition itself is frozen: highs/lows must not influence it
      std::vector<double> c = {10, 11, 12, 13, 14, 15, 13.9, 16, 12};
      std::vector<double> atr(9, 1.0);
      std::vector<int> d1, f1;
      std::vector<double> s1, e1;
      NbCalcNRTR(c, atr, 9, 2.0, d1, s1, e1, f1);
      CHECK(near(e1[5], 15.0) && near(s1[5], 13.0), "extreme = highest CLOSE since flip, stop = extreme - 2*ATR");
      CHECK(d1[8] == -1 && near(e1[8], 12.0) && near(s1[8], 14.0), "flip on CLOSE beyond the stop; new extreme = that close");
   }
   end("18");

   begin("19 lots for a fixed % risk (reference only)");
   {
      double m = 0.0;
      // 10000 balance, 1% = 100 budget; SL 5.70 on gold, tick 0.01 worth 1.0 -> 570 per lot -> 0.17 lots
      CHECK(near(NbLotsForRisk(10000, 1.0, 5.70, 0.01, 1.0, 0.01, 0.01, 100, m), 0.17) && near(m, 96.9), "rounded DOWN to the step");
      CHECK(NbLotsForRisk(100, 1.0, 5.70, 0.01, 1.0, 0.01, 0.01, 100, m) == 0.0, "min lot risks more than 1% -> 0 (skip)");
      CHECK(near(NbLotsForRisk(1e9, 1.0, 5.70, 0.01, 1.0, 0.01, 0.01, 100, m), 100.0), "clamped to volume max");
      CHECK(NbLotsForRisk(10000, 1.0, 0.0, 0.01, 1.0, 0.01, 0.01, 100, m) == 0.0, "no risk distance -> no lots");
      CHECK(NbLotsForRisk(10000, 0.0, 5.7, 0.01, 1.0, 0.01, 0.01, 100, m) == 0.0, "0% risk -> no lots");
      // silver: 3 dp, tick 0.001 worth 5.0, SL 0.092 -> 92 ticks * 5 = 460 per lot -> 0.21
      CHECK(near(NbLotsForRisk(10000, 1.0, 0.092, 0.001, 5.0, 0.01, 0.01, 100, m), 0.21), "silver example");
   }
   end("19");

   begin("20 live box: NbPlanSide equals the trigger's own levels");
   {
      Crafted k = craft(30, 1, 0, 20);
      TrigOut t = runTrig(k, true, PG);
      double e1, sl, t1, t2, rk;
      bool ok = NbPlanSide(k.c, k.atr, k.piv, k.np, 20, 1, PG, e1, sl, t1, t2, rk);
      CHECK(ok && t.nSig == 1 && near(e1, t.sigs[0].entry) && near(sl, t.sigs[0].sl) && near(t1, t.sigs[0].tp1) && near(t2, t.sigs[0].tp2),
            "BUY plan at the trigger bar = the signal's levels");
      CHECK(!NbPlanSide(k.c, k.atr, k.piv, k.np, 20, -1, PG, e1, sl, t1, t2, rk), "no confirmed swing high above -> SELL plan unavailable");
      CHECK(!NbPlanSide(k.c, k.atr, k.piv, k.np, 5, 1, PG, e1, sl, t1, t2, rk), "before the swing low is confirmed -> no BUY plan");
      Crafted m2 = craft(30, -1, 0, 20);
      TrigOut u2 = runTrig(m2, true, PG);
      ok = NbPlanSide(m2.c, m2.atr, m2.piv, m2.np, 20, -1, PG, e1, sl, t1, t2, rk);
      CHECK(ok && u2.nSig == 1 && near(sl, u2.sigs[0].sl) && t2 < t1 && t1 < e1 && e1 < sl, "SELL plan = signal levels, order TP2 < TP1 < Entry < SL");
   }
   end("20");

   begin("xx building blocks: NRTR, EMA, alignment, reason text");
   {
      std::vector<double> c = {10, 11, 12, 13, 14, 15, 13.9, 16, 12};
      std::vector<double> atr(9, 1.0);
      std::vector<int> d, f;
      std::vector<double> st, ex;
      NbCalcNRTR(c, atr, 9, 2.0, d, st, ex, f);
      CHECK(d[0] == 0 && d[1] == 0 && d[2] == 1, "seed: first 2*ATR move from the low sets BULL");
      CHECK(near(st[5], 13.0) && d[6] == 1, "15 - 2 = 13 stop; 13.9 holds");
      CHECK(near(st[6], 13.0), "stop never ratchets down");
      CHECK(d[8] == -1 && f[8] == -1 && near(st[8], 14.0), "close 12 < 14 flips BEAR, stop = 12 + 2");
      std::vector<double> e;
      std::vector<double> cc = {1, 2, 3, 4};
      NbCalcEMA(cc, 4, 3, e);
      CHECK(e[1] == 0.0 && near(e[2], 2.0) && near(e[3], 3.0), "EMA seeded by SMA, 0 = not ready");
      // 15M bar 10:00 closes at 10:15, so the 5M bar 10:05-10:10 must still see the 09:45 bar
      std::vector<datetime> t15 = {35100, 36000};   // 09:45, 10:00
      std::vector<datetime> t5 = {36000, 36300, 36600};   // 10:00, 10:05, 10:10
      std::vector<int> map;
      NbAlign(t15, 2, 900, t5, 3, 300, map);
      CHECK(map[0] == 0 && map[1] == 0 && map[2] == 1, "no 15M look-ahead in the 5M timeline");
      CHECK(NbReasonAt(NB_R_5M_AGAINST | NB_R_STALE, 0) == "DATA STALE / MARKET CLOSED", "staleness is read first");
      CHECK(NbReasonAt(NB_R_5M_AGAINST | NB_R_STALE, 1) == "5M AGAINST 15M", "second reason");
      bool named = true;
      for(int k = 0; k < NB_R_COUNT; k++) named = named && NbReasonName(NbReasonBit(k)) != "";
      CHECK(named, "every reason code has plain-English text");
   }
   end("xx");

   std::printf("\nENGINE TESTS: %d checks passed, %d failed\n", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
