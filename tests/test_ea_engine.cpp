// EA engine tests. build/ea_engine.inc is the ENGINE block of the real
// NRTR_QML_MetalScalper.mq5, translated syntax-only by mql2cpp.py.
#include "../tests/mql_shim.h"
#include "ea_engine.inc"
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

static NqParams params(double tick, int digits)
{
   NqParams P;
   P.atrPeriod = 14;
   P.nrtrMult = 2.0;
   P.emaSlow = 200;
   P.emaFast = 20;
   P.swing = 3;
   P.scalpSlAtr = 1.5;
   P.scalpTpAtr = 1.0;
   P.scalpValidBars = 2;
   P.scalpTimeBars = 45;
   P.qmlSlBufAtr = 0.2;
   P.qmlWaitBars = 36;
   P.planValidBars = 72;
   P.pbRetrace = 0.5;
   P.pbMinImpulseAtr = 2.0;
   P.pbSlBufAtr = 0.2;
   P.planTp1R = 1.0;
   P.planTp2R = 2.0;
   P.fcMinScore = 2;
   P.tick = tick;
   P.digits = digits;
   return P;
}

static const long long T0 = 1788220800LL;

static void fill(NqSeries &s, const std::vector<SBar> &v, int sec)
{
   NqSeriesResize(s, (int)v.size());
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

struct Market
{
   std::vector<SBar> m1, m5, m15;
};
static Market makeMarket(uint64_t seed, double price, double tick, double vol, int days)
{
   Market m;
   m.m1 = gen1m(seed, days * 1440, T0, price, tick, vol);
   m.m5 = agg(m.m1, 300);
   m.m15 = agg(m.m1, 900);
   return m;
}
struct Run
{
   NqSeries s15, s5, s1;
   std::vector<NqPivot> piv5;
   std::vector<NqSignal> sigs;
   std::vector<NqPlan> plans;
   int nSig = 0, nPlans = 0;
};
static void runAll(Run &r, const Market &m, const NqParams &P, size_t cut1)
{
   std::vector<SBar> a(m.m1.begin(), m.m1.begin() + (long)cut1);
   std::vector<SBar> b = agg(a, 300);
   std::vector<SBar> c = agg(a, 900);
   // only CLOSED 5M/15M bars are known at the close of the last 1M bar
   long long lastClose = a.back().t + 60;
   while(!b.empty() && b.back().t + 300 > lastClose) b.pop_back();
   while(!c.empty() && c.back().t + 900 > lastClose) c.pop_back();
   fill(r.s1, a, 60);
   fill(r.s5, b, 300);
   fill(r.s15, c, 900);
   NqRunContext(r.s15, P);
   NqRunRegime(r.s5, r.piv5, r.s15, P);
   NqRunTrigger(r.s1, r.s5, true, P, r.sigs, r.nSig);
   NqFindPlans(r.s5, r.piv5, r.s5.np, P, r.plans, r.nPlans);
}

// crafted M5 path: a bearish Quasimodo. Left shoulder A = bar 10 (100.0),
// neck B = bar 16 (95.0), head C = bar 22 (102.0), neck break at bar 28.
static std::vector<SBar> craftQml(bool bearish, double base)
{
   std::vector<double> c;
   auto seg = [&](double from, double to, int bars) {
      for(int i = 1; i <= bars; i++) c.push_back(from + (to - from) * i / bars);
   };
   c.push_back(90.0);
   seg(90.0, 100.0, 10);   // bars 1..10 rise to A=100 at bar 10
   seg(100.0, 95.0, 6);    // bars 11..16 fall to B=95 at bar 16
   seg(95.0, 102.0, 6);    // bars 17..22 rise to C=102 at bar 22
   seg(102.0, 96.0, 5);    // bars 23..27 fall to 96
   c.push_back(94.5);      // bar 28 closes below the neck
   seg(94.5, 97.0, 2);     // 29,30 bounce
   c.push_back(100.3);     // bar 31: high touches the shoulder -> fill
   seg(100.3, 98.0, 3);    // 32..34
   c.push_back(95.0);      // bar 35: TP1 region
   seg(95.0, 96.0, 3);
   std::vector<SBar> v;
   for(size_t i = 0; i < c.size(); i++)
   {
      double x = bearish ? c[i] : (200.0 - c[i]);
      x += base;
      double o = (i == 0) ? x : v.back().c;
      v.push_back({T0 + (long long)i * 300, o, std::max(o, x) + 0.05, std::min(o, x) - 0.05, x});
   }
   return v;
}

int main()
{
   NqParams P = params(0.01, 2);

   begin("E01 M5 regime decision: NRTR + confirmed structure, else CHOP with reason");
   {
      int r = 0;
      CHECK(NqRegimeDecision(1, NQ_ST_BULL, r) == NQ_REG_BULL && r == 0, "bull");
      CHECK(NqRegimeDecision(-1, NQ_ST_BEAR, r) == NQ_REG_BEAR && r == 0, "bear");
      CHECK(NqRegimeDecision(1, NQ_ST_BEAR, r) == NQ_REG_CHOP && (r & NQ_R_STRUCT_CONFLICT), "conflict");
      CHECK(NqRegimeDecision(1, NQ_ST_MIXED, r) == NQ_REG_CHOP && (r & NQ_R_STRUCT_MIXED), "mixed");
      CHECK(NqRegimeDecision(1, NQ_ST_UNKNOWN, r) == NQ_REG_CHOP && (r & NQ_R_STRUCT_UNCONF), "unconfirmed");
      CHECK(NqRegimeDecision(0, NQ_ST_BULL, r) == NQ_REG_CHOP && (r & NQ_R_NRTR5_NOT_READY), "nrtr not ready");
      CHECK(NqContextOf(1, 101, 100) == 1 && NqContextOf(-1, 99, 100) == -1 && NqContextOf(1, 99, 100) == 0 &&
            NqContextOf(0, 101, 100) == 0 && NqContextOf(1, 101, 0) == 0, "context");
   }
   end("E01");

   begin("E02 forecast: votes, threshold, hit judged only at the next close");
   {
      NqSeries s;
      std::vector<SBar> v;
      double c = 100.0;
      for(int i = 0; i < 40; i++)
      {
         double nc = c + ((i % 7 == 3) ? -0.3 : 0.2);
         v.push_back({T0 + i * 60, c, std::max(c, nc) + 0.05, std::min(c, nc) - 0.05, nc});
         c = nc;
      }
      fill(s, v, 60);
      NqCalcATR(s.h, s.l, s.c, s.n, P.atrPeriod, s.atr);
      NqCalcEMA(s.c, s.n, P.emaFast, s.emaF);
      NqCalcNRTR(s.c, s.atr, s.n, P.nrtrMult, s.dir, s.stop, s.ext, s.flip);
      ArrayResize(s.hi, s.n);
      for(int i = 0; i < s.n; i++) s.hi[i] = 1;
      NqForecastSeries(s, 2);
      bool okScore = true, okHit = true, lastUnresolved = (s.fcHit[s.n - 1] == 0);
      for(int i = 0; i < s.n; i++)
      {
         int exp = 2 * s.hi[i] + s.dir[i] + NqSign(s.c[i], s.o[i]) + (s.emaF[i] > 0 ? NqSign(s.c[i], s.emaF[i]) : 0);
         if(s.fcScore[i] != exp) okScore = false;
         int want = (exp >= 2) ? 1 : ((exp <= -2) ? -1 : 0);
         if(want == 0) want = (s.dir[i] != 0) ? s.dir[i] : NqSign(s.c[i], s.o[i]);
         if(want == 0 && i > 0) want = s.fc[i - 1];
         if(s.fc[i] != want) okScore = false;
         if(i + 1 < s.n && s.fc[i] != 0)
         {
            int want = (NqSign(s.c[i + 1], s.c[i]) == s.fc[i]) ? 1 : -1;
            if(s.fcHit[i] != want) okHit = false;
         }
         if(i + 1 < s.n && s.fc[i] == 0 && s.fcHit[i] != 0) okHit = false;
      }
      CHECK(okScore, "score = 2*higher + nrtr + body + ema side; below the threshold the tie-break gives every candle an arrow");
      bool everyCandle = true;
      for(int i = 15; i < s.n; i++) if(s.fc[i] == 0) everyCandle = false;
      CHECK(everyCandle, "an arrow on every candle once the NRTR is ready");
      CHECK(okHit, "hit = next close vs this close, equal = miss");
      CHECK(lastUnresolved, "the newest forecast is unresolved until the next candle closes");
      int n = 0, h = 0;
      NqForecastStats(s, 0, n, h);
      CHECK(n > 0 && h <= n, "stats count resolved arrows only");
      CHECK(NqEvidenceText(5) == "n<20 = luck" && NqEvidenceText(50) == "n<100 = early" && NqEvidenceText(150) == "n>=100", "evidence label");
   }
   end("E02");

   begin("E03 auto lot: risk money / loss per lot, floored to the volume step, never widened");
   {
      // gold: tick 0.01 = 1.00 per lot; SL 4.80 -> 480 per lot; 50 risk -> 0.104 -> 0.10
      CHECK(near(NqLotFor(50.0, 4.80, 0.01, 1.0, 0.01, 100.0, 0.01), 0.10), "0.10 lots");
      CHECK(near(NqLossAt(0.10, 4.80, 0.01, 1.0), 48.0), "loss at SL 48.00 <= 50");
      CHECK(NqLotFor(3.0, 4.80, 0.01, 1.0, 0.01, 100.0, 0.01) == 0.0, "min lot would risk 4.80 > 3.00 -> no trade");
      CHECK(near(NqLotFor(1e9, 4.80, 0.01, 1.0, 0.01, 50.0, 0.01), 50.0), "clamped to volMax");
      CHECK(near(NqLotFor(50.0, 4.80, 0.01, 1.0, 0.1, 100.0, 0.1), 0.1), "step 0.1 -> 0.1");
      CHECK(NqLotFor(50.0, 4.80, 0.01, 1.0, 0.2, 100.0, 0.1) == 0.0, "min 0.2 would risk 96 > 50 -> no trade");
      CHECK(NqLotFor(50.0, 0.0, 0.01, 1.0, 0.01, 100.0, 0.01) == 0.0 && NqLotFor(0.0, 4.8, 0.01, 1.0, 0.01, 100.0, 0.01) == 0.0, "degenerate inputs -> 0");
      // silver: tick 0.001, tick value 5 (5000 oz), SL 0.60 -> 3000 per lot; 50 -> 0.016 -> 0.01
      CHECK(near(NqLotFor(50.0, 0.60, 0.001, 5.0, 0.01, 100.0, 0.01), 0.01), "silver 0.01");
      CHECK(near(NqRiskMoney(10000.0, 0.5), 50.0) && NqRiskMoney(0.0, 0.5) == 0.0, "risk money");
   }
   end("E03");

   begin("E04 risk gate bits and session filter");
   {
      CHECK(NqRiskGate(true, true, false, true, 20, 50, 0.0, 200.0, 0, 2, 0, 10, true) == 0, "open");
      CHECK((NqRiskGate(true, false, false, true, 20, 50, 0.0, 200.0, 0, 2, 0, 10, true) & NQ_K_REAL_ACCOUNT) != 0, "real blocked");
      CHECK(NqRiskGate(true, false, true, true, 20, 50, 0.0, 200.0, 0, 2, 0, 10, true) == 0, "real allowed only explicitly");
      CHECK((NqRiskGate(false, true, false, true, 20, 50, 0.0, 200.0, 0, 2, 0, 10, true) & NQ_K_AUTO_OFF) != 0, "auto off");
      CHECK((NqRiskGate(true, true, false, false, 20, 50, 0.0, 200.0, 0, 2, 0, 10, true) & NQ_K_TRADE_DISABLED) != 0, "terminal off");
      CHECK((NqRiskGate(true, true, false, true, 80, 50, 0.0, 200.0, 0, 2, 0, 10, true) & NQ_K_SPREAD) != 0, "spread");
      CHECK((NqRiskGate(true, true, false, true, 20, 50, -200.0, 200.0, 0, 2, 0, 10, true) & NQ_K_DAILY_CAP) != 0, "daily cap at the limit");
      CHECK((NqRiskGate(true, true, false, true, 20, 50, -199.0, 200.0, 0, 2, 0, 10, true) & NQ_K_DAILY_CAP) == 0, "just inside the cap");
      CHECK((NqRiskGate(true, true, false, true, 20, 50, 0.0, 200.0, 2, 2, 0, 10, true) & NQ_K_MAX_POS) != 0, "max positions");
      CHECK((NqRiskGate(true, true, false, true, 20, 50, 0.0, 200.0, 0, 2, 10, 10, true) & NQ_K_MAX_TRADES) != 0, "max trades");
      CHECK((NqRiskGate(true, true, false, true, 20, 50, 0.0, 200.0, 0, 2, 0, 10, false) & NQ_K_SESSION) != 0, "session");
      CHECK(NqInSession(3, 0, 24) && NqInSession(9, 8, 17) && !NqInSession(18, 8, 17) && NqInSession(23, 22, 2) && NqInSession(1, 22, 2) && !NqInSession(5, 22, 2), "session hours incl. overnight");
      CHECK(NqGateAt(NQ_K_SPREAD | NQ_K_REAL_ACCOUNT, 0) == NqGateName(NQ_K_REAL_ACCOUNT), "real account is named first");
   }
   end("E04");

   begin("E05 bearish QML: sell limit at the left shoulder, SL above the head, created on the neck break");
   {
      std::vector<SBar> v = craftQml(true, 0.0);
      NqSeries s;
      std::vector<NqPivot> piv;
      NqSeries ctx;
      fill(ctx, agg(v, 900), 900);
      NqRunContext(ctx, P);
      fill(s, v, 300);
      NqRunRegime(s, piv, ctx, P);
      std::vector<NqPlan> plans;
      int np = 0;
      NqFindPlans(s, piv, s.np, P, plans, np);
      int k = -1;
      for(int i = 0; i < np; i++) if(plans[i].kind == NQ_PLAN_QML && plans[i].dir == NQ_SELL) k = i;
      CHECK(k >= 0, "a bearish QML plan exists");
      if(k >= 0)
      {
         const NqPlan &p = plans[(size_t)k];
         CHECK(p.idx == 28, "created at the close of bar 28 (neck break)");
         CHECK(near(p.entry, s.h[10]), "entry = left shoulder high");
         CHECK(near(p.lvlA, s.l[16]) && near(p.lvlB, s.h[22]), "neck = B low, head = C high");
         CHECK(p.sl > s.h[22] && near(p.sl, NqRoundTick(s.h[22] + 0.2 * s.atr[28], 0.01, 2, 1)), "SL above head + 0.2 ATR");
         CHECK(near(p.tp1, NqRoundTick(p.entry - p.risk, 0.01, 2, 0)) && near(p.tp2, NqRoundTick(p.entry - 2 * p.risk, 0.01, 2, 0)), "TP1 = 1R, TP2 = 2R");
         CHECK(p.keyTime == s.t[22], "keyed by the head time");
         CHECK(p.fillIdx == 31, "filled when a later bar's high reaches the shoulder");
         CHECK(p.status == NQ_PL_TP1 && p.statusIdx == 35, "then reached TP1");
      }
      // no decision before the neck break: a prefix ending at bar 27 has no plan
      std::vector<SBar> v27(v.begin(), v.begin() + 28);
      NqSeries s27;
      std::vector<NqPivot> piv27;
      fill(s27, v27, 300);
      NqRunRegime(s27, piv27, ctx, P);
      std::vector<NqPlan> pl27;
      int np27 = 0;
      NqFindPlans(s27, piv27, s27.np, P, pl27, np27);
      bool none = true;
      for(int i = 0; i < np27; i++) if(pl27[i].kind == NQ_PLAN_QML) none = false;
      CHECK(none, "no QML plan while the neck is intact");
      // a gap over the shoulder still fills the sell limit (at a better price in
      // reality); a bar that also runs through the SL is judged a stop, pessimistically
      std::vector<SBar> vi(v.begin(), v.begin() + 29);
      for(int i = 0; i < 3; i++)
      {
         double o = 102.5 + i;
         double x = 103.0 + i;
         vi.push_back({T0 + (long long)vi.size() * 300, o, x + 0.05, o - 0.05, x});
      }
      NqSeries si;
      std::vector<NqPivot> pivi;
      fill(si, vi, 300);
      NqRunRegime(si, pivi, ctx, P);
      std::vector<NqPlan> pli;
      int npi = 0;
      NqFindPlans(si, pivi, si.np, P, pli, npi);
      int ki = -1;
      for(int i = 0; i < npi; i++) if(pli[i].kind == NQ_PLAN_QML && pli[i].dir == NQ_SELL) ki = i;
      CHECK(ki >= 0 && pli[(size_t)ki].status == NQ_PL_SL && pli[(size_t)ki].fillIdx == 29 && pli[(size_t)ki].statusIdx == 29,
            "gap through shoulder and head: filled and stopped on the same bar");
   }
   end("E05");

   begin("E06 bullish QML mirror: buy limit at the left shoulder low, SL below the head");
   {
      std::vector<SBar> v = craftQml(false, 0.0);
      NqSeries s;
      std::vector<NqPivot> piv;
      NqSeries ctx;
      fill(ctx, agg(v, 900), 900);
      NqRunContext(ctx, P);
      fill(s, v, 300);
      NqRunRegime(s, piv, ctx, P);
      std::vector<NqPlan> plans;
      int np = 0;
      NqFindPlans(s, piv, s.np, P, plans, np);
      int k = -1;
      for(int i = 0; i < np; i++) if(plans[i].kind == NQ_PLAN_QML && plans[i].dir == NQ_BUY) k = i;
      CHECK(k >= 0, "a bullish QML plan exists");
      if(k >= 0)
      {
         const NqPlan &p = plans[(size_t)k];
         CHECK(p.idx == 28 && near(p.entry, s.l[10]) && p.sl < s.l[22] && near(p.lvlB, s.l[22]), "mirror levels");
         CHECK(p.tp1 > p.entry && near(p.tp1, NqRoundTick(p.entry + p.risk, 0.01, 2, 0)), "TP above entry");
         CHECK(p.fillIdx == 31 && p.status == NQ_PL_TP1, "filled at the shoulder, reached TP1");
      }
   }
   end("E06");

   begin("E07 synthetic market: every plan and every scalp signal obeys its own rules");
   {
      Market m = makeMarket(11, 4150.0, 0.01, 0.35, 6);
      Run r;
      runAll(r, m, P, m.m1.size());
      const NqSeries &s5 = r.s5;
      bool okPb = true, okQml = true, okJudge = true;
      int nPb = 0, nQ = 0;
      for(int k = 0; k < r.nPlans; k++)
      {
         const NqPlan &p = r.plans[(size_t)k];
         if(p.kind == NQ_PLAN_PB)
         {
            nPb++;
            if(p.dir > 0)
            {
               if(s5.regime[p.idx] != NQ_REG_BULL || !(p.entry > p.lvlA && p.entry < p.lvlB) || !(p.sl < p.lvlA) ||
                  !(s5.c[p.idx] > p.entry) || !near(p.tp1, NqRoundTick(p.entry + p.risk, 0.01, 2, 0)))
                  okPb = false;
            }
            else
            {
               if(s5.regime[p.idx] != NQ_REG_BEAR || !(p.entry < p.lvlA && p.entry > p.lvlB) || !(p.sl > p.lvlA) ||
                  !(s5.c[p.idx] < p.entry))
                  okPb = false;
            }
         }
         else
         {
            nQ++;
            if(p.dir < 0 && !(p.sl > p.lvlB && p.entry < p.lvlB && p.entry > p.lvlA && s5.c[p.idx] < p.lvlA)) okQml = false;
            if(p.dir > 0 && !(p.sl < p.lvlB && p.entry > p.lvlB && p.entry < p.lvlA && s5.c[p.idx] > p.lvlA)) okQml = false;
         }
         // re-judge the plan bar by bar from its own rules
         if(p.status == NQ_PL_FILLED || p.status == NQ_PL_TP1 || p.status == NQ_PL_SL)
         {
            if(p.fillIdx <= p.idx) okJudge = false;
            bool touched = (p.dir > 0) ? (s5.l[p.fillIdx] <= p.entry) : (s5.h[p.fillIdx] >= p.entry);
            if(!touched) okJudge = false;
            for(int t = p.idx + 1; t < p.fillIdx; t++)
            {
               bool early = (p.dir > 0) ? (s5.l[t] <= p.entry) : (s5.h[t] >= p.entry);
               if(early) okJudge = false;
            }
         }
         if(p.status == NQ_PL_EXPIRED && p.statusIdx - p.idx != P.planValidBars) okJudge = false;
      }
      std::printf("    plans: %d pullback, %d QML, scalp signals: %d\n", nPb, nQ, r.nSig);
      CHECK(nPb + nQ > 0, "the synthetic market produces plans");
      CHECK(okPb, "pullback plans: regime direction, entry inside the leg, SL beyond the swing, price above/below entry");
      CHECK(okQml, "QML plans: entry at the shoulder between neck and head, SL beyond the head, neck broken");
      CHECK(okJudge, "fills and expiries match the bars");
      // at most one ACTIVE plan per kind+direction
      int act[2][2] = {{0, 0}, {0, 0}};
      for(int k = 0; k < r.nPlans; k++)
         if(r.plans[(size_t)k].status == NQ_PL_ACTIVE)
            act[r.plans[(size_t)k].kind == NQ_PLAN_QML ? 0 : 1][r.plans[(size_t)k].dir > 0 ? 0 : 1]++;
      CHECK(act[0][0] <= 1 && act[0][1] <= 1 && act[1][0] <= 1 && act[1][1] <= 1, "one live plan per kind and side");

      const NqSeries &s1 = r.s1;
      bool okSig = true, okState = true;
      for(int k = 0; k < r.nSig; k++)
      {
         const NqSignal &g = r.sigs[(size_t)k];
         int b = g.idx;
         if(g.dir != s1.hi[b] || s1.dir[b] != g.dir) okSig = false;
         if(g.dir > 0 && !(s1.c[b] > s1.o[b] && s1.c[b] > s1.emaF[b])) okSig = false;
         if(g.dir < 0 && !(s1.c[b] < s1.o[b] && s1.c[b] < s1.emaF[b])) okSig = false;
         double atr5 = s1.atrHi[b];
         double sl = (g.dir > 0) ? NqRoundTick(g.entry - 1.5 * atr5, 0.01, 2, -1) : NqRoundTick(g.entry + 1.5 * atr5, 0.01, 2, 1);
         double tp = (g.dir > 0) ? NqRoundTick(g.entry + 1.0 * atr5, 0.01, 2, 1) : NqRoundTick(g.entry - 1.0 * atr5, 0.01, 2, -1);
         if(!near(g.entry, s1.c[b]) || !near(g.sl, sl) || !near(g.tp, tp)) okSig = false;
         // outcome re-judged: SL first, then TP, then time stop
         int want = NQ_SIG_ACTIVE, at = -1;
         for(int t = b + 1; t < s1.n && want == NQ_SIG_ACTIVE; t++)
         {
            if(g.dir > 0) { if(s1.l[t] <= g.sl) want = NQ_SIG_SL; else if(s1.h[t] >= g.tp) want = NQ_SIG_TP; }
            else { if(s1.h[t] >= g.sl) want = NQ_SIG_SL; else if(s1.l[t] <= g.tp) want = NQ_SIG_TP; }
            if(want == NQ_SIG_ACTIVE && t - b >= P.scalpTimeBars) want = NQ_SIG_TIMEOUT;
            if(want != NQ_SIG_ACTIVE) at = t;
         }
         if(g.status != want || (want != NQ_SIG_ACTIVE && g.statusIdx != at)) okSig = false;
         // one signal per aligned episode: the previous signal's episode must have ended
         if(k > 0)
         {
            int pb = r.sigs[(size_t)k - 1].idx;
            bool broke = false;
            for(int t = pb + 1; t <= b; t++)
               if(!(s1.hi[t] != 0 && s1.dir[t] == s1.hi[t]) || s1.hi[t] != s1.hi[pb]) { broke = true; break; }
            if(!broke) okSig = false;
         }
      }
      for(int b = 0; b < s1.n; b++)
      {
         int st = s1.state[b];
         if(st == NQ_BUY || st == NQ_SELL)
         {
            int c = s1.sigOf[b];
            if(c < 0 || b - r.sigs[(size_t)c].idx >= P.scalpValidBars ||
               (r.sigs[(size_t)c].status != NQ_SIG_ACTIVE && r.sigs[(size_t)c].statusIdx <= b))
               okState = false;
            if(s1.reasons[b] != 0) okState = false;
         }
         else if(s1.reasons[b] == 0) okState = false;
      }
      CHECK(r.nSig > 20, "enough scalp signals to test");
      CHECK(okSig, "signal = first closed candle of an aligned episode, SL 1.5 ATR5, TP 1.0 ATR5, judged SL-first");
      CHECK(okState, "BUY/SELL state only while a signal is active and young; WAIT always has a reason");
   }
   end("E07");

   begin("E08 no repaint: every past state, arrow, signal and plan is unchanged by later bars");
   {
      Market m = makeMarket(23, 60.9, 0.001, 0.006, 6);   // silver-like
      NqParams Ps = params(0.001, 3);
      Run full;
      runAll(full, m, Ps, m.m1.size());
      bool ok = true;
      int cuts = 0;
      for(size_t cut = 1440 * 3; cut < m.m1.size(); cut += 377)
      {
         Run r;
         runAll(r, m, Ps, cut);
         cuts++;
         int n1 = r.s1.n;
         for(int i = 0; i < n1; i++)
         {
            if(r.s1.state[i] != full.s1.state[i] || r.s1.reasons[i] != full.s1.reasons[i] || r.s1.fc[i] != full.s1.fc[i] ||
               r.s1.hi[i] != full.s1.hi[i])
            { ok = false; break; }
            if(i + 1 < n1 && r.s1.fcHit[i] != full.s1.fcHit[i]) { ok = false; break; }
         }
         for(int i = 0; i < r.s5.n; i++)
            if(r.s5.regime[i] != full.s5.regime[i] || r.s5.st[i] != full.s5.st[i] || r.s5.fc[i] != full.s5.fc[i]) { ok = false; break; }
         // signals created before the cut: same entry/sl/tp; status may only progress
         for(int k = 0; k < r.nSig && k < full.nSig; k++)
         {
            const NqSignal &a = r.sigs[(size_t)k];
            const NqSignal &b = full.sigs[(size_t)k];
            if(a.idx != b.idx || a.dir != b.dir || !near(a.entry, b.entry) || !near(a.sl, b.sl) || !near(a.tp, b.tp)) { ok = false; break; }
            if(a.status != NQ_SIG_ACTIVE && (a.status != b.status || a.statusIdx != b.statusIdx)) { ok = false; break; }
         }
         for(int k = 0; k < r.nPlans && k < full.nPlans; k++)
         {
            const NqPlan &a = r.plans[(size_t)k];
            const NqPlan &b = full.plans[(size_t)k];
            if(a.idx != b.idx || a.kind != b.kind || a.dir != b.dir || a.keyTime != b.keyTime || !near(a.entry, b.entry) ||
               !near(a.sl, b.sl) || !near(a.tp1, b.tp1)) { ok = false; break; }
            bool aDone = (a.status != NQ_PL_ACTIVE && a.status != NQ_PL_FILLED);
            if(aDone && (a.status != b.status || a.statusIdx != b.statusIdx)) { ok = false; break; }
            if(a.status == NQ_PL_FILLED && b.fillIdx != a.fillIdx) { ok = false; break; }
         }
         if(!ok) { std::printf("    mismatch at cut %zu\n", cut); break; }
      }
      std::printf("    %d cut points over %zu M1 bars\n", cuts, m.m1.size());
      CHECK(ok, "prefix results equal the full run on the shared history");
   }
   end("E08");

   begin("E09 freshness, metal detection, text tables");
   {
      long long now = T0 + 100000;
      CHECK(NqIsFresh(now - 120, 60, now - 600, 300, now - 1800, 900, now), "fresh");
      CHECK(!NqIsFresh(now - 300, 60, now - 600, 300, now - 1800, 900, now), "M1 4 min old -> stale");
      CHECK(!NqIsFresh(now - 120, 60, now - 2000, 300, now - 1800, 900, now), "M5 stale");
      CHECK(!NqIsFresh(0, 60, now - 600, 300, now - 1800, 900, now), "missing -> stale");
      CHECK(NqMetalOf("XAUUSD", "XAU", "USD") == NQ_METAL_GOLD && NqMetalOf("#XAGUSD.m", "", "USD") == NQ_METAL_SILVER &&
            NqMetalOf("GOLD", "", "") == NQ_METAL_GOLD && NqMetalOf("EURUSD", "EUR", "USD") == NQ_METAL_NONE &&
            NqMetalOf("XAUEUR", "XAU", "EUR") == NQ_METAL_NONE, "metals");
      bool names = true;
      for(int k = 0; k < NQ_R_COUNT; k++) if(NqReasonName(NqReasonBit(k)) == "") names = false;
      for(int k = 0; k < NQ_K_COUNT; k++) if(NqGateName(NqGateBit(k)) == "") names = false;
      CHECK(names, "every reason and gate bit has a name");
      CHECK(NqReasonAt(NQ_R_M1_AGAINST | NQ_R_STALE, 0) == NqReasonName(NQ_R_STALE), "stale is named first");
   }
   end("E09");

   begin("E10 NY trap state machine: range -> sweep -> return -> confirmation -> plan; expiry at session end");
   {
      // one server day of M5 bars: pre-NY 00:00-16:30 in 90..100, then the NY session
      auto mk = [&](std::vector<SBar> &v, double o, double h, double l, double c) {
         v.push_back({T0 + (long long)v.size() * 300, o, h, l, c});
      };
      std::vector<SBar> v;
      int preBars = (16 * 60 + 30) / 5;   // bars before 16:30
      for(int i = 0; i < preBars; i++)
      {
         double x = 95.0 + 4.0 * std::sin(i * 0.37);   // range 91..99
         mk(v, x, x + 0.5, x - 0.5, x + 0.2);
      }
      double preHi = 0, preLo = 1e9;
      for(const SBar &b : v) { preHi = std::max(preHi, b.h); preLo = std::min(preLo, b.l); }
      mk(v, 96.0, 97.0, 95.5, 96.5);              // 16:30 inside the range
      mk(v, 96.5, preHi + 1.5, 96.0, preHi + 0.8); // 16:35 SWEEP above the pre-NY high
      int sweepBar = (int)v.size() - 1;
      mk(v, preHi + 0.8, preHi + 1.0, preHi - 1.5, preHi - 1.0);   // 16:40 close back inside -> RETURNED
      int retBar = (int)v.size() - 1;
      mk(v, preHi - 1.0, preHi - 0.5, preHi - 2.0, preHi - 1.8);   // 16:45 confirmation bar
      int confBar = (int)v.size() - 1;
      mk(v, preHi - 1.8, preHi + 0.2, preHi - 2.0, preHi - 0.5);   // 16:50 touches the shoulder -> fill
      int fillBar = (int)v.size() - 1;
      for(int i = 0; i < 6; i++) mk(v, preHi - 0.5, preHi - 0.3, preHi - 0.9, preHi - 0.6);
      mk(v, preHi - 0.6, preHi - 0.5, preHi - 6.0, preHi - 5.0);   // drops through TP1
      int tpBar = (int)v.size() - 1;
      while(v.size() < 288) mk(v, preHi - 5.0, preHi - 4.5, preHi - 5.5, preHi - 5.0);
      mk(v, 90, 91, 89, 90);   // first bar of the next day
      NqSeries s;
      fill(s, v, 300);
      NqCalcATR(s.h, s.l, s.c, s.n, P.atrPeriod, s.atr);
      std::vector<int> conf((size_t)s.n, 1);           // bullish everywhere ...
      for(int i = confBar; i < s.n; i++) conf[(size_t)i] = -1;   // ... bearish from the confirmation bar
      std::vector<NqPlan> plans;
      int np = 0;
      NqNyState y;
      NqRunNyTrap(s, conf, P, 0, 16 * 60 + 30, 23 * 60, plans, np, y);
      CHECK(np == 1, "exactly one NY plan");
      if(np == 1)
      {
         const NqPlan &pl = plans[0];
         CHECK(pl.kind == NQ_PLAN_NY && pl.dir == NQ_SELL && pl.tf == 300, "bull trap -> SELL plan on M5");
         CHECK(pl.idx == confBar, "armed on the confirmation bar, not on the sweep or the return");
         CHECK(near(pl.entry, NqRoundTick(preHi, 0.01, 2, 0)) && near(pl.lvlA, preHi) && near(pl.lvlB, s.h[sweepBar]), "entry = swept pre-NY high, extreme recorded");
         CHECK(pl.sl > s.h[sweepBar], "SL beyond the sweep extreme");
         CHECK(pl.fillIdx == fillBar && pl.status == NQ_PL_TP1 && pl.statusIdx == tpBar, "filled at the level, reached TP1");
      }
      CHECK(y.day == NqDayOf(v.back().t) && y.stBull == NQ_NY_NONE, "the next day starts a fresh state");
      // no confirmation -> no plan, and the state stays RETURNED until the session ends
      std::vector<int> bull((size_t)s.n, 1);
      std::vector<NqPlan> p2;
      int np2 = 0;
      NqNyState y2;
      std::vector<SBar> v2(v.begin(), v.begin() + retBar + 3);
      NqSeries s2;
      fill(s2, v2, 300);
      NqCalcATR(s2.h, s2.l, s2.c, s2.n, P.atrPeriod, s2.atr);
      bull.resize((size_t)s2.n, 1);
      NqRunNyTrap(s2, bull, P, 0, 16 * 60 + 30, 23 * 60, p2, np2, y2);
      CHECK(np2 == 0 && y2.stBull == NQ_NY_RETURNED && y2.stBear == NQ_NY_OPEN, "sweep + return without confirmation is not a trade");
      // armed but never filled -> expires when the session ends
      std::vector<SBar> v3(v.begin(), v.begin() + confBar + 1);
      for(int i = 0; i < 80; i++) v3.push_back({T0 + (long long)v3.size() * 300, preHi - 3.0, preHi - 2.5, preHi - 3.5, preHi - 3.0});
      NqSeries s3;
      fill(s3, v3, 300);
      NqCalcATR(s3.h, s3.l, s3.c, s3.n, P.atrPeriod, s3.atr);
      std::vector<int> c3((size_t)s3.n, -1);
      std::vector<NqPlan> p3;
      int np3 = 0;
      NqNyState y3;
      NqRunNyTrap(s3, c3, P, 0, 16 * 60 + 30, 23 * 60, p3, np3, y3);
      CHECK(np3 == 1 && p3[0].status == NQ_PL_EXPIRED && y3.stBull == NQ_NY_DONE && !y3.inSession, "unfilled plan expires at the session end");
      CHECK(near(NqDistAtr(NQ_SELL, 101.0, 100.0, 100.2, 2.0), 0.5) && near(NqDistAtr(NQ_BUY, 99.0, 100.0, 100.2, 2.0), 0.6), "distance in ATR units from bid (sell) / ask (buy)");
   }
   end("E10");

   std::printf("\nEA ENGINE TESTS: %d checks passed, %d failed\n", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
