// Engine tests for the v1.05 FIVE-QUESTION PLAN of the twins.
// build/engine_<market>.inc is the ENGINE block of the real .mq5, translated
// syntax-only by mql2cpp.py, so these tests run the exact shipped text.
// Hand-made candles with hand-computed expectations first (F1-F14), then a
// synthetic 16-day market checked against an independent session oracle,
// plan invariants and no-repaint cut points (F15-F18).
#include "../tests/mql_shim.h"
#if NB_TEST_MARKET == 0
#include "engine.inc"
#elif NB_TEST_MARKET == 2
#include "engine_forex.inc"
#else
#include "engine_crypto.inc"
#endif
#include "../tests/synth.h"
#include <cstdio>

static int g_pass = 0, g_fail = 0, g_sec = 0;
#define CHECK(cond, msg)                                                   \
   do {                                                                    \
      if(cond) g_pass++;                                                   \
      else { g_fail++; std::printf("    FAIL %s:%d  %s\n", __FILE__, __LINE__, msg); } \
   } while(0)
static void begin(const char *n) { g_sec = g_fail; std::printf("[ RUN  ] %s\n", n); }
static void end(const char *n) { std::printf("[ %s ] %s\n", g_fail == g_sec ? " OK " : "FAIL", n); }
static bool near(double a, double b, double eps = 1e-9) { return std::fabs(a - b) <= eps; }

static NbParams params(double tick, int digits)
{
   NbParams P;
   P.atrPeriod = 14; P.nrtrMult = 2.0; P.emaPeriod = 200; P.swing = 3; P.slBufAtr = 0.10;
   P.tp1R = 1.0; P.tp2R = 2.0; P.validBars = 6; P.tick = tick; P.digits = digits;
   return P;
}
static NbFqCfg cfg(bool clockOk = false, long offset = 0)
{
   NbFqCfg C;
   C.zoneAtr = 0.25; C.window = 12; C.minRR = 1.5; C.validBars = 12; C.openMax = NB_FQ_OPEN_MAX;
   C.asiaStart = 0; C.asiaEnd = 7; C.lonStart = 7; C.lonEnd = 12; C.clockOk = clockOk; C.offset = offset;
   C.slBufMult = 1.0; C.confirmAtr = 0.0;
   return C;
}

//--- hand-made fixture: every 5M bar has its own 15M bar (map[i] = i) whose
//    structure is chosen per bar; 15M ATR = 1.0 (zone 0.25), 5M ATR = 0.4
//    (SL buffer 0.04). Levels come from hand-placed 15M swings, known from bar 0.
struct Fx
{
   NbSeries s5, s15;
   std::vector<NbPivot> p15, p5;
   std::vector<int> st;
   std::vector<NbFqBar> fq;
   std::vector<NbFqPlan> pl;
   int npl = 0;
   Fx() { NbSeriesResize(s5, 0); NbSeriesResize(s15, 0); s5.sec = 300; s15.sec = 900; }
};
static const long long D0 = 1788220800LL;   // a UTC day boundary
static void bar(Fx &f, double o, double h, double l, double c, int st = NB_ST_BULL)
{
   int n = f.s5.n;
   NbSeriesResize(f.s5, n + 1);
   f.s5.t[(size_t)n] = D0 + 8 * 3600 + (long long)n * 300;
   f.s5.o[(size_t)n] = o; f.s5.h[(size_t)n] = h; f.s5.l[(size_t)n] = l; f.s5.c[(size_t)n] = c;
   f.st.push_back(st);
}
static void swing15(Fx &f, int kind, double price)
{
   NbPivot p;
   p.idx = 0; p.confirmIdx = 0; p.kind = kind; p.price = price; p.label = NB_L_NONE;
   f.p15.push_back(p);
}
static void swing5(Fx &f, int kind, double price, int idx, int confirmIdx)
{
   NbPivot p;
   p.idx = idx; p.confirmIdx = confirmIdx; p.kind = kind; p.price = price; p.label = NB_L_NONE;
   f.p5.push_back(p);
}
static void runFx(Fx &f, const NbFqCfg &C, const NbParams &P, bool lastClosed = true)
{
   int n = f.s5.n;
   NbSeriesResize(f.s15, n);
   f.s15.sec = 900;
   ArrayResize(f.s15.st, n);
   ArrayResize(f.s15.atr, n);
   ArrayResize(f.s5.atr, n);
   ArrayResize(f.s5.map, n);
   for(int i = 0; i < n; i++)
   {
      f.s15.t[(size_t)i] = f.s5.t[(size_t)i];
      f.s15.st[(size_t)i] = f.st[(size_t)i];
      f.s15.atr[(size_t)i] = 1.0;
      f.s5.atr[(size_t)i] = 0.4;
      f.s5.map[(size_t)i] = i;
   }
   NbRunFq(f.s5, f.s15, f.p15, (int)f.p15.size(), f.p5, (int)f.p5.size(), lastClosed, P, C, f.fq, f.pl, f.npl);
}
// the textbook BUY sweep of support 100.00 (see F1 for the arithmetic)
static void buySweep(Fx &f, double confClose = 100.4)
{
   bar(f, 100.8, 101.0, 100.6, 100.9);   // 0 above the level
   bar(f, 100.9, 101.0, 100.5, 100.6);   // 1 still above: the bar before the pierce
   bar(f, 100.6, 100.7, 99.7, 99.9);     // 2 PIERCE: low < 100, previous close > 100 (closes below)
   bar(f, 99.9, 100.2, 99.6, 100.1);     // 3 sweep low 99.60, back above; trigger = this high 100.20
   bar(f, 100.1, 100.15, 99.95, 100.05); // 4 no close above 100.20 yet
   bar(f, 100.05, 100.5, 100.0, confClose); // 5 bullish close above 100.20 = CONFIRMATION
}

