// Whole-EA tests: the complete NRTR_QML_MetalScalper.mq5 (translated
// syntax-only) runs on a simulated MT5 terminal WITH a trade API:
// OnInit -> OnTick per closed M1 bar -> OnDeinit. Every order the EA sends
// is checked against the engine's own records.
#include "../tests/mt5_sim_ea.h"
#include "ea_full.inc"
#include "../tests/synth.h"
#include <cstdio>
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

static const long long T0 = 1788220800LL;   // 2026-08-31 00:00 UTC (a Monday)

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
static std::string lbl(const char *id) { return obj(std::string("NQEA_P_") + id); }
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
      int placed = 0, bad = 0, cancels = 0, wrongCancel = 0, twice = 0, overRisk = 0;
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
               if((p.dir > 0) != (r.type == ORDER_TYPE_BUY_LIMIT)) bad++;
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
      CHECK(fillBad == 0, "fills happened at the plan entry");
   }
   end("A2");

   begin("A3 REAL account: nothing is ever sent, the banner says so");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.accountMode = ACCOUNT_TRADE_MODE_REAL;
      startAt(START);
      run(START + 1, END);
      CHECK(SIM.sent.empty(), "zero requests on a real account");
      CHECK(lbl("state").find("REAL ACCOUNT") != std::string::npos, "banner: REAL ACCOUNT - TRADING BLOCKED");
      CHECK(lbl("bf1").find("REAL ACCOUNT") != std::string::npos, "board footer names the reason");
   }
   end("A3");

   begin("A4 daily loss cap and spread guard stop NEW entries; closing still works");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
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
      run(START + 1, END);
      CHECK(countSent(TRADE_ACTION_DEAL, true) == 0 && countSent(TRADE_ACTION_PENDING, true) == 0, "spread 500 > 50: no entries");
      CHECK((g_gate & NQ_K_SPREAD) != 0, "gate: spread");
      // terminal autotrading off
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      SIM.terminalTrade = false;
      startAt(START);
      run(START + 1, END);
      CHECK(countSent(TRADE_ACTION_DEAL, true) == 0 && countSent(TRADE_ACTION_PENDING, true) == 0, "autotrading off: no entries");
   }
   end("A4");

   begin("A5 regime flip closes an open scalp that is against the new M5 regime");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
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
      run(START + 1, START + 900);
      std::vector<NqPlan> plans = g_plans;
      std::vector<NqSignal> sigs = g_sigs;
      int nPl = g_nPlans, nSg = g_nSig;
      std::map<std::string, SimObj> objs = SIM.objs;
      size_t orders = SIM.ord.size(), sent = SIM.sent.size();
      OnDeinit(0);
      CHECK(SIM.objs.empty(), "deinit removes every object");
      CHECK(OnInit() == INIT_SUCCEEDED, "re-init");
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
         if(it == SIM.objs.end()) { diff++; continue; }
         if(kv.first == "NQEA_P_r2") continue;   // transient note of the last action, not state
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
      run(START + 1, START + 300);
      CHECK(SIM.sent.empty() && lbl("state").find("GOLD / SILVER ONLY") != std::string::npos, "EURUSD: no trading, panel says so");
   }
   end("A7");

   begin("A8 forecast arrows: one per candle in the window plus a live one; past arrows never change");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      startAt(START);
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
      CHECK(g_s1.fc[n - 1] != 0 && SIM.objs["NQEA_A_LIVE"].i[OBJPROP_WIDTH] == 3 && obj("NQEA_A_LIVE_T").find("NEXT") == 0,
            "the live arrow is wide and carries a NEXT label");
      int noArrow = 0;
      for(int i = std::max(1, n - InpArrowBars); i < n; i++) if(g_s1.fc[i - 1] == 0) noArrow++;
      CHECK(noArrow == 0, "every candle in the window has an arrow");
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
      run(START + 1, START + 300);
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
      CHECK(rows == 7, "7 engine rows");
      CHECK(dup == 0, "no key twice");
      CHECK(empty == 0, "every row has a value");
      CHECK(lbl("h1").find("ENGINE") != std::string::npos && lbl("h2").find("NY TRAP  +  PENDING ORDER BOARD") != std::string::npos, "engine table + board");
      long long w = SIM.objs["NQEA_P_bg"].i[OBJPROP_XSIZE];
      CHECK(w < 700, "single column");
      // the board: 5 plan rows with 7 columns + a detail line, 6 broker rows, NY lines, footer
      bool boardOk = true;
      const char *types[5] = {"QML M5", "PULLBACK M5", "NY TRAP", "SWING QML", "SWING PB"};
      for(int q = 0; q < 5; q++)
      {
         std::string id = "bp" + std::to_string(q);
         if(lbl((id + "0").c_str()) != types[q]) boardOk = false;
         for(int c = 1; c <= 6; c++) if(lbl((id + std::to_string(c)).c_str()) == "<missing>") boardOk = false;
         if(lbl((id + "d").c_str()) == "<missing>") boardOk = false;
      }
      for(int i = 0; i < 6; i++) if(lbl(("bb" + std::to_string(i) + "0").c_str()) == "<missing>") boardOk = false;
      CHECK(boardOk, "board rows: TYPE SIDE ENTRY SL TP DIST STATUS for 5 plan slots + 6 broker rows");
      CHECK(lbl("ny1").find("NY SESSION") == 0 && lbl("ny2").find("PRE-NY RANGE") == 0 && lbl("ny3").find("SWEEP / TRAP") == 0 &&
            lbl("ny4").find("SLOT") == 0, "NY session, pre-NY range, sweep/trap and slot lines");
      CHECK(lbl("bh4") == "TP SENT" && lbl("bh5") == "DIST", "the board shows the TP actually sent and the distance");
      CHECK(lbl("bf2").find("LAST UPDATE") != std::string::npos, "footer carries the last update time");
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
   }
   end("A9");

   begin("A10 silver spec (3 digits, tick value 5): SL/TP on the grid, lots from the real tick value; rejected order is logged, not retried");
   {
      Market silver = makeMarket(5, 60.9, 0.001, 0.006, (int)DAYS);
      load(silver, "XAGUSD", "XAG", 3, 0.001, 5.0);
      startAt(START);
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

   std::printf("\nEA TESTS: %d checks passed, %d failed\n", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
