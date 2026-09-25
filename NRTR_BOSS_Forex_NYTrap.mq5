//+------------------------------------------------------------------+
//|                                        NRTR_BOSS_Forex_NYTrap.mq5 |
//|      Crypto / Forex learning panel with the NY-open trap module   |
//|                                                                  |
//|  15M = BOSS / DIRECTION   (NRTR + EMA200 + confirmed structure)  |
//|   5M = ENTRY TRIGGER      (NRTR + CLOSED confirmation candle)    |
//|  NY  = THE WILDLIFE       (pre-NY range, sweep, reclaim = trap)  |
//|                                                                  |
//|  Outside the NY window the panel follows structure: the 15M     |
//|  boss decides the side, a closed 5M candle times the entry.      |
//|  Inside the NY window (default: first 90 min after the New York  |
//|  open) structure signals are PAUSED and only one setup exists:   |
//|  price takes out the pre-NY range and a 5M candle CLOSES back    |
//|  inside against the sweep. That is the "everything looked        |
//|  bullish at the open and then it sold" pattern, defined as a     |
//|  rule so it can be counted instead of remembered.                |
//|                                                                  |
//|  VISUAL ONLY. This indicator never sends, modifies or closes an  |
//|  order or position. It may READ open positions on this symbol to |
//|  show EXIT / PROTECT advice; it never changes the account.       |
//|  (MT5 also blocks trade functions inside indicators by design.)  |
//|                                                                  |
//|  "CLICK BUY" means: the defined conditions are currently aligned |
//|  for the educational setup. It is NOT a profit guarantee.        |
//|                                                                  |
//|  The market this file accepts is fixed by NB_MARKET below. The   |
//|  crypto twin and the forex twin are otherwise the same text.     |
//|                                                                  |
//|  Personal tool. No network, no Telegram, no external executor.   |
//|                                                                  |
//|  FROZEN DEFINITIONS (v1.01, audit of blob f95f970). Changing any |
//|  of these is a NEW versioned behaviour, never a silent edit:     |
//|  * NRTR = CUSTOM ATR-NRTR on CLOSES: extreme = highest (lowest)  |
//|    close since the flip, stop = extreme -/+ mult*ATR(Wilder),    |
//|    ratchets only, flips on a CLOSE beyond the stop. This is NOT  |
//|    guaranteed to match any MT5 CodeBase "NRTR" bar for bar; the  |
//|    panel is labelled CUSTOM ATR-NRTR for that reason.            |
//|  * EXIT / PROTECT uses the COMPLETE 15M BOSS mode (NRTR + EMA200 |
//|    + confirmed structure), never the NRTR direction alone:       |
//|      BUY  + BOSS BUY  = HOLD      SELL + BOSS SELL = HOLD        |
//|      BUY  + BOSS SELL = EXIT      SELL + BOSS BUY  = EXIT        |
//|      any  + BOSS WAIT = UNKNOWN / PROTECT (no automatic EXIT)    |
//|      stale or missing 15M data = UNKNOWN                         |
//|  * SAME-CANDLE RULE: if one closed 5M candle after the entry     |
//|    touches both the SL and TP1, the SL wins (tick order is not   |
//|    available). Conservative by design.                           |
//|  * TP invariant: TP2 R-multiple is strictly greater than TP1's.  |
//|                                                                  |
//|  v1.02 DISPLAY additions (no new decision rule, still read-only):|
//|  * an UP / DOWN arrow on EVERY closed candle = NRTR direction of  |
//|    the chart's own timeframe class (5M on M1-M5 charts, 15M      |
//|    above). Bright = agrees with the 15M boss mode, dim = not.    |
//|  * the CLICK BUY / CLICK SELL banner blinks (a light, not a      |
//|    button - the click is still yours on the broker's panel).    |
//|  * SWING TP = entry +/- a distance (typed, or automatic = N x    |
//|    15M ATR in the twins) and pending-order REFERENCE prices      |
//|    (pullback limit at the 5M NRTR stop, breakout stop at the 15M |
//|    NRTR channel edge). Reference only, nothing is sent.          |
//|  * NEW YORK OPEN: one MT5 pop-up + sound at the open the SESSION |
//|    CLOCK computes (twins), and the NY window on the panel.       |
//|  * ZigZag: confirmed 15M swings are joined by a line.            |
//|  v1.03: arrows only on NRTR FLIP candles (every-candle = option),|
//|    a yellow PREVIEW on the forming candle (what would happen if  |
//|    it closed now - never stored, never a decision input), and a  |
//|    two-column LIVE BOX (BUY | SELL plan + GATE) from the same    |
//|    engine functions. Still display only, still read-only.        |
//|  v1.04 FRESHNESS (found live on XAGUSD, Asia open): the old rule  |
//|    "last closed 15M bar <= 30 min old" is false for the first 15  |
//|    minutes after the broker's 00:00-01:00 metals break although   |
//|    fresh 5M candles print. Freshness is now judged by WITNESSES:  |
//|    (1) the broker's last tick is recent, (2) the FORMING 5M and   |
//|    15M bars are current, (3) tick clock and server clock agree,   |
//|    (4) the closed bars are the newest ones MT5 has closed. Any    |
//|    failing witness = STALE / UNKNOWN (fail closed). A DATA CLOCK   |
//|    block on the panel shows every witness. Gate policy unchanged. |
//|  * LOTS FOR x% RISK: balance (read only) x risk% / money per lot |
//|    at the SL, rounded DOWN to the volume step. A suggestion you  |
//|    type yourself; the panel never sizes or sends anything.       |
//|  TWINS (this file): the NY-open trap module (session clock from  |
//|    two witnesses, pre-NY range, sweep + reclaim = trap, flow     |
//|    paused in the window) and a LAST 5 CANDLES strip per TF.      |
//+------------------------------------------------------------------+
#property copyright   "Personal use - learning tool"
#property version     "1.04"
#property description "Forex NRTR BOSS learning panel: 15M direction, 5M timing, NY-open trap. CUSTOM ATR-NRTR."
#property description "EURUSD USDJPY GBPUSD and the other pairs of USD EUR GBP JPY CHF AUD NZD CAD ..."
#property description "Visual decision support only - never places, modifies or closes orders."
#property indicator_chart_window
#property indicator_buffers 10
#property indicator_plots   6
#property indicator_label1  "15M EMA200"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_label2  "15M NRTR stop"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_color2  clrLimeGreen,clrTomato
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2
#property indicator_label3  "15M NRTR extreme"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrSilver
#property indicator_style3  STYLE_DOT
#property indicator_width3  1
#property indicator_label4  "5M NRTR stop"
#property indicator_type4   DRAW_COLOR_LINE
#property indicator_color4  clrMediumSeaGreen,clrIndianRed
#property indicator_style4  STYLE_DOT
#property indicator_width4  1
#property indicator_label5  "Candle arrow UP (bright = with 15M boss)"
#property indicator_type5   DRAW_COLOR_ARROW
#property indicator_color5  clrLime,clrDarkGreen
#property indicator_width5  1
#property indicator_label6  "Candle arrow DOWN (bright = with 15M boss)"
#property indicator_type6   DRAW_COLOR_ARROW
#property indicator_color6  clrRed,clrMaroon
#property indicator_width6  1

//=== NB_ENGINE_BEGIN ===
//+------------------------------------------------------------------+
//| ENGINE                                                           |
//| Pure calculation, no terminal calls. Every array is in time      |
//| order (index 0 = oldest) and holds CLOSED bars only. Every loop  |
//| is causal: the value at bar i uses bars 0..i and nothing later,  |
//| so a historical state can never change when new bars arrive.     |
//| This block is written in the subset of MQL5 that is also valid   |
//| C++ so the test suite compiles and runs this exact text.         |
//+------------------------------------------------------------------+

// markets a twin file can be built for
#define NB_MKT_CRYPTO 1
#define NB_MKT_FOREX  2
// THE ONLY CODE LINE THAT DIFFERS BETWEEN THE TWO TWIN FILES
#define NB_MARKET NB_MKT_FOREX

// decision / trade direction
#define NB_WAIT   0
#define NB_BUY    1
#define NB_SELL  -1
#define NB_EXIT   2

// 15M structure state
#define NB_ST_UNKNOWN 0
#define NB_ST_BULL    1
#define NB_ST_BEAR    2
#define NB_ST_MIXED   3

// swing labels
#define NB_L_NONE 0
#define NB_L_HH   1
#define NB_L_LH   2
#define NB_L_EQH  3
#define NB_L_HL   4
#define NB_L_LL   5
#define NB_L_EQL  6

// reason bits (why the panel is not showing CLICK BUY / CLICK SELL)
#define NB_R_NRTR15_NOT_READY 0x1
#define NB_R_EMA_NOT_READY    0x2
#define NB_R_STRUCT_UNCONF    0x4
#define NB_R_STRUCT_MIXED     0x8
#define NB_R_NRTR_CONFLICT    0x10
#define NB_R_EMA_CONFLICT     0x20
#define NB_R_STRUCT_CONFLICT  0x40
#define NB_R_EMA_FLAT         0x80
#define NB_R_NO_15M_BAR       0x100
#define NB_R_5M_NOT_READY     0x200
#define NB_R_5M_AGAINST       0x400
#define NB_R_5M_WAIT_CANDLE   0x800
#define NB_R_5M_NO_STOP       0x1000
#define NB_R_SIG_EXPIRED      0x2000
#define NB_R_SIG_TP1          0x4000
#define NB_R_SIG_SL           0x8000
#define NB_R_CANDLE_OPEN      0x10000
#define NB_R_STALE            0x20000
#define NB_R_NO_DATA          0x40000
#define NB_R_UNSUPPORTED      0x80000
#define NB_R_NY_WINDOW        0x100000
#define NB_R_NY_NO_RANGE      0x200000
#define NB_R_COUNT            22

// learning-signal outcome
#define NB_SIG_ACTIVE    1
#define NB_SIG_EXPIRED   2
#define NB_SIG_TP1       3
#define NB_SIG_SL        4
#define NB_SIG_CANCELLED 5

// learning-signal kind
#define NB_K_FLOW 0     // structure flow: 15M boss + 5M trigger
#define NB_K_TRAP 1     // NY-open sweep of the pre-NY range + close back inside

// session phase of a 5M bar
#define NB_PH_OUT 0     // outside: structure flow
#define NB_PH_PRE 1     // pre-NY range is being built
#define NB_PH_NY  2     // NY window: the wildlife

// session clock mode
#define NB_CLK_AUTO   0 // broker clock vs PC clock + the US DST calendar
#define NB_CLK_MANUAL 1 // NY open typed in broker server time

// position advice
#define NB_ADV_NONE    0
#define NB_ADV_HOLD    1
#define NB_ADV_EXIT    2
#define NB_ADV_UNKNOWN 3
#define NB_WHY_NONE        0
#define NB_WHY_INVALIDATED 1
#define NB_WHY_AGAINST     2
#define NB_WHY_INTACT      3
#define NB_WHY_UNKNOWN     4
#define NB_WHY_BOSS_WAIT   5

// the structural SL looks back at most this many 5M bars (5 hours)
#define NB_SL_SEARCH_BARS 60

struct NbParams
{
   int      atrPeriod;
   double   nrtrMult;
   int      emaPeriod;
   int      swing;
   double   slBufAtr;
   double   tp1R;
   double   tp2R;
   int      validBars;
   double   tick;
   int      digits;
};

// NY session configuration (all explicit user decisions, nothing inferred)
struct NbSessCfg
{
   int      clockMode;     // NB_CLK_*
   bool     clockOk;       // false = the session module is OFF (never guessed)
   long     offset;        // broker server time - UTC, seconds (AUTO)
   int      manualOpenSec; // NY open as seconds of the server day (MANUAL)
   int      preHours;      // pre-NY range length, hours before the open
   int      winMin;        // NY window length, minutes after the open
   int      minRangeBars;  // closed 5M bars the pre-NY range needs to count
   bool     pauseFlow;     // pause structure-flow signals inside the window
};

struct NbPivot
{
   int      idx;          // bar of the swing
   int      confirmIdx;   // first bar at whose CLOSE the swing is known (idx + swing)
   int      kind;         // +1 swing high, -1 swing low
   double   price;
   int      label;        // NB_L_*
};

struct NbSignal
{
   int      idx;          // 5M bar whose close triggered it
   int      dir;          // NB_BUY / NB_SELL
   int      kind;         // NB_K_FLOW / NB_K_TRAP
   double   entry;
   double   sl;
   double   tp1;
   double   tp2;
   double   risk;
   int      status;       // NB_SIG_*
   int      statusIdx;
   int      swingIdx;     // pivot used for the SL (flow)
   double   level;        // pre-NY range level that was swept (trap)
   double   sweep;        // extreme of the sweep, the SL base (trap)
};

struct NbSeries
{
   int      n;
   int      sec;
   int      np;
   datetime t[];
   double   o[];
   double   h[];
   double   l[];
   double   c[];
   double   atr[];
   double   ema[];
   int      dir[];
   double   stop[];
   double   ext[];
   int      flip[];
   int      st[];
   int      hl[];
   int      ll[];
   int      lk[];
   int      mode[];
   int      mr[];
   int      map[];
   int      boss[];
   int      bossR[];
   int      state[];
   int      reasons[];
   int      sigOf[];
   int      ph[];         // session phase per bar
   long     sid[];        // session id per bar (-1 = none)
   double   rh[];         // pre-NY range high known at this bar (0 = none)
   double   rl[];         // pre-NY range low
   int      rn[];         // closed 5M bars in the pre-NY range
   double   swH[];        // highest high above the range so far in the window (0 = no sweep)
   double   swL[];        // lowest low below the range so far in the window (0 = no sweep)
};

void NbSeriesResize(NbSeries &s, int n)
{
   s.n = n;
   s.np = 0;
   ArrayResize(s.t, n);
   ArrayResize(s.o, n);
   ArrayResize(s.h, n);
   ArrayResize(s.l, n);
   ArrayResize(s.c, n);
}

//--- input contract. TP2 must be STRICTLY beyond TP1 (else the BUY/SELL level
//    invariants SL < Entry < TP1 < TP2 and TP2 < TP1 < Entry < SL cannot hold).
bool NbParamsValid(const NbParams &P)
{
   if(P.atrPeriod < 1 || P.nrtrMult <= 0.0 || P.emaPeriod < 2)
      return false;
   if(P.swing < 1 || P.swing > 20 || P.slBufAtr < 0.0)
      return false;
   if(P.tp1R <= 0.0 || P.tp2R <= 0.0 || P.tp2R <= P.tp1R)
      return false;
   if(P.validBars < 1)
      return false;
   return true;
}

//--- position size for a fixed % of balance at risk. REFERENCE ONLY.
//    lots = (balance * risk%) / (risk in ticks * tick value), rounded DOWN
//    to the volume step, clamped to [volMin, volMax]. Returns 0.0 when even
//    the minimum lot risks more than allowed (the panel then says so).
//    moneyAtRisk = what the returned lots actually risk at the SL.
double NbLotsForRisk(double balance, double riskPct, double riskPrice, double tick, double tickValue,
                     double volMin, double volStep, double volMax, double &moneyAtRisk)
{
   moneyAtRisk = 0.0;
   if(balance <= 0.0 || riskPct <= 0.0 || riskPrice <= 0.0 || tick <= 0.0 || tickValue <= 0.0 || volMin <= 0.0)
      return 0.0;
   double perLot = riskPrice / tick * tickValue;     // money lost per 1.00 lot at the SL
   if(perLot <= 0.0)
      return 0.0;
   double budget = balance * riskPct / 100.0;
   double lots = budget / perLot;
   if(volStep > 0.0)
      lots = MathFloor(lots / volStep + 1e-9) * volStep;
   if(volMax > 0.0 && lots > volMax)
      lots = volMax;
   if(lots < volMin - 1e-9)
      return 0.0;
   lots = NormalizeDouble(lots, 2);
   moneyAtRisk = lots * perLot;
   return lots;
}

//--- price grid: round to the symbol's real tick size (mode -1 down, +1 up, 0 nearest)
double NbRoundTick(double price, double tick, int digits, int mode)
{
   if(tick <= 0.0)
      return NormalizeDouble(price, digits);
   double q = price / tick;
   double r = 0.0;
   if(mode < 0)
      r = MathFloor(q + 1e-7);
   else if(mode > 0)
      r = MathCeil(q - 1e-7);
   else
      r = MathRound(q);
   return NormalizeDouble(r * tick, digits);
}

//--- Wilder ATR. 0.0 = not ready.
void NbCalcATR(const double &h[], const double &l[], const double &c[], int n, int period, double &atr[])
{
   ArrayResize(atr, n);
   if(period < 1)
      period = 1;
   double sum = 0.0;
   for(int i = 0; i < n; i++)
   {
      double tr = h[i] - l[i];
      if(i > 0)
         tr = MathMax(tr, MathMax(MathAbs(h[i] - c[i - 1]), MathAbs(l[i] - c[i - 1])));
      if(i < period)
      {
         sum += tr;
         atr[i] = (i == period - 1) ? sum / period : 0.0;
      }
      else
         atr[i] = (atr[i - 1] * (period - 1) + tr) / period;
   }
}

