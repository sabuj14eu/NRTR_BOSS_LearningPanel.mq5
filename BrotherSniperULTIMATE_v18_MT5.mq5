//+------------------------------------------------------------------+
//|                                BrotherSniperULTIMATE_v18_MT5.mq5 |
//|   The MT5 TWIN of BrotherSniperULTIMATE_v18_FINAL_v6.pine        |
//|   (Pine v6, script version 18.12) - SENSOR + EXECUTION          |
//|                                                                  |
//|  WHAT THIS IS. The TradingView indicator ported LINE BY LINE to  |
//|  MQL5 so the same readings appear on the MT5 chart - the MAIN    |
//|  DASHBOARD (54 rows), the STRUCTURAL BRAIN (38 rows), the SMART  |
//|  SCALP panel, the MANUAL MONITOR, the PIVOT table, the chart     |
//|  structure (swings, S/R, BOS, CHoCH, FVG, order blocks, sweeps, |
//|  inducement, pivots, PDH/PDL, NWOG, ORG, midnight, sessions).   |
//|  Every rule, threshold and default is the Pine's; the section   |
//|  numbers in the comments are the Pine's section numbers, so the  |
//|  two files can be read side by side. Where MT5 cannot do what    |
//|  Pine does, the limitation is written at the place it applies.  |
//|                                                                  |
//|  EXECUTION (the Pine fired webhooks; this file places orders):   |
//|   * SMART SCALP bot fire (the Pine's strict chain: score ->      |
//|     grade -> R:R -> location gate -> cooldown -> squelch ->     |
//|     news policy -> entry distance) -> ONE market order at the   |
//|     bar close with the Pine's SL and TP1, lot from the account   |
//|     risk input, on the CONFIRMED bar only.                       |
//|   * PULLBACK arm (v18.7 B1, validated n=640) -> ONE limit order  |
//|     at the armed entry with the Pine's SL and TP1; pulled when   |
//|     the arm dies (TREND FLIP / EXPIRED / GAPPED THRU), while     |
//|     the DXY squelch is active, or in a news window when the news |
//|     policy blocks; re-placed when the arm is alive again.        |
//|   * No webhook, no file, no DLL. This EA posts NOTHING anywhere: |
//|     it is not a second signal source for the council or the     |
//|     bots. Its account is its own (magic 180918).                 |
//|   * The MT5 "Algo Trading" button is the on/off switch, on a     |
//|     demo or a real account alike (the operator's decision).     |
//|                                                                  |
//|  Only orders with this EA's magic are ever touched.              |
//+------------------------------------------------------------------+
#property copyright   "Personal use - the MT5 twin of the Pine sensor"
#property version     "18.12"
#property description "Brother Sniper ULTIMATE v18.12 on MT5: the same dashboards and chart structure as the Pine, plus execution."
#property description "SMART SCALP fires = market orders at bar close; PULLBACK arms = limit orders; the Algo Trading button is the switch."
#property strict

#define BS_VERSION "18.12-mt5.1"

//=== SECTION 1 - INPUTS (the Pine's inputs, same names, same defaults) ===
enum BS_MARKET { MK_AUTO = 0, MK_SILVER, MK_GOLD, MK_EURUSD, MK_USDJPY, MK_DXY, MK_OIL, MK_US30, MK_NAS100, MK_BTC, MK_ETH, MK_XRP };
enum BS_MODE { SM_AGGRESSIVE = 0, SM_BALANCED, SM_CONSERVATIVE };
enum BS_POS { P_TOP_LEFT = 0, P_TOP_CENTER, P_TOP_RIGHT, P_MID_LEFT, P_MID_CENTER, P_MID_RIGHT, P_BOT_LEFT, P_BOT_CENTER, P_BOT_RIGHT };
enum BS_SIZE { SZ_STANDARD = 0, SZ_MEDIUM, SZ_BIG };
enum BS_ENTRYMODE { EM_TOUCH = 0, EM_REJECT, EM_REJECT_CONFIRM };
enum BS_MKTMODE { MM_AUTO = 0, MM_RANGE, MM_TREND };
enum BS_PENDSRC { PS_GATE = 0, PS_SESSION, PS_GATE_SESSION };
enum BS_TIGHTACT { TA_DRAW = 0, TA_HIDE, TA_RED };

input group "-- Core Settings --"
input int            InpLength        = 5;      // Swing Length
input double         InpRR            = 2.0;    // Risk Reward
input BS_MARKET      InpMarketType    = MK_AUTO; // Market Type
input double         InpSwingTarget   = 2.50;   // Swing Target ($)
input double         InpSwingStop     = 1.00;   // Swing SL ($)

input group "-- SMART SCALP (v18 FINAL) --"
input bool           InpSsEnable      = true;   // Enable SMART SCALP (the bot fire = a market order here)
input BS_MODE        InpSsMode        = SM_BALANCED; // Scalp Mode (label only - threshold in FIRE CONTROL)
input double         InpSsAtrCap      = 2.5;    // Max SL x ATR (safety cap)
input bool           InpSsShowPanel   = true;   // Show Active Signal panel
input bool           InpSsShowLines   = true;   // Draw Entry/SL/TP lines on chart when fired
input BS_POS         InpSsPanelPos    = P_TOP_CENTER; // Active Signal panel position
input bool           InpSsWhitelistOnly = true; // Bot fire only on whitelisted symbols
input int            InpSaExpireBars  = 16;     // Active-Signal panel expiry (bars)

input group "-- FIRE CONTROL (v18.6) --"
input int            InpFcThreshold   = 6;      // Bot score threshold (4-9)
input double         InpFcMinRR       = 1.6;    // Bot min R:R (v4 veto)
input bool           InpFcRequireDom  = true;   // Require score > opposite side
input int            InpFcMacroCap    = 1;      // Max macro DEMOTION (points)
input bool           InpFcFireAllGrades = false; // Fire ALL grades (data-collection week)
input bool           InpFcAsiaScore   = true;   // Asia counts as active session (+1 score)

input group "-- FILL BUFFERS (v18.4g) --"
input bool           InpUseFillBuffer = true;   // Pull TP in / push SL out so orders fill
input double         InpTpBufAtr      = 0.10;   // TP pull-in buffer (x ATR)
input double         InpSlBufAtr      = 0.05;   // SL push-out buffer (x ATR)

input group "-- Webhook Symbol Whitelist (v18.3) --"
input bool           InpWlGold        = true;   // Allow XAUUSD / Gold
input bool           InpWlSilver      = true;   // Allow XAGUSD / Silver
input bool           InpWlBTC         = true;   // Allow BTC
input bool           InpWlETH         = true;   // Allow ETH
input bool           InpWlUSDJPY      = true;   // Allow USDJPY
input bool           InpWlEURUSD      = false;  // Allow EURUSD
input bool           InpWlUS30        = true;   // Allow US30 / Dow
input bool           InpWlUS100       = true;   // Allow US100 / NAS100
input bool           InpWlOil         = false;  // Allow Oil / WTI
input bool           InpWlXRP         = false;  // Allow XRP
input bool           InpWlDXY         = false;  // Allow DXY

input group "-- NY Trap Protocol (v18.3) --"
input bool           InpUseNYProtocol = true;   // Enable NY Trap Protocol
input bool           InpNyKzPreOpen   = true;   // Killzone: Pre-Open 08:30-09:00 NY
input bool           InpNyKzCashOpen  = true;   // Killzone: Cash Open 09:30-10:30 NY
input bool           InpNyKzAfternoon = false;  // Killzone: Afternoon 13:00-14:00 NY
input double         InpAtrPadMultNY  = 0.4;    // ATR pad multiplier during NY killzone
input double         InpAtrPadCapPips = 15.0;   // ATR pad cap (x pipZone price units)
input double         InpTrapVolMult   = 2.0;    // Trap detector: candle range >= X x 20-bar avg
input bool           InpUseDXYSquelch = true;   // DXY Volatility Squelch
input double         InpDxySquelchPct = 0.15;   // DXY squelch: 1m range > X%
input int            InpDxySquelchSecs = 180;   // DXY squelch duration (seconds)

input group "-- LOCATION GATE (v18.4) --"
input bool           InpUseLocationGate = true; // Require structure retest before firing
input double         InpLgZoneAtr     = 0.5;    // Zone proximity tolerance (x ATR)
input double         InpLgChaseAtr    = 0.8;    // Chase guard: min pullback off extreme (x ATR)
input int            InpLgPbLookback  = 20;     // Chase guard lookback (bars)
input BS_ENTRYMODE   InpLgEntryMode   = EM_REJECT_CONFIRM; // Entry trigger at zone
input BS_MKTMODE     InpLgMarketMode  = MM_AUTO; // Market mode (which zones can fire)
input int            InpLgFreshBars   = 8;      // Fire window after zone touch (bars)
input int            InpLgCooldownBars = 6;     // Cooldown between same-direction fires (bars)
input bool           InpLgApplyChart  = false;  // Apply gate to chart signals too
input double         InpLgWickPct     = 0.35;   // Rejection wick minimum (x bar range)
input double         InpLgMaxEntryDist = 0.0;   // Max entry distance from zone (x ATR, 0 = OFF)

input group "-- ADAPTIVE ENGINE (v18.5) --"
input bool           InpUseAdaptive   = true;   // Auto-scale gates & SL with volatility regime
input double         InpAeZoneHi      = 0.7;    // HIGH vol: zone tolerance x
input double         InpAeChaseHi     = 1.5;    // HIGH vol: chase guard x
input double         InpAeSLFloorHi   = 1.0;    // HIGH vol / news: min SL (x ATR)
input double         InpAeSLFloorLo   = 0.7;    // Normal: min SL (x ATR)

input group "-- NEWS AWARENESS (v18.5) --"
input bool           InpUseNewsAware  = true;   // Tag US news windows (no blocking)
input bool           InpNewsBlockNew  = false;  // Hard-block NEW entries in news windows

input group "-- Dashboard appearance + positions --"
input BS_SIZE        InpDashSizeMode  = SZ_STANDARD; // Dashboard text size
input BS_POS         InpDashPos       = P_TOP_RIGHT;  // Main Dashboard Position
input BS_POS         InpPendPos       = P_TOP_LEFT;   // Structural Brain Position
input BS_POS         InpPvtPos        = P_BOT_LEFT;   // Pivot Table Position
input BS_POS         InpManPos        = P_BOT_CENTER; // Manual Monitor position
input int            InpHistoryBars   = 1500;   // Bars re-read each tick (the Pine runs the whole history; 300-5000)
input int            InpDrawBars      = 300;    // Chart annotations kept for the last N bars

input group "-- Pending Source (v18.4g) / Yield Macro (v18.4) / Range Too-Tight (v18.1) --"
input BS_PENDSRC     InpPendSrcMode   = PS_GATE_SESSION; // Pending order levels from
input bool           InpUseYieldMacro = true;   // Use US 10Y yield in macro modifier
input string         InpYieldSymbol   = "";     // Yield symbol ("" = AUTO: US10Y, USTNOTE10 ...; "-" = off)
input string         InpDxySymbol     = "";     // Dollar index symbol ("" = AUTO: USDX, DXY ...; "-" = off)
input string         InpOilSymbol     = "";     // Oil symbol ("" = AUTO: USOIL, WTI, XTIUSD ...; "-" = off)
input bool           InpUseTightFilter = true;  // Block pending orders when session range is too tight
input bool           InpTightAutoPerSym = true; // Auto-pick threshold per instrument
input double         InpTightManualPts = 5.0;   // Manual minimum range (in price points)
input BS_TIGHTACT    InpTightAction   = TA_DRAW; // Action when too tight

input group "-- Account & Risk --"
input double         InpRiskPct       = 1.0;    // Risk Per Trade (%) of balance (lots from the real tick value)
input double         InpMaxSpread     = 3.0;    // Max Spread (pips) - the Pine's range proxy
input int            InpMaxTradesPerDay = 12;   // Max Trades Per Day (THIS EA enforces it: the Pine did not)
input double         InpMaxDailyLossPct = 2.0;  // Max Daily Loss (%) (THIS EA enforces it on its own closed P&L)
input int            InpMaxOpenPositions = 1;   // Max open positions of this EA on this chart
input bool           InpSplitTp2      = false;  // Scalp: two half orders (TP1 + TP2) instead of one order at TP1
input bool           InpCloseOnFlip   = false;  // Close a scalp position when the 15m trend flips against it (the panel's 'trend flip')
input bool           InpAllowRealAccount = true; // Trade on a REAL account too (the Algo Trading button is the switch)
input int            InpMagic         = 180918; // Magic number (this EA only ever touches its own orders)
input bool           InpShowSessionBG = true;   // Show Session Background Colors
input bool           InpShowPDHL      = true;   // Show Prev Day High/Low
input bool           InpShowWeeklyHL  = true;   // Show Weekly High/Low
input bool           InpUseDXYFilter  = false;  // DXY Correlation Filter (legacy chart signals)

input group "-- Indicator Settings --"
input int            InpRsiLength     = 14;     // RSI Length
input int            InpRsiOB         = 70;     // RSI Overbought
input int            InpRsiOS         = 30;     // RSI Oversold
input int            InpAtrLength     = 14;     // ATR Length
input double         InpAtrMult       = 1.5;    // ATR SL Multiplier
input int            InpAdxLength     = 14;     // ADX Length
input int            InpAdxStrong     = 25;     // ADX Strong Trend
input int            InpAdxWeak       = 15;     // ADX Weak Trend
input bool           InpUseVolume     = true;   // Volume Filter ON/OFF (chart signals only)
input double         InpVolMult       = 1.0;    // Min Volume x Avg

input group "-- Display Toggles / Chart Labels --"
input bool           InpShowFVG       = true;   // Show Fair Value Gaps
input bool           InpShowLiqZone   = true;   // Show Liquidity Zones
input bool           InpShowOB        = true;   // Show Order Blocks
input bool           InpShowBOS       = true;   // Show BOS Labels
input bool           InpShowScalp     = true;   // Show Scalp Signals
input bool           InpShowPivot     = true;   // Show Pivot Lines
input bool           InpShowInducement = true;  // Show Inducement Labels
input bool           InpShowAllLabels = true;   // MASTER: show chart annotation labels
input bool           InpShowTrendBox  = false;  // Show UPTREND / DOWNTREND box
input bool           InpShowRealMove  = false;  // Show 'RM Real Move' labels
input bool           InpShowStopHunt  = true;   // Show liquidity sweep (SH) labels
input bool           InpShowFakeBO    = false;  // Show fake-breakout (FB) trap labels
input bool           InpShowCHoCH     = true;   // Show CHoCH labels
input bool           InpShowCandlePat = false;  // Show candle pattern marks (E/P/D)
input double         InpLiqBuffer     = 0.5;    // Liq Zone Buffer (ATR x)
input bool           InpShowNWOG      = true;   // Show NWOG (New Week Opening Gap)
input bool           InpShowORG       = true;   // Show ORG (Opening Range Gap)
input bool           InpShowEmas      = true;   // Draw EMA 20 / 50 (as line segments; an EA cannot plot)

input group "-- Session Filter --"
input bool           InpUseSessionFilter = false; // Session Filter ON/OFF
input bool           InpSessTzAware   = true;   // DST-aware sessions (Tokyo/London/New York)
input int            InpAsiaOpen      = 0;      // Asia Open (UTC hour) - legacy
input int            InpAsiaClose     = 9;      // Asia Close (UTC hour)
input int            InpLonOpen       = 8;      // London Open (UTC hour)
input int            InpLonClose      = 17;     // London Close (UTC hour)
input int            InpNyOpen        = 13;     // New York Open (UTC hour)
input int            InpNyClose       = 22;     // New York Close (UTC hour)

input group "-- PULLBACK TRIGGER (v18.7) --"
input bool           InpPbEnable      = true;   // Enable PULLBACK (the arm = a limit order here)
input double         InpPbFront       = 0.15;   // Entry front-run (x ATR)
input double         InpPbSlAtr       = 1.5;    // Stop beyond level (x ATR) - 1.5 validated, 0.8 FAILED
input double         InpPbRoomAtr     = 0.4;    // Min room to level (x ATR)
input int            InpPbCoolBars    = 20;     // Cooldown bars between fires
input int            InpPbMaxHr       = 2;      // Max fires per hour (this chart)
input int            InpPbExpiry      = 90;     // ARMED level expiry (bars)
input double         InpPbTapMax      = 1.0;    // Max tap distance (x ATR)

input group "-- MANUAL MONITOR (v18.4g) --"
input bool           InpShowManual    = true;   // Show Manual Trade Monitor panel
input double         InpManRiskAtr    = 1.5;    // Manual ATR stop (x ATR)
input double         InpManMinSlAtr   = 1.0;    // Manual MIN stop distance (x ATR)
input double         InpManMaxTpAtr   = 8.0;    // Manual MAX structural TP distance (x ATR)

// feature flags (compile-time in the Pine; unvalidated engines ship dark)
const bool FEATURE_RANGE_BROKEN = true;
const bool FEATURE_PULLBACK     = true;
const bool FEATURE_STRUCT_GATE  = false;

input group "-- SignalMesh (journal of every fire / fill / close; ANALYSIS side only) --"
input bool           InpJournalToFile = true;   // Append every event to MQL5/Files/BS18_events_<symbol>.jsonl
input string         InpSignalMeshUrl = "https://app.signalmesh.dev/webhooks/brain/signal";   // Journal door (preset; "" = off). Armed only when the secret is set
input string         InpSignalMeshSecret = "";  // X-Brain-Secret (never printed). Empty = nothing is posted. Allow https://app.signalmesh.dev in Tools > Options > Expert Advisors
input int            InpSlippagePoints = 20;    // Max slippage (points) on market orders

//=== CONSTANTS: the Pine's colours (MT5 colour = 0xBBGGRR) =========
const color cLime     = 0x00FF00;
const color cGreen    = 0x008000;
const color cRed      = 0x0000FF;
const color cOrange   = 0x008CFF;
const color cYellow   = 0x00FFFF;
const color cAqua     = 0xFFFF00;
const color cTeal     = 0x808000;
const color cBlue     = 0xFF0000;
const color cPurple   = 0x800080;
const color cFuchsia  = 0xFF00FF;
const color cMaroon   = 0x000080;
const color cGray     = 0x808080;
const color cSilver   = 0xC0C0C0;
const color cWhite    = 0xFFFFFF;
const color cBlack    = 0x000000;
const color cAmber    = 0x00AAFF;   // #ffaa00
const color cNote     = 0xFFCCAA;   // #aaccff
const color cCyan     = 0xFFE500;   // #00e5ff
const color cNeonG    = 0x88FF00;   // #00ff88
const color cNeonR    = 0x6633FF;   // #ff3366
const color cDim      = 0x888888;
const color cDim2     = 0x555555;
const color cDim3     = 0x666666;
const color cNavy     = 0x3A1F1A;   // #1a1f3a
const color cPanelBg  = 0x270E0A;   // #0a0e27
const color cOrange2  = 0x0088FF;   // #ff8800
const color cManBg    = 0x1A1206;   // #06121a
const color cManHd    = 0x2A1F0A;   // #0a1f2a
// "transparent" fills on MT5 objects are solid: darkened shades stand in for Pine's alpha
const color cFillTeal   = 0x4A4A14;
const color cFillOrange = 0x14364A;
const color cFillBlue   = 0x4A2010;
const color cFillPurple = 0x3A143A;
const color cFillRedD   = 0x14143A;
const color cFillGrnD   = 0x143A14;
const color cFillGray   = 0x2A2A2A;
const color cSessGreen  = 0x101A10;
const color cSessRed    = 0x10101A;

#define BS_EV_MAX 400
const string BS_PREFIX = "BS18_";   // every chart object of this EA starts with it

//=== GLOBALS ======================================================
string   g_sym;
int      g_digits;
double   g_point;
double   g_tick;
double   g_volMin, g_volMax, g_volStep;
int      g_stopsLevel;
int      g_fill;
bool     g_isDemo;
long     g_srvOff;          // TimeTradeServer() - TimeGMT(), seconds
int      g_periodSec;
bool     g_intraday;
string   g_ticker;          // upper-case chart symbol
string   g_market;          // effectiveMarket
double   g_pipZone;
bool     g_symbolAllowed;
string   g_dxySym, g_yldSym, g_oilSym;
int      g_dxyM1Ok;         // 1 = the broker serves a 1m dollar index; 0 = no data
string   g_uUp, g_uDn, g_uArrUp, g_uArrDn, g_uWarn, g_uOk, g_uNo, g_uStar, g_uDot, g_uDash, g_uCross, g_uBullet, g_uFire, g_uBot, g_uHand, g_uDoubleDash;

// the window of chart bars read on every tick (index 0 = oldest)
int      g_n;
datetime g_t[];
double   g_o[];
double   g_h[];
double   g_l[];
double   g_c[];
double   g_v[];
double   g_ema20[];
double   g_ema50[];
double   g_rsi[];
double   g_atr[];
double   g_adx[];
double   g_volAvg[];
double   g_atrAvg[];
double   g_spread[];
double   g_vwap[];
double   g_rngAvg20[];
// higher timeframes + macro witnesses (whole series, closed-bar semantics resolved by time)
MqlRates g_h1[];
MqlRates g_h4[];
MqlRates g_d1[];
MqlRates g_w1[];
double   g_h1e20[];
double   g_h1e50[];
double   g_h4e20[];
double   g_h4e50[];
double   g_d1e20[];
double   g_d1e50[];
MqlRates g_dxyD[];
MqlRates g_yldD[];
MqlRates g_oilH[];
double   g_dxyE10[];
double   g_dxyE20[];
double   g_yldE10[];
double   g_yldE20[];
bool     g_haveH1, g_haveH4, g_haveD1, g_haveW1, g_haveDxy, g_haveYld, g_haveOil;

// live-only guards (clock based, like the Pine's timenow)
datetime g_squelchUntil;
double   g_dxyM1Pct;
bool     g_dxyM1Has;

// trading + journal
int      g_openCount, g_pendCount;
double   g_balance, g_dayPnl, g_floating;
int      g_tradesToday;       // this EA's fills today (NY calendar day)
int      g_dayKeyTrades;
datetime g_lastFireBar;       // the confirmed bar whose fire was acted on
datetime g_lastPbBar;
string   g_note;
string   g_webUrl;
string   g_webSecret;
string   g_webQ[];
int      g_webN;
datetime g_webLast;
int      g_webFails;
bool     g_jrFileWarned;
bool     g_webWarned;

// chart drawing state
datetime g_drawnBar;          // the last bar the history annotations were drawn for
int      g_evCount;
int      g_lineCount;

//=== SMALL HELPERS ==================================================
string NqRiskGate();
string S(string x) { return x; }
string U(int cp) { return ShortToString((ushort)cp); }
string F2(double v) { return DoubleToString(v, 2); }
string F4(double v) { return DoubleToString(v, 4); }
string FD(double v) { return DoubleToString(v, g_digits); }
string FS(double v) { return (v == EMPTY_VALUE) ? g_uDoubleDash : DoubleToString(v, 2); }   // the Pine's f_s: "--" for na
string FI(int v) { return IntegerToString(v); }
string F1(double v) { return DoubleToString(v, 1); }
bool   NA(double v) { return v == EMPTY_VALUE; }
double NZ(double v, double d) { return NA(v) ? d : v; }
int    RoundI(double v) { return (int)MathRound(v); }
double RoundTo(double v, int dec) { double p = MathPow(10.0, dec); return MathRound(v * p) / p; }

string NqJsonEsc(string v)
{
   string out = v;
   StringReplace(out, "\\", "\\\\");
   StringReplace(out, "\"", "\\\"");
   return out;
}
string NqJsonS(string key, string val) { return "\"" + key + "\":\"" + NqJsonEsc(val) + "\""; }
string NqJsonN(string key, double val, int digits) { return "\"" + key + "\":" + ((val == EMPTY_VALUE) ? S("null") : DoubleToString(val, digits)); }
string NqJsonI(string key, long val) { return "\"" + key + "\":" + IntegerToString(val); }
string NqJsonB(string key, bool val) { return "\"" + key + "\":" + (val ? S("true") : S("false")); }

//=== CIVIL TIME + DST (the Pine's America/New_York, Europe/London, Asia/Tokyo clocks) ===
void BsCivil(datetime t, int &y, int &m, int &d)
{
   long days = (long)t / 86400;
   long z = days + 719468;
   long era = ((z >= 0) ? z : z - 146096) / 146097;
   long doe = z - era * 146097;
   long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
   long yy = yoe + era * 400;
   long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
   long mp = (5 * doy + 2) / 153;
   d = (int)(doy - (153 * mp + 2) / 5 + 1);
   m = (int)((mp < 10) ? mp + 3 : mp - 9);
   y = (int)((m <= 2) ? yy + 1 : yy);
}
long BsDaysFromCivil(int y, int m, int d)
{
   long yy = (m <= 2) ? y - 1 : y;
   long era = ((yy >= 0) ? yy : yy - 399) / 400;
   long yoe = yy - era * 400;
   long doy = (153 * ((m > 2) ? m - 3 : m + 9) + 2) / 5 + d - 1;
   long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
   return era * 146097 + doe - 719468;
}
// the n-th Sunday of the month (n = 0 is the LAST Sunday)
int BsSundayOf(int y, int m, int n)
{
   if(n > 0)
   {
      long first = BsDaysFromCivil(y, m, 1);
      int dowFirst = (int)((first + 4) % 7);
      int day = 1 + ((7 - dowFirst) % 7) + 7 * (n - 1);
      return day;
   }
   int lastDay = (m == 12) ? 31 : (int)(BsDaysFromCivil(y, m + 1, 1) - BsDaysFromCivil(y, m, 1));
   long lastT = BsDaysFromCivil(y, m, lastDay);
   int dowLast = (int)((lastT + 4) % 7);
   return lastDay - dowLast;
}
bool BsUsDst(datetime utc)
{
   int y = 0, m = 0, d = 0;
   BsCivil(utc, y, m, d);
   datetime a = (datetime)(BsDaysFromCivil(y, 3, BsSundayOf(y, 3, 2)) * 86400 + 7 * 3600);
   datetime b = (datetime)(BsDaysFromCivil(y, 11, BsSundayOf(y, 11, 1)) * 86400 + 6 * 3600);
   return (utc >= a && utc < b);
}
bool BsEuDst(datetime utc)
{
   int y = 0, m = 0, d = 0;
   BsCivil(utc, y, m, d);
   datetime a = (datetime)(BsDaysFromCivil(y, 3, BsSundayOf(y, 3, 0)) * 86400 + 3600);
   datetime b = (datetime)(BsDaysFromCivil(y, 10, BsSundayOf(y, 10, 0)) * 86400 + 3600);
   return (utc >= a && utc < b);
}
datetime BsGmt(datetime server) { return (datetime)((long)server - g_srvOff); }
datetime BsNyLocal(datetime server) { datetime g = BsGmt(server); return (datetime)((long)g - 5 * 3600 + (BsUsDst(g) ? 3600 : 0)); }
datetime BsLonLocal(datetime server) { datetime g = BsGmt(server); return (datetime)((long)g + (BsEuDst(g) ? 3600 : 0)); }
datetime BsTokyoLocal(datetime server) { return (datetime)((long)BsGmt(server) + 9 * 3600); }
int  BsMod(datetime local) { return (int)(((long)local % 86400 + 86400) % 86400 / 60); }
int  BsDow(datetime local) { return (int)(((long)local / 86400 + 4) % 7); }   // 0 = Sunday
int  BsDom(datetime local) { int y = 0, m = 0, d = 0; BsCivil(local, y, m, d); return d; }
long BsDayKey(datetime local) { return (long)local / 86400; }
bool BsInWin(int mod, int s, int e) { if(s == e) return false; return (s < e) ? (mod >= s && mod < e) : (mod >= s || mod < e); }
int  BsHM(int h, int m) { return h * 60 + m; }

//=== SYMBOL RESOLUTION (a witness the broker does not serve = no data, never a guess) ===
string BsFindSym(string csv)
{
   int pos = 0;
   int n = StringLen(csv);
   while(pos < n)
   {
      int c = StringFind(csv, ",", pos);
      if(c < 0)
         c = n;
      string cand = StringSubstr(csv, pos, c - pos);
      pos = c + 1;
      if(cand != "" && SymbolSelect(cand, true))
         return cand;
   }
   return "";
}
string BsResolve(string inp, string autoCsv)
{
   if(inp == "-")
      return "";
   if(inp != "")
      return SymbolSelect(inp, true) ? inp : "";
   return BsFindSym(autoCsv);
}

//=== LOTS (the real tick value, never the Pine's "$ per point" estimate) ===
double NqLotFor(double riskMoney, double slDist, double tick, double tickValue,
                double volMin, double volMax, double volStep)
{
   if(riskMoney <= 0.0 || slDist <= 0.0 || tick <= 0.0 || tickValue <= 0.0 || volMin <= 0.0 || volStep <= 0.0)
      return 0.0;
   double lossPerLot = slDist / tick * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;
   double lot = riskMoney / lossPerLot;
   lot = MathFloor(lot / volStep + 1e-9) * volStep;
   if(volMax > 0.0 && lot > volMax)
      lot = volMax;
   if(lot < volMin - 1e-12)
      return 0.0;
   return NormalizeDouble(lot, 8);
}
double BsLots(double slDist)
{
   double tickValue = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      tickSize = g_tick;
   return NqLotFor(g_balance * InpRiskPct / 100.0, slDist, tickSize, tickValue, g_volMin, g_volMax, g_volStep);
}
double BsRoundTick(double px, int dir)
{
   if(g_tick <= 0.0)
      return px;
   double k = px / g_tick;
   double r = (dir > 0) ? MathCeil(k - 1e-9) : ((dir < 0) ? MathFloor(k + 1e-9) : MathRound(k));
   return NormalizeDouble(r * g_tick, g_digits);
}

//=== ROLLING MATH over the window arrays (index i = the bar, like the Pine's series) ===
double BsHighest(const double &a[], int i, int len) { double m = a[i]; for(int k = i - len + 1; k <= i; k++) if(k >= 0 && a[k] > m) m = a[k]; return m; }
double BsLowest(const double &a[], int i, int len) { double m = a[i]; for(int k = i - len + 1; k <= i; k++) if(k >= 0 && a[k] < m) m = a[k]; return m; }
double BsSmaAt(const double &a[], int i, int len)
{
   double s = 0.0;
   int cnt = 0;
   for(int k = i - len + 1; k <= i; k++)
      if(k >= 0) { s += a[k]; cnt++; }
   return (cnt > 0) ? s / cnt : 0.0;
}
// EMA over a whole array (seeded with the first value, the way a long history converges)
void BsEma(const double &src[], int n, int len, double &out[])
{
   ArrayResize(out, n);
   if(n <= 0)
      return;
   double k = 2.0 / (len + 1.0);
   out[0] = src[0];
   for(int i = 1; i < n; i++)
      out[i] = src[i] * k + out[i - 1] * (1.0 - k);
}

