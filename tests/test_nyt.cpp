// v1.06 METALS: NY trap layer + decision ladder. The complete metals .mq5
// (translated syntax-only) runs here: hand-made NY trap cases on the engine
// functions (N*), then the whole indicator on a simulated terminal for
// XAUUSD and XAGUSD separately (L*), checking the user's ten points.
#include "../tests/mt5_sim.h"
#ifndef NYT_INC
#define NYT_INC "full.inc"
#endif
#include NYT_INC
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
static bool has(const std::string &s, const std::string &sub) { return s.find(sub) != std::string::npos; }
static bool onGrid(double x, double tick) { return std::fabs(x / tick - std::round(x / tick)) < 1e-6; }

static const long long D0 = 1788220800LL;   // 2026-09-01, a Tuesday (UTC midnight = broker midnight here)

//--------------------------------------------------------------- engine cases
static NbNytCfg ncfg(double slMult = 1.0, double confirm = 0.0)
{
   NbNytCfg N;
   N.openSec = 16 * 3600 + 1800; N.preHours = 4; N.winMin = 90; N.minBars = 12;
   N.slBufAtr = 0.10; N.slBufMult = slMult; N.confirmAtr = confirm; N.refAtr = 1.0;
   N.tp1R = 1.0; N.tp2R = 2.0; N.validBars = 6; N.tick = 0.01; N.digits = 2;
   return N;
}
struct Day
{
   NbSeries s;
   std::vector<NbNytBar> nt;
   Day() { NbSeriesResize(s, 0); s.sec = 300; }
};
static void bar(Day &d, long long t, double o, double h, double l, double c)
{
   int n = d.s.n;
   NbSeriesResize(d.s, n + 1);
   d.s.t[(size_t)n] = t; d.s.o[(size_t)n] = o; d.s.h[(size_t)n] = h; d.s.l[(size_t)n] = l; d.s.c[(size_t)n] = c;
}
// 12:00 .. 16:25 flat bars: range 12:30-16:25 = 48 bars, H 100.50 / L 99.50
static void flat(Day &d, long long day0, int preBars = 48)
{
   bar(d, day0 + 12 * 3600, 100.0, 100.2, 99.8, 100.1);            // 12:00 before the range
   bar(d, day0 + 12 * 3600 + 900, 100.0, 100.2, 99.8, 100.1);      // 12:15
   long long start = day0 + 16 * 3600 + 1800 - (long long)preBars * 300;
   for(int k = 0; k < preBars; k++)
      bar(d, start + (long long)k * 300, 100.0, 100.5, 99.5, (k % 2) ? 100.2 : 99.8);
}
static long long ny(long long day0, int k) { return day0 + 16 * 3600 + 1800 + (long long)k * 300; }
static void runDay(Day &d, const NbNytCfg &N, bool lastClosed = true)
{
   ArrayResize(d.s.atr, d.s.n);
   ArrayInitialize(d.s.atr, 1.0);
   NbRunNyt(d.s, lastClosed, N, d.nt);
}
static int idxAt(const Day &d, long long t) { for(int i = 0; i < d.s.n; i++) if(d.s.t[(size_t)i] == t) return i; return -1; }

