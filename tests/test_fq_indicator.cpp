// Whole-indicator tests for the v1.05 FIVE-QUESTION PLAN table of the twins:
// the complete .mq5 (translated syntax-only) runs against the simulated MT5
// terminal; the table (NBSP_Q_) and its chart drawing (NBSP_F_) are read back
// from the objects the indicator created and compared with an independent
// run of the engine functions on the same bars.
#include "../tests/mt5_sim.h"
#if NB_TEST_MARKET == 0
#include "full.inc"
#define PFX "NBLP_"
#elif NB_TEST_MARKET == 2
#include "full_forex.inc"
#define PFX "NBSP_"
#else
#include "full_crypto.inc"
#define PFX "NBSP_"
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
#if NB_TEST_MARKET == 0
static const char *SYM = "XAUUSD", *BASE = "XAU", *QUOTE = "USD";
static const int DIGITS = 2;
static const double TICK = 0.01, PRICE = 2400.0, VOL = 0.8;
static const char *ONLY = "GOLD / SILVER ONLY";
static const char *OTHER = "EURUSD", *OTHERB = "EUR";
static const char *MKT = "METALS";
#elif NB_TEST_MARKET == 2
static const char *SYM = "EURUSD", *BASE = "EUR", *QUOTE = "USD";
static const int DIGITS = 5;
static const double TICK = 0.00001, PRICE = 1.08, VOL = 0.0004;
static const char *ONLY = "FOREX ONLY";
static const char *OTHER = "BTCUSD", *OTHERB = "BTC";
static const char *MKT = "FOREX";
#else
static const char *SYM = "BTCUSD", *BASE = "BTC", *QUOTE = "USD";
static const int DIGITS = 2;
static const double TICK = 0.01, PRICE = 60000.0, VOL = 40.0;
static const char *ONLY = "CRYPTO ONLY";
static const char *OTHER = "EURUSD", *OTHERB = "EUR";
static const char *MKT = "CRYPTO";
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
static std::string q(const std::string &id) { return SIM.objs.count(PFX "Q_" + id) ? SIM.objs[PFX "Q_" + id].s[OBJPROP_TEXT] : "<missing>"; }
static std::string ptxt(const std::string &id) { return SIM.objs.count(PFX "P_" + id) ? SIM.objs[PFX "P_" + id].s[OBJPROP_TEXT] : "<missing>"; }
static bool has(const std::string &s, const std::string &sub) { return s.find(sub) != std::string::npos; }
static int countPrefix(const std::string &p)
{
   int n = 0;
   for(auto &kv : SIM.objs) if(kv.first.compare(0, p.size(), p) == 0) n++;
   return n;
}
static std::string ftxt(const std::string &id) { return SIM.objs.count(PFX "F_" + id) ? SIM.objs[PFX "F_" + id].s[OBJPROP_TEXT] : "<missing>"; }
static double fprice(const std::string &id) { return SIM.objs.count(PFX "F_" + id) ? SIM.objs[PFX "F_" + id].d[OBJPROP_PRICE * 100 + 0] : -1.0; }
static long long fint(const std::string &id, int prop) { return SIM.objs.count(PFX "F_" + id) ? SIM.objs[PFX "F_" + id].i[prop] : -999; }

#if NB_TEST_MARKET == 0
static bool g_refSilver = false;   // metals file: reference run with the silver settings
#endif
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
#if NB_TEST_MARKET != 0
   NbSessCfg S;
   S.clockMode = NB_CLK_AUTO; S.clockOk = true; S.offset = 3 * 3600; S.manualOpenSec = 0;
   S.preHours = InpPreNyRangeHours; S.winMin = InpNyWindowMinutes; S.minRangeBars = InpMinRangeBars; S.pauseFlow = InpNyPauseFlow;
#endif
   NbFqCfg C;
   C.zoneAtr = InpFqZoneAtr; C.window = InpFqWindowBars; C.minRR = InpFqMinRR; C.validBars = InpFqValidBars;
   C.openMax = NB_FQ_OPEN_MAX; C.asiaStart = InpFqAsiaStartUtc; C.asiaEnd = InpFqAsiaEndUtc;
   C.lonStart = InpFqLondonStartUtc; C.lonEnd = InpFqLondonEndUtc; C.clockOk = true; C.offset = 3 * 3600;
   C.slBufMult = 1.0; C.confirmAtr = 0.0;
