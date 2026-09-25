// Whole-indicator tests for the NY-trap twins: the complete .mq5 (translated
// syntax-only) runs against the simulated MT5 terminal and the panel is read
// back from the chart objects it created. Compiled once per twin.
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
static const char *LABEL = "EURUSD NRTR BOSS";
#else
static const char *SYM = "BTCUSD", *BASE = "BTC", *QUOTE = "USD";
static const int DIGITS = 2;
static const double TICK = 0.01, PRICE = 60000.0, VOL = 40.0;
static const char *ONLY = "CRYPTO ONLY";
static const char *LABEL = "BTC NRTR BOSS";
#endif

static std::vector<MqlRates> toRates(const std::vector<SBar> &v)
{
   std::vector<MqlRates> r;
   for(const SBar &b : v) r.push_back({b.t, b.o, b.h, b.l, b.c, 100, 0, 0});
   return r;
}
struct Market { std::vector<SBar> m5, m15; };
static Market makeMarket(uint64_t seed, double price, double tick, double vol, int days)
{
   Market m;
   m.m5 = gen5m(seed, days * 288, T0, price, tick, vol);
   m.m15 = agg(m.m5, 900);
   return m;
}
static void load(const Market &m, const char *sym, const char *base, const char *quote, int digits, double tick)
{
   SIM = SimState();
   SIM.sym = sym; SIM.base = base; SIM.profit = quote; SIM.digits = digits; SIM.tick = tick;
   SIM.tickValue = tick * 100.0; SIM.volMin = 0.01; SIM.gmtOff = 3 * 3600;
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
static std::string txt(const std::string &id) { return SIM.objs.count("NBSP_P_" + id) ? SIM.objs["NBSP_P_" + id].s[OBJPROP_TEXT] : "<missing>"; }
static bool has(const std::string &s, const std::string &sub) { return s.find(sub) != std::string::npos; }
static int countPrefix(const std::string &p)
{
   int n = 0;
   for(auto &kv : SIM.objs) if(kv.first.compare(0, p.size(), p) == 0) n++;
   return n;
}

// reference computation straight from the engine, for a candidate `now`
struct Ref
{
   int state, reasons, sig, dir15, mode15, ph;
   NbSignal s;
};
static Ref reference(const Market &m, long long now)
{
   NbParams P;
   P.atrPeriod = InpNrtrAtrPeriod; P.nrtrMult = InpNrtrMultiplier; P.emaPeriod = InpEmaPeriod;
   P.swing = InpSwingStrength; P.slBufAtr = InpSlBufferAtr; P.tp1R = InpTp1R; P.tp2R = InpTp2R;
   P.validBars = InpSignalValidBars; P.tick = TICK; P.digits = DIGITS;
   NbSessCfg S;
   S.clockMode = NB_CLK_AUTO; S.clockOk = true; S.offset = 3 * 3600; S.manualOpenSec = 0;
   S.preHours = InpPreNyRangeHours; S.winMin = InpNyWindowMinutes; S.minRangeBars = InpMinRangeBars; S.pauseFlow = InpNyPauseFlow;
   long long anchor = (now / 86400) * 86400 - (long long)InpHistoryDays * 86400;
   NbSeries a, b;
   std::vector<SBar> v5, v15;
   for(const SBar &x : m.m5) if(x.t >= anchor && x.t + 300 <= now) v5.push_back(x);
   for(const SBar &x : m.m15) if(x.t >= anchor && x.t + 900 <= now) v15.push_back(x);
   NbSeriesResize(a, (int)v5.size()); a.sec = 300;
   NbSeriesResize(b, (int)v15.size()); b.sec = 900;
   for(size_t i = 0; i < v5.size(); i++) { a.t[i] = v5[i].t; a.o[i] = v5[i].o; a.h[i] = v5[i].h; a.l[i] = v5[i].l; a.c[i] = v5[i].c; }
   for(size_t i = 0; i < v15.size(); i++) { b.t[i] = v15[i].t; b.o[i] = v15[i].o; b.h[i] = v15[i].h; b.l[i] = v15[i].l; b.c[i] = v15[i].c; }
   std::vector<NbPivot> p15, p5;
   std::vector<NbSignal> sg;
   int ns = 0;
   NbRun15(b, p15, P);
   NbRun5(a, p5, b, true, P, S, sg, ns);
   Ref r;
   r.state = a.state.back(); r.reasons = a.reasons.back(); r.sig = a.sigOf.back(); r.dir15 = b.dir.back(); r.mode15 = b.mode.back(); r.ph = a.ph.back();
   if(r.sig >= 0) r.s = sg[(size_t)r.sig];
   return r;
}
template <class F> static long long findNow(const Market &m, F pred)
{
   for(size_t i = 11 * 288; i + 1 < m.m5.size(); i++)
   {
      long long now = m.m5[i].t + 300 + 20;
      Ref r = reference(m, now);
      if(pred(r)) return now;
   }
   return 0;
}

int main()
{
   std::printf("twin under test: %s on %s\n", NB_MARKET == NB_MKT_CRYPTO ? "CRYPTO" : "FOREX", SYM);
   Market mk = makeMarket(7, PRICE, TICK, VOL, 16);

   begin("I1 symbol filter: this twin's market only");
   {
      const char *rejectSym = (NB_MARKET == NB_MKT_CRYPTO) ? "EURUSD" : "BTCUSD";
      const char *rejectBase = (NB_MARKET == NB_MKT_CRYPTO) ? "EUR" : "BTC";
      load(mk, rejectSym, rejectBase, "USD", DIGITS, TICK);
      SIM.now = mk.m5[3000].t + 20;
      start();
      CHECK(has(txt("state"), ONLY), "banner names the market this file is for");
      CHECK(has(txt("r1"), ONLY), "reason too");
      CHECK(countPrefix("NBSP_C_") == 0, "no chart markings on unsupported symbols");
      bool empty = true;
      for(double x : *SIM.bufs[0]) empty = empty && x == EMPTY_VALUE;
      CHECK(empty, "no EMA plotted");
      OnDeinit(0);
      load(mk, "XAUUSD", "XAU", "USD", 2, 0.01); SIM.now = mk.m5[3000].t + 20; start();
      CHECK(has(txt("state"), ONLY), "gold rejected by both twins");
      OnDeinit(0);
      load(mk, "US100", "USD", "USD", 2, 0.01); SIM.now = mk.m5[3000].t + 20; start();
      CHECK(has(txt("state"), ONLY), "index rejected");
      OnDeinit(0);
      // accepted spellings
      const char *ok[][3] = {
#if NB_TEST_MARKET == 2
         {"EURUSD", "EUR", "USD"}, {"USDJPY.m", "USD", "JPY"}, {"#GBPUSD", "", ""}, {"AUDNZD", "AUD", "NZD"}
#else
         {"BTCUSD", "BTC", "USD"}, {"ETHUSD.m", "ETH", "USD"}, {"#SOLUSD", "", ""}, {"LTCUSD", "LTC", "USD"}, {"Bitcoin", "", "USD"}
#endif
      };
      for(auto &o : ok)
      {
         load(mk, o[0], o[1], o[2], DIGITS, TICK);
         SIM.now = mk.m5[3000].t + 20;
         start();
         char msg[120];
         std::snprintf(msg, sizeof msg, "%s accepted, title '%s'", o[0], txt("title").c_str());
         CHECK(!has(txt("state"), ONLY) && has(txt("title"), "NRTR BOSS") && !has(txt("title"), "  NRTR"), msg);
         OnDeinit(0);
      }
   }
   end("I1");

   begin("I2 structure flow: CLICK BUY / CLICK SELL rendered with the engine's exact levels");
   {
      long long nb = findNow(mk, [](const Ref &r) { return r.state == NB_BUY && r.s.kind == NB_K_FLOW; });
      long long ns = findNow(mk, [](const Ref &r) { return r.state == NB_SELL && r.s.kind == NB_K_FLOW; });
      CHECK(nb > 0 && ns > 0, "fixture contains a flow BUY and a flow SELL moment");
      for(int side = 0; side < 2 && nb > 0 && ns > 0; side++)
      {
         long long now = side == 0 ? nb : ns;
         Ref r = reference(mk, now);
         load(mk, SYM, BASE, QUOTE, DIGITS, TICK);
         SIM.now = now;
         CHECK(start() == INIT_SUCCEEDED, "init ok");
         CHECK(has(txt("title"), LABEL), "title carries the symbol label");
         CHECK(has(txt("state"), side == 0 ? "CLICK BUY" : "CLICK SELL") && !has(txt("state"), "TRAP"), "banner (flow, not trap)");
         CHECK(has(txt("v10"), DoubleToString(r.s.entry, DIGITS)), "entry printed with the symbol's digits");
         CHECK(has(txt("v11"), DoubleToString(r.s.sl, DIGITS)) && has(txt("v11"), "5M swing"), "SL from structure");
         CHECK(has(txt("v12"), DoubleToString(r.s.tp1, DIGITS)) && has(txt("v12"), "1.0R"), "TP1 = 1R");
         CHECK(has(txt("v13"), DoubleToString(r.s.tp2, DIGITS)) && has(txt("v13"), "2.0R"), "TP2 = 2R");
         CHECK(has(txt("v6"), side == 0 ? "BUY MODE" : "SELL MODE"), "15M decision row");
         CHECK(has(txt("v9"), "READY"), "5M confirm READY");
         CHECK(has(txt("vn1"), "AUTO: SERVER = UTC+3"), "session clock row: AUTO +3 from the two witnesses");
         CHECK(has(txt("vn2"), "OUTSIDE NY") || has(txt("vn2"), "PRE-NY"), "a flow signal is never inside the NY window (pause on)");
         CHECK(countPrefix("NBSP_C_L_") == 10, "entry/SL/TP1/TP2/swing lines + labels drawn");
         CHECK((side == 0 ? txt("lbB0") : txt("lbS0")) != "---" && (side == 0 ? txt("lbB1") : txt("lbS1")) != "---", "live box has a plan for the clicked side");
         CHECK(has(side == 0 ? txt("lbGb") : txt("lbGs"), "READY - CLICK"), "gate line of the clicked side reads READY - CLICK");
         CHECK(has(txt("v22"), "LOTS") || has(txt("v22"), "SKIP"), "lots for 1% risk row");
         CHECK(has(txt("v17"), "entry"), "swing TP row from the automatic 15M-ATR distance");
         CHECK(has(txt("vc5"), " UP / ") && has(txt("vc5"), "net ") && has(txt("vc5"), "ATR)"), "last 5 x 5M strip");
         CHECK(has(txt("vc15"), " UP / ") && has(txt("vc15"), "net "), "last 5 x 15M strip");
         CHECK(has(txt("vd7"), "LIVE"), "data clock says LIVE");
         CHECK(has(txt("vs"), "NY OPEN") || has(txt("vs"), "NEW YORK SESSION") || has(txt("vs"), "OUTSIDE NY"), "NEW YORK OPEN row from the session clock");
         std::printf("    %s at %s: entry %s SL %s TP1 %s TP2 %s | %s\n", side == 0 ? "BUY " : "SELL",
                     TimeToString(now, TIME_DATE | TIME_MINUTES).c_str(), DoubleToString(r.s.entry, DIGITS).c_str(),
                     DoubleToString(r.s.sl, DIGITS).c_str(), DoubleToString(r.s.tp1, DIGITS).c_str(),
                     DoubleToString(r.s.tp2, DIGITS).c_str(), txt("v15").c_str());
         OnDeinit(0);
         CHECK(countPrefix("NBSP_") == 0, "OnDeinit removes every object it created");
      }
   }
   end("I2");

   begin("I3 NY trap: CLICK SELL / BUY - NY TRAP rendered with the sweep levels");
   {
      long long ns = findNow(mk, [](const Ref &r) { return r.state == NB_SELL && r.s.kind == NB_K_TRAP; });
      long long nb = findNow(mk, [](const Ref &r) { return r.state == NB_BUY && r.s.kind == NB_K_TRAP; });
      CHECK(ns > 0 && nb > 0, "fixture contains a SELL trap and a BUY trap moment");
      for(int side = 0; side < 2 && ns > 0 && nb > 0; side++)
      {
         long long now = side == 0 ? ns : nb;
         Ref r = reference(mk, now);
         load(mk, SYM, BASE, QUOTE, DIGITS, TICK);
         SIM.now = now;
         start();
         CHECK(has(txt("state"), side == 0 ? "CLICK SELL - NY TRAP" : "CLICK BUY - NY TRAP"), "banner says NY TRAP");
         CHECK(has(txt("r1"), side == 0 ? "NY SWEPT PRE-NY HIGH" : "NY SWEPT PRE-NY LOW") && has(txt("r1"), DoubleToString(r.s.level, DIGITS)), "reason: which level was swept");
         CHECK(has(txt("r2"), "FADE THE TRAP") && has(txt("r2"), "15M WAS"), "reason: fade, and what the 15M said");
         CHECK(has(txt("v10"), DoubleToString(r.s.entry, DIGITS)), "entry");
         CHECK(has(txt("v11"), DoubleToString(r.s.sl, DIGITS)) && has(txt("v11"), "beyond the sweep") && has(txt("k11"), "sweep"), "SL beyond the sweep");
         CHECK(has(txt("v9"), "NY TRAP - STRUCTURE NOT USED"), "5M confirm row explains");
         CHECK(has(txt("vn2"), "NY WINDOW"), "phase row: NY window");
         CHECK(has(txt("vn3"), "H ") && has(txt("vn3"), "/  L "), "range row shows H / L");
         CHECK(has(txt("vn4"), side == 0 ? "SELL TRAP @" : "BUY TRAP @") && has(txt("vn4"), "active"), "trap row: fired and active");
         bool marker = false;
         for(auto &kv : SIM.objs)
            if(kv.first.compare(0, 7, "NBSP_C_G_") == 0 || kv.first.compare(0, 9, "NBSP_C_G_") == 0)
               if(has(kv.second.s[OBJPROP_TEXT], "NY TRAP")) marker = true;
         CHECK(marker, "an 'NY TRAP' marker is on the chart");
         CHECK(countPrefix("NBSP_C_R_") == 4, "pre-NY range high/low segments + labels drawn");
         std::printf("    %s trap at %s: swept %s to %s, entry %s SL %s\n", side == 0 ? "SELL" : "BUY ",
                     TimeToString(now, TIME_DATE | TIME_MINUTES).c_str(), DoubleToString(r.s.level, DIGITS).c_str(),
                     DoubleToString(r.s.sweep, DIGITS).c_str(), DoubleToString(r.s.entry, DIGITS).c_str(),
                     DoubleToString(r.s.sl, DIGITS).c_str());
         OnDeinit(0);
      }
   }
   end("I3");

   begin("I4 inside the NY window without a sweep: WAIT, flow paused, watching");
   {
      long long now = findNow(mk, [](const Ref &r) { return r.ph == NB_PH_NY && r.state == NB_WAIT && (r.reasons & NB_R_NY_WINDOW) != 0 && (r.reasons & NB_R_NY_NO_RANGE) == 0; });
      CHECK(now > 0, "fixture has a paused moment");
      load(mk, SYM, BASE, QUOTE, DIGITS, TICK);
      SIM.now = now;
      start();
      CHECK(has(txt("state"), "WAIT"), "banner WAIT");
      CHECK(has(txt("r1"), "NY OPEN WINDOW - FLOW PAUSED"), "reason names the window");
      CHECK(has(txt("v9"), "PAUSED - NY WINDOW"), "5M confirm row");
      CHECK(has(txt("vn2"), "NY WINDOW") && has(txt("vn2"), "until"), "phase row with the end time");
      CHECK(has(txt("vs"), "NY OPEN - WINDOW") && has(txt("vs"), "TRAP ARMED"), "top NEW YORK OPEN row: window running, trap armed");
      CHECK(has(txt("vn4"), "WATCHING") || has(txt("vn4"), "SWEPT TO"), "trap row: watching or swept-waiting");
      CHECK(txt("v10") == "---" && countPrefix("NBSP_C_L_") == 0, "no levels while waiting");
      OnDeinit(0);
   }
   end("I4");

   begin("I5 session clock: witnesses disagree -> module OFF, said in words, flow still runs");
   {
      long long now = findNow(mk, [](const Ref &r) { return r.state == NB_BUY && r.s.kind == NB_K_FLOW; });
      load(mk, SYM, BASE, QUOTE, DIGITS, TICK);
      SIM.now = now;
      SIM.gmtOff = 3 * 3600 + 11 * 60;   // PC clock 11 min off any zone
      start();
      CHECK(has(txt("vn1"), "UNKNOWN") && has(txt("vn1"), "SET MANUAL"), "clock row says UNKNOWN / SET MANUAL");
      CHECK(txt("vn2") == "---" && txt("vn4") == "---", "no phase, no trap when the clock is unknown");
      CHECK(!has(txt("r1"), "NY OPEN WINDOW"), "no NY reason is ever shown");
      CHECK(has(txt("vs"), "SESSION CLOCK UNKNOWN"), "top row: clock unknown");
      OnDeinit(0);
      load(mk, SYM, BASE, QUOTE, DIGITS, TICK);
      SIM.now = now;
      SIM.gmtOff = -5 * 3600;   // a UTC-5 broker
      start();
      CHECK(has(txt("vn1"), "AUTO: SERVER = UTC-5"), "negative offset printed");
      OnDeinit(0);
   }
   end("I5");

   begin("I6 existing position + 15M reversal -> EXIT / PROTECT (read only)");
   {
      long long now = 0, openT = 0;
      for(size_t i = 11 * 288; i + 1 < mk.m5.size() && now == 0; i += 3)
      {
         long long cand = mk.m5[i].t + 320;
         Ref r = reference(mk, cand);
         if(r.mode15 != NB_SELL) continue;
         for(long long back = 3600; back < 72 * 3600; back += 900)
            if(reference(mk, cand - back).mode15 == NB_BUY) { now = cand; openT = cand - back; break; }
      }
      CHECK(now > 0, "fixture has a 15M reversal");
      load(mk, SYM, BASE, QUOTE, DIGITS, TICK);
      SIM.now = now;
      SIM.pos.push_back({SYM, POSITION_TYPE_BUY, 0.10, openT});
      std::vector<SimPos> before = SIM.pos;
      start();
      CHECK(has(txt("state"), "EXIT / PROTECT BUY"), "banner EXIT / PROTECT (boss flipped BUY -> SELL mode)");
      CHECK(has(txt("r1"), "15M TREND INVALIDATED (BOSS FLIPPED)"), "reason");
      bool untouched = SIM.pos.size() == before.size() && SIM.pos[0].type == before[0].type && SIM.pos[0].vol == before[0].vol;
      CHECK(untouched, "positions unchanged (read only)");
      OnDeinit(0);
   }
   end("I6");

   begin("I7 no repaint through the terminal: a forming crash candle changes nothing (flow and trap)");
   {
      long long nows[2] = {findNow(mk, [](const Ref &r) { return r.state == NB_BUY && r.s.kind == NB_K_FLOW; }),
                           findNow(mk, [](const Ref &r) { return r.state != NB_WAIT && r.s.kind == NB_K_TRAP; })};
      for(long long now : nows)
      {
         load(mk, SYM, BASE, QUOTE, DIGITS, TICK);
         SIM.now = now;
         start();
         std::string s1 = txt("state"), e1 = txt("v10"), t1 = txt("vn4");
         OnDeinit(0);
         load(mk, SYM, BASE, QUOTE, DIGITS, TICK);
         SIM.now = now;
         for(auto *ser : {&SIM.m5, &SIM.m15})
            for(auto &b : *ser)
               if(b.time <= now && b.time + (ser == &SIM.m5 ? 300 : 900) > now) { b.low -= PRICE * 0.05; b.close -= PRICE * 0.05; b.high += PRICE * 0.05; }
         start();
         CHECK(txt("state") == s1 && txt("v10") == e1 && txt("vn4") == t1, "an unfinished crash/spike candle changes nothing");
         OnDeinit(0);
      }
   }
   end("I7");

   begin("I8 restart -> identical panel, markers and buffers");
   {
      long long now = findNow(mk, [](const Ref &r) { return r.state == NB_SELL && r.s.kind == NB_K_TRAP; });
      load(mk, SYM, BASE, QUOTE, DIGITS, TICK);
      SIM.now = now;
      start();
      auto snap1 = SIM.objs;
      std::vector<std::vector<double>> b1;
      for(auto &kv : SIM.bufs) b1.push_back(*kv.second);
      OnDeinit(0);
      start();
      bool same = snap1.size() == SIM.objs.size();
      for(auto &kv : snap1)
      {
         if(!SIM.objs.count(kv.first)) { same = false; break; }
         const SimObj &b = SIM.objs[kv.first];
         if(kv.second.s != b.s || kv.second.i != b.i || kv.second.d != b.d) same = false;
      }
      CHECK(same, "every panel label and chart object identical after restart");
      size_t k = 0;
      bool bsame = true;
      for(auto &kv : SIM.bufs) bsame = bsame && b1[k++] == *kv.second;
      CHECK(bsame, "every plot buffer identical after restart");
      std::printf("    %zu objects compared\n", snap1.size());
      OnDeinit(0);
   }
   end("I8");

   begin("I9 missing / stale data -> WAIT, never a guess (weekend for forex, frozen feed for crypto)");
   {
      load(mk, SYM, BASE, QUOTE, DIGITS, TICK);
      SIM.now = mk.m5[4000].t + 20;
      SIM.copyFail = true;
      start();
      CHECK(has(txt("state"), "WAIT") && has(txt("r1"), "MISSING DATA"), "history unavailable -> WAIT / MISSING DATA");
      SIM.copyFail = false;
      OnTimer();
      CHECK(!has(txt("r1"), "MISSING DATA"), "recovers once history loads");
      OnDeinit(0);
      load(mk, SYM, BASE, QUOTE, DIGITS, TICK);
      SIM.now = mk.m5.back().t + 30 * 3600;   // feed stopped 30 hours ago
      SIM.pos.push_back({SYM, POSITION_TYPE_BUY, 0.1, mk.m5.back().t - 3600});
      start();
      CHECK(has(txt("state"), "WAIT") && has(txt("r1"), "DATA STALE"), "stale feed -> WAIT / DATA STALE");
      CHECK(has(txt("pw"), "CANNOT JUDGE"), "position advice withheld");
      CHECK(has(txt("vd7"), "NO RECENT TICK"), "data clock names the failing witness");
      CHECK(txt("vpv") == "---", "no preview on stale data");
      OnDeinit(0);
   }
   end("I9");

   std::printf("\nSESSION INDICATOR TESTS (%s): %d checks passed, %d failed\n", NB_MARKET == NB_MKT_CRYPTO ? "crypto" : "forex", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
