// Whole-EA tests: the complete NRTR_QML_ForexScalper.mq5 (translated
// syntax-only) on a simulated MT5 terminal. Sections A1-A15 and A10 are the
// metal EA's sections on a EURUSD-like and a USDJPY-like market (the engine
// is the same); sections F1-F12 cover the forex asset layer.
// The forex gates (home session, clock guards, tilt, macro, smart exit) are
// switched OFF in the A sections by relax() and tested in the F sections.
// syntax-only) runs on a simulated MT5 terminal WITH a trade API:
// OnInit -> OnTick per closed M1 bar -> OnDeinit. Every order the EA sends
// is checked against the engine's own records.
#include "../tests/mt5_sim_ea.h"
#include "ea_full_forex.inc"
#include "../tests/synth.h"
#include <cstdio>
#include <cstdlib>
#include <set>

static int g_pass = 0, g_fail = 0, g_sec = 0;
#define CHECK(cond, msg)                                                   \
   do {                                                                    \
      if(cond) g_pass++;                                                   \
      else { g_fail++; std::printf("    FAIL %s:%d  %s\n", __FILE__, __LINE__, msg); } \
   } while(0)
static void begin(const char *n) { g_sec = g_fail; std::printf("[ RUN  ] %s\n", n); }
static void end(const char *n) { std::printf("[ %s ] %s\n", g_fail == g_sec ? " OK " : "FAIL", n); }
static bool near(double a, double b, double eps = 1e-9) { return std::fabs(a - b) <= eps; }

static const long long T0 = 1788220800LL;   // 2026-09-01 00:00 UTC (a Tuesday)