//=== DATA: the chart window, the higher timeframes, the macro witnesses =====
// index of the LAST CLOSED bar of series s at chart time t (the Pine's [1] + lookahead_on:
// the bar BEFORE the one that contains t); -1 when there is none
int BsClosedIdx(const MqlRates &s[], int ns, datetime t)
{
   int lo = 0, hi = ns - 1, ans = -1;
   while(lo <= hi)
   {
      int mid = (lo + hi) / 2;
      if(s[mid].time <= t) { ans = mid; lo = mid + 1; }
      else hi = mid - 1;
   }
   return ans - 1;
}
bool BsLoadSeries(string sym, ENUM_TIMEFRAMES tf, int count, MqlRates &out[])
{
   if(sym == "")
      return false;
   ArrayResize(out, 0);
   int n = CopyRates(sym, tf, 0, count, out);
   if(n < 2)
   {
      ArrayResize(out, 0);
      return false;
   }
   return true;
}
void BsEmaOfRates(const MqlRates &s[], int len, double &out[])
{
   int n = ArraySize(s);
   double c[];
   ArrayResize(c, n);
   for(int i = 0; i < n; i++)
      c[i] = s[i].close;
   BsEma(c, n, len, out);
}

bool BsLoadWindow()
{
   MqlRates r[];
   int want = (InpHistoryBars < 300) ? 300 : InpHistoryBars;
   int n = CopyRates(g_sym, PERIOD_CURRENT, 0, want, r);
   if(n < 120)
      return false;
   g_n = n;
   ArrayResize(g_t, n); ArrayResize(g_o, n); ArrayResize(g_h, n); ArrayResize(g_l, n); ArrayResize(g_c, n); ArrayResize(g_v, n);
   for(int i = 0; i < n; i++)
   {
      g_t[i] = r[i].time;
      g_o[i] = r[i].open;
      g_h[i] = r[i].high;
      g_l[i] = r[i].low;
      g_c[i] = r[i].close;
      g_v[i] = (double)r[i].tick_volume;
   }
   return true;
}

// SECTION 4 - BASE INDICATORS (ta.rsi / ta.atr / ta.dmi / ta.ema / ta.sma / ta.vwap)
void BsBaseIndicators()
{
   int n = g_n;
   ArrayResize(g_ema20, n); ArrayResize(g_ema50, n); ArrayResize(g_rsi, n); ArrayResize(g_atr, n); ArrayResize(g_adx, n);
   ArrayResize(g_volAvg, n); ArrayResize(g_atrAvg, n); ArrayResize(g_spread, n); ArrayResize(g_vwap, n); ArrayResize(g_rngAvg20, n);
   BsEma(g_c, n, 20, g_ema20);
   BsEma(g_c, n, 50, g_ema50);
   // RSI (Wilder)
   double gain = 0.0, loss = 0.0;
   int rl = (InpRsiLength < 2) ? 2 : InpRsiLength;
   for(int i = 0; i < n; i++)
   {
      double ch = (i > 0) ? g_c[i] - g_c[i - 1] : 0.0;
      double up = (ch > 0) ? ch : 0.0;
      double dn = (ch < 0) ? -ch : 0.0;
      if(i == 0) { gain = up; loss = dn; }
      else { gain = (gain * (rl - 1) + up) / rl; loss = (loss * (rl - 1) + dn) / rl; }
      g_rsi[i] = (loss <= 0.0) ? ((gain <= 0.0) ? 50.0 : 100.0) : 100.0 - 100.0 / (1.0 + gain / loss);
   }
   // ATR (Wilder) + ADX (Wilder, like ta.dmi)
   int al = (InpAtrLength < 1) ? 1 : InpAtrLength;
   int dl = (InpAdxLength < 1) ? 1 : InpAdxLength;
   double atr = 0.0, sTR = 0.0, sDMp = 0.0, sDMm = 0.0, adx = 0.0;
   double hl[];
   ArrayResize(hl, n);
   for(int i = 0; i < n; i++)
   {
      hl[i] = g_h[i] - g_l[i];
      double tr = hl[i];
      if(i > 0)
      {
         tr = MathMax(tr, MathMax(MathAbs(g_h[i] - g_c[i - 1]), MathAbs(g_l[i] - g_c[i - 1])));
         double upm = g_h[i] - g_h[i - 1];
         double dnm = g_l[i - 1] - g_l[i];
         double dmp = (upm > dnm && upm > 0) ? upm : 0.0;
         double dmm = (dnm > upm && dnm > 0) ? dnm : 0.0;
         atr = (i == 1) ? tr : (atr * (al - 1) + tr) / al;
         sTR = (i == 1) ? tr : (sTR * (dl - 1) + tr) / dl;
         sDMp = (i == 1) ? dmp : (sDMp * (dl - 1) + dmp) / dl;
         sDMm = (i == 1) ? dmm : (sDMm * (dl - 1) + dmm) / dl;
         double dip = (sTR > 0) ? 100.0 * sDMp / sTR : 0.0;
         double dim = (sTR > 0) ? 100.0 * sDMm / sTR : 0.0;
         double dx = (dip + dim > 0) ? 100.0 * MathAbs(dip - dim) / (dip + dim) : 0.0;
         adx = (i == 1) ? dx : (adx * (dl - 1) + dx) / dl;
      }
      else
         atr = tr;
      g_atr[i] = atr;
      g_adx[i] = adx;
   }
   for(int i = 0; i < n; i++)
   {
      g_volAvg[i] = BsSmaAt(g_v, i, 20);
      g_atrAvg[i] = BsSmaAt(g_atr, i, 50);
      g_spread[i] = BsSmaAt(hl, i, 3) * 0.1;
      g_rngAvg20[i] = BsSmaAt(hl, i, 20);
   }
   // daily VWAP (hlc3), anchored at the New York midnight like the ICT levels
   double pv = 0.0, vv = 0.0;
   long dayKey = -1;
   for(int i = 0; i < n; i++)
   {
      long k = BsDayKey(BsNyLocal(g_t[i]));
      if(k != dayKey) { pv = 0.0; vv = 0.0; dayKey = k; }
      double hlc3 = (g_h[i] + g_l[i] + g_c[i]) / 3.0;
      double vol = (g_v[i] > 0.0) ? g_v[i] : 1.0;
      pv += hlc3 * vol;
      vv += vol;
      g_vwap[i] = (vv > 0.0) ? pv / vv : hlc3;
   }
}

void BsLoadHtf()
{
   g_haveH1 = BsLoadSeries(g_sym, PERIOD_H1, 600, g_h1);
   g_haveH4 = BsLoadSeries(g_sym, PERIOD_H4, 400, g_h4);
   g_haveD1 = BsLoadSeries(g_sym, PERIOD_D1, 300, g_d1);
   g_haveW1 = BsLoadSeries(g_sym, PERIOD_W1, 120, g_w1);
   if(g_haveH1) { BsEmaOfRates(g_h1, 20, g_h1e20); BsEmaOfRates(g_h1, 50, g_h1e50); }
   if(g_haveH4) { BsEmaOfRates(g_h4, 20, g_h4e20); BsEmaOfRates(g_h4, 50, g_h4e50); }
   if(g_haveD1) { BsEmaOfRates(g_d1, 20, g_d1e20); BsEmaOfRates(g_d1, 50, g_d1e50); }
   g_haveDxy = BsLoadSeries(g_dxySym, PERIOD_D1, 200, g_dxyD);
   if(g_haveDxy) { BsEmaOfRates(g_dxyD, 10, g_dxyE10); BsEmaOfRates(g_dxyD, 20, g_dxyE20); }
   g_haveYld = InpUseYieldMacro && BsLoadSeries(g_yldSym, PERIOD_D1, 200, g_yldD);
   if(g_haveYld) { BsEmaOfRates(g_yldD, 10, g_yldE10); BsEmaOfRates(g_yldD, 20, g_yldE20); }
   g_haveOil = BsLoadSeries(g_oilSym, PERIOD_H1, 300, g_oilH);
}

// SECTION 5d - DXY VOLATILITY SQUELCH: the worst 1-minute range of the dollar index inside
// the CURRENT chart bar (the Pine's request.security_lower_tf), a LIVE guard on the real clock
void BsDxySquelchScan()
{
   g_dxyM1Has = false;
   g_dxyM1Pct = 0.0;
   if(!InpUseDXYSquelch || g_dxySym == "" || g_n < 1)
      return;
   MqlRates m1[];
   int want = g_periodSec / 60 + 2;
   if(want < 3)
      want = 3;
   int n = CopyRates(g_dxySym, PERIOD_M1, 0, want, m1);
   if(n <= 0)
      return;
   datetime barOpen = g_t[g_n - 1];
   double mx = 0.0;
   int seen = 0;
   for(int i = 0; i < n; i++)
   {
      if(m1[i].time < barOpen)
         continue;
      seen++;
      if(m1[i].close > 0.0)
      {
         double r = (m1[i].high - m1[i].low) / m1[i].close * 100.0;
         if(r > mx)
            mx = r;
      }
   }
   if(seen == 0)
      return;
   g_dxyM1Has = true;
   g_dxyM1Pct = mx;
   if(mx >= InpDxySquelchPct)
      g_squelchUntil = (datetime)((long)TimeTradeServer() + InpDxySquelchSecs);
}

//=== THE PINE'S STATE (every `var` of the script, replayed over the window on every pass) ===
struct BsEv            // a chart annotation produced while replaying (drawn once per bar)
{
   int      kind;      // 1 label up, 2 label down, 3 box, 4 line segment
   datetime t1, t2;
   double   p1, p2;
   string   text;
   color    clr;
   color    txt;
   int      size;      // font px
   int      width;
};
BsEv     g_ev[];
int      g_nEv;

// outputs of the pass at the bar the panels read (the live bar) - named as in the Pine
struct BsOut
{
   // session / clock
   bool inAsia, inLondon, inNewYork, sessionTrade;
   string sessionTxt; color sessionClr;
   bool inKzPre, inKzOpen, inKzAfter, inAnyNYKz; string kzLabel; color kzClr;
   bool inNewsWindow, volHigh;
   double aeZoneMul, aeChaseMul, aeSLFloor;
   bool dxySquelched; int dxySqRemain; string dxySqTxt; color dxySqClr;
   // levels
   double pdHigh, pdLow, wHigh, wLow, nwogOpen, orgHigh, orgLow, midnightOpen, nyCloseY;
   double dxyClose; bool dxyRising, dxyFalling; string dxyTxt; color dxyClr;
   bool isMetals, dxyBullConfirm, dxySellConfirm;
   bool yieldRising, yieldFalling; string yieldTxt; color yieldClr;
   int tradesToday;
   // HTF
   bool h1Bull, h1Bear, h4Bull, h4Bear, dailyBull, dailyBear, htfBullAgree, htfBearAgree, htfFullAgree;
   int htfBullCount, htfBearCount;
   // structure
   double highSwing, lowSwing, lastHigh, lastLow, prevHigh, prevLow;
   string trend; bool isUpTrend, isDownTrend, isHH, isHL, isLH, isLL;
   string structState;
   double rangeHigh, rangeLow, equilLevel; bool inPremium, inDiscount; string fibZoneTxt; color fibZoneClr;
   // pivots
   double pivotP, pivotR1, pivotR2, pivotR3, pivotS1, pivotS2, pivotS3; string nearestPivotName; double nearestPivotVal; bool atPivot, abovePP;
   // choch / bos
   bool chochUp, chochDown, chochRecent; string lastChoch, chochTxt; color chochClr; bool bosUp, bosDown;
   // fvg
   double lastBullFVGtop, lastBullFVGbot, lastBearFVGtop, lastBearFVGbot;
   bool bullFVGabove, bullFVGinside, bearFVGbelow, bearFVGinside, fvgPresent; string fvgStatusTxt; color fvgStatusClr;
   // ob
   bool impulseUp, impulseDown, bullOB, bearOB; string lastOBtype; bool obMitigated; string obStatusTxt; color obStatusClr, obStrengthClr;
   double ssBullOBhigh, ssBullOBlow, ssBearOBhigh, ssBearOBlow;
   // liquidity
   bool stopHuntBull, stopHuntBear, equalHighs, equalLows, sweepRecent; string lastSweepType, sweepTxt; color sweepClr;
   bool fakeBOdown, fakeBOup, realMoveUp, realMoveDown;
   // candles
   bool bullEngulf, bearEngulf, pinBarBull, pinBarBear, isDoji, isHammer, isShootStar, insideBar, bullMaru, bearMaru;
   string currentPatternTxt; color currentPatternClr; bool candlePatternOk, candlePatternOkBear;
   // inducement
   bool bearInducement, bullInducement; string inducementTxt; color inducementClr;
   // scalp ticks
   bool nearSupport, nearResistance, scalpTickBull, scalpTickBear;
   // score
   int scoreBuy, scoreSell; string scoreBuyTxt, scoreSellTxt; color scoreBuyClr, scoreSellClr;
   string confVerdict, buyVerdict, sellVerdict; color buyVerdictClr, sellVerdictClr;
   int minFactorsBuy, minFactorsSell; bool minRuleBuy, minRuleSell; string minRuleBuyTxt, minRuleSellTxt; color minRuleBuyClr, minRuleSellClr;
   string rrQuality; color rrQualityClr;
   // location gate
   bool trendDayOK, sellZnFVG, sellZnOB, sellZnSwing, sellZnPivot, sellZnOther, sellSweepLG, sellZnTrend, sellZoneNear;
   bool buyZnFVG, buyZnOB, buyZnSwing, buyZnPivot, buyZnOther, buySweepLG, buyZnTrend, buyZoneNear;
   string sellZoneTxt, buyZoneTxt, sellZoneMem, buyZoneMem;
   bool sellZoneOK, buyZoneOK, sellChaseOK, buyChaseOK, sellRejectC, buyRejectC, sellConfirmC, buyConfirmC, sellTrigOK, buyTrigOK;
   bool lgBuyCooldownOK, lgSellCooldownOK, locBuyOK, locSellOK; string locBuyTxt, locSellTxt; color locBuyClr, locSellClr;
   double buyDistZ, sellDistZ;
   // pullback
   double pbBuyE, pbBuySL, pbBuyT1, pbBuyT2, pbSellE, pbSellSL, pbSellT1, pbSellT2;
   string pbBuyDeath, pbSellDeath, pbBuySrc, pbSellSrc; int trendAge; bool pbHtfAln; bool pbFireB, pbFireS; double pbRRb, pbRRs;
   // manual monitor
   string manDir; bool manCtr, manIsBuy; double manMktE, manPendE, manSL, manTP1, manTP2, manRR; string manMethod, manStatus; color manStatusClr; bool manGatePass;
   // legacy conditions
   bool buyCondition, sellCondition;
   // sessions ranges
   double asiaH, asiaL, lonH, lonL, nyH, nyL;
   bool oilSpike; string oilTxt; color oilClr; bool atrExpand; string atrExpTxt; color atrExpClr;
   double sessPct; bool sessPctOk;
   // pending brain
   double pendHiRaw, pendLoRaw, pendHiSrc, pendLoSrc, pendRngA; bool pendInvalid, pendBrokeUp, pendBrokeDn;
   string nyRegime; color nyRegimeClr; bool isBigCandle, lonWasTight, trapFiredUp, trapFiredDown; string trapBias; color trapBiasClr; string trapDetail;
   double atrPad; bool atrPadActive; string tgtSource; color tgtSourceClr; bool pendHiFromGate, pendLoFromGate; string pendHiSrcTxt, pendLoSrcTxt;
   double pendRange, tightThreshold; bool rangeTooTight; string rangeTightTxt; bool hideEntries, redWarn;
   double pendSellE, pendSellSL, pendSellTP1, pendSellTP2, pendSellTP3, pendBuyE, pendBuySL, pendBuyTP1, pendBuyTP2, pendBuyTP3;
   double pendRiskS, pendRiskB, pendLotsS, pendLotsB, distSell, distBuy, pendRRS, pendRRB;
   bool pendSellAtMkt, pendBuyAtMkt; double buyStopE, sellStopE;
   // smart scalp
   bool ssFireB, ssFireS, ssFireBotB, ssFireBotS; double ssBuySL, ssSellSL, ssBuyTP1, ssBuyTP2, ssSellTP1, ssSellTP2, ssBuyRR, ssSellRR, ssBLots, ssSLots;
   string ssBGrade, ssSGrade; int adjScoreBuy, adjScoreSell, bV, sV, macroBuy, macroSell; bool buyTP1struct, sellTP1struct;
   string botBuyWhy, botSellWhy; bool botBC, botSC;
   // active signal panel
   bool saActive; string saDir; double saEntry, saSL, saTP1, saTP2, saRR, saLots; int saScore, saBar; string saGrade, saEndWhy;
   // misc
   double rsiValue, atrValue, atrSL, adxVal, volAvg, spreadVal, dVwap, ma20, ma50, lgEma20; string vwapSide;
   bool volOk, spreadOk, adxTrendStrong, adxTrendModerate, adxTrendWeak; string trendStrengthTxt; color trendStrengthClr; string spreadTxt; color spreadClr;
   string volLevel; color volLevelClr; bool rsiBull, rsiBear;
   bool emaCross; string biasDir; color biasClr; bool readyBuy, readySell, nearSup, nearRes;
   double close;
};
BsOut    g_out;

// the replay's working state (reset at the top of every pass)
struct BsVars
{
   double lastHigh, lastLow, prevHigh, prevLow, rangeHigh, rangeLow;
   string trend; bool smHH, smHL, smLH, smLL;
   double lastBullFVGtop, lastBullFVGbot, lastBearFVGtop, lastBearFVGbot;
   string lastOBtype; bool lastOBfresh; int lastOBbar; double ssBullOBhigh, ssBullOBlow, ssBearOBhigh, ssBearOBlow;
   int lastSHbullBar, lastSHbearBar; string lastSweepType; int lastSweepBar; int lastFBdownBar, lastFBupBar, lastRMupBar, lastRMdownBar;
   int lastBearIndBar, lastBullIndBar; string lastChoch; int lastChochBar;
   string sellZoneMem, buyZoneMem; double buyZonePx, sellZonePx; int lgLastBuyFireBar, lgLastSellFireBar;
   double nwogOpen, orgHigh, orgLow, midnightOpen; int tradesToday; long dayKeyNy;
   double asiaH, asiaL, lonH, lonL, nyH, nyL; bool prvAsia, prvLon, prvNY; double lonRngLast;
   double lonRngHist[5]; int lonRngN;
   double pbBuyE, pbBuySL, pbBuyT1, pbBuyT2, pbSellE, pbSellSL, pbSellT1, pbSellT2; int pbLastFire, pbBuyArmBar, pbSellArmBar;
   string pbBuyDeath, pbSellDeath, pbBuySrc, pbSellSrc; int pbFiresHr; long pbHrKey; int h1FlipBar; bool prevH1Bull, prevH1Bear;
   double sigEntry, sigMicroSL; string sigDir; int sigBar; bool sigActive;
   double saEntry, saSL, saTP1, saTP2, saRR, saLots; int saScore; string saGrade; string saDir; int saBar; bool saActive; string saEndWhy;
   bool sellRejC1, sellRejC2, buyRejC1, buyRejC2;   // sellRejectC[1], [2]
   int sellTouchAge, buyTouchAge;                    // ta.barssince
   int sellTouchAgeBar, buyTouchAgeBar;              // last bar the zone was near (-1 = never)
   bool prevCloseAboveLastHigh, prevCloseBelowLastLow; double prevLastHigh, prevLastLow;
   // the latest closed-bar fires (what the trade layer acts on)
   datetime ssFireBarT; bool ssFireBotBuy; datetime pbFireBarT; bool pbFireBuy;
};
BsVars   V;

// the confirmed-bar snapshot of what the trade layer needs (filled by BsPass at i == n-2)
struct BsFireSnap
{
   datetime bar;
   bool ssBuy, ssSell; double ssEntry, ssSL, ssTP1, ssTP2, ssRR, ssLots; string ssGrade; int ssScore;
   bool pbBuy, pbSell; double pbE, pbSL, pbT1, pbT2, pbRR; bool pbAln;
   double armBuyE, armBuySL, armBuyT1, armBuyT2, armSellE, armSellSL, armSellT1, armSellT2; int armBuyBar, armSellBar; datetime armBuyT, armSellT;
   bool pbCoolOK, pbHrOK, squelched, newsBlock;
};
BsFireSnap g_fire;

void BsResetVars()
{
   V.lastHigh = EMPTY_VALUE; V.lastLow = EMPTY_VALUE; V.prevHigh = EMPTY_VALUE; V.prevLow = EMPTY_VALUE; V.rangeHigh = EMPTY_VALUE; V.rangeLow = EMPTY_VALUE;
   V.trend = "NONE"; V.smHH = false; V.smHL = false; V.smLH = false; V.smLL = false;
   V.lastBullFVGtop = EMPTY_VALUE; V.lastBullFVGbot = EMPTY_VALUE; V.lastBearFVGtop = EMPTY_VALUE; V.lastBearFVGbot = EMPTY_VALUE;
   V.lastOBtype = "NONE"; V.lastOBfresh = false; V.lastOBbar = -1; V.ssBullOBhigh = EMPTY_VALUE; V.ssBullOBlow = EMPTY_VALUE; V.ssBearOBhigh = EMPTY_VALUE; V.ssBearOBlow = EMPTY_VALUE;
   V.lastSHbullBar = -1; V.lastSHbearBar = -1; V.lastSweepType = "NONE"; V.lastSweepBar = -1; V.lastFBdownBar = -1; V.lastFBupBar = -1; V.lastRMupBar = -1; V.lastRMdownBar = -1;
   V.lastBearIndBar = -1; V.lastBullIndBar = -1; V.lastChoch = "NONE"; V.lastChochBar = -1;
   V.sellZoneMem = g_uDash; V.buyZoneMem = g_uDash; V.buyZonePx = EMPTY_VALUE; V.sellZonePx = EMPTY_VALUE; V.lgLastBuyFireBar = -100000; V.lgLastSellFireBar = -100000;
   V.nwogOpen = EMPTY_VALUE; V.orgHigh = EMPTY_VALUE; V.orgLow = EMPTY_VALUE; V.midnightOpen = EMPTY_VALUE; V.tradesToday = 0; V.dayKeyNy = -1;
   V.asiaH = EMPTY_VALUE; V.asiaL = EMPTY_VALUE; V.lonH = EMPTY_VALUE; V.lonL = EMPTY_VALUE; V.nyH = EMPTY_VALUE; V.nyL = EMPTY_VALUE; V.prvAsia = false; V.prvLon = false; V.prvNY = false;
   V.lonRngLast = EMPTY_VALUE; V.lonRngN = 0;
   V.pbBuyE = EMPTY_VALUE; V.pbBuySL = EMPTY_VALUE; V.pbBuyT1 = EMPTY_VALUE; V.pbBuyT2 = EMPTY_VALUE; V.pbSellE = EMPTY_VALUE; V.pbSellSL = EMPTY_VALUE; V.pbSellT1 = EMPTY_VALUE; V.pbSellT2 = EMPTY_VALUE;
   V.pbLastFire = -1; V.pbBuyArmBar = -1; V.pbSellArmBar = -1; V.pbBuyDeath = ""; V.pbSellDeath = ""; V.pbBuySrc = ""; V.pbSellSrc = ""; V.pbFiresHr = 0; V.pbHrKey = -1; V.h1FlipBar = -1; V.prevH1Bull = false; V.prevH1Bear = false;
   V.sigEntry = EMPTY_VALUE; V.sigMicroSL = EMPTY_VALUE; V.sigDir = "NONE"; V.sigBar = -1; V.sigActive = false;
   V.saEntry = EMPTY_VALUE; V.saSL = EMPTY_VALUE; V.saTP1 = EMPTY_VALUE; V.saTP2 = EMPTY_VALUE; V.saRR = EMPTY_VALUE; V.saLots = EMPTY_VALUE; V.saScore = 0; V.saGrade = g_uDoubleDash; V.saDir = "NONE"; V.saBar = -1; V.saActive = false; V.saEndWhy = "";
   V.sellRejC1 = false; V.sellRejC2 = false; V.buyRejC1 = false; V.buyRejC2 = false; V.sellTouchAgeBar = -1; V.buyTouchAgeBar = -1;
   V.prevLastHigh = EMPTY_VALUE; V.prevLastLow = EMPTY_VALUE;
   V.ssFireBarT = 0; V.ssFireBotBuy = false; V.pbFireBarT = 0; V.pbFireBuy = false;
}

// SECTION 3 - AUTO PIPZONE
bool BsHas(string hay, string needle) { return StringFind(hay, needle) >= 0; }
string BsAutoMarket()
{
   string t = g_ticker;
   if(BsHas(t, "XAUUSD") || BsHas(t, "GOLD")) return "Gold";
   if(BsHas(t, "XAGUSD") || BsHas(t, "SILVER")) return "Silver";
   if(BsHas(t, "EURUSD")) return "Forex EURUSD";
   if(BsHas(t, "USDJPY")) return "Forex USDJPY";
   if(BsHas(t, "DXY")) return "DXY";
   if(BsHas(t, "USOIL") || BsHas(t, "WTICO") || BsHas(t, "WTI")) return "Oil WTI";
   if(BsHas(t, "US30") || BsHas(t, "DJI")) return "US30 Dow";
   if(BsHas(t, "NAS100") || BsHas(t, "NDX") || BsHas(t, "NASDAQ")) return "NAS100";
   if(BsHas(t, "BTC")) return "BTC";
   if(BsHas(t, "ETH")) return "ETH";
   if(BsHas(t, "XRP")) return "XRP";
   return "UNKNOWN";
}
string BsMarketName(BS_MARKET m)
{
   switch(m)
   {
      case MK_SILVER: return "Silver";
      case MK_GOLD: return "Gold";
      case MK_EURUSD: return "Forex EURUSD";
      case MK_USDJPY: return "Forex USDJPY";
      case MK_DXY: return "DXY";
      case MK_OIL: return "Oil WTI";
      case MK_US30: return "US30 Dow";
      case MK_NAS100: return "NAS100";
      case MK_BTC: return "BTC";
      case MK_ETH: return "ETH";
      case MK_XRP: return "XRP";
      default: return "Auto";
   }
}
double BsPipZoneOf(string mk)
{
   if(mk == "Gold") return 1.00;
   if(mk == "Silver") return 0.10;
   if(mk == "Forex EURUSD") return 0.0010;
   if(mk == "Forex USDJPY") return 0.10;
   if(mk == "DXY") return 0.10;
   if(mk == "Oil WTI") return 0.10;
   if(mk == "US30 Dow") return 10.0;
   if(mk == "NAS100") return 10.0;
   if(mk == "BTC") return 50.0;
   if(mk == "ETH") return 2.00;
   if(mk == "XRP") return 0.005;
   return 0.10;
}
double BsTightAutoThr(string mk)
{
   if(mk == "Gold") return 5.0;
   if(mk == "Silver") return 0.20;
   if(mk == "Forex EURUSD") return 0.0030;
   if(mk == "Forex USDJPY") return 0.30;
   if(mk == "DXY") return 0.30;
   if(mk == "Oil WTI") return 0.50;
   if(mk == "US30 Dow") return 30.0;
   if(mk == "NAS100") return 30.0;
   if(mk == "BTC") return 200.0;
   if(mk == "ETH") return 8.0;
   if(mk == "XRP") return 0.015;
   return 5.0;
}
bool BsSymbolAllowed()
{
   if(g_market == "UNKNOWN")
      return false;
   if(!InpSsWhitelistOnly)
      return true;
   string t = g_ticker;
   return (InpWlGold && (BsHas(t, "XAUUSD") || BsHas(t, "GOLD"))) || (InpWlSilver && (BsHas(t, "XAGUSD") || BsHas(t, "SILVER"))) ||
          (InpWlBTC && BsHas(t, "BTC")) || (InpWlETH && BsHas(t, "ETH")) || (InpWlUSDJPY && BsHas(t, "USDJPY")) || (InpWlEURUSD && BsHas(t, "EURUSD")) ||
          (InpWlUS30 && (BsHas(t, "US30") || BsHas(t, "DJI"))) || (InpWlUS100 && (BsHas(t, "US100") || BsHas(t, "NAS100") || BsHas(t, "NDX") || BsHas(t, "NASDAQ"))) ||
          (InpWlOil && (BsHas(t, "USOIL") || BsHas(t, "WTI"))) || (InpWlXRP && BsHas(t, "XRP")) || (InpWlDXY && BsHas(t, "DXY"));
}

// chart annotations collected during the replay
void BsEvPush(int kind, datetime t1, double p1, datetime t2, double p2, string text, color clr, color txt, int size, int width)
{
   if(g_nEv >= BS_EV_MAX)
      return;
   int k = g_nEv;
   ArrayResize(g_ev, k + 1, 64);
   g_ev[k].kind = kind; g_ev[k].t1 = t1; g_ev[k].p1 = p1; g_ev[k].t2 = t2; g_ev[k].p2 = p2;
   g_ev[k].text = text; g_ev[k].clr = clr; g_ev[k].txt = txt; g_ev[k].size = size; g_ev[k].width = width;
   g_nEv = k + 1;
}
void BsLabelUp(bool draw, datetime t, double p, string text, color clr, int size)   { if(draw) BsEvPush(1, t, p, 0, 0, text, clr, cWhite, size, 1); }
void BsLabelDown(bool draw, datetime t, double p, string text, color clr, int size) { if(draw) BsEvPush(2, t, p, 0, 0, text, clr, cWhite, size, 1); }
void BsBox(bool draw, datetime t1, double p1, datetime t2, double p2, color fill, color border) { if(draw) BsEvPush(3, t1, p1, t2, p2, "", fill, border, 0, 1); }
void BsSeg(bool draw, datetime t1, double p1, datetime t2, double p2, color clr, int style, int width) { if(draw) BsEvPush(4, t1, p1, t2, p2, "", clr, (color)style, 0, width); }
datetime BsBarT(int i) { return (i >= 0 && i < g_n) ? g_t[i] : (datetime)((long)g_t[g_n - 1] + (long)(i - g_n + 1) * g_periodSec); }

// SECTION 7 - pivot high / low (ta.pivothigh(high, length, length)): confirmed `length` bars later
bool BsPivotHigh(int i, int len, double &val)
{
   int c = i - len;
   if(c - len < 0)
      return false;
   double pv = g_h[c];
   for(int k = c - len; k < c; k++)
      if(g_h[k] >= pv)
         return false;
   for(int k = c + 1; k <= i; k++)
      if(g_h[k] > pv)
         return false;
   val = pv;
   return true;
}
bool BsPivotLow(int i, int len, double &val)
{
   int c = i - len;
   if(c - len < 0)
      return false;
   double pv = g_l[c];
   for(int k = c - len; k < c; k++)
      if(g_l[k] <= pv)
         return false;
   for(int k = c + 1; k <= i; k++)
      if(g_l[k] < pv)
         return false;
   val = pv;
   return true;
}
// SECTION 16B helpers (f_znUp / f_znDn)
bool BsZnUp(double lvl, double hi, double cl, double tol) { return !NA(lvl) && hi >= lvl - tol && cl <= lvl + tol; }
bool BsZnDn(double lvl, double lo, double cl, double tol) { return !NA(lvl) && lo <= lvl + tol && cl >= lvl - tol; }
double BsPbBelow(double lvl, double cl) { return (!NA(lvl) && lvl < cl) ? lvl : -1.0e12; }
double BsPbAbove(double lvl, double cl) { return (!NA(lvl) && lvl > cl) ? lvl : 1.0e12; }
// sorted candidate arrays for the SMART SCALP SL / TP pickers
void BsPushIf(double &arr[], int &n, double v, bool cond) { if(cond && !NA(v)) { ArrayResize(arr, n + 1, 16); arr[n] = v; n++; } }
void BsSortAsc(double &arr[], int n) { for(int i = 1; i < n; i++) { double x = arr[i]; int j = i - 1; while(j >= 0 && arr[j] > x) { arr[j + 1] = arr[j]; j--; } arr[j + 1] = x; } }
void BsSortDesc(double &arr[], int n) { for(int i = 1; i < n; i++) { double x = arr[i]; int j = i - 1; while(j >= 0 && arr[j] < x) { arr[j + 1] = arr[j]; j--; } arr[j + 1] = x; } }
double BsArrMax(const double &arr[], int n) { double m = arr[0]; for(int i = 1; i < n; i++) if(arr[i] > m) m = arr[i]; return m; }
double BsArrMin(const double &arr[], int n) { double m = arr[0]; for(int i = 1; i < n; i++) if(arr[i] < m) m = arr[i]; return m; }

