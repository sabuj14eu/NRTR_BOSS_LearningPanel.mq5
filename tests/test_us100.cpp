// US100 / USTEC tests (v1.11): the whole NRTR_BOSS_US100.mq5 (translated
// syntax-only) on the simulated MT5 terminal, on a synthetic USTEC market
// with REAL trading hours (Sun 18:00 - Fri 17:00 NY, daily break 17:00-18:00)
// and a server clock that follows the broker's DST rule. The expected NY
// time of every bar comes from a hand-written DST date TABLE here, not from
// the indicator's own calendar arithmetic.
#include "../tests/mt5_sim.h"
#include "full_us100.inc"
#include "../tests/synth.h"
#include <cstdio>
#include <cstring>
#include <functional>
#include <fstream>
#include <sstream>

static int g_pass = 0, g_fail = 0, g_sec = 0;
#define CHECK(cond, msg)                                                   \
   do {                                                                    \
      if(cond) g_pass++;                                                   \
      else { g_fail++; std::printf("    FAIL %s:%d  %s\n", __FILE__, __LINE__, msg); } \
   } while(0)
static void begin(const char *n) { g_sec = g_fail; std::printf("[ RUN  ] %s\n", n); }
static void end(const char *n) { std::printf("[ %s ] %s\n", g_fail == g_sec ? " OK " : "FAIL", n); }
static bool has(const std::string &s, const std::string &sub) { return s.find(sub) != std::string::npos; }
static bool near(double a, double b) { return std::fabs(a - b) < 1e-6; }

//---------------------------------------------------------------- the reference calendar (a TABLE, 2026)
// US DST 2026: 8 March - 1 November (07:00 / 06:00 UTC). EU: 29 March - 25 October (01:00 UTC).
static long long U(int y, int m, int d, int hh, int mm)
{
   struct tm g = {};
   g.tm_year = y - 1900; g.tm_mon = m - 1; g.tm_mday = d; g.tm_hour = hh; g.tm_min = mm;
   return (long long)timegm(&g);
}
static bool refUsDst(long long utc) { return utc >= U(2026, 3, 8, 7, 0) && utc < U(2026, 11, 1, 6, 0); }
static bool refEuDst(long long utc) { return utc >= U(2026, 3, 29, 1, 0) && utc < U(2026, 10, 25, 1, 0); }
static long long refEt(long long utc) { return utc - (refUsDst(utc) ? 4 : 5) * 3600; }
enum { RULE_US = 0, RULE_EU = 1, RULE_NONE = 2 };
static long long refSrvOff(long long utc, int rule)
{
   if(rule == RULE_US) return 2 * 3600 + (refUsDst(utc) ? 3600 : 0);
   if(rule == RULE_EU) return 2 * 3600 + (refEuDst(utc) ? 3600 : 0);
   return 2 * 3600;
}
static int etMin(long long et) { return (int)(((et % 86400) + 86400) % 86400 / 60); }
static int etDow(long long et) { return (int)(((et / 86400) + 4) % 7); }
static bool tradable(long long et)
{
   int d = etDow(et), m = etMin(et);
   if(d == 6) return false;
   if(d == 0) return m >= 18 * 60;
   if(d == 5) return m < 17 * 60;
   return !(m >= 17 * 60 && m < 18 * 60);   // the daily break
}

