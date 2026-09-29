// Simulated MT5 terminal WITH a trade API, for running the whole EA under
// g++. Market data, positions, pending orders, deal history, account and
// chart objects are all in-memory. simStep() walks one M1 bar: it fills
// limit orders, triggers SL/TP (stop first, pessimistically), moves the
// clock past the bar's close and calls OnTick(), exactly once per bar.
//
// STILL DELIBERATELY ABSENT: WebRequest, Socket*, SendNotification,
// SendMail, FileOpen, DLL imports. Referencing them fails the build.
#pragma once
#include "mql_shim.h"
#include <ctime>
#include <map>

struct MqlRates
{
   datetime time;
   double open;
   double high;
   double low;
   double close;
   long long tick_volume;
   int spread;
   long long real_volume;
};

enum ENUM_TIMEFRAMES { PERIOD_CURRENT = 0, PERIOD_M1 = 1, PERIOD_M5 = 5, PERIOD_M15 = 15, PERIOD_H1 = 16385 };
inline int PeriodSeconds(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1: return 60;
      case PERIOD_M5: return 300;
      case PERIOD_M15: return 900;
      case PERIOD_H1: return 3600;
      default: return 900;
   }
}

enum { INIT_SUCCEEDED = 0, INIT_FAILED = 1, INIT_PARAMETERS_INCORRECT = 2 };
enum { SYMBOL_DIGITS = 1, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL, SYMBOL_FILLING_MODE, SYMBOL_SPREAD,
       SYMBOL_TRADE_TICK_SIZE, SYMBOL_POINT, SYMBOL_TRADE_TICK_VALUE, SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX,
       SYMBOL_VOLUME_STEP, SYMBOL_BID, SYMBOL_ASK, SYMBOL_CURRENCY_BASE, SYMBOL_CURRENCY_PROFIT };
enum { SYMBOL_FILLING_FOK = 1, SYMBOL_FILLING_IOC = 2 };
enum ENUM_ORDER_TYPE_FILLING { ORDER_FILLING_FOK = 0, ORDER_FILLING_IOC = 1, ORDER_FILLING_RETURN = 2 };
enum ENUM_ORDER_TYPE_TIME { ORDER_TIME_GTC = 0, ORDER_TIME_DAY = 1, ORDER_TIME_SPECIFIED = 2 };
enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY = 0, ORDER_TYPE_SELL = 1, ORDER_TYPE_BUY_LIMIT = 2, ORDER_TYPE_SELL_LIMIT = 3,
                       ORDER_TYPE_BUY_STOP = 4, ORDER_TYPE_SELL_STOP = 5 };
enum ENUM_TRADE_REQUEST_ACTIONS { TRADE_ACTION_DEAL = 1, TRADE_ACTION_PENDING = 5, TRADE_ACTION_SLTP = 6,
                                  TRADE_ACTION_MODIFY = 7, TRADE_ACTION_REMOVE = 8 };