//=== THE PASS: the Pine script, bar by bar, over the window ========================
// draw = annotations are collected (only on a new bar, only for the last InpDrawBars bars)
void BsPass(bool draw)
{
   int n = g_n;
   BsResetVars();
   g_nEv = 0;
   ArrayResize(g_ev, 0);
   datetime nowS = TimeTradeServer();
   bool squelchNow = (nowS < g_squelchUntil);
   int drawFrom = n - 1 - InpDrawBars;
   int length = (InpLength < 2) ? 2 : InpLength;
   bool sellRej1 = false, sellRej2 = false, buyRej1 = false, buyRej2 = false;
   bool h1BullPrev = false, h1BearPrev = false;
   int firstBar = 0;

   for(int i = firstBar; i < n; i++)
   {
      bool confirmed = (i < n - 1);
      bool isLast = (i == n - 1);
      bool dr = draw && i >= drawFrom && confirmed;
      datetime t = g_t[i];
      double open = g_o[i], high = g_h[i], low = g_l[i], close = g_c[i], vol = g_v[i];
      double close1 = (i > 0) ? g_c[i - 1] : close, open1 = (i > 0) ? g_o[i - 1] : open, high1 = (i > 0) ? g_h[i - 1] : high, low1 = (i > 0) ? g_l[i - 1] : low;
      double close2 = (i > 1) ? g_c[i - 2] : close1, open2 = (i > 1) ? g_o[i - 2] : open1, high2 = (i > 1) ? g_h[i - 2] : high1, low2 = (i > 1) ? g_l[i - 2] : low1;
      double atrValue = g_atr[i], rsiValue = g_rsi[i], adxVal = g_adx[i];
      double atrSL = atrValue * InpAtrMult;
      double volAvg = g_volAvg[i];
      bool volOk = !InpUseVolume || vol >= volAvg * InpVolMult;
      bool rsiBull = rsiValue < InpRsiOB, rsiBear = rsiValue > InpRsiOS;
      bool adxTrendStrong = adxVal >= InpAdxStrong, adxTrendModerate = adxVal >= InpAdxWeak && adxVal < InpAdxStrong, adxTrendWeak = adxVal < InpAdxWeak;
      double spreadVal = g_spread[i];
      bool spreadOk = spreadVal <= (g_pipZone * InpMaxSpread);
      double dVwap = g_vwap[i];
      string vwapSide = (close > dVwap) ? "ABOVE" : "BELOW";
      double ma20 = g_ema20[i], ma50 = g_ema50[i];

      // SECTION 5 - SESSION (DST-aware: Tokyo 09-18, London 08-17, New York 08-17)
      datetime tNy = BsNyLocal(t), tLon = BsLonLocal(t), tTok = BsTokyoLocal(t), tGmt = BsGmt(t);
      int modNy = BsMod(tNy), modLon = BsMod(tLon), modTok = BsMod(tTok), hourUtc = BsMod(tGmt) / 60;
      bool inAsia = InpSessTzAware ? BsInWin(modTok, BsHM(9, 0), BsHM(18, 0)) : (hourUtc >= InpAsiaOpen && hourUtc < InpAsiaClose);
      bool inLondon = InpSessTzAware ? BsInWin(modLon, BsHM(8, 0), BsHM(17, 0)) : (hourUtc >= InpLonOpen && hourUtc < InpLonClose);
      bool inNewYork = InpSessTzAware ? BsInWin(modNy, BsHM(8, 0), BsHM(17, 0)) : (hourUtc >= InpNyOpen && hourUtc < InpNyClose);
      string sessionTxt = inNewYork ? "NEW YORK" : (inLondon ? "LONDON" : (inAsia ? "ASIA" : "OFF-HRS"));
      bool sessionTrade = !InpUseSessionFilter || inLondon || inNewYork;
      double atrAvg = g_atrAvg[i];
      string volLevel = (atrValue > atrAvg * 1.3) ? "HIGH" : ((atrValue > atrAvg * 0.7) ? "MEDIUM" : "LOW");
      // SECTION 5c - NY killzones + news windows (America/New_York)
      bool inKzPre = InpNyKzPreOpen && BsInWin(modNy, BsHM(8, 30), BsHM(9, 0));
      bool inKzOpen = InpNyKzCashOpen && BsInWin(modNy, BsHM(9, 30), BsHM(10, 30));
      bool inKzAfter = InpNyKzAfternoon && BsInWin(modNy, BsHM(13, 0), BsHM(14, 0));
      bool inAnyNYKz = InpUseNYProtocol && (inKzPre || inKzOpen || inKzAfter);
      bool inNewsData = BsInWin(modNy, BsHM(8, 25), BsHM(9, 5));
      bool inNewsFOMC = BsInWin(modNy, BsHM(13, 55), BsHM(14, 35));
      bool inNewsWindow = InpUseNewsAware && (inNewsData || inNewsFOMC);
      bool volHigh = (volLevel == "HIGH");
      double aeZoneMul = (InpUseAdaptive && volHigh) ? InpAeZoneHi : 1.0;
      double aeChaseMul = (InpUseAdaptive && volHigh) ? InpAeChaseHi : 1.0;
      double aeSLFloor = (InpUseAdaptive && (volHigh || inNewsWindow)) ? InpAeSLFloorHi : InpAeSLFloorLo;
      bool dxySquelched = (i >= n - 2) && squelchNow;

      // SECTION 5b - PDH/PDL, weekly H/L (the last CLOSED daily / weekly bar)
      double pdHigh = EMPTY_VALUE, pdLow = EMPTY_VALUE, dHigh = EMPTY_VALUE, dLow = EMPTY_VALUE, dClose2 = EMPTY_VALUE;
      if(g_haveD1)
      {
         int j = BsClosedIdx(g_d1, ArraySize(g_d1), t);
         if(j >= 0) { pdHigh = g_d1[j].high; pdLow = g_d1[j].low; dHigh = pdHigh; dLow = pdLow; dClose2 = g_d1[j].close; }
      }
      double wHigh = EMPTY_VALUE, wLow = EMPTY_VALUE;
      if(g_haveW1)
      {
         int j = BsClosedIdx(g_w1, ArraySize(g_w1), t);
         if(j >= 0) { wHigh = g_w1[j].high; wLow = g_w1[j].low; }
      }
      // NWOG / ORG / Midnight: the chart's own 00:00 NY and 09:30 NY bar
      if(g_intraday && BsDow(tNy) == 1 && modNy == 0)
         V.nwogOpen = open;
      bool isNYOpen = g_intraday && modNy == BsHM(9, 30);
      if(isNYOpen) { V.orgHigh = high; V.orgLow = low; }
      if(g_intraday && modNy == 0)
         V.midnightOpen = open;
      // DXY correlation (daily, confirmed) + US 10Y yield
      double dxyClose = EMPTY_VALUE; bool dxyRising = false, dxyFalling = false;
      if(g_haveDxy)
      {
         int j = BsClosedIdx(g_dxyD, ArraySize(g_dxyD), t);
         if(j >= 0) { dxyClose = g_dxyD[j].close; dxyRising = dxyClose > g_dxyE10[j] && g_dxyE10[j] > g_dxyE20[j]; dxyFalling = dxyClose < g_dxyE10[j] && g_dxyE10[j] < g_dxyE20[j]; }
      }
      string dxyTxt = NA(dxyClose) ? "N/A" : (dxyRising ? "RISING " + g_uArrUp : (dxyFalling ? "FALLING " + g_uArrDn : "NEUTRAL"));
      bool isMetals = (g_market == "Silver" || g_market == "Gold");
      bool dxyBullConfirm = !InpUseDXYFilter || !isMetals || dxyFalling || NA(dxyClose);
      bool dxySellConfirm = !InpUseDXYFilter || !isMetals || dxyRising || NA(dxyClose);
      double yldClose = EMPTY_VALUE; bool yieldRising = false, yieldFalling = false;
      if(g_haveYld)
      {
         int j = BsClosedIdx(g_yldD, ArraySize(g_yldD), t);
         if(j >= 0) { yldClose = g_yldD[j].close; yieldRising = yldClose > g_yldE10[j] && g_yldE10[j] > g_yldE20[j]; yieldFalling = yldClose < g_yldE10[j] && g_yldE10[j] < g_yldE20[j]; }
      }
      string yieldTxt = !InpUseYieldMacro ? "OFF" : (NA(yldClose) ? "N/A" : (yieldRising ? "RISING " + g_uArrUp : (yieldFalling ? "FALLING " + g_uArrDn : "NEUTRAL")));
      // daily counter reset on the New York calendar day
      long dayKey = BsDayKey(tNy);
      if(dayKey != V.dayKeyNy) { if(V.dayKeyNy != -1) V.tradesToday = 0; V.dayKeyNy = dayKey; }
      bool tradeAllowed = true;

      // SECTION 6 - HTF TREND (last closed H1 / H4 / D bar)
      bool h1Bull = false, h1Bear = false, h4Bull = false, h4Bear = false, dailyBull = false, dailyBear = false;
      if(g_haveH1) { int j = BsClosedIdx(g_h1, ArraySize(g_h1), t); if(j >= 0) { h1Bull = g_h1e20[j] > g_h1e50[j] && g_h1[j].close > g_h1e20[j]; h1Bear = g_h1e20[j] < g_h1e50[j] && g_h1[j].close < g_h1e20[j]; } }
      if(g_haveH4) { int j = BsClosedIdx(g_h4, ArraySize(g_h4), t); if(j >= 0) { h4Bull = g_h4e20[j] > g_h4e50[j] && g_h4[j].close > g_h4e20[j]; h4Bear = g_h4e20[j] < g_h4e50[j] && g_h4[j].close < g_h4e20[j]; } }
      if(g_haveD1) { int j = BsClosedIdx(g_d1, ArraySize(g_d1), t); if(j >= 0) { dailyBull = g_d1e20[j] > g_d1e50[j] && g_d1[j].close > g_d1e20[j]; dailyBear = g_d1e20[j] < g_d1e50[j] && g_d1[j].close < g_d1e20[j]; } }
      bool htfBullAgree = h4Bull, htfBearAgree = h4Bear;
      bool htfFullAgree = (dailyBull && h4Bull) || (dailyBear && h4Bear);
      int htfBullCount = (h1Bull ? 1 : 0) + (h4Bull ? 1 : 0) + (dailyBull ? 1 : 0);
      int htfBearCount = (h1Bear ? 1 : 0) + (h4Bear ? 1 : 0) + (dailyBear ? 1 : 0);

      // SECTION 7 - SWINGS, TREND & STRUCTURE
      double lastHighBefore = V.lastHigh, lastLowBefore = V.lastLow;
      double highSwing = EMPTY_VALUE, lowSwing = EMPTY_VALUE;
      double pv = 0.0;
      if(BsPivotHigh(i, length, pv)) highSwing = pv;
      if(BsPivotLow(i, length, pv)) lowSwing = pv;
      if(!NA(highSwing)) { V.prevHigh = V.lastHigh; V.lastHigh = highSwing; }
      if(!NA(lowSwing)) { V.prevLow = V.lastLow; V.lastLow = lowSwing; }
      if(!NA(highSwing) && !NA(V.prevHigh)) V.trend = (highSwing > V.prevHigh) ? "UP" : "DOWN";
      if(!NA(lowSwing) && !NA(V.prevLow)) V.trend = (lowSwing > V.prevLow) ? "UP" : "DOWN";
      bool isUpTrend = (V.trend == "UP"), isDownTrend = (V.trend == "DOWN");
      bool isHH = !NA(V.lastHigh) && !NA(V.prevHigh) && V.lastHigh > V.prevHigh;
      bool isHL = !NA(V.lastLow) && !NA(V.prevLow) && V.lastLow > V.prevLow;
      bool isLH = !NA(V.lastHigh) && !NA(V.prevHigh) && V.lastHigh < V.prevHigh;
      bool isLL = !NA(V.lastLow) && !NA(V.prevLow) && V.lastLow < V.prevLow;
      if(!NA(highSwing) && !NA(V.prevHigh)) { V.smHH = highSwing > V.prevHigh; V.smLH = highSwing < V.prevHigh; }
      if(!NA(lowSwing) && !NA(V.prevLow)) { V.smHL = lowSwing > V.prevLow; V.smLL = lowSwing < V.prevLow; }
      string structState = (V.smHH && V.smHL) ? "UP" : ((V.smLH && V.smLL) ? "DOWN" : "TRANSITION");
      if(!NA(highSwing)) V.rangeHigh = highSwing;
      if(!NA(lowSwing)) V.rangeLow = lowSwing;
      double rangeHigh = V.rangeHigh, rangeLow = V.rangeLow;
      double equilLevel = (!NA(rangeHigh) && !NA(rangeLow)) ? (rangeHigh + rangeLow) / 2.0 : EMPTY_VALUE;
      bool inPremium = !NA(equilLevel) && close > equilLevel, inDiscount = !NA(equilLevel) && close < equilLevel;
      string fibZoneTxt = inPremium ? "PREMIUM" : (inDiscount ? "DISCOUNT" : "EQ");
      double lastHigh = V.lastHigh, lastLow = V.lastLow, prevHigh = V.prevHigh, prevLow = V.prevLow;

      // SECTION 8 - PIVOT POINTS (yesterday's D1 bar)
      double pivotP = EMPTY_VALUE, pivotR1 = EMPTY_VALUE, pivotR2 = EMPTY_VALUE, pivotR3 = EMPTY_VALUE, pivotS1 = EMPTY_VALUE, pivotS2 = EMPTY_VALUE, pivotS3 = EMPTY_VALUE;
      string nearestPivotName = "PP"; double nearestPivotVal = EMPTY_VALUE; bool atPivot = false, abovePP = false;
      if(!NA(dHigh))
      {
         pivotP = (dHigh + dLow + dClose2) / 3.0;
         pivotR1 = 2 * pivotP - dLow; pivotR2 = pivotP + (dHigh - dLow); pivotR3 = dHigh + 2 * (pivotP - dLow);
         pivotS1 = 2 * pivotP - dHigh; pivotS2 = pivotP - (dHigh - dLow); pivotS3 = dLow - 2 * (dHigh - pivotP);
         double dPP = MathAbs(close - pivotP), dR1 = MathAbs(close - pivotR1), dR2 = MathAbs(close - pivotR2), dS1 = MathAbs(close - pivotS1), dS2 = MathAbs(close - pivotS2);
         nearestPivotName = (dPP <= dR1 && dPP <= dR2 && dPP <= dS1 && dPP <= dS2) ? "PP" : ((dR1 <= dR2 && dR1 <= dS1 && dR1 <= dS2) ? "R1" : ((dS1 <= dR2 && dS1 <= dS2) ? "S1" : ((dR2 <= dS2) ? "R2" : "S2")));
         nearestPivotVal = (nearestPivotName == "PP") ? pivotP : ((nearestPivotName == "R1") ? pivotR1 : ((nearestPivotName == "R2") ? pivotR2 : ((nearestPivotName == "S1") ? pivotS1 : pivotS2)));
         atPivot = MathAbs(close - nearestPivotVal) < atrValue * 0.3;
         abovePP = close > pivotP;
      }

      // SECTION 9 - CHoCH + BOS + S/R lines (CHoCH on a crossover of the CONFIRMED pivot against the trend)
      bool chochUp = !NA(lastHigh) && !NA(lastHighBefore) && close1 <= lastHighBefore && close > lastHigh && isDownTrend;
      bool chochDown = !NA(lastLow) && !NA(lastLowBefore) && close1 >= lastLowBefore && close < lastLow && isUpTrend;
      if(chochUp) { V.lastChoch = "UP"; V.lastChochBar = i; BsLabelUp(dr && InpShowAllLabels && InpShowCHoCH, BsBarT(i - 1), low1, "CHoCH " + g_uArrUp, cGreen, 8); }
      if(chochDown) { V.lastChoch = "DOWN"; V.lastChochBar = i; BsLabelDown(dr && InpShowAllLabels && InpShowCHoCH, BsBarT(i - 1), high1, "CHoCH " + g_uArrDn, cRed, 8); }
      bool chochRecent = V.lastChochBar >= 0 && (i - V.lastChochBar) <= 10;
      string chochTxt = chochRecent ? ((V.lastChoch == "UP") ? "UP " + g_uArrUp : "DOWN " + g_uArrDn) : "NONE";
      if(!NA(highSwing)) BsSeg(dr, BsBarT(i - length), highSwing, BsBarT(i + 60), highSwing, cRed, STYLE_DASH, 1);
      if(!NA(highSwing)) BsLabelUp(dr, BsBarT(i - length), highSwing, "R " + F2(highSwing), cRed, 7);
      if(!NA(lowSwing)) BsSeg(dr, BsBarT(i - length), lowSwing, BsBarT(i + 60), lowSwing, cGreen, STYLE_DASH, 1);
      if(!NA(lowSwing)) BsLabelDown(dr, BsBarT(i - length), lowSwing, "S " + F2(lowSwing), cGreen, 7);
      bool bosUp = InpShowBOS && InpShowAllLabels && !NA(prevHigh) && close > prevHigh && close1 <= prevHigh;
      bool bosDown = InpShowBOS && InpShowAllLabels && !NA(prevLow) && close < prevLow && close1 >= prevLow;
      if(bosUp) { BsLabelDown(dr, t, high, "BOS " + g_uArrUp, cGreen, 8); BsSeg(dr, BsBarT(i - 3), prevHigh, BsBarT(i + 5), prevHigh, cGreen, STYLE_DASH, 1); }
      if(bosDown) { BsLabelUp(dr, t, low, "BOS " + g_uArrDn, cRed, 8); BsSeg(dr, BsBarT(i - 3), prevLow, BsBarT(i + 5), prevLow, cRed, STYLE_DASH, 1); }

      // SECTION 10 - FVG (+ v18.5 mitigation)
      bool bullFVGraw = low > high2, bearFVGraw = high < low2;
      if(bullFVGraw) { V.lastBullFVGtop = low; V.lastBullFVGbot = high2; BsBox(dr && InpShowFVG, BsBarT(i - 2), low, t, high2, cFillTeal, cTeal); }
      if(bearFVGraw) { V.lastBearFVGtop = low2; V.lastBearFVGbot = high; BsBox(dr && InpShowFVG, BsBarT(i - 2), low2, t, high, cFillOrange, cOrange); }
      if(!NA(V.lastBullFVGbot) && close < V.lastBullFVGbot) { V.lastBullFVGtop = EMPTY_VALUE; V.lastBullFVGbot = EMPTY_VALUE; }
      if(!NA(V.lastBearFVGtop) && close > V.lastBearFVGtop) { V.lastBearFVGtop = EMPTY_VALUE; V.lastBearFVGbot = EMPTY_VALUE; }
      double lastBullFVGtop = V.lastBullFVGtop, lastBullFVGbot = V.lastBullFVGbot, lastBearFVGtop = V.lastBearFVGtop, lastBearFVGbot = V.lastBearFVGbot;
      bool bullFVGabove = !NA(lastBullFVGtop) && close > lastBullFVGtop;
      bool bullFVGinside = !NA(lastBullFVGtop) && close >= lastBullFVGbot && close <= lastBullFVGtop;
      bool bearFVGbelow = !NA(lastBearFVGbot) && close < lastBearFVGbot;
      bool bearFVGinside = !NA(lastBearFVGtop) && close >= lastBearFVGbot && close <= lastBearFVGtop;
      bool fvgPresent = bullFVGabove || bullFVGinside || bearFVGbelow || bearFVGinside;
      string fvgStatusTxt = bullFVGabove ? "ABOVE FVG" : (bullFVGinside ? "IN BULL FVG" : (bearFVGbelow ? "BELOW FVG" : (bearFVGinside ? "IN BEAR FVG" : "NO FVG")));

      // SECTION 11 - ORDER BLOCK + STRENGTH (detection unconditional; drawing obeys the toggle)
      double candleBodySMC = MathAbs(close - open), candleTotSMC = high - low + 0.000001;
      bool impulseUp = close > close1 && close1 > close2 && (close - close2) > atrValue * 1.2;
      bool impulseDown = close < close1 && close1 < close2 && (close2 - close) > atrValue * 1.2;
      bool strongImpUp = close > close1 && close1 > close2 && (close - close2) > atrValue * 1.8;
      bool strongImpDown = close < close1 && close1 < close2 && (close2 - close) > atrValue * 1.8;
      bool bullOB = impulseUp && open2 > close2, bearOB = impulseDown && open2 < close2;
      bool bullOBstrong = strongImpUp && open2 > close2, bearOBstrong = strongImpDown && open2 < close2;
      if(bullOB)
      {
         V.lastOBtype = bullOBstrong ? "STRONG BULL" : "BULL"; V.lastOBfresh = true; V.lastOBbar = i;
         V.ssBullOBhigh = MathMax(open2, close2); V.ssBullOBlow = MathMin(open2, close2);
         BsBox(dr && InpShowOB, BsBarT(i - 3), MathMax(open2, close2), BsBarT(i + 15), MathMin(open2, close2), cFillBlue, cBlue);
         BsLabelUp(dr && InpShowOB, BsBarT(i - 2), MathMin(open2, close2), bullOBstrong ? "OB" + g_uStar : "OB", cBlue, 7);
      }
      if(bearOB)
      {
         V.lastOBtype = bearOBstrong ? "STRONG BEAR" : "BEAR"; V.lastOBfresh = true; V.lastOBbar = i;
         V.ssBearOBhigh = MathMax(open2, close2); V.ssBearOBlow = MathMin(open2, close2);
         BsBox(dr && InpShowOB, BsBarT(i - 3), MathMax(open2, close2), BsBarT(i + 15), MathMin(open2, close2), cFillPurple, cPurple);
         BsLabelDown(dr && InpShowOB, BsBarT(i - 2), MathMax(open2, close2), bearOBstrong ? "OB" + g_uStar : "OB", cPurple, 7);
      }
      if(!NA(V.ssBullOBlow) && close < V.ssBullOBlow) { V.ssBullOBhigh = EMPTY_VALUE; V.ssBullOBlow = EMPTY_VALUE; }
      if(!NA(V.ssBearOBhigh) && close > V.ssBearOBhigh) { V.ssBearOBhigh = EMPTY_VALUE; V.ssBearOBlow = EMPTY_VALUE; }
      double ssBullOBhigh = V.ssBullOBhigh, ssBullOBlow = V.ssBullOBlow, ssBearOBhigh = V.ssBearOBhigh, ssBearOBlow = V.ssBearOBlow;
      string lastOBtype = V.lastOBtype;
      bool obMitigated = V.lastOBbar >= 0 && (i - V.lastOBbar) > 5;
      string obStatusTxt = (lastOBtype == "NONE") ? "NONE" : (obMitigated ? "MITIGATED" : "FRESH");

      // SECTION 12 - LIQUIDITY ZONES + SWEEP
      bool stopHuntBull = !NA(lastLow) && low < lastLow - g_pipZone && close > lastLow && (close - low) > (high - low) * 0.6 && (V.lastSHbullBar < 0 || i - V.lastSHbullBar > 3);
      bool stopHuntBear = !NA(lastHigh) && high > lastHigh + g_pipZone && close < lastHigh && (high - close) > (high - low) * 0.6 && (V.lastSHbearBar < 0 || i - V.lastSHbearBar > 3);
      if(stopHuntBull) { V.lastSHbullBar = i; V.lastSweepType = "BUY-SIDE SWEPT"; V.lastSweepBar = i; BsLabelUp(dr && InpShowAllLabels && InpShowStopHunt, t, low, "SH " + g_uArrUp + "\nLiq Sweep\nBuy-Side!", cLime, 8); }
      if(stopHuntBear) { V.lastSHbearBar = i; V.lastSweepType = "SELL-SIDE SWEPT"; V.lastSweepBar = i; BsLabelDown(dr && InpShowAllLabels && InpShowStopHunt, t, high, "SH " + g_uArrDn + "\nLiq Sweep\nSell-Side!", cRed, 8); }
      bool equalHighs = !NA(prevHigh) && !NA(lastHigh) && MathAbs(lastHigh - prevHigh) <= g_pipZone * 2;
      bool equalLows = !NA(prevLow) && !NA(lastLow) && MathAbs(lastLow - prevLow) <= g_pipZone * 2;
      bool sweepRecent = V.lastSweepBar >= 0 && (i - V.lastSweepBar) <= 5;
      string lastSweepType = V.lastSweepType;
      string sweepTxt = sweepRecent ? lastSweepType : (equalHighs ? "POOL ABOVE" : (equalLows ? "POOL BELOW" : "NONE"));
      bool fakeBOdown = !NA(rangeHigh) && high > rangeHigh && close < rangeHigh && open < rangeHigh && (high - close) > atrValue * 0.4 && (V.lastFBdownBar < 0 || i - V.lastFBdownBar > 3);
      bool fakeBOup = !NA(rangeLow) && low < rangeLow && close > rangeLow && open > rangeLow && (close - low) > atrValue * 0.4 && (V.lastFBupBar < 0 || i - V.lastFBupBar > 3);
      if(fakeBOdown) { V.lastFBdownBar = i; BsLabelDown(dr && InpShowAllLabels && InpShowFakeBO, t, high, "FB " + g_uArrDn + "\nFake BO\nBear trap!", cOrange, 8); }
      if(fakeBOup) { V.lastFBupBar = i; BsLabelUp(dr && InpShowAllLabels && InpShowFakeBO, t, low, "FB " + g_uArrUp + "\nFake BO\nBull trap!", cOrange, 8); }
      bool realMoveUp = !NA(rangeHigh) && close > rangeHigh + g_pipZone && close > open && candleBodySMC > candleTotSMC * 0.55 && volOk && (V.lastRMupBar < 0 || i - V.lastRMupBar > 3);
      bool realMoveDown = !NA(rangeLow) && close < rangeLow - g_pipZone && close < open && candleBodySMC > candleTotSMC * 0.55 && volOk && (V.lastRMdownBar < 0 || i - V.lastRMdownBar > 3);
      if(realMoveUp) { V.lastRMupBar = i; BsLabelUp(dr && InpShowAllLabels && InpShowRealMove, t, low, "RM " + g_uArrUp + "\nReal Move\nRide it!", cTeal, 8); }
      if(realMoveDown) { V.lastRMdownBar = i; BsLabelDown(dr && InpShowAllLabels && InpShowRealMove, t, high, "RM " + g_uArrDn + "\nReal Move\nRide it!", cTeal, 8); }

      // SECTION 13 - CANDLESTICK PATTERNS
      double bodySize = MathAbs(close - open), candleRange = high - low + 0.000001;
      double lowerWick = MathMin(close, open) - low, upperWick = high - MathMax(close, open);
      bool bullEngulf = close1 < open1 && close > open && close > open1 && open < close1 && (close - open) > (open1 - close1) * 0.8;
      bool bearEngulf = close1 > open1 && close < open && close < open1 && open > close1 && (open - close) > (close1 - open1) * 0.8;
      bool pinBarBull = lowerWick > bodySize * 2 && lowerWick > upperWick * 2 && candleRange > 0;
      bool pinBarBear = upperWick > bodySize * 2 && upperWick > lowerWick * 2 && candleRange > 0;
      bool isDoji = MathAbs(close - open) <= candleRange * 0.1 && candleRange > 0;
      bool isHammer = pinBarBull && close > open, isShootStar = pinBarBear && close < open;
      bool insideBar = high < high1 && low > low1;
      bool maruBozu = bodySize > candleRange * 0.9, bullMaru = maruBozu && close > open, bearMaru = maruBozu && close < open;
      string currentPatternTxt = bullEngulf ? "BULL ENGULF" : (bearEngulf ? "BEAR ENGULF" : (isHammer ? "HAMMER" : (isShootStar ? "SHOOT STAR" : (isDoji ? "DOJI" : (bullMaru ? "BULL MARUBZ" : (bearMaru ? "BEAR MARUBZ" : (insideBar ? "INSIDE BAR" : "NO PATTERN")))))));
      bool candlePatternOk = bullEngulf || pinBarBull || isHammer || bullMaru;
      bool candlePatternOkBear = bearEngulf || pinBarBear || isShootStar || bearMaru;
      bool patDraw = dr && InpShowAllLabels && InpShowCandlePat;
      if(bullEngulf && patDraw && (isUpTrend || (!NA(rangeLow) && close <= rangeLow + g_pipZone * 5))) BsLabelUp(true, t, low, "E" + g_uArrUp, cTeal, 8);
      if(bearEngulf && patDraw && (isDownTrend || (!NA(rangeHigh) && close >= rangeHigh - g_pipZone * 5))) BsLabelDown(true, t, high, "E" + g_uArrDn, cMaroon, 8);
      if(pinBarBull && patDraw && (isUpTrend || (!NA(rangeLow) && close <= rangeLow + g_pipZone * 5))) BsLabelUp(true, t, low, "P" + g_uArrUp, cBlue, 8);
      if(pinBarBear && patDraw && (isDownTrend || (!NA(rangeHigh) && close >= rangeHigh - g_pipZone * 5))) BsLabelDown(true, t, high, "P" + g_uArrDn, cPurple, 8);
      if(isDoji && patDraw) BsLabelDown(true, t, high, "D", cGray, 7);

      // SECTION 14 - INDUCEMENT v2
      bool bearRejection = bearEngulf || (upperWick > bodySize * 1.8 && upperWick > lowerWick * 2.0);
      bool bullRejection = bullEngulf || (lowerWick > bodySize * 1.8 && lowerWick > upperWick * 2.0);
      bool liqSweepBear = !NA(prevHigh) && high > prevHigh + g_pipZone && close < prevHigh;
      bool liqSweepBull = !NA(prevLow) && low < prevLow - g_pipZone && close > prevLow;
      bool bearInducement = inPremium && (liqSweepBear || equalHighs) && bearRejection && (V.lastBearIndBar < 0 || i - V.lastBearIndBar > length);
      bool bullInducement = inDiscount && (liqSweepBull || equalLows) && bullRejection && (V.lastBullIndBar < 0 || i - V.lastBullIndBar > length);
      if(bearInducement) { V.lastBearIndBar = i; BsLabelDown(dr && InpShowInducement && InpShowAllLabels, t, high, g_uWarn + " BEAR INDUCEMENT\nTrap -> DROP\nPremium | Equal Highs Swept\nWatch for BOS " + g_uArrDn, cRed, 8); }
      if(bullInducement) { V.lastBullIndBar = i; BsLabelUp(dr && InpShowInducement && InpShowAllLabels, t, low, g_uWarn + " BULL INDUCEMENT\nTrap -> RALLY\nDiscount | Equal Lows Swept\nWatch for BOS " + g_uArrUp, cGreen, 8); }
      string inducementTxt = bearInducement ? "BEARISH" : (bullInducement ? "BULLISH" : "NONE");

      // SECTION 15 - SCALP SIGNALS
      bool nearSupport = !NA(rangeLow) && close <= rangeLow + (atrValue * 0.3);
      bool nearResistance = !NA(rangeHigh) && close >= rangeHigh - (atrValue * 0.3);
      bool scalpTickBull = close > open && close1 < open1 && close > open1 && candleBodySMC < atrValue * 0.6 && rsiValue >= 35 && rsiValue <= 65 && (h4Bull || isUpTrend) && (nearSupport || bullFVGinside) && !adxTrendWeak && volOk;
      bool scalpTickBear = close < open && close1 > open1 && close < open1 && candleBodySMC < atrValue * 0.6 && rsiValue >= 35 && rsiValue <= 65 && (h4Bear || isDownTrend) && (nearResistance || bearFVGinside) && !adxTrendWeak && volOk;
      double scalpSL = atrValue * 1.0, scalpTP1 = atrValue * 1.0, scalpTP2 = atrValue * 2.0, scalpTP3 = atrValue * 3.0;
      if(InpShowScalp && InpShowAllLabels && scalpTickBull && tradeAllowed)
         BsLabelUp(dr, t, low, "SC " + g_uArrUp + " SCALP BUY\nE:   " + F2(close) + "\nSL:  " + F2(close - scalpSL) + "\nTP1: " + F2(close + scalpTP1) + "\nTP2: " + F2(close + scalpTP2) + "\nTP3: " + F2(close + scalpTP3), cGreen, 7);
      if(InpShowScalp && InpShowAllLabels && scalpTickBear && tradeAllowed)
         BsLabelDown(dr, t, high, "SC " + g_uArrDn + " SCALP SELL\nE:   " + F2(close) + "\nSL:  " + F2(close + scalpSL) + "\nTP1: " + F2(close - scalpTP1) + "\nTP2: " + F2(close - scalpTP2) + "\nTP3: " + F2(close - scalpTP3), cMaroon, 7);

      // SECTION 16 - CONFLUENCE SCORE 0-10
      int sessScorePt = (inLondon || inNewYork || (InpFcAsiaScore && inAsia)) ? 1 : 0;
      int scoreBuy = (isUpTrend ? 1 : 0) + ((htfBullCount >= 2) ? 2 : ((htfBullCount == 1) ? 1 : 0)) + (bullInducement ? 2 : 0) + ((BsHas(lastOBtype, "BULL") && !NA(ssBullOBlow)) ? 1 : 0) + ((fvgPresent && bullFVGabove) ? 1 : 0) + ((rsiValue > 50 && rsiBull) ? 1 : 0) + sessScorePt + (inDiscount ? 1 : 0) + (candlePatternOk ? 1 : 0);
      int scoreSell = (isDownTrend ? 1 : 0) + ((htfBearCount >= 2) ? 2 : ((htfBearCount == 1) ? 1 : 0)) + (bearInducement ? 2 : 0) + ((BsHas(lastOBtype, "BEAR") && !NA(ssBearOBhigh)) ? 1 : 0) + ((fvgPresent && bearFVGbelow) ? 1 : 0) + ((rsiValue < 50 && rsiBear) ? 1 : 0) + sessScorePt + (inPremium ? 1 : 0) + (candlePatternOkBear ? 1 : 0);
      if(scoreBuy > 10) scoreBuy = 10;
      if(scoreSell > 10) scoreSell = 10;
      int minFactorsBuy = (isUpTrend ? 1 : 0) + (htfBullAgree ? 1 : 0) + (rsiBull ? 1 : 0) + (volOk ? 1 : 0) + (inDiscount ? 1 : 0);
      int minFactorsSell = (isDownTrend ? 1 : 0) + (htfBearAgree ? 1 : 0) + (rsiBear ? 1 : 0) + (volOk ? 1 : 0) + (inPremium ? 1 : 0);
      bool minRuleBuy = minFactorsBuy >= 3, minRuleSell = minFactorsSell >= 3;

      // SECTION 16B - LOCATION GATE
      double lgZoneTol = atrValue * InpLgZoneAtr * aeZoneMul;
      double lgEma20 = ma20;
      bool trendDayOK = adxTrendStrong && ((isUpTrend && h1Bull && h4Bull) || (isDownTrend && h1Bear && h4Bear));
      bool sellZnTrend = InpLgMarketMode != MM_RANGE && isDownTrend && (InpLgMarketMode == MM_TREND || (adxTrendStrong && h1Bear && h4Bear)) && BsZnUp(lgEma20, high, close, lgZoneTol);
      bool buyZnTrend = InpLgMarketMode != MM_RANGE && isUpTrend && (InpLgMarketMode == MM_TREND || (adxTrendStrong && h1Bull && h4Bull)) && BsZnDn(lgEma20, low, close, lgZoneTol);
      bool sellZnFVG = !NA(lastBearFVGbot) && high >= lastBearFVGbot - lgZoneTol && close <= lastBearFVGtop + lgZoneTol;
      bool sellZnOB = !NA(ssBearOBlow) && high >= ssBearOBlow - lgZoneTol && close <= ssBearOBhigh + lgZoneTol;
      bool sellZnSwing = BsZnUp(lastHigh, high, close, lgZoneTol) || BsZnUp(prevHigh, high, close, lgZoneTol);
      bool sellZnPivot = BsZnUp(pivotP, high, close, lgZoneTol) || BsZnUp(pivotR1, high, close, lgZoneTol) || BsZnUp(pivotR2, high, close, lgZoneTol);
      bool sellZnOther = BsZnUp(pdHigh, high, close, lgZoneTol) || BsZnUp(rangeHigh, high, close, lgZoneTol) || (BsZnUp(equilLevel, high, close, lgZoneTol) && isDownTrend);
      bool sellSweepLG = sweepRecent && lastSweepType == "BUY-SIDE SWEPT";
      bool sellZoneNear = sellZnFVG || sellZnOB || sellZnSwing || sellZnPivot || sellZnOther || sellSweepLG || sellZnTrend;
      string sellZoneTxt = sellZnFVG ? "FVG" : (sellZnOB ? "OB" : (sellZnSwing ? "SWING-H" : (sellZnPivot ? "PIVOT" : (sellSweepLG ? "SWEEP" : (sellZnTrend ? "TREND-PB" : (sellZnOther ? "LEVEL" : g_uDash))))));
      bool buyZnFVG = !NA(lastBullFVGbot) && low <= lastBullFVGtop + lgZoneTol && close >= lastBullFVGbot - lgZoneTol;
      bool buyZnOB = !NA(ssBullOBlow) && low <= ssBullOBhigh + lgZoneTol && close >= ssBullOBlow - lgZoneTol;
      bool buyZnSwing = BsZnDn(lastLow, low, close, lgZoneTol) || BsZnDn(prevLow, low, close, lgZoneTol);
      bool buyZnPivot = BsZnDn(pivotP, low, close, lgZoneTol) || BsZnDn(pivotS1, low, close, lgZoneTol) || BsZnDn(pivotS2, low, close, lgZoneTol);
      bool buyZnOther = BsZnDn(pdLow, low, close, lgZoneTol) || BsZnDn(rangeLow, low, close, lgZoneTol) || (BsZnDn(equilLevel, low, close, lgZoneTol) && isUpTrend);
      bool buySweepLG = sweepRecent && lastSweepType == "SELL-SIDE SWEPT";
      bool buyZoneNear = buyZnFVG || buyZnOB || buyZnSwing || buyZnPivot || buyZnOther || buySweepLG || buyZnTrend;
      string buyZoneTxt = buyZnFVG ? "FVG" : (buyZnOB ? "OB" : (buyZnSwing ? "SWING-L" : (buyZnPivot ? "PIVOT" : (buySweepLG ? "SWEEP" : (buyZnTrend ? "TREND-PB" : (buyZnOther ? "LEVEL" : g_uDash))))));
      if(sellZoneNear) { V.sellTouchAgeBar = i; V.sellZoneMem = sellZoneTxt; V.sellZonePx = close; }
      if(buyZoneNear) { V.buyTouchAgeBar = i; V.buyZoneMem = buyZoneTxt; V.buyZonePx = close; }
      bool sellZoneOK = V.sellTouchAgeBar >= 0 && (i - V.sellTouchAgeBar) <= InpLgFreshBars;
      bool buyZoneOK = V.buyTouchAgeBar >= 0 && (i - V.buyTouchAgeBar) <= InpLgFreshBars;
      double buyDistZ = (!NA(V.buyZonePx) && atrValue > 0) ? MathAbs(close - V.buyZonePx) / atrValue : 0.0;
      double sellDistZ = (!NA(V.sellZonePx) && atrValue > 0) ? MathAbs(close - V.sellZonePx) / atrValue : 0.0;
      double lgPbLo = BsLowest(g_l, i, InpLgPbLookback), lgPbHi = BsHighest(g_h, i, InpLgPbLookback);
      bool sellChaseOK = sellZnTrend || InpLgChaseAtr <= 0.0 || (close - lgPbLo) >= atrValue * InpLgChaseAtr * aeChaseMul;
      bool buyChaseOK = buyZnTrend || InpLgChaseAtr <= 0.0 || (lgPbHi - close) >= atrValue * InpLgChaseAtr * aeChaseMul;
      double lgBarRange = MathMax(high - low, g_tick);
      bool sellRejectC = close < open && (high - MathMax(open, close)) >= lgBarRange * InpLgWickPct && sellZoneNear;
      bool buyRejectC = close > open && (MathMin(open, close) - low) >= lgBarRange * InpLgWickPct && buyZoneNear;
      bool sellConfirmC = (sellRej1 && close < low1) || (sellRej2 && close < low2);
      bool buyConfirmC = (buyRej1 && close > high1) || (buyRej2 && close > high2);
      bool sellTrigOK = (InpLgEntryMode == EM_TOUCH) ? true : ((InpLgEntryMode == EM_REJECT) ? sellRejectC : sellConfirmC);
      bool buyTrigOK = (InpLgEntryMode == EM_TOUCH) ? true : ((InpLgEntryMode == EM_REJECT) ? buyRejectC : buyConfirmC);
      bool lgBuyCooldownOK = InpLgCooldownBars <= 0 || (i - V.lgLastBuyFireBar) >= InpLgCooldownBars;
      bool lgSellCooldownOK = InpLgCooldownBars <= 0 || (i - V.lgLastSellFireBar) >= InpLgCooldownBars;
      bool locBuyOK = !InpUseLocationGate || (buyZoneOK && buyChaseOK && buyTrigOK);
      bool locSellOK = !InpUseLocationGate || (sellZoneOK && sellChaseOK && sellTrigOK);
      string locBuyTxt = !InpUseLocationGate ? "OFF" : (locBuyOK ? "PASS @ " + V.buyZoneMem : (!buyZoneOK ? "WAIT RETEST" : (!buyChaseOK ? "CHASING" : "WAIT CONFIRM")));
      string locSellTxt = !InpUseLocationGate ? "OFF" : (locSellOK ? "PASS @ " + V.sellZoneMem : (!sellZoneOK ? "WAIT RETEST" : (!sellChaseOK ? "CHASING" : "WAIT CONFIRM")));

      // SECTION 19 (part) - SESSION HIGH / LOW TRACKING (recording freezes at the next open)
      bool recAsia = inAsia && !inLondon, recLon = inLondon && !inNewYork;
      V.asiaH = (recAsia && !V.prvAsia) ? high : (recAsia ? MathMax(NZ(V.asiaH, high), high) : V.asiaH);
      V.asiaL = (recAsia && !V.prvAsia) ? low : (recAsia ? MathMin(NZ(V.asiaL, low), low) : V.asiaL);
      V.lonH = (recLon && !V.prvLon) ? high : (recLon ? MathMax(NZ(V.lonH, high), high) : V.lonH);
      V.lonL = (recLon && !V.prvLon) ? low : (recLon ? MathMin(NZ(V.lonL, low), low) : V.lonL);
      V.nyH = (inNewYork && !V.prvNY) ? high : (inNewYork ? MathMax(NZ(V.nyH, high), high) : V.nyH);
      V.nyL = (inNewYork && !V.prvNY) ? low : (inNewYork ? MathMin(NZ(V.nyL, low), low) : V.nyL);
      bool prvLonBefore = V.prvLon;
      V.prvAsia = recAsia; V.prvLon = recLon; V.prvNY = inNewYork;
      double asiaH = V.asiaH, asiaL = V.asiaL, lonH = V.lonH, lonL = V.lonL, nyH = V.nyH, nyL = V.nyL;
      double nyCloseY = dClose2;
      // oil spike (confirmed hourly closes)
      bool oilSpike = false;
      if(g_haveOil)
      {
         int j = BsClosedIdx(g_oilH, ArraySize(g_oilH), t);
         if(j >= 1 && g_oilH[j - 1].close > 0)
            oilSpike = ((g_oilH[j].close - g_oilH[j - 1].close) / g_oilH[j - 1].close) * 100.0 > 2.0;
      }
      bool atrExpand = atrAvg > 0 && atrValue > atrAvg * 1.2;
      double sessHi = inLondon ? lonH : (inNewYork ? nyH : asiaH);
      double sessLo = inLondon ? lonL : (inNewYork ? nyL : asiaL);
      double sessRng = (!NA(sessHi) && !NA(sessLo)) ? sessHi - sessLo : EMPTY_VALUE;
      bool sessPctOk = !NA(sessRng) && sessRng > 0;
      double sessPct = sessPctOk ? MathRound(((close - sessLo) / sessRng) * 100.0) : EMPTY_VALUE;

      // PENDING LEVEL SOURCE (v18.4g) + crossed-anchor guard (v18.8 A4) + broken range (A2)
      double pendHiGate = sellZoneNear ? ((!NA(ssBearOBhigh) && sellZnOB) ? ssBearOBhigh : ((!NA(lastBearFVGtop) && sellZnFVG) ? lastBearFVGtop : (!NA(lastHigh) ? lastHigh : EMPTY_VALUE))) : EMPTY_VALUE;
      double pendLoGate = buyZoneNear ? ((!NA(ssBullOBlow) && buyZnOB) ? ssBullOBlow : ((!NA(lastBullFVGbot) && buyZnFVG) ? lastBullFVGbot : (!NA(lastLow) ? lastLow : EMPTY_VALUE))) : EMPTY_VALUE;
      double pendHiSess = inLondon ? asiaH : (inNewYork ? lonH : (!NA(nyH) ? nyH : pdHigh));
      double pendLoSess = inLondon ? asiaL : (inNewYork ? lonL : (!NA(nyL) ? nyL : pdLow));
      double pendHiSrc = (InpPendSrcMode == PS_SESSION) ? pendHiSess : ((InpPendSrcMode == PS_GATE) ? pendHiGate : (!NA(pendHiGate) ? pendHiGate : pendHiSess));
      double pendLoSrc = (InpPendSrcMode == PS_SESSION) ? pendLoSess : ((InpPendSrcMode == PS_GATE) ? pendLoGate : (!NA(pendLoGate) ? pendLoGate : pendLoSess));
      double pendHiRaw = pendHiSrc, pendLoRaw = pendLoSrc;
      double pendRngA = (!NA(pendHiSrc) && !NA(pendLoSrc) && atrValue > 0) ? (pendHiSrc - pendLoSrc) / atrValue : EMPTY_VALUE;
      bool pendInvalid = !NA(pendRngA) && pendRngA < 1.0;
      if(pendInvalid) { pendHiSrc = EMPTY_VALUE; pendLoSrc = EMPTY_VALUE; }
      bool pendBrokeUp = FEATURE_RANGE_BROKEN && !NA(pendHiSrc) && close > pendHiSrc;
      bool pendBrokeDn = FEATURE_RANGE_BROKEN && !NA(pendLoSrc) && close < pendLoSrc;

      // SECTION 7c - NY TRAP PROTOCOL
      bool isMetalsOrFX = (g_market == "Gold" || g_market == "Silver" || g_market == "Forex EURUSD" || g_market == "Forex USDJPY" || g_market == "DXY");
      bool isIndex = (g_market == "US30 Dow" || g_market == "NAS100");
      bool isCrypto = (g_market == "BTC" || g_market == "ETH" || g_market == "XRP");
      string nyRegime = (inAnyNYKz && isMetalsOrFX) ? "TRAP" : ((inAnyNYKz && isIndex) ? "TREND" : ((inAnyNYKz && isCrypto) ? "TRAP" : "NEUTRAL"));
      double barRange = high - low, barRangeAvg20 = g_rngAvg20[i];
      bool isBigCandle = barRangeAvg20 > 0 && barRange >= barRangeAvg20 * InpTrapVolMult;
      if(!inLondon && prvLonBefore)
         V.lonRngLast = NZ(lonH, high) - NZ(lonL, low);
      // ta.sma(lonRngLast, 5): the last five BARS' values of that var (na while it has none)
      V.lonRngHist[V.lonRngN % 5] = V.lonRngLast; V.lonRngN++;
      double lonRngAvg5 = EMPTY_VALUE;
      if(V.lonRngN >= 5 && !NA(V.lonRngLast))
      {
         double s5 = 0.0; bool anyNa = false;
         for(int k = 0; k < 5; k++) { if(NA(V.lonRngHist[k])) anyNa = true; else s5 += V.lonRngHist[k]; }
         if(!anyNa) lonRngAvg5 = s5 / 5.0;
      }
      bool lonWasTight = !NA(V.lonRngLast) && !NA(lonRngAvg5) && lonRngAvg5 > 0 && V.lonRngLast < lonRngAvg5 * 0.8;
      bool brokeAbove = !NA(lonH) && high > lonH, brokeBelow = !NA(lonL) && low < lonL;
      bool trapFiredUp = inAnyNYKz && nyRegime == "TRAP" && isBigCandle && lonWasTight && brokeAbove;
      bool trapFiredDown = inAnyNYKz && nyRegime == "TRAP" && isBigCandle && lonWasTight && brokeBelow;
      string trapBias = trapFiredUp ? "BEARISH-REV" : (trapFiredDown ? "BULLISH-REV" : g_uDash);
      string trapDetail = trapFiredUp ? "London H swept on big candle - expect reversal" : (trapFiredDown ? "London L swept on big candle - expect reversal" : ((inAnyNYKz && nyRegime == "TRAP") ? (lonWasTight ? "Watching London range for sweep" : "London not tight - trap pattern unlikely") : g_uDash));
      double atrPadRaw = (inAnyNYKz && InpAtrPadMultNY > 0) ? atrValue * InpAtrPadMultNY : 0.0;
      double atrPad = MathMin(atrPadRaw, InpAtrPadCapPips * g_pipZone);
      bool atrPadActive = atrPad > 0;
      double pendHiPadded = !NA(pendHiSrc) ? pendHiSrc + atrPad : EMPTY_VALUE;
      double pendLoPadded = !NA(pendLoSrc) ? pendLoSrc - atrPad : EMPTY_VALUE;
      string tgtSource = (inLondon && !NA(asiaH) && !NA(asiaL)) ? "Asia (FRESH)" : ((inNewYork && !NA(lonH) && !NA(lonL)) ? "London (FRESH)" : ((!NA(nyH) && !NA(nyL)) ? "NY yest (STALE)" : "PDH/PDL (STALE)"));
      bool tgtSourceFresh = (inLondon && !NA(asiaH) && !NA(asiaL)) || (inNewYork && !NA(lonH) && !NA(lonL));
      bool pendHiFromGate = InpPendSrcMode != PS_SESSION && !NA(pendHiGate);
      bool pendLoFromGate = InpPendSrcMode != PS_SESSION && !NA(pendLoGate);
      string pendHiSrcTxt = NA(pendHiSrc) ? g_uDoubleDash : (pendHiFromGate ? (sellZnOB ? "OB" : (sellZnFVG ? "FVG" : "SWING-H")) : tgtSource);
      string pendLoSrcTxt = NA(pendLoSrc) ? g_uDoubleDash : (pendLoFromGate ? (buyZnOB ? "OB" : (buyZnFVG ? "FVG" : "SWING-L")) : tgtSource);
      double pendRange = (!NA(pendHiSrc) && !NA(pendLoSrc)) ? pendHiSrc - pendLoSrc : EMPTY_VALUE;
      double tightThreshold = InpTightAutoPerSym ? BsTightAutoThr(g_market) : InpTightManualPts;
      bool rangeTooTight = InpUseTightFilter && !NA(pendRange) && pendRange < tightThreshold;
      string rangeTightTxt = !NA(pendRange) ? F4(pendRange) + (rangeTooTight ? " < " : " >= ") + F4(tightThreshold) : "no range yet";
      bool hideEntries = rangeTooTight && InpTightAction == TA_HIDE;
      bool redWarn = rangeTooTight && InpTightAction == TA_RED;
      // pending order math (session-anchored levels, fill buffers)
      double pendHiEntrySrc = atrPadActive ? pendHiPadded : pendHiSrc, pendLoEntrySrc = atrPadActive ? pendLoPadded : pendLoSrc;
      double pendSellE = !NA(pendHiEntrySrc) ? pendHiEntrySrc - g_pipZone : EMPTY_VALUE;
      double pendSellSL = !NA(pendHiSrc) ? pendHiSrc + atrSL : EMPTY_VALUE;
      double pendSellTP1 = (!NA(pendHiSrc) && !NA(pendLoSrc)) ? pendHiSrc - (pendHiSrc - pendLoSrc) * 0.5 : EMPTY_VALUE;
      double pendSellTP2 = !NA(pendLoSrc) ? pendLoSrc : EMPTY_VALUE;
      double pendSellTP3 = (!NA(pendHiSrc) && !NA(pendLoSrc)) ? pendLoSrc - (pendHiSrc - pendLoSrc) * 0.3 : EMPTY_VALUE;
      double pendBuyE = !NA(pendLoEntrySrc) ? pendLoEntrySrc + g_pipZone : EMPTY_VALUE;
      double pendBuySL = !NA(pendLoSrc) ? pendLoSrc - atrSL : EMPTY_VALUE;
      double pendBuyTP1 = (!NA(pendHiSrc) && !NA(pendLoSrc)) ? pendLoSrc + (pendHiSrc - pendLoSrc) * 0.5 : EMPTY_VALUE;
      double pendBuyTP2 = !NA(pendHiSrc) ? pendHiSrc : EMPTY_VALUE;
      double pendBuyTP3 = (!NA(pendHiSrc) && !NA(pendLoSrc)) ? pendHiSrc + (pendHiSrc - pendLoSrc) * 0.3 : EMPTY_VALUE;
      double pendTPbuf = InpUseFillBuffer ? atrValue * InpTpBufAtr : 0.0, pendSLbuf = InpUseFillBuffer ? atrValue * InpSlBufAtr : 0.0;
      if(!NA(pendSellTP1)) pendSellTP1 += pendTPbuf;
      if(!NA(pendSellTP2)) pendSellTP2 += pendTPbuf;
      if(!NA(pendSellSL)) pendSellSL += pendSLbuf;
      if(!NA(pendBuyTP1)) pendBuyTP1 -= pendTPbuf;
      if(!NA(pendBuyTP2)) pendBuyTP2 -= pendTPbuf;
      if(!NA(pendBuySL)) pendBuySL -= pendSLbuf;
      double pendRiskS = (!NA(pendSellE) && !NA(pendSellSL)) ? MathAbs(pendSellE - pendSellSL) : EMPTY_VALUE;
      double pendRiskB = (!NA(pendBuyE) && !NA(pendBuySL)) ? MathAbs(pendBuyE - pendBuySL) : EMPTY_VALUE;
      double pendLotsS = (!NA(pendRiskS) && pendRiskS > 0.001) ? BsLots(pendRiskS) : EMPTY_VALUE;
      double pendLotsB = (!NA(pendRiskB) && pendRiskB > 0.001) ? BsLots(pendRiskB) : EMPTY_VALUE;
      double distSell = !NA(pendSellE) ? RoundTo(MathAbs(close - pendSellE), 2) : EMPTY_VALUE;
      double distBuy = !NA(pendBuyE) ? RoundTo(MathAbs(close - pendBuyE), 2) : EMPTY_VALUE;
      double pendRRS = (!NA(pendSellTP2) && !NA(pendSellE) && !NA(pendSellSL) && MathAbs(pendSellE - pendSellSL) > 0.001) ? RoundTo(MathAbs(pendSellTP2 - pendSellE) / MathAbs(pendSellE - pendSellSL), 1) : EMPTY_VALUE;
      double pendRRB = (!NA(pendBuyTP2) && !NA(pendBuyE) && !NA(pendBuySL) && MathAbs(pendBuyE - pendBuySL) > 0.001) ? RoundTo(MathAbs(pendBuyTP2 - pendBuyE) / MathAbs(pendBuyE - pendBuySL), 1) : EMPTY_VALUE;
      bool pendSellAtMkt = !NA(pendSellE) && close >= pendSellE, pendBuyAtMkt = !NA(pendBuyE) && close <= pendBuyE;
      double buyStopE = !NA(pendHiRaw) ? pendHiRaw + g_pipZone : EMPTY_VALUE, sellStopE = !NA(pendLoRaw) ? pendLoRaw - g_pipZone : EMPTY_VALUE;

      // v18.7 B1 - PULLBACK TRIGGER (freeze-on-arm, death paths, hourly damper)
      double pbSwLo = BsLowest(g_l, i, 24), pbSwHi = BsHighest(g_h, i, 24);
      double orgLow = V.orgLow, orgHigh = V.orgHigh;
      double pbLvlBr = MathMax(MathMax(BsPbBelow(pbSwLo, close), BsPbBelow(pdLow, close)), MathMax(BsPbBelow(pivotS1, close), BsPbBelow(orgLow, close)));
      double pbLvlSr = MathMin(MathMin(BsPbAbove(pbSwHi, close), BsPbAbove(pdHigh, close)), MathMin(BsPbAbove(pivotR1, close), BsPbAbove(orgHigh, close)));
      double pbLvlB = (pbLvlBr < -1.0e11) ? EMPTY_VALUE : pbLvlBr, pbLvlS = (pbLvlSr > 1.0e11) ? EMPTY_VALUE : pbLvlSr;
      double pbTpM = inAsia ? 1.0 : 1.8;
      if(i > 0 && (h1Bull != h1BullPrev || h1Bear != h1BearPrev)) V.h1FlipBar = i;
      h1BullPrev = h1Bull; h1BearPrev = h1Bear;
      int trendAge = (V.h1FlipBar < 0) ? 0 : i - V.h1FlipBar;
      long hrK = (long)t / 3600;
      if(V.pbHrKey < 0 || hrK != V.pbHrKey) { V.pbHrKey = hrK; V.pbFiresHr = 0; }
      if(NA(V.pbBuyE) && h1Bull && isUpTrend && !NA(pbLvlB) && (close - (pbLvlB + InpPbFront * atrValue)) >= InpPbRoomAtr * atrValue)
      {
         V.pbBuyE = pbLvlB + InpPbFront * atrValue; V.pbBuySL = pbLvlB - InpPbSlAtr * atrValue;
         V.pbBuyT1 = V.pbBuyE + pbTpM * atrValue; V.pbBuyT2 = V.pbBuyE + pbTpM * 1.8 * atrValue;
         V.pbBuyArmBar = i; V.pbBuyDeath = "";
         V.pbBuySrc = (pbLvlB == pbSwLo) ? "SWING24" : ((pbLvlB == pdLow) ? "PDL" : ((pbLvlB == pivotS1) ? "S1" : "ORG"));
      }
      if(!(h1Bull && isUpTrend) && !NA(V.pbBuyE)) { V.pbBuyE = EMPTY_VALUE; V.pbBuyDeath = "TREND FLIP"; }
      if(!NA(V.pbBuyE) && V.pbBuyArmBar >= 0 && i - V.pbBuyArmBar > InpPbExpiry) { V.pbBuyE = EMPTY_VALUE; V.pbBuyDeath = "EXPIRED " + FI(InpPbExpiry) + "b"; }
      if(!NA(V.pbBuyE) && close < V.pbBuyE - InpPbTapMax * atrValue) { V.pbBuyE = EMPTY_VALUE; V.pbBuyDeath = "GAPPED THRU"; }
      if(NA(V.pbSellE) && h1Bear && isDownTrend && !NA(pbLvlS) && ((pbLvlS - InpPbFront * atrValue) - close) >= InpPbRoomAtr * atrValue)
      {
         V.pbSellE = pbLvlS - InpPbFront * atrValue; V.pbSellSL = pbLvlS + InpPbSlAtr * atrValue;
         V.pbSellT1 = V.pbSellE - pbTpM * atrValue; V.pbSellT2 = V.pbSellE - pbTpM * 1.8 * atrValue;
         V.pbSellArmBar = i; V.pbSellDeath = "";
         V.pbSellSrc = (pbLvlS == pbSwHi) ? "SWING24" : ((pbLvlS == pdHigh) ? "PDH" : ((pbLvlS == pivotR1) ? "R1" : "ORG"));
      }
      if(!(h1Bear && isDownTrend) && !NA(V.pbSellE)) { V.pbSellE = EMPTY_VALUE; V.pbSellDeath = "TREND FLIP"; }
      if(!NA(V.pbSellE) && V.pbSellArmBar >= 0 && i - V.pbSellArmBar > InpPbExpiry) { V.pbSellE = EMPTY_VALUE; V.pbSellDeath = "EXPIRED " + FI(InpPbExpiry) + "b"; }
      if(!NA(V.pbSellE) && close > V.pbSellE + InpPbTapMax * atrValue) { V.pbSellE = EMPTY_VALUE; V.pbSellDeath = "GAPPED THRU"; }
      bool pbCoolOK = V.pbLastFire < 0 || (i - V.pbLastFire) >= InpPbCoolBars;
      bool pbHtfAln = (isUpTrend && h1Bull && h4Bull) || (isDownTrend && h1Bear && h4Bear);
      bool newsOK = (!InpNewsBlockNew || !inNewsWindow);
      bool pbFireB = FEATURE_PULLBACK && InpPbEnable && InpSsEnable && tradeAllowed && pbCoolOK && V.pbFiresHr < InpPbMaxHr && !NA(V.pbBuyE) && low <= V.pbBuyE && close >= V.pbBuyE && g_symbolAllowed && !dxySquelched && newsOK && confirmed;
      bool pbFireS = FEATURE_PULLBACK && InpPbEnable && InpSsEnable && tradeAllowed && pbCoolOK && V.pbFiresHr < InpPbMaxHr && !NA(V.pbSellE) && high >= V.pbSellE && close <= V.pbSellE && g_symbolAllowed && !dxySquelched && newsOK && confirmed;
      double pbRRb = 0.0, pbRRs = 0.0;
      double pbBuyE = V.pbBuyE, pbBuySL = V.pbBuySL, pbBuyT1 = V.pbBuyT1, pbBuyT2 = V.pbBuyT2, pbSellE = V.pbSellE, pbSellSL = V.pbSellSL, pbSellT1 = V.pbSellT1, pbSellT2 = V.pbSellT2;
      if(pbFireB)
      {
         pbRRb = (MathAbs(pbBuyE - pbBuySL) > 0) ? (pbBuyT1 - pbBuyE) / (pbBuyE - pbBuySL) : 0.0;
         V.tradesToday++; V.pbLastFire = i; V.pbFiresHr++; V.pbBuyE = EMPTY_VALUE;
         V.pbFireBarT = t; V.pbFireBuy = true;
      }
      if(pbFireS)
      {
         pbRRs = (MathAbs(pbSellE - pbSellSL) > 0) ? (pbSellE - pbSellT1) / (pbSellSL - pbSellE) : 0.0;
         V.tradesToday++; V.pbLastFire = i; V.pbFiresHr++; V.pbSellE = EMPTY_VALUE;
         V.pbFireBarT = t; V.pbFireBuy = false;
      }

      // SECTION 17 - ENTRY CONDITIONS + SIGNAL STATE (the legacy MICRO / SWING labels)
      bool buyCondition = isUpTrend && htfBullAgree && nearSupport && rsiBull && volOk && sessionTrade && spreadOk && !adxTrendWeak && tradeAllowed && dxyBullConfirm;
      bool sellCondition = isDownTrend && htfBearAgree && nearResistance && rsiBear && volOk && sessionTrade && spreadOk && !adxTrendWeak && tradeAllowed && dxySellConfirm;
      int barsElapsed = (V.sigBar >= 0) ? i - V.sigBar : 9999;
      bool signalExpired = barsElapsed > 20;
      bool trendFlipped = (V.sigDir == "BUY" && isDownTrend) || (V.sigDir == "SELL" && isUpTrend);
      bool slHit = false;
      if(!NA(V.sigMicroSL) && !NA(V.sigEntry)) { if(V.sigDir == "BUY" && close < V.sigMicroSL) slHit = true; if(V.sigDir == "SELL" && close > V.sigMicroSL) slHit = true; }
      if(trendFlipped || signalExpired || slHit) { V.sigEntry = EMPTY_VALUE; V.sigMicroSL = EMPTY_VALUE; V.sigDir = "NONE"; V.sigBar = -1; V.sigActive = false; }
      if(buyCondition && !NA(lastLow))
      {
         double entry = close, sl = MathMax(lastLow - g_pipZone, entry - atrSL), risk = MathAbs(entry - sl);
         double tp1 = entry + risk, tp2 = entry + risk * InpRR, swingTP = entry + InpSwingTarget, swingSL = entry - InpSwingStop;
         double swingR = RoundTo(InpSwingTarget / InpSwingStop, 1), lotSize = (risk > 0.001) ? BsLots(risk) : 0.0;
         if(tp2 > entry && sl < entry && swingTP > entry && swingSL < entry)
         {
            V.sigEntry = entry; V.sigMicroSL = sl; V.sigDir = "BUY"; V.sigBar = i; V.sigActive = true;
            BsLabelUp(dr, t, low, "MICRO BUY\nE:    " + F2(entry) + "\nSL:   " + F2(sl) + "\nTP1:  " + F2(tp1) + "\nTP2:  " + F2(tp2) + "\nLots: " + F2(lotSize) + "\nScore:" + FI(scoreBuy) + "/10", cGreen, 8);
            BsLabelUp(dr, t, low - atrValue * 1.5, "SWING BUY\nE:   " + F2(entry) + "\nSL:  " + F2(swingSL) + "\nTP:  " + F2(swingTP) + "\nR:R  1:" + F1(swingR), cBlue, 8);
         }
      }
      if(sellCondition && !NA(lastHigh))
      {
         double entry = close, sl = MathMin(lastHigh + g_pipZone, entry + atrSL), risk = MathAbs(sl - entry);
         double tp1 = entry - risk, tp2 = entry - risk * InpRR, swingTP = entry - InpSwingTarget, swingSL = entry + InpSwingStop;
         double swingR = RoundTo(InpSwingTarget / InpSwingStop, 1), lotSize = (risk > 0.001) ? BsLots(risk) : 0.0;
         if(tp2 < entry && sl > entry && swingTP < entry && swingSL > entry)
         {
            V.sigEntry = entry; V.sigMicroSL = sl; V.sigDir = "SELL"; V.sigBar = i; V.sigActive = true;
            BsLabelDown(dr, t, high, "MICRO SELL\nE:    " + F2(entry) + "\nSL:   " + F2(sl) + "\nTP1:  " + F2(tp1) + "\nTP2:  " + F2(tp2) + "\nLots: " + F2(lotSize) + "\nScore:" + FI(scoreSell) + "/10", cRed, 8);
            BsLabelDown(dr, t, high + atrValue * 1.5, "SWING SELL\nE:   " + F2(entry) + "\nSL:  " + F2(swingSL) + "\nTP:  " + F2(swingTP) + "\nR:R  1:" + F1(swingR), cOrange, 8);
         }
      }

      // SMART SCALP v18.6 - the single fire chain (f_smartScalp)
      int threshold = InpFcThreshold;
      bool scoreOKbuy = scoreBuy >= threshold && (!InpFcRequireDom || scoreBuy > scoreSell);
      bool scoreOKsell = scoreSell >= threshold && (!InpFcRequireDom || scoreSell > scoreBuy);
      bool baseGate = InpSsEnable && tradeAllowed && sessionTrade;
      double recentLow10 = BsLowest(g_l, i, 10), recentHigh10 = BsHighest(g_h, i, 10);
      double cand[]; int nc = 0;
      BsPushIf(cand, nc, lastLow - g_pipZone, !NA(lastLow) && (lastLow - g_pipZone) < close);
      BsPushIf(cand, nc, prevLow - g_pipZone, !NA(prevLow) && (prevLow - g_pipZone) < close);
      BsPushIf(cand, nc, recentLow10 - g_pipZone, (recentLow10 - g_pipZone) < close);
      BsPushIf(cand, nc, lastBullFVGbot - g_pipZone, !NA(lastBullFVGbot) && (lastBullFVGbot - g_pipZone) < close);
      BsPushIf(cand, nc, ssBullOBlow - g_pipZone, !NA(ssBullOBlow) && (ssBullOBlow - g_pipZone) < close);
      BsPushIf(cand, nc, ma50 - g_pipZone, (ma50 - g_pipZone) < close);
      BsPushIf(cand, nc, rangeLow - g_pipZone, !NA(rangeLow) && (rangeLow - g_pipZone) < close);
      double buySLraw = (nc > 0) ? BsArrMax(cand, nc) : (close - atrSL);
      double buySLcap = MathMax(buySLraw, close - atrValue * InpSsAtrCap);
      double buySL = MathMin(buySLcap, close - atrValue * aeSLFloor);
      double tps[]; int nt = 0;
      BsPushIf(tps, nt, pivotR1, !NA(pivotR1) && pivotR1 > close);
      BsPushIf(tps, nt, pivotR2, !NA(pivotR2) && pivotR2 > close);
      BsPushIf(tps, nt, pivotR3, !NA(pivotR3) && pivotR3 > close);
      BsPushIf(tps, nt, lastHigh, !NA(lastHigh) && lastHigh > close);
      BsPushIf(tps, nt, prevHigh, !NA(prevHigh) && prevHigh > close);
      BsPushIf(tps, nt, recentHigh10, recentHigh10 > close);
      BsPushIf(tps, nt, lastBearFVGtop, !NA(lastBearFVGtop) && lastBearFVGtop > close);
      BsPushIf(tps, nt, rangeHigh, !NA(rangeHigh) && rangeHigh > close);
      BsPushIf(tps, nt, ssBearOBlow, !NA(ssBearOBlow) && ssBearOBlow > close);
      BsPushIf(tps, nt, pdHigh, !NA(pdHigh) && pdHigh > close);
      BsSortAsc(tps, nt);
      double buyRisk = MathAbs(close - buySL), buy1R = close + buyRisk;
      bool buyTP1struct = false;
      double buyTP1 = EMPTY_VALUE, buyTP2 = EMPTY_VALUE;
      int idx1 = -1;
      for(int k = 0; k < nt; k++) if(idx1 < 0 && tps[k] >= buy1R) idx1 = k;
      if(idx1 >= 0)
      {
         buyTP1 = tps[idx1]; buyTP1struct = true;
         double minTP2 = buyTP1 + buyRisk * 0.5;
         for(int k = idx1 + 1; k < nt; k++) if(NA(buyTP2) && tps[k] >= minTP2) buyTP2 = tps[k];
      }
      if(NA(buyTP1)) { buyTP1 = close + buyRisk * 1.8; buyTP1struct = false; }
      if(NA(buyTP2)) buyTP2 = buyTP1 + buyRisk * 1.0;
      if(buyTP2 - buyTP1 < buyRisk * 0.5) buyTP2 = buyTP1 + buyRisk * 0.8;
      if(InpUseFillBuffer)
      {
         buyTP1 = MathMax(close + g_tick, buyTP1 - atrValue * InpTpBufAtr);
         buyTP2 = MathMax(buyTP1 + g_tick, buyTP2 - atrValue * InpTpBufAtr);
         buySL = MathMin(close - g_tick, buySL - atrValue * InpSlBufAtr);
      }
      double cs[]; int ncs = 0;
      BsPushIf(cs, ncs, lastHigh + g_pipZone, !NA(lastHigh) && (lastHigh + g_pipZone) > close);
      BsPushIf(cs, ncs, prevHigh + g_pipZone, !NA(prevHigh) && (prevHigh + g_pipZone) > close);
      BsPushIf(cs, ncs, recentHigh10 + g_pipZone, (recentHigh10 + g_pipZone) > close);
      BsPushIf(cs, ncs, lastBearFVGtop + g_pipZone, !NA(lastBearFVGtop) && (lastBearFVGtop + g_pipZone) > close);
      BsPushIf(cs, ncs, ssBearOBhigh + g_pipZone, !NA(ssBearOBhigh) && (ssBearOBhigh + g_pipZone) > close);
      BsPushIf(cs, ncs, ma50 + g_pipZone, (ma50 + g_pipZone) > close);
      BsPushIf(cs, ncs, rangeHigh + g_pipZone, !NA(rangeHigh) && (rangeHigh + g_pipZone) > close);
      double sellSLraw = (ncs > 0) ? BsArrMin(cs, ncs) : (close + atrSL);
      double sellSLcap = MathMin(sellSLraw, close + atrValue * InpSsAtrCap);
      double sellSL = MathMax(sellSLcap, close + atrValue * aeSLFloor);
      double tss[]; int nts = 0;
      BsPushIf(tss, nts, pivotS1, !NA(pivotS1) && pivotS1 < close);
      BsPushIf(tss, nts, pivotS2, !NA(pivotS2) && pivotS2 < close);
      BsPushIf(tss, nts, pivotS3, !NA(pivotS3) && pivotS3 < close);
      BsPushIf(tss, nts, lastLow, !NA(lastLow) && lastLow < close);
      BsPushIf(tss, nts, prevLow, !NA(prevLow) && prevLow < close);
      BsPushIf(tss, nts, recentLow10, recentLow10 < close);
      BsPushIf(tss, nts, lastBullFVGbot, !NA(lastBullFVGbot) && lastBullFVGbot < close);
      BsPushIf(tss, nts, rangeLow, !NA(rangeLow) && rangeLow < close);
      BsPushIf(tss, nts, ssBullOBhigh, !NA(ssBullOBhigh) && ssBullOBhigh < close);
      BsPushIf(tss, nts, pdLow, !NA(pdLow) && pdLow < close);
      BsSortDesc(tss, nts);
      double sellRisk = MathAbs(sellSL - close), sell1R = close - sellRisk;
      bool sellTP1struct = false;
      double sellTP1 = EMPTY_VALUE, sellTP2 = EMPTY_VALUE;
      int idx2 = -1;
      for(int k = 0; k < nts; k++) if(idx2 < 0 && tss[k] <= sell1R) idx2 = k;
      if(idx2 >= 0)
      {
         sellTP1 = tss[idx2]; sellTP1struct = true;
         double minTP2s = sellTP1 - sellRisk * 0.5;
         for(int k = idx2 + 1; k < nts; k++) if(NA(sellTP2) && tss[k] <= minTP2s) sellTP2 = tss[k];
      }
      if(NA(sellTP1)) { sellTP1 = close - sellRisk * 1.8; sellTP1struct = false; }
      if(NA(sellTP2)) sellTP2 = sellTP1 - sellRisk * 1.0;
      if(sellTP1 - sellTP2 < sellRisk * 0.5) sellTP2 = sellTP1 - sellRisk * 0.8;
      if(InpUseFillBuffer)
      {
         sellTP1 = MathMin(close - g_tick, sellTP1 + atrValue * InpTpBufAtr);
         sellTP2 = MathMin(sellTP1 - g_tick, sellTP2 + atrValue * InpTpBufAtr);
         sellSL = MathMax(close + g_tick, sellSL + atrValue * InpSlBufAtr);
      }
      double buyRR = (buyRisk > 0.0) ? MathAbs(buyTP1 - close) / buyRisk : 0.0;
      double sellRR = (sellRisk > 0.0) ? MathAbs(close - sellTP1) / sellRisk : 0.0;
      // the 6 veto flags
      bool v1b = !(isDownTrend && V.lastChoch == "DOWN" && bearInducement), v2b = h4Bull || !h4Bear, v3b = !(sweepRecent && lastSweepType == "BUY-SIDE SWEPT"), v4b = buyRR >= InpFcMinRR, v5b = buyTP1struct, v6b = spreadOk;
      bool v1s = !(isUpTrend && V.lastChoch == "UP" && bullInducement), v2s = h4Bear || !h4Bull, v3s = !(sweepRecent && lastSweepType == "SELL-SIDE SWEPT"), v4s = sellRR >= InpFcMinRR, v5s = sellTP1struct, v6s = spreadOk;
      int bV = (v1b ? 1 : 0) + (v2b ? 1 : 0) + (v3b ? 1 : 0) + (v4b ? 1 : 0) + (v5b ? 1 : 0) + (v6b ? 1 : 0);
      int sV = (v1s ? 1 : 0) + (v2s ? 1 : 0) + (v3s ? 1 : 0) + (v4s ? 1 : 0) + (v5s ? 1 : 0) + (v6s ? 1 : 0);
      // macro confidence modifier (capped demotion)
      bool isBTC = BsHas(g_ticker, "BTC"), isJPY = BsHas(g_ticker, "USDJPY");
      int macroBuyRaw = (isMetals ? ((dxyFalling ? 1 : 0) + (dxyRising ? -1 : 0) + (oilSpike ? -1 : 0)) : 0) + (isBTC ? ((dxyFalling ? 1 : 0) + (dxyRising ? -1 : 0)) : 0) + (isJPY ? ((dxyRising ? 1 : 0) + (dxyFalling ? -1 : 0)) : 0)
                      + (isMetals ? ((yieldFalling ? 1 : 0) + (yieldRising ? -1 : 0)) : 0) + (isBTC ? ((yieldFalling ? 1 : 0) + (yieldRising ? -1 : 0)) : 0) + (isJPY ? ((yieldRising ? 1 : 0) + (yieldFalling ? -1 : 0)) : 0) + (isIndex ? ((yieldFalling ? 1 : 0) + (yieldRising ? -1 : 0)) : 0);
      int macroSellRaw = (isMetals ? ((dxyRising ? 1 : 0) + (dxyFalling ? -1 : 0) + (oilSpike ? -1 : 0)) : 0) + (isBTC ? ((dxyRising ? 1 : 0) + (dxyFalling ? -1 : 0)) : 0) + (isJPY ? ((dxyFalling ? 1 : 0) + (dxyRising ? -1 : 0)) : 0)
                       + (isMetals ? ((yieldRising ? 1 : 0) + (yieldFalling ? -1 : 0)) : 0) + (isBTC ? ((yieldRising ? 1 : 0) + (yieldFalling ? -1 : 0)) : 0) + (isJPY ? ((yieldFalling ? 1 : 0) + (yieldRising ? -1 : 0)) : 0) + (isIndex ? ((yieldRising ? 1 : 0) + (yieldFalling ? -1 : 0)) : 0);
      int macroBuy = MathMax(macroBuyRaw, -InpFcMacroCap), macroSell = MathMax(macroSellRaw, -InpFcMacroCap);
      int adjScoreBuy = MathMin(10, MathMax(0, scoreBuy + macroBuy)), adjScoreSell = MathMin(10, MathMax(0, scoreSell + macroSell));
      string bGrade = (adjScoreBuy >= 9 && bV == 6 && dailyBull && h4Bull) ? "A+" : ((adjScoreBuy >= 8 && bV >= 5 && h4Bull) ? "A" : ((adjScoreBuy >= 7 && bV >= 5) ? "B" : ((adjScoreBuy >= 7 && bV >= 4) ? "C" : "D")));
      string sGrade = (adjScoreSell >= 9 && sV == 6 && dailyBear && h4Bear) ? "A+" : ((adjScoreSell >= 8 && sV >= 5 && h4Bear) ? "A" : ((adjScoreSell >= 7 && sV >= 5) ? "B" : ((adjScoreSell >= 7 && sV >= 4) ? "C" : "D")));
      bool fireBuy = baseGate && scoreOKbuy && buyRisk > 0.0 && (!InpLgApplyChart || (locBuyOK && lgBuyCooldownOK));
      bool fireSell = baseGate && scoreOKsell && sellRisk > 0.0 && (!InpLgApplyChart || (locSellOK && lgSellCooldownOK));
      bool bGradeOK = InpFcFireAllGrades || bGrade == "A+" || bGrade == "A" || bGrade == "B";
      bool sGradeOK = InpFcFireAllGrades || sGrade == "A+" || sGrade == "A" || sGrade == "B";
      bool fireBuyBot = fireBuy && v4b && bGradeOK && locBuyOK && lgBuyCooldownOK && buyTrigOK;
      bool fireSellBot = fireSell && v4s && sGradeOK && locSellOK && lgSellCooldownOK && sellTrigOK;
      fireBuyBot = fireBuyBot && g_symbolAllowed && !dxySquelched && newsOK && (InpLgMaxEntryDist <= 0.0 || buyDistZ <= InpLgMaxEntryDist);
      fireSellBot = fireSellBot && g_symbolAllowed && !dxySquelched && newsOK && (InpLgMaxEntryDist <= 0.0 || sellDistZ <= InpLgMaxEntryDist);
      double bLots = (buyRisk > 0.001) ? BsLots(buyRisk) : 0.0, sLots = (sellRisk > 0.001) ? BsLots(sellRisk) : 0.0;
      // the fire consumes the cooldown + the daily quota (confirmed bars only, like freq_once_per_bar_close)
      bool ssFireBotB = fireBuyBot && confirmed, ssFireBotS = fireSellBot && confirmed;
      if(ssFireBotB) { V.lgLastBuyFireBar = i; V.ssFireBarT = t; V.ssFireBotBuy = true; }
      if(ssFireBotS) { V.lgLastSellFireBar = i; V.ssFireBarT = t; V.ssFireBotBuy = false; }
      if(ssFireBotB || ssFireBotS) V.tradesToday++;
      bool ssFireB = fireBuy, ssFireS = fireSell;
      if(ssFireB && confirmed) BsEvPush(5, t, low, 0, 0, "", cNeonG, cNeonG, 0, 0);
      if(ssFireS && confirmed) BsEvPush(6, t, high, 0, 0, "", cNeonR, cNeonR, 0, 0);

      // SMART SCALP state: latch on a CONFIRMED fire, auto-clear with the reason (v18.12.1)
      if(ssFireB && confirmed) { V.saEntry = close; V.saSL = buySL; V.saTP1 = buyTP1; V.saTP2 = buyTP2; V.saScore = scoreBuy; V.saRR = buyRR; V.saGrade = bGrade; V.saLots = bLots; V.saDir = "BUY"; V.saBar = i; V.saActive = true; }
      if(ssFireS && confirmed) { V.saEntry = close; V.saSL = sellSL; V.saTP1 = sellTP1; V.saTP2 = sellTP2; V.saScore = scoreSell; V.saRR = sellRR; V.saGrade = sGrade; V.saLots = sLots; V.saDir = "SELL"; V.saBar = i; V.saActive = true; }
      bool saTpHit = (V.saDir == "BUY" && !NA(V.saTP2) && high >= V.saTP2) || (V.saDir == "SELL" && !NA(V.saTP2) && low <= V.saTP2);
      bool saSlHit = (V.saDir == "BUY" && !NA(V.saSL) && close < V.saSL) || (V.saDir == "SELL" && !NA(V.saSL) && close > V.saSL);
      bool saFlip = (V.saDir == "BUY" && isDownTrend) || (V.saDir == "SELL" && isUpTrend);
      bool saTimeout = V.saActive && V.saBar >= 0 && i - V.saBar > InpSaExpireBars;
      if(V.saActive && (saTimeout || saTpHit || saSlHit || saFlip)) { V.saActive = false; V.saEndWhy = saTpHit ? "TP2 HIT" : (saSlHit ? "SL HIT" : (saFlip ? "trend flip" : "expired")); }

      // MANUAL TRADE MONITOR (v18.4g / v18.9 P1-A / v18.12.2)
      bool manTrendUp = h1Bull || (!h1Bear && isUpTrend), manTrendDn = h1Bear || (!h1Bull && isDownTrend);
      string manDir = (locSellOK && locBuyOK) ? (manTrendUp ? "BUY" : "SELL") : (locSellOK ? "SELL" : (locBuyOK ? "BUY" : ((sellZoneNear && buyZoneNear) ? (manTrendUp ? "BUY" : "SELL") : (sellZoneNear ? "SELL" : (buyZoneNear ? "BUY" : "NONE")))));
      bool manCtr = (manDir == "SELL" && manTrendUp) || (manDir == "BUY" && manTrendDn);
      bool manIsBuy = (manDir == "BUY");
      double manFB = InpUseFillBuffer ? atrValue * InpTpBufAtr : 0.0, manSB = InpUseFillBuffer ? atrValue * InpSlBufAtr : 0.0;
      double manZoneEdge = manIsBuy ? ((buyZnOB && !NA(ssBullOBhigh)) ? ssBullOBhigh : ((buyZnFVG && !NA(lastBullFVGtop)) ? lastBullFVGtop : (!NA(lastLow) ? lastLow : EMPTY_VALUE)))
                                     : ((sellZnOB && !NA(ssBearOBlow)) ? ssBearOBlow : ((sellZnFVG && !NA(lastBearFVGbot)) ? lastBearFVGbot : (!NA(lastHigh) ? lastHigh : EMPTY_VALUE)));
      double manMktE = close, manPendE = !NA(manZoneEdge) ? manZoneEdge : close;
      double manAtrSL = manIsBuy ? manMktE - atrValue * InpManRiskAtr - manSB : manMktE + atrValue * InpManRiskAtr + manSB;
      double manAtrTP1 = manIsBuy ? manMktE + atrValue * InpManRiskAtr * 1.5 - manFB : manMktE - atrValue * InpManRiskAtr * 1.5 + manFB;
      double manAtrTP2 = manIsBuy ? manMktE + atrValue * InpManRiskAtr * 3.0 - manFB : manMktE - atrValue * InpManRiskAtr * 3.0 + manFB;
      double manStrSL = !NA(manZoneEdge) ? (manIsBuy ? manZoneEdge - atrValue * 0.3 - manSB : manZoneEdge + atrValue * 0.3 + manSB) : manAtrSL;
      manStrSL = manIsBuy ? MathMin(manStrSL, manMktE - atrValue * InpManMinSlAtr) : MathMax(manStrSL, manMktE + atrValue * InpManMinSlAtr);
      double manStrTP1 = manIsBuy ? ((!NA(pivotR1) && pivotR1 > manMktE && pivotR1 - manMktE <= atrValue * InpManMaxTpAtr) ? pivotR1 - manFB : manAtrTP1) : ((!NA(pivotS1) && pivotS1 < manMktE && manMktE - pivotS1 <= atrValue * InpManMaxTpAtr) ? pivotS1 + manFB : manAtrTP1);
      double manStrTP2 = manIsBuy ? ((!NA(pivotR2) && pivotR2 > manMktE && pivotR2 - manMktE <= atrValue * InpManMaxTpAtr) ? pivotR2 - manFB : manAtrTP2) : ((!NA(pivotS2) && pivotS2 < manMktE && manMktE - pivotS2 <= atrValue * InpManMaxTpAtr) ? pivotS2 + manFB : manAtrTP2);
      double manAtrRR = (MathAbs(manMktE - manAtrSL) > 0) ? MathAbs(manAtrTP2 - manMktE) / MathAbs(manMktE - manAtrSL) : 0.0;
      double manStrRR = (MathAbs(manMktE - manStrSL) > 0) ? MathAbs(manStrTP2 - manMktE) / MathAbs(manMktE - manStrSL) : 0.0;
      bool manUseStr = manStrRR >= manAtrRR;
      double manSL = manUseStr ? manStrSL : manAtrSL, manTP1 = manUseStr ? manStrTP1 : manAtrTP1, manTP2 = manUseStr ? manStrTP2 : manAtrTP2;
      double manRR = RoundTo(manUseStr ? manStrRR : manAtrRR, 1);
      string manMethod = manUseStr ? "structure" : "ATR";
      string manStatus = (manDir == "NONE") ? "no zone" : (manIsBuy ? (buyTrigOK ? "CONFIRMED" : (buyRejectC ? "REJECTION" : "ZONE TOUCH")) : (sellTrigOK ? "CONFIRMED" : (sellRejectC ? "REJECTION" : "ZONE TOUCH")));
      bool manGatePass = locBuyOK || locSellOK;

      // the confirmed-bar snapshot the trade layer acts on (the live bar never confirms)
      if(i == n - 2)
      {
         g_fire.bar = t;
         g_fire.ssBuy = ssFireBotB; g_fire.ssSell = ssFireBotS; g_fire.ssEntry = close;
         g_fire.ssSL = ssFireBotB ? buySL : sellSL; g_fire.ssTP1 = ssFireBotB ? buyTP1 : sellTP1; g_fire.ssTP2 = ssFireBotB ? buyTP2 : sellTP2;
         g_fire.ssRR = ssFireBotB ? buyRR : sellRR; g_fire.ssLots = ssFireBotB ? bLots : sLots; g_fire.ssGrade = ssFireBotB ? bGrade : sGrade; g_fire.ssScore = ssFireBotB ? scoreBuy : scoreSell;
         g_fire.pbBuy = pbFireB; g_fire.pbSell = pbFireS; g_fire.pbE = pbFireB ? pbBuyE : pbSellE; g_fire.pbSL = pbFireB ? pbBuySL : pbSellSL;
         g_fire.pbT1 = pbFireB ? pbBuyT1 : pbSellT1; g_fire.pbT2 = pbFireB ? pbBuyT2 : pbSellT2; g_fire.pbRR = pbFireB ? pbRRb : pbRRs; g_fire.pbAln = pbHtfAln;
         g_fire.armBuyE = V.pbBuyE; g_fire.armBuySL = V.pbBuySL; g_fire.armBuyT1 = V.pbBuyT1; g_fire.armBuyT2 = V.pbBuyT2; g_fire.armBuyBar = V.pbBuyArmBar;
         g_fire.armBuyT = (V.pbBuyArmBar >= 0) ? g_t[V.pbBuyArmBar] : 0;
         g_fire.armSellE = V.pbSellE; g_fire.armSellSL = V.pbSellSL; g_fire.armSellT1 = V.pbSellT1; g_fire.armSellT2 = V.pbSellT2; g_fire.armSellBar = V.pbSellArmBar;
         g_fire.armSellT = (V.pbSellArmBar >= 0) ? g_t[V.pbSellArmBar] : 0;
         g_fire.pbCoolOK = (V.pbLastFire < 0 || (i - V.pbLastFire) >= InpPbCoolBars); g_fire.pbHrOK = (V.pbFiresHr < InpPbMaxHr);
         g_fire.squelched = squelchNow; g_fire.newsBlock = (InpNewsBlockNew && inNewsWindow);
      }

      // shift the per-bar memories (the Pine's [1] / [2])
      sellRej2 = sellRej1; sellRej1 = sellRejectC; buyRej2 = buyRej1; buyRej1 = buyRejectC;

      if(!isLast)
         continue;

      // ---- the bar the panels read: everything the dashboards print, named as in the Pine ----
      BsOut o;
      o.close = close; o.inAsia = inAsia; o.inLondon = inLondon; o.inNewYork = inNewYork; o.sessionTrade = sessionTrade; o.sessionTxt = sessionTxt;
      o.sessionClr = inNewYork ? cOrange : (inLondon ? cBlue : (inAsia ? cPurple : cGray));
      o.inKzPre = inKzPre; o.inKzOpen = inKzOpen; o.inKzAfter = inKzAfter; o.inAnyNYKz = inAnyNYKz;
      o.kzLabel = inKzPre ? "Pre-Open (08:30-09:00 ET)" : (inKzOpen ? "Cash Open (09:30-10:30 ET)" : (inKzAfter ? "Afternoon (13:00-14:00 ET)" : g_uDash));
      o.kzClr = inKzPre ? cYellow : (inKzOpen ? cOrange : (inKzAfter ? cAqua : cGray));
      o.inNewsWindow = inNewsWindow; o.volHigh = volHigh; o.aeZoneMul = aeZoneMul; o.aeChaseMul = aeChaseMul; o.aeSLFloor = aeSLFloor;
      o.dxySquelched = squelchNow; o.dxySqRemain = squelchNow ? (int)MathMax(0, (long)g_squelchUntil - (long)nowS) : 0;
      o.dxySqTxt = squelchNow ? "ACTIVE - " + FI(o.dxySqRemain) + "s left" : (InpUseDXYSquelch ? "armed" : "OFF");
      o.dxySqClr = squelchNow ? cRed : (InpUseDXYSquelch ? cLime : cGray);
      o.pdHigh = pdHigh; o.pdLow = pdLow; o.wHigh = wHigh; o.wLow = wLow; o.nwogOpen = V.nwogOpen; o.orgHigh = V.orgHigh; o.orgLow = V.orgLow; o.midnightOpen = V.midnightOpen; o.nyCloseY = nyCloseY;
      o.dxyClose = dxyClose; o.dxyRising = dxyRising; o.dxyFalling = dxyFalling; o.dxyTxt = dxyTxt; o.dxyClr = dxyRising ? cRed : (dxyFalling ? cLime : cOrange);
      o.isMetals = isMetals; o.dxyBullConfirm = dxyBullConfirm; o.dxySellConfirm = dxySellConfirm;
      o.yieldRising = yieldRising; o.yieldFalling = yieldFalling; o.yieldTxt = yieldTxt; o.yieldClr = yieldRising ? cRed : (yieldFalling ? cLime : cOrange);
      o.tradesToday = V.tradesToday;
      o.h1Bull = h1Bull; o.h1Bear = h1Bear; o.h4Bull = h4Bull; o.h4Bear = h4Bear; o.dailyBull = dailyBull; o.dailyBear = dailyBear;
      o.htfBullAgree = htfBullAgree; o.htfBearAgree = htfBearAgree; o.htfFullAgree = htfFullAgree; o.htfBullCount = htfBullCount; o.htfBearCount = htfBearCount;
      o.highSwing = highSwing; o.lowSwing = lowSwing; o.lastHigh = lastHigh; o.lastLow = lastLow; o.prevHigh = prevHigh; o.prevLow = prevLow;
      o.trend = V.trend; o.isUpTrend = isUpTrend; o.isDownTrend = isDownTrend; o.isHH = isHH; o.isHL = isHL; o.isLH = isLH; o.isLL = isLL; o.structState = structState;
      o.rangeHigh = rangeHigh; o.rangeLow = rangeLow; o.equilLevel = equilLevel; o.inPremium = inPremium; o.inDiscount = inDiscount; o.fibZoneTxt = fibZoneTxt;
      o.fibZoneClr = inPremium ? cRed : (inDiscount ? cLime : cOrange);
      o.pivotP = pivotP; o.pivotR1 = pivotR1; o.pivotR2 = pivotR2; o.pivotR3 = pivotR3; o.pivotS1 = pivotS1; o.pivotS2 = pivotS2; o.pivotS3 = pivotS3;
      o.nearestPivotName = nearestPivotName; o.nearestPivotVal = nearestPivotVal; o.atPivot = atPivot; o.abovePP = abovePP;
      o.chochUp = chochUp; o.chochDown = chochDown; o.chochRecent = chochRecent; o.lastChoch = V.lastChoch; o.chochTxt = chochTxt;
      o.chochClr = chochRecent ? ((V.lastChoch == "UP") ? cLime : cRed) : cGray; o.bosUp = bosUp; o.bosDown = bosDown;
      o.lastBullFVGtop = lastBullFVGtop; o.lastBullFVGbot = lastBullFVGbot; o.lastBearFVGtop = lastBearFVGtop; o.lastBearFVGbot = lastBearFVGbot;
      o.bullFVGabove = bullFVGabove; o.bullFVGinside = bullFVGinside; o.bearFVGbelow = bearFVGbelow; o.bearFVGinside = bearFVGinside; o.fvgPresent = fvgPresent; o.fvgStatusTxt = fvgStatusTxt;
      o.fvgStatusClr = bullFVGabove ? cLime : (bullFVGinside ? cTeal : (bearFVGbelow ? cRed : (bearFVGinside ? cOrange : cGray)));
      o.impulseUp = impulseUp; o.impulseDown = impulseDown; o.bullOB = bullOB; o.bearOB = bearOB; o.lastOBtype = lastOBtype; o.obMitigated = obMitigated; o.obStatusTxt = obStatusTxt;
      o.obStatusClr = obMitigated ? cOrange : cLime; o.obStrengthClr = BsHas(lastOBtype, "STRONG") ? cLime : ((lastOBtype == "NONE") ? cGray : cYellow);
      o.ssBullOBhigh = ssBullOBhigh; o.ssBullOBlow = ssBullOBlow; o.ssBearOBhigh = ssBearOBhigh; o.ssBearOBlow = ssBearOBlow;
      o.stopHuntBull = stopHuntBull; o.stopHuntBear = stopHuntBear; o.equalHighs = equalHighs; o.equalLows = equalLows; o.sweepRecent = sweepRecent; o.lastSweepType = lastSweepType; o.sweepTxt = sweepTxt;
      o.sweepClr = (sweepRecent && lastSweepType == "BUY-SIDE SWEPT") ? cLime : ((sweepRecent && lastSweepType == "SELL-SIDE SWEPT") ? cRed : (equalHighs ? cRed : (equalLows ? cLime : cGray)));
      o.fakeBOdown = fakeBOdown; o.fakeBOup = fakeBOup; o.realMoveUp = realMoveUp; o.realMoveDown = realMoveDown;
      o.bullEngulf = bullEngulf; o.bearEngulf = bearEngulf; o.pinBarBull = pinBarBull; o.pinBarBear = pinBarBear; o.isDoji = isDoji; o.isHammer = isHammer; o.isShootStar = isShootStar; o.insideBar = insideBar; o.bullMaru = bullMaru; o.bearMaru = bearMaru;
      o.currentPatternTxt = currentPatternTxt; o.currentPatternClr = (bullEngulf || isHammer || bullMaru) ? cLime : ((bearEngulf || isShootStar || bearMaru) ? cRed : ((isDoji || insideBar) ? cOrange : cGray));
      o.candlePatternOk = candlePatternOk; o.candlePatternOkBear = candlePatternOkBear;
      o.bearInducement = bearInducement; o.bullInducement = bullInducement; o.inducementTxt = inducementTxt; o.inducementClr = bearInducement ? cRed : (bullInducement ? cLime : cGray);
      o.nearSupport = nearSupport; o.nearResistance = nearResistance; o.scalpTickBull = scalpTickBull; o.scalpTickBear = scalpTickBear;
      o.scoreBuy = scoreBuy; o.scoreSell = scoreSell; o.scoreBuyTxt = FI(scoreBuy) + "/10"; o.scoreSellTxt = FI(scoreSell) + "/10";
      o.scoreBuyClr = (scoreBuy >= 8) ? cLime : ((scoreBuy >= 5) ? cYellow : cRed); o.scoreSellClr = (scoreSell >= 8) ? cLime : ((scoreSell >= 5) ? cYellow : cRed);
      o.confVerdict = (scoreBuy >= 8) ? "STRONG BUY" : ((scoreSell >= 8) ? "STRONG SELL" : ((scoreBuy >= 5) ? "POSSIBLE BUY" : ((scoreSell >= 5) ? "POSSIBLE SELL" : "AVOID")));
      o.buyVerdict = (scoreBuy >= 8) ? "STRONG BUY" : ((scoreBuy >= 5) ? "POSSIBLE BUY" : "WEAK - wait"); o.buyVerdictClr = (scoreBuy >= 8) ? cLime : ((scoreBuy >= 5) ? cGreen : cGray);
      o.sellVerdict = (scoreSell >= 8) ? "STRONG SELL" : ((scoreSell >= 5) ? "POSSIBLE SELL" : "WEAK - wait"); o.sellVerdictClr = (scoreSell >= 8) ? cRed : ((scoreSell >= 5) ? cMaroon : cGray);
      o.minFactorsBuy = minFactorsBuy; o.minFactorsSell = minFactorsSell; o.minRuleBuy = minRuleBuy; o.minRuleSell = minRuleSell;
      o.minRuleBuyTxt = (minRuleBuy ? "GO " : "WAIT ") + FI(minFactorsBuy) + "/5"; o.minRuleSellTxt = (minRuleSell ? "GO " : "WAIT ") + FI(minFactorsSell) + "/5";
      o.minRuleBuyClr = minRuleBuy ? cLime : cRed; o.minRuleSellClr = minRuleSell ? cLime : cRed;
      o.rrQuality = (InpRR >= 2.5) ? "EXCELLENT" : ((InpRR >= 2.0) ? "GOOD" : "POOR"); o.rrQualityClr = (InpRR >= 2.5) ? cLime : ((InpRR >= 2.0) ? cYellow : cRed);
      o.trendDayOK = trendDayOK; o.sellZnFVG = sellZnFVG; o.sellZnOB = sellZnOB; o.sellZnSwing = sellZnSwing; o.sellZnPivot = sellZnPivot; o.sellZnOther = sellZnOther; o.sellSweepLG = sellSweepLG; o.sellZnTrend = sellZnTrend; o.sellZoneNear = sellZoneNear;
      o.buyZnFVG = buyZnFVG; o.buyZnOB = buyZnOB; o.buyZnSwing = buyZnSwing; o.buyZnPivot = buyZnPivot; o.buyZnOther = buyZnOther; o.buySweepLG = buySweepLG; o.buyZnTrend = buyZnTrend; o.buyZoneNear = buyZoneNear;
      o.sellZoneTxt = sellZoneTxt; o.buyZoneTxt = buyZoneTxt; o.sellZoneMem = V.sellZoneMem; o.buyZoneMem = V.buyZoneMem;
      o.sellZoneOK = sellZoneOK; o.buyZoneOK = buyZoneOK; o.sellChaseOK = sellChaseOK; o.buyChaseOK = buyChaseOK; o.sellRejectC = sellRejectC; o.buyRejectC = buyRejectC; o.sellConfirmC = sellConfirmC; o.buyConfirmC = buyConfirmC; o.sellTrigOK = sellTrigOK; o.buyTrigOK = buyTrigOK;
      o.lgBuyCooldownOK = lgBuyCooldownOK; o.lgSellCooldownOK = lgSellCooldownOK; o.locBuyOK = locBuyOK; o.locSellOK = locSellOK; o.locBuyTxt = locBuyTxt; o.locSellTxt = locSellTxt;
      o.locBuyClr = (locBuyOK && InpUseLocationGate) ? cLime : cGray; o.locSellClr = (locSellOK && InpUseLocationGate) ? cRed : cGray; o.buyDistZ = buyDistZ; o.sellDistZ = sellDistZ;
      o.pbBuyE = V.pbBuyE; o.pbBuySL = V.pbBuySL; o.pbBuyT1 = V.pbBuyT1; o.pbBuyT2 = V.pbBuyT2; o.pbSellE = V.pbSellE; o.pbSellSL = V.pbSellSL; o.pbSellT1 = V.pbSellT1; o.pbSellT2 = V.pbSellT2;
      o.pbBuyDeath = V.pbBuyDeath; o.pbSellDeath = V.pbSellDeath; o.pbBuySrc = V.pbBuySrc; o.pbSellSrc = V.pbSellSrc; o.trendAge = trendAge; o.pbHtfAln = pbHtfAln; o.pbFireB = pbFireB; o.pbFireS = pbFireS; o.pbRRb = pbRRb; o.pbRRs = pbRRs;
      o.manDir = manDir; o.manCtr = manCtr; o.manIsBuy = manIsBuy; o.manMktE = manMktE; o.manPendE = manPendE; o.manSL = manSL; o.manTP1 = manTP1; o.manTP2 = manTP2; o.manRR = manRR; o.manMethod = manMethod; o.manStatus = manStatus;
      o.manStatusClr = (manStatus == "CONFIRMED") ? cLime : ((manStatus == "REJECTION") ? cOrange : ((manStatus == "ZONE TOUCH") ? cYellow : cGray)); o.manGatePass = manGatePass;
      o.buyCondition = buyCondition; o.sellCondition = sellCondition;
      o.asiaH = asiaH; o.asiaL = asiaL; o.lonH = lonH; o.lonL = lonL; o.nyH = nyH; o.nyL = nyL;
      o.oilSpike = oilSpike; o.oilTxt = oilSpike ? "SPIKE " + g_uArrUp + " risk-off" : "calm"; o.oilClr = oilSpike ? cOrange : cGray;
      o.atrExpand = atrExpand; o.atrExpTxt = atrExpand ? "EXPAND " + g_uArrUp : "normal"; o.atrExpClr = atrExpand ? cAmber : cGray; o.sessPct = sessPct; o.sessPctOk = sessPctOk;
      o.pendHiRaw = pendHiRaw; o.pendLoRaw = pendLoRaw; o.pendHiSrc = pendHiSrc; o.pendLoSrc = pendLoSrc; o.pendRngA = pendRngA; o.pendInvalid = pendInvalid; o.pendBrokeUp = pendBrokeUp; o.pendBrokeDn = pendBrokeDn;
      o.nyRegime = nyRegime; o.nyRegimeClr = (nyRegime == "TRAP") ? cFuchsia : ((nyRegime == "TREND") ? cAqua : cGray); o.isBigCandle = isBigCandle; o.lonWasTight = lonWasTight; o.trapFiredUp = trapFiredUp; o.trapFiredDown = trapFiredDown;
      o.trapBias = trapBias; o.trapBiasClr = trapFiredUp ? cRed : (trapFiredDown ? cLime : cGray); o.trapDetail = trapDetail;
      o.atrPad = atrPad; o.atrPadActive = atrPadActive; o.tgtSource = tgtSource; o.tgtSourceClr = tgtSourceFresh ? cLime : cOrange; o.pendHiFromGate = pendHiFromGate; o.pendLoFromGate = pendLoFromGate; o.pendHiSrcTxt = pendHiSrcTxt; o.pendLoSrcTxt = pendLoSrcTxt;
      o.pendRange = pendRange; o.tightThreshold = tightThreshold; o.rangeTooTight = rangeTooTight; o.rangeTightTxt = rangeTightTxt; o.hideEntries = hideEntries; o.redWarn = redWarn;
      o.pendSellE = pendSellE; o.pendSellSL = pendSellSL; o.pendSellTP1 = pendSellTP1; o.pendSellTP2 = pendSellTP2; o.pendSellTP3 = pendSellTP3; o.pendBuyE = pendBuyE; o.pendBuySL = pendBuySL; o.pendBuyTP1 = pendBuyTP1; o.pendBuyTP2 = pendBuyTP2; o.pendBuyTP3 = pendBuyTP3;
      o.pendRiskS = pendRiskS; o.pendRiskB = pendRiskB; o.pendLotsS = pendLotsS; o.pendLotsB = pendLotsB; o.distSell = distSell; o.distBuy = distBuy; o.pendRRS = pendRRS; o.pendRRB = pendRRB;
      o.pendSellAtMkt = pendSellAtMkt; o.pendBuyAtMkt = pendBuyAtMkt; o.buyStopE = buyStopE; o.sellStopE = sellStopE;
      o.ssFireB = ssFireB; o.ssFireS = ssFireS; o.ssFireBotB = fireBuyBot; o.ssFireBotS = fireSellBot; o.ssBuySL = buySL; o.ssSellSL = sellSL; o.ssBuyTP1 = buyTP1; o.ssBuyTP2 = buyTP2; o.ssSellTP1 = sellTP1; o.ssSellTP2 = sellTP2;
      o.ssBuyRR = buyRR; o.ssSellRR = sellRR; o.ssBLots = bLots; o.ssSLots = sLots; o.ssBGrade = bGrade; o.ssSGrade = sGrade; o.adjScoreBuy = adjScoreBuy; o.adjScoreSell = adjScoreSell; o.bV = bV; o.sV = sV; o.macroBuy = macroBuy; o.macroSell = macroSell;
      o.buyTP1struct = buyTP1struct; o.sellTP1struct = sellTP1struct;
      // BOT GATE verdicts: the fire of the LAST CONFIRMED bar is what "FIRED" means on MT5 (the live bar never confirms)
      o.botBC = (V.ssFireBarT == g_t[n - 2] && V.ssFireBotBuy); o.botSC = (V.ssFireBarT == g_t[n - 2] && !V.ssFireBotBuy);
      bool bGradeOKd = (bGrade == "A+" || bGrade == "A" || bGrade == "B"), sGradeOKd = (sGrade == "A+" || sGrade == "A" || sGrade == "B");
      o.botBuyWhy = fireBuyBot ? "ALL GATES PASS" : (!InpSsEnable ? "scalp OFF" : ((scoreBuy < threshold) ? "score " + FI(scoreBuy) + " < " + FI(threshold) : ((InpFcRequireDom && scoreBuy <= scoreSell) ? "SELL side scores >= BUY" : (!bGradeOKd ? "grade " + bGrade + " (need B+)" : ((buyRR < InpFcMinRR) ? "R:R " + F2(buyRR) + " < " + F1(InpFcMinRR) : (!locBuyOK ? "gate: " + locBuyTxt : (!lgBuyCooldownOK ? "cooldown" : (squelchNow ? "DXY squelch" : "session/veto"))))))));
      o.botSellWhy = fireSellBot ? "ALL GATES PASS" : (!InpSsEnable ? "scalp OFF" : ((scoreSell < threshold) ? "score " + FI(scoreSell) + " < " + FI(threshold) : ((InpFcRequireDom && scoreSell <= scoreBuy) ? "BUY side scores >= SELL" : (!sGradeOKd ? "grade " + sGrade + " (need B+)" : ((sellRR < InpFcMinRR) ? "R:R " + F2(sellRR) + " < " + F1(InpFcMinRR) : (!locSellOK ? "gate: " + locSellTxt : (!lgSellCooldownOK ? "cooldown" : (squelchNow ? "DXY squelch" : "session/veto"))))))));
      o.saActive = V.saActive; o.saDir = V.saDir; o.saEntry = V.saEntry; o.saSL = V.saSL; o.saTP1 = V.saTP1; o.saTP2 = V.saTP2; o.saRR = V.saRR; o.saLots = V.saLots; o.saScore = V.saScore; o.saBar = V.saBar; o.saGrade = V.saGrade; o.saEndWhy = V.saEndWhy;
      o.rsiValue = rsiValue; o.atrValue = atrValue; o.atrSL = atrSL; o.adxVal = adxVal; o.volAvg = volAvg; o.spreadVal = spreadVal; o.dVwap = dVwap; o.ma20 = ma20; o.ma50 = ma50; o.lgEma20 = lgEma20; o.vwapSide = vwapSide;
      o.volOk = volOk; o.spreadOk = spreadOk; o.adxTrendStrong = adxTrendStrong; o.adxTrendModerate = adxTrendModerate; o.adxTrendWeak = adxTrendWeak;
      o.trendStrengthTxt = adxTrendStrong ? "STRONG" : (adxTrendModerate ? "MODERATE" : "WEAK"); o.trendStrengthClr = adxTrendStrong ? cLime : (adxTrendModerate ? cYellow : cRed);
      o.spreadTxt = spreadOk ? "NORMAL" : "HIGH"; o.spreadClr = spreadOk ? cLime : cRed; o.volLevel = volLevel; o.volLevelClr = (volLevel == "HIGH") ? cRed : ((volLevel == "MEDIUM") ? cYellow : cLime); o.rsiBull = rsiBull; o.rsiBear = rsiBear;
      o.emaCross = ma20 > ma50;
      o.biasDir = (isUpTrend && htfBullAgree && dailyBull && adxVal >= 20) ? "STRONG BULL" : ((isUpTrend && adxVal < 20) ? "BULL (weak)" : (isUpTrend ? "BULL" : ((isDownTrend && htfBearAgree && dailyBear && adxVal >= 20) ? "STRONG BEAR" : ((isDownTrend && adxVal < 20) ? "BEAR (weak)" : (isDownTrend ? "BEAR" : "NEUTRAL")))));
      o.biasClr = BsHas(o.biasDir, "BULL") ? cLime : (BsHas(o.biasDir, "BEAR") ? cRed : cOrange);
      o.readyBuy = isUpTrend && htfBullAgree && rsiBull && volOk; o.readySell = isDownTrend && htfBearAgree && rsiBear && volOk;
      o.nearSup = nearSupport; o.nearRes = nearResistance;
      g_out = o;
   }
}

