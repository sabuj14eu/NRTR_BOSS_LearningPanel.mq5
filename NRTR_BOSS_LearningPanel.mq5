//+------------------------------------------------------------------+
//|                                     NRTR_BOSS_LearningPanel.mq5  |
//|             Gold / Silver learning & decision-support panel      |
//|                                                                  |
//|  15M = BOSS / DIRECTION   (NRTR + EMA200 + confirmed structure)  |
//|   5M = ENTRY TRIGGER      (NRTR + CLOSED confirmation candle)    |
//|                                                                  |
//|  VISUAL ONLY. This indicator never sends, modifies or closes an  |
//|  order or position. It may READ open positions on this symbol to |
//|  show EXIT / PROTECT advice; it never changes the account.       |
//|  (MT5 also blocks trade functions inside indicators by design.)  |
//|                                                                  |
//|  "CLICK BUY" means: the defined conditions are currently aligned |
//|  for the educational setup. It is NOT a profit guarantee.        |
//|                                                                  |
//|  Supported symbols: Gold (XAUUSD / GOLD) and Silver (XAGUSD /    |
//|  SILVER), with any broker prefix/suffix. Nothing else.           |
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
//|  * SWING TP = entry +/- a fixed distance per metal (inputs,      |
//|    default gold 20.00, silver 2.00) and pending-order REFERENCE  |
//|    prices (pullback limit at the 5M NRTR stop, breakout stop at  |
//|    the 15M NRTR channel edge). Reference only, nothing is sent.  |
//|  * NEW YORK OPEN: one MT5 pop-up + sound at the broker time you  |
//|    set, and a WAIT note for the first N minutes. Local only.     |
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
//|  v1.05 FIVE-QUESTION PLAN (the same table as the crypto / forex  |
//|    twins, bottom middle; the main panel is unchanged): TREND =   |
//|    15M HH/HL or LH/LL; LOCATION = at a mapped level (prev day    |
//|    H/L, Asia H/L, London H/L, confirmed 15M swings); LIQUIDITY = |
//|    swept, or broken by a 5M close; CONFIRMATION = 5M close       |
//|    beyond the sweep candle (or the breakout close); REWARD =     |
//|    next level >= 1.5R. All five = READY: a PENDING LIMIT at the  |
//|    level, SL beyond the structure, TP1/TP2 = the next levels.    |
//|    SILVER gets a wider stop and a stronger confirmation close    |
//|    (inputs). Asia / London need the broker clock proven by two   |
//|    witnesses (server vs PC). Stale data = NO TRADE. Every plan   |
//|    is recorded and counted. Nothing is sent. See CHANGELOG.md.   |
//+------------------------------------------------------------------+
#property copyright   "Personal use - learning tool"
#property version     "1.05"
#property description "Gold/Silver NRTR BOSS learning panel: 15M direction, 5M timing. CUSTOM ATR-NRTR."
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
#define NB_R_COUNT            20

// learning-signal outcome
#define NB_SIG_ACTIVE    1
#define NB_SIG_EXPIRED   2
#define NB_SIG_TP1       3
#define NB_SIG_SL        4
#define NB_SIG_CANCELLED 5

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

// supported metals
#define NB_METAL_NONE   0
#define NB_METAL_GOLD   1
#define NB_METAL_SILVER 2

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
   double   entry;
   double   sl;
   double   tp1;
   double   tp2;
   double   risk;
   int      status;       // NB_SIG_*
   int      statusIdx;
   int      swingIdx;     // pivot used for the SL
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