const unsigned int TRADE_RETCODE_PLACED = 10008;
const unsigned int TRADE_RETCODE_DONE = 10009;
const unsigned int TRADE_RETCODE_INVALID_VOLUME = 10014;
const unsigned int TRADE_RETCODE_INVALID_PRICE = 10015;
const unsigned int TRADE_RETCODE_INVALID_STOPS = 10016;
const unsigned int TRADE_RETCODE_TRADE_DISABLED = 10017;
const unsigned int TRADE_RETCODE_NO_MONEY = 10019;
const unsigned int TRADE_RETCODE_INVALID = 10013;
enum { ACCOUNT_CURRENCY = 1 };
enum { ACCOUNT_TRADE_MODE = 1, ACCOUNT_TRADE_ALLOWED, ACCOUNT_TRADE_EXPERT, ACCOUNT_LOGIN };
enum { ACCOUNT_TRADE_MODE_DEMO = 0, ACCOUNT_TRADE_MODE_CONTEST = 1, ACCOUNT_TRADE_MODE_REAL = 2 };
enum { ACCOUNT_BALANCE = 1, ACCOUNT_EQUITY, ACCOUNT_MARGIN_FREE };
enum { TERMINAL_TRADE_ALLOWED = 1 };
enum { MQL_TRADE_ALLOWED = 1 };
enum { POSITION_MAGIC = 1, POSITION_TYPE, POSITION_TIME, POSITION_TICKET, POSITION_IDENTIFIER };
enum { POSITION_SYMBOL = 1, POSITION_COMMENT };
enum { POSITION_VOLUME = 1, POSITION_PRICE_OPEN, POSITION_SL, POSITION_TP, POSITION_PROFIT, POSITION_SWAP };
enum ENUM_POSITION_TYPE { POSITION_TYPE_BUY = 0, POSITION_TYPE_SELL = 1 };
enum { ORDER_MAGIC = 1, ORDER_TYPE, ORDER_TIME_SETUP, ORDER_TICKET };
enum { ORDER_SYMBOL = 1, ORDER_COMMENT };
enum { ORDER_PRICE_OPEN = 1, ORDER_SL, ORDER_TP, ORDER_VOLUME_CURRENT };
enum { DEAL_MAGIC = 1, DEAL_ENTRY, DEAL_TYPE, DEAL_TIME, DEAL_ORDER, DEAL_POSITION_ID };
enum { DEAL_SYMBOL = 1, DEAL_COMMENT };
enum { DEAL_PROFIT = 1, DEAL_COMMISSION, DEAL_SWAP, DEAL_VOLUME, DEAL_PRICE };
enum { DEAL_ENTRY_IN = 0, DEAL_ENTRY_OUT = 1, DEAL_ENTRY_INOUT = 2, DEAL_ENTRY_OUT_BY = 3 };
enum { DEAL_TYPE_BUY = 0, DEAL_TYPE_SELL = 1 };
enum { OBJ_LABEL = 1, OBJ_RECTANGLE_LABEL, OBJ_TEXT, OBJ_TREND, OBJ_ARROW };
enum { OBJPROP_CORNER = 1, OBJPROP_XDISTANCE, OBJPROP_YDISTANCE, OBJPROP_XSIZE, OBJPROP_YSIZE, OBJPROP_BGCOLOR,
       OBJPROP_BORDER_TYPE, OBJPROP_COLOR, OBJPROP_WIDTH, OBJPROP_BACK, OBJPROP_SELECTABLE, OBJPROP_HIDDEN,
       OBJPROP_ZORDER, OBJPROP_ANCHOR, OBJPROP_TEXT, OBJPROP_FONT, OBJPROP_FONTSIZE, OBJPROP_TIME, OBJPROP_PRICE,
       OBJPROP_TOOLTIP, OBJPROP_STYLE, OBJPROP_RAY_RIGHT, OBJPROP_ARROWCODE };
enum { CORNER_LEFT_UPPER = 0 };
enum { ANCHOR_LEFT_UPPER = 0, ANCHOR_LEFT_LOWER, ANCHOR_CENTER, ANCHOR_UPPER, ANCHOR_LOWER, ANCHOR_TOP, ANCHOR_BOTTOM };
enum { BORDER_FLAT = 0 };
enum { STYLE_SOLID = 0, STYLE_DASH, STYLE_DOT };
enum { TIME_DATE = 1, TIME_MINUTES = 2 };
enum { CHARTEVENT_CHART_CHANGE = 9 };
enum { CHART_WIDTH_IN_PIXELS = 1, CHART_HEIGHT_IN_PIXELS };
const color clrWhite = 0xFFFFFF;