//=== DRAWING: chart objects ========================================================
void BsObjText(string name, datetime t, double p, string text, color clr, int px, int anchor)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, px);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}
void BsObjLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, int style, int width, bool ray)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, ray);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}
void BsObjBox(string name, datetime t1, double p1, datetime t2, double p2, color fill, color border)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, (fill == cBlack) ? border : fill);
   ObjectSetInteger(0, name, OBJPROP_FILL, fill != cBlack);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}
void BsObjArrow(string name, datetime t, double p, int code, color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, t, p);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, p);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}
void BsLevel(string id, double p, string text, color clr, int style, int width, int lookback)
{
   string ln = BS_PREFIX + "L_" + id, lb = BS_PREFIX + "L_" + id + "t";
   if(NA(p)) { if(ObjectFind(0, ln) >= 0) { ObjectDelete(0, ln); ObjectDelete(0, lb); } return; }
   BsObjLine(ln, BsBarT(g_n - 1 - lookback), p, BsBarT(g_n + 30), p, clr, style, width, true);
   BsObjText(lb, BsBarT(g_n + 2), p, text + " " + F2(p), clr, 7, ANCHOR_LEFT);
}

// the history annotations (events of the replay) - drawn once per bar
void BsDrawEvents()
{
   ObjectsDeleteAll(0, BS_PREFIX + "E_");
   int boxes = 0, lines = 0, labels = 0;
   for(int k = 0; k < g_nEv; k++)
   {
      string nm = BS_PREFIX + "E_" + FI(k);
      if(g_ev[k].kind == 1) { BsObjText(nm, g_ev[k].t1, g_ev[k].p1, g_ev[k].text, g_ev[k].clr, g_ev[k].size, ANCHOR_LEFT_UPPER); labels++; }
      else if(g_ev[k].kind == 2) { BsObjText(nm, g_ev[k].t1, g_ev[k].p1, g_ev[k].text, g_ev[k].clr, g_ev[k].size, ANCHOR_LEFT_LOWER); labels++; }
      else if(g_ev[k].kind == 3) { BsObjBox(nm, g_ev[k].t1, g_ev[k].p1, g_ev[k].t2, g_ev[k].p2, g_ev[k].clr, g_ev[k].txt); boxes++; }
      else if(g_ev[k].kind == 4) { BsObjLine(nm, g_ev[k].t1, g_ev[k].p1, g_ev[k].t2, g_ev[k].p2, g_ev[k].clr, (int)g_ev[k].txt, g_ev[k].width, false); lines++; }
      else if(g_ev[k].kind == 5) BsObjArrow(nm, g_ev[k].t1, g_ev[k].p1, 233, g_ev[k].clr);
      else if(g_ev[k].kind == 6) BsObjArrow(nm, g_ev[k].t1, g_ev[k].p1, 234, g_ev[k].clr);
   }
   // SECTION 18 - EMA 20 / 50 as segments, swing triangles; session background as day-part rectangles
   int from = MathMax(1, g_n - 1 - MathMin(InpDrawBars, 150));
   if(InpShowEmas)
      for(int i = from; i < g_n; i++)
      {
         BsObjLine(BS_PREFIX + "E_ma20_" + FI(i), g_t[i - 1], g_ema20[i - 1], g_t[i], g_ema20[i], g_out.isUpTrend ? cGreen : cRed, STYLE_SOLID, 2, false);
         BsObjLine(BS_PREFIX + "E_ma50_" + FI(i), g_t[i - 1], g_ema50[i - 1], g_t[i], g_ema50[i], g_out.isUpTrend ? cLime : cMaroon, STYLE_SOLID, 1, false);
      }
   int length = (InpLength < 2) ? 2 : InpLength;
   int fromS = MathMax(2 * length, g_n - 1 - InpDrawBars);
   double pv = 0.0;
   for(int i = fromS; i < g_n - 1; i++)
   {
      if(BsPivotHigh(i, length, pv)) BsObjArrow(BS_PREFIX + "E_sh_" + FI(i), g_t[i - length], pv, 234, cRed);
      if(BsPivotLow(i, length, pv)) BsObjArrow(BS_PREFIX + "E_sl_" + FI(i), g_t[i - length], pv, 233, cGreen);
   }
   if(InpShowSessionBG)
   {
      double top = BsHighest(g_h, g_n - 1, g_n) * 1.02, bot = BsLowest(g_l, g_n - 1, g_n) * 0.98;
      int segStart = -1, segKind = 0, segN = 0;
      for(int i = MathMax(0, g_n - 1 - InpDrawBars); i <= g_n; i++)
      {
         int kind = 0;
         if(i < g_n)
         {
            datetime tNy = BsNyLocal(g_t[i]), tLon = BsLonLocal(g_t[i]), tTok = BsTokyoLocal(g_t[i]);
            bool inAsia = InpSessTzAware ? BsInWin(BsMod(tTok), BsHM(9, 0), BsHM(18, 0)) : false;
            bool inLon = InpSessTzAware ? BsInWin(BsMod(tLon), BsHM(8, 0), BsHM(17, 0)) : false;
            bool inNy = InpSessTzAware ? BsInWin(BsMod(tNy), BsHM(8, 0), BsHM(17, 0)) : false;
            kind = (inLon || inNy) ? 1 : (inAsia ? 2 : 0);
         }
         if(kind != segKind)
         {
            if(segKind != 0 && segStart >= 0)
               BsObjBox(BS_PREFIX + "E_sess_" + FI(segN++), g_t[segStart], top, BsBarT(i), bot, (segKind == 1) ? cSessGreen : cSessRed, (segKind == 1) ? cSessGreen : cSessRed);
            segStart = i; segKind = kind;
         }
      }
   }
}

