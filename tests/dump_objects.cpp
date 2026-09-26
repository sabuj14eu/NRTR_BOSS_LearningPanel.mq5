// "The existing panel did not change" - proven, not claimed.
// Built twice by run_tests.sh: once against the v1.04 file from git
// (baseline commit 3f046ef, before the v1.05 five-question table) and once
// against the current file. Both binaries run the SAME scenarios on the same
// simulated terminal and print every chart object, every plot buffer (hash),
// every alert and every log line - EXCEPT the objects that v1.05 added
// (prefixes NBSP_Q_ = table, NBSP_F_ = its chart drawing). The two outputs
// must be byte-identical.
#include "../tests/mt5_sim.h"
#include DUMP_INC
#include "../tests/synth.h"
#include <cstdio>
#include <cstring>

static const long long T0 = 1788220800LL;
#if NB_TEST_MARKET == 2
static const char *SYM = "EURUSD", *BASE = "EUR", *QUOTE = "USD";
static const int DIGITS = 5;
static const double TICK = 0.00001, PRICE = 1.08, VOL = 0.0004;
#else
static const char *SYM = "BTCUSD", *BASE = "BTC", *QUOTE = "USD";
static const int DIGITS = 2;
static const double TICK = 0.01, PRICE = 60000.0, VOL = 40.0;
#endif

static std::vector<MqlRates> toRates(const std::vector<SBar> &v)
{
   std::vector<MqlRates> r;
   for(const SBar &b : v) r.push_back({b.t, b.o, b.h, b.l, b.c, 100, 0, 0});
   return r;
}
static std::vector<SBar> g5, g15;
static void load(const char *sym, const char *base)
{
   SIM = SimState();
   SIM.sym = sym; SIM.base = base; SIM.profit = QUOTE; SIM.digits = DIGITS; SIM.tick = TICK;
   SIM.tickValue = TICK * 100.0; SIM.volMin = 0.01; SIM.gmtOff = 3 * 3600;
   SIM.m5 = toRates(g5); SIM.m15 = toRates(g15);
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
static unsigned long long fnv(const void *p, size_t n, unsigned long long h = 1469598103934665603ULL)
{
   const unsigned char *b = (const unsigned char *)p;
   for(size_t k = 0; k < n; k++) { h ^= b[k]; h *= 1099511628211ULL; }
   return h;
}
static bool added(const std::string &name)
{
   return name.compare(0, 7, "NBSP_Q_") == 0 || name.compare(0, 7, "NBSP_F_") == 0;
}
static void dump(const char *label)
{
   std::printf("=== %s\n", label);
   int kept = 0;
   for(auto &kv : SIM.objs)
   {
      if(added(kv.first)) continue;
      kept++;
      std::printf("O %s t=%d", kv.first.c_str(), kv.second.type);
      for(auto &x : kv.second.i) std::printf(" i%d=%lld", x.first, x.second);
      for(auto &x : kv.second.d) std::printf(" d%d=%.10g", x.first, x.second);
      for(auto &x : kv.second.s) std::printf(" s%d=[%s]", x.first, x.second.c_str());
      std::printf("\n");
   }
   for(auto &kv : SIM.bufs)
   {
      const std::vector<double> &b = *kv.second;
      int filled = 0;
      for(double x : b) if(x != EMPTY_VALUE && x != 0.0) filled++;
      std::printf("B %d n=%zu filled=%d hash=%016llx\n", kv.first, b.size(), filled, fnv(b.data(), b.size() * sizeof(double)));
   }
   for(auto &a : SIM.alerts) std::printf("A %s\n", a.c_str());
   for(auto &a : SIM.log) std::printf("L %s\n", a.c_str());
   std::printf("objects kept %d\n", kept);
}

int main()
{
   g5 = gen5m(7, 16 * 288, T0, PRICE, TICK, VOL);
   g15 = agg(g5, 900);
   char label[160];
   int scen = 0;
   for(ENUM_TIMEFRAMES tf : {PERIOD_M15, PERIOD_M5})
   {
      _Period = tf;
      for(size_t i = 11 * 288; i + 1 < g5.size(); i += 61)
      {
         load(SYM, BASE);
         SIM.now = g5[i].t + 300 + 20;
         OnInit();
         calc();
         SIM.now += 1;   // one more timer second: blink state, countdown
         OnTimer();
         std::snprintf(label, sizeof label, "tf %d  now %lld", (int)tf, SIM.now);
         dump(label);
         OnDeinit(0);
         std::printf("after deinit %zu objects\n", SIM.objs.size());
         scen++;
      }
   }
   _Period = PERIOD_M5;
   // an open position (read-only advice rows)
   load(SYM, BASE);
   SIM.now = g5[13 * 288 + 7].t + 320;
   SIM.pos.push_back({SYM, POSITION_TYPE_BUY, 0.10, SIM.now - 5 * 3600});
   OnInit(); calc(); dump("position"); OnDeinit(0); scen++;
   // stale feed
   load(SYM, BASE);
   SIM.now = g5.back().t + 30 * 3600;
   OnInit(); calc(); dump("stale"); OnDeinit(0); scen++;
   // missing history, then recovery
   load(SYM, BASE);
   SIM.now = g5[4000].t + 20;
   SIM.copyFail = true;
   OnInit(); calc(); dump("missing"); SIM.copyFail = false; OnTimer(); dump("recovered"); OnDeinit(0); scen++;
   // unsupported symbol
   load((NB_MARKET == NB_MKT_CRYPTO) ? "EURUSD" : "BTCUSD", (NB_MARKET == NB_MKT_CRYPTO) ? "EUR" : "BTC");
   SIM.now = g5[3000].t + 20;
   OnInit(); calc(); dump("unsupported"); OnDeinit(0); scen++;
   std::fprintf(stderr, "%d scenarios dumped\n", scen);
   return 0;
}