// independent session oracle for F16 (a different algorithm on purpose:
// brute force over the bars instead of a running state machine)
static void oracleWindow(const NbSeries &s, int i, long off, int hs, int he, double &hi, double &lo)
{
   hi = 0.0; lo = 0.0;
   long long known = s.t[(size_t)i] + s.sec;
   for(long long d = (s.t[(size_t)i] - off) / 86400; d >= (s.t[0] - off) / 86400 - 1; d--)
   {
      long long ws = d * 86400 + hs * 3600 + off, we = d * 86400 + he * 3600 + off;
      if(we > known) continue;
      int cnt = 0;
      double h = 0, l = 0;
      for(int k = 0; k <= i; k++)
      {
         long long t = s.t[(size_t)k];
         if(t < ws || t >= we) continue;
         if(cnt == 0) { h = s.h[(size_t)k]; l = s.l[(size_t)k]; }
         h = std::max(h, s.h[(size_t)k]); l = std::min(l, s.l[(size_t)k]);
         cnt++;
      }
      if(cnt >= NB_FQ_SESS_MIN_BARS) { hi = h; lo = l; return; }
   }
}
static void oracleDay(const NbSeries &s, int i, double &hi, double &lo)
{
   hi = 0.0; lo = 0.0;
   long long day = s.t[(size_t)i] / 86400;
   for(long long d = day - 1; d >= s.t[0] / 86400; d--)
   {
      int cnt = 0;
      double h = 0, l = 0;
      for(int k = 0; k < i; k++)
      {
         if(s.t[(size_t)k] / 86400 != d) continue;
         if(cnt == 0) { h = s.h[(size_t)k]; l = s.l[(size_t)k]; }
         h = std::max(h, s.h[(size_t)k]); l = std::min(l, s.l[(size_t)k]);
         cnt++;
      }
      if(cnt >= NB_FQ_SESS_MIN_BARS) { hi = h; lo = l; return; }
   }
}

//--- full pipeline on synthetic data, as the terminal runs it
struct Run
{
   NbSeries s15, s5;
   std::vector<NbPivot> p15, p5;
   std::vector<NbSignal> sigs;
   int nSig = 0;
   std::vector<NbFqBar> fq;
   std::vector<NbFqPlan> pl;
   int npl = 0;
};
static void fill(NbSeries &s, const std::vector<SBar> &v, int sec)
{
   NbSeriesResize(s, (int)v.size());
   s.sec = sec;
   for(size_t i = 0; i < v.size(); i++) { s.t[i] = v[i].t; s.o[i] = v[i].o; s.h[i] = v[i].h; s.l[i] = v[i].l; s.c[i] = v[i].c; }
}
#if NB_TEST_MARKET != 0
static NbSessCfg sessCfg()
{
   NbSessCfg S;
   S.clockMode = NB_CLK_AUTO; S.clockOk = true; S.offset = 3 * 3600; S.manualOpenSec = 0;
   S.preHours = 4; S.winMin = 90; S.minRangeBars = 12; S.pauseFlow = true;
   return S;
}
#endif
static const char *mktName()
{
#if NB_TEST_MARKET == 0
   return "METALS";
#else
   return NB_MARKET == NB_MKT_CRYPTO ? "CRYPTO" : "FOREX";
#endif
}
static void runAt(Run &r, const std::vector<SBar> &m5, const std::vector<SBar> &m15, int last5, const NbParams &P,
                  const NbFqCfg &C)
{
   std::vector<SBar> a(m5.begin(), m5.begin() + last5 + 1);
   long long known = m5[(size_t)last5].t + 300;
   std::vector<SBar> b;
   for(const SBar &x : m15) if(x.t + 900 <= known) b.push_back(x);
   fill(r.s5, a, 300);
   fill(r.s15, b, 900);
   NbRun15(r.s15, r.p15, P);
#if NB_TEST_MARKET == 0
   NbRun5(r.s5, r.p5, r.s15, true, P, r.sigs, r.nSig);
#else
   NbRun5(r.s5, r.p5, r.s15, true, P, sessCfg(), r.sigs, r.nSig);
#endif
   NbRunFq(r.s5, r.s15, r.p15, r.s15.np, r.p5, r.s5.np, true, P, C, r.fq, r.pl, r.npl);
}
static bool sameBar(const NbFqBar &a, const NbFqBar &b)
{
   return a.pdh == b.pdh && a.pdl == b.pdl && a.ash == b.ash && a.asl == b.asl && a.loh == b.loh && a.lol == b.lol &&
          a.zone == b.zone && a.sup == b.sup && a.supSrc == b.supSrc && a.sup2 == b.sup2 && a.res == b.res &&
          a.resSrc == b.resSrc && a.res2 == b.res2 && a.trend == b.trend && a.status == b.status && a.why == b.why &&
          a.kind == b.kind && a.level == b.level && a.src == b.src && a.event == b.event && a.ext == b.ext &&
          a.trig == b.trig && a.conf == b.conf && a.entry == b.entry && a.sl == b.sl && a.tp1 == b.tp1 && a.tp2 == b.tp2 &&
          a.tp1Src == b.tp1Src && a.tp2Src == b.tp2Src && a.risk == b.risk && a.rr1 == b.rr1 && a.rr2 == b.rr2 &&
          a.plan == b.plan && a.forming == b.forming;
}
static bool onGrid(double x, double tick) { return std::fabs(x / tick - std::round(x / tick)) < 1e-6; }