//--- EMA seeded with the SMA of the first `period` closes. 0.0 = not ready.
void NbCalcEMA(const double &c[], int n, int period, double &ema[])
{
   ArrayResize(ema, n);
   if(period < 1)
      period = 1;
   double a = 2.0 / (period + 1.0);
   double sum = 0.0;
   for(int i = 0; i < n; i++)
   {
      if(i < period)
      {
         sum += c[i];
         ema[i] = (i == period - 1) ? sum / period : 0.0;
      }
      else
         ema[i] = ema[i - 1] + a * (c[i] - ema[i - 1]);
   }
}

//--- CUSTOM ATR-NRTR (FROZEN DEFINITION - see the file header).
//    Nick Rypock Trailing Reverse idea, but ATR-scaled and computed on
//    CLOSES only. This is the exact algorithm this file implements:
//      seed:    not ready (dir 0) until the closes span >= k*ATR; the side
//               nearer the current close becomes the first direction.
//      bullish: extreme = highest CLOSE since the flip,
//               stop = extreme - k*ATR(Wilder, atrPeriod), ratchets UP only;
//               a CLOSE < stop flips bearish on that bar (flip[i] = -1) and
//               the new extreme is that close.
//      bearish: mirror (stop ratchets DOWN only, CLOSE > stop flips, +1).
//    It does NOT use highs/lows, a dynamic look-back period or a percentage
//    band, so it is NOT guaranteed to reproduce any MT5 CodeBase NRTR bar
//    for bar (direction, flip bar or line value). The panel says
//    CUSTOM ATR-NRTR for that reason. dir 0 = not ready (never guessed).
void NbCalcNRTR(const double &c[], const double &atr[], int n, double k,
                int &dir[], double &stop[], double &ext[], int &flip[])
{
   ArrayResize(dir, n);
   ArrayResize(stop, n);
   ArrayResize(ext, n);
   ArrayResize(flip, n);
   int d = 0;
   double e = 0.0;
   double st = 0.0;
   double hiC = 0.0;
   double loC = 0.0;
   bool seeded = false;
   for(int i = 0; i < n; i++)
   {
      flip[i] = 0;
      if(atr[i] <= 0.0 || k <= 0.0)
      {
         dir[i] = d;
         stop[i] = (d != 0) ? st : 0.0;
         ext[i] = (d != 0) ? e : 0.0;
         continue;
      }
      double band = k * atr[i];
      if(d == 0)
      {
         if(!seeded)
         {
            hiC = c[i];
            loC = c[i];
            seeded = true;
         }
         if(c[i] > hiC)
            hiC = c[i];
         if(c[i] < loC)
            loC = c[i];
         if(hiC - loC >= band)
         {
            if(c[i] - loC >= hiC - c[i])
            {
               d = 1;
               e = hiC;
               st = e - band;
            }
            else
            {
               d = -1;
               e = loC;
               st = e + band;
            }
         }
      }
      else if(d > 0)
      {
         if(c[i] > e)
            e = c[i];
         double cand = e - band;
         if(cand > st)
            st = cand;
         if(c[i] < st)
         {
            d = -1;
            e = c[i];
            st = e + band;
            flip[i] = -1;
         }
      }
      else
      {
         if(c[i] < e)
            e = c[i];
         double cand = e + band;
         if(cand < st)
            st = cand;
         if(c[i] > st)
         {
            d = 1;
            e = c[i];
            st = e - band;
            flip[i] = 1;
         }
      }
      dir[i] = d;
      stop[i] = (d != 0) ? st : 0.0;
      ext[i] = (d != 0) ? e : 0.0;
   }
}

//--- NRTR channel for display: upper = bearish stop or bullish extreme,
//    lower = bullish stop or bearish extreme.
double NbNrtrUpper(int d, double stop, double ext)
{
   if(d > 0)
      return ext;
   if(d < 0)
      return stop;
   return 0.0;
}

double NbNrtrLower(int d, double stop, double ext)
{
   if(d > 0)
      return stop;
   if(d < 0)
      return ext;
   return 0.0;
}

int NbLabelSwing(int kind, double price, bool havePrev, double prev)
{
   if(!havePrev)
      return NB_L_NONE;
   if(kind > 0)
   {
      if(price > prev)
         return NB_L_HH;
      if(price < prev)
         return NB_L_LH;
      return NB_L_EQH;
   }
   if(price > prev)
      return NB_L_HL;
   if(price < prev)
      return NB_L_LL;
   return NB_L_EQL;
}

//--- Confirmed swings only. A swing at bar j needs `s` bars on each side and
//    is KNOWN only at the close of bar j+s (confirmIdx). Until then it does
//    not exist - the forming side of a ZigZag is never used.
int NbFindPivots(const double &h[], const double &l[], int n, int s, NbPivot &piv[])
{
   ArrayResize(piv, 0);
   if(s < 1)
      s = 1;
   int np = 0;
   bool haveH = false;
   bool haveL = false;
   double lastH = 0.0;
   double lastL = 0.0;
   for(int j = s; j + s < n; j++)
   {
      bool isH = true;
      bool isL = true;
      for(int k = 1; k <= s; k++)
      {
         if(!(h[j] > h[j - k]) || !(h[j] >= h[j + k]))
            isH = false;
         if(!(l[j] < l[j - k]) || !(l[j] <= l[j + k]))
            isL = false;
      }
      if(isH)
      {
         ArrayResize(piv, np + 1, 256);
         piv[np].idx = j;
         piv[np].confirmIdx = j + s;
         piv[np].kind = 1;
         piv[np].price = h[j];
         piv[np].label = NbLabelSwing(1, h[j], haveH, lastH);
         np++;
         haveH = true;
         lastH = h[j];
      }
      if(isL)
      {
         ArrayResize(piv, np + 1, 256);
         piv[np].idx = j;
         piv[np].confirmIdx = j + s;
         piv[np].kind = -1;
         piv[np].price = l[j];
         piv[np].label = NbLabelSwing(-1, l[j], haveL, lastL);
         np++;
         haveL = true;
         lastL = l[j];
      }
   }
   return np;
}

//--- Structure known at the close of every bar, from confirmed swings only.
//    BULL = last high HH and last low HL. BEAR = LH and LL.
//    Fewer than two highs or two lows = UNKNOWN (never guessed).
void NbStructureSeries(const NbPivot &piv[], int np, int n, int &st[], int &hl[], int &ll[], int &lk[])
{
   ArrayResize(st, n);
   ArrayResize(hl, n);
   ArrayResize(ll, n);
   ArrayResize(lk, n);
   int p = 0;
   int curH = NB_L_NONE;
   int curL = NB_L_NONE;
   int curK = 0;
   for(int t = 0; t < n; t++)
   {
      while(p < np && piv[p].confirmIdx <= t)
      {
         if(piv[p].kind > 0)
            curH = piv[p].label;
         else
            curL = piv[p].label;
         curK = piv[p].kind;
         p++;
      }
      hl[t] = curH;
      ll[t] = curL;
      lk[t] = curK;
      if(curH == NB_L_NONE || curL == NB_L_NONE)
         st[t] = NB_ST_UNKNOWN;
      else if(curH == NB_L_HH && curL == NB_L_HL)
         st[t] = NB_ST_BULL;
      else if(curH == NB_L_LH && curL == NB_L_LL)
         st[t] = NB_ST_BEAR;
      else
         st[t] = NB_ST_MIXED;
   }
}

//--- 15M BOSS decision for one closed 15M bar.
int NbBossDecision(int nrtrDir, double close, double ema, int st, int &reasons)
{
   reasons = 0;
   if(nrtrDir == 0)
      reasons |= NB_R_NRTR15_NOT_READY;
   if(ema <= 0.0)
      reasons |= NB_R_EMA_NOT_READY;
   if(st == NB_ST_UNKNOWN)
      reasons |= NB_R_STRUCT_UNCONF;
   if(st == NB_ST_MIXED)
      reasons |= NB_R_STRUCT_MIXED;

   int emaDir = 0;
   if(ema > 0.0)
   {
      if(close > ema)
         emaDir = 1;
      else if(close < ema)
         emaDir = -1;
   }
   int sDir = 0;
   if(st == NB_ST_BULL)
      sDir = 1;
   if(st == NB_ST_BEAR)
      sDir = -1;

   if(reasons == 0 && nrtrDir == 1 && emaDir == 1 && sDir == 1)
      return NB_BUY;
   if(reasons == 0 && nrtrDir == -1 && emaDir == -1 && sDir == -1)
      return NB_SELL;

   if(ema > 0.0 && emaDir == 0)
      reasons |= NB_R_EMA_FLAT;
   bool nrtrOdd = false;
   if(nrtrDir != 0 && emaDir != 0 && sDir != 0 && emaDir == sDir && nrtrDir != emaDir)
   {
      reasons |= NB_R_NRTR_CONFLICT;
      nrtrOdd = true;
   }
   if(!nrtrOdd)
   {
      if(nrtrDir != 0 && emaDir != 0 && emaDir != nrtrDir)
         reasons |= NB_R_EMA_CONFLICT;
      if(nrtrDir != 0 && sDir != 0 && sDir != nrtrDir)
         reasons |= NB_R_STRUCT_CONFLICT;
   }
   if(reasons == 0)
      reasons = NB_R_NO_DATA;
   return NB_WAIT;
}

//--- map[j] = last bar of A that had CLOSED when bar j of B closed (-1 = none).
//    This is what stops a 15M bar that is still forming from leaking into a
//    historical 5M decision.
void NbAlign(const datetime &tA[], int nA, int secA, const datetime &tB[], int nB, int secB, int &map[])
{
   ArrayResize(map, nB);
   int i = -1;
   for(int j = 0; j < nB; j++)
   {
      while(i + 1 < nA && tA[i + 1] + secA <= tB[j] + secB)
         i++;
      map[j] = i;
   }
}

//--- most recent confirmed 5M swing on the protective side of the entry
int NbFindStopSwing(const NbPivot &piv[], int np, int s, int dir, double entry, int maxAge, double &price)
{
   for(int p = np - 1; p >= 0; p--)
   {
      if(piv[p].confirmIdx > s)
         continue;
      if(s - piv[p].idx > maxAge)
         break;
      if(dir > 0 && piv[p].kind < 0 && piv[p].price < entry)
      {
         price = piv[p].price;
         return p;
      }
      if(dir < 0 && piv[p].kind > 0 && piv[p].price > entry)
      {
         price = piv[p].price;
         return p;
      }
   }
   return -1;
}

//--- hypothetical plan for ONE side at closed 5M bar s, from the same rules
//    the trigger uses (entry = close, SL = confirmed protective swing -/+
//    buffer, TP = R multiples). Display only: the GATE decides, not this.
bool NbPlanSide(const double &c[], const double &atr5[], const NbPivot &piv[], int np, int s, int dir,
                const NbParams &P, double &entry, double &sl, double &tp1, double &tp2, double &risk)
{
   entry = 0.0;
   sl = 0.0;
   tp1 = 0.0;
   tp2 = 0.0;
   risk = 0.0;
   if(s < 0 || dir == 0 || atr5[s] <= 0.0)
      return false;
   double swing = 0.0;
   int sp = NbFindStopSwing(piv, np, s, dir, c[s], NB_SL_SEARCH_BARS, swing);
   if(sp < 0)
      return false;
   entry = c[s];
   double buf = P.slBufAtr * atr5[s];
   sl = (dir > 0) ? NbRoundTick(swing - buf, P.tick, P.digits, -1) : NbRoundTick(swing + buf, P.tick, P.digits, 1);
   risk = NormalizeDouble(MathAbs(entry - sl), P.digits);
   double minRisk = (P.tick > 0.0) ? P.tick * 0.5 : 0.0;
   if(risk <= minRisk || risk <= 0.0)
      return false;
   tp1 = NbRoundTick(entry + dir * P.tp1R * risk, P.tick, P.digits, 0);
   tp2 = NbRoundTick(entry + dir * P.tp2R * risk, P.tick, P.digits, 0);
   return true;
}

//+------------------------------------------------------------------+
//| NY SESSION CLOCK                                                 |
//| A clock needs two witnesses. In AUTO mode the broker's clock     |
//| (TimeTradeServer) and the PC's clock (TimeGMT) are compared by   |
//| the terminal layer; the offset must sit on a half-hour or the    |
//| module switches itself OFF and says so. The US DST calendar is   |
//| computed per bar, never assumed. MANUAL mode uses a typed time.  |
//+------------------------------------------------------------------+