//--- 5M trigger pass. An "episode" is a stretch where the 15M mode and the
//    5M NRTR point the same way. Inside an episode the FIRST closed candle
//    in that direction (with a valid structural stop) is the learning signal;
//    it stays CLICK-able until it expires, reaches TP1 or hits its SL. A new
//    signal needs a new episode (5M pulls back against 15M, then realigns).
//    lastClosed=false: the last bar is still forming and is NOT evaluated.
void NbRunTrigger(const double &o[], const double &h[], const double &l[], const double &c[],
                  const double &atr5[], const int &dir5[], const int &boss[], const int &bossR[],
                  const NbPivot &piv[], int np, int n, bool lastClosed, const NbParams &P,
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
      // 2) episode bookkeeping
      int b = boss[s];
      int d = dir5[s];
      int align = (b != 0 && d == b) ? b : 0;
      if(align != epDir)
      {
         if(cur >= 0 && sigs[cur].status == NB_SIG_ACTIVE)
         {
            sigs[cur].status = NB_SIG_CANCELLED;
            sigs[cur].statusIdx = s;
         }
         epDir = align;
         cur = -1;
      }
      // 3) decision
      int r = 0;
      if(b == 0)
         r |= bossR[s];
      else if(d == 0)
         r |= NB_R_5M_NOT_READY;
      else if(d != b)
         r |= NB_R_5M_AGAINST;
      else
      {
         if(cur < 0)
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
                  double minRisk = (P.tick > 0.0) ? P.tick * 0.5 : 0.0;
                  if(risk <= minRisk || risk <= 0.0)
                     r |= NB_R_5M_NO_STOP;
                  else
                  {
                     ArrayResize(sigs, nSig + 1, 64);
                     sigs[nSig].idx = s;
                     sigs[nSig].dir = b;
                     sigs[nSig].entry = entry;
                     sigs[nSig].sl = sl;
                     sigs[nSig].tp1 = NbRoundTick(entry + b * P.tp1R * risk, P.tick, P.digits, 0);
                     sigs[nSig].tp2 = NbRoundTick(entry + b * P.tp2R * risk, P.tick, P.digits, 0);
                     sigs[nSig].risk = risk;
                     sigs[nSig].status = NB_SIG_ACTIVE;
                     sigs[nSig].statusIdx = s;
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
      sigOf[s] = cur;
      if(r == 0 && cur >= 0 && sigs[cur].status == NB_SIG_ACTIVE)
      {
         state[s] = b;
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
            NbSignal &sigs[], int &nSig)
{
   int n = s.n;
   NbCalcATR(s.h, s.l, s.c, n, P.atrPeriod, s.atr);
   NbCalcNRTR(s.c, s.atr, n, P.nrtrMult, s.dir, s.stop, s.ext, s.flip);
   s.np = NbFindPivots(s.h, s.l, n, P.swing, piv);
   NbAlign(b.t, b.n, b.sec, s.t, n, s.sec, s.map);
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

//--- Gold / Silver only. Broker prefixes/suffixes are fine (XAUUSD.m, #XAGUSD).
int NbMetalOf(string name, string base, string profitCcy)
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
   string b = base;
   StringToUpper(b);
   string q = profitCcy;
   StringToUpper(q);
   if(q != "" && q != "USD")
      return NB_METAL_NONE;
   if(StringFind(u, "XAU") == 0 || StringFind(u, "GOLD") == 0 || b == "XAU")
      return NB_METAL_GOLD;
   if(StringFind(u, "XAG") == 0 || StringFind(u, "SILVER") == 0 || b == "XAG")
      return NB_METAL_SILVER;
   return NB_METAL_NONE;
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

// reasons in the order a beginner should read them
int NbReasonBit(int k)
{
   switch(k)
   {
      case 0:  return NB_R_UNSUPPORTED;
      case 1:  return NB_R_STALE;
      case 2:  return NB_R_NO_DATA;
      case 3:  return NB_R_NO_15M_BAR;
      case 4:  return NB_R_NRTR15_NOT_READY;
      case 5:  return NB_R_EMA_NOT_READY;
      case 6:  return NB_R_STRUCT_UNCONF;
      case 7:  return NB_R_STRUCT_MIXED;
      case 8:  return NB_R_NRTR_CONFLICT;
      case 9:  return NB_R_EMA_CONFLICT;
      case 10: return NB_R_STRUCT_CONFLICT;
      case 11: return NB_R_EMA_FLAT;
      case 12: return NB_R_5M_NOT_READY;
      case 13: return NB_R_5M_AGAINST;
      case 14: return NB_R_CANDLE_OPEN;
      case 15: return NB_R_5M_WAIT_CANDLE;
      case 16: return NB_R_5M_NO_STOP;
      case 17: return NB_R_SIG_SL;
      case 18: return NB_R_SIG_TP1;
      case 19: return NB_R_SIG_EXPIRED;
   }
   return 0;
}

string NbReasonName(int bit)
{
   switch(bit)
   {
      case NB_R_UNSUPPORTED:      return "GOLD / SILVER ONLY";
      case NB_R_STALE:            return "DATA STALE / MARKET CLOSED";
      case NB_R_NO_DATA:          return "MISSING DATA - NOT ENOUGH HISTORY";
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
      case NB_SIG_CANCELLED: return "cancelled (5M or 15M turned)";
   }
   return "";
}

//=== NB_FQ_BEGIN === (identical text in all three files - tests/check_fq_blocks.py)
//+------------------------------------------------------------------+
//| v1.05 FIVE-QUESTION PLAN (the bottom-middle table)               |
//| A SECOND, SEPARATE rule set. It does not read or change the main |
//| panel's decision; it answers five questions on every CLOSED 5M   |
//| bar, with the 15M as the map:                                    |
//|   1 TREND         15M confirmed structure: HH+HL or LH+LL        |
//|   2 LOCATION      price is at a mapped level (previous broker day |
//|                   high/low, Asia high/low, London high/low, the  |
//|                   last confirmed 15M swings), not in the middle  |
//|   3 LIQUIDITY     the level was SWEPT (pierced from the trade    |
//|                   side, then back) or BROKEN by a 5M CLOSE       |
//|   4 CONFIRMATION  sweep: a 5M candle CLOSES beyond the sweep     |
//|                   candle's high (low) with its body; breakout:   |
//|                   the breakout close itself (a body, not a wick) |
//|   5 REWARD        the next mapped level is >= minRR away         |
//| All five = READY: a PENDING LIMIT at the level (the retest), SL  |
//| beyond the structure, TP1 / TP2 = the next mapped levels. With   |
//| the 15M trend only (no counter-trend plan). A plan is frozen at  |
//| the close where it appears and followed bar by bar; its outcome  |
//| is recorded so it can be COUNTED (n<20 is luck, ~100 to judge).  |
//| Causal: bar i uses 5M bars <= i, 15M bars closed by then, swings |
//| confirmed by then, session ranges that had ENDED by then.        |
//| It never places anything. It is a plan you may type yourself.    |
//+------------------------------------------------------------------+

// level sources (bit mask: one merged level can carry several)
#define NB_LV_PDH 0x1     // previous broker day high
#define NB_LV_PDL 0x2     // previous broker day low
#define NB_LV_ASH 0x4     // Asia high (latest ENDED Asia window)
#define NB_LV_ASL 0x8     // Asia low
#define NB_LV_LOH 0x10    // London high (latest ENDED London window)
#define NB_LV_LOL 0x20    // London low
#define NB_LV_SWH 0x40    // confirmed 15M swing high
#define NB_LV_SWL 0x80    // confirmed 15M swing low

#define NB_FQ_SWINGS        4     // last confirmed 15M swing highs AND lows used as levels (each)
#define NB_FQ_SESS_MIN_BARS 12    // a day / Asia / London range needs >= this many closed 5M bars
#define NB_FQ_OPEN_MAX      144   // a filled plan with neither TP1 nor SL after 144 x 5M (12 h) = TIMED OUT

// plan kind
#define NB_PK_NONE  0
#define NB_PK_SWEEP 1     // sweep -> rejection -> structure break -> retest
#define NB_PK_BREAK 2     // breakout / breakdown close -> retest -> continuation

// table status of a closed 5M bar
#define NB_FQ_NOTRADE 0   // a question is badly missing (no trend, no data)
#define NB_FQ_WATCH   1   // trend yes, no sweep / break at a level yet (levels drawn in advance)
#define NB_FQ_SETUP   2   // swept, waiting for the confirmation close
#define NB_FQ_SKIP    3   // confirmed, but no stop / no target / not enough room
#define NB_FQ_READY   4   // all five YES: the pending limit is valid
#define NB_FQ_FILLED  5   // the limit was touched: running to TP1 / SL

// the one reason behind the status
#define NB_FW_NONE      0
#define NB_FW_NO_DATA   1
#define NB_FW_UNCONF    2
#define NB_FW_MIXED     3
#define NB_FW_NO_LEVELS 4
#define NB_FW_MIDDLE    5
#define NB_FW_AT_LEVEL  6
#define NB_FW_WAIT_CONF 7
#define NB_FW_NO_STOP   8
#define NB_FW_NO_TARGET 9
#define NB_FW_LOW_RR    10
#define NB_FW_PENDING   11
#define NB_FW_FILLED    12
#define NB_FW_AT_BREAK  13   // at the level a breakout / breakdown close would break

// plan outcome
#define NB_PO_PENDING   1   // limit not touched yet
#define NB_PO_FILLED    2   // limit touched, open
#define NB_PO_TP1       3
#define NB_PO_SL        4
#define NB_PO_EXPIRED   5   // not filled within validBars
#define NB_PO_MISSED    6   // price reached TP1 before the limit filled (no chase)
#define NB_PO_CANCELLED 7   // 15M structure turned while the limit was pending
#define NB_PO_TIMEOUT   8   // filled, neither TP1 nor SL within NB_FQ_OPEN_MAX bars

struct NbFqCfg
{
   double   zoneAtr;       // level zone half-width and merge width, x 15M ATR
   int      window;        // sweep / breakout must be inside the last `window` closed 5M bars
   double   minRR;         // minimum reward to TP1, in R
   int      validBars;     // a pending limit lives this many closed 5M bars
   int      openMax;       // a filled plan times out after this many closed 5M bars
   int      asiaStart;     // UTC hours [start, end)
   int      asiaEnd;
   int      lonStart;
   int      lonEnd;
   bool     clockOk;       // Asia / London need a known UTC offset; the day levels do not
   long     offset;        // broker server time - UTC, seconds
   double   slBufMult;     // v1.06: SL buffer multiplier (1.0; silver: wider stops)
   double   confirmAtr;    // v1.06: the confirmation close must pass by this x 5M ATR (0; silver: stronger)
};

struct NbLv
{
   double   price;
   int      src;           // NB_LV_* mask
   int      pri;           // merge priority: 1 day, 2 London, 3 Asia, 4 swing (lower wins)
};

struct NbFqPlan
{
   int      idx;           // 5M bar at whose close the plan appeared (READY)
   int      dir;           // NB_BUY / NB_SELL
   int      kind;          // NB_PK_*
   double   level;
   int      src;
   int      event;         // pierce bar (sweep) or breakout close bar
   double   ext;           // sweep extreme (sweep only)
   double   trig;          // price the confirmation close had to pass (sweep only)
   int      conf;          // confirmation bar
   double   entry;         // the pending LIMIT = the level (the retest)
   double   sl;
   double   tp1;
   double   tp2;           // 0 = no second level mapped
   int      tp1Src;
   int      tp2Src;
   double   risk;
   double   rr1;
   double   rr2;
   int      status;        // NB_PO_*
   int      fillIdx;       // -1 = not filled
   int      statusIdx;     // bar where the outcome was decided
};

struct NbFqBar
{
   // session levels known at this bar's close (0 = not known)
   double   pdh;
   double   pdl;
   double   ash;
   double   asl;
   double   loh;
   double   lol;
   // the map around the close
   double   zone;
   double   sup;           // nearest level below the close (0 = none)
   int      supSrc;
   double   sup2;          // the one after it
   double   res;           // nearest level above the close
   int      resSrc;
   double   res2;
   // the five questions
   int      trend;         // +1 15M BULL structure, -1 BEAR, 0 none
   int      status;        // NB_FQ_*
   int      why;           // NB_FW_*
   int      kind;          // candidate / plan kind
   double   level;
   int      src;
   int      event;
   double   ext;
   double   trig;
   int      conf;          // -1 = not confirmed
   double   entry;
   double   sl;
   double   tp1;
   double   tp2;
   int      tp1Src;
   int      tp2Src;
   double   risk;
   double   rr1;
   double   rr2;
   int      plan;          // live plan, else the latest plan, else -1
   bool     forming;       // carried from the previous closed bar, never evaluated
};

//--- decision fields only (the session levels are filled separately)
void NbFqReset(NbFqBar &b)
{
   b.zone = 0.0;
   b.sup = 0.0;
   b.supSrc = 0;
   b.sup2 = 0.0;
   b.res = 0.0;
   b.resSrc = 0;
   b.res2 = 0.0;
   b.trend = 0;
   b.status = NB_FQ_NOTRADE;
   b.why = NB_FW_NONE;
   b.kind = NB_PK_NONE;
   b.level = 0.0;
   b.src = 0;
   b.event = -1;
   b.ext = 0.0;
   b.trig = 0.0;
   b.conf = -1;
   b.entry = 0.0;
   b.sl = 0.0;
   b.tp1 = 0.0;
   b.tp2 = 0.0;
   b.tp1Src = 0;
   b.tp2Src = 0;
   b.risk = 0.0;
   b.rr1 = 0.0;
   b.rr2 = 0.0;
   b.plan = -1;
   b.forming = false;
}

void NbFqCopy(NbFqBar &d, const NbFqBar &s)
{
   d.zone = s.zone;
   d.sup = s.sup;
   d.supSrc = s.supSrc;
   d.sup2 = s.sup2;
   d.res = s.res;
   d.resSrc = s.resSrc;
   d.res2 = s.res2;
   d.trend = s.trend;
   d.status = s.status;
   d.why = s.why;
   d.kind = s.kind;
   d.level = s.level;
   d.src = s.src;
   d.event = s.event;
   d.ext = s.ext;
   d.trig = s.trig;
   d.conf = s.conf;
   d.entry = s.entry;
   d.sl = s.sl;
   d.tp1 = s.tp1;
   d.tp2 = s.tp2;
   d.tp1Src = s.tp1Src;
   d.tp2Src = s.tp2Src;
   d.risk = s.risk;
   d.rr1 = s.rr1;
   d.rr2 = s.rr2;
   d.plan = s.plan;
   d.forming = s.forming;
}

void NbFqFromPlan(NbFqBar &b, const NbFqPlan &g)
{
   b.kind = g.kind;
   b.level = g.level;
   b.src = g.src;
   b.event = g.event;
   b.ext = g.ext;
   b.trig = g.trig;
   b.conf = g.conf;
   b.entry = g.entry;
   b.sl = g.sl;
   b.tp1 = g.tp1;
   b.tp2 = g.tp2;
   b.tp1Src = g.tp1Src;
   b.tp2Src = g.tp2Src;
   b.risk = g.risk;
   b.rr1 = g.rr1;
   b.rr2 = g.rr2;
}

void NbFqNewPlan(NbFqPlan &g, int idx, int dir, const NbFqBar &b)
{
   g.idx = idx;
   g.dir = dir;
   g.kind = b.kind;
   g.level = b.level;
   g.src = b.src;
   g.event = b.event;
   g.ext = b.ext;
   g.trig = b.trig;
   g.conf = b.conf;
   g.entry = b.entry;
   g.sl = b.sl;
   g.tp1 = b.tp1;
   g.tp2 = b.tp2;
   g.tp1Src = b.tp1Src;
   g.tp2Src = b.tp2Src;
   g.risk = b.risk;
   g.rr1 = b.rr1;
   g.rr2 = b.rr2;
   g.status = NB_PO_PENDING;
   g.fillIdx = -1;
   g.statusIdx = idx;
}

//--- one UTC session window [hStart, hEnd) fed bar by bar. The window's
//    high / low become KNOWN (kH / kL) only at the close of the bar that
//    reaches the window's end, or at the first bar after it (data gaps);
//    a window with fewer than NB_FQ_SESS_MIN_BARS bars is never published.
void NbFqWindow(datetime t, double hi, double lo, int sec, long offset, int hStart, int hEnd, long &id, double &wH,
                double &wL, int &wN, datetime &wEnd, bool &pub, double &kH, double &kL)
{
   long u = (long)t - offset;
   long uDay = u / 86400;
   long sod = u - uDay * 86400;
   bool inside = (sod >= (long)hStart * 3600 && sod < (long)hEnd * 3600);
   if(!pub && (long)t >= (long)wEnd)
   {
      if(wN >= NB_FQ_SESS_MIN_BARS)
      {
         kH = wH;
         kL = wL;
      }
      pub = true;
   }
   if(inside)
   {
      if(uDay != id)
      {
         id = uDay;
         wH = hi;
         wL = lo;
         wN = 0;
         pub = false;
         wEnd = (datetime)(uDay * 86400 + (long)hEnd * 3600 + offset);
      }
      if(hi > wH)
         wH = hi;
      if(lo < wL)
         wL = lo;
      wN++;
   }
   if(!pub && (long)t + sec >= (long)wEnd)
   {
      if(wN >= NB_FQ_SESS_MIN_BARS)
      {
         kH = wH;
         kL = wL;
      }
      pub = true;
   }
}

//--- session levels for every closed 5M bar (causal).
//    PDH / PDL: high / low of the latest COMPLETE broker day before the
//    bar's own day (server 00:00-24:00, the same day MT5's D1 bar uses).
//    Asia / London: high / low of the latest ENDED UTC window; they need
//    the session clock (two witnesses, AUTO) and are 0 without it.
void NbFqSessions(const datetime &t[], const double &h[], const double &l[], int n, int sec, const NbFqCfg &C,
                  NbFqBar &fq[])
{
   long dId = -1;
   double dH = 0.0;
   double dL = 0.0;
   int dN = 0;
   double pH = 0.0;
   double pL = 0.0;
   long aId = -1;
   double aH = 0.0;
   double aL = 0.0;
   int aN = 0;
   datetime aEnd = 0;
   bool aPub = true;
   double aKH = 0.0;
   double aKL = 0.0;
   long oId = -1;
   double oH = 0.0;
   double oL = 0.0;
   int oN = 0;
   datetime oEnd = 0;
   bool oPub = true;
   double oKH = 0.0;
   double oKL = 0.0;
   for(int i = 0; i < n; i++)
   {
      long day = ((long)t[i]) / 86400;
      if(day != dId)
      {
         if(dId >= 0 && dN >= NB_FQ_SESS_MIN_BARS)
         {
            pH = dH;
            pL = dL;
         }
         dId = day;
         dH = h[i];
         dL = l[i];
         dN = 0;
      }
      if(h[i] > dH)
         dH = h[i];
      if(l[i] < dL)
         dL = l[i];
      dN++;
      fq[i].pdh = pH;
      fq[i].pdl = pL;
      fq[i].ash = 0.0;
      fq[i].asl = 0.0;
      fq[i].loh = 0.0;
      fq[i].lol = 0.0;
      if(!C.clockOk)
         continue;
      NbFqWindow(t[i], h[i], l[i], sec, C.offset, C.asiaStart, C.asiaEnd, aId, aH, aL, aN, aEnd, aPub, aKH, aKL);
      NbFqWindow(t[i], h[i], l[i], sec, C.offset, C.lonStart, C.lonEnd, oId, oH, oL, oN, oEnd, oPub, oKH, oKL);
      fq[i].ash = aKH;
      fq[i].asl = aKL;
      fq[i].loh = oKH;
      fq[i].lol = oKL;
   }
}

void NbLvAdd(NbLv &lv[], int &n, double price, int src, int pri)
{
   if(price <= 0.0)
      return;
   ArrayResize(lv, n + 1, 32);
   lv[n].price = price;
   lv[n].src = src;
   lv[n].pri = pri;
   n++;
}

//--- the levels known at one bar: its session levels plus the last
//    NB_FQ_SWINGS confirmed 15M swing highs and lows among piv[0..pc-1]
//    (the caller passes only swings confirmed by then). Sorted ascending;
//    levels closer than `tol` to the first of their group become ONE level
//    (price of the stronger source, sources OR'ed).
int NbFqLevels(const NbFqBar &b, const NbPivot &piv[], int pc, double tol, NbLv &lv[])
{
   int n = 0;
   ArrayResize(lv, 0);
   NbLvAdd(lv, n, b.pdh, NB_LV_PDH, 1);
   NbLvAdd(lv, n, b.pdl, NB_LV_PDL, 1);
   NbLvAdd(lv, n, b.loh, NB_LV_LOH, 2);
   NbLvAdd(lv, n, b.lol, NB_LV_LOL, 2);
   NbLvAdd(lv, n, b.ash, NB_LV_ASH, 3);
   NbLvAdd(lv, n, b.asl, NB_LV_ASL, 3);
   int nh = 0;
   int nlo = 0;
   for(int p = pc - 1; p >= 0 && (nh < NB_FQ_SWINGS || nlo < NB_FQ_SWINGS); p--)
   {
      if(piv[p].kind > 0 && nh < NB_FQ_SWINGS)
      {
         NbLvAdd(lv, n, piv[p].price, NB_LV_SWH, 4);
         nh++;
      }
      if(piv[p].kind < 0 && nlo < NB_FQ_SWINGS)
      {
         NbLvAdd(lv, n, piv[p].price, NB_LV_SWL, 4);
         nlo++;
      }
   }
   for(int a = 1; a < n; a++)
   {
      int k = a;
      while(k > 0 && lv[k - 1].price > lv[k].price)
      {
         double tp = lv[k].price;
         int ts = lv[k].src;
         int tq = lv[k].pri;
         lv[k].price = lv[k - 1].price;
         lv[k].src = lv[k - 1].src;
         lv[k].pri = lv[k - 1].pri;
         lv[k - 1].price = tp;
         lv[k - 1].src = ts;
         lv[k - 1].pri = tq;
         k--;
      }
   }
   int m = 0;
   double first = 0.0;
   for(int a = 0; a < n; a++)
   {
      if(m > 0 && lv[a].price - first <= tol)
      {
         lv[m - 1].src |= lv[a].src;
         if(lv[a].pri < lv[m - 1].pri)
         {
            lv[m - 1].price = lv[a].price;
            lv[m - 1].pri = lv[a].pri;
         }
         continue;
      }
      first = lv[a].price;
      lv[m].price = lv[a].price;
      lv[m].src = lv[a].src;
      lv[m].pri = lv[a].pri;
      m++;
   }
   ArrayResize(lv, m);
   return m;
}

//--- nearest levels below / above a price (lv sorted ascending)
void NbFqNearest(const NbLv &lv[], int n, double px, NbFqBar &b)
{
   b.sup = 0.0;
   b.supSrc = 0;
   b.sup2 = 0.0;
   b.res = 0.0;
   b.resSrc = 0;
   b.res2 = 0.0;
   for(int a = 0; a < n; a++)
   {
      if(lv[a].price < px)
      {
         b.sup2 = b.sup;
         b.sup = lv[a].price;
         b.supSrc = lv[a].src;
      }
      else if(lv[a].price > px)
      {
         if(b.res <= 0.0)
         {
            b.res = lv[a].price;
            b.resSrc = lv[a].src;
         }
         else if(b.res2 <= 0.0)
            b.res2 = lv[a].price;
      }
   }
}

//--- index of the first level strictly beyond `from` in direction dir, -1 = none
int NbLvBeyond(const NbLv &lv[], int n, double from, int dir)
{
   if(dir > 0)
   {
      for(int a = 0; a < n; a++)
         if(lv[a].price > from)
            return a;
      return -1;
   }
   for(int a = n - 1; a >= 0; a--)
      if(lv[a].price < from)
         return a;
   return -1;
}

//--- latest bar in (i - window, i] whose CLOSE crossed `lvl` (dir +1: from
//    <= to >, dir -1: from >= to <). -1 = none. Display helper.
int NbFqCross(const double &c[], int i, int window, double lvl, int dir)
{
   for(int j = i; j >= 1 && j > i - window; j--)
   {
      if(dir > 0 && c[j] > lvl && c[j - 1] <= lvl)
         return j;
      if(dir < 0 && c[j] < lvl && c[j - 1] >= lvl)
         return j;
   }
   return -1;
}

//--- a live plan meets one closed 5M bar k (> the plan's bar).
//    Pending: a touch of the entry = filled. On the FILL candle only the SL
//    is judged (tick order unknown, so a TP1 touch there is not counted).
//    TP1 reached before any fill = MISSED (no chase). validBars without a
//    fill = EXPIRED.
//    Filled: SAME-CANDLE RULE as the main panel: SL is tested first.
void NbFqTrack(NbFqPlan &g, int k, double hi, double lo, int validBars, int openMax)
{
   if(g.status == NB_PO_PENDING)
   {
      bool fill = (g.dir > 0) ? (lo <= g.entry) : (hi >= g.entry);
      if(fill)
      {
         g.fillIdx = k;
         bool stop = (g.dir > 0) ? (lo <= g.sl) : (hi >= g.sl);
         if(stop)
         {
            g.status = NB_PO_SL;
            g.statusIdx = k;
         }
         else
            g.status = NB_PO_FILLED;
         return;
      }
      bool ran = (g.dir > 0) ? (hi >= g.tp1) : (lo <= g.tp1);
      if(ran)
      {
         g.status = NB_PO_MISSED;
         g.statusIdx = k;
         return;
      }
      if(k - g.idx >= validBars)
      {
         g.status = NB_PO_EXPIRED;
         g.statusIdx = k;
      }
      return;
   }
   if(g.status == NB_PO_FILLED && k > g.fillIdx)
   {
      bool stop = (g.dir > 0) ? (lo <= g.sl) : (hi >= g.sl);
      bool tp = (g.dir > 0) ? (hi >= g.tp1) : (lo <= g.tp1);
      if(stop)
      {
         g.status = NB_PO_SL;
         g.statusIdx = k;
      }
      else if(tp)
      {
         g.status = NB_PO_TP1;
         g.statusIdx = k;
      }
      else if(k - g.fillIdx >= openMax)
      {
         g.status = NB_PO_TIMEOUT;
         g.statusIdx = k;
      }
   }
}

//--- the five questions on every closed 5M bar, and the plans they produce.
//    s15 must already be computed (NbRun15) and s5 aligned to it (NbRun5:
//    s5.map, s5.atr). piv5 are the 5M swings (for the breakout stop).
//    lastClosed=false: the last bar is still forming and is NOT evaluated.
void NbRunFq(const NbSeries &s5, const NbSeries &s15, const NbPivot &piv15[], int np15, const NbPivot &piv5[],
             int np5, bool lastClosed, const NbParams &P, const NbFqCfg &C, NbFqBar &fq[], NbFqPlan &pl[], int &nPl)
{
   int n = s5.n;
   ArrayResize(fq, n);
   ArrayResize(pl, 0);
   nPl = 0;
   NbFqSessions(s5.t, s5.h, s5.l, n, s5.sec, C, fq);
   int nEvalFq = lastClosed ? n : n - 1;
   int cur = -1;       // live plan (pending or filled)
   int latest = -1;    // latest plan of any outcome
   int usedEv = -1;    // newest event that already produced a plan
   int pc = 0;         // 15M swings confirmed so far
   double minRisk = (P.tick > 0.0) ? P.tick * 0.5 : 0.0;
   NbLv lv[];
   for(int i = 0; i < n; i++)
   {
      NbFqReset(fq[i]);
      if(i >= nEvalFq)
      {
         // unfinished candle: carry the last CLOSED answer, never evaluate it
         if(i > 0)
         {
            NbFqCopy(fq[i], fq[i - 1]);
            fq[i].pdh = fq[i - 1].pdh;
            fq[i].pdl = fq[i - 1].pdl;
            fq[i].ash = fq[i - 1].ash;
            fq[i].asl = fq[i - 1].asl;
            fq[i].loh = fq[i - 1].loh;
            fq[i].lol = fq[i - 1].lol;
         }
         fq[i].forming = true;
         continue;
      }
      // 1) the live plan meets this closed bar
      if(cur >= 0 && i > pl[cur].idx)
         NbFqTrack(pl[cur], i, s5.h[i], s5.l[i], C.validBars, C.openMax);
      int k15 = s5.map[i];
      int tr = 0;
      if(k15 >= 0)
      {
         if(s15.st[k15] == NB_ST_BULL)
            tr = 1;
         if(s15.st[k15] == NB_ST_BEAR)
            tr = -1;
      }
      // a pending limit dies when the 15M structure stops agreeing
      if(cur >= 0 && pl[cur].status == NB_PO_PENDING && tr != pl[cur].dir)
      {
         pl[cur].status = NB_PO_CANCELLED;
         pl[cur].statusIdx = i;
      }
      if(cur >= 0 && pl[cur].status != NB_PO_PENDING && pl[cur].status != NB_PO_FILLED)
         cur = -1;
      while(k15 >= 0 && pc < np15 && piv15[pc].confirmIdx <= k15)
         pc++;
      fq[i].trend = tr;
      fq[i].plan = (cur >= 0) ? cur : latest;
      if(k15 < 0 || s15.atr[k15] <= 0.0 || s5.atr[i] <= 0.0)
      {
         fq[i].why = NB_FW_NO_DATA;
         continue;
      }
      double zone = C.zoneAtr * s15.atr[k15];
      int nl = NbFqLevels(fq[i], piv15, pc, zone, lv);
      fq[i].zone = zone;
      NbFqNearest(lv, nl, s5.c[i], fq[i]);
      if(cur >= 0)
      {
         NbFqFromPlan(fq[i], pl[cur]);
         fq[i].status = (pl[cur].status == NB_PO_FILLED) ? NB_FQ_FILLED : NB_FQ_READY;
         fq[i].why = (pl[cur].status == NB_PO_FILLED) ? NB_FW_FILLED : NB_FW_PENDING;
         continue;
      }
      if(tr == 0)
      {
         fq[i].why = (s15.st[k15] == NB_ST_MIXED) ? NB_FW_MIXED : NB_FW_UNCONF;
         continue;
      }
      if(nl == 0)
      {
         fq[i].why = NB_FW_NO_LEVELS;
         continue;
      }
      // 2) candidate: the newest sweep or breakout of a level on the trade
      //    side (below the close for a BUY, above it for a SELL)
      double cl = s5.c[i];
      int bK = NB_PK_NONE;
      int bEv = -1;
      int bA = -1;
      for(int a = 0; a < nl; a++)
      {
         double L = lv[a].price;
         if((tr > 0 && !(L < cl)) || (tr < 0 && !(L > cl)))
            continue;
         int ev = -1;
         int kind = NB_PK_NONE;
         // sweep: the bar before was on the trade side, this bar pierced the
         // level; the close now is back on the trade side (checked above).
         // The EARLIEST unused pierce inside the window starts the sweep, so
         // a re-dip during the same sweep never moves the stop above the
         // real sweep extreme.
         int j0 = i - C.window + 1;
         if(j0 < 1)
            j0 = 1;
         if(j0 <= usedEv)
            j0 = usedEv + 1;
         for(int j = j0; j <= i; j++)
         {
            bool pierce = (tr > 0) ? (s5.l[j] < L && s5.c[j - 1] > L) : (s5.h[j] > L && s5.c[j - 1] < L);
            if(pierce)
            {
               ev = j;
               kind = NB_PK_SWEEP;
               break;
            }
         }
         // breakout: the LATEST close through the level, with its body, held since
         if(ev < 0)
         {
            for(int j = i; j >= 1 && j > i - C.window; j--)
            {
               bool cross = (tr > 0) ? (s5.c[j] > L && s5.c[j - 1] <= L) : (s5.c[j] < L && s5.c[j - 1] >= L);
               if(!cross)
                  continue;
               double need = C.confirmAtr * s5.atr[j];
               bool body = (tr > 0) ? (s5.c[j] > s5.o[j] && s5.c[j] > L + need) : (s5.c[j] < s5.o[j] && s5.c[j] < L - need);
               bool held = true;
               for(int k = j + 1; k <= i; k++)
                  if((tr > 0 && s5.c[k] <= L) || (tr < 0 && s5.c[k] >= L))
                     held = false;
               if(body && held)
               {
                  ev = j;
                  kind = NB_PK_BREAK;
               }
               break;
            }
         }
         if(ev < 0 || ev <= usedEv)
            continue;
         bool better = (bA < 0 || ev > bEv);
         if(!better && ev == bEv && kind == NB_PK_SWEEP && bK != NB_PK_SWEEP)
            better = true;
         if(!better && ev == bEv && kind == bK && MathAbs(L - cl) < MathAbs(lv[bA].price - cl))
            better = true;
         if(better)
         {
            bA = a;
            bEv = ev;
            bK = kind;
         }
      }
      if(bA < 0)
      {
         // no sweep / break: LOCATION only - at the level to buy from (sell
         // from), at the level a with-trend close would break, or nowhere
         double lvNear = (tr > 0) ? fq[i].sup : fq[i].res;
         double lvBrk = (tr > 0) ? fq[i].res : fq[i].sup;
         bool at = false;
         bool atBrk = false;
         if(lvNear > 0.0)
            at = (tr > 0) ? (cl - lvNear <= zone || s5.l[i] <= lvNear + zone)
                          : (lvNear - cl <= zone || s5.h[i] >= lvNear - zone);
         if(lvBrk > 0.0)
            atBrk = (tr > 0) ? (lvBrk - cl <= zone || s5.h[i] >= lvBrk - zone)
                             : (cl - lvBrk <= zone || s5.l[i] <= lvBrk + zone);
         fq[i].status = NB_FQ_WATCH;
         fq[i].why = at ? NB_FW_AT_LEVEL : (atBrk ? NB_FW_AT_BREAK : NB_FW_MIDDLE);
         continue;
      }
      double lvl = lv[bA].price;
      fq[i].kind = bK;
      fq[i].level = lvl;
      fq[i].src = lv[bA].src;
      fq[i].event = bEv;
      double buf = P.slBufAtr * C.slBufMult * s5.atr[i];
      double sl = 0.0;
      if(bK == NB_PK_SWEEP)
      {
         // the sweep extreme since the pierce, and the candle that made it
         int m = bEv;
         double ext = (tr > 0) ? s5.l[bEv] : s5.h[bEv];
         for(int k = bEv; k <= i; k++)
         {
            if((tr > 0 && s5.l[k] <= ext) || (tr < 0 && s5.h[k] >= ext))
            {
               ext = (tr > 0) ? s5.l[k] : s5.h[k];
               m = k;
            }
         }
         // confirmation: a later candle CLOSES beyond that candle's other
         // extreme (and beyond the level), with its body
         double trig = (tr > 0) ? MathMax(s5.h[m], lvl) : MathMin(s5.l[m], lvl);
         int conf = -1;
         for(int k = m + 1; k <= i; k++)
         {
            double need = C.confirmAtr * s5.atr[k];
            bool okc = (tr > 0) ? (s5.c[k] > trig + need && s5.c[k] > s5.o[k]) : (s5.c[k] < trig - need && s5.c[k] < s5.o[k]);
            if(okc)
            {
               conf = k;
               break;
            }
         }
         fq[i].ext = ext;
         fq[i].trig = trig;
         fq[i].conf = conf;
         if(conf < 0)
         {
            fq[i].status = NB_FQ_SETUP;
            fq[i].why = NB_FW_WAIT_CONF;
            continue;
         }
         sl = (tr > 0) ? NbRoundTick(ext - buf, P.tick, P.digits, -1) : NbRoundTick(ext + buf, P.tick, P.digits, 1);
      }
      else
      {
         // breakout: the close through the level IS the confirmation; the
         // stop goes beyond the latest confirmed 5M swing behind the level
         fq[i].conf = bEv;
         double sw = 0.0;
         int sp = NbFindStopSwing(piv5, np5, i, tr, lvl, NB_SL_SEARCH_BARS, sw);
         if(sp < 0)
         {
            fq[i].status = NB_FQ_SKIP;
            fq[i].why = NB_FW_NO_STOP;
            continue;
         }
         sl = (tr > 0) ? NbRoundTick(sw - buf, P.tick, P.digits, -1) : NbRoundTick(sw + buf, P.tick, P.digits, 1);
      }
      double entry = NbRoundTick(lvl, P.tick, P.digits, 0);
      double risk = NormalizeDouble(MathAbs(entry - sl), P.digits);
      fq[i].entry = entry;
      fq[i].sl = sl;
      fq[i].risk = risk;
      if(risk <= minRisk || risk <= 0.0 || (tr > 0 && sl >= entry) || (tr < 0 && sl <= entry))
      {
         fq[i].status = NB_FQ_SKIP;
         fq[i].why = NB_FW_NO_STOP;
         continue;
      }
      // 3) reward: TP1 = the next mapped level beyond the entry zone AND
      //    beyond the current close; TP2 = the level after it. No level
      //    mapped = reward UNKNOWN, which is never a YES.
      double from = (tr > 0) ? MathMax(entry + zone, cl) : MathMin(entry - zone, cl);
      int t1 = NbLvBeyond(lv, nl, from, tr);
      if(t1 < 0)
      {
         fq[i].status = NB_FQ_SKIP;
         fq[i].why = NB_FW_NO_TARGET;
         continue;
      }
      int t2 = NbLvBeyond(lv, nl, lv[t1].price, tr);
      fq[i].tp1 = lv[t1].price;
      fq[i].tp1Src = lv[t1].src;
      if(t2 >= 0)
      {
         fq[i].tp2 = lv[t2].price;
         fq[i].tp2Src = lv[t2].src;
      }
      fq[i].rr1 = MathAbs(fq[i].tp1 - entry) / risk;
      fq[i].rr2 = (t2 >= 0) ? MathAbs(fq[i].tp2 - entry) / risk : 0.0;
      if(fq[i].rr1 < C.minRR)
      {
         fq[i].status = NB_FQ_SKIP;
         fq[i].why = NB_FW_LOW_RR;
         continue;
      }
      // 4) READY: the plan is frozen at this close and followed from the next bar
      ArrayResize(pl, nPl + 1, 64);
      NbFqNewPlan(pl[nPl], i, tr, fq[i]);
      cur = nPl;
      latest = nPl;
      nPl++;
      usedEv = bEv;
      fq[i].status = NB_FQ_READY;
      fq[i].why = NB_FW_PENDING;
      fq[i].plan = cur;
   }
}

//--- the levels a bar used, rebuilt from scratch (display and tests; the
//    run above builds the same list incrementally)
int NbFqLevelsAt(const NbSeries &s5, const NbSeries &s15, const NbPivot &piv15[], int np15, const NbFqCfg &C,
                 const NbFqBar &fq[], int i, NbLv &lv[])
{
   ArrayResize(lv, 0);
   if(i < 0 || i >= s5.n || i >= ArraySize(fq))
      return 0;
   int k15 = s5.map[i];
   if(k15 < 0 || s15.atr[k15] <= 0.0)
      return 0;
   int pc = 0;
   while(pc < np15 && piv15[pc].confirmIdx <= k15)
      pc++;
   return NbFqLevels(fq[i], piv15, pc, C.zoneAtr * s15.atr[k15], lv);
}

//--- outcome counts over all plans (the evidence the table prints)
void NbFqTally(const NbFqPlan &pl[], int n, int &nTp, int &nSl, int &nUnfilled, int &nOpen, int &nTimeout)
{
   nTp = 0;
   nSl = 0;
   nUnfilled = 0;
   nOpen = 0;
   nTimeout = 0;
   for(int k = 0; k < n; k++)
   {
      int s = pl[k].status;
      if(s == NB_PO_TP1)
         nTp++;
      else if(s == NB_PO_SL)
         nSl++;
      else if(s == NB_PO_EXPIRED || s == NB_PO_MISSED || s == NB_PO_CANCELLED)
         nUnfilled++;
      else if(s == NB_PO_PENDING || s == NB_PO_FILLED)
         nOpen++;
      else if(s == NB_PO_TIMEOUT)
         nTimeout++;
   }
}

//--- v1.06: net result of the finished plans in R (TP1 = +its R, SL = -1;
//    not filled / cancelled / timed out = 0). Evidence, not a promise.
double NbFqNetR(const NbFqPlan &pl[], int n)
{
   double r = 0.0;
   for(int k = 0; k < n; k++)
   {
      if(pl[k].status == NB_PO_TP1)
         r += pl[k].rr1;
      else if(pl[k].status == NB_PO_SL)
         r -= 1.0;
   }
   return r;
}

//--- words
string NbLvSrcText(int src)
{
   string t = "";
   if((src & NB_LV_PDH) != 0)
      t = t + ((t == "") ? "" : " + ") + "PREV DAY HIGH";
   if((src & NB_LV_PDL) != 0)
      t = t + ((t == "") ? "" : " + ") + "PREV DAY LOW";
   if((src & NB_LV_LOH) != 0)
      t = t + ((t == "") ? "" : " + ") + "LONDON HIGH";
   if((src & NB_LV_LOL) != 0)
      t = t + ((t == "") ? "" : " + ") + "LONDON LOW";
   if((src & NB_LV_ASH) != 0)
      t = t + ((t == "") ? "" : " + ") + "ASIA HIGH";
   if((src & NB_LV_ASL) != 0)
      t = t + ((t == "") ? "" : " + ") + "ASIA LOW";
   if((src & NB_LV_SWH) != 0)
      t = t + ((t == "") ? "" : " + ") + "15M SWING HIGH";
   if((src & NB_LV_SWL) != 0)
      t = t + ((t == "") ? "" : " + ") + "15M SWING LOW";
   if(t == "")
      t = "LEVEL";
   return t;
}

string NbLvSrcShort(int src)
{
   string t = "";
   if((src & NB_LV_PDH) != 0)
      t = t + ((t == "") ? "" : "+") + "PDH";
   if((src & NB_LV_PDL) != 0)
      t = t + ((t == "") ? "" : "+") + "PDL";
   if((src & NB_LV_LOH) != 0)
      t = t + ((t == "") ? "" : "+") + "LDN H";
   if((src & NB_LV_LOL) != 0)
      t = t + ((t == "") ? "" : "+") + "LDN L";
   if((src & NB_LV_ASH) != 0)
      t = t + ((t == "") ? "" : "+") + "ASIA H";
   if((src & NB_LV_ASL) != 0)
      t = t + ((t == "") ? "" : "+") + "ASIA L";
   if((src & NB_LV_SWH) != 0)
      t = t + ((t == "") ? "" : "+") + "SWING H";
   if((src & NB_LV_SWL) != 0)
      t = t + ((t == "") ? "" : "+") + "SWING L";
   if(t == "")
      t = "LEVEL";
   return t;
}

//--- v1.06: the long name when it is short enough for a chart label
//    (MT5 cuts object text at 63 characters), else the short codes
string NbLvName(int src)
{
   string t = NbLvSrcText(src);
   if(StringLen(t) <= 34)
      return t;
   return NbLvSrcShort(src);
}

//--- v1.06: at most two short codes (+n) - fits a table cell. Strongest
//    source first (day, London, Asia, swing), as in NbLvSrcShort.
int NbLvBitAt(int k)
{
   switch(k)
   {
      case 0: return NB_LV_PDH;
      case 1: return NB_LV_PDL;
      case 2: return NB_LV_LOH;
      case 3: return NB_LV_LOL;
      case 4: return NB_LV_ASH;
      case 5: return NB_LV_ASL;
      case 6: return NB_LV_SWH;
      case 7: return NB_LV_SWL;
   }
   return 0;
}

string NbLvTag(int src)
{
   string t = "";
   int shown = 0;
   int more = 0;
   for(int b = 0; b < 8; b++)
   {
      int bit = NbLvBitAt(b);
      if((src & bit) == 0)
         continue;
      if(shown < 2)
      {
         t = t + ((t == "") ? "" : "+") + NbLvSrcShort(bit);
         shown++;
      }
      else
         more++;
   }
   if(more > 0)
      t = t + "+" + IntegerToString(more);
   if(t == "")
      t = "LEVEL";
   return t;
}

//--- v1.06: broker clock from two witnesses (server vs PC GMT): on a half
//    hour within 5 minutes and a plausible zone, else unknown. For files
//    that have no session clock of their own (the metals panel).
bool NbFqWitnessClock(datetime server, datetime gmt, long &offset)
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

string NbFqStatusText(int st)
{
   switch(st)
   {
      case NB_FQ_WATCH:  return "WATCH";
      case NB_FQ_SETUP:  return "SETTING UP";
      case NB_FQ_SKIP:   return "SKIP";
      case NB_FQ_READY:  return "READY";
      case NB_FQ_FILLED: return "FILLED";
   }
   return "NO TRADE";
}

string NbFqWhyText(int why)
{
   switch(why)
   {
      case NB_FW_NO_DATA:   return "15M / 5M DATA NOT READY";
      case NB_FW_UNCONF:    return "15M STRUCTURE NOT CONFIRMED";
      case NB_FW_MIXED:     return "15M STRUCTURE MIXED - NO SIDE";
      case NB_FW_NO_LEVELS: return "NO LEVELS MAPPED YET";
      case NB_FW_MIDDLE:    return "PRICE IN THE MIDDLE - NO ENTRY HERE";
      case NB_FW_AT_LEVEL:  return "AT THE LEVEL - WAIT FOR A SWEEP";
      case NB_FW_WAIT_CONF: return "SWEPT - WAIT FOR THE CONFIRMATION CLOSE";
      case NB_FW_NO_STOP:   return "NO CONFIRMED 5M SWING FOR THE SL";
      case NB_FW_NO_TARGET: return "NO MAPPED TARGET BEYOND - REWARD UNKNOWN";
      case NB_FW_LOW_RR:    return "NEXT LEVEL TOO CLOSE - NOT ENOUGH ROOM";
      case NB_FW_PENDING:   return "PENDING LIMIT - WAITING FOR THE RETEST";
      case NB_FW_FILLED:    return "LIMIT FILLED - RUNNING TO TP1 / SL";
      case NB_FW_AT_BREAK:  return "AT THE BREAKOUT LINE - WAIT FOR A 5M CLOSE BEYOND";
   }
   return "";
}

string NbFqOutcomeText(int st)
{
   switch(st)
   {
      case NB_PO_PENDING:   return "pending - limit not filled yet";
      case NB_PO_FILLED:    return "filled - running";
      case NB_PO_TP1:       return "HIT TP1";
      case NB_PO_SL:        return "HIT SL";
      case NB_PO_EXPIRED:   return "not filled in time";
      case NB_PO_MISSED:    return "ran to TP1 without a fill (no chase)";
      case NB_PO_CANCELLED: return "cancelled - 15M structure turned";
      case NB_PO_TIMEOUT:   return "filled, no TP1 / SL in 12 h";
   }
   return "";
}

string NbFqKindText(int kind, int dir)
{
   if(kind == NB_PK_SWEEP)
      return "SWEEP";
   if(kind == NB_PK_BREAK)
      return (dir > 0) ? "BREAKOUT" : "BREAKDOWN";
   return "";
}

//--- what a level means, in words a beginner can act on.
//    role +1 = the level is ABOVE price (resistance), -1 = BELOW (support)
string NbFqHint(int role, int trend)
{
   if(role > 0)
   {
      if(trend > 0)
         return "5M close ABOVE = BREAKOUT " + NbSymArrow() + " possible BUY on the retest";
      if(trend < 0)
         return "sweep above + 5M close back BELOW = possible SELL";
      return "15M unclear: breakout or rejection - just watch";
   }
   if(trend < 0)
      return "5M close BELOW = BREAKDOWN " + NbSymArrow() + " possible SELL on the retest";
   if(trend > 0)
      return "sweep below + 5M close back ABOVE = possible BUY";
   return "15M unclear: breakdown or bounce - just watch";
}

//--- the other side of the same level: what the plan will NOT do
string NbFqHint2(int role, int trend)
{
   if(role > 0 && trend < 0)
      return "a real BREAKOUT above = against the 15M trend, no trade";
   if(role < 0 && trend > 0)
      return "a real BREAKDOWN below = against the 15M trend, no trade";
   if(role > 0 && trend > 0)
      return "a rejection here = no SELL (15M is bullish)";
   if(role < 0 && trend < 0)
      return "a bounce here = no BUY (15M is bearish)";
   return "";
}
//=== NB_FQ_END ===
//=== NB_ENGINE_END ===

//+------------------------------------------------------------------+
//| TERMINAL LAYER - data loading, panel, chart drawing.             |
//| READ-ONLY with respect to the trading account.                   |
//+------------------------------------------------------------------+
const string NB_PFX   = "NBLP_";
const string NB_PFX_P = "NBLP_P_";
const string NB_PFX_C = "NBLP_C_";
const string NB_PFX_Q = "NBLP_Q_";   // v1.05: the bottom-middle 5-question table
const string NB_PFX_F = "NBLP_F_";   // v1.05: its chart drawing (S/R lines, zones, plan)
#define NB_RGB(r, g, b) ((color)((r) | ((g) << 8) | ((b) << 16)))

enum ENUM_NB_CORNER
{
   NB_TOP_LEFT = 0,     // Top left
   NB_TOP_RIGHT = 1,    // Top right
   NB_BOTTOM_LEFT = 2,  // Bottom left
   NB_BOTTOM_RIGHT = 3  // Bottom right
};

input group "Engine (15M boss + 5M trigger are fixed)"
input int            InpNrtrAtrPeriod   = 14;          // NRTR ATR period
input double         InpNrtrMultiplier  = 2.0;         // NRTR ATR multiplier
input int            InpEmaPeriod       = 200;         // EMA period (15M)
input int            InpSwingStrength   = 3;           // Structure lookback: bars each side of a swing
input double         InpSlBufferAtr     = 0.10;        // SL buffer beyond 5M swing (x 5M ATR)
input double         InpTp1R            = 1.0;         // TP1 (R multiple)
input double         InpTp2R            = 2.0;         // TP2 (R multiple)
input int            InpSignalValidBars = 6;           // Signal stays clickable for (5M bars)
input int            InpHistoryDays     = 10;          // History used (days)
input group "Position size (reference only - the lot you type is your decision)"
input double         InpRiskPercent     = 1.0;         // Risk per trade, % of balance (0.1 - 5.0)
input group "Swing / pending-order references (nothing is sent)"
input double         InpSwingDistGold   = 20.0;        // Gold swing TP distance (price, e.g. 20.00)
input double         InpSwingDistSilver = 2.0;         // Silver swing TP distance (price, e.g. 2.00)
input group "Data clock (freshness witnesses)"
input int            InpMaxTickAgeSec   = 120;         // Last broker tick older than this = STALE
input int            InpMaxClockSkewSec = 300;         // Tick clock ahead of server clock by more = STALE
input group "New York open (broker time, local pop-up only)"
input bool           InpNyAlert         = true;        // Alert + sound at NY open
input string         InpNyOpenTime      = "16:30";     // NY 09:30 in your BROKER's clock (HH:MM)
input int            InpNyQuietMinutes  = 15;          // Show WAIT for this many minutes after the open
input group "Display"
input double         InpPanelScale      = 0.9;         // Panel size (0.7 - 1.6)
input ENUM_NB_CORNER InpPanelCorner     = NB_TOP_LEFT; // Panel position
input int            InpPanelX          = 12;          // Panel X offset (px)
input int            InpPanelY          = 24;          // Panel Y offset (px)
input bool           InpDrawChart       = true;        // Draw EMA/NRTR/structure/markers/levels
input bool           InpCandleArrows    = true;        // Arrow on the candle where the NRTR flips
input bool           InpArrowEveryBar   = false;       // Also a small arrow on every closed candle
input bool           InpPreview         = true;        // Yellow PREVIEW on the forming candle (not a signal)
input bool           InpBlink           = true;        // Blink the CLICK BUY / SELL banner
input group "5-QUESTION PLAN (v1.05, bottom-middle table - nothing is sent)"
input bool           InpFqShow          = true;        // Show the 5-question table (bottom middle)
input bool           InpFqDraw          = true;        // Draw big support / resistance lines, zones and the plan
input double         InpFqZoneAtr       = 0.25;        // Level zone and merge width (x 15M ATR)
input int            InpFqWindowBars    = 12;          // Sweep / breakout must be within this many closed 5M bars
input double         InpFqMinRR         = 1.5;         // Minimum reward to TP1 (R) - less = SKIP
input int            InpFqValidBars     = 12;          // Pending limit valid for (closed 5M bars)
input int            InpFqAsiaStartUtc  = 0;           // Asia range start (UTC hour)
input int            InpFqAsiaEndUtc    = 7;           // Asia range end (UTC hour)
input int            InpFqLondonStartUtc = 7;          // London range start (UTC hour)
input int            InpFqLondonEndUtc  = 12;          // London range end (UTC hour)
input int            InpFqBottomY       = 16;          // Table distance from the chart bottom (px)
input double         InpFqSilverSlMult  = 2.0;         // SILVER: SL buffer x this (wider, volatility-adjusted stop)
input double         InpFqSilverConfirmAtr = 0.25;     // SILVER: confirmation close must pass by this x 5M ATR

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
int      g_metal;
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
NbParams g_P;
datetime g_anchor;
NbSeries g_s15;
NbSeries g_s5;
NbPivot  g_piv15[];
NbPivot  g_piv5[];
NbSignal g_sigs[];
int      g_nSig;
datetime g_seen15;
datetime g_seen5;
bool     g_ready;
int      g_dataR;
bool     g_bufDirty;

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
int      g_nyOpenSec;      // seconds after broker midnight, -1 = disabled / bad input
long     g_nyAlertDay;     // broker day (t/86400) already alerted
double   g_swingDist;

// v1.05 five-question plan state
NbFqCfg  g_C;
NbFqBar  g_fq[];
NbFqPlan g_fqPlans[];
int      g_nFqPlan;

// prototypes
int    PlotDrawType(int plot);
void   NbUpdate();
void   NbReadSpec();
bool   NbLoad(ENUM_TIMEFRAMES tf, NbSeries &s, int &why);
void   NbRecompute();
void   NbEvaluate();
void   NbFillBuffers(int rates_total, const datetime &time[], const double &high[], const double &low[]);
void   NbNyCheck(datetime now);
int    NbParseHHMM(string txt);
string NbNyText(datetime now);
void   NbText(string name, datetime t, double price, string txt, color clr, int size, int anchor, string tip);
void   NbLevel(string name, datetime t, double price, color clr, int style, string txt);
void   NbDrawChart();
void   NbRect(string id, int x, int y, int w, int h, color bg, color border);
void   NbLabel(string id, int x, int y, string txt, color clr, int size, string font, int anchor);
string NbPx(double v);
color  NbDirColor(int d);
string NbMmSs(long secs);
string NbHms(long secs);
void   NbPreview(bool ok, int i5, int d5, double bid, string &line1, string &line2, color &clr);
void   NbDrawPanel();
void   NbRow(string kid, string vid, int kx, int vx, int y, string key, string val, color vc, color kc, int fs);
// v1.05 prototypes
void   NbFqConfig();
void   NbFqRecompute();
void   NbFLine(string name, datetime t1, double price, color clr, int width, int style);
void   NbFZone(string name, datetime t1, datetime t2, double p1, double p2, color fill);
void   NbFqDrawChart();
void   NbQRect(string id, int x, int y, int w, int h, color bg, color border);
void   NbQLabel(string id, int x, int y, string txt, color clr, int size, string font, int anchor);
color  NbQAnsColor(string ans);
void   NbFqDrawTable();

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
   if(!NbParamsValid(g_P) || InpHistoryDays < 3)
   {
      Print("NRTR BOSS: invalid inputs");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpFqZoneAtr <= 0.0 || InpFqZoneAtr > 2.0 || InpFqWindowBars < 2 || InpFqWindowBars > 96 || InpFqMinRR < 0.5 ||
      InpFqMinRR > 10.0 || InpFqValidBars < 1 || InpFqValidBars > 288 || InpFqAsiaStartUtc < 0 ||
      InpFqAsiaStartUtc >= InpFqAsiaEndUtc || InpFqAsiaEndUtc > 24 || InpFqLondonStartUtc < 0 ||
      InpFqLondonStartUtc >= InpFqLondonEndUtc || InpFqLondonEndUtc > 24 || InpFqBottomY < 0 ||
      InpFqSilverSlMult < 1.0 || InpFqSilverSlMult > 5.0 || InpFqSilverConfirmAtr < 0.0 || InpFqSilverConfirmAtr > 2.0)
   {
      Print("NRTR BOSS: invalid inputs - 5-question plan settings out of range");
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
   g_metal = NbMetalOf(g_sym, SymbolInfoString(g_sym, SYMBOL_CURRENCY_BASE),
                       SymbolInfoString(g_sym, SYMBOL_CURRENCY_PROFIT));
   NbReadSpec();
   IndicatorSetString(INDICATOR_SHORTNAME, "NRTR BOSS Learning Panel (CUSTOM ATR-NRTR)");
   IndicatorSetInteger(INDICATOR_DIGITS, g_digits);

   g_P.tick = g_tick;
   g_P.digits = g_digits;

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
   g_finalR = (g_metal == NB_METAL_NONE) ? NB_R_UNSUPPORTED : NB_R_NO_DATA;
   g_adv = NB_ADV_NONE;
   g_advWhy = NB_WHY_NONE;
   g_advDir = 0;
   g_blink = false;
   g_nyOpenSec = InpNyAlert ? NbParseHHMM(InpNyOpenTime) : -1;
   if(InpNyAlert && g_nyOpenSec < 0)
      Print("NRTR BOSS: NY open time '" + InpNyOpenTime + "' is not HH:MM - NY alert disabled");
   g_nyAlertDay = -1;
   g_swingDist = (g_metal == NB_METAL_SILVER) ? InpSwingDistSilver : InpSwingDistGold;
   ArrayResize(g_fq, 0);
   ArrayResize(g_fqPlans, 0);
   g_nFqPlan = 0;
   NbFqConfig();
   if(g_swingDist < 0.0)
      g_swingDist = 0.0;

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
      NbFqDrawTable();
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
   if(g_metal != NB_METAL_NONE)
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
   NbFqDrawTable();
   ChartRedraw(0);
}

//--- "HH:MM" -> seconds after midnight, -1 if malformed
int NbParseHHMM(string txt)
{
   if(StringLen(txt) != 5 || StringGetCharacter(txt, 2) != ':')
      return -1;
   for(int i = 0; i < 5; i++)
   {
      if(i == 2)
         continue;
      ushort ch = StringGetCharacter(txt, i);
      if(ch < '0' || ch > '9')
         return -1;
   }
   int hh = (int)StringToInteger(StringSubstr(txt, 0, 2));
   int mm = (int)StringToInteger(StringSubstr(txt, 3, 2));
   if(hh < 0 || hh > 23 || mm < 0 || mm > 59)
      return -1;
   return hh * 3600 + mm * 60;
}

//--- New York open: ONE local pop-up + sound per broker day, weekdays only,
//    inside the open minute. Nothing leaves the terminal.
void NbNyCheck(datetime now)
{
   if(g_nyOpenSec < 0 || now <= 0)
      return;
   long day = (long)now / 86400;
   int wd = (int)((day + 4) % 7);          // 1970-01-01 was a Thursday (4); 0 = Sunday
   if(wd == 0 || wd == 6)
      return;
   long sod = (long)now - day * 86400;
   if(sod < g_nyOpenSec || sod >= g_nyOpenSec + 60)
      return;
   if(g_nyAlertDay == day)
      return;
   g_nyAlertDay = day;
   string msg = "NRTR BOSS " + g_sym + ": NEW YORK OPEN (" + InpNyOpenTime + " broker time). First " +
                IntegerToString(InpNyQuietMinutes) + " min = WAIT for a closed 5M candle. You decide.";
   Alert(msg);
   PlaySound("alert.wav");
   Print(msg);
}

//--- session row text
string NbNyText(datetime now)
{
   if(g_nyOpenSec < 0)
      return "NY ALERT OFF";
   long day = (long)now / 86400;
   long sod = (long)now - day * 86400;
   long d = sod - g_nyOpenSec;
   if(d < 0)
      return "NY OPEN " + InpNyOpenTime + " in " + NbHms(-d);
   if(d < (long)InpNyQuietMinutes * 60)
      return "NY OPEN - FIRST " + IntegerToString(InpNyQuietMinutes) + " MIN: WAIT, LET IT PRINT";
   if(d < 6 * 3600)
      return "NEW YORK SESSION - " + NbHms(d) + " since the open";
   return "OUTSIDE NY OPEN WINDOW";
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
      ArrayResize(g_fq, 0);
      ArrayResize(g_fqPlans, 0);
      g_nFqPlan = 0;
      ObjectsDeleteAll(0, NB_PFX_F);
      return;
   }
   NbRun15(g_s15, g_piv15, g_P);
   NbRun5(g_s5, g_piv5, g_s15, true, g_P, g_sigs, g_nSig);
   g_ready = true;
   NbDrawChart();
   NbFqRecompute();
   NbFqDrawChart();
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
   if(g_metal == NB_METAL_NONE)
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
//| WAIT markers where the boss drops out of a mode, and the levels  |
//| of the currently clickable learning signal.                      |
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

   // decision markers: one per learning signal
   for(int k = 0; k < g_nSig; k++)
   {
      int s = g_sigs[k].idx;
      if(g_s5.t[s] < tWarm)
         continue;
      string nm = NB_PFX_C + "G_" + IntegerToString(s);
      string side = (g_sigs[k].dir > 0) ? "BUY" : "SELL";
      string tip = side + " entry " +
                   DoubleToString(g_sigs[k].entry, g_digits) + " SL " + DoubleToString(g_sigs[k].sl, g_digits) +
                   " TP1 " + DoubleToString(g_sigs[k].tp1, g_digits) + " TP2 " +
                   DoubleToString(g_sigs[k].tp2, g_digits) + " - " + NbSignalStatusText(g_sigs[k].status);
      double off = g_s5.atr[s] * 0.3;
      if(g_sigs[k].dir > 0)
         NbText(nm, g_s5.t[s], g_s5.l[s] - off, NbSymUp() + " BUY", cUp, 11, ANCHOR_UPPER, tip);
      else
         NbText(nm, g_s5.t[s], g_s5.h[s] + off, NbSymDown() + " SELL", cDn, 11, ANCHOR_LOWER, tip);
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
   int rows = 62;
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
   color cMetal = (g_metal == NB_METAL_SILVER) ? NB_RGB(200, 206, 214) : NB_RGB(212, 175, 55);
   color cKey = NB_RGB(140, 150, 165);
   color cVal = NB_RGB(235, 238, 242);
   color cSec = NB_RGB(212, 175, 55);
   color cUp = NB_RGB(46, 204, 113);
   color cDn = NB_RGB(231, 76, 60);
   color cWait = NB_RGB(241, 196, 15);
   color cExit = NB_RGB(230, 126, 34);
   color cDim = NB_RGB(95, 105, 120);
   if(g_metal == NB_METAL_SILVER)
      cSec = NB_RGB(200, 206, 214);

   NbRect("bg", ox, oy, W, H, cBg, cMetal);

   // title
   int y = oy + pad;
   string title = "NRTR BOSS";
   if(g_metal == NB_METAL_GOLD)
      title = "GOLD NRTR BOSS";
   if(g_metal == NB_METAL_SILVER)
      title = "SILVER NRTR BOSS";
   NbLabel("title", ox + kx, y, title, cMetal, fsT, "Arial Black", ANCHOR_LEFT_UPPER);
   y += (int)MathRound(rh * 1.4);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   g_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   NbLabel("sym", ox + kx, y, g_sym + "   PRICE " + NbPx(bid), cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(4 * sc);

   // big state banner
   string st = NbSymDot() + "  WAIT - NO TRADE";
   color bc = cWait;
   if(g_final == NB_BUY)
   {
      st = NbSymUp() + "  CLICK BUY";
      bc = cUp;
   }
   if(g_final == NB_SELL)
   {
      st = NbSymDown() + "  CLICK SELL";
      bc = cDn;
   }
   if(g_final == NB_EXIT)
   {
      string exSide = (g_advDir > 0) ? "BUY" : "SELL";
      st = "!  EXIT / PROTECT " + exSide;
      bc = cExit;
   }
   if(g_metal == NB_METAL_NONE)
      st = NbSymDot() + "  GOLD / SILVER ONLY";
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
   if(g_final == NB_BUY)
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
   string nyTxt = (g_metal == NB_METAL_NONE) ? "---" : NbNyText(TimeTradeServer());
   color nyC = cVal;
   if(StringFind(nyTxt, "NY OPEN - FIRST") == 0)
      nyC = cExit;
   NbRow("ks", "vs", ox + kx, ox + vx, y, "NEW YORK OPEN", nyTxt, nyC, cKey, fs);
   y += rh;

   bool ok = (g_metal != NB_METAL_NONE && g_ready && g_s15.n > 0 && g_s5.n > 0);
   int i15 = ok ? g_s15.n - 1 : 0;
   int i5 = ok ? g_s5.n - 1 : 0;

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
      if(m15 == NB_WAIT)
         conf = "WAIT (15M NOT IN MODE)";
      else if(d5 != m15)
         conf = "WAIT - 5M AGAINST 15M";
      else if(g_s5.state[i5] != NB_WAIT)
         conf = "READY - WITH 15M";
      else
         conf = "WAIT - WITH 15M";
      confC = (g_s5.state[i5] != NB_WAIT) ? NbDirColor(g_s5.state[i5]) : cWait;
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

   // learning levels
   NbLabel("hl", ox + kx, y + (int)MathRound(3 * sc), "LEARNING LEVELS  -  NO ORDER IS SENT", cSec, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(3 * sc);
   int cur = ok ? g_s5.sigOf[i5] : -1;
   bool live = (cur >= 0 && (g_final == NB_BUY || g_final == NB_SELL) && g_sigs[cur].status == NB_SIG_ACTIVE);
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
   NbRow("k11", "v11", ox + kx, ox + vx, y, "SL (structure)", vS, live ? cDn : cDim, cKey, fs);
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
   string dStatus = (g_metal == NB_METAL_NONE) ? "---" : NbFreshText(g_freshCode);
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
   y += rh + (int)MathRound(4 * sc);

   NbLabel("f1", ox + kx, y, "Learning tool. Aligned conditions, not a profit promise.", cDim, fsH, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;
   NbLabel("f2", ox + kx, y, "It never places, changes or closes an order. You decide.", cDim, fsH, "Arial", ANCHOR_LEFT_UPPER);
}

void NbRow(string kid, string vid, int kx, int vx, int y, string key, string val, color vc, color kc, int fs)
{
   NbLabel(kid, kx, y, key, kc, fs, "Arial", ANCHOR_LEFT_UPPER);
   NbLabel(vid, vx, y, val, vc, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| FIVE-QUESTION PLAN - the per-file adapters (v1.05 metals). Every |
//| line between NB_FQT_BEGIN and NB_FQT_END below is identical text |
//| in the crypto, forex and metals files; only these lines differ.  |
//+------------------------------------------------------------------+
string NbFqLabel()
{
   if(g_metal == NB_METAL_GOLD)
      return "GOLD";
   if(g_metal == NB_METAL_SILVER)
      return "SILVER";
   return "";
}

string NbFqOnlyText()
{
   return "GOLD / SILVER ONLY";
}

color NbFqAccent()
{
   return (g_metal == NB_METAL_SILVER) ? NB_RGB(200, 206, 214) : NB_RGB(212, 175, 55);
}

//--- this file has no session clock of its own: the broker's offset from
//    UTC is taken only when two witnesses agree (server vs PC GMT)
void NbFqClock(bool &ok, long &offset)
{
   ok = NbFqWitnessClock(TimeTradeServer(), TimeGMT(), offset);
}

//--- gold = the plain rules; silver = wider stop + stronger confirmation
//    (explicit inputs, shown on the table)
void NbFqAsset(double &slMult, double &confirmAtr, string &note)
{
   slMult = 1.0;
   confirmAtr = 0.0;
   note = "";
   if(g_metal == NB_METAL_SILVER)
   {
      slMult = InpFqSilverSlMult;
      confirmAtr = InpFqSilverConfirmAtr;
      note = "SILVER: stop x" + DoubleToString(slMult, 1) + ", confirm +" + DoubleToString(confirmAtr, 2) + " ATR";
   }
}

//=== NB_FQT_BEGIN === (identical text in all three files - tests/check_fq_blocks.py)
//+------------------------------------------------------------------+
//| FIVE-QUESTION PLAN - terminal side (v1.05, v1.06 layout)         |
//| Own objects only: <prefix>Q_ (the bottom-middle table) and       |
//| <prefix>F_ (big support / resistance lines, zones, plan lines,   |
//| markers). The main panel and its chart objects are not touched.  |
//| MT5 cuts object text at 63 characters, so every label here is    |
//| built to stay at or under 63 (tested); long rows are two labels. |
//| The per-file adapters NbFqLabel / NbFqOnlyText / NbFqAccent /    |
//| NbFqClock / NbFqAsset sit just above this block.                 |
//+------------------------------------------------------------------+
void NbFqConfig()
{
   g_C.zoneAtr = InpFqZoneAtr;
   g_C.window = InpFqWindowBars;
   g_C.minRR = InpFqMinRR;
   g_C.validBars = InpFqValidBars;
   g_C.openMax = NB_FQ_OPEN_MAX;
   g_C.asiaStart = InpFqAsiaStartUtc;
   g_C.asiaEnd = InpFqAsiaEndUtc;
   g_C.lonStart = InpFqLondonStartUtc;
   g_C.lonEnd = InpFqLondonEndUtc;
   // Asia / London need UTC: only a clock proven by two witnesses gives
   // it. Unknown = those levels are not known (never guessed).
   bool ok = false;
   long off = 0;
   NbFqClock(ok, off);
   g_C.clockOk = ok;
   g_C.offset = ok ? off : 0;
   double slm = 1.0;
   double cfa = 0.0;
   string note = "";
   NbFqAsset(slm, cfa, note);
   g_C.slBufMult = slm;
   g_C.confirmAtr = cfa;
}

void NbFqRecompute()
{
   NbFqConfig();
   NbRunFq(g_s5, g_s15, g_piv15, g_s15.np, g_piv5, g_s5.np, true, g_P, g_C, g_fq, g_fqPlans, g_nFqPlan);
}

//--- a horizontal line that runs to the right edge and beyond (drawn in advance)
void NbFLine(string name, datetime t1, double price, color clr, int width, int style)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t1 + 300, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t1 + 300);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//--- a filled zone behind the candles, from t1 to t2 (t2 may be in the future)
void NbFZone(string name, datetime t1, datetime t2, double p1, double p2, color fill)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//--- chart text drawn in the BACKGROUND (v1.06): behind the candles and
//    therefore never on top of the main panel or the table
void NbFText(string name, datetime t, double price, string txt, color clr, int size, int anchor, string tip)
{
   NbText(name, t, price, txt, clr, size, anchor, tip);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//--- chart: every mapped level (thin), the nearest SUPPORT and RESISTANCE
//    (big line + zone reaching 6 h into the future + what it means in
//    words), the middle, breakout / breakdown closes, the live plan and a
//    marker per plan in history. Redrawn on every new closed bar.
void NbFqDrawChart()
{
   ObjectsDeleteAll(0, NB_PFX_F);
   // the table is recreated right after this (same refresh), so it is drawn
   // after the chart markers and stays on top of them
   ObjectsDeleteAll(0, NB_PFX_Q);
   if(!InpFqDraw || !g_ready || g_s5.n < 1 || ArraySize(g_fq) != g_s5.n)
      return;
   int i = g_s5.n - 1;
   NbLv lv[];
   int nl = NbFqLevelsAt(g_s5, g_s15, g_piv15, g_s15.np, g_C, g_fq, i, lv);
   datetime tNow = g_s5.t[i] + g_s5.sec;          // open of the forming 5M bar
   datetime tL = tNow - 12 * 3600;                 // lines start 12 h back
   datetime tR = tNow + 6 * 3600;                  // zones reach 6 h ahead: drawn BEFORE price gets there
   int tr = g_fq[i].trend;
   double zone = g_fq[i].zone;
   double cl = g_s5.c[i];
   color cUp = NB_RGB(46, 204, 113);
   color cDn = NB_RGB(231, 76, 60);
   color cMid = NB_RGB(150, 150, 150);

   for(int a = 0; a < nl; a++)
   {
      if(lv[a].price == g_fq[i].sup || lv[a].price == g_fq[i].res)
         continue;   // the nearest two are drawn big below
      color lc = (lv[a].price > cl) ? NB_RGB(170, 90, 90) : NB_RGB(80, 160, 110);
      string nm = NB_PFX_F + "LV_" + IntegerToString(a);
      NbFLine(nm, tL, lv[a].price, lc, 1, STYLE_DOT);
      NbFText(nm + "_T", tNow, lv[a].price, NbLvName(lv[a].src) + "  " + NbPx(lv[a].price), lc, 7, ANCHOR_RIGHT_LOWER,
              "Mapped level (" + NbLvSrcText(lv[a].src) + "). " + ((lv[a].price > cl) ? "Above price = resistance." : "Below price = support."));
   }
   if(g_fq[i].res > 0.0)
   {
      double rv = g_fq[i].res;
      NbFZone(NB_PFX_F + "RES_Z", tL, tR, rv - zone, rv + zone, NB_RGB(70, 24, 24));
      NbFLine(NB_PFX_F + "RES", tL, rv, cDn, 3, STYLE_SOLID);
      NbFText(NB_PFX_F + "RES_T", tNow, rv + zone, "RESISTANCE " + NbPx(rv) + "  (" + NbLvName(g_fq[i].resSrc) + ")", cDn, 10,
              ANCHOR_RIGHT_LOWER, "Nearest level ABOVE price (" + NbLvSrcText(g_fq[i].resSrc) + "). Zone = +/- " +
              DoubleToString(g_C.zoneAtr, 2) + " x 15M ATR.");
      NbFText(NB_PFX_F + "RES_H", tNow, rv - zone, NbFqHint(1, tr), cDn, 8, ANCHOR_RIGHT_UPPER, NbFqHint2(1, tr));
   }
   if(g_fq[i].sup > 0.0)
   {
      double sv = g_fq[i].sup;
      NbFZone(NB_PFX_F + "SUP_Z", tL, tR, sv - zone, sv + zone, NB_RGB(20, 60, 36));
      NbFLine(NB_PFX_F + "SUP", tL, sv, cUp, 3, STYLE_SOLID);
      NbFText(NB_PFX_F + "SUP_T", tNow, sv - zone, "SUPPORT " + NbPx(sv) + "  (" + NbLvName(g_fq[i].supSrc) + ")", cUp, 10,
              ANCHOR_RIGHT_UPPER, "Nearest level BELOW price (" + NbLvSrcText(g_fq[i].supSrc) + "). Zone = +/- " +
              DoubleToString(g_C.zoneAtr, 2) + " x 15M ATR.");
      NbFText(NB_PFX_F + "SUP_H", tNow, sv + zone, NbFqHint(-1, tr), cUp, 8, ANCHOR_RIGHT_LOWER, NbFqHint2(-1, tr));
   }
   if(g_fq[i].res > 0.0 && g_fq[i].sup > 0.0)
   {
      double mid = NbRoundTick((g_fq[i].res + g_fq[i].sup) / 2.0, g_P.tick, g_P.digits, 0);
      NbFLine(NB_PFX_F + "MID", tL, mid, cMid, 1, STYLE_DASH);
      NbFText(NB_PFX_F + "MID_T", tNow, mid, "MIDDLE - NO ENTRY HERE", cMid, 8, ANCHOR_RIGHT_LOWER,
              "Halfway between support and resistance: the middle of nowhere.");
   }
   // BREAKOUT / BREAKDOWN: the latest 5M close through the nearest levels
   int bo = (g_fq[i].sup > 0.0) ? NbFqCross(g_s5.c, i, g_C.window, g_fq[i].sup, 1) : -1;
   int bd = (g_fq[i].res > 0.0) ? NbFqCross(g_s5.c, i, g_C.window, g_fq[i].res, -1) : -1;
   if(bo >= 0)
      NbFText(NB_PFX_F + "BO", g_s5.t[bo], g_s5.h[bo] + g_s5.atr[bo] * 0.3,
              NbSymUp() + " BREAKOUT" + ((tr > 0) ? " (with 15M)" : " (against 15M - no trade)"), cUp, 9, ANCHOR_LOWER,
              "5M candle CLOSED above " + NbPx(g_fq[i].sup) + ". Old resistance = new support (retest).");
   if(bd >= 0)
      NbFText(NB_PFX_F + "BD", g_s5.t[bd], g_s5.l[bd] - g_s5.atr[bd] * 0.3,
              NbSymDown() + " BREAKDOWN" + ((tr < 0) ? " (with 15M)" : " (against 15M - no trade)"), cDn, 9, ANCHOR_UPPER,
              "5M candle CLOSED below " + NbPx(g_fq[i].res) + ". Old support = new resistance (retest).");
   // the sweep being watched right now
   if(g_fq[i].kind == NB_PK_SWEEP && g_fq[i].event >= 0 && g_fq[i].status != NB_FQ_READY && g_fq[i].status != NB_FQ_FILLED)
   {
      int e = g_fq[i].event;
      NbFText(NB_PFX_F + "SW", g_s5.t[e], g_fq[i].ext, "SWEEP", NB_RGB(241, 196, 15), 9, (tr > 0) ? ANCHOR_UPPER : ANCHOR_LOWER,
              "Level " + NbPx(g_fq[i].level) + " pierced to " + NbPx(g_fq[i].ext) + ". Confirmation = a 5M close " +
              ((tr > 0) ? "above " : "below ") + NbPx(g_fq[i].trig));
   }
   // one marker per plan in history (hover: levels + what happened)
   for(int k = 0; k < g_nFqPlan; k++)
   {
      int s = g_fqPlans[k].idx;
      if(s < 0 || s >= g_s5.n)
         continue;
      string side = (g_fqPlans[k].dir > 0) ? "BUY" : "SELL";
      string tip = "5-QUESTION PLAN " + side + " LIMIT " + NbPx(g_fqPlans[k].entry) + " SL " + NbPx(g_fqPlans[k].sl) + " TP1 " +
                   NbPx(g_fqPlans[k].tp1) + " (" + DoubleToString(g_fqPlans[k].rr1, 2) + "R) - " + NbFqOutcomeText(g_fqPlans[k].status);
      double off = g_s5.atr[s] * 0.6;
      string nm = NB_PFX_F + "PM_" + IntegerToString(s);
      string txt = "PLAN " + side + " (" + NbFqKindText(g_fqPlans[k].kind, g_fqPlans[k].dir) + ")";
      if(g_fqPlans[k].dir > 0)
         NbFText(nm, g_s5.t[s], g_s5.l[s] - off, NbSymUp() + " " + txt, cUp, 9, ANCHOR_UPPER, tip);
      else
         NbFText(nm, g_s5.t[s], g_s5.h[s] + off, NbSymDown() + " " + txt, cDn, 9, ANCHOR_LOWER, tip);
   }
   // the live plan: its lines start at the plan's candle and run ahead
   int p = g_fq[i].plan;
   if(p >= 0 && p < g_nFqPlan && (g_fq[i].status == NB_FQ_READY || g_fq[i].status == NB_FQ_FILLED))
   {
      datetime tp0 = g_s5.t[g_fqPlans[p].idx];
      string side = (g_fqPlans[p].dir > 0) ? "BUY LIMIT" : "SELL LIMIT";
      NbFLine(NB_PFX_F + "PL_E", tp0, g_fqPlans[p].entry, clrWhite, 2, STYLE_SOLID);
      NbFText(NB_PFX_F + "PL_E_T", tp0, g_fqPlans[p].entry, side + "  " + NbPx(g_fqPlans[p].entry) + "  (you type it)", clrWhite, 9,
              ANCHOR_LEFT_LOWER, "Pending limit at the level = the retest. Nothing is sent.");
      NbFLine(NB_PFX_F + "PL_SL", tp0, g_fqPlans[p].sl, cDn, 1, STYLE_DASH);
      NbFText(NB_PFX_F + "PL_SL_T", tp0, g_fqPlans[p].sl, "SL  " + NbPx(g_fqPlans[p].sl), cDn, 8, ANCHOR_LEFT_LOWER, "Beyond the structure.");
      NbFLine(NB_PFX_F + "PL_T1", tp0, g_fqPlans[p].tp1, cUp, 1, STYLE_DASH);
      NbFText(NB_PFX_F + "PL_T1_T", tp0, g_fqPlans[p].tp1, "TP1  " + NbPx(g_fqPlans[p].tp1) + "  " + DoubleToString(g_fqPlans[p].rr1, 2) + "R",
              cUp, 8, ANCHOR_LEFT_LOWER, "Next mapped level: " + NbLvSrcText(g_fqPlans[p].tp1Src));
      if(g_fqPlans[p].tp2 > 0.0)
      {
         NbFLine(NB_PFX_F + "PL_T2", tp0, g_fqPlans[p].tp2, cUp, 1, STYLE_DOT);
         NbFText(NB_PFX_F + "PL_T2_T", tp0, g_fqPlans[p].tp2, "TP2  " + NbPx(g_fqPlans[p].tp2) + "  " + DoubleToString(g_fqPlans[p].rr2, 2) + "R",
                 cUp, 8, ANCHOR_LEFT_LOWER, "The mapped level after TP1: " + NbLvSrcText(g_fqPlans[p].tp2Src));
      }
   }
}

void NbQRect(string id, int x, int y, int w, int h, color bg, color border)
{
   string name = NB_PFX_Q + id;
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

void NbQLabel(string id, int x, int y, string txt, color clr, int size, string font, int anchor)
{
   string name = NB_PFX_Q + id;
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

//--- YES / NO / ?? in colour
color NbQAnsColor(string ans)
{
   if(ans == "YES")
      return NB_RGB(46, 204, 113);
   if(ans == "NO")
      return NB_RGB(231, 76, 60);
   if(ans == "??")
      return NB_RGB(241, 196, 15);
   return NB_RGB(95, 105, 120);
}

//--- the bottom-middle table. Redrawn every second (price, clock); the
//    answers come from the last CLOSED 5M bar. Stale data = NO TRADE.
void NbFqDrawTable()
{
   if(!InpFqShow)
   {
      ObjectsDeleteAll(0, NB_PFX_Q);
      return;
   }
   double sc = MathMax(0.7, MathMin(1.6, InpPanelScale));
   int W = (int)MathRound(760 * sc);
   int rh = (int)MathRound(15 * sc);
   int pad = (int)MathRound(10 * sc);
   int fs = (int)MathRound(9 * sc);
   int fsS = (int)MathRound(8 * sc);
   int fsT = (int)MathRound(11 * sc);
   int fsB = (int)MathRound(13 * sc);
   int bannerH = (int)MathRound(26 * sc);
   int H = pad * 2 + bannerH + 16 * rh + (int)MathRound(8 * sc);
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   // bottom MIDDLE; pushed sideways only if it would cover the main panel
   int pw = (int)MathRound(430 * sc);   // the main panel's width (NbDrawPanel)
   int ox = (cw - W) / 2;
   if(InpPanelCorner == NB_TOP_LEFT || InpPanelCorner == NB_BOTTOM_LEFT)
   {
      if(ox < InpPanelX + pw + 8)
         ox = InpPanelX + pw + 8;
   }
   else if(ox + W > cw - InpPanelX - pw - 8)
      ox = cw - InpPanelX - pw - 8 - W;
   if(ox < 0)
      ox = 0;
   int oy = ch - H - InpFqBottomY;
   if(oy < 0)
      oy = 0;
   int xr = ox + (int)MathRound(400 * sc);   // right half of the split rows

   color cBg = NB_RGB(16, 20, 28);
   color cMkt = NbFqAccent();
   color cKey = NB_RGB(140, 150, 165);
   color cVal = NB_RGB(235, 238, 242);
   color cUp = NB_RGB(46, 204, 113);
   color cDn = NB_RGB(231, 76, 60);
   color cWait = NB_RGB(241, 196, 15);
   color cSkip = NB_RGB(230, 126, 34);
   color cDim = NB_RGB(95, 105, 120);
   color cFill = NB_RGB(80, 160, 255);

   string lbl = NbFqLabel();
   bool ok = (lbl != "" && g_ready && g_s5.n > 0 && g_s15.n > 0 && ArraySize(g_fq) == g_s5.n);
   int i = ok ? g_s5.n - 1 : 0;
   string limW = "";   // "BUY LIMIT " / "SELL LIMIT " (set below, used in several rows)
   bool gate = ok && g_fresh;           // STALE DATA IS NEVER A PLAN
   int tr = gate ? g_fq[i].trend : 0;
   int st = gate ? g_fq[i].status : NB_FQ_NOTRADE;
   int why = gate ? g_fq[i].why : NB_FW_NONE;
   int kind = gate ? g_fq[i].kind : NB_PK_NONE;
   int p = ok ? g_fq[i].plan : -1;
   bool live = gate && p >= 0 && p < g_nFqPlan && (st == NB_FQ_READY || st == NB_FQ_FILLED);
   int dir = live ? g_fqPlans[p].dir : tr;
   int k15 = ok ? g_s5.map[i] : -1;
   double atr15 = (ok && k15 >= 0) ? g_s15.atr[k15] : 0.0;
   // stale data never shows a live plan on the chart either; the lines come
   // back by themselves when the data is live again
   if(ok && InpFqDraw)
   {
      bool drawn = (ObjectFind(0, NB_PFX_F + "PL_E") >= 0);
      if(!gate && drawn)
         ObjectsDeleteAll(0, NB_PFX_F + "PL_");
      else if(gate && live && !drawn)
         NbFqDrawChart();
   }
   limW = (dir > 0) ? "BUY LIMIT " : "SELL LIMIT ";
   string beyondW = (dir > 0) ? "ABOVE " : "BELOW ";

   NbQRect("bg", ox, oy, W, H, cBg, cMkt);
   int y = oy + pad;

   // title: symbol and the 15M side
   string trTxt = "NO CLEAR TREND";
   color trC = cWait;
   if(tr > 0)
   {
      trTxt = "BULLISH";
      trC = cUp;
   }
   if(tr < 0)
   {
      trTxt = "BEARISH";
      trC = cDn;
   }
   string head = (lbl == "") ? "5-QUESTION PLAN" : (lbl + "  -  15M " + (gate ? trTxt : "---"));
   NbQLabel("title", ox + pad, y, head, gate ? trC : cDim, fsT, "Arial Black", ANCHOR_LEFT_UPPER);
   NbQLabel("sub", ox + W - pad, y + (int)MathRound(2 * sc), "5-QUESTION PLAN  -  15M MAP + 5M TIMING  -  PENDING ORDERS", cMkt, fsS,
            "Arial Black", ANCHOR_RIGHT_UPPER);
   y += (int)MathRound(rh * 1.3);

   // STATUS banner
   string sTxt = "NO TRADE";
   color sC = cDim;
   if(lbl == "")
      sTxt = NbFqOnlyText();
   else if(!ok)
      sTxt = "NO TRADE  -  MISSING DATA";
   else if(!g_fresh)
      sTxt = "NO TRADE  -  DATA STALE / MARKET CLOSED";
   else if(st == NB_FQ_READY && live)
   {
      sTxt = "READY  -  " + limW + NbPx(g_fqPlans[p].entry);
      sC = (dir > 0) ? cUp : cDn;
   }
   else if(st == NB_FQ_FILLED && live)
   {
      sTxt = "FILLED (if you placed it)  -  SL / TP1 RUNNING";
      sC = cFill;
   }
   else if(st == NB_FQ_SETUP)
   {
      sTxt = "SETTING UP  -  SWEPT, WAIT FOR THE CONFIRMATION CLOSE";
      sC = cWait;
   }
   else if(st == NB_FQ_SKIP)
   {
      sTxt = "SKIP  -  " + NbFqWhyText(why);
      if(why == NB_FW_LOW_RR)
         sTxt = "SKIP  -  ONLY " + DoubleToString(g_fq[i].rr1, 2) + "R TO TP1 (NEED " + DoubleToString(g_C.minRR, 1) + ")";
      sC = cSkip;
   }
   else if(st == NB_FQ_WATCH)
   {
      sTxt = "WATCH  -  " + NbFqWhyText(why);
      sC = NB_RGB(120, 170, 220);
   }
   else
      sTxt = "NO TRADE  -  " + NbFqWhyText(why);
   NbQRect("banner", ox + pad, y, W - 2 * pad, bannerH, cBg, sC);
   NbQLabel("status", ox + W / 2, y + bannerH / 2, sTxt, sC, fsB, "Arial Black", ANCHOR_CENTER);
   y += bannerH + (int)MathRound(4 * sc);

   // five questions (left) and the order (right)
   string qKey[5] = {"1  TREND", "2  LOCATION", "3  LIQUIDITY", "4  CONFIRMATION", "5  REWARD"};
   string qAns[5] = {"---", "---", "---", "---", "---"};
   string qTxt[5] = {" ", " ", " ", " ", " "};
   if(gate)
   {
      string stTxt = (k15 >= 0) ? NbStructText(g_s15.st[k15], g_s15.hl[k15], g_s15.ll[k15], g_s15.lk[k15]) : "NOT CONFIRMED";
      qAns[0] = (tr != 0) ? "YES" : "NO";
      qTxt[0] = stTxt + ((tr > 0) ? "  = BUY SIDE ONLY" : ((tr < 0) ? "  = SELL SIDE ONLY" : "  = NO SIDE"));
      string role = (dir > 0) ? "SUPPORT " : "RESISTANCE ";
      if(kind == NB_PK_SWEEP)
      {
         qAns[1] = "YES";
         qTxt[1] = "AT " + role + NbPx(g_fq[i].level) + " (" + NbLvTag(g_fq[i].src) + ")";
      }
      else if(kind == NB_PK_BREAK)
      {
         qAns[1] = "YES";
         qTxt[1] = "RETEST OF " + NbPx(g_fq[i].level) + " (" + NbLvTag(g_fq[i].src) + ")";
      }
      else if(why == NB_FW_AT_LEVEL)
      {
         double lvA = (tr > 0) ? g_fq[i].sup : g_fq[i].res;
         int srA = (tr > 0) ? g_fq[i].supSrc : g_fq[i].resSrc;
         qAns[1] = "YES";
         qTxt[1] = "AT " + role + NbPx(lvA) + " (" + NbLvTag(srA) + ")";
      }
      else if(why == NB_FW_AT_BREAK)
      {
         double lvB = (tr > 0) ? g_fq[i].res : g_fq[i].sup;
         int srB = (tr > 0) ? g_fq[i].resSrc : g_fq[i].supSrc;
         string bW = (tr > 0) ? "AT RESISTANCE " : "AT SUPPORT ";
         string lnW = (tr > 0) ? " - BREAKOUT LINE" : " - BREAKDOWN LINE";
         qAns[1] = "YES";
         qTxt[1] = bW + NbPx(lvB) + " (" + NbLvTag(srB) + ")" + lnW;
      }
      else if(why == NB_FW_MIDDLE && atr15 > 0.0)
      {
         qAns[1] = "NO";
         string dS = (g_fq[i].sup > 0.0) ? DoubleToString((g_s5.c[i] - g_fq[i].sup) / atr15, 1) : "?";
         string dR = (g_fq[i].res > 0.0) ? DoubleToString((g_fq[i].res - g_s5.c[i]) / atr15, 1) : "?";
         qTxt[1] = "MIDDLE: " + dS + " ATR OVER SUPPORT, " + dR + " UNDER RESIST.";
      }
      if(tr != 0)
      {
         if(kind == NB_PK_SWEEP)
         {
            qAns[2] = "YES";
            qTxt[2] = "SWEPT TO " + NbPx(g_fq[i].ext) + ", BACK " + ((dir > 0) ? "ABOVE" : "BELOW");
            qAns[3] = (g_fq[i].conf >= 0) ? "YES" : "NO";
            string cW = (g_fq[i].conf >= 0) ? "5M CLOSED " : "WAIT: 5M CLOSE ";
            qTxt[3] = cW + beyondW + NbPx(g_fq[i].trig);
         }
         else if(kind == NB_PK_BREAK)
         {
            qAns[2] = "YES";
            qTxt[2] = (dir > 0) ? "5M CLOSED ABOVE (BREAKOUT)" : "5M CLOSED BELOW (BREAKDOWN)";
            qAns[3] = "YES";
            qTxt[3] = "BODY CLOSE BEYOND - NOT A WICK";
         }
         else
         {
            qAns[2] = "NO";
            qTxt[2] = "NOT SWEPT / NOT BROKEN YET";
            qAns[3] = "NO";
            qTxt[3] = "NOTHING TO CONFIRM YET";
         }
      }
      if(g_fq[i].rr1 > 0.0)
      {
         qAns[4] = (g_fq[i].rr1 >= g_C.minRR) ? "YES" : "NO";
         qTxt[4] = "TP1 = " + DoubleToString(g_fq[i].rr1, 2) + "R   (NEED " + DoubleToString(g_C.minRR, 1) + "R)";
      }
      else if(why == NB_FW_NO_TARGET)
      {
         qAns[4] = "??";
         qTxt[4] = "NO LEVEL MAPPED BEYOND = UNKNOWN = NO";
      }
      else if(why == NB_FW_NO_STOP)
      {
         qAns[4] = "NO";
         qTxt[4] = "NO CONFIRMED 5M SWING FOR THE SL";
      }
   }
   int xa = ox + pad + (int)MathRound(108 * sc);
   int xt = ox + pad + (int)MathRound(140 * sc);
   int xk = ox + (int)MathRound(450 * sc);
   int xv = ox + (int)MathRound(505 * sc);
   // order column: live plan, or the candidate's numbers (dim when not READY)
   bool haveNum = gate && g_fq[i].entry > 0.0;
   color oC = live ? cVal : cDim;
   string oKey[7] = {"ORDER", "SL", "TP1", "TP2", "R:R", "LOTS", "VALID"};
   string oVal[7] = {"---", "---", "---", "---", "---", "---", "---"};
   if(haveNum)
   {
      oVal[0] = limW + NbPx(g_fq[i].entry);
      string slWhy = (kind == NB_PK_SWEEP) ? ((dir > 0) ? "below sweep low" : "above sweep high")
                                           : ((dir > 0) ? "below 5M swing low" : "above 5M swing high");
      oVal[1] = NbPx(g_fq[i].sl) + "   " + slWhy;
      if(g_fq[i].tp1 > 0.0)
         oVal[2] = NbPx(g_fq[i].tp1) + "   " + NbLvTag(g_fq[i].tp1Src);
      if(g_fq[i].tp2 > 0.0)
         oVal[3] = NbPx(g_fq[i].tp2) + "   " + NbLvTag(g_fq[i].tp2Src);
      else if(g_fq[i].tp1 > 0.0)
         oVal[3] = "--- (no 2nd level mapped)";
      if(g_fq[i].rr1 > 0.0)
         oVal[4] = "1 : " + DoubleToString(g_fq[i].rr1, 2) + ((g_fq[i].rr2 > 0.0) ? ("    /    1 : " + DoubleToString(g_fq[i].rr2, 2)) : "");
      if(g_tick > 0.0 && g_tickValue > 0.0)
      {
         double atRisk = 0.0;
         double lots = NbLotsForRisk(g_balance, InpRiskPercent, g_fq[i].risk, g_tick, g_tickValue, g_volMin, g_volStep, g_volMax, atRisk);
         oVal[5] = (lots > 0.0) ? (DoubleToString(lots, 2) + "   (" + DoubleToString(atRisk, 2) + " " + g_accCcy + " = " +
                                   DoubleToString(InpRiskPercent, 1) + "%)")
                                : ("SKIP - " + DoubleToString(g_volMin, 2) + " lot risks > " + DoubleToString(InpRiskPercent, 1) + "%");
      }
      if(live && st == NB_FQ_READY)
      {
         datetime tExp = g_s5.t[g_fqPlans[p].idx] + (datetime)(g_s5.sec * (g_C.validBars + 1));
         oVal[6] = "not filled by " + TimeToString(tExp, TIME_MINUTES) + " = cancel it";
      }
      else if(live && st == NB_FQ_FILLED && g_fqPlans[p].fillIdx >= 0)
         oVal[6] = "filled in the 5M bar of " + TimeToString(g_s5.t[g_fqPlans[p].fillIdx], TIME_MINUTES);
      else
         oVal[6] = "not a trade: " + NbFqStatusText(st);
   }
   for(int r = 0; r < 7; r++)
   {
      string rid = IntegerToString(r);
      if(r < 5)
      {
         NbQLabel("qk" + rid, ox + pad, y, qKey[r], cKey, fs, "Arial", ANCHOR_LEFT_UPPER);
         NbQLabel("qa" + rid, xa, y, qAns[r], NbQAnsColor(qAns[r]), fs, "Arial Black", ANCHOR_LEFT_UPPER);
         NbQLabel("qt" + rid, xt, y, qTxt[r], gate ? cVal : cDim, fsS, "Arial", ANCHOR_LEFT_UPPER);
      }
      NbQLabel("ok" + rid, xk, y, oKey[r], cKey, fs, "Arial", ANCHOR_LEFT_UPPER);
      color vc = oC;
      if(live && r == 0)
         vc = (dir > 0) ? cUp : cDn;
      if(live && r == 1)
         vc = cDn;
      if(live && (r == 2 || r == 3))
         vc = cUp;
      NbQLabel("ov" + rid, xv, y, oVal[r], vc, fsS, "Arial Bold", ANCHOR_LEFT_UPPER);
      y += rh;
   }
   y += (int)MathRound(3 * sc);

   // NEXT: what to do, in two short lines
   string n1 = "---";
   string n2 = " ";
   if(lbl == "")
      n1 = "This file is for " + NbFqOnlyText();
   else if(!ok)
      n1 = "NEXT: nothing - history is not loaded yet.";
   else if(!g_fresh)
   {
      n1 = "NEXT: nothing - stale data is never a plan.";
      n2 = "Wait for live ticks (see the main panel's DATA CLOCK).";
   }
   else if(st == NB_FQ_READY && live)
   {
      datetime tEnd = g_s5.t[g_fqPlans[p].idx] + (datetime)(g_s5.sec * (g_C.validBars + 1));
      n1 = "NEXT: type " + limW + NbPx(g_fqPlans[p].entry) + "  SL " + NbPx(g_fqPlans[p].sl) + "  TP " + NbPx(g_fqPlans[p].tp1);
      n2 = "Not filled by " + TimeToString(tEnd, TIME_MINUTES) + " = cancel it. No chasing.";
   }
   else if(st == NB_FQ_FILLED && live)
   {
      n1 = "NEXT: if you placed it, leave the SL and TP alone.";
      n2 = "The main panel's EXIT / PROTECT still applies.";
   }
   else if(st == NB_FQ_SETUP)
   {
      n1 = "NEXT: wait for a 5M candle to CLOSE " + beyondW + NbPx(g_fq[i].trig);
      n2 = "then a " + limW + "at " + NbPx(g_fq[i].level) + " (the retest).";
   }
   else if(st == NB_FQ_SKIP)
   {
      n1 = "NEXT: skip this one. Wait for the next setup.";
      n2 = NbFqWhyText(why);
   }
   else if(st == NB_FQ_WATCH && tr > 0)
   {
      n1 = "NEXT: wait. BUY idea 1: a sweep of SUPPORT " + NbPx(g_fq[i].sup);
      n2 = "BUY idea 2: a 5M close above RESISTANCE " + NbPx(g_fq[i].res);
   }
   else if(st == NB_FQ_WATCH && tr < 0)
   {
      n1 = "NEXT: wait. SELL idea 1: a sweep of RESISTANCE " + NbPx(g_fq[i].res);
      n2 = "SELL idea 2: a 5M close below SUPPORT " + NbPx(g_fq[i].sup);
   }
   else
   {
      n1 = "NEXT: nothing.";
      n2 = NbFqWhyText(why);
   }
   NbQLabel("next1", ox + pad, y, n1, (st == NB_FQ_READY && live) ? sC : cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   y += rh;
   NbQLabel("next2", ox + pad, y, n2, cVal, fs, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;

   // the map: two halves per row
   string lvL = "---";
   string lvR = " ";
   string mapL = "---";
   string mapR = " ";
   if(ok)
   {
      lvL = (g_fq[i].sup > 0.0) ? ("SUPPORT " + NbPx(g_fq[i].sup) + " (" + NbLvTag(g_fq[i].supSrc) + ")") : "SUPPORT ---";
      lvR = (g_fq[i].res > 0.0) ? ("RESISTANCE " + NbPx(g_fq[i].res) + " (" + NbLvTag(g_fq[i].resSrc) + ")") : "RESISTANCE ---";
      if(atr15 > 0.0 && g_fq[i].sup > 0.0)
         lvL = lvL + "  " + DoubleToString((g_s5.c[i] - g_fq[i].sup) / atr15, 1) + " ATR below";
      if(atr15 > 0.0 && g_fq[i].res > 0.0)
         lvR = lvR + "  " + DoubleToString((g_fq[i].res - g_s5.c[i]) / atr15, 1) + " ATR above";
      mapL = "15M MAP   PDH " + NbPx(g_fq[i].pdh) + "  PDL " + NbPx(g_fq[i].pdl);
      if(g_C.clockOk)
         mapR = "ASIA " + NbPx(g_fq[i].ash) + " / " + NbPx(g_fq[i].asl) + "   LDN " + NbPx(g_fq[i].loh) + " / " + NbPx(g_fq[i].lol);
      else
         mapR = "ASIA / LONDON: UTC offset unknown - not shown";
   }
   NbQLabel("lvL", ox + pad, y, lvL, cVal, fsS, "Arial", ANCHOR_LEFT_UPPER);
   NbQLabel("lvR", xr, y, lvR, cVal, fsS, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;
   NbQLabel("mapL", ox + pad, y, mapL, cKey, fsS, "Arial", ANCHOR_LEFT_UPPER);
   NbQLabel("mapR", xr, y, mapR, cKey, fsS, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;

   // evidence: the last plan and the count
   string lastL = "LAST PLAN: none in the loaded history yet";
   string lastR = " ";
   if(ok && p >= 0 && p < g_nFqPlan)
   {
      string lsW = (g_fqPlans[p].dir > 0) ? "BUY " : "SELL ";
      lastL = "LAST PLAN: " + lsW + NbFqKindText(g_fqPlans[p].kind, g_fqPlans[p].dir) + " @ " +
              TimeToString(g_s5.t[g_fqPlans[p].idx] + g_s5.sec, TIME_MINUTES) + "  limit " + NbPx(g_fqPlans[p].entry);
      lastR = NbFqOutcomeText(g_fqPlans[p].status);
   }
   NbQLabel("lastL", ox + pad, y, lastL, cVal, fsS, "Arial", ANCHOR_LEFT_UPPER);
   NbQLabel("lastR", xr, y, lastR, cVal, fsS, "Arial Bold", ANCHOR_LEFT_UPPER);
   y += rh;
   int nTp = 0;
   int nSl = 0;
   int nUn = 0;
   int nOp = 0;
   int nTo = 0;
   double netR = 0.0;
   if(ok)
   {
      NbFqTally(g_fqPlans, g_nFqPlan, nTp, nSl, nUn, nOp, nTo);
      netR = NbFqNetR(g_fqPlans, g_nFqPlan);
   }
   string tallyL = "HISTORY " + IntegerToString(InpHistoryDays) + " days: " + IntegerToString(ok ? g_nFqPlan : 0) + " plans - TP1 " +
                   IntegerToString(nTp) + " / SL " + IntegerToString(nSl) + " / not filled " + IntegerToString(nUn);
   string sgnR = (netR >= 0.0) ? "+" : "";
   string tallyR = "open " + IntegerToString(nOp) + ((nTo > 0) ? (" / timed out " + IntegerToString(nTo)) : "") + "   NET " + sgnR +
                   DoubleToString(netR, 1) + "R   " + ((nTp + nSl < 20) ? "(n<20 = luck)" : "(~100 to judge)");
   color netC = cKey;
   if(nTp + nSl >= 20)
      netC = (netR > 0.0) ? cUp : cDn;
   NbQLabel("tallyL", ox + pad, y, tallyL, cKey, fsS, "Arial", ANCHOR_LEFT_UPPER);
   NbQLabel("tallyR", xr, y, tallyR, netC, fsS, "Arial Bold", ANCHOR_LEFT_UPPER);
   y += rh;

   // the main panel's answer, so a disagreement is visible (different rules)
   string mainTxt = "WAIT";
   string mainWhy = NbReasonAt(g_finalR, 0);
   if(g_final == NB_BUY)
   {
      mainTxt = "CLICK BUY";
      mainWhy = " ";
   }
   if(g_final == NB_SELL)
   {
      mainTxt = "CLICK SELL";
      mainWhy = " ";
   }
   if(g_final == NB_EXIT)
   {
      mainTxt = "EXIT / PROTECT";
      mainWhy = " ";
   }
   if(live && st == NB_FQ_READY)
      mainWhy = (g_final == dir) ? "agrees with this table" : "other rules - they can disagree";
   if(mainWhy == "")
      mainWhy = " ";
   NbQLabel("mainL", ox + pad, y, "MAIN PANEL (NRTR rules): " + mainTxt, cKey, fsS, "Arial", ANCHOR_LEFT_UPPER);
   NbQLabel("mainR", xr, y, mainWhy, cKey, fsS, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;
   double slm = 1.0;
   double cfa = 0.0;
   string note = "";
   NbFqAsset(slm, cfa, note);
   NbQLabel("footL", ox + pad, y, "Plan only. Nothing is sent. You type the pending order.", cDim, fsS, "Arial", ANCHOR_LEFT_UPPER);
   NbQLabel("footR", xr, y, (note == "") ? "A hypothesis until the count says otherwise." : note, cDim, fsS, "Arial", ANCHOR_LEFT_UPPER);
}
//=== NB_FQT_END ===
//+------------------------------------------------------------------+