struct MqlTradeRequest
{
   ENUM_TRADE_REQUEST_ACTIONS action = TRADE_ACTION_DEAL;
   ulong magic = 0;
   ulong order = 0;
   string symbol;
   double volume = 0;
   double price = 0;
   double stoplimit = 0;
   double sl = 0;
   double tp = 0;
   ulong deviation = 0;
   ENUM_ORDER_TYPE type = ORDER_TYPE_BUY;
   ENUM_ORDER_TYPE_FILLING type_filling = ORDER_FILLING_FOK;
   ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC;
   datetime expiration = 0;
   string comment;
   ulong position = 0;
   ulong position_by = 0;
};
struct MqlTradeResult
{
   unsigned int retcode = 0;
   ulong deal = 0;
   ulong order = 0;
   double volume = 0;
   double price = 0;
   double bid = 0;
   double ask = 0;
   string comment;
   unsigned int request_id = 0;
   int retcode_external = 0;
};
template <class T> void ZeroMemory(T &x) { x = T(); }

struct SimObj
{
   int type;
   std::map<int, long long> i;
   std::map<int, std::string> s;
   std::map<int, double> d;
};
struct SimPos
{
   ulong ticket;
   std::string sym;
   int type;   // POSITION_TYPE_*
   double vol, open, sl, tp;
   datetime time;
   long long magic;
   std::string comment;
};
struct SimOrder
{
   ulong ticket;
   std::string sym;
   int type;   // ORDER_TYPE_*
   double vol, price, sl, tp;
   datetime time;
   long long magic;
   std::string comment;
};
struct SimDeal
{
   ulong ticket;
   std::string sym;
   int entry;   // DEAL_ENTRY_*
   int type;    // 0 buy 1 sell
   double vol, price, profit;
   datetime time;
   long long magic;
   std::string comment;
   std::string reason;   // "market", "limit", "sl", "tp", "close"
};
struct SimState
{
   std::string sym = "XAUUSD", base = "XAU", profit = "USD";
   int digits = 2;
   double tick = 0.01, point = 0.01, tickValue = 1.0, volMin = 0.01, volMax = 100.0, volStep = 0.01;
   int stopsLevel = 0, spreadPts = 20, fillingMode = SYMBOL_FILLING_FOK | SYMBOL_FILLING_IOC;
   double contract = 100.0, leverage = 100.0;
   double bid = 0.0;
   std::vector<MqlRates> m1, m5, m15;   // full history, may extend past `now`
   datetime now = 0;
   bool copyFail = false;
   int accountMode = ACCOUNT_TRADE_MODE_DEMO;
   bool terminalTrade = true, mqlTrade = true, accountTrade = true, expertTrade = true;
   double balance = 10000.0;
   std::vector<SimPos> pos;
   std::vector<SimOrder> ord;
   std::vector<SimDeal> deals;
   ulong nextTicket = 1000;
   int selPos = -1, selOrd = -1;
   datetime histFrom = 0, histTo = 0;
   std::map<std::string, SimObj> objs;
   std::vector<std::string> log;
   std::vector<MqlTradeRequest> sent;   // every request OrderSend received
   bool rejectAll = false;
};
static SimState SIM;
static std::string _Symbol = "XAUUSD";
static ENUM_TIMEFRAMES _Period = PERIOD_M1;

inline double simAsk() { return SIM.bid + SIM.spreadPts * SIM.point; }

inline const std::vector<MqlRates> &simSeries(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_M1) return SIM.m1;
   return tf == PERIOD_M5 ? SIM.m5 : SIM.m15;
}
// bars that exist at SIM.now: the last one is the forming bar (series index 0)
inline int simVisible(ENUM_TIMEFRAMES tf)
{
   const auto &v = simSeries(tf);
   int k = 0;
   while(k < (int)v.size() && v[(size_t)k].time <= SIM.now) k++;
   return k;
}
inline int Bars(const string &, ENUM_TIMEFRAMES tf) { return simVisible(tf); }
inline int iBarShift(const string &, ENUM_TIMEFRAMES tf, datetime t, bool exact = false)
{
   (void)exact;
   int v = simVisible(tf);
   const auto &s = simSeries(tf);
   if(v == 0 || t < s[0].time) return -1;
   int k = v - 1;
   while(k > 0 && s[(size_t)k].time > t) k--;
   return v - 1 - k;
}
inline datetime iTime(const string &, ENUM_TIMEFRAMES tf, int shift)
{
   int v = simVisible(tf);
   if(shift < 0 || shift >= v) return 0;
   return simSeries(tf)[(size_t)(v - 1 - shift)].time;
}
inline int CopyRates(const string &, ENUM_TIMEFRAMES tf, int start, int count, std::vector<MqlRates> &out)
{
   if(SIM.copyFail) return -1;
   int v = simVisible(tf);
   if(start >= v || count <= 0) return -1;
   int last = v - 1 - start;
   int first = std::max(0, last - count + 1);
   const auto &s = simSeries(tf);
   out.assign(s.begin() + first, s.begin() + last + 1);
   return (int)out.size();
}