//--- civil date from days since 1970-01-01 (proleptic Gregorian)
void NbCivil(long days, int &y, int &m, int &d)
{
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

//--- US daylight saving in force on that UTC day? (second Sunday of March
//    to first Sunday of November; NY opens at 09:30 local, well after the
//    02:00 switch, so the day is enough)
bool NbUsDst(long days)
{
   int y = 0;
   int m = 0;
   int d = 0;
   NbCivil(days, y, m, d);
   if(m < 3 || m > 11)
      return false;
   if(m > 3 && m < 11)
      return true;
   int dow = (int)((days + 4) % 7);                 // 1970-01-01 was a Thursday; Sunday = 0
   int dow1 = ((dow - (d - 1)) % 7 + 7) % 7;         // weekday of the 1st of this month
   int firstSun = 1 + (7 - dow1) % 7;
   if(m == 3)
      return d >= firstSun + 7;
   return d < firstSun;
}

//--- NY open (server time) of the session a bar at server time t belongs to.
//    sessId identifies the session so per-session bookkeeping resets.
datetime NbNyOpenOf(datetime t, const NbSessCfg &S, long &sessId)
{
   if(S.clockMode == NB_CLK_MANUAL)
   {
      long day = ((long)t) / 86400;
      sessId = day;
      return (datetime)(day * 86400 + S.manualOpenSec);
   }
   long utc = (long)t - S.offset;
   long day = utc / 86400;
   sessId = day;
   long openUtc = day * 86400 + (NbUsDst(day) ? (13 * 3600 + 1800) : (14 * 3600 + 1800));
   return (datetime)(openUtc + S.offset);
}

//--- session pass over the closed 5M bars: phase, pre-NY range, sweeps.
//    Causal: bar i sees the range built from bars before it and the sweep
//    extreme up to and including itself.
void NbRunSession(NbSeries &s, const NbSessCfg &S)
{
   int n = s.n;
   ArrayResize(s.ph, n);
   ArrayResize(s.sid, n);
   ArrayResize(s.rh, n);
   ArrayResize(s.rl, n);
   ArrayResize(s.rn, n);
   ArrayResize(s.swH, n);
   ArrayResize(s.swL, n);
   long curId = -1;
   double preH = 0.0;
   double preL = 0.0;
   int cnt = 0;
   double mxH = 0.0;
   double mnL = 0.0;
   int nyCnt = 0;
   for(int i = 0; i < n; i++)
   {
      s.ph[i] = NB_PH_OUT;
      s.sid[i] = -1;
      s.rh[i] = 0.0;
      s.rl[i] = 0.0;
      s.rn[i] = 0;
      s.swH[i] = 0.0;
      s.swL[i] = 0.0;
      if(!S.clockOk)
         continue;
      long id = -1;
      datetime open = NbNyOpenOf(s.t[i], S, id);
      datetime preStart = open - (datetime)(S.preHours * 3600);
      datetime nyEnd = open + (datetime)(S.winMin * 60);
      int p = NB_PH_OUT;
      if(s.t[i] >= preStart && s.t[i] < open)
         p = NB_PH_PRE;
      else if(s.t[i] >= open && s.t[i] < nyEnd)
         p = NB_PH_NY;
      if(id != curId)
      {
         curId = id;
         cnt = 0;
         preH = 0.0;
         preL = 0.0;
         mxH = 0.0;
         mnL = 0.0;
         nyCnt = 0;
      }
      if(p == NB_PH_PRE)
      {
         if(cnt == 0)
         {
            preH = s.h[i];
            preL = s.l[i];
         }
         else
         {
            preH = MathMax(preH, s.h[i]);
            preL = MathMin(preL, s.l[i]);
         }
         cnt++;
      }
      if(p == NB_PH_NY)
      {
         if(nyCnt == 0)
         {
            mxH = s.h[i];
            mnL = s.l[i];
         }
         else
         {
            mxH = MathMax(mxH, s.h[i]);
            mnL = MathMin(mnL, s.l[i]);
         }
         nyCnt++;
      }
      s.ph[i] = p;
      s.sid[i] = id;
      if(p != NB_PH_OUT && cnt > 0)
      {
         s.rh[i] = preH;
         s.rl[i] = preL;
         s.rn[i] = cnt;
      }
      if(p == NB_PH_NY && cnt >= S.minRangeBars && nyCnt > 0)
      {
         if(mxH > preH)
            s.swH[i] = mxH;
         if(mnL < preL)
            s.swL[i] = mnL;
      }
   }
}

//--- one learning signal record
void NbMakeSignal(NbSignal &g, int idx, int dir, int kind, double entry, double sl, double risk,
                  const NbParams &P)
{
   g.idx = idx;
   g.dir = dir;
   g.kind = kind;
   g.entry = entry;
   g.sl = sl;
   g.tp1 = NbRoundTick(entry + dir * P.tp1R * risk, P.tick, P.digits, 0);
   g.tp2 = NbRoundTick(entry + dir * P.tp2R * risk, P.tick, P.digits, 0);
   g.risk = risk;
   g.status = NB_SIG_ACTIVE;
   g.statusIdx = idx;
   g.swingIdx = -1;
   g.level = 0.0;
   g.sweep = 0.0;
}

//--- 5M trigger pass.
//    FLOW: an "episode" is a stretch where the 15M mode and the 5M NRTR
//    point the same way. Inside an episode the FIRST closed candle in that
//    direction (with a valid structural stop) is the learning signal; it
//    stays CLICK-able until it expires, reaches TP1 or hits its SL. A new
//    signal needs a new episode (5M pulls back against 15M, then realigns).
//    TRAP: inside the NY window, once the pre-NY range high has been taken,
//    the first 5M candle that CLOSES back below it with a bearish body is
//    the SELL trap (mirror for BUY). One trap per side per session. A trap
//    cancels an active flow signal; while a trap is current no flow signal
//    starts. With pauseFlow the window never starts a flow signal at all.
//    lastClosed=false: the last bar is still forming and is NOT evaluated.
void NbRunTrigger(const double &o[], const double &h[], const double &l[], const double &c[],
                  const double &atr5[], const int &dir5[], const int &boss[], const int &bossR[],
                  const NbPivot &piv[], int np, int n, bool lastClosed, const NbParams &P,
                  const int &ph[], const long &sid[], const double &rh[], const double &rl[],
                  const int &rn[], const double &swH[], const double &swL[], const NbSessCfg &S,
                  int &state[], int &reasons[], int &sigOf[], NbSignal &sigs[], int &nSig)
{
   ArrayResize(state, n);
   ArrayResize(reasons, n);
   ArrayResize(sigOf, n);
   ArrayResize(sigs, 0);
   nSig = 0;
   int nEval = lastClosed ? n : n - 1;
   int epDir = 0;
   int cur = -1;
   long trapSess = -1;
   bool firedBuy = false;
   bool firedSell = false;
   double minRisk = (P.tick > 0.0) ? P.tick * 0.5 : 0.0;
   for(int s = 0; s < n; s++)
   {
      if(s >= nEval)
      {
         // unfinished candle: carry the last CLOSED state, add the reason
         state[s] = (s > 0) ? state[s - 1] : NB_WAIT;
         reasons[s] = ((s > 0) ? reasons[s - 1] : 0) | NB_R_CANDLE_OPEN;
         sigOf[s] = (s > 0) ? sigOf[s - 1] : -1;
         continue;
      }
      // 1) outcome of the active signal, judged on this closed bar.
      //    SAME-CANDLE RULE (frozen): the SL is tested FIRST. If one candle
      //    touches both the SL and TP1, tick order is unknown, so SL wins.
      if(cur >= 0 && sigs[cur].status == NB_SIG_ACTIVE && s > sigs[cur].idx)
      {
         if(sigs[cur].dir > 0)
         {
            if(l[s] <= sigs[cur].sl)
               sigs[cur].status = NB_SIG_SL;
            else if(h[s] >= sigs[cur].tp1)
               sigs[cur].status = NB_SIG_TP1;
         }
         else
         {
            if(h[s] >= sigs[cur].sl)
               sigs[cur].status = NB_SIG_SL;
            else if(l[s] <= sigs[cur].tp1)
               sigs[cur].status = NB_SIG_TP1;
         }
         if(sigs[cur].status == NB_SIG_ACTIVE && s - sigs[cur].idx >= P.validBars)
            sigs[cur].status = NB_SIG_EXPIRED;
         if(sigs[cur].status != NB_SIG_ACTIVE)
            sigs[cur].statusIdx = s;
      }
      bool inNy = (ph[s] == NB_PH_NY);
      bool curTrap = (cur >= 0 && sigs[cur].kind == NB_K_TRAP);
      // a finished trap outside the window releases the flow: fresh episode
      if(curTrap && !inNy && sigs[cur].status != NB_SIG_ACTIVE)
      {
         cur = -1;
         curTrap = false;
         epDir = 0;
      }
      // 2) episode bookkeeping (flow only; a trap is not tied to an episode)
      int b = boss[s];
      int d = dir5[s];
      int align = (b != 0 && d == b) ? b : 0;
      if(align != epDir)
      {
         if(cur >= 0 && !curTrap && sigs[cur].status == NB_SIG_ACTIVE)
         {
            sigs[cur].status = NB_SIG_CANCELLED;
            sigs[cur].statusIdx = s;
         }
         epDir = align;
         if(!curTrap)
            cur = -1;
      }
      // 3) NY trap: sweep of the pre-NY range, then a close back inside
      if(inNy && sid[s] != trapSess)
      {
         trapSess = sid[s];
         firedBuy = false;
         firedSell = false;
      }
      bool haveRange = (inNy && rn[s] >= S.minRangeBars && rh[s] > 0.0);
      bool trapActive = (curTrap && sigs[cur].status == NB_SIG_ACTIVE);
      if(haveRange && !trapActive && atr5[s] > 0.0)
      {
         int tdir = 0;
         double level = 0.0;
         double sweep = 0.0;
         if(!firedSell && swH[s] > 0.0 && c[s] < rh[s] && c[s] < o[s])
         {
            tdir = NB_SELL;
            level = rh[s];
            sweep = swH[s];
         }
         else if(!firedBuy && swL[s] > 0.0 && c[s] > rl[s] && c[s] > o[s])
         {
            tdir = NB_BUY;
            level = rl[s];
            sweep = swL[s];
         }
         if(tdir != 0)
         {
            double buf = P.slBufAtr * atr5[s];
            double sl = (tdir > 0) ? NbRoundTick(sweep - buf, P.tick, P.digits, -1)
                                   : NbRoundTick(sweep + buf, P.tick, P.digits, 1);
            double risk = NormalizeDouble(MathAbs(c[s] - sl), P.digits);
            if(risk > minRisk && risk > 0.0)
            {
               if(cur >= 0 && sigs[cur].status == NB_SIG_ACTIVE)
               {
                  sigs[cur].status = NB_SIG_CANCELLED;
                  sigs[cur].statusIdx = s;
               }
               ArrayResize(sigs, nSig + 1, 64);
               NbMakeSignal(sigs[nSig], s, tdir, NB_K_TRAP, c[s], sl, risk, P);
               sigs[nSig].level = level;
               sigs[nSig].sweep = sweep;
               cur = nSig;
               nSig++;
               curTrap = true;
               if(tdir > 0)
                  firedBuy = true;
               else
                  firedSell = true;
            }
         }
      }
      // 4) decision
      int r = 0;
      if(curTrap)
      {
         if(sigs[cur].status == NB_SIG_EXPIRED)
            r |= NB_R_SIG_EXPIRED;
         if(sigs[cur].status == NB_SIG_TP1)
            r |= NB_R_SIG_TP1;
         if(sigs[cur].status == NB_SIG_SL)
            r |= NB_R_SIG_SL;
         if(sigs[cur].status == NB_SIG_CANCELLED)
            r |= NB_R_NY_WINDOW;
      }
      else
      {
         bool paused = (inNy && S.pauseFlow);
         bool flowLive = (cur >= 0 && sigs[cur].status == NB_SIG_ACTIVE);
         if(paused && !flowLive)
         {
            r |= NB_R_NY_WINDOW;
            if(!haveRange)
               r |= NB_R_NY_NO_RANGE;
         }
         if(b == 0)
            r |= bossR[s];
         else if(d == 0)
            r |= NB_R_5M_NOT_READY;
         else if(d != b)
            r |= NB_R_5M_AGAINST;
         else
         {
            if(cur < 0 && !paused)
            {
               bool body = (b > 0) ? (c[s] > o[s]) : (c[s] < o[s]);
               if(!body)
                  r |= NB_R_5M_WAIT_CANDLE;
               else
               {
                  double swing = 0.0;
                  int sp = NbFindStopSwing(piv, np, s, b, c[s], NB_SL_SEARCH_BARS, swing);
                  if(sp < 0 || atr5[s] <= 0.0)
                     r |= NB_R_5M_NO_STOP;
                  else
                  {
                     double entry = c[s];
                     double buf = P.slBufAtr * atr5[s];
                     double sl = (b > 0) ? NbRoundTick(swing - buf, P.tick, P.digits, -1)
                                         : NbRoundTick(swing + buf, P.tick, P.digits, 1);
                     double risk = NormalizeDouble(MathAbs(entry - sl), P.digits);
                     if(risk <= minRisk || risk <= 0.0)
                        r |= NB_R_5M_NO_STOP;
                     else
                     {
                        ArrayResize(sigs, nSig + 1, 64);
                        NbMakeSignal(sigs[nSig], s, b, NB_K_FLOW, entry, sl, risk, P);
                        sigs[nSig].swingIdx = piv[sp].idx;
                        cur = nSig;
                        nSig++;
                     }
                  }
               }
            }
            if(cur >= 0)
            {
               if(sigs[cur].status == NB_SIG_EXPIRED)
                  r |= NB_R_SIG_EXPIRED;
               if(sigs[cur].status == NB_SIG_TP1)
                  r |= NB_R_SIG_TP1;
               if(sigs[cur].status == NB_SIG_SL)
                  r |= NB_R_SIG_SL;
            }
         }
      }
      sigOf[s] = cur;
      if(r == 0 && cur >= 0 && sigs[cur].status == NB_SIG_ACTIVE)
      {
         state[s] = sigs[cur].dir;
         reasons[s] = 0;
      }
      else
      {
         state[s] = NB_WAIT;
         reasons[s] = (r != 0) ? r : NB_R_NO_DATA;
      }
   }
}

//--- full 15M pipeline
void NbRun15(NbSeries &s, NbPivot &piv[], const NbParams &P)
{
   int n = s.n;
   NbCalcATR(s.h, s.l, s.c, n, P.atrPeriod, s.atr);
   NbCalcEMA(s.c, n, P.emaPeriod, s.ema);
   NbCalcNRTR(s.c, s.atr, n, P.nrtrMult, s.dir, s.stop, s.ext, s.flip);
   s.np = NbFindPivots(s.h, s.l, n, P.swing, piv);
   NbStructureSeries(piv, s.np, n, s.st, s.hl, s.ll, s.lk);
   ArrayResize(s.mode, n);
   ArrayResize(s.mr, n);
   for(int i = 0; i < n; i++)
   {
      int r = 0;
      s.mode[i] = NbBossDecision(s.dir[i], s.c[i], s.ema[i], s.st[i], r);
      s.mr[i] = r;
   }
}

//--- full 5M pipeline, driven by an already computed 15M series
void NbRun5(NbSeries &s, NbPivot &piv[], const NbSeries &b, bool lastClosed, const NbParams &P,
            const NbSessCfg &S, NbSignal &sigs[], int &nSig)
{
   int n = s.n;
   NbCalcATR(s.h, s.l, s.c, n, P.atrPeriod, s.atr);
   NbCalcNRTR(s.c, s.atr, n, P.nrtrMult, s.dir, s.stop, s.ext, s.flip);
   s.np = NbFindPivots(s.h, s.l, n, P.swing, piv);
   NbAlign(b.t, b.n, b.sec, s.t, n, s.sec, s.map);
   NbRunSession(s, S);
   ArrayResize(s.boss, n);
   ArrayResize(s.bossR, n);
   for(int i = 0; i < n; i++)
   {
      int k = s.map[i];
      if(k < 0)
      {
         s.boss[i] = NB_WAIT;
         s.bossR[i] = NB_R_NO_15M_BAR;
      }
      else
      {
         s.boss[i] = b.mode[k];
         s.bossR[i] = b.mr[k];
      }
   }
   NbRunTrigger(s.o, s.h, s.l, s.c, s.atr, s.dir, s.boss, s.bossR, piv, s.np, n, lastClosed, P,
                s.ph, s.sid, s.rh, s.rl, s.rn, s.swH, s.swL, S,
                s.state, s.reasons, s.sigOf, sigs, nSig);
}

//--- value of a per-bar 15M series (e.g. BOSS mode) as it was KNOWN at time
//    `when`: the value of the last bar that had CLOSED by then, 0 if none.
int NbKnownAtTime(const datetime &t[], const int &v[], int n, int sec, datetime when)
{
   int k = -1;
   for(int i = 0; i < n; i++)
   {
      if(t[i] + sec <= when)
         k = i;
      else
         break;
   }
   return (k >= 0) ? v[k] : 0;
}

// freshness witnesses (v1.04)
#define NB_FR_OK        0
#define NB_FR_NO_BAR    1   // no closed bar loaded
#define NB_FR_NO_TICK   2   // broker's last tick too old (feed dead / market closed)
#define NB_FR_BAR0_OLD  3   // forming bar is not the current one
#define NB_FR_CLOCK     4   // tick clock and server clock disagree
#define NB_FR_GAP       5   // a closed bar exists that we have not loaded

//--- v1.04: freshness by witnesses, fail closed. `now` = server clock
//    (TimeTradeServer), `tick` = time of the broker's last quote
//    (TimeCurrent / SYMBOL_TIME), bar0_5/bar0_15 = open time of the FORMING
//    bars, last5/last15 = open time of the last CLOSED bars we hold.
//    A session break makes closed bars old without making data stale, so
//    closed-bar age is NOT a witness; the forming bar and the tick are.
int NbFreshness(datetime now, datetime tick, datetime bar0_5, datetime bar0_15, datetime last5, datetime last15,
                int sec5, int sec15, int maxTickAge, int maxClockSkew)
{
   if(last5 <= 0 || last15 <= 0 || bar0_5 <= 0 || bar0_15 <= 0 || tick <= 0 || now <= 0)
      return NB_FR_NO_BAR;
   if(now - tick > maxTickAge)
      return NB_FR_NO_TICK;
   if(MathAbs((long)now - (long)tick) > maxClockSkew && tick > now)
      return NB_FR_CLOCK;
   // the forming bars must be the current ones: their window must contain
   // the tick (or be the bar right before it while the new one is not yet
   // opened by a tick)
   if(tick - bar0_5 > 2 * sec5 || tick - bar0_15 > 2 * sec15)
      return NB_FR_BAR0_OLD;
   // the closed bars we hold must be the ones right before the forming bars
   if(bar0_5 <= last5 || bar0_15 <= last15)
      return NB_FR_GAP;
   return NB_FR_OK;
}

string NbFreshText(int code)
{
   switch(code)
   {
      case NB_FR_OK:       return "LIVE";
      case NB_FR_NO_BAR:   return "NO BARS";
      case NB_FR_NO_TICK:  return "NO RECENT TICK - FEED DEAD OR MARKET CLOSED";
      case NB_FR_BAR0_OLD: return "FORMING BAR IS OLD - HISTORY NOT CURRENT";
      case NB_FR_CLOCK:    return "CLOCK MISMATCH - TICK TIME AHEAD OF SERVER CLOCK";
      case NB_FR_GAP:      return "CLOSED BAR NOT LOADED YET - RELOADING";
   }
   return "UNKNOWN";
}

//--- (v1.00-v1.03 rule, kept for reference/tests; no longer the gate)
bool NbIsFresh(datetime last5, int sec5, datetime last15, int sec15, datetime now)
{
   if(last5 <= 0 || last15 <= 0)
      return false;
   if(now - (last5 + sec5) > 3 * sec5)
      return false;
   if(now - (last15 + sec15) > 2 * sec15)
      return false;
   return true;
}

//--- READ-ONLY advice for an existing position (posDir +1 buy, -1 sell),
//    judged on the COMPLETE 15M BOSS mode (NB_BUY / NB_SELL / NB_WAIT), never
//    on the NRTR direction alone. modeAtOpen = BOSS mode known when the
//    position was opened, modeNow = BOSS mode of the last CLOSED 15M bar.
//      posDir == modeNow            -> HOLD    (INTACT)
//      modeNow == -posDir           -> EXIT    (INVALIDATED if opened with the
//                                              boss, AGAINST if it never agreed)
//      modeNow == NB_WAIT           -> UNKNOWN (BOSS_WAIT: protect, you decide)
//    Stale / missing data is handled by the caller and is also UNKNOWN.
//    A single NRTR flip only moves the boss to WAIT, so it can never produce
//    EXIT by itself.
int NbExitAdvice(int posDir, int modeAtOpen, int modeNow, int &why)
{
   why = NB_WHY_NONE;
   if(posDir == 0)
      return NB_ADV_NONE;
   if(modeNow == posDir)
   {
      why = NB_WHY_INTACT;
      return NB_ADV_HOLD;
   }
   if(modeNow == -posDir)
   {
      why = (modeAtOpen == posDir) ? NB_WHY_INVALIDATED : NB_WHY_AGAINST;
      return NB_ADV_EXIT;
   }
   why = NB_WHY_BOSS_WAIT;
   return NB_ADV_UNKNOWN;
}

//--- final panel state. Stale data can never become a positive state.
int NbFinalState(int sig, int sigR, bool fresh, int adv, int &outR)
{
   if(!fresh)
   {
      outR = NB_R_STALE;
      return NB_WAIT;
   }
   if(adv == NB_ADV_EXIT)
   {
      outR = 0;
      return NB_EXIT;
   }
   outR = sigR;
   if(sig != NB_BUY && sig != NB_SELL)
   {
      if(outR == 0)
         outR = NB_R_NO_DATA;
      return NB_WAIT;
   }
   return sig;
}

//--- session clock from the two witnesses: broker server time and the
//    PC's GMT. The offset must sit on a half hour (within 5 min) and be
//    plausible; otherwise the module is OFF and the panel says so.
bool NbClockFromWitnesses(datetime server, datetime gmt, long &offset)
{
   offset = 0;
   if(server <= 0 || gmt <= 0)
      return false;
   long off = (long)server - (long)gmt;
   long r = (long)MathRound((double)off / 1800.0) * 1800;
   if(MathAbs(off - r) > 300)
      return false;
   if(r < -12 * 3600 || r > 14 * 3600)
      return false;
   offset = r;
   return true;
}

//+------------------------------------------------------------------+
//| MARKET FILTER - the twin files differ only in NB_MARKET.         |
//+------------------------------------------------------------------+
string NbStripPrefix(string name)
{
   string u = name;
   StringToUpper(u);
   int len = StringLen(u);
   int p = 0;
   while(p < len)
   {
      ushort ch = StringGetCharacter(u, p);
      if(ch >= 'A' && ch <= 'Z')
         break;
      p++;
   }
   if(p > 0)
      u = StringSubstr(u, p);
   return u;
}

// supported crypto bases, ordered so longer codes are tried first
string NbCryptoCode(int k)
{
   switch(k)
   {
      case 0:  return "BTC";
      case 1:  return "ETH";
      case 2:  return "SOL";
      case 3:  return "LTC";
      case 4:  return "XRP";
      case 5:  return "BNB";
      case 6:  return "ADA";
      case 7:  return "DOGE";
      case 8:  return "AVAX";
      case 9:  return "DOT";
      case 10: return "LINK";
      case 11: return "BCH";
   }
   return "";
}
#define NB_CRYPTO_COUNT 12

// broker aliases that spell the coin out
string NbCryptoAlias(int k, string &code)
{
   switch(k)
   {
      case 0: code = "BTC"; return "BITCOIN";
      case 1: code = "ETH"; return "ETHEREUM";
      case 2: code = "SOL"; return "SOLANA";
      case 3: code = "LTC"; return "LITECOIN";
      case 4: code = "XRP"; return "RIPPLE";
      case 5: code = "DOGE"; return "DOGECOIN";
   }
   code = "";
   return "";
}
#define NB_CRYPTO_ALIAS_COUNT 6

string NbFxCode(int k)
{
   switch(k)
   {
      case 0:  return "USD";
      case 1:  return "EUR";
      case 2:  return "GBP";
      case 3:  return "JPY";
      case 4:  return "CHF";
      case 5:  return "AUD";
      case 6:  return "NZD";
      case 7:  return "CAD";
      case 8:  return "SGD";
      case 9:  return "NOK";
      case 10: return "SEK";
      case 11: return "DKK";
      case 12: return "PLN";
      case 13: return "ZAR";
      case 14: return "MXN";
      case 15: return "HKD";
      case 16: return "CNH";
   }
   return "";
}
#define NB_FX_COUNT 17

bool NbIsFxCode(string code)
{
   for(int k = 0; k < NB_FX_COUNT; k++)
      if(code == NbFxCode(k))
         return true;
   return false;
}

bool NbIsCryptoQuote(string q)
{
   return (q == "USD" || q == "USDT" || q == "USDC");
}

//--- Accepted symbol -> short label ("BTC", "EURUSD"); "" = rejected.
//    Broker prefixes/suffixes are fine (BTCUSD.m, #ETHUSD, EURUSD.r).
string NbMarketLabel(string name, string base, string profitCcy)
{
   string u = NbStripPrefix(name);
   string b = base;
   StringToUpper(b);
   string q = profitCcy;
   StringToUpper(q);
   if(NB_MARKET == NB_MKT_CRYPTO)
   {
      if(q != "" && !NbIsCryptoQuote(q))
         return "";
      for(int k = 0; k < NB_CRYPTO_COUNT; k++)
      {
         string code = NbCryptoCode(k);
         if(b == code)
            return code;
         if(StringFind(u, code) == 0 && StringFind(u, "USD", StringLen(code)) == StringLen(code))
            return code;
      }
      for(int k = 0; k < NB_CRYPTO_ALIAS_COUNT; k++)
      {
         string code = "";
         string alias = NbCryptoAlias(k, code);
         if(StringFind(u, alias) == 0)
            return code;
      }
      return "";
   }
   // forex: two ISO currency codes from the list, base != quote
   if(b != "" && q != "" && NbIsFxCode(b) && NbIsFxCode(q) && b != q)
      return b + q;
   if(StringLen(u) >= 6)
   {
      string c1 = StringSubstr(u, 0, 3);
      string c2 = StringSubstr(u, 3, 3);
      if(NbIsFxCode(c1) && NbIsFxCode(c2) && c1 != c2)
         return c1 + c2;
   }
   return "";
}

//--- text helpers (ASCII source; symbols built from code points)
string NbSymArrow()  { return ShortToString(0x2192); }
string NbSymDot()    { return ShortToString(0x25CF); }
string NbSymUp()     { return ShortToString(0x25B2); }
string NbSymDown()   { return ShortToString(0x25BC); }

string NbLabelName(int lbl)
{
   switch(lbl)
   {
      case NB_L_HH:  return "HH";
      case NB_L_LH:  return "LH";
      case NB_L_EQH: return "EQH";
      case NB_L_HL:  return "HL";
      case NB_L_LL:  return "LL";
      case NB_L_EQL: return "EQL";
   }
   return "?";
}

string NbDirText(int d)
{
   if(d > 0)
      return "BULLISH";
   if(d < 0)
      return "BEARISH";
   return "NOT READY";
}

string NbModeText(int m)
{
   if(m == NB_BUY)
      return "BUY MODE";
   if(m == NB_SELL)
      return "SELL MODE";
   return "WAIT";
}

string NbStructText(int st, int hl, int ll, int lk)
{
   if(st == NB_ST_UNKNOWN)
      return "NOT CONFIRMED";
   string a = NbLabelName(hl);
   string b = NbLabelName(ll);
   string txt = (lk > 0) ? (b + " " + NbSymArrow() + " " + a) : (a + " " + NbSymArrow() + " " + b);
   if(st == NB_ST_MIXED)
      txt = txt + "  (MIXED)";
   return txt;
}

string NbMarketOnlyText()
{
   if(NB_MARKET == NB_MKT_CRYPTO)
      return "CRYPTO ONLY (BTC ETH SOL LTC ...)";
   return "FOREX ONLY (EURUSD USDJPY ...)";
}

// reasons in the order a beginner should read them
int NbReasonBit(int k)
{
   switch(k)
   {
      case 0:  return NB_R_UNSUPPORTED;
      case 1:  return NB_R_STALE;
      case 2:  return NB_R_NO_DATA;
      case 3:  return NB_R_NY_WINDOW;
      case 4:  return NB_R_NY_NO_RANGE;
      case 5:  return NB_R_NO_15M_BAR;
      case 6:  return NB_R_NRTR15_NOT_READY;
      case 7:  return NB_R_EMA_NOT_READY;
      case 8:  return NB_R_STRUCT_UNCONF;
      case 9:  return NB_R_STRUCT_MIXED;
      case 10: return NB_R_NRTR_CONFLICT;
      case 11: return NB_R_EMA_CONFLICT;
      case 12: return NB_R_STRUCT_CONFLICT;
      case 13: return NB_R_EMA_FLAT;
      case 14: return NB_R_5M_NOT_READY;
      case 15: return NB_R_5M_AGAINST;
      case 16: return NB_R_CANDLE_OPEN;
      case 17: return NB_R_5M_WAIT_CANDLE;
      case 18: return NB_R_5M_NO_STOP;
      case 19: return NB_R_SIG_SL;
      case 20: return NB_R_SIG_TP1;
      case 21: return NB_R_SIG_EXPIRED;
   }
   return 0;
}

string NbReasonName(int bit)
{
   switch(bit)
   {
      case NB_R_UNSUPPORTED:      return NbMarketOnlyText();
      case NB_R_STALE:            return "DATA STALE / MARKET CLOSED";
      case NB_R_NO_DATA:          return "MISSING DATA - NOT ENOUGH HISTORY";
      case NB_R_NY_WINDOW:        return "NY OPEN WINDOW - FLOW PAUSED, WATCHING FOR SWEEP";
      case NB_R_NY_NO_RANGE:      return "NO PRE-NY RANGE (NOT ENOUGH 5M BARS BEFORE OPEN)";
      case NB_R_NO_15M_BAR:       return "NO CLOSED 15M BAR YET";
      case NB_R_NRTR15_NOT_READY: return "15M NRTR NOT READY";
      case NB_R_EMA_NOT_READY:    return "15M EMA200 NOT READY";
      case NB_R_STRUCT_UNCONF:    return "15M STRUCTURE NOT CONFIRMED";
      case NB_R_STRUCT_MIXED:     return "15M STRUCTURE MIXED";
      case NB_R_NRTR_CONFLICT:    return "15M NRTR CONFLICT";
      case NB_R_EMA_CONFLICT:     return "EMA CONFLICT";
      case NB_R_STRUCT_CONFLICT:  return "STRUCTURE AGAINST NRTR";
      case NB_R_EMA_FLAT:         return "PRICE SITTING ON EMA200";
      case NB_R_5M_NOT_READY:     return "5M NRTR NOT READY";
      case NB_R_5M_AGAINST:       return "5M AGAINST 15M";
      case NB_R_CANDLE_OPEN:      return "5M CANDLE NOT CLOSED YET";
      case NB_R_5M_WAIT_CANDLE:   return "WAIT FOR 5M CANDLE TO CLOSE IN DIRECTION";
      case NB_R_5M_NO_STOP:       return "NO CONFIRMED 5M SWING FOR SL";
      case NB_R_SIG_SL:           return "SETUP HIT ITS SL - STAND ASIDE";
      case NB_R_SIG_TP1:          return "SETUP ALREADY AT TP1 - TOO LATE";
      case NB_R_SIG_EXPIRED:      return "SETUP EXPIRED - WAIT FOR NEXT";
   }
   return "";
}

// nth (0-based) reason present in r, in reading order; "" if none
string NbReasonAt(int r, int nth)
{
   int seen = 0;
   for(int k = 0; k < NB_R_COUNT; k++)
   {
      int bit = NbReasonBit(k);
      if((r & bit) != 0)
      {
         if(seen == nth)
            return NbReasonName(bit);
         seen++;
      }
   }
   return "";
}

string NbSignalStatusText(int status)
{
   switch(status)
   {
      case NB_SIG_ACTIVE:    return "active";
      case NB_SIG_EXPIRED:   return "expired unfilled window";
      case NB_SIG_TP1:       return "reached TP1";
      case NB_SIG_SL:        return "hit SL";
      case NB_SIG_CANCELLED: return "cancelled (5M/15M turned or NY trap fired)";
   }
   return "";
}

string NbPhaseText(int p)
{
   if(p == NB_PH_PRE)
      return "PRE-NY RANGE BUILDING";
   if(p == NB_PH_NY)
      return "NY WINDOW - THE WILDLIFE";
   return "OUTSIDE NY - STRUCTURE FLOW";
}
//=== NB_ENGINE_END ===

//+------------------------------------------------------------------+
//| TERMINAL LAYER - data loading, panel, chart drawing.             |
//| READ-ONLY with respect to the trading account.                   |
//+------------------------------------------------------------------+
const string NB_PFX   = "NBSP_";
const string NB_PFX_P = "NBSP_P_";
const string NB_PFX_C = "NBSP_C_";
#define NB_RGB(r, g, b) ((color)((r) | ((g) << 8) | ((b) << 16)))

enum ENUM_NB_CORNER
{
   NB_TOP_LEFT = 0,     // Top left
   NB_TOP_RIGHT = 1,    // Top right
   NB_BOTTOM_LEFT = 2,  // Bottom left
   NB_BOTTOM_RIGHT = 3  // Bottom right
};

enum ENUM_NB_CLOCK
{
   NB_CLOCK_AUTO = 0,   // AUTO: broker clock vs PC clock + US DST calendar
   NB_CLOCK_MANUAL = 1  // MANUAL: NY open typed in broker server time
};

input group "Engine (15M boss + 5M trigger are fixed)"
input int            InpNrtrAtrPeriod   = 14;          // NRTR ATR period
input double         InpNrtrMultiplier  = 2.0;         // NRTR ATR multiplier
input int            InpEmaPeriod       = 200;         // EMA period (15M)
input int            InpSwingStrength   = 3;           // Structure lookback: bars each side of a swing
input double         InpSlBufferAtr     = 0.10;        // SL buffer beyond 5M swing / NY sweep (x 5M ATR)
input double         InpTp1R            = 1.0;         // TP1 (R multiple)
input double         InpTp2R            = 2.0;         // TP2 (R multiple)
input int            InpSignalValidBars = 6;           // Signal stays clickable for (5M bars)
input int            InpHistoryDays     = 10;          // History used (days)
input group "Position size (reference only - the lot you type is your decision)"
input double         InpRiskPercent     = 1.0;         // Risk per trade, % of balance (0.1 - 5.0)
input group "Swing / pending-order references (nothing is sent)"
input double         InpSwingDist       = 0.0;         // Swing TP distance in price (0 = automatic, from the 15M ATR)
input double         InpSwingAtrMult    = 3.0;         // Automatic swing TP distance = this x 15M ATR
input group "Data clock (freshness witnesses)"
input int            InpMaxTickAgeSec   = 120;         // Last broker tick older than this = STALE
input int            InpMaxClockSkewSec = 300;         // Tick clock ahead of server clock by more = STALE
input group "NY session - the wildlife"
input ENUM_NB_CLOCK  InpSessionClock    = NB_CLOCK_AUTO; // Session clock
input int            InpNyOpenHour      = 16;          // MANUAL only: NY open hour (broker server time)
input int            InpNyOpenMinute    = 30;          // MANUAL only: NY open minute
input int            InpPreNyRangeHours = 4;           // Pre-NY range: hours before the open
input int            InpNyWindowMinutes = 90;          // NY window: minutes after the open
input int            InpMinRangeBars    = 12;          // Pre-NY range needs at least this many closed 5M bars
input bool           InpNyPauseFlow     = true;        // Pause structure-flow signals inside the NY window
input bool           InpNyAlert         = true;        // MT5 pop-up + sound at the NY open (local only)
input group "Display"
input double         InpPanelScale      = 0.9;         // Panel size (0.7 - 1.6)
input ENUM_NB_CORNER InpPanelCorner     = NB_TOP_LEFT; // Panel position
input int            InpPanelX          = 12;          // Panel X offset (px)
input int            InpPanelY          = 24;          // Panel Y offset (px)
input bool           InpDrawChart       = true;        // Draw EMA/NRTR/structure/markers/levels/range
input bool           InpCandleArrows    = true;        // Arrow on the candle where the NRTR flips
input bool           InpArrowEveryBar   = false;       // Also a small arrow on every closed candle
input bool           InpPreview         = true;        // Yellow PREVIEW on the forming candle (not a signal)
input bool           InpBlink           = true;        // Blink the CLICK BUY / SELL banner

// plot buffers
double g_bEma[];
double g_bStop15[];
double g_bStop15Clr[];
double g_bExt15[];
double g_bStop5[];
double g_bStop5Clr[];
double g_bArrUp[];
double g_bArrUpClr[];
double g_bArrDn[];
double g_bArrDnClr[];

// symbol specification (always read from MT5, never hard-coded)
string   g_sym;
string   g_label;      // "" = unsupported symbol
int      g_digits;
double   g_tick;
double   g_tickValue;
double   g_volMin;
double   g_volStep;
double   g_volMax;
double   g_balance;
double   g_equity;
string   g_accCcy;

// engine state
NbParams  g_P;
NbSessCfg g_S;
datetime  g_anchor;
NbSeries  g_s15;
NbSeries  g_s5;
NbPivot   g_piv15[];
NbPivot   g_piv5[];
NbSignal  g_sigs[];
int       g_nSig;
datetime  g_seen15;
datetime  g_seen5;
bool      g_ready;
int       g_dataR;
bool      g_bufDirty;

// view state
bool     g_fresh;
int      g_freshCode;
datetime g_diagNow;
datetime g_diagTick;
datetime g_diagBar05;
datetime g_diagBar015;
int      g_final;
int      g_finalR;
int      g_adv;
int      g_advWhy;
int      g_advDir;
int      g_buyCnt;
double   g_buyVol;
int      g_sellCnt;
double   g_sellVol;
bool     g_blink;
long     g_nyAlertDay;     // session id already alerted
double   g_swingDist;

// prototypes
int    PlotDrawType(int plot);
void   NbUpdate();
void   NbReadSpec();
void   NbReadClock();
bool   NbLoad(ENUM_TIMEFRAMES tf, NbSeries &s, int &why);
void   NbRecompute();
void   NbEvaluate();
void   NbFillBuffers(int rates_total, const datetime &time[], const double &high[], const double &low[]);
void   NbNyCheck(datetime now);
string NbNyText(datetime now);
void   NbText(string name, datetime t, double price, string txt, color clr, int size, int anchor, string tip);
void   NbLevel(string name, datetime t, double price, color clr, int style, string txt);
void   NbSegment(string name, datetime t1, datetime t2, double price, color clr, int style, string txt);
void   NbDrawChart();
void   NbRect(string id, int x, int y, int w, int h, color bg, color border);
void   NbLabel(string id, int x, int y, string txt, color clr, int size, string font, int anchor);
string NbPx(double v);
color  NbDirColor(int d);
string NbMmSs(long secs);
string NbClockText();
string NbCandleStrip(const NbSeries &s, int i, color &clr);
string NbHms(long secs);
void   NbPreview(bool ok, int i5, int d5, double bid, string &line1, string &line2, color &clr);
void   NbDrawPanel();
void   NbRow(string kid, string vid, int kx, int vx, int y, string key, string val, color vc, color kc, int fs);

//+------------------------------------------------------------------+
int OnInit()
{
   g_P.atrPeriod = InpNrtrAtrPeriod;
   g_P.nrtrMult = InpNrtrMultiplier;
   g_P.emaPeriod = InpEmaPeriod;
   g_P.swing = InpSwingStrength;
   g_P.slBufAtr = InpSlBufferAtr;
   g_P.tp1R = InpTp1R;
   g_P.tp2R = InpTp2R;
   g_P.validBars = InpSignalValidBars;
   g_P.tick = 0.0;
   g_P.digits = 0;
   if(InpRiskPercent < 0.1 || InpRiskPercent > 5.0)
   {
      Print("NRTR BOSS: invalid inputs - risk % must be between 0.1 and 5.0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTp2R <= InpTp1R)
   {
      Print("NRTR BOSS: invalid inputs - TP2 (R) must be strictly greater than TP1 (R)");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!NbParamsValid(g_P) || InpHistoryDays < 3 || InpNyOpenHour < 0 || InpNyOpenHour > 23 ||
      InpNyOpenMinute < 0 || InpNyOpenMinute > 59 || InpPreNyRangeHours < 1 || InpPreNyRangeHours > 12 ||
      InpNyWindowMinutes < 5 || InpNyWindowMinutes > 480 || InpMinRangeBars < 1 || InpSwingDist < 0.0 ||
      InpSwingAtrMult < 0.0)
   {
      Print("NRTR BOSS: invalid inputs");
      return INIT_PARAMETERS_INCORRECT;
   }

   SetIndexBuffer(0, g_bEma, INDICATOR_DATA);
   SetIndexBuffer(1, g_bStop15, INDICATOR_DATA);
   SetIndexBuffer(2, g_bStop15Clr, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(3, g_bExt15, INDICATOR_DATA);
   SetIndexBuffer(4, g_bStop5, INDICATOR_DATA);
   SetIndexBuffer(5, g_bStop5Clr, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(6, g_bArrUp, INDICATOR_DATA);
   SetIndexBuffer(7, g_bArrUpClr, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(8, g_bArrDn, INDICATOR_DATA);
   SetIndexBuffer(9, g_bArrDnClr, INDICATOR_COLOR_INDEX);
   for(int i = 0; i < 6; i++)
   {
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);
      bool on = (i < 4) ? InpDrawChart : InpCandleArrows;
      PlotIndexSetInteger(i, PLOT_DRAW_TYPE, on ? PlotDrawType(i) : (int)DRAW_NONE);
   }
   PlotIndexSetInteger(4, PLOT_ARROW, 233);        // Wingdings up arrow
   PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, 12);
   PlotIndexSetInteger(5, PLOT_ARROW, 234);        // Wingdings down arrow
   PlotIndexSetInteger(5, PLOT_ARROW_SHIFT, -12);

   g_sym = _Symbol;
   g_label = NbMarketLabel(g_sym, SymbolInfoString(g_sym, SYMBOL_CURRENCY_BASE),
                           SymbolInfoString(g_sym, SYMBOL_CURRENCY_PROFIT));
   NbReadSpec();
   IndicatorSetString(INDICATOR_SHORTNAME, "NRTR BOSS NY Trap Panel (CUSTOM ATR-NRTR)");
   IndicatorSetInteger(INDICATOR_DIGITS, g_digits);

   g_P.tick = g_tick;
   g_P.digits = g_digits;
   NbReadClock();

   // Anchor on a calendar day: a restart on the same day reads exactly the
   // same closed bars and therefore shows exactly the same state.
   long nowL = (long)TimeTradeServer();
   g_anchor = (datetime)((nowL / 86400) * 86400 - (long)InpHistoryDays * 86400);

   NbSeriesResize(g_s15, 0);
   NbSeriesResize(g_s5, 0);
   g_s15.sec = PeriodSeconds(PERIOD_M15);
   g_s5.sec = PeriodSeconds(PERIOD_M5);
   ArrayResize(g_sigs, 0);
   g_nSig = 0;
   g_seen15 = 0;
   g_seen5 = 0;
   g_ready = false;
   g_dataR = NB_R_NO_DATA;
   g_bufDirty = true;
   g_fresh = false;
   g_freshCode = NB_FR_NO_BAR;
   g_diagNow = 0;
   g_diagTick = 0;
   g_diagBar05 = 0;
   g_diagBar015 = 0;
   g_final = NB_WAIT;
   g_finalR = (g_label == "") ? NB_R_UNSUPPORTED : NB_R_NO_DATA;
   g_adv = NB_ADV_NONE;
   g_advWhy = NB_WHY_NONE;
   g_advDir = 0;
   g_blink = false;
   g_nyAlertDay = -1;
   g_swingDist = (InpSwingDist > 0.0) ? InpSwingDist : 0.0;   // automatic value arrives with the first recompute

   ObjectsDeleteAll(0, NB_PFX);
   EventSetTimer(1);
   NbUpdate();
   return INIT_SUCCEEDED;
}

int PlotDrawType(int plot)
{
   if(plot == 4 || plot == 5)
      return (int)DRAW_COLOR_ARROW;
   if(plot == 1 || plot == 3)
      return (int)DRAW_COLOR_LINE;
   return (int)DRAW_LINE;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, NB_PFX);
   ChartRedraw(0);
}

void OnTimer()
{
   g_blink = !g_blink;
   NbUpdate();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      NbDrawPanel();
      ChartRedraw(0);
   }
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(rates_total <= 0)
      return 0;
   if(prev_calculated == 0)
      g_bufDirty = true;
   NbUpdate();
   if(g_bufDirty || prev_calculated != rates_total)
      NbFillBuffers(rates_total, time, high, low);
   return rates_total;
}

//+------------------------------------------------------------------+
//| One refresh: new closed bars -> recompute; always re-read        |
//| positions and redraw the panel (price, countdown).               |
//+------------------------------------------------------------------+
void NbUpdate()
{
   if(g_label != "")
   {
      datetime t15 = iTime(g_sym, PERIOD_M15, 1);
      datetime t5 = iTime(g_sym, PERIOD_M5, 1);
      if(!g_ready || t15 != g_seen15 || t5 != g_seen5)
      {
         g_seen15 = t15;
         g_seen5 = t5;
         NbRecompute();
      }
      NbNyCheck(TimeTradeServer());
   }
   NbEvaluate();
   NbDrawPanel();
   ChartRedraw(0);
}

//--- New York open: ONE local pop-up + sound per session, weekdays only,
//    inside the open minute, at the open the SESSION CLOCK computes.
//    Nothing leaves the terminal.
void NbNyCheck(datetime now)
{
   if(!InpNyAlert || !g_S.clockOk || now <= 0)
      return;
   long id = -1;
   datetime open = NbNyOpenOf(now, g_S, id);
   if(now < open || now >= open + 60)
      return;
   long day = (long)open / 86400;
   int wd = (int)((day + 4) % 7);          // 1970-01-01 was a Thursday (4); 0 = Sunday
   if(wd == 0 || wd == 6)
      return;
   if(g_nyAlertDay == id)
      return;
   g_nyAlertDay = id;
   string msg = "NRTR BOSS " + g_sym + ": NEW YORK OPEN (" + TimeToString(open, TIME_MINUTES) + " broker time). Next " +
                IntegerToString(g_S.winMin) + " min: structure flow paused, watching the pre-NY range for a sweep. You decide.";
   Alert(msg);
   PlaySound("alert.wav");
   Print(msg);
}

//--- session row text: countdown to / since the open the session clock computes
string NbNyText(datetime now)
{
   if(!g_S.clockOk)
      return "SESSION CLOCK UNKNOWN - SET MANUAL";
   long id = -1;
   datetime open = NbNyOpenOf(now, g_S, id);
   long d = (long)now - (long)open;
   if(d < 0)
   {
      string pre = (-d <= (long)g_S.preHours * 3600) ? "  -  PRE-NY RANGE BUILDING" : "";
      return "NY OPEN " + TimeToString(open, TIME_MINUTES) + " in " + NbHms(-d) + pre;
   }
   if(d < (long)g_S.winMin * 60)
      return "NY OPEN - WINDOW " + NbHms(d) + " / " + IntegerToString(g_S.winMin) + " MIN: FLOW PAUSED, TRAP ARMED";
   if(d < 6 * 3600)
      return "NEW YORK SESSION - " + NbHms(d) + " since the open  -  STRUCTURE FLOW";
   return "OUTSIDE NY OPEN WINDOW  -  STRUCTURE FLOW";
}

void NbReadSpec()
{
   g_digits = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   g_tick = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   if(g_tick <= 0.0)
      g_tick = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   g_tickValue = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE);
   g_volMin = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   g_volStep = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   g_volMax = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   g_balance = AccountInfoDouble(ACCOUNT_BALANCE);     // read only
   g_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_accCcy = AccountInfoString(ACCOUNT_CURRENCY);
}

//--- the session clock: two witnesses (broker, PC) or a typed time
void NbReadClock()
{
   g_S.preHours = InpPreNyRangeHours;
   g_S.winMin = InpNyWindowMinutes;
   g_S.minRangeBars = InpMinRangeBars;
   g_S.pauseFlow = InpNyPauseFlow;
   g_S.manualOpenSec = InpNyOpenHour * 3600 + InpNyOpenMinute * 60;
   g_S.offset = 0;
   if(InpSessionClock == NB_CLOCK_MANUAL)
   {
      g_S.clockMode = NB_CLK_MANUAL;
      g_S.clockOk = true;
      return;
   }
   g_S.clockMode = NB_CLK_AUTO;
   long off = 0;
   g_S.clockOk = NbClockFromWitnesses(TimeTradeServer(), TimeGMT(), off);
   g_S.offset = off;
}

//--- load CLOSED bars from the anchor to the last closed bar. Bar 0 (the
//    forming one) is never read.
bool NbLoad(ENUM_TIMEFRAMES tf, NbSeries &s, int &why)
{
   int sec = PeriodSeconds(tf);
   s.sec = sec;
   int shift = iBarShift(g_sym, tf, g_anchor, false);
   if(shift < 0)
      shift = Bars(g_sym, tf) - 1;
   if(shift < 1)
   {
      NbSeriesResize(s, 0);
      why = NB_R_NO_DATA;
      return false;
   }
   if(shift > 50000)
      shift = 50000;
   MqlRates r[];
   int got = CopyRates(g_sym, tf, 1, shift, r);
   if(got <= 0)
   {
      NbSeriesResize(s, 0);
      why = NB_R_NO_DATA;
      return false;
   }
   datetime now = TimeTradeServer();
   int n = got;
   while(n > 0 && r[n - 1].time + sec > now)
      n--;
   NbSeriesResize(s, n);
   for(int i = 0; i < n; i++)
   {
      s.t[i] = r[i].time;
      s.o[i] = r[i].open;
      s.h[i] = r[i].high;
      s.l[i] = r[i].low;
      s.c[i] = r[i].close;
   }
   if(n < 2)
   {
      why = NB_R_NO_DATA;
      return false;
   }
   return true;
}

void NbRecompute()
{
   NbReadSpec();
   NbReadClock();
   g_P.tick = g_tick;
   g_P.digits = g_digits;
   g_ready = false;
   g_dataR = 0;
   g_bufDirty = true;
   int why = 0;
   bool ok = NbLoad(PERIOD_M15, g_s15, why);
   if(ok)
      ok = NbLoad(PERIOD_M5, g_s5, why);
   if(!ok)
   {
      g_dataR = (why != 0) ? why : NB_R_NO_DATA;
      g_nSig = 0;
      ArrayResize(g_sigs, 0);
      g_seen15 = 0;   // retry on the next timer tick
      g_seen5 = 0;
      ObjectsDeleteAll(0, NB_PFX_C);
      return;
   }
   NbRun15(g_s15, g_piv15, g_P);
   NbRun5(g_s5, g_piv5, g_s15, true, g_P, g_S, g_sigs, g_nSig);
   g_ready = true;
   // swing TP distance: typed, or automatic from the last CLOSED 15M ATR
   g_swingDist = InpSwingDist;
   if(g_swingDist <= 0.0 && g_s15.n > 0 && g_s15.atr[g_s15.n - 1] > 0.0)
      g_swingDist = NbRoundTick(InpSwingAtrMult * g_s15.atr[g_s15.n - 1], g_tick, g_digits, 0);
   NbDrawChart();
}

//--- decide what the panel shows right now
void NbEvaluate()
{
   g_buyCnt = 0;
   g_buyVol = 0.0;
   g_sellCnt = 0;
   g_sellVol = 0.0;
   datetime buyTime = 0;
   datetime sellTime = 0;
   // READ ONLY: positions are selected for reading and never changed
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_sym)
         continue;
      long ptype = PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      if(ptype == POSITION_TYPE_BUY)
      {
         g_buyCnt++;
         g_buyVol += vol;
         if(buyTime == 0 || ot < buyTime)
            buyTime = ot;
      }
      else if(ptype == POSITION_TYPE_SELL)
      {
         g_sellCnt++;
         g_sellVol += vol;
         if(sellTime == 0 || ot < sellTime)
            sellTime = ot;
      }
   }

   g_adv = NB_ADV_NONE;
   g_advWhy = NB_WHY_NONE;
   g_advDir = 0;
   if(g_label == "")
   {
      g_fresh = false;
      g_final = NB_WAIT;
      g_finalR = NB_R_UNSUPPORTED;
      return;
   }
   if(!g_ready || g_s5.n < 1 || g_s15.n < 1)
   {
      g_fresh = false;
      g_freshCode = NB_FR_NO_BAR;
      g_diagNow = TimeTradeServer();
      g_diagTick = TimeCurrent();
      g_diagBar05 = iTime(g_sym, PERIOD_M5, 0);
      g_diagBar015 = iTime(g_sym, PERIOD_M15, 0);
      g_final = NB_WAIT;
      g_finalR = (g_dataR != 0) ? g_dataR : NB_R_NO_DATA;
      if(g_buyCnt + g_sellCnt > 0)
      {
         g_adv = NB_ADV_UNKNOWN;
         g_advWhy = NB_WHY_UNKNOWN;
      }
      return;
   }
   int n5 = g_s5.n;
   int n15 = g_s15.n;
   datetime now = TimeTradeServer();
   datetime tick = (datetime)SymbolInfoInteger(g_sym, SYMBOL_TIME);
   if(tick <= 0)
      tick = TimeCurrent();
   g_diagNow = now;
   g_diagTick = tick;
   g_diagBar05 = iTime(g_sym, PERIOD_M5, 0);
   g_diagBar015 = iTime(g_sym, PERIOD_M15, 0);
   g_freshCode = NbFreshness(now, tick, g_diagBar05, g_diagBar015, g_s5.t[n5 - 1], g_s15.t[n15 - 1], g_s5.sec, g_s15.sec,
                             InpMaxTickAgeSec, InpMaxClockSkewSec);
   g_fresh = (g_freshCode == NB_FR_OK);
   if(g_freshCode == NB_FR_GAP)
   {
      g_seen15 = 0;   // force a reload on the next tick
      g_seen5 = 0;
   }
   // EXIT / PROTECT is judged on the COMPLETE 15M BOSS mode of the last
   // CLOSED 15M bar (NRTR + EMA200 + confirmed structure), never on the
   // NRTR direction alone.
   int modeNow = g_s15.mode[n15 - 1];

   int advB = NB_ADV_NONE;
   int whyB = NB_WHY_NONE;
   int advS = NB_ADV_NONE;
   int whyS = NB_WHY_NONE;
   if(g_buyCnt > 0)
      advB = NbExitAdvice(1, NbKnownAtTime(g_s15.t, g_s15.mode, n15, g_s15.sec, buyTime), modeNow, whyB);
   if(g_sellCnt > 0)
      advS = NbExitAdvice(-1, NbKnownAtTime(g_s15.t, g_s15.mode, n15, g_s15.sec, sellTime), modeNow, whyS);
   if(!g_fresh && (g_buyCnt + g_sellCnt) > 0)
   {
      g_adv = NB_ADV_UNKNOWN;
      g_advWhy = NB_WHY_UNKNOWN;
   }
   else if(advB == NB_ADV_EXIT)
   {
      g_adv = advB;
      g_advWhy = whyB;
      g_advDir = 1;
   }
   else if(advS == NB_ADV_EXIT)
   {
      g_adv = advS;
      g_advWhy = whyS;
      g_advDir = -1;
   }
   else if(advB != NB_ADV_NONE)
   {
      g_adv = advB;
      g_advWhy = whyB;
      g_advDir = 1;
   }
   else if(advS != NB_ADV_NONE)
   {
      g_adv = advS;
      g_advWhy = whyS;
      g_advDir = -1;
   }
   g_final = NbFinalState(g_s5.state[n5 - 1], g_s5.reasons[n5 - 1], g_fresh, g_adv, g_finalR);
}