//---------------------------------------------------------------- the fixture
struct UBar { long long utc, et, t; double o, h, l, c; };
struct UMkt { std::vector<UBar> b; int rule; };
static UMkt makeUs(long long startUtc, int days, int rule, uint64_t seed, double price = 21000.0, double vol = 12.0)
{
   UMkt m;
   m.rule = rule;
   std::vector<long long> utcs;
   for(long long u = startUtc; u < startUtc + (long long)days * 86400; u += 300)
      if(tradable(refEt(u))) utcs.push_back(u);
   std::vector<SBar> px = gen5m(seed, (int)utcs.size(), 0, price, 0.01, vol);
   for(size_t k = 0; k < utcs.size(); k++)
   {
      long long u = utcs[k];
      m.b.push_back({u, refEt(u), u + refSrvOff(u, rule), px[k].o, px[k].h, px[k].l, px[k].c});
   }
   return m;
}
static std::vector<SBar> sbars(const UMkt &m)
{
   std::vector<SBar> v;
   for(const UBar &x : m.b) v.push_back({x.t, x.o, x.h, x.l, x.c});
   return v;
}
static std::vector<MqlRates> toRates(const std::vector<SBar> &v)
{
   std::vector<MqlRates> r;
   for(const SBar &b : v) r.push_back({b.t, b.o, b.h, b.l, b.c, 100, 0, 0});
   return r;
}
// load the market into the simulated terminal; `nowUtc` = the real time
static void load(const UMkt &m, long long nowUtc, const char *sym = "USTEC")
{
   SIM = SimState();
   SIM.sym = sym; SIM.base = "USD"; SIM.profit = "USD"; SIM.digits = 2; SIM.tick = 0.01;
   SIM.tickValue = 0.01; SIM.volMin = 0.1; SIM.volStep = 0.1; SIM.volMax = 100.0; SIM.contract = 1.0;
   SIM.gmtOff = refSrvOff(nowUtc, m.rule);
   std::vector<SBar> v = sbars(m);
   SIM.m5 = toRates(v);
   SIM.m15 = toRates(agg(v, 900));
   SIM.m60 = toRates(agg(v, 3600));
   SIM.m240 = toRates(agg(v, 14400));
   SIM.now = nowUtc + SIM.gmtOff;
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
static std::string json() { for(auto &kv : SIM.files) if(kv.first.find(".json") != std::string::npos && kv.first.find(".tmp") == std::string::npos) return kv.second; return ""; }
static int findUtc(const UMkt &m, long long utc) { for(size_t k = 0; k < m.b.size(); k++) if(m.b[k].utc == utc) return (int)k; return -1; }

//---------------------------------------------------------------- an independent reference for the US map
struct RefUs { double pdh = 0, pdl = 0, pcl = 0, pmh = 0, pml = 0, onh = 0, onl = 0, open = 0, or15h = 0, or15l = 0, rthH = 0, rthL = 0; };
static long long tdayOf(long long et) { long long d = et / 86400; return etMin(et) >= 18 * 60 ? d + 1 : d; }
// the map known at the close of fixture bar k, using only bars from the loaded window [a, k]
static RefUs refUs(const UMkt &m, int a, int k)
{
   RefUs r;
   long long td = tdayOf(m.b[(size_t)k].et);
   long long endEt = m.b[(size_t)k].et + 300;
   // previous complete regular session: the newest earlier trading day with >= 36 RTH bars
   std::map<long long, std::vector<int>> rth;
   for(int j = a; j <= k; j++)
   {
      int mn = etMin(m.b[(size_t)j].et);
      if(mn >= 570 && mn < 960) rth[tdayOf(m.b[(size_t)j].et)].push_back(j);
   }
   for(auto it = rth.rbegin(); it != rth.rend(); ++it)
   {
      if(it->first >= td || it->second.size() < 36) continue;
      r.pdh = -1e18; r.pdl = 1e18;
      for(int j : it->second) { r.pdh = std::max(r.pdh, m.b[(size_t)j].h); r.pdl = std::min(r.pdl, m.b[(size_t)j].l); }
      r.pcl = m.b[(size_t)it->second.back()].c;
      break;
   }
   std::vector<int> pm, on, orb;
   for(int j = a; j <= k; j++)
   {
      if(tdayOf(m.b[(size_t)j].et) != td) continue;
      int mn = etMin(m.b[(size_t)j].et);
      if(mn >= 240 && mn < 570) pm.push_back(j);
      if(mn >= 18 * 60 || mn < 240) on.push_back(j);
      if(mn >= 570 && mn < 585) orb.push_back(j);
      if(mn >= 570 && mn < 960)
      {
         r.rthH = (r.rthH == 0) ? m.b[(size_t)j].h : std::max(r.rthH, m.b[(size_t)j].h);
         r.rthL = (r.rthL == 0) ? m.b[(size_t)j].l : std::min(r.rthL, m.b[(size_t)j].l);
         if(mn == 570) r.open = m.b[(size_t)j].o;
      }
   }
   long long base = td * 86400;
   if(endEt >= base + 570 * 60 && pm.size() >= 12)
   {
      r.pmh = -1e18; r.pml = 1e18;
      for(int j : pm) { r.pmh = std::max(r.pmh, m.b[(size_t)j].h); r.pml = std::min(r.pml, m.b[(size_t)j].l); }
   }
   if(endEt >= base + 240 * 60 && on.size() >= 12)
   {
      r.onh = -1e18; r.onl = 1e18;
      for(int j : on) { r.onh = std::max(r.onh, m.b[(size_t)j].h); r.onl = std::min(r.onl, m.b[(size_t)j].l); }
   }
   if(endEt >= base + 585 * 60 && orb.size() == 3 && r.open > 0)
   {
      r.or15h = -1e18; r.or15l = 1e18;
      for(int j : orb) { r.or15h = std::max(r.or15h, m.b[(size_t)j].h); r.or15l = std::min(r.or15l, m.b[(size_t)j].l); }
   }
   return r;
}

int main()
{
   // Sunday 6 Sep 2026 22:00 UTC = 18:00 NY: 20 calendar days of USTEC, server = NY close (US DST rule)
   const long long S0 = U(2026, 9, 6, 22, 0);
   UMkt mk = makeUs(S0, 20, RULE_US, 11);
   std::printf("fixture: %zu USTEC 5M bars, %s .. %s server time\n", mk.b.size(), TimeToString(mk.b.front().t, TIME_DATE | TIME_MINUTES).c_str(),
               TimeToString(mk.b.back().t, TIME_DATE | TIME_MINUTES).c_str());

   begin("U0 symbol filter and session labels (a table, not the code's arithmetic)");
   {
      const char *okS[] = {"USTEC", "US100.cash", "NAS100.m", "#USTEC", "USTECH100", "NDX100"};
      const char *noS[] = {"US500", "US30", "NVDA", "EURUSD", "BTCUSD", "XAUUSD", "GER40"};
      for(const char *s : okS) CHECK(NbMarketLabel(s, "USD", "USD") == "US100", s);
      for(const char *s : noS) CHECK(NbMarketLabel(s, "USD", "USD") == "", s);
      struct { int y, mo, d, hh, mi, want; } t[] = {
         {2026, 9, 9, 9, 29, NB_US_PRE}, {2026, 9, 9, 9, 30, NB_US_OPEN5}, {2026, 9, 9, 9, 35, NB_US_OPEN15},
         {2026, 9, 9, 9, 45, NB_US_OPEN30}, {2026, 9, 9, 10, 0, NB_US_MORNING}, {2026, 9, 9, 11, 30, NB_US_LUNCH},
         {2026, 9, 9, 13, 30, NB_US_AFTERNOON}, {2026, 9, 9, 15, 0, NB_US_FINAL}, {2026, 9, 9, 16, 0, NB_US_AFTER},
         {2026, 9, 9, 18, 0, NB_US_OVERNIGHT}, {2026, 9, 9, 3, 59, NB_US_OVERNIGHT}, {2026, 9, 9, 4, 0, NB_US_PRE},
         {2026, 9, 11, 17, 0, NB_US_CLOSED}, {2026, 9, 12, 12, 0, NB_US_CLOSED}, {2026, 9, 13, 17, 55, NB_US_CLOSED},
         {2026, 9, 13, 18, 0, NB_US_OVERNIGHT}};
      for(auto &x : t)
      {
         long long et = U(x.y, x.mo, x.d, x.hh, x.mi);   // an NY wall-clock value expressed as seconds
         char msg[80];
         std::snprintf(msg, sizeof msg, "%02d:%02d on %d-%02d-%02d = %s", x.hh, x.mi, x.y, x.mo, x.d, NbUsSessText(x.want).c_str());
         CHECK(NbUsSessOf(et) == x.want, msg);
      }
   }
   end("U0");

   begin("U15 DST: the server clock converted PER BAR (US rule, EU rule, the weeks the US and EU differ)");
   {
      // the server's own DST rule, checked against the table at every hour of 2026
      bool usOk = true, euOk = true, etOk = true;
      for(long long u = U(2026, 1, 1, 0, 0); u < U(2027, 1, 1, 0, 0); u += 3600)
      {
         if(NbSrvDstOn(NB_SRVDST_US, u) != refUsDst(u) && (u % 86400) / 3600 >= 8) usOk = false;   // the day-level US rule: from 08:00 UTC
         if(NbSrvDstOn(NB_SRVDST_EU, u) != refEuDst(u)) euOk = false;
         for(int rule = 0; rule < 3; rule++)
         {
            long long t = u + refSrvOff(u, rule);
            long long now = U(2026, 12, 15, 12, 0);   // witnesses read in winter
            long base = NbSrvBase(refSrvOff(now, rule), now, rule);
            if(tradable(refEt(u)) && NbUsEt((datetime)t, true, NB_CLK_AUTO, base, rule, 0) != refEt(u)) etOk = false;
         }
      }
      CHECK(usOk, "US server rule = the table (all of 2026, trading hours)");
      CHECK(euOk, "EU server rule = the table (all of 2026, to the hour)");
      CHECK(etOk, "every tradable hour of 2026: NY time exact for US / EU / fixed servers, read with a WINTER witness");
      // a summer witness gives the same answer (the series is not converted with one scalar)
      bool same = true;
      for(long long u = U(2026, 1, 5, 0, 0); u < U(2026, 12, 20, 0, 0); u += 3600 * 5)
      {
         if(!tradable(refEt(u))) continue;
         long long now = U(2026, 7, 1, 12, 0);
         for(int rule = 0; rule < 3; rule++)
            if(NbUsEt((datetime)(u + refSrvOff(u, rule)), true, NB_CLK_AUTO, NbSrvBase(refSrvOff(now, rule), now, rule), rule, 0) != refEt(u)) same = false;
      }
      CHECK(same, "a SUMMER witness converts winter history exactly too");
      // the whole indicator across the US switch (1 Nov) with a NY-close server (the input's default rule):
      // 09:30 NY stays OPEN on both sides (EU / fixed servers are proven above, at every hour of 2026)
      UMkt dm = makeUs(U(2026, 10, 18, 22, 0), 17, RULE_US, 5);
      load(dm, U(2026, 11, 4, 18, 0));
      start();
      int opens = 0, wrong = 0, before = 0;
      for(int i = 0; i < g_s5.n && i < (int)g_us.size(); i++)
      {
         int k = -1;
         for(size_t q = 0; q < dm.b.size(); q++) if(dm.b[q].t == g_s5.t[i]) { k = (int)q; break; }
         if(k < 0) continue;
         if(etMin(dm.b[(size_t)k].et) == 570) { opens++; before += dm.b[(size_t)k].utc < U(2026, 11, 1, 6, 0); if(g_us[(size_t)i].sess != NB_US_OPEN5) wrong++; }
         if(g_us[(size_t)i].et != dm.b[(size_t)k].et) wrong++;
      }
      char msg[120];
      std::snprintf(msg, sizeof msg, "%d regular opens (%d before the switch), every one at 09:30 NY; every bar's NY time exact (%d wrong)", opens, before, wrong);
      CHECK(opens >= 7 && before >= 3 && opens - before >= 3 && wrong == 0, msg);
      OnDeinit(0);
   }
   end("U15");

   // a normal moment: Wednesday 23 Sep 2026, 11:02 NY (bar 10:55-11:00 closed)
   const long long N1 = U(2026, 9, 23, 15, 0) + 120;   // 11:02 EDT
   begin("U1 / U2 / U3 the US map vs an independent reference, bar by bar (prev day, pre-market, overnight, open, OR)");
   {
      load(mk, N1);
      CHECK(start() == INIT_SUCCEEDED, "init ok");
      int a = -1;
      for(size_t q = 0; q < mk.b.size(); q++) if(mk.b[q].t == g_s5.t[0]) { a = (int)q; break; }
      int bad = 0, checked = 0, withPm = 0, withOr = 0, withPd = 0;
      for(int i = 0; i < g_s5.n; i++)
      {
         int k = a + i;
         if(mk.b[(size_t)k].t != g_s5.t[i]) { bad++; continue; }
         RefUs r = refUs(mk, a, k);
         const NbUsBar &b = g_us[(size_t)i];
         bool same = near(b.pdh, r.pdh) && near(b.pdl, r.pdl) && near(b.pcl, r.pcl) && near(b.pmh, r.pmh) && near(b.pml, r.pml) &&
                     near(b.onh, r.onh) && near(b.onl, r.onl) && near(b.open, r.open) && near(b.or15h, r.or15h) && near(b.or15l, r.or15l) &&
                     near(b.rthH, r.rthH) && near(b.rthL, r.rthL);
         if(!same && bad < 3)
            std::printf("    bar %s NY: pdh %.2f/%.2f pm %.2f/%.2f open %.2f/%.2f or15 %.2f/%.2f\n",
                        TimeToString((datetime)mk.b[(size_t)k].et, TIME_DATE | TIME_MINUTES).c_str(), b.pdh, r.pdh, b.pmh, r.pmh, b.open, r.open, b.or15h, r.or15h);
         if(!same) bad++;
         checked++;
         withPm += b.pmh > 0; withOr += b.or15h > 0; withPd += b.pdh > 0;
      }
      char msg[160];
      std::snprintf(msg, sizeof msg, "%d bars: all 12 US fields equal the reference (%d differ); pm known on %d, OR15 on %d, prev day on %d",
                    checked, bad, withPm, withOr, withPd);
      CHECK(bad == 0 && withPm > 500 && withOr > 500 && withPd > 1500, msg);
      int i5 = g_s5.n - 1;
      CHECK(g_us[(size_t)i5].sess == NB_US_MORNING, "the last closed bar (10:55) is MORNING");
      CHECK(has(txt("vs"), "MORNING") && has(txt("vs"), "NY 11:02"), "session row: MORNING, NY 11:02 (live clock)");
      CHECK(has(txt("vn2"), "H ") && has(txt("vn2"), "CLOSE"), "prev day row printed");
      CHECK(has(txt("vn3"), "ONH/ONL ") && has(txt("vn3"), "PMH/PML ") && !has(txt("vn3"), "---"), "ONH/ONL + PMH/PML row, both known at 11:00");
      CHECK(NbLvSrcShort(NB_LV_ASH) == "PMH" && NbLvSrcShort(NB_LV_ASL) == "PML" && NbLvSrcShort(NB_LV_LOH) == "ORH", "table codes PMH / PML / ORH");
      CHECK(has(txt("vn5"), "5m ") && has(txt("vn5"), "15m ") && has(txt("vn6"), "30m "), "opening range rows");
      CHECK(has(txt("vn7"), "(so far)"), "regular session so far");
      CHECK(has(txt("hny"), "US SESSION MAP") && txt("vn4") != "---", "US map header + gap row");
      CHECK(has(txt("title"), "US100") && has(txt("title"), "US INDEX") && txt("ver") == "v1.11", "title and version v1.11");
      bool fit = true;
      for(auto &kv : SIM.objs)
         if(kv.first.compare(0, 5, "NBSP_") == 0 && kv.second.s.count(OBJPROP_TEXT) && kv.second.s[OBJPROP_TEXT].size() > 63)
         { fit = false; std::printf("    too long (%zu): %s = %s\n", kv.second.s[OBJPROP_TEXT].size(), kv.first.c_str(), kv.second.s[OBJPROP_TEXT].c_str()); }
      CHECK(fit, "every label <= 63 characters (MT5 cuts longer text)");
      long long bgY = SIM.objs["NBSP_P_bg"].i[OBJPROP_YDISTANCE], bgH = SIM.objs["NBSP_P_bg"].i[OBJPROP_YSIZE], maxY = 0;
      std::string lowest;
      for(auto &kv : SIM.objs)
         if(kv.first.compare(0, 7, "NBSP_P_") == 0 && kv.second.type == OBJ_LABEL && kv.second.i[OBJPROP_YDISTANCE] > maxY)
         { maxY = kv.second.i[OBJPROP_YDISTANCE]; lowest = kv.first; }
      char bmsg[120];
      std::snprintf(bmsg, sizeof bmsg, "the lowest label (%s at y=%lld) sits inside the panel background (bottom %lld)", lowest.c_str(), maxY, bgY + bgH);
      CHECK(maxY + 12 <= bgY + bgH, bmsg);
      OnDeinit(0);
   }
   end("U1/U2/U3");

   begin("U1 pre-market never mixes with the regular session (planted spikes)");
   {
      UMkt m2 = mk;
      // Tuesday 22 Sep: a pre-market spike at 08:00 NY, far above everything; a regular-session spike at 09:30 far below
      int kp = findUtc(m2, U(2026, 9, 22, 12, 0));   // 08:00 EDT
      int ko = findUtc(m2, U(2026, 9, 22, 13, 30));  // 09:30 EDT
      CHECK(kp > 0 && ko > 0, "planted bars exist");
      double spikeH = 30000.0, spikeL = 12000.0;
      m2.b[(size_t)kp].h = spikeH;
      m2.b[(size_t)ko].l = spikeL;
      load(m2, U(2026, 9, 22, 14, 2));   // Tue 10:02 NY
      start();
      int i5 = g_s5.n - 1;
      const NbUsBar &b = g_us[(size_t)i5];
      CHECK(near(b.pmh, spikeH), "PM HIGH = the pre-market spike");
      CHECK(b.rthH < spikeH && b.or5h < spikeH && b.or15h < spikeH && b.or30h < spikeH, "the pre-market spike is in NO regular-session level");
      CHECK(near(b.rthL, spikeL) && near(b.or5l, spikeL) && near(b.or30l, spikeL), "the 09:30 spike is the regular low and every OR low");
      CHECK(b.pml > spikeL, "the regular-session spike is not in the pre-market low");
      OnDeinit(0);
      load(m2, U(2026, 9, 23, 14, 2));   // the next day
      start();
      i5 = g_s5.n - 1;
      CHECK(g_us[(size_t)i5].pdh < spikeH && near(g_us[(size_t)i5].pdl, spikeL), "next day: PDH ignores the pre-market spike, PDL is the regular spike");
      OnDeinit(0);
      // the last pre-market bar (09:25) missing: PMH / PML are published at the 09:30 bar and must still exclude it
      UMkt m4;
      m4.rule = mk.rule;
      for(const UBar &x : mk.b) if(x.et != U(2026, 9, 22, 9, 25)) m4.b.push_back(x);
      int k9 = -1;
      for(size_t q = 0; q < m4.b.size(); q++) if(m4.b[q].et == U(2026, 9, 22, 9, 30)) k9 = (int)q;
      m4.b[(size_t)k9].h = 31000.0;
      m4.b[(size_t)k9].l = 11000.0;
      load(m4, U(2026, 9, 22, 13, 37));   // 09:37: the 09:30 bar closed
      start();
      i5 = g_s5.n - 1;
      CHECK(g_us[(size_t)i5].pmh > 0.0 && g_us[(size_t)i5].pmh < 31000.0 && g_us[(size_t)i5].pml > 11000.0,
            "09:25 bar missing: PMH / PML published at 09:30 WITHOUT the regular 09:30 bar");
      CHECK(near(g_us[(size_t)i5].or5h, 31000.0), "that bar is the OR5 high");
      OnDeinit(0);
   }
   end("U1b");

   begin("U2 previous day across the weekend and a missing session; U3 a missing opening-range bar");
   {
      // Monday 14 Sep 10:02 NY: PDH / PDL / close = Friday 11 Sep regular session
      load(mk, U(2026, 9, 14, 14, 2));
      start();
      double fh = -1e18, fl = 1e18, fc = 0;
      for(const UBar &x : mk.b)
         if(x.et / 86400 == U(2026, 9, 11, 0, 0) / 86400 && etMin(x.et) >= 570 && etMin(x.et) < 960) { fh = std::max(fh, x.h); fl = std::min(fl, x.l); fc = x.c; }
      int i5 = g_s5.n - 1;
      CHECK(near(g_us[(size_t)i5].pdh, fh) && near(g_us[(size_t)i5].pdl, fl) && near(g_us[(size_t)i5].pcl, fc), "Monday: previous day = Friday's regular session");
      OnDeinit(0);
      // Thursday 17 Sep: Wednesday's regular session mostly missing (a thin day) -> previous day = Tuesday
      UMkt m3;
      m3.rule = mk.rule;
      for(const UBar &x : mk.b)
      {
         bool wedRth = x.et / 86400 == U(2026, 9, 16, 0, 0) / 86400 && etMin(x.et) >= 600 && etMin(x.et) < 960;
         bool orGap = x.et == U(2026, 9, 17, 9, 40);   // Thursday 09:40 NY bar missing
         if(!wedRth && !orGap) m3.b.push_back(x);
      }
      load(m3, U(2026, 9, 17, 14, 32));   // Thu 10:32
      start();
      double th = -1e18;
      for(const UBar &x : m3.b)
         if(x.et / 86400 == U(2026, 9, 15, 0, 0) / 86400 && etMin(x.et) >= 570 && etMin(x.et) < 960) th = std::max(th, x.h);
      i5 = g_s5.n - 1;
      CHECK(near(g_us[(size_t)i5].pdh, th), "a session with < 36 regular bars is not 'the previous day' (Tuesday kept)");
      CHECK(g_us[(size_t)i5].or5h > 0.0, "OR5 published (its only bar exists)");
      CHECK(g_us[(size_t)i5].or15h == 0.0 && g_us[(size_t)i5].or30h == 0.0, "OR15 / OR30 NOT published: a bar of the window is missing (never guessed)");
      OnDeinit(0);
      // before 09:35 nothing of the opening range is known
      load(mk, U(2026, 9, 17, 13, 33));   // 09:33: the 09:30 bar still forming
      start();
      i5 = g_s5.n - 1;
      CHECK(g_us[(size_t)i5].open == 0.0 && g_us[(size_t)i5].or5h == 0.0, "09:33: open and OR5 unknown (their bar has not closed)");
      CHECK(g_us[(size_t)i5].pmh > 0.0, "09:33: pre-market published (its window ended at 09:30)");
      OnDeinit(0);
   }
   end("U2/U3");

   begin("U4 gap: up / none, % and ATR, FILLED only when the regular session trades back; gapped levels");
   {
      // Friday 18 Sep: everything from Thursday 18:00 NY (the reopen) is shifted +400 -> a real gap at the reopen
      UMkt g = mk;
      long long reopen = U(2026, 9, 17, 22, 0);   // Thu 18:00 EDT
      for(UBar &x : g.b) if(x.utc >= reopen) { x.o += 400; x.h += 400; x.l += 400; x.c += 400; }
      load(g, U(2026, 9, 18, 14, 2));   // Fri 10:02 NY
      start();
      int i5 = g_s5.n - 1;
      NbUsBar b;
      NbUsCopy(b, g_us[(size_t)i5]);
      double pcl = 0, op = 0;
      for(const UBar &x : g.b)
      {
         if(x.et / 86400 == U(2026, 9, 17, 0, 0) / 86400 && etMin(x.et) >= 570 && etMin(x.et) < 960) pcl = x.c;
         if(x.et == U(2026, 9, 18, 9, 30)) op = x.o;
      }
      CHECK(near(b.pcl, pcl) && near(b.open, op) && near(b.gap, op - pcl), "gap = the 09:30 open - the previous regular close");
      CHECK(b.gapDir == 1 && b.gapAtr > 0.3, "GAP UP (above the 0.3 x 15M ATR threshold)");
      bool touched = false;
      for(const UBar &x : g.b) if(x.et >= U(2026, 9, 18, 9, 30) && x.et < U(2026, 9, 18, 10, 0) && x.l <= pcl) touched = true;
      CHECK(b.gapFilled == touched, "FILLED only if the regular session traded back to the previous close");
      CHECK(has(txt("vn4"), "GAP UP") && has(txt("vn4"), "%") && has(txt("vn4"), "ATR"), "gap row: GAP UP, % and ATR");
      std::string j = json();
      CHECK(has(j, "\"gap\":{\"direction\":\"UP\"") && has(j, "\"rule\":\"a level the gap jumped over is neither a sweep nor a breakout\""), "bridge: gap UP + the rule");
      OnDeinit(0);
      // now plant the fill at 11:00: a bar that trades down to the previous close
      int kf = findUtc(g, U(2026, 9, 18, 15, 0));
      g.b[(size_t)kf].l = pcl - 1.0;
      load(g, U(2026, 9, 18, 14, 57));   // 10:57: before the fill bar
      start();
      bool before = g_us[(size_t)(g_s5.n - 1)].gapFilled;
      OnDeinit(0);
      load(g, U(2026, 9, 18, 15, 7));    // 11:07: the fill bar closed
      start();
      bool after = g_us[(size_t)(g_s5.n - 1)].gapFilled;
      CHECK((!before || touched) && after, "FILLED appears with the bar that trades back, not before");
      CHECK(has(txt("vn4"), "FILLED"), "gap row says FILLED");
      OnDeinit(0);
      // a tiny move is NO GAP
      load(mk, U(2026, 9, 18, 14, 2));
      start();
      NbUsCopy(b, g_us[(size_t)(g_s5.n - 1)]);
      CHECK(std::fabs(b.gapAtr) >= 0.3 || (b.gapDir == 0 && has(txt("vn4"), "NO GAP")), "below the threshold: NO GAP");
      OnDeinit(0);
      // the gap test itself
      CHECK(NbUsGapped(100.0, 110.0, 105.0) && NbUsGapped(110.0, 100.0, 105.0), "a level strictly between the previous close and the open is gapped");
      CHECK(!NbUsGapped(100.0, 110.0, 100.0) && !NbUsGapped(100.0, 110.0, 110.0) && !NbUsGapped(100.0, 100.5, 105.0), "a level at either price, or beyond both, is not");
   }
   end("U4");

   begin("U4b / U5 / U6 / U12 the five-question plan on US levels: no gap is a sweep or a break; plans are sound");
   {
      // gaps at every 18:00 reopen (+/- 60 alternating) so levels get jumped over
      UMkt g = mk;
      double shift = 0.0;
      long long lastDay = -1;
      int flip = 1;
      for(UBar &x : g.b)
      {
         long long td = tdayOf(x.et);
         if(td != lastDay) { if(lastDay >= 0) { shift += 60.0 * flip; flip = -flip; } lastDay = td; }
         x.o += shift; x.h += shift; x.l += shift; x.c += shift;
      }
      load(g, U(2026, 9, 25, 19, 2));   // Fri 15:02 NY
      start();
      int sweeps = 0, breaks = 0, gappedEvents = 0, badSl = 0, badRr = 0, badFill = 0, badSide = 0, gapsOverLevels = 0;
      for(int p = 0; p < g_nFqPlan; p++)
      {
         const NbFqPlan &q = g_fqPlans[(size_t)p];
         int j = q.event;
         if(j >= 1 && NbUsGapped(g_s5.c[(size_t)(j - 1)], g_s5.o[(size_t)j], q.level)) gappedEvents++;
         if(q.kind == NB_PK_SWEEP) { sweeps++; if(!(q.dir > 0 ? g_s5.l[(size_t)j] < q.level : g_s5.h[(size_t)j] > q.level)) badSide++; }
         if(q.kind == NB_PK_BREAK) { breaks++; if(!(q.dir > 0 ? g_s5.c[(size_t)j] > q.level : g_s5.c[(size_t)j] < q.level)) badSide++; }
         bool slOk = q.dir > 0 ? (q.sl < q.entry && q.entry < q.tp1 && (q.tp2 == 0.0 || q.tp2 > q.tp1)) : (q.sl > q.entry && q.entry > q.tp1 && (q.tp2 == 0.0 || q.tp2 < q.tp1));
         if(!slOk || !near(q.risk, std::fabs(q.entry - q.sl))) badSl++;
         if(!near(q.rr1, std::fabs(q.tp1 - q.entry) / q.risk) || q.rr1 < InpFqMinRR - 1e-9) badRr++;
         if(q.fillIdx >= 0 && !(q.dir > 0 ? g_s5.l[(size_t)q.fillIdx] <= q.entry : g_s5.h[(size_t)q.fillIdx] >= q.entry)) badFill++;
         if(q.fillIdx >= 0 && q.fillIdx <= q.idx) badFill++;
      }
      // how often the data jumped over a mapped level (so the rule was exercised)
      for(int i = 1; i < g_s5.n; i++)
      {
         const NbFqBar &f = g_fq[(size_t)i];
         double lv[] = {f.pdh, f.pdl, f.ash, f.asl, f.loh, f.lol};
         for(double L : lv) if(L > 0.0 && NbUsGapped(g_s5.c[(size_t)(i - 1)], g_s5.o[(size_t)i], L)) gapsOverLevels++;
      }
      // every candidate the table evaluated (not only the plans that became READY)
      int candB = 0, candS = 0, candGapped = 0;
      for(int i = 0; i < g_s5.n; i++)
      {
         const NbFqBar &f = g_fq[(size_t)i];
         if(f.forming || f.event < 1 || (f.kind != NB_PK_SWEEP && f.kind != NB_PK_BREAK) || f.level <= 0.0) continue;
         candB += f.kind == NB_PK_BREAK;
         candS += f.kind == NB_PK_SWEEP;
         if(NbUsGapped(g_s5.c[(size_t)(f.event - 1)], g_s5.o[(size_t)f.event], f.level)) candGapped++;
      }
      char cmsg[160];
      std::snprintf(cmsg, sizeof cmsg, "%d break and %d sweep candidates on the table; %d of them start on a gap", candB, candS, candGapped);
      CHECK(candB > 0 && candS > 0 && candGapped == 0, cmsg);
      char msg[200];
      std::snprintf(msg, sizeof msg, "%d plans (%d sweep, %d break); %d mapped levels were jumped by a gap; %d plans started on a gap",
                    g_nFqPlan, sweeps, breaks, gapsOverLevels, gappedEvents);
      CHECK(gapsOverLevels > 0 && gappedEvents == 0, msg);
      CHECK(sweeps + breaks > 0, "the fixture produced plans");
      CHECK(badSide == 0, "every sweep pierced its level; every break CLOSED beyond it (a wick is neither)");
      CHECK(badSl == 0, "every plan: SL on the right side, entry, TP1, TP2 in order, risk = |entry - SL|");
      CHECK(badRr == 0, "R:R = |TP1 - entry| / risk and never below the minimum");
      CHECK(badFill == 0, "a limit fills only when a LATER bar trades to the entry (the retest)");
      int mid = 0, midReady = 0;
      for(int i = 0; i < g_s5.n; i++) if(g_fq[(size_t)i].why == NB_FW_MIDDLE) { mid++; if(g_fq[(size_t)i].status == NB_FQ_READY) midReady++; }
      CHECK(mid > 0 && midReady == 0, "PRICE IN THE MIDDLE - NO ENTRY HERE occurs and is never READY");
      OnDeinit(0);
      // a harsh fixture: EVERY bar opens halfway toward its own close, so about half of all level
      // crossings happen inside a gap. Crypto rules would count them; the US rules must count none.
      {
         UMkt hg = mk;
         for(size_t q = 1; q < hg.b.size(); q++)
         {
            UBar &x = hg.b[q];
            x.o = std::round((hg.b[q - 1].c + 0.5 * (x.c - hg.b[q - 1].c)) * 100.0) / 100.0;
            x.h = std::max(x.h, x.o);
            x.l = std::min(x.l, x.o);
         }
         load(hg, U(2026, 9, 25, 19, 2));
         start();
         int hb = 0, hs = 0, hgap = 0, crossGapped = 0;
         for(int i = 0; i < g_s5.n; i++)
         {
            const NbFqBar &f = g_fq[(size_t)i];
            double lv[] = {f.pdh, f.pdl, f.ash, f.asl, f.loh, f.lol};
            if(i > 0) for(double L : lv) if(L > 0.0 && NbUsGapped(g_s5.c[(size_t)(i - 1)], g_s5.o[(size_t)i], L)) crossGapped++;
            if(f.forming || f.event < 1 || (f.kind != NB_PK_SWEEP && f.kind != NB_PK_BREAK) || f.level <= 0.0) continue;
            hb += f.kind == NB_PK_BREAK;
            hs += f.kind == NB_PK_SWEEP;
            if(NbUsGapped(g_s5.c[(size_t)(f.event - 1)], g_s5.o[(size_t)f.event], f.level)) hgap++;
         }
         char hmsg[180];
         std::snprintf(hmsg, sizeof hmsg, "every bar gapped: %d gapped level crossings; %d break + %d sweep candidates, %d start on a gap", crossGapped, hb, hs, hgap);
         CHECK(crossGapped > 20 && hb > 0 && hgap == 0, hmsg);
      }
      bool names = has(NbLvSrcText(NB_LV_ASH), "PRE-MARKET") && has(NbLvSrcText(NB_LV_LOH), "OPENING RANGE") && !has(NbLvSrcText(0xff), "ASIA") &&
                   !has(NbLvSrcText(0xff), "LONDON");
      CHECK(names, "the table names US levels (PRE-MARKET, OPENING RANGE), never Asia / London");
      OnDeinit(0);
   }
   end("U4b/U5/U6/U12");

   begin("U7 causal: appending future bars changes nothing in the past; the 15M bar used is closed");
   {
      load(mk, U(2026, 9, 25, 13, 32));   // Fri 09:32 NY
      start();
      std::vector<NbUsBar> early(g_us.begin(), g_us.end());
      std::vector<NbFqBar> fqE(g_fq.begin(), g_fq.end());
      std::vector<datetime> tE(g_s5.t.begin(), g_s5.t.end());
      OnDeinit(0);
      load(mk, U(2026, 9, 25, 19, 32));   // the same day, 6 hours later: the same history window + 72 more bars
      start();
      int diff = 0, cmp = 0;
      for(size_t k = 0; k < tE.size() && k < (size_t)g_s5.n; k++)
      {
         if(g_s5.t[k] != tE[k]) { diff++; continue; }
         const NbUsBar &a = early[k], &b = g_us[k];
         cmp++;
         bool same = a.et == b.et && a.sess == b.sess && a.tday == b.tday && near(a.pdh, b.pdh) && near(a.pdl, b.pdl) && near(a.pcl, b.pcl) &&
                     near(a.onh, b.onh) && near(a.pmh, b.pmh) && near(a.pml, b.pml) && near(a.open, b.open) && near(a.or5h, b.or5h) &&
                     near(a.or15l, b.or15l) && near(a.or30h, b.or30h) && near(a.rthH, b.rthH) && near(a.rthL, b.rthL) && near(a.gap, b.gap) &&
                     a.gapDir == b.gapDir && a.gapFilled == b.gapFilled;
         same = same && fqE[k].status == g_fq[k].status && fqE[k].why == g_fq[k].why && near(fqE[k].entry, g_fq[k].entry) && near(fqE[k].sl, g_fq[k].sl);
         if(!same) diff++;
      }
      char msg[100];
      std::snprintf(msg, sizeof msg, "%d bars compared, %d changed by the future", cmp, diff);
      CHECK(cmp > 2000 && diff == 0, msg);
      bool closed15 = true;
      for(int i = 0; i < g_s5.n; i++)
      {
         int k = g_s5.map[(size_t)i];
         if(k >= 0 && g_s15.t[(size_t)k] + 900 > g_s5.t[(size_t)i] + 300) closed15 = false;
      }
      CHECK(closed15, "every 5M bar reads a 15M bar that had CLOSED by the 5M close");
      OnDeinit(0);
   }
   end("U7");

   begin("U8 stale data: WAIT, no US levels shown as live, no chip, bridge suppressed");
   {
      load(mk, mk.b.back().utc + 30 * 3600);
      start();
      CHECK(has(txt("state"), "WAIT") && has(txt("r1"), "DATA STALE"), "banner WAIT / DATA STALE");
      CHECK(has(txt("vn2"), "DATA STALE"), "US map says stale");
      CHECK(has(txt("mk"), "MARKET ---"), "no market state");
      std::string j = json();
      CHECK(has(j, "\"module\":\"US SESSION MAP\"") && has(j, "\"state\":\"SUPPRESSED - DATA STALE\""), "bridge: the US map suppressed");
      CHECK(has(j, "NO TRADE - DATA STALE"), "bridge action: NO TRADE - DATA STALE");
      OnDeinit(0);
   }
   end("U8");

   begin("U9 price too far: READY only near the entry; 0.8R either way = TOO FAR; no price = never READY");
   {
      long long nowT = 0;
      for(long long u = U(2026, 9, 21, 13, 30) + 120; u < U(2026, 9, 25, 20, 0) && nowT == 0; u += 300)
      {
         load(mk, u);
         start();
         if((g_final == NB_BUY || g_final == NB_SELL) && g_s5.sigOf[(size_t)(g_s5.n - 1)] >= 0) nowT = u;
         else OnDeinit(0);
      }
      CHECK(nowT > 0, "the fixture has a live 5M signal moment");
      if(nowT > 0)
      {
         const NbSignal &s = g_sigs[(size_t)g_s5.sigOf[(size_t)(g_s5.n - 1)]];
         bool buy = g_final == NB_BUY;
         double risk = std::fabs(s.entry - s.sl);
         SIM.bid = s.entry; SIM.ask = 0.0; OnTimer();
         CHECK(has(txt("state"), buy ? "READY - CLICK BUY" : "READY - CLICK SELL"), "at the entry: READY - CLICK");
         SIM.bid = s.entry + (buy ? 0.8 : -0.8) * risk; OnTimer();
         CHECK(has(txt("state"), "PRICE TOO FAR") && has(txt("r2"), "DO NOT CHASE"), "0.8R past: PRICE TOO FAR - DO NOT CHASE");
         SIM.bid = s.entry - (buy ? 0.8 : -0.8) * risk; OnTimer();
         CHECK(has(txt("state"), "PRICE TOO FAR"), "0.8R toward the SL: TOO FAR too");
         SIM.bid = 0.0; OnTimer();
         CHECK(!has(txt("state"), "READY"), "no live price: never READY");
         OnDeinit(0);
      }
   }
   end("U9");

   begin("U10 a forming candle changes nothing (US map, plan, signal)");
   {
      long long nowU = U(2026, 9, 23, 13, 32);   // 09:32 NY: the 09:30 bar is forming
      load(mk, nowU);
      start();
      std::vector<NbUsBar> a(g_us.begin(), g_us.end());
      int f1 = g_final, np = g_nFqPlan;
      std::string st = txt("state");
      OnDeinit(0);
      load(mk, nowU);
      for(auto *ser : {&SIM.m5, &SIM.m15, &SIM.m60, &SIM.m240})
         for(auto &b : *ser)
            if(b.time <= SIM.now && b.time + 300 > SIM.now) { b.high += 900; b.low -= 900; b.close -= 900; }
      start();
      bool same = a.size() == g_us.size();
      for(size_t k = 0; same && k < a.size(); k++)
         same = near(a[k].open, g_us[k].open) && near(a[k].or5h, g_us[k].or5h) && near(a[k].rthL, g_us[k].rthL) && a[k].gapFilled == g_us[k].gapFilled;
      CHECK(same && g_final == f1 && g_nFqPlan == np, "a +/-900 point forming spike changes no US level, no plan, no signal");
      CHECK(g_us.back().open == 0.0, "the open is still unknown while its bar is forming");
      OnDeinit(0);
   }
   end("U10");

   begin("U11 broker volume step: never above the budget, never rounded up; the loss tick value");
   {
      double atRisk = 0.0;
      struct { double step, min, want; } t[] = {{1.0, 1.0, 3.0}, {0.1, 0.1, 3.5}, {0.01, 0.01, 3.57}, {0.005, 0.005, 3.57}};
      for(auto &x : t)
      {
         double lots = NbLotsForRisk(10000, 1, 28.0, 0.01, 0.01, x.min, x.step, 100, atRisk);   // $100 budget, $2.80 per 0.01 lot... 28 points x $1
         char msg[80];
         std::snprintf(msg, sizeof msg, "step %.3f: %.3f lots (want %.3f), risk $%.2f <= $100", x.step, lots, x.want, atRisk);
         CHECK(near(lots, x.want) && atRisk <= 100.0 + 1e-9, msg);
      }
      CHECK(near(NbLotsForRisk(1000, 1, 2.6667, 0.01, 1, 0.005, 0.005, 100, atRisk), 0.035), "0.035 at step 0.005, not 0.04");
      load(mk, N1);
      SIM.tickValueLoss = SIM.tickValue * 1.5;
      start();
      CHECK(near(g_tickValue, SIM.tickValue * 1.5), "a larger loss tick value is used");
      OnDeinit(0);
   }
   end("U11");

   begin("U13 no cross-asset inference: the file reads its own symbol only; context is null");
   {
      std::ifstream f("NRTR_BOSS_US100.mq5");
      std::stringstream ss;
      ss << f.rdbuf();
      std::string src = ss.str();
      int calls = 0, foreign = 0;
      const char *apis[] = {"CopyRates(", "iBarShift(", "Bars(", "SymbolInfoDouble(", "SymbolInfoInteger(", "SymbolInfoString(", "SymbolInfoTick("};
      for(const char *api : apis)
      {
         size_t p = 0;
         while((p = src.find(api, p)) != std::string::npos)
         {
            size_t q = p + std::strlen(api);
            std::string arg = src.substr(q, 6);
            bool proto = src.compare(p > 0 ? p - 1 : 0, 1, " ") != 0 && src.compare(p > 0 ? p - 1 : 0, 1, "(") != 0 && src.compare(p > 0 ? p - 1 : 0, 1, "!") != 0 &&
                         src.compare(p > 0 ? p - 1 : 0, 1, "=") != 0;
            if(!proto) { calls++; if(arg.compare(0, 5, "g_sym") != 0) { foreign++; std::printf("    %s%s...\n", api, arg.c_str()); } }
            p = q;
         }
      }
      char msg[100];
      std::snprintf(msg, sizeof msg, "%d market-data calls, all on g_sym (%d on another symbol)", calls, foreign);
      CHECK(calls > 10 && foreign == 0, msg);
      load(mk, N1);
      start();
      std::string j = json();
      CHECK(has(j, "\"context\":null") && has(j, "correlation is not a signal"), "bridge: context null, 'correlation is not a signal'");
      OnDeinit(0);
   }
   end("U13");

   begin("U14 news: a label only, direction always UNKNOWN; decisions identical with news on / off / unavailable");
   {
      long long nowU = U(2026, 9, 23, 12, 20);   // 08:20 NY
      struct Snap { int fin, np; std::string st, j, row; };
      auto run = [&](int mode) {
         load(mk, nowU);
         if(mode >= 1) SIM.calOk = true;
         if(mode == 2)
         {
            SIM.cal.push_back({(datetime)(U(2026, 9, 23, 12, 30) + 3 * 3600), CALENDAR_IMPORTANCE_HIGH, "CPI m/m", "US", "USD"});
            SIM.cal.push_back({(datetime)(U(2026, 9, 24, 12, 30) + 3 * 3600), CALENDAR_IMPORTANCE_HIGH, "Initial Jobless Claims", "US", "USD"});
            SIM.cal.push_back({(datetime)(U(2026, 9, 23, 12, 25) + 3 * 3600), CALENDAR_IMPORTANCE_LOW, "Minor thing", "US", "USD"});
         }
         start();
         Snap s{g_final, g_nFqPlan, txt("state"), json(), txt("vn8")};
         OnDeinit(0);
         return s;
      };
      Snap a = run(0), b = run(1), c = run(2);
      CHECK(has(a.row, "UNKNOWN") && has(a.row, "NOT AVAILABLE"), "no calendar: NEWS UNKNOWN (never 'no news')");
      CHECK(has(b.row, "UNKNOWN"), "an empty calendar: UNKNOWN");
      CHECK(has(c.row, "WINDOW: CPI m/m") && has(c.row, "DIRECTION UNKNOWN"), "CPI in 10 min: WINDOW label, direction UNKNOWN");
      auto newsObj = [](const std::string &j) { size_t p = j.find("\"news\":{"); return p == std::string::npos ? std::string() : j.substr(p, j.find('}', p) - p); };
      CHECK(has(newsObj(c.j), "\"state\":\"EVENT WINDOW\"") && has(newsObj(c.j), "\"direction\":\"UNKNOWN\"") &&
            has(newsObj(b.j), "\"direction\":\"UNKNOWN\"") && has(newsObj(a.j), "\"direction\":\"UNKNOWN\""),
            "bridge: the news object's direction is UNKNOWN in every case");
      CHECK(a.fin == b.fin && b.fin == c.fin && a.np == c.np && a.st == c.st, "banner, signal and plans identical with news unavailable / empty / CPI");
   }
   end("U14");

   begin("U16 no execution: mt5_order_action NONE, read only");
   {
      load(mk, N1);
      start();
      std::string j = json();
      CHECK(has(j, "\"mt5_order_action\":\"NONE\"") && has(j, "\"read_only\":true"), "bridge: NONE / read_only");
      CHECK(has(j, "\"source\":\"NRTR_BOSS_US100\"") && has(j, "\"market\":\"US_INDEX\""), "bridge: source US100, market US_INDEX");
      CHECK(has(j, "\"regime_pullback\":{\"applicable\":true,\"not_a_signal\":true"), "regime watch present, not a signal");
      std::ofstream("build/bridge_us100.json") << j;   // for the Python schema + sender test
      OnDeinit(0);
      // the NY trap module is OFF in this file: over the whole window, no bar is in a NY phase and no trap signal exists
      load(mk, U(2026, 9, 25, 19, 32));
      start();
      int traps = 0, nyPh = 0;
      for(int k = 0; k < g_nSig; k++) traps += g_sigs[(size_t)k].kind == NB_K_TRAP;
      for(int i = 0; i < g_s5.n; i++) nyPh += g_s5.ph[(size_t)i] != NB_PH_OUT;
      char msg[100];
      std::snprintf(msg, sizeof msg, "%d signals over the window: %d NY-trap signals, %d bars in a NY phase", g_nSig, traps, nyPh);
      CHECK(g_nSig > 0 && traps == 0 && nyPh == 0, msg);
      OnDeinit(0);
   }
   end("U16");

   std::printf("\nUS100 TESTS: %d checks passed, %d failed\n", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