inline long long SymbolInfoInteger(const string &, int prop)
{
   switch(prop)
   {
      case SYMBOL_DIGITS: return SIM.digits;
      case SYMBOL_TRADE_STOPS_LEVEL: return SIM.stopsLevel;
      case SYMBOL_TRADE_FREEZE_LEVEL: return 0;
      case SYMBOL_FILLING_MODE: return SIM.fillingMode;
      case SYMBOL_SPREAD: return SIM.spreadPts;
   }
   return 0;
}
inline double SymbolInfoDouble(const string &, int prop)
{
   switch(prop)
   {
      case SYMBOL_TRADE_TICK_SIZE: return SIM.tick;
      case SYMBOL_POINT: return SIM.point;
      case SYMBOL_TRADE_TICK_VALUE: return SIM.tickValue;
      case SYMBOL_VOLUME_MIN: return SIM.volMin;
      case SYMBOL_VOLUME_MAX: return SIM.volMax;
      case SYMBOL_VOLUME_STEP: return SIM.volStep;
      case SYMBOL_BID: return SIM.bid;
      case SYMBOL_ASK: return simAsk();
   }
   return 0.0;
}
inline string SymbolInfoString(const string &, int prop)
{
   if(prop == SYMBOL_CURRENCY_BASE) return SIM.base;
   if(prop == SYMBOL_CURRENCY_PROFIT) return SIM.profit;
   return "";
}
inline double simPosProfit(const SimPos &p)
{
   double diff = (p.type == POSITION_TYPE_BUY) ? (SIM.bid - p.open) : (p.open - simAsk());
   return diff / SIM.tick * SIM.tickValue * p.vol;
}
inline double simFloating()
{
   double f = 0.0;
   for(const SimPos &p : SIM.pos) f += simPosProfit(p);
   return f;
}
inline double simMarginUsed()
{
   double m = 0.0;
   for(const SimPos &p : SIM.pos) m += p.vol * SIM.contract * p.open / SIM.leverage;
   return m;
}
inline string AccountInfoString(int) { return "USD"; }
inline long long AccountInfoInteger(int prop)
{
   switch(prop)
   {
      case ACCOUNT_TRADE_MODE: return SIM.accountMode;
      case ACCOUNT_TRADE_ALLOWED: return SIM.accountTrade ? 1 : 0;
      case ACCOUNT_TRADE_EXPERT: return SIM.expertTrade ? 1 : 0;
      case ACCOUNT_LOGIN: return 52901228;
   }
   return 0;
}
inline double AccountInfoDouble(int prop)
{
   switch(prop)
   {
      case ACCOUNT_BALANCE: return SIM.balance;
      case ACCOUNT_EQUITY: return SIM.balance + simFloating();
      case ACCOUNT_MARGIN_FREE: return SIM.balance + simFloating() - simMarginUsed();
   }
   return 0.0;
}
inline long long TerminalInfoInteger(int) { return SIM.terminalTrade ? 1 : 0; }
inline long long MQLInfoInteger(int) { return SIM.mqlTrade ? 1 : 0; }
inline datetime TimeTradeServer() { return SIM.now; }
inline datetime TimeCurrent() { return SIM.now; }
inline string TimeToString(datetime t, int flags)
{
   time_t tt = (time_t)t;
   struct tm g;
   gmtime_r(&tt, &g);
   char b[64];
   std::string out;
   if(flags & TIME_DATE) { std::strftime(b, sizeof b, "%Y.%m.%d", &g); out += b; }
   if(flags & TIME_MINUTES) { if(!out.empty()) out += " "; std::strftime(b, sizeof b, "%H:%M", &g); out += b; }
   return out;
}

