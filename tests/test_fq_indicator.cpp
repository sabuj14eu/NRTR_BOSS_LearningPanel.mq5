// Whole-indicator tests for the v1.05 FIVE-QUESTION PLAN table of the twins:
// the complete .mq5 (translated syntax-only) runs against the simulated MT5
// terminal; the table (NBSP_Q_) and its chart drawing (NBSP_F_) are read back
// from the objects the indicator created and compared with an independent
// run of the engine functions on the same bars.
#include "../tests/mt5_sim.h"
#if NB_TEST_MARKET == 2
#include "full_forex.inc"
#else
#include "full_crypto.inc"
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

static const long long T0 = 1788220800LL;
#if NB_TEST_MARKET == 2
static const char *SYM = "EURUSD", *BASE = "EUR", *QUOTE = "USD";
static const int DIGITS = 5;
static const double TICK = 0.00001, PRICE = 1.08, VOL = 0.0004;
static const char *ONLY = "FOREX ONLY";
#else
static const char *SYM = "BTCUSD", *BASE = "BTC", *QUOTE = "USD";
static const int DIGITS = 2;
static const double TICK = 0.01, PRICE = 60000.0, VOL = 40.0;
static const char *ONLY = "CRYPTO ONLY";
#endif

static std::vector<MqlRates> toRates(const std::vector<SBar> &v)
{
   std::vector<MqlRates> r;
   for(const SBar &b : v) r.push_back({b.t, b.o, b.h, b.l, b.c, 100, 0, 0});
   return r;
}
struct Market { std::vector<SBar> m5, m15; };
static Market makeMarket(uint64_t seed, int days)
{
   Market m;
   m.m5 = gen5m(seed, days * 288, T0, PRICE, TICK, VOL);
   m.m15 = agg(m.m5, 900);
   return m;
}
static void load(const Market &m, const char *sym, const char *base, const char *quote)
{
   SIM = SimState();
   SIM.sym = sym; SIM.base = base; SIM.profit = quote; SIM.digits = DIGITS; SIM.tick = TICK;
   SIM.tickValue = TICK * 100.0; SIM.volMin = 0.01; SIM.gmtOff = 3 * 3600;
   SIM.m5 = toRates(m.m5); SIM.m15 = toRates(m.m15);
   _Symbol = sym;
}
static void calc()
{
   int v = simVisible(_Period);
   const auto &s = simSeries(_Period);
   std::vector<datetime> t;
   std::vector<double> o, h, l, c;
   std::vector<long> tv, vol;
   std::vector<int> sp;
   for(int i = 0; i < v; i++)
   {
      t.push_back(s[(size_t)i].time); o.push_back(s[(size_t)i].open); h.push_back(s[(size_t)i].high);
      l.push_back(s[(size_t)i].low); c.push_back(s[(size_t)i].close); tv.push_back(0); vol.push_back(0); sp.push_back(0);
   }
   for(auto &kv : SIM.bufs) kv.second->assign((size_t)v, 0.0);
   if(v > 0) SIM.bid = c.back();
   OnCalculate(v, 0, t, o, h, l, c, tv, vol, sp);
   OnTimer();
}
static int start() { int rc = OnInit(); calc(); return rc; }
static std::string q(const std::string &id) { return SIM.objs.count("NBSP_Q_" + id) ? SIM.objs["NBSP_Q_" + id].s[OBJPROP_TEXT] : "<missing>"; }
static std::string ptxt(const std::string &id) { return SIM.objs.count("NBSP_P_" + id) ? SIM.objs["NBSP_P_" + id].s[OBJPROP_TEXT] : "<missing>"; }
static bool has(const std::string &s, const std::string &sub) { return s.find(sub) != std::string::npos; }
static int countPrefix(const std::string &p)
{
   int n = 0;
   for(auto &kv : SIM.objs) if(kv.first.compare(0, p.size(), p) == 0) n++;
   return n;
}
static std::string ftxt(const std::string &id) { return SIM.objs.count("NBSP_F_" + id) ? SIM.objs["NBSP_F_" + id].s[OBJPROP_TEXT] : "<missing>"; }
static double fprice(const std::string &id) { return SIM.objs.count("NBSP_F_" + id) ? SIM.objs["NBSP_F_" + id].d[OBJPROP_PRICE * 100 + 0] : -1.0; }
static long long fint(const std::string &id, int prop) { return SIM.objs.count("NBSP_F_" + id) ? SIM.objs["NBSP_F_" + id].i[prop] : -999; }