// the live levels (redrawn on every tick, like barstate.islast blocks)
void BsDrawLive()
{
   BsOut o = g_out;
   if(InpShowPDHL) { BsLevel("pdh", o.pdHigh, "PDH", cRed, STYLE_DASH, 2, 100); BsLevel("pdl", o.pdLow, "PDL", cGreen, STYLE_DASH, 2, 100); }
   if(InpShowWeeklyHL) { BsLevel("wkh", o.wHigh, "WKH", cRed, STYLE_DOT, 1, 200); BsLevel("wkl", o.wLow, "WKL", cGreen, STYLE_DOT, 1, 200); }
   if(InpShowNWOG) BsLevel("nwog", o.nwogOpen, "NWOG", cPurple, STYLE_DASH, 2, 200);
   if(InpShowORG) { BsLevel("orgh", o.orgHigh, "ORG H:", cOrange, STYLE_DASH, 1, 100); BsLevel("orgl", o.orgLow, "ORG L:", cOrange, STYLE_DASH, 1, 100); }
   BsLevel("mid", o.midnightOpen, "Midnight Open", cAqua, STYLE_DOT, 1, 300);
   if(InpShowPivot)
   {
      BsLevel("pp", o.pivotP, "PP", cWhite, STYLE_DASH, 2, 50);
      BsLevel("r1", o.pivotR1, "R1", cRed, STYLE_DOT, 1, 50); BsLevel("r2", o.pivotR2, "R2", cRed, STYLE_DOT, 1, 50); BsLevel("r3", o.pivotR3, "R3", cRed, STYLE_DOT, 1, 50);
      BsLevel("s1", o.pivotS1, "S1", cGreen, STYLE_DOT, 1, 50); BsLevel("s2", o.pivotS2, "S2", cGreen, STYLE_DOT, 1, 50); BsLevel("s3", o.pivotS3, "S3", cGreen, STYLE_DOT, 1, 50);
   }
   if(!NA(o.equilLevel)) BsLevel("mid50", o.equilLevel, "50%", cOrange, STYLE_SOLID, 1, 3 * InpLength);
   int length = (InpLength < 2) ? 2 : InpLength;
   if(InpShowLiqZone && !NA(o.lastHigh) && !NA(o.lastLow))
   {
      double liqBuf = o.atrValue * InpLiqBuffer;
      BsObjBox(BS_PREFIX + "L_liqH", BsBarT(g_n - 1 - length * 3), o.lastHigh + liqBuf, BsBarT(g_n + 8), o.lastHigh, cFillRedD, cRed);
      BsObjBox(BS_PREFIX + "L_liqL", BsBarT(g_n - 1 - length * 3), o.lastLow, BsBarT(g_n + 8), o.lastLow - liqBuf, cFillGrnD, cGreen);
   }
   if(!NA(o.lastHigh) && !NA(o.lastLow))
      BsObjBox(BS_PREFIX + "L_swing", BsBarT(g_n - 1 - length * 3), o.lastHigh, BsBarT(g_n + 5), o.lastLow, cBlack, o.isUpTrend ? cGreen : cRed);
   if(InpShowAllLabels && InpShowTrendBox)
      BsObjText(BS_PREFIX + "L_trend", g_t[g_n - 1], g_h[g_n - 1], o.isUpTrend ? g_uUp + " UPTREND  HH / HL" : (o.isDownTrend ? g_uDn + " DOWNTREND  LH / LL" : g_uDoubleDash + " NO TREND"), o.isUpTrend ? cGreen : (o.isDownTrend ? cRed : cGray), 9, ANCHOR_LEFT_LOWER);
   // SMART SCALP lines while a signal is active (v18.9 A3: project forward only)
   string ids[4] = {"ssE", "ssSL", "ssT1", "ssT2"};
   if(InpSsShowLines && o.saActive && o.saBar >= 0)
   {
      double pxs[4]; pxs[0] = o.saEntry; pxs[1] = o.saSL; pxs[2] = o.saTP1; pxs[3] = o.saTP2;
      string txt[4] = {"E ", "SL ", "TP1 ", "TP2 "};
      color cl[4] = {cAmber, cNeonR, cNeonG, cNeonG};
      int wd[4] = {3, 3, 2, 3};
      for(int k = 0; k < 4; k++)
      {
         BsObjLine(BS_PREFIX + "L_" + ids[k], g_t[o.saBar], pxs[k], BsBarT(g_n + 40), pxs[k], cl[k], (k == 0) ? STYLE_SOLID : STYLE_DASH, wd[k], true);
         BsObjText(BS_PREFIX + "L_" + ids[k] + "t", BsBarT(g_n + 5), pxs[k], txt[k] + F4(pxs[k]), cl[k], 9, ANCHOR_LEFT);
      }
   }
   else
      for(int k = 0; k < 4; k++) { ObjectDelete(0, BS_PREFIX + "L_" + ids[k]); ObjectDelete(0, BS_PREFIX + "L_" + ids[k] + "t"); }
}