// ---- positions ----
inline int PositionsTotal() { return (int)SIM.pos.size(); }
inline ulong PositionGetTicket(int i)
{
   if(i < 0 || i >= (int)SIM.pos.size()) { SIM.selPos = -1; return 0; }
   SIM.selPos = i;
   return SIM.pos[(size_t)i].ticket;
}
inline bool PositionSelectByTicket(ulong tk)
{
   for(size_t i = 0; i < SIM.pos.size(); i++)
      if(SIM.pos[i].ticket == tk) { SIM.selPos = (int)i; return true; }
   SIM.selPos = -1;
   return false;
}
inline string PositionGetString(int prop)
{
   if(SIM.selPos < 0) return "";
   const SimPos &p = SIM.pos[(size_t)SIM.selPos];
   return prop == POSITION_SYMBOL ? p.sym : (prop == POSITION_COMMENT ? p.comment : "");
}
inline long long PositionGetInteger(int prop)
{
   if(SIM.selPos < 0) return 0;
   const SimPos &p = SIM.pos[(size_t)SIM.selPos];
   switch(prop)
   {
      case POSITION_MAGIC: return p.magic;
      case POSITION_TYPE: return p.type;
      case POSITION_TIME: return p.time;
      case POSITION_TICKET: return (long long)p.ticket;
      case POSITION_IDENTIFIER: return (long long)p.ticket;
   }
   return 0;
}
inline double PositionGetDouble(int prop)
{
   if(SIM.selPos < 0) return 0.0;
   const SimPos &p = SIM.pos[(size_t)SIM.selPos];
   switch(prop)
   {
      case POSITION_VOLUME: return p.vol;
      case POSITION_PRICE_OPEN: return p.open;
      case POSITION_SL: return p.sl;
      case POSITION_TP: return p.tp;
      case POSITION_PROFIT: return simPosProfit(p);
      case POSITION_SWAP: return 0.0;
   }
   return 0.0;
}
// ---- pending orders ----
inline int OrdersTotal() { return (int)SIM.ord.size(); }
inline ulong OrderGetTicket(int i)
{
   if(i < 0 || i >= (int)SIM.ord.size()) { SIM.selOrd = -1; return 0; }
   SIM.selOrd = i;
   return SIM.ord[(size_t)i].ticket;
}
inline string OrderGetString(int prop)
{
   if(SIM.selOrd < 0) return "";
   const SimOrder &o = SIM.ord[(size_t)SIM.selOrd];
   return prop == ORDER_SYMBOL ? o.sym : (prop == ORDER_COMMENT ? o.comment : "");
}
inline long long OrderGetInteger(int prop)
{
   if(SIM.selOrd < 0) return 0;
   const SimOrder &o = SIM.ord[(size_t)SIM.selOrd];
   switch(prop)
   {
      case ORDER_MAGIC: return o.magic;
      case ORDER_TYPE: return o.type;
      case ORDER_TIME_SETUP: return o.time;
      case ORDER_TICKET: return (long long)o.ticket;
   }
   return 0;
}
inline double OrderGetDouble(int prop)
{
   if(SIM.selOrd < 0) return 0.0;
   const SimOrder &o = SIM.ord[(size_t)SIM.selOrd];
   switch(prop)
   {
      case ORDER_PRICE_OPEN: return o.price;
      case ORDER_SL: return o.sl;
      case ORDER_TP: return o.tp;
      case ORDER_VOLUME_CURRENT: return o.vol;
   }
   return 0.0;
}
// ---- deal history ----
inline bool HistorySelect(datetime from, datetime to) { SIM.histFrom = from; SIM.histTo = to; return true; }
inline std::vector<size_t> simHistIdx()
{
   std::vector<size_t> v;
   for(size_t i = 0; i < SIM.deals.size(); i++)
      if(SIM.deals[i].time >= SIM.histFrom && SIM.deals[i].time <= SIM.histTo) v.push_back(i);
   return v;
}
inline int HistoryDealsTotal() { return (int)simHistIdx().size(); }
inline ulong HistoryDealGetTicket(int i)
{
   auto v = simHistIdx();
   if(i < 0 || i >= (int)v.size()) return 0;
   return SIM.deals[v[(size_t)i]].ticket;
}
inline const SimDeal *simDeal(ulong tk)
{
   for(const SimDeal &d : SIM.deals) if(d.ticket == tk) return &d;
   return nullptr;
}
inline long long HistoryDealGetInteger(ulong tk, int prop)
{
   const SimDeal *d = simDeal(tk);
   if(!d) return 0;
   switch(prop)
   {
      case DEAL_MAGIC: return d->magic;
      case DEAL_ENTRY: return d->entry;
      case DEAL_TYPE: return d->type;
      case DEAL_TIME: return d->time;
   }
   return 0;
}
inline string HistoryDealGetString(ulong tk, int prop)
{
   const SimDeal *d = simDeal(tk);
   if(!d) return "";
   return prop == DEAL_SYMBOL ? d->sym : d->comment;
}
inline double HistoryDealGetDouble(ulong tk, int prop)
{
   const SimDeal *d = simDeal(tk);
   if(!d) return 0.0;
   switch(prop)
   {
      case DEAL_PROFIT: return d->profit;
      case DEAL_VOLUME: return d->vol;
      case DEAL_PRICE: return d->price;
   }
   return 0.0;   // commission / swap: none in the simulator
}