//--- independent engine run on the bars the terminal would load at `now`
struct Ref
{
   NbSeries s5, s15;
   std::vector<NbPivot> p15, p5;
   std::vector<NbSignal> sig;
   int nSig = 0;
   std::vector<NbFqBar> fq;
   std::vector<NbFqPlan> pl;
   int npl = 0;
   NbFqBar b;        // last closed bar
   int state = 0, reasons = 0;
};
static void reference(const Market &m, long long now, Ref &r)
{
   NbParams P;
   P.atrPeriod = InpNrtrAtrPeriod; P.nrtrMult = InpNrtrMultiplier; P.emaPeriod = InpEmaPeriod;
   P.swing = InpSwingStrength; P.slBufAtr = InpSlBufferAtr; P.tp1R = InpTp1R; P.tp2R = InpTp2R;
   P.validBars = InpSignalValidBars; P.tick = TICK; P.digits = DIGITS;
   NbSessCfg S;
   S.clockMode = NB_CLK_AUTO; S.clockOk = true; S.offset = 3 * 3600; S.manualOpenSec = 0;
   S.preHours = InpPreNyRangeHours; S.winMin = InpNyWindowMinutes; S.minRangeBars = InpMinRangeBars; S.pauseFlow = InpNyPauseFlow;
   NbFqCfg C;
   C.zoneAtr = InpFqZoneAtr; C.window = InpFqWindowBars; C.minRR = InpFqMinRR; C.validBars = InpFqValidBars;
   C.openMax = NB_FQ_OPEN_MAX; C.asiaStart = InpFqAsiaStartUtc; C.asiaEnd = InpFqAsiaEndUtc;
   C.lonStart = InpFqLondonStartUtc; C.lonEnd = InpFqLondonEndUtc; C.clockOk = true; C.offset = 3 * 3600;
   long long anchor = (now / 86400) * 86400 - (long long)InpHistoryDays * 86400;
   std::vector<SBar> v5, v15;
   for(const SBar &x : m.m5) if(x.t >= anchor && x.t + 300 <= now) v5.push_back(x);
   for(const SBar &x : m.m15) if(x.t >= anchor && x.t + 900 <= now) v15.push_back(x);
   NbSeriesResize(r.s5, (int)v5.size()); r.s5.sec = 300;
   NbSeriesResize(r.s15, (int)v15.size()); r.s15.sec = 900;
   for(size_t i = 0; i < v5.size(); i++) { r.s5.t[i] = v5[i].t; r.s5.o[i] = v5[i].o; r.s5.h[i] = v5[i].h; r.s5.l[i] = v5[i].l; r.s5.c[i] = v5[i].c; }
   for(size_t i = 0; i < v15.size(); i++) { r.s15.t[i] = v15[i].t; r.s15.o[i] = v15[i].o; r.s15.h[i] = v15[i].h; r.s15.l[i] = v15[i].l; r.s15.c[i] = v15[i].c; }
   NbRun15(r.s15, r.p15, P);
   NbRun5(r.s5, r.p5, r.s15, true, P, S, r.sig, r.nSig);
   NbRunFq(r.s5, r.s15, r.p15, r.s15.np, r.p5, r.s5.np, true, P, C, r.fq, r.pl, r.npl);
   r.b = r.fq.back();
   r.state = r.s5.state.back();
   r.reasons = r.s5.reasons.back();
}
template <class F> static long long findNow(const Market &m, F pred, size_t from = 11 * 288)
{
   for(size_t i = from; i + 1 < m.m5.size(); i++)
   {
      long long now = m.m5[i].t + 300 + 20;
      Ref r;
      reference(m, now, r);
      if(pred(r)) return now;
   }
   return 0;
}
static std::map<std::string, SimObj> snapPrefix(const std::string &p)
{
   std::map<std::string, SimObj> out;
   for(auto &kv : SIM.objs) if(kv.first.compare(0, p.size(), p) == 0) out[kv.first] = kv.second;
   return out;
}
static bool sameObjs(const std::map<std::string, SimObj> &a, const std::map<std::string, SimObj> &b)
{
   if(a.size() != b.size()) return false;
   for(auto &kv : a)
   {
      auto it = b.find(kv.first);
      if(it == b.end()) return false;
      if(kv.second.s != it->second.s || kv.second.i != it->second.i || kv.second.d != it->second.d) return false;
   }
   return true;
}