//=== DRAWING: the tables (every cell rewritten in place, like the v18.9 var tables) =====
int g_tblX, g_tblY, g_tblCols, g_tblColW[4], g_tblRowH;
string g_tblName;
int BsPx(int sz) { return sz; }   // text sizes are font pixel sizes here
int BsFontDash() { return (InpDashSizeMode == SZ_BIG) ? 11 : ((InpDashSizeMode == SZ_MEDIUM) ? 9 : 8); }
int BsFontDashTiny() { return (InpDashSizeMode == SZ_BIG) ? 9 : ((InpDashSizeMode == SZ_MEDIUM) ? 8 : 7); }
int BsFontBrain() { return (InpDashSizeMode == SZ_BIG) ? 14 : ((InpDashSizeMode == SZ_MEDIUM) ? 11 : 9); }
int BsFontBrainTiny() { return (InpDashSizeMode == SZ_BIG) ? 11 : ((InpDashSizeMode == SZ_MEDIUM) ? 9 : 8); }
void BsTable(string name, BS_POS pos, int cols, int w0, int w1, int w2, int rows, int rowH)
{
   g_tblName = name; g_tblCols = cols; g_tblColW[0] = w0; g_tblColW[1] = w1; g_tblColW[2] = w2; g_tblColW[3] = 0; g_tblRowH = rowH;
   int W = w0 + w1 + ((cols > 2) ? w2 : 0), H = rows * rowH;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS), ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int x = 6, y = 24;
   if(pos == P_TOP_CENTER || pos == P_MID_CENTER || pos == P_BOT_CENTER) x = (cw - W) / 2;
   if(pos == P_TOP_RIGHT || pos == P_MID_RIGHT || pos == P_BOT_RIGHT) x = cw - W - 60;
   if(pos == P_MID_LEFT || pos == P_MID_CENTER || pos == P_MID_RIGHT) y = (ch - H) / 2;
   if(pos == P_BOT_LEFT || pos == P_BOT_CENTER || pos == P_BOT_RIGHT) y = ch - H - 30;
   if(x < 0) x = 0;
   if(y < 0) y = 0;
   g_tblX = x; g_tblY = y;
   string bg = BS_PREFIX + "T_" + name + "_bg";
   if(ObjectFind(0, bg) < 0)
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x - 2);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y - 2);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, W + 4);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, H + 4);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, (name == "man") ? cManBg : cPanelBg);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, (name == "man") ? cCyan : cAmber);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bg, OBJPROP_ZORDER, 0);
}
void BsCell(int col, int row, string text, color txt, int px, color bg, bool hasBg)
{
   int x = g_tblX;
   for(int k = 0; k < col; k++) x += g_tblColW[k];
   int y = g_tblY + row * g_tblRowH;
   string base = BS_PREFIX + "T_" + g_tblName + "_" + FI(row) + "_" + FI(col);
   string nb = base + "b";
   if(hasBg)
   {
      if(ObjectFind(0, nb) < 0) ObjectCreate(0, nb, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nb, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nb, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, nb, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, nb, OBJPROP_XSIZE, g_tblColW[col] - 1);
      ObjectSetInteger(0, nb, OBJPROP_YSIZE, g_tblRowH - 1);
      ObjectSetInteger(0, nb, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, nb, OBJPROP_COLOR, bg);
      ObjectSetInteger(0, nb, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, nb, OBJPROP_BACK, false);
      ObjectSetInteger(0, nb, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nb, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nb, OBJPROP_ZORDER, 1);
   }
   else if(ObjectFind(0, nb) >= 0)
      ObjectDelete(0, nb);
   if(ObjectFind(0, base) < 0) ObjectCreate(0, base, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, base, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, base, OBJPROP_XDISTANCE, x + 3);
   ObjectSetInteger(0, base, OBJPROP_YDISTANCE, y + 2);
   ObjectSetString(0, base, OBJPROP_TEXT, text);
   ObjectSetString(0, base, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, base, OBJPROP_FONTSIZE, px);
   ObjectSetInteger(0, base, OBJPROP_COLOR, txt);
   ObjectSetInteger(0, base, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, base, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, base, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, base, OBJPROP_ZORDER, 2);
}
// the Pine's row helpers
void f_hdr(int r, string t0, string t1, string t2, color c0, color c1, color c2, color bg) { int px = BsFontDash(); BsCell(0, r, t0, c0, px, bg, true); BsCell(1, r, t1, c1, px, bg, true); BsCell(2, r, t2, c2, px, bg, true); }
void f_r3(int r, string t0, string t1, string t2, color c0, color c1, color c2) { int px = BsFontDash(); BsCell(0, r, t0, c0, px, cBlack, false); BsCell(1, r, t1, c1, px, cBlack, false); BsCell(2, r, t2, c2, px, cBlack, false); }
void f_row(int r, string c0, string c1, color clr, string c2) { f_r3(r, c0, c1, c2, cWhite, clr, cNote); }
void f_t3(int r, string t0, string t1, string t2, color c0, color c1, color c2) { int px = BsFontDashTiny(); BsCell(0, r, t0, c0, px, cBlack, false); BsCell(1, r, t1, c1, px, cBlack, false); BsCell(2, r, t2, c2, px, cBlack, false); }
void f_r3B(int r, string t0, string t1, string t2, color c0, color c1, color c2) { int px = BsFontBrain(); BsCell(0, r, t0, c0, px, cBlack, false); BsCell(1, r, t1, c1, px, cBlack, false); BsCell(2, r, t2, c2, px, cBlack, false); }
void f_t3B(int r, string t0, string t1, string t2, color c0, color c1, color c2) { int px = BsFontBrainTiny(); BsCell(0, r, t0, c0, px, cBlack, false); BsCell(1, r, t1, c1, px, cBlack, false); BsCell(2, r, t2, c2, px, cBlack, false); }
void f_b3B(int r, string t0, string t1, string t2, color c0, color c1, color c2, color bg) { int px = BsFontBrainTiny(); BsCell(0, r, t0, c0, px, bg, true); BsCell(1, r, t1, c1, px, bg, true); BsCell(2, r, t2, c2, px, bg, true); }
void f_m2(int r, string t0, string t1, color c1) { int px = BsFontDash(); BsCell(0, r, t0, cWhite, px, cBlack, false); BsCell(1, r, t1, c1, px, cBlack, false); }
void f_pvt(int r, string nm, double lvl)
{
   color bgP = (g_out.nearestPivotName == nm) ? 0x40A0A0 : 0x202020;
   color clrP = BsHas(nm, "R") ? cRed : (BsHas(nm, "S") ? cLime : cWhite);
   f_b3B(r, nm, FS(lvl), NA(lvl) ? g_uDoubleDash : F2(RoundTo(MathAbs(g_out.close - lvl), 2)), clrP, clrP, cNote, bgP);
}