#if NB_TEST_MARKET == 0
   if(g_refSilver) { C.slBufMult = InpFqSilverSlMult; C.confirmAtr = InpFqSilverConfirmAtr; P.tick = 0.001; P.digits = 3; }
#endif
   long long anchor = (now / 86400) * 86400 - (long long)InpHistoryDays * 86400;
   std::vector<SBar> v5, v15;
   for(const SBar &x : m.m5) if(x.t >= anchor && x.t + 300 <= now) v5.push_back(x);
   for(const SBar &x : m.m15) if(x.t >= anchor && x.t + 900 <= now) v15.push_back(x);
   NbSeriesResize(r.s5, (int)v5.size()); r.s5.sec = 300;
   NbSeriesResize(r.s15, (int)v15.size()); r.s15.sec = 900;
   for(size_t i = 0; i < v5.size(); i++) { r.s5.t[i] = v5[i].t; r.s5.o[i] = v5[i].o; r.s5.h[i] = v5[i].h; r.s5.l[i] = v5[i].l; r.s5.c[i] = v5[i].c; }
   for(size_t i = 0; i < v15.size(); i++) { r.s15.t[i] = v15[i].t; r.s15.o[i] = v15[i].o; r.s15.h[i] = v15[i].h; r.s15.l[i] = v15[i].l; r.s15.c[i] = v15[i].c; }
   NbRun15(r.s15, r.p15, P);
#if NB_TEST_MARKET == 0
   NbRun5(r.s5, r.p5, r.s15, true, P, r.sig, r.nSig);
#else
   NbRun5(r.s5, r.p5, r.s15, true, P, S, r.sig, r.nSig);
