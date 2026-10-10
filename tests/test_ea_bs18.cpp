// Whole-EA tests: BrotherSniperULTIMATE_v18_MT5.mq5 (the Pine twin, translated
// syntax-only) on a simulated MT5 terminal with a trade API. The chart is M5
// (the Pine ran on 5m / 15m), the broker serves H1 / H4 / D1 / W1 of the
// symbol, a dollar index (M1 + D1), a 10-year yield (D1) and oil (H1).
#include "../tests/mt5_sim_ea.h"
#include "ea_full_bs18.inc"
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
struct Market { std::vector<SBar> m1, m5, h1, h4, d1, w1; };
static Market makeMarket(uint64_t seed, double price, double tick, double vol, int days)
{
   Market m;
   m.m1 = gen1m(seed, days * 1440, T0, price, tick, vol);
   m.m5 = agg(m.m1, 300);
   m.h1 = agg(m.m5, 3600);
   m.h4 = agg(m.m5, 14400);
   m.d1 = agg(m.m5, 86400);
   m.w1 = agg(m.m5, 604800);
   return m;
}
static void load(const Market &m, const char *sym, const char *base, int digits, double tick, double tickValue)
{
   SIM = SimState();
   SIM.sym = sym; SIM.base = base; SIM.profit = "USD";
   SIM.digits = digits; SIM.tick = tick; SIM.point = tick; SIM.tickValue = tickValue;
   SIM.m1 = toRates(m.m1); SIM.m5 = toRates(m.m5); SIM.h1 = toRates(m.h1); SIM.h4 = toRates(m.h4); SIM.d1 = toRates(m.d1); SIM.w1 = toRates(m.w1);
   SIM.gmtOffsetSec = 3 * 3600;
   _Symbol = sym;
   _Period = PERIOD_M5;
}
static void addWitnesses(uint64_t seed)
{
   Market dxy = makeMarket(seed + 1, 103.5, 0.001, 0.0004, 9);
   SIM.extraTf["USDX"][PERIOD_M1] = toRates(dxy.m1);
   SIM.extraTf["USDX"][PERIOD_D1] = toRates(dxy.d1);
   Market yld = makeMarket(seed + 2, 4.25, 0.001, 0.0008, 9);
   SIM.extraTf["US10Y"][PERIOD_D1] = toRates(yld.d1);
   Market oil = makeMarket(seed + 3, 71.0, 0.01, 0.02, 9);
   SIM.extraTf["USOIL"][PERIOD_H1] = toRates(oil.h1);
}
// the M5 bar at index i has just closed
static int startAt(size_t i)
{
   SIM.now = SIM.m5[i].time + 300;
   SIM.bid = SIM.m5[i].close;
   return OnInit();
}
static void stepTo(size_t i)
{
   const MqlRates &b = SIM.m5[i];
   SIM.now = b.time; SIM.bid = b.open;
   simBarPath(b);
   SIM.bid = b.close; SIM.now = b.time + 300;
   OnTick();
}
static void run(size_t from, size_t to) { for(size_t i = from; i <= to; i++) stepTo(i); }
static std::string obj(const std::string &name, int prop = OBJPROP_TEXT)
{
   auto it = SIM.objs.find(name);
   if(it == SIM.objs.end()) return "<missing>";
   return it->second.s[prop];
}
static std::string cell(const char *tbl, int r, int c) { return obj(std::string("BS18_T_") + tbl + "_" + std::to_string(r) + "_" + std::to_string(c)); }
static int countObjs(const std::string &prefix) { int n = 0; for(auto &kv : SIM.objs) if(kv.first.compare(0, prefix.size(), prefix) == 0) n++; return n; }
static int countSent(int action) { int n = 0; for(const MqlTradeRequest &r : SIM.sent) if((int)r.action == action) n++; return n; }