// ---- matching engine ----
inline void simDeal(const SimPos &p, int entry, double price, double profit, const char *reason)
{
   SimDeal d;
   d.ticket = SIM.nextTicket++;
   d.sym = p.sym;
   d.entry = entry;
   d.type = (entry == DEAL_ENTRY_IN) ? p.type : (p.type == POSITION_TYPE_BUY ? 1 : 0);
   d.vol = p.vol;
   d.price = price;
   d.profit = profit;
   d.time = SIM.now;
   d.magic = p.magic;
   d.comment = p.comment;
   d.reason = reason;
   SIM.deals.push_back(d);
}
inline void simClosePos(size_t i, double price, const char *reason)
{
   SimPos p = SIM.pos[i];
   double diff = (p.type == POSITION_TYPE_BUY) ? (price - p.open) : (p.open - price);
   double profit = diff / SIM.tick * SIM.tickValue * p.vol;
   SIM.balance += profit;
   simDeal(p, DEAL_ENTRY_OUT, price, profit, reason);
   SIM.pos.erase(SIM.pos.begin() + (long)i);
}
inline ulong simOpenPos(const std::string &sym, int type, double vol, double price, double sl, double tp,
                        long long magic, const std::string &comment, const char *reason)
{
   SimPos p;
   p.ticket = SIM.nextTicket++;
   p.sym = sym;
   p.type = type;
   p.vol = vol;
   p.open = price;
   p.sl = sl;
   p.tp = tp;
   p.time = SIM.now;
   p.magic = magic;
   p.comment = comment;
   SIM.pos.push_back(p);
   simDeal(p, DEAL_ENTRY_IN, price, 0.0, reason);
   return p.ticket;
}
inline bool simVolumeOk(double v)
{
   if(v < SIM.volMin - 1e-9 || v > SIM.volMax + 1e-9) return false;
   double q = v / SIM.volStep;
   return std::fabs(q - std::round(q)) < 1e-6;
}
inline bool OrderCalcMargin(ENUM_ORDER_TYPE, const string &, double vol, double price, double &margin)
{
   margin = vol * SIM.contract * price / SIM.leverage;
   return true;
}
inline bool OrderSend(const MqlTradeRequest &req, MqlTradeResult &res)
{
   SIM.sent.push_back(req);
   res = MqlTradeResult();
   if(SIM.rejectAll) { res.retcode = TRADE_RETCODE_INVALID; return false; }
   if(!SIM.terminalTrade || !SIM.mqlTrade || !SIM.accountTrade || !SIM.expertTrade)
   {
      res.retcode = TRADE_RETCODE_TRADE_DISABLED;
      return false;
   }
   double minDist = SIM.stopsLevel * SIM.point;
   if(req.action == TRADE_ACTION_DEAL)
   {
      if(req.position != 0)
      {
         for(size_t i = 0; i < SIM.pos.size(); i++)
            if(SIM.pos[i].ticket == req.position)
            {
               double px = (SIM.pos[i].type == POSITION_TYPE_BUY) ? SIM.bid : simAsk();
               simClosePos(i, px, "close");
               res.retcode = TRADE_RETCODE_DONE;
               res.deal = SIM.nextTicket - 1;
               return true;
            }
         res.retcode = TRADE_RETCODE_INVALID;
         return false;
      }
      if(!simVolumeOk(req.volume)) { res.retcode = TRADE_RETCODE_INVALID_VOLUME; return false; }
      bool buy = (req.type == ORDER_TYPE_BUY);
      double px = buy ? simAsk() : SIM.bid;
      if(buy && ((req.sl > 0 && req.sl > px - minDist) || (req.tp > 0 && req.tp < px + minDist)))
      { res.retcode = TRADE_RETCODE_INVALID_STOPS; return false; }
      if(!buy && ((req.sl > 0 && req.sl < px + minDist) || (req.tp > 0 && req.tp > px - minDist)))
      { res.retcode = TRADE_RETCODE_INVALID_STOPS; return false; }
      double margin = req.volume * SIM.contract * px / SIM.leverage;
      if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE)) { res.retcode = TRADE_RETCODE_NO_MONEY; return false; }
      ulong tk = simOpenPos(req.symbol, buy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, req.volume, px, req.sl, req.tp,
                            (long long)req.magic, req.comment, "market");
      res.retcode = TRADE_RETCODE_DONE;
      res.order = tk;
      res.deal = SIM.nextTicket - 1;
      res.price = px;
      return true;
   }
   if(req.action == TRADE_ACTION_PENDING)
   {
      if(!simVolumeOk(req.volume)) { res.retcode = TRADE_RETCODE_INVALID_VOLUME; return false; }
      if(req.type == ORDER_TYPE_BUY_LIMIT)
      {
         if(req.price > simAsk() - minDist) { res.retcode = TRADE_RETCODE_INVALID_PRICE; return false; }
         if((req.sl > 0 && req.sl > req.price - minDist) || (req.tp > 0 && req.tp < req.price + minDist))
         { res.retcode = TRADE_RETCODE_INVALID_STOPS; return false; }
      }
      else if(req.type == ORDER_TYPE_SELL_LIMIT)
      {
         if(req.price < SIM.bid + minDist) { res.retcode = TRADE_RETCODE_INVALID_PRICE; return false; }
         if((req.sl > 0 && req.sl < req.price + minDist) || (req.tp > 0 && req.tp > req.price - minDist))
         { res.retcode = TRADE_RETCODE_INVALID_STOPS; return false; }
      }
      else { res.retcode = TRADE_RETCODE_INVALID; return false; }
      SimOrder o;
      o.ticket = SIM.nextTicket++;
      o.sym = req.symbol;
      o.type = req.type;
      o.vol = req.volume;
      o.price = req.price;
      o.sl = req.sl;
      o.tp = req.tp;
      o.time = SIM.now;
      o.magic = (long long)req.magic;
      o.comment = req.comment;
      SIM.ord.push_back(o);
      res.retcode = TRADE_RETCODE_PLACED;
      res.order = o.ticket;
      return true;
   }
   if(req.action == TRADE_ACTION_REMOVE)
   {
      for(size_t i = 0; i < SIM.ord.size(); i++)
         if(SIM.ord[i].ticket == req.order)
         {
            SIM.ord.erase(SIM.ord.begin() + (long)i);
            res.retcode = TRADE_RETCODE_DONE;
            res.order = req.order;
            return true;
         }
      res.retcode = TRADE_RETCODE_INVALID;
      return false;
   }
   res.retcode = TRADE_RETCODE_INVALID;
   return false;
}