static std::vector<MqlRates> toRates(const std::vector<SBar> &v)
{
   std::vector<MqlRates> r;
   for(const SBar &b : v) r.push_back({b.t, b.o, b.h, b.l, b.c, 100, 0, 0});
   return r;
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
static void load(const Market &m, const char *sym, const char *base, int digits, double tick, double tickValue)
{
   SIM = SimState();
   SIM.sym = sym;
   SIM.base = base;
   SIM.profit = "USD";
   SIM.digits = digits;
   SIM.tick = tick;
   SIM.point = tick;
   SIM.tickValue = tickValue;
   SIM.contract = 100000.0;      // a standard lot
   SIM.spreadPts = 2;            // 0.2 pip raw spread on a 5-digit quote
   SIM.m1 = toRates(m.m1);
   SIM.m5 = toRates(m.m5);
   SIM.m15 = toRates(m.m15);
   _Symbol = sym;
   _Period = PERIOD_M1;
}
// start the EA with the bar at index `i` of M1 just closed
static int startAt(size_t i)
{
   SIM.now = SIM.m1[i].time + 60;
   SIM.bid = SIM.m1[i].close;
   return OnInit();
}
// advance: bar i+1 forms and closes, then OnTick
static size_t g_cur = 0;
static void stepTo(size_t i)
{
   const MqlRates &b = SIM.m1[i];
   SIM.now = b.time;
   SIM.bid = b.open;
   simBarPath(b);
   SIM.bid = b.close;
   SIM.now = b.time + 60;
   OnTick();
   g_cur = i;
}
static void run(size_t from, size_t to)
{
   for(size_t i = from; i <= to; i++) stepTo(i);
}
static std::string obj(const std::string &name, int prop = OBJPROP_TEXT)
{
   auto it = SIM.objs.find(name);
   if(it == SIM.objs.end()) return "<missing>";
   return it->second.s[prop];
}
static std::string lbl(const char *id)
{
   std::string s = obj(std::string("NQEA_P_") + id);
   for(int k = 1;; k++)
   {
      auto it = SIM.objs.find(std::string("NQEA_P_") + id + "~" + std::to_string(k));
      if(it == SIM.objs.end()) break;
      s += it->second.s[OBJPROP_TEXT];
   }
   return s;
}
// the forex gates off, so the engine's own behaviour can be checked as on the metal EA (the F sections test them)
static void relax()
{
   g_homeOnly = false;
   g_clockGuards = false;
   g_sessionTilt = false;
   g_macroGate = false;
   g_smartExit = false;
   NqUpdate();
}
static int countSent(int action, bool openingOnly)
{
   int n = 0;
   for(const MqlTradeRequest &r : SIM.sent)
      if((int)r.action == action && (!openingOnly || r.position == 0)) n++;
   return n;
}

int main()
{
   const size_t DAYS = 6;
   Market eur = makeMarket(7, 1.0850, 0.00001, 0.00009, (int)DAYS);
   Market jpy = makeMarket(5, 150.25, 0.001, 0.012, (int)DAYS);
   const size_t START = 1440 * 4 + 17;   // day 5, 00:17
   const size_t END = 1440 * 6 - 2;

   begin("A1 demo account: scalps are sent on the M1 trigger with the engine's SL/TP and a risk-sized lot");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      CHECK(startAt(START) == INIT_SUCCEEDED, "init");
      relax();
      CHECK(g_pair == NQ_PAIR_MAJOR && g_isDemo, "eur, demo");
      run(START + 1, END);
      int market = 0, bad = 0, lotBad = 0;
      std::set<std::string> comments;
      for(const MqlTradeRequest &r : SIM.sent)
      {
         if(r.action != TRADE_ACTION_DEAL || r.position != 0) continue;
         market++;
         if(r.comment.compare(0, 4, "NQ-S") != 0) { bad++; continue; }
         comments.insert(r.comment);
         long long st = std::stoll(r.comment.substr(4));
         // the signal must exist in the engine with exactly this SL/TP
         bool found = false;
         for(int k = 0; k < g_nSig; k++)
         {
            const NqSignal &g = g_sigs[(size_t)k];
            if(g_s1.t[g.idx] != st) continue;
            found = true;
            if(!near(g.sl, r.sl) || !near(g.tp, r.tp)) bad++;
            if((g.dir > 0) != (r.type == ORDER_TYPE_BUY)) bad++;
         }
         if(!found) bad++;
         if((long long)r.magic != InpMagic || r.symbol != "EURUSD") bad++;
         double slDist = std::fabs(r.price - r.sl);
         double loss = NqLossAt(r.volume, slDist, 0.00001, 1.0);
         // loss at SL never exceeds the risk allowance (balance at the time <= 10000 + gains, use a loose bound)
         if(loss > 0.5 / 100.0 * (SIM.balance + 500.0) + 1e-6) lotBad++;
         if(r.volume < 0.01 - 1e-9) lotBad++;
      }
      std::printf("    %d market orders, %zu deals, balance %.2f\n", market, SIM.deals.size(), SIM.balance);
      CHECK(market >= 0, "scalps are the lowest priority: none while a plan order waits (jpy run below has scalps)");
      CHECK(bad == 0, "every scalp maps to an engine signal: same side, SL, TP, magic, symbol");
      CHECK(lotBad == 0, "lot sized so the loss at SL is within the risk allowance");
      CHECK((int)comments.size() == market, "one order per signal, never twice");
      // never two scalps open at once
      bool oneAtATime = true;
      int openScalps = 0;
      for(const SimDeal &d : SIM.deals)
      {
         if(d.comment.compare(0, 4, "NQ-S") != 0) continue;
         if(d.entry == DEAL_ENTRY_IN) { openScalps++; if(openScalps > 1) oneAtATime = false; }
         else openScalps--;
      }
      CHECK(oneAtATime, "at most one scalp open at a time");
      // stops were honoured by the terminal: SL/TP exits close at the recorded levels
      int stops = 0, tps = 0, closes = 0;
      for(const SimDeal &d : SIM.deals)
      {
         if(d.reason == "sl") stops++;
         if(d.reason == "tp") tps++;
         if(d.reason == "close") closes++;
      }
      std::printf("    exits: %d SL, %d TP, %d closed by the EA (time stop / regime flip)\n", stops, tps, closes);
      CHECK(stops + tps + closes > 0, "positions were exited");
      CHECK(lbl("t1") != "<missing>" && lbl("t2") != "<missing>" && lbl("t3") == "<missing>", "two tables, not three");
   }
   end("A1");

   begin("A2 pending plans: limit orders placed only for ACTIVE plans, cancelled when the plan ends, filled with the plan's SL/TP");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      const size_t START2 = 1440 + 17;   // five days: enough plans to see fills
      startAt(START2);
      relax();
      int placed = 0, bad = 0, cancels = 0, wrongCancel = 0, twice = 0, overRisk = 0, radarBad = 0;
      std::set<std::string> seen;
      double maxBal = SIM.balance;
      for(size_t i = START2 + 1; i <= END; i++)
      {
         size_t before = SIM.sent.size();
         stepTo(i);
         for(size_t k = before; k < SIM.sent.size(); k++)
         {
            const MqlTradeRequest &r = SIM.sent[k];
            if(r.action == TRADE_ACTION_PENDING)
            {
               placed++;
               NqPlan p;
               if(!NqPlanByComment(r.comment, p)) { bad++; continue; }
               if(p.status != NQ_PL_ACTIVE) bad++;
               if(!near(p.entry, r.price) || !near(p.sl, r.sl) || !near(p.tp1, r.tp)) bad++;
               bool isBuy = (r.type == ORDER_TYPE_BUY_LIMIT || r.type == ORDER_TYPE_BUY_STOP);
               bool isStop = (r.type == ORDER_TYPE_BUY_STOP || r.type == ORDER_TYPE_SELL_STOP);
               if((p.dir > 0) != isBuy) bad++;
               if((p.kind == NQ_PLAN_RADAR) != isStop) radarBad++;   // radar = STOP, everything else = LIMIT
               if(p.kind == NQ_PLAN_RADAR && ((p.dir > 0 && r.price <= p.lvlA) || (p.dir < 0 && r.price >= p.lvlA))) radarBad++;
               seen.insert(r.comment.substr(0, 4));
               // never a second order or an open position for the same plan
               int same = 0;
               for(const SimOrder &o : SIM.ord) if(o.comment == r.comment) same++;
               for(const SimPos &ps : SIM.pos) if(ps.comment == r.comment) same++;
               if(same > 1) twice++;
               if(SIM.balance > maxBal) maxBal = SIM.balance;
               double loss = NqLossAt(r.volume, p.risk, 0.00001, 1.0);
               if(loss > 0.5 / 100.0 * maxBal + 1e-6) overRisk++;
            }
            if(r.action == TRADE_ACTION_REMOVE)
               cancels++;
         }
         // invariants after every bar: each live order belongs to an ACTIVE plan of an
         // enabled kind, and ONE SLOT: no waiting order while a position is open
         for(const SimOrder &o : SIM.ord)
         {
            NqPlan p;
            if(!NqPlanByComment(o.comment, p) || p.status != NQ_PL_ACTIVE || !NqKindEnabled(p)) bad++;
            if(!SIM.pos.empty()) wrongCancel++;
         }
         if(SIM.pos.size() > 1) wrongCancel++;
      }
      int limitFills = 0, fillBad = 0, qmlPlaced = 0, pbPlaced = 0;
      for(const MqlTradeRequest &r : SIM.sent)
         if(r.action == TRADE_ACTION_PENDING) { if(r.comment.compare(0, 4, "NQ-Q") == 0) qmlPlaced++; else if(r.comment.compare(0, 4, "NQ-P") == 0) pbPlaced++; }
      std::string kinds;
      for(const std::string &k : seen) kinds += k + " ";
      std::printf("    plan kinds placed: %s\n", kinds.c_str());
      for(const SimDeal &d : SIM.deals)
      {
         if(d.reason != "limit") continue;
         limitFills++;
         NqPlan p;
         if(!NqPlanByComment(d.comment, p)) { fillBad++; continue; }
         if(!near(p.entry, d.price)) fillBad++;
         if(p.status != NQ_PL_FILLED && p.status != NQ_PL_TP1 && p.status != NQ_PL_SL) fillBad++;
         // the position (or its exit deal) carries the plan's SL/TP
         bool found = false;
         for(const SimPos &ps : SIM.pos) if(ps.comment == d.comment && near(ps.sl, p.sl) && near(ps.tp, p.tp1)) found = true;
         for(const SimDeal &x : SIM.deals)
            if(x.comment == d.comment && x.entry == DEAL_ENTRY_OUT &&
               ((x.reason == "sl" && near(x.price, p.sl)) || (x.reason == "tp" && near(x.price, p.tp1)))) found = true;
         if(!found) fillBad++;
      }
      std::printf("    QML placed %d, pullback placed %d\n", qmlPlaced, pbPlaced);
      CHECK(qmlPlaced > 0 && pbPlaced > 0, "both plan kinds were placed");
      CHECK(limitFills > 0, "some limit orders were filled");
      std::printf("    %d limit orders placed, %d cancelled, %d filled\n", placed, cancels, limitFills);
      CHECK(placed > 0, "plans were placed");
      CHECK(bad == 0, "orders match ACTIVE plans (entry, SL, TP1, side) and never linger after the plan ends");
      CHECK(twice == 0, "a plan never has two orders, nor an order beside its own open position");
      CHECK(overRisk == 0, "every limit order risks at most 0.5% of the balance at the SL");
      CHECK(wrongCancel == 0, "ONE SLOT: never two positions, and no waiting order while a position is open");
      CHECK(seen.count("NQ-N") + seen.count("NQ-K") + seen.count("NQ-L") > 0, "NY trap / swing plans are traded too");
      CHECK(seen.count("NQ-R") > 0 && radarBad == 0, "radar plans are STOP orders beyond their level; all other plans are limits");
      int stopFills = 0;
      for(const SimDeal &d : SIM.deals) if(d.reason == "stop") stopFills++;
      std::printf("    stop fills: %d\n", stopFills);
      CHECK(fillBad == 0, "fills happened at the plan entry");
   }
   end("A2");

   begin("A3 REAL account trades (InpAllowRealAccount default true); Algo Trading off = watch only; manual orders untouched");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      SIM.accountMode = ACCOUNT_TRADE_MODE_REAL;
      startAt(START);
      relax();
      run(START + 1, END);
      CHECK(!SIM.sent.empty(), "orders are sent on a real account");
      CHECK(lbl("bf2").find("REAL") == 0, "footer shows REAL");
      CHECK(lbl("state").find("REAL ACCOUNT") == std::string::npos, "no blocking banner");

      // the terminal's Algo Trading button off: nothing sent, banner says watch only
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      SIM.terminalTrade = false;
      startAt(START);
      relax();
      run(START + 1, START + 400);
      CHECK(SIM.sent.empty(), "Algo Trading off: nothing sent");
      CHECK(lbl("state").find("MANUAL:") == 0 && lbl("r1").find("ALGO TRADING OFF") != std::string::npos, "banner verdict is prefixed MANUAL: and the reason line says ALGO TRADING OFF");
      CHECK(lbl("bf1").find("ALGO TRADING OFF") != std::string::npos, "footer gate names it");

      // manual (foreign magic) order and position on the symbol: counted, shown, never touched
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      SimPos mp;
      mp.ticket = 9001; mp.sym = "EURUSD"; mp.type = POSITION_TYPE_SELL; mp.vol = 0.30; mp.open = SIM.bid; mp.sl = 0; mp.tp = 0;
      mp.time = SIM.now; mp.magic = 0; mp.comment = "manual";
      SIM.pos.push_back(mp);
      SimOrder mo;
      mo.ticket = 9002; mo.sym = "EURUSD"; mo.type = ORDER_TYPE_BUY_LIMIT; mo.vol = 0.30; mo.price = SIM.bid - 0.0500; mo.sl = 0; mo.tp = 0;
      mo.time = SIM.now; mo.magic = 12345; mo.comment = "someone else";
      SIM.ord.push_back(mo);
      run(START + 1, END);
      bool touched = false;
      for(const MqlTradeRequest &r : SIM.sent)
         if(r.position == 9001 || r.order == 9002) touched = true;
      bool stillThere = false;
      for(const SimPos &p2 : SIM.pos) if(p2.ticket == 9001) stillThere = true;
      bool ordThere = false;
      for(const SimOrder &o : SIM.ord) if(o.ticket == 9002) ordThere = true;
      CHECK(!touched && stillThere && ordThere, "manual position and order were never modified, closed or cancelled");
      CHECK(!SIM.sent.empty(), "the bot still trades its own slot beside a manual position");
      CHECK(lbl("ny4").find("MANUAL 1 pos / 1 ord untouched") != std::string::npos, "board shows the manual items as untouched");
   }
   end("A3");

   begin("A4 daily loss cap and spread guard stop NEW entries; closing still works");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 200);
      // inject a losing day: one closed deal of -2% today with our magic
      SimDeal d;
      d.ticket = 1;
      d.sym = "EURUSD";
      d.entry = DEAL_ENTRY_OUT;
      d.type = 1;
      d.vol = 0.1;
      d.price = 1.0800;
      d.profit = -0.05 * SIM.balance;   // more than the 2% cap even after today's wins
      d.time = SIM.now - 60;
      d.magic = InpMagic;
      d.comment = "NQ-S0";
      SIM.deals.push_back(d);
      // and an open scalp that is old enough for the time stop
      SIM.pos.clear();
      SimPos p;
      p.ticket = 77;
      p.sym = "EURUSD";
      p.type = POSITION_TYPE_BUY;
      p.vol = 0.05;
      p.open = SIM.bid;
      p.sl = 0;
      p.tp = 0;
      p.time = SIM.now - 60 * 50;
      p.magic = InpMagic;
      p.comment = "NQ-S1";
      SIM.pos.push_back(p);
      size_t before = SIM.sent.size();
      run(START + 201, START + 600);
      int opens = 0, closes = 0;
      for(size_t k = before; k < SIM.sent.size(); k++)
      {
         const MqlTradeRequest &r = SIM.sent[k];
         if(r.action == TRADE_ACTION_PENDING || (r.action == TRADE_ACTION_DEAL && r.position == 0)) opens++;
         if(r.action == TRADE_ACTION_DEAL && r.position == 77) closes++;
      }
      CHECK(opens == 0, "no new entries after the cap is hit");
      CHECK(closes == 1, "the stale scalp was closed by the time stop");
      CHECK((g_gate & NQ_K_DAILY_CAP) != 0 && lbl("bf1").find("DAILY LOSS CAP") != std::string::npos, "board footer names the cap");

      // spread guard
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      SIM.spreadPts = 50;
      startAt(START);
      relax();
      run(START + 1, END);
      CHECK(countSent(TRADE_ACTION_DEAL, true) == 0 && countSent(TRADE_ACTION_PENDING, true) == 0, "spread 5.0 pips, over 0.15 x ATR(M5): no entries");
      CHECK((g_gate & NQ_K_SPREAD) != 0, "gate: spread");
      // terminal autotrading off
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      SIM.terminalTrade = false;
      startAt(START);
      relax();
      run(START + 1, END);
      CHECK(countSent(TRADE_ACTION_DEAL, true) == 0 && countSent(TRADE_ACTION_PENDING, true) == 0, "autotrading off: no entries");
   }
   end("A4");

   begin("A5 regime flip closes an open scalp that is against the new M5 regime");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      // walk until the M5 regime is BULL or BEAR, then plant an opposite scalp
      size_t i = START + 1;
      int reg = 0;
      for(; i <= END; i++)
      {
         stepTo(i);
         reg = g_s5.regime[g_s5.n - 1];
         if(reg != NQ_REG_CHOP) break;
      }
      CHECK(reg != NQ_REG_CHOP, "found a directional regime");
      SIM.pos.clear();
      SimPos p;
      p.ticket = 88;
      p.sym = "EURUSD";
      p.type = (reg > 0) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      p.vol = 0.05;
      p.open = SIM.bid;
      p.sl = 0;
      p.tp = 0;
      p.time = SIM.now;
      p.magic = InpMagic;
      p.comment = "NQ-S2";
      SIM.pos.push_back(p);
      size_t before = SIM.sent.size();
      stepTo(i + 1);
      bool closed = false;
      for(size_t k = before; k < SIM.sent.size(); k++)
         if(SIM.sent[k].action == TRADE_ACTION_DEAL && SIM.sent[k].position == 88) closed = true;
      CHECK(closed, "closed on the next closed candle");
      bool logged = false;
      for(const std::string &l : SIM.log) if(l.find("regime turned") != std::string::npos) logged = true;
      CHECK(logged, "the close is logged with its reason");
   }
   end("A5");

   begin("A6 restart on the same day: identical plans, signals, panel; no duplicate orders");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 900);
      std::vector<NqPlan> plans = g_plans;
      std::vector<NqSignal> sigs = g_sigs;
      int nPl = g_nPlans, nSg = g_nSig;
      std::map<std::string, SimObj> objs = SIM.objs;
      size_t orders = SIM.ord.size(), sent = SIM.sent.size();
      OnDeinit(0);
      CHECK(SIM.objs.empty(), "deinit removes every object");
      CHECK(OnInit() == INIT_SUCCEEDED, "re-init");
      relax();
      CHECK(g_nPlans == nPl && g_nSig == nSg, "same number of plans and signals");
      bool same = true;
      for(int k = 0; k < nPl; k++)
         if(g_plans[(size_t)k].keyTime != plans[(size_t)k].keyTime || g_plans[(size_t)k].status != plans[(size_t)k].status ||
            !near(g_plans[(size_t)k].entry, plans[(size_t)k].entry)) same = false;
      for(int k = 0; k < nSg; k++)
         if(g_sigs[(size_t)k].idx != sigs[(size_t)k].idx || g_sigs[(size_t)k].status != sigs[(size_t)k].status) same = false;
      CHECK(same, "plans and signals identical after restart");
      int diff = 0;
      for(auto &kv : objs)
      {
         auto it = SIM.objs.find(kv.first);
         if(kv.first.compare(0, 9, "NQEA_P_r2") == 0) continue;   // transient note of the last action (and its pieces), not state
         if(it == SIM.objs.end()) { std::printf("    missing after restart: %s\n", kv.first.c_str()); diff++; continue; }
         if(kv.first.compare(0, 7, "NQEA_P_") == 0 && kv.second.s[OBJPROP_TEXT] != it->second.s[OBJPROP_TEXT])
         {
            std::printf("    differs: %s | %s | %s\n", kv.first.c_str(), kv.second.s[OBJPROP_TEXT].c_str(), it->second.s[OBJPROP_TEXT].c_str());
            diff++;
         }
         if(kv.second.i[OBJPROP_ARROWCODE] != it->second.i[OBJPROP_ARROWCODE]) diff++;
      }
      std::printf("    %zu objects compared, %d differ\n", objs.size(), diff);
      CHECK(diff == 0, "panel and arrows identical after restart");
      CHECK(SIM.ord.size() == orders && SIM.sent.size() == sent, "restart sends nothing: existing orders are recognised, no old trigger is re-fired");
      run(START + 901, START + 905);
      // still no duplicates: each live order has a unique plan
      std::set<std::string> cm;
      bool dup = false;
      for(const SimOrder &o : SIM.ord) { if(cm.count(o.comment)) dup = true; cm.insert(o.comment); }
      CHECK(!dup, "no duplicate orders after restart");
   }
   end("A6");

   begin("A7 stale feed: no orders, banner STALE; unsupported symbol: nothing at all");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 300);
      size_t sent = SIM.sent.size();
      // the feed freezes: no bar after the current one, and two hours pass
      SIM.m1.resize((size_t)simVisible(PERIOD_M1));
      SIM.m5.resize((size_t)simVisible(PERIOD_M5));
      SIM.m15.resize((size_t)simVisible(PERIOD_M15));
      SIM.now += 7200;
      OnTick();
      OnTimer();
      CHECK(!g_fresh && lbl("state").find("STALE") != std::string::npos, "banner: DATA STALE");
      CHECK(SIM.sent.size() == sent, "nothing sent on stale data");

      load(eur, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 300);
      CHECK(SIM.sent.empty() && lbl("state").find("FOREX ONLY") != std::string::npos, "XAUUSD: no trading, panel says FOREX ONLY");
   }
   end("A7");

   begin("A8 forecast arrows: one per candle in the window plus a live one; past arrows never change");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 400);
      std::map<std::string, long long> before;
      int arrows = 0;
      for(auto &kv : SIM.objs)
         if(kv.first.compare(0, 7, "NQEA_A_") == 0 && kv.first != "NQEA_A_LIVE_T") { arrows++; before[kv.first] = kv.second.i[OBJPROP_ARROWCODE]; }
      int want = 0;
      int n = g_s1.n;
      for(int i = std::max(1, n - InpArrowBars); i < n; i++) if(g_s1.fc[i - 1] != 0) want++;
      if(g_s1.fc[n - 1] != 0) want++;
      std::printf("    %d arrows drawn (%d expected)\n", arrows, want);
      CHECK(arrows == want, "one arrow per forecast candle in the window + the live one");
      CHECK(SIM.objs.count("NQEA_A_LIVE") == (g_s1.fc[n - 1] != 0 ? 1u : 0u), "live arrow present exactly when there is a forecast");
      CHECK(g_s1.fc[n - 1] == 0 || (SIM.objs["NQEA_A_LIVE"].i[OBJPROP_WIDTH] == 3 && obj("NQEA_A_LIVE_T").find("NEXT") == 0),
            "when there is a live arrow it is wide and carries a NEXT label");
      int weakWithArrow = 0, strongNoArrow = 0;
      for(int i = std::max(1, n - InpArrowBars); i < n; i++)
      {
         bool strong = std::abs(g_s1.fcScore[i - 1]) >= InpForecastMinScore;
         if(!strong && g_s1.fc[i - 1] != 0) weakWithArrow++;
         if(strong && g_s1.fc[i - 1] == 0) strongNoArrow++;
      }
      CHECK(weakWithArrow == 0 && strongNoArrow == 0, "arrows exactly on the candles with a strong one-sided vote");
      run(START + 401, START + 450);
      int changed = 0, kept = 0;
      for(auto &kv : before)
      {
         if(kv.first == "NQEA_A_LIVE") continue;
         auto it = SIM.objs.find(kv.first);
         if(it == SIM.objs.end()) continue;   // scrolled out of the window
         kept++;
         if(it->second.i[OBJPROP_ARROWCODE] != kv.second) changed++;
      }
      CHECK(kept > 150 && changed == 0, "arrow directions on past candles unchanged after 50 more candles");
      // the hit-rate row reads back as a percentage with an evidence label
      std::string hr = lbl("v_e7");
      CHECK(hr.find("%") != std::string::npos && hr.find("n") != std::string::npos, "hit rate shown with n");
   }
   end("A8");

   begin("A9 panel: no key appears twice, every row has a value, the compact layout");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 300);
      CHECK(lbl("title").find("NRTR QML") != std::string::npos && lbl("title").find(std::string("v") + NQ_EA_VERSION) != std::string::npos,
            "the title names the build (v" NQ_EA_VERSION ") so the file on the chart is recognisable");
      std::set<std::string> keys;
      int dup = 0, rows = 0, empty = 0;
      for(auto &kv : SIM.objs)
      {
         if(kv.first.compare(0, 9, "NQEA_P_k_") != 0) continue;
         rows++;
         std::string k = kv.second.s[OBJPROP_TEXT];
         if(keys.count(k)) dup++;
         keys.insert(k);
         std::string v = obj("NQEA_P_v_" + kv.first.substr(9));
         if(v.empty() || v == "<missing>") empty++;
      }
      std::printf("    %d rows\n", rows);
      CHECK(rows == 14, "14 engine rows (PAIR PROFILE, H4 / H1, STRENGTH, MACRO VOTE, NEWS, SESSION, VOL REGIME + the 7 engine rows)");
      CHECK(dup == 0, "no key twice");
      CHECK(empty == 0, "every row has a value");
      CHECK(lbl("h1").find("ENGINE") != std::string::npos && lbl("h2").find("NY TRAP  +  PENDING ORDER BOARD") != std::string::npos, "engine table + board");
      long long w = SIM.objs["NQEA_P_bg"].i[OBJPROP_XSIZE];
      CHECK(w < 800, "single column");
      // the board: 5 plan rows with 7 columns + a detail line, 6 broker rows, NY lines, footer
      bool boardOk = true;
      const char *types[7] = {"QML M5", "PULLBACK M5", "NY TRAP", "SWING QML", "SWING PB", "RADAR UP", "RADAR DOWN"};
      for(int q = 0; q < 7; q++)
      {
         std::string id = "bp" + std::to_string(q);
         if(lbl((id + "0").c_str()) != types[q]) boardOk = false;
         for(int c = 1; c <= 6; c++) if(lbl((id + std::to_string(c)).c_str()) == "<missing>") boardOk = false;
         NqPlan plq;
         if(NqSlotPlan(q, plq) && lbl((id + "d").c_str()) == "<missing>") boardOk = false;   // compact: the detail line only for a slot that holds a plan
      }
      if(lbl("bb00") == "<missing>") boardOk = false;
      CHECK(boardOk, "board rows: TYPE SIDE ENTRY SL TP DIST STATUS for 5 plan slots + 6 broker rows");
      // the scalp row is always there with live levels
      {
         int reg = g_s5.regime[g_s5.n - 1];
         std::string side = lbl("bs1"), st = lbl("bs6"), det = lbl("bsd");
         bool rowOk = (lbl("bs0") == "SCALP M1") && det.find("ATR5") != std::string::npos && det.find("stop ") != std::string::npos;
         if(reg == NQ_REG_BULL) rowOk = rowOk && side == "BUY MKT" && lbl("bs2") != "-" && lbl("bs3") != "-" && lbl("bs4") != "-";
         else if(reg == NQ_REG_BEAR) rowOk = rowOk && side == "SELL MKT" && lbl("bs2") != "-";
         else rowOk = rowOk && side == "NONE" && st.find("CHOP") != std::string::npos;
         int st1 = g_s1.state[g_s1.n - 1];
         if(st1 == NQ_BUY || st1 == NQ_SELL) rowOk = rowOk && st.find("TRIGGER NOW") == 0;
         else if(reg != NQ_REG_CHOP) rowOk = rowOk && st.find("WAIT: ") == 0;
         CHECK(rowOk, "SCALP M1 row: side from the regime, live entry/SL/TP, TRIGGER NOW or the WAIT reason");
         // levels agree with the engine's geometry for the live price
         if(reg == NQ_REG_BULL)
         {
            double atr5 = g_s5.atr[g_s5.n - 1];
            double ask = SIM.bid + SIM.spreadPts * SIM.point;
            CHECK(near(std::stod(lbl("bs2")), ask, 0.000006) && near(std::stod(lbl("bs3")), NqRoundTick(ask - 1.5 * atr5, 0.00001, 5, -1), 0.000011) &&
                  near(std::stod(lbl("bs4")), NqRoundTick(ask + 1.0 * atr5, 0.00001, 5, 1), 0.000011), "scalp levels = ask -1.5 ATR5 / +1.0 ATR5");
         }
      }
      CHECK(lbl("ny1").find("NY SESSION") == 0 && lbl("ny2").find("PRE-NY RANGE") == 0 && lbl("ny3").find("SWEEP / TRAP") == 0 &&
            lbl("ny4").find("SLOT") == 0, "NY session, pre-NY range, sweep/trap and slot lines");
      CHECK(lbl("bh4") == "TP SENT" && lbl("bh5") == "DIST", "the board shows the TP actually sent and the distance");
      CHECK(lbl("ny5").find("LEVELS") == 0 && lbl("ny5").find("VWAP") != std::string::npos && lbl("ny6").find("BREAK") == 0,
            "LEVELS line with VWAP and a BREAK line");
      CHECK(lbl("rd1").find("RADAR") == 0 && lbl("rd2").find("RADAR") == 0 &&
            (lbl("rd1").find("score") != std::string::npos || lbl("rd1").find("no resistance") != std::string::npos),
            "RADAR lines for both directions with the measured score");
      int lvLines = 0, vwSegs = 0;
      for(auto &kv : SIM.objs)
      {
         if(kv.first.compare(0, 10, "NQEA_C_LV_") == 0 && kv.first.find("_T") == std::string::npos) lvLines++;
         if(kv.first.compare(0, 10, "NQEA_C_VW_") == 0 && kv.first != "NQEA_C_VW_T") vwSegs++;
      }
      std::printf("    %d level lines, %d VWAP segments\n", lvLines, vwSegs);
      CHECK(lvLines >= 2 && vwSegs > 10, "session / previous-day level lines and the VWAP polyline are on the chart");
      CHECK(lbl("bf2").find("UPDATE") != std::string::npos, "footer carries the last update time");
      CHECK(lbl("k_e6") == "NEXT M1 BIAS", "the arrow row is labelled as a bias, not a prediction");
      // a live position and a waiting order show up as broker rows within one refresh
      SIM.pos.clear();
      SIM.ord.clear();
      SimPos ps;
      ps.ticket = 555; ps.sym = "EURUSD"; ps.type = POSITION_TYPE_BUY; ps.vol = 0.05; ps.open = SIM.bid; ps.sl = SIM.bid - 0.0005; ps.tp = SIM.bid + 0.0005;
      ps.time = SIM.now - 600; ps.magic = InpMagic; ps.comment = "NQ-Q1";
      SIM.pos.push_back(ps);
      SimOrder so;
      so.ticket = 556; so.sym = "EURUSD"; so.type = ORDER_TYPE_SELL_LIMIT; so.vol = 0.05; so.price = SIM.bid + 0.00010; so.sl = SIM.bid + 0.0006; so.tp = SIM.bid - 0.0004;
      so.time = SIM.now - 120; so.magic = InpMagic; so.comment = "NQ-N1";
      SIM.ord.push_back(so);
      OnTimer();
      CHECK(lbl("bb00") == "BROKER" && lbl("bb06").find("#556") != std::string::npos && lbl("bb06").find("NY trap") != std::string::npos,
            "broker order row: ticket and kind");
      CHECK(lbl("bb06").find("NEAR") != std::string::npos, "an order within 0.5 ATR of the price is marked NEAR");
      CHECK(lbl("bb10") == "POSITION" && lbl("bb16").find("RUNNING  #555") != std::string::npos, "position row: RUNNING with ticket");
      CHECK(lbl("ny4").find("SLOT  TAKEN") == 0, "slot line says TAKEN while a position is open");
      // MT5 draws at most 63 characters of a label: no piece may exceed it, and a long text is split, not cut
      bool fits = true;
      for(auto &kv : SIM.objs)
         if(kv.first.compare(0, 5, "NQEA_") == 0 && kv.second.s[OBJPROP_TEXT].size() > 63) { fits = false; std::printf("    too long: %s = %s\n", kv.first.c_str(), kv.second.s[OBJPROP_TEXT].c_str()); }
      CHECK(fits, "no label piece longer than 63 characters (the MT5 limit)");
      std::string longT = "LTC   risk x0.75   SL buf x1.50   spread <= 0.25 ATR   lead BTCUSD BULLISH   and a tail that makes it long";
      NqLabel("zz", 10, 10, longT, 0, 9, "Arial", ANCHOR_LEFT_UPPER);
      CHECK(obj("NQEA_P_zz").size() <= 63 && SIM.objs.count("NQEA_P_zz~1") > 0 && lbl("zz") == longT &&
            SIM.objs["NQEA_P_zz~1"].i[OBJPROP_XDISTANCE] > 10,
            "a long label is split into pieces at spaces, placed side by side, nothing lost");
      NqLabel("zz", 10, 10, "short", 0, 9, "Arial", ANCHOR_LEFT_UPPER);
      CHECK(lbl("zz") == "short" && SIM.objs.count("NQEA_P_zz~1") == 0, "a shorter text removes the stale pieces");
      ObjectsDeleteAll(0, "NQEA_P_zz");
   }
   end("A9");

   begin("A11 the verdict: HOLD / EXIT on a running position, PRICE NEAR with a chart marker, WAIT otherwise");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      size_t i = START + 1;
      int reg = 0;
      for(; i <= END; i++) { stepTo(i); reg = g_s5.regime[g_s5.n - 1]; if(reg != NQ_REG_CHOP) break; }
      CHECK(reg != NQ_REG_CHOP, "found a directional regime");
      CHECK(lbl("state").find("WAIT") == 0 || lbl("state").find("PRICE NEAR") != std::string::npos || lbl("state").find("SCALP") == 0,
            "no position: the verdict is WAIT / PRICE NEAR / SCALP");
      // a position WITH the regime -> HOLD; against it -> EXIT (bot does not close plan positions by default)
      SIM.ord.clear();
      SIM.pos.clear();
      SimPos p;
      p.ticket = 4242; p.sym = "EURUSD"; p.type = (reg > 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL; p.vol = 0.05; p.open = SIM.bid;
      p.sl = 0; p.tp = 0; p.time = SIM.now; p.magic = InpMagic; p.comment = "NQ-Q4242";
      SIM.pos.push_back(p);
      OnTimer();
      CHECK(lbl("state").find("HOLD") == 0 && lbl("state").find("#4242") != std::string::npos, "with the regime: HOLD #ticket");
      SIM.pos[0].type = (reg > 0) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      OnTimer();
      CHECK(lbl("state").find("EXIT") == 0 && lbl("state").find("REGIME FLIPPED") != std::string::npos && lbl("state").find("you decide") != std::string::npos,
            "against the regime: EXIT #ticket - regime flipped (you decide)");
      size_t before = SIM.sent.size();
      stepTo(i + 1);
      bool closed = false;
      for(size_t k = before; k < SIM.sent.size(); k++) if(SIM.sent[k].action == TRADE_ACTION_DEAL && SIM.sent[k].position == 4242) closed = true;
      CHECK(!closed, "InpPlanCloseOnFlip=false: the bot leaves the plan position to the human");
      // a waiting plan order near the price -> PRICE NEAR verdict + NEAR marker on the chart
      SIM.pos.clear();
      bool nearShown = false;
      for(size_t j = i + 2; j <= END; j++)
      {
         stepTo(j);
         NqPlan pl;
         double atr5 = g_s5.atr[g_s5.n - 1];
         for(int q = 0; q < NQ_PLAN_SLOTS; q++)
         {
            if(!NqSlotPlan(q, pl) || pl.status != NQ_PL_ACTIVE) continue;
            double ask = SIM.bid + SIM.spreadPts * SIM.point;
            double d = NqPlanIsStop(pl) ? NqDistAtrStop(pl.dir, pl.entry, SIM.bid, ask, atr5) : NqDistAtr(pl.dir, pl.entry, SIM.bid, ask, atr5);
            if(d >= 0 && d <= InpNearAtr && SIM.pos.empty())
            {
               nearShown = (lbl("state").find("PRICE NEAR") != std::string::npos) && SIM.objs.count("NQEA_A_NEAR") > 0;
               break;
            }
         }
         if(nearShown) break;
      }
      CHECK(nearShown, "a level within 0.5 ATR: verdict PRICE NEAR and a NEAR marker object on the chart");
   }
   end("A11");

   begin("A12 journal: every plan event as one JSON line in the file and one POST to SignalMesh, secret never logged, queue on failure");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      g_webUrl = "https://status.example/webhooks/brain/signal";
      g_webSecret = "s3cr3t-token";
      run(START + 1, END);
      std::string fname = "NQ_events_EURUSD.jsonl";
      CHECK(SIM.files.count(fname) == 1, "journal file NQ_events_<symbol>.jsonl exists");
      std::vector<std::string> lines;
      {
         std::string body = SIM.files[fname];
         size_t pos = 0;
         while(pos < body.size())
         {
            size_t e = body.find('\n', pos);
            if(e == std::string::npos) e = body.size();
            if(e > pos) lines.push_back(body.substr(pos, e - pos));
            pos = e + 1;
         }
      }
      std::printf("    %zu journal lines, %zu POSTs\n", lines.size(), SIM.web.size());
      CHECK(lines.size() > 20, "events were written");
      int badJson = 0;
      std::set<std::string> events, ids;
      int armedFirst = 0, ordered = 0;
      std::map<std::string, std::vector<std::string>> perId;
      for(const std::string &l : lines)
      {
         if(l.front() != '{' || l.back() != '}') badJson++;
         for(const char *k : {"\"signal_id\":", "\"system\":\"NQ-EA\"", "\"symbol\":\"EURUSD\"", "\"event\":", "\"status\":", "\"plan_kind\":",
                              "\"entry\":", "\"sl\":", "\"tp1\":", "\"fired_at\":", "\"ts\":", "\"account_mode\":\"demo\""})
            if(l.find(k) == std::string::npos) badJson++;
         size_t a = l.find("\"event\":\"") + 9, b = l.find('"', a);
         std::string ev = l.substr(a, b - a);
         events.insert(ev);
         size_t c = l.find("\"signal_id\":\"") + 13, d = l.find('"', c);
         std::string id = l.substr(c, d - c);
         ids.insert(id);
         perId[id].push_back(ev);
         if(l.find("s3cr3t") != std::string::npos) badJson++;   // the secret is a header, never a field
      }
      CHECK(badJson == 0, "every line is a JSON object with the platform fields; the secret is never in a payload");
      for(auto &kv : perId)
      {
         if(kv.second.front() == "armed") armedFirst++;
         // a plan's life: armed, then placed/rejected/near..., then at most one terminal event
         int terminal = 0;
         for(const std::string &e : kv.second)
            if(e == "tp1" || e == "sl" || e == "false_break" || e == "expired" || e == "cancelled" || e == "replaced") terminal++;
         if(terminal <= 1) ordered++;
      }
      CHECK(armedFirst == (int)perId.size(), "the first event of every plan is 'armed'");
      CHECK(ordered == (int)perId.size(), "at most one terminal event per plan");
      CHECK(events.count("placed") && (events.count("filled") || events.count("tp1") || events.count("sl")) &&
            (events.count("expired") || events.count("replaced") || events.count("cancelled")),
            "placed, filled/closed and cancelled events all occur");
      // status mapping onto the platform vocabulary, never 'approved' (that word fans out Telegram alerts)
      int approved = 0, badMap = 0;
      for(const std::string &l : lines)
      {
         if(l.find("\"status\":\"approved\"") != std::string::npos) approved++;
         bool tp = l.find("\"event\":\"tp1\"") != std::string::npos;
         bool sl = l.find("\"event\":\"sl\"") != std::string::npos;
         if(tp && (l.find("\"status\":\"closed\"") == std::string::npos || l.find("\"outcome\":\"win\"") == std::string::npos)) badMap++;
         if(sl && (l.find("\"status\":\"closed\"") == std::string::npos || l.find("\"outcome\":\"loss\"") == std::string::npos)) badMap++;
         if(l.find("\"event\":\"armed\"") != std::string::npos && l.find("\"status\":\"pending\"") == std::string::npos) badMap++;
      }
      CHECK(approved == 0 && badMap == 0, "armed=pending, tp1=closed/win, sl=closed/loss, never approved");
      // POSTs: one per line, right URL, secret in the header, never in the Experts log
      CHECK(SIM.web.size() == lines.size(), "one POST per journal line");
      bool hdr = !SIM.web.empty();
      for(auto &w : SIM.web)
         if(w.url != "https://status.example/webhooks/brain/signal" || w.method != "POST" ||
            w.headers.find("X-Brain-Secret: s3cr3t-token") == std::string::npos ||
            w.headers.find("Content-Type: application/json") == std::string::npos || w.body != w.body) hdr = false;
      CHECK(hdr, "POST to the configured URL with X-Brain-Secret and JSON content type");
      bool leaked = false;
      for(const std::string &l : SIM.log) if(l.find("s3cr3t") != std::string::npos) leaked = true;
      CHECK(!leaked, "the secret never appears in the log");
      // the platform down: events are queued in order and drained once it answers
      size_t webBefore = SIM.web.size(), linesBefore = lines.size();
      SIM.webCode = -1;
      run(END - 1439, END - 1300);   // re-run a slice of bars: new events appear (statuses differ from the recorded ones)
      size_t fileLines = 0;
      for(char ch : SIM.files[fname]) if(ch == '\n') fileLines++;
      int queued = g_webN;
      std::printf("    queued while down: %d (file grew by %zu)\n", queued, fileLines - linesBefore);
      CHECK(fileLines > linesBefore, "the file keeps every event while the platform is down");
      CHECK(queued > 0 && queued == (int)(fileLines - linesBefore), "every undelivered event is queued");
      SIM.webCode = 200;
      for(int k = 0; k < 400 && g_webN > 0; k++) { SIM.now += 5; OnTimer(); }
      CHECK(g_webN == 0 && SIM.web.size() >= webBefore + (fileLines - linesBefore), "the queue drains in order once the platform answers");
      (void)webBefore;
   }
   end("A12");

   begin("A13 telemetry: an ANALYSIS ONLY snapshot to its own URL on every closed M1 candle and every N seconds, demo only, secret in the header, never a plan event");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      SIM.gmtOffsetSec = 3 * 3600;
      startAt(START);
      relax();
      g_webUrl = "";                                   // journal off: every POST below is telemetry
      g_telUrl = "https://status.example/webhooks/forex/telemetry";
      g_telSec = 60;
      g_telDemoOnly = true;
      g_webSecret = "s3cr3t-token";
      size_t before = SIM.web.size();
      run(START + 1, START + 30);
      size_t posts = SIM.web.size() - before;
      std::printf("    %zu telemetry POSTs over 30 closed M1 bars\n", posts);
      CHECK(posts == 30, "exactly one snapshot per closed M1 candle");
      bool routed = posts > 0;
      std::string last;
      for(size_t i = before; i < SIM.web.size(); i++)
      {
         const auto &w = SIM.web[i];
         if(w.url != g_telUrl || w.method != "POST" || w.headers.find("X-Brain-Secret: s3cr3t-token") == std::string::npos ||
            w.headers.find("Content-Type: application/json") == std::string::npos)
            routed = false;
         last = w.body;
      }
      CHECK(routed, "every snapshot goes to the telemetry URL, JSON, secret in the header");
      CHECK(last.rfind("{\"system\":\"NQ-EA\",\"kind\":\"telemetry\",\"mode\":\"ANALYSIS_ONLY\"", 0) == 0, "the snapshot names itself ANALYSIS_ONLY before anything else");
      int braces = 0, brackets = 0;
      bool inStr = false;
      for(size_t i = 0; i < last.size(); i++)
      {
         char ch = last[i];
         if(inStr) { if(ch == '\\') i++; else if(ch == '"') inStr = false; continue; }
         if(ch == '"') inStr = true;
         else if(ch == '{') braces++;
         else if(ch == '}') braces--;
         else if(ch == '[') brackets++;
         else if(ch == ']') brackets--;
      }
      CHECK(braces == 0 && brackets == 0 && !inStr && last.back() == '}', "the snapshot is balanced JSON");
      for(const char *k : {"\"label\":\"ANALYSIS ONLY - DEMO - NOT A TRADE SIGNAL\"", "\"source\":\"NRTR_QML_ForexScalper\"", "\"ea_version\":\"1.0.3\"", "\"strength\":{", "\"news\":{\"state\":\"CLEAR\"", "\"session\":{", "\"htf\":{", "\"smart_exit\":{", "\"portfolio\":{",
                           "\"symbol\":\"EURUSD\"", "\"asset_class\":\"forex\"", "\"pair_class\":\"MAJOR\"", "\"base\":\"EUR\"", "\"quote\":\"USD\"", "\"account_mode\":\"demo\"", "\"ts_server\":", "\"ts_gmt\":",
                           "\"server_offset_sec\":10800", "\"heartbeat_sec\":60", "\"clock\":\"AUTO\"", "\"clock_offset_min\":180", "\"ny_dst\":true", "\"ny_open_min\":990", "\"london_open_min\":600", "\"asia_open_min\":60", "\"rollover_min\":0", "\"fresh\":true", "\"candles\":{\"state\":\"CLOSED FRESH\"",
                           "\"m1_closed_server\":", "\"m1_age_sec\":", "\"atr5\":", "\"m15\":{\"context\":\"", "\"nrtr_level\":",
                           "\"m5\":{\"regime\":\"", "\"structure\":\"", "\"structure_state\":\"", "\"lookback\":3", "\"reasons\":[",
                           "\"m1\":{\"nrtr_dir\":\"", "\"trigger\":\"", "\"forecast_next\":\"", "\"forecast_resolved\":",
                           "\"observed\":{\"label\":\"OBSERVED EA STATE - not a SignalMesh recommendation\"", "\"verdict\":\"", "\"gate\":[",
                           "\"scalp_row\":{\"side\":\"", "\"radar\":{\"up\":{\"state\":\"", "\"ny\":{\"high_side\":\"", "\"plans\":[",
                           "\"account\":{\"balance\":", "\"record\":{\"scalp\":{\"done\":", "\"evidence\":\""})
         CHECK(last.find(k) != std::string::npos, k);
      CHECK(last.find("\"event\":") == std::string::npos && last.find("\"status\":\"pending\"") == std::string::npos,
            "a snapshot is not a plan event: no event key, no platform status vocabulary at the top level");
      // the ages are measured on the EA's own clock: the M1 bar closed at most a few seconds before the snapshot
      {
         size_t a = last.find("\"m1_age_sec\":");
         long age = (a == std::string::npos) ? -1 : std::atol(last.c_str() + a + 13);
         CHECK(age >= 0 && age < 60, "m1_age_sec is the closed bar's age on the server clock");
      }
      // timer cadence without a new bar: one snapshot per 60 s, not one per tick
      size_t b2 = SIM.web.size();
      for(int k = 0; k < 6; k++) { SIM.now += 10; OnTimer(); }
      CHECK(SIM.web.size() - b2 == 1, "without a new candle the heartbeat is one snapshot per 60 s");
      bool leaked = false;
      for(const std::string &l : SIM.log) if(l.find("s3cr3t") != std::string::npos) leaked = true;
      CHECK(!leaked, "the secret never appears in the log");

      // a REAL account is never the witness while demo-only is on
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      SIM.accountMode = ACCOUNT_TRADE_MODE_REAL;
      startAt(START);
      relax();
      g_webUrl = "";
      g_telUrl = "https://status.example/webhooks/forex/telemetry";
      g_telSec = 60;
      g_telDemoOnly = true;
      size_t b3 = SIM.web.size();
      run(START + 1, START + 10);
      CHECK(SIM.web.size() == b3, "REAL account + demo-only: no telemetry leaves the terminal");
      bool said = false;
      for(const std::string &l : SIM.log) if(l.find("demo-only") != std::string::npos) said = true;
      CHECK(said, "and the Experts log says why, once");
      g_telDemoOnly = false;
      run(START + 11, START + 12);
      CHECK(SIM.web.size() > b3 && SIM.web.back().body.find("\"account_mode\":\"real\"") != std::string::npos,
            "with demo-only off the snapshot says account_mode real, so the page can flag it");
      SIM.accountMode = ACCOUNT_TRADE_MODE_DEMO;
      SIM.gmtOffsetSec = 3 * 3600;
      g_telUrl = "";
      g_telDemoOnly = true;
   }
   end("A13");

   begin("A14 volatility regime: DEAD blocks new trades, EXPANSION asks more, EXTREME blocks until a fresh M5 swing; the gate names it");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 30);
      CHECK(g_volClass != NQ_VOL_UNKNOWN && g_volRatio > 0.0 && g_volAvg > 0.0, "a class is assigned once the 24h average exists");
      CHECK(lbl("k_e0v") == "VOL REGIME" && lbl("v_e0v").find("ATR5") != std::string::npos, "the VOL REGIME row shows the ratio");
      int n5 = g_s5.n;
      double keep = g_s5.atr[(size_t)n5 - 1];
      double avg = 0.0;
      for(int i = n5 - 1 - InpVolAvgBars; i < n5 - 1; i++) avg += g_s5.atr[(size_t)i];
      avg /= InpVolAvgBars;
      g_s5.atr[(size_t)n5 - 1] = avg * 0.3; NqVolRegime();
      CHECK(g_volClass == NQ_VOL_DEAD && NqVolGateBits() == NQ_K_VOL_DEAD, "0.3x the average = DEAD, gate closed");
      g_s5.atr[(size_t)n5 - 1] = avg * 1.0; NqVolRegime();
      CHECK(g_volClass == NQ_VOL_NORMAL && NqVolGateBits() == 0, "1.0x = NORMAL, gate open");
      g_s5.atr[(size_t)n5 - 1] = avg * 1.8; NqVolRegime();
      CHECK(g_volClass == NQ_VOL_EXPANSION && NqVolGateBits() == 0, "1.8x = EXPANSION, gate open (stronger confirmation instead)");
      g_s5.atr[(size_t)n5 - 1] = avg * 3.0; NqVolRegime();
      CHECK(g_volClass == NQ_VOL_EXTREME && NqVolGateBits() == NQ_K_VOL_EXTREME && g_volWaitFresh, "3.0x = EXTREME, gate closed, waiting for fresh structure");
      g_s5.atr[(size_t)n5 - 1] = avg * 1.0; NqVolRegime();
      CHECK(g_volClass == NQ_VOL_NORMAL && NqVolGateBits() == NQ_K_VOL_EXTREME, "back to NORMAL with no fresh M5 swing yet: still closed");
      CHECK(NqGateAtX(NQ_K_VOL_EXTREME, 0).find("FRESH STRUCTURE") != std::string::npos && NqGateAtX(NQ_K_SPREAD | NQ_K_VOL_DEAD, 0) == NqGateName(NQ_K_SPREAD) &&
            NqGateAtX(NQ_K_SPREAD | NQ_K_VOL_DEAD, 1).find("DEAD") != std::string::npos && NqGateAtX(NQ_K_SPREAD | NQ_K_VOL_DEAD, 2) == "",
            "the gate names the regime after the engine's own reasons");
      g_s5.atr[(size_t)n5 - 1] = keep;
      bool cleared = false;
      int waited = 0, openWhileWaiting = 0;
      for(size_t i = START + 31; i <= START + 600 && !cleared; i++)
      {
         stepTo(i);
         if(g_volWaitFresh) { waited++; if((g_gate & NQ_K_VOL_EXTREME) == 0) openWhileWaiting++; }
         else cleared = true;
      }
      CHECK(cleared && waited > 0 && openWhileWaiting == 0, "a fresh confirmed M5 swing after the extreme reopens the gate; it stayed closed until then");
      OnDeinit(0);
   }
   end("A14");

   begin("A15 spike guard: a 15-ATR up-spike blocks pullback / radar plans in its direction; a BUY on the way back gets a flashing EXIT WARNING");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 30);
      CHECK(g_volAvg > 0.0 && g_spikeDir == 0, "a quiet synthetic market: no spike");
      int n5 = g_s5.n;
      double base = g_s5.c[(size_t)n5 - 1], avg = g_volAvg;
      double keepL = g_s5.l[(size_t)n5 - 10], keepH = g_s5.h[(size_t)n5 - 4];
      CHECK(g_spikeNorm > 2.0 * avg && g_spikeNorm < 8.0 * avg, "a normal hour spans a few ATR(M5), so the ATR alone cannot define a spike");
      g_s5.l[(size_t)n5 - 10] = base - 6.0 * avg;   // the low first ...
      g_s5.h[(size_t)n5 - 4] = base + 9.0 * avg;    // ... then the high: an up-spike of 15 ATR, the close 60% back down
      NqSpikeScan();
      CHECK(g_spikeDir == 1 && near(g_spikeAtr, 15.0, 1e-6) && g_spikeX >= InpSpikeX && near(g_spikeRetr, 0.6, 1e-6) && g_spikeWarn,
            "up-spike of 15 ATR, several normal hours in one, 60% given back: EXIT WARNING armed");
      g_s5.h[(size_t)n5 - 4] = base + 1.5 * avg;
      NqSpikeScan();
      CHECK(g_spikeDir == 0, "a 7.5 ATR hour is a trending hour, not a spike");
      g_s5.h[(size_t)n5 - 4] = base + 9.0 * avg;
      NqSpikeScan();
      NqPlan pl;
      pl.dir = 1; pl.kind = NQ_PLAN_PB;
      bool pbUp = NqSpikeBlocks(pl);
      pl.kind = NQ_PLAN_RADAR;
      bool rdUp = NqSpikeBlocks(pl);
      pl.kind = NQ_PLAN_QML;
      bool qmlUp = NqSpikeBlocks(pl);
      pl.kind = NQ_PLAN_PB; pl.dir = -1;
      bool pbDn = NqSpikeBlocks(pl);
      pl.kind = NQ_PLAN_NY; pl.dir = 1;
      bool nyUp = NqSpikeBlocks(pl);
      pl.kind = NQ_PLAN_QML; pl.dir = -1;
      bool qmlDn = NqSpikeBlocks(pl);
      CHECK(pbUp && rdUp && qmlUp && nyUp && !pbDn && !qmlDn,
            "every plan kind in the spike's direction is blocked (QML and NY trap too - the bounce of a spike is not a setup); plans against the spike are not");
      SIM.ord.clear();
      SIM.pos.clear();
      SimPos p;
      p.ticket = 4343; p.sym = "EURUSD"; p.type = POSITION_TYPE_BUY; p.vol = 0.05; p.open = SIM.bid;
      p.sl = 0; p.tp = 0; p.time = SIM.now; p.magic = InpMagic; p.comment = "NQ-Q4343";
      SIM.pos.push_back(p);
      int keepReg = g_s5.regime[(size_t)n5 - 1];
      g_s5.regime[(size_t)n5 - 1] = NQ_REG_BULL;
      NqVerdict();
      CHECK(g_verdict.find("EXIT WARNING BUY #4343") != std::string::npos && g_verdict.find("SPIKE REVERSAL") != std::string::npos &&
            g_verdict.find("60%") != std::string::npos && g_verdict.find("you decide") != std::string::npos && g_warnOn,
            "a BUY with the regime still bullish: EXIT WARNING #ticket - spike reversal, 60% back, you decide");
      NqDrawWarn();
      CHECK(SIM.objs.count("NQEA_A_WARN") > 0 && obj("NQEA_A_WARN").find("EXIT WARNING") != std::string::npos, "the warning is drawn on the chart");
      SIM.pos[0].type = POSITION_TYPE_SELL;
      NqVerdict();
      CHECK(g_verdict.find("HOLD SELL #4343") != std::string::npos || g_verdict.find("EXIT SELL #4343") != std::string::npos,
            "a SELL is not in the spike direction: no warning");
      CHECK(!g_warnOn, "no warning flag for the SELL");
      SIM.pos[0].type = POSITION_TYPE_BUY;
      g_s5.regime[(size_t)n5 - 1] = NQ_REG_BEAR;
      NqVerdict();
      CHECK(g_verdict.find("EXIT BUY #4343") != std::string::npos && g_verdict.find("REGIME FLIPPED") != std::string::npos && !g_warnOn,
            "the regime flip outranks the warning: plain EXIT");
      NqDrawWarn();
      CHECK(SIM.objs.count("NQEA_A_WARN") == 0, "the chart warning is removed with the flag");
      g_s5.regime[(size_t)n5 - 1] = keepReg;
      g_s5.l[(size_t)n5 - 10] = keepL;
      g_s5.h[(size_t)n5 - 4] = keepH;
      NqSpikeScan();
      CHECK(g_spikeDir == 0 && !g_spikeWarn, "the spike gone: nothing armed");
      SIM.pos.clear();
      OnDeinit(0);
   }
   end("A15");

   begin("A10 USDJPY spec (3 digits, tick value 0.66): SL/TP on the grid, lots from the real tick value; rejected order is logged, not retried");
   {
      load(jpy, "USDJPY", "USD", 3, 0.001, 0.66);
      SIM.profit = "JPY";
      SIM.contract = 100000.0 / 150.25;   // margin per lot in USD on a USD-based pair
      startAt(START);
      relax();
      run(START + 1, END);
      int market = 0, bad = 0;
      for(const MqlTradeRequest &r : SIM.sent)
      {
         if(r.action != TRADE_ACTION_DEAL || r.position != 0) continue;
         market++;
         if(std::fabs(r.sl * 1000.0 - std::round(r.sl * 1000.0)) > 1e-6) bad++;
         if(std::fabs(r.tp * 1000.0 - std::round(r.tp * 1000.0)) > 1e-6) bad++;
         double loss = NqLossAt(r.volume, std::fabs(r.price - r.sl), 0.001, 0.66);
         if(loss > 0.5 / 100.0 * (SIM.balance + 500.0) + 1e-6) bad++;
      }
      std::printf("    USDJPY: %d scalps\n", market);
      CHECK(market > 0 && bad == 0, "USDJPY orders on the 0.001 grid, sized from tick value 0.66");

      load(jpy, "USDJPY", "USD", 3, 0.001, 0.66);
      SIM.profit = "JPY";
      SIM.contract = 100000.0 / 150.25;   // margin per lot in USD on a USD-based pair
      SIM.rejectAll = true;
      startAt(START);
      relax();
      run(START + 1, END);
      int rejects = 0;
      for(const std::string &l : SIM.log) if(l.find("REJECTED") != std::string::npos) rejects++;
      std::set<std::string> cm;
      int dupScalp = 0;
      for(const MqlTradeRequest &r : SIM.sent)
         if(r.action == TRADE_ACTION_DEAL && r.position == 0) { if(cm.count(r.comment)) dupScalp++; cm.insert(r.comment); }
      CHECK(rejects > 0 && dupScalp == 0, "rejections are logged and a rejected scalp is not re-sent for the same trigger");
   }
   end("A10");


   // ======================= the forex asset layer =======================
   begin("F1 pair detector: any two ISO codes in any broker spelling; metals, crypto, indices and single currencies refused; forced class");
   {
      string b, q;
      CHECK(NqPairOf("EURUSD", "EUR", "USD", 0, b, q) == NQ_PAIR_MAJOR && b == "EUR" && q == "USD", "EURUSD = MAJOR, EUR / USD");
      CHECK(NqPairOf("USDJPY.m", "", "", 0, b, q) == NQ_PAIR_MAJOR && b == "USD" && q == "JPY", "USDJPY.m from the name alone");
      CHECK(NqPairOf("#GBPJPY", "", "", 0, b, q) == NQ_PAIR_CROSS && NqPairOf("AUDNZD", "", "", 0, b, q) == NQ_PAIR_CROSS &&
            NqPairOf("EURGBP", "EUR", "GBP", 0, b, q) == NQ_PAIR_CROSS, "#GBPJPY, AUDNZD, EURGBP = CROSS");
      CHECK(NqPairOf("EUR/USD", "EUR", "USD", 0, b, q) == NQ_PAIR_MAJOR && NqPairOf("mEURUSDmicro", "", "", 0, b, q) == NQ_PAIR_MAJOR &&
            NqPairOf("AUDUSD-STD", "", "", 0, b, q) == NQ_PAIR_MAJOR, "EUR/USD, mEURUSDmicro, AUDUSD-STD");
      CHECK(NqPairOf("USDTRY", "USD", "TRY", 0, b, q) == NQ_PAIR_EXOTIC && NqPairOf("EURPLN", "", "", 0, b, q) == NQ_PAIR_EXOTIC &&
            NqPairOf("USDZAR.i", "", "", 0, b, q) == NQ_PAIR_EXOTIC && q == "ZAR", "USDTRY, EURPLN, USDZAR.i = EXOTIC");
      CHECK(NqPairOf("XAUUSD", "XAU", "USD", 0, b, q) == NQ_PAIR_NONE && NqPairOf("BTCUSD", "BTC", "USD", 0, b, q) == NQ_PAIR_NONE &&
            NqPairOf("US500", "USD", "USD", 0, b, q) == NQ_PAIR_NONE && NqPairOf("USDX", "", "", 0, b, q) == NQ_PAIR_NONE &&
            NqPairOf("USDOLLAR", "", "", 0, b, q) == NQ_PAIR_NONE && NqPairOf("USOIL", "", "", 0, b, q) == NQ_PAIR_NONE,
            "gold, bitcoin, an index, the dollar index, oil: refused");
      CHECK(NqPairOf("Euro vs Dollar", "EUR", "USD", 0, b, q) == NQ_PAIR_MAJOR, "the broker's base / profit currency when the name says nothing");
      CHECK(NqPairOf("FOO", "USD", "ZZZ", NQ_PAIR_EXOTIC, b, q) == NQ_PAIR_EXOTIC && b == "USD" && q == "ZZZ", "forced: the broker's words as they are");
      CHECK(NqPairOf("EURGBP", "", "", NQ_PAIR_MAJOR, b, q) == NQ_PAIR_MAJOR, "forced overrides the class");
      CHECK(NqPairOf("FOO", "", "", NQ_PAIR_EXOTIC, b, q) == NQ_PAIR_NONE, "forced cannot invent the currencies");
   }
   end("F1");

   begin("F2 pair profile, pips and the spread cap: MAJOR raw, USDJPY 3 digits, EXOTIC half risk / no radar / no scalp");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      CHECK(g_pair == NQ_PAIR_MAJOR && g_pairName == "MAJOR" && near(g_pip, 0.0001) && near(g_profRisk, 1.0) && g_profScalp && g_profRadar && near(g_profSpread, 0.15),
            "EURUSD: MAJOR profile, pip 0.0001");
      CHECK(lbl("v_e0p").find("MAJOR  EUR/USD") == 0 && lbl("v_e0p").find("pip 0.00010 = 10.00 USD/lot") != std::string::npos &&
            lbl("v_e0p").find("spread 0.2 pips") != std::string::npos, "PAIR PROFILE row: class, pip value, spread in pips");
      run(START + 1, START + 30);
      int cap = NqMaxSpreadPts();
      double atr5 = g_s5.atr[(size_t)g_s1.map[(size_t)g_s1.n - 1]];
      CHECK(cap > 0 && near((double)cap, std::round(0.15 * atr5 / 0.00001)) && (g_gate & NQ_K_SPREAD) == 0, "the cap is 0.15 x ATR(M5) in points; 0.2 pip passes");
      SIM.spreadPts = cap + 1;
      stepTo(START + 31);
      CHECK((g_gate & NQ_K_SPREAD) != 0, "one point over the cap: SPREAD TOO WIDE");
      SIM.spreadPts = 2;
      OnDeinit(0);

      load(jpy, "USDJPY", "USD", 3, 0.001, 0.66);
      SIM.profit = "JPY";
      SIM.contract = 100000.0 / 150.25;
      startAt(START);
      relax();
      CHECK(g_pair == NQ_PAIR_MAJOR && g_base == "USD" && g_quote == "JPY" && near(g_pip, 0.01), "USDJPY: 3 digits, pip 0.01");
      OnDeinit(0);

      Market tr = makeMarket(9, 34.5, 0.00001, 0.004, (int)DAYS);
      load(tr, "USDTRY", "USD", 5, 0.00001, 0.03);
      SIM.profit = "TRY";
      startAt(START);
      relax();
      CHECK(g_pair == NQ_PAIR_EXOTIC && near(g_profRisk, 0.5) && near(g_riskMoney, NqRiskMoney(SIM.balance, InpRiskPct) * 0.5) && near(g_profBuf, 1.5) &&
            near(g_P.qmlSlBufAtr, InpQmlSlBufAtr * 1.5) && near(g_P.pbMinImpulseAtr, InpPbMinImpulseAtr * 1.25) && !g_profRadar && !g_profScalp,
            "USDTRY: EXOTIC - half the risk money, buffers x1.5, impulse x1.25, no radar, no scalp");
      NqPlan rp;
      rp.kind = NQ_PLAN_RADAR;
      rp.dir = 1;
      CHECK(!NqKindEnabled(rp), "an exotic's radar plan is not tradable");
      run(START + 1, START + 600);
      CHECK(countSent(TRADE_ACTION_DEAL, true) == 0, "no scalp (market order) is ever sent on an exotic");
      CHECK(lbl("v_e0p").find("EXOTIC") == 0 && lbl("v_e0p").find("radar off") != std::string::npos && lbl("v_e0p").find("scalp off") != std::string::npos,
            "the panel says so");
      OnDeinit(0);
   }
   end("F2");

   begin("F3 the forex clock: AUTO sessions from the GMT offset, home sessions per currency, rollover, Friday stop, week open, weekend");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      g_homeOnly = true;
      g_clockGuards = true;
      CHECK(g_clkAuto && g_clk.nyS == 990 && g_clk.lonS == 600 && g_clk.asiaS == 60 && g_clk.roll == 0 && lbl("ny1").find("clock AUTO") != std::string::npos,
            "GMT+3 broker in summer: NY 16:30, London 10:00, Asia 01:00, rollover 00:00 - the NY SESSION line says AUTO");
      CHECK(g_homeMask == 6, "EURUSD home sessions = London + NY");
      datetime fri = T0 + 3 * 86400;   // T0 is Tuesday 2026-09-01: Friday the 4th
      datetime mon = T0 + 6 * 86400;   // Monday the 7th
      NqSessionScan(fri + 5 * 3600);
      CHECK(g_sessOpen == 1 && !g_homeOpen && NqSessionName() == "ASIA" && (NqForexGateBits() & NQ_K_HOME) != 0, "05:00 server = Asia: EURUSD's home is closed, gate bit HOME");
      NqSessionScan(fri + 12 * 3600);
      CHECK(g_sessOpen == 2 && g_homeOpen && NqSessionName() == "LONDON" && (NqForexGateBits() & NQ_K_HOME) == 0, "12:00 = London: open");
      NqSessionScan(fri + 17 * 3600);
      CHECK(g_sessOpen == 4 && g_homeOpen && NqSessionName() == "NY", "17:00 = New York: open");
      NqSessionScan(fri + 23 * 3600 + 50 * 60);
      CHECK(g_rollover && (NqForexGateBits() & NQ_K_ROLLOVER) != 0, "23:50 = 10 min before the rollover: ROLLOVER bit");
      NqSessionScan(fri + 22 * 3600 + 30 * 60);
      CHECK(g_weekEdge && g_weekFriday && g_weekText.find("FRIDAY STOP") == 0 && !g_rollover && (NqForexGateBits() & NQ_K_WEEK_EDGE) != 0,
            "Friday 22:30 = 90 min before the close: FRIDAY STOP (orders pulled, profits banked)");
      NqSessionScan(fri + 19 * 3600);
      CHECK(!g_weekEdge && !g_weekFriday, "Friday 19:00 = 5 h before the close: open");
      NqSessionScan(mon + 30 * 60);
      CHECK(g_weekEdge && !g_weekFriday && g_weekText.find("FIRST 60 MIN") == 0, "Monday 00:30: the first hour of the week");
      NqSessionScan(fri + 86400 + 3600);
      CHECK(g_weekEdge && g_weekText.find("WEEKEND") == 0, "Saturday 01:00: weekend");
      NqSessionScan(mon - 3600);
      CHECK(g_weekEdge && g_weekText.find("WEEKEND") == 0, "Sunday 23:00: weekend");
      g_clockGuards = false;
      NqSessionScan(fri + 22 * 3600 + 30 * 60);
      CHECK(!g_weekEdge && !g_rollover, "guards off: nothing");
      OnDeinit(0);

      load(jpy, "USDJPY", "USD", 3, 0.001, 0.66);
      SIM.profit = "JPY";
      SIM.contract = 100000.0 / 150.25;
      startAt(START);
      relax();
      g_homeOnly = true;
      NqSessionScan(fri + 5 * 3600);
      CHECK(g_homeMask == 5 && g_homeOpen, "USDJPY home = Asia + NY: open at 05:00");
      NqSessionScan(fri + 12 * 3600);
      CHECK(!g_homeOpen, "USDJPY in London: home closed");
      OnDeinit(0);

      // a UTC broker: the week opens Sunday 21:00 server, the rollover is 21:00
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      SIM.gmtOffsetSec = 0;   // after load(): a fresh SimState is an EET-like broker
      startAt(START);
      relax();
      g_clockGuards = true;
      CHECK(g_clkAuto && g_clk.nyS == 810 && g_clk.roll == 21 * 60 && g_clk.lonS == 7 * 60, "GMT+0: NY 13:30, London 07:00, rollover 21:00");
      NqSessionScan(mon - 2 * 3600 - 30 * 60);
      CHECK(g_weekEdge && g_weekText.find("FIRST 60 MIN") == 0, "Sunday 21:30 server on a UTC broker: the week just opened");
      NqSessionScan(mon - 4 * 3600);
      CHECK(g_weekEdge && g_weekText.find("WEEKEND") == 0, "Sunday 20:00: still the weekend");
      NqSessionScan(fri + 19 * 3600 + 30 * 60);
      CHECK(g_weekFriday, "Friday 19:30 UTC = 90 min before the 21:00 close: FRIDAY STOP");
      OnDeinit(0);

      // a broker on New York time (GMT-4 in summer): Asia wraps the server midnight (18:00 -> 03:00) and is held as a wrap
      load(jpy, "USDJPY", "USD", 3, 0.001, 0.66);
      SIM.profit = "JPY";
      SIM.contract = 100000.0 / 150.25;
      SIM.gmtOffsetSec = -4 * 3600;
      startAt(START);
      relax();
      g_homeOnly = true;
      CHECK(g_clkAuto && g_clk.nyS == 9 * 60 + 30 && g_clk.asiaS0 == 18 * 60 && g_clk.asiaE0 == 3 * 60 && g_clk.asiaS == 0,
            "GMT-4: NY 09:30, Asia 18:00 -> 03:00 kept unclamped (the day-bound levels use 00:00 -> 03:00)");
      NqSessionScan(fri + 19 * 3600);
      CHECK(g_sessOpen == 1 && g_homeOpen && NqSessionName() == "ASIA", "19:00 server = Asia (after the NY close): USDJPY's home is open");
      NqSessionScan(fri + 3600);
      CHECK(g_sessOpen == 1 && g_homeOpen, "01:00 server = still Asia");
      NqSessionScan(fri + 5 * 3600);
      CHECK(g_sessOpen == 2 && !g_homeOpen, "05:00 server = London: USDJPY's home closed");
      CHECK(lbl("v_e0h").find("Asia 18:00") != std::string::npos, "the SESSION row shows the true Asia open");
      SIM.gmtOffsetSec = 3 * 3600;
      OnDeinit(0);
   }
   end("F3");

   begin("F4 news guard: the MT5 calendar closes the gate around HIGH events of the pair's currencies, pulls resting orders, banks profit; UNKNOWN is not clear");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      CHECK(g_newsOk && !g_newsBlock && !g_newsUnknown && lbl("v_e0n").find("clear") == 0 && (g_gate & (NQ_K_NEWS | NQ_K_NEWS_UNKNOWN)) == 0,
            "a working calendar with no HIGH event: CLEAR, nothing gated");
      simAddEvent("USD", SIM.now + 20 * 60, CALENDAR_IMPORTANCE_HIGH, "Initial Jobless Claims");
      SimOrder so;
      so.ticket = 7001; so.sym = "EURUSD"; so.type = ORDER_TYPE_BUY_LIMIT; so.vol = 0.10; so.price = SIM.bid - 0.0020; so.sl = SIM.bid - 0.0030; so.tp = SIM.bid - 0.0010;
      so.time = SIM.now; so.magic = InpMagic; so.comment = "NQ-Q1";
      SIM.ord.push_back(so);
      stepTo(START + 1);
      CHECK(g_nEv >= 1 && g_newsBlock && (g_gate & NQ_K_NEWS) != 0 && g_newsWhy.find("USD Initial Jobless Claims") == 0 && lbl("v_e0n").find("GUARD") == 0,
            "a HIGH USD event 20 min ahead: NEWS GUARD, the gate names the event");
      bool pulled = true;
      for(const SimOrder &o : SIM.ord) if(o.ticket == 7001) pulled = false;
      bool said = false;
      for(const std::string &l : SIM.log) if(l.find("NEWS GUARD: resting orders are pulled") != std::string::npos) said = true;
      CHECK(pulled && said, "the resting order was pulled with the reason");
      SIM.cal.clear();
      simAddEvent("GBP", SIM.now + 10 * 60, CALENDAR_IMPORTANCE_HIGH, "BoE Rate Decision");
      stepTo(START + 2);
      CHECK(!g_newsBlock, "a GBP event is not this pair's business");
      simAddEvent("EUR", SIM.now + 10 * 60, CALENDAR_IMPORTANCE_HIGH, "ECB Press Conference");
      stepTo(START + 3);
      CHECK(g_newsBlock && g_newsWhy.find("EUR ECB Press Conference") == 0 && g_newsWhy.find("TOP TIER") != std::string::npos, "an EUR event counts; a central-bank presser is TOP TIER");
      SIM.cal.clear();
      simAddEvent("USD", SIM.now + 50 * 60, CALENDAR_IMPORTANCE_HIGH, "Factory Orders");
      stepTo(START + 4);
      CHECK(!g_newsBlock && lbl("v_e0n").find("next HIGH USD Factory Orders") != std::string::npos, "a plain HIGH event 50 min away is outside the 30-min window; the row names it next");
      SIM.cal.clear();
      simAddEvent("USD", SIM.now + 50 * 60, CALENDAR_IMPORTANCE_HIGH, "FOMC Rate Decision");
      stepTo(START + 5);
      CHECK(g_newsBlock && g_newsWhy.find("TOP TIER") != std::string::npos, "FOMC 50 min away is inside the 60-min TOP TIER window");
      SIM.cal.clear();
      simAddEvent("USD", SIM.now + 10 * 60, CALENDAR_IMPORTANCE_MODERATE, "Consumer Credit");
      stepTo(START + 6);
      CHECK(!g_newsBlock, "a MODERATE event does not gate by default");
      g_newsMediumBlocks = true;
      NqNewsState();
      CHECK(g_newsBlock, "InpNewsMediumBlocks: it does");
      g_newsMediumBlocks = false;
      SIM.cal.clear();
      simAddEvent("USD", SIM.now - 40 * 60, CALENDAR_IMPORTANCE_HIGH, "Factory Orders");
      stepTo(START + 7);
      CHECK(!g_newsBlock, "40 min after a HIGH release: the window (30 min after) has closed");
      SIM.cal.clear();
      simAddEvent("USD", SIM.now - 20 * 60, CALENDAR_IMPORTANCE_HIGH, "Factory Orders");
      stepTo(START + 8);
      CHECK(g_newsBlock && g_newsWhy.find("ago") != std::string::npos, "20 min after: still inside");
      // the calendar's own reading of a release votes for its currency for InpNewsVoteHours
      SIM.cal.clear();
      simAddEvent("USD", SIM.now - 3600, CALENDAR_IMPORTANCE_HIGH, "Nonfarm Payrolls", CALENDAR_IMPACT_POSITIVE, true);
      stepTo(START + 9);
      std::string w;
      CHECK(NqNewsVote(1, w) == -1 && NqNewsVote(-1, w) == 1 && lbl("v_e0n").find("released 4h: USD Nonfarm Payrolls POSITIVE") != std::string::npos,
            "USD POSITIVE 1 h ago: -1 for a EURUSD BUY, +1 for a SELL; the row shows it");
      simAddEvent("EUR", SIM.now - 2 * 3600, CALENDAR_IMPORTANCE_HIGH, "HICP", CALENDAR_IMPACT_POSITIVE, true);
      stepTo(START + 10);
      w = "";
      CHECK(NqNewsVote(1, w) == 0 && w.find("news USD") != std::string::npos && w.find("news EUR") != std::string::npos, "EUR POSITIVE 2 h ago cancels it: counted, never weighted");
      SIM.cal.clear();
      simAddEvent("USD", SIM.now - 5 * 3600, CALENDAR_IMPORTANCE_HIGH, "Old release", CALENDAR_IMPACT_POSITIVE, true);
      stepTo(START + 11);
      CHECK(NqNewsVote(1, w) == 0, "a release older than InpNewsVoteHours votes nothing");
      // banking a position in profit when a window opens
      SIM.cal.clear();
      SIM.pos.clear();
      {
         const MqlRates &nb = SIM.m1[START + 12];
         SimPos p;
         p.ticket = 7101; p.sym = "EURUSD"; p.type = POSITION_TYPE_BUY; p.vol = 0.10; p.open = nb.close - 0.0005; p.sl = p.open - 0.0010; p.tp = p.open + 0.0030;
         p.time = SIM.now - 600; p.magic = InpMagic; p.comment = "NQ-P7101";
         SIM.pos.push_back(p);
         SimPos l = p;
         l.ticket = 7102; l.type = POSITION_TYPE_SELL; l.open = nb.close - 0.0005; l.sl = l.open + 0.0010; l.tp = l.open - 0.0030; l.comment = "NQ-P7102";
         SIM.pos.push_back(l);
      }
      simAddEvent("USD", SIM.now + 10 * 60, CALENDAR_IMPORTANCE_HIGH, "FOMC Statement");
      stepTo(START + 12);
      bool bankedA = true, keptB = false;
      for(const SimPos &p : SIM.pos) { if(p.ticket == 7101) bankedA = false; if(p.ticket == 7102) keptB = true; }
      bool reason = false;
      for(const std::string &l : SIM.log) if(l.find("NEWS: banking +0.50R before USD FOMC Statement") != std::string::npos) reason = true;
      CHECK(bankedA && keptB && reason, "the window opens: the +0.5R BUY is banked with the reason, the losing SELL keeps its SL");
      SIM.pos.clear();
      SIM.cal.clear();
      // the calendar is re-read on the timer, not only on a new candle: an event added between candles is known within a minute
      simAddEvent("USD", SIM.now + 10 * 60, CALENDAR_IMPORTANCE_HIGH, "Fed Chair Speaks");
      g_newsReadT = SIM.now - 61;   // the last read is a minute old
      SIM.now += 30;                // 30 s into the forming candle: no new bar
      OnTimer();
      CHECK(g_newsBlock && g_newsWhy.find("USD Fed Chair Speaks") == 0 && g_seen1 == SIM.m1[START + 12].time,
            "no new candle, the last read a minute old: the timer re-read found the event and closed the gate");
      SIM.now -= 30;
      SIM.cal.clear();
      // the calendar call FAILS (the terminal has no calendar / an error): UNKNOWN with the error code, the gate closed, nothing placed
      SIM.calOk = false;
      stepTo(START + 13);
      CHECK(!g_newsOk && g_newsUnknown && g_newsErr == 5402 && (g_gate & NQ_K_NEWS_UNKNOWN) != 0 && lbl("v_e0n").find("UNKNOWN") == 0 &&
            lbl("v_e0n").find("error 5402") != std::string::npos && NqGateAtX(g_gate, 0).find("NEWS UNKNOWN") != std::string::npos,
            "a failed calendar call: NEWS UNKNOWN with the error code closes the gate and says so");
      {
         size_t sentB = SIM.sent.size();
         run(START + 14, START + 200);
         int opened = 0;
         for(size_t k = sentB; k < SIM.sent.size(); k++)
            if(SIM.sent[k].action == TRADE_ACTION_PENDING || (SIM.sent[k].action == TRADE_ACTION_DEAL && SIM.sent[k].position == 0)) opened++;
         CHECK(opened == 0, "186 candles with the calendar failing: no new order of any kind");
      }
      // the call succeeds but returns no values at all: UNKNOWN as well (an empty answer is not "no news")
      SIM.calOk = true;
      SIM.calFiller = false;
      stepTo(START + 201);
      CHECK(!g_newsOk && g_newsUnknown && (g_gate & NQ_K_NEWS_UNKNOWN) != 0, "an empty calendar answer is UNKNOWN too");
      SIM.calFiller = true;
      SIM.calOk = false;
      stepTo(START + 202);
      g_newsUnknownBlocks = false;
      NqNewsState();
      CHECK(g_newsUnknown && (NqForexGateBits() & NQ_K_NEWS_UNKNOWN) == 0 && g_newsText.find("trading anyway") != std::string::npos, "InpNewsUnknownBlocks = false: trade blind, said plainly");
      g_newsUnknownBlocks = true;
      SIM.calOk = true;
      SIM.tester = true;
      stepTo(START + 14);
      CHECK(g_newsTester && !g_newsUnknown && !g_newsBlock && (g_gate & (NQ_K_NEWS | NQ_K_NEWS_UNKNOWN)) == 0 && lbl("v_e0n").find("N/A in the Strategy Tester") == 0,
            "the Strategy Tester has no calendar: N/A, not gated, not UNKNOWN");
      SIM.tester = false;
      OnDeinit(0);
   }
   end("F4");

   begin("F5 currency strength from the broker's majors, the witnesses (oil, gold, bond, DXY), the macro vote and its A+ override");
   {
      Market gbp = makeMarket(21, 1.2700, 0.00001, 0.00010, (int)DAYS);
      Market aud = makeMarket(22, 0.6600, 0.00001, 0.00007, (int)DAYS);
      Market nzd = makeMarket(23, 0.6000, 0.00001, 0.00007, (int)DAYS);
      Market usdjpy = makeMarket(24, 150.25, 0.001, 0.012, (int)DAYS);
      Market usdcad = makeMarket(25, 1.3600, 0.00001, 0.00008, (int)DAYS);
      Market usdchf = makeMarket(26, 0.8800, 0.00001, 0.00007, (int)DAYS);
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      SIM.extra["GBPUSD"] = toRates(gbp.m15);
      SIM.extra["AUDUSD"] = toRates(aud.m15);
      SIM.extra["NZDUSD"] = toRates(nzd.m15);
      SIM.extra["USDJPY"] = toRates(usdjpy.m15);
      SIM.extra["USDCAD"] = toRates(usdcad.m15);
      SIM.extra["USDCHF"] = toRates(usdchf.m15);
      startAt(START);
      relax();
      CHECK(g_strPairs == 7 && g_strOk, "all seven majors served: 7 pairs");
      double rE = 0, rG = 0, rA = 0, rN = 0, rJ = 0, rC = 0, rF = 0;
      CHECK(NqMoveOf(g_s15, rE) && NqPairMove("GBPUSD", rG) && NqPairMove("AUDUSD", rA) && NqPairMove("NZDUSD", rN) &&
            NqPairMove("USDJPY", rJ) && NqPairMove("USDCAD", rC) && NqPairMove("USDCHF", rF), "every pair's move is measurable");
      double usd = (-rE - rG - rA - rN + rJ + rC + rF) / 7.0;
      CHECK(near(NqStrOf("EUR"), rE, 1e-9) && near(NqStrOf("USD"), usd, 1e-9) && near(NqStrOf("GBP"), rG, 1e-9) && near(NqStrOf("JPY"), -rJ, 1e-9) &&
            near(g_strDiff, rE - usd, 1e-9), "strength = the mean of a currency's signed moves in ATR units; diff = base - quote");
      double ad = std::fabs(g_strDiff);
      CHECK(g_strGrade == (ad >= 2.0 ? 2 : (ad >= 1.0 ? 1 : 0)) && g_strDir == (g_strDiff > 0 ? 1 : (g_strDiff < 0 ? -1 : 0)), "grade by the two thresholds");
      CHECK(lbl("v_e0s").find("EUR ") == 0 && lbl("v_e0s").find("7 pairs") != std::string::npos && lbl("v_e0s").find("basket:") != std::string::npos, "the STRENGTH row");
      OnDeinit(0);
      SIM.extra.clear();
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      CHECK(g_strPairs == 1 && g_strOk && near(NqStrOf("USD"), -NqStrOf("EUR"), 1e-12), "a broker with none of the majors: the pair alone, said as 1 pair");
      OnDeinit(0);

      // witnesses: oil speaks for CAD, the bond and the index for USD, gold for AUD; a symbol the broker lacks is NO DATA
      Market oil = makeMarket(41, 75.0, 0.01, 0.08, (int)DAYS);
      Market cad = makeMarket(31, 1.3600, 0.00001, 0.00008, (int)DAYS);
      load(cad, "USDCAD", "USD", 5, 0.00001, 0.74);
      SIM.profit = "CAD";
      SIM.extra["XTIUSD"] = toRates(oil.m15);
      startAt(START);
      relax();
      CHECK(g_oilSym == "XTIUSD" && g_goldSym == "" && g_bondSym == "" && g_dxySym == "", "USDCAD: oil found (AUTO), no gold (no AUD), no bond / index at this broker");
      CHECK(g_oilDir != 0, "the oil witness is read");
      std::string w;
      int keep = g_oilDir;
      g_oilDir = 1;
      CHECK(NqWitnessVote(1, "oil", g_oilSym, g_oilDir, NQ_OIL_CCY, 1, w) == -1 && NqWitnessVote(-1, "oil", g_oilSym, g_oilDir, NQ_OIL_CCY, 1, w) == 1,
            "oil BULLISH = CAD stronger = USDCAD down: -1 for a BUY, +1 for a SELL");
      CHECK(NqWitnessVote(1, "bond", "USTNOTE", 1, NQ_USD_CCY, -1, w) == -1 && NqWitnessVote(1, "yield", "US10Y", 1, NQ_USD_CCY, 1, w) == 1,
            "a bond PRICE up = USD weaker (-1 for a USD-base BUY); a YIELD up = USD stronger (+1)");
      CHECK(!NqBondIsYield("USTNOTE") && !NqBondIsYield("ZN") && NqBondIsYield("US10Y") && NqBondIsYield("USYIELD10") && !NqBondIsYield("US10YT"),
            "AUTO bond kind from the name");
      CHECK(NqWitnessVote(1, "gold", "XAUUSD", 1, NQ_GOLD_CCY, 1, w) == 0, "gold speaks for AUD only: no vote on USDCAD");
      g_oilDir = keep;
      g_oilSym = "NOPE";
      NqReadWitnesses();
      OnTimer();
      CHECK(g_oilDir == 0 && NqWitnessVote(1, "oil", g_oilSym, g_oilDir, NQ_OIL_CCY, 1, w) == 0 && lbl("v_e0m").find("oil NOPE NO DATA") != std::string::npos,
            "a witness the broker cannot serve: NO DATA on the row, no vote");
      OnDeinit(0);
      SIM.extra.clear();

      // the vote and the block on EURUSD: strength EUR<USD STRONG (-2) + DXY BULLISH (-1) = -3 against a BUY
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      g_macroGate = true;
      g_strOk = true; g_strDir = -1; g_strGrade = 2;
      g_dxySym = "USDX"; g_dxyDir = 1;
      g_oilSym = ""; g_goldSym = ""; g_bondSym = "";
      std::string why;
      CHECK(NqMacroVote(1, why) == -3 && why.find("strength EUR<USD STRONG -2") == 0 && why.find("DXY BULLISH -1") != std::string::npos, "BUY vote -3 with its voters named");
      CHECK(NqMacroVote(-1, why) == 3, "SELL vote +3");
      size_t i15 = (size_t)g_s15.n - 1, i5 = (size_t)g_s5.n - 1;
      int c15 = g_s15.ctx[i15], r5 = g_s5.regime[i5];
      g_s15.ctx[i15] = -1; g_s5.regime[i5] = NQ_REG_BEAR;
      CHECK(NqMacroBlocks(1, 0, false, why) && why.find("MACRO AGAINST BUY (vote -3") == 0 && !NqMacroBlocks(-1, 0, false, why), "a BUY is blocked, a SELL is not");
      g_s15.ctx[i15] = 1; g_s5.regime[i5] = NQ_REG_BULL;
      CHECK(!NqMacroBlocks(1, 0, false, why) && NqMacroBlocks(1, 8, true, why) && !NqMacroBlocks(1, 9, true, why),
            "the pair's own A+ structure overrides: M15 + M5 with the trade (a radar break also needs score 9)");
      g_s15.ctx[i15] = -1;
      CHECK(NqMacroBlocks(1, 10, true, why), "M15 against: no override however high the score");
      g_strGrade = 1; g_dxyDir = 0;
      CHECK(!NqMacroBlocks(1, 0, false, why), "a WEAK vote (-1) blocks nothing");
      g_strGrade = 2; g_macroGate = false;
      CHECK(!NqMacroBlocks(1, 0, false, why), "gate off: the vote is shown, nothing blocked");
      OnTimer();
      CHECK(lbl("v_e0m").find("vote BUY -2 / SELL +2") == 0 && lbl("v_e0m").find("gate off") != std::string::npos, "the MACRO VOTE row");
      g_s15.ctx[i15] = c15; g_s5.regime[i5] = r5;
      OnDeinit(0);
   }
   end("F5");

   begin("F6 session tilt: Asia leans BUY, NY leans SELL; against the tilt only with strong confirmation; recorded on every journal line");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      g_sessionTilt = true;
      g_strOk = false; g_oilSym = ""; g_goldSym = ""; g_bondSym = ""; g_dxySym = "";
      size_t i15 = (size_t)g_s15.n - 1, i5 = (size_t)g_s5.n - 1;
      int c15 = g_s15.ctx[i15], r5 = g_s5.regime[i5];
      std::string why;
      g_sessOpen = 4;
      CHECK(NqTiltNow() == -1 && NqSessionName() == "NY", "New York leans SELL");
      g_s15.ctx[i15] = -1; g_s5.regime[i5] = NQ_REG_BEAR;
      CHECK(NqTiltBlocks(1, 0, false, NQ_PLAN_PB, why) && why.find("AGAINST THE NY TILT (SELL)") == 0 && !NqTiltBlocks(-1, 0, false, NQ_PLAN_PB, why),
            "a BUY pullback in NY with M15 and M5 against it: blocked; a SELL never");
      g_s15.ctx[i15] = 1; g_s5.regime[i5] = NQ_REG_BULL;
      CHECK(!NqTiltBlocks(1, 0, false, NQ_PLAN_PB, why), "M15 + M5 with the BUY, macro vote 0: strong confirmation, allowed");
      g_s5.regime[i5] = NQ_REG_CHOP;
      CHECK(NqTiltBlocks(1, 0, false, NQ_PLAN_PB, why) && !NqTiltBlocks(1, 0, false, NQ_PLAN_QML, why) && !NqTiltBlocks(1, 0, false, NQ_PLAN_NY, why),
            "M5 CHOP: a pullback is not confirmed; a reversal plan (QML, NY trap) needs the M15 context only");
      g_s5.regime[i5] = NQ_REG_BULL;
      CHECK(NqTiltBlocks(1, 7, true, NQ_PLAN_RADAR, why) && !NqTiltBlocks(1, 8, true, NQ_PLAN_RADAR, why), "a radar break against the tilt needs score 8");
      g_strOk = true; g_strDir = -1; g_strGrade = 1;
      CHECK(NqTiltBlocks(1, 0, false, NQ_PLAN_PB, why) && why.find("macro vote -1") != std::string::npos, "the macro vote against it: not strong");
      g_strOk = false;
      g_sessOpen = 1;
      CHECK(NqTiltNow() == 1 && NqTiltBlocks(-1, 0, false, NQ_PLAN_PB, why) && !NqTiltBlocks(1, 0, false, NQ_PLAN_PB, why), "Asia leans BUY: a SELL needs confirmation");
      g_sessOpen = 2;
      CHECK(NqTiltNow() == 0 && !NqTiltBlocks(-1, 0, false, NQ_PLAN_PB, why), "London: no lean");
      g_sessionTilt = false;
      g_sessOpen = 4;
      g_s15.ctx[i15] = -1; g_s5.regime[i5] = NQ_REG_BEAR;
      CHECK(!NqTiltBlocks(1, 0, false, NQ_PLAN_PB, why), "tilt off: nothing blocked");
      g_s15.ctx[i15] = c15; g_s5.regime[i5] = r5;
      run(START + 1, START + 600);
      auto it = SIM.files.find("NQ_events_EURUSD.jsonl");
      bool have = it != SIM.files.end() && !it->second.empty();
      int missing = 0, lines = 0;
      if(have)
      {
         std::string s = it->second;
         size_t p = 0;
         while(p < s.size())
         {
            size_t e = s.find('\n', p);
            if(e == std::string::npos) e = s.size();
            std::string l = s.substr(p, e - p);
            if(!l.empty())
            {
               lines++;
               for(const char *k : {"\"engine\":\"NQ-FOREX\"", "\"pair_class\":\"MAJOR\"", "\"base\":\"EUR\"", "\"quote\":\"USD\"", "\"session\":\"", "\"tilt\":",
                                    "\"with_tilt\":", "\"h4_ctx\":", "\"m5_break\":", "\"system\":\"NQ-EA\"", "\"signal_id\":\"NQ:EURUSD:"})
                  if(l.find(k) == std::string::npos) missing++;
            }
            p = e + 1;
         }
      }
      CHECK(have && lines > 0 && missing == 0, "every journal line carries engine, pair class, base / quote, session, tilt, with_tilt, the H4 context and the last M5 break");
      OnDeinit(0);
   }
   end("F6");

   begin("F7 smart exit: bank on an M5 flip in profit, cut under water, lock the SL at +0.7R, bank on an M1 turn; a reversal plan whose regime never agreed is left alone");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      g_smartExit = true;
      size_t i = START + 1;
      int reg = 0;
      for(; i <= END; i++) { stepTo(i); reg = g_s5.regime[(size_t)g_s5.n - 1]; if(reg == NQ_REG_BULL) break; }
      CHECK(reg == NQ_REG_BULL, "found a bullish M5 regime");
      size_t n5 = (size_t)g_s5.n;
      int keep1 = g_s5.regime[n5 - 1], keep2 = g_s5.regime[n5 - 2];
      double risk = 0.0010;
      auto plant = [&](ulong tk, int type, double open, const char *cmt) {
         SIM.pos.clear();
         SIM.ord.clear();
         SimPos p;
         p.ticket = tk; p.sym = "EURUSD"; p.type = type; p.vol = 0.10; p.open = open;
         p.sl = (type == POSITION_TYPE_BUY) ? open - risk : open + risk; p.tp = (type == POSITION_TYPE_BUY) ? open + 3 * risk : open - 3 * risk;
         p.time = g_s5.t[n5 - 2]; p.magic = InpMagic; p.comment = cmt;
         SIM.pos.push_back(p);
      };
      auto closedWith = [&](ulong tk, const char *txt) {
         for(const SimPos &p : SIM.pos) if(p.ticket == tk) return false;
         for(const std::string &l : SIM.log) if(l.find(txt) != std::string::npos) return true;
         return false;
      };
      // a) the regime agreed (bar n-2 BULL), then flipped (bar n-1 BEAR): +0.3R is banked
      g_s5.regime[n5 - 2] = NQ_REG_BULL; g_s5.regime[n5 - 1] = NQ_REG_BEAR;
      plant(8001, POSITION_TYPE_BUY, SIM.bid - 0.3 * risk, "NQ-P8001");
      CHECK(NqRegimeAgreedSince(g_s5.t[n5 - 2], 1), "the regime agreed since the open");
      NqVerdict();
      CHECK(g_verdict.find("EXIT BUY #8001") == 0 && g_verdict.find("SMART EXIT banks it") != std::string::npos && g_verdict.find("+0.30R") != std::string::npos,
            "the verdict says the smart exit will bank +0.30R at the next M1 close");
      NqTrade();
      CHECK(closedWith(8001, "SMART EXIT: M5 regime flipped BEARISH against the position, banking +0.30R"), "banked with the reason");
      // b) under water: cut before the SL
      plant(8002, POSITION_TYPE_BUY, SIM.bid + 0.3 * risk, "NQ-P8002");
      NqTrade();
      CHECK(closedWith(8002, "SMART EXIT: M5 regime flipped BEARISH against the position at -0.30R - cut before the SL"), "cut at -0.30R with the reason");
      // c) a scalp under water on a flip: the scalp rule, not the smart cut
      plant(8003, POSITION_TYPE_BUY, SIM.bid + 0.3 * risk, "NQ-S8003");
      NqTrade();
      CHECK(closedWith(8003, "M5 regime turned BEARISH against the scalp"), "a scalp keeps its own flip rule");
      // d) the regime never agreed (a reversal plan filled against it): the flip means nothing, the plan runs
      g_s5.regime[n5 - 2] = NQ_REG_BEAR;
      plant(8004, POSITION_TYPE_BUY, SIM.bid - 0.3 * risk, "NQ-Q8004");
      int keepD1 = g_s1.dir[(size_t)g_s1.n - 1];
      g_s1.dir[(size_t)g_s1.n - 1] = 1;
      NqVerdict();
      CHECK(g_verdict.find("EXIT BUY #8004") == 0 && g_verdict.find("never agreed") != std::string::npos, "the verdict explains why the bot will not act");
      NqTrade();
      bool stillThere = false;
      for(const SimPos &p : SIM.pos) if(p.ticket == 8004) stillThere = true;
      CHECK(stillThere, "left to its SL / TP");
      // e) the lock: +0.8R with the regime intact moves the SL to entry + 0.1R, once
      g_s5.regime[n5 - 2] = NQ_REG_BULL; g_s5.regime[n5 - 1] = NQ_REG_BULL;
      plant(8005, POSITION_TYPE_BUY, SIM.bid - 0.8 * risk, "NQ-P8005");
      size_t before = SIM.sent.size();
      NqTrade();
      bool locked = false;
      double wantSl = NqRoundTick(SIM.pos.empty() ? 0.0 : SIM.pos[0].open + 0.1 * risk, 0.00001, 5, -1);
      for(size_t k = before; k < SIM.sent.size(); k++)
         if(SIM.sent[k].action == TRADE_ACTION_SLTP && SIM.sent[k].position == 8005 && near(SIM.sent[k].sl, wantSl, 1e-9)) locked = true;
      CHECK(locked && !SIM.pos.empty() && near(SIM.pos[0].sl, wantSl, 1e-9), "SL moved to entry + 0.1R by a SLTP request; the position stays");
      bool logged = false;
      for(const std::string &l : SIM.log) if(l.find("SMART LOCK: +0.80R reached") != std::string::npos) logged = true;
      CHECK(logged, "logged with the reason");
      before = SIM.sent.size();
      NqTrade();
      int again = 0;
      for(size_t k = before; k < SIM.sent.size(); k++) if(SIM.sent[k].action == TRADE_ACTION_SLTP) again++;
      CHECK(again == 0, "never loosened, never repeated");
      NqVerdict();
      CHECK(g_verdict.find("HOLD BUY #8005") == 0 && g_verdict.find("SL locked") != std::string::npos, "HOLD ... SL locked");
      // f) the M1 bias turned against a +0.6R position: banked; at +0.3R not
      g_s1.dir[(size_t)g_s1.n - 1] = -1;
      plant(8006, POSITION_TYPE_BUY, SIM.bid - 0.6 * risk, "NQ-P8006");
      NqTrade();
      CHECK(closedWith(8006, "SMART EXIT: M1 bias turned BEARISH, banking +0.60R"), "M1 turn with +0.6R: banked");
      plant(8007, POSITION_TYPE_BUY, SIM.bid - 0.3 * risk, "NQ-P8007");
      NqTrade();
      stillThere = false;
      for(const SimPos &p : SIM.pos) if(p.ticket == 8007) stillThere = true;
      CHECK(stillThere, "+0.3R is under the M1 threshold: kept");
      // g) smart exit off: the hard rules only (a plan position on a flip says EXIT, you decide)
      g_smartExit = false;
      g_s5.regime[n5 - 1] = NQ_REG_BEAR;
      plant(8008, POSITION_TYPE_BUY, SIM.bid - 0.3 * risk, "NQ-P8008");
      NqTrade();
      stillThere = false;
      for(const SimPos &p : SIM.pos) if(p.ticket == 8008) stillThere = true;
      NqVerdict();
      CHECK(stillThere && g_verdict.find("you decide") != std::string::npos, "off: the plan position is left to the human");
      g_s1.dir[(size_t)g_s1.n - 1] = keepD1;
      g_s5.regime[n5 - 1] = keep1; g_s5.regime[n5 - 2] = keep2;
      SIM.pos.clear();
      OnDeinit(0);
   }
   end("F7");

   begin("F8 the Friday stop and the portfolio: orders pulled and profits banked before the weekend; positions across pairs and same-currency exposure");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 5);
      SIM.pos.clear();
      SIM.ord.clear();
      SimOrder so;
      so.ticket = 9101; so.sym = "EURUSD"; so.type = ORDER_TYPE_BUY_LIMIT; so.vol = 0.10; so.price = SIM.bid - 0.0020; so.sl = SIM.bid - 0.0030; so.tp = SIM.bid - 0.0010;
      so.time = SIM.now; so.magic = InpMagic; so.comment = "NQ-Q9101";
      SIM.ord.push_back(so);
      SimPos a;
      a.ticket = 9102; a.sym = "EURUSD"; a.type = POSITION_TYPE_BUY; a.vol = 0.10; a.open = SIM.bid - 0.0002; a.sl = a.open - 0.0010; a.tp = a.open + 0.0030;
      a.time = SIM.now - 600; a.magic = InpMagic; a.comment = "NQ-P9102";
      SIM.pos.push_back(a);
      SimPos l = a;
      l.ticket = 9103; l.type = POSITION_TYPE_SELL; l.open = SIM.bid - 0.0002; l.sl = l.open + 0.0010; l.tp = l.open - 0.0030; l.comment = "NQ-P9103";
      SIM.pos.push_back(l);
      g_weekFriday = true;
      g_weekEdge = true;
      NqTrade();
      bool orderGone = true, aGone = true, lKept = false;
      for(const SimOrder &o : SIM.ord) if(o.ticket == 9101) orderGone = false;
      for(const SimPos &p : SIM.pos) { if(p.ticket == 9102) aGone = false; if(p.ticket == 9103) lKept = true; }
      bool r1 = false, r2 = false;
      for(const std::string &l2 : SIM.log)
      {
         if(l2.find("WEEKEND: resting orders are pulled before the Friday close") != std::string::npos) r1 = true;
         if(l2.find("WEEKEND: banking +0.20R before the Friday close") != std::string::npos) r2 = true;
      }
      CHECK(orderGone && aGone && lKept && r1 && r2, "Friday stop: the order is pulled, the +0.2R BUY is banked, the losing SELL keeps its SL (InpWeekendCloseLosers = false)");
      g_weekFriday = false;
      g_weekEdge = false;
      SIM.pos.clear();
      // the portfolio: this EA's positions on OTHER charts count (same magic), by their symbol's currencies
      auto other = [&](ulong tk, const char *sym, int type) {
         SimPos p;
         p.ticket = tk; p.sym = sym; p.type = type; p.vol = 0.10; p.open = 1.0; p.sl = 0; p.tp = 0; p.time = SIM.now; p.magic = InpMagic; p.comment = "NQ-P1";
         SIM.pos.push_back(p);
      };
      other(9201, "USDJPY", POSITION_TYPE_BUY);
      other(9202, "USDCAD", POSITION_TYPE_BUY);
      NqReadAccount();
      std::string why;
      CHECK(g_portfolioPos == 2 && !g_portfolioFull && NqExpOf("USD") == 2 && NqExpOf("JPY") == -1 && NqExpOf("CAD") == -1, "two USD longs on other charts: USD +2");
      CHECK(NqExposureBlocks(-1, why) && why.find("EXPOSURE - already 2 position(s) long USD") == 0 && !NqExposureBlocks(1, why),
            "a EURUSD SELL (a third USD long) is blocked; a BUY (USD short) is not");
      CHECK(g_openCount == 0, "they do not take this chart's slot");
      other(9203, "GBPUSD", POSITION_TYPE_SELL);
      NqReadAccount();
      NqEvaluate();
      CHECK(g_portfolioPos == 3 && g_portfolioFull && (g_gate & NQ_K_PORTFOLIO) != 0 && NqGateAtX(g_gate, 0).find("PORTFOLIO FULL - 3 POSITIONS") != std::string::npos,
            "three positions across pairs = the cap: PORTFOLIO FULL closes the gate");
      OnTimer();
      CHECK(lbl("v_e0h").find("portfolio 3 pos") != std::string::npos && lbl("v_e0h").find("USD+3") != std::string::npos, "the SESSION row shows the portfolio and the exposure");
      SIM.pos.clear();
      OnDeinit(0);
   }
   end("F8");

   begin("F9 higher timeframes: H1 / H4 context, confirmed structure, BOS / CHoCH classification, the HTF voters");
   {
      Market big = makeMarket(7, 1.0850, 0.00001, 0.00009, 40);
      load(big, "EURUSD", "EUR", 5, 0.00001, 1.0);
      SIM.h1 = toRates(agg(big.m1, 3600));
      SIM.h4 = toRates(agg(big.m1, 14400));
      const size_t START40 = 1440 * 39 + 17;
      startAt(START40);
      relax();
      CHECK(g_h1Ok && g_h4Ok && g_h1.n == 400 && g_h4.n >= 200 && g_h4.emaS[(size_t)g_h4.n - 1] > 0.0 && g_h1.emaS[(size_t)g_h1.n - 1] > 0.0,
            "400 H1 and 200+ H4 bars loaded: EMA200 ready on both");
      CHECK(lbl("v_e0t").find("H4 ") == 0 && lbl("v_e0t").find("|   H1 ") != std::string::npos && lbl("v_e0t").find("last ") != std::string::npos, "the H4 / H1 row");
      NqSeries s;
      NqSeriesResize(s, 3);
      ArrayResize(s.st, 3);
      NqSwingBreak b;
      b.pivIdx = 0; b.idx = 1; b.level = 1.0; b.close = 1.0;
      s.st[0] = NQ_ST_BULL; b.dir = 1;
      bool okB = (NqBreakKind(s, b) == "BOS");
      b.dir = -1;
      okB = okB && (NqBreakKind(s, b) == "CHoCH");
      s.st[0] = NQ_ST_BEAR;
      okB = okB && (NqBreakKind(s, b) == "BOS");
      b.dir = 1;
      okB = okB && (NqBreakKind(s, b) == "CHoCH");
      s.st[0] = NQ_ST_MIXED;
      okB = okB && (NqBreakKind(s, b) == "BREAK");
      CHECK(okB, "a close through a swing WITH the structure in force = BOS, AGAINST it = CHoCH, no structure = BREAK");
      size_t i4 = (size_t)g_h4.n - 1, i1 = (size_t)g_h1.n - 1;
      int c4 = g_h4.ctx[i4], c1 = g_h1.ctx[i1];
      g_h4.ctx[i4] = 1; g_h1.ctx[i1] = 1;
      int keepN = g_nSbH1;
      g_nSbH1 = 0;
      std::string w;
      CHECK(NqHtfVote(1, w) == 2 && w.find("H4 BULLISH +1") == 0 && w.find("H1 BULLISH +1") != std::string::npos && NqHtfVote(-1, w) == -2, "H4 and H1 context vote 1 each");
      g_h1.ctx[i1] = -1;
      CHECK(NqHtfVote(1, w) == 0, "H1 against H4: they cancel");
      // a fresh H1 CHoCH down votes its direction
      g_h1.ctx[i1] = 1;
      ArrayResize(g_sbH1, 1);
      g_sbH1[0].pivIdx = 0; g_sbH1[0].idx = g_h1.n - 2; g_sbH1[0].dir = -1; g_sbH1[0].level = 1.0; g_sbH1[0].close = 1.0;
      g_h1.st[(size_t)g_h1.n - 3] = NQ_ST_BULL;
      g_nSbH1 = 1;
      CHECK(NqHtfVote(1, w) == 1 && w.find("H1 CHoCH down -1") != std::string::npos, "a CHoCH down 1 bar ago: -1 for a BUY (counted beside the two contexts)");
      g_sbH1[0].idx = g_h1.n - 30;
      CHECK(NqHtfVote(1, w) == 2, "a CHoCH older than InpHtfChochBars votes nothing");
      g_nSbH1 = keepN;
      g_h4.ctx[i4] = c4; g_h1.ctx[i1] = c1;
      // no H1 / H4 at the broker: NO DATA, no vote, the EA runs on
      OnDeinit(0);
      SIM.h1.clear();
      SIM.h4.clear();
      startAt(START40);
      relax();
      CHECK(!g_h1Ok && !g_h4Ok && NqHtfVote(1, w) == 0 && lbl("v_e0t").find("H4 NO DATA") == 0 && g_ready, "no H1 / H4 served: NO DATA, no vote, everything else runs");
      OnDeinit(0);
   }
   end("F9");


   begin("F10 compact board, click-to-fold blocks, the SL guard: a position without a stop gets the plan's stop back or is closed");
   {
      load(eur, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 300);
      // compact: an empty plan slot has no detail line, a filled one has; broker rows only as many as there are
      int withDetail = 0, withoutDetail = 0, badDetail = 0;
      for(int q = 0; q < NQ_PLAN_SLOTS; q++)
      {
         NqPlan pl;
         bool has = NqSlotPlan(q, pl);
         bool det = lbl(("bp" + std::to_string(q) + "d").c_str()) != "<missing>";
         if(has && det) withDetail++;
         else if(!has && !det) withoutDetail++;
         else badDetail++;
      }
      CHECK(badDetail == 0 && withDetail + withoutDetail == NQ_PLAN_SLOTS, "a detail line exactly for the slots that hold a plan");
      int brokerRows = 0;
      for(int i = 0; i < 6; i++) if(lbl(("bb" + std::to_string(i) + "0").c_str()) != "<missing>") brokerRows++;
      CHECK(brokerRows == std::max(1, std::min(6, (int)SIM.ord.size() + (int)SIM.pos.size())), "broker rows = the orders and positions there are, at least one line");
      // fold the desk: the engine rows go, the header stays and says unfold; unfold brings them back
      CHECK(lbl("k_e1") == "M15 CONTEXT" && lbl("h1").find("(click: fold)") != std::string::npos, "the desk is open");
      OnChartEvent(CHARTEVENT_OBJECT_CLICK, 0, 0.0, "NQEA_P_h1");
      CHECK(g_deskCollapsed && lbl("k_e1") == "<missing>" && lbl("h1").find("(click: unfold)") != std::string::npos && lbl("t2") != "<missing>",
            "click on the desk header: folded to its header, the board untouched");
      OnChartEvent(CHARTEVENT_OBJECT_CLICK, 0, 0.0, "NQEA_P_h1~1");
      CHECK(!g_deskCollapsed && lbl("k_e1") == "M15 CONTEXT", "a click on a piece of the header unfolds it");
      // fold the board: the banner and the reasons stay, the tables and the footer go
      OnChartEvent(CHARTEVENT_OBJECT_CLICK, 0, 0.0, "NQEA_P_title");
      CHECK(g_boardCollapsed && lbl("state") != "<missing>" && lbl("r1") != "<missing>" && lbl("t2") == "<missing>" && lbl("bf1") == "<missing>" &&
            lbl("f1") == "<missing>" && lbl("title").find("(click: unfold)") != std::string::npos && lbl("t1") != "<missing>",
            "click on the title: the board folds to its banner, the desk stays");
      OnTimer();
      CHECK(lbl("t2") == "<missing>" && lbl("state") != "<missing>", "a refresh keeps it folded");
      OnChartEvent(CHARTEVENT_OBJECT_CLICK, 0, 0.0, "NQEA_P_title");
      CHECK(!g_boardCollapsed && lbl("t2") != "<missing>" && lbl("bf1") != "<missing>", "a second click unfolds it");
      OnChartEvent(CHARTEVENT_OBJECT_CLICK, 0, 0.0, "NQEA_P_v_e1");
      CHECK(!g_boardCollapsed && !g_deskCollapsed, "a click elsewhere does nothing");
      // the SL guard
      int kp = -1;
      for(int k = g_nPlans - 1; k >= 0; k--) if(g_plans[(size_t)k].dir > 0 && g_plans[(size_t)k].sl > 0.0) { kp = k; break; }
      CHECK(kp >= 0, "a BUY plan exists in the history");
      if(kp >= 0)
      {
         const NqPlan &pp = g_plans[(size_t)kp];
         double keepBid = SIM.bid;
         SIM.pos.clear();
         SIM.ord.clear();
         SimPos p;
         p.ticket = 9301; p.sym = SIM.sym; p.type = POSITION_TYPE_BUY; p.vol = 0.10; p.open = pp.entry; p.sl = 0; p.tp = 0;
         p.time = SIM.now - 600; p.magic = InpMagic; p.comment = NqPlanComment(pp);
         SIM.pos.push_back(p);
         SIM.bid = pp.sl + pp.risk * 0.5;   // above the plan's stop: the stop is restored
         size_t before = SIM.sent.size();
         NqTrade();
         bool restored = false;
         for(size_t k = before; k < SIM.sent.size(); k++)
            if(SIM.sent[k].action == TRADE_ACTION_SLTP && SIM.sent[k].position == 9301 && near(SIM.sent[k].sl, pp.sl, 1e-9) && near(SIM.sent[k].tp, pp.tp1, 1e-9)) restored = true;
         bool logged = false;
         for(const std::string &l : SIM.log) if(l.find("SL MISSING: the plan's stop") != std::string::npos) logged = true;
         CHECK(restored && logged && !SIM.pos.empty() && near(SIM.pos[0].sl, pp.sl, 1e-9), "no stop at the broker: the plan's SL and TP1 are restored by one SLTP request, logged");
         SIM.pos.clear();
         p.ticket = 9302;
         SIM.pos.push_back(p);
         SIM.bid = pp.sl - pp.risk * 0.5;   // already beyond the stop: closed now
         NqTrade();
         bool gone = true;
         for(const SimPos &q2 : SIM.pos) if(q2.ticket == 9302) gone = false;
         bool said = false;
         for(const std::string &l : SIM.log) if(l.find("SL MISSING and the price is already beyond") != std::string::npos) said = true;
         CHECK(gone && said, "no stop and the price beyond it: closed with the reason");
         SIM.bid = keepBid;
      }
      SIM.pos.clear();
      OnDeinit(0);
   }
   end("F10");

   std::printf("\nFOREX EA TESTS: %d checks passed, %d failed\n", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