int main()
{
   const int DAYS = 9;                 // Tue 1 .. Wed 9 September: a Monday (the 7th) is inside for the NWOG
   Market gold = makeMarket(7, 4150.0, 0.01, 0.35, DAYS);
   const size_t START = 288 * 5 + 10;  // day 6 (Sunday the 6th), bar 10
   const size_t END = 288 * DAYS - 2;

   begin("B1 init on a gold chart: market detected, pipZone 1.00, whitelist PASS, the three witnesses resolved, journal armed only by the secret");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      addWitnesses(7);
      CHECK(startAt(START) == INIT_SUCCEEDED, "init");
      CHECK(g_market == "Gold" && near(g_pipZone, 1.0) && g_symbolAllowed, "Gold, pipZone 1.00, whitelisted");
      CHECK(g_dxySym == "USDX" && g_yldSym == "US10Y" && g_oilSym == "USOIL", "dollar index, yield and oil found at the broker");
      CHECK(g_isDemo && g_periodSec == 300 && g_intraday, "demo, M5 chart");
      CHECK(std::string(InpSignalMeshUrl).find("https://app.signalmesh.dev/webhooks/brain/signal") == 0 && std::string(InpSignalMeshSecret).empty() && g_webUrl.empty(),
            "the journal address is preset but without the secret nothing is posted");
      OnDeinit(0);
      CHECK(countObjs("BS18_") == 0, "deinit removes every object of the EA");
   }
   end("B1");

   begin("B2 one tick: the window, the indicators, the five tables with the Pine's rows, the live levels, the history annotations");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      addWitnesses(7);
      startAt(START);
      stepTo(START + 1);
      CHECK(g_n >= 300 && g_n <= 1500, "the window holds the last bars");
      CHECK(g_haveH1 && g_haveH4 && g_haveD1 && g_haveW1 && g_haveDxy && g_haveYld && g_haveOil, "every series loaded");
      CHECK(cell("main", 0, 0) == "Gold" && cell("main", 1, 0) == "BIAS" && cell("main", 2, 0) == "Score BUY" && cell("main", 3, 0) == "Score SELL", "main dash header + bias + scores");
      CHECK(cell("main", 7, 0) == "15m Trend" && cell("main", 13, 0) == "RSI" && cell("main", 21, 0) == "CHoCH" && cell("main", 24, 0) == "FVG", "main dash rows keep the Pine's order");
      CHECK(cell("main", 44, 0) == "Fires Today" && cell("main", 50, 0) == "DXY Squelch" && cell("main", 52, 0) == "US 10Y Yield" && cell("main", 53, 0) == "Adaptive", "the last rows");
      CHECK(cell("pend", 0, 0) == "STRUCTURAL BRAIN" || cell("pend", 0, 0).find("FORMING") != std::string::npos, "structural brain title");
      CHECK(cell("pend", 1, 0) == "Entry" && cell("pend", 9, 0) == "Trigger" && cell("pend", 16, 0) == "PDH" && cell("pend", 31, 0) == "Daily VWAP" && cell("pend", 34, 0) == "Status", "brain rows");
      CHECK(cell("pvt", 0, 0) == "PIVOT" && cell("pvt", 4, 0) == "PP" && cell("pvt", 9, 0) == "Bias", "pivot table");
      CHECK(cell("man", 1, 0) == "Status" && cell("man", 8, 0) == "Gate", "manual monitor");
      CHECK(cell("ss", 2, 0) == "ENTRY" && cell("ss", 6, 0) == "GRADE" && cell("ss", 11, 0) == "Panels", "smart scalp panel");
      CHECK(cell("main", 2, 1).find("/10") != std::string::npos && cell("main", 3, 1).find("/10") != std::string::npos, "scores print x/10");
      CHECK(!NA(g_out.pdHigh) && !NA(g_out.pivotP) && !NA(g_out.wHigh), "PDH, the pivots and the weekly high come from the closed D1 / W1 bars");
      CHECK(g_out.pivotR1 > g_out.pivotP && g_out.pivotS1 < g_out.pivotP, "R1 above PP above S1");
      CHECK(obj("BS18_L_pdh") != "<missing>" && obj("BS18_L_pp") != "<missing>", "PDH and PP lines drawn");
      CHECK(countObjs("BS18_E_") > 20, "history annotations drawn (swings, S/R, FVG, OB ...)");
      CHECK(g_out.rsiValue > 0 && g_out.rsiValue < 100 && g_out.atrValue > 0 && g_out.adxVal >= 0, "RSI / ATR / ADX sane");
      CHECK(!g_out.dxyTxt.empty() && g_out.yieldTxt != "N/A" && g_out.yieldTxt != "OFF", "DXY and yield rows read the witnesses");
      OnDeinit(0);
   }
   end("B2");

   begin("B3 the clock: DST-aware sessions, killzones and news windows in New York time; ORG / midnight / NWOG latch on the chart's own bars");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      addWitnesses(7);
      startAt(START);
      // September: US + EU daylight time. Server = GMT+3. 09:30 New York = 13:30 GMT = 16:30 server.
      datetime mon = T0 + 6 * 86400;              // Monday the 7th, 00:00 GMT = 03:00 server
      datetime nyOpenSrv = mon + 16 * 3600 + 30 * 60;
      CHECK(BsMod(BsNyLocal(nyOpenSrv)) == BsHM(9, 30), "16:30 server is 09:30 New York in September");
      CHECK(BsMod(BsLonLocal(mon + 9 * 3600)) == BsHM(7, 0), "09:00 server is 07:00 London (BST)");
      CHECK(BsMod(BsTokyoLocal(mon + 9 * 3600)) == BsHM(15, 0), "09:00 server is 15:00 Tokyo");
      CHECK(BsUsDst(T0) && BsEuDst(T0) && !BsUsDst(T0 + 70 * 86400) && !BsEuDst(T0 + 70 * 86400), "DST on in September, off in November");
      // run through Monday: the 00:00 NY bar (07:00 server) latches NWOG + midnight, the 09:30 NY bar latches the ORG
      size_t monIdx = (size_t)((mon + 7 * 3600 - T0) / 300);
      run(START + 1, monIdx + 130);
      CHECK(!NA(g_out.midnightOpen) && near(g_out.midnightOpen, SIM.m5[monIdx].open, 1e-9), "midnight open = the 00:00 NY bar's open");
      CHECK(!NA(g_out.nwogOpen) && near(g_out.nwogOpen, SIM.m5[monIdx].open, 1e-9), "NWOG = Monday's 00:00 NY bar open");
      size_t orgIdx = (size_t)((nyOpenSrv - T0) / 300);
      CHECK(!NA(g_out.orgHigh) && near(g_out.orgHigh, SIM.m5[orgIdx].high, 1e-9) && near(g_out.orgLow, SIM.m5[orgIdx].low, 1e-9), "ORG = the 09:30 NY bar's high / low");
      // the live bar at the ORG bar: NEW YORK session, Cash Open killzone, not a news window
      stepTo(orgIdx - 1);
      CHECK(g_out.inNewYork && g_out.inLondon && g_out.sessionTxt == "NEW YORK", "09:30 NY: New York (and London still open)");
      CHECK(g_out.inKzOpen && g_out.inAnyNYKz && g_out.kzLabel.find("Cash Open") == 0 && g_out.nyRegime == "TRAP", "Cash Open killzone, metals = TRAP regime");
      CHECK(!g_out.inNewsWindow, "09:30 is outside the 08:25-09:05 news window");
      CHECK(!NA(g_out.lonH) && !NA(g_out.asiaH), "Asia and London ranges recorded");
      // 08:30 NY = 15:30 server: pre-open killzone + news window
      size_t preIdx = (size_t)((mon + 15 * 3600 + 30 * 60 - T0) / 300);
      stepTo(preIdx - 1);
      CHECK(g_out.inKzPre && g_out.inNewsWindow, "08:30 NY: pre-open killzone and the data news window");
      OnDeinit(0);
   }
   end("B3");

   begin("B4 SMART SCALP fire -> ONE market order with the Pine's SL / TP1 and a risk-sized lot; the journal line carries the payload; a second tick does not resend");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      addWitnesses(7);
      startAt(START);
      stepTo(START + 1);
      g_webUrl = "https://status.example/webhooks/brain/signal";
      g_webSecret = "s3cr3t-token";
      SIM.sent.clear(); SIM.web.clear();
      // plant the confirmed-bar snapshot the pass would have produced
      g_fire.bar = g_t[g_n - 2];
      g_fire.ssBuy = true; g_fire.ssSell = false; g_fire.ssEntry = SIM.bid; g_fire.ssSL = SIM.bid - 6.0; g_fire.ssTP1 = SIM.bid + 7.0; g_fire.ssTP2 = SIM.bid + 11.0;
      g_fire.ssRR = 1.17; g_fire.ssLots = 0.0; g_fire.ssGrade = "A"; g_fire.ssScore = 8;
      g_lastFireBar = 0;
      BsTrade(true);
      CHECK(countSent(TRADE_ACTION_DEAL) == 1, "one market order");
      const MqlTradeRequest &r = SIM.sent[0];
      CHECK(r.type == ORDER_TYPE_BUY && r.magic == (ulong)InpMagic && r.comment.compare(0, 7, "SS-BUY-") == 0, "BUY, our magic, SS-BUY-<stamp> comment");
      CHECK(near(r.sl, NormalizeDouble(SIM.bid - 6.0, 2), 1e-9) && near(r.tp, NormalizeDouble(SIM.bid + 7.0, 2), 1e-9), "SL / TP = the snapshot's");
      double lossAtSl = r.volume * std::fabs(r.price - r.sl) / 0.01 * 1.0;
      CHECK(r.volume > 0 && lossAtSl <= SIM.balance * InpRiskPct / 100.0 + 1e-6 && lossAtSl > SIM.balance * InpRiskPct / 100.0 * 0.8, "lot sized to the risk input from the real tick value");
      CHECK(SIM.web.size() == 2, "two journal POSTs: fired, then executed");
      bool hdr = true, sys = true, keys = true;
      for(auto &w : SIM.web)
      {
         if(w.headers.find("X-Brain-Secret: s3cr3t-token") == std::string::npos) hdr = false;
         if(w.body.find("\"system\":\"BS-MT5\"") == std::string::npos) sys = false;
         for(const char *k : {"\"type\":\"SMART_SCALP\"", "\"signal\":\"BUY\"", "\"signal_id\":\"SS-BUY-", "\"symbol\":\"XAUUSD\"", "\"tf\":\"5\"", "\"entry\":", "\"sl\":", "\"tp1\":", "\"tp2\":", "\"rr\":", "\"grade\":\"A\"", "\"pine_ver\":\"18.12\"", "\"payload_schema\":2", "\"struct\":", "\"event\":", "\"status\":", "\"account_mode\":\"demo\"", "\"magic\":180918"})
            if(w.body.find(k) == std::string::npos) keys = false;
      }
      CHECK(hdr && sys && keys, "secret in the header; system BS-MT5 (never v18, never v7); the Pine's payload fields");
      CHECK(SIM.web[0].body.find("\"event\":\"fired\"") != std::string::npos && SIM.web[1].body.find("\"event\":\"executed\"") != std::string::npos && SIM.web[1].body.find("\"status\":\"executed\"") != std::string::npos, "fired then executed, never 'approved'");
      bool secretPrinted = false;
      for(auto &l : SIM.log) if(l.find("s3cr3t") != std::string::npos) secretPrinted = true;
      CHECK(!secretPrinted, "the secret is never printed");
      BsTrade(true);
      CHECK(countSent(TRADE_ACTION_DEAL) == 1, "the same confirmed bar is acted on once");
      BsScanAccount();
      CHECK(g_openCount == 1 && g_tradesToday == 1, "the position is counted: one open, one fill today");
      CHECK(NqRiskGate() == "MAX POSITIONS 1", "max open positions (1) now gates");
      OnDeinit(0);
   }
   end("B4");

   begin("B5 PULLBACK arm -> a resting BUY LIMIT at the armed entry; the arm's death pulls it; a DXY squelch pulls it too");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      addWitnesses(7);
      startAt(START);
      stepTo(START + 1);
      g_webUrl = "https://status.example/webhooks/brain/signal";
      g_webSecret = "s3cr3t-token";
      SIM.sent.clear(); SIM.web.clear(); SIM.pos.clear(); SIM.ord.clear();
      g_fire.bar = g_t[g_n - 2];
      g_fire.ssBuy = false; g_fire.ssSell = false;
      g_fire.armBuyE = SIM.bid - 9.0; g_fire.armBuySL = SIM.bid - 14.0; g_fire.armBuyT1 = SIM.bid - 4.0; g_fire.armBuyT2 = SIM.bid; g_fire.armBuyBar = g_n - 10; g_fire.armBuyT = g_t[g_n - 10];
      g_fire.armSellE = EMPTY_VALUE;
      g_fire.pbCoolOK = true; g_fire.pbHrOK = true; g_fire.squelched = false; g_fire.newsBlock = false; g_fire.pbAln = true;
      g_out.pbBuySrc = "SWING24";
      BsTrade(true);
      CHECK(countSent(TRADE_ACTION_PENDING) == 1, "one limit order");
      const MqlTradeRequest &r = SIM.sent[0];
      CHECK(r.type == ORDER_TYPE_BUY_LIMIT && near(r.price, NormalizeDouble(SIM.bid - 9.0, 2), 1e-9) && near(r.sl, NormalizeDouble(SIM.bid - 14.0, 2), 1e-9) && near(r.tp, NormalizeDouble(SIM.bid - 4.0, 2), 1e-9), "BUY LIMIT at the armed entry with the Pine's stop (1.5 ATR beyond the level) and TP1");
      CHECK(r.comment.compare(0, 12, "BS18-PB-BUY-") == 0 && r.magic == (ulong)InpMagic, "comment names the arm, our magic");
      CHECK(SIM.web.size() == 1 && SIM.web[0].body.find("\"type\":\"PULLBACK\"") != std::string::npos && SIM.web[0].body.find("\"event\":\"placed\"") != std::string::npos && SIM.web[0].body.find("\"level_src\":\"SWING24\"") != std::string::npos, "journal: PULLBACK placed with its level source");
      BsTrade(true);
      CHECK(countSent(TRADE_ACTION_PENDING) == 1 && SIM.ord.size() == 1, "the same arm is not placed twice");
      // the arm dies (TREND FLIP): the order is pulled with the reason
      g_fire.armBuyE = EMPTY_VALUE;
      g_out.pbBuyDeath = "TREND FLIP";
      BsTrade(false);
      CHECK(countSent(TRADE_ACTION_REMOVE) == 1 && SIM.ord.empty(), "the dead arm's order is cancelled");
      CHECK(SIM.web.size() == 2 && SIM.web[1].body.find("\"event\":\"cancelled\"") != std::string::npos && SIM.web[1].body.find("TREND FLIP") != std::string::npos, "journal: cancelled, TREND FLIP");
      // re-armed, then a DXY squelch: pulled while the squelch lasts, re-placed on the next bar after it
      g_fire.armBuyE = SIM.bid - 9.0; g_fire.armBuyT = g_t[g_n - 5];
      BsTrade(true);
      CHECK(SIM.ord.size() == 1, "re-armed: a new order");
      g_fire.squelched = true;
      BsTrade(false);
      CHECK(SIM.ord.empty(), "squelch: pulled");
      g_fire.squelched = false;
      BsTrade(true);
      CHECK(SIM.ord.size() == 1, "squelch over: back");
      OnDeinit(0);
   }
   end("B5");

   begin("B6 the risk gate: Algo Trading off = nothing is sent; a fire still journals; the daily counters follow this EA's own deals");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      addWitnesses(7);
      startAt(START);
      stepTo(START + 1);
      SIM.terminalTrade = false;
      BsScanAccount();
      CHECK(NqRiskGate() == "ALGO TRADING OFF", "the Algo Trading button is the switch");
      SIM.sent.clear(); SIM.web.clear();
      g_fire.bar = g_t[g_n - 2]; g_fire.ssBuy = true; g_fire.ssSL = SIM.bid - 6.0; g_fire.ssTP1 = SIM.bid + 7.0; g_fire.ssTP2 = SIM.bid + 11.0; g_fire.ssGrade = "B"; g_fire.ssScore = 7; g_fire.ssRR = 1.2;
      g_lastFireBar = 0;
      BsTrade(true);
      CHECK(countSent(TRADE_ACTION_DEAL) == 0 && countSent(TRADE_ACTION_PENDING) == 0, "no order with the button off (a resting order may be pulled)");
      stepTo(START + 2);
      CHECK(cell("main", 43, 1) == "ALGO TRADING OFF", "the Risk Gate row says why");
      SIM.terminalTrade = true;
      SIM.accountMode = ACCOUNT_TRADE_MODE_REAL;
      BsScanAccount();
      CHECK(NqRiskGate() == "", "a real account trades when InpAllowRealAccount is true (the operator's decision)");
      OnDeinit(0);
   }
   end("B6");

   begin("B7 the replay over the whole market: deterministic, no crash, fires only on confirmed bars, annotations capped, the DXY squelch reads the 1-minute bars");
   {
      load(gold, "XAUUSD", "XAU", 2, 0.01, 1.0);
      addWitnesses(7);
      startAt(START);
      int fires = 0, pbFires = 0;
      datetime lastSs = 0, lastPb = 0;
      for(size_t i = START + 1; i <= END; i++)
      {
         stepTo(i);
         if(V.ssFireBarT != lastSs) { fires++; lastSs = V.ssFireBarT; CHECK(V.ssFireBarT <= g_t[g_n - 2], "a scalp fire is never on the live bar"); }
         if(V.pbFireBarT != lastPb) { pbFires++; lastPb = V.pbFireBarT; }
      }
      std::printf("    scalp fires %d, pullback fires %d, market orders %d, limit orders %d, events %d\n", fires, pbFires, countSent(TRADE_ACTION_DEAL), countSent(TRADE_ACTION_PENDING), g_nEv);
      CHECK(g_nEv <= BS_EV_MAX, "annotation list capped");
      BsOut a = g_out;
      BsPass(false);
      CHECK(a.scoreBuy == g_out.scoreBuy && a.scoreSell == g_out.scoreSell && a.trend == g_out.trend && a.fibZoneTxt == g_out.fibZoneTxt && near(a.pivotP, g_out.pivotP), "a second pass over the same bars gives the same readings");
      // DXY squelch: a wild 1-minute bar of the dollar index inside the live chart bar
      datetime live = g_t[g_n - 1];
      auto &dm1 = SIM.extraTf["USDX"][PERIOD_M1];
      for(auto &b : dm1) if(b.time >= live && b.time < live + 300) { b.high = b.close * 1.004; b.low = b.close * 0.996; }
      BsDxySquelchScan();
      CHECK(g_dxyM1Has && g_dxyM1Pct >= 0.7 && g_squelchUntil > SIM.now, "a 0.8% one-minute range arms the squelch");
      BsPass(false);
      BsDrawAll(false);
      CHECK(g_out.dxySquelched && cell("main", 50, 1).find("ACTIVE") == 0, "the panel says ACTIVE with the seconds left");
      OnDeinit(0);
   }
   end("B7");

   std::printf("\nBS18 EA TESTS: %d checks passed, %d failed\n", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