// price path of one bar: fills, then stops. Pessimistic: SL before TP,
// and a fill that also touches its SL in the same bar is stopped out.
inline void simBarPath(const MqlRates &b)
{
   for(size_t i = 0; i < SIM.ord.size();)
   {
      SimOrder o = SIM.ord[i];
      bool fill = (o.type == ORDER_TYPE_BUY_LIMIT) ? (b.low <= o.price) : (b.high >= o.price);
      if(!fill) { i++; continue; }
      SIM.ord.erase(SIM.ord.begin() + (long)i);
      simOpenPos(o.sym, o.type == ORDER_TYPE_BUY_LIMIT ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, o.vol, o.price, o.sl,
                 o.tp, o.magic, o.comment, "limit");
   }
   for(size_t i = 0; i < SIM.pos.size();)
   {
      const SimPos &p = SIM.pos[i];
      if(p.type == POSITION_TYPE_BUY)
      {
         if(p.sl > 0 && b.low <= p.sl) { simClosePos(i, p.sl, "sl"); continue; }
         if(p.tp > 0 && b.high >= p.tp) { simClosePos(i, p.tp, "tp"); continue; }
      }
      else
      {
         if(p.sl > 0 && b.high + SIM.spreadPts * SIM.point >= p.sl) { simClosePos(i, p.sl, "sl"); continue; }
         if(p.tp > 0 && b.low + SIM.spreadPts * SIM.point <= p.tp) { simClosePos(i, p.tp, "tp"); continue; }
      }
      i++;
   }
}