//+------------------------------------------------------------------+
//| plot buffers: each chart bar shows the 15M / 5M value that was   |
//| KNOWN when that chart bar closed (no look-ahead on any TF).      |
//+------------------------------------------------------------------+
void NbFillBuffers(int rates_total, const datetime &time[], const double &high[], const double &low[])
{
   g_bufDirty = false;
   int chartSec = PeriodSeconds(_Period);
   bool use5 = (chartSec <= 300);
   int prevAd = 0;
   int n15 = g_ready ? g_s15.n : 0;
   int n5 = g_ready ? g_s5.n : 0;
   int p15 = -1;
   int p5 = -1;
   for(int i = 0; i < rates_total; i++)
   {
      g_bEma[i] = EMPTY_VALUE;
      g_bStop15[i] = EMPTY_VALUE;
      g_bStop15Clr[i] = 0.0;
      g_bExt15[i] = EMPTY_VALUE;
      g_bStop5[i] = EMPTY_VALUE;
      g_bStop5Clr[i] = 0.0;
      g_bArrUp[i] = EMPTY_VALUE;
      g_bArrUpClr[i] = 0.0;
      g_bArrDn[i] = EMPTY_VALUE;
      g_bArrDnClr[i] = 0.0;
      if(n15 == 0)
         continue;
      datetime known = time[i] + chartSec;
      while(p15 + 1 < n15 && g_s15.t[p15 + 1] + g_s15.sec <= known)
         p15++;
      while(p5 + 1 < n5 && g_s5.t[p5 + 1] + g_s5.sec <= known)
         p5++;
      if(p15 >= 0)
      {
         if(g_s15.ema[p15] > 0.0)
            g_bEma[i] = g_s15.ema[p15];
         if(g_s15.dir[p15] != 0)
         {
            g_bStop15[i] = g_s15.stop[p15];
            g_bStop15Clr[i] = (g_s15.dir[p15] > 0) ? 0.0 : 1.0;
            g_bExt15[i] = g_s15.ext[p15];
         }
      }
      if(p5 >= 0 && g_s5.dir[p5] != 0 && chartSec <= 900)
      {
         g_bStop5[i] = g_s5.stop[p5];
         g_bStop5Clr[i] = (g_s5.dir[p5] > 0) ? 0.0 : 1.0;
      }
      // arrow on every CLOSED chart candle: the NRTR direction of the chart's
      // own timeframe class, as known at that candle's close. The forming
      // candle (time + chartSec > known) never gets one. Bright when the 15M
      // boss mode agrees, dim otherwise.
      if(known > TimeTradeServer())
         continue;
      int ad = 0;
      if(use5)
         ad = (p5 >= 0) ? g_s5.dir[p5] : 0;
      else
         ad = (p15 >= 0) ? g_s15.dir[p15] : 0;
      if(ad == 0)
         continue;
      bool flipHere = (ad != prevAd);
      prevAd = ad;
      if(!flipHere && !InpArrowEveryBar)
         continue;
      int bossHere = (p15 >= 0) ? g_s15.mode[p15] : NB_WAIT;
      double clrIdx = (bossHere == ad) ? 0.0 : 1.0;
      if(ad > 0)
      {
         g_bArrUp[i] = low[i];
         g_bArrUpClr[i] = clrIdx;
      }
      else
      {
         g_bArrDn[i] = high[i];
         g_bArrDnClr[i] = clrIdx;
      }
   }
}

