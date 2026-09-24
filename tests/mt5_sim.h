// Simulated MT5 terminal for running the whole indicator under g++.
//
// DELIBERATELY ABSENT: OrderSend, OrderSendAsync, PositionClose/Modify,
// CTrade, MqlTradeRequest, WebRequest, Socket*, SendNotification ...
// If the indicator referenced any of them, the full-file build would fail
// to compile - that is part of safety test #13.
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
enum { INDICATOR_DATA = 0, INDICATOR_COLOR_INDEX = 1, INDICATOR_CALCULATIONS = 2 };
enum { PLOT_EMPTY_VALUE = 1, PLOT_DRAW_TYPE = 2, PLOT_ARROW = 3, PLOT_ARROW_SHIFT = 4 };
enum { DRAW_NONE = 0, DRAW_LINE = 1, DRAW_COLOR_LINE = 2, DRAW_ARROW = 3, DRAW_COLOR_ARROW = 4 };
enum { INDICATOR_SHORTNAME = 1, INDICATOR_DIGITS = 2 };
enum { SYMBOL_DIGITS = 1, SYMBOL_TRADE_TICK_SIZE, SYMBOL_POINT, SYMBOL_TRADE_TICK_VALUE, SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_STEP, SYMBOL_VOLUME_MAX,
       SYMBOL_BID, SYMBOL_CURRENCY_BASE, SYMBOL_CURRENCY_PROFIT };
enum { ACCOUNT_CURRENCY = 1 };
enum { ACCOUNT_BALANCE = 1, ACCOUNT_EQUITY = 2 };
enum { POSITION_SYMBOL = 1, POSITION_TYPE, POSITION_VOLUME, POSITION_TIME };
enum { POSITION_TYPE_BUY = 0, POSITION_TYPE_SELL = 1 };
enum { OBJ_LABEL = 1, OBJ_RECTANGLE_LABEL, OBJ_TEXT, OBJ_TREND };
enum { OBJPROP_CORNER = 1, OBJPROP_XDISTANCE, OBJPROP_YDISTANCE, OBJPROP_XSIZE, OBJPROP_YSIZE, OBJPROP_BGCOLOR,
       OBJPROP_BORDER_TYPE, OBJPROP_COLOR, OBJPROP_WIDTH, OBJPROP_BACK, OBJPROP_SELECTABLE, OBJPROP_HIDDEN,
       OBJPROP_ZORDER, OBJPROP_ANCHOR, OBJPROP_TEXT, OBJPROP_FONT, OBJPROP_FONTSIZE, OBJPROP_TIME, OBJPROP_PRICE,
       OBJPROP_TOOLTIP, OBJPROP_STYLE, OBJPROP_RAY_RIGHT };
enum { CORNER_LEFT_UPPER = 0 };
enum { ANCHOR_LEFT_UPPER = 0, ANCHOR_LEFT_LOWER, ANCHOR_CENTER, ANCHOR_UPPER, ANCHOR_LOWER };
enum { BORDER_FLAT = 0 };
enum { STYLE_SOLID = 0, STYLE_DASH, STYLE_DOT, STYLE_DASHDOT };
enum { TIME_DATE = 1, TIME_MINUTES = 2 };
enum { CHARTEVENT_CHART_CHANGE = 9 };
enum { CHART_WIDTH_IN_PIXELS = 1, CHART_HEIGHT_IN_PIXELS };
const color clrWhite = 0xFFFFFF;

struct SimObj
{
   int type;
   std::map<int, long long> i;
   std::map<int, std::string> s;
   std::map<int, double> d;
};
struct SimPos
{
   std::string sym;
   int type;
   double vol;
   datetime time;
};
struct SimState
{
   std::string sym = "XAUUSD", base = "XAU", profit = "USD";
   int digits = 2;
   double tick = 0.01, tickValue = 1.0, volMin = 0.01, volStep = 0.01, volMax = 100.0, bid = 0.0;
   double balance = 10000.0, equity = 10000.0;
   std::vector<MqlRates> m1, m5, m15;   // full history, may extend past `now`
   datetime now = 0;
   bool copyFail = false;
   std::vector<SimPos> pos;
   int selected = -1;
   std::map<std::string, SimObj> objs;
   std::map<int, std::vector<double> *> bufs;
   std::vector<std::string> log;
   std::vector<std::string> alerts;
   std::vector<std::string> sounds;
};
static SimState SIM;
static std::string _Symbol = "XAUUSD";
static ENUM_TIMEFRAMES _Period = PERIOD_M15;

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

inline long long SymbolInfoInteger(const string &, int prop) { return prop == SYMBOL_DIGITS ? SIM.digits : 0; }
inline double SymbolInfoDouble(const string &, int prop)
{
   switch(prop)
   {
      case SYMBOL_TRADE_TICK_SIZE: return SIM.tick;
      case SYMBOL_POINT: return SIM.tick;
      case SYMBOL_TRADE_TICK_VALUE: return SIM.tickValue;
      case SYMBOL_VOLUME_MIN: return SIM.volMin;
      case SYMBOL_VOLUME_STEP: return SIM.volStep;
      case SYMBOL_VOLUME_MAX: return SIM.volMax;
      case SYMBOL_BID: return SIM.bid;
   }
   return 0.0;
}
inline string SymbolInfoString(const string &, int prop)
{
   if(prop == SYMBOL_CURRENCY_BASE) return SIM.base;
   if(prop == SYMBOL_CURRENCY_PROFIT) return SIM.profit;
   return "";
}
inline string AccountInfoString(int) { return "USD"; }
inline double AccountInfoDouble(int prop) { return prop == ACCOUNT_BALANCE ? SIM.balance : SIM.equity; }
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

// READ-ONLY position access (the real MQL5 API has the same shape)
inline int PositionsTotal() { return (int)SIM.pos.size(); }
inline ulong PositionGetTicket(int i)
{
   if(i < 0 || i >= (int)SIM.pos.size()) { SIM.selected = -1; return 0; }
   SIM.selected = i;
   return (ulong)(1000 + i);
}
inline string PositionGetString(int prop) { return (SIM.selected >= 0 && prop == POSITION_SYMBOL) ? SIM.pos[(size_t)SIM.selected].sym : ""; }
inline long long PositionGetInteger(int prop)
{
   if(SIM.selected < 0) return 0;
   const SimPos &p = SIM.pos[(size_t)SIM.selected];
   if(prop == POSITION_TYPE) return p.type;
   if(prop == POSITION_TIME) return p.time;
   return 0;
}
inline double PositionGetDouble(int prop) { return (SIM.selected >= 0 && prop == POSITION_VOLUME) ? SIM.pos[(size_t)SIM.selected].vol : 0.0; }

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
inline bool ObjectSetDouble(long, const string &name, int prop, double v) { SIM.objs[name].d[prop] = v; return true; }
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
inline bool SetIndexBuffer(int idx, std::vector<double> &b, int) { SIM.bufs[idx] = &b; return true; }
inline bool PlotIndexSetDouble(int, int, double) { return true; }
inline bool PlotIndexSetInteger(int, int, int) { return true; }
inline bool IndicatorSetString(int, const string &) { return true; }
inline bool IndicatorSetInteger(int, int) { return true; }
inline bool EventSetTimer(int) { return true; }
inline void EventKillTimer() {}
inline void Print(const string &s) { SIM.log.push_back(s); }
inline void Alert(const string &s) { SIM.alerts.push_back(s); }
inline bool PlaySound(const string &s) { SIM.sounds.push_back(s); return true; }