#endif
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
   std::printf("file under test: %s on %s\n", MKT, SYM);
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
         SimObj &bg = SIM.objs[PFX "Q_bg"];
         SimObj &pbg = SIM.objs[PFX "P_bg"];
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
            if(kv.first.compare(0, 7, PFX "Q_") != 0 || kv.second.type != OBJ_LABEL) continue;
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
         CHECK((has(q("ov5"), " USD = ") && has(q("ov5"), "%)")) || has(q("ov5"), "SKIP"), "lots for the risk % from the SL distance");
         CHECK(has(q("ov6"), "not filled by"), "validity row");
         CHECK(has(q("qt4"), DoubleToString(g.rr1, 2) + "R") && has(q("qt4"), "NEED 1.5R"), "reward answer shows the number and the bar");
         CHECK(has(q("next1"), "type " + lim) && has(q("next1"), "SL " + DoubleToString(g.sl, DIGITS)) &&
               has(q("next1"), "TP " + DoubleToString(g.tp1, DIGITS)), "NEXT: what to type");
         CHECK(has(q("next2"), "Not filled by") && has(q("next2"), "No chasing"), "NEXT line 2: when to cancel");
         CHECK(fprice("PL_E") == g.entry && fprice("PL_SL") == g.sl && fprice("PL_T1") == g.tp1, "plan lines on the chart at the plan's prices");
         CHECK(fint("PL_E", OBJPROP_RAY_RIGHT) == 1, "plan lines run ahead to the right");
         CHECK(SIM.objs.count(PFX "F_PM_" + std::to_string(g.idx)) == 1, "a PLAN marker on the plan's candle");
         int tp, sl, un, op, to;
         NbFqTally(r.pl, r.npl, tp, sl, un, op, to);
         char m[96];
         std::snprintf(m, sizeof m, "%d plans - TP1 %d / SL %d / not filled %d", r.npl, tp, sl, un);
         CHECK(has(q("tallyL"), m), "history tally = the engine's count");
         double net = NbFqNetR(r.pl, r.npl);
         std::string netS = std::string("NET ") + (net >= 0 ? "+" : "") + DoubleToString(net, 1) + "R";
         CHECK(has(q("tallyR"), netS), "NET R = the engine's sum (TP1 = +R, SL = -1)");
         std::printf("    %s at %s: %s SL %s TP1 %s (%.2fR) | %s\n", side == 0 ? "BUY " : "SELL",
                     TimeToString(now, TIME_DATE | TIME_MINUTES).c_str(), lim.c_str(), DoubleToString(g.sl, DIGITS).c_str(),
                     DoubleToString(g.tp1, DIGITS).c_str(), g.rr1, (q("tallyL") + " | " + q("tallyR")).c_str());
         OnDeinit(0);
         CHECK(countPrefix(PFX "Q_") == 0 && countPrefix(PFX "F_") == 0, "OnDeinit removes the table and its chart objects");
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
         CHECK(SIM.objs[PFX "F_RES_Z"].i[OBJPROP_TIME * 100 + 1] > lastT + 3600 && SIM.objs[PFX "F_SUP_Z"].i[OBJPROP_TIME * 100 + 1] > lastT + 3600,
               "zones reach into the future (drawn before price gets there)");
         CHECK(SIM.objs[PFX "F_RES_Z"].type == OBJ_RECTANGLE && SIM.objs[PFX "F_RES_Z"].i[OBJPROP_FILL] == 1, "zones are filled rectangles");
         double zr = SIM.objs[PFX "F_RES_Z"].d[OBJPROP_PRICE * 100 + 1] - SIM.objs[PFX "F_RES_Z"].d[OBJPROP_PRICE * 100 + 0];
         CHECK(std::fabs(zr - 2.0 * r.b.zone) < TICK, "zone height = 2 x (0.25 x 15M ATR)");
         CHECK(has(ftxt("RES_T"), "RESISTANCE") && has(ftxt("RES_T"), DoubleToString(r.b.res, DIGITS)), "resistance label: word + price");
         CHECK(has(ftxt("SUP_T"), "SUPPORT") && has(ftxt("SUP_T"), DoubleToString(r.b.sup, DIGITS)), "support label: word + price");
         if(want > 0)
         {
            CHECK(has(ftxt("RES_H"), "BREAKOUT") && has(ftxt("RES_H"), "possible BUY"), "bull 15M: resistance says BREAKOUT = possible BUY");
            CHECK(has(ftxt("SUP_H"), "possible BUY") && has(SIM.objs[PFX "F_SUP_H"].s[OBJPROP_TOOLTIP], "BREAKDOWN"),
                  "bull 15M: support says sweep = possible BUY; hover: a BREAKDOWN is against the trend");
         }
         else
         {
            CHECK(has(ftxt("SUP_H"), "BREAKDOWN") && has(ftxt("SUP_H"), "possible SELL"), "bear 15M: support says BREAKDOWN = possible SELL");
            CHECK(has(ftxt("RES_H"), "possible SELL") && has(SIM.objs[PFX "F_RES_H"].s[OBJPROP_TOOLTIP], "BREAKOUT"),
                  "bear 15M: resistance says sweep = possible SELL; hover: a BREAKOUT is against the trend");
         }
         CHECK(has(ftxt("MID_T"), "MIDDLE - NO ENTRY HERE"), "the middle between them is marked NO ENTRY");
         CHECK(has(q("mapL"), "PDH " + (r.b.pdh > 0 ? DoubleToString(r.b.pdh, DIGITS) : std::string("---"))) &&
               has(q("mapR"), "ASIA " + (r.b.ash > 0 ? DoubleToString(r.b.ash, DIGITS) : std::string("---"))) &&
               has(q("mapR"), "LDN " + (r.b.loh > 0 ? DoubleToString(r.b.loh, DIGITS) : std::string("---"))),
               "15M map row: PDH, Asia and London values = the engine's (clock from two witnesses, UTC+3)");
         CHECK(has(q("lvL"), "SUPPORT " + DoubleToString(r.b.sup, DIGITS)) && has(q("lvR"), "RESISTANCE " + DoubleToString(r.b.res, DIGITS)),
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
         CHECK(has(ftxt("BO"), "BREAKOUT") && SIM.objs[PFX "F_BO"].i[OBJPROP_TIME] == r.s5.t[(size_t)j], "BREAKOUT marker on that exact candle");
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
         CHECK(has(q("next1"), "wait for a 5M candle to CLOSE") && has(q("next1"), DoubleToString(r.b.trig, DIGITS)) &&
               has(q("next2"), DoubleToString(r.b.level, DIGITS)), "NEXT: close beyond the trigger, then the limit at the level");
         CHECK(countPrefix(PFX "F_PL_") == 0, "no plan lines before READY");
         CHECK(has(ftxt("SW"), "SWEEP"), "the sweep is marked on the chart");
         OnDeinit(0);
      }
      if(nw > 0)
      {
         load(mk, SYM, BASE, QUOTE); SIM.now = nw; start();
         CHECK(has(q("status"), "WATCH") && has(q("status"), "MIDDLE"), "banner WATCH - middle");
         CHECK(q("qa1") == "NO" && has(q("qt1"), "MIDDLE:") && has(q("qt1"), "ATR"), "location NO with the distances in ATR");
         CHECK(has(q("next1"), "NEXT: wait.") && has(q("next2"), "idea 2"), "NEXT: wait, with the two prices");
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
         CHECK(countPrefix(PFX "F_PL_") == 0, "no plan lines for a SKIP");
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
         CHECK(countPrefix(PFX "F_PL_") == 0, "no live plan lines on the chart");
         CHECK(has(q("next1"), "stale data is never a plan"), "NEXT says why");
         OnDeinit(0);
      }
   }
   end("Q5");

   begin("Q6 unsupported symbol / missing history -> no plan, no drawing");
   {
      load(mk, OTHER, OTHERB, "USD");
      SIM.now = mk.m5[3000].t + 20;
      start();
      CHECK(has(q("status"), ONLY) && countPrefix(PFX "F_") == 0, "market-only text, nothing drawn");
      OnDeinit(0);
      load(mk, SYM, BASE, QUOTE);
      SIM.now = mk.m5[4000].t + 20;
      SIM.copyFail = true;
      start();
      CHECK(has(q("status"), "MISSING DATA") && countPrefix(PFX "F_") == 0, "history unavailable: MISSING DATA, nothing drawn");
      SIM.copyFail = false;
      OnTimer();
      CHECK(!has(q("status"), "MISSING DATA") && countPrefix(PFX "F_") > 0, "recovers once history loads");
      OnDeinit(0);
   }
   end("Q6");

   begin("Q7 no repaint through the terminal + restart identical");
   {
      if(nReadyB > 0)
      {
         load(mk, SYM, BASE, QUOTE); SIM.now = nReadyB; start();
         auto tq = snapPrefix(PFX "Q_"), tf = snapPrefix(PFX "F_");
         OnDeinit(0);
         start();
         CHECK(sameObjs(tq, snapPrefix(PFX "Q_")) && sameObjs(tf, snapPrefix(PFX "F_")), "restart: table and drawing identical");
         OnDeinit(0);
         load(mk, SYM, BASE, QUOTE); SIM.now = nReadyB;
         for(auto *ser : {&SIM.m5, &SIM.m15})
            for(auto &b : *ser)
               if(b.time <= nReadyB && b.time + (ser == &SIM.m5 ? 300 : 900) > nReadyB) { b.low -= PRICE * 0.05; b.high += PRICE * 0.05; b.close -= PRICE * 0.04; }
         start();
         auto tq2 = snapPrefix(PFX "Q_"), tf2 = snapPrefix(PFX "F_");
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
         CHECK(has(ptxt("state"), "CLICK BUY") && has(q("mainL"), "MAIN PANEL (NRTR rules): CLICK BUY"), "CLICK BUY on both");
         OnDeinit(0);
      }
      if(nw > 0)
      {
         Ref r;
         reference(mk, nw, r);
         load(mk, SYM, BASE, QUOTE); SIM.now = nw; start();
         CHECK(has(q("mainL"), "MAIN PANEL (NRTR rules): WAIT") && q("mainR") == NbReasonAt(r.reasons, 0), "WAIT with the main panel's first reason");
         OnDeinit(0);
      }
      CHECK(nm > 0 && nw > 0, "fixture has both moments");
   }
   end("Q8");

   begin("Q9 v1.06: no label over MT5's 63-character limit, markers behind the candles, table drawn after the markers");
   {
      // MT5 strings are UTF-16: count code points, not UTF-8 bytes
      auto cps = [](const std::string &u) { int n = 0; for(unsigned char ch : u) if((ch & 0xC0) != 0x80) n++; return n; };
      int moments = 0, texts = 0, over = 0, notBack = 0, notOnTop = 0;
      std::string worst;
      for(size_t k = 11 * 288; k + 1 < mk.m5.size(); k += 37)
      {
         for(int w : {1400, 1920})
         {
            load(mk, SYM, BASE, QUOTE);
            SIM.chartW = w;
            SIM.now = mk.m5[k].t + 320;
            start();
            // the order only matters after the next closed candle, when the
            // main panel's chart markers are deleted and created again
            SIM.now += 300;
            OnTimer();
            long long lastC = 0, firstQ = -1;
            for(auto &kv : SIM.objs)
            {
               const std::string &nm = kv.first;
               bool mine = nm.compare(0, 7, PFX "Q_") == 0 || nm.compare(0, 7, PFX "F_") == 0;
               if(nm.compare(0, 7, PFX "C_") == 0) lastC = std::max(lastC, SIM.seqOf[nm]);
               if(nm.compare(0, 7, PFX "Q_") == 0 && (firstQ < 0 || SIM.seqOf[nm] < firstQ)) firstQ = SIM.seqOf[nm];
               if(!mine || !kv.second.s.count(OBJPROP_TEXT)) continue;
               texts++;
               int n = cps(kv.second.s[OBJPROP_TEXT]);
               if(n > 63) { over++; if(worst.empty()) worst = nm + " (" + std::to_string(n) + "): " + kv.second.s[OBJPROP_TEXT]; }
               if(nm.compare(0, 7, PFX "F_") == 0 && kv.second.type == OBJ_TEXT && kv.second.i[OBJPROP_BACK] != 1) notBack++;
            }
            if(firstQ >= 0 && lastC > 0 && firstQ < lastC) notOnTop++;
            OnDeinit(0);
            moments++;
         }
      }
      char m[160];
      std::snprintf(m, sizeof m, "%d texts on %d chart moments: none longer than 63 characters", texts, moments);
      CHECK(texts > 2000 && over == 0, m);
      std::printf("    %s\n", m);
      if(over) std::printf("    first too long: %s\n", worst.c_str());
      CHECK(notBack == 0, "every chart text of the table's drawing is in the background (behind candles and panels)");
      CHECK(notOnTop == 0, "the table is created after the main panel's chart markers (drawn on top of them)");
   }
   end("Q9");

