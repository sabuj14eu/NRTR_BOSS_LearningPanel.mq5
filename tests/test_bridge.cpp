// v1.07 DATA BRIDGE + COUNTER-TREND WATCH (twins). The complete .mq5
// (translated syntax-only) runs on the simulated terminal:
//   P*  the watch engine NbRunPw on hand-made bars, prices worked out by hand
//   B*  the whole indicator: the file it writes (name, folder, flags, when),
//       the watch strip, stale data, a failing disk, an unsupported symbol
// The JSON itself is checked by tests/test_bridge_py.py against an
// EXPECTED file this test writes from the raw simulated history and an
// independent engine run (build/bridge_expect_<market>.json).
#include "../tests/mt5_sim.h"
#if NB_TEST_MARKET == 2
#include "full_forex.inc"
#elif NB_TEST_MARKET == 1
#include "full_crypto.inc"
#else
#include "full.inc"       // the metals file: 0 = XAUUSD, 3 = XAGUSD
#define METALS 1
#endif
#ifdef METALS
#define PFX "NBLP_"
#define STRIP_BG PFX "Y_bg"      // the watch rows live on the metals NY strip
#define WPFX PFX "Y_w"
#else
#define PFX "NBSP_"
#define STRIP_BG PFX "W_bg"
#define WPFX PFX "W_"
#endif
#include "../tests/synth.h"
#include <cstdio>
#include <fstream>

static int g_pass = 0, g_fail = 0, g_sec = 0;
#define CHECK(cond, msg)                                                   \
   do {                                                                    \
      if(cond) g_pass++;                                                   \
      else { g_fail++; std::printf("    FAIL %s:%d  %s\n", __FILE__, __LINE__, msg); } \
   } while(0)
static void begin(const char *n) { g_sec = g_fail; std::printf("[ RUN  ] %s\n", n); }
static void end(const char *n) { std::printf("[ %s ] %s\n", g_fail == g_sec ? " OK " : "FAIL", n); }
static bool has(const std::string &s, const std::string &sub) { return s.find(sub) != std::string::npos; }
static bool near(double a, double b) { return std::fabs(a - b) < 1e-9; }

static const long long T0 = 1788220800LL;
#if NB_TEST_MARKET == 2
static const char *SYM = "EURUSD", *BASE = "EUR", *QUOTE = "USD", *MKT = "FOREX", *TAG = "forex";
static const int DIGITS = 5;
static const double TICK = 0.00001, PRICE = 1.08, VOL = 0.0004;
#elif NB_TEST_MARKET == 0
static const char *SYM = "XAUUSD", *BASE = "XAU", *QUOTE = "USD", *MKT = "METALS", *TAG = "gold";
static const int DIGITS = 2;
static const double TICK = 0.01, PRICE = 2400.0, VOL = 0.8;
#elif NB_TEST_MARKET == 3
static const char *SYM = "XAGUSD", *BASE = "XAG", *QUOTE = "USD", *MKT = "METALS", *TAG = "silver";
static const int DIGITS = 3;
static const double TICK = 0.001, PRICE = 30.0, VOL = 0.02;
#else
static const char *SYM = "BTCUSD", *BASE = "BTC", *QUOTE = "USD", *MKT = "CRYPTO", *TAG = "crypto";
static const int DIGITS = 2;
static const double TICK = 0.01, PRICE = 60000.0, VOL = 40.0;
#endif
static const std::string FILE_JSON = std::string("NRTR_BRIDGE\\") + SYM + ".json";
static const std::string FILE_TMP = std::string("NRTR_BRIDGE\\") + SYM + ".tmp";

