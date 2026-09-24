// Whole-indicator tests: the complete .mq5 (translated syntax-only) runs
// against a simulated MT5 terminal: OnInit -> OnCalculate -> OnTimer ->
// OnDeinit, and the panel is read back from the chart objects it created.
#include "../tests/mt5_sim.h"
#include "full.inc"
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

static std::vector<MqlRates> toRates(const std::vector<SBar> &v)
{
   std::vector<MqlRates> r;
   for(const SBar &b : v) r.push_back({b.t, b.o, b.h, b.l, b.c, 100, 0, 0});
   return r;
}

struct Market
{
   std::vector<SBar> m5, m15;
};
static Market makeMarket(uint64_t seed, double price, double tick, double vol, int days)
{
   Market m;
   m.m5 = gen5m(seed, days * 288, T0, price, tick, vol);
   m.m15 = agg(m.m5, 900);
   return m;
}

static void load(const Market &m, const char *sym, const char *base, int digits, double tick)
{
   SIM = SimState();
   SIM.sym = sym;
   SIM.base = base;
   SIM.profit = "USD";
   SIM.digits = digits;
   SIM.tick = tick;
   SIM.tickValue = tick * 100.0;   // e.g. 100 oz contract
   SIM.volMin = 0.01;
   SIM.m5 = toRates(m.m5);
   SIM.m15 = toRates(m.m15);
   _Symbol = sym;
}

// run the terminal lifecycle once at SIM.now
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
      t.push_back(s[(size_t)i].time);
      o.push_back(s[(size_t)i].open);
      h.push_back(s[(size_t)i].high);
      l.push_back(s[(size_t)i].low);
      c.push_back(s[(size_t)i].close);
      tv.push_back(0);
      vol.push_back(0);
      sp.push_back(0);
   }
   for(auto &kv : SIM.bufs) kv.second->assign((size_t)v, 0.0);
   if(v > 0) SIM.bid = c.back();
   OnCalculate(v, 0, t, o, h, l, c, tv, vol, sp);
   OnTimer();
}
static int start()
{
   int rc = OnInit();
   calc();
   return rc;
}
static std::string txt(const std::string &id) { return SIM.objs.count("NBLP_P_" + id) ? SIM.objs["NBLP_P_" + id].s[OBJPROP_TEXT] : "<missing>"; }
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
   int state, reasons, sig, dir15, n5;
   NbSignal s;
};
static Ref reference(const Market &m, long long now, double tick, int digits)
{
   NbParams P;
   P.atrPeriod = InpNrtrAtrPeriod; P.nrtrMult = InpNrtrMultiplier; P.emaPeriod = InpEmaPeriod;
   P.swing = InpSwingStrength; P.slBufAtr = InpSlBufferAtr; P.tp1R = InpTp1R; P.tp2R = InpTp2R;
   P.validBars = InpSignalValidBars; P.tick = tick; P.digits = digits;
   long long anchor = (now / 86400) * 86400 - (long long)InpHistoryDays * 86400;
   NbSeries a, b;
   std::vector<SBar> v5, v15;
   for(const SBar &x : m.m5) if(x.t >= anchor && x.t + 300 <= now) v5.push_back(x);
   for(const SBar &x : m.m15) if(x.t >= anchor && x.t + 900 <= now) v15.push_back(x);
   // the terminal never hands over bar 0 (the forming one) either
   NbSeriesResize(a, (int)v5.size()); a.sec = 300;
   NbSeriesResize(b, (int)v15.size()); b.sec = 900;
   for(size_t i = 0; i < v5.size(); i++) { a.t[i] = v5[i].t; a.o[i] = v5[i].o; a.h[i] = v5[i].h; a.l[i] = v5[i].l; a.c[i] = v5[i].c; }
   for(size_t i = 0; i < v15.size(); i++) { b.t[i] = v15[i].t; b.o[i] = v15[i].o; b.h[i] = v15[i].h; b.l[i] = v15[i].l; b.c[i] = v15[i].c; }
   std::vector<NbPivot> p15, p5;
   std::vector<NbSignal> sg;
   int ns = 0;
   NbRun15(b, p15, P);
   NbRun5(a, p5, b, true, P, sg, ns);
   Ref r;
   r.n5 = a.n;
   r.state = a.state.back();
   r.reasons = a.reasons.back();
   r.sig = a.sigOf.back();
   r.dir15 = b.dir.back();
   if(r.sig >= 0) r.s = sg[(size_t)r.sig];
   return r;
}
// first `now` (5M close + 20s, inside the next bar) where pred(ref) holds
template <class F> static long long findNow(const Market &m, double tick, int digits, F pred)
{
   for(size_t i = 11 * 288; i + 1 < m.m5.size(); i++)
   {
      long long now = m.m5[i].t + 300 + 20;
      Ref r = reference(m, now, tick, digits);
      if(pred(r)) return now;
   }
   return 0;
}