int main()
{
   std::printf("market under test: %s\n", mktName());
   NbParams P = params(0.01, 2);
   NbFqCfg C = cfg();

   begin("F1 BUY sweep of support: SETUP until the confirmation close, then READY with exact levels");
   {
      Fx f;
      swing15(f, -1, 100.0); swing15(f, 1, 103.0); swing15(f, 1, 104.5);
      buySweep(f);
      bar(f, 100.4, 100.6, 100.3, 100.5);   // 6 no touch of 100.00
      bar(f, 100.5, 100.55, 99.98, 100.2);  // 7 low 99.98 <= 100.00: the limit FILLS, SL 99.56 untouched
      bar(f, 100.2, 103.1, 100.2, 103.05);  // 8 high 103.10 >= TP1 103.00
      runFx(f, C, P);
      CHECK(f.fq[0].status == NB_FQ_WATCH && f.fq[0].why == NB_FW_MIDDLE, "bar 0: close 100.90 is 0.9 ATR over support = MIDDLE");
      CHECK(f.fq[0].sup == 100.0 && f.fq[0].res == 103.0 && f.fq[0].res2 == 104.5, "bar 0: nearest support / resistance mapped");
      CHECK(f.fq[2].kind == NB_PK_NONE, "bar 2: closed BELOW the level - it is not support now, no BUY candidate");
      CHECK(f.fq[3].status == NB_FQ_SETUP && f.fq[3].why == NB_FW_WAIT_CONF, "bar 3: swept and back above = SETTING UP");
      CHECK(f.fq[3].kind == NB_PK_SWEEP && f.fq[3].event == 2 && near(f.fq[3].ext, 99.6) && near(f.fq[3].trig, 100.2),
            "bar 3: pierce bar 2, sweep low 99.60, trigger = sweep candle high 100.20");
      CHECK(f.fq[4].status == NB_FQ_SETUP && f.fq[4].conf == -1, "bar 4: close 100.05 < 100.20 is no confirmation");
      CHECK(f.fq[4].event == 2 && near(f.fq[4].ext, 99.6) && near(f.fq[4].trig, 100.2),
            "bar 4 re-dips to 99.95 inside the same sweep: the sweep still starts at bar 2, low 99.60 (the stop never moves up)");
      CHECK(f.fq[5].status == NB_FQ_READY && f.fq[5].conf == 5, "bar 5: close 100.40 > 100.20 with a bullish body = READY");
      CHECK(near(f.fq[5].entry, 100.0) && near(f.fq[5].sl, 99.56) && near(f.fq[5].risk, 0.44),
            "entry = the level 100.00, SL = sweep low 99.60 - 0.1 x 5M ATR = 99.56, risk 0.44");
      CHECK(near(f.fq[5].tp1, 103.0) && near(f.fq[5].tp2, 104.5), "TP1 / TP2 = the next two mapped levels");
      CHECK(near(f.fq[5].rr1, 3.0 / 0.44, 1e-9) && near(f.fq[5].rr2, 4.5 / 0.44, 1e-9), "R:R 6.82 / 10.23 from the real distances");
      CHECK(f.fq[5].tp1Src == NB_LV_SWH && f.fq[5].src == NB_LV_SWL, "sources carried: level = swing low, TP1 = swing high");
      CHECK(f.npl == 1 && f.pl[0].idx == 5 && f.pl[0].dir == NB_BUY && f.pl[0].kind == NB_PK_SWEEP, "exactly one BUY plan, at bar 5");
      CHECK(f.fq[6].status == NB_FQ_READY && f.fq[6].why == NB_FW_PENDING && near(f.fq[6].entry, 100.0), "bar 6: limit still pending");
      CHECK(f.fq[7].status == NB_FQ_FILLED && f.pl[0].fillIdx == 7, "bar 7: low touched 100.00 = FILLED");
      CHECK(f.pl[0].status == NB_PO_TP1 && f.pl[0].statusIdx == 8, "bar 8: TP1 reached, outcome recorded");
      CHECK(f.fq[8].plan == 0 && f.fq[8].status != NB_FQ_READY && f.fq[8].status != NB_FQ_FILLED, "bar 8: plan closed, the table shows it as the LAST plan");
      std::printf("    READY at bar 5: BUY LIMIT %.2f SL %.2f TP1 %.2f (%.2fR) TP2 %.2f (%.2fR)\n", f.fq[5].entry, f.fq[5].sl,
                  f.fq[5].tp1, f.fq[5].rr1, f.fq[5].tp2, f.fq[5].rr2);
   }
   end("F1");

   begin("F2 no confirmation close -> never READY");
   {
      Fx f;
      swing15(f, -1, 100.0); swing15(f, 1, 103.0);
      buySweep(f, 100.18);   // bar 5 closes 100.18: above the level, below the trigger 100.20
      runFx(f, C, P);
      CHECK(f.fq[5].status == NB_FQ_SETUP && f.fq[5].why == NB_FW_WAIT_CONF, "still SETTING UP at bar 5");
      CHECK(f.npl == 0, "no plan");
   }
   end("F2");

   begin("F3 REWARD: next resistance too close -> SKIP with the real R");
   {
      Fx f;
      swing15(f, -1, 100.0); swing15(f, 1, 100.6); swing15(f, 1, 103.0);
      buySweep(f);
      runFx(f, C, P);
      CHECK(f.fq[5].status == NB_FQ_SKIP && f.fq[5].why == NB_FW_LOW_RR, "SKIP - not enough room");
      CHECK(near(f.fq[5].tp1, 100.6) && near(f.fq[5].rr1, 0.6 / 0.44, 1e-9) && f.fq[5].rr1 < 1.5, "TP1 100.60 = 1.36R < 1.5R");
      CHECK(f.npl == 0, "no plan");
      NbFqCfg C2 = C;
      C2.minRR = 1.3;
      Fx g;
      swing15(g, -1, 100.0); swing15(g, 1, 100.6); swing15(g, 1, 103.0);
      buySweep(g);
      runFx(g, C2, P);
      CHECK(g.fq[5].status == NB_FQ_READY, "the same candles with minimum 1.3R: READY (the threshold is the only difference)");
   }
   end("F3");

   begin("F4 REWARD unknown: no level mapped beyond -> SKIP, never READY");
   {
      Fx f;
      swing15(f, -1, 100.0);
      buySweep(f);
      runFx(f, C, P);
      CHECK(f.fq[5].status == NB_FQ_SKIP && f.fq[5].why == NB_FW_NO_TARGET && f.fq[5].rr1 == 0.0, "UNKNOWN reward is not a YES");
      CHECK(f.npl == 0, "no plan");
   }
   end("F4");

   begin("F5 TREND: 15M structure mixed / not confirmed -> NO TRADE even on a textbook sweep");
   {
      for(int st : {NB_ST_MIXED, NB_ST_UNKNOWN})
      {
         Fx f;
         swing15(f, -1, 100.0); swing15(f, 1, 103.0);
         buySweep(f);
         for(auto &x : f.st) x = st;
         runFx(f, C, P);
         bool none = true;
         for(int i = 0; i < f.s5.n; i++) none = none && f.fq[(size_t)i].status == NB_FQ_NOTRADE && f.fq[(size_t)i].trend == 0;
         CHECK(none, "every bar NO TRADE");
         CHECK(f.fq[5].why == (st == NB_ST_MIXED ? NB_FW_MIXED : NB_FW_UNCONF), "the reason names the structure state");
         CHECK(f.npl == 0, "no plan");
      }
   }
   end("F5");

   begin("F6 with the trend only: no BUY in a bearish 15M, no SELL on a breakdown in a bullish 15M");
   {
      Fx f;
      swing15(f, -1, 100.0); swing15(f, 1, 103.0); swing15(f, 1, 104.5);
      buySweep(f);
      for(auto &x : f.st) x = NB_ST_BEAR;
      runFx(f, C, P);
      CHECK(f.npl == 0 && f.fq[5].trend == -1 && f.fq[5].status == NB_FQ_WATCH, "bearish 15M: the BUY sweep is ignored (WATCH)");
      Fx g;
      swing15(g, -1, 100.0); swing15(g, -1, 97.0); swing15(g, 1, 103.0);
      bar(g, 100.5, 100.6, 100.2, 100.3);
      bar(g, 100.3, 100.35, 99.6, 99.7);    // bearish close through support 100.00 = a breakdown
      bar(g, 99.7, 99.8, 99.2, 99.3);
      runFx(g, C, P);
      bool noSell = true;
      for(int k = 0; k < g.npl; k++) noSell = noSell && g.pl[(size_t)k].dir != NB_SELL;
      CHECK(g.npl == 0 && noSell, "bullish 15M: a breakdown never becomes a SELL plan");
      CHECK(g.fq[2].kind == NB_PK_NONE && g.fq[2].status == NB_FQ_WATCH, "it is only watched");
   }
   end("F6");

   begin("F7 BUY breakout: 5M body close above resistance -> READY limit at the level (the retest)");
   {
      Fx f;
      swing15(f, -1, 100.0); swing15(f, 1, 103.0); swing15(f, 1, 104.5);
      swing5(f, -1, 102.4, 0, 1);            // a confirmed 5M swing low behind the level (for the SL)
      bar(f, 102.5, 102.8, 102.4, 102.7);
      bar(f, 102.7, 102.9, 102.6, 102.8);
      bar(f, 102.8, 103.4, 102.7, 103.3);   // 2 bullish close above 103.00 from below
      runFx(f, C, P);
      CHECK(f.fq[1].status == NB_FQ_WATCH && f.fq[1].why == NB_FW_AT_BREAK, "bar 1: close 102.80 is 0.2 under resistance 103.00 = AT THE BREAKOUT LINE");
      CHECK(f.fq[0].status == NB_FQ_WATCH && f.fq[0].why == NB_FW_AT_BREAK, "bar 0: its high 102.80 reached the resistance zone (>= 102.75)");
      CHECK(f.fq[2].status == NB_FQ_READY && f.fq[2].kind == NB_PK_BREAK && f.fq[2].event == 2 && f.fq[2].conf == 2, "READY on the breakout close");
      CHECK(near(f.fq[2].entry, 103.0) && near(f.fq[2].sl, 102.36) && near(f.fq[2].risk, 0.64), "entry 103.00, SL 102.40 - 0.04 = 102.36");
      CHECK(near(f.fq[2].tp1, 104.5) && f.fq[2].tp2 == 0.0 && near(f.fq[2].rr1, 1.5 / 0.64, 1e-9), "TP1 104.50 = 2.34R, no TP2 mapped");
      CHECK(f.npl == 1 && f.pl[0].kind == NB_PK_BREAK && f.pl[0].dir == NB_BUY, "one BREAKOUT BUY plan");
   }
   end("F7");

   begin("F8 breakout without a structural stop -> SKIP; a close back below kills the breakout");
   {
      Fx f;
      swing15(f, -1, 100.0); swing15(f, 1, 103.0); swing15(f, 1, 104.5);
      bar(f, 102.5, 102.8, 102.4, 102.7);
      bar(f, 102.7, 102.9, 102.6, 102.8);
      bar(f, 102.8, 103.4, 102.7, 103.3);
      bar(f, 103.3, 103.35, 102.8, 102.9);  // 3 closes back below 103.00: failed breakout
      runFx(f, C, P);
      CHECK(f.fq[2].status == NB_FQ_SKIP && f.fq[2].why == NB_FW_NO_STOP, "no confirmed 5M swing below the level = no stop = SKIP");
      CHECK(f.fq[3].kind == NB_PK_NONE && f.fq[3].status == NB_FQ_WATCH, "after the close back below: no candidate");
      CHECK(f.npl == 0, "no plan");
   }
   end("F8");

   begin("F9 SELL sweep of resistance (mirror) -> READY SELL LIMIT with exact levels");
   {
      Fx f;
      swing15(f, 1, 103.0); swing15(f, -1, 100.0); swing15(f, -1, 99.0);
      bar(f, 102.2, 102.4, 102.0, 102.1, NB_ST_BEAR);
      bar(f, 102.1, 102.5, 102.0, 102.4, NB_ST_BEAR);
      bar(f, 102.4, 103.3, 102.3, 103.1, NB_ST_BEAR);   // 2 pierce above 103 from below
      bar(f, 103.1, 103.4, 102.8, 102.9, NB_ST_BEAR);   // 3 sweep high 103.40, back below; trigger 102.80
      bar(f, 102.9, 103.0, 102.7, 102.75, NB_ST_BEAR);  // 4 bearish close below 102.80 = confirmation
      runFx(f, C, P);
      CHECK(f.fq[3].status == NB_FQ_SETUP && near(f.fq[3].trig, 102.8) && near(f.fq[3].ext, 103.4), "bar 3: SETTING UP, trigger 102.80");
      CHECK(f.fq[4].status == NB_FQ_READY && f.npl == 1 && f.pl[0].dir == NB_SELL, "bar 4: READY SELL");
      CHECK(near(f.fq[4].entry, 103.0) && near(f.fq[4].sl, 103.44) && near(f.fq[4].risk, 0.44), "SELL LIMIT 103.00, SL 103.40 + 0.04 = 103.44");
      CHECK(near(f.fq[4].tp1, 100.0) && near(f.fq[4].tp2, 99.0), "TP1 / TP2 = the next supports below");
      CHECK(f.fq[4].sl > f.fq[4].entry && f.fq[4].entry > f.fq[4].tp1 && f.fq[4].tp1 > f.fq[4].tp2, "TP2 < TP1 < ENTRY < SL");
   }
   end("F9");

   begin("F10 plan outcome rules (NbFqTrack): fill, same candle, missed, expired, timeout");
   {
      NbFqBar b;
      NbFqReset(b);
      b.kind = NB_PK_SWEEP; b.entry = 100.0; b.sl = 99.5; b.tp1 = 101.0; b.tp2 = 102.0; b.risk = 0.5; b.rr1 = 2; b.rr2 = 4;
      NbFqPlan g;
      NbFqNewPlan(g, 10, NB_BUY, b);
      NbFqTrack(g, 11, 100.5, 99.4, 12, 144);
      CHECK(g.status == NB_PO_SL && g.fillIdx == 11 && g.statusIdx == 11, "fill and SL on the same candle = SL (conservative)");
      NbFqNewPlan(g, 10, NB_BUY, b);
      NbFqTrack(g, 11, 101.2, 99.9, 12, 144);
      CHECK(g.status == NB_PO_FILLED && g.fillIdx == 11, "fill and TP1 on the same candle: filled, TP1 NOT counted on the fill candle");
      NbFqTrack(g, 12, 101.1, 100.2, 12, 144);
      CHECK(g.status == NB_PO_TP1 && g.statusIdx == 12, "TP1 on the next candle counts");
      NbFqNewPlan(g, 10, NB_BUY, b);
      NbFqTrack(g, 11, 100.4, 100.01, 12, 144);
      NbFqTrack(g, 12, 101.0, 100.3, 12, 144);
      CHECK(g.status == NB_PO_MISSED && g.fillIdx == -1, "TP1 reached with the limit untouched = MISSED (no chase)");
      NbFqNewPlan(g, 10, NB_BUY, b);
      for(int k = 11; k < 22; k++) NbFqTrack(g, k, 100.5, 100.2, 12, 144);
      CHECK(g.status == NB_PO_PENDING, "11 bars untouched: still pending");
      NbFqTrack(g, 22, 100.5, 100.2, 12, 144);
      CHECK(g.status == NB_PO_EXPIRED && g.statusIdx == 22, "the 12th bar untouched = EXPIRED");
      NbFqNewPlan(g, 10, NB_BUY, b);
      NbFqTrack(g, 11, 100.3, 99.9, 12, 144);
      NbFqTrack(g, 12, 101.5, 99.3, 12, 144);
      CHECK(g.status == NB_PO_SL, "filled, then one candle touches SL and TP1 = SL (same-candle rule)");
      NbFqNewPlan(g, 10, NB_BUY, b);
      NbFqTrack(g, 11, 100.3, 99.9, 12, 144);
      for(int k = 12; k < 11 + 144; k++) NbFqTrack(g, k, 100.6, 99.8, 12, 144);
      CHECK(g.status == NB_PO_FILLED, "143 bars filled without TP1 / SL: still open");
      NbFqTrack(g, 155, 100.6, 99.8, 12, 144);
      CHECK(g.status == NB_PO_TIMEOUT && g.statusIdx == 155, "144 bars: TIMED OUT");
      NbFqBar s;
      NbFqReset(s);
      s.kind = NB_PK_SWEEP; s.entry = 103.0; s.sl = 103.5; s.tp1 = 102.0; s.risk = 0.5;
      NbFqNewPlan(g, 5, NB_SELL, s);
      NbFqTrack(g, 6, 102.9, 102.5, 12, 144);
      CHECK(g.status == NB_PO_PENDING, "SELL: high 102.90 below the limit 103.00 = not filled");
      NbFqTrack(g, 7, 103.0, 102.6, 12, 144);
      NbFqTrack(g, 8, 102.8, 101.9, 12, 144);
      CHECK(g.fillIdx == 7 && g.status == NB_PO_TP1, "SELL: filled at 103.00, TP1 102.00 next candle");
   }
   end("F10");

   begin("F11 a pending plan is CANCELLED when the 15M structure stops agreeing");
   {
      Fx f;
      swing15(f, -1, 100.0); swing15(f, 1, 103.0);
      buySweep(f);
      bar(f, 100.4, 100.6, 100.3, 100.5, NB_ST_MIXED);
      runFx(f, C, P);
      CHECK(f.npl == 1 && f.pl[0].status == NB_PO_CANCELLED && f.pl[0].statusIdx == 6, "cancelled at bar 6");
      CHECK(f.fq[6].status == NB_FQ_NOTRADE && f.fq[6].why == NB_FW_MIXED && f.fq[6].plan == 0, "bar 6: NO TRADE, last plan shown");
   }
   end("F11");

   begin("F12 the forming candle is never evaluated");
   {
      Fx f;
      swing15(f, -1, 100.0); swing15(f, 1, 103.0);
      buySweep(f);
      runFx(f, C, P, false);
      CHECK(f.fq[5].forming && f.fq[5].status == NB_FQ_SETUP && f.fq[5].conf == -1, "bar 5 still forming: carries bar 4 (SETTING UP)");
      CHECK(f.npl == 0, "no plan from an unfinished candle");
      runFx(f, C, P, true);
      CHECK(!f.fq[5].forming && f.fq[5].status == NB_FQ_READY, "the same candle closed: READY");
   }
   end("F12");

   begin("F13 levels: merge within the zone (stronger source wins), last 4 swings each side, unconfirmed swings excluded");
   {
      NbFqBar b;
      NbFqReset(b);
      b.pdh = 103.0; b.pdl = 0.0; b.ash = 102.9; b.asl = 0.0; b.loh = 0.0; b.lol = 0.0;
      std::vector<NbPivot> piv;
      auto add = [&](int kind, double price, int ci) { NbPivot p; p.idx = ci - 3; p.confirmIdx = ci; p.kind = kind; p.price = price; p.label = 0; piv.push_back(p); };
      add(1, 103.1, 5);    // merges into the 102.9 group (0.2 from its first member)
      add(1, 103.3, 6);    // 0.4 from 102.9: a separate level
      for(int k = 0; k < 6; k++) add(-1, 90.0 + k, 7 + k);   // six swing lows: only the last four count
      add(1, 110.0, 50);   // confirmed later
      std::vector<NbLv> lv;
      int n = NbFqLevels(b, piv, 8, 0.25, lv);   // swings 0..7 are confirmed by this bar, the 110.00 one is not
      bool has110 = false;
      for(auto &x : lv) has110 = has110 || x.price == 110.0;
      CHECK(!has110, "a swing confirmed after this bar is not a level");
      CHECK(n == 6, "4 swing lows + the merged 102.9/103.0/103.1 + 103.3");
      CHECK(near(lv[0].price, 92.0) && near(lv[3].price, 95.0), "only the last four swing lows (92..95)");
      CHECK(near(lv[4].price, 103.0) && lv[4].src == (NB_LV_ASH | NB_LV_PDH | NB_LV_SWH), "merged level priced at PREV DAY HIGH, sources OR'ed");
      CHECK(near(lv[5].price, 103.3), "103.30 stays separate (0.4 from the group's first member)");
      CHECK(NbLvBeyond(lv, n, 95.0, 1) == 4 && NbLvBeyond(lv, n, 103.3, 1) == -1 && NbLvBeyond(lv, n, 92.0, -1) == -1, "beyond search both ways");
      NbFqNearest(lv, n, 100.0, b);
      CHECK(near(b.sup, 95.0) && near(b.sup2, 94.0) && near(b.res, 103.0) && near(b.res2, 103.3), "nearest two each side of 100.00");
      CHECK(NbLvSrcText(NB_LV_PDH | NB_LV_SWH) == "PREV DAY HIGH + 15M SWING HIGH" && NbLvSrcShort(NB_LV_ASL) == "ASIA L", "level names in words");
   }
   end("F13");

   begin("F14 session levels: PDH/PDL of the previous complete broker day; Asia / London only after the window ENDS");
   {
      // two server days of 5M bars, broker = UTC+3
      NbSeries s;
      NbSeriesResize(s, 0);
      s.sec = 300;
      long long day0 = D0 + 86400;   // server midnight
      std::vector<double> hs;
      for(int k = 0; k < 2 * 288; k++)
      {
         int n = s.n;
         NbSeriesResize(s, n + 1);
         s.t[(size_t)n] = day0 + (long long)k * 300;
         double base = 100.0 + (k % 288) * 0.01;
         s.o[(size_t)n] = base; s.c[(size_t)n] = base; s.h[(size_t)n] = base + 0.5; s.l[(size_t)n] = base - 0.5;
      }
      std::vector<NbFqBar> fq((size_t)s.n);
      NbFqCfg Cs = cfg(true, 3 * 3600);
      NbFqSessions(s.t, s.h, s.l, s.n, s.sec, Cs, fq);
      CHECK(fq[0].pdh == 0.0 && fq[287].pdh == 0.0, "day 1: no previous day in the data = unknown, not zero-risk");
      CHECK(near(fq[288].pdh, 100.0 + 287 * 0.01 + 0.5) && near(fq[288].pdl, 99.5), "day 2 first bar: PDH / PDL of day 1");
      // Asia 00:00-07:00 UTC = 03:00-10:00 server: bars 36 .. 119 of the day
      CHECK(fq[118].ash == 0.0, "09:50 server: Asia still running -> not known");
      CHECK(near(fq[119].ash, 100.0 + 119 * 0.01 + 0.5) && near(fq[119].asl, 100.0 + 36 * 0.01 - 0.5), "09:55 server closes 10:00 = Asia ended: known");
      // London 07:00-12:00 UTC = 10:00-15:00 server: bars 120 .. 179
      CHECK(fq[178].loh == 0.0 && near(fq[179].loh, 100.0 + 179 * 0.01 + 0.5) && near(fq[179].lol, 100.0 + 120 * 0.01 - 0.5), "London known only at its end");
      CHECK(near(fq[288 + 50].ash, fq[119].ash), "next day before its Asia ends: yesterday's Asia range is the latest known");
      NbFqCfg Cn = cfg(false, 0);
      NbFqSessions(s.t, s.h, s.l, s.n, s.sec, Cn, fq);
      bool none = true;
      for(auto &x : fq) none = none && x.ash == 0.0 && x.asl == 0.0 && x.loh == 0.0 && x.lol == 0.0;
      CHECK(none && fq[300].pdh > 0.0, "no session clock: Asia / London unknown (never guessed), day levels still known");
      // a partial day (< 12 bars) is never the previous day
      NbSeries p;
      NbSeriesResize(p, 0);
      p.sec = 300;
      for(int k = 0; k < 288 + 5 + 20; k++)
      {
         int n = p.n;
         NbSeriesResize(p, n + 1);
         long long t = (k < 288) ? day0 + (long long)k * 300 : (k < 293 ? day0 + 86400 + (long long)(k - 288) * 300 : day0 + 2 * 86400 + (long long)(k - 293) * 300);
         p.t[(size_t)n] = t;
         double v = (k < 288) ? 100.0 : (k < 293 ? 200.0 : 150.0);
         p.o[(size_t)n] = v; p.c[(size_t)n] = v; p.h[(size_t)n] = v + 1; p.l[(size_t)n] = v - 1;
      }
      std::vector<NbFqBar> fq2((size_t)p.n);
      NbFqSessions(p.t, p.h, p.l, p.n, p.sec, Cn, fq2);
      CHECK(near(fq2[293].pdh, 101.0), "a 5-bar day is skipped: the previous COMPLETE day stays the PDH");
   }
   end("F14");

   begin("F19 v1.06: silver options (wider stop, stronger confirmation), NET R, witness clock, short level tags");
   {
      NbFqCfg Cs = C;
      Cs.slBufMult = 2.0;
      Fx f;
      swing15(f, -1, 100.0); swing15(f, 1, 103.0);
      buySweep(f);
      runFx(f, Cs, P);
      CHECK(f.fq[5].status == NB_FQ_READY && near(f.fq[5].sl, 99.52), "stop buffer x2: SL 99.60 - 2 x 0.04 = 99.52");
      Cs = C;
      Cs.confirmAtr = 0.25;   // close must pass 100.20 + 0.25 x 0.4 = 100.30; bar 5 closes 100.40
      Fx g;
      swing15(g, -1, 100.0); swing15(g, 1, 103.0);
      buySweep(g);
      runFx(g, Cs, P);
      CHECK(g.fq[5].status == NB_FQ_READY, "confirmation +0.25 ATR: 100.40 > 100.30 still confirms");
      Cs.confirmAtr = 0.6;    // needs 100.44
      Fx h;
      swing15(h, -1, 100.0); swing15(h, 1, 103.0);
      buySweep(h);
      runFx(h, Cs, P);
      CHECK(h.fq[5].status == NB_FQ_SETUP && h.npl == 0, "confirmation +0.6 ATR: 100.40 < 100.44 is not enough - still SETTING UP");
      Cs.confirmAtr = 1.0;    // a breakout close must clear 103.00 + 0.40
      Fx k;
      swing15(k, -1, 100.0); swing15(k, 1, 103.0); swing15(k, 1, 104.5);
      swing5(k, -1, 102.4, 0, 1);
      bar(k, 102.5, 102.8, 102.4, 102.7);
      bar(k, 102.7, 102.9, 102.6, 102.8);
      bar(k, 102.8, 103.4, 102.7, 103.3);
      runFx(k, Cs, P);
      CHECK(k.fq[2].kind == NB_PK_NONE && k.npl == 0, "breakout close 103.30 < 103.40: not a breakout for the stricter asset");
      std::vector<NbFqPlan> pl(3);
      pl[0].status = NB_PO_TP1; pl[0].rr1 = 2.5;
      pl[1].status = NB_PO_SL; pl[1].rr1 = 3.0;
      pl[2].status = NB_PO_EXPIRED; pl[2].rr1 = 4.0;
      CHECK(near(NbFqNetR(pl, 3), 1.5), "NET R: +2.5 (TP1) - 1 (SL) + 0 (not filled) = +1.5");
      long off = 0;
      CHECK(NbFqWitnessClock(1000000 + 3 * 3600 + 100, 1000000, off) && off == 3 * 3600, "witness clock: +3h with 100 s drift");
      CHECK(!NbFqWitnessClock(1000000 + 3 * 3600 + 600, 1000000, off) && off == 0, "witness clock: 10 min off a half hour = unknown");
      CHECK(!NbFqWitnessClock(0, 1000000, off), "witness clock: a missing witness = unknown");
      CHECK(NbLvTag(NB_LV_PDH | NB_LV_ASH | NB_LV_SWH | NB_LV_LOL) == "PDH+LDN L+2" && NbLvTag(NB_LV_SWL) == "SWING L", "short tags: two codes and a count");
      CHECK(NbLvName(NB_LV_PDH | NB_LV_LOH | NB_LV_ASH | NB_LV_SWH) == NbLvSrcShort(NB_LV_PDH | NB_LV_LOH | NB_LV_ASH | NB_LV_SWH) &&
            NbLvName(NB_LV_PDH) == "PREV DAY HIGH", "chart names: long when short enough, codes otherwise");
   }
   end("F19");

   // ---- synthetic market -------------------------------------------------
#if NB_TEST_MARKET == 0
   double tick = 0.01;
   int digits = 2;
   double price = 2400.0;
   double vol = 0.8;
#else
   double tick = (NB_MARKET == NB_MKT_CRYPTO) ? 0.01 : 0.00001;
   int digits = (NB_MARKET == NB_MKT_CRYPTO) ? 2 : 5;
   double price = (NB_MARKET == NB_MKT_CRYPTO) ? 60000.0 : 1.08;
   double vol = (NB_MARKET == NB_MKT_CRYPTO) ? 40.0 : 0.0004;
#endif
   NbParams PS = params(tick, digits);
   NbFqCfg CS = cfg(true, 3 * 3600);
   std::vector<SBar> m5 = gen5m(7, 16 * 288, D0, price, tick, vol);
   std::vector<SBar> m15 = agg(m5, 900);
   Run full;
   runAt(full, m5, m15, (int)m5.size() - 1, PS, CS);

   begin("F15 synthetic 16 days: every plan obeys the rules");
   {
      int buy = 0, sell = 0, sweep = 0, brk = 0, bad = 0, badGrid = 0, overlap = 0, badTrend = 0, badWin = 0;
      for(int k = 0; k < full.npl; k++)
      {
         const NbFqPlan &g = full.pl[(size_t)k];
         (g.dir > 0 ? buy : sell)++;
         (g.kind == NB_PK_SWEEP ? sweep : brk)++;
         bool ordered = (g.dir > 0) ? (g.sl < g.entry && g.entry < g.tp1 && (g.tp2 == 0.0 || g.tp2 > g.tp1))
                                    : (g.sl > g.entry && g.entry > g.tp1 && (g.tp2 == 0.0 || g.tp2 < g.tp1));
         if(!ordered || g.rr1 < CS.minRR || g.risk <= 0.0) bad++;
         if(!onGrid(g.entry, tick) || !onGrid(g.sl, tick)) badGrid++;
         if(full.fq[(size_t)g.idx].trend != g.dir) badTrend++;
         if(g.event <= g.idx - CS.window || g.event > g.idx || g.conf < g.event || g.conf > g.idx) badWin++;
         if(k > 0 && g.idx < full.pl[(size_t)k - 1].statusIdx) overlap++;
         double cl = full.s5.c[(size_t)g.idx];
         if((g.dir > 0 && !(g.entry < cl && cl < g.tp1)) || (g.dir < 0 && !(g.entry > cl && cl > g.tp1))) bad++;
      }
      int tp, sl, un, op, to;
      NbFqTally(full.pl, full.npl, tp, sl, un, op, to);
      std::printf("    %d plans: BUY %d / SELL %d, SWEEP %d / BREAK %d  -> TP1 %d  SL %d  not filled %d  open %d  timed out %d\n",
                  full.npl, buy, sell, sweep, brk, tp, sl, un, op, to);
      CHECK(buy >= 3 && sell >= 3 && sweep >= 1 && brk >= 1, "the fixture exercises both sides and both kinds (else this test proves nothing)");
      CHECK(bad == 0, "BUY: SL < ENTRY < close < TP1 < TP2, SELL mirrored, TP1 >= 1.5R");
      CHECK(badGrid == 0, "entry and SL on the symbol's tick grid");
      CHECK(badTrend == 0, "every plan points the way the 15M structure pointed at its bar");
      CHECK(badWin == 0, "event and confirmation inside the setup window, before the plan");
      CHECK(overlap == 0, "one plan at a time: a new plan only after the previous one finished");
      CHECK(tp + sl + un + op + to == full.npl, "every plan has exactly one outcome class");
      int ready = 0;
      for(int i = 0; i < full.s5.n; i++)
         if(full.fq[(size_t)i].status == NB_FQ_READY && full.fq[(size_t)i].why == NB_FW_PENDING) ready++;
      CHECK(ready >= full.npl, "READY bars cover every plan");
   }
   end("F15");

   begin("F16 session levels match an independent brute-force oracle on every bar");
   {
      int badDay = 0, badAsia = 0, badLon = 0;
      for(int i = 0; i < full.s5.n; i++)
      {
         double h, l;
         oracleDay(full.s5, i, h, l);
         if(full.fq[(size_t)i].pdh != h || full.fq[(size_t)i].pdl != l) badDay++;
         oracleWindow(full.s5, i, 3 * 3600, 0, 7, h, l);
         if(full.fq[(size_t)i].ash != h || full.fq[(size_t)i].asl != l) badAsia++;
         oracleWindow(full.s5, i, 3 * 3600, 7, 12, h, l);
         if(full.fq[(size_t)i].loh != h || full.fq[(size_t)i].lol != l) badLon++;
      }
      char m[128];
      std::snprintf(m, sizeof m, "PDH/PDL on %d bars", full.s5.n);
      CHECK(badDay == 0, m);
      CHECK(badAsia == 0, "Asia high / low: only ENDED windows, never the running one");
      CHECK(badLon == 0, "London high / low: only ENDED windows");
   }
   end("F16");

   begin("F17 the drawn levels are the levels the engine used (NbFqLevelsAt == incremental run)");
   {
      int bad = 0, checked = 0;
      for(int i = 0; i < full.s5.n; i += 7)
      {
         if(full.fq[(size_t)i].zone <= 0.0) continue;
         std::vector<NbLv> lv;
         int n = NbFqLevelsAt(full.s5, full.s15, full.p15, full.s15.np, CS, full.fq, i, lv);
         NbFqBar b = full.fq[(size_t)i];
         NbFqNearest(lv, n, full.s5.c[(size_t)i], b);
         if(b.sup != full.fq[(size_t)i].sup || b.res != full.fq[(size_t)i].res || b.supSrc != full.fq[(size_t)i].supSrc ||
            b.resSrc != full.fq[(size_t)i].resSrc || b.sup2 != full.fq[(size_t)i].sup2 || b.res2 != full.fq[(size_t)i].res2)
            bad++;
         checked++;
      }
      CHECK(checked > 500 && bad == 0, "identical support / resistance on every checked bar");
   }
   end("F17");

   begin("F18 no repaint: cut points and a different future change no past answer");
   {
      int cuts = 0, badCut = 0, badFuture = 0, badPlan = 0;
      std::vector<SBar> alt = m5;
      for(int c = 11 * 288; c < (int)m5.size() - 1; c += 47)
      {
         Run r;
         runAt(r, m5, m15, c, PS, CS);
         if(!sameBar(r.fq[(size_t)c], full.fq[(size_t)c])) badCut++;
         for(int k = 0; k < r.npl; k++)
         {
            const NbFqPlan &a = r.pl[(size_t)k];
            const NbFqPlan &b = full.pl[(size_t)k];
            if(k >= full.npl || a.idx != b.idx || a.entry != b.entry || a.sl != b.sl || a.tp1 != b.tp1 || a.tp2 != b.tp2 || a.dir != b.dir)
               badPlan++;
         }
         // a different future after the cut
         std::vector<SBar> fut = gen5m(1000 + (uint64_t)c, (int)m5.size() - c - 1, m5[(size_t)c + 1].t, m5[(size_t)c].c, tick, vol * 3);
         for(size_t k = 0; k < fut.size(); k++) alt[(size_t)c + 1 + k] = fut[k];
         for(int k = 0; k <= c; k++) alt[(size_t)k] = m5[(size_t)k];
         std::vector<SBar> alt15 = agg(alt, 900);
         Run f2;
         runAt(f2, alt, alt15, (int)alt.size() - 1, PS, CS);
         for(int i = 0; i <= c; i += 3)
            if(!sameBar(f2.fq[(size_t)i], full.fq[(size_t)i]))
            {
               // plan outcomes may legitimately differ only through bars after c; the per-bar answers may not
               badFuture++;
               break;
            }
         cuts++;
      }
      char m[96];
      std::snprintf(m, sizeof m, "%d cut points: the last bar's answer equals the full run's answer for that bar", cuts);
      CHECK(cuts >= 30, "at least 30 cut points");
      CHECK(badCut == 0, m);
      CHECK(badPlan == 0, "every plan known at a cut has the same bar, side, entry, SL, TP1, TP2 in the full run");
      CHECK(badFuture == 0, "a different future leaves every earlier bar's answer bit-identical");
   }
   end("F18");

   std::printf("\nFIVE-QUESTION ENGINE TESTS (%s): %d checks passed, %d failed\n", mktName(), g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