// DASHBOARD 1 - MAIN (3 cols: metric | value | why), 54 rows
void BsDrawMain()
{
   BsOut o = g_out;
   int px = BsFontDash(), rh = px + 7, sc = (px * 100) / 8;
   BsTable("main", InpDashPos, 3, 90 * sc / 100, 120 * sc / 100, 265 * sc / 100, 54, rh);
   BsCell(0, 0, g_market, cWhite, px, cNavy, true);
   BsCell(1, 0, o.sessionTxt, cWhite, px, o.sessionClr, true);
   BsCell(2, 0, F2(o.close), cYellow, px, cNavy, true);
   f_hdr(1, "BIAS", o.biasDir, o.htfFullAgree ? "HTF aligned " + g_uOk : "HTF mixed", cWhite, o.biasClr, o.htfFullAgree ? cLime : cOrange, cNavy);
   f_r3(2, "Score BUY", o.scoreBuyTxt, o.buyVerdict, cWhite, o.scoreBuyClr, o.buyVerdictClr);
   f_r3(3, "Score SELL", o.scoreSellTxt, o.sellVerdict, cWhite, o.scoreSellClr, o.sellVerdictClr);
   f_r3(4, "Bull/Bear", FI(o.minFactorsBuy) + " bull", FI(o.minFactorsSell) + " bear", cWhite, o.minRuleBuyClr, o.minRuleSellClr);
   f_row(5, "Pattern", o.currentPatternTxt, o.currentPatternClr, o.isDoji ? "Indecision" : (o.insideBar ? "Consolidation" : "Active pattern"));
   f_hdr(6, g_uDoubleDash + " FILTERS " + g_uDoubleDash, "", "WHY?", cWhite, cWhite, cOrange, cNavy);
   f_row(7, "15m Trend", o.isUpTrend ? g_uUp + " UP" : (o.isDownTrend ? g_uDn + " DOWN" : g_uDoubleDash + " NONE"), o.isUpTrend ? cLime : (o.isDownTrend ? cRed : cGray), "STRUCT: " + o.structState + ((o.structState == "TRANSITION") ? " " + g_uWarn : ""));
   f_row(8, "H1 Trend", o.h1Bull ? g_uUp + " BULL" : (o.h1Bear ? g_uDn + " BEAR" : g_uDoubleDash + " MIX"), o.h1Bull ? cLime : (o.h1Bear ? cRed : cOrange), "H1 context");
   f_row(9, "H4 Trend", o.h4Bull ? g_uUp + " BULL" : (o.h4Bear ? g_uDn + " BEAR" : g_uDoubleDash + " MIX"), o.h4Bull ? cLime : (o.h4Bear ? cRed : cOrange), o.h4Bull ? "H4 safe to buy" : (o.h4Bear ? "H4 safe to sell" : "H4 conflict"));
   f_row(10, "Daily", o.dailyBull ? g_uUp + " BULL" : (o.dailyBear ? g_uDn + " BEAR" : g_uDoubleDash + " MIX"), o.dailyBull ? cLime : (o.dailyBear ? cRed : cOrange), "Big picture bias");
   f_row(11, "HTF Align", o.htfFullAgree ? g_uOk + " YES" : g_uNo + " NO", o.htfFullAgree ? cLime : cRed, "info - affects GRADE only, never blocks bot");
   f_hdr(12, g_uDoubleDash + " MOMENTUM " + g_uDoubleDash, "", "WHY?", cWhite, cWhite, cOrange, cNavy);
   string rsiTxt2 = (o.rsiValue > InpRsiOB) ? "OB " : ((o.rsiValue < InpRsiOS) ? "OS " : "OK ");
   f_row(13, "RSI", rsiTxt2 + FI(RoundI(o.rsiValue)), (o.rsiValue > InpRsiOB) ? cRed : ((o.rsiValue < InpRsiOS) ? cLime : cWhite), (o.rsiValue > InpRsiOB) ? "Overbought caution" : ((o.rsiValue < InpRsiOS) ? "Oversold - possible buy" : "Neutral, no pressure"));
   f_row(14, "Volume", o.volOk ? g_uOk + " OK" : g_uNo + " LOW", o.volOk ? cLime : cRed, "chart signals only - NEVER blocks bot");
   f_row(15, "ATR SL", F2(RoundTo(o.atrSL, 2)), cYellow, "Mkt avg move: " + F2(RoundTo(o.atrValue, 2)));
   f_row(16, "Trend Str", o.trendStrengthTxt + " ADX:" + FI(RoundI(o.adxVal)), o.trendStrengthClr, o.adxTrendStrong ? "Strong momentum" : (o.adxTrendModerate ? "Moderate push" : "Choppy - avoid"));
   f_row(17, "Risk $", "$" + F2(RoundTo(g_balance * InpRiskPct / 100.0, 2)), cYellow, "Max loss per trade");
   f_hdr(18, g_uDoubleDash + " SMART MONEY " + g_uDoubleDash, "", "WHY?", cWhite, cWhite, cOrange, cNavy);
   string srPctTxt = (o.nearSup && !NA(o.rangeLow) && o.rangeLow > 0) ? "+" + F2(RoundTo(((o.close - o.rangeLow) / o.close) * 100.0, 2)) + "% above"
                     : ((o.nearRes && !NA(o.rangeHigh) && o.rangeHigh > 0) ? F2(RoundTo(((o.close - o.rangeHigh) / o.close) * 100.0, 2)) + "% below"
                     : ((!NA(o.rangeHigh) && !NA(o.rangeLow) && o.rangeHigh > o.rangeLow) ? FI(RoundI(((o.close - o.rangeLow) / (o.rangeHigh - o.rangeLow)) * 100.0)) + "% in range" : "no S/R yet"));
   f_row(19, "Price Zone", o.nearSup ? "~ SUPPORT" : (o.nearRes ? "~ RESIST" : "~ MID"), o.nearSup ? cLime : (o.nearRes ? cRed : cOrange), srPctTxt);
   f_row(20, "Fib Zone", o.fibZoneTxt, o.fibZoneClr, o.inDiscount ? "Discount = buy zone" : (o.inPremium ? "Premium = sell zone" : "At equilibrium"));
   f_row(21, "CHoCH", o.chochTxt, o.chochClr, o.chochRecent ? "Structure reversed recently" : "No recent CHoCH");
   f_row(22, "Inducement", o.inducementTxt, o.inducementClr, o.bearInducement ? "Trap before DROP" : (o.bullInducement ? "Trap before RALLY" : "No trap detected"));
   f_row(23, "Liquidity", o.sweepTxt, o.sweepClr, o.equalHighs ? "Pool above - sweep risk" : (o.equalLows ? "Pool below - sweep risk" : "No pool nearby"));
   f_row(24, "FVG", o.fvgStatusTxt, o.fvgStatusClr, o.fvgPresent ? "Institutional imbalance" : "No active FVG");
   f_row(25, "OB Strength", o.lastOBtype, o.obStrengthClr, (o.obStatusTxt == "FRESH") ? "Fresh - not mitigated" : ((o.obStatusTxt == "MITIGATED") ? "Mitigated - weaker" : "No OB"));
   f_row(26, "Pivot Near", o.nearestPivotName + " " + FS(o.nearestPivotVal), o.atPivot ? cYellow : cWhite, o.abovePP ? "Above PP = bull bias" : "Below PP = bear bias");
   f_row(27, "EMA Cross", o.emaCross ? "20>50 BULL" : "20<50 BEAR", o.emaCross ? cLime : cRed, "EMA momentum direction");
   f_hdr(28, g_uDoubleDash + " EXECUTION " + g_uDoubleDash, "", "WHY?", cWhite, cWhite, cOrange, cNavy);
   BsCell(0, 29, "Session", cWhite, px, cBlack, false);
   BsCell(1, 29, o.sessionTxt, cWhite, px, o.sessionClr, true);
   BsCell(2, 29, (o.inLondon || o.inNewYork) ? "Active - trade allowed" : ((o.inAsia && InpFcAsiaScore) ? "Asia - scoring enabled" : "Off hours - avoid"), cNote, px, cBlack, false);
   f_row(30, "Volatility", o.volLevel, o.volLevelClr, (o.volLevel == "HIGH") ? "Big move expected" : "Normal conditions");
   f_row(31, "Range stress", o.spreadTxt, o.spreadClr, "3-bar range proxy - real spread lives in MT5");
   f_row(32, "R:R Quality", o.rrQuality, o.rrQualityClr, "R:R = 1:" + F1(InpRR));
   f_row(33, "Scalp", o.scalpTickBull ? g_uUp + " SC BUY" : (o.scalpTickBear ? g_uDn + " SC SELL" : g_uDash), o.scalpTickBull ? cLime : (o.scalpTickBear ? cRed : cGray), o.scalpTickBull ? "Momentum shift UP" : (o.scalpTickBear ? "Momentum shift DOWN" : "No scalp signal"));
   f_hdr(34, g_uDoubleDash + " SIGNAL " + g_uDoubleDash, "", "", cWhite, cWhite, cWhite, cNavy);
   f_hdr(35, "Signal", o.readyBuy ? g_uUp + " BUY READY" : (o.readySell ? g_uDn + " SELL READY" : g_uBullet + " WAIT"), o.sessionTrade ? "Session OK" : "Off hours", cWhite, o.readyBuy ? cLime : (o.readySell ? cRed : cOrange), cNote, cNavy);
   f_row(36, g_uUp + " Gate BUY", o.locBuyTxt, o.locBuyClr, o.buyZoneOK ? "@ " + o.buyZoneMem : "wait retest below");
   f_row(37, g_uDn + " Gate SELL", o.locSellTxt, o.locSellClr, o.sellZoneOK ? "@ " + o.sellZoneMem : "wait retest above");
   f_row(38, "Min 3/5 Buy", o.minRuleBuyTxt, o.minRuleBuyClr, "Trend+HTF+RSI+Vol+Zone");
   f_row(39, "Min 3/5 Sell", o.minRuleSellTxt, o.minRuleSellClr, "Trend+HTF+RSI+Vol+Zone");
   BsCell(0, 40, g_uBot + " BOT " + g_uUp + " BUY", cWhite, px, cNavy, true);
   BsCell(1, 40, o.botBC ? g_uFire + " FIRED" : "wait", o.botBC ? cLime : cGray, px, o.botBC ? cFillGrnD : cNavy, true);
   BsCell(2, 40, o.botBuyWhy, o.botBC ? cLime : cOrange, BsFontDashTiny(), cNavy, true);
   BsCell(0, 41, g_uBot + " BOT " + g_uDn + " SELL", cWhite, px, cNavy, true);
   BsCell(1, 41, o.botSC ? g_uFire + " FIRED" : "wait", o.botSC ? cRed : cGray, px, o.botSC ? cFillRedD : cNavy, true);
   BsCell(2, 41, o.botSellWhy, o.botSC ? cRed : cOrange, BsFontDashTiny(), cNavy, true);
   f_hdr(42, g_uDoubleDash + " v16 RISK " + g_uDoubleDash, "", "WHY?", cWhite, cWhite, cOrange, cMaroon);
   string gate = NqRiskGate();
   BsCell(0, 43, "Risk Gate", cWhite, px, cBlack, false);
   BsCell(1, 43, (gate == "") ? "OPEN" : gate, (gate == "") ? cLime : cRed, px, cNavy, true);
   BsCell(2, 43, "THIS EA enforces trades/day + daily loss on its own account (the Pine left it to the bot)", cNote, BsFontDashTiny(), cBlack, false);
   f_row(44, "Fires Today", FI(o.tradesToday) + " (this chart)", (o.tradesToday >= InpMaxTradesPerDay) ? cOrange : cLime, "fills: " + FI(g_tradesToday) + " / " + FI(InpMaxTradesPerDay) + " (EA count)");
   f_row(45, "Daily Loss", "-" + F1(InpMaxDailyLossPct) + "% cap", (g_dayPnl < 0) ? cOrange : cGray, "today " + F2(g_dayPnl) + " closed, " + F2(g_floating) + " floating (EA magic)");
   f_hdr(46, g_uDoubleDash + " NY PROTOCOL " + g_uDoubleDash, InpUseNYProtocol ? "ENABLED" : "OFF", "v18.3 regime-aware", cWhite, InpUseNYProtocol ? cLime : cGray, cNote, cPurple);
   f_row(47, "Killzone", o.inAnyNYKz ? o.kzLabel : g_uDash, o.kzClr, o.inAnyNYKz ? (o.atrPadActive ? "ATR pad active +" + F4(RoundTo(o.atrPad, 4)) : "no ATR pad") : "outside NY windows");
   f_row(48, "NY Regime", o.nyRegime, o.nyRegimeClr, (o.nyRegime == "TRAP") ? "metals/FX - watch for reversal" : ((o.nyRegime == "TREND") ? "indices - cash open drive" : "standard logic"));
   f_row(49, "Trap Detector", o.trapBias, o.trapBiasClr, o.trapDetail);
   f_row(50, "DXY Squelch", o.dxySqTxt, o.dxySqClr, o.dxySquelched ? "blocking new fires" : (InpUseDXYSquelch ? "1m: " + (g_dxyM1Has ? DoubleToString(RoundTo(g_dxyM1Pct, 3), 3) + "% (thr " + F2(InpDxySquelchPct) + "%)" : "no data") : "filter off"));
   f_hdr(51, g_uDoubleDash + " LOCATION GATE " + g_uDoubleDash, InpUseLocationGate ? "ENABLED" : "OFF", S("MODE: ") + ((InpLgMarketMode == MM_AUTO) ? "AUTO" : ((InpLgMarketMode == MM_RANGE) ? "RANGE" : "TREND")) + (o.trendDayOK ? " | TREND DAY" : ""), cWhite, InpUseLocationGate ? cLime : cGray, cNote, cTeal);
   f_row(52, "US 10Y Yield", o.yieldTxt, o.yieldClr, o.yieldRising ? "headwind for BUY" : (o.yieldFalling ? "tailwind for BUY" : "neutral"));
   f_row(53, "Adaptive", !InpUseAdaptive ? "OFF" : (o.inNewsWindow ? "NEWS WINDOW" : (o.volHigh ? "HIGH-VOL MODE" : "normal")), !InpUseAdaptive ? cGray : (o.inNewsWindow ? cOrange : (o.volHigh ? cRed : cLime)), !InpUseAdaptive ? "fixed v18.4 math" : (o.inNewsWindow ? "SL floor widened - no blocking" : (o.volHigh ? "zones tighter, SL floor wider" : "standard thresholds")));
}

// DASHBOARD 2 - STRUCTURAL BRAIN, 38 rows
string _pbSt(double e, string d) { return !InpPbEnable ? "OFF" : (NA(e) ? ((d != "") ? g_uCross + " " + d : "no setup") : "ARMED - waiting tap"); }
color  _pbStC(double e, string d) { return !InpPbEnable ? cGray : (NA(e) ? ((d != "") ? cOrange : cGray) : cOrange); }
void BsDrawBrain()
{
   BsOut o = g_out;
   int px = BsFontBrain(), rh = px + 7, sc = (px * 100) / 9;
   BsTable("pend", InpPendPos, 3, 110 * sc / 100, 170 * sc / 100, 170 * sc / 100, 38, rh);
   string pT = o.pendInvalid ? g_uWarn + " FORMING " + F1(o.pendRngA) + "/1.0 ATR - stops live below" : "STRUCTURAL BRAIN";
   BsCell(0, 0, pT, o.pendInvalid ? cOrange : cAmber, px, o.pendInvalid ? cFillRedD : cNavy, true);
   BsCell(1, 0, o.pendBrokeUp ? g_uDn + " SELL " + g_uWarn + " RANGE BROKEN" : (o.pendSellAtMkt ? g_uDn + " SELL " + g_uWarn + " LIMIT BELOW MKT" : g_uDn + " SELL LMT"), o.pendBrokeUp ? cGray : (o.pendSellAtMkt ? cOrange : cRed), px, o.pendBrokeUp ? cFillGray : (o.pendSellAtMkt ? cFillOrange : cFillRedD), true);
   BsCell(2, 0, o.pendBrokeDn ? g_uUp + " BUY " + g_uWarn + " RANGE BROKEN" : (o.pendBuyAtMkt ? g_uUp + " BUY " + g_uWarn + " LIMIT ABOVE MKT" : g_uUp + " BUY LMT"), o.pendBrokeDn ? cGray : (o.pendBuyAtMkt ? cOrange : cLime), px, o.pendBrokeDn ? cFillGray : (o.pendBuyAtMkt ? cFillOrange : cFillGrnD), true);
   string pendSellEtxt = o.hideEntries ? g_uWarn + " TIGHT" : FS(o.pendSellE), pendBuyEtxt = o.hideEntries ? g_uWarn + " TIGHT" : FS(o.pendBuyE);
   f_r3B(1, "Entry", pendSellEtxt, pendBuyEtxt, cWhite, (o.hideEntries || o.pendSellAtMkt) ? cOrange : cRed, (o.hideEntries || o.pendBuyAtMkt) ? cOrange : cLime);
   f_r3B(2, "Stop Loss", o.hideEntries ? g_uDash : FS(o.pendSellSL), o.hideEntries ? g_uDash : FS(o.pendBuySL), cWhite, cRed, cRed);
   f_r3B(3, "TP 1", o.hideEntries ? g_uDash : FS(o.pendSellTP1), o.hideEntries ? g_uDash : FS(o.pendBuyTP1), cWhite, cLime, cLime);
   f_r3B(4, "TP 2", o.hideEntries ? g_uDash : FS(o.pendSellTP2), o.hideEntries ? g_uDash : FS(o.pendBuyTP2), cWhite, cLime, cLime);
   f_r3B(5, "Lots (est)", o.hideEntries ? g_uDash : FS(o.pendLotsS), o.hideEntries ? g_uDash : FS(o.pendLotsB), cWhite, cYellow, cYellow);
   f_r3B(6, "R:R (ladder)", !NA(o.pendRRS) ? "1:" + F1(o.pendRRS) + ((o.pendRRS < 1) ? " " + g_uWarn : "") : g_uDoubleDash, !NA(o.pendRRB) ? "1:" + F1(o.pendRRB) + ((o.pendRRB < 1) ? " " + g_uWarn : "") : g_uDoubleDash, cWhite, (!NA(o.pendRRS) && o.pendRRS < 1) ? cRed : cWhite, (!NA(o.pendRRB) && o.pendRRB < 1) ? cRed : cWhite);
   f_t3B(7, "Distance", (!NA(o.distSell) && o.atrValue > 0) ? F2(o.distSell) + " (" + F1(o.distSell / o.atrValue) + " ATR)" : g_uDoubleDash, (!NA(o.distBuy) && o.atrValue > 0) ? F2(o.distBuy) + " (" + F1(o.distBuy / o.atrValue) + " ATR)" : g_uDoubleDash, cWhite, cOrange, cOrange);
   f_b3B(8, g_uDoubleDash + " STOP ORDERS " + g_uDoubleDash, g_uDn + " SELL STOP", g_uUp + " BUY STOP", cAmber, cRed, cLime, cNavy);
   f_r3B(9, "Trigger", FS(o.sellStopE), FS(o.buyStopE), cWhite, cRed, cLime);
   f_t3B(10, "Meaning", "range low breaks = momentum SELL", "range high breaks = momentum BUY", cWhite, cNote, cNote);
   f_b3B(11, g_uDoubleDash + " SESSIONS " + g_uDoubleDash, "HIGH", "LOW", cAmber, cNote, cNote, cNavy);
   f_t3B(12, o.inAsia ? "Asia " + g_uBullet : "Asia", FS(o.asiaH), FS(o.asiaL), o.inAsia ? cLime : cNote, cRed, cLime);
   f_t3B(13, o.inLondon ? "London " + g_uBullet : "London", FS(o.lonH), FS(o.lonL), o.inLondon ? cLime : cNote, cRed, cLime);
   f_t3B(14, o.inNewYork ? "NY " + g_uBullet : "NY", FS(o.nyH), FS(o.nyL), o.inNewYork ? cLime : cNote, cRed, cLime);
   f_b3B(15, g_uDoubleDash + " KEY LEVELS " + g_uDoubleDash, "Level", "Why it matters", cAmber, cNote, cNote, cNavy);
   f_t3B(16, "PDH", FS(o.pdHigh), "yesterday high - liquidity above", cWhite, cRed, cNote);
   f_t3B(17, "PDL", FS(o.pdLow), "yesterday low - liquidity below", cWhite, cLime, cNote);
   f_t3B(18, "NY Close", FS(o.nyCloseY), "yesterday close - day anchor", cWhite, cAqua, cNote);
   f_t3B(19, "NWOG", FS(o.nwogOpen), "week open gap - magnet level", cWhite, cPurple, cNote);
   f_t3B(20, "ORG High", FS(o.orgHigh), "NY 9:30 open range top", cWhite, cOrange, cNote);
   f_t3B(21, "ORG Low", FS(o.orgLow), "NY 9:30 open range bottom", cWhite, cOrange, cNote);
   f_t3B(22, "Midnight", FS(o.midnightOpen), "NY 00:00 open - ICT day bias", cWhite, cAqua, cNote);
   f_b3B(23, g_uDoubleDash + " MACRO " + g_uDoubleDash, "Reading", "Effect", cAmber, cNote, cNote, cNavy);
   f_t3B(24, "DXY", o.dxyTxt, o.isMetals ? (o.dxyRising ? "metals BEAR" : (o.dxyFalling ? "metals BULL" : "neutral")) : "n/a", cWhite, o.dxyClr, cNote);
   f_t3B(25, "Oil 1H", o.oilTxt, o.oilSpike ? "gold " + g_uArrUp + " likely" : "no risk-off", cWhite, o.oilClr, cNote);
   f_t3B(26, "ATR", o.atrExpTxt, o.atrExpand ? "moves bigger" : "moves normal", cWhite, o.atrExpClr, cNote);
   string sessPosNote = o.sessPctOk ? ((o.sessPct > 100) ? "ABOVE range - expansion" : ((o.sessPct < 0) ? "BELOW range - expansion" : ((o.sessPct > 70) ? "near high - sell zone" : ((o.sessPct < 30) ? "near low - buy zone" : "mid-range - wait")))) : "session starting";
   f_t3B(27, "Sess Pos", o.sessPctOk ? FI(RoundI(o.sessPct)) + "% of range" : g_uDoubleDash, sessPosNote, cWhite, cYellow, cNote);
   bool noRng = NA(o.pendRange);
   color tightClr = noRng ? cSilver : (o.rangeTooTight ? cWhite : cLime);
   color tightBg = noRng ? cFillGray : ((o.rangeTooTight && o.redWarn) ? cRed : (o.rangeTooTight ? cMaroon : (InpUseTightFilter ? cFillGrnD : cFillGray)));
   f_b3B(28, noRng ? g_uDash + " forming / no range" : (o.rangeTooTight ? g_uWarn + " TOO TIGHT - skip" : (InpUseTightFilter ? g_uOk + " Range OK" : "filter off")), o.rangeTightTxt, noRng ? "stop orders still live" : (o.rangeTooTight ? "no profit room" : "range > min"), tightClr, tightClr, tightClr, tightBg);
   f_b3B(29, "Level src (" + g_uDn + "|" + g_uUp + ")", o.pendHiSrcTxt, o.pendLoSrcTxt, cWhite, o.pendHiFromGate ? cAqua : o.tgtSourceClr, o.pendLoFromGate ? cAqua : o.tgtSourceClr, cNavy);
   f_b3B(30, g_uDoubleDash + " VWAP (v18.7) " + g_uDoubleDash, "Level", "Bias", cAmber, cNote, cNote, cNavy);
   f_t3B(31, "Daily VWAP", FS(o.dVwap), (o.vwapSide == "ABOVE") ? "price above - bull lean" : "price below - bear lean", cWhite, cAqua, (o.vwapSide == "ABOVE") ? cLime : cRed);
   f_t3B(32, "", "", "", cWhite, cWhite, cWhite);
   f_b3B(33, g_uDoubleDash + " PULLBACK (v18.7) " + g_uDoubleDash, g_uDn + " SELL", g_uUp + " BUY", cAmber, cRed, cLime, cNavy);
   f_t3B(34, "Status", _pbSt(o.pbSellE, o.pbSellDeath), _pbSt(o.pbBuyE, o.pbBuyDeath), cWhite, _pbStC(o.pbSellE, o.pbSellDeath), _pbStC(o.pbBuyE, o.pbBuyDeath));
   f_r3B(35, "Entry", FS(o.pbSellE), FS(o.pbBuyE), cWhite, cRed, cLime);
   f_r3B(36, "Stop (" + F1(InpPbSlAtr) + " ATR)", FS(NA(o.pbSellE) ? EMPTY_VALUE : o.pbSellSL), FS(NA(o.pbBuyE) ? EMPTY_VALUE : o.pbBuySL), cWhite, cRed, cRed);
   f_r3B(37, "TP1", FS(NA(o.pbSellE) ? EMPTY_VALUE : o.pbSellT1), FS(NA(o.pbBuyE) ? EMPTY_VALUE : o.pbBuyT1), cWhite, cLime, cLime);
}

// MANUAL TRADE MONITOR (2 cols, 9 rows) + PIVOT TABLE (3 cols, 10 rows)
void BsDrawManual()
{
   if(!InpShowManual) { ObjectsDeleteAll(0, BS_PREFIX + "T_man_"); return; }
   BsOut o = g_out;
   int px = BsFontDash(), rh = px + 7, sc = (px * 100) / 8;
   BsTable("man", InpManPos, 2, 120 * sc / 100, 190 * sc / 100, 0, 9, rh);
   color manClr = (o.manDir == "BUY") ? cLime : ((o.manDir == "SELL") ? cRed : cGray);
   BsCell(0, 0, g_uHand + " MANUAL MONITOR", cCyan, px, cManHd, true);
   BsCell(1, 0, o.manDir + (o.manCtr ? " " + g_uWarn + "CTR" : ""), o.manCtr ? cOrange : manClr, px, cManHd, true);
   f_m2(1, "Status", o.manStatus + (o.manCtr ? " - counter-trend" : ""), o.manCtr ? cOrange : o.manStatusClr);
   f_m2(2, "Market entry", FS(o.manMktE), cAqua);
   f_m2(3, "Pending entry", FS(o.manPendE), cOrange);
   f_m2(4, "Stop Loss", FS(o.manSL), cRed);
   f_m2(5, "TP 1", FS(o.manTP1), cLime);
   f_m2(6, "TP 2", FS(o.manTP2), cLime);
   f_m2(7, "R:R", "1:" + F1(o.manRR) + " (" + o.manMethod + ")", (o.manRR >= 1.5) ? cLime : cOrange);
   f_m2(8, "Gate", o.manGatePass ? (o.manCtr ? "PASS - counter-trend " + g_uWarn : "PASS - you can trade") : "wait", o.manGatePass ? (o.manCtr ? cOrange : cLime) : cGray);
}
void BsDrawPivot()
{
   BsOut o = g_out;
   int px = BsFontDash(), rh = BsFontBrainTiny() + 7, sc = (px * 100) / 8;
   BsTable("pvt", InpPvtPos, 3, 50 * sc / 100, 90 * sc / 100, 80 * sc / 100, 10, rh);
   BsCell(0, 0, "PIVOT", cWhite, px, cNavy, true); BsCell(1, 0, "Level", cWhite, px, cNavy, true); BsCell(2, 0, "Dist", cWhite, px, cNavy, true);
   f_pvt(1, "R3", o.pivotR3); f_pvt(2, "R2", o.pivotR2); f_pvt(3, "R1", o.pivotR1); f_pvt(4, "PP", o.pivotP); f_pvt(5, "S1", o.pivotS1); f_pvt(6, "S2", o.pivotS2); f_pvt(7, "S3", o.pivotS3);
   f_t3(8, "vs PP", o.abovePP ? "ABOVE PP" : "BELOW PP", F2(o.close), cWhite, o.abovePP ? cLime : cRed, cWhite);
   f_b3B(9, "Bias", o.abovePP ? g_uUp + " BULL BIAS" : g_uDn + " BEAR BIAS", o.nearestPivotName, cWhite, o.abovePP ? cLime : cRed, cYellow, cNavy);
}