int main()
{
   std::printf("twin under test: %s on %s\n", NB_MARKET == NB_MKT_CRYPTO ? "CRYPTO" : "FOREX", SYM);
   Market mk = makeMarket(7, 16);

   long long nReadyB = findNow(mk, [](const Ref &r) { return r.b.status == NB_FQ_READY && r.pl[(size_t)r.b.plan].dir > 0 && r.pl[(size_t)r.b.plan].idx == r.s5.n - 1; });
   long long nReadyS = findNow(mk, [](const Ref &r) { return r.b.status == NB_FQ_READY && r.pl[(size_t)r.b.plan].dir < 0 && r.pl[(size_t)r.b.plan].idx == r.s5.n - 1; });

   begin("Q1 the table sits at the bottom middle and never covers the main panel");
   {
      CHECK(nReadyB > 0, "fixture has a READY BUY moment");
      for(int w : {1400, 1920})
      {
         load(mk, SYM, BASE, QUOTE);
         SIM.chartW = w;
         SIM.now = nReadyB;
         start();
         SimObj &bg = SIM.objs["NBSP_Q_bg"];
         SimObj &pbg = SIM.objs["NBSP_P_bg"];
         long long x = bg.i[OBJPROP_XDISTANCE], y = bg.i[OBJPROP_YDISTANCE], W = bg.i[OBJPROP_XSIZE], H = bg.i[OBJPROP_YSIZE];
         long long pRight = pbg.i[OBJPROP_XDISTANCE] + pbg.i[OBJPROP_XSIZE];
         long long centred = (w - W) / 2;
         char m[160];
         std::snprintf(m, sizeof m, "chart %d px: x %lld = the centre %lld unless the main panel (right edge %lld) is in the way", w, x, centred, pRight);
         CHECK(x == std::max(centred, pRight + 8), m);
         CHECK(x >= pRight, "no horizontal overlap with the main panel");
         CHECK(y + H == 900 - InpFqBottomY, "bottom edge InpFqBottomY px above the chart bottom");
         if(w == 1920) CHECK(x == centred, "on a wide chart it is exactly centred");
         bool inside = true;
         for(auto &kv : SIM.objs)
         {
            if(kv.first.compare(0, 7, "NBSP_Q_") != 0 || kv.second.type != OBJ_LABEL) continue;
            long long lx = kv.second.i[OBJPROP_XDISTANCE], ly = kv.second.i[OBJPROP_YDISTANCE];
            if(lx < x || lx > x + W || ly < y || ly > y + H) { inside = false; std::printf("    outside: %s\n", kv.first.c_str()); }
         }
         CHECK(inside, "every table label is inside the table rectangle");
         OnDeinit(0);
      }
   }
   end("Q1");

   begin("Q2 READY renders the engine's exact plan: order, SL, TP1, TP2, R:R, next step, chart lines");
   {
      CHECK(nReadyB > 0 && nReadyS > 0, "fixture has READY BUY and READY SELL moments");
      for(int side = 0; side < 2 && nReadyB > 0 && nReadyS > 0; side++)
      {
         long long now = side == 0 ? nReadyB : nReadyS;
         Ref r;
         reference(mk, now, r);
         const NbFqPlan &g = r.pl[(size_t)r.b.plan];
         load(mk, SYM, BASE, QUOTE);
         SIM.now = now;
         CHECK(start() == INIT_SUCCEEDED, "init ok");
         std::string lim = std::string(side == 0 ? "BUY LIMIT " : "SELL LIMIT ") + DoubleToString(g.entry, DIGITS);
         CHECK(has(q("status"), "READY") && has(q("status"), lim), "banner: READY - <side> LIMIT <entry>");
         bool allYes = true;
         for(int k = 0; k < 5; k++) allYes = allYes && q("qa" + std::to_string(k)) == "YES";
         CHECK(allYes, "all five questions answer YES");
         CHECK(has(q("title"), side == 0 ? "15M BULLISH" : "15M BEARISH"), "title names the 15M side");
         CHECK(has(q("ov0"), lim), "ORDER row");
         CHECK(has(q("ov1"), DoubleToString(g.sl, DIGITS)), "SL row");
         CHECK(has(q("ov2"), DoubleToString(g.tp1, DIGITS)), "TP1 row");
         CHECK(g.tp2 > 0.0 ? has(q("ov3"), DoubleToString(g.tp2, DIGITS)) : has(q("ov3"), "no 2nd level"), "TP2 row");
         CHECK(has(q("ov4"), "1 : " + DoubleToString(g.rr1, 2)), "R:R row = the engine's R");
         CHECK(has(q("ov5"), "risks") || has(q("ov5"), "SKIP"), "lots for the risk % from the SL distance");
         CHECK(has(q("ov6"), "not filled by"), "validity row");
         CHECK(has(q("qt4"), DoubleToString(g.rr1, 2) + "R") && has(q("qt4"), "NEED 1.5R"), "reward answer shows the number and the bar");
         CHECK(has(q("next"), "type " + lim) && has(q("next"), "SL " + DoubleToString(g.sl, DIGITS)) &&
               has(q("next"), "TP " + DoubleToString(g.tp1, DIGITS)), "NEXT: what to type");
         CHECK(fprice("PL_E") == g.entry && fprice("PL_SL") == g.sl && fprice("PL_T1") == g.tp1, "plan lines on the chart at the plan's prices");
         CHECK(fint("PL_E", OBJPROP_RAY_RIGHT) == 1, "plan lines run ahead to the right");
         CHECK(SIM.objs.count("NBSP_F_PM_" + std::to_string(g.idx)) == 1, "a PLAN marker on the plan's candle");
         int tp, sl, un, op, to;
         NbFqTally(r.pl, r.npl, tp, sl, un, op, to);
         char m[64];
         std::snprintf(m, sizeof m, "%d plans  -  TP1 %d / SL %d", r.npl, tp, sl);
         CHECK(has(q("tally"), m), "history tally = the engine's count");
         std::printf("    %s at %s: %s SL %s TP1 %s (%.2fR) | %s\n", side == 0 ? "BUY " : "SELL",
                     TimeToString(now, TIME_DATE | TIME_MINUTES).c_str(), lim.c_str(), DoubleToString(g.sl, DIGITS).c_str(),
                     DoubleToString(g.tp1, DIGITS).c_str(), g.rr1, q("tally").c_str());
         OnDeinit(0);
         CHECK(countPrefix("NBSP_Q_") == 0 && countPrefix("NBSP_F_") == 0, "OnDeinit removes the table and its chart objects");
      }
   }
   end("Q2");

   begin("Q3 big SUPPORT / RESISTANCE lines + zones drawn ahead, with BREAKOUT / BREAKDOWN meaning in words");
   {
      int done = 0;
      for(int want : {1, -1})
      {
         long long now = findNow(mk, [want](const Ref &r) { return r.b.trend == want && r.b.sup > 0.0 && r.b.res > 0.0 && r.b.zone > 0.0; });
         CHECK(now > 0, "fixture has a moment with both levels for this trend");
         if(now == 0) continue;
         Ref r;
         reference(mk, now, r);
         load(mk, SYM, BASE, QUOTE);
         SIM.now = now;
         start();
         long long lastT = r.s5.t.back();
         CHECK(fprice("RES") == r.b.res && fprice("SUP") == r.b.sup, "big lines at the engine's nearest resistance / support");
         CHECK(fint("RES", OBJPROP_WIDTH) == 3 && fint("SUP", OBJPROP_WIDTH) == 3, "big = width 3");
         CHECK(fint("RES", OBJPROP_RAY_RIGHT) == 1 && fint("SUP", OBJPROP_RAY_RIGHT) == 1, "they run to the right edge (ahead of price)");
         CHECK(SIM.objs["NBSP_F_RES_Z"].i[OBJPROP_TIME * 100 + 1] > lastT + 3600 && SIM.objs["NBSP_F_SUP_Z"].i[OBJPROP_TIME * 100 + 1] > lastT + 3600,
               "zones reach into the future (drawn before price gets there)");
         CHECK(SIM.objs["NBSP_F_RES_Z"].type == OBJ_RECTANGLE && SIM.objs["NBSP_F_RES_Z"].i[OBJPROP_FILL] == 1, "zones are filled rectangles");
         double zr = SIM.objs["NBSP_F_RES_Z"].d[OBJPROP_PRICE * 100 + 1] - SIM.objs["NBSP_F_RES_Z"].d[OBJPROP_PRICE * 100 + 0];
         CHECK(std::fabs(zr - 2.0 * r.b.zone) < TICK, "zone height = 2 x (0.25 x 15M ATR)");
         CHECK(has(ftxt("RES_T"), "RESISTANCE") && has(ftxt("RES_T"), DoubleToString(r.b.res, DIGITS)), "resistance label: word + price");
         CHECK(has(ftxt("SUP_T"), "SUPPORT") && has(ftxt("SUP_T"), DoubleToString(r.b.sup, DIGITS)), "support label: word + price");
         if(want > 0)
         {
            CHECK(has(ftxt("RES_H"), "BREAKOUT") && has(ftxt("RES_H"), "possible BUY"), "bull 15M: resistance says BREAKOUT = possible BUY");
            CHECK(has(ftxt("SUP_H"), "possible BUY") && has(SIM.objs["NBSP_F_SUP_H"].s[OBJPROP_TOOLTIP], "BREAKDOWN"),
                  "bull 15M: support says sweep = possible BUY; hover: a BREAKDOWN is against the trend");
         }
         else
         {
            CHECK(has(ftxt("SUP_H"), "BREAKDOWN") && has(ftxt("SUP_H"), "possible SELL"), "bear 15M: support says BREAKDOWN = possible SELL");
            CHECK(has(ftxt("RES_H"), "possible SELL") && has(SIM.objs["NBSP_F_RES_H"].s[OBJPROP_TOOLTIP], "BREAKOUT"),
                  "bear 15M: resistance says sweep = possible SELL; hover: a BREAKOUT is against the trend");
         }
         CHECK(has(ftxt("MID_T"), "MIDDLE - NO ENTRY HERE"), "the middle between them is marked NO ENTRY");
         CHECK(has(q("lv"), "SUPPORT " + DoubleToString(r.b.sup, DIGITS)) && has(q("lv"), "RESISTANCE " + DoubleToString(r.b.res, DIGITS)),
               "the table's level row names the same two prices");
         OnDeinit(0);
         done++;
      }
      // a BREAKOUT / BREAKDOWN marker appears on the candle that closed through a level
      long long nb = findNow(mk, [](const Ref &r) {
         int n = r.s5.n - 1;
         return r.b.sup > 0.0 && NbFqCross(r.s5.c, n, InpFqWindowBars, r.b.sup, 1) >= 0;
      });
      CHECK(nb > 0, "fixture has a close up through what is now support");
      if(nb > 0)
      {
         Ref r;
         reference(mk, nb, r);
         int j = NbFqCross(r.s5.c, r.s5.n - 1, InpFqWindowBars, r.b.sup, 1);
         load(mk, SYM, BASE, QUOTE);
         SIM.now = nb;
         start();
         CHECK(has(ftxt("BO"), "BREAKOUT") && SIM.objs["NBSP_F_BO"].i[OBJPROP_TIME] == r.s5.t[(size_t)j], "BREAKOUT marker on that exact candle");
         CHECK(has(ftxt("BO"), r.b.trend > 0 ? "(with 15M)" : "(against 15M - no trade)"), "it says whether it is with the 15M trend");
         OnDeinit(0);
      }
   }
   end("Q3");

   begin("Q4 SETTING UP / WATCH / SKIP render their own words");
   {
      long long ns = findNow(mk, [](const Ref &r) { return r.b.status == NB_FQ_SETUP; });
      long long nw = findNow(mk, [](const Ref &r) { return r.b.status == NB_FQ_WATCH && r.b.why == NB_FW_MIDDLE && r.b.trend != 0; });
      long long nk = findNow(mk, [](const Ref &r) { return r.b.status == NB_FQ_SKIP && r.b.why == NB_FW_LOW_RR; });
      CHECK(ns > 0 && nw > 0 && nk > 0, "fixture has SETUP, WATCH-middle and SKIP-low-R moments");
      if(ns > 0)
      {
         Ref r;
         reference(mk, ns, r);
         load(mk, SYM, BASE, QUOTE); SIM.now = ns; start();
         CHECK(has(q("status"), "SETTING UP"), "banner SETTING UP");
         CHECK(q("qa2") == "YES" && q("qa3") == "NO", "liquidity YES, confirmation NO");
         CHECK(has(q("qt3"), "WAIT: 5M CLOSE") && has(q("qt3"), DoubleToString(r.b.trig, DIGITS)), "confirmation row names the trigger price");
         CHECK(has(q("next"), "wait for a 5M candle to CLOSE") && has(q("next"), DoubleToString(r.b.level, DIGITS)), "NEXT: close beyond the trigger, then the limit");
         CHECK(countPrefix("NBSP_F_PL_") == 0, "no plan lines before READY");
         CHECK(has(ftxt("SW"), "SWEEP"), "the sweep is marked on the chart");
         OnDeinit(0);
      }
      if(nw > 0)
      {
         load(mk, SYM, BASE, QUOTE); SIM.now = nw; start();
         CHECK(has(q("status"), "WATCH") && has(q("status"), "MIDDLE"), "banner WATCH - middle");
         CHECK(q("qa1") == "NO" && has(q("qt1"), "MIDDLE:") && has(q("qt1"), "ATR"), "location NO with the distances in ATR");
         CHECK(has(q("next"), "NEXT: wait."), "NEXT: wait, with the two prices");
         CHECK(q("ov0") == "---", "no order");
         OnDeinit(0);
      }
      if(nk > 0)
      {
         Ref r;
         reference(mk, nk, r);
         load(mk, SYM, BASE, QUOTE); SIM.now = nk; start();
         CHECK(has(q("status"), "SKIP") && has(q("status"), "ONLY " + DoubleToString(r.b.rr1, 2) + "R TO TP1"), "banner SKIP with the real R");
         CHECK(q("qa4") == "NO", "reward NO");
         CHECK(has(q("ov6"), "not a trade"), "the numbers are shown, marked not a trade");
         CHECK(countPrefix("NBSP_F_PL_") == 0, "no plan lines for a SKIP");
         OnDeinit(0);
      }
   }
   end("Q4");

   begin("Q5 stale data -> NO TRADE, even when the last closed bar was READY");
   {
      if(nReadyB > 0)
      {
         Market cut = mk;
         // history ends with the READY bar plus the candle after it, which
         // the terminal sees as the (dead) forming bar
         cut.m5.erase(std::remove_if(cut.m5.begin(), cut.m5.end(), [&](const SBar &b) { return b.t > nReadyB - 20; }), cut.m5.end());
         cut.m15 = agg(cut.m5, 900);
         load(cut, SYM, BASE, QUOTE);
         SIM.now = nReadyB + 600;   // no tick for 10 minutes (limit 120 s)
         start();
         CHECK(g_ready && !g_fq.empty() && g_fq.back().status == NB_FQ_READY,
               "the engine's last closed bar IS READY - so only the freshness gate can hide it");
         CHECK(has(ptxt("vd7"), "NO RECENT TICK"), "main panel data clock: stale");
         CHECK(has(q("status"), "NO TRADE") && has(q("status"), "DATA STALE") && !has(q("status"), "READY"), "table: NO TRADE - DATA STALE");
         bool dashes = true;
         for(int k = 0; k < 5; k++) dashes = dashes && q("qa" + std::to_string(k)) == "---";
         CHECK(dashes && q("ov0") == "---", "no answers, no order on stale data");
         CHECK(countPrefix("NBSP_F_PL_") == 0, "no live plan lines on the chart");
         CHECK(has(q("next"), "stale data is never a plan"), "NEXT says why");
         OnDeinit(0);
      }
   }
   end("Q5");

   begin("Q6 unsupported symbol / missing history -> no plan, no drawing");
   {
      load(mk, (NB_MARKET == NB_MKT_CRYPTO) ? "EURUSD" : "BTCUSD", (NB_MARKET == NB_MKT_CRYPTO) ? "EUR" : "BTC", "USD");
      SIM.now = mk.m5[3000].t + 20;
      start();
      CHECK(has(q("status"), ONLY) && countPrefix("NBSP_F_") == 0, "market-only text, nothing drawn");
      OnDeinit(0);
      load(mk, SYM, BASE, QUOTE);
      SIM.now = mk.m5[4000].t + 20;
      SIM.copyFail = true;
      start();
      CHECK(has(q("status"), "MISSING DATA") && countPrefix("NBSP_F_") == 0, "history unavailable: MISSING DATA, nothing drawn");
      SIM.copyFail = false;
      OnTimer();
      CHECK(!has(q("status"), "MISSING DATA") && countPrefix("NBSP_F_") > 0, "recovers once history loads");
      OnDeinit(0);
   }
   end("Q6");

   begin("Q7 no repaint through the terminal + restart identical");
   {
      if(nReadyB > 0)
      {
         load(mk, SYM, BASE, QUOTE); SIM.now = nReadyB; start();
         auto tq = snapPrefix("NBSP_Q_"), tf = snapPrefix("NBSP_F_");
         OnDeinit(0);
         start();
         CHECK(sameObjs(tq, snapPrefix("NBSP_Q_")) && sameObjs(tf, snapPrefix("NBSP_F_")), "restart: table and drawing identical");
         OnDeinit(0);
         load(mk, SYM, BASE, QUOTE); SIM.now = nReadyB;
         for(auto *ser : {&SIM.m5, &SIM.m15})
            for(auto &b : *ser)
               if(b.time <= nReadyB && b.time + (ser == &SIM.m5 ? 300 : 900) > nReadyB) { b.low -= PRICE * 0.05; b.high += PRICE * 0.05; b.close -= PRICE * 0.04; }
         start();
         auto tq2 = snapPrefix("NBSP_Q_"), tf2 = snapPrefix("NBSP_F_");
         // the price line of the title row reads the live bid only through NbPx in the main panel; the table never does
         CHECK(sameObjs(tq, tq2), "a forming crash candle changes nothing in the table");
         CHECK(sameObjs(tf, tf2), "... and nothing on the chart drawing");
         OnDeinit(0);
      }
   }
   end("Q7");

   begin("Q8 the MAIN PANEL row repeats the main panel's own answer");
   {
      long long nm = findNow(mk, [](const Ref &r) { return r.state == NB_BUY; });
      long long nw = findNow(mk, [](const Ref &r) { return r.state == NB_WAIT && r.reasons != 0; });
      if(nm > 0)
      {
         load(mk, SYM, BASE, QUOTE); SIM.now = nm; start();
         CHECK(has(ptxt("state"), "CLICK BUY") && has(q("main"), "MAIN PANEL (NRTR rules): CLICK BUY"), "CLICK BUY on both");
         OnDeinit(0);
      }
      if(nw > 0)
      {
         Ref r;
         reference(mk, nw, r);
         load(mk, SYM, BASE, QUOTE); SIM.now = nw; start();
         CHECK(has(q("main"), "WAIT - " + NbReasonAt(r.reasons, 0)), "WAIT with the main panel's first reason");
         OnDeinit(0);
      }
      CHECK(nm > 0 && nw > 0, "fixture has both moments");
   }
   end("Q8");

   std::printf("\nFIVE-QUESTION INDICATOR TESTS (%s): %d checks passed, %d failed\n", NB_MARKET == NB_MKT_CRYPTO ? "crypto" : "forex", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