//+------------------------------------------------------------------+
//| chart objects: confirmed structure labels, decision markers,     |
//| WAIT markers where the boss drops out of a mode, the pre-NY      |
//| range of the latest session, and the levels of the currently    |
//| clickable learning signal.                                       |
//+------------------------------------------------------------------+
void NbText(string name, datetime t, double price, string txt, color clr, int size, int anchor, string tip)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}

void NbLevel(string name, datetime t, double price, color clr, int style, string txt)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t, price, t + 300, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   NbText(name + "_T", t, price, txt + " " + DoubleToString(price, g_digits), clr, 8, ANCHOR_LEFT_LOWER, txt);
}

//--- a finite horizontal segment (pre-NY range edges)
void NbSegment(string name, datetime t1, datetime t2, double price, color clr, int style, string txt)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   NbText(name + "_T", t1, price, txt + " " + DoubleToString(price, g_digits), clr, 8, ANCHOR_LEFT_LOWER, txt);
}

void NbDrawChart()
{
   ObjectsDeleteAll(0, NB_PFX_C);
   if(!InpDrawChart || !g_ready)
      return;
   int n15 = g_s15.n;
   int n5 = g_s5.n;
   if(n15 < 1 || n5 < 1)
      return;
   // markers only once the EMA has had time to settle
   int warm = (int)MathMin(n15 - 1, InpEmaPeriod);
   datetime tWarm = g_s15.t[warm];
   color cUp = NB_RGB(46, 204, 113);
   color cDn = NB_RGB(231, 76, 60);
   color cWait = NB_RGB(241, 196, 15);
   color cEq = NB_RGB(150, 150, 150);
   color cNy = NB_RGB(155, 89, 182);

   // confirmed 15M structure (drawn at the swing; it appears only after
   // InpSwingStrength more 15M bars have CLOSED and never moves afterwards)
   for(int p = 0; p < g_s15.np; p++)
   {
      if(g_piv15[p].label == NB_L_NONE || g_s15.t[g_piv15[p].idx] < tWarm)
         continue;
      int lbl = g_piv15[p].label;
      color clr = cEq;
      if(lbl == NB_L_HH || lbl == NB_L_HL)
         clr = cUp;
      if(lbl == NB_L_LH || lbl == NB_L_LL)
         clr = cDn;
      string nm = NB_PFX_C + "S_" + IntegerToString(g_piv15[p].idx) + (g_piv15[p].kind > 0 ? "H" : "L");
      NbText(nm, g_s15.t[g_piv15[p].idx], g_piv15[p].price, NbLabelName(lbl), clr, 8,
             g_piv15[p].kind > 0 ? ANCHOR_LOWER : ANCHOR_UPPER,
             "Confirmed 15M swing " + NbLabelName(lbl) + " (known at close of " +
             TimeToString(g_s15.t[g_piv15[p].confirmIdx], TIME_DATE | TIME_MINUTES) + ")");
   }

   // ZigZag: confirmed 15M swings joined in order (appears with the same
   // delay as the labels, never moves afterwards)
   int prevP = -1;
   for(int p = 0; p < g_s15.np; p++)
   {
      if(g_s15.t[g_piv15[p].idx] < tWarm)
         continue;
      if(prevP >= 0 && g_piv15[p].kind != g_piv15[prevP].kind)
      {
         string zn = NB_PFX_C + "Z_" + IntegerToString(g_piv15[p].idx);
         if(ObjectFind(0, zn) < 0)
            ObjectCreate(0, zn, OBJ_TREND, 0, g_s15.t[g_piv15[prevP].idx], g_piv15[prevP].price,
                         g_s15.t[g_piv15[p].idx], g_piv15[p].price);
         ObjectSetInteger(0, zn, OBJPROP_COLOR, NB_RGB(80, 160, 255));
         ObjectSetInteger(0, zn, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, zn, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, zn, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, zn, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, zn, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, zn, OBJPROP_BACK, true);
      }
      prevP = p;
   }

   // WAIT markers: the 15M boss drops out of BUY/SELL mode
   for(int i = warm + 1; i < n15; i++)
   {
      if(g_s15.mode[i - 1] != NB_WAIT && g_s15.mode[i] == NB_WAIT)
      {
         string nm = NB_PFX_C + "W_" + IntegerToString(i);
         NbText(nm, g_s15.t[i], g_s15.h[i], "WAIT", cWait, 8, ANCHOR_LOWER,
                "15M boss left " + NbModeText(g_s15.mode[i - 1]) + ": " + NbReasonAt(g_s15.mr[i], 0));
      }
   }

   // decision markers: one per learning signal (flow and NY trap)
   for(int k = 0; k < g_nSig; k++)
   {
      int s = g_sigs[k].idx;
      if(g_s5.t[s] < tWarm)
         continue;
      string nm = NB_PFX_C + "G_" + IntegerToString(s);
      string side = (g_sigs[k].dir > 0) ? "BUY" : "SELL";
      string kind = (g_sigs[k].kind == NB_K_TRAP) ? "NY TRAP " : "";
      string tip = kind + side + " entry " +
                   DoubleToString(g_sigs[k].entry, g_digits) + " SL " + DoubleToString(g_sigs[k].sl, g_digits) +
                   " TP1 " + DoubleToString(g_sigs[k].tp1, g_digits) + " TP2 " +
                   DoubleToString(g_sigs[k].tp2, g_digits) + " - " + NbSignalStatusText(g_sigs[k].status);
      if(g_sigs[k].kind == NB_K_TRAP)
         tip = tip + " (swept " + DoubleToString(g_sigs[k].level, g_digits) + " to " +
               DoubleToString(g_sigs[k].sweep, g_digits) + ")";
      double off = g_s5.atr[s] * 0.3;
      color mc = (g_sigs[k].kind == NB_K_TRAP) ? cNy : ((g_sigs[k].dir > 0) ? cUp : cDn);
      if(g_sigs[k].dir > 0)
         NbText(nm, g_s5.t[s], g_s5.l[s] - off, NbSymUp() + " " + kind + "BUY", mc, 11, ANCHOR_UPPER, tip);
      else
         NbText(nm, g_s5.t[s], g_s5.h[s] + off, NbSymDown() + " " + kind + "SELL", mc, 11, ANCHOR_LOWER, tip);
   }

   // pre-NY range of the latest session that has one
   for(int i = n5 - 1; i >= 0; i--)
   {
      if(g_s5.ph[i] == NB_PH_OUT || g_s5.rn[i] < 1)
         continue;
      long id = g_s5.sid[i];
      int first = i;
      while(first > 0 && g_s5.sid[first - 1] == id && g_s5.ph[first - 1] != NB_PH_OUT)
         first--;
      datetime t1 = g_s5.t[first];
      datetime t2 = g_s5.t[i] + g_s5.sec;
      string tag = (g_s5.rn[i] >= InpMinRangeBars) ? "PRE-NY HIGH" : "PRE-NY HIGH (building)";
      NbSegment(NB_PFX_C + "R_H", t1, t2, g_s5.rh[i], cNy, STYLE_DASHDOT, tag);
      NbSegment(NB_PFX_C + "R_L", t1, t2, g_s5.rl[i], cNy, STYLE_DASHDOT, "PRE-NY LOW");
      break;
   }

   // levels of the currently clickable signal only
   int cur = g_s5.sigOf[n5 - 1];
   if(cur >= 0 && g_s5.state[n5 - 1] != NB_WAIT && g_sigs[cur].status == NB_SIG_ACTIVE)
   {
      datetime ts = g_s5.t[g_sigs[cur].idx];
      NbLevel(NB_PFX_C + "L_ENTRY", ts, g_sigs[cur].entry, clrWhite, STYLE_SOLID, "ENTRY");
      NbLevel(NB_PFX_C + "L_SL", ts, g_sigs[cur].sl, cDn, STYLE_DASH, "SL");
      NbLevel(NB_PFX_C + "L_TP1", ts, g_sigs[cur].tp1, cUp, STYLE_DASH, "TP1 " + DoubleToString(g_P.tp1R, 1) + "R");
      NbLevel(NB_PFX_C + "L_TP2", ts, g_sigs[cur].tp2, cUp, STYLE_DOT, "TP2 " + DoubleToString(g_P.tp2R, 1) + "R");
      if(g_swingDist > 0.0)
      {
         double sw = NbRoundTick(g_sigs[cur].entry + g_sigs[cur].dir * g_swingDist, g_P.tick, g_P.digits, 0);
         NbLevel(NB_PFX_C + "L_SWING", ts, sw, NB_RGB(80, 160, 255), STYLE_DASHDOT,
                 "SWING TP +" + DoubleToString(g_swingDist, g_digits));
      }
   }
}