// SMART SCALP - ACTIVE SIGNAL PANEL (2 cols, 12 rows)
void BsDrawSSPanel()
{
   if(!InpSsShowPanel) { ObjectsDeleteAll(0, BS_PREFIX + "T_ss_"); return; }
   BsOut o = g_out;
   int rh = 22;
   BsTable("ss", InpSsPanelPos, 2, 120, 175, 0, 12, rh);
   string modeT = (InpSsMode == SM_AGGRESSIVE) ? "Aggressive" : ((InpSsMode == SM_CONSERVATIVE) ? "Conservative" : "Balanced");
   BsCell(0, 0, g_uStar + " SMART SCALP " + modeT, cAmber, 9, cNavy, true);
   BsCell(1, 0, "", cAmber, 9, cNavy, true);
   bool showLive = o.saActive;
   color dirClr = !showLive ? cDim2 : ((o.saDir == "BUY") ? cNeonG : ((o.saDir == "SELL") ? cNeonR : cDim2));
   string dirTxt = !showLive ? "WAITING" : ((o.saDir == "BUY") ? g_uUp + " BUY" : ((o.saDir == "SELL") ? g_uDn + " SELL" : "WAITING"));
   bool firedConf = o.botBC || o.botSC;
   string statTxt = showLive ? g_uBullet + " LIVE" : (firedConf ? g_uStar + " FIRED" : ((o.saEndWhy != "") ? o.saEndWhy : "scanning"));
   color statClr = showLive ? cNeonG : (firedConf ? cAmber : ((o.saEndWhy == "TP2 HIT") ? cNeonG : ((o.saEndWhy == "SL HIT") ? cNeonR : cDim)));
   color grdClr = !showLive ? cDim2 : ((o.saGrade == "A+") ? cAqua : ((o.saGrade == "A") ? cNeonG : ((o.saGrade == "B") ? cAmber : ((o.saGrade == "C") ? cOrange2 : ((o.saGrade == "D") ? cNeonR : cDim2)))));
   string grdShow = showLive ? o.saGrade : g_uDash;
   string grdNote = (grdShow == "A+") ? "best" : ((grdShow == "A") ? "strong" : ((grdShow == "B") ? "good" : ((grdShow == "C") ? "ok" : ((grdShow == "D") ? "weak" : ""))));
   int barsAgo = (o.saBar >= 0) ? (g_n - 1 - o.saBar) : 0;
   string ageTxt = (showLive && barsAgo > 0) ? FI(barsAgo) + " bars" : (showLive ? "now" : g_uDash);
   string rrShow = (showLive && !NA(o.saRR)) ? "1:" + F2(o.saRR) : g_uDash;
   color rrClr = (showLive && !NA(o.saRR) && o.saRR >= 2.5) ? cNeonG : ((showLive && !NA(o.saRR) && o.saRR >= 1.8) ? cAmber : cNeonR);
   string rrNote = (showLive && !NA(o.saRR) && o.saRR >= 2.5) ? "good" : ((showLive && !NA(o.saRR) && o.saRR >= 1.8) ? "ok" : (showLive ? "low" : ""));
   string scoreTxt = showLive ? FI(o.saScore) + "/10  " + F2(o.saLots) + " lots" : "Buy " + FI(o.scoreBuy) + " Sell " + FI(o.scoreSell);
   BsCell(0, 1, dirTxt, dirClr, 14, cBlack, false);
   BsCell(1, 1, statTxt, statClr, 11, cBlack, false);
   BsCell(0, 2, "ENTRY", cWhite, 9, cNavy, true); BsCell(1, 2, (showLive && !NA(o.saEntry)) ? F4(o.saEntry) : g_uDash, cAmber, 11, cBlack, false);
   BsCell(0, 3, "STOP LOSS", cWhite, 9, cNavy, true); BsCell(1, 3, (showLive && !NA(o.saSL)) ? F4(o.saSL) : g_uDash, cNeonR, 11, cBlack, false);
   BsCell(0, 4, "TP 1", cWhite, 9, cNavy, true); BsCell(1, 4, (showLive && !NA(o.saTP1)) ? F4(o.saTP1) : g_uDash, cNeonG, 11, cBlack, false);
   BsCell(0, 5, "TP 2", cWhite, 9, cNavy, true); BsCell(1, 5, (showLive && !NA(o.saTP2)) ? F4(o.saTP2) : g_uDash, cNeonG, 11, cBlack, false);
   BsCell(0, 6, "GRADE", cWhite, 9, cNavy, true); BsCell(1, 6, grdShow + " " + grdNote, grdClr, 11, cBlack, false);
   BsCell(0, 7, "R:R", cWhite, 9, cNavy, true); BsCell(1, 7, rrShow + " " + rrNote, rrClr, 11, cBlack, false);
   BsCell(0, 8, "Score|Lots", cAqua, 8, cNavy, true); BsCell(1, 8, scoreTxt, cAmber, 9, cBlack, false);
   BsCell(0, 9, "Now", cDim, 8, cNavy, true); BsCell(1, 9, F4(o.close), cAqua, 9, cBlack, false);
   BsCell(0, 10, "Age", cDim, 8, cNavy, true); BsCell(1, 10, ageTxt + " " + o.sessionTxt, cAqua, 8, cBlack, false);
   bool pcConf = o.manDir != "NONE" && o.saDir != "NONE" && o.saBar >= 0 && (g_n - 1 - o.saBar) <= 16 && o.manDir != o.saDir;
   BsCell(0, 11, pcConf ? g_uWarn + " CONFLICT" : "Panels", pcConf ? cWhite : cDim3, 9, pcConf ? cRed : cNavy, true);
   BsCell(1, 11, pcConf ? "Scalp " + o.saDir + " vs Manual " + o.manDir : "agree / idle", pcConf ? cYellow : cDim3, 9, cBlack, false);
}
void BsDrawAll(bool newBar)
{
   if(newBar)
      BsDrawEvents();
   BsDrawLive();
   BsDrawMain();
   BsDrawBrain();
   BsDrawManual();
   BsDrawPivot();
   BsDrawSSPanel();
   ChartRedraw(0);
}

//=== JOURNAL: file + SignalMesh (ANALYSIS side; never the brain's signal path) ======
string BsStamp(datetime t)
{
   int y = 0, m = 0, d = 0;
   BsCivil(t, y, m, d);
   int mod = BsMod(t);
   return IntegerToString(y, 4, '0') + IntegerToString(m, 2, '0') + IntegerToString(d, 2, '0') + IntegerToString(mod / 60, 2, '0') + IntegerToString(mod % 60, 2, '0') + "00";
}
void NqJournalWrite(string line)
{
   if(!InpJournalToFile)
      return;
   string name = "BS18_events_" + g_sym + ".jsonl";
   int h = FileOpen(name, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
   {
      if(!g_jrFileWarned)
         Print("BS18 journal: cannot open MQL5/Files/" + name);
      g_jrFileWarned = true;
      return;
   }
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, line + "\n");
   FileClose(h);
}
bool NqPost(string url, string json)
{
   if(url == "")
      return true;
   char data[];
   StringToCharArray(json, data, 0, StringLen(json), CP_UTF8);
   char result[];
   string resultHeaders = "";
   string headers = "Content-Type: application/json\r\n";
   if(g_webSecret != "")
      headers = headers + "X-Brain-Secret: " + g_webSecret + "\r\n";
   int code = WebRequest("POST", url, headers, 3000, data, result, resultHeaders);
   return (code >= 200 && code < 300);
}
void NqWebFlush()
{
   if(g_webUrl == "" || g_webN <= 0)
      return;
   datetime now = TimeTradeServer();
   if(g_webFails > 0 && now - g_webLast < MathMin(300, 5 * g_webFails))
      return;
   g_webLast = now;
   if(!NqPost(g_webUrl, g_webQ[0]))
   {
      g_webFails++;
      if(g_webFails == 1 || g_webFails % 50 == 0)
         Print("BS18 journal: SignalMesh POST failed (" + FI(g_webFails) + " in a row) - queued " + FI(g_webN));
      return;
   }
   g_webFails = 0;
   for(int i = 1; i < g_webN; i++)
      g_webQ[i - 1] = g_webQ[i];
   g_webN--;
   ArrayResize(g_webQ, g_webN);
}
void BsEmit(string json)
{
   NqJournalWrite(json);
   if(g_webUrl == "")
      return;
   if(g_webN >= 500)
      return;
   ArrayResize(g_webQ, g_webN + 1, 32);
   g_webQ[g_webN] = json;
   g_webN++;
   NqWebFlush();
}
// one event line: the Pine's SMART_SCALP / PULLBACK payload fields (append-only contract) + the EA's status words
string BsEventJson(string type, string sigId, string dir, double entry, double sl, double tp1, double tp2, double rr, string grade,
                   string event, string status, string extra)
{
   BsOut o = g_out;
   string j = "{" + NqJsonS("system", "BS-MT5") + "," + NqJsonS("kind", "event") + "," + NqJsonS("type", type) + "," +
              NqJsonS("signal", dir) + "," + NqJsonS("direction", dir) + "," + NqJsonS("signal_id", sigId) + "," +
              NqJsonS("symbol", g_sym) + "," + NqJsonS("tf", FI(g_periodSec / 60)) + "," +
              NqJsonN("entry", entry, g_digits) + "," + NqJsonN("sl", sl, g_digits) + "," + NqJsonN("tp", tp1, g_digits) + "," +
              NqJsonN("tp1", tp1, g_digits) + "," + NqJsonN("tp2", tp2, g_digits) + "," + NqJsonN("rr", rr, 2) + "," + NqJsonS("grade", grade) + "," +
              NqJsonS("trend", o.isUpTrend ? "UP" : (o.isDownTrend ? "DOWN" : "NONE")) + "," + NqJsonB("htf_align", (o.isUpTrend && o.h1Bull && o.h4Bull) || (o.isDownTrend && o.h1Bear && o.h4Bear)) + "," +
              NqJsonS("session", o.sessionTxt) + "," + NqJsonB("news_window", o.inNewsWindow) + "," + NqJsonS("vwap_side", o.vwapSide) + "," +
              NqJsonS("pine_ver", "18.12") + "," + NqJsonI("payload_schema", 2) + "," + NqJsonI("fired_at", (long)TimeTradeServer()) + "," +
              NqJsonI("trend_age", o.trendAge) + "," + NqJsonI("trades_today", g_tradesToday) + "," + NqJsonS("struct", o.structState) + "," +
              NqJsonS("choch", o.chochTxt) + "," + NqJsonS("inducement", o.inducementTxt) + "," + NqJsonS("sweep", o.sweepTxt) + "," + NqJsonS("zone", o.fibZoneTxt) + "," +
              NqJsonI("rsi", RoundI(o.rsiValue)) + "," + NqJsonI("adx", RoundI(o.adxVal)) + "," + NqJsonS("ny_regime", o.nyRegime) + "," +
              NqJsonS("vol_regime", o.volLevel) + "," + NqJsonS("dxy_dir", o.dxyTxt) + "," + NqJsonS("yield_dir", o.yieldTxt) + "," +
              NqJsonS("event", event) + "," + NqJsonS("status", status) + "," + NqJsonS("outcome", "") + "," +
              NqJsonS("account_mode", g_isDemo ? "demo" : "real") + "," + NqJsonI("magic", InpMagic) + "," + NqJsonS("ea_version", BS_VERSION) + "," +
              NqJsonI("ts", (long)TimeTradeServer());
   if(extra != "")
      j = j + "," + extra;
   return j + "}";
}

//=== THE TRADE LAYER ==============================================================
bool g_tradeAllowedNow;
string NqRiskGate()
{
   if(!g_tradeAllowedNow)
      return "ALGO TRADING OFF";
   if(!g_isDemo && !InpAllowRealAccount)
      return "REAL ACCOUNT (input off)";
   if(InpMaxOpenPositions > 0 && g_openCount >= InpMaxOpenPositions)
      return "MAX POSITIONS " + FI(g_openCount);
   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
      return "MAX TRADES/DAY " + FI(g_tradesToday);
   if(InpMaxDailyLossPct > 0 && g_balance > 0 && (g_dayPnl + g_floating) <= -g_balance * InpMaxDailyLossPct / 100.0)
      return "DAILY LOSS CAP";
   if(g_market == "UNKNOWN")
      return "UNKNOWN SYMBOL";
   return "";
}
bool BsIsOurs(long magic, string sym) { return magic == InpMagic && sym == g_sym; }
bool NqSend(MqlTradeRequest &req, string why)
{
   MqlTradeResult res;
   ZeroMemory(res);
   bool ok = OrderSend(req, res);
   bool done = ok && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED);
   string what = "";
   if(req.action == TRADE_ACTION_DEAL)
      what = "MARKET " + ((req.type == ORDER_TYPE_BUY) ? S("BUY ") : S("SELL ")) + F2(req.volume);
   else if(req.action == TRADE_ACTION_PENDING)
      what = ((req.type == ORDER_TYPE_BUY_LIMIT) ? S("BUY LIMIT ") : S("SELL LIMIT ")) + F2(req.volume) + " @ " + FD(req.price);
   else if(req.action == TRADE_ACTION_REMOVE)
      what = "CANCEL #" + IntegerToString((long)req.order);
   Print("BS18 " + what + " SL " + FD(req.sl) + " TP " + FD(req.tp) + " | " + why + " | " + (done ? S("OK") : S("REJECTED")) + " retcode " + IntegerToString((long)res.retcode) +
         ((res.order != 0) ? (" order " + IntegerToString((long)res.order)) : S("")));
   g_note = (done ? S("SENT: ") : S("REJECTED: ")) + what;
   return done;
}
void BsScanAccount()
{
   g_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_openCount = 0; g_pendCount = 0; g_floating = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(!BsIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL))) continue;
      g_openCount++;
      g_floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(!BsIsOurs(OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL))) continue;
      g_pendCount++;
   }
   // today's closed result + fills (this EA's magic), on the New York calendar day
   datetime nowS = TimeTradeServer();
   long dayKey = BsDayKey(BsNyLocal(nowS));
   datetime dayStart = (datetime)((long)nowS - ((long)BsNyLocal(nowS) % 86400 + 86400) % 86400);
   g_dayPnl = 0.0; g_tradesToday = 0;
   if(HistorySelect(dayStart, nowS + 86400))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong dk = HistoryDealGetTicket(i);
         if(dk == 0) continue;
         if(!BsIsOurs(HistoryDealGetInteger(dk, DEAL_MAGIC), HistoryDealGetString(dk, DEAL_SYMBOL))) continue;
         long entry = HistoryDealGetInteger(dk, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN) g_tradesToday++;
         else g_dayPnl += HistoryDealGetDouble(dk, DEAL_PROFIT) + HistoryDealGetDouble(dk, DEAL_COMMISSION) + HistoryDealGetDouble(dk, DEAL_SWAP);
      }
   }
   g_dayKeyTrades = (int)dayKey;
   g_tradeAllowedNow = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 && MQLInfoInteger(MQL_TRADE_ALLOWED) != 0 &&
                        AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0 && AccountInfoInteger(ACCOUNT_TRADE_EXPERT) != 0);
}
bool BsStopsLegal(int dir, double px, double sl, double tp)
{
   double minDist = g_stopsLevel * g_point;
   if(dir > 0) return (sl < px - minDist) && (tp > px + minDist);
   return (sl > px + minDist) && (tp < px - minDist);
}
bool BsMarketOrder(int dir, double lots, double sl, double tp, string cmt, string why)
{
   MqlTradeRequest req;
   ZeroMemory(req);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = g_sym;
   req.magic = InpMagic;
   req.volume = lots;
   req.type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price = (dir > 0) ? SymbolInfoDouble(g_sym, SYMBOL_ASK) : SymbolInfoDouble(g_sym, SYMBOL_BID);
   req.sl = sl;
   req.tp = tp;
   req.deviation = InpSlippagePoints;
   req.type_filling = (ENUM_ORDER_TYPE_FILLING)g_fill;
   req.comment = cmt;
   return NqSend(req, why);
}
bool BsLimitOrder(int dir, double lots, double price, double sl, double tp, string cmt, string why)
{
   MqlTradeRequest req;
   ZeroMemory(req);
   req.action = TRADE_ACTION_PENDING;
   req.symbol = g_sym;
   req.magic = InpMagic;
   req.volume = lots;
   req.type = (dir > 0) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   req.price = price;
   req.sl = sl;
   req.tp = tp;
   req.type_filling = ORDER_FILLING_RETURN;
   req.type_time = ORDER_TIME_GTC;
   req.comment = cmt;
   return NqSend(req, why);
}
bool BsCancel(ulong ticket, string why)
{
   MqlTradeRequest req;
   ZeroMemory(req);
   req.action = TRADE_ACTION_REMOVE;
   req.order = ticket;
   return NqSend(req, why);
}
bool BsClosePosition(ulong ticket, string why)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   MqlTradeRequest req;
   ZeroMemory(req);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = g_sym;
   req.magic = InpMagic;
   req.position = ticket;
   req.volume = PositionGetDouble(POSITION_VOLUME);
   bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   req.type = isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price = isBuy ? SymbolInfoDouble(g_sym, SYMBOL_BID) : SymbolInfoDouble(g_sym, SYMBOL_ASK);
   req.deviation = InpSlippagePoints;
   req.type_filling = (ENUM_ORDER_TYPE_FILLING)g_fill;
   req.comment = "BS18 close";
   return NqSend(req, why);
}
// a resting PULLBACK order of ours (comment "BS18-PB-BUY-<arm stamp>" / "BS18-PB-SELL-<arm stamp>")
ulong BsFindPbOrder(int dir, string &cmtOut)
{
   string want = (dir > 0) ? "BS18-PB-BUY-" : "BS18-PB-SELL-";
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(!BsIsOurs(OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL))) continue;
      string c = OrderGetString(ORDER_COMMENT);
      if(StringFind(c, want) == 0) { cmtOut = c; return tk; }
   }
   cmtOut = "";
   return 0;
}


void BsTrade(bool newBar)
{
   if(g_n < 3)
      return;
   datetime confirmedT = g_t[g_n - 2];
   string gate = NqRiskGate();
   bool canTrade = (gate == "");
   // 1) SMART SCALP: the fire of the just-closed bar, acted on once
   if(newBar && g_fire.bar == confirmedT && (g_fire.ssBuy || g_fire.ssSell) && g_lastFireBar != confirmedT)
   {
      g_lastFireBar = confirmedT;
      int dir = g_fire.ssBuy ? 1 : -1;
      string sid = (dir > 0 ? S("SS-BUY-") : S("SS-SELL-")) + BsStamp(BsGmt(confirmedT));
      string dirT = (dir > 0) ? "BUY" : "SELL";
      double sl = BsRoundTick(g_fire.ssSL, 0), tp1 = BsRoundTick(g_fire.ssTP1, 0), tp2 = BsRoundTick(g_fire.ssTP2, 0);
      double px = (dir > 0) ? SymbolInfoDouble(g_sym, SYMBOL_ASK) : SymbolInfoDouble(g_sym, SYMBOL_BID);
      double lots = BsLots(MathAbs(px - sl));
      BsEmit(BsEventJson("SMART_SCALP", sid, dirT, g_fire.ssEntry, g_fire.ssSL, g_fire.ssTP1, g_fire.ssTP2, g_fire.ssRR, g_fire.ssGrade, "fired", "pending",
                         NqJsonI("score", g_fire.ssScore) + "," + NqJsonN("lots", lots, 2) + "," + NqJsonS("gate", gate)));
      if(!canTrade)
         Print("BS18 SMART SCALP " + dirT + " fired but the risk gate says " + gate + " - not sent");
      else if(lots <= 0.0 || !BsStopsLegal(dir, px, sl, tp1))
      {
         Print("BS18 SMART SCALP " + dirT + " fired but lot " + F2(lots) + " / stops not legal - not sent");
         BsEmit(BsEventJson("SMART_SCALP", sid, dirT, px, sl, tp1, tp2, g_fire.ssRR, g_fire.ssGrade, "rejected", "cancelled", NqJsonS("reason", "lot or stops")));
      }
      else
      {
         bool sent = false;
         if(InpSplitTp2 && lots >= 2 * g_volMin)
         {
            double half = MathFloor(lots / 2.0 / g_volStep + 1e-9) * g_volStep;
            sent = BsMarketOrder(dir, half, sl, tp1, sid + "-1", "SMART SCALP " + dirT + " grade " + g_fire.ssGrade + " TP1");
            sent = BsMarketOrder(dir, half, sl, tp2, sid + "-2", "SMART SCALP " + dirT + " grade " + g_fire.ssGrade + " TP2") || sent;
         }
         else
            sent = BsMarketOrder(dir, lots, sl, tp1, sid, "SMART SCALP " + dirT + " grade " + g_fire.ssGrade + " score " + FI(g_fire.ssScore) + " R:R " + F2(g_fire.ssRR));
         BsEmit(BsEventJson("SMART_SCALP", sid, dirT, px, sl, tp1, tp2, g_fire.ssRR, g_fire.ssGrade, sent ? "executed" : "rejected", sent ? "executed" : "cancelled",
                            NqJsonN("lots", lots, 2) + "," + NqJsonN("price", px, g_digits)));
      }
   }
   // 2) PULLBACK: ONE resting limit per side mirrors the ARMED level; pulled when the arm dies or a live guard blocks
   for(int side = 0; side < 2; side++)
   {
      int dir = (side == 0) ? 1 : -1;
      double e = (dir > 0) ? g_fire.armBuyE : g_fire.armSellE;
      double sl = (dir > 0) ? g_fire.armBuySL : g_fire.armSellSL;
      double t1 = (dir > 0) ? g_fire.armBuyT1 : g_fire.armSellT1;
      double t2 = (dir > 0) ? g_fire.armBuyT2 : g_fire.armSellT2;
      datetime armT = (dir > 0) ? g_fire.armBuyT : g_fire.armSellT;
      string cmt = "";
      ulong tk = BsFindPbOrder(dir, cmt);
      string wantCmt = (dir > 0 ? S("BS18-PB-BUY-") : S("BS18-PB-SELL-")) + FI((int)((long)armT % 100000000));
      bool alive = FEATURE_PULLBACK && InpPbEnable && InpSsEnable && !NA(e) && g_symbolAllowed && g_fire.pbCoolOK && g_fire.pbHrOK && !g_fire.squelched && !g_fire.newsBlock && canTrade;
      string dirT = (dir > 0) ? "BUY" : "SELL";
      if(tk != 0 && (!alive || cmt != wantCmt))
      {
         string why = NA(e) ? ((dir > 0) ? g_out.pbBuyDeath : g_out.pbSellDeath) : (g_fire.squelched ? S("DXY squelch") : (g_fire.newsBlock ? S("news window") : (!canTrade ? gate : S("re-armed"))));
         if(BsCancel(tk, "PULLBACK " + dirT + " pulled: " + why))
            BsEmit(BsEventJson("PULLBACK", "PB-" + dirT + "-" + StringSubstr(cmt, 12), dirT, e, sl, t1, t2, 0.0, "", "cancelled", "cancelled", NqJsonS("reason", why)));
         tk = 0;
      }
      if(tk == 0 && alive && newBar)
      {
         double price = BsRoundTick(e, 0), slR = BsRoundTick(sl, 0), tpR = BsRoundTick(t1, 0);
         double px = (dir > 0) ? SymbolInfoDouble(g_sym, SYMBOL_ASK) : SymbolInfoDouble(g_sym, SYMBOL_BID);
         bool onSide = (dir > 0) ? (price < px - g_stopsLevel * g_point) : (price > px + g_stopsLevel * g_point);
         double lots = BsLots(MathAbs(price - slR));
         double rr = (MathAbs(price - slR) > 0) ? MathAbs(tpR - price) / MathAbs(price - slR) : 0.0;
         if(onSide && lots > 0.0 && BsStopsLegal(dir, price, slR, tpR))
         {
            string sid = "PB-" + dirT + "-" + StringSubstr(wantCmt, 12);
            bool sent = BsLimitOrder(dir, lots, price, slR, tpR, wantCmt, "PULLBACK " + dirT + " armed at " + ((dir > 0) ? g_out.pbBuySrc : g_out.pbSellSrc) + " grade " + (g_fire.pbAln ? S("A") : S("B")));
            BsEmit(BsEventJson("PULLBACK", sid, dirT, price, slR, tpR, BsRoundTick(t2, 0), rr, g_fire.pbAln ? "A" : "B", sent ? "placed" : "rejected", sent ? "pending" : "cancelled",
                               NqJsonN("lots", lots, 2) + "," + NqJsonS("level_src", (dir > 0) ? g_out.pbBuySrc : g_out.pbSellSrc)));
         }
      }
   }
   // 3) a SMART SCALP position against a flipped 15m trend (the panel's own 'trend flip' retirement), when asked
   if(InpCloseOnFlip && newBar)
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !PositionSelectByTicket(tk)) continue;
         if(!BsIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL))) continue;
         string c = PositionGetString(POSITION_COMMENT);
         if(StringFind(c, "SS-") != 0) continue;
         bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         if((isBuy && g_out.isDownTrend) || (!isBuy && g_out.isUpTrend))
            if(BsClosePosition(tk, "SMART SCALP trend flip against the position"))
               BsEmit(BsEventJson("SMART_SCALP", c, isBuy ? "BUY" : "SELL", PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL), PositionGetDouble(POSITION_TP), 0.0, 0.0, "", "closed", "closed", NqJsonS("reason", "trend flip")));
      }
}

//=== EVENTS =========================================================================
int OnInit()
{
   g_sym = _Symbol;
   g_ticker = g_sym;
   StringToUpper(g_ticker);
   g_digits = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   g_tick = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   if(g_tick <= 0.0)
      g_tick = g_point;
   g_volMin = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   g_volMax = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   g_volStep = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   if(g_volStep <= 0.0)
      g_volStep = g_volMin;
   g_stopsLevel = (int)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL);
   long fm = SymbolInfoInteger(g_sym, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK) != 0) g_fill = (int)ORDER_FILLING_FOK;
   else if((fm & SYMBOL_FILLING_IOC) != 0) g_fill = (int)ORDER_FILLING_IOC;
   else g_fill = (int)ORDER_FILLING_RETURN;
   g_isDemo = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO);
   g_periodSec = PeriodSeconds(_Period);
   if(g_periodSec <= 0)
      g_periodSec = 300;
   g_intraday = (g_periodSec < 86400);
   g_srvOff = (long)TimeTradeServer() - (long)TimeGMT();
   // the Pine's glyphs (UTF-16 code points; the source stays pure ASCII)
   g_uUp = U(0x25B2); g_uDn = U(0x25BC); g_uArrUp = U(0x2191); g_uArrDn = U(0x2193); g_uWarn = U(0x26A0); g_uOk = U(0x2714); g_uNo = U(0x2718);
   g_uStar = U(0x2605); g_uDot = U(0x25CF); g_uDash = U(0x2014); g_uCross = U(0x271D); g_uBullet = U(0x25CF); g_uFire = U(0x2605); g_uBot = U(0x263A); g_uHand = U(0x270B);
   g_uDoubleDash = U(0x2500) + U(0x2500);
   g_market = (InpMarketType == MK_AUTO) ? BsAutoMarket() : BsMarketName(InpMarketType);
   g_pipZone = BsPipZoneOf(g_market);
   g_symbolAllowed = BsSymbolAllowed();
   g_dxySym = BsResolve(InpDxySymbol, "USDX,DXY,USDOLLAR,DX,USDIDX,USIDX,DOLLAR,USDINDEX,USDOLLARINDEX");
   g_yldSym = InpUseYieldMacro ? BsResolve(InpYieldSymbol, "US10Y,USTNOTE10,TNOTE,US10YT,UST10Y,USNOTE10,US10,ZN,TY") : "";
   g_oilSym = BsResolve(InpOilSymbol, "USOIL,WTI,XTIUSD,CRUDE,OIL,CL,USOUSD,WTIUSD,UKOIL,BRENT,XBRUSD");
   g_squelchUntil = 0;
   g_lastFireBar = 0; g_lastPbBar = 0; g_drawnBar = 0; g_nEv = 0; g_note = "";
   g_webUrl = InpSignalMeshUrl;
   g_webSecret = InpSignalMeshSecret;
   if(g_webSecret == "")
   {
      g_webUrl = "";
      if(InpSignalMeshUrl != "")
         Print("BS18 SignalMesh: the secret input is empty - journal POSTs are OFF until you set it (the address is preset)");
   }
   ArrayResize(g_webQ, 0); g_webN = 0; g_webLast = 0; g_webFails = 0; g_jrFileWarned = false; g_webWarned = false;
   ZeroMemory(g_fire);
   g_fire.armBuyE = EMPTY_VALUE; g_fire.armSellE = EMPTY_VALUE;
   if(InpHistoryBars < 300 || InpHistoryBars > 5000 || InpRiskPct <= 0.0 || InpRiskPct > 5.0 || InpLength < 2 || InpLength > 20 || InpFcThreshold < 4 || InpFcThreshold > 9)
   {
      Print("BS18: an input is out of range (history 300-5000, risk 0-5%, swing length 2-20, score threshold 4-9)");
      return INIT_PARAMETERS_INCORRECT;
   }
   Print(S("BS18 ") + BS_VERSION + " on " + g_sym + " (" + g_market + ", pipZone " + DoubleToString(g_pipZone, 4) + ") " + (g_isDemo ? S("DEMO") : S("REAL")) +
         "  DXY " + ((g_dxySym == "") ? S("none") : g_dxySym) + "  yield " + ((g_yldSym == "") ? S("none") : g_yldSym) + "  oil " + ((g_oilSym == "") ? S("none") : g_oilSym) +
         "  whitelist " + (g_symbolAllowed ? S("PASS") : S("BLOCKED")));
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, BS_PREFIX);
   ChartRedraw(0);
}
void BsUpdate(bool force)
{
   if(!BsLoadWindow())
      return;
   bool newBar = (g_t[g_n - 1] != g_drawnBar);
   g_srvOff = (long)TimeTradeServer() - (long)TimeGMT();
   if(newBar || force)
      BsLoadHtf();
   BsBaseIndicators();
   BsDxySquelchScan();
   BsScanAccount();
   BsPass(newBar || force);
   BsTrade(newBar);
   BsDrawAll(newBar || force);
   if(newBar)
      g_drawnBar = g_t[g_n - 1];
}
void OnTick()
{
   BsUpdate(false);
}
void OnTimer()
{
   NqWebFlush();
}
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
      BsUpdate(true);
}