struct Market { std::vector<SBar> m5, m15; };
static bool g_realVol = false;   // v1.09: does this "broker" report real volume? (CFD brokers: no = 0 in MqlRates)
static std::vector<MqlRates> toRates(const std::vector<SBar> &v)
{
   std::vector<MqlRates> r;
   long long k = 0;
   for(const SBar &b : v)
   {
      r.push_back({b.t, b.o, b.h, b.l, b.c, 100 + (k % 37), 0, g_realVol ? 5000 + (k % 101) : 0});   // volumes vary: copied, not assumed
      k++;
   }
   return r;
}
static void load(const Market &m, const char *sym = SYM, const char *base = BASE)
{
   SIM = SimState();
   SIM.sym = sym; SIM.base = base; SIM.profit = QUOTE; SIM.digits = DIGITS; SIM.tick = TICK;
   SIM.tickValue = TICK * 100.0; SIM.volMin = 0.01; SIM.gmtOff = 3 * 3600;
   SIM.m5 = toRates(m.m5); SIM.m15 = toRates(m.m15);
   SIM.m60 = toRates(agg(m.m5, 3600)); SIM.m240 = toRates(agg(m.m5, 14400));
   _Symbol = sym;
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
static int start()
{
   int v = simVisible(PERIOD_M5);   // a live terminal has a quote before the indicator starts
   if(v > 0 && SIM.bid <= 0.0) SIM.bid = SIM.m5[(size_t)v - 1].close;
   int rc = OnInit();
   calc();
   return rc;
}
static std::string W(const std::string &id) { return SIM.objs.count(WPFX + id) ? SIM.objs[WPFX + id].s[OBJPROP_TEXT] : "<missing>"; }
static int countPrefix(const std::string &p)
{
   int n = 0;
   for(auto &kv : SIM.objs) if(kv.first.compare(0, p.size(), p) == 0) n++;
   return n;
}
static int cps(const std::string &u) { int n = 0; for(unsigned char ch : u) if((ch & 0xC0) != 0x80) n++; return n; }
static int countSub(const std::string &s, const std::string &sub)
{
   int n = 0;
   for(size_t p = s.find(sub); p != std::string::npos; p = s.find(sub, p + 1)) n++;
   return n;
}
static std::string px(double v) { return DoubleToString(v, DIGITS); }

//--- independent engine run (same functions, own inputs) on the bars MT5 would load at `now`
struct Ref
{
   NbSeries s5, s15;
   std::vector<NbPivot> p15, p5;
   std::vector<NbSignal> sig;
   int nSig = 0;
   std::vector<NbPwRec> pw;
   int nPw = 0, cur = -1;
#ifdef METALS
   std::vector<NbNytBar> nt;
   int mk = 0, mkFlips = 0;
   double mkDist = 0.0, mkWidth = 0.0;
#endif
};
static void reference(const Market &m, long long now, Ref &r)
{
   NbParams P;
   P.atrPeriod = InpNrtrAtrPeriod; P.nrtrMult = InpNrtrMultiplier; P.emaPeriod = InpEmaPeriod;
   P.swing = InpSwingStrength; P.slBufAtr = InpSlBufferAtr; P.tp1R = InpTp1R; P.tp2R = InpTp2R;
   P.validBars = InpSignalValidBars; P.tick = TICK; P.digits = DIGITS;
#ifndef METALS
   NbSessCfg S;
   S.clockMode = NB_CLK_AUTO; S.clockOk = true; S.offset = 3 * 3600; S.manualOpenSec = 0;
   S.preHours = InpPreNyRangeHours; S.winMin = InpNyWindowMinutes; S.minRangeBars = InpMinRangeBars; S.pauseFlow = InpNyPauseFlow;
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
#ifdef METALS
   NbRun5(r.s5, r.p5, r.s15, true, P, r.sig, r.nSig);
   NbNytCfg N;   // the NY trap layer with the simulator's broker: UTC+3, AUTO clock
   N.openSec = 0; N.autoClock = true; N.offset = 3 * 3600; N.preHours = InpNytRangeHours; N.winMin = InpNytWindowMin;
   N.minBars = InpNytMinBars; N.slBufAtr = InpSlBufferAtr; N.slBufMult = (NB_TEST_MARKET == 3) ? InpFqSilverSlMult : 1.0;
   N.confirmAtr = (NB_TEST_MARKET == 3) ? InpFqSilverConfirmAtr : 0.0; N.refAtr = InpNytRefAtr; N.tp1R = InpTp1R; N.tp2R = InpTp2R;
   N.validBars = InpSignalValidBars; N.tick = TICK; N.digits = DIGITS;
   NbRunNyt(r.s5, true, N, r.nt);
   r.mk = NbMarketState(r.s15, r.s15.n - 1, r.s5.dir.back(), r.mkDist, r.mkFlips, r.mkWidth);
#else
   NbRun5(r.s5, r.p5, r.s15, true, P, S, r.sig, r.nSig);
#endif
   r.nPw = NbRunPw(r.s5.h, r.s5.l, r.s5.c, r.s5.atr, r.s5.flip, r.s5.stop, r.s5.boss, r.s5.n, true, InpSlBufferAtr, InpTp1R,
                   InpSignalValidBars, TICK, DIGITS, r.pw, r.cur);
}

//--- the EXPECTED file for the Python check: raw bars from the simulated history
//    itself (not through the indicator), indicators from the independent run
static void writeExpect(const Market &m, long long now, const Ref &r, const std::string &path)
{
   auto bars = [&](const std::vector<SBar> &v, int sec, bool forming) {
      std::vector<SBar> closed;
      SBar fm{};
      bool hasF = false;
      for(const SBar &b : v)
      {
         if(b.t + sec <= now) closed.push_back(b);
         else if(b.t <= now) { fm = b; hasF = true; }
      }
      std::string o;
      if(forming)
      {
         if(!hasF) return std::string("null");
         char buf[256];
         std::snprintf(buf, sizeof buf, "{\"ts\":%lld,\"o\":%.*f,\"h\":%.*f,\"l\":%.*f,\"c\":%.*f}", fm.t, DIGITS, fm.o, DIGITS, fm.h, DIGITS, fm.l,
                       DIGITS, fm.c);
         return std::string(buf);
      }
      size_t first = closed.size() > 18 ? closed.size() - 18 : 0;
      o = "[";
      for(size_t k = first; k < closed.size(); k++)
      {
         char buf[256];
         std::snprintf(buf, sizeof buf, "%s{\"ts\":%lld,\"o\":%.*f,\"h\":%.*f,\"l\":%.*f,\"c\":%.*f}", k > first ? "," : "", closed[k].t, DIGITS,
                       closed[k].o, DIGITS, closed[k].h, DIGITS, closed[k].l, DIGITS, closed[k].c);
         o += buf;
      }
      return o + "]";
   };
   auto ind = [&](const NbSeries &s, bool is15) {
      std::string o = "[";
      int first = s.n > 18 ? s.n - 18 : 0;
      for(int k = first; k < s.n; k++)
      {
         char buf[320];
         if(is15)
            std::snprintf(buf, sizeof buf, "%s{\"ts\":%lld,\"dir\":%d,\"stop\":%.*f,\"atr\":%.*f,\"ema\":%.*f,\"mode\":%d}", k > first ? "," : "",
                          (long long)s.t[(size_t)k], s.dir[(size_t)k], DIGITS, s.stop[(size_t)k], DIGITS + 1, s.atr[(size_t)k], DIGITS,
                          s.ema[(size_t)k], s.mode[(size_t)k]);
         else
            std::snprintf(buf, sizeof buf, "%s{\"ts\":%lld,\"dir\":%d,\"stop\":%.*f,\"atr\":%.*f,\"state\":%d,\"boss\":%d}", k > first ? "," : "",
                          (long long)s.t[(size_t)k], s.dir[(size_t)k], DIGITS, s.stop[(size_t)k], DIGITS + 1, s.atr[(size_t)k], s.state[(size_t)k],
                          s.boss[(size_t)k]);
         o += buf;
      }
      return o + "]";
   };
   std::string pw = "null";
   if(r.cur >= 0)
   {
      char buf[256];
      const NbPwRec &p = r.pw[(size_t)r.cur];
      std::snprintf(buf, sizeof buf, "{\"dir\":%d,\"entry\":%.*f,\"sl\":%.*f,\"tp1\":%.*f}", p.dir, DIGITS, p.entry, DIGITS, p.sl, DIGITS, p.tp1);
      pw = buf;
   }
   int n = 0, tp = 0, sl = 0, ex = 0;
   double net = 0.0;
   NbPwStats(r.pw, r.nPw, InpTp1R, n, tp, sl, ex, net);
   std::ofstream f(path);
   f << "{\"symbol\":\"" << SYM << "\",\"market\":\"" << MKT << "\",\"digits\":" << DIGITS << ",\"now\":" << now
     << ",\"m5_closed\":" << bars(m.m5, 300, false) << ",\"m5_forming\":" << bars(m.m5, 300, true)
     << ",\"m15_closed\":" << bars(m.m15, 900, false) << ",\"m15_forming\":" << bars(m.m15, 900, true)
     << ",\"m5_ind\":" << ind(r.s5, false) << ",\"m15_ind\":" << ind(r.s15, true)
     << ",\"boss\":" << r.s15.mode.back() << ",\"state\":" << r.s5.state.back() << ",\"pw_open\":" << pw
     << ",\"pw_record\":{\"n\":" << n << ",\"tp1\":" << tp << ",\"sl\":" << sl << ",\"expired\":" << ex << "}";
#ifdef METALS
   auto side = [&](const NbNytSide &t) {
      char buf[320];
      bool pxs = (t.state != NB_NT_OFF && t.level > 0.0 && t.sl > 0.0);
      std::snprintf(buf, sizeof buf, "{\"state\":\"%s\",\"why\":\"%s\",\"has_prices\":%s,\"entry\":%.*f,\"sl\":%.*f,\"tp1\":%.*f,\"tp2\":%.*f,\"ref\":%s}",
                    NbNytStateText(t.state).c_str(), NbNytWhyText(t.why).c_str(), pxs ? "true" : "false", DIGITS, t.entry, DIGITS, t.sl, DIGITS,
                    t.tp1, DIGITS, t.tp2, t.estimate ? "true" : "false");
      return std::string(buf);
   };
   const NbNytBar &b = r.nt.back();
   f << ",\"ny_session\":" << (b.sid >= 0 ? "true" : "false") << ",\"ny_sell\":" << side(b.sell) << ",\"ny_buy\":" << side(b.buy)
     << ",\"pre_ny_high\":" << DoubleToString(b.rh, DIGITS) << ",\"pre_ny_low\":" << DoubleToString(b.rl, DIGITS)
     << ",\"market_state\":\"" << NbMarketStateText(r.mk) << "\"";
#endif
   f << "}\n";
}
static void dumpFile(const std::string &path)
{
   std::ofstream f(path);
   f << SIM.files[FILE_JSON];
}

//--- hand-made bars for the engine cases: 10 bars, flip / boss set per case
struct HandBars
{
   std::vector<double> h, l, c, atr, stop;
   std::vector<int> flip, boss;
   void add(double hh, double ll, double cc, int fl, double st, int bs)
   {
      h.push_back(hh); l.push_back(ll); c.push_back(cc); atr.push_back(1.0); flip.push_back(fl); stop.push_back(st); boss.push_back(bs);
   }
   int run(std::vector<NbPwRec> &rec, int &cur, bool lastClosed = true, int valid = 6)
   {
      return NbRunPw(h, l, c, atr, flip, stop, boss, (int)c.size(), lastClosed, 0.10, 1.0, valid, 0.01, 2, rec, cur);
   }
};

int main()
{
   std::printf("file under test: %s on %s\n", MKT, SYM);
   //============================================================ engine
   begin("P1 BUY WATCH: 15M SELL MODE + 5M NRTR flips up on a closed bar - exact ref prices; TP1");
   {
      HandBars b;
      b.add(100.5, 99.5, 100.0, 0, 101.0, NB_SELL);
      b.add(101.2, 100.1, 101.0, +1, 99.40, NB_SELL);    // flip up: entry 101.00, SL 99.40 - 0.10 = 99.30, risk 1.70, TP1 102.70
      b.add(101.5, 100.6, 101.2, 0, 99.60, NB_SELL);
      b.add(102.8, 101.0, 102.5, 0, 99.90, NB_SELL);     // high 102.80 >= 102.70
      std::vector<NbPwRec> r;
      int cur = -2;
      int n = b.run(r, cur);
      CHECK(n == 1 && r[0].idx == 1 && r[0].dir == NB_BUY, "one BUY watch at the flip bar");
      CHECK(near(r[0].entry, 101.0) && near(r[0].sl, 99.30) && near(r[0].risk, 1.70) && near(r[0].tp1, 102.70), "entry 101.00, SL 99.30, risk 1.70, TP1 102.70");
      CHECK(r[0].status == NB_PW_TP1 && r[0].outIdx == 3 && cur == -1, "bar 3 reaches TP1; nothing open after");
      std::printf("    BUY WATCH: entry %.2f SL %.2f TP1 %.2f\n", r[0].entry, r[0].sl, r[0].tp1);
   }
   end("P1");

   begin("P2 SELL WATCH mirror; SL wins a candle that touches both; expiry");
   {
      HandBars b;
      b.add(100.5, 99.5, 100.0, 0, 99.0, NB_BUY);
      b.add(100.2, 98.9, 99.0, -1, 100.40, NB_BUY);      // flip down: SL 100.40 + 0.10 = 100.50, risk 1.50, TP1 97.50
      b.add(100.6, 97.4, 99.0, 0, 100.30, NB_BUY);       // touches SL AND TP1
      std::vector<NbPwRec> r;
      int cur = -2;
      b.run(r, cur);
      CHECK(r.size() == 1 && r[0].dir == NB_SELL && near(r[0].sl, 100.50) && near(r[0].tp1, 97.50), "SELL: SL 100.50, TP1 97.50");
      CHECK(r[0].status == NB_PW_SL && r[0].outIdx == 2, "SL and TP1 in one candle = SL (tick order unknown)");
      HandBars x;
      x.add(100.5, 99.5, 100.0, 0, 99.0, NB_BUY);
      x.add(100.2, 98.9, 99.0, -1, 100.40, NB_BUY);
      for(int k = 0; k < 6; k++) x.add(99.3, 98.7, 99.0, 0, 100.30, NB_BUY);
      std::vector<NbPwRec> rx;
      x.run(rx, cur);
      CHECK(rx[0].status == NB_PW_EXPIRED && rx[0].outIdx == 7 && cur == -1, "6 bars without SL / TP1 = expired at bar 7");
   }
   end("P2");

   begin("P3 no watch WITH the boss, with the boss in WAIT, or without a flip; one at a time");
   {
      HandBars b;
      b.add(101.2, 100.1, 101.0, +1, 99.40, NB_BUY);     // flip up in BUY MODE: that is the main engine's business
      b.add(101.2, 100.1, 101.0, +1, 99.40, NB_WAIT);    // boss WAIT: nothing to pull back against
      b.add(101.2, 100.1, 101.0, 0, 99.40, NB_SELL);     // no flip
      b.add(98.2, 97.1, 98.0, -1, 99.40, NB_SELL);       // flip down in SELL MODE: with the boss
      std::vector<NbPwRec> r;
      int cur = -2;
      CHECK(b.run(r, cur) == 0 && cur == -1, "no watch in any of the four");
      HandBars o;
      o.add(101.2, 100.1, 101.0, +1, 99.40, NB_SELL);    // opens
      o.add(101.3, 100.2, 101.1, -1, 102.0, NB_SELL);
      o.add(101.4, 100.3, 101.2, +1, 99.50, NB_SELL);    // a second flip up while the first is open: ignored
      std::vector<NbPwRec> ro;
      CHECK(o.run(ro, cur) == 1 && cur == 0, "one watch at a time; still open at the end");
   }
   end("P3");

   begin("P4 the forming bar is never evaluated; a stop on the wrong side is no watch");
   {
      HandBars b;
      b.add(100.5, 99.5, 100.0, 0, 101.0, NB_SELL);
      b.add(101.2, 100.1, 101.0, +1, 99.40, NB_SELL);    // this bar still forming
      std::vector<NbPwRec> r;
      int cur = -2;
      CHECK(b.run(r, cur, false) == 0 && cur == -1, "forming flip bar: no watch");
      CHECK(b.run(r, cur, true) == 1, "same bar closed: a watch");
      HandBars w;
      w.add(101.2, 100.1, 101.0, +1, 101.50, NB_SELL);   // BUY with the stop ABOVE the close
      CHECK(w.run(r, cur) == 0, "stop above a BUY entry = no watch");
   }
   end("P4");

   begin("P5 the record: TP1 +1R, SL -1R, expired 0R, the open one not counted");
   {
      std::vector<NbPwRec> r(4);
      r[0].status = NB_PW_TP1; r[1].status = NB_PW_SL; r[2].status = NB_PW_EXPIRED; r[3].status = NB_PW_OPEN;
      int n, tp, sl, ex;
      double net;
      NbPwStats(r, 4, 1.0, n, tp, sl, ex, net);
      CHECK(n == 3 && tp == 1 && sl == 1 && ex == 1 && near(net, 0.0), "n 3 (open excluded), TP1 1, SL 1, expired 1, net 0R");
   }
   end("P5");

   //============================================================ whole indicator
   Market mk;
   mk.m5 = gen5m(7, 16 * 288, T0, PRICE, TICK, VOL);
   mk.m15 = agg(mk.m5, 900);

   begin("B1 the file: Files\\Common\\NRTR_BRIDGE\\<SYMBOL>.json, write-only, temp file renamed, nothing else");
   {
      load(mk);
      SIM.now = mk.m5[12 * 288 + 50].t + 137;
      CHECK(start() == INIT_SUCCEEDED, "init ok");
      CHECK(SIM.files.count(FILE_JSON) == 1 && SIM.files.size() == 1, "exactly one file, the symbol's .json (no .tmp left)");
      int fl = SIM.fileFlags[FILE_JSON];
      CHECK((fl & FILE_WRITE) && (fl & FILE_COMMON) && !(fl & FILE_READ), "opened write-only in the COMMON folder");
      const std::string &j = SIM.files[FILE_JSON];
      CHECK(j.size() > 2000 && j.compare(0, 2, "{\n") == 0 && j.substr(j.size() - 2) == "}\n", "a whole JSON object");
      CHECK(has(j, "\"schema\":\"nrtr_bridge/1\"") && has(j, std::string("\"market\":\"") + MKT + "\"") && has(j, std::string("\"symbol\":\"") + SYM + "\""),
            "schema, market, symbol");
      size_t pRaw = j.find("\"raw\":"), pInd = j.find("\"indicators\":"), pSt = j.find("\"structure\":"), pSig = j.find("\"mt5_signal\":");
      CHECK(pRaw < pInd && pInd < pSt && pSt < pSig && pSig != std::string::npos, "sections in order: raw, indicators, structure, mt5_signal");
      CHECK(!has(j.substr(0, pSig), "\"action\"") && !has(j.substr(0, pSig), "\"final\""), "no conclusion inside the raw / indicator / structure sections");
      CHECK(countSub(j.substr(pRaw, pInd - pRaw), "\"ts\":") == 2 * 18 + 2, "raw: 18 closed + 1 forming per timeframe");
      CHECK(has(j, "\"not_a_signal\":true") && has(j, "\"change_key\":"), "the watch is marked not a signal; a change key is present");
      CHECK(countPrefix(WPFX) >= 4 && has(W("h"), "NOT A SIGNAL"), "the watch rows are drawn and say NOT A SIGNAL");
      // v1.09 schema
      CHECK(countSub(j, "\"forming\":false,\"confirmed\":true") == 2 * 18 && countSub(j, "\"forming\":true,\"confirmed\":false") == 2,
            "every closed candle: forming false / confirmed true; the two forming candles: forming true / confirmed false");
      CHECK(countSub(j, "FORMING / PREVIEW ONLY / NEVER A SIGNAL") == 2, "both forming candles carry the label");
      CHECK(has(j, "\"mt5_order_action\":\"NONE\",\"read_only\":true") && has(j, "\"fresh\":true,\"freshness\""), "order action NONE, read only, fresh at the top");
      CHECK(countSub(j, "\"real_volume\":null") == 2 * 18 + 2, "this broker gives no real volume: null on every candle, never 0");
      CHECK(has(j, "\"ask\":") && has(j, "\"spread_points\":25,") && has(j, "\"full_data\":\"18 CLOSED + FORMING per timeframe (M5, M15)\""),
            "ask, spread in points (MT5's), full-data note");
      CHECK(has(j, "\"market_state\":") && has(j, "\"regime_pullback\":"), "market_state and regime_pullback keys in every file (null where none)");
#ifdef METALS
      CHECK(has(j, "\"regime_pullback\":{\"applicable\":true,\"not_a_signal\":true"), "metals: the regime pullback, not a signal");
#else
      CHECK(has(j, "\"market_state\":null,\"regime_pullback\":null"), "twins: null, not invented");
#endif
      bool ascii = true;
      for(unsigned char ch : j) if(ch > 126 || (ch < 32 && ch != '\n')) ascii = false;
      CHECK(ascii, "plain ASCII");
      Ref r;
      reference(mk, SIM.now, r);
      writeExpect(mk, SIM.now, r, std::string("build/bridge_expect_") + TAG + ".json");
      dumpFile(std::string("build/bridge_") + TAG + ".json");
      OnDeinit(0);
   }
   end("B1");

   begin("B2 when it writes: each new closed 5M bar, else every InpBridgeEverySec seconds");
   {
      load(mk);
      long long t0 = mk.m5[12 * 288 + 50].t + 20;
      SIM.now = t0;
      start();
      int w0 = SIM.fileWrites;
      CHECK(w0 >= 1, "written at start");
      SIM.now = t0 + 3;
      OnTimer();
      CHECK(SIM.fileWrites == w0, "3 s later, same bar: not rewritten");
      SIM.now = t0 + InpBridgeEverySec + 1;
      OnTimer();
      CHECK(SIM.fileWrites == w0 + 1, "after InpBridgeEverySec: rewritten (the forming candle moved on)");
      SIM.now = mk.m5[12 * 288 + 51].t - 4;   // 4 s before the bar closes: the timer rewrites
      OnTimer();
      CHECK(SIM.fileWrites == w0 + 2, "timer rewrite just before the close");
      SIM.now = mk.m5[12 * 288 + 51].t + 1;   // 5 s later the bar has closed: less than InpBridgeEverySec
      OnTimer();
      CHECK(SIM.fileWrites == w0 + 3, "a new closed 5M bar: rewritten at once, not InpBridgeEverySec later");
      CHECK(has(SIM.files[FILE_JSON], "\"ts\":" + std::to_string((long long)mk.m5[12 * 288 + 50].t)), "and it contains the bar that just closed");
      CHECK(has(W("br"), "BRIDGE: NRTR_BRIDGE") && has(W("br"), ".json"), "the strip names the file");
      OnDeinit(0);
   }
   end("B2");

   begin("B2b market closed (weekend / break): no forming candle - still exactly 18 closed, forming null");
   {
      Market cut = mk;
      cut.m5.resize(12 * 288 + 60);          // the feed ends here: every bar is closed
      cut.m15 = agg(cut.m5, 900);
      load(cut);
      SIM.now = cut.m5.back().t + 3600;      // an hour after the last bar
      start();
      const std::string &j = SIM.files[FILE_JSON];
      size_t pRaw = j.find("\"raw\":"), pInd = j.find("\"indicators\":");
      CHECK(countSub(j.substr(pRaw, pInd - pRaw), "\"ts\":") == 2 * 18, "18 closed per timeframe, no forming");
      CHECK(countSub(j.substr(pRaw, pInd - pRaw), "\"forming\":null") == 2, "forming: null on both timeframes");
      std::string raw5 = j.substr(pRaw, j.find("\"m15\":", pRaw) - pRaw);   // the M5 part of 'raw' only
      CHECK(has(raw5, "\"ts\":" + std::to_string((long long)cut.m5.back().t) + ","), "the last 5M bar is in 'closed'");
      CHECK(!has(raw5, "\"ts\":" + std::to_string((long long)cut.m5[cut.m5.size() - 19].t) + ","), "the 19th-last 5M bar is not");
      CHECK(has(j, "\"fresh\":false"), "and it is written as stale");
      OnDeinit(0);
   }
   end("B2b");

   begin("B8 the forming candle can never create or change a signal (M5 and M15)");
   {
      load(mk);
      long long now = mk.m5[12 * 288 + 50].t + 137;
      SIM.now = now;
      start();
      std::string a = SIM.files[FILE_JSON];
      auto part = [](const std::string &j, const std::string &from, const std::string &to) {
         size_t p = j.find(from), q = j.find(to, p);
         return (p == std::string::npos || q == std::string::npos) ? std::string("<none>") : j.substr(p, q - p);
      };
      std::string keyA = part(a, "\"change_key\":", "}"), sigA = part(a, "\"final\":", "\"ny\":"), pwA = part(a, "\"pullback_watch\":", "\"positions\":");
      std::string rpA = part(a, "\"regime_pullback\":", "\"pullback_watch\":"), fqA = part(a, "\"five_question\":", "\"pullback_watch\":");
      OnDeinit(0);
      // the same moment, but both forming candles explode (a 3% spike each way, a huge body)
      load(mk);
      SIM.now = now;
      for(auto *ser : {&SIM.m5, &SIM.m15})
         for(auto &b : *ser)
            if(b.time <= now && b.time + (ser == &SIM.m5 ? 300 : 900) > now) { b.high += PRICE * 0.03; b.low -= PRICE * 0.03; b.close = b.open + PRICE * 0.025; }
      start();
      std::string b = SIM.files[FILE_JSON];
      CHECK(a != b && part(b, "\"forming\":{", "}") != part(a, "\"forming\":{", "}"), "the file shows the new forming candle");
      CHECK(part(b, "\"change_key\":", "}") == keyA, "change_key unchanged: Telegram stays silent");
      CHECK(part(b, "\"final\":", "\"ny\":") == sigA, "final, action, reason and signal unchanged");
      CHECK(part(b, "\"pullback_watch\":", "\"positions\":") == pwA && part(b, "\"regime_pullback\":", "\"pullback_watch\":") == rpA &&
            part(b, "\"five_question\":", "\"pullback_watch\":") == fqA, "watch, regime pullback and pending plan unchanged");
      OnDeinit(0);
   }
   end("B8");

   begin("B9 what MT5 does not give is null, never invented: real volume, ask, spread");
   {
      g_realVol = true;
      load(mk);
      g_realVol = false;
      SIM.now = mk.m5[12 * 288 + 50].t + 137;
      start();
      std::string j = SIM.files[FILE_JSON];
      CHECK(countSub(j, "\"real_volume\":null") == 0 && has(j, "\"real_volume\":50"), "a broker that reports real volume: copied");
      OnDeinit(0);
      load(mk);
      SIM.now = mk.m5[12 * 288 + 50].t + 137;
      SIM.askMissing = true;
      start();
      j = SIM.files[FILE_JSON];
      CHECK(has(j, "\"ask\":null,\"spread_points\":null,\"spread_price\":null"), "no ask from MT5: ask, spread points and spread price all null");
      CHECK(!has(j, "\"bid\":null"), "the bid is still there");
      OnDeinit(0);
      load(mk);
      SIM.now = mk.m5[12 * 288 + 50].t + 137;
      start();
      SIM.ask = SIM.bid + 30 * TICK;
      SIM.now += InpBridgeEverySec + 1;
      OnTimer();
      j = SIM.files[FILE_JSON];
      CHECK(has(j, "\"ask\":" + px(SIM.ask)) && has(j, "\"spread_price\":" + px(30 * TICK)), "with an ask: ask and ask - bid");
      OnDeinit(0);
   }
   end("B9");

   begin("B10 the write is atomic: a failed rename leaves the previous file whole, and says so");
   {
      load(mk);
      SIM.now = mk.m5[12 * 288 + 50].t + 137;
      start();
      std::string before = SIM.files[FILE_JSON];
      SIM.moveFail = true;
      SIM.now = mk.m5[12 * 288 + 51].t + 5;   // a new closed bar: a rewrite is attempted
      OnTimer();
      CHECK(SIM.files[FILE_JSON] == before, "the reader still sees the previous, complete file (never half a file)");
      CHECK(has(W("br"), "WRITE FAILED"), "the strip says WRITE FAILED");
      SIM.moveFail = false;
      SIM.now += InpBridgeEverySec + 1;
      OnTimer();
      CHECK(SIM.files[FILE_JSON] != before && SIM.files[FILE_JSON].substr(SIM.files[FILE_JSON].size() - 2) == "}\n" && has(W("br"), ".json"),
            "next write succeeds, whole file, status back");
      OnDeinit(0);
   }
   end("B10");

   begin("B3 stale data is written as stale: no action, no signal, no watch");
   {
      load(mk);
      SIM.now = mk.m5[12 * 288 + 50].t + 137;
      SIM.tickTime = SIM.now - 3600;   // the feed died an hour ago
      start();
      const std::string &j = SIM.files[FILE_JSON];
      CHECK(!g_fresh && has(j, "\"fresh\":false") && has(j, "\"action\":\"NO TRADE - DATA STALE / MARKET CLOSED\""), "fresh false, NO TRADE - DATA STALE");
      CHECK(has(j, "\"signal\":null") && has(j, "\"final\":\"WAIT\"") && has(j, "\"state\":\"NONE\""), "no signal, final WAIT, no open watch");
      CHECK(has(j, "\"change_key\":\"S|"), "the change key says stale (the sender posts the change once)");
      CHECK(W("st") == "---  (data stale - no watch)", "strip: no watch from stale data");
      CHECK(has(j, "\"fresh\":false,\"freshness\""), "stale at the top level too");
#ifdef METALS
      CHECK(has(j, "\"state\":\"SUPPRESSED - DATA STALE\",\"location\":null,\"candidate\":null"), "metals: the regime pullback is suppressed");
#endif
      dumpFile(std::string("build/bridge_stale_") + TAG + ".json");
      OnDeinit(0);
   }
   end("B3");

   begin("B4 a failing disk is shown, never hidden; an unsupported symbol writes nothing");
   {
      load(mk);
      SIM.now = mk.m5[12 * 288 + 50].t + 137;
      SIM.fileFail = true;
      start();
      CHECK(SIM.files.empty() && has(W("br"), "WRITE FAILED"), "no file, strip says WRITE FAILED");
      OnDeinit(0);
#if NB_TEST_MARKET == 2
      load(mk, "BTCUSD", "BTC");
#else
      load(mk, "EURUSD", "EUR");   // crypto file, and the metals file: EURUSD is not theirs
#endif
      SIM.now = mk.m5[12 * 288 + 50].t + 137;
      start();
      CHECK(SIM.files.empty(), "unsupported symbol: no file");
      OnDeinit(0);
   }
   end("B4");

   begin("B5 the WATCH strip: on top of the table, the engine's watch and record, never a CLICK");
   {
      int moments = 0, open = 0, bad = 0, badDock = 0, too = 0, clickFromWatch = 0;
      std::string worst;
      for(size_t k = 11 * 288; k + 1 < mk.m5.size(); k += 9)
      {
         long long now = mk.m5[k].t + 320;
         Ref r;
         reference(mk, now, r);
         load(mk);
         SIM.now = now;
         start();
         if(!g_fresh) { OnDeinit(0); continue; }
         moments++;
         SimObj &wb = SIM.objs[STRIP_BG], &qb = SIM.objs[PFX "Q_bg"];
         if(wb.i[OBJPROP_XDISTANCE] != qb.i[OBJPROP_XDISTANCE] || wb.i[OBJPROP_XSIZE] != qb.i[OBJPROP_XSIZE] ||
            wb.i[OBJPROP_YDISTANCE] + wb.i[OBJPROP_YSIZE] != qb.i[OBJPROP_YDISTANCE]) badDock++;
         int n = 0, tp = 0, sl = 0, ex = 0;
         double net = 0.0;
         NbPwStats(r.pw, r.nPw, InpTp1R, n, tp, sl, ex, net);
         if(!has(W("rec"), "record n=" + std::to_string(n) + ": TP1 " + std::to_string(tp) + " / SL " + std::to_string(sl))) bad++;
         const std::string &j = SIM.files[FILE_JSON];
         if(r.cur >= 0)
         {
            open++;
            const NbPwRec &p = r.pw[(size_t)r.cur];
            std::string want = std::string(p.dir > 0 ? "BUY WATCH @ " : "SELL WATCH @ ") + px(p.entry) + "  ref SL " + px(p.sl) + "  ref TP1 " + px(p.tp1);
            if(W("st") != want) bad++;
            if(!has(j, "\"ref_entry\":" + px(p.entry)) || !has(j, "\"ref_sl\":" + px(p.sl)) || !has(j, "\"ref_tp1\":" + px(p.tp1))) bad++;
            // the watch never drives the conclusion: CLICK only when the main engine says BUY / SELL
            // a BUY / SELL action (twins: CLICK..., metals v1.10: READY - CLICK... or ...SETUP - PRICE TOO FAR) only from the main engine
            bool actOn = has(j, "\"action\":\"CLICK") || has(j, "\"action\":\"READY - CLICK") || has(j, "SETUP - PRICE TOO FAR - WAIT");
            if(actOn != (g_final == NB_BUY || g_final == NB_SELL)) clickFromWatch++;
         }
         else if(!has(W("st"), "none - ")) bad++;
         for(auto &kv : SIM.objs)
            if(kv.first.compare(0, std::string(WPFX).size(), WPFX) == 0 && kv.second.s.count(OBJPROP_TEXT) && cps(kv.second.s[OBJPROP_TEXT]) > 63)
            { too++; if(worst.empty()) worst = kv.first + ": " + kv.second.s[OBJPROP_TEXT]; }
         OnDeinit(0);
      }
      std::printf("    %d fresh moments, %d with an open watch\n", moments, open);
      CHECK(moments > 100 && open > 0, "the fixture has open watches (else this proves nothing)");
      CHECK(badDock == 0, "strip: same x and width as the table, bottom edge on its top edge");
      CHECK(bad == 0, "strip and file: the independent engine's watch prices and record");
      CHECK(clickFromWatch == 0, "an open watch never produces a CLICK");
      CHECK(too == 0, "no strip text over MT5's 63 characters");
      if(too) std::printf("    too long: %s\n", worst.c_str());
   }
   end("B5");

   begin("B6 a moment with an open watch, written for the Python check");
   {
      long long now = 0;
      for(size_t k = 11 * 288; k + 1 < mk.m5.size() && now == 0; k++)
      {
         Ref r;
         reference(mk, mk.m5[k].t + 320, r);
         if(r.cur >= 0) now = mk.m5[k].t + 320;
      }
      CHECK(now > 0, "found");
      if(now > 0)
      {
         load(mk);
         SIM.now = now;
         start();
         Ref r;
         reference(mk, now, r);
         writeExpect(mk, now, r, std::string("build/bridge_expect_watch_") + TAG + ".json");
         dumpFile(std::string("build/bridge_watch_") + TAG + ".json");
         CHECK(has(SIM.files[FILE_JSON], "\"state\":\"OPEN\""), "the file shows the open watch");
         OnDeinit(0);
      }
   }
   end("B6");

#ifdef METALS
   begin("B7 metals: a moment in the NY window with a swept / triggered trap, written for the Python check");
   {
      long long now = 0;
      for(size_t k = 11 * 288; k + 1 < mk.m5.size() && now == 0; k++)
      {
         Ref r;
         reference(mk, mk.m5[k].t + 320, r);
         const NbNytBar &b = r.nt.back();
         if(b.phase == NB_NTP_NY && (b.sell.state == NB_NT_VALID || b.sell.state == NB_NT_TRIGGERED || b.buy.state == NB_NT_VALID ||
                                     b.buy.state == NB_NT_TRIGGERED))
            now = mk.m5[k].t + 320;
      }
      CHECK(now > 0, "found");
      if(now > 0)
      {
         load(mk);
         SIM.now = now;
         start();
         Ref r;
         reference(mk, now, r);
         writeExpect(mk, now, r, std::string("build/bridge_expect_ny_") + TAG + ".json");
         dumpFile(std::string("build/bridge_ny_") + TAG + ".json");
         CHECK(has(SIM.files[FILE_JSON], "\"phase\":\"NY WINDOW\""), "the file is inside the NY window");
         OnDeinit(0);
      }
   }
   end("B7");
#endif

   std::printf("\nBRIDGE + WATCH TESTS (%s): %d checks passed, %d failed\n", TAG, g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