#if NB_TEST_MARKET == 0
   begin("Q10 SILVER on the metals panel: wider stop and stronger confirmation, shown on the table");
   {
      Market ms;
      ms.m5 = gen5m(11, 16 * 288, T0, 30.0, 0.001, 0.02);
      ms.m15 = agg(ms.m5, 900);
      g_refSilver = true;
      long long now = findNow(ms, [](const Ref &r) { return r.b.status == NB_FQ_READY && r.pl[(size_t)r.b.plan].idx == r.s5.n - 1 &&
                                                            r.pl[(size_t)r.b.plan].kind == NB_PK_SWEEP; });
      CHECK(now > 0, "silver fixture has a READY sweep moment (reference run with the silver settings)");
      if(now > 0)
      {
         Ref r;
         reference(ms, now, r);
         const NbFqPlan &g = r.pl[(size_t)r.b.plan];
         double expectSl = (g.dir > 0) ? NbRoundTick(g.ext - InpSlBufferAtr * InpFqSilverSlMult * r.s5.atr[(size_t)g.idx], 0.001, 3, -1)
                                       : NbRoundTick(g.ext + InpSlBufferAtr * InpFqSilverSlMult * r.s5.atr[(size_t)g.idx], 0.001, 3, 1);
         CHECK(std::fabs(g.sl - expectSl) < 1e-9, "engine SL = sweep extreme -/+ 0.10 x 5M ATR x 2.0 (silver stop)");
         SIM = SimState();
         SIM.sym = "XAGUSD"; SIM.base = "XAG"; SIM.profit = "USD"; SIM.digits = 3; SIM.tick = 0.001;
         SIM.tickValue = 5.0; SIM.volMin = 0.01; SIM.gmtOff = 3 * 3600;
         SIM.m5 = toRates(ms.m5); SIM.m15 = toRates(ms.m15);
         _Symbol = "XAGUSD";
         SIM.now = now;
         start();
         CHECK(has(q("title"), "SILVER  -  15M"), "title: SILVER");
         CHECK(has(q("status"), "READY") && has(q("status"), DoubleToString(g.entry, 3)), "READY with the silver engine's entry");
         CHECK(has(q("ov1"), DoubleToString(g.sl, 3)), "SL row = the wider silver stop");
         CHECK(q("footR") == "SILVER: stop x2.0, confirm +0.25 ATR", "the table says which silver settings are in force");
         std::printf("    silver READY at %s: %s  SL %s\n", TimeToString(now, TIME_DATE | TIME_MINUTES).c_str(), q("ov0").c_str(), q("ov1").c_str());
         OnDeinit(0);
      }
      g_refSilver = false;
      load(mk, SYM, BASE, QUOTE);
      SIM.now = nReadyB;
      start();
      CHECK(q("footR") == "A hypothesis until the count says otherwise.", "gold: plain rules, no silver note");
      OnDeinit(0);
   }
   end("Q10");
#endif

   std::printf("\nFIVE-QUESTION INDICATOR TESTS (%s): %d checks passed, %d failed\n", MKT, g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