//+------------------------------------------------------------------+
//| PANEL                                                            |
//+------------------------------------------------------------------+
void NbRect(string id, int x, int y, int w, int h, color bg, color border)
{
   string name = NB_PFX_P + id;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
}

void NbLabel(string id, int x, int y, string txt, color clr, int size, string font, int anchor)
{
   string name = NB_PFX_P + id;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 11);
}

string NbPx(double v)
{
   if(v <= 0.0)
      return "---";
   return DoubleToString(v, g_digits);
}

color NbDirColor(int d)
{
   if(d > 0)
      return NB_RGB(46, 204, 113);
   if(d < 0)
      return NB_RGB(231, 76, 60);
   return NB_RGB(241, 196, 15);
}

string NbMmSs(long secs)
{
   if(secs < 0)
      secs = 0;
   return IntegerToString(secs / 60, 2, '0') + ":" + IntegerToString(secs % 60, 2, '0');
}

//--- the last five CLOSED candles of a series, oldest first: an arrow per
//    candle (body direction), the up/down count and the net move from the
//    first open to the last close, in price and in ATRs. Display only.
string NbCandleStrip(const NbSeries &s, int i, color &clr)
{
   clr = NB_RGB(95, 105, 120);
   if(i < 0 || s.n < 1)
      return "---";
   int first = (i - 4 >= 0) ? i - 4 : 0;
   string strip = "";
   int up = 0;
   int dn = 0;
   for(int k = first; k <= i; k++)
   {
      if(s.c[k] > s.o[k])
      {
         strip = strip + NbSymUp() + " ";
         up++;
      }
      else if(s.c[k] < s.o[k])
      {
         strip = strip + NbSymDown() + " ";
         dn++;
      }
      else
         strip = strip + "- ";
   }
   double net = s.c[i] - s.o[first];
   string sgn = (net >= 0.0) ? "+" : "-";
   string txt = strip + "  " + IntegerToString(up) + " UP / " + IntegerToString(dn) + " DOWN   net " + sgn +
                DoubleToString(MathAbs(net), g_digits);
   if(s.atr[i] > 0.0)
      txt = txt + "  (" + sgn + DoubleToString(MathAbs(net) / s.atr[i], 1) + " ATR)";
   if(up > dn)
      clr = NB_RGB(46, 204, 113);
   else if(dn > up)
      clr = NB_RGB(231, 76, 60);
   else
      clr = NB_RGB(241, 196, 15);
   return txt;
}

//--- what the session clock is doing, in words
string NbClockText()
{
   if(g_S.clockMode == NB_CLK_MANUAL)
      return "MANUAL: NY OPEN " + IntegerToString(InpNyOpenHour, 2, '0') + ":" +
             IntegerToString(InpNyOpenMinute, 2, '0') + " SERVER";
   if(!g_S.clockOk)
      return "UNKNOWN - BROKER vs PC CLOCK DISAGREE, SET MANUAL";
   long h = g_S.offset / 3600;
   long m = MathAbs(g_S.offset % 3600) / 60;
   string sgn = (g_S.offset >= 0) ? "+" : "-";
   string txt = "AUTO: SERVER = UTC" + sgn + IntegerToString(MathAbs(h));
   if(m != 0)
      txt = txt + ":" + IntegerToString(m, 2, '0');
   return txt + "  (US DST PER DAY)";
}

//--- h:mm:ss when an hour or more, else mm:ss
string NbHms(long secs)
{
   if(secs < 0)
      secs = 0;
   if(secs < 3600)
      return NbMmSs(secs);
   return IntegerToString(secs / 3600) + ":" + NbMmSs(secs % 3600);
}

//--- PREVIEW of the forming 5M candle: what the LAST CLOSED NRTR stop says
//    about the current price. Text + a yellow marker only. It is recomputed
//    every second from the live bid, is never stored, and no decision reads
//    it - the real arrow and the real state arrive at the close.
void NbPreview(bool ok, int i5, int d5, double bid, string &line1, string &line2, color &clr)
{
   line1 = "---";
   line2 = " ";
   clr = NB_RGB(95, 105, 120);
   ObjectsDeleteAll(0, NB_PFX + "V_");
   if(!ok || !g_fresh || d5 == 0 || bid <= 0.0 || !InpPreview)
      return;
   double stop5 = g_s5.stop[i5];
   datetime t0 = iTime(g_sym, PERIOD_M5, 0);
   double o0 = iOpen(g_sym, PERIOD_M5, 0);
   string body = (bid > o0) ? "bullish body" : ((bid < o0) ? "bearish body" : "flat");
   color cUp = NB_RGB(46, 204, 113);
   color cDn = NB_RGB(231, 76, 60);
   color cPv = NB_RGB(241, 196, 15);
   bool wouldFlip = (d5 > 0) ? (bid < stop5) : (bid > stop5);
   if(wouldFlip)
   {
      string flipTo = (d5 > 0) ? "BEARISH" : "BULLISH";
      string side = (d5 > 0) ? "below" : "above";
      line1 = "IF IT CLOSED NOW: 5M NRTR FLIPS " + flipTo + "  (" + body + ")";
      line2 = "price " + NbPx(bid) + " is " + side + " the 5M stop " + NbPx(stop5) + " - wait for the close";
      clr = cPv;
   }
   else
   {
      line1 = "IF IT CLOSED NOW: 5M NRTR STAYS " + NbDirText(d5) + "  (" + body + ")";
      string side = (d5 > 0) ? "below " : "above ";
      line2 = "flips only on a close " + side + NbPx(stop5);
      clr = (d5 > 0) ? cUp : cDn;
   }
   if(t0 > 0)
   {
      string nm = NB_PFX + "V_ARROW";
      int dirPv = wouldFlip ? -d5 : d5;
      NbText(nm, t0, bid, (dirPv > 0 ? NbSymUp() : NbSymDown()) + " ?", cPv, 10, dirPv > 0 ? ANCHOR_UPPER : ANCHOR_LOWER,
             "PREVIEW of the forming 5M candle - not a signal. " + line1);
   }
}