//--------------------------------------------------------------- terminal
static std::vector<MqlRates> toRates(const std::vector<SBar> &v)
{
   std::vector<MqlRates> r;
   for(const SBar &b : v) r.push_back({b.t, b.o, b.h, b.l, b.c, 100, 0, 0});
   return r;
}
struct Metal
{
   const char *sym, *base;
   int digits;
   double tick, tickValue, price, vol;
   bool silver;
   std::vector<SBar> m5, m15;
};
static Metal makeMetal(bool silver, uint64_t seed)
{
   Metal m;
   m.silver = silver;
   m.sym = silver ? "XAGUSD" : "XAUUSD";
   m.base = silver ? "XAG" : "XAU";
   m.digits = silver ? 3 : 2;
   m.tick = silver ? 0.001 : 0.01;
   m.tickValue = silver ? 5.0 : 1.0;      // 1.00 lot: silver 5000 oz x 0.001, gold 100 oz x 0.01
   m.price = silver ? 30.0 : 2400.0;
   m.vol = silver ? 0.02 : 0.8;
   m.m5 = gen5m(seed, 16 * 288, D0, m.price, m.tick, m.vol);
   m.m15 = agg(m.m5, 900);
   return m;
}
static void load(const Metal &m)
{
   SIM = SimState();
   SIM.sym = m.sym; SIM.base = m.base; SIM.profit = "USD"; SIM.digits = m.digits; SIM.tick = m.tick;
   SIM.tickValue = m.tickValue; SIM.volMin = 0.01; SIM.gmtOff = 3 * 3600; SIM.contract = m.silver ? 5000.0 : 100.0;
   SIM.m5 = toRates(m.m5); SIM.m15 = toRates(m.m15);
   _Symbol = m.sym;
   _Period = PERIOD_M5;
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
static std::string L(const std::string &id) { return SIM.objs.count("NBLP_L_" + id) ? SIM.objs["NBLP_L_" + id].s[OBJPROP_TEXT] : "<missing>"; }
static std::string P(const std::string &id) { return SIM.objs.count("NBLP_P_" + id) ? SIM.objs["NBLP_P_" + id].s[OBJPROP_TEXT] : "<missing>"; }
static double NP(const std::string &id) { return SIM.objs.count("NBLP_N_" + id) ? SIM.objs["NBLP_N_" + id].d[OBJPROP_PRICE * 100 + 0] : -1.0; }
static std::string NT(const std::string &id) { return SIM.objs.count("NBLP_N_" + id) ? SIM.objs["NBLP_N_" + id].s[OBJPROP_TEXT] : "<missing>"; }
static int countPrefix(const std::string &p)
{
   int n = 0;
   for(auto &kv : SIM.objs) if(kv.first.compare(0, p.size(), p) == 0) n++;
   return n;
}
static std::string px(double v, int d) { return DoubleToString(v, d); }

// independent run of the same engine functions on the bars the terminal would load
struct Ref
{
   NbSeries s5, s15;
   std::vector<NbPivot> p15, p5;
   std::vector<NbSignal> sig;
   int nSig = 0;
   std::vector<NbNytBar> nt;
   NbNytBar b;
   int boss = 0, state = 0;
};
static void reference(const Metal &m, long long now, Ref &r)
{
   NbParams Pp;
   Pp.atrPeriod = InpNrtrAtrPeriod; Pp.nrtrMult = InpNrtrMultiplier; Pp.emaPeriod = InpEmaPeriod; Pp.swing = InpSwingStrength;
   Pp.slBufAtr = InpSlBufferAtr; Pp.tp1R = InpTp1R; Pp.tp2R = InpTp2R; Pp.validBars = InpSignalValidBars; Pp.tick = m.tick; Pp.digits = m.digits;
   NbNytCfg N;
   N.openSec = NbParseHHMM(InpNyOpenTime); N.preHours = InpNytRangeHours; N.winMin = InpNytWindowMin; N.minBars = InpNytMinBars;
   N.slBufAtr = InpSlBufferAtr; N.slBufMult = m.silver ? InpFqSilverSlMult : 1.0; N.confirmAtr = m.silver ? InpFqSilverConfirmAtr : 0.0;
   N.refAtr = InpNytRefAtr; N.tp1R = InpTp1R; N.tp2R = InpTp2R; N.validBars = InpSignalValidBars; N.tick = m.tick; N.digits = m.digits;
   long long anchor = (now / 86400) * 86400 - (long long)InpHistoryDays * 86400;
   std::vector<SBar> v5, v15;
   for(const SBar &x : m.m5) if(x.t >= anchor && x.t + 300 <= now) v5.push_back(x);
   for(const SBar &x : m.m15) if(x.t >= anchor && x.t + 900 <= now) v15.push_back(x);
   NbSeriesResize(r.s5, (int)v5.size()); r.s5.sec = 300;
   NbSeriesResize(r.s15, (int)v15.size()); r.s15.sec = 900;
   for(size_t i = 0; i < v5.size(); i++) { r.s5.t[i] = v5[i].t; r.s5.o[i] = v5[i].o; r.s5.h[i] = v5[i].h; r.s5.l[i] = v5[i].l; r.s5.c[i] = v5[i].c; }
   for(size_t i = 0; i < v15.size(); i++) { r.s15.t[i] = v15[i].t; r.s15.o[i] = v15[i].o; r.s15.h[i] = v15[i].h; r.s15.l[i] = v15[i].l; r.s15.c[i] = v15[i].c; }
   NbRun15(r.s15, r.p15, Pp);
   NbRun5(r.s5, r.p5, r.s15, true, Pp, r.sig, r.nSig);
   NbRunNyt(r.s5, true, N, r.nt);
   r.b = r.nt.back();
   r.boss = r.s15.mode.back();
   r.state = r.s5.state.back();
}
template <class F> static long long findNow(const Metal &m, F pred, size_t from = 11 * 288, size_t step = 1)
{
   for(size_t i = from; i + 1 < m.m5.size(); i += step)
   {
      long long now = m.m5[i].t + 300 + 20;
      Ref r;
      reference(m, now, r);
      if(pred(r)) return now;
   }
   return 0;
}
static int cps(const std::string &u) { int n = 0; for(unsigned char ch : u) if((ch & 0xC0) != 0x80) n++; return n; }

int main()
{
#ifdef NYT_SIMPLE
   // built from a copy of the source with InpSimpleView = true (run_tests.sh step 5e)
   for(int mi = 0; mi < 2; mi++)
   {
      Metal m = makeMetal(mi == 1, mi == 1 ? 11 : 7);
      begin(mi ? "S1 XAGUSD simple view: ladder + chart only" : "S1 XAUUSD simple view: ladder + chart only");
      load(m);
      SIM.now = m.m5[12 * 288 + 50].t + 320;
      CHECK(start() == INIT_SUCCEEDED, "init ok");
      CHECK(countPrefix("NBLP_P_") == 0 && countPrefix("NBLP_Q_") == 0, "main panel and 5-question table hidden");
      CHECK(countPrefix("NBLP_L_") > 20 && has(L("h1"), "15M = BOSS") && L("act") != "<missing>", "the ladder is drawn");
      CHECK(countPrefix("NBLP_C_") > 0 || countPrefix("NBLP_N_") > 0, "chart objects still drawn");
      OnTimer();
      CHECK(countPrefix("NBLP_P_") == 0 && countPrefix("NBLP_Q_") == 0, "still hidden after a timer refresh");
      OnDeinit(0);
      CHECK(countPrefix("NBLP_") == 0, "OnDeinit removes everything");
      end(mi ? "S1 XAGUSD" : "S1 XAUUSD");
   }
   std::printf("\nSIMPLE VIEW TESTS (metals): %d checks passed, %d failed\n", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
#endif
   //============================================================ engine
   begin("N1 SELL trap: sweep, then a bearish 5M close back below the range high = TRIGGERED with exact levels");
   {
      Day d;
      flat(d, D0);
      bar(d, ny(D0, 0), 100.2, 100.9, 100.1, 100.7);    // 16:30 sweeps above 100.50, closes above: VALID
      bar(d, ny(D0, 1), 100.7, 100.95, 100.2, 100.3);   // 16:35 bearish close back below: TRIGGERED
      bar(d, ny(D0, 2), 100.3, 100.4, 99.5, 99.6);      // 16:40 low 99.50 <= TP1 99.55
      runDay(d, ncfg());
      int i0 = idxAt(d, ny(D0, 0)), i1 = i0 + 1, i2 = i0 + 2;
      CHECK(d.nt[0].phase == NB_NTP_BEFORE && d.nt[0].sell.state == NB_NT_WAIT && d.nt[0].sell.why == NB_NTW_BEFORE, "12:00: before the range = WAIT");
      CHECK(d.nt[5].phase == NB_NTP_PRE && d.nt[5].sell.why == NB_NTW_BUILDING, "range bars: WAIT, building");
      CHECK(near(d.nt[i0 - 1].rh, 100.5) && near(d.nt[i0 - 1].rl, 99.5) && d.nt[i0 - 1].rn == 48, "range 12:30-16:25: H 100.50 / L 99.50, 48 bars");
      CHECK(d.nt[i0].phase == NB_NTP_NY && d.nt[i0].sell.state == NB_NT_VALID && near(d.nt[i0].sell.sweep, 100.9), "16:30: swept to 100.90 = VALID");
      CHECK(d.nt[i0].sell.estimate && near(d.nt[i0].sell.entry, 100.5) && near(d.nt[i0].sell.sl, 101.0), "VALID refs: entry ref = the level, SL = sweep 100.90 + 0.10");
      CHECK(d.nt[i0].buy.state == NB_NT_WAIT && d.nt[i0].buy.why == NB_NTW_NOT_SWEPT, "buy side: not swept = WAIT");
      const NbNytSide &s = d.nt[i1].sell;
      CHECK(s.state == NB_NT_TRIGGERED && s.why == NB_NTW_ACTIVE && s.trigIdx == i1 && !s.estimate, "16:35: bearish close 100.30 < 100.50 = TRIGGERED");
      CHECK(near(s.entry, 100.3) && near(s.sweep, 100.95) && near(s.sl, 101.05) && near(s.risk, 0.75), "entry 100.30, SL = sweep 100.95 + 0.1 x ATR 1.0 = 101.05, risk 0.75");
      CHECK(near(s.tp1, 99.55) && near(s.tp2, 98.8), "TP1 = 1R 99.55, TP2 = 2R 98.80");
      CHECK(d.nt[i2].sell.state == NB_NT_TRIGGERED && d.nt[i2].sell.why == NB_NTW_TP1 && d.nt[i2].sell.outIdx == i2, "16:40: TP1 reached (recorded)");
      std::printf("    SELL trap: entry %.2f SL %.2f TP1 %.2f TP2 %.2f\n", s.entry, s.sl, s.tp1, s.tp2);
   }
   end("N1");

   begin("N2 same-candle sweep + close back inside; a bearish close still above is not a trigger; BUY mirror");
   {
      Day d;
      flat(d, D0);
      bar(d, ny(D0, 0), 100.45, 100.9, 100.1, 100.3);   // wick above, bearish close below in ONE candle
      runDay(d, ncfg());
      CHECK(d.nt.back().sell.state == NB_NT_TRIGGERED && near(d.nt.back().sell.sl, 101.0), "one-candle trap: TRIGGERED, SL 100.90 + 0.10");
      Day e;
      flat(e, D0);
      bar(e, ny(D0, 0), 100.8, 100.9, 100.55, 100.6);   // bearish body but closes ABOVE the level
      runDay(e, ncfg());
      CHECK(e.nt.back().sell.state == NB_NT_VALID, "bearish close still above 100.50 = still VALID, not triggered");
      Day b;
      flat(b, D0);
      bar(b, ny(D0, 0), 99.8, 99.9, 99.1, 99.3);        // sweep below 99.50
      bar(b, ny(D0, 1), 99.3, 99.8, 99.05, 99.7);       // bullish close back above
      runDay(b, ncfg());
      const NbNytSide &s = b.nt.back().buy;
      CHECK(s.state == NB_NT_TRIGGERED && near(s.entry, 99.7) && near(s.sl, 98.95) && near(s.tp1, 100.45) && near(s.tp2, 101.2),
            "BUY: entry 99.70, SL = 99.05 - 0.10 = 98.95, TP1 100.45, TP2 101.20");
      CHECK(s.sl < s.entry && s.entry < s.tp1 && s.tp1 < s.tp2, "BUY order: SL < ENTRY < TP1 < TP2");
   }
   end("N2");

   begin("N3 INVALID: window over untriggered, SL hit (SL wins a same candle), expiry, no range");
   {
      Day d;
      flat(d, D0);
      bar(d, ny(D0, 0), 100.2, 100.9, 100.1, 100.7);    // swept, never back inside
      for(int k = 1; k < 19; k++) bar(d, ny(D0, k), 100.7, 100.8, 100.6, 100.7);   // until 18:00
      runDay(d, ncfg());
      CHECK(d.nt[(size_t)idxAt(d, ny(D0, 17))].sell.state == NB_NT_VALID, "17:55 still VALID");
      CHECK(d.nt[(size_t)idxAt(d, ny(D0, 18))].sell.state == NB_NT_INVALID && d.nt[(size_t)idxAt(d, ny(D0, 18))].sell.why == NB_NTW_OVER,
            "18:00 window over without a trigger = INVALID");
      CHECK(d.nt.back().buy.state == NB_NT_INVALID, "the never-swept buy side is INVALID after the window too");
      Day s;
      flat(s, D0);
      bar(s, ny(D0, 0), 100.45, 100.9, 100.1, 100.3);   // trigger, SL 101.00, TP1 99.60
      bar(s, ny(D0, 1), 100.3, 101.1, 99.5, 100.0);     // touches SL and TP1 in one candle
      runDay(s, ncfg());
      CHECK(s.nt.back().sell.state == NB_NT_INVALID && s.nt.back().sell.why == NB_NTW_SL, "SL and TP1 in one candle = SL (tick order unknown)");
      Day x;
      flat(x, D0);
      bar(x, ny(D0, 0), 100.45, 100.9, 100.1, 100.3);
      for(int k = 1; k <= 6; k++) bar(x, ny(D0, k), 100.3, 100.4, 100.2, 100.3);
      runDay(x, ncfg());
      CHECK(x.nt[(size_t)idxAt(x, ny(D0, 5))].sell.why == NB_NTW_ACTIVE && x.nt.back().sell.state == NB_NT_INVALID &&
            x.nt.back().sell.why == NB_NTW_EXPIRED, "6 bars without TP1 / SL = expired");
      Day r;
      flat(r, D0, 5);
      bar(r, ny(D0, 0), 100.45, 100.9, 100.1, 100.3);
      runDay(r, ncfg());
      CHECK(r.nt.back().sell.state == NB_NT_INVALID && r.nt.back().sell.why == NB_NTW_NO_RANGE, "5 range bars < 12 = no range, a textbook trap is INVALID");
   }
   end("N3");

   begin("N4 SILVER settings: wider stop, stronger close back inside");
   {
      Day d;
      flat(d, D0);
      bar(d, ny(D0, 0), 100.2, 100.9, 100.1, 100.7);
      bar(d, ny(D0, 1), 100.7, 100.95, 100.2, 100.3);   // 100.30 is not below 100.50 - 0.25
      runDay(d, ncfg(2.0, 0.25));
      CHECK(d.nt.back().sell.state == NB_NT_VALID, "silver: 100.30 > 100.25 is not a close back inside by 0.25 ATR");
      bar(d, ny(D0, 2), 100.3, 100.4, 100.1, 100.2);
      runDay(d, ncfg(2.0, 0.25));
      const NbNytSide &s = d.nt.back().sell;
      CHECK(s.state == NB_NT_TRIGGERED && near(s.entry, 100.2) && near(s.sl, 101.15), "silver: 100.20 triggers; SL = 100.95 + 2 x 0.10 = 101.15");
   }
   end("N4");

   begin("N5 no session: weekend, NY time not set; one trap per side per day; a new day resets");
   {
      Day w;
      long long sat = D0 + 4 * 86400;   // 2026-09-05 Saturday
      flat(w, sat);
      bar(w, ny(sat, 0), 100.45, 100.9, 100.1, 100.3);
      runDay(w, ncfg());
      CHECK(w.nt.back().phase == NB_NTP_OUT && w.nt.back().sell.state == NB_NT_OFF && w.nt.back().sell.why == NB_NTW_WEEKEND, "Saturday = OFF");
      Day c;
      flat(c, D0);
      NbNytCfg N = ncfg();
      N.openSec = -1;
      runDay(c, N);
      CHECK(c.nt.back().sell.state == NB_NT_OFF && c.nt.back().sell.why == NB_NTW_NO_CLOCK, "no NY time = OFF, never guessed");
      Day o;
      flat(o, D0);
      bar(o, ny(D0, 0), 100.45, 100.9, 100.1, 100.3);   // trigger
      bar(o, ny(D0, 1), 100.3, 100.4, 99.5, 99.55);     // TP1
      bar(o, ny(D0, 2), 99.6, 101.2, 99.6, 101.1);
      bar(o, ny(D0, 3), 101.1, 101.3, 100.2, 100.25);   // a second sweep + close back inside
      runDay(o, ncfg());
      CHECK(o.nt.back().sell.trigIdx == idxAt(o, ny(D0, 0)) && o.nt.back().sell.why == NB_NTW_TP1, "one SELL trap per day: the second pattern is ignored");
      long long d1 = D0 + 86400;
      flat(o, d1);
      runDay(o, ncfg());
      CHECK(o.nt.back().sid == d1 / 86400 && o.nt.back().sell.state == NB_NT_WAIT && o.nt.back().sell.trigIdx == -1, "next day: a fresh session");
   }
   end("N5");

   begin("N6 the forming candle is never evaluated");
   {
      Day d;
      flat(d, D0);
      bar(d, ny(D0, 0), 100.2, 100.9, 100.1, 100.7);
      bar(d, ny(D0, 1), 100.7, 100.95, 100.2, 100.3);
      runDay(d, ncfg(), false);
      CHECK(d.nt.back().forming && d.nt.back().sell.state == NB_NT_VALID, "the trigger candle still forming: VALID carried, not TRIGGERED");
      runDay(d, ncfg(), true);
      CHECK(d.nt.back().sell.state == NB_NT_TRIGGERED, "the same candle closed: TRIGGERED");
   }
   end("N6");

   //============================================================ whole indicator
   for(int mi = 0; mi < 2; mi++)
   {
      Metal m = makeMetal(mi == 1, mi == 1 ? 11 : 7);
      const char *tag = m.silver ? "XAGUSD" : "XAUUSD";
      std::printf("---- %s ----\n", tag);
      char title[160];

      std::snprintf(title, sizeof title, "L1 %s: the ladder sits top right, inside the chart, clear of the main panel and the table", tag);
      begin(title);
      {
         load(m);
         SIM.now = m.m5[12 * 288 + 50].t + 320;
         CHECK(start() == INIT_SUCCEEDED, "init ok");
         SimObj &lb = SIM.objs["NBLP_L_bg"], &pb = SIM.objs["NBLP_P_bg"], &qb = SIM.objs["NBLP_Q_bg"];
         long long lx = lb.i[OBJPROP_XDISTANCE], ly = lb.i[OBJPROP_YDISTANCE], lw = lb.i[OBJPROP_XSIZE], lh = lb.i[OBJPROP_YSIZE];
         CHECK(lx + lw <= 1400 && ly + lh <= 900 && lx >= 0, "inside the 1400 x 900 chart");
         CHECK(lx >= pb.i[OBJPROP_XDISTANCE] + pb.i[OBJPROP_XSIZE], "right of the main panel");
         bool clearQ = ly + lh <= qb.i[OBJPROP_YDISTANCE] || lx >= qb.i[OBJPROP_XDISTANCE] + qb.i[OBJPROP_XSIZE];
         CHECK(clearQ, "no overlap with the bottom-middle table");
         CHECK(has(L("h1"), "15M = BOSS / DIRECTION") && has(L("h2"), "5M = ENTRY / SCALP TIMING") && has(L("h3"), "NY TRAP / PENDING") &&
               has(L("h4"), "ACTION"), "the four steps are labelled in their order");
         CHECK(SIM.objs["NBLP_L_h1"].i[OBJPROP_YDISTANCE] < SIM.objs["NBLP_L_h2"].i[OBJPROP_YDISTANCE] &&
               SIM.objs["NBLP_L_h2"].i[OBJPROP_YDISTANCE] < SIM.objs["NBLP_L_h3"].i[OBJPROP_YDISTANCE] &&
               SIM.objs["NBLP_L_h3"].i[OBJPROP_YDISTANCE] < SIM.objs["NBLP_L_h4"].i[OBJPROP_YDISTANCE] &&
               SIM.objs["NBLP_L_h4"].i[OBJPROP_YDISTANCE] < SIM.objs["NBLP_L_act"].i[OBJPROP_YDISTANCE], "top to bottom: 15M, 5M, NY trap, ACTION");
         OnDeinit(0);
         CHECK(countPrefix("NBLP_") == 0, "OnDeinit removes everything");
      }
      end(title);

      std::snprintf(title, sizeof title, "L2 %s: 15M is always the boss, 5M always the timing - over every hour of 5 days", tag);
      begin(title);
      {
         int moments = 0, bossRow = 0, bad = 0, clicks = 0, pend = 0, conflicts = 0, too = 0;
         std::string worst;
         for(size_t k = 11 * 288; k + 1 < m.m5.size(); k += 12)
         {
            load(m);
            SIM.now = m.m5[k].t + 320;
            start();
            int boss = g_s15.mode[(size_t)g_s15.n - 1];
            std::string act = L("act");
            if((boss == NB_BUY && has(L("b2"), "BOSS = BUY MODE")) || (boss == NB_SELL && has(L("b2"), "BOSS = SELL MODE")) ||
               (boss == NB_WAIT && has(L("b2"), "BOSS = WAIT")))
               bossRow++;
            // a BUY action needs the 15M boss in BUY mode, a SELL action SELL mode - whatever layer found it
            bool buyAct = has(act, "BUY VALID") || (has(act, "PENDING ORDER PLAN") && has(L("v0"), "BUY"));
            bool sellAct = has(act, "SELL VALID") || (has(act, "PENDING ORDER PLAN") && has(L("v0"), "SELL"));
            if((buyAct && boss != NB_BUY) || (sellAct && boss != NB_SELL)) bad++;
            if(has(act, "CLICK")) clicks++;
            if(has(act, "PENDING ORDER PLAN")) pend++;
            if(has(act, "CONFLICT")) { conflicts++; if(boss == NB_WAIT) bad++; }
            // the 5M layer: a CLICK from the main engine only when its 5M state is confirmed on a closed candle
            if(has(act, "CLICK") && has(L("src"), "5M CONFIRMED") && g_final != boss) bad++;
            for(auto &kv : SIM.objs)
               if((kv.first.compare(0, 7, "NBLP_L_") == 0 || kv.first.compare(0, 7, "NBLP_N_") == 0) && kv.second.s.count(OBJPROP_TEXT) &&
                  cps(kv.second.s[OBJPROP_TEXT]) > 63) { too++; if(worst.empty()) worst = kv.first + ": " + kv.second.s[OBJPROP_TEXT]; }
            OnDeinit(0);
            moments++;
         }
         std::printf("    %d moments: %d CLICK, %d PENDING ORDER PLAN, %d CONFLICT\n", moments, clicks, pend, conflicts);
         CHECK(moments > 100 && bossRow == moments, "step 1 always shows the 15M boss mode the engine holds");
         CHECK(bad == 0, "no BUY / SELL action against or without the 15M boss; CONFLICT only when the boss is opposite");
         CHECK(too == 0, "no ladder / NY trap label longer than MT5's 63 characters");
         if(too) std::printf("    too long: %s\n", worst.c_str());
      }
      end(title);

      std::snprintf(title, sizeof title, "L3 %s: BUY / SELL VALID - CLICK shows the engine's exact entry, SL, TP1, TP2 on the tick grid", tag);
      begin(title);
      {
         long long now = findNow(m, [](const Ref &r) { return r.state != NB_WAIT && r.nSig > 0; }, 11 * 288, 1);
         CHECK(now > 0, "fixture has a confirmed 15M + 5M signal moment");
         if(now > 0)
         {
            Ref r;
            reference(m, now, r);
            const NbSignal &g = r.sig[(size_t)r.s5.sigOf.back()];
            load(m);
            SIM.now = now;
            start();
            CHECK(has(L("act"), g.dir > 0 ? "BUY VALID - CLICK BUY" : "SELL VALID - CLICK SELL"), "one obvious action");
            CHECK(has(L("v1"), px(g.entry, m.digits)) && has(L("v2"), px(g.sl, m.digits)) && has(L("v3"), px(g.tp1, m.digits)) &&
                  has(L("v4"), px(g.tp2, m.digits)), "ENTRY / SL / TP1 / TP2 = the engine's, with the symbol's digits");
            CHECK(onGrid(g.sl, m.tick) && onGrid(g.tp1, m.tick) && onGrid(g.tp2, m.tick), "SL / TP on the broker's tick grid");
            CHECK(has(L("foot"), "NOTHING IS SENT"), "nothing is sent");
            std::printf("    %s  entry %s SL %s TP1 %s TP2 %s | %s\n", L("act").c_str(), px(g.entry, m.digits).c_str(), px(g.sl, m.digits).c_str(),
                        px(g.tp1, m.digits).c_str(), px(g.tp2, m.digits).c_str(), L("s2").c_str());
            OnDeinit(0);
         }
      }
      end(title);

      std::snprintf(title, sizeof title, "L4 %s: NY TRAP BUY / SELL lines at the right prices, states WAIT / VALID / TRIGGERED / INVALID", tag);
      begin(title);
      {
         int seen[5] = {0, 0, 0, 0, 0};
         int checked = 0, badLine = 0, badVal = 0, badGrid = 0;
         for(size_t k = 11 * 288; k + 1 < m.m5.size(); k += 7)
         {
            long long now = m.m5[k].t + 320;
            Ref r;
            reference(m, now, r);
            if(r.b.phase == NB_NTP_OUT || r.b.sid < 0) continue;
            seen[r.b.sell.state]++;
            seen[r.b.buy.state]++;
            if(r.b.phase < NB_NTP_NY) continue;
            load(m);
            SIM.now = now;
            start();
            for(int sd = 0; sd < 2; sd++)
            {
               const NbNytSide &s = sd ? r.b.buy : r.b.sell;
               const char *t = sd ? "B_" : "S_";
               double want = (s.state == NB_NT_TRIGGERED) ? s.entry : s.level;
               if(s.level > 0.0 && std::fabs(NP(std::string(t) + "E") - want) > 1e-9) badLine++;
               if(s.level > 0.0 && !has(NT(std::string(t) + "E_T"), std::string(sd ? "NY TRAP BUY  " : "NY TRAP SELL  ") + NbNytStateText(s.state))) badLine++;
               bool live = s.state == NB_NT_WAIT || s.state == NB_NT_VALID || NbNytLive(s);
               if(live && s.sl > 0.0 && (std::fabs(NP(std::string(t) + "SL") - s.sl) > 1e-9 || std::fabs(NP(std::string(t) + "T1") - s.tp1) > 1e-9 ||
                                         std::fabs(NP(std::string(t) + "T2") - s.tp2) > 1e-9)) badLine++;
               if(s.sl > 0.0 && (!onGrid(s.sl, m.tick) || !onGrid(s.tp1, m.tick) || !onGrid(s.tp2, m.tick))) badGrid++;
               if(s.state == NB_NT_TRIGGERED)
               {
                  bool ordered = (s.dir > 0) ? (s.sl < s.entry && s.entry < s.tp1 && s.tp1 < s.tp2) : (s.sl > s.entry && s.entry > s.tp1 && s.tp1 > s.tp2);
                  double buf = InpSlBufferAtr * (m.silver ? InpFqSilverSlMult : 1.0) * r.s5.atr[(size_t)s.trigIdx];
                  double wantSl = (s.dir > 0) ? NbRoundTick(s.sweep - buf, m.tick, m.digits, -1) : NbRoundTick(s.sweep + buf, m.tick, m.digits, 1);
                  if(!ordered || std::fabs(s.sl - wantSl) > 1e-9) badVal++;
                  if(r.nt[(size_t)s.trigIdx].phase != NB_NTP_NY) badVal++;
               }
               std::string row = L(sd ? "tbb" : "tsb");
               if(!has(row, NbNytStateText(s.state))) badLine++;
            }
            OnDeinit(0);
            checked++;
         }
         std::printf("    %d NY-window moments; states seen WAIT %d VALID %d TRIGGERED %d INVALID %d\n", checked, seen[1], seen[2], seen[3], seen[4]);
         CHECK(checked > 20 && seen[1] > 0 && seen[2] > 0 && seen[3] > 0 && seen[4] > 0, "the fixture shows all four states (else this proves nothing)");
         CHECK(badLine == 0, "entry / SL / TP1 / TP2 lines and the ladder rows = the engine's trap, state named");
         CHECK(badVal == 0, "triggered traps: levels ordered, SL = sweep +/- buffer (silver x2), trigger inside the NY window");
         CHECK(badGrid == 0, "trap prices on the broker's tick grid");
      }
      end(title);

      std::snprintf(title, sizeof title, "L5 %s: NY trap vs 15M boss - CONFLICT is shown and never called READY", tag);
      begin(title);
      {
         // Deterministic: a fresh moment where the main engine WAITs, then the boss
         // and the trap side are INJECTED and the ladder is redrawn - all three
         // relations x both directions, every run (the random fixture alone may
         // never produce a conflict).
         long long nw = findNow(m, [](const Ref &r) { return r.state == NB_WAIT; }, 3 * 288, 1);
         CHECK(nw > 0, "fixture has a WAIT moment to inject into");
         if(nw > 0)
         {
            load(m);
            SIM.now = nw;
            start();
            CHECK(g_final == NB_WAIT && g_fresh, "main engine WAIT and data fresh at the injection moment");
            int i5 = g_s5.n - 1, i15 = g_s15.n - 1;
            double a = g_s5.atr[i5] > 0.0 ? g_s5.atr[i5] : 1.0;
            double c = g_s5.c[i5];
            int bad = 0;
            for(int td = -1; td <= 1; td += 2)
               for(int bs = -1; bs <= 1; bs++)
               {
                  NbNytSide T;
                  NbNytSideReset(T, td);
                  T.state = NB_NT_TRIGGERED;
                  T.why = NB_NTW_ACTIVE;
                  T.level = NormalizeDouble(c + td * 0.5 * a, m.digits);
                  T.entry = NormalizeDouble(c, m.digits);
                  T.sl = NormalizeDouble(c - td * 1.0 * a, m.digits);
                  T.risk = MathAbs(T.entry - T.sl);
                  T.tp1 = NormalizeDouble(c + td * T.risk, m.digits);
                  T.tp2 = NormalizeDouble(c + td * 2.0 * T.risk, m.digits);
                  NbNytSideReset(g_nt[i5].buy, NB_BUY);
                  NbNytSideReset(g_nt[i5].sell, NB_SELL);
                  if(td > 0)
                     NbNytSideCopy(g_nt[i5].buy, T);
                  else
                     NbNytSideCopy(g_nt[i5].sell, T);
                  g_s15.mode[i15] = bs;
                  NbLadderDraw();
                  std::string act = L("act"), vs = L("vs"), foot = L("foot"), src = L("src");
                  if(bs == -td)
                  {
                     if(!(act == "NY TRAP vs 15M BOSS = CONFLICT" && has(vs, "CONFLICT") && has(foot, "NO TRADE"))) bad++;
                  }
                  else if(bs == td)
                  {
                     if(!(act == (td > 0 ? "BUY VALID - CLICK BUY" : "SELL VALID - CLICK SELL") && has(src, "NY TRAP") &&
                          has(vs, "AGREES") && has(L("v1"), px(T.entry, m.digits)) && has(L("v2"), px(T.sl, m.digits)) &&
                          has(L("v3"), px(T.tp1, m.digits)) && has(L("v4"), px(T.tp2, m.digits))))
                        bad++;
                  }
                  else
                  {
                     if(!(act == "WAIT" && has(vs, "NOT IN MODE") && has(foot, "NO TRADE"))) bad++;
                  }
                  if(bs != td && has(act, "VALID")) bad++;
                  if(bad) { std::printf("    td %d boss %d -> act '%s' vs '%s'\n", td, bs, act.c_str(), vs.c_str()); break; }
               }
            CHECK(bad == 0, "trap vs boss: opposite = CONFLICT + NO TRADE, same = VALID with the trap's prices, boss WAIT = WAIT");
            OnDeinit(0);
         }
      }
      end(title);

      std::snprintf(title, sizeof title, "L6 %s: the forming candle is PREVIEW ONLY - it never confirms anything", tag);
      begin(title);
      {
         long long now = findNow(m, [](const Ref &r) { return r.b.sell.state == NB_NT_VALID || r.b.buy.state == NB_NT_VALID; }, 11 * 288, 1);
         CHECK(now > 0, "fixture has a swept (VALID) trap moment");
         if(now > 0)
         {
            load(m);
            SIM.now = now;
            start();
            std::string a1 = L("act"), t1 = L("t1"), t2 = L("t2"), s1 = L("tsb"), b1 = L("tbb"), v1 = L("v1");
            int n5 = g_s5.n;
            OnDeinit(0);
            load(m);
            SIM.now = now;
            // the forming candle closes back inside BOTH sides, with a huge body
            for(auto *ser : {&SIM.m5, &SIM.m15})
               for(auto &b : *ser)
                  if(b.time <= now && b.time + (ser == &SIM.m5 ? 300 : 900) > now) { b.high += m.price * 0.03; b.low -= m.price * 0.03; b.close = b.open - m.price * 0.02; }
            start();
            SIM.bid = SIM.m5[(size_t)simVisible(PERIOD_M5) - 1].close;
            OnTimer();
            CHECK(g_s5.n == n5 && L("act") == a1 && L("t1") == t1 && L("t2") == t2 && L("tsb") == s1 && L("tbb") == b1 && L("v1") == v1,
                  "action, 5M rows and both trap states unchanged by the forming candle");
            CHECK(has(L("pv"), "IF IT CLOSED NOW: BEARISH BODY") && has(L("pvk"), "PREVIEW ONLY"), "only the PREVIEW row shows it, labelled so");
            OnDeinit(0);
         }
      }
      end(title);

      std::snprintf(title, sizeof title, "L7 %s: position active - direction, entry, SL / TP distances in money, EXIT / PROTECT, read only", tag);
      begin(title);
      {
         load(m);
         SIM.now = m.m5[13 * 288 + 7].t + 320;
         double bidNow = m.m5[13 * 288 + 7].c;
         SimPos p = {m.sym, POSITION_TYPE_BUY, 0.20, SIM.now - 3600, bidNow - 10 * m.tick * 100, bidNow - 30 * m.tick * 100, bidNow + 50 * m.tick * 100};
         SIM.pos.push_back(p);
         std::vector<SimPos> before = SIM.pos;
         start();
         double cur = SIM.bid;
         CHECK(has(L("act"), "POSITION ACTIVE") && has(L("src"), "BUY 0.20 @ " + px(p.price, m.digits)), "POSITION ACTIVE with direction, volume, entry");
         double slAway = std::fabs(cur - p.sl), tpAway = std::fabs(p.tp - cur);
         std::string slMoney = DoubleToString(slAway / m.tick * m.tickValue * 0.20, 2), tpMoney = DoubleToString(tpAway / m.tick * m.tickValue * 0.20, 2);
         CHECK(has(L("v1"), px(p.sl, m.digits)) && has(L("v1"), DoubleToString(slAway, m.digits) + " away = " + slMoney), "SL distance in price and money (tick value x lots)");
         CHECK(has(L("v2"), px(p.tp, m.digits)) && has(L("v2"), DoubleToString(tpAway, m.digits) + " away = " + tpMoney), "TP distance in price and money");
         CHECK(has(L("v4"), "HOLD") || has(L("v4"), "PROTECT") || has(L("v4"), "EXIT"), "EXIT / PROTECT advice from the 15M boss");
         CHECK(has(L("foot"), "READ ONLY"), "read only");
         CHECK(SIM.pos.size() == before.size() && SIM.pos[0].sl == before[0].sl && SIM.pos[0].tp == before[0].tp && SIM.pos[0].vol == before[0].vol,
               "the position is never modified");
         std::printf("    %s | %s | %s\n", L("src").c_str(), L("v1").c_str(), L("v2").c_str());
         OnDeinit(0);
      }
      end(title);

      std::snprintf(title, sizeof title, "L8 %s: own parameters - scalp reference, money from the broker's tick value, silver trap settings", tag);
      begin(title);
      {
         load(m);
         SIM.now = m.m5[12 * 288 + 50].t + 320;
         start();
         double smin = m.silver ? InpScalpSilverMin : InpScalpGoldMin, smax = m.silver ? InpScalpSilverMax : InpScalpGoldMax;
         CHECK(has(L("s1"), std::string("SCALP REF ") + (m.silver ? "SILVER: " : "GOLD: ") + px(smin, m.digits) + " .. " + px(smax, m.digits)),
               m.silver ? "silver: 0.300 .. 1.000" : "gold: 5.00 .. 20.00");
         std::string money = DoubleToString(smin / m.tick * m.tickValue, 0) + " .. " + DoubleToString(smax / m.tick * m.tickValue, 0);
         CHECK(has(L("s2"), money), "1.00 lot money = move / tick size x the broker's tick value");
         CHECK(has(L("s3"), "contract " + DoubleToString(SIM.contract, 0)) && has(L("s3"), DoubleToString(m.tickValue, 2)), "the broker's own contract and tick value are shown");
         CHECK(g_N.slBufMult == (m.silver ? InpFqSilverSlMult : 1.0) && g_N.confirmAtr == (m.silver ? InpFqSilverConfirmAtr : 0.0) &&
               g_N.tick == m.tick && g_N.digits == m.digits, m.silver ? "silver: trap stop x2, confirm +0.25 ATR, tick 0.001" : "gold: plain trap, tick 0.01");
         OnDeinit(0);
      }
      end(title);

      std::snprintf(title, sizeof title, "L9 %s: the 01:00 metals reopen is live, not DATA STALE; a dead feed is", tag);
      begin(title);
      {
         Metal gap = m;
         gap.m5.erase(std::remove_if(gap.m5.begin(), gap.m5.end(), [](const SBar &b) { return (b.t % 86400) < 3600; }), gap.m5.end());
         gap.m15 = agg(gap.m5, 900);
         load(gap);
         long long day = D0 + 14 * 86400;   // a Tuesday
         SIM.now = day + 3600 + 12 * 60 + 7;   // 01:12:07, 12 minutes after the reopen
         start();
         CHECK(g_fresh && has(P("vd7"), "LIVE"), "main panel data clock: LIVE at 01:12");
         CHECK(!has(L("act"), "NO TRADE") && !has(L("src"), "DATA STALE"), "the ladder is not stale either");
         OnDeinit(0);
         load(gap);
         SIM.now = day + 3600 + 12 * 60 + 7;
         SIM.tickTime = day - 60;   // last tick at 23:59 yesterday: the feed never reopened
         start();
         CHECK(!g_fresh && has(L("act"), "NO TRADE") && has(L("src"), "DATA STALE"), "no tick since yesterday = NO TRADE, DATA STALE");
         OnDeinit(0);
      }
      end(title);
   }

   begin("L10 unsupported symbol: nothing drawn, the ladder says so");
   {
      Metal m = makeMetal(false, 7);
      load(m);
      SIM.sym = "EURUSD"; SIM.base = "EUR"; _Symbol = "EURUSD";
      SIM.now = m.m5[3000].t + 20;
      start();
      CHECK(has(L("act"), "GOLD / SILVER ONLY") && countPrefix("NBLP_N_") == 0, "GOLD / SILVER ONLY, no NY trap lines");
      OnDeinit(0);
   }
   end("L10");

   std::printf("\nNY TRAP + LADDER TESTS (metals): %d checks passed, %d failed\n", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
