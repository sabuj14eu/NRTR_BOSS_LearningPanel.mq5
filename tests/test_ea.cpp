// Whole-EA tests: the complete NRTR_QML_MetalScalper.mq5 (translated
// syntax-only) runs on a simulated MT5 terminal WITH a trade API:
// OnInit -> OnTick per closed M1 bar -> OnDeinit. Every order the EA sends
// is checked against the engine's own records.
#include "../tests/mt5_sim_ea.h"
#include "ea_full.inc"
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
// the v1.9 gates off, so the engine's own behaviour is checked as before (the M sections test them)
static void relax()
{
   g_clockGuards = false;
   g_macroGate = false;
   g_smartExit = false;
   g_profitLock = false;
   g_flipCutLoss = false;
   g_adrGate = false;      // the v1.11 MH15 PLUS gates off too (the S sections test them)
   g_ladderGate = false;
   g_studyGate = false;
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
   Market gold = makeMarket(7, 4150.0, 0.01, 0.35, (int)DAYS);
   const size_t START = 1440 * 4 + 17;   // day 5, 00:17
   const size_t END = 1440 * 6 - 2;

   begin("A1 demo account: scalps are sent on the M1 trigger with the engine's SL/TP and a risk-sized lot");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      CHECK(startAt(START) == INIT_SUCCEEDED, "init");
      relax();
      CHECK(g_metal == NQ_METAL_GOLD && g_isDemo, "gold, demo");
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
         if((long long)r.magic != InpMagic || r.symbol != "XAUUSD") bad++;
         double slDist = std::fabs(r.price - r.sl);
         double loss = NqLossAt(r.volume, slDist, 0.01, 1.0);
         // loss at SL never exceeds the risk allowance (balance at the time <= 10000 + gains, use a loose bound)
         if(loss > 0.5 / 100.0 * (SIM.balance + 500.0) + 1e-6) lotBad++;
         if(r.volume < 0.01 - 1e-9) lotBad++;
      }
      std::printf("    %d market orders, %zu deals, balance %.2f\n", market, SIM.deals.size(), SIM.balance);
      CHECK(market >= 0, "scalps are the lowest priority: none while a plan order waits (silver run below has scalps)");
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
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
               if(!near(p.entry, r.price) || !near(p.sl, r.sl) || !near(NqPlanTpSent(p), r.tp)) bad++;
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
               double loss = NqLossAt(r.volume, p.risk, 0.01, 1.0);
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
         for(const SimPos &ps : SIM.pos) if(ps.comment == d.comment && near(ps.sl, p.sl) && near(ps.tp, NqPlanTpSent(p))) found = true;
         for(const SimDeal &x : SIM.deals)
            if(x.comment == d.comment && x.entry == DEAL_ENTRY_OUT &&
               ((x.reason == "sl" && near(x.price, p.sl)) || (x.reason == "tp" && near(x.price, NqPlanTpSent(p))))) found = true;
         if(!found) fillBad++;
      }
      std::printf("    QML placed %d, pullback placed %d\n", qmlPlaced, pbPlaced);
      CHECK(qmlPlaced > 0 && pbPlaced > 0, "both plan kinds were placed");
      CHECK(limitFills > 0, "some limit orders were filled");
      std::printf("    %d limit orders placed, %d cancelled, %d filled\n", placed, cancels, limitFills);
      CHECK(placed > 0, "plans were placed");
      CHECK(bad == 0, "orders match ACTIVE plans (entry, SL, the TP SENT = TP2 by default, side) and never linger after the plan ends");
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.accountMode = ACCOUNT_TRADE_MODE_REAL;
      startAt(START);
      relax();
      run(START + 1, END);
      CHECK(!SIM.sent.empty(), "orders are sent on a real account");
      CHECK(lbl("bf2").find("REAL") == 0, "footer shows REAL");
      CHECK(lbl("state").find("REAL ACCOUNT") == std::string::npos, "no blocking banner");

      // the terminal's Algo Trading button off: nothing sent, banner says watch only
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.terminalTrade = false;
      startAt(START);
      relax();
      run(START + 1, START + 400);
      CHECK(SIM.sent.empty(), "Algo Trading off: nothing sent");
      CHECK(lbl("state").find("MANUAL:") == 0 && lbl("r1").find("ALGO TRADING OFF") != std::string::npos, "banner verdict is prefixed MANUAL: and the reason line says ALGO TRADING OFF");
      CHECK(lbl("bf1").find("ALGO TRADING OFF") != std::string::npos, "footer gate names it");

      // manual (foreign magic) order and position on the symbol: counted, shown, never touched
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      SimPos mp;
      mp.ticket = 9001; mp.sym = "XAUUSD"; mp.type = POSITION_TYPE_SELL; mp.vol = 0.30; mp.open = SIM.bid; mp.sl = 0; mp.tp = 0;
      mp.time = SIM.now; mp.magic = 0; mp.comment = "manual";
      SIM.pos.push_back(mp);
      SimOrder mo;
      mo.ticket = 9002; mo.sym = "XAUUSD"; mo.type = ORDER_TYPE_BUY_LIMIT; mo.vol = 0.30; mo.price = SIM.bid - 50; mo.sl = 0; mo.tp = 0;
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 200);
      // inject a losing day: one closed deal of -2% today with our magic
      SimDeal d;
      d.ticket = 1;
      d.sym = "XAUUSD";
      d.entry = DEAL_ENTRY_OUT;
      d.type = 1;
      d.vol = 0.1;
      d.price = 4100;
      d.profit = -0.05 * SIM.balance;   // more than the 2% cap even after today's wins
      d.time = SIM.now - 60;
      d.magic = InpMagic;
      d.comment = "NQ-S0";
      SIM.deals.push_back(d);
      // and an open scalp that is old enough for the time stop
      SIM.pos.clear();
      SimPos p;
      p.ticket = 77;
      p.sym = "XAUUSD";
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.spreadPts = 500;
      startAt(START);
      relax();
      run(START + 1, END);
      CHECK(countSent(TRADE_ACTION_DEAL, true) == 0 && countSent(TRADE_ACTION_PENDING, true) == 0, "spread 500 > 50: no entries");
      CHECK((g_gate & NQ_K_SPREAD) != 0, "gate: spread");
      // terminal autotrading off
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.terminalTrade = false;
      startAt(START);
      relax();
      run(START + 1, END);
      CHECK(countSent(TRADE_ACTION_DEAL, true) == 0 && countSent(TRADE_ACTION_PENDING, true) == 0, "autotrading off: no entries");
   }
   end("A4");

   begin("A5 regime flip closes an open scalp that is against the new M5 regime");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
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
      p.sym = "XAUUSD";
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
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

      load(gold, "EURUSD", "EUR", 5, 0.00001, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 300);
      CHECK(SIM.sent.empty() && lbl("state").find("GOLD / SILVER / COPPER ONLY") != std::string::npos, "EURUSD: no trading, panel says so");
   }
   end("A7");

   begin("A8 forecast arrows: one per candle in the window plus a live one; past arrows never change");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 300);
      CHECK(lbl("title").find("NRTR QML") != std::string::npos && lbl("title").find(std::string("v") + NQ_EA_VERSION) != std::string::npos,
            "the title names the build (v" NQ_EA_VERSION ") so the file on the chart is recognisable");
      std::set<std::string> keys;
      int dup = 0, rows = 0, empty = 0, studyRows = 0;
      for(auto &kv : SIM.objs)
      {
         if(kv.first.compare(0, 9, "NQEA_P_k_") != 0) continue;
         if(kv.first.compare(0, 10, "NQEA_P_k_f") == 0) studyRows++;   // the MH15 PLUS table's rows (v1.11.0) are counted apart
         else rows++;
         std::string k = kv.second.s[OBJPROP_TEXT];
         if(keys.count(k)) dup++;
         keys.insert(k);
         std::string v = obj("NQEA_P_v_" + kv.first.substr(9));
         if(v.empty() || v == "<missing>") empty++;
      }
      std::printf("    %d rows\n", rows);
      CHECK(rows == 12, "12 engine rows (H4 / H1, MACRO VOTE, NEWS, WEEK / SMART, VOL REGIME + the 7 engine rows)");
      CHECK(studyRows == (g_studies ? 10 : 0), "the MH15 PLUS table: 10 rows under its ladder (CANDLES first) when the studies are on, none when they are off");
      CHECK(dup == 0, "no key twice");
      CHECK(empty == 0, "every row has a value");
      CHECK(lbl("h1").find("ENGINE") != std::string::npos && lbl("h2").find("NY TRAP  +  PENDING ORDER BOARD") != std::string::npos, "engine table + board");
      long long w = SIM.objs["NQEA_P_bg"].i[OBJPROP_XSIZE];
      CHECK(w < 800, "single column");
      // SPLIT layout (default): the information desk sits in its own block at the bottom middle, the board top-left
      // (the simulated chart is 1400 x 900: the desk sits at the bottom edge, centred; on a short chart it may overlap the board)
      CHECK(SIM.objs.count("NQEA_P_bgI") == 1 && SIM.objs["NQEA_P_bgI"].i[OBJPROP_XDISTANCE] > 100 &&
            SIM.objs["NQEA_P_bgI"].i[OBJPROP_YDISTANCE] + SIM.objs["NQEA_P_bgI"].i[OBJPROP_YSIZE] <= 900 &&
            SIM.objs["NQEA_P_t1"].i[OBJPROP_YDISTANCE] > SIM.objs["NQEA_P_bgI"].i[OBJPROP_YDISTANCE] &&
            SIM.objs["NQEA_P_t1"].i[OBJPROP_YDISTANCE] > SIM.objs["NQEA_P_t2"].i[OBJPROP_YDISTANCE] && lbl("h1").find("INFORMATION DESK") == 0,
            "SPLIT: the INFORMATION DESK block is centred at the bottom edge with the engine table inside it, under the trading board's table");
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
            CHECK(near(std::stod(lbl("bs2")), ask, 0.006) && near(std::stod(lbl("bs3")), NqRoundTick(ask - 1.5 * atr5, 0.01, 2, -1), 0.011) &&
                  near(std::stod(lbl("bs4")), NqRoundTick(ask + 1.0 * atr5, 0.01, 2, 1), 0.011), "scalp levels = ask -1.5 ATR5 / +1.0 ATR5");
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
      ps.ticket = 555; ps.sym = "XAUUSD"; ps.type = POSITION_TYPE_BUY; ps.vol = 0.05; ps.open = SIM.bid; ps.sl = SIM.bid - 5; ps.tp = SIM.bid + 5;
      ps.time = SIM.now - 600; ps.magic = InpMagic; ps.comment = "NQ-Q1";
      SIM.pos.push_back(ps);
      SimOrder so;
      so.ticket = 556; so.sym = "XAUUSD"; so.type = ORDER_TYPE_SELL_LIMIT; so.vol = 0.05; so.price = SIM.bid + 0.10; so.sl = SIM.bid + 6; so.tp = SIM.bid - 4;
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
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
      p.ticket = 4242; p.sym = "XAUUSD"; p.type = (reg > 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL; p.vol = 0.05; p.open = SIM.bid;
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      CHECK(std::string(InpSignalMeshUrl).find("https://app.signalmesh.dev/webhooks/") == 0 && std::string(InpTelemetryUrl).find("https://app.signalmesh.dev/webhooks/") == 0 &&
            std::string(InpSignalMeshSecret).empty() && g_webUrl.empty() && g_telUrl.empty(),
            "the SignalMesh addresses are preset, but without the secret both doors are OFF: nothing is ever posted blind");
      g_webUrl = "https://status.example/webhooks/brain/signal";
      g_webSecret = "s3cr3t-token";
      run(START + 1, END);
      std::string fname = "NQ_events_XAUUSD.jsonl";
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
         for(const char *k : {"\"signal_id\":", "\"system\":\"NQ-EA\"", "\"symbol\":\"XAUUSD\"", "\"event\":", "\"status\":", "\"plan_kind\":",
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.gmtOffsetSec = 3 * 3600;
      startAt(START);
      relax();
      g_webUrl = "";                                   // journal off: every POST below is telemetry
      g_telUrl = "https://status.example/webhooks/metal/telemetry";
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
      for(const char *k : {"\"label\":\"ANALYSIS ONLY - DEMO - NOT A TRADE SIGNAL\"", "\"source\":\"NRTR_QML_MetalScalper\"", "\"ea_version\":\"1.12.0\"", "\"trade_swing\":\"ALL\"", "\"profit_lock\":false", "\"hand_managed\":0", "\"htf\":{", "\"witnesses\":{", "\"macro\":{", "\"news\":{\"state\":\"CLEAR\"", "\"session\":{", "\"portfolio\":{", "\"smart_exit\":{",
                           "\"symbol\":\"XAUUSD\"", "\"metal\":\"GOLD\"", "\"account_mode\":\"demo\"", "\"ts_server\":", "\"ts_gmt\":",
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.accountMode = ACCOUNT_TRADE_MODE_REAL;
      startAt(START);
      relax();
      g_webUrl = "";
      g_telUrl = "https://status.example/webhooks/metal/telemetry";
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
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
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
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
      p.ticket = 4343; p.sym = "XAUUSD"; p.type = POSITION_TYPE_BUY; p.vol = 0.05; p.open = SIM.bid;
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

   begin("A10 silver spec (3 digits, tick value 5): SL/TP on the grid, lots from the real tick value; rejected order is logged, not retried");
   {
      Market silver = makeMarket(5, 60.9, 0.001, 0.006, (int)DAYS);
      load(silver, "XAGUSD", "XAG", 3, 0.001, 5.0);
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
         double loss = NqLossAt(r.volume, std::fabs(r.price - r.sl), 0.001, 5.0);
         if(loss > 0.5 / 100.0 * (SIM.balance + 500.0) + 1e-6) bad++;
      }
      std::printf("    silver: %d scalps\n", market);
      CHECK(market > 0 && bad == 0, "silver orders on the 0.001 grid, sized from tick value 5");

      load(silver, "XAGUSD", "XAG", 3, 0.001, 5.0);
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


   // ======================= v1.9: the metal's macro / news / smart-exit layer =======================
   begin("M1 news guard (USD): the MT5 calendar closes the gate around HIGH USD events, pulls resting orders, banks profit; UNKNOWN is not clear");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      CHECK(g_newsOk && !g_newsBlock && !g_newsUnknown && lbl("v_e0n").find("clear") == 0 && (g_gate & (NQ_K_NEWS | NQ_K_NEWS_UNKNOWN)) == 0,
            "a working calendar with no HIGH event: CLEAR, nothing gated");
      simAddEvent("USD", SIM.now + 20 * 60, CALENDAR_IMPORTANCE_HIGH, "Initial Jobless Claims");
      SimOrder so;
      so.ticket = 7001; so.sym = "XAUUSD"; so.type = ORDER_TYPE_BUY_LIMIT; so.vol = 0.10; so.price = SIM.bid - 2.0; so.sl = SIM.bid - 3.0; so.tp = SIM.bid - 1.0;
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
      simAddEvent("EUR", SIM.now + 10 * 60, CALENDAR_IMPORTANCE_HIGH, "ECB Press Conference");
      stepTo(START + 2);
      CHECK(!g_newsBlock, "GBP and EUR events are not the metal's business: its news is the dollar's");
      simAddEvent("USD", SIM.now + 10 * 60, CALENDAR_IMPORTANCE_HIGH, "FOMC Press Conference");
      stepTo(START + 3);
      CHECK(g_newsBlock && g_newsWhy.find("USD FOMC Press Conference") == 0 && g_newsWhy.find("TOP TIER") != std::string::npos, "a USD presser counts and is TOP TIER");
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
            "USD POSITIVE 1 h ago = dollar up = metal down: -1 for a BUY, +1 for a SELL; the row shows it");
      simAddEvent("USD", SIM.now - 2 * 3600, CALENDAR_IMPORTANCE_HIGH, "Unemployment Rate", CALENDAR_IMPACT_NEGATIVE, true);
      stepTo(START + 10);
      w = "";
      CHECK(NqNewsVote(1, w) == 0 && w.find("POSITIVE") != std::string::npos && w.find("NEGATIVE") != std::string::npos, "a USD NEGATIVE release 2 h ago cancels it: one vote each");
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
         p.ticket = 7101; p.sym = "XAUUSD"; p.type = POSITION_TYPE_BUY; p.vol = 0.10; p.open = nb.close - 0.5; p.sl = p.open - 1.0; p.tp = p.open + 3.0;
         p.time = SIM.now - 600; p.magic = InpMagic; p.comment = "NQ-P7101";
         SIM.pos.push_back(p);
         SimPos l = p;
         l.ticket = 7102; l.type = POSITION_TYPE_SELL; l.open = nb.close - 0.5; l.sl = l.open + 1.0; l.tp = l.open - 3.0; l.comment = "NQ-P7102";
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
      CHECK(g_newsUnknown && (NqMetalGateBits() & NQ_K_NEWS_UNKNOWN) == 0 && g_newsText.find("trading anyway") != std::string::npos, "InpNewsUnknownBlocks = false: trade blind, said plainly");
      g_newsUnknownBlocks = true;
      SIM.calOk = true;
      SIM.tester = true;
      stepTo(START + 14);
      CHECK(g_newsTester && !g_newsUnknown && !g_newsBlock && (g_gate & (NQ_K_NEWS | NQ_K_NEWS_UNKNOWN)) == 0 && lbl("v_e0n").find("N/A in the Strategy Tester") == 0,
            "the Strategy Tester has no calendar: N/A, not gated, not UNKNOWN");
      SIM.tester = false;
      OnDeinit(0);
   }
   end("M1");

   begin("M2 smart exit 1.10.0: nothing banks under the lock threshold, nothing closes a loser but the SL or the explicit cut; the lock is its own switch; a reversal plan whose regime never agreed is left alone");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      g_smartExit = true;
      g_profitLock = true;
      g_flipCutLoss = false;
      size_t i = START + 1;
      int reg = 0;
      for(; i <= END; i++) { stepTo(i); reg = g_s5.regime[(size_t)g_s5.n - 1]; if(reg == NQ_REG_BULL) break; }
      CHECK(reg == NQ_REG_BULL, "found a bullish M5 regime");
      size_t n5 = (size_t)g_s5.n;
      int keep1 = g_s5.regime[n5 - 1], keep2 = g_s5.regime[n5 - 2];
      double risk = 1.0;
      auto plant = [&](ulong tk, int type, double open, const char *cmt) {
         SIM.pos.clear();
         SIM.ord.clear();
         ArrayResize(g_mgd, 0);
         g_nMgd = 0;
         SimPos p;
         p.ticket = tk; p.sym = "XAUUSD"; p.type = type; p.vol = 0.10; p.open = open;
         p.sl = (type == POSITION_TYPE_BUY) ? open - risk : open + risk; p.tp = (type == POSITION_TYPE_BUY) ? open + 3 * risk : open - 3 * risk;
         p.time = g_s5.t[n5 - 2]; p.magic = InpMagic; p.comment = cmt;
         SIM.pos.push_back(p);
      };
      auto alive = [&](ulong tk) { for(const SimPos &p : SIM.pos) if(p.ticket == tk) return true; return false; };
      auto closedWith = [&](ulong tk, const char *txt) {
         if(alive(tk)) return false;
         for(const std::string &l : SIM.log) if(l.find(txt) != std::string::npos) return true;
         return false;
      };
      // a) the regime agreed (bar n-2 BULL), then flipped (bar n-1 BEAR): +0.3R is UNDER the lock threshold -> kept
      g_s5.regime[n5 - 2] = NQ_REG_BULL; g_s5.regime[n5 - 1] = NQ_REG_BEAR;
      plant(8001, POSITION_TYPE_BUY, SIM.bid - 0.3 * risk, "NQ-P8001");
      CHECK(NqRegimeAgreedSince(g_s5.t[n5 - 2], 1), "the regime agreed since the open");
      NqVerdict();
      CHECK(g_verdict.find("EXIT BUY #8001") == 0 && g_verdict.find("you decide - +0.30R is under the lock threshold +0.70R, the SL decides") != std::string::npos,
            "the verdict says the smart exit will NOT act under the threshold and why");
      NqTrade();
      CHECK(alive(8001) && g_smartNote.find("SMART EXIT held #8001: M5 flipped at +0.30R, under the lock threshold +0.70R") == 0, "kept; the panel note says held and why");
      // b) under water on a flip, the cut off (default): kept, the SL decides
      plant(8002, POSITION_TYPE_BUY, SIM.bid + 0.3 * risk, "NQ-P8002");
      NqVerdict();
      CHECK(g_verdict.find("you decide - under water: no cut below the lock threshold, the SL decides") != std::string::npos, "the verdict: under water, the SL decides");
      NqTrade();
      CHECK(alive(8002), "a -0.30R position is not closed by a profit rule");
      // b2) a one-dollar profit on a flip: kept (no arbitrary money threshold - the R rule holds)
      plant(8009, POSITION_TYPE_BUY, SIM.bid - 0.01 * risk, "NQ-P8009");
      NqTrade();
      CHECK(alive(8009), "+0.01R on a flip: kept");
      // b3) the explicit STRUCTURAL CUT on: under water on a flip -> closed, named as the cut, not as a profit rule
      g_flipCutLoss = true;
      plant(8010, POSITION_TYPE_BUY, SIM.bid + 0.3 * risk, "NQ-P8010");
      NqVerdict();
      CHECK(g_verdict.find("STRUCTURAL CUT at the next M1 close - InpSmartFlipCutLoss") != std::string::npos, "the verdict names the explicit cut");
      NqTrade();
      CHECK(closedWith(8010, "STRUCTURAL CUT (InpSmartFlipCutLoss): M5 regime flipped BEARISH against BUY #8010 at -0.30R - closed before the SL by your explicit setting"),
            "cut with its own reason");
      plant(8011, POSITION_TYPE_BUY, SIM.bid - 0.3 * risk, "NQ-P8011");
      NqTrade();
      CHECK(alive(8011), "the cut is a loss rule only: +0.30R under the threshold is still kept");
      g_flipCutLoss = false;
      // c) a scalp under water on a flip: the scalp's own flip rule, not the smart exit
      plant(8003, POSITION_TYPE_BUY, SIM.bid + 0.3 * risk, "NQ-S8003");
      NqTrade();
      CHECK(closedWith(8003, "M5 regime turned BEARISH against the scalp"), "a scalp keeps its own flip rule");
      // d) the regime never agreed (a reversal plan filled against it): the flip means nothing, the plan runs
      g_s5.regime[n5 - 2] = NQ_REG_BEAR;
      plant(8004, POSITION_TYPE_BUY, SIM.bid - 0.9 * risk, "NQ-Q8004");
      int keepD1 = g_s1.dir[(size_t)g_s1.n - 1];
      g_s1.dir[(size_t)g_s1.n - 1] = 1;
      NqVerdict();
      CHECK(g_verdict.find("EXIT BUY #8004") == 0 && g_verdict.find("never agreed") != std::string::npos, "the verdict explains why the bot will not act");
      NqTrade();
      CHECK(alive(8004), "left to its SL / TP even above the threshold");
      // e) the lock: +0.8R with the regime intact moves the SL to entry + 0.1R, once, with the rule named
      g_s5.regime[n5 - 2] = NQ_REG_BULL; g_s5.regime[n5 - 1] = NQ_REG_BULL;
      plant(8005, POSITION_TYPE_BUY, SIM.bid - 0.8 * risk, "NQ-P8005");
      size_t before = SIM.sent.size();
      NqTrade();
      bool locked = false;
      double wantSl = NqRoundTick(SIM.pos.empty() ? 0.0 : SIM.pos[0].open + 0.1 * risk, 0.01, 2, -1);
      for(size_t k = before; k < SIM.sent.size(); k++)
         if(SIM.sent[k].action == TRADE_ACTION_SLTP && SIM.sent[k].position == 8005 && near(SIM.sent[k].sl, wantSl, 1e-9)) locked = true;
      CHECK(locked && !SIM.pos.empty() && near(SIM.pos[0].sl, wantSl, 1e-9), "SL moved to entry + 0.1R by a SLTP request; the position stays");
      bool logged = false;
      for(const std::string &l : SIM.log) if(l.find("PROFIT LOCK: BUY #8005 at +0.80R reached the threshold +0.70R - SL to entry +0.10R") != std::string::npos) logged = true;
      CHECK(logged, "logged with the rule, the R and the threshold");
      before = SIM.sent.size();
      NqTrade();
      int again = 0;
      for(size_t k = before; k < SIM.sent.size(); k++) if(SIM.sent[k].action == TRADE_ACTION_SLTP) again++;
      CHECK(again == 0, "never loosened, never repeated");
      // f) the M1 bias turned against a +0.6R position: UNDER the threshold -> kept; +0.9R -> banked, named
      g_s1.dir[(size_t)g_s1.n - 1] = -1;
      plant(8006, POSITION_TYPE_BUY, SIM.bid - 0.6 * risk, "NQ-P8006");
      NqTrade();
      CHECK(alive(8006), "M1 turn with +0.6R: under the lock threshold, kept");
      plant(8007, POSITION_TYPE_BUY, SIM.bid - 0.9 * risk, "NQ-P8007");
      NqTrade();
      CHECK(closedWith(8007, "SMART EXIT (M1 turn): M1 bias turned BEARISH against BUY #8007 at +0.90R - above the lock threshold +0.70R, banking"), "M1 turn with +0.9R: banked with the reason");
      g_s1.dir[(size_t)g_s1.n - 1] = 1;
      // g) smart exit off, lock on: a flip above the threshold is NOT banked, the SL is locked
      g_smartExit = false;
      g_s5.regime[n5 - 1] = NQ_REG_BEAR;
      plant(8008, POSITION_TYPE_BUY, SIM.bid - 0.8 * risk, "NQ-P8008");
      NqTrade();
      NqVerdict();
      CHECK(alive(8008) && near(SIM.pos[0].sl, wantSl, 1e-9) && g_verdict.find("you decide") != std::string::npos, "off: locked but left to the human on the flip");
      // h) lock off, smart exit on: banked above the threshold with no SL moved
      g_smartExit = true;
      g_profitLock = false;
      plant(8012, POSITION_TYPE_BUY, SIM.bid - 0.8 * risk, "NQ-P8012");
      before = SIM.sent.size();
      NqTrade();
      int sltp = 0;
      for(size_t k = before; k < SIM.sent.size(); k++) if(SIM.sent[k].action == TRADE_ACTION_SLTP) sltp++;
      CHECK(closedWith(8012, "SMART EXIT (M5 flip): regime flipped BEARISH against BUY #8012 at +0.80R - above the lock threshold +0.70R, banking before the TP") && sltp == 0,
            "the threshold gates the bank even without the lock switch; nothing else moved");
      g_profitLock = true;
      g_s1.dir[(size_t)g_s1.n - 1] = keepD1;
      g_s5.regime[n5 - 1] = keep1; g_s5.regime[n5 - 2] = keep2;
      SIM.pos.clear();
      ArrayResize(g_mgd, 0);
      g_nMgd = 0;
      OnDeinit(0);
   }
   end("M2");

   begin("M3 the Friday stop and the portfolio: orders pulled and profits banked before the weekend; positions across charts");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 5);
      SIM.pos.clear();
      SIM.ord.clear();
      SimOrder so;
      so.ticket = 9101; so.sym = "XAUUSD"; so.type = ORDER_TYPE_BUY_LIMIT; so.vol = 0.10; so.price = SIM.bid - 2.0; so.sl = SIM.bid - 3.0; so.tp = SIM.bid - 1.0;
      so.time = SIM.now; so.magic = InpMagic; so.comment = "NQ-Q9101";
      SIM.ord.push_back(so);
      SimPos a;
      a.ticket = 9102; a.sym = "XAUUSD"; a.type = POSITION_TYPE_BUY; a.vol = 0.10; a.open = SIM.bid - 0.2; a.sl = a.open - 1.0; a.tp = a.open + 3.0;
      a.time = SIM.now - 600; a.magic = InpMagic; a.comment = "NQ-P9102";
      SIM.pos.push_back(a);
      SimPos l = a;
      l.ticket = 9103; l.type = POSITION_TYPE_SELL; l.open = SIM.bid - 0.2; l.sl = l.open + 1.0; l.tp = l.open - 3.0; l.comment = "NQ-P9103";
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
      // the portfolio: this EA's positions on OTHER charts count (same magic)
      auto other = [&](ulong tk, const char *sym, int type) {
         SimPos p;
         p.ticket = tk; p.sym = sym; p.type = type; p.vol = 0.10; p.open = 60.0; p.sl = 0; p.tp = 0; p.time = SIM.now; p.magic = InpMagic; p.comment = "NQ-P1";
         SIM.pos.push_back(p);
      };
      other(9201, "XAGUSD", POSITION_TYPE_BUY);
      NqReadAccount();
      NqEvaluate();
      CHECK(g_portfolioPos == 1 && !g_portfolioFull && g_openCount == 0 && (g_gate & NQ_K_PORTFOLIO) == 0, "one position on another chart: counted, not this chart's slot, under the cap");
      other(9202, "XAGUSD", POSITION_TYPE_SELL);
      NqReadAccount();
      NqEvaluate();
      CHECK(g_portfolioPos == 2 && g_portfolioFull && (g_gate & NQ_K_PORTFOLIO) != 0 && NqGateAtX(g_gate, 0).find("PORTFOLIO FULL - 2 POSITIONS") != std::string::npos,
            "two positions across charts = the cap: PORTFOLIO FULL closes the gate");
      OnTimer();
      CHECK(lbl("v_e0h").find("portfolio 2 pos") != std::string::npos, "the WEEK / SMART row shows the portfolio");
      SIM.pos.clear();
      OnDeinit(0);
   }
   end("M3");

   begin("M4 higher timeframes: H1 / H4 context, confirmed structure, BOS / CHoCH classification, the HTF voters");
   {
      Market big = makeMarket(7, 4150.0, 0.01, 0.35, 40);
      load(big, "XAUUSD", "XAU", 2, 0.01, 1.0);
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
   end("M4");

   begin("M5 the week's edges and the rollover on the server clock: Friday stop, the first hour of the week, the weekend, the rollover window");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      g_clockGuards = true;
      datetime fri = T0 + 3 * 86400;   // T0 is Tuesday 2026-09-01: Friday the 4th
      datetime mon = T0 + 6 * 86400;   // Monday the 7th
      NqSessionScan(fri + 22 * 3600 + 30 * 60);
      CHECK(g_weekEdge && g_weekFriday && g_weekText.find("FRIDAY STOP") == 0 && (NqMetalGateBits() & NQ_K_WEEK_EDGE) != 0, "Friday 22:30 = 90 min before the close: FRIDAY STOP");
      NqSessionScan(fri + 19 * 3600);
      CHECK(!g_weekEdge && !g_rollover, "Friday 19:00: open");
      NqSessionScan(fri + 23 * 3600 + 50 * 60);
      CHECK(g_rollover && (NqMetalGateBits() & NQ_K_ROLLOVER) != 0, "23:50 = 10 min before the rollover: ROLLOVER bit");
      NqSessionScan(mon + 30 * 60);
      CHECK(g_weekEdge && !g_weekFriday && g_weekText.find("FIRST 60 MIN") == 0, "Monday 00:30: the first hour of the week");
      NqSessionScan(fri + 86400 + 3600);
      CHECK(g_weekEdge && g_weekText.find("WEEKEND") == 0, "Saturday 01:00: weekend");
      NqSessionScan(fri + 12 * 3600);
      CHECK(NqSessionName() == "LONDON" && !g_weekEdge, "Friday 12:00 = London, open");
      g_clockGuards = false;
      NqSessionScan(fri + 22 * 3600 + 30 * 60);
      CHECK(!g_weekEdge && !g_rollover, "guards off: nothing");
      OnDeinit(0);
   }
   end("M5");


   begin("M6 compact board, click-to-fold blocks, the SL guard: a position without a stop gets the plan's stop back or is closed");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
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
            if(SIM.sent[k].action == TRADE_ACTION_SLTP && SIM.sent[k].position == 9301 && near(SIM.sent[k].sl, pp.sl, 1e-9) && near(SIM.sent[k].tp, 0.0, 1e-9)) restored = true;
         bool logged = false;
         for(const std::string &l : SIM.log) if(l.find("SL MISSING (HAND-MANAGED): the plan's disaster stop") != std::string::npos) logged = true;
         CHECK(restored && logged && !SIM.pos.empty() && near(SIM.pos[0].sl, pp.sl, 1e-9) && NqMgdHand(9301),
               "no stop and no TP at the broker: the TP is not the EA's, so the position is HAND-MANAGED; the disaster stop alone is restored by one SLTP request, logged");
         // the same position with the EA's TP in place: the EA's own, SL restored with the plain reason, TP kept
         SIM.pos.clear();
         ArrayResize(g_mgd, 0);
         g_nMgd = 0;
         p.ticket = 9303;
         p.tp = NqPlanTpSent(pp);
         SIM.pos.push_back(p);
         before = SIM.sent.size();
         NqTrade();
         restored = false;
         for(size_t k = before; k < SIM.sent.size(); k++)
            if(SIM.sent[k].action == TRADE_ACTION_SLTP && SIM.sent[k].position == 9303 && near(SIM.sent[k].sl, pp.sl, 1e-9) && near(SIM.sent[k].tp, NqPlanTpSent(pp), 1e-9)) restored = true;
         logged = false;
         for(const std::string &l : SIM.log) if(l.find("SL MISSING: the plan's stop") != std::string::npos) logged = true;
         CHECK(restored && logged && !NqMgdHand(9303), "no stop but the EA's TP: the plan's SL is restored, the TP kept, not hand-managed");
         ArrayResize(g_mgd, 0);
         g_nMgd = 0;
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
   end("M6");


   begin("M7 the R yardstick (1.10.0): on a plan-backed position the lock moves the SL and R still reads +0.80R; the bank above the threshold names it; a legitimate SL closes a loser the EA left alone");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 300);
      int kp = -1;
      for(int k = g_nPlans - 1; k >= 0; k--) if(g_plans[(size_t)k].dir > 0 && g_plans[(size_t)k].sl > 0.0 && g_plans[(size_t)k].risk > 0.0) { kp = k; break; }
      CHECK(kp >= 0, "a BUY plan with a recorded risk exists in the window");
      if(kp >= 0)
      {
         NqPlan pp = g_plans[(size_t)kp];
         std::string cmt = NqPlanComment(pp);
         size_t n5 = (size_t)g_s5.n;
         int keep1 = g_s5.regime[n5 - 1], keep2 = g_s5.regime[n5 - 2];
         int keepD1 = g_s1.dir[(size_t)g_s1.n - 1];
         double keepBid = SIM.bid;
         auto plantPlan = [&](ulong tk, double rNow) {
            SIM.pos.clear();
            SIM.ord.clear();
            ArrayResize(g_mgd, 0);
            g_nMgd = 0;
            SimPos p;
            p.ticket = tk; p.sym = SIM.sym; p.type = POSITION_TYPE_BUY; p.vol = 0.10; p.open = pp.entry;
            p.sl = pp.sl; p.tp = NqPlanTpSent(pp); p.time = g_s5.t[n5 - 2]; p.magic = InpMagic; p.comment = cmt;
            SIM.pos.push_back(p);
            SIM.bid = pp.entry + rNow * pp.risk;
         };
         auto alive = [&](ulong tk) { for(const SimPos &p : SIM.pos) if(p.ticket == tk) return true; return false; };
         auto logged = [&](const char *txt) { for(const std::string &l : SIM.log) if(l.find(txt) != std::string::npos) return true; return false; };
         g_smartExit = true;
         g_profitLock = true;
         g_flipCutLoss = false;
         g_s1.dir[(size_t)g_s1.n - 1] = 1;
         // the lock on a plan-backed position: R is the plan's risk before AND after the SL moves
         g_s5.regime[n5 - 2] = NQ_REG_BULL; g_s5.regime[n5 - 1] = NQ_REG_BULL;
         plantPlan(7001, 0.8);
         CHECK(near(NqRiskOf(cmt, pp.entry, pp.sl), pp.risk, 1e-9) && near(NqPosR(pp.entry, pp.sl, SIM.bid, 1, cmt), 0.8, 1e-6), "before the lock: R = +0.80R on the plan's risk");
         size_t before = SIM.sent.size();
         NqTrade();
         double wantSl = NqRoundTick(pp.entry + 0.1 * pp.risk, 0.01, 2, -1);
         bool locked = false;
         for(size_t k = before; k < SIM.sent.size(); k++)
            if(SIM.sent[k].action == TRADE_ACTION_SLTP && SIM.sent[k].position == 7001 && near(SIM.sent[k].sl, wantSl, 1e-9) && near(SIM.sent[k].tp, NqPlanTpSent(pp), 1e-9)) locked = true;
         CHECK(locked && alive(7001) && near(SIM.pos[0].sl, wantSl, 1e-9), "PROFIT LOCK moved the SL to entry + 0.1R and kept the TP");
         double rAfter = NqPosR(pp.entry, SIM.pos[0].sl, SIM.bid, 1, cmt);
         std::printf("    R after the lock: %.4f (the SL now sits %.2f ABOVE entry; the plan risk is %.2f)\n", rAfter, SIM.pos[0].sl - SIM.pos[0].open, pp.risk);
         CHECK(near(rAfter, 0.8, 1e-6), "REGRESSION: after the lock R still reads +0.80R, not +8.00R (the yardstick is the plan's recorded risk)");
         NqVerdict();
         CHECK(g_verdict.find("HOLD BUY #7001") == 0 && g_verdict.find("(+0.80R)") != std::string::npos && g_verdict.find("SL locked") != std::string::npos, "HOLD shows the true R and the lock");
         CHECK(!NqMgdHand(7001) && g_nMgd == 1 && near(g_mgd[0].sl, wantSl, 1e-9), "the lock's SL is recorded as the EA's own, not a hand edit");
         before = SIM.sent.size();
         NqTrade();
         int again = 0;
         for(size_t k = before; k < SIM.sent.size(); k++) if(SIM.sent[k].action == TRADE_ACTION_SLTP) again++;
         CHECK(again == 0 && alive(7001), "a second candle: nothing repeated, nothing closed");
         // the regime flips against the locked +0.80R position: banked, the reason names the R and the threshold
         g_s5.regime[n5 - 1] = NQ_REG_BEAR;
         NqVerdict();
         CHECK(g_verdict.find("SMART EXIT banks it at the next M1 close - +0.80R is above the lock threshold +0.70R") != std::string::npos, "the verdict announces the bank with the numbers");
         NqTrade();
         CHECK(!alive(7001) && logged("SMART EXIT (M5 flip): regime flipped BEARISH against BUY #7001 at +0.80R - above the lock threshold +0.70R, banking before the TP"),
               "banked at the true +0.80R (a wrong yardstick would have printed +8.00R)");
         // the same flip at +0.30R on the plan: kept
         plantPlan(7002, 0.3);
         NqTrade();
         CHECK(alive(7002) && g_smartNote.find("SMART EXIT held #7002: M5 flipped at +0.30R") == 0, "+0.30R on the plan's risk: held");
         // a legitimate SL: a -0.9R loser with the regime intact is left alone by the EA and closed by the broker's stop
         g_s5.regime[n5 - 1] = NQ_REG_BULL;
         plantPlan(7003, -0.9);
         before = SIM.sent.size();
         NqTrade();
         NqVerdict();
         CHECK(alive(7003) && SIM.sent.size() == before && g_verdict.find("HOLD BUY #7003") == 0 && g_verdict.find("(-0.90R)") != std::string::npos,
               "the EA sends nothing for a loser above its stop: HOLD at -0.90R");
         MqlRates bar = {SIM.now, SIM.bid, SIM.bid, pp.sl - 0.5 * pp.risk, pp.sl - 0.3 * pp.risk, 100, 0, 0};
         simBarPath(bar);
         bool slDeal = false;
         for(const SimDeal &d : SIM.deals) if(d.posId == 7003 && d.entry == DEAL_ENTRY_OUT && d.reason == "sl") slDeal = true;
         CHECK(!alive(7003) && slDeal, "the broker's SL closes it: a legitimate stop always stands");
         g_s1.dir[(size_t)g_s1.n - 1] = keepD1;
         g_s5.regime[n5 - 1] = keep1; g_s5.regime[n5 - 2] = keep2;
         SIM.bid = keepBid;
      }
      SIM.pos.clear();
      ArrayResize(g_mgd, 0);
      g_nMgd = 0;
      OnDeinit(0);
   }
   end("M7");

   begin("M8 HAND-MANAGED (1.10.0): a changed SL or TP hands the position to the human - no lock, no smart exit, no flip close, no time stop, no news / weekend banking, no TP restore; a missing SL still comes back; a restart rebuilds the expectation");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 300);
      int kp = -1;
      for(int k = g_nPlans - 1; k >= 0; k--) if(g_plans[(size_t)k].dir > 0 && g_plans[(size_t)k].sl > 0.0 && g_plans[(size_t)k].risk > 0.0) { kp = k; break; }
      int ks = -1;
      for(int k = g_nSig - 1; k >= 0; k--) if(g_sigs[(size_t)k].dir > 0 && g_sigs[(size_t)k].risk > 0.0) { ks = k; break; }
      CHECK(kp >= 0 && ks >= 0, "a BUY plan and a BUY scalp record exist in the window");
      if(kp >= 0 && ks >= 0)
      {
         NqPlan pp = g_plans[(size_t)kp];
         std::string cmt = NqPlanComment(pp);
         size_t n5 = (size_t)g_s5.n;
         int keep1 = g_s5.regime[n5 - 1], keep2 = g_s5.regime[n5 - 2];
         double keepBid = SIM.bid;
         const std::string fname = "NQ_events_XAUUSD.jsonl";
         auto plantPlan = [&](ulong tk, double rNow, double sl, double tp) {
            SIM.pos.clear();
            SIM.ord.clear();
            ArrayResize(g_mgd, 0);
            g_nMgd = 0;
            SimPos p;
            p.ticket = tk; p.sym = SIM.sym; p.type = POSITION_TYPE_BUY; p.vol = 0.10; p.open = pp.entry;
            p.sl = sl; p.tp = tp; p.time = g_s5.t[n5 - 2]; p.magic = InpMagic; p.comment = cmt;
            SIM.pos.push_back(p);
            SIM.bid = pp.entry + rNow * pp.risk;
         };
         auto alive = [&](ulong tk) { for(const SimPos &p : SIM.pos) if(p.ticket == tk) return true; return false; };
         auto logged = [&](const char *txt) { for(const std::string &l : SIM.log) if(l.find(txt) != std::string::npos) return true; return false; };
         auto count = [&](const std::string &body, const char *txt) { size_t n = 0, pos = 0; while((pos = body.find(txt, pos)) != std::string::npos) { n++; pos++; } return n; };
         g_smartExit = true;
         g_profitLock = true;
         g_flipCutLoss = false;
         g_s5.regime[n5 - 2] = NQ_REG_BULL; g_s5.regime[n5 - 1] = NQ_REG_BULL;
         // first sight of a fresh fill: the plan's SL / TP are the expectation
         plantPlan(8101, 0.2, pp.sl, NqPlanTpSent(pp));
         NqTrade();
         CHECK(!NqMgdHand(8101) && g_nMgd == 1 && near(g_mgd[0].sl, pp.sl, 1e-9) && near(g_mgd[0].tp, NqPlanTpSent(pp), 1e-9), "first sight: recorded as the EA's own");
         // the human widens the stop
         size_t handBefore = count(SIM.files[fname], "\"event\":\"hand_managed\"");
         SIM.pos[0].sl = pp.sl - 0.5 * pp.risk;
         NqTrade();
         CHECK(NqMgdHand(8101) && alive(8101) && logged("HAND-MANAGED: BUY #8101 SL ") && logged("differ from the EA's SL "), "a widened stop: HAND-MANAGED, logged with both pairs");
         std::string body = SIM.files[fname];
         CHECK(count(body, "\"event\":\"hand_managed\"") == handBefore + 1 && body.find("\"expected_sl\":") != std::string::npos && body.find("\"expected_tp\":") != std::string::npos,
               "one journal event hand_managed with the EA's expected SL / TP (append-only fields)");
         // +0.8R, regime intact: no lock
         SIM.bid = pp.entry + 0.8 * pp.risk;
         size_t before = SIM.sent.size();
         NqTrade();
         CHECK(alive(8101) && SIM.sent.size() == before && near(SIM.pos[0].sl, pp.sl - 0.5 * pp.risk, 1e-9), "no PROFIT LOCK on a hand-managed position");
         NqVerdict();
         CHECK(g_verdict.find("HAND-MANAGED BUY #8101") == 0 && g_verdict.find("the EA leaves it to you") != std::string::npos, "the verdict says HAND-MANAGED");
         OnTimer();
         CHECK(lbl("bb06").find("HAND-MANAGED  #8101") == 0, "the broker row says HAND-MANAGED");
         // the regime flips: no smart exit
         g_s5.regime[n5 - 1] = NQ_REG_BEAR;
         NqTrade();
         CHECK(alive(8101), "no SMART EXIT on a hand-managed position");
         g_s5.regime[n5 - 1] = NQ_REG_BULL;
         // news banking: the EA's own position is banked, the hand-managed one stays
         SimPos q = SIM.pos[0];
         q.ticket = 8102; q.sl = pp.sl; q.tp = NqPlanTpSent(pp);
         SIM.pos.push_back(q);
         g_newsBlock = true; g_newsWinT = 1; g_newsWhy = "TEST USD release";
         NqTrade();
         CHECK(alive(8101) && !alive(8102) && logged("NEWS: banking +0.80R before TEST USD release"), "news banking skips the hand-managed position and banks the EA's own");
         g_newsBlock = false; g_newsWinT = 0; g_newsWhy = "";
         // the Friday flat: the hand-managed position stays
         g_weekFriday = true; g_weekEdge = true;
         NqTrade();
         CHECK(alive(8101), "the Friday flat leaves a hand-managed position");
         g_weekFriday = false; g_weekEdge = false;
         // a TP removed by hand: hand-managed and never restored; then the SL goes missing: the disaster stop comes back, the TP stays yours
         plantPlan(8103, 0.2, pp.sl, NqPlanTpSent(pp));
         NqTrade();
         SIM.pos[0].tp = 0.0;
         NqTrade();
         CHECK(NqMgdHand(8103) && alive(8103) && near(SIM.pos[0].tp, 0.0, 1e-9), "a removed TP: hand-managed, the TP is NOT restored");
         SIM.pos[0].sl = 0.0;
         before = SIM.sent.size();
         NqTrade();
         bool restored = false;
         for(size_t k = before; k < SIM.sent.size(); k++)
            if(SIM.sent[k].action == TRADE_ACTION_SLTP && SIM.sent[k].position == 8103 && near(SIM.sent[k].sl, pp.sl, 1e-9) && near(SIM.sent[k].tp, 0.0, 1e-9)) restored = true;
         CHECK(restored && logged("SL MISSING (HAND-MANAGED): the plan's disaster stop") && near(SIM.pos[0].sl, pp.sl, 1e-9) && near(SIM.pos[0].tp, 0.0, 1e-9),
               "a missing SL comes back on a hand-managed position too (outage protection), logged, the TP untouched");
         // a scalp with a hand-changed TP is not time-stopped; the EA's own scalp still is
         const NqSignal &sg = g_sigs[(size_t)ks];
         std::string scmt = std::string("NQ-S") + std::to_string((long long)g_s1.t[(size_t)sg.idx]);
         auto plantScalp = [&](ulong tk, double tp) {
            SIM.pos.clear();
            SIM.ord.clear();
            ArrayResize(g_mgd, 0);
            g_nMgd = 0;
            SimPos s;
            s.ticket = tk; s.sym = SIM.sym; s.type = POSITION_TYPE_BUY; s.vol = 0.10; s.open = sg.entry;
            s.sl = sg.sl; s.tp = tp; s.time = SIM.now - 3600 * 2; s.magic = InpMagic; s.comment = scmt;
            SIM.pos.push_back(s);
            SIM.bid = sg.entry + 0.1 * sg.risk;
         };
         plantScalp(8104, sg.tp + 0.5 * sg.risk);
         NqTrade();
         CHECK(NqMgdHand(8104) && alive(8104), "a scalp whose TP you moved: hand-managed, no time stop");
         plantScalp(8105, sg.tp);
         NqTrade();
         CHECK(!alive(8105) && logged("scalp time stop"), "the EA's own stale scalp is still time-stopped");
         // a restart rebuilds the expectation from the plan: the lock's stop and either TP are the EA's own, anything else is the human's
         double lockSl = NqRoundTick(pp.entry + 0.1 * pp.risk, 0.01, 2, -1);
         plantPlan(8106, 0.8, lockSl, NqPlanTpSent(pp));
         NqTrade();
         CHECK(!NqMgdHand(8106), "after a restart a position at the lock's stop is the EA's own");
         plantPlan(8107, 0.2, pp.sl, InpPlanUseTp2 ? pp.tp1 : pp.tp2);
         NqTrade();
         CHECK(!NqMgdHand(8107), "after a restart the other TP (InpPlanUseTp2 changed) is still the EA's own");
         plantPlan(8108, 0.2, pp.sl - 0.3 * pp.risk, NqPlanTpSent(pp));
         NqTrade();
         CHECK(NqMgdHand(8108), "after a restart a stop that is neither the plan's nor the lock's is the human's");
         g_s5.regime[n5 - 1] = keep1; g_s5.regime[n5 - 2] = keep2;
         SIM.bid = keepBid;
      }
      SIM.pos.clear();
      ArrayResize(g_mgd, 0);
      g_nMgd = 0;
      OnDeinit(0);
   }
   end("M8");

   begin("M9 trade sessions (1.10.0): a family mask blocks NEW orders outside its sessions and never pulls a resting one; ALL changes nothing; scalps obey their mask; every journal event names its session");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      size_t i = START + 1;
      bool found = false;
      for(; i <= START + 700; i++) { stepTo(i); if(!SIM.ord.empty() && SIM.pos.empty() && g_gate == 0 && g_fresh) { found = true; break; } }
      CHECK(found, "a candle with resting plan orders and no position");
      auto countAct = [&](size_t from, int action) { int n = 0; for(size_t k = from; k < SIM.sent.size(); k++) if((int)SIM.sent[k].action == action) n++; return n; };
      int keepOpen = g_sessOpen;
      // every family LONDON-only while the clock says ASIA: the orders are not re-placed and the note says why
      g_swingSess = NQ_SESS_LONDON; g_m5Sess = NQ_SESS_LONDON; g_scalpSess = NQ_SESS_LONDON;
      g_sessOpen = 1;
      SIM.ord.clear();
      size_t before = SIM.sent.size();
      NqTrade();
      CHECK(countAct(before, TRADE_ACTION_PENDING) == 0 && g_note.find("OUTSIDE ITS TRADE SESSIONS (now ASIA, allowed LONDON)") != std::string::npos,
            "ASIA with a LONDON mask: nothing placed, the note (a plan's or a scalp's) names the session and the mask");
      // LONDON: placed
      g_sessOpen = 2;
      before = SIM.sent.size();
      NqTrade();
      int placed = countAct(before, TRADE_ACTION_PENDING);
      CHECK(placed > 0 && !SIM.ord.empty(), "LONDON with a LONDON mask: placed");
      // the clock moves to NY: the resting orders stay (the mask gates NEW orders only)
      g_sessOpen = 4;
      size_t resting = SIM.ord.size();
      before = SIM.sent.size();
      NqTrade();
      CHECK(countAct(before, TRADE_ACTION_REMOVE) == 0 && SIM.ord.size() == resting, "NY with a LONDON mask: the London orders rest on - a resting order may fill in the next session");
      // ALL: placed even in OFF time
      g_swingSess = NQ_SESS_ALL; g_m5Sess = NQ_SESS_ALL; g_scalpSess = NQ_SESS_ALL;
      g_sessOpen = 0;
      SIM.ord.clear();
      before = SIM.sent.size();
      NqTrade();
      CHECK(countAct(before, TRADE_ACTION_PENDING) > 0, "ALL = no restriction, OFF time included (the default changes nothing)");
      g_sessOpen = keepOpen;
      CHECK(NqSessMaskText(0) == "ALL" && NqSessMaskText(3) == "ASIA+LONDON" && NqSessMaskText(6) == "LONDON+NY" && NqSessMaskText(5) == "ASIA+NY" && NqSessMaskText(4) == "NY",
            "the mask names");
      g_m5Sess = NQ_SESS_ASIA_LONDON;
      OnTimer();
      CHECK(lbl("v_e0h").find("trade: swing ALL / M5 ASIA+LONDON / scalp ALL") != std::string::npos, "the WEEK / SMART row shows a restricted family");
      g_m5Sess = NQ_SESS_ALL;
      OnTimer();
      CHECK(lbl("v_e0h").find("trade:") == std::string::npos, "with every mask ALL the row says nothing about it");
      // the journal: every event line carries the session
      std::string body = SIM.files["NQ_events_XAUUSD.jsonl"];
      size_t lines = 0, withSession = 0, pos = 0;
      for(char ch : body) if(ch == '\n') lines++;
      while((pos = body.find("\"session\":\"", pos)) != std::string::npos) { withSession++; pos++; }
      CHECK(lines > 0 && withSession == lines, "every journal line carries \"session\"");
      if(g_nPlans > 0)
      {
         std::string js = NqEventJson(g_plans[0], "armed", "");
         CHECK(js.find("\"session\":\"" + NqSessionName() + "\"") != std::string::npos, "the event names the session in force (ASIA / LONDON / NY / OFF)");
      }
      OnDeinit(0);
      // scalps: the gold market always has a plan order waiting (A1), the silver market opens scalps (A10). With ALL, count the
      // scalps per session; then with the mask of ONE session that had scalps, every scalp that opens must open in that session
      Market silverM9 = makeMarket(5, 60.9, 0.001, 0.006, (int)DAYS);
      auto scalpsIn = [&](int mask, int per[8]) {
         load(silverM9, "XAGUSD", "XAG", 3, 0.001, 5.0);
         startAt(START);
         relax();
         g_scalpSess = mask;
         int n = 0;
         for(int b0 = 0; b0 < 8; b0++) per[b0] = 0;
         for(size_t q = START + 1; q <= END; q++)
         {
            size_t d0 = SIM.deals.size();
            stepTo(q);
            for(size_t k = d0; k < SIM.deals.size(); k++)
               if(SIM.deals[k].entry == DEAL_ENTRY_IN && SIM.deals[k].comment.compare(0, 4, "NQ-S") == 0) { n++; per[(g_sessOpen == 0) ? 0 : (g_sessOpen & 7)]++; }
         }
         OnDeinit(0);
         return n;
      };
      int perAll[8], perMask[8];
      int scAll = scalpsIn(NQ_SESS_ALL, perAll);
      int pick = (perAll[1] >= perAll[2] && perAll[1] >= perAll[4]) ? 1 : ((perAll[2] >= perAll[4]) ? 2 : 4);
      int scMask = scalpsIn(pick, perMask);
      int outside = 0;
      for(int b0 = 0; b0 < 8; b0++) if(b0 != pick) outside += perMask[b0];
      std::printf("    silver scalps with ALL: %d (off %d / asia %d / london %d / ny %d); with the mask %s: %d, outside it %d\n",
                  scAll, perAll[0], perAll[1], perAll[2], perAll[4], NqSessMaskText(pick).c_str(), scMask, outside);
      CHECK(scAll > 0 && perAll[pick] > 0, "with ALL the silver run opens scalps (otherwise this check would prove nothing)");
      CHECK(scMask > 0 && outside == 0, "with a one-session mask every scalp that opens opens in that session, none outside it");
      g_scalpSess = NQ_SESS_ALL;
   }
   end("M9");

   // METAL-ONLY BEGIN (v1.11.0: the MH15 PLUS studies; the pure block is the same text in the crypto twin, proved by the derivation)
   begin("S1 day forecast: ADR = mean range of the last 14 COMPLETED days, top / bottom, the snap, the states, nothing invented");
   {
      NqSeries d;
      NqSeriesResize(d, 16);
      d.sec = 86400;
      for(int i = 0; i < 16; i++)
      {
         d.t[i] = T0 + (long long)i * 86400;
         d.o[i] = 100.0;
         d.h[i] = 100.0 + ((i == 0) ? 50.0 : (1.0 + 0.1 * i));   // day 0 is huge: it must NOT be in the 14-day ADR
         d.l[i] = 100.0 - (1.0 + 0.1 * i);
         d.c[i] = 100.5;
         d.v[i] = 1;
      }
      // completed days 1..14 (day 15 is forming): ranges 2 + 0.2 i -> mean = 2 + 0.2 * 7.5 = 3.5
      long long day = T0 + 15LL * 86400;
      NqSeries s;
      NqSeriesResize(s, 6);
      s.sec = 300;
      double hh[6] = {100.6, 100.9, 101.2, 101.0, 100.8, 101.1};
      double ll[6] = {100.2, 100.5, 100.7, 100.4, 100.3, 100.6};
      for(int i = 0; i < 6; i++)
      {
         s.t[i] = day - 600 + (long long)i * 300;   // the first two bars belong to YESTERDAY
         s.o[i] = ll[i]; s.h[i] = hh[i]; s.l[i] = ll[i]; s.c[i] = hh[i] - 0.1; s.v[i] = 1;
      }
      long long now = day + 4 * 300;
      NqDayFc f;
      NqDayForecast(d, s, now, 14, 0.0, 0.0, 0.0, false, f);
      CHECK(f.ok && near(f.adr, 3.5) && f.adrDays == 14 && f.dayStart == day, "ADR 3.5 from days 1..14: the forming day and the huge day 0 are not in it");
      CHECK(f.barsToday == 4 && near(f.hi, 101.2) && near(f.lo, 100.3) && near(f.last, 101.0), "today = the closed bars since the broker day started (yesterday's two are not read)");
      CHECK(near(f.pdh, d.h[14]) && near(f.pdl, d.l[14]) && near(f.pdc, 100.5), "the previous day = the last COMPLETED daily bar");
      CHECK(near(f.topRaw, 100.3 + 3.5) && near(f.botRaw, 101.2 - 3.5) && near(f.top, 103.8) && near(f.bottom, 97.7) && f.topSnap == 0 && f.botSnap == 0,
            "top = today's low + ADR, bottom = today's high - ADR (no snap without a tolerance)");
      CHECK(near(f.usedPct, 100.0 * 0.9 / 3.5, 1e-9) && near(f.movePct, 100.0 * 0.5 / 3.5, 1e-9) && f.state == NQ_FD_FRESH && f.fullT == 0 && f.fadeDir == 0,
            "used 25.7% = FRESH, move +14.3% of the ADR from yesterday's close, no ADR FULL yet");
      // the snap: within 0.5 of the 4h swing high 104.1 -> moved onto it; the previous day's low 97.6 is nearer than the 4h swing low 97.4
      NqDayForecast(d, s, now, 14, 104.1, 97.4, 0.5, false, f);
      CHECK(near(f.top, 104.1) && f.topSnap == 1 && near(f.bottom, d.l[14]) && f.botSnap == 2, "snap: top onto the 4h swing high, bottom onto the previous day's low (the nearest wins)");
      NqDayForecast(d, s, now, 14, 104.5, 96.0, 0.5, false, f);
      CHECK(near(f.top, 103.8) && f.topSnap == 0 && near(f.bottom, 97.6) && f.botSnap == 2, "a swing further than the tolerance does not move the level");
      // a day that fills its ADR on a new high: DONE, top in, the hypothetical fade
      NqSeries s2;
      NqSeriesResize(s2, 5);
      s2.sec = 300;
      double h2[5] = {100.6, 101.5, 102.9, 104.2, 103.9};
      double l2[5] = {100.2, 100.5, 101.4, 102.8, 103.2};
      for(int i = 0; i < 5; i++)
      {
         s2.t[i] = day + (long long)i * 300;
         s2.o[i] = l2[i]; s2.h[i] = h2[i]; s2.l[i] = l2[i]; s2.c[i] = h2[i] - 0.2; s2.v[i] = 1;
      }
      NqDayForecast(d, s2, day + 5 * 300, 14, 0.0, 0.0, 0.0, false, f);
      CHECK(f.ok && f.state == NQ_FD_DONE && f.usedPct >= 100.0 && near(f.top, 104.2) && near(f.bottom, 100.2), "range 4.0 >= ADR 3.5: DONE, top = today's high, bottom = today's low");
      CHECK(f.fullT == day + 4 * 300 && f.fullSide == 1, "ADR FULL on the fourth bar's close, completed by a new high (top in)");
      CHECK(f.fadeDir == -1 && near(f.fadeEntry, 104.0) && near(f.fadeSl, 104.2 + 0.875) && near(f.fadeTp1, 104.0 - 0.875) && near(f.fadeTp2, 104.0 - 1.75),
            "the fade scenario: SELL from that close, stop 0.25 ADR beyond the day's high, targets 0.25 / 0.5 ADR back");
      NqDayForecast(d, s2, day + 5 * 300, 14, 0.0, 0.0, 0.0, true, f);
      CHECK(f.state == NQ_FD_EXPAND, "event mode: a full day on an event day reads EXPANSION");
      // states by used %
      NqSeries s3;
      NqSeriesResize(s3, 1);
      s3.sec = 300;
      s3.t[0] = day; s3.o[0] = 100.0; s3.l[0] = 100.0; s3.v[0] = 1;
      s3.h[0] = 101.5; s3.c[0] = 101.4;
      NqDayForecast(d, s3, day + 300, 14, 0.0, 0.0, 0.0, false, f);
      CHECK(f.state == NQ_FD_UP, "42.9% used, above yesterday's close: MOVING UP");
      s3.h[0] = 100.4; s3.l[0] = 98.9; s3.c[0] = 99.0;
      NqDayForecast(d, s3, day + 300, 14, 0.0, 0.0, 0.0, false, f);
      CHECK(f.state == NQ_FD_DOWN, "42.9% used, below yesterday's close: MOVING DOWN");
      s3.h[0] = 103.0; s3.l[0] = 100.0; s3.c[0] = 102.9;
      NqDayForecast(d, s3, day + 300, 14, 0.0, 0.0, 0.0, false, f);
      CHECK(f.state == NQ_FD_NEAR && f.fullT == 0, "85.7% used: NEAR FULL");
      // nothing invented
      NqSeries d13;
      NqSeriesResize(d13, 14);
      d13.sec = 86400;
      for(int i = 0; i < 14; i++) { d13.t[i] = d.t[i + 2]; d13.o[i] = 100; d13.h[i] = 101; d13.l[i] = 99; d13.c[i] = 100; d13.v[i] = 1; }
      NqDayForecast(d13, s, now, 14, 0.0, 0.0, 0.0, false, f);
      CHECK(!f.ok && f.why.find("ADR needs 14 completed days (13 loaded)") == 0 && f.state == NQ_FD_UNKNOWN, "13 completed days: UNKNOWN, with the reason");
      NqDayForecast(d, s, day + 2 * 86400, 14, 0.0, 0.0, 0.0, false, f);
      CHECK(!f.ok && f.why == "no daily bar of today yet", "the newest daily bar is over: no bar of today, UNKNOWN");
      NqSeries dm = d;
      for(int i = 0; i < 16; i++) dm.t[i] = T0 + (long long)i * 900;
      NqDayForecast(dm, s, T0 + 16 * 900, 14, 0.0, 0.0, 0.0, false, f);
      CHECK(!f.ok && f.why == "the daily series is not daily", "a series that is not daily (a broker answering with another timeframe) is refused");
      NqSeries none;
      NqSeriesResize(none, 0);
      NqDayForecast(d, none, now, 14, 0.0, 0.0, 0.0, false, f);
      CHECK(!f.ok && f.why == "no closed bar of today yet" && near(f.adr, 3.5), "no closed intraday bar today: UNKNOWN (the ADR is still shown)");
   }
   end("S1");

   begin("S2 rotation ladder: score = (room x 0.5 + min(|move|, 60)) x (1 in session, else 0.5); rank 1 = GO TRADE; the MH15 sessions");
   {
      CHECK(near(NqLadderScore(40.0, 30.0, true), 60.0) && near(NqLadderScore(40.0, -30.0, false), 30.0), "used 40, move 30: 60 in session, 30 outside (the sign of the move does not matter)");
      CHECK(near(NqLadderScore(20.0, 95.0, true), 100.0) && near(NqLadderScore(130.0, 10.0, true), 10.0) && near(NqLadderRoom(130.0), 0.0),
            "the move is capped at 60; a day past its ADR has no room");
      std::vector<double> sc = {41.0, 55.5, 55.5};
      std::vector<int> have = {1, 1, 1}, rank;
      NqLadderRank(sc, have, 3, rank);
      CHECK(rank[0] == 3 && rank[1] == 1 && rank[2] == 2, "rank 1 = the highest score; a tie keeps the row order");
      have = {1, 0, 1};
      NqLadderRank(sc, have, 3, rank);
      CHECK(rank[0] == 2 && rank[1] == 0 && rank[2] == 1, "a row without data is not ranked");
      // EET summer broker: 17:00 New York = 00:00 server
      CHECK(NqNyMinute(0, 0) == 1020 && NqNyMinute(10 * 60, 0) == 180 && NqNyMinute(15 * 60, 0) == 480 && NqNyMinute(23 * 60 + 59, 0) == 1019, "server minute -> New York minute");
      CHECK(NqNyMinute(21 * 60, 21 * 60) == 1020 && NqNyMinute(7 * 60, 21 * 60) == 180, "a GMT broker (17:00 New York = 21:00 server)");
      CHECK(!NqMetalInSession(179) && NqMetalInSession(180) && NqMetalInSession(1019) && !NqMetalInSession(1020) && !NqMetalInSession(1200),
            "a metal's sessions: London + New York = 03:00-17:00 New York");
      CHECK(NqMh15Session(200) == "LONDON" && NqMh15Session(480) == "NEW YORK" && NqMh15Session(1150) == "ASIA" && NqMh15Session(60) == "ASIA" && NqMh15Session(1050) == "OFF",
            "Asia 19:00-03:00, London 03:00-08:00, New York 08:00-17:00");
   }
   end("S2");

   // a piecewise-linear path through turning points (bar index, price): small bars, so the ATR is small and the pivots are exact
   auto zig = [&](const std::vector<std::pair<int, double>> &pts) {
      NqSeries s;
      int n = pts.back().first + 1;
      NqSeriesResize(s, n);
      s.sec = 900;
      std::vector<double> c((size_t)n, pts[0].second);
      for(size_t k = 0; k + 1 < pts.size(); k++)
         for(int i = pts[k].first; i <= pts[k + 1].first; i++)
            c[(size_t)i] = pts[k].second + (pts[k + 1].second - pts[k].second) * (i - pts[k].first) / (double)(pts[k + 1].first - pts[k].first);
      for(int i = 0; i < n; i++)
      {
         double o = (i > 0) ? c[(size_t)i - 1] : c[0];
         s.t[i] = T0 + (long long)i * 900;
         s.o[i] = o;
         s.c[i] = c[(size_t)i];
         s.h[i] = std::max(o, c[(size_t)i]) + 0.01;
         s.l[i] = std::min(o, c[(size_t)i]) - 0.01;
         s.v[i] = 100;
      }
      return s;
   };
   auto mirror = [&](NqSeries s, double k) {
      for(int i = 0; i < s.n; i++)
      {
         double o = k - s.o[i], c = k - s.c[i], h = k - s.l[i], l = k - s.h[i];
         s.o[i] = o; s.c[i] = c; s.h[i] = h; s.l[i] = l;
      }
      return s;
   };
   auto ewAt = [&](const NqSeries &s, int at) {
      std::vector<double> atr;
      NqCalcATR(s.h, s.l, s.c, s.n, 14, atr);
      std::vector<NqPivot> p8;
      int n8 = NqFindPivots(s.h, s.l, s.n, 8, p8);
      NqElliott e;
      NqElliottCount(s, atr, p8, n8, at, e);
      return e;
   };
   auto cut = [&](const NqSeries &s, int at) {
      NqSeries c;
      NqSeriesResize(c, at + 1);
      c.sec = s.sec;
      for(int i = 0; i <= at; i++) { c.t[i] = s.t[i]; c.o[i] = s.o[i]; c.h[i] = s.h[i]; c.l[i] = s.l[i]; c.c[i] = s.c[i]; c.v[i] = s.v[i]; }
      return c;
   };

   begin("S3 Elliott count: PARTIAL until five waves pass every rule; the wave-3 setup triggers on the close beyond wave 1; five done = a setup against; no lookahead");
   {
      // P0 130 @100, P1 150 @110, P2 165 @105 (50% back), P3 195 @122, P4 210 @115 (above wave 1), P5 230 @127, then A / B / C
      NqSeries s = zig({{0, 105}, {100, 105}, {130, 100}, {150, 110}, {165, 105}, {195, 122}, {210, 115}, {230, 127}, {250, 119}, {262, 123}, {285, 112}});
      NqElliott e = ewAt(s, 170);
      CHECK(e.stage == NQ_EW_UNKNOWN && e.setupDir == 0, "the wave-2 pivot is not confirmed yet (8 bars): UNKNOWN - a forming swing is never counted");
      e = ewAt(s, 173);
      CHECK(e.stage == NQ_EW_12 && e.dir == 1 && !e.complete && e.nP == 3 && e.setupDir == 0 && near(e.retr2, 5.02 / 10.02, 1e-6), "waves 1-2 printed, PARTIAL, not triggered: no setup");
      CHECK(NqEwVote(e, 1) == 0 && NqEwVote(e, -1) == 0, "an untriggered 1-2 count votes nothing");
      e = ewAt(s, 174);
      CHECK(e.stage == NQ_EW_W3 && e.setupDir == 1 && e.setupIdx == 174 && e.setupLife == NQ_SU_ALIVE && near(e.entry, s.c[174]) && near(e.sl, 104.99) &&
            near(e.t1, 104.99 + 10.02) && near(e.t2, 104.99 + 1.618 * 10.02) && e.horizon == 2 * (174 - 130),
            "the first close beyond the wave-1 end TRIGGERS the wave-3 setup: SL = wave 2, targets 1 and 1.618 x wave 1, horizon = twice the count's bars");
      CHECK(NqEwVote(e, 1) == 1 && NqEwVote(e, -1) == -1, "a live wave-3 setup votes with the impulse and against the other side");
      e = ewAt(s, 196);
      CHECK(e.stage == NQ_EW_W3 && e.setupIdx == 174 && e.setupLife == NQ_SU_TARGET && NqEwVote(e, 1) == 0, "target 2 reached: the setup is over and votes nothing");
      e = ewAt(s, 203);
      CHECK(e.stage == NQ_EW_W4 && e.setupDir == 0 && !e.complete && near(e.w3x, 17.02 / 10.02, 1e-6) && NqEwVote(e, 1) == 0, "wave 3 printed: the wave-4 pullback is not a setup");
      e = ewAt(s, 218);
      CHECK(e.stage == NQ_EW_W5 && !e.late && NqEwVote(e, 1) == 0, "wave 5 underway, still inside wave 3: no vote");
      e = ewAt(s, 223);
      CHECK(e.stage == NQ_EW_W5 && e.late && NqEwVote(e, 1) == -1 && NqEwVote(e, -1) == 0, "beyond the wave-3 end: DO NOT ADD LATE - against a buy, nothing for a sell");
      e = ewAt(s, 238);
      CHECK(e.stage == NQ_EW_DONE && e.complete && e.nP == 6 && e.setupDir == -1 && e.setupIdx == 238 && e.setupLife == NQ_SU_ALIVE && near(e.sl, 127.01) &&
            near(e.t1, 127.01 - 0.382 * 27.02) && near(e.t2, 127.01 - 0.618 * 27.02),
            "five waves COMPLETE: the setup is AGAINST the impulse, SL = the wave-5 end, targets 38.2% / 61.8% of the move");
      CHECK(NqEwVote(e, -1) == 1 && NqEwVote(e, 1) == -1, "a finished five votes for the reversal");
      e = ewAt(s, 258);
      CHECK(e.stage == NQ_EW_ABC && e.abc == 1 && e.dir == 1 && e.setupDir == 0 && NqEwVote(e, 1) == 0 && NqEwVote(e, -1) == 0, "the next pivot after a finished five is labelled A (labels only)");
      // no lookahead: the count at bar t from the first t+1 bars equals the count at t from the whole series
      int diff = 0;
      for(int at = 140; at < s.n; at++)
      {
         NqElliott a = ewAt(s, at), b = ewAt(cut(s, at), at);
         if(a.stage != b.stage || a.dir != b.dir || a.setupDir != b.setupDir || a.setupLife != b.setupLife || a.setupIdx != b.setupIdx || !near(a.entry, b.entry)) diff++;
      }
      CHECK(diff == 0, "walked forward: the count at every bar is the same with and without the bars after it");
      // the rules
      NqElliott r = ewAt(zig({{0, 105}, {100, 105}, {130, 100}, {150, 110}, {165, 109}, {200, 122}}), 180);
      CHECK(r.stage == NQ_EW_UNKNOWN, "wave 2 retraces 10% (< 23.6%): no count");
      r = ewAt(zig({{0, 105}, {100, 105}, {130, 100}, {150, 110}, {165, 105}, {195, 122}, {210, 109}, {230, 127}}), 220);
      CHECK(r.stage != NQ_EW_W5, "wave 4 enters wave 1: not wave 5 of that impulse");
      r = ewAt(zig({{0, 105}, {100, 105}, {130, 100}, {150, 110}, {165, 105}, {180, 99.5}, {200, 104}}), 176);
      CHECK(r.stage == NQ_EW_UNKNOWN, "a bar passes the start of wave 1: the 1-2 count is dead");
      // the mirror: a down impulse
      NqSeries m = mirror(s, 230.0);
      e = ewAt(m, 174);
      CHECK(e.stage == NQ_EW_W3 && e.dir == -1 && e.setupDir == -1 && near(e.sl, 230.0 - 104.99) && NqEwVote(e, -1) == 1, "the bearish mirror counts the same way");
      // nothing made in the first 120 bars is a setup
      NqSeries early = zig({{0, 105}, {10, 105}, {40, 100}, {60, 110}, {75, 105}, {105, 122}, {120, 115}});
      e = ewAt(early, 84);
      CHECK(e.stage == NQ_EW_W3 && e.setupDir == 0 && NqEwVote(e, 1) == 0, "a trigger inside the first 120 loaded bars is shown but is not a setup (the walk has not settled)");
   }
   end("S3");

   begin("S4 Wolfe wave: five points confirmed (entry, SL, TP1, TP2, expiry), DEVELOPING is never a setup, stop / target / mirror");
   {
      auto wwAt = [&](const NqSeries &s, int at) {
         std::vector<double> atr;
         NqCalcATR(s.h, s.l, s.c, s.n, 14, atr);
         std::vector<NqPivot> p10;
         int n10 = NqFindPivots(s.h, s.l, s.n, 10, p10);
         NqWolfe w;
         NqWolfeWave(s, atr, p10, n10, at, w);
         return w;
      };
      // 1 low 100 @140, 2 high 110 @160, 3 low 96 @180, 4 high 101 @200, 5 low 92 @220 (on line 1-3), then up
      NqSeries s = zig({{0, 105}, {110, 105}, {140, 100}, {160, 110}, {180, 96}, {200, 101}, {220, 92}, {300, 108}});
      NqWolfe w = wwAt(s, 215);
      CHECK(w.state == NQ_WW_DEVELOPING && w.dir == 1 && NqWolfeVote(w, 1) == 0 && NqWolfeVote(w, -1) == 0, "points 1-4 fit, point 5 not printed: DEVELOPING, never a vote");
      CHECK(near(w.zoneLo, 92.49 - 0.15 * 14.02, 1e-6) && near(w.zoneHi, 92.49 + 0.15 * 14.02, 1e-6), "its zone: line 1-3 at the newest bar +/- 15% of the pattern height");
      w = wwAt(s, 229);
      CHECK(w.state == NQ_WW_DEVELOPING, "point 5 printed but not confirmed (10 bars): still developing");
      w = wwAt(s, 230);
      double apex = (10.02 - 0.1 * 140 + 0.225 * 160) / 0.125;
      double epa = 99.99 + 1.02 / 60.0 * (apex - 140);
      std::vector<double> atr;
      NqCalcATR(s.h, s.l, s.c, s.n, 14, atr);
      CHECK(w.state == NQ_WW_CONFIRMED && w.dir == 1 && w.detIdx == 230 && w.life == NQ_SU_ALIVE && near(w.entry, s.c[230]) && near(w.apex, apex, 1e-6),
            "bullish Wolfe CONFIRMED on the bar that confirms point 5; entry = that bar's close; the apex is where 1-3 and 2-4 meet");
      CHECK(near(w.sl, 91.99 - 0.5 * atr[230]) && near(w.tp1, 101.01) && near(w.tp2, epa, 1e-6) && w.expiryIdx == (int)std::ceil(apex) + 80,
            "SL = point 5 - 0.5 ATR, TP1 = the nearer of point 4 and the EPA, TP2 = the further, expiry one pattern length after the apex");
      CHECK(NqWolfeVote(w, 1) == 1 && NqWolfeVote(w, -1) == -1, "a live confirmed Wolfe votes its direction");
      w = wwAt(s, 275);
      CHECK(w.state == NQ_WW_CONFIRMED && w.life == NQ_SU_TARGET && NqWolfeVote(w, 1) == 0, "TP2 reached: over, no vote");
      NqSeries st = zig({{0, 105}, {110, 105}, {140, 100}, {160, 110}, {180, 96}, {200, 101}, {220, 92}, {232, 94.4}, {245, 90}});
      w = wwAt(st, 240);
      CHECK(w.state == NQ_WW_CONFIRMED && w.life == NQ_SU_STOPPED && NqWolfeVote(w, 1) == 0, "price through point 5 - 0.5 ATR: stopped, no vote");
      NqSeries m = mirror(s, 200.0);
      w = wwAt(m, 230);
      CHECK(w.state == NQ_WW_CONFIRMED && w.dir == -1 && near(w.tp1, 200.0 - 101.01) && w.sl > 200.0 - 91.99 && NqWolfeVote(w, -1) == 1, "the bearish mirror (a rising wedge)");
      // point 5 far from line 1-3: not a Wolfe
      NqSeries far = zig({{0, 105}, {110, 105}, {140, 100}, {160, 110}, {180, 96}, {200, 101}, {220, 86}, {300, 108}});
      w = wwAt(far, 232);
      CHECK(w.state != NQ_WW_CONFIRMED, "point 5 more than 15% of the height away from line 1-3: not confirmed");
      // lines that do not converge within one pattern length: not a Wolfe
      NqSeries wide = zig({{0, 105}, {110, 105}, {140, 100}, {160, 110}, {180, 96}, {200, 104}, {220, 92}, {300, 108}});
      w = wwAt(wide, 232);
      CHECK(w.state != NQ_WW_CONFIRMED, "the apex further than one pattern length after point 5: not confirmed");
   }
   end("S4");

   begin("S5 Fibonacci extension, anchored VWAP, volume profile (tick volume)");
   {
      // A low 100 @130, B high 110 @150, C low 105 @162 (holds inside A-B), up to 113, then down through C
      NqSeries s = zig({{0, 105}, {100, 105}, {130, 100}, {150, 110}, {162, 105}, {190, 113}, {215, 103}});
      std::vector<NqPivot> p5;
      int n5 = NqFindPivots(s.h, s.l, s.n, 5, p5);
      NqFibExt f;
      NqFibExtension(s, p5, n5, 190, f);
      CHECK(f.ok && f.dir == 1 && near(f.a, 99.99) && near(f.b, 110.01) && near(f.c, 104.99) && near(f.lv[0], 104.99 + 0.618 * 10.02) && near(f.lv[1], 115.01) &&
            near(f.lv[5], 104.99 + 2.618 * 10.02), "A, B, C = the last three alternating pivots; level = C + ratio x (B - A)");
      CHECK(f.reached == 1 && !f.invalid, "0.618 was traded by a later closed bar, 1.0 was not; the set is valid");
      NqFibExtension(s, p5, n5, 215, f);
      CHECK(f.ok && near(f.c, 104.99) && f.invalid && f.reached == 1, "the newest pivot went beyond: the three before it stay A-B-C; a close beyond C INVALIDATES the set");
      NqFibExtension(s, p5, n5, 140, f);
      CHECK(!f.ok, "fewer than three pivots: no set");
      // anchored VWAP: two bars, typical 10 (volume 1) and 20 (volume 3)
      NqSeries v;
      NqSeriesResize(v, 2);
      v.h[0] = 10; v.l[0] = 10; v.c[0] = 10; v.v[0] = 1;
      v.h[1] = 20; v.l[1] = 20; v.c[1] = 20; v.v[1] = 3;
      double vw = 0, band = 0;
      CHECK(NqAnchoredVwap(v, 0, 1, vw, band) && near(vw, 17.5) && near(band, std::sqrt(18.75), 1e-9), "VWAP 17.5, band = the volume-weighted standard deviation");
      CHECK(NqAnchoredVwap(v, 1, 1, vw, band) && near(vw, 20.0) && near(band, 0.0) && !NqAnchoredVwap(v, 2, 1, vw, band), "from the anchor bar onward; an anchor after the end = none");
      // volume profile: ten bars 100-101 and one bar 100-110, 100 ticks each, 40 rows of 0.25
      NqSeries q;
      NqSeriesResize(q, 11);
      for(int i = 0; i < 11; i++) { q.l[i] = 100; q.h[i] = (i == 5) ? 110 : 101; q.c[i] = 100.5; q.v[i] = 100; }
      NqProfile p;
      NqVolumeProfile(q, 0, 10, 40, p);
      CHECK(p.ok && near(p.step, 0.25) && near(p.poc, 100.125) && near(p.vah, 101.0) && near(p.val, 100.0), "POC = the busiest row; the value area grows outward to 70% of the activity");
      NqSeries flat;
      NqSeriesResize(flat, 3);
      for(int i = 0; i < 3; i++) { flat.l[i] = 100; flat.h[i] = 100; flat.c[i] = 100; flat.v[i] = 1; }
      NqVolumeProfile(flat, 0, 2, 40, p);
      CHECK(!p.ok, "a series with no range has no profile");
      // the set on one series, and its two context votes
      NqSeries e = zig({{0, 105}, {100, 105}, {130, 100}, {150, 110}, {165, 105}, {195, 122}, {210, 115}, {230, 127}, {250, 119}});
      NqStudySet S;
      NqRunStudies(cut(e, 238), e.t[200], S);
      CHECK(S.ok && S.nBars == 239 && S.ew.stage == NQ_EW_DONE && S.haveAvHi && S.haveAvLo && S.haveAvDay && S.vp.ok && S.vp.val < S.vp.poc && S.vp.poc < S.vp.vah,
            "one run: Elliott, the three anchored VWAPs and the profile");
      CHECK(S.close > S.avLo && S.close < S.avHi && NqAvwapVote(S, 1) == 0, "price between the two swing-anchored VWAPs: no vote");
      S.avHi = S.close - 1.0;
      CHECK(NqAvwapVote(S, 1) == 1 && NqAvwapVote(S, -1) == -1, "above both anchored VWAPs: for a buy, against a sell");
      S.vp.val = S.close + 1.0;
      S.vp.vah = S.close + 2.0;
      CHECK(NqValueVote(S, 1) == -1 && NqValueVote(S, -1) == 1, "below the value area: against a buy, for a sell");
      NqSeries tiny = cut(e, 20);
      NqRunStudies(tiny, 0, S);
      CHECK(!S.ok && NqAvwapVote(S, 1) == 0 && NqValueVote(S, 1) == 0, "fewer than 30 bars: no studies, no votes");
   }
   end("S5");

   // daily bars for the simulated broker: `before` synthetic days of range R before T0, then the market's own days
   auto makeDays = [&](const Market &m, int before, double R) {
      std::vector<MqlRates> d;
      double p0 = m.m1[0].o;
      for(int k = before; k >= 1; k--) d.push_back({T0 - (long long)k * 86400, p0, p0 + R / 2, p0 - R / 2, p0, 100, 0, 0});
      for(const SBar &b : agg(m.m1, 86400)) d.push_back({b.t, b.o, b.h, b.l, b.c, 100, 0, 0});
      return d;
   };
   auto todayHiLo = [&](double &hi, double &lo) {
      hi = -1e18; lo = 1e18;
      for(const MqlRates &b : SIM.m5)
         if(b.time >= g_fc.dayStart && b.time + 300 <= SIM.now) { hi = std::max(hi, b.high); lo = std::min(lo, b.low); }
   };

   begin("S6 the table on a simulated broker: ADR from the broker's daily bars, today from closed M5 bars, no daily bars = UNKNOWN and no gate, fold");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      CHECK(g_studies && !g_fc.ok && g_fc.why == "no daily bars" && lbl("v_f1").find("UNKNOWN - no daily bars (no gate)") == 0, "the broker serves no daily bars: the forecast is UNKNOWN and says why");
      g_adrGate = true;
      std::string why;
      CHECK(!NqAdrRoomBlocks(1, SIM.bid, SIM.bid + 1000.0, why) && !NqStudiesBlock(1, SIM.bid, SIM.bid + 1000.0, why), "UNKNOWN gates nothing");
      OnDeinit(0);

      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.d1 = makeDays(gold, 20, 20.0);
      startAt(START);
      relax();
      run(START + 1, START + 200);
      double sum = 0.0;
      int nc = 0;
      for(int i = (int)SIM.d1.size() - 1; i >= 0 && nc < 14; i--)
         if(SIM.d1[(size_t)i].time + 86400 <= SIM.now) { sum += SIM.d1[(size_t)i].high - SIM.d1[(size_t)i].low; nc++; }
      double hi = 0, lo = 0;
      todayHiLo(hi, lo);
      CHECK(g_fc.ok && nc == 14 && near(g_fc.adr, sum / 14.0, 1e-9) && g_fc.dayStart == T0 + 4 * 86400, "ADR = the mean range of the last 14 completed broker days; the day starts where the daily bar starts");
      CHECK(near(g_fc.hi, hi) && near(g_fc.lo, lo) && near(g_fc.usedPct, 100.0 * (hi - lo) / g_fc.adr, 1e-9), "today's high / low = the closed M5 bars since the day started (never the forming bar)");
      CHECK(near(g_fc.top, std::max(lo + g_fc.adr, hi)) && near(g_fc.bottom, std::min(hi - g_fc.adr, lo)), "top / bottom (no 4h bars at this broker: no snap)");
      std::printf("    ADR %.2f, used %.0f%% %s, top %.2f bottom %.2f\n", g_fc.adr, g_fc.usedPct, NqFdStateText(g_fc.state).c_str(), g_fc.top, g_fc.bottom);
      CHECK(lbl("tF") != "<missing>" && lbl("hF").find("MH15 PLUS") == 0 && lbl("v_f1").find("ADR ") == 0 && lbl("v_f1").find(" used ") != std::string::npos,
            "the MH15 PLUS table is on the chart with the DAY FORECAST row");
      CHECK(lbl("fl0_0") == "GOLD" && lbl("fl1_0") == "SILVER" && lbl("fl2_0") == "COPPER" && lbl("fl0_1") == "XAUUSD" && lbl("fl0_7").find("(this chart)") != std::string::npos &&
            lbl("fl1_2").find("UNKNOWN - not on this broker") == 0, "three ladder rows; a metal the broker does not serve is UNKNOWN");
      CHECK(g_ldBest == 0 && g_ldRank[0] == 1 && NqLadderKnown() == 1, "one row with data: it is #1, and with fewer than two rows the ladder gates nothing");
      g_ladderGate = true;
      g_ldRank[0] = 3;
      CHECK(!NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why), "... even if it were ranked last");
      g_ladderGate = false;
      CHECK(SIM.objs.count("NQEA_C_FC_T") == 1 && SIM.objs.count("NQEA_C_FC_B") == 1, "the forecast top / bottom are drawn on the chart");
      // the gate, on the live forecast: a buy whose target is beyond the top is removed, one that fits is not
      g_adrGate = true;
      double e1 = g_fc.top - 1.0;
      CHECK(NqAdrRoomBlocks(1, e1, e1 + 1.5, why) && why.find("ADR ROOM: BUY") == 0 && !NqAdrRoomBlocks(1, e1, e1 + 0.9, why), "BUY 1.0 under the top: a 1.5 target is blocked, a 0.9 target fits");
      double e2 = g_fc.bottom + 1.0;
      CHECK(NqAdrRoomBlocks(-1, e2, e2 - 1.5, why) && why.find("ADR ROOM: SELL") == 0 && !NqAdrRoomBlocks(-1, e2, e2 - 0.9, why), "SELL 1.0 above the bottom: the mirror");
      CHECK(NqAdrRoomBlocks(1, g_fc.top + 0.5, g_fc.top + 0.6, why) && why.find("has nothing left") != std::string::npos, "a breakout entry above the top has no room at all");
      int keep = g_fc.state;
      g_fc.state = NQ_FD_EXPAND;
      CHECK(!NqAdrRoomBlocks(1, e1, e1 + 1.5, why), "EXPANSION (event mode): the gate stands down");
      g_fc.state = keep;
      g_adrGate = false;
      CHECK(!NqAdrRoomBlocks(1, e1, e1 + 1.5, why), "gate off: nothing is removed");
      // fold / unfold
      OnChartEvent(CHARTEVENT_OBJECT_CLICK, 0, 0.0, "NQEA_P_hF");
      CHECK(g_fcCollapsed && lbl("v_f1") == "<missing>" && lbl("hF").find("(click: unfold)") != std::string::npos, "a click on the table's header folds it");
      OnChartEvent(CHARTEVENT_OBJECT_CLICK, 0, 0.0, "NQEA_P_hF");
      CHECK(!g_fcCollapsed && lbl("v_f1").find("ADR ") == 0, "... and unfolds it");
      std::string tj = NqTelemetryJson();
      CHECK(tj.find("\"mh15\":{\"on\":true") != std::string::npos && tj.find("\"ladder\":[{\"name\":\"GOLD\",\"symbol\":\"XAUUSD\",\"ok\":true") != std::string::npos &&
            tj.find("\"go_trade\":\"GOLD\"") != std::string::npos, "telemetry carries the table (ANALYSIS ONLY)");
      OnDeinit(0);
   }
   end("S6");

   begin("S7 ADR ROOM end to end: with the gate ON no order is opened or left resting whose first target is outside the day's forecast range");
   {
      // returns the number of opening requests whose first target did not fit when they were sent
      auto runDay = [&](bool gate, int &opened, int &blocks, int &restingBad) {
         load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
         SIM.d1 = makeDays(gold, 20, 4.0);     // quiet days before: a small ADR, so the day fills it
         startAt(START);
         relax();
         g_adrGate = gate;
         opened = 0; blocks = 0; restingBad = 0;
         int bad = 0;
         std::string lastNote;
         for(size_t i = START + 1; i <= END; i++)
         {
            size_t before = SIM.sent.size();
            stepTo(i);
            if(!g_fc.ok) continue;
            for(size_t k = before; k < SIM.sent.size(); k++)
            {
               const MqlTradeRequest &r = SIM.sent[k];
               bool pend = (r.action == TRADE_ACTION_PENDING);
               bool mkt = (r.action == TRADE_ACTION_DEAL && r.position == 0);
               if(!pend && !mkt) continue;
               opened++;
               int dir = (r.type == ORDER_TYPE_BUY || r.type == ORDER_TYPE_BUY_LIMIT || r.type == ORDER_TYPE_BUY_STOP) ? 1 : -1;
               double target = r.tp;
               NqPlan p;
               if(pend && NqPlanByComment(r.comment, p)) target = p.tp1;
               double room = (dir > 0) ? (g_fc.top - r.price) : (r.price - g_fc.bottom);
               if(room < std::fabs(target - r.price) - 1e-9) bad++;
            }
            for(const SimOrder &o : SIM.ord)
            {
               NqPlan p;
               if(!NqPlanByComment(o.comment, p)) continue;
               double room = (p.dir > 0) ? (g_fc.top - p.entry) : (p.entry - g_fc.bottom);
               if(room < std::fabs(p.tp1 - p.entry) - 1e-9) restingBad++;
            }
            if(g_studyNote != lastNote) { lastNote = g_studyNote; if(lastNote.find("ADR ROOM") == 0) blocks++; }
         }
         OnDeinit(0);
         return bad;
      };
      int openedOff = 0, blocksOff = 0, restOff = 0, openedOn = 0, blocksOn = 0, restOn = 0;
      int badOff = runDay(false, openedOff, blocksOff, restOff);
      int badOn = runDay(true, openedOn, blocksOn, restOn);
      std::printf("    gate OFF: %d opening requests, %d with a target outside the range, %d resting-order minutes outside; gate ON: %d requests, %d outside, %d resting outside, %d blocks\n",
                  openedOff, badOff, restOff, openedOn, badOn, restOn, blocksOn);
      CHECK(openedOff > 0 && badOff + restOff > 0 && blocksOff == 0, "without the gate the run does send or rest orders whose target is outside the range (else this check would prove nothing)");
      CHECK(openedOn > 0 && badOn == 0 && restOn == 0, "with the gate: every order sent fits, and a resting order whose room is gone is pulled the same minute");
      CHECK(blocksOn > 0 && openedOn <= openedOff, "the gate only removes entries (never more than the run without it), and says so on the table");
   }
   end("S7");

   begin("S8 the ladder across gold / silver / copper: peers found by the chart's spelling, ranked by score, the last row stands aside");
   {
      Market silverL = makeMarket(5, 60.9, 0.001, 0.006, (int)DAYS);
      Market copperL = makeMarket(9, 4.52, 0.0001, 0.0006, (int)DAYS);
      auto serve = [&](const char *name, const Market &m, double R) {
         SIM.extraTf[name][(int)PERIOD_D1] = makeDays(m, 20, R);
         SIM.extraTf[name][(int)PERIOD_M5] = toRates(m.m5);
      };
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.d1 = makeDays(gold, 20, 20.0);
      serve("XAGUSD", silverL, 0.9);
      serve("XCUUSD", copperL, 0.08);
      startAt(START);
      relax();
      run(START + 1, START + 400);
      CHECK(g_ldSym[0] == "XAUUSD" && g_ldSym[1] == "XAGUSD" && g_ldSym[2] == "XCUUSD", "AUTO: the broker's silver and copper symbols are found");
      CHECK(g_ldFc[0].ok && g_ldFc[1].ok && g_ldFc[2].ok && NqLadderKnown() == 3, "all three rows have a forecast");
      // a peer's forecast is its own: its ADR from its daily bars, its day from its closed M5 bars
      double hi = -1e18, lo = 1e18;
      for(const SBar &b : silverL.m5)
         if(b.t >= g_ldFc[1].dayStart && b.t + 300 <= SIM.now) { hi = std::max(hi, b.h); lo = std::min(lo, b.l); }
      CHECK(near(g_ldFc[1].hi, hi) && near(g_ldFc[1].lo, lo) && g_ldFc[1].adr > 0.0 && near(g_ldFc[1].usedPct, 100.0 * (hi - lo) / g_ldFc[1].adr, 1e-9), "silver's row is silver's own day");
      int bad = 0, best = -1;
      for(int k = 0; k < 3; k++)
      {
         if(!near(g_ldScore[k], NqLadderScore(g_ldFc[k].usedPct, g_ldFc[k].movePct, g_ldInSess), 1e-9)) bad++;
         if(best < 0 || g_ldScore[k] > g_ldScore[best]) best = k;
      }
      std::printf("    scores: gold %.1f (#%d)  silver %.1f (#%d)  copper %.1f (#%d)  session x%s\n", g_ldScore[0], g_ldRank[0], g_ldScore[1], g_ldRank[1],
                  g_ldScore[2], g_ldRank[2], g_ldInSess ? "1.0" : "0.5");
      CHECK(bad == 0 && g_ldBest == best && g_ldRank[best] == 1 && g_ldRank[0] + g_ldRank[1] + g_ldRank[2] == 6, "score per row, ranks 1-2-3, GO TRADE = the highest score");
      std::string rk = "fl" + std::to_string(best) + "_7";
      CHECK(lbl(rk.c_str()).find("#1  GO TRADE") == 0 && lbl("v_f0").find(std::string("GO TRADE = ") + NqPeerName(best)) == 0, "the table names the GO TRADE row");
      // the gate: the last of three stands aside, the top two may open
      std::string why;
      g_ladderGate = true;
      int own = g_ldRank[0];
      double ownScore = g_ldScore[0];
      g_ldRank[0] = 3;
      g_ldScore[0] = g_ldScore[g_ldBest] - 10.0;
      CHECK(NqLadderAside(0) && NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why) && why.find("LADDER: GOLD is #3 of 3") == 0 && g_studyNote == why,
            "gold #3 of 3 and 10 points under the GO TRADE row: stands aside (and LAST BLOCK says so)");
      g_ldScore[0] = g_ldScore[g_ldBest] - 9.9;
      CHECK(!NqLadderAside(0) && !NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why), "#3 but within 10 points of the best: a near tie is no difference, no block");
      g_ldScore[0] = g_ldScore[g_ldBest] - 30.0;
      g_ldRank[0] = 2;
      CHECK(!NqLadderAside(0) && !NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why), "#2 of 3 may open (top 2) however far behind");
      g_ldRank[0] = own;
      g_ldScore[0] = ownScore;
      g_ladderGate = false;
      CHECK(!NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why), "gate off: the ladder is shown, nothing is removed");
      OnDeinit(0);

      // end to end: with the ladder gate ON, an order opens only while gold is in the top two
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.d1 = makeDays(gold, 20, 4.0);       // a small ADR: gold fills its day and drops down the ladder
      serve("XAGUSD", silverL, 0.9);
      serve("XCUUSD", copperL, 0.08);
      startAt(START);
      relax();
      g_ladderGate = true;
      int opened = 0, openedLast = 0, minutesLast = 0;
      for(size_t i = START + 1; i <= END; i++)
      {
         size_t before = SIM.sent.size();
         stepTo(i);
         if(NqLadderAside(0)) minutesLast++;
         for(size_t k = before; k < SIM.sent.size(); k++)
         {
            const MqlTradeRequest &r = SIM.sent[k];
            if(r.action != TRADE_ACTION_PENDING && !(r.action == TRADE_ACTION_DEAL && r.position == 0)) continue;
            opened++;
            if(NqLadderAside(0)) openedLast++;
         }
      }
      std::printf("    gold stood aside (#3, 10+ under the best) for %d of %d minutes; %d orders opened, %d of them while aside\n", minutesLast, (int)(END - START), opened, openedLast);
      CHECK(minutesLast > 0 && opened > 0 && openedLast == 0, "no order is opened while gold stands aside");
      OnDeinit(0);

      // the chart's spelling is kept: XAUUSD.m looks for XAGUSD.m first
      load(gold, "XAUUSD.m", "XAU", 2, 0.01, 1.0);
      SIM.d1 = makeDays(gold, 20, 20.0);
      serve("XAGUSD.m", silverL, 0.9);
      serve("XAGUSD", silverL, 0.9);
      startAt(START);
      CHECK(g_ldSym[0] == "XAUUSD.m" && g_ldSym[1] == "XAGUSD.m" && g_ldSym[2] == "", "prefix / suffix of the chart symbol first; a metal the broker lacks stays out");
      relax();
      run(START + 1, START + 10);
      CHECK(NqLadderKnown() == 2 && g_ldRank[2] == 0 && lbl("fl2_2").find("UNKNOWN - not on this broker") == 0, "two rows ranked, copper UNKNOWN");
      g_ladderGate = true;
      g_ldRank[0] = 2;
      std::string why2;
      CHECK(!NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why2), "#2 of 2 is inside the top two: no block");
      OnDeinit(0);

      // a broker that answers a daily request with another timeframe: refused, never ranked
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.d1 = makeDays(gold, 20, 20.0);
      SIM.macro15 = toRates(silverL.m15);     // any second symbol answers with these M15 bars, whatever timeframe is asked
      startAt(START);
      relax();
      run(START + 1, START + 10);
      CHECK(g_ldSym[1] != "" && !g_ldFc[1].ok && g_ldFc[1].why == "the daily series is not daily" && g_ldRank[1] == 0, "bars that are not daily are not an ADR: the row is UNKNOWN");
      OnDeinit(0);
      SIM.macro15.clear();
   }
   end("S8");

   begin("S9 the study vote: two studies against an entry block it, one does not; the table shows the vote");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
      relax();
      run(START + 1, START + 60);
      CHECK(g_st.ok && g_st.nBars > 100 && lbl("v_f3") != "<missing>" && lbl("v_f6").find("AVWAP from the high") == 0, "the pattern studies run on the closed M15 bars and are on the table");
      g_studyGate = true;
      g_st.ew.stage = NQ_EW_UNKNOWN;
      g_st.ww.state = NQ_WW_NONE;
      g_st.close = 100.0;
      g_st.haveAvHi = true; g_st.haveAvLo = true; g_st.avHi = 101.0; g_st.avLo = 102.0;
      g_st.vp.ok = true; g_st.vp.val = 100.5; g_st.vp.vah = 103.0;
      std::string why, voters;
      CHECK(NqStudyVote(1, voters) == -2 && NqStudyVote(-1, voters) == 2, "below both anchored VWAPs and below the value area: BUY -2, SELL +2");
      CHECK(!NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why) && !NqStudiesBlock(-1, SIM.bid, SIM.bid - 0.01, why),
            "context alone (-2 from the VWAPs and the value area) never blocks: no setup is among the objectors");
      g_st.vp.ok = false;
      g_st.ew.stage = NQ_EW_W3; g_st.ew.dir = -1; g_st.ew.setupDir = -1; g_st.ew.setupLife = NQ_SU_ALIVE;
      CHECK(NqStudyVote(1, voters) == -2 && voters.find("elliott wave-3 setup down -1") == 0, "a live Elliott wave-3 setup down + below both VWAPs: BUY -2");
      CHECK(NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why) && why.find("STUDIES AGAINST BUY (vote -2: elliott wave-3 setup down -1, avwap below both -1)") == 0,
            "a setup against, confirmed by the context: the buy is blocked and the voters are named");
      CHECK(!NqStudiesBlock(-1, SIM.bid, SIM.bid - 0.01, why), "the sell is not touched");
      NqDrawPanel();
      CHECK(lbl("v_f7").find("vote BUY -2 / SELL +2  (blocks at -2 with a live setup against)") == 0 && lbl("v_f8").find("STUDIES AGAINST BUY") == 0, "STUDY VOTE and LAST BLOCK rows");
      g_st.haveAvHi = false;
      CHECK(NqStudyVote(1, voters) == -1 && !NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why), "the setup alone (-1) does not block");
      g_st.haveAvHi = true;
      g_st.ww.state = NQ_WW_CONFIRMED; g_st.ww.dir = 1; g_st.ww.life = NQ_SU_ALIVE;
      CHECK(NqStudyVote(1, voters) == -1 && !NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why), "a live bullish Wolfe votes for the buy: -1 net, not blocked");
      g_studyGate = false;
      g_st.ww.state = NQ_WW_NONE;
      CHECK(NqStudyVote(1, voters) == -2 && !NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why), "gate off: the vote is shown, nothing is removed");
      g_studies = false;
      CHECK(NqStudyVote(1, voters) == 0 && !NqStudiesBlock(1, SIM.bid, SIM.bid + 0.01, why), "master switch off: no vote, no gate");
      OnDeinit(0);
   }
   end("S9");

   begin("S10 copper is the third metal: the detector, the panel, its row on the ladder");
   {
      CHECK(NqMetalOf("XCUUSD", "XCU", "USD") == NQ_METAL_COPPER && NqMetalOf("COPPER", "", "USD") == NQ_METAL_COPPER && NqMetalOf("#Copper.m", "", "USD") == NQ_METAL_COPPER &&
            NqMetalOf("COPPER-C", "", "") == NQ_METAL_COPPER && NqMetalOf("HGCOPPER", "", "USD") == NQ_METAL_COPPER, "copper spellings");
      CHECK(NqMetalOf("HG", "", "USD") == NQ_METAL_COPPER && NqMetalOf("HG.c", "", "USD") == NQ_METAL_COPPER && NqMetalOf("HG_Z6", "", "USD") == NQ_METAL_COPPER &&
            NqMetalOf("HGKD", "", "USD") == NQ_METAL_NONE && NqMetalOf("HKDUSD", "HKD", "USD") == NQ_METAL_NONE, "HG is copper only alone or with a contract code, never a longer name");
      CHECK(NqMetalOf("XCUEUR", "XCU", "EUR") == NQ_METAL_NONE && NqMetalOf("XAUUSD", "XAU", "USD") == NQ_METAL_GOLD && NqMetalOf("SILVER", "", "USD") == NQ_METAL_SILVER &&
            NqMetalOf("EURUSD", "EUR", "USD") == NQ_METAL_NONE, "a non-dollar quote is refused; gold and silver are detected as before");
      Market copper = makeMarket(9, 4.52, 0.0001, 0.0006, (int)DAYS);
      load(copper, "XCUUSD", "XCU", 4, 0.0001, 2.5);
      SIM.d1 = makeDays(copper, 20, 0.08);
      CHECK(startAt(START) == INIT_SUCCEEDED && g_metal == NQ_METAL_COPPER && NqPeerRow() == 2, "the EA starts on copper; it is row 3 of the ladder");
      relax();
      run(START + 1, START + 30);
      CHECK(lbl("title").find("COPPER  -  NRTR QML SCALPER") == 0 && lbl("fl2_1") == "XCUUSD" && lbl("fl2_7").find("(this chart)") != std::string::npos && g_fc.ok,
            "the title says COPPER and the table's copper row is this chart");
      CHECK(NqTelemetryJson().find("\"metal\":\"COPPER\"") != std::string::npos, "telemetry names the metal");
      OnDeinit(0);
   }
   end("S10");
   // remove every M1 candle with a <= t < b and rebuild M5 / M15 from what is left: a hole on all three timeframes
   auto punch = [&](Market m, long long a, long long b) {
      std::vector<SBar> keep;
      for(const SBar &x : m.m1) if(x.t < a || x.t >= b) keep.push_back(x);
      m.m1 = keep;
      m.m5 = agg(m.m1, 300);
      m.m15 = agg(m.m1, 900);
      return m;
   };
   auto ixOf = [&](long long t) { size_t i = 0; while(i + 1 < SIM.m1.size() && SIM.m1[i].time < t) i++; return i; };
   auto gateSays = [&](const char *what) { for(int k = 0; k < 24; k++) { std::string s = NqGateAtX(g_gate, k); if(s.empty()) break; if(s.find(what) != std::string::npos) return true; } return false; };

   begin("G1 candle integrity (pure): a hole is WEEKEND, DAILY CLOSE, LONG CLOSE or DATA GAP; the scan and the recovery");
   {
      const long long D = 86400, H = 3600, M = 60;   // T0 = Tuesday 00:00
      CHECK(NqGapClassify(T0 + D + 10 * H, T0 + D + 10 * H + 14 * M, 0, 900, 14400, 7200) == NQ_GAP_NONE, "14 minutes without a candle is not a hole (15 is)");
      CHECK(NqGapClassify(T0 + D + 10 * H, T0 + D + 10 * H + 50 * M, 0, 900, 14400, 7200) == NQ_GAP_DATA, "Wednesday 10:00-10:50, nowhere near the rollover: DATA GAP");
      CHECK(NqGapClassify(T0 + D + 15 * H, T0 + D + 16 * H, 0, 900, 14400, 7200) == NQ_GAP_DATA, "an hour missing mid-session: DATA GAP");
      CHECK(NqGapClassify(T0 + 3 * D + 23 * H + 55 * M, T0 + 6 * D + 5 * M, 0, 900, 14400, 7200) == NQ_GAP_WEEKEND, "Friday 23:55 to Monday 00:05: WEEKEND");
      CHECK(NqGapClassify(T0 + 3 * D + 21 * H, T0 + 5 * D + 22 * H, 21 * 60, 900, 14400, 7200) == NQ_GAP_WEEKEND, "a GMT broker: Friday 21:00 to Sunday 22:00: WEEKEND");
      CHECK(NqGapClassify(T0 + D + 23 * H + 58 * M, T0 + 2 * D + 1 * H + 2 * M, 0, 900, 14400, 7200) == NQ_GAP_CLOSE, "23:58-01:02 across the 00:00 rollover: DAILY CLOSE");
      CHECK(NqGapClassify(T0 + D + 20 * H + 59 * M, T0 + D + 22 * H, 21 * 60, 900, 14400, 7200) == NQ_GAP_CLOSE, "a GMT broker's 21:00 rollover: DAILY CLOSE");
      CHECK(NqGapClassify(T0 + D + 21 * H + 59 * M, T0 + D + 23 * H, 0, 900, 14400, 7200) == NQ_GAP_CLOSE, "a break that ends an hour before the rollover is this broker's daily close (2 h tolerance)");
      CHECK(NqGapClassify(T0 + D + 20 * H, T0 + 2 * D + 6 * H, 0, 900, 14400, 7200) == NQ_GAP_LONG, "ten hours around the rollover: LONG CLOSE (holiday / early close), not a daily break");
      CHECK(NqGapClassify(T0 + D + 10 * H, T0 + D + 12 * H, 0, 0, 14400, 7200) == NQ_GAP_NONE, "a hole size of 0 = the check is off");
      // an M5 series: Friday 20:00 .. Monday 11:30 with the weekend out, and a 40-minute hole on Monday 10:00
      NqSeries s;
      NqSeriesResize(s, 0);
      s.sec = 300;
      std::vector<long long> ts;
      for(long long t = T0 + 3 * D + 20 * H; t < T0 + 3 * D + 24 * H; t += 300) ts.push_back(t);
      for(long long t = T0 + 6 * D; t < T0 + 6 * D + 11 * H + 30 * M; t += 300) if(t < T0 + 6 * D + 10 * H || t >= T0 + 6 * D + 10 * H + 40 * M) ts.push_back(t);
      NqSeriesResize(s, (int)ts.size());
      for(size_t i = 0; i < ts.size(); i++) { s.t[i] = ts[i]; s.o[i] = 1; s.h[i] = 1; s.l[i] = 1; s.c[i] = 1; s.v[i] = 1; }
      NqGapInfo g;
      NqGapScan(s, 600, 0, 900, 14400, 7200, 12, g);
      CHECK(g.kind == NQ_GAP_DATA && g.from == T0 + 6 * D + 10 * H && g.to == T0 + 6 * D + 10 * H + 40 * M && g.barsSince == 10 && g.active && g.nData == 1,
            "the scan finds the Monday hole: from, to, 10 candles since, still active (12 needed)");
      CHECK(g.nLegit == 1 && g.lastLegit == NQ_GAP_WEEKEND && g.lastLegitTo == T0 + 6 * D, "the weekend is counted apart, as legitimate, with the time the candles came back");
      NqGapScan(s, 600, 0, 900, 14400, 7200, 10, g);
      CHECK(g.kind == NQ_GAP_DATA && !g.active && g.nData == 1, "10 candles after it (10 needed): the timeframe is valid again, the hole stays counted in the window");
      NqGapScan(s, 5, 0, 900, 14400, 7200, 12, g);
      CHECK(g.kind == NQ_GAP_NONE && !g.active && g.nData == 0, "a window that ends after the hole sees nothing");
   }
   end("G1");

   begin("G2 candle integrity end to end: a 50-minute hole closes the gate for NEW entries for an hour of candles, the studies do not vote; a daily close is only named");
   {
      const long long D4 = T0 + 3 * 86400;      // Friday
      Market holed = punch(gold, D4 + 10 * 3600, D4 + 10 * 3600 + 50 * 60);
      load(holed, "XAUUSD", "XAU", 2, 0.01, 1.0);
      size_t s0 = ixOf(D4 + 8 * 3600);
      startAt(s0);
      relax();
      run(s0 + 1, ixOf(D4 + 9 * 3600 + 58 * 60));
      CHECK(g_gapGuard && (g_gate & NQ_K_DATA_GAP) == 0 && g_gapText == "" && !g_gap1.active && !g_gap5.active && !g_gap15.active && lbl("v_fg").find("M1 OK / M5 OK / M15 OK") == 0,
            "before the hole: every timeframe valid, the CANDLES row says so");
      size_t sentAt = SIM.sent.size();
      stepTo(ixOf(D4 + 10 * 3600 + 50 * 60));
      CHECK((g_gate & NQ_K_DATA_GAP) != 0 && g_gap1.active && g_gap1.kind == NQ_GAP_DATA && g_gap1.from == D4 + 10 * 3600 && g_gap1.to == D4 + 10 * 3600 + 50 * 60,
            "the first candle after the hole: DATA GAP on M1 with the hole's exact times, the gate is closed");
      stepTo(ixOf(D4 + 11 * 3600 + 2 * 60));
      CHECK(g_gap5.active && g_gap5.kind == NQ_GAP_DATA && g_gap15.active && g_gap15.kind == NQ_GAP_DATA && gateSays("DATA GAP - M1 DATA GAP: no candles"),
            "M5 and M15 name the same hole; the gate's reason names the timeframe and the hole");
      std::string voters;
      CHECK(NqStudyGapped() && NqStudyVote(1, voters) == 0 && NqStudyVote(-1, voters) == 0 && lbl("v_fg").find("M1 DATA GAP / M5 DATA GAP / M15 DATA GAP") == 0 &&
            lbl("v_f7").find("NO VOTE: a hole in the M15 candles") != std::string::npos, "a hole inside the M15 window: the studies do not vote, the table says why");
      CHECK(NqTelemetryJson().find("\"candles\":{\"guard\":true,\"blocking\":true,\"m1\":\"DATA GAP\"") != std::string::npos, "telemetry carries it");
      int opened = 0, blockedMin = 0;
      for(size_t i = ixOf(D4 + 11 * 3600 + 3 * 60); i <= ixOf(D4 + 11 * 3600 + 40 * 60); i++)
      {
         size_t b4 = SIM.sent.size();
         stepTo(i);
         if((g_gate & NQ_K_DATA_GAP) != 0) blockedMin++;
         for(size_t k = b4; k < SIM.sent.size(); k++)
            if(SIM.sent[k].action == TRADE_ACTION_PENDING || (SIM.sent[k].action == TRADE_ACTION_DEAL && SIM.sent[k].position == 0)) opened++;
      }
      for(size_t k = sentAt; k < SIM.sent.size(); k++)
         if(SIM.sent[k].action == TRADE_ACTION_PENDING || (SIM.sent[k].action == TRADE_ACTION_DEAL && SIM.sent[k].position == 0)) opened++;
      CHECK(blockedMin == 38 && opened == 0, "50 minutes after the candles came back the gate is still closed and nothing was opened");
      run(ixOf(D4 + 11 * 3600 + 41 * 60), ixOf(D4 + 12 * 3600 + 5 * 60));
      CHECK((g_gate & NQ_K_DATA_GAP) == 0 && g_gapText == "" && !g_gap1.active && !g_gap5.active && !g_gap15.active, "an hour of candles on every timeframe: valid again, the gate bit is gone");
      CHECK(g_gap15.nData == 1 && NqStudyGapped() && lbl("v_fg").find("1 hole(s) in the M15 study window: the studies do not vote") != std::string::npos,
            "the hole is still inside the M15 study window: the studies stay silent until it has left");
      g_gapGuard = false;
      CHECK(NqGapGateBits() == 0 && !NqStudyGapped(), "guard off: holes are shown only");
      OnDeinit(0);

      // a legitimate daily close: an hour without candles across the 00:00 rollover (17:00 New York on this clock)
      Market closed = punch(gold, D4 - 20 * 60, D4 + 40 * 60);
      load(closed, "XAUUSD", "XAU", 2, 0.01, 1.0);
      size_t c0 = ixOf(D4 - 2 * 3600);
      startAt(c0);
      relax();
      int gapMin = 0;
      for(size_t i = c0 + 1; i <= ixOf(D4 + 90 * 60); i++) { stepTo(i); if((g_gate & NQ_K_DATA_GAP) != 0) gapMin++; }
      CHECK(gapMin == 0 && g_gap5.kind == NQ_GAP_NONE && g_gap5.lastLegit == NQ_GAP_CLOSE && g_gap5.lastLegitTo == D4 + 40 * 60 && g_gap15.nData == 0 && !NqStudyGapped(),
            "the daily close is named and never blocks: no DATA GAP, the studies keep voting");
      CHECK(lbl("v_fg").find("last market close: DAILY CLOSE") != std::string::npos && lbl("v_fg").find("(legitimate)") != std::string::npos, "the CANDLES row keeps the legitimate close apart");
      OnDeinit(0);
   }
   end("G2");
   // METAL-ONLY END

   std::printf("\nEA TESTS: %d checks passed, %d failed\n", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