void NbDrawPanel()
{
   double sc = MathMax(0.7, MathMin(1.6, InpPanelScale));
   int W = (int)MathRound(430 * sc);
   int rh = (int)MathRound(17 * sc);
   int pad = (int)MathRound(12 * sc);
   int fs = (int)MathRound(9 * sc);
   int fsH = (int)MathRound(8 * sc);
   int fsT = (int)MathRound(13 * sc);
   int fsB = (int)MathRound(16 * sc);
   int kx = pad;
   int vx = pad + (int)MathRound(150 * sc);
   int bannerH = (int)MathRound(40 * sc);
   int rows = 70;
   int H = pad * 2 + bannerH + rows * rh;

   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int ox = InpPanelX;
   int oy = InpPanelY;
   if(InpPanelCorner == NB_TOP_RIGHT || InpPanelCorner == NB_BOTTOM_RIGHT)
      ox = (int)MathMax(0, cw - W - InpPanelX);
   if(InpPanelCorner == NB_BOTTOM_LEFT || InpPanelCorner == NB_BOTTOM_RIGHT)
      oy = (int)MathMax(0, ch - H - InpPanelY);

   color cBg = NB_RGB(16, 20, 28);
   color cMkt = (NB_MARKET == NB_MKT_CRYPTO) ? NB_RGB(247, 147, 26) : NB_RGB(52, 152, 219);
   color cKey = NB_RGB(140, 150, 165);
   color cVal = NB_RGB(235, 238, 242);
   color cSec = cMkt;
   color cUp = NB_RGB(46, 204, 113);
   color cDn = NB_RGB(231, 76, 60);
   color cWait = NB_RGB(241, 196, 15);
   color cExit = NB_RGB(230, 126, 34);
   color cDim = NB_RGB(95, 105, 120);
   color cNy = NB_RGB(155, 89, 182);

   NbRect("bg", ox, oy, W, H, cBg, cMkt);

   // title
   int y = oy + pad;
   string title = (g_label == "") ? "NRTR BOSS" : (g_label + " NRTR BOSS");
   title = title + ((NB_MARKET == NB_MKT_CRYPTO) ? "  (CRYPTO + NY TRAP)" : "  (FOREX + NY TRAP)");
   NbLabel("title", ox + kx, y, title, cMkt, fsT, "Arial Black", ANCHOR_LEFT_UPPER);
   y += (int)MathRound(rh * 1.4);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   g_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   NbLabel("sym", ox + kx, y, g_sym + "   PRICE " + NbPx(bid), cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(4 * sc);

   bool ok = (g_label != "" && g_ready && g_s15.n > 0 && g_s5.n > 0);
   int i15 = ok ? g_s15.n - 1 : 0;
   int i5 = ok ? g_s5.n - 1 : 0;
   int cur = ok ? g_s5.sigOf[i5] : -1;
   bool live = (cur >= 0 && (g_final == NB_BUY || g_final == NB_SELL) && g_sigs[cur].status == NB_SIG_ACTIVE);
   bool liveTrap = (live && g_sigs[cur].kind == NB_K_TRAP);

   // big state banner
   string st = NbSymDot() + "  WAIT - NO TRADE";
   color bc = cWait;
   if(g_final == NB_BUY)
   {
      st = NbSymUp() + (liveTrap ? "  CLICK BUY - NY TRAP" : "  CLICK BUY");
      bc = liveTrap ? cNy : cUp;
   }
   if(g_final == NB_SELL)
   {
      st = NbSymDown() + (liveTrap ? "  CLICK SELL - NY TRAP" : "  CLICK SELL");
      bc = liveTrap ? cNy : cDn;
   }
   if(g_final == NB_EXIT)
   {
      string exSide = (g_advDir > 0) ? "BUY" : "SELL";
      st = "!  EXIT / PROTECT " + exSide;
      bc = cExit;
   }
   if(g_label == "")
      st = NbSymDot() + "  " + NbMarketOnlyText();
   // blink = a light, not a button: the banner alternates bright / dark
   // while a CLICK state is live. Text never changes, so nothing is lost.
   color bcFill = bc;
   if(InpBlink && g_blink && (g_final == NB_BUY || g_final == NB_SELL))
      bcFill = NB_RGB(16, 20, 28);
   NbRect("banner", ox + kx, y, W - 2 * kx, bannerH, bcFill, bc);
   NbLabel("state", ox + W / 2, y + bannerH / 2, st, (bcFill == bc) ? NB_RGB(10, 12, 16) : bc, fsB, "Arial Black", ANCHOR_CENTER);
   y += bannerH + (int)MathRound(4 * sc);

   // reasons
   string r1 = "";
   string r2 = "";
   if(liveTrap)
   {
      string sideTxt = (g_final == NB_SELL) ? "HIGH" : "LOW";
      r1 = "NY SWEPT PRE-NY " + sideTxt + " " + NbPx(g_sigs[cur].level) + " (to " + NbPx(g_sigs[cur].sweep) + ")";
      r2 = "5M CLOSED BACK INSIDE - FADE THE TRAP. 15M WAS " + NbModeText(g_s15.mode[i15]);
   }
   else if(g_final == NB_BUY)
   {
      r1 = "15M BULLISH + HH/HL + ABOVE EMA200";
      r2 = "5M NRTR BULLISH + CANDLE CLOSED";
   }
   else if(g_final == NB_SELL)
   {
      r1 = "15M BEARISH + LH/LL + BELOW EMA200";
      r2 = "5M NRTR BEARISH + CANDLE CLOSED";
   }
   else if(g_final == NB_EXIT)
   {
      r1 = (g_advWhy == NB_WHY_INVALIDATED) ? "15M TREND INVALIDATED (BOSS FLIPPED)" : "POSITION AGAINST 15M BOSS";
      r2 = "15M BOSS NOW " + NbModeText(g_s15.n > 0 ? g_s15.mode[g_s15.n - 1] : NB_WAIT) + " - YOU DECIDE";
   }
   else
   {
      r1 = NbReasonAt(g_finalR, 0);
      r2 = NbReasonAt(g_finalR, 1);
   }
   NbLabel("r1", ox + kx, y, "REASON: " + r1, cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   y += rh;
   NbLabel("r2", ox + kx, y, (r2 == "") ? " " : ("            " + r2), cVal, fs, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;
   string nyTxt = (g_label == "") ? "---" : NbNyText(TimeTradeServer());
   color nyC = cVal;
   if(StringFind(nyTxt, "NY OPEN - WINDOW") == 0)
      nyC = cNy;
   NbRow("ks", "vs", ox + kx, ox + vx, y, "NEW YORK OPEN", nyTxt, nyC, cKey, fs);
   y += rh;

   // 15M boss
   NbLabel("h15", ox + kx, y + (int)MathRound(3 * sc), "15M BOSS  -  DIRECTION   (CUSTOM ATR-NRTR)", cSec, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(3 * sc);
   int d15 = ok ? g_s15.dir[i15] : 0;
   NbRow("k1", "v1", ox + kx, ox + vx, y, "15M NRTR", ok ? (NbSymDot() + " " + NbDirText(d15)) : "---", ok ? NbDirColor(d15) : cDim, cKey, fs);
   y += rh;
   string chn = "---";
   if(ok && d15 != 0)
      chn = NbPx(NbNrtrUpper(d15, g_s15.stop[i15], g_s15.ext[i15])) + "  /  " + NbPx(NbNrtrLower(d15, g_s15.stop[i15], g_s15.ext[i15]));
   NbRow("k2", "v2", ox + kx, ox + vx, y, "NRTR UPPER / LOWER", chn, cVal, cKey, fs);
   y += rh;
   string lastFlip = "NONE YET";
   if(ok)
   {
      for(int i = i15; i >= 0; i--)
      {
         if(g_s15.flip[i] != 0)
         {
            lastFlip = (g_s15.flip[i] > 0) ? "BULL" : "BEAR";
            lastFlip = lastFlip + " @ " +
                       TimeToString(g_s15.t[i] + g_s15.sec, TIME_MINUTES) + "  " + NbPx(g_s15.c[i]);
            break;
         }
      }
   }
   NbRow("k3", "v3", ox + kx, ox + vx, y, "LAST 15M NRTR FLIP", ok ? lastFlip : "---", cVal, cKey, fs);
   y += rh;
   string emaTxt = "NOT READY";
   int emaDir = 0;
   if(ok && g_s15.ema[i15] > 0.0)
   {
      emaDir = (g_s15.c[i15] > g_s15.ema[i15]) ? 1 : ((g_s15.c[i15] < g_s15.ema[i15]) ? -1 : 0);
      emaTxt = (emaDir > 0) ? "ABOVE" : ((emaDir < 0) ? "BELOW" : "ON");
      emaTxt = emaTxt + "  (" + NbPx(g_s15.ema[i15]) + ")";
   }
   NbRow("k4", "v4", ox + kx, ox + vx, y, "15M CLOSE vs EMA" + IntegerToString(InpEmaPeriod), ok ? emaTxt : "---", ok ? NbDirColor(emaDir) : cDim, cKey, fs);
   y += rh;
   int stv = ok ? g_s15.st[i15] : NB_ST_UNKNOWN;
   color stc = cWait;
   if(stv == NB_ST_BULL)
      stc = cUp;
   if(stv == NB_ST_BEAR)
      stc = cDn;
   NbRow("k5", "v5", ox + kx, ox + vx, y, "15M STRUCTURE", ok ? NbStructText(stv, g_s15.hl[i15], g_s15.ll[i15], g_s15.lk[i15]) : "---", ok ? stc : cDim, cKey, fs);
   y += rh;
   int m15 = ok ? g_s15.mode[i15] : NB_WAIT;
   NbRow("k6", "v6", ox + kx, ox + vx, y, "15M DECISION", ok ? NbModeText(m15) : "---", ok ? NbDirColor(m15) : cDim, cKey, fs);
   y += rh;

   // 5M trigger
   NbLabel("h5", ox + kx, y + (int)MathRound(3 * sc), "5M TRIGGER  -  TIMING", cSec, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(3 * sc);
   int d5 = ok ? g_s5.dir[i5] : 0;
   NbRow("k7", "v7", ox + kx, ox + vx, y, "5M NRTR", ok ? (NbSymDot() + " " + NbDirText(d5)) : "---", ok ? NbDirColor(d5) : cDim, cKey, fs);
   y += rh;
   string candle = "---";
   if(ok)
   {
      datetime nowS = TimeTradeServer();
      datetime b0 = (g_diagBar05 > 0) ? g_diagBar05 : (g_s5.t[i5] + g_s5.sec);
      long left = (long)(b0 + g_s5.sec - nowS);
      candle = "CLOSED " + TimeToString(g_s5.t[i5] + g_s5.sec, TIME_MINUTES) + "   next " + NbMmSs(left);
   }
   NbRow("k8", "v8", ox + kx, ox + vx, y, "5M CANDLE", candle, cVal, cKey, fs);
   y += rh;
   string conf = "---";
   color confC = cDim;
   if(ok)
   {
      if(liveTrap)
         conf = "NY TRAP - STRUCTURE NOT USED";
      else if(g_s5.ph[i5] == NB_PH_NY && g_S.pauseFlow && g_s5.state[i5] == NB_WAIT)
         conf = "PAUSED - NY WINDOW";
      else if(m15 == NB_WAIT)
         conf = "WAIT (15M NOT IN MODE)";
      else if(d5 != m15)
         conf = "WAIT - 5M AGAINST 15M";
      else if(g_s5.state[i5] != NB_WAIT)
         conf = "READY - WITH 15M";
      else
         conf = "WAIT - WITH 15M";
      confC = (g_s5.state[i5] != NB_WAIT) ? (liveTrap ? cNy : NbDirColor(g_s5.state[i5])) : cWait;
   }
   NbRow("k9", "v9", ox + kx, ox + vx, y, "5M CONFIRM", conf, confC, cKey, fs);
   y += rh;
   string pv1 = "";
   string pv2 = "";
   color pvC = cDim;
   NbPreview(ok, i5, d5, bid, pv1, pv2, pvC);
   NbRow("kpv", "vpv", ox + kx, ox + vx, y, "LIVE CANDLE (PREVIEW)", pv1, pvC, cKey, fs);
   y += rh;
   NbLabel("vpv2", ox + vx, y, pv2, cDim, fsH, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;
   // the last five CLOSED candles of each timeframe, oldest on the left
   string c5s = "---";
   string c15s = "---";
   color c5c = cDim;
   color c15c = cDim;
   if(ok)
   {
      c5s = NbCandleStrip(g_s5, i5, c5c);
      c15s = NbCandleStrip(g_s15, i15, c15c);
   }
   NbRow("kc5", "vc5", ox + kx, ox + vx, y, "LAST 5 x 5M CLOSED", c5s, c5c, cKey, fs);
   y += rh;
   NbRow("kc15", "vc15", ox + kx, ox + vx, y, "LAST 5 x 15M CLOSED", c15s, c15c, cKey, fs);
   y += rh;

   // NY session
   NbLabel("hny", ox + kx, y + (int)MathRound(3 * sc), "NY SESSION  -  THE WILDLIFE", cNy, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(3 * sc);
   NbRow("kn1", "vn1", ox + kx, ox + vx, y, "SESSION CLOCK", NbClockText(), g_S.clockOk ? cVal : cWait, cKey, fs);
   y += rh;
   string phase = "---";
   color phaseC = cDim;
   string range = "---";
   string trap = "---";
   color trapC = cDim;
   if(ok && g_S.clockOk)
   {
      int p = g_s5.ph[i5];
      long sidNow = 0;
      datetime open = NbNyOpenOf(g_s5.t[i5], g_S, sidNow);
      datetime nyEnd = open + (datetime)(g_S.winMin * 60);
      phase = NbPhaseText(p);
      if(p == NB_PH_PRE)
         phase = phase + "  (open " + TimeToString(open, TIME_MINUTES) + ")";
      else if(p == NB_PH_NY)
         phase = phase + "  (until " + TimeToString(nyEnd, TIME_MINUTES) + ")";
      else
         phase = phase + "  (next NY " + TimeToString(open, TIME_MINUTES) + ")";
      phaseC = (p == NB_PH_NY) ? cNy : ((p == NB_PH_PRE) ? cVal : cDim);
      if(p != NB_PH_OUT && g_s5.rn[i5] > 0)
      {
         range = "H " + NbPx(g_s5.rh[i5]) + "  /  L " + NbPx(g_s5.rl[i5]) + "   (" + IntegerToString(g_s5.rn[i5]) + " bars";
         range = range + ((g_s5.rn[i5] >= g_S.minRangeBars) ? ")" : (", need " + IntegerToString(g_S.minRangeBars) + ")"));
      }
      if(p == NB_PH_NY)
      {
         if(cur >= 0 && g_sigs[cur].kind == NB_K_TRAP)
         {
            string ts = ((g_sigs[cur].dir > 0) ? "BUY" : "SELL");
            trap = ts + " TRAP @ " + TimeToString(g_s5.t[g_sigs[cur].idx] + g_s5.sec, TIME_MINUTES) + " - " +
                   NbSignalStatusText(g_sigs[cur].status);
            trapC = (g_sigs[cur].status == NB_SIG_ACTIVE) ? cNy : cWait;
         }
         else if(g_s5.rn[i5] < g_S.minRangeBars)
         {
            trap = "NO RANGE - NOTHING TO SWEEP";
            trapC = cWait;
         }
         else if(g_s5.swH[i5] > 0.0)
         {
            trap = "HIGH SWEPT TO " + NbPx(g_s5.swH[i5]) + " - WAIT BEARISH 5M CLOSE INSIDE";
            trapC = cNy;
         }
         else if(g_s5.swL[i5] > 0.0)
         {
            trap = "LOW SWEPT TO " + NbPx(g_s5.swL[i5]) + " - WAIT BULLISH 5M CLOSE INSIDE";
            trapC = cNy;
         }
         else
         {
            trap = "WATCHING - RANGE NOT SWEPT YET";
            trapC = cVal;
         }
      }
      else if(cur >= 0 && g_sigs[cur].kind == NB_K_TRAP)
      {
         string ls = (g_sigs[cur].dir > 0) ? "BUY" : "SELL";
         trap = "LAST TRAP " + ls + " - " + NbSignalStatusText(g_sigs[cur].status);
         trapC = (g_sigs[cur].status == NB_SIG_ACTIVE) ? cNy : cDim;
      }
      else
         trap = "ARMED AT THE NEXT NY OPEN";
   }
   NbRow("kn2", "vn2", ox + kx, ox + vx, y, "PHASE", phase, phaseC, cKey, fs);
   y += rh;
   NbRow("kn3", "vn3", ox + kx, ox + vx, y, "PRE-NY RANGE", range, cVal, cKey, fs);
   y += rh;
   NbRow("kn4", "vn4", ox + kx, ox + vx, y, "NY TRAP", trap, trapC, cKey, fs);
   y += rh;

   // learning levels
   NbLabel("hl", ox + kx, y + (int)MathRound(3 * sc), "LEARNING LEVELS  -  NO ORDER IS SENT", cSec, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(3 * sc);
   string vE = "---";
   string vS = "---";
   string v1 = "---";
   string v2 = "---";
   string vR = "---";
   string vM = "---";
   string vW = "---";
   string vRR = "---";
   string vL = "---";
   color vLc = cDim;
   if(live)
   {
      if(g_tick > 0.0 && g_tickValue > 0.0)
      {
         double atRisk = 0.0;
         double lots = NbLotsForRisk(g_balance, InpRiskPercent, g_sigs[cur].risk, g_tick, g_tickValue, g_volMin,
                                     g_volStep, g_volMax, atRisk);
         if(lots > 0.0)
         {
            vL = DoubleToString(lots, 2) + " LOTS   risks " + DoubleToString(atRisk, 2) + " " + g_accCcy + "  (" +
                 DoubleToString(InpRiskPercent, 1) + "% of " + DoubleToString(g_balance, 0) + ")";
            vLc = cUp;
         }
         else
         {
            vL = "EVEN " + DoubleToString(g_volMin, 2) + " LOT RISKS > " + DoubleToString(InpRiskPercent, 1) + "% - SKIP";
            vLc = cDn;
         }
      }
      if(g_swingDist > 0.0)
      {
         double sw = NbRoundTick(g_sigs[cur].entry + g_sigs[cur].dir * g_swingDist, g_P.tick, g_P.digits, 0);
         vW = NbPx(sw) + "   (entry " + (g_sigs[cur].dir > 0 ? "+ " : "- ") + DoubleToString(g_swingDist, g_digits) + ")";
      }
      vRR = "1 : " + DoubleToString(g_P.tp1R, 1) + "  /  1 : " + DoubleToString(g_P.tp2R, 1);
      vE = NbPx(g_sigs[cur].entry) + "   (5M close " + TimeToString(g_s5.t[g_sigs[cur].idx] + g_s5.sec, TIME_MINUTES) + ")";
      if(liveTrap)
         vS = NbPx(g_sigs[cur].sl) + "   (beyond the sweep)";
      else
         vS = NbPx(g_sigs[cur].sl) + "   (5M swing " + (g_sigs[cur].dir > 0 ? "low" : "high") + ")";
      v1 = NbPx(g_sigs[cur].tp1) + "   (" + DoubleToString(g_P.tp1R, 1) + "R)";
      v2 = NbPx(g_sigs[cur].tp2) + "   (" + DoubleToString(g_P.tp2R, 1) + "R)";
      int ageLeft = g_P.validBars - (i5 - g_sigs[cur].idx);
      vR = DoubleToString(g_sigs[cur].risk, g_digits) + "   valid " + IntegerToString(ageLeft) + " more 5M bars";
      if(g_tick > 0.0 && g_tickValue > 0.0)
      {
         double m1 = g_sigs[cur].risk / g_tick * g_tickValue;
         vM = DoubleToString(m1, 2) + " " + g_accCcy + " / 1 lot   (" + DoubleToString(m1 * g_volMin, 2) + " / " +
              DoubleToString(g_volMin, 2) + ")";
      }
   }
   NbRow("k10", "v10", ox + kx, ox + vx, y, "ENTRY (reference)", vE, cVal, cKey, fs);
   y += rh;
   NbRow("k11", "v11", ox + kx, ox + vx, y, liveTrap ? "SL (sweep)" : "SL (structure)", vS, live ? cDn : cDim, cKey, fs);
   y += rh;
   NbRow("k12", "v12", ox + kx, ox + vx, y, "TP1", v1, live ? cUp : cDim, cKey, fs);
   y += rh;
   NbRow("k13", "v13", ox + kx, ox + vx, y, "TP2", v2, live ? cUp : cDim, cKey, fs);
   y += rh;
   NbRow("k17", "v17", ox + kx, ox + vx, y, "SWING TP (fixed $)", vW, live ? NB_RGB(80, 160, 255) : cDim, cKey, fs);
   y += rh;
   NbRow("k18", "v18", ox + kx, ox + vx, y, "R:R  TP1 / TP2", vRR, live ? cUp : cDim, cKey, fs);
   y += rh;
   NbRow("k14", "v14", ox + kx, ox + vx, y, "RISK (price)", vR, cVal, cKey, fs);
   y += rh;
   NbRow("k15", "v15", ox + kx, ox + vx, y, "RISK (money)", vM, cVal, cKey, fs);
   y += rh;
   NbRow("k21", "v21", ox + kx, ox + vx, y, "BALANCE / EQUITY", DoubleToString(g_balance, 2) + " / " + DoubleToString(g_equity, 2) + " " + g_accCcy, cVal, cKey, fs);
   y += rh;
   NbRow("k22", "v22", ox + kx, ox + vx, y, "LOTS FOR " + DoubleToString(InpRiskPercent, 1) + "% RISK", vL, vLc, cKey, fs);
   y += rh;

   // LIVE BOX: both sides from the same engine rules; the GATE decides
   NbLabel("hb", ox + kx, y + (int)MathRound(3 * sc), "LIVE BOX  -  BOTH SIDES FROM THE SAME RULES  -  THE GATE DECIDES", cSec, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(3 * sc);
   int cxB = ox + vx;
   int cxS = ox + vx + (int)MathRound(135 * sc);
   NbLabel("lbHb", cxB, y, NbSymUp() + " BUY", cUp, fs, "Arial Black", ANCHOR_LEFT_UPPER);
   NbLabel("lbHs", cxS, y, NbSymDown() + " SELL", cDn, fs, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh;
   double pe[2], ps[2], p1[2], p2[2], pr[2];
   bool pok[2];
   for(int q = 0; q < 2; q++)
   {
      int sd = (q == 0) ? 1 : -1;
      pok[q] = ok && NbPlanSide(g_s5.c, g_s5.atr, g_piv5, g_s5.np, i5, sd, g_P, pe[q], ps[q], p1[q], p2[q], pr[q]);
      if(!pok[q])
      {
         pe[q] = 0.0; ps[q] = 0.0; p1[q] = 0.0; p2[q] = 0.0; pr[q] = 0.0;
      }
   }
   string lbKeys[6] = {"ENTRY", "STOP LOSS", "TP1", "TP2", "SWING TP", "LOTS " + DoubleToString(InpRiskPercent, 1) + "%"};
   for(int rI = 0; rI < 6; rI++)
   {
      string vb = "---";
      string vs2 = "---";
      for(int q = 0; q < 2; q++)
      {
         if(!pok[q])
            continue;
         int sd = (q == 0) ? 1 : -1;
         string txt = "---";
         if(rI == 0) txt = NbPx(pe[q]);
         if(rI == 1) txt = NbPx(ps[q]);
         if(rI == 2) txt = NbPx(p1[q]);
         if(rI == 3) txt = NbPx(p2[q]);
         if(rI == 4) txt = (g_swingDist > 0.0) ? NbPx(NbRoundTick(pe[q] + sd * g_swingDist, g_P.tick, g_P.digits, 0)) : "---";
         if(rI == 5)
         {
            double atRisk = 0.0;
            double lots = (g_tick > 0.0 && g_tickValue > 0.0)
                          ? NbLotsForRisk(g_balance, InpRiskPercent, pr[q], g_tick, g_tickValue, g_volMin, g_volStep, g_volMax, atRisk)
                          : 0.0;
            txt = (lots > 0.0) ? (DoubleToString(lots, 2) + "  (" + DoubleToString(atRisk, 0) + " " + g_accCcy + ")") : "SKIP";
         }
         if(q == 0) vb = txt; else vs2 = txt;
      }
      string kid = "lbK" + IntegerToString(rI);
      NbLabel(kid, ox + kx, y, lbKeys[rI], cKey, fs, "Arial", ANCHOR_LEFT_UPPER);
      NbLabel("lbB" + IntegerToString(rI), cxB, y, vb, pok[0] ? cVal : cDim, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NbLabel("lbS" + IntegerToString(rI), cxS, y, vs2, pok[1] ? cVal : cDim, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      y += rh;
   }
   // GATE line per side
   string gB = "---";
   string gS = "---";
   color gBc = cDim;
   color gSc = cDim;
   if(ok)
   {
      for(int q = 0; q < 2; q++)
      {
         int sd = (q == 0) ? 1 : -1;
         string g = "";
         color gc = cWait;
         if(g_final == sd)
         {
            g = "READY - CLICK";
            gc = (sd > 0) ? cUp : cDn;
         }
         else if(!g_fresh)
            g = "DATA STALE";
         else if(m15 == -sd)
            g = "15M BOSS " + NbModeText(m15);
         else if(m15 == NB_WAIT)
            g = "15M: " + NbReasonAt(g_s15.mr[i15], 0);
         else if(d5 != sd)
            g = "5M NRTR AGAINST";
         else if(!pok[q])
            g = "NO CONFIRMED 5M SWING FOR SL";
         else
            g = NbReasonAt(g_s5.reasons[i5], 0);
         if(g == "")
            g = "WAIT";
         if(q == 0) { gB = g; gBc = gc; } else { gS = g; gSc = gc; }
      }
   }
   NbLabel("lbKg", ox + kx, y, "GATE", cKey, fs, "Arial", ANCHOR_LEFT_UPPER);
   NbLabel("lbGb", cxB, y, gB, gBc, fsH, "Arial Bold", ANCHOR_LEFT_UPPER);
   NbLabel("lbGs", cxS, y, gS, gSc, fsH, "Arial Bold", ANCHOR_LEFT_UPPER);
   y += rh;

   // pending-order REFERENCE prices (nothing is sent)
   NbLabel("hq", ox + kx, y + (int)MathRound(3 * sc), "PENDING ORDER REFERENCE  -  YOU TYPE IT, NOTHING IS SENT", cSec, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(3 * sc);
   string pLim = "---";
   string pStp = "---";
   color pC = cDim;
   if(ok && m15 != NB_WAIT && d15 != 0)
   {
      double up15 = NbNrtrUpper(d15, g_s15.stop[i15], g_s15.ext[i15]);
      double lo15 = NbNrtrLower(d15, g_s15.stop[i15], g_s15.ext[i15]);
      pC = NbDirColor(m15);
      if(m15 == NB_BUY)
      {
         pLim = "BUY LIMIT near 5M NRTR stop " + NbPx(d5 > 0 ? g_s5.stop[i5] : 0.0) + "  (pullback)";
         pStp = "BUY STOP above 15M channel " + NbPx(up15) + "  (breakout)";
      }
      else
      {
         pLim = "SELL LIMIT near 5M NRTR stop " + NbPx(d5 < 0 ? g_s5.stop[i5] : 0.0) + "  (pullback)";
         pStp = "SELL STOP below 15M channel " + NbPx(lo15) + "  (breakout)";
      }
   }
   else if(ok)
   {
      pLim = "15M boss is WAIT - no pending idea";
      pStp = "swing distance for " + g_sym + ": " + DoubleToString(g_swingDist, g_digits);
   }
   NbRow("k19", "v19", ox + kx, ox + vx, y, "PULLBACK", pLim, pC, cKey, fs);
   y += rh;
   NbRow("k20", "v20", ox + kx, ox + vx, y, "BREAKOUT", pStp, pC, cKey, fs);
   y += rh;

   // position (read only)
   NbLabel("hp", ox + kx, y + (int)MathRound(3 * sc), "POSITION  -  READ ONLY", cSec, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(3 * sc);
   string pos = "NO POSITION";
   string posWhy = " ";
   color posC = cDim;
   if(g_buyCnt + g_sellCnt > 0)
   {
      pos = "";
      if(g_buyCnt > 0)
         pos = "BUY " + DoubleToString(g_buyVol, 2);
      if(g_sellCnt > 0)
         pos = pos + (pos == "" ? "" : "  +  ") + "SELL " + DoubleToString(g_sellVol, 2);
      posC = cVal;
      if(g_adv == NB_ADV_EXIT)
      {
         string pSide = (g_advDir > 0) ? "BUY" : "SELL";
         string pWhy = (g_advWhy == NB_WHY_INVALIDATED) ? "15M TREND INVALIDATED" : "AGAINST 15M BOSS";
         posWhy = "EXIT / PROTECT " + pSide + ": " + pWhy;
         posC = cExit;
      }
      else if(g_adv == NB_ADV_HOLD)
      {
         posWhy = "15M REGIME INTACT - BOSS " + NbModeText(g_advDir);
         posC = cUp;
      }
      else if(g_advWhy == NB_WHY_BOSS_WAIT)
      {
         posWhy = "PROTECT - 15M BOSS WAIT, NOT INVALIDATED";
         if(g_ready && g_s15.n > 0)
         {
            string w0 = NbReasonAt(g_s15.mr[g_s15.n - 1], 0);
            if(w0 != "")
               posWhy = posWhy + ": " + w0;
         }
         posC = cExit;
      }
      else
      {
         posWhy = "CANNOT JUDGE - 15M DATA NOT VALID";
         posC = cWait;
      }
   }
   NbRow("k16", "v16", ox + kx, ox + vx, y, "OPEN ON " + g_sym, pos, cVal, cKey, fs);
   y += rh;
   NbLabel("pw", ox + kx, y, posWhy, posC, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(4 * sc);

   // DATA CLOCK: every freshness witness, so a STALE verdict can be checked
   NbLabel("hd", ox + kx, y + (int)MathRound(3 * sc), "DATA CLOCK  -  WHY LIVE OR STALE", cSec, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(3 * sc);
   string dBroker = (g_diagTick > 0) ? TimeToString(g_diagTick, TIME_DATE | TIME_SECONDS) : "---";
   string dServer = (g_diagNow > 0) ? TimeToString(g_diagNow, TIME_DATE | TIME_SECONDS) : "---";
   long skew = (g_diagTick > 0 && g_diagNow > 0) ? ((long)g_diagTick - (long)g_diagNow) : 0;
   NbRow("kd1", "vd1", ox + kx, ox + vx, y, "BROKER TIME (last tick)", dBroker + ((g_diagNow > 0) ? ("   age " + NbHms((long)g_diagNow - (long)g_diagTick)) : ""), cVal, cKey, fs);
   y += rh;
   NbRow("kd2", "vd2", ox + kx, ox + vx, y, "SERVER CLOCK (estimate)", dServer + "   skew " + IntegerToString(skew) + "s", cVal, cKey, fs);
   y += rh;
   string m5c = ok ? (TimeToString(g_s5.t[i5], TIME_DATE | TIME_MINUTES) + "   age " + NbHms((long)g_diagNow - (long)(g_s5.t[i5] + g_s5.sec))) : "---";
   string m15c = ok ? (TimeToString(g_s15.t[i15], TIME_DATE | TIME_MINUTES) + "   age " + NbHms((long)g_diagNow - (long)(g_s15.t[i15] + g_s15.sec))) : "---";
   NbRow("kd3", "vd3", ox + kx, ox + vx, y, "LAST M5 CLOSED", m5c, cVal, cKey, fs);
   y += rh;
   NbRow("kd4", "vd4", ox + kx, ox + vx, y, "LAST M15 CLOSED", m15c, cVal, cKey, fs);
   y += rh;
   string f5 = (g_diagBar05 > 0) ? (TimeToString(g_diagBar05, TIME_MINUTES) + "   age " + NbHms((long)g_diagTick - (long)g_diagBar05)) : "---";
   string f15 = (g_diagBar015 > 0) ? (TimeToString(g_diagBar015, TIME_MINUTES) + "   age " + NbHms((long)g_diagTick - (long)g_diagBar015)) : "---";
   NbRow("kd5", "vd5", ox + kx, ox + vx, y, "FORMING M5 / M15", f5 + "  /  " + f15, cVal, cKey, fs);
   y += rh;
   NbRow("kd6", "vd6", ox + kx, ox + vx, y, "STALE THRESHOLD", "tick > " + IntegerToString(InpMaxTickAgeSec) + "s  or  forming bar > 2 bars old  or  clock skew > " + IntegerToString(InpMaxClockSkewSec) + "s", cVal, cKey, fs);
   y += rh;
   string dStatus = (g_label == "") ? "---" : NbFreshText(g_freshCode);
   NbRow("kd7", "vd7", ox + kx, ox + vx, y, "DATA STATUS", dStatus, g_fresh ? cUp : cDn, cKey, fs);
   y += rh;

   // how to read the chart (the three tools, in one line each)
   NbLabel("hg", ox + kx, y + (int)MathRound(3 * sc), "HOW TO READ THE CHART", cSec, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(3 * sc);
   NbLabel("g1", ox + kx, y, "NRTR CHANNEL: thick stop line. Green under price = BULLISH, red over = BEARISH.", cVal, fsH, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;
   NbLabel("g2", ox + kx, y, "ZIGZAG (blue): confirmed swings. HH+HL = up, LH+LL = down. Shown " + IntegerToString(InpSwingStrength) + " bars late, never moves.", cVal, fsH, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;
   NbLabel("g3", ox + kx, y, "EMA200 (blue line): filter. Close above = BUY side only, below = SELL side only.", cVal, fsH, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;
   NbLabel("g4", ox + kx, y, "ARROW = NRTR flip on a CLOSED candle (bright = with 15M boss). Yellow ? = preview only.", cVal, fsH, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;
   NbLabel("g5", ox + kx, y, "NY TRAP (purple): pre-NY range (dashed) swept, then a 5M close back inside. Purple marker = trap.", cVal, fsH, "Arial", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(4 * sc);

   NbLabel("f1", ox + kx, y, "Learning tool. Aligned conditions, not a profit promise. Count the markers.", cDim, fsH, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;
   NbLabel("f2", ox + kx, y, "It never places, changes or closes an order. You decide.", cDim, fsH, "Arial", ANCHOR_LEFT_UPPER);
}

void NbRow(string kid, string vid, int kx, int vx, int y, string key, string val, color vc, color kc, int fs)
{
   NbLabel(kid, kx, y, key, kc, fs, "Arial", ANCHOR_LEFT_UPPER);
   NbLabel(vid, vx, y, val, vc, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
}
//+------------------------------------------------------------------+
