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
[[maybe_unused]] static bool near(double a, double b, double eps = 1e-9) { return std::fabs(a - b) <= eps; }
static bool has(const std::string &s, const std::string &sub) { return s.find(sub) != std::string::npos; }
[[maybe_unused]] static bool onGrid(double x, double tick) { return std::fabs(x / tick - std::round(x / tick)) < 1e-6; }

static const long long D0 = 1788220800LL;   // 2026-09-01, a Tuesday (UTC midnight = broker midnight here)

//--------------------------------------------------------------- engine cases
[[maybe_unused]] static NbNytCfg ncfg(double slMult = 1.0, double confirm = 0.0)
{
   NbNytCfg N;
   N.openSec = 16 * 3600 + 1800; N.autoClock = false; N.offset = 0; N.preHours = 4; N.winMin = 90; N.minBars = 12;
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
[[maybe_unused]] static void bar(Day &d, long long t, double o, double h, double l, double c)
{
   int n = d.s.n;
   NbSeriesResize(d.s, n + 1);
   d.s.t[(size_t)n] = t; d.s.o[(size_t)n] = o; d.s.h[(size_t)n] = h; d.s.l[(size_t)n] = l; d.s.c[(size_t)n] = c;
}
// 12:00 .. 16:25 flat bars: range 12:30-16:25 = 48 bars, H 100.50 / L 99.50
[[maybe_unused]] static void flat(Day &d, long long day0, int preBars = 48)
{
   bar(d, day0 + 12 * 3600, 100.0, 100.2, 99.8, 100.1);            // 12:00 before the range
   bar(d, day0 + 12 * 3600 + 900, 100.0, 100.2, 99.8, 100.1);      // 12:15
   long long start = day0 + 16 * 3600 + 1800 - (long long)preBars * 300;
   for(int k = 0; k < preBars; k++)
      bar(d, start + (long long)k * 300, 100.0, 100.5, 99.5, (k % 2) ? 100.2 : 99.8);
}
[[maybe_unused]] static long long ny(long long day0, int k) { return day0 + 16 * 3600 + 1800 + (long long)k * 300; }
[[maybe_unused]] static void runDay(Day &d, const NbNytCfg &N, bool lastClosed = true)
{
   ArrayResize(d.s.atr, d.s.n);
   ArrayInitialize(d.s.atr, 1.0);
   NbRunNyt(d.s, lastClosed, N, d.nt);
}
[[maybe_unused]] static int idxAt(const Day &d, long long t) { for(int i = 0; i < d.s.n; i++) if(d.s.t[(size_t)i] == t) return i; return -1; }

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
static void load(const Metal &m, bool htf = true)
{
   SIM = SimState();
   if(htf) { SIM.m60 = toRates(agg(m.m5, 3600)); SIM.m240 = toRates(agg(m.m5, 14400)); }   // v1.09: 1H / 4H for the regime
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
[[maybe_unused]] static std::string L(const std::string &id) { return SIM.objs.count("NBLP_L_" + id) ? SIM.objs["NBLP_L_" + id].s[OBJPROP_TEXT] : "<missing>"; }
[[maybe_unused]] static std::string P(const std::string &id) { return SIM.objs.count("NBLP_P_" + id) ? SIM.objs["NBLP_P_" + id].s[OBJPROP_TEXT] : "<missing>"; }
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
   N.openSec = InpNyAutoClock ? 0 : NbParseHHMM(InpNyOpenTime); N.autoClock = InpNyAutoClock; N.offset = 3 * 3600;   // the simulator's broker: UTC+3
   N.preHours = InpNytRangeHours; N.winMin = InpNytWindowMin; N.minBars = InpNytMinBars;
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

// v1.07 line rule: SL / TP1 / TP2 only while a side is swept (VALID) or in
// play (TRIGGERED, active); ENTRY line only in play; nothing else
[[maybe_unused]] static bool linesOk(const NbNytSide &s, const std::string &t)
{
   bool inPlay = NbNytLive(s);
   bool drawn = (s.state == NB_NT_VALID || inPlay) && s.sl > 0.0;
   if(!drawn)
      return countPrefix("NBLP_N_" + t + "E") == 0 && countPrefix("NBLP_N_" + t + "SL") == 0 && countPrefix("NBLP_N_" + t + "T1") == 0 &&
             countPrefix("NBLP_N_" + t + "T2") == 0;
   if(std::fabs(NP(t + "SL") - s.sl) > 1e-9 || std::fabs(NP(t + "T1") - s.tp1) > 1e-9 || std::fabs(NP(t + "T2") - s.tp2) > 1e-9)
      return false;
   if(inPlay)
      return std::fabs(NP(t + "E") - s.entry) < 1e-9 && has(NT(t + "E_T"), std::string(s.dir > 0 ? "NY TRAP BUY  ENTRY " : "NY TRAP SELL  ENTRY "));
   return countPrefix("NBLP_N_" + t + "E") == 0;
}
[[maybe_unused]] static std::string Y(const std::string &id) { return SIM.objs.count("NBLP_Y_" + id) ? SIM.objs["NBLP_Y_" + id].s[OBJPROP_TEXT] : "<missing>"; }
// NY high / low of the closed bars in the NY window, computed here from the raw bars
[[maybe_unused]] static bool nyHL(const Ref &r, double &hi, double &lo)
{
   bool any = false;
   for(int k = 0; k < r.s5.n; k++)
      if(r.s5.t[(size_t)k] >= r.b.open && r.s5.t[(size_t)k] < r.b.winEnd && r.nt[(size_t)k].sid == r.b.sid)
      {
         if(!any || r.s5.h[(size_t)k] > hi) hi = r.s5.h[(size_t)k];
         if(!any || r.s5.l[(size_t)k] < lo) lo = r.s5.l[(size_t)k];
         any = true;
      }
   return any;
}

int main()
{
#ifdef NYT_SIMPLE
   // built from a copy of the source with InpSimpleView = true (run_tests.sh step 5e)
   for(int mi = 0; mi < 2; mi++)
   {
      Metal m = makeMetal(mi == 1, mi == 1 ? 11 : 7);
      begin(mi ? "S1 XAGUSD simple view: NY rows + chart only" : "S1 XAUUSD simple view: NY rows + chart only");
      load(m);
      SIM.now = m.m5[12 * 288 + 50].t + 320;
      CHECK(start() == INIT_SUCCEEDED, "init ok");
      CHECK(countPrefix("NBLP_P_") == 0 && countPrefix("NBLP_Q_") == 0, "main panel and 5-question table hidden");
      CHECK(countPrefix("NBLP_Y_") > 5 && countPrefix("NBLP_L_") == 0, "the NY rows are drawn (the ladder stays off)");
      CHECK(SIM.objs["NBLP_Y_bg"].i[OBJPROP_YDISTANCE] + SIM.objs["NBLP_Y_bg"].i[OBJPROP_YSIZE] == 900 - InpFqBottomY, "the NY rows move down to the bottom");
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
#ifndef NYT_LADDER
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

   begin("N7 the close back inside needs a body IN THE TRAP'S DIRECTION");
   {
      Day d;
      flat(d, D0);
      bar(d, ny(D0, 0), 100.2, 100.9, 100.1, 100.7);    // swept above 100.50
      bar(d, ny(D0, 1), 100.1, 100.4, 100.0, 100.3);    // closes back BELOW 100.50, but a BULLISH body
      runDay(d, ncfg());
      CHECK(d.nt.back().sell.state == NB_NT_VALID, "SELL: a bullish candle closing back inside is not a trigger");
      Day b;
      flat(b, D0);
      bar(b, ny(D0, 0), 99.8, 99.9, 99.1, 99.3);        // swept below 99.50
      bar(b, ny(D0, 1), 99.9, 100.0, 99.6, 99.7);       // closes back ABOVE 99.50, but a BEARISH body
      runDay(b, ncfg());
      CHECK(b.nt.back().buy.state == NB_NT_VALID, "BUY: a bearish candle closing back inside is not a trigger");
      Day z;
      flat(z, D0);
      bar(z, ny(D0, 0), 100.2, 100.9, 100.1, 100.7);
      bar(z, ny(D0, 1), 100.3, 100.4, 100.1, 100.3);    // doji back inside
      runDay(z, ncfg());
      CHECK(z.nt.back().sell.state == NB_NT_VALID, "a doji back inside is not a trigger");
   }
   end("N7");

   begin("N8 v1.07 AUTO clock: 09:30 New York in broker time, right in the weeks the US and EU disagree");
   {
      NbNytCfg A = ncfg();
      A.autoClock = true;
      long day = 0;
      struct Case { int y, m, d; long off; const char *want; const char *why; } cases[] = {
         {2026, 9, 28, 3 * 3600, "16:30", "Sep 28 2026: EU summer (UTC+3), US summer: 16:30"},
         {2026, 10, 26, 2 * 3600, "15:30", "Oct 26 2026: EU winter already (UTC+2), US still summer: 15:30"},
         {2026, 11, 2, 2 * 3600, "16:30", "Nov 2 2026: both winter: 16:30"},
         {2027, 3, 15, 2 * 3600, "15:30", "Mar 15 2027: US summer from Mar 14, EU still winter: 15:30"},
         {2027, 3, 29, 3 * 3600, "16:30", "Mar 29 2027: both summer: 16:30"},
      };
      for(const Case &c : cases)
      {
         // days since 1970 for the date (inverse of NbCivil, checked against it)
         long dd = 0;
         for(long k = 20000; k < 22000; k++) { int y, m, d; NbCivil(k, y, m, d); if(y == c.y && m == c.m && d == c.d) { dd = k; break; } }
         A.offset = c.off;
         datetime o = NbNytOpenOf((datetime)(dd * 86400 + 12 * 3600), A, day);
         CHECK(TimeToString(o, TIME_MINUTES) == c.want && day == dd, c.why);
      }
      NbNytCfg T = ncfg();
      long dd = 0;
      for(long k = 20000; k < 22000; k++) { int y, m, d; NbCivil(k, y, m, d); if(y == 2026 && m == 10 && d == 26) { dd = k; break; } }
      CHECK(TimeToString(NbNytOpenOf((datetime)(dd * 86400), T, day), TIME_MINUTES) == "16:30", "TYPED clock: 16:30 whatever the date (the old behaviour)");
      // the whole trap engine follows the clock: on Oct 26 the window opens at 15:30
      Day w;
      long long d26 = dd * 86400LL;
      for(long long t = d26 + 11 * 3600 + 1800; t < d26 + 17 * 3600; t += 300) bar(w, t, 100.0, 100.5, 99.5, 100.1);
      A.offset = 2 * 3600;
      runDay(w, A);
      CHECK(w.nt[(size_t)idxAt(w, d26 + 15 * 3600 + 1800)].phase == NB_NTP_NY && w.nt[(size_t)idxAt(w, d26 + 15 * 3600 + 1500)].phase == NB_NTP_PRE,
            "AUTO on Oct 26: 15:25 = pre-NY range, 15:30 = NY window");
   }
   end("N8");

   begin("N9 v1.07 MARKET STATE on hand-made 15M bars (a description, never a signal)");
   {
      auto mk = [](int mode, double c, double ema, double atr, int flips, double width, int dir5, double &dist, int &fl, double &wd) {
         NbSeries b;
         int n = NB_MK_LOOKBACK + 1;
         NbSeriesResize(b, n);
         ArrayResize(b.atr, n); ArrayResize(b.ema, n); ArrayResize(b.flip, n); ArrayResize(b.mode, n);
         for(int j = 0; j < n; j++)
         {
            b.c[(size_t)j] = c; b.h[(size_t)j] = c + width * atr / 2.0; b.l[(size_t)j] = c - width * atr / 2.0;
            b.atr[(size_t)j] = atr; b.ema[(size_t)j] = ema; b.mode[(size_t)j] = mode; b.flip[(size_t)j] = (j >= n - flips) ? 1 : 0;
         }
         return NbMarketState(b, n - 1, dir5, dist, fl, wd);
      };
      double dist; int fl; double wd;
      CHECK(mk(NB_BUY, 102.0, 100.0, 1.0, 0, 3.0, 1, dist, fl, wd) == NB_MK_SUPER_BULL && near(dist, 2.0), "BUY MODE, 5M up, +2.0 ATR, no flip = SUPER BULLISH");
      CHECK(mk(NB_BUY, 101.0, 100.0, 1.0, 0, 3.0, 1, dist, fl, wd) == NB_MK_TREND_UP, "+1.0 ATR only = TREND UP");
      CHECK(mk(NB_BUY, 102.0, 100.0, 1.0, 1, 3.0, 1, dist, fl, wd) == NB_MK_TREND_UP, "one flip in 6 h = TREND UP, not SUPER");
      CHECK(mk(NB_BUY, 102.0, 100.0, 1.0, 0, 3.0, -1, dist, fl, wd) == NB_MK_TREND_UP, "5M against = TREND UP, not SUPER");
      CHECK(mk(NB_SELL, 98.0, 100.0, 1.0, 0, 3.0, -1, dist, fl, wd) == NB_MK_SUPER_BEAR, "the mirror: SUPER BEARISH");
      CHECK(mk(NB_SELL, 99.5, 100.0, 1.0, 0, 3.0, -1, dist, fl, wd) == NB_MK_TREND_DOWN, "TREND DOWN");
      CHECK(mk(NB_WAIT, 100.0, 100.0, 1.0, 3, 3.0, 1, dist, fl, wd) == NB_MK_CHOP && fl == 3, "boss WAIT + 3 flips = CHOP");
      CHECK(mk(NB_WAIT, 100.0, 100.0, 1.0, 1, 3.5, 1, dist, fl, wd) == NB_MK_RANGE && near(wd, 3.5), "boss WAIT, 1 flip, width 3.5 ATR = RANGE");
      CHECK(mk(NB_WAIT, 100.0, 100.0, 1.0, 1, 6.0, 1, dist, fl, wd) == NB_MK_TRANSITION, "boss WAIT, width 6 ATR = TRANSITION");
      CHECK(mk(NB_BUY, 102.0, 0.0, 1.0, 0, 3.0, 1, dist, fl, wd) == NB_MK_UNKNOWN, "no EMA yet = unknown, never guessed");
   }
   end("N9");

   //============================================================ v1.09 regime pullback (engine, hand-made bars)
   // 15M ATR 1.0, 5M ATR 0.2, start 0.5 ATR, location 0.25 ATR, SL buffer 0.1 x 5M ATR, min R:R 1.5
   struct RpCase
   {
      NbSeries s;
      std::vector<int> d60, d240;
      std::vector<double> a15, r15, s15, r60, s60;
      std::vector<NbRpBar> rb;
      std::vector<NbRpRec> rec;
      int nInv = 0, nRec = 0;
      RpCase() { NbSeriesResize(s, 0); s.sec = 300; }
      void add(double o, double h, double l, double c, int boss = NB_SELL, int h1 = -1, int h4 = -1, double res = 102.0, double sup = 95.0)
      {
         int n = s.n;
         NbSeriesResize(s, n + 1);
         s.t[(size_t)n] = D0 + 12 * 3600 + n * 300; s.o[(size_t)n] = o; s.h[(size_t)n] = h; s.l[(size_t)n] = l; s.c[(size_t)n] = c;
         ArrayResize(s.atr, n + 1); s.atr[(size_t)n] = 0.2;
         ArrayResize(s.boss, n + 1); s.boss[(size_t)n] = boss;
         ArrayResize(s.dir, n + 1); s.dir[(size_t)n] = (c >= o) ? 1 : -1;
         d60.push_back(h1); d240.push_back(h4); a15.push_back(1.0); r15.push_back(res); s15.push_back(sup); r60.push_back(0.0); s60.push_back(0.0);
      }
      void run(bool lastClosed = true, double minRR = 1.5)
      {
         NbRpCfg C;
         C.startAtr = 0.5; C.locAtr = 0.25; C.slBufAtr = 0.1; C.minRR = minRR; C.validBars = 6; C.trackBars = 24; C.tick = 0.01; C.digits = 2;
         nRec = NbRunRp(s, d60, d240, a15, r15, s15, r60, s60, lastClosed, C, rb, rec, nInv);
      }
   };
   // the textbook bearish re-entry: leg to 98.50, pull-up to the 15M lower high 102.00, rejection, bearish close
   auto bearCase = [](RpCase &k) {
      k.add(100.0, 100.2, 99.8, 100.0);     // 0 regime appears: leg low 99.80
      k.add(100.0, 100.0, 98.5, 98.7);      // 1 new leg low 98.50
      k.add(98.7, 100.0, 98.6, 99.9);       // 2 close 99.90 = 1.4 ATR above the leg: PULL-UP WATCH, level 102.00
      k.add(99.9, 101.9, 99.8, 101.6);      // 3 high 101.90 within 0.25 ATR of 102.00: at structure
      k.add(101.6, 101.95, 101.0, 101.1);   // 4 new pull high 101.95, closes in its lower half: rejection
      k.add(101.1, 101.3, 100.5, 100.6);    // 5 bearish close 100.60 < 101.00: SL 101.95 + 0.02 = 101.97, risk 1.37, reward 2.10, R:R 1.53
   };
   begin("R1 v1.09 BEARISH regime (4H/1H/15M) + pull-up to structure + rejection + bearish 5M close = SELL re-entry candidate");
   {
      RpCase k;
      bearCase(k);
      k.add(100.6, 100.7, 98.4, 98.6);      // 6 low 98.40 <= target 98.50
      k.run();
      CHECK(k.rb[0].state == NB_RP_TREND && k.rb[0].regime == NB_SELL, "bar 0: bearish regime, tracking the leg");
      CHECK(k.rb[2].state == NB_RP_PULLBACK && k.rb[2].why == NB_RPW_WAIT_LOCATION && near(k.rb[2].level, 102.0) && near(k.rb[2].pullAtr, 1.5),
            "bar 2: PULL-UP WATCH, structure 102.00, pull 1.5 ATR (98.50 -> 100.00)");
      CHECK(k.rb[3].atLoc && k.rb[3].why == NB_RPW_WAIT_REJECT, "bar 3: at structure, waiting for a rejection");
      CHECK(k.rb[4].rejected && k.rb[4].why == NB_RPW_WAIT_CLOSE, "bar 4: rejection, waiting for the confirming close");
      CHECK(k.rb[5].state == NB_RP_CANDIDATE && k.nRec == 1 && k.rec[0].dir == NB_SELL, "bar 5: SELL PULLBACK / RE-ENTRY CANDIDATE (with the regime)");
      CHECK(near(k.rec[0].entry, 100.6) && near(k.rec[0].sl, 101.97) && near(k.rec[0].target, 98.5) && std::fabs(k.rec[0].rr - 2.1 / 1.37) < 1e-9,
            "entry 100.60, SL 101.97, target 98.50 (the leg low), R:R 1.53");
      CHECK(k.rec[0].status == NB_RPO_TARGET && k.rec[0].outIdx == 6, "bar 6: target reached (recorded)");
      std::printf("    SELL re-entry: entry %.2f SL %.2f target %.2f R:R %.2f\n", k.rec[0].entry, k.rec[0].sl, k.rec[0].target, k.rec[0].rr);
   }
   end("R1");

   begin("R2 a 5M close above the bearish structure = BEARISH THESIS INVALIDATED until a new leg low");
   {
      RpCase k;
      k.add(100.0, 100.2, 99.8, 100.0);
      k.add(100.0, 100.0, 98.5, 98.7);
      k.add(98.7, 100.0, 98.6, 99.9);
      k.add(99.9, 102.5, 99.8, 102.3);      // closes 102.30 > 102.00
      k.add(102.3, 102.4, 100.0, 100.1);    // back down, no new low: still invalidated
      k.add(100.1, 100.2, 98.3, 98.4);      // new leg low 98.30: the bearish thesis is armed again
      k.run();
      CHECK(k.rb[3].state == NB_RP_INVALIDATED && k.rb[3].why == NB_RPW_INVALIDATED && k.nInv == 1, "bar 3: INVALIDATED (counted)");
      CHECK(k.rb[4].state == NB_RP_INVALIDATED && k.nRec == 0, "bar 4: stays invalidated, no candidate - wait for bullish confirmation");
      CHECK(k.rb[5].state == NB_RP_TREND && near(k.rb[5].legExt, 98.3), "bar 5: a new leg low re-arms the bearish watch");
   }
   end("R2");

   begin("R3 a pull-up in a bearish regime NEVER becomes a BUY - whatever the bullish candles do");
   {
      RpCase k;
      bearCase(k);
      for(int j = 0; j < 30; j++)                           // strong bullish candles, sweeps, rejections, all of it
         k.add(100.6 + j * 0.05, 101.99, 100.4 + j * 0.05, 100.9 + j * 0.05 + ((j % 3 == 0) ? -0.6 : 0.3));
      k.run();
      int buys = 0;
      for(int r = 0; r < k.nRec; r++) if(k.rec[(size_t)r].dir != NB_SELL) buys++;
      bool anyBuyState = false;
      for(auto &b : k.rb) if(b.regime == NB_BUY) anyBuyState = true;
      CHECK(buys == 0 && !anyBuyState && k.nRec >= 1, "every record is a SELL, no bar is in a bullish regime");
      CHECK(k.rec[0].status == NB_RPO_SL || k.rec[0].status == NB_RPO_EXPIRED || k.rec[0].status == NB_RPO_TARGET, "the candidate got an outcome");
   }
   end("R3");

   begin("R4 not taken: confirming close away from structure; R:R below the minimum; one candidate per pull");
   {
      RpCase far;
      bearCase(far);
      for(int j = 0; j < (int)far.r15.size(); j++) far.r15[(size_t)j] = 105.0;   // the structure is far above the pull
      far.run();
      CHECK(far.nRec == 0 && far.rb[5].why == NB_RPW_NOT_AT_LEVEL && far.rb[5].state == NB_RP_PULLBACK, "rejection + close far from 105.00: not taken");
      RpCase lo;
      bearCase(lo);
      lo.run(true, 2.0);
      CHECK(lo.nRec == 0 && lo.rb[5].why == NB_RPW_LOW_RR, "R:R 1.53 < 2.0: not taken");
      RpCase once;
      bearCase(once);
      for(int j = 0; j < 8; j++) once.add(100.6, 101.9, 100.5, (j % 2) ? 100.55 : 101.5);   // chop at the level after the candidate
      once.run();
      CHECK(once.nRec == 1, "no second candidate from the same pull (needs a new leg low first)");
      CHECK(once.rb[12].state == NB_RP_TREND && once.rb[12].why == NB_RPW_NO_CHASE, "after 6 bars: candidate expired - do not chase");
   }
   end("R4");

   begin("R5 DIRECTION needs 4H + 1H + 15M together; 1H / 4H missing is said, never guessed");
   {
      RpCase a;
      a.add(100.0, 100.2, 99.8, 100.0, NB_SELL, +1, -1);
      a.add(100.0, 100.2, 99.8, 100.0, NB_SELL, -1, 0);
      a.add(100.0, 100.2, 99.8, 100.0, NB_WAIT, -1, -1);
      a.run();
      CHECK(a.rb[0].state == NB_RP_NONE && a.rb[0].why == NB_RPW_NOT_ALIGNED, "1H up, 4H down: not aligned");
      CHECK(a.rb[1].state == NB_RP_NONE && a.rb[1].why == NB_RPW_NO_HTF, "4H unknown: 1H / 4H data missing");
      CHECK(a.rb[2].state == NB_RP_NONE && a.rb[2].why == NB_RPW_NOT_ALIGNED, "15M boss WAIT: not aligned");
   }
   end("R5");

   begin("R6 the forming candle never confirms a candidate");
   {
      RpCase k;
      bearCase(k);
      k.run(false);                          // bar 5 (the confirming close) still forming
      CHECK(k.nRec == 0 && k.rb[5].state == NB_RP_PULLBACK && k.rb[5].why == NB_RPW_WAIT_CLOSE, "forming: no candidate, the rejection state is carried");
      k.run(true);
      CHECK(k.nRec == 1, "the same bar closed: the candidate appears");
   }
   end("R6");

   begin("R7 the BULLISH mirror: pull-down to the 15M higher low + rejection + bullish close = BUY re-entry (with the regime)");
   {
      RpCase b;
      auto m = [&](double o, double h, double l, double c) { b.add(200 - o, 200 - l, 200 - h, 200 - c, NB_BUY, +1, +1, 105.0, 98.0); };
      m(100.0, 100.2, 99.8, 100.0);
      m(100.0, 100.0, 98.5, 98.7);
      m(98.7, 100.0, 98.6, 99.9);
      m(99.9, 101.9, 99.8, 101.6);
      m(101.6, 101.95, 101.0, 101.1);
      m(101.1, 101.3, 100.5, 100.6);
      b.run();
      CHECK(b.nRec == 1 && b.rec[0].dir == NB_BUY && b.rb[5].state == NB_RP_CANDIDATE, "BUY PULLBACK / RE-ENTRY CANDIDATE");
      CHECK(near(b.rec[0].entry, 99.4) && near(b.rec[0].sl, 98.03) && near(b.rec[0].target, 101.5), "entry 99.40, SL 98.03, target 101.50 (mirror of R1)");
   }
   end("R7");

   //============================================================ v1.07 default view: NY strip + lines
   for(int mi = 0; mi < 2; mi++)
   {
      Metal m = makeMetal(mi == 1, mi == 1 ? 11 : 7);
      const char *tag = m.silver ? "XAGUSD" : "XAUUSD";
      std::printf("---- %s (default view) ----\n", tag);
      char title[160];

      std::snprintf(title, sizeof title, "Y1 %s: no box top right; the NY rows sit on top of the bottom-middle table", tag);
      begin(title);
      {
         load(m);
         SIM.now = m.m5[12 * 288 + 50].t + 320;
         CHECK(start() == INIT_SUCCEEDED, "init ok");
         CHECK(countPrefix("NBLP_L_") == 0, "the big ladder box is off by default");
         SimObj &yb = SIM.objs["NBLP_Y_bg"], &qb = SIM.objs["NBLP_Q_bg"];
         long long yx = yb.i[OBJPROP_XDISTANCE], yy = yb.i[OBJPROP_YDISTANCE], yw = yb.i[OBJPROP_XSIZE], yh = yb.i[OBJPROP_YSIZE];
         CHECK(yx == qb.i[OBJPROP_XDISTANCE] && yw == qb.i[OBJPROP_XSIZE], "same x and width as the table");
         CHECK(yy + yh == qb.i[OBJPROP_YDISTANCE] && yy > 450, "docked exactly on the table's top edge, in the lower half");
         int topRight = 0;
         for(auto &kv : SIM.objs)
            if(kv.second.type == OBJ_RECTANGLE_LABEL && kv.first.compare(0, 5, "NBLP_") == 0 &&
               kv.second.i[OBJPROP_XDISTANCE] + kv.second.i[OBJPROP_XSIZE] > 1400 - 300 && kv.second.i[OBJPROP_YDISTANCE] < 300)
               topRight++;
         CHECK(topRight == 0, "nothing of this indicator in the top-right corner (MT5's price scale stays visible)");
         CHECK(has(Y("h"), "NY TRAP") && Y("s") == "SELL" && Y("b") == "BUY" && Y("v") != "<missing>", "rows: NY TRAP, SELL, BUY, verdict");
         OnDeinit(0);
         CHECK(countPrefix("NBLP_") == 0, "OnDeinit removes everything");
      }
      end(title);

      std::snprintf(title, sizeof title, "Y2 %s: rows and lines = the engine: PRE-NY H/L, NY H/L, state, ENTRY / SL / TP1 / TP2", tag);
      begin(title);
      {
         int checked = 0, badRow = 0, badLine = 0, badHL = 0, too = 0, nyLines = 0, sideLines = 0;
         std::string worst;
         for(size_t k = 11 * 288; k + 1 < m.m5.size(); k += 5)
         {
            long long now = m.m5[k].t + 320;
            Ref r;
            reference(m, now, r);
            if(r.b.phase == NB_NTP_OUT || r.b.sid < 0) continue;
            load(m);
            SIM.now = now;
            start();
            if(!g_fresh) { OnDeinit(0); continue; }
            for(int sd = 0; sd < 2; sd++)
            {
               const NbNytSide &s = sd ? r.b.buy : r.b.sell;
               std::string id = sd ? "b" : "s";
               if(!has(Y(id + "_st"), std::string(NbNytStateText(s.state)) + "  -  " + NbNytWhyText(s.why))) badRow++;
               if(s.state != NB_NT_OFF && s.level > 0.0 && s.sl > 0.0)
               {
                  std::string want = std::string(s.estimate ? "ref E " : "ENTRY ") + px(s.entry, m.digits) + "   SL " + px(s.sl, m.digits) + "   TP1 " +
                                     px(s.tp1, m.digits) + "   TP2 " + px(s.tp2, m.digits);
                  if(Y(id + "_px") != want) badRow++;
               }
               if(!linesOk(s, sd ? "B_" : "S_")) badLine++;
               if(countPrefix(std::string("NBLP_N_") + (sd ? "B_SL" : "S_SL"))) sideLines++;
            }
            if(r.b.rn > 0)
            {
               if(!has(Y("hr"), "PRE-NY H " + px(r.b.rh, m.digits) + "  L " + px(r.b.rl, m.digits))) badRow++;
               if(std::fabs(NP("RH") - r.b.rh) > 1e-9 || std::fabs(NP("RL") - r.b.rl) > 1e-9) badLine++;
               if(!has(NT("RH_T"), std::string("NY TRAP SELL ") + NbNytStateText(r.b.sell.state)) ||
                  !has(NT("RL_T"), std::string("NY TRAP BUY ") + NbNytStateText(r.b.buy.state))) badLine++;
            }
            double hi = 0.0, lo = 0.0;
            if(nyHL(r, hi, lo))
            {
               nyLines++;
               if(std::fabs(NP("NH") - hi) > 1e-9 || std::fabs(NP("NL") - lo) > 1e-9) badHL++;
               if(!has(Y("hr"), "NY H " + px(hi, m.digits) + "  L " + px(lo, m.digits))) badHL++;
            }
            else if(countPrefix("NBLP_N_NH") || countPrefix("NBLP_N_NL")) badHL++;
            for(auto &kv : SIM.objs)
               if((kv.first.compare(0, 7, "NBLP_Y_") == 0 || kv.first.compare(0, 7, "NBLP_N_") == 0) && kv.second.s.count(OBJPROP_TEXT) &&
                  cps(kv.second.s[OBJPROP_TEXT]) > 63) { too++; if(worst.empty()) worst = kv.first + ": " + kv.second.s[OBJPROP_TEXT]; }
            OnDeinit(0);
            checked++;
         }
         std::printf("    %d session moments; %d with NY H/L lines, %d side-line sets\n", checked, nyLines, sideLines);
         CHECK(checked > 50 && nyLines > 10 && sideLines > 0, "the fixture covers NY windows and in-play sides (else this proves nothing)");
         CHECK(badRow == 0, "SELL / BUY rows: the engine's state, why, and exact ENTRY / SL / TP1 / TP2 on the symbol's digits");
         CHECK(badLine == 0, "PRE-NY H/L lines carry the trap state; SL / TP lines only while swept or in play, ENTRY only in play");
         CHECK(badHL == 0, "NY HIGH / LOW lines and row = the closed NY-window bars, computed independently here");
         CHECK(too == 0, "no NY row or line text over MT5's 63 characters");
         if(too) std::printf("    too long: %s\n", worst.c_str());
      }
      end(title);

      std::snprintf(title, sizeof title, "Y3 %s: the verdict row - the 15M boss always decides", tag);
      begin(title);
      {
         long long nw = findNow(m, [](const Ref &r) { return r.state == NB_WAIT; }, 3 * 288, 1);
         CHECK(nw > 0, "fixture has a WAIT moment to inject into");
         if(nw > 0)
         {
            load(m);
            SIM.now = nw;
            start();
            CHECK(g_fresh, "data fresh at the injection moment");
            int i5 = g_s5.n - 1, i15 = g_s15.n - 1;
            double a = g_s5.atr[i5] > 0.0 ? g_s5.atr[i5] : 1.0, c = g_s5.c[i5];
            int bad = 0;
            for(int st = 0; st < 2; st++)          // 0 = swept (VALID), 1 = in play (TRIGGERED)
               for(int td = -1; td <= 1; td += 2)
                  for(int bs = -1; bs <= 1; bs++)
                  {
                     NbNytSide T;
                     NbNytSideReset(T, td);
                     T.state = st ? NB_NT_TRIGGERED : NB_NT_VALID;
                     T.why = st ? NB_NTW_ACTIVE : NB_NTW_SWEPT;
                     T.level = NormalizeDouble(c + td * 0.5 * a, m.digits);
                     T.entry = NormalizeDouble(c, m.digits);
                     T.sl = NormalizeDouble(c - td * a, m.digits);
                     T.risk = MathAbs(T.entry - T.sl);
                     T.tp1 = NormalizeDouble(c + td * T.risk, m.digits);
                     T.tp2 = NormalizeDouble(c + td * 2.0 * T.risk, m.digits);
                     NbNytSideReset(g_nt[i5].buy, NB_BUY);
                     NbNytSideReset(g_nt[i5].sell, NB_SELL);
                     if(td > 0) NbNytSideCopy(g_nt[i5].buy, T); else NbNytSideCopy(g_nt[i5].sell, T);
                     g_s15.mode[i15] = bs;
                     NbNyStripDraw();
                     std::string v = Y("v");
                     std::string side = td > 0 ? "BUY" : "SELL";
                     bool okv;
                     if(bs == -td) okv = (v == "NY TRAP vs 15M BOSS = CONFLICT  -  NO TRADE");
                     else if(st == 0) okv = has(v, "swept") && !has(v, "VALID") && !has(v, "CLICK");
                     else if(bs == td) okv = (v == "NY TRAP " + side + " + 15M BOSS = " + side + " VALID - CLICK " + side);
                     else okv = has(v, "15M BOSS WAIT") && has(v, "NO TRADE");
                     if(bs != td && has(v, "CLICK")) okv = false;
                     if(!okv) { bad++; std::printf("    swept/in-play %d td %d boss %d -> '%s'\n", st, td, bs, v.c_str()); }
                  }
            NbNytSideReset(g_nt[i5].buy, NB_BUY);
            NbNytSideReset(g_nt[i5].sell, NB_SELL);
            NbNyStripDraw();
            CHECK(has(Y("v"), "nothing in play") && !has(Y("v"), "CLICK"), "nothing swept: nothing in play");
            CHECK(bad == 0, "opposite boss = CONFLICT, NO TRADE; boss WAIT = NO TRADE; swept only = wait; CLICK only with the boss");
            OnDeinit(0);
         }
      }
      end(title);

      std::snprintf(title, sizeof title, "Y4 %s: stale data shows no trap at all; the 01:00 reopen is not stale", tag);
      begin(title);
      {
         Metal gap = m;
         gap.m5.erase(std::remove_if(gap.m5.begin(), gap.m5.end(), [](const SBar &b) { return (b.t % 86400) < 3600; }), gap.m5.end());
         gap.m15 = agg(gap.m5, 900);
         long long day = D0 + 14 * 86400;
         load(gap);
         SIM.now = day + 3600 + 12 * 60 + 7;
         start();
         CHECK(g_fresh && !has(Y("v"), "STALE"), "01:12 after the 01:00 reopen: not stale");
         OnDeinit(0);
         load(gap);
         SIM.now = day + 3600 + 12 * 60 + 7;
         SIM.tickTime = day - 60;
         start();
         CHECK(!g_fresh && Y("v") == "NO TRADE  -  DATA STALE / MARKET CLOSED", "dead feed: NO TRADE, DATA STALE");
         CHECK(Y("s_st") == "---" && Y("s_px") == "---" && Y("b_st") == "---" && Y("b_px") == "---" && Y("hr") == "---",
               "no state and no price is shown from stale data");
         OnDeinit(0);
      }
      end(title);
   }

   //============================================================ v1.09: regime pullback on the whole indicator
   for(int mi = 0; mi < 2; mi++)
   {
      Metal m = makeMetal(mi == 1, mi == 1 ? 11 : 7);
      const char *tag = m.silver ? "XAGUSD" : "XAUUSD";
      char title[180];
      std::snprintf(title, sizeof title, "Y7 %s: regime pullback rows = an independent 1H/4H/15M/5M run; stale and missing 1H/4H are said", tag);
      begin(title);
      {
         // independent: our own 1H / 4H bars, mapping (last CLOSED bar at the 5M close) and structure (last CONFIRMED swing)
         auto refRp = [&](long long now, NbRpBar &last, std::vector<NbRpRec> &recs, int &nRec) {
            Ref r;
            reference(m, now, r);
            long long anchor = (now / 86400) * 86400 - (long long)InpHistoryDays * 86400;
            auto series = [&](int sec, NbSeries &x) {
               std::vector<SBar> v;
               for(const SBar &b : agg(m.m5, sec)) if(b.t >= anchor && b.t + sec <= now) v.push_back(b);
               NbSeriesResize(x, (int)v.size()); x.sec = sec;
               for(size_t k = 0; k < v.size(); k++) { x.t[k] = v[k].t; x.o[k] = v[k].o; x.h[k] = v[k].h; x.l[k] = v[k].l; x.c[k] = v[k].c; }
               NbCalcATR(x.h, x.l, x.c, x.n, InpNrtrAtrPeriod, x.atr);
               NbCalcNRTR(x.c, x.atr, x.n, InpNrtrMultiplier, x.dir, x.stop, x.ext, x.flip);
            };
            NbSeries h1, h4;
            series(3600, h1);
            series(14400, h4);
            std::vector<NbPivot> p60;
            int np60 = NbFindPivots(h1.h, h1.l, h1.n, InpSwingStrength, p60);
            int n = r.s5.n;
            std::vector<int> d60((size_t)n), d240((size_t)n);
            std::vector<double> a15((size_t)n), r15((size_t)n), s15((size_t)n), r60((size_t)n), s60((size_t)n);
            for(int i = 0; i < n; i++)
            {
               long long close5 = (long long)r.s5.t[(size_t)i] + 300;
               int k1 = -1, k4 = -1, k15 = -1;
               for(int k = 0; k < h1.n; k++) if((long long)h1.t[(size_t)k] + 3600 <= close5) k1 = k;
               for(int k = 0; k < h4.n; k++) if((long long)h4.t[(size_t)k] + 14400 <= close5) k4 = k;
               for(int k = 0; k < r.s15.n; k++) if((long long)r.s15.t[(size_t)k] + 900 <= close5) k15 = k;
               d60[(size_t)i] = k1 >= 0 ? h1.dir[(size_t)k1] : 0;
               d240[(size_t)i] = k4 >= 0 ? h4.dir[(size_t)k4] : 0;
               a15[(size_t)i] = k15 >= 0 ? r.s15.atr[(size_t)k15] : 0.0;
               double hi = 0, lo = 0, hi1 = 0, lo1 = 0;
               for(const NbPivot &p : r.p15) if(p.confirmIdx <= k15) { if(p.kind > 0) hi = p.price; else lo = p.price; }
               for(int q = 0; q < np60; q++) if(p60[(size_t)q].confirmIdx <= k1) { if(p60[(size_t)q].kind > 0) hi1 = p60[(size_t)q].price; else lo1 = p60[(size_t)q].price; }
               r15[(size_t)i] = hi; s15[(size_t)i] = lo; r60[(size_t)i] = hi1; s60[(size_t)i] = lo1;
            }
            NbRpCfg C;
            C.startAtr = InpRpStartAtr; C.locAtr = 0.25; C.slBufAtr = InpSlBufferAtr; C.minRR = InpRpMinRR; C.validBars = InpSignalValidBars;
            C.trackBars = 24; C.tick = m.tick; C.digits = m.digits;
            std::vector<NbRpBar> rb;
            int nInv = 0;
            nRec = NbRunRp(r.s5, d60, d240, a15, r15, s15, r60, s60, true, C, rb, recs, nInv);
            last = rb.back();
         };
         int moments = 0, bad = 0, badTxt = 0, too = 0, buyInBear = 0;
         std::map<int, int> seen;
         for(size_t k = 11 * 288; k + 1 < m.m5.size(); k += 6)
         {
            long long now = m.m5[k].t + 320;
            NbRpBar want;
            std::vector<NbRpRec> recs;
            int nRec = 0;
            refRp(now, want, recs, nRec);
            load(m);
            SIM.now = now;
            start();
            if(!g_fresh) { OnDeinit(0); continue; }
            moments++;
            const NbRpBar &got = g_rp.back();
            if(got.regime != want.regime || got.state != want.state || got.why != want.why || !near(got.level, want.level) ||
               !near(got.legExt, want.legExt) || g_nRp != nRec)
               bad++;
            seen[want.state]++;
            std::string st = Y("rpst"), ttl = Y("rph");
            if(want.state == NB_RP_CANDIDATE && want.cand >= 0)
            {
               const NbRpRec &c = recs[(size_t)want.cand];
               if(ttl != (want.regime < 0 ? "SELL PULLBACK / RE-ENTRY CANDIDATE" : "BUY PULLBACK / RE-ENTRY CANDIDATE") ||
                  !has(st, "entry " + px(c.entry, m.digits) + "  SL " + px(c.sl, m.digits))) badTxt++;
               if(want.regime < 0 && c.dir != NB_SELL) buyInBear++;
            }
            else if(want.state == NB_RP_PULLBACK && !has(st, want.regime < 0 ? "PULL-UP " : "PULL-DOWN ")) badTxt++;
            else if(want.state == NB_RP_INVALIDATED && !has(ttl, "THESIS INVALIDATED")) badTxt++;
            else if(want.state == NB_RP_NONE && !has(st, "none - ")) badTxt++;
            for(auto &kv : SIM.objs)
               if(kv.first.compare(0, 9, "NBLP_Y_rp") == 0 && cps(kv.second.s[OBJPROP_TEXT]) > 63) too++;
            OnDeinit(0);
         }
         std::printf("    %d moments; states NONE %d TREND %d PULLBACK %d CANDIDATE %d INVALIDATED %d\n", moments, seen[0], seen[1], seen[2], seen[3], seen[4]);
         CHECK(moments > 150 && seen[NB_RP_TREND] + seen[NB_RP_PULLBACK] > 0, "the fixture has aligned regimes (else this proves nothing)");
         CHECK(bad == 0, "the indicator's regime, state, why, structure, leg and record = the independent run");
         CHECK(badTxt == 0, "the strip names the state; a candidate shows its entry / SL");
         CHECK(buyInBear == 0, "no BUY candidate from a bearish regime");
         CHECK(too == 0, "within 63 characters");
         // injected (candidates are rare on random data): the strip and the bridge show exactly the engine's candidate
         load(m);
         SIM.now = m.m5[12 * 288 + 50].t + 320;
         start();
         if(g_fresh && !g_rp.empty())
         {
            int i5 = g_s5.n - 1;
            NbRpRec rc;
            rc.idx = i5; rc.dir = NB_SELL; rc.entry = NormalizeDouble(g_s5.c[i5], m.digits); rc.sl = NormalizeDouble(rc.entry + 30 * m.tick, m.digits);
            rc.target = NormalizeDouble(rc.entry - 60 * m.tick, m.digits); rc.rr = 2.0; rc.status = NB_RPO_OPEN; rc.outIdx = -1;
            g_rpRec.push_back(rc);
            g_nRp = (int)g_rpRec.size();
            NbRpBar &b = g_rp.back();
            b.regime = NB_SELL; b.state = NB_RP_CANDIDATE; b.why = NB_RPW_CANDIDATE; b.cand = g_nRp - 1; b.level = rc.sl + 10 * m.tick;
            b.atLoc = true; b.swept = false; b.rejected = true; b.rr = 2.0; b.pullAtr = 1.2;
            NbNyStripDraw();
            CHECK(Y("rph") == "SELL PULLBACK / RE-ENTRY CANDIDATE" && Y("rpst") == "entry " + px(rc.entry, m.digits) + "  SL " + px(rc.sl, m.digits) +
                  "  TP " + px(rc.target, m.digits) + "  R:R 2.0", "injected candidate: title and prices on the strip");
            CHECK(has(Y("rpc2"), "5 close YES") && has(Y("rpc2"), "6 R:R 2.0"), "the checklist says all six");
            std::string rj = NbBrRegime();
            CHECK(has(rj, "\"state\":\"SELL PULLBACK / RE-ENTRY CANDIDATE\"") && has(rj, "\"side\":\"SELL\"") &&
                  has(rj, "\"entry\":" + px(rc.entry, m.digits)) && has(rj, "\"not_a_signal\":true") && has(rj, "\"regime\":\"BEARISH\""),
                  "the bridge: direction BEARISH, location = the SELL candidate, not a signal");
            CHECK(g_final != NB_BUY || g_s5.state[i5] == NB_BUY, "the candidate never changes the main engine");
            b.state = NB_RP_INVALIDATED; b.why = NB_RPW_INVALIDATED; b.cand = -1;
            NbNyStripDraw();
            CHECK(Y("rph") == "BEARISH THESIS INVALIDATED" && has(Y("rpst"), "wait for bullish confirmation") &&
                  has(NbBrRegime(), "\"state\":\"BEARISH THESIS INVALIDATED\""), "injected invalidation: strip and bridge");
         }
         else
            CHECK(false, "fixture moment is fresh with regime rows");
         OnDeinit(0);
         load(m, false);                          // MT5 has no 1H / 4H history
         SIM.now = m.m5[12 * 288 + 50].t + 320;
         start();
         CHECK(!g_htfOk && Y("rpst") == "none - 1H / 4H data missing", "no 1H / 4H: said, never substituted");
         OnDeinit(0);
         load(m);
         SIM.now = m.m5[12 * 288 + 50].t + 320;
         SIM.tickTime = SIM.now - 3600;
         start();
         CHECK(Y("rpst") == "---  (data stale - no watch)" && Y("rpc1") == " ", "stale data: no regime watch shown");
         OnDeinit(0);
      }
      end(title);
   }

   //============================================================ v1.07: MARKET chip, clock, PC time
   for(int mi = 0; mi < 2; mi++)
   {
      Metal m = makeMetal(mi == 1, mi == 1 ? 11 : 7);
      const char *tag = m.silver ? "XAGUSD" : "XAUUSD";
      char title[160];
      std::snprintf(title, sizeof title, "Y5 %s: the MARKET chip on the left box = the engine; stale = no state", tag);
      begin(title);
      {
         int moments = 0, bad = 0, too = 0;
         std::map<std::string, int> seen;
         for(size_t k = 11 * 288; k + 1 < m.m5.size(); k += 11)
         {
            long long now = m.m5[k].t + 320;
            Ref r;
            reference(m, now, r);
            load(m);
            SIM.now = now;
            start();
            if(!g_fresh) { OnDeinit(0); continue; }
            double dist; int fl; double wd;
            int want = NbMarketState(r.s15, r.s15.n - 1, r.s5.dir.back(), dist, fl, wd);
            std::string chip = P("mk");
            if(chip != "MARKET: " + NbMarketStateText(want) && !(want == NB_MK_UNKNOWN && chip == "MARKET ---")) bad++;
            if(want != NB_MK_UNKNOWN && !has(P("mkd"), "6h: " + std::to_string(fl) + " flips")) bad++;
            if(cps(chip) > 63 || cps(P("mkd")) > 63) too++;
            seen[chip]++;
            OnDeinit(0);
            moments++;
         }
         std::printf("    %d moments:", moments);
         for(auto &kv : seen) std::printf("  %s x%d", kv.first.c_str(), kv.second);
         std::printf("\n");
         CHECK(moments > 80 && seen.size() >= 3, "the fixture shows at least three market states");
         CHECK(bad == 0, "chip and detail = the independent engine run");
         CHECK(too == 0, "within 63 characters");
         Metal gap = m;
         load(gap);
         SIM.now = m.m5[12 * 288 + 50].t + 320;
         SIM.tickTime = SIM.now - 3600;
         start();
         CHECK(P("mk") == "MARKET ---" && has(P("mkd"), "stale"), "dead feed: no market state");
         OnDeinit(0);
      }
      end(title);
   }

   begin("Y6 v1.07 clock on the whole indicator: Oct 27 2026 (EU winter, US summer) = NY 15:30; PC time shown; two witnesses or no clock");
   {
      long long dOct = 0;
      for(long k = 20000; k < 22000; k++) { int y, mo, d; NbCivil(k, y, mo, d); if(y == 2026 && mo == 10 && d == 13) { dOct = k * 86400LL; break; } }
      Metal m = makeMetal(false, 7);
      m.m5 = gen5m(7, 16 * 288, dOct, m.price, m.tick, m.vol);
      m.m15 = agg(m.m5, 900);
      load(m);
      SIM.gmtOff = 2 * 3600;     // the broker is on EET (UTC+2) after Oct 25
      SIM.localOff = 1 * 3600;   // the PC in Poland is on CET (UTC+1)
      long long day = dOct + 14 * 86400;   // Tuesday Oct 27
      SIM.now = day + 15 * 3600 + 5 * 60 + 20;   // 15:05 broker
      start();
      CHECK(has(P("ny"), "NY OPEN 15:30 in") || has(P("vny"), "NY OPEN 15:30 in") || [&] { for(auto &kv : SIM.objs) if(kv.first.compare(0, 7, "NBLP_P_") == 0 && has(kv.second.s[OBJPROP_TEXT], "NY OPEN 15:30 in")) return true; return false; }(),
            "main panel: NY OPEN 15:30 (the typed 16:30 would be an hour late this week)");
      CHECK(has(Y("h"), "NY TRAP  15:30-17:00") && has(Y("h"), "(PC 14:30-16:00)"), "NY rows: window 15:30-17:00 broker = 14:30-16:00 on the PC");
      CHECK(has(SIM.files["NRTR_BRIDGE\\XAUUSD.json"], "AUTO: server = UTC+2.0"), "the bridge file says which clock it used");
      OnDeinit(0);
      load(m);
      SIM.gmtOff = 2 * 3600 + 7 * 60;   // the witnesses disagree by 7 minutes: no clock, never guessed
      SIM.now = day + 15 * 3600 + 5 * 60 + 20;
      start();
      CHECK(g_N.openSec < 0 && has(Y("s_st"), "NY clock unknown"), "witnesses disagree: the NY trap is OFF and says why");
      bool unknownRow = false;
      for(auto &kv : SIM.objs) if(kv.first.compare(0, 7, "NBLP_P_") == 0 && has(kv.second.s[OBJPROP_TEXT], "NY CLOCK UNKNOWN")) unknownRow = true;
      CHECK(unknownRow, "and the main panel's NY row says NY CLOCK UNKNOWN");
      OnDeinit(0);
   }
   end("Y6");
#endif

#ifdef NYT_LADDER

   //============================================================ ladder build (InpLadderShow = true)
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
            // step 2 says CONFIRMED exactly when the engine's closed-candle decision is BUY / SELL
            if(has(L("t2"), "TIMING = CONFIRMED") != (g_final == NB_BUY || g_final == NB_SELL)) bad++;
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
               if(!linesOk(s, sd ? "B_" : "S_")) badLine++;
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
#endif

#ifdef NYT_LADDER
   std::printf("\nDECISION LADDER TESTS (metals, InpLadderShow = true): %d checks passed, %d failed\n", g_pass, g_fail);
#else
   std::printf("\nNY TRAP + NY STRIP TESTS (metals): %d checks passed, %d failed\n", g_pass, g_fail);
#endif
   return g_fail == 0 ? 0 : 1;
}