// ---- chart objects ----
inline int ObjectFind(long, const string &name) { return SIM.objs.count(name) ? 0 : -1; }
inline bool ObjectCreate(long, const string &name, int type, int, datetime t1, double p1, datetime t2 = 0, double p2 = 0)
{
   (void)t2; (void)p2;
   SimObj o;
   o.type = type;
   o.i[OBJPROP_TIME] = t1;
   o.d[OBJPROP_PRICE] = p1;
   SIM.objs[name] = o;
   return true;
}
inline bool ObjectSetInteger(long, const string &name, int prop, long long v) { SIM.objs[name].i[prop] = v; return true; }
inline bool ObjectSetInteger(long, const string &name, int prop, int modifier, long long v)
{
   SIM.objs[name].i[prop + 100 * modifier] = v;
   return true;
}
inline bool ObjectSetDouble(long, const string &name, int prop, double v) { SIM.objs[name].d[prop] = v; return true; }
inline bool ObjectSetDouble(long, const string &name, int prop, int modifier, double v)
{
   SIM.objs[name].d[prop + 100 * modifier] = v;
   return true;
}
inline bool ObjectSetString(long, const string &name, int prop, const string &v) { SIM.objs[name].s[prop] = v; return true; }
inline int ObjectsDeleteAll(long, const string &prefix, int = -1, int = -1)
{
   int n = 0;
   for(auto it = SIM.objs.begin(); it != SIM.objs.end();)
      if(it->first.compare(0, prefix.size(), prefix) == 0) { it = SIM.objs.erase(it); n++; }
      else ++it;
   return n;
}
inline void ChartRedraw(long = 0) {}
inline long long ChartGetInteger(long, int prop, int = 0) { return prop == CHART_WIDTH_IN_PIXELS ? 1400 : 900; }
inline bool EventSetTimer(int) { return true; }
inline void EventKillTimer() {}
inline void Print(const string &s) { SIM.log.push_back(s); }