int main()
{
   Market gold = makeMarket(7, 2400.0, 0.01, 1.2, 16);
   Market silver = makeMarket(21, 30.0, 0.001, 0.015, 16);

   begin("I1 unsupported symbol -> GOLD / SILVER ONLY, nothing computed");
   {
      load(gold, "EURUSD", "EUR", 5, 0.00001);
      SIM.now = gold.m5[3000].t + 20;
      start();
      CHECK(has(txt("state"), "GOLD / SILVER ONLY"), "banner says gold/silver only");
      CHECK(has(txt("r1"), "GOLD / SILVER ONLY"), "reason says gold/silver only");
      CHECK(countPrefix("NBLP_C_") == 0, "no chart markings on unsupported symbols");
      bool empty = true;
      for(double x : *SIM.bufs[0]) empty = empty && x == EMPTY_VALUE;
      CHECK(empty, "no EMA plotted");
      OnDeinit(0);
      load(gold, "US100", "USD", 2, 0.01); SIM.now = gold.m5[3000].t + 20; start();
      CHECK(has(txt("state"), "GOLD / SILVER ONLY"), "US100 rejected");
      OnDeinit(0);
      load(gold, "BTCUSD", "BTC", 2, 0.01); SIM.now = gold.m5[3000].t + 20; start();
      CHECK(has(txt("state"), "GOLD / SILVER ONLY"), "BTCUSD rejected");
      OnDeinit(0);
   }
   end("I1");

   begin("I2 GOLD: CLICK BUY and CLICK SELL rendered with the engine's exact levels");
   {
      long long nb = findNow(gold, 0.01, 2, [](const Ref &r) { return r.state == NB_BUY; });
      long long ns = findNow(gold, 0.01, 2, [](const Ref &r) { return r.state == NB_SELL; });
      CHECK(nb > 0 && ns > 0, "fixture contains a BUY moment and a SELL moment");
      for(int side = 0; side < 2 && nb > 0 && ns > 0; side++)
      {
         long long now = side == 0 ? nb : ns;
         Ref r = reference(gold, now, 0.01, 2);
         load(gold, "XAUUSD", "XAU", 2, 0.01);
         SIM.now = now;
         CHECK(start() == INIT_SUCCEEDED, "init ok");
         CHECK(has(txt("title"), "GOLD NRTR BOSS"), "gold title");
         CHECK(has(txt("state"), side == 0 ? "CLICK BUY" : "CLICK SELL"), "banner");
         CHECK(has(txt("v10"), DoubleToString(r.s.entry, 2)), "entry printed with 2 digits");
         CHECK(has(txt("v11"), DoubleToString(r.s.sl, 2)), "SL");
         CHECK(has(txt("v12"), DoubleToString(r.s.tp1, 2)) && has(txt("v12"), "1.0R"), "TP1 = 1R");
         CHECK(has(txt("v13"), DoubleToString(r.s.tp2, 2)) && has(txt("v13"), "2.0R"), "TP2 = 2R");
         CHECK(has(txt("v14"), DoubleToString(r.s.risk, 2)), "risk");
         CHECK(has(txt("v6"), side == 0 ? "BUY MODE" : "SELL MODE"), "15M decision row");
         CHECK(has(txt("v9"), "READY"), "5M confirm READY");
         CHECK(countPrefix("NBLP_C_L_") == 8, "entry/SL/TP1/TP2 lines + labels drawn");
         CHECK(countPrefix("NBLP_C_G_") > 0, "decision markers drawn");
         std::printf("    %s at %s: entry %s SL %s TP1 %s TP2 %s\n", side == 0 ? "BUY " : "SELL",
                     TimeToString(now, TIME_DATE | TIME_MINUTES).c_str(), DoubleToString(r.s.entry, 2).c_str(),
                     DoubleToString(r.s.sl, 2).c_str(), DoubleToString(r.s.tp1, 2).c_str(), DoubleToString(r.s.tp2, 2).c_str());
         OnDeinit(0);
         CHECK(countPrefix("NBLP_") == 0, "OnDeinit removes every object it created");
      }
   }
   end("I2");

   begin("I3 conflict -> WAIT with the plain-English reason");
   {
      long long now = findNow(gold, 0.01, 2, [](const Ref &r) { return r.state == NB_WAIT && (r.reasons & NB_R_5M_AGAINST) != 0; });
      CHECK(now > 0, "fixture contains 5M-against-15M");
      load(gold, "XAUUSD", "XAU", 2, 0.01);
      SIM.now = now;
      start();
      CHECK(has(txt("state"), "WAIT"), "banner WAIT");
      CHECK(has(txt("r1"), "5M AGAINST 15M"), "reason 5M AGAINST 15M");
      CHECK(has(txt("v9"), "AGAINST 15M"), "5M confirm row");
      CHECK(txt("v10") == "---" && txt("v11") == "---", "no levels shown while waiting");
      CHECK(countPrefix("NBLP_C_L_") == 0, "no entry/SL/TP lines while waiting");
      OnDeinit(0);
   }
   end("I3");

   begin("I4 SILVER: digits and tick come from the symbol (3 dp)");
   {
      long long now = findNow(silver, 0.001, 3, [](const Ref &r) { return r.state != NB_WAIT; });
      CHECK(now > 0, "silver fixture has a signal");
      Ref r = reference(silver, now, 0.001, 3);
      load(silver, "XAGUSD.m", "XAG", 3, 0.001);
      SIM.now = now;
      start();
      CHECK(has(txt("title"), "SILVER NRTR BOSS"), "silver title");
      CHECK(has(txt("v10"), DoubleToString(r.s.entry, 3)), "entry with 3 digits");
      CHECK(has(txt("v11"), DoubleToString(r.s.sl, 3)), "SL with 3 digits");
      double q = r.s.sl / 0.001;
      CHECK(std::fabs(q - std::round(q)) < 1e-6, "SL on the 0.001 grid");
      std::printf("    silver %s entry %s SL %s risk %s | money row: %s\n", r.state > 0 ? "BUY" : "SELL",
                  DoubleToString(r.s.entry, 3).c_str(), DoubleToString(r.s.sl, 3).c_str(),
                  DoubleToString(r.s.risk, 3).c_str(), txt("v15").c_str());
      OnDeinit(0);
   }
   end("I4");

   begin("I5 existing BUY / SELL position + 15M reversal -> EXIT / PROTECT (read only)");
   {
      // a moment where 15M NRTR is bearish, and a time earlier where it was bullish
      for(int side = 1; side >= -1; side -= 2)
      {
         long long now = 0, openT = 0;
         for(size_t i = 11 * 288; i + 1 < gold.m5.size() && now == 0; i += 7)
         {
            long long cand = gold.m5[i].t + 320;
            Ref r = reference(gold, cand, 0.01, 2);
            if(r.dir15 != -side) continue;
            for(long long back = 3600; back < 5 * 3600; back += 900)
               if(reference(gold, cand - back, 0.01, 2).dir15 == side) { now = cand; openT = cand - back; break; }
         }
         CHECK(now > 0, "fixture has a 15M reversal");
         load(gold, "XAUUSD", "XAU", 2, 0.01);
         SIM.now = now;
         SIM.pos.push_back({"XAUUSD", side > 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, 0.10, openT});
         SIM.pos.push_back({"XAGUSD", POSITION_TYPE_BUY, 1.0, openT});   // other symbol: ignored
         std::vector<SimPos> before = SIM.pos;
         start();
         CHECK(has(txt("state"), side > 0 ? "EXIT / PROTECT BUY" : "EXIT / PROTECT SELL"), "banner EXIT / PROTECT");
         CHECK(has(txt("r1"), "15M TREND INVALIDATED"), "reason 15M TREND INVALIDATED");
         CHECK(has(txt("pw"), "15M TREND INVALIDATED"), "position row explains");
         CHECK(has(txt("v16"), side > 0 ? "BUY 0.10" : "SELL 0.10"), "reads the position on this symbol only");
         bool untouched = SIM.pos.size() == before.size();
         for(size_t k = 0; untouched && k < before.size(); k++)
            untouched = SIM.pos[k].type == before[k].type && SIM.pos[k].vol == before[k].vol && SIM.pos[k].time == before[k].time;
         CHECK(untouched, "positions unchanged (read only)");
         OnDeinit(0);
      }
      // regime intact -> not EXIT
      long long now = findNow(gold, 0.01, 2, [](const Ref &r) { return r.dir15 == 1; });
      load(gold, "XAUUSD", "XAU", 2, 0.01);
      SIM.now = now;
      SIM.pos.push_back({"XAUUSD", POSITION_TYPE_BUY, 0.10, now - 600});
      start();
      CHECK(!has(txt("state"), "EXIT"), "BUY with bullish 15M is not EXIT");
      CHECK(has(txt("pw"), "15M REGIME INTACT"), "position row: regime intact");
      OnDeinit(0);
      load(gold, "XAUUSD", "XAU", 2, 0.01);
      SIM.now = now;
      start();
      CHECK(txt("v16") == "NO POSITION", "no position -> NO POSITION");
      OnDeinit(0);
   }
   end("I5");

   begin("I6 no repaint through the terminal: forming bar ignored, chart TF irrelevant");
   {
      long long now = findNow(gold, 0.01, 2, [](const Ref &r) { return r.state == NB_BUY; });
      load(gold, "XAUUSD", "XAU", 2, 0.01);
      SIM.now = now;
      start();
      std::string s1 = txt("state"), e1 = txt("v10"), m1 = txt("v6");
      std::vector<double> ema1 = *SIM.bufs[0];
      OnDeinit(0);
      // wreck the forming 5M and 15M bars: a crash candle that has not closed
      load(gold, "XAUUSD", "XAU", 2, 0.01);
      SIM.now = now;
      for(auto *ser : {&SIM.m5, &SIM.m15})
         for(auto &b : *ser)
            if(b.time <= now && b.time + (ser == &SIM.m5 ? 300 : 900) > now) { b.low -= 50; b.close -= 50; }
      start();
      CHECK(txt("state") == s1 && txt("v10") == e1 && txt("v6") == m1, "an unfinished crash candle changes nothing");
      std::vector<double> ema2 = *SIM.bufs[0];
      CHECK(ema1 == ema2, "EMA buffer identical, incl. the forming chart bar");
      OnDeinit(0);
      // same moment viewed on a M1 chart
      load(gold, "XAUUSD", "XAU", 2, 0.01);
      for(const SBar &b : gold.m5)
         for(int k = 0; k < 5; k++) SIM.m1.push_back({b.t + k * 60, b.o, b.h, b.l, b.c, 1, 0, 0});
      _Period = PERIOD_M1;
      SIM.now = now;
      start();
      CHECK(txt("state") == s1 && txt("v10") == e1, "M1 chart shows the same 15M/5M decision");
      OnDeinit(0);
      _Period = PERIOD_M15;
      // an M15 chart bar shows the EMA of the 15M bar that CLOSED with it
      load(gold, "XAUUSD", "XAU", 2, 0.01);
      SIM.now = now;
      start();
      int v = simVisible(PERIOD_M15);
      CHECK(g_s15.n > 0 && (*SIM.bufs[0])[(size_t)(v - 2)] == g_s15.ema[(size_t)(g_s15.n - 1)], "last closed chart bar = last closed 15M EMA");
      CHECK((*SIM.bufs[0])[(size_t)(v - 1)] == g_s15.ema[(size_t)(g_s15.n - 1)], "forming chart bar holds the last CLOSED value, not a live one");
      OnDeinit(0);
   }
   end("I6");

   begin("I7 restart -> identical panel, markers and buffers");
   {
      long long now = findNow(gold, 0.01, 2, [](const Ref &r) { return r.state == NB_SELL; });
      load(gold, "XAUUSD", "XAU", 2, 0.01);
      SIM.now = now;
      start();
      auto snap1 = SIM.objs;
      std::vector<std::vector<double>> b1;
      for(auto &kv : SIM.bufs) b1.push_back(*kv.second);
      OnDeinit(0);
      CHECK(countPrefix("NBLP_") == 0, "clean shutdown");
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
   end("I7");

   begin("I8 missing / stale data -> WAIT, never a guess");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01);
      SIM.now = gold.m5[4000].t + 20;
      SIM.copyFail = true;
      start();
      CHECK(has(txt("state"), "WAIT") && has(txt("r1"), "MISSING DATA"), "history unavailable -> WAIT / MISSING DATA");
      CHECK(txt("v10") == "---", "no levels");
      SIM.copyFail = false;   // history arrives: next timer tick recovers by itself
      OnTimer();
      CHECK(!has(txt("r1"), "MISSING DATA"), "recovers once history loads");
      OnDeinit(0);

      load(gold, "XAUUSD", "XAU", 2, 0.01);
      SIM.now = gold.m5.back().t + 6 * 3600;   // feed stopped 6 hours ago (weekend / frozen)
      SIM.pos.push_back({"XAUUSD", POSITION_TYPE_BUY, 0.1, gold.m5.back().t - 3600});
      start();
      CHECK(has(txt("state"), "WAIT") && has(txt("r1"), "DATA STALE"), "stale feed -> WAIT / DATA STALE");
      CHECK(has(txt("pw"), "CANNOT JUDGE"), "stale feed -> position advice withheld");
      OnDeinit(0);

      load(gold, "XAUUSD", "XAU", 2, 0.01);
      SIM.m5.clear();
      SIM.m15.clear();
      SIM.now = T0 + 86400;
      start();
      CHECK(has(txt("state"), "WAIT") && has(txt("r1"), "MISSING DATA"), "no bars at all -> WAIT");
      OnDeinit(0);

      load(gold, "XAUUSD", "XAU", 2, 0.01);
      SIM.now = T0 + 3600;   // one hour of history: EMA200 impossible
      start();
      CHECK(has(txt("state"), "WAIT"), "short history -> WAIT");
      std::printf("    short-history reason: %s / %s\n", txt("r1").c_str(), txt("r2").c_str());
      OnDeinit(0);
   }
   end("I8");

   std::printf("\nINDICATOR TESTS: %d checks passed, %d failed\n", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
