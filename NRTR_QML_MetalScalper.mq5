//+------------------------------------------------------------------+
//|                                       NRTR_QML_MetalScalper.mq5  |
//|        Gold / Silver scalp + pending-order EA  (MT5 DEMO)        |
//|                                                                  |
//|  M15 = CONTEXT ONLY        (EMA200 + NRTR: shades, never gates)  |
//|   M5 = REGIME + STRUCTURE  (NRTR + confirmed HH/HL or LH/LL)     |
//|         -> BULLISH / BEARISH / CHOP-UNKNOWN                      |
//|   M1 = ENTRY TRIGGER       (NRTR realign + CLOSED candle)        |
//|         -> BUY / SELL / WAIT                                     |
//|   RISK ENGINE  -> AUTO LOT  -> MT5 (demo by default)             |
//|                                                                  |
//|  Two ways to trade, both from CLOSED candles only:               |
//|   1. AUTO SCALP: market order on the M1 trigger. SL 1.5 x ATR5,  |
//|      TP 1.0 x ATR5 (the validated small-R ladder), time stop.    |
//|   2. PENDING ORDER PLAN: QML (Quasimodo) reversal limit orders   |
//|      and 50% pullback limit orders in the M5 regime. Set them    |
//|      and go to work; the EA can place/cancel them for you.       |
//|                                                                  |
//|  FORECAST ARROW: every candle gets an arrow with the forecast    |
//|  for the NEXT candle. It is a forecast, so its hit rate is       |
//|  measured and shown. n < 20 is luck, ~100 to judge.              |
//|                                                                  |
//|  Supported symbols: Gold (XAUUSD / GOLD) and Silver (XAGUSD /    |
//|  SILVER), any broker prefix/suffix. Nothing else.                |
//|  Personal tool. No network, no Telegram, no DLL, no files.       |
//+------------------------------------------------------------------+
#property copyright   "Personal use - demo trading tool"
#property version     "1.00"
#property description "Gold/Silver: M15 context, M5 regime+structure, M1 trigger, risk engine, auto lot."
#property description "Auto scalp + QML/pullback pending-order plans + per-candle forecast arrows."
#property description "Trades on DEMO accounts only unless InpAllowRealAccount is set."
#property strict

//=== NB_ENGINE_BEGIN ===
//+------------------------------------------------------------------+
//| ENGINE                                                           |
//| Pure calculation, no terminal calls. Every array is in time      |
//| order (index 0 = oldest) and holds CLOSED bars only. Every loop  |
//| is causal: the value at bar i uses bars 0..i and nothing later,  |
//| so a historical state can never change when new bars arrive.    |
//| Written in the subset of MQL5 that is also valid C++ so the      |
//| test suite compiles and runs this exact text.                    |
//+------------------------------------------------------------------+

// direction
#define NQ_WAIT   0
#define NQ_BUY    1
#define NQ_SELL  -1

// M5 regime
#define NQ_REG_CHOP  0
#define NQ_REG_BULL  1
#define NQ_REG_BEAR -1

// structure state
#define NQ_ST_UNKNOWN 0
#define NQ_ST_BULL    1
#define NQ_ST_BEAR    2
#define NQ_ST_MIXED   3

// swing labels
#define NQ_L_NONE 0
#define NQ_L_HH   1
#define NQ_L_LH   2
#define NQ_L_EQH  3
#define NQ_L_HL   4
#define NQ_L_LL   5
#define NQ_L_EQL  6

// engine reason bits (why the trigger is WAIT)
#define NQ_R_UNSUPPORTED      0x1
#define NQ_R_STALE            0x2
#define NQ_R_NO_DATA          0x4
#define NQ_R_NO_HIGHER_BAR    0x8
#define NQ_R_NRTR5_NOT_READY  0x10
#define NQ_R_STRUCT_UNCONF    0x20
#define NQ_R_STRUCT_MIXED     0x40
#define NQ_R_STRUCT_CONFLICT  0x80
#define NQ_R_M1_NOT_READY     0x100
#define NQ_R_M1_AGAINST       0x200
#define NQ_R_M1_WAIT_CANDLE   0x400
#define NQ_R_M1_EMA           0x800
#define NQ_R_NO_ATR           0x1000
#define NQ_R_SIG_EXPIRED      0x2000
#define NQ_R_SIG_TP           0x4000
#define NQ_R_SIG_SL           0x8000
#define NQ_R_CANDLE_OPEN      0x10000
#define NQ_R_COUNT            17

// risk-engine gate bits (why the EA will not send an order right now)
#define NQ_K_AUTO_OFF        0x1
#define NQ_K_REAL_ACCOUNT    0x2
#define NQ_K_TRADE_DISABLED  0x4
#define NQ_K_SPREAD          0x8
#define NQ_K_DAILY_CAP       0x10
#define NQ_K_MAX_POS         0x20
#define NQ_K_MAX_TRADES      0x40
#define NQ_K_SESSION         0x80
#define NQ_K_STOPS_LEVEL     0x100
#define NQ_K_LOT_TOO_SMALL   0x200
#define NQ_K_MARGIN          0x400
#define NQ_K_COUNT           11

// scalp signal status
#define NQ_SIG_ACTIVE  1
#define NQ_SIG_TIMEOUT 2
#define NQ_SIG_TP      3
#define NQ_SIG_SL      4

// pending-order plan kinds and status
#define NQ_PLAN_QML 1
#define NQ_PLAN_PB  2
#define NQ_PL_ACTIVE   1
#define NQ_PL_FILLED   2
#define NQ_PL_TP1      3
#define NQ_PL_SL       4
#define NQ_PL_EXPIRED  5
#define NQ_PL_INVALID  6
#define NQ_PL_REPLACED 7

// supported metals
#define NQ_METAL_NONE   0
#define NQ_METAL_GOLD   1
#define NQ_METAL_SILVER 2

struct NqParams
{
   int      atrPeriod;
   double   nrtrMult;
   int      emaSlow;        // M15 context EMA
   int      emaFast;        // M1/M5 momentum EMA (forecast + trigger filter)
   int      swing;          // structure lookback (bars each side)
   double   scalpSlAtr;     // SL = k x ATR(M5)
   double   scalpTpAtr;     // TP = k x ATR(M5)
   int      scalpValidBars; // trigger stays actionable this many M1 bars
   int      scalpTimeBars;  // time stop (M1 bars) for the scalp record
   double   qmlSlBufAtr;    // SL buffer beyond the QML head (x ATR5)
   int      qmlWaitBars;    // bars allowed between head confirmation and neck break
   int      planValidBars;  // pending plan lifetime (M5 bars)
   double   pbRetrace;      // pullback entry = swing + retrace x impulse
   double   pbMinImpulseAtr;// impulse must be at least this many ATR5
   double   pbSlBufAtr;     // SL buffer beyond the pullback swing (x ATR5)
   double   planTp1R;
   double   planTp2R;
   int      fcMinScore;     // |score| needed for a forecast arrow
   double   tick;
   int      digits;
};

struct NqPivot
{
   int      idx;          // bar of the swing
   int      confirmIdx;   // first bar at whose CLOSE the swing is known (idx + swing)
   int      kind;         // +1 swing high, -1 swing low
   double   price;
   int      label;        // NQ_L_*
};

struct NqSignal
{
   int      idx;          // M1 bar whose close triggered it
   int      dir;          // NQ_BUY / NQ_SELL
   double   entry;
   double   sl;
   double   tp;
   double   risk;
   int      status;       // NQ_SIG_*
   int      statusIdx;
};

struct NqPlan
{
   int      kind;         // NQ_PLAN_QML / NQ_PLAN_PB
   int      dir;          // NQ_BUY (buy limit) / NQ_SELL (sell limit)
   int      idx;          // M5 bar at whose close the plan was created
   datetime keyTime;      // time of the key swing (unique id, survives restarts)
   double   entry;
   double   sl;
   double   tp1;
   double   tp2;
   double   risk;
   double   lvlA;         // QML: neck (break level). PB: the swing being retraced
   double   lvlB;         // QML: head. PB: impulse extreme
   int      status;       // NQ_PL_*
   int      statusIdx;
   int      fillIdx;
};

// an armed QML candidate: head confirmed, waiting for the neck to break
struct NqQmlCand
{
   bool     armed;
   int      dir;          // NQ_SELL = bearish QML (sell limit at the left shoulder)
   int      headIdx;
   datetime headTime;
   double   shoulder;
   double   head;
   double   neck;
   int      deadline;
};

struct NqSeries
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
   double   emaS[];
   double   emaF[];
   int      dir[];
   double   stop[];
   double   ext[];
   int      flip[];
   int      st[];
   int      hl[];
   int      ll[];
   int      lk[];
   int      map[];        // index of the higher-TF bar known at this close (-1 none)
   int      hi[];         // higher-TF vote mapped onto this series (ctx or regime)
   int      hiR[];        // higher-TF reason bits mapped
   double   atrHi[];      // higher-TF ATR mapped (M1 uses ATR5 for SL/TP)
   int      ctx[];        // M15: context vote
   int      regime[];     // M5: regime
   int      regR[];       // M5: regime reasons
   int      state[];      // M1: trigger state
   int      reasons[];    // M1: trigger reasons
   int      sigOf[];      // M1: signal index active at this bar
   int      fc[];         // forecast for the NEXT bar, made at this close
   int      fcScore[];
   int      fcHit[];      // +1 hit, -1 miss, 0 unresolved / no forecast
};

void NqSeriesResize(NqSeries &s, int n)
{
   s.n = n;
   s.np = 0;
   ArrayResize(s.t, n);
   ArrayResize(s.o, n);
   ArrayResize(s.h, n);
   ArrayResize(s.l, n);
   ArrayResize(s.c, n);
}

//--- price grid: round to the symbol's real tick size (mode -1 down, +1 up, 0 nearest)
double NqRoundTick(double price, double tick, int digits, int mode)
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

int NqSign(double a, double b)
{
   if(a > b)
      return 1;
   if(a < b)
      return -1;
   return 0;
}

//--- Wilder ATR. 0.0 = not ready.
void NqCalcATR(const double &h[], const double &l[], const double &c[], int n, int period, double &atr[])
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
void NqCalcEMA(const double &c[], int n, int period, double &ema[])
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

//--- NRTR (Nick Rypock Trailing Reverse), ATR-scaled, on CLOSES.
//    Bullish: extreme = highest close since the flip, stop = extreme - k*ATR
//             (ratchets up only). A close below the stop flips bearish.
//    Bearish: mirror. dir 0 = not ready (never guessed).
void NqCalcNRTR(const double &c[], const double &atr[], int n, double k,
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

int NqLabelSwing(int kind, double price, bool havePrev, double prev)
{
   if(!havePrev)
      return NQ_L_NONE;
   if(kind > 0)
   {
      if(price > prev)
         return NQ_L_HH;
      if(price < prev)
         return NQ_L_LH;
      return NQ_L_EQH;
   }
   if(price > prev)
      return NQ_L_HL;
   if(price < prev)
      return NQ_L_LL;
   return NQ_L_EQL;
}

//--- Confirmed swings only. A swing at bar j needs `s` bars on each side and
//    is KNOWN only at the close of bar j+s (confirmIdx). Until then it does
//    not exist - the forming side of a ZigZag is never used.
int NqFindPivots(const double &h[], const double &l[], int n, int s, NqPivot &piv[])
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
         piv[np].label = NqLabelSwing(1, h[j], haveH, lastH);
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
         piv[np].label = NqLabelSwing(-1, l[j], haveL, lastL);
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
void NqStructureSeries(const NqPivot &piv[], int np, int n, int &st[], int &hl[], int &ll[], int &lk[])
{
   ArrayResize(st, n);
   ArrayResize(hl, n);
   ArrayResize(ll, n);
   ArrayResize(lk, n);
   int p = 0;
   int curH = NQ_L_NONE;
   int curL = NQ_L_NONE;
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
      if(curH == NQ_L_NONE || curL == NQ_L_NONE)
         st[t] = NQ_ST_UNKNOWN;
      else if(curH == NQ_L_HH && curL == NQ_L_HL)
         st[t] = NQ_ST_BULL;
      else if(curH == NQ_L_LH && curL == NQ_L_LL)
         st[t] = NQ_ST_BEAR;
      else
         st[t] = NQ_ST_MIXED;
   }
}

//--- map[j] = last bar of A that had CLOSED when bar j of B closed (-1 = none).
//    This is what stops a higher-TF bar that is still forming from leaking
//    into a lower-TF decision.
void NqAlign(const datetime &tA[], int nA, int secA, const datetime &tB[], int nB, int secB, int &map[])
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

//--- M15 CONTEXT: +1 when NRTR bullish AND close above EMA200, -1 mirror,
//    0 otherwise. Context only: it never gates a trade, it shades the panel
//    and tells the forecast which way the tide runs.
int NqContextOf(int dir, double close, double ema)
{
   if(dir == 0 || ema <= 0.0)
      return 0;
   if(dir > 0 && close > ema)
      return 1;
   if(dir < 0 && close < ema)
      return -1;
   return 0;
}

//--- M5 REGIME: NRTR direction agreeing with confirmed structure.
//    Everything else is CHOP / UNKNOWN with the reason named.
int NqRegimeDecision(int dir5, int st, int &reasons)
{
   reasons = 0;
   if(dir5 == 0)
      reasons |= NQ_R_NRTR5_NOT_READY;
   if(st == NQ_ST_UNKNOWN)
      reasons |= NQ_R_STRUCT_UNCONF;
   if(st == NQ_ST_MIXED)
      reasons |= NQ_R_STRUCT_MIXED;
   int sDir = 0;
   if(st == NQ_ST_BULL)
      sDir = 1;
   if(st == NQ_ST_BEAR)
      sDir = -1;
   if(reasons == 0 && dir5 == sDir)
      return dir5;
   if(dir5 != 0 && sDir != 0 && dir5 != sDir)
      reasons |= NQ_R_STRUCT_CONFLICT;
   if(reasons == 0)
      reasons = NQ_R_NO_DATA;
   return NQ_REG_CHOP;
}

//--- FORECAST for the next candle, made at the close of candle i.
//    Votes: higher-TF (x2), own NRTR, close vs fast EMA, last body.
//    fc = +1 UP / -1 DOWN / 0 no arrow. fcHit[i] is judged at close i+1
//    against close[i+1] vs close[i]. An equal close counts as a miss.
void NqForecastSeries(NqSeries &s, int minScore)
{
   int n = s.n;
   ArrayResize(s.fc, n);
   ArrayResize(s.fcScore, n);
   ArrayResize(s.fcHit, n);
   if(minScore < 1)
      minScore = 1;
   for(int i = 0; i < n; i++)
   {
      int score = 2 * s.hi[i] + s.dir[i] + NqSign(s.c[i], s.o[i]);
      if(s.emaF[i] > 0.0)
         score += NqSign(s.c[i], s.emaF[i]);
      s.fcScore[i] = score;
      s.fc[i] = 0;
      if(score >= minScore)
         s.fc[i] = 1;
      else if(score <= -minScore)
         s.fc[i] = -1;
      s.fcHit[i] = 0;
      if(i > 0 && s.fc[i - 1] != 0)
         s.fcHit[i - 1] = (NqSign(s.c[i], s.c[i - 1]) == s.fc[i - 1]) ? 1 : -1;
   }
}

//--- forecast hit rate over resolved arrows from bar `from` on
void NqForecastStats(const NqSeries &s, int from, int &count, int &hits)
{
   count = 0;
   hits = 0;
   if(from < 0)
      from = 0;
   for(int i = from; i + 1 < s.n; i++)
   {
      if(s.fc[i] == 0)
         continue;
      count++;
      if(s.fcHit[i] > 0)
         hits++;
   }
}

//--- M15 pipeline: ATR, EMA200, NRTR, context
void NqRunContext(NqSeries &s, const NqParams &P)
{
   int n = s.n;
   NqCalcATR(s.h, s.l, s.c, n, P.atrPeriod, s.atr);
   NqCalcEMA(s.c, n, P.emaSlow, s.emaS);
   NqCalcEMA(s.c, n, P.emaFast, s.emaF);
   NqCalcNRTR(s.c, s.atr, n, P.nrtrMult, s.dir, s.stop, s.ext, s.flip);
   ArrayResize(s.ctx, n);
   ArrayResize(s.hi, n);
   ArrayResize(s.hiR, n);
   ArrayResize(s.atrHi, n);
   for(int i = 0; i < n; i++)
   {
      s.ctx[i] = NqContextOf(s.dir[i], s.c[i], s.emaS[i]);
      s.hi[i] = 0;        // nothing above M15
      s.hiR[i] = 0;
      s.atrHi[i] = s.atr[i];
   }
   NqForecastSeries(s, P.fcMinScore);
}

//--- M5 pipeline: ATR, fast EMA, NRTR, confirmed structure, regime;
//    the M15 context is mapped in as the forecast's higher vote.
void NqRunRegime(NqSeries &s, NqPivot &piv[], const NqSeries &ctx, const NqParams &P)
{
   int n = s.n;
   NqCalcATR(s.h, s.l, s.c, n, P.atrPeriod, s.atr);
   NqCalcEMA(s.c, n, P.emaFast, s.emaF);
   NqCalcNRTR(s.c, s.atr, n, P.nrtrMult, s.dir, s.stop, s.ext, s.flip);
   s.np = NqFindPivots(s.h, s.l, n, P.swing, piv);
   NqStructureSeries(piv, s.np, n, s.st, s.hl, s.ll, s.lk);
   NqAlign(ctx.t, ctx.n, ctx.sec, s.t, n, s.sec, s.map);
   ArrayResize(s.regime, n);
   ArrayResize(s.regR, n);
   ArrayResize(s.hi, n);
   ArrayResize(s.hiR, n);
   ArrayResize(s.atrHi, n);
   for(int i = 0; i < n; i++)
   {
      int r = 0;
      s.regime[i] = NqRegimeDecision(s.dir[i], s.st[i], r);
      s.regR[i] = r;
      int k = s.map[i];
      s.hi[i] = (k >= 0) ? ctx.ctx[k] : 0;
      s.hiR[i] = 0;
      s.atrHi[i] = s.atr[i];
   }
   NqForecastSeries(s, P.fcMinScore);
}

//--- M1 trigger pass. An "episode" is a stretch where the M5 regime and the
//    M1 NRTR point the same way. Inside an episode the FIRST closed candle
//    with a body in that direction, closing on the right side of the fast
//    EMA, is the scalp signal. It is actionable for scalpValidBars M1 bars.
//    Its record is judged by SL first, then TP, then the time stop - the
//    same sequence the live position experiences.
//    lastClosed=false: the last bar is still forming and is NOT evaluated.
void NqRunTrigger(NqSeries &s, const NqSeries &reg, bool lastClosed, const NqParams &P,
                  NqSignal &sigs[], int &nSig)
{
   int n = s.n;
   NqCalcATR(s.h, s.l, s.c, n, P.atrPeriod, s.atr);
   NqCalcEMA(s.c, n, P.emaFast, s.emaF);
   NqCalcNRTR(s.c, s.atr, n, P.nrtrMult, s.dir, s.stop, s.ext, s.flip);
   NqAlign(reg.t, reg.n, reg.sec, s.t, n, s.sec, s.map);
   ArrayResize(s.hi, n);
   ArrayResize(s.hiR, n);
   ArrayResize(s.atrHi, n);
   for(int i = 0; i < n; i++)
   {
      int k = s.map[i];
      if(k < 0)
      {
         s.hi[i] = 0;
         s.hiR[i] = NQ_R_NO_HIGHER_BAR;
         s.atrHi[i] = 0.0;
      }
      else
      {
         s.hi[i] = reg.regime[k];
         s.hiR[i] = reg.regR[k];
         s.atrHi[i] = reg.atr[k];
      }
   }
   NqForecastSeries(s, P.fcMinScore);

   ArrayResize(s.state, n);
   ArrayResize(s.reasons, n);
   ArrayResize(s.sigOf, n);
   ArrayResize(sigs, 0);
   nSig = 0;
   int nEval = lastClosed ? n : n - 1;
   int epDir = 0;
   int cur = -1;
   int firstOpen = 0;   // signals before this index are all resolved
   for(int b = 0; b < n; b++)
   {
      if(b >= nEval)
      {
         s.state[b] = (b > 0) ? s.state[b - 1] : NQ_WAIT;
         s.reasons[b] = ((b > 0) ? s.reasons[b - 1] : 0) | NQ_R_CANDLE_OPEN;
         s.sigOf[b] = (b > 0) ? s.sigOf[b - 1] : -1;
         continue;
      }
      // 1) judge every unresolved signal on this closed bar
      for(int k = firstOpen; k < nSig; k++)
      {
         if(sigs[k].status != NQ_SIG_ACTIVE || b <= sigs[k].idx)
            continue;
         if(sigs[k].dir > 0)
         {
            if(s.l[b] <= sigs[k].sl)
               sigs[k].status = NQ_SIG_SL;
            else if(s.h[b] >= sigs[k].tp)
               sigs[k].status = NQ_SIG_TP;
         }
         else
         {
            if(s.h[b] >= sigs[k].sl)
               sigs[k].status = NQ_SIG_SL;
            else if(s.l[b] <= sigs[k].tp)
               sigs[k].status = NQ_SIG_TP;
         }
         if(sigs[k].status == NQ_SIG_ACTIVE && b - sigs[k].idx >= P.scalpTimeBars)
            sigs[k].status = NQ_SIG_TIMEOUT;
         if(sigs[k].status != NQ_SIG_ACTIVE)
            sigs[k].statusIdx = b;
      }
      while(firstOpen < nSig && sigs[firstOpen].status != NQ_SIG_ACTIVE)
         firstOpen++;
      // 2) episode bookkeeping
      int reg5 = s.hi[b];
      int d = s.dir[b];
      int align = (reg5 != 0 && d == reg5) ? reg5 : 0;
      if(align != epDir)
      {
         epDir = align;
         cur = -1;
      }
      // 3) decision
      int r = 0;
      if(reg5 == 0)
         r |= (s.hiR[b] != 0) ? s.hiR[b] : NQ_R_NO_DATA;
      else if(d == 0)
         r |= NQ_R_M1_NOT_READY;
      else if(d != reg5)
         r |= NQ_R_M1_AGAINST;
      else
      {
         if(cur < 0)
         {
            bool body = (reg5 > 0) ? (s.c[b] > s.o[b]) : (s.c[b] < s.o[b]);
            bool emaOk = (s.emaF[b] > 0.0) && ((reg5 > 0) ? (s.c[b] > s.emaF[b]) : (s.c[b] < s.emaF[b]));
            if(!body)
               r |= NQ_R_M1_WAIT_CANDLE;
            else if(!emaOk)
               r |= NQ_R_M1_EMA;
            else if(s.atrHi[b] <= 0.0)
               r |= NQ_R_NO_ATR;
            else
            {
               double entry = s.c[b];
               double sl = (reg5 > 0) ? NqRoundTick(entry - P.scalpSlAtr * s.atrHi[b], P.tick, P.digits, -1)
                                      : NqRoundTick(entry + P.scalpSlAtr * s.atrHi[b], P.tick, P.digits, 1);
               double tp = (reg5 > 0) ? NqRoundTick(entry + P.scalpTpAtr * s.atrHi[b], P.tick, P.digits, 1)
                                      : NqRoundTick(entry - P.scalpTpAtr * s.atrHi[b], P.tick, P.digits, -1);
               double risk = NormalizeDouble(MathAbs(entry - sl), P.digits);
               double minRisk = (P.tick > 0.0) ? P.tick * 0.5 : 0.0;
               if(risk <= minRisk || MathAbs(tp - entry) <= minRisk)
                  r |= NQ_R_NO_ATR;
               else
               {
                  ArrayResize(sigs, nSig + 1, 64);
                  sigs[nSig].idx = b;
                  sigs[nSig].dir = reg5;
                  sigs[nSig].entry = entry;
                  sigs[nSig].sl = sl;
                  sigs[nSig].tp = tp;
                  sigs[nSig].risk = risk;
                  sigs[nSig].status = NQ_SIG_ACTIVE;
                  sigs[nSig].statusIdx = b;
                  cur = nSig;
                  nSig++;
               }
            }
         }
         if(cur >= 0)
         {
            if(sigs[cur].status == NQ_SIG_TP)
               r |= NQ_R_SIG_TP;
            else if(sigs[cur].status == NQ_SIG_SL)
               r |= NQ_R_SIG_SL;
            else if(sigs[cur].status == NQ_SIG_TIMEOUT || b - sigs[cur].idx >= P.scalpValidBars)
               r |= NQ_R_SIG_EXPIRED;
         }
      }
      s.sigOf[b] = cur;
      if(r == 0 && cur >= 0 && sigs[cur].status == NQ_SIG_ACTIVE)
      {
         s.state[b] = reg5;
         s.reasons[b] = 0;
      }
      else
      {
         s.state[b] = NQ_WAIT;
         s.reasons[b] = (r != 0) ? r : NQ_R_NO_DATA;
      }
   }
}

//--- helpers for the plan pass
void NqQmlCandReset(NqQmlCand &c)
{
   c.armed = false;
   c.dir = 0;
   c.headIdx = -1;
   c.headTime = 0;
   c.shoulder = 0.0;
   c.head = 0.0;
   c.neck = 0.0;
   c.deadline = -1;
}

void NqPlanClose(NqPlan &p, int status, int at)
{
   p.status = status;
   p.statusIdx = at;
}

// judge one existing plan on closed M5 bar t (t > p.idx)
void NqPlanJudge(NqPlan &p, const NqSeries &s, int t, const NqParams &P)
{
   if(p.status == NQ_PL_ACTIVE)
   {
      bool filled = (p.dir > 0) ? (s.l[t] <= p.entry) : (s.h[t] >= p.entry);
      if(filled)
      {
         p.status = NQ_PL_FILLED;
         p.fillIdx = t;
         p.statusIdx = t;
         // pessimistic: a fill and a stop on the same bar is a stop
         if(p.dir > 0 && s.l[t] <= p.sl)
            NqPlanClose(p, NQ_PL_SL, t);
         else if(p.dir < 0 && s.h[t] >= p.sl)
            NqPlanClose(p, NQ_PL_SL, t);
         return;
      }
      // An unfilled limit sits between the price and its own stop, so the
      // price cannot close beyond the stop side without filling it first:
      // a QML plan ends only by fill or expiry. A pullback plan is also
      // cancelled when the M5 regime it rides turns (NRTR flips on a close,
      // which can happen above a buy limit).
      if(p.kind == NQ_PLAN_PB)
      {
         if((p.dir > 0 && s.regime[t] != NQ_REG_BULL) || (p.dir < 0 && s.regime[t] != NQ_REG_BEAR))
         {
            NqPlanClose(p, NQ_PL_INVALID, t);
            return;
         }
      }
      if(t - p.idx >= P.planValidBars)
         NqPlanClose(p, NQ_PL_EXPIRED, t);
      return;
   }
   if(p.status == NQ_PL_FILLED)
   {
      if(p.dir > 0)
      {
         if(s.l[t] <= p.sl)
            NqPlanClose(p, NQ_PL_SL, t);
         else if(s.h[t] >= p.tp1)
            NqPlanClose(p, NQ_PL_TP1, t);
      }
      else
      {
         if(s.h[t] >= p.sl)
            NqPlanClose(p, NQ_PL_SL, t);
         else if(s.l[t] <= p.tp1)
            NqPlanClose(p, NQ_PL_TP1, t);
      }
   }
}

// a new plan supersedes the active plan of the same kind and direction
void NqPlanSupersede(NqPlan &plans[], int nPlans, int kind, int dir, int at)
{
   for(int k = 0; k < nPlans; k++)
      if(plans[k].kind == kind && plans[k].dir == dir && plans[k].status == NQ_PL_ACTIVE)
         NqPlanClose(plans[k], NQ_PL_REPLACED, at);
}

int NqPlanAdd(NqPlan &plans[], int &nPlans, const NqPlan &p)
{
   ArrayResize(plans, nPlans + 1, 64);
   plans[nPlans] = p;
   nPlans++;
   return nPlans - 1;
}

//--- PENDING ORDER PLANS on closed M5 bars. Causal: at bar t only pivots
//    confirmed by t and closes up to t are used.
//
//    QML (Quasimodo) reversal, bearish: swing high A (left shoulder), swing
//    low B (neck), swing high C above A (head), then a CLOSE below B.
//    -> SELL LIMIT at A, SL above C, TP1 = 1R, TP2 = 2R. Bullish mirror.
//
//    PULLBACK in the regime: when a new HH (BULL) is confirmed, BUY LIMIT
//    at the retrace of the leg from the last confirmed HL to that HH,
//    SL below the HL, TP1 = 1R, TP2 = 2R. Mirror for BEAR.
void NqFindPlans(const NqSeries &s, const NqPivot &piv[], int np, const NqParams &P,
                 NqPlan &plans[], int &nPlans)
{
   ArrayResize(plans, 0);
   nPlans = 0;
   int n = s.n;
   int p = 0;
   NqQmlCand cb;   // bearish candidate
   NqQmlCand cu;   // bullish candidate
   NqQmlCandReset(cb);
   NqQmlCandReset(cu);
   int firstOpen = 0;
   for(int t = 0; t < n; t++)
   {
      // 1) existing plans see this bar
      for(int k = firstOpen; k < nPlans; k++)
         if((plans[k].status == NQ_PL_ACTIVE || plans[k].status == NQ_PL_FILLED) && t > plans[k].idx)
            NqPlanJudge(plans[k], s, t, P);
      while(firstOpen < nPlans && plans[firstOpen].status != NQ_PL_ACTIVE && plans[firstOpen].status != NQ_PL_FILLED)
         firstOpen++;

      // 2) pivots confirmed at this close
      while(p < np && piv[p].confirmIdx <= t)
      {
         int q = p;
         p++;
         if(piv[q].confirmIdx != t)
            continue;   // (older pivots were confirmed on earlier bars already processed)
         double atr = s.atr[t];
         if(atr <= 0.0)
            continue;
         if(piv[q].kind > 0)
         {
            // previous swing low (neck / retraced swing), then the swing high before it
            int qb = q - 1;
            while(qb >= 0 && piv[qb].kind > 0)
               qb--;
            int qa = qb - 1;
            while(qa >= 0 && piv[qa].kind < 0)
               qa--;
            if(qb >= 0 && qa >= 0 && piv[q].price > piv[qa].price && piv[qb].price < piv[qa].price)
            {
               cb.armed = true;
               cb.dir = NQ_SELL;
               cb.headIdx = piv[q].idx;
               cb.headTime = s.t[piv[q].idx];
               cb.shoulder = piv[qa].price;
               cb.head = piv[q].price;
               cb.neck = piv[qb].price;
               cb.deadline = t + P.qmlWaitBars;
               // bars between the head and its confirmation are already closed
               for(int j = piv[q].idx + 1; j < t; j++)
                  if(s.c[j] < cb.neck)
                  {
                     cb.deadline = t;   // break already happened: decide at t
                     break;
                  }
            }
            // pullback BUY: new HH in a BULL regime, retrace of HL -> HH
            if(qb >= 0 && piv[q].label == NQ_L_HH && s.regime[t] == NQ_REG_BULL &&
               piv[q].price - piv[qb].price >= P.pbMinImpulseAtr * atr)
            {
               double lo = piv[qb].price;
               double hiP = piv[q].price;
               double entry = NqRoundTick(lo + P.pbRetrace * (hiP - lo), P.tick, P.digits, 0);
               double sl = NqRoundTick(lo - P.pbSlBufAtr * atr, P.tick, P.digits, -1);
               double risk = NormalizeDouble(entry - sl, P.digits);
               if(risk > 0.0 && s.c[t] > entry)
               {
                  NqPlan pl;
                  pl.kind = NQ_PLAN_PB;
                  pl.dir = NQ_BUY;
                  pl.idx = t;
                  pl.keyTime = s.t[piv[q].idx];
                  pl.entry = entry;
                  pl.sl = sl;
                  pl.tp1 = NqRoundTick(entry + P.planTp1R * risk, P.tick, P.digits, 0);
                  pl.tp2 = NqRoundTick(entry + P.planTp2R * risk, P.tick, P.digits, 0);
                  pl.risk = risk;
                  pl.lvlA = lo;
                  pl.lvlB = hiP;
                  pl.status = NQ_PL_ACTIVE;
                  pl.statusIdx = t;
                  pl.fillIdx = -1;
                  NqPlanSupersede(plans, nPlans, NQ_PLAN_PB, NQ_BUY, t);
                  NqPlanAdd(plans, nPlans, pl);
               }
            }
         }
         else
         {
            int qb = q - 1;
            while(qb >= 0 && piv[qb].kind < 0)
               qb--;
            int qa = qb - 1;
            while(qa >= 0 && piv[qa].kind > 0)
               qa--;
            if(qb >= 0 && qa >= 0 && piv[q].price < piv[qa].price && piv[qb].price > piv[qa].price)
            {
               cu.armed = true;
               cu.dir = NQ_BUY;
               cu.headIdx = piv[q].idx;
               cu.headTime = s.t[piv[q].idx];
               cu.shoulder = piv[qa].price;
               cu.head = piv[q].price;
               cu.neck = piv[qb].price;
               cu.deadline = t + P.qmlWaitBars;
               for(int j = piv[q].idx + 1; j < t; j++)
                  if(s.c[j] > cu.neck)
                  {
                     cu.deadline = t;
                     break;
                  }
            }
            // pullback SELL: new LL in a BEAR regime, retrace of LH -> LL
            if(qb >= 0 && piv[q].label == NQ_L_LL && s.regime[t] == NQ_REG_BEAR &&
               piv[qb].price - piv[q].price >= P.pbMinImpulseAtr * atr)
            {
               double hiP = piv[qb].price;
               double lo = piv[q].price;
               double entry = NqRoundTick(hiP - P.pbRetrace * (hiP - lo), P.tick, P.digits, 0);
               double sl = NqRoundTick(hiP + P.pbSlBufAtr * atr, P.tick, P.digits, 1);
               double risk = NormalizeDouble(sl - entry, P.digits);
               if(risk > 0.0 && s.c[t] < entry)
               {
                  NqPlan pl;
                  pl.kind = NQ_PLAN_PB;
                  pl.dir = NQ_SELL;
                  pl.idx = t;
                  pl.keyTime = s.t[piv[q].idx];
                  pl.entry = entry;
                  pl.sl = sl;
                  pl.tp1 = NqRoundTick(entry - P.planTp1R * risk, P.tick, P.digits, 0);
                  pl.tp2 = NqRoundTick(entry - P.planTp2R * risk, P.tick, P.digits, 0);
                  pl.risk = risk;
                  pl.lvlA = hiP;
                  pl.lvlB = lo;
                  pl.status = NQ_PL_ACTIVE;
                  pl.statusIdx = t;
                  pl.fillIdx = -1;
                  NqPlanSupersede(plans, nPlans, NQ_PLAN_PB, NQ_SELL, t);
                  NqPlanAdd(plans, nPlans, pl);
               }
            }
         }
      }

      // 3) armed QML candidates: neck break on this close -> plan
      if(cb.armed)
      {
         if(s.c[t] < cb.neck && s.atr[t] > 0.0)
         {
            double entry = NqRoundTick(cb.shoulder, P.tick, P.digits, 0);
            double sl = NqRoundTick(cb.head + P.qmlSlBufAtr * s.atr[t], P.tick, P.digits, 1);
            double risk = NormalizeDouble(sl - entry, P.digits);
            if(risk > 0.0 && s.c[t] < entry)
            {
               NqPlan pl;
               pl.kind = NQ_PLAN_QML;
               pl.dir = NQ_SELL;
               pl.idx = t;
               pl.keyTime = cb.headTime;
               pl.entry = entry;
               pl.sl = sl;
               pl.tp1 = NqRoundTick(entry - P.planTp1R * risk, P.tick, P.digits, 0);
               pl.tp2 = NqRoundTick(entry - P.planTp2R * risk, P.tick, P.digits, 0);
               pl.risk = risk;
               pl.lvlA = cb.neck;
               pl.lvlB = cb.head;
               pl.status = NQ_PL_ACTIVE;
               pl.statusIdx = t;
               pl.fillIdx = -1;
               NqPlanSupersede(plans, nPlans, NQ_PLAN_QML, NQ_SELL, t);
               NqPlanAdd(plans, nPlans, pl);
            }
            cb.armed = false;
         }
         else if(t >= cb.deadline || s.c[t] > cb.head)
            cb.armed = false;
      }
      if(cu.armed)
      {
         if(s.c[t] > cu.neck && s.atr[t] > 0.0)
         {
            double entry = NqRoundTick(cu.shoulder, P.tick, P.digits, 0);
            double sl = NqRoundTick(cu.head - P.qmlSlBufAtr * s.atr[t], P.tick, P.digits, -1);
            double risk = NormalizeDouble(entry - sl, P.digits);
            if(risk > 0.0 && s.c[t] > entry)
            {
               NqPlan pl;
               pl.kind = NQ_PLAN_QML;
               pl.dir = NQ_BUY;
               pl.idx = t;
               pl.keyTime = cu.headTime;
               pl.entry = entry;
               pl.sl = sl;
               pl.tp1 = NqRoundTick(entry + P.planTp1R * risk, P.tick, P.digits, 0);
               pl.tp2 = NqRoundTick(entry + P.planTp2R * risk, P.tick, P.digits, 0);
               pl.risk = risk;
               pl.lvlA = cu.neck;
               pl.lvlB = cu.head;
               pl.status = NQ_PL_ACTIVE;
               pl.statusIdx = t;
               pl.fillIdx = -1;
               NqPlanSupersede(plans, nPlans, NQ_PLAN_QML, NQ_BUY, t);
               NqPlanAdd(plans, nPlans, pl);
            }
            cu.armed = false;
         }
         else if(t >= cu.deadline || s.c[t] < cu.head)
            cu.armed = false;
      }
   }
}

//--- index of the newest plan of `kind` that is ACTIVE or FILLED (-1 none)
int NqLatestPlan(const NqPlan &plans[], int nPlans, int kind)
{
   for(int k = nPlans - 1; k >= 0; k--)
      if(plans[k].kind == kind && (plans[k].status == NQ_PL_ACTIVE || plans[k].status == NQ_PL_FILLED))
         return k;
   return -1;
}

//--- plan record: how many got filled and how many of those reached TP1
void NqPlanStats(const NqPlan &plans[], int nPlans, int kind, int &filled, int &won, int &lost)
{
   filled = 0;
   won = 0;
   lost = 0;
   for(int k = 0; k < nPlans; k++)
   {
      if(plans[k].kind != kind)
         continue;
      if(plans[k].status == NQ_PL_TP1 || plans[k].status == NQ_PL_SL || plans[k].status == NQ_PL_FILLED)
         filled++;
      if(plans[k].status == NQ_PL_TP1)
         won++;
      if(plans[k].status == NQ_PL_SL)
         lost++;
   }
}

void NqSignalStats(const NqSignal &sigs[], int nSig, int &done, int &won, int &lost)
{
   done = 0;
   won = 0;
   lost = 0;
   for(int k = 0; k < nSig; k++)
   {
      if(sigs[k].status == NQ_SIG_ACTIVE)
         continue;
      done++;
      if(sigs[k].status == NQ_SIG_TP)
         won++;
      if(sigs[k].status == NQ_SIG_SL)
         lost++;
   }
}

//--- RISK ENGINE ---------------------------------------------------------
// money at risk for one trade (never more than the explicit percentage)
double NqRiskMoney(double balance, double riskPct)
{
   if(balance <= 0.0 || riskPct <= 0.0)
      return 0.0;
   return balance * riskPct / 100.0;
}

// AUTO LOT: the largest lot on the volume grid whose loss at the SL is at
// most riskMoney. 0.0 = even the minimum lot risks too much -> no trade
// (the EA refuses rather than widening the risk).
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

// loss of `lot` lots at the SL, in account money
double NqLossAt(double lot, double slDist, double tick, double tickValue)
{
   if(lot <= 0.0 || slDist <= 0.0 || tick <= 0.0 || tickValue <= 0.0)
      return 0.0;
   return lot * slDist / tick * tickValue;
}

// session filter in server hours; start==end (or 0..24) = always on
bool NqInSession(int hour, int startH, int endH)
{
   if(startH == endH || (startH <= 0 && endH >= 24))
      return true;
   if(startH < endH)
      return (hour >= startH && hour < endH);
   return (hour >= startH || hour < endH);
}

// the gate: every reason the EA must NOT send a new order right now
int NqRiskGate(bool autoOn, bool isDemo, bool allowReal, bool tradeAllowed,
               int spreadPts, int maxSpreadPts, double dayPnl, double dayCapMoney,
               int openCount, int maxOpen, int tradesToday, int maxTrades, bool inSession)
{
   int g = 0;
   if(!autoOn)
      g |= NQ_K_AUTO_OFF;
   if(!isDemo && !allowReal)
      g |= NQ_K_REAL_ACCOUNT;
   if(!tradeAllowed)
      g |= NQ_K_TRADE_DISABLED;
   if(maxSpreadPts > 0 && spreadPts > maxSpreadPts)
      g |= NQ_K_SPREAD;
   if(dayCapMoney > 0.0 && dayPnl <= -dayCapMoney)
      g |= NQ_K_DAILY_CAP;
   if(maxOpen > 0 && openCount >= maxOpen)
      g |= NQ_K_MAX_POS;
   if(maxTrades > 0 && tradesToday >= maxTrades)
      g |= NQ_K_MAX_TRADES;
   if(!inSession)
      g |= NQ_K_SESSION;
   return g;
}

//--- data is only usable if the last closed bars are recent
bool NqIsFresh(datetime last1, int sec1, datetime last5, int sec5, datetime last15, int sec15, datetime now)
{
   if(last1 <= 0 || last5 <= 0 || last15 <= 0)
      return false;
   if(now - (last1 + sec1) > 3 * sec1)
      return false;
   if(now - (last5 + sec5) > 3 * sec5)
      return false;
   if(now - (last15 + sec15) > 2 * sec15)
      return false;
   return true;
}

//--- Gold / Silver only. Broker prefixes/suffixes are fine (XAUUSD.m, #XAGUSD).
int NqMetalOf(string name, string base, string profitCcy)
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
      return NQ_METAL_NONE;
   if(StringFind(u, "XAU") == 0 || StringFind(u, "GOLD") == 0 || b == "XAU")
      return NQ_METAL_GOLD;
   if(StringFind(u, "XAG") == 0 || StringFind(u, "SILVER") == 0 || b == "XAG")
      return NQ_METAL_SILVER;
   return NQ_METAL_NONE;
}

//--- text helpers (ASCII source; symbols built from code points)
string NqSymArrow() { return ShortToString(0x2192); }
string NqSymDot()   { return ShortToString(0x25CF); }
string NqSymUp()    { return ShortToString(0x25B2); }
string NqSymDown()  { return ShortToString(0x25BC); }

string NqLabelName(int lbl)
{
   switch(lbl)
   {
      case NQ_L_HH:  return "HH";
      case NQ_L_LH:  return "LH";
      case NQ_L_EQH: return "EQH";
      case NQ_L_HL:  return "HL";
      case NQ_L_LL:  return "LL";
      case NQ_L_EQL: return "EQL";
   }
   return "?";
}

string NqDirText(int d)
{
   if(d > 0)
      return "BULLISH";
   if(d < 0)
      return "BEARISH";
   return "NOT READY";
}

string NqContextText(int c)
{
   if(c > 0)
      return "BULLISH";
   if(c < 0)
      return "BEARISH";
   return "NEUTRAL";
}

string NqRegimeText(int r)
{
   if(r == NQ_REG_BULL)
      return "BULLISH";
   if(r == NQ_REG_BEAR)
      return "BEARISH";
   return "CHOP / UNKNOWN";
}

string NqStructText(int st, int hl, int ll, int lk)
{
   if(st == NQ_ST_UNKNOWN)
      return "NOT CONFIRMED";
   string a = NqLabelName(hl);
   string b = NqLabelName(ll);
   string txt = (lk > 0) ? (b + " " + NqSymArrow() + " " + a) : (a + " " + NqSymArrow() + " " + b);
   if(st == NQ_ST_MIXED)
      txt = txt + "  (MIXED)";
   return txt;
}

int NqReasonBit(int k)
{
   switch(k)
   {
      case 0:  return NQ_R_UNSUPPORTED;
      case 1:  return NQ_R_STALE;
      case 2:  return NQ_R_NO_DATA;
      case 3:  return NQ_R_NO_HIGHER_BAR;
      case 4:  return NQ_R_NRTR5_NOT_READY;
      case 5:  return NQ_R_STRUCT_UNCONF;
      case 6:  return NQ_R_STRUCT_MIXED;
      case 7:  return NQ_R_STRUCT_CONFLICT;
      case 8:  return NQ_R_M1_NOT_READY;
      case 9:  return NQ_R_M1_AGAINST;
      case 10: return NQ_R_CANDLE_OPEN;
      case 11: return NQ_R_M1_WAIT_CANDLE;
      case 12: return NQ_R_M1_EMA;
      case 13: return NQ_R_NO_ATR;
      case 14: return NQ_R_SIG_SL;
      case 15: return NQ_R_SIG_TP;
      case 16: return NQ_R_SIG_EXPIRED;
   }
   return 0;
}

string NqReasonName(int bit)
{
   switch(bit)
   {
      case NQ_R_UNSUPPORTED:     return "GOLD / SILVER ONLY";
      case NQ_R_STALE:           return "DATA STALE / MARKET CLOSED";
      case NQ_R_NO_DATA:         return "MISSING DATA - NOT ENOUGH HISTORY";
      case NQ_R_NO_HIGHER_BAR:   return "NO CLOSED M5 BAR YET";
      case NQ_R_NRTR5_NOT_READY: return "M5 NRTR NOT READY";
      case NQ_R_STRUCT_UNCONF:   return "M5 STRUCTURE NOT CONFIRMED";
      case NQ_R_STRUCT_MIXED:    return "M5 STRUCTURE MIXED - CHOP";
      case NQ_R_STRUCT_CONFLICT: return "M5 STRUCTURE AGAINST NRTR - CHOP";
      case NQ_R_M1_NOT_READY:    return "M1 NRTR NOT READY";
      case NQ_R_M1_AGAINST:      return "M1 AGAINST M5 REGIME";
      case NQ_R_CANDLE_OPEN:     return "M1 CANDLE NOT CLOSED YET";
      case NQ_R_M1_WAIT_CANDLE:  return "WAIT FOR M1 CANDLE TO CLOSE IN DIRECTION";
      case NQ_R_M1_EMA:          return "M1 CLOSE ON WRONG SIDE OF FAST EMA";
      case NQ_R_NO_ATR:          return "ATR NOT READY - NO SL/TP";
      case NQ_R_SIG_SL:          return "LAST SCALP HIT SL - WAIT FOR NEW EPISODE";
      case NQ_R_SIG_TP:          return "LAST SCALP REACHED TP - WAIT FOR NEW EPISODE";
      case NQ_R_SIG_EXPIRED:     return "TRIGGER EXPIRED - WAIT FOR NEW EPISODE";
   }
   return "";
}

// nth (0-based) reason present in r, in reading order; "" if none
string NqReasonAt(int r, int nth)
{
   int seen = 0;
   for(int k = 0; k < NQ_R_COUNT; k++)
   {
      int bit = NqReasonBit(k);
      if((r & bit) != 0)
      {
         if(seen == nth)
            return NqReasonName(bit);
         seen++;
      }
   }
   return "";
}

int NqGateBit(int k)
{
   switch(k)
   {
      case 0:  return NQ_K_REAL_ACCOUNT;
      case 1:  return NQ_K_TRADE_DISABLED;
      case 2:  return NQ_K_AUTO_OFF;
      case 3:  return NQ_K_DAILY_CAP;
      case 4:  return NQ_K_MAX_TRADES;
      case 5:  return NQ_K_MAX_POS;
      case 6:  return NQ_K_SESSION;
      case 7:  return NQ_K_SPREAD;
      case 8:  return NQ_K_STOPS_LEVEL;
      case 9:  return NQ_K_LOT_TOO_SMALL;
      case 10: return NQ_K_MARGIN;
   }
   return 0;
}

string NqGateName(int bit)
{
   switch(bit)
   {
      case NQ_K_REAL_ACCOUNT:   return "REAL ACCOUNT - BLOCKED (demo only)";
      case NQ_K_TRADE_DISABLED: return "AUTOTRADING OFF IN TERMINAL / EA";
      case NQ_K_AUTO_OFF:       return "AUTO TRADE SWITCHED OFF";
      case NQ_K_DAILY_CAP:      return "DAILY LOSS CAP HIT - NO NEW TRADES";
      case NQ_K_MAX_TRADES:     return "MAX TRADES FOR TODAY REACHED";
      case NQ_K_MAX_POS:        return "MAX OPEN POSITIONS REACHED";
      case NQ_K_SESSION:        return "OUTSIDE TRADING SESSION";
      case NQ_K_SPREAD:         return "SPREAD TOO WIDE";
      case NQ_K_STOPS_LEVEL:    return "SL/TP INSIDE BROKER STOPS LEVEL";
      case NQ_K_LOT_TOO_SMALL:  return "MIN LOT RISKS MORE THAN ALLOWED";
      case NQ_K_MARGIN:         return "NOT ENOUGH FREE MARGIN";
   }
   return "";
}

string NqGateAt(int g, int nth)
{
   int seen = 0;
   for(int k = 0; k < NQ_K_COUNT; k++)
   {
      int bit = NqGateBit(k);
      if((g & bit) != 0)
      {
         if(seen == nth)
            return NqGateName(bit);
         seen++;
      }
   }
   return "";
}

string NqSignalStatusText(int status)
{
   switch(status)
   {
      case NQ_SIG_ACTIVE:  return "active";
      case NQ_SIG_TIMEOUT: return "time stop";
      case NQ_SIG_TP:      return "reached TP";
      case NQ_SIG_SL:      return "hit SL";
   }
   return "";
}

string NqPlanStatusText(int status)
{
   switch(status)
   {
      case NQ_PL_ACTIVE:   return "WAITING FOR FILL";
      case NQ_PL_FILLED:   return "FILLED - RUNNING";
      case NQ_PL_TP1:      return "reached TP1";
      case NQ_PL_SL:       return "hit SL";
      case NQ_PL_EXPIRED:  return "expired unfilled";
      case NQ_PL_INVALID:  return "cancelled - regime turned";
      case NQ_PL_REPLACED: return "replaced by newer";
   }
   return "";
}

string NqPlanKindText(int kind)
{
   return (kind == NQ_PLAN_QML) ? "QML" : "PULLBACK";
}

// evidence-law label for a sample size
string NqEvidenceText(int n)
{
   if(n < 20)
      return "n<20 = luck";
   if(n < 100)
      return "n<100 = early";
   return "n>=100";
}
//=== NB_ENGINE_END ===

//+------------------------------------------------------------------+
//| TERMINAL LAYER - data loading, risk gate, orders, chart, panel.  |
//| Every order it sends is printed to the Experts log with its      |
//| rationale and its result. Nothing is sent intra-bar: decisions   |
//| are taken once per CLOSED M1 candle.                             |
//+------------------------------------------------------------------+
const string NQ_PFX   = "NQEA_";
const string NQ_PFX_P = "NQEA_P_";
const string NQ_PFX_C = "NQEA_C_";
const string NQ_PFX_A = "NQEA_A_";
const string NQ_CMT_SCALP = "NQ-S";
const string NQ_CMT_QML   = "NQ-Q";
const string NQ_CMT_PB    = "NQ-P";
#define NQ_RGB(r, g, b) ((color)((r) | ((g) << 8) | ((b) << 16)))

enum ENUM_NQ_CORNER
{
   NQ_TOP_LEFT = 0,     // Top left
   NQ_BOTTOM_LEFT = 2   // Bottom left
};

input group "Engine (M15 context / M5 regime / M1 trigger are fixed)"
input int            InpNrtrAtrPeriod    = 14;          // NRTR ATR period
input double         InpNrtrMultiplier   = 2.0;         // NRTR ATR multiplier
input int            InpEmaSlow          = 200;         // M15 context EMA
input int            InpEmaFast          = 20;          // Fast EMA (M1 filter + forecast)
input int            InpSwingStrength    = 3;           // Structure lookback: bars each side of a swing
input int            InpHistoryDays      = 8;           // History used (days)
input group "Auto scalp (market order on the M1 trigger)"
input bool           InpScalpAuto        = true;        // Send scalp orders automatically
input double         InpScalpSlAtr       = 1.5;         // Scalp SL = x ATR(M5)  (1.5 validated)
input double         InpScalpTpAtr       = 1.0;         // Scalp TP = x ATR(M5)  (1.0 validated ladder)
input int            InpScalpValidBars   = 2;           // Trigger actionable for (M1 bars)
input int            InpScalpTimeStop    = 45;          // Scalp time stop (M1 bars)
input bool           InpScalpCloseOnFlip = true;        // Close a scalp when the M5 regime turns against it
input group "Pending order plans (QML + pullback limit orders)"
input bool           InpPendingAuto      = true;        // Place / cancel the plan's limit orders automatically
input double         InpQmlSlBufAtr      = 0.2;         // QML SL buffer beyond the head (x ATR5)
input int            InpQmlWaitBars      = 36;          // QML: max M5 bars from head to neck break
input int            InpPlanValidBars    = 72;          // Plan lifetime (M5 bars)  72 = 6 hours
input double         InpPbRetrace        = 0.5;         // Pullback entry: retrace of the impulse leg
input double         InpPbMinImpulseAtr  = 2.0;         // Pullback: impulse at least x ATR5
input double         InpPbSlBufAtr       = 0.2;         // Pullback SL buffer beyond the swing (x ATR5)
input double         InpPlanTp1R         = 1.0;         // Plan TP1 (R)
input double         InpPlanTp2R         = 2.0;         // Plan TP2 (R)
input bool           InpPlanUseTp2       = false;       // Limit order TP = TP2 instead of TP1
input group "Risk engine (explicit - the EA never widens these)"
input double         InpRiskPct          = 0.5;         // Risk per trade (% of balance)
input double         InpDailyLossCapPct  = 2.0;         // Daily loss cap (% of balance) - stops new trades
input int            InpMaxOpenPositions = 2;           // Max open positions (this EA, this symbol)
input int            InpMaxTradesPerDay  = 10;          // Max entries per day
input int            InpMaxSpreadPoints  = 50;          // Max spread (points)
input int            InpSessionStartHour = 0;           // Session start (server hour)
input int            InpSessionEndHour   = 24;          // Session end (server hour)
input bool           InpAllowRealAccount = false;       // Allow trading on a REAL account (default: demo only)
input int            InpMagic            = 180915;      // Magic number
input int            InpSlippagePoints   = 20;          // Max slippage (points)
input group "Forecast arrows"
input int            InpForecastMinScore = 2;           // Score needed for an arrow (1-5)
input int            InpArrowBars        = 300;         // Arrows drawn on the last N candles
input group "Display"
input double         InpPanelScale       = 1.0;         // Panel size (0.7 - 1.6)
input ENUM_NQ_CORNER InpPanelCorner      = NQ_TOP_LEFT; // Panel position
input int            InpPanelX           = 12;          // Panel X offset (px)
input int            InpPanelY           = 24;          // Panel Y offset (px)
input bool           InpDrawChart        = true;        // Draw arrows / structure / levels

// symbol specification (always read from MT5, never hard-coded)
string   g_sym;
int      g_metal;
int      g_digits;
double   g_tick;
double   g_point;
double   g_tickValue;
double   g_volMin;
double   g_volMax;
double   g_volStep;
int      g_stopsLevel;
int      g_fill;
string   g_accCcy;
bool     g_isDemo;

// engine state
NqParams g_P;
datetime g_anchor;
NqSeries g_s15;
NqSeries g_s5;
NqSeries g_s1;
NqPivot  g_piv5[];
NqSignal g_sigs[];
int      g_nSig;
NqPlan   g_plans[];
int      g_nPlans;
datetime g_seen15;
datetime g_seen5;
datetime g_seen1;
bool     g_ready;
int      g_dataR;
bool     g_newBar1;

// account view (this EA's magic, this symbol)
int      g_openCount;
double   g_floating;
int      g_scalpCount;
string   g_posText;
int      g_pendCount;
string   g_pendText;
double   g_dayPnl;
int      g_tradesToday;
double   g_balance;
double   g_freeMargin;
int      g_spreadPts;
string   g_lastTrade;

// view state
bool     g_fresh;
int      g_final;
int      g_finalR;
int      g_gate;
double   g_riskMoney;
double   g_capMoney;
double   g_lotNext;
double   g_lossNext;
datetime g_actedSig;
string   g_note;

// prototypes
void   NqUpdate();
void   NqReadSpec();
bool   NqLoad(ENUM_TIMEFRAMES tf, NqSeries &s, int &why);
void   NqRecompute();
void   NqReadAccount();
void   NqEvaluate();
void   NqTrade();
string NqPx(double v);
color  NqDirColor(int d);
string NqMmSs(long secs);
string NqHhMm(long secs);
void   NqDrawChart();
void   NqDrawPanel();

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpNrtrAtrPeriod < 1 || InpNrtrMultiplier <= 0.0 || InpEmaSlow < 2 || InpEmaFast < 2 ||
      InpSwingStrength < 1 || InpSwingStrength > 20 || InpHistoryDays < 3 || InpScalpSlAtr <= 0.0 ||
      InpScalpTpAtr <= 0.0 || InpScalpValidBars < 1 || InpScalpTimeStop < 1 || InpQmlSlBufAtr < 0.0 ||
      InpQmlWaitBars < 1 || InpPlanValidBars < 1 || InpPbRetrace <= 0.0 || InpPbRetrace >= 1.0 ||
      InpPbMinImpulseAtr < 0.0 || InpPbSlBufAtr < 0.0 || InpPlanTp1R <= 0.0 || InpPlanTp2R <= 0.0 ||
      InpRiskPct <= 0.0 || InpRiskPct > 5.0 || InpDailyLossCapPct < 0.0 || InpMaxOpenPositions < 0 ||
      InpMaxTradesPerDay < 0 || InpMaxSpreadPoints < 0 || InpSessionStartHour < 0 || InpSessionStartHour > 24 ||
      InpSessionEndHour < 0 || InpSessionEndHour > 24 || InpMagic <= 0 || InpForecastMinScore < 1 ||
      InpArrowBars < 0)
   {
      Print("NQ: invalid inputs (risk per trade is capped at 5%)");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_sym = _Symbol;
   g_metal = NqMetalOf(g_sym, SymbolInfoString(g_sym, SYMBOL_CURRENCY_BASE),
                       SymbolInfoString(g_sym, SYMBOL_CURRENCY_PROFIT));
   NqReadSpec();

   g_P.atrPeriod = InpNrtrAtrPeriod;
   g_P.nrtrMult = InpNrtrMultiplier;
   g_P.emaSlow = InpEmaSlow;
   g_P.emaFast = InpEmaFast;
   g_P.swing = InpSwingStrength;
   g_P.scalpSlAtr = InpScalpSlAtr;
   g_P.scalpTpAtr = InpScalpTpAtr;
   g_P.scalpValidBars = InpScalpValidBars;
   g_P.scalpTimeBars = InpScalpTimeStop;
   g_P.qmlSlBufAtr = InpQmlSlBufAtr;
   g_P.qmlWaitBars = InpQmlWaitBars;
   g_P.planValidBars = InpPlanValidBars;
   g_P.pbRetrace = InpPbRetrace;
   g_P.pbMinImpulseAtr = InpPbMinImpulseAtr;
   g_P.pbSlBufAtr = InpPbSlBufAtr;
   g_P.planTp1R = InpPlanTp1R;
   g_P.planTp2R = InpPlanTp2R;
   g_P.fcMinScore = InpForecastMinScore;
   g_P.tick = g_tick;
   g_P.digits = g_digits;

   // Anchor on a calendar day: a restart on the same day reads exactly the
   // same closed bars and therefore shows exactly the same state.
   long nowL = (long)TimeTradeServer();
   g_anchor = (datetime)((nowL / 86400) * 86400 - (long)InpHistoryDays * 86400);

   NqSeriesResize(g_s15, 0);
   NqSeriesResize(g_s5, 0);
   NqSeriesResize(g_s1, 0);
   g_s15.sec = PeriodSeconds(PERIOD_M15);
   g_s5.sec = PeriodSeconds(PERIOD_M5);
   g_s1.sec = PeriodSeconds(PERIOD_M1);
   ArrayResize(g_sigs, 0);
   g_nSig = 0;
   ArrayResize(g_plans, 0);
   g_nPlans = 0;
   g_seen15 = 0;
   g_seen5 = 0;
   g_seen1 = 0;
   g_ready = false;
   g_dataR = NQ_R_NO_DATA;
   g_newBar1 = false;
   g_fresh = false;
   g_final = NQ_WAIT;
   g_finalR = (g_metal == NQ_METAL_NONE) ? NQ_R_UNSUPPORTED : NQ_R_NO_DATA;
   g_gate = 0;
   g_lotNext = 0.0;
   g_lossNext = 0.0;
   g_actedSig = 0;
   g_note = "";
   g_lastTrade = "none today";

   ObjectsDeleteAll(0, NQ_PFX);
   EventSetTimer(1);
   Print("NQ: started on " + g_sym + (g_isDemo ? " (DEMO)" : " (REAL - trading blocked unless allowed)"));
   NqUpdate();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, NQ_PFX);
   ChartRedraw(0);
}

void OnTick()
{
   NqUpdate();
}

void OnTimer()
{
   NqUpdate();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      NqDrawPanel();
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| One refresh: new closed bars -> recompute -> trade once per      |
//| closed M1 candle; always re-read the account and redraw.         |
//+------------------------------------------------------------------+
void NqUpdate()
{
   g_newBar1 = false;
   if(g_metal != NQ_METAL_NONE)
   {
      datetime t15 = iTime(g_sym, PERIOD_M15, 1);
      datetime t5 = iTime(g_sym, PERIOD_M5, 1);
      datetime t1 = iTime(g_sym, PERIOD_M1, 1);
      if(!g_ready || t15 != g_seen15 || t5 != g_seen5 || t1 != g_seen1)
      {
         g_newBar1 = (t1 != g_seen1);
         g_seen15 = t15;
         g_seen5 = t5;
         g_seen1 = t1;
         NqRecompute();
      }
   }
   NqReadAccount();
   NqEvaluate();
   if(g_newBar1 && g_ready)
      NqTrade();
   NqDrawPanel();
   ChartRedraw(0);
}

void NqReadSpec()
{
   g_digits = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   g_tick = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   if(g_tick <= 0.0)
      g_tick = g_point;
   g_tickValue = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE);
   g_volMin = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   g_volMax = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   g_volStep = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   if(g_volStep <= 0.0)
      g_volStep = g_volMin;
   g_stopsLevel = (int)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL);
   long fm = SymbolInfoInteger(g_sym, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK) != 0)
      g_fill = (int)ORDER_FILLING_FOK;
   else if((fm & SYMBOL_FILLING_IOC) != 0)
      g_fill = (int)ORDER_FILLING_IOC;
   else
      g_fill = (int)ORDER_FILLING_RETURN;
   g_accCcy = AccountInfoString(ACCOUNT_CURRENCY);
   g_isDemo = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO);
}

//--- load CLOSED bars from the anchor to the last closed bar. Bar 0 (the
//    forming one) is never read.
bool NqLoad(ENUM_TIMEFRAMES tf, NqSeries &s, int &why)
{
   int sec = PeriodSeconds(tf);
   s.sec = sec;
   int shift = iBarShift(g_sym, tf, g_anchor, false);
   if(shift < 0)
      shift = Bars(g_sym, tf) - 1;
   if(shift < 1)
   {
      NqSeriesResize(s, 0);
      why = NQ_R_NO_DATA;
      return false;
   }
   if(shift > 50000)
      shift = 50000;
   MqlRates r[];
   int got = CopyRates(g_sym, tf, 1, shift, r);
   if(got <= 0)
   {
      NqSeriesResize(s, 0);
      why = NQ_R_NO_DATA;
      return false;
   }
   datetime now = TimeTradeServer();
   int n = got;
   while(n > 0 && r[n - 1].time + sec > now)
      n--;
   NqSeriesResize(s, n);
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
      why = NQ_R_NO_DATA;
      return false;
   }
   return true;
}

void NqRecompute()
{
   NqReadSpec();
   g_P.tick = g_tick;
   g_P.digits = g_digits;
   g_ready = false;
   g_dataR = 0;
   int why = 0;
   bool ok = NqLoad(PERIOD_M15, g_s15, why);
   if(ok)
      ok = NqLoad(PERIOD_M5, g_s5, why);
   if(ok)
      ok = NqLoad(PERIOD_M1, g_s1, why);
   if(!ok)
   {
      g_dataR = (why != 0) ? why : NQ_R_NO_DATA;
      g_nSig = 0;
      ArrayResize(g_sigs, 0);
      g_nPlans = 0;
      ArrayResize(g_plans, 0);
      g_seen15 = 0;   // retry on the next tick / timer
      g_seen5 = 0;
      g_seen1 = 0;
      ObjectsDeleteAll(0, NQ_PFX_C);
      ObjectsDeleteAll(0, NQ_PFX_A);
      return;
   }
   NqRunContext(g_s15, g_P);
   NqRunRegime(g_s5, g_piv5, g_s15, g_P);
   NqRunTrigger(g_s1, g_s5, true, g_P, g_sigs, g_nSig);
   NqFindPlans(g_s5, g_piv5, g_s5.np, g_P, g_plans, g_nPlans);
   g_ready = true;
   NqDrawChart();
}

//+------------------------------------------------------------------+
//| account view: this EA's positions, orders, today's closed P/L    |
//+------------------------------------------------------------------+
string NqPlanComment(const NqPlan &p)
{
   return ((p.kind == NQ_PLAN_QML) ? NQ_CMT_QML : NQ_CMT_PB) + IntegerToString((long)p.keyTime);
}

bool NqIsOurs(long magic, string sym)
{
   return (magic == InpMagic && sym == g_sym);
}

void NqReadAccount()
{
   g_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   g_spreadPts = (int)SymbolInfoInteger(g_sym, SYMBOL_SPREAD);
   g_riskMoney = NqRiskMoney(g_balance, InpRiskPct);
   g_capMoney = NqRiskMoney(g_balance, InpDailyLossCapPct);

   g_openCount = 0;
   g_floating = 0.0;
   g_scalpCount = 0;
   g_posText = "";
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(!NqIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
         continue;
      g_openCount++;
      double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      g_floating += pr;
      string cmt = PositionGetString(POSITION_COMMENT);
      string kind = "plan";
      if(StringFind(cmt, NQ_CMT_SCALP) == 0)
      {
         kind = "scalp";
         g_scalpCount++;
      }
      else if(StringFind(cmt, NQ_CMT_QML) == 0)
         kind = "QML";
      else if(StringFind(cmt, NQ_CMT_PB) == 0)
         kind = "pullback";
      string side = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      string one = side + " " + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + " @ " +
                   DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), g_digits) + " (" + kind + ") " +
                   ((pr >= 0.0) ? "+" : "") + DoubleToString(pr, 2);
      g_posText = (g_posText == "") ? one : (g_posText + "  |  " + one);
   }
   if(g_posText == "")
      g_posText = "NONE";

   g_pendCount = 0;
   g_pendText = "";
   int ot = OrdersTotal();
   for(int i = 0; i < ot; i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0)
         continue;
      if(!NqIsOurs(OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
         continue;
      g_pendCount++;
      string cmt = OrderGetString(ORDER_COMMENT);
      string kind = (StringFind(cmt, NQ_CMT_QML) == 0) ? "QML" : ((StringFind(cmt, NQ_CMT_PB) == 0) ? "pullback" : "?");
      string side = (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT) ? "buy limit" : "sell limit";
      string one = kind + " " + side + " " + DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), g_digits);
      g_pendText = (g_pendText == "") ? one : (g_pendText + "  |  " + one);
   }
   if(g_pendText == "")
      g_pendText = "NONE";

   // today's closed result and entries, from the deal history (magic + symbol).
   // The "last action" line is derived from the same history, so a restart
   // shows exactly what the terminal knows, not what this instance remembers.
   g_dayPnl = 0.0;
   g_tradesToday = 0;
   g_lastTrade = "none today";
   datetime lastIn = 0;
   datetime now = TimeTradeServer();
   datetime dayStart = (datetime)(((long)now / 86400) * 86400);
   if(HistorySelect(dayStart, now + 60))
   {
      int nd = HistoryDealsTotal();
      for(int i = 0; i < nd; i++)
      {
         ulong dk = HistoryDealGetTicket(i);
         if(dk == 0)
            continue;
         if(!NqIsOurs(HistoryDealGetInteger(dk, DEAL_MAGIC), HistoryDealGetString(dk, DEAL_SYMBOL)))
            continue;
         long entry = HistoryDealGetInteger(dk, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
         {
            g_tradesToday++;
            datetime dt = (datetime)HistoryDealGetInteger(dk, DEAL_TIME);
            if(dt >= lastIn)
            {
               lastIn = dt;
               string side = (HistoryDealGetInteger(dk, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY " : "SELL ";
               g_lastTrade = side + DoubleToString(HistoryDealGetDouble(dk, DEAL_VOLUME), 2) + " @ " +
                             DoubleToString(HistoryDealGetDouble(dk, DEAL_PRICE), g_digits) + "  " + TimeToString(dt, TIME_MINUTES);
            }
         }
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
            g_dayPnl += HistoryDealGetDouble(dk, DEAL_PROFIT) + HistoryDealGetDouble(dk, DEAL_COMMISSION) +
                        HistoryDealGetDouble(dk, DEAL_SWAP);
      }
   }
}

//+------------------------------------------------------------------+
//| decide what the panel shows and whether the gate is open         |
//+------------------------------------------------------------------+
void NqEvaluate()
{
   g_lotNext = 0.0;
   g_lossNext = 0.0;
   if(g_metal == NQ_METAL_NONE)
   {
      g_fresh = false;
      g_final = NQ_WAIT;
      g_finalR = NQ_R_UNSUPPORTED;
      g_gate = NQ_K_AUTO_OFF;
      return;
   }
   datetime now = TimeTradeServer();
   int hour = (int)(((long)now % 86400) / 3600);
   bool tradeAllowed = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 && MQLInfoInteger(MQL_TRADE_ALLOWED) != 0 &&
                        AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0 && AccountInfoInteger(ACCOUNT_TRADE_EXPERT) != 0);
   double dayTotal = g_dayPnl + g_floating;
   g_gate = NqRiskGate(InpScalpAuto || InpPendingAuto, g_isDemo, InpAllowRealAccount, tradeAllowed,
                       g_spreadPts, InpMaxSpreadPoints, dayTotal, g_capMoney, g_openCount, InpMaxOpenPositions,
                       g_tradesToday, InpMaxTradesPerDay, NqInSession(hour, InpSessionStartHour, InpSessionEndHour));

   if(!g_ready || g_s1.n < 1 || g_s5.n < 1 || g_s15.n < 1)
   {
      g_fresh = false;
      g_final = NQ_WAIT;
      g_finalR = (g_dataR != 0) ? g_dataR : NQ_R_NO_DATA;
      return;
   }
   int n1 = g_s1.n;
   g_fresh = NqIsFresh(g_s1.t[n1 - 1], g_s1.sec, g_s5.t[g_s5.n - 1], g_s5.sec, g_s15.t[g_s15.n - 1], g_s15.sec, now);
   if(!g_fresh)
   {
      g_final = NQ_WAIT;
      g_finalR = NQ_R_STALE;
      return;
   }
   int st = g_s1.state[n1 - 1];
   g_finalR = g_s1.reasons[n1 - 1];
   g_final = (st == NQ_BUY || st == NQ_SELL) ? st : NQ_WAIT;
   if(g_final == NQ_WAIT && g_finalR == 0)
      g_finalR = NQ_R_NO_DATA;

   // the lot the next scalp would get (for the panel), from the latest ATR5
   int k5 = g_s1.map[n1 - 1];
   double atr5 = (k5 >= 0) ? g_s5.atr[k5] : 0.0;
   if(atr5 > 0.0)
   {
      double slDist = NormalizeDouble(InpScalpSlAtr * atr5, g_digits);
      g_lotNext = NqLotFor(g_riskMoney, slDist, g_tick, g_tickValue, g_volMin, g_volMax, g_volStep);
      g_lossNext = NqLossAt(g_lotNext, slDist, g_tick, g_tickValue);
   }
}

//+------------------------------------------------------------------+
//| ORDERS. One function sends everything, prints the rationale and  |
//| the terminal's answer. Retcodes 10008 (placed) / 10009 (done).   |
//+------------------------------------------------------------------+
bool NqSend(MqlTradeRequest &req, string why)
{
   MqlTradeResult res;
   ZeroMemory(res);
   bool ok = OrderSend(req, res);
   bool done = ok && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED);
   string what = "";
   if(req.action == TRADE_ACTION_DEAL)
   {
      string side = (req.type == ORDER_TYPE_BUY) ? "BUY " : "SELL ";
      what = "MARKET " + side + DoubleToString(req.volume, 2);
   }
   else if(req.action == TRADE_ACTION_PENDING)
   {
      string side = (req.type == ORDER_TYPE_BUY_LIMIT) ? "BUY LIMIT " : "SELL LIMIT ";
      what = side + DoubleToString(req.volume, 2) + " @ " + DoubleToString(req.price, g_digits);
   }
   else if(req.action == TRADE_ACTION_REMOVE)
      what = "CANCEL #" + IntegerToString((long)req.order);
   string line = "NQ " + what + " SL " + DoubleToString(req.sl, g_digits) + " TP " + DoubleToString(req.tp, g_digits) +
                 " | " + why + " | " + (done ? "OK" : "REJECTED") + " retcode " + IntegerToString((long)res.retcode) +
                 ((res.deal != 0) ? (" deal " + IntegerToString((long)res.deal)) : "") +
                 ((res.order != 0) ? (" order " + IntegerToString((long)res.order)) : "");
   Print(line);
   g_note = (done ? "SENT: " : "REJECTED: ") + what;
   return done;
}

bool NqMarket(int dir, double lot, double sl, double tp, string comment, string why)
{
   MqlTradeRequest req;
   ZeroMemory(req);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = g_sym;
   req.magic = InpMagic;
   req.volume = lot;
   req.type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price = (dir > 0) ? SymbolInfoDouble(g_sym, SYMBOL_ASK) : SymbolInfoDouble(g_sym, SYMBOL_BID);
   req.sl = sl;
   req.tp = tp;
   req.deviation = InpSlippagePoints;
   req.type_filling = (ENUM_ORDER_TYPE_FILLING)g_fill;
   req.comment = comment;
   return NqSend(req, why);
}

bool NqPending(int dir, double price, double lot, double sl, double tp, string comment, string why)
{
   MqlTradeRequest req;
   ZeroMemory(req);
   req.action = TRADE_ACTION_PENDING;
   req.symbol = g_sym;
   req.magic = InpMagic;
   req.volume = lot;
   req.type = (dir > 0) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   req.price = price;
   req.sl = sl;
   req.tp = tp;
   req.type_filling = (ENUM_ORDER_TYPE_FILLING)g_fill;
   req.type_time = ORDER_TIME_GTC;   // the EA cancels on expiry itself (broker-agnostic)
   req.comment = comment;
   return NqSend(req, why);
}

bool NqCancel(ulong ticket, string why)
{
   MqlTradeRequest req;
   ZeroMemory(req);
   req.action = TRADE_ACTION_REMOVE;
   req.order = ticket;
   return NqSend(req, why);
}

bool NqClosePosition(ulong ticket, string why)
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
   req.comment = "NQ close";
   return NqSend(req, why);
}

// per-order checks that need the live price: stops level, lot, margin
int NqOrderGate(int dir, double entry, double sl, double tp, double &lot, int orderType)
{
   int g = 0;
   double minDist = g_stopsLevel * g_point;
   if(minDist > 0.0 && (MathAbs(entry - sl) < minDist || MathAbs(tp - entry) < minDist))
      g |= NQ_K_STOPS_LEVEL;
   double slDist = MathAbs(entry - sl);
   lot = NqLotFor(g_riskMoney, slDist, g_tick, g_tickValue, g_volMin, g_volMax, g_volStep);
   if(lot <= 0.0)
      g |= NQ_K_LOT_TOO_SMALL;
   else
   {
      double margin = 0.0;
      if(OrderCalcMargin((ENUM_ORDER_TYPE)orderType, g_sym, lot, entry, margin))
      {
         if(margin > g_freeMargin)
            g |= NQ_K_MARGIN;
      }
   }
   return g;
}

// the pending order (if any) that belongs to a plan
ulong NqFindPlanOrder(const NqPlan &p)
{
   string cmt = NqPlanComment(p);
   long want = (p.dir > 0) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   int ot = OrdersTotal();
   for(int i = 0; i < ot; i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0)
         continue;
      if(!NqIsOurs(OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
         continue;
      if(OrderGetInteger(ORDER_TYPE) != want)
         continue;
      if(OrderGetString(ORDER_COMMENT) == cmt)
         return tk;
      // a broker that rewrites comments: same type at the same price is the same plan
      if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - p.entry) < g_tick * 0.5)
         return tk;
   }
   return 0;
}

// a plan whose order already filled has a position carrying its comment
bool NqPlanHasPosition(const NqPlan &p)
{
   string cmt = NqPlanComment(p);
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(!NqIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
         continue;
      if(PositionGetString(POSITION_COMMENT) == cmt)
         return true;
   }
   return false;
}

int NqPlanIndexOfComment(string cmt)
{
   for(int k = g_nPlans - 1; k >= 0; k--)
      if(NqPlanComment(g_plans[k]) == cmt)
         return k;
   return -1;
}

//+------------------------------------------------------------------+
//| TRADE: called once per CLOSED M1 candle.                         |
//+------------------------------------------------------------------+
void NqTrade()
{
   if(g_metal == NQ_METAL_NONE || !g_ready)
      return;
   int n1 = g_s1.n;
   int n5 = g_s5.n;
   int reg5 = g_s5.regime[n5 - 1];
   datetime now = TimeTradeServer();

   // 1) manage open scalps: time stop, regime flip. Works even when the
   //    gate is closed - closing is never blocked, only opening is.
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(!NqIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
         continue;
      string cmt = PositionGetString(POSITION_COMMENT);
      if(StringFind(cmt, NQ_CMT_SCALP) != 0)
         continue;
      int pdir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      long ageBars = ((long)now - (long)opened) / g_s1.sec;
      if(ageBars >= InpScalpTimeStop)
         NqClosePosition(tk, "scalp time stop: " + IntegerToString(ageBars) + " M1 bars without TP/SL");
      else if(InpScalpCloseOnFlip && g_fresh && reg5 != NQ_REG_CHOP && reg5 != pdir)
         NqClosePosition(tk, "M5 regime turned " + NqRegimeText(reg5) + " against the scalp");
   }

   // 2) pending plans <-> pending orders
   if(g_fresh)
   {
      // cancel orders whose plan is gone or no longer active
      int ot = OrdersTotal();
      for(int i = ot - 1; i >= 0; i--)
      {
         ulong tk = OrderGetTicket(i);
         if(tk == 0)
            continue;
         if(!NqIsOurs(OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
            continue;
         string cmt = OrderGetString(ORDER_COMMENT);
         if(StringFind(cmt, NQ_CMT_QML) != 0 && StringFind(cmt, NQ_CMT_PB) != 0)
            continue;   // not one of our plan orders
         int k = NqPlanIndexOfComment(cmt);
         if(k < 0 || g_plans[k].status != NQ_PL_ACTIVE)
         {
            string why = (k < 0) ? "plan no longer exists (history window moved)" : ("plan " + NqPlanStatusText(g_plans[k].status));
            NqCancel(tk, why);
         }
      }
      // place orders for active plans
      if(InpPendingAuto)
      {
         int kinds[2];
         kinds[0] = NQ_PLAN_QML;
         kinds[1] = NQ_PLAN_PB;
         for(int q = 0; q < 2; q++)
         {
            int k = NqLatestPlan(g_plans, g_nPlans, kinds[q]);
            if(k < 0 || g_plans[k].status != NQ_PL_ACTIVE)
               continue;
            if(NqFindPlanOrder(g_plans[k]) != 0)
               continue;
            // filled on an M1 bar but not yet seen by the M5 engine: never place it twice
            if(NqPlanHasPosition(g_plans[k]))
               continue;
            if(g_gate != 0)
               continue;
            double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
            double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
            double minDist = g_stopsLevel * g_point;
            bool sideOk = (g_plans[k].dir > 0) ? (g_plans[k].entry < ask - minDist) : (g_plans[k].entry > bid + minDist);
            if(!sideOk)
            {
               g_note = NqPlanKindText(g_plans[k].kind) + ": PRICE ALREADY AT THE LEVEL - LIMIT NOT PLACED";
               continue;
            }
            double tp = InpPlanUseTp2 ? g_plans[k].tp2 : g_plans[k].tp1;
            double lot = 0.0;
            int og = NqOrderGate(g_plans[k].dir, g_plans[k].entry, g_plans[k].sl, tp, lot,
                                 (g_plans[k].dir > 0) ? (int)ORDER_TYPE_BUY_LIMIT : (int)ORDER_TYPE_SELL_LIMIT);
            if(og != 0)
            {
               g_note = NqPlanKindText(g_plans[k].kind) + ": " + NqGateAt(og, 0);
               continue;
            }
            string why = NqPlanKindText(g_plans[k].kind) + " plan from M5 close " +
                         TimeToString(g_s5.t[g_plans[k].idx] + g_s5.sec, TIME_DATE | TIME_MINUTES) +
                         " risk " + DoubleToString(InpRiskPct, 2) + "% = " + DoubleToString(g_riskMoney, 2) + " " + g_accCcy;
            NqPending(g_plans[k].dir, g_plans[k].entry, lot, g_plans[k].sl, tp, NqPlanComment(g_plans[k]), why);
         }
      }
   }

   // 3) scalp entry on a fresh trigger (the just-closed M1 candle)
   if(!g_fresh || !InpScalpAuto)
      return;
   int st = g_s1.state[n1 - 1];
   if(st != NQ_BUY && st != NQ_SELL)
      return;
   int cur = g_s1.sigOf[n1 - 1];
   if(cur < 0 || g_sigs[cur].idx != n1 - 1)
      return;   // only the candle that just closed, never an older trigger
   datetime sigTime = g_s1.t[g_sigs[cur].idx];
   if(sigTime == g_actedSig)
      return;
   string sideT = (st > 0) ? "BUY" : "SELL";
   if(g_scalpCount > 0)
   {
      g_note = "SCALP TRIGGER " + sideT + " - a scalp is already open";
      return;
   }
   if(g_gate != 0)
   {
      g_note = "SCALP TRIGGER " + sideT + " - " + NqGateAt(g_gate, 0);
      return;
   }
   double entry = (st > 0) ? SymbolInfoDouble(g_sym, SYMBOL_ASK) : SymbolInfoDouble(g_sym, SYMBOL_BID);
   if(entry <= 0.0)
      entry = g_sigs[cur].entry;
   // SL/TP from the trigger candle's close, as the record is judged
   double sl = g_sigs[cur].sl;
   double tp = g_sigs[cur].tp;
   double lot = 0.0;
   int og = NqOrderGate(st, entry, sl, tp, lot, (st > 0) ? (int)ORDER_TYPE_BUY : (int)ORDER_TYPE_SELL);
   if(og != 0)
   {
      g_note = "SCALP TRIGGER " + sideT + " - " + NqGateAt(og, 0);
      g_actedSig = sigTime;
      return;
   }
   int k5 = g_s1.map[n1 - 1];
   string why = "M5 " + NqRegimeText(g_s5.regime[k5]) + ", M1 NRTR realigned + candle closed " +
                TimeToString(sigTime + g_s1.sec, TIME_MINUTES) + ", ATR5 " + DoubleToString(g_s5.atr[k5], g_digits) +
                ", risk " + DoubleToString(InpRiskPct, 2) + "% = " + DoubleToString(g_riskMoney, 2) + " " + g_accCcy +
                " -> lot " + DoubleToString(lot, 2);
   g_actedSig = sigTime;
   NqMarket(st, lot, sl, tp, NQ_CMT_SCALP + IntegerToString((long)sigTime), why);
}

//+------------------------------------------------------------------+
//| CHART: forecast arrow on every candle of the chart TF (M1/M5/M15)|
//| + live arrow on the forming candle, M5 structure labels, scalp   |
//| markers, and the levels of the active plans / scalp.             |
//+------------------------------------------------------------------+
void NqText(string name, datetime t, double price, string txt, color clr, int size, int anchor, string tip)
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

void NqArrow(string name, datetime t, double price, int dir, color clr, string tip)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, (dir > 0) ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, (dir > 0) ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}

void NqLevel(string name, datetime t, double price, color clr, int style, string txt)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t, price, t + 300, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t + 300);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   NqText(name + "_T", t, price, txt + " " + DoubleToString(price, g_digits), clr, 8, ANCHOR_LEFT_LOWER, txt);
}

// which engine series matches the chart timeframe (0 none, 1/5/15)
int NqChartSeries()
{
   int sec = PeriodSeconds(_Period);
   if(sec == 60)
      return 1;
   if(sec == 300)
      return 5;
   if(sec == 900)
      return 15;
   return 0;
}

void NqDrawArrowsFor(const NqSeries &s, string tfName)
{
   int n = s.n;
   if(n < 2)
      return;
   color cHit = NQ_RGB(46, 204, 113);
   color cMiss = NQ_RGB(231, 76, 60);
   color cOpen = NQ_RGB(241, 196, 15);
   int from = (InpArrowBars > 0) ? (int)MathMax(1, n - InpArrowBars) : 1;
   for(int i = from; i < n; i++)
   {
      int f = s.fc[i - 1];
      if(f == 0)
         continue;
      int hit = s.fcHit[i - 1];
      color clr = (hit > 0) ? cHit : ((hit < 0) ? cMiss : cOpen);
      double off = (s.atr[i] > 0.0) ? s.atr[i] * 0.25 : 0.0;
      double price = (f > 0) ? s.l[i] - off : s.h[i] + off;
      string tip = tfName + " forecast made " + TimeToString(s.t[i - 1] + s.sec, TIME_MINUTES) + ": " +
                   ((f > 0) ? "UP" : "DOWN") + " (score " + IntegerToString(s.fcScore[i - 1]) + ") - " +
                   ((hit > 0) ? "HIT" : ((hit < 0) ? "MISS" : "open"));
      NqArrow(NQ_PFX_A + IntegerToString((long)s.t[i]), s.t[i], price, f, clr, tip);
   }
   // the live arrow: forecast for the candle that is forming right now
   int fl = s.fc[n - 1];
   if(fl != 0)
   {
      datetime tl = s.t[n - 1] + s.sec;
      double off = (s.atr[n - 1] > 0.0) ? s.atr[n - 1] * 0.25 : 0.0;
      double price = (fl > 0) ? s.l[n - 1] - off : s.h[n - 1] + off;
      NqArrow(NQ_PFX_A + "LIVE", tl, price, fl, clrWhite,
              "LIVE " + tfName + " forecast for the forming candle: " + ((fl > 0) ? "UP" : "DOWN") +
              " (score " + IntegerToString(s.fcScore[n - 1]) + ")");
   }
}

void NqDrawChart()
{
   ObjectsDeleteAll(0, NQ_PFX_C);
   ObjectsDeleteAll(0, NQ_PFX_A);
   if(!InpDrawChart || !g_ready)
      return;
   int n5 = g_s5.n;
   int n1 = g_s1.n;
   if(n5 < 1 || n1 < 1)
      return;
   color cUp = NQ_RGB(46, 204, 113);
   color cDn = NQ_RGB(231, 76, 60);
   color cEq = NQ_RGB(150, 150, 150);
   color cQml = NQ_RGB(255, 140, 0);
   color cPb = NQ_RGB(100, 180, 255);

   int cs = NqChartSeries();
   if(cs == 1)
      NqDrawArrowsFor(g_s1, "M1");
   else if(cs == 5)
      NqDrawArrowsFor(g_s5, "M5");
   else if(cs == 15)
      NqDrawArrowsFor(g_s15, "M15");

   // confirmed M5 structure (drawn at the swing, appears `swing` bars later, never moves)
   int chartSec = PeriodSeconds(_Period);
   if(chartSec <= 900)
   {
      int firstP = (int)MathMax(0, g_s5.np - 40);
      for(int p = firstP; p < g_s5.np; p++)
      {
         if(g_piv5[p].label == NQ_L_NONE)
            continue;
         int lbl = g_piv5[p].label;
         color clr = cEq;
         if(lbl == NQ_L_HH || lbl == NQ_L_HL)
            clr = cUp;
         if(lbl == NQ_L_LH || lbl == NQ_L_LL)
            clr = cDn;
         string nm = NQ_PFX_C + "S_" + IntegerToString(g_piv5[p].idx) + (g_piv5[p].kind > 0 ? "H" : "L");
         NqText(nm, g_s5.t[g_piv5[p].idx], g_piv5[p].price, NqLabelName(lbl), clr, 8,
                g_piv5[p].kind > 0 ? ANCHOR_LOWER : ANCHOR_UPPER,
                "Confirmed M5 swing " + NqLabelName(lbl) + " (known at close of " +
                TimeToString(g_s5.t[g_piv5[p].confirmIdx] + g_s5.sec, TIME_DATE | TIME_MINUTES) + ")");
      }
   }

   // scalp markers (last 40 signals)
   int firstS = (int)MathMax(0, g_nSig - 40);
   for(int k = firstS; k < g_nSig; k++)
   {
      int s = g_sigs[k].idx;
      string nm = NQ_PFX_C + "G_" + IntegerToString(s);
      string side = (g_sigs[k].dir > 0) ? "BUY" : "SELL";
      string tip = "SCALP " + side + " entry " + DoubleToString(g_sigs[k].entry, g_digits) + " SL " +
                   DoubleToString(g_sigs[k].sl, g_digits) + " TP " + DoubleToString(g_sigs[k].tp, g_digits) +
                   " - " + NqSignalStatusText(g_sigs[k].status);
      double off = g_s1.atrHi[s] * 0.6;
      if(g_sigs[k].dir > 0)
         NqText(nm, g_s1.t[s], g_s1.l[s] - off, NqSymUp() + " S", cUp, 9, ANCHOR_UPPER, tip);
      else
         NqText(nm, g_s1.t[s], g_s1.h[s] + off, NqSymDown() + " S", cDn, 9, ANCHOR_LOWER, tip);
   }

   // levels of the active scalp trigger
   int cur = g_s1.sigOf[n1 - 1];
   if(cur >= 0 && g_s1.state[n1 - 1] != NQ_WAIT && g_sigs[cur].status == NQ_SIG_ACTIVE)
   {
      datetime ts = g_s1.t[g_sigs[cur].idx];
      NqLevel(NQ_PFX_C + "L_SE", ts, g_sigs[cur].entry, clrWhite, STYLE_SOLID, "SCALP ENTRY");
      NqLevel(NQ_PFX_C + "L_SS", ts, g_sigs[cur].sl, cDn, STYLE_DASH, "SCALP SL");
      NqLevel(NQ_PFX_C + "L_ST", ts, g_sigs[cur].tp, cUp, STYLE_DASH, "SCALP TP");
   }

   // levels of the latest active QML and pullback plans
   int kinds[2];
   kinds[0] = NQ_PLAN_QML;
   kinds[1] = NQ_PLAN_PB;
   for(int q = 0; q < 2; q++)
   {
      int k = NqLatestPlan(g_plans, g_nPlans, kinds[q]);
      if(k < 0)
         continue;
      string id = (kinds[q] == NQ_PLAN_QML) ? "Q" : "P";
      string nmk = NqPlanKindText(kinds[q]) + " " + ((g_plans[k].dir > 0) ? "BUY LIMIT" : "SELL LIMIT");
      color clr = (kinds[q] == NQ_PLAN_QML) ? cQml : cPb;
      datetime ts = g_s5.t[g_plans[k].idx];
      NqLevel(NQ_PFX_C + "L_" + id + "E", ts, g_plans[k].entry, clr, STYLE_SOLID, nmk);
      NqLevel(NQ_PFX_C + "L_" + id + "S", ts, g_plans[k].sl, cDn, STYLE_DASH, nmk + " SL");
      NqLevel(NQ_PFX_C + "L_" + id + "1", ts, g_plans[k].tp1, cUp, STYLE_DASH, nmk + " TP1");
      NqLevel(NQ_PFX_C + "L_" + id + "2", ts, g_plans[k].tp2, cUp, STYLE_DOT, nmk + " TP2");
   }
}

//+------------------------------------------------------------------+
//| PANEL: banner + two compact tables, one column. TOP = engine     |
//| (M15 context, M5 regime + structure, M1 trigger, forecast).      |
//| BOTTOM = pending order plan + auto scalp + risk. No row twice.   |
//+------------------------------------------------------------------+
void NqRect(string id, int x, int y, int w, int h, color bg, color border)
{
   string name = NQ_PFX_P + id;
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

void NqLabel(string id, int x, int y, string txt, color clr, int size, string font, int anchor)
{
   string name = NQ_PFX_P + id;
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

void NqRow(string id, int kx, int vx, int y, string key, string val, color vc, color kc, int fs)
{
   NqLabel("k_" + id, kx, y, key, kc, fs, "Arial", ANCHOR_LEFT_UPPER);
   NqLabel("v_" + id, vx, y, val, vc, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
}

string NqPx(double v)
{
   if(v <= 0.0)
      return "---";
   return DoubleToString(v, g_digits);
}

color NqDirColor(int d)
{
   if(d > 0)
      return NQ_RGB(46, 204, 113);
   if(d < 0)
      return NQ_RGB(231, 76, 60);
   return NQ_RGB(241, 196, 15);
}

string NqMmSs(long secs)
{
   if(secs < 0)
      secs = 0;
   return IntegerToString(secs / 60, 2, '0') + ":" + IntegerToString(secs % 60, 2, '0');
}

string NqHhMm(long secs)
{
   if(secs < 0)
      secs = 0;
   return IntegerToString(secs / 3600) + "h" + IntegerToString((secs % 3600) / 60, 2, '0') + "m";
}

string NqMoney(double v)
{
   return ((v >= 0.0) ? "+" : "") + DoubleToString(v, 2) + " " + g_accCcy;
}

void NqDrawPanel()
{
   double sc = MathMax(0.7, MathMin(1.6, InpPanelScale));
   int W = (int)MathRound(430 * sc);
   int rh = (int)MathRound(17 * sc);
   int pad = (int)MathRound(10 * sc);
   int fs = (int)MathRound(9 * sc);
   int fsH = (int)MathRound(8 * sc);
   int fsT = (int)MathRound(13 * sc);
   int fsB = (int)MathRound(16 * sc);
   int kOff = (int)MathRound(8 * sc);
   int vOff = (int)MathRound(122 * sc);
   int bannerH = (int)MathRound(38 * sc);
   int rowsTop = 7;
   int rowsBot = 9;
   int tTopH = rh + 3 + rowsTop * rh + 4;
   int tBotH = rh + 3 + rowsBot * rh + 4;
   int H = pad * 2 + (int)MathRound(rh * 1.4) + rh + 4 + bannerH + 4 + 2 * rh + tTopH + 6 + tBotH + 4 + rh;

   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int ox = InpPanelX;
   int oy = InpPanelY;
   if(InpPanelCorner == NQ_BOTTOM_LEFT)
      oy = (int)MathMax(0, ch - H - InpPanelY);

   color cBg = NQ_RGB(16, 20, 28);
   color cTbl = NQ_RGB(22, 27, 37);
   color cMetal = (g_metal == NQ_METAL_SILVER) ? NQ_RGB(200, 206, 214) : NQ_RGB(212, 175, 55);
   color cKey = NQ_RGB(140, 150, 165);
   color cVal = NQ_RGB(235, 238, 242);
   color cUp = NQ_RGB(46, 204, 113);
   color cDn = NQ_RGB(231, 76, 60);
   color cWait = NQ_RGB(241, 196, 15);
   color cBlock = NQ_RGB(230, 126, 34);
   color cDim = NQ_RGB(95, 105, 120);

   NqRect("bg", ox, oy, W, H, cBg, cMetal);

   bool ok = (g_metal != NQ_METAL_NONE && g_ready && g_s15.n > 0 && g_s5.n > 0 && g_s1.n > 0);
   int i15 = ok ? g_s15.n - 1 : 0;
   int i5 = ok ? g_s5.n - 1 : 0;
   int i1 = ok ? g_s1.n - 1 : 0;
   datetime nowS = TimeTradeServer();

   // title + price line (+ M1 candle countdown)
   int y = oy + pad;
   string title = "NRTR QML METAL SCALPER";
   if(g_metal == NQ_METAL_GOLD)
      title = "GOLD  -  NRTR QML SCALPER";
   if(g_metal == NQ_METAL_SILVER)
      title = "SILVER  -  NRTR QML SCALPER";
   NqLabel("title", ox + pad, y, title, cMetal, fsT, "Arial Black", ANCHOR_LEFT_UPPER);
   y += (int)MathRound(rh * 1.4);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   string candle = "";
   if(ok)
      candle = "   M1 closes in " + NqMmSs((long)(g_s1.t[i1] + 2 * g_s1.sec - nowS));
   NqLabel("sym", ox + pad, y, g_sym + "   " + NqPx(bid) + " / " + NqPx(ask) + "   " + (g_isDemo ? "DEMO" : "REAL") + candle,
           cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   y += rh + 4;

   // banner
   string st = NqSymDot() + "  WAIT - NO TRADE";
   color bc = cWait;
   if(g_metal == NQ_METAL_NONE)
      st = NqSymDot() + "  GOLD / SILVER ONLY";
   else if((g_gate & NQ_K_REAL_ACCOUNT) != 0)
   {
      st = "!  REAL ACCOUNT - TRADING BLOCKED";
      bc = cBlock;
   }
   else if(!g_fresh && ok)
      st = NqSymDot() + "  DATA STALE / MARKET CLOSED";
   else if(g_final == NQ_BUY || g_final == NQ_SELL)
   {
      string side = (g_final > 0) ? "BUY" : "SELL";
      string sym = (g_final > 0) ? NqSymUp() : NqSymDown();
      if(g_gate != 0)
      {
         st = sym + "  " + side + " TRIGGER - BLOCKED";
         bc = cBlock;
      }
      else
      {
         st = sym + "  SCALP " + side + (InpScalpAuto ? "  (AUTO)" : "  (MANUAL)");
         bc = (g_final > 0) ? cUp : cDn;
      }
   }
   NqRect("banner", ox + pad, y, W - 2 * pad, bannerH, bc, bc);
   NqLabel("state", ox + W / 2, y + bannerH / 2, st, NQ_RGB(10, 12, 16), fsB, "Arial Black", ANCHOR_CENTER);
   y += bannerH + 4;

   // reasons
   string r1 = "";
   string r2 = "";
   if(g_metal == NQ_METAL_NONE)
      r1 = NqReasonName(NQ_R_UNSUPPORTED);
   else if(!ok)
      r1 = NqReasonAt(g_finalR, 0);
   else if(!g_fresh)
      r1 = NqReasonName(NQ_R_STALE);
   else if(g_final != NQ_WAIT)
   {
      r1 = "M5 " + NqRegimeText(g_s5.regime[i5]) + " + M1 NRTR REALIGNED + CANDLE CLOSED IN DIRECTION";
      r2 = (g_gate != 0) ? NqGateAt(g_gate, 0) : ("SL " + DoubleToString(InpScalpSlAtr, 1) + " x ATR5, TP " +
                                                     DoubleToString(InpScalpTpAtr, 1) + " x ATR5, time stop " +
                                                     IntegerToString(InpScalpTimeStop) + " M1 bars");
   }
   else
   {
      r1 = NqReasonAt(g_finalR, 0);
      r2 = NqReasonAt(g_finalR, 1);
   }
   if(g_note != "" && r2 == "")
      r2 = g_note;
   NqLabel("r1", ox + pad, y, "REASON: " + r1, cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   y += rh;
   NqLabel("r2", ox + pad, y, (r2 == "") ? " " : ("            " + r2), cVal, fs, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;

   // ---------------- TOP TABLE: engine ----------------
   int tx = ox + pad;
   int TW = W - 2 * pad;
   int kx = tx + kOff;
   int vx = tx + vOff;
   NqRect("t1", tx, y, TW, tTopH, cTbl, cDim);
   NqLabel("h1", kx, y + 3, "ENGINE   M15 " + NqSymArrow() + " M5 " + NqSymArrow() + " M1", cMetal, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   int yr = y + rh + 3;

   int ctx = ok ? g_s15.ctx[i15] : 0;
   string ctxT = "---";
   if(ok)
   {
      string emaSide = "EMA not ready";
      if(g_s15.emaS[i15] > 0.0)
      {
         string rel = (g_s15.c[i15] > g_s15.emaS[i15]) ? "above" : ((g_s15.c[i15] < g_s15.emaS[i15]) ? "below" : "on");
         emaSide = rel + " EMA" + IntegerToString(InpEmaSlow) + " " + NqPx(g_s15.emaS[i15]);
      }
      ctxT = NqContextText(ctx) + "  (NRTR " + NqDirText(g_s15.dir[i15]) + ", " + emaSide + ")";
   }
   NqRow("e1", kx, vx, yr, "M15 CONTEXT", ctxT, ok ? NqDirColor(ctx) : cDim, cKey, fs);
   yr += rh;
   int reg = ok ? g_s5.regime[i5] : 0;
   string regT = ok ? NqRegimeText(reg) : "---";
   if(ok && reg == NQ_REG_CHOP)
      regT = regT + "  (" + NqReasonAt(g_s5.regR[i5], 0) + ")";
   else if(ok)
      regT = regT + "  (NRTR stop " + NqPx(g_s5.stop[i5]) + ")";
   NqRow("e2", kx, vx, yr, "M5 REGIME", regT, ok ? NqDirColor(reg) : cDim, cKey, fs);
   yr += rh;
   int stv = ok ? g_s5.st[i5] : NQ_ST_UNKNOWN;
   color stc = cWait;
   if(stv == NQ_ST_BULL)
      stc = cUp;
   if(stv == NQ_ST_BEAR)
      stc = cDn;
   NqRow("e3", kx, vx, yr, "M5 STRUCTURE", ok ? NqStructText(stv, g_s5.hl[i5], g_s5.ll[i5], g_s5.lk[i5]) : "---", ok ? stc : cDim, cKey, fs);
   yr += rh;
   string atrT = "---";
   if(ok && g_s5.atr[i5] > 0.0)
      atrT = NqPx(g_s5.atr[i5]) + "   scalp SL " + NqPx(InpScalpSlAtr * g_s5.atr[i5]) + "  TP " + NqPx(InpScalpTpAtr * g_s5.atr[i5]);
   NqRow("e4", kx, vx, yr, "M5 ATR" + IntegerToString(InpNrtrAtrPeriod), atrT, cVal, cKey, fs);
   yr += rh;
   string trg = "---";
   color trgC = cDim;
   if(ok)
   {
      int s1 = g_s1.state[i1];
      if(s1 == NQ_BUY || s1 == NQ_SELL)
      {
         int cur = g_s1.sigOf[i1];
         string sideT = (s1 > 0) ? "BUY" : "SELL";
         trg = sideT + "  entry " + NqPx(g_sigs[cur].entry) + "  SL " + NqPx(g_sigs[cur].sl) + "  TP " + NqPx(g_sigs[cur].tp);
         trgC = NqDirColor(s1);
      }
      else
      {
         trg = "WAIT  (M1 NRTR " + NqDirText(g_s1.dir[i1]) + "; " + NqReasonAt(g_s1.reasons[i1], 0) + ")";
         trgC = cWait;
      }
   }
   NqRow("e5", kx, vx, yr, "M1 TRIGGER", trg, trgC, cKey, fs);
   yr += rh;
   string fcT = "---";
   color fcC = cDim;
   if(ok)
   {
      int f = g_s1.fc[i1];
      if(f > 0)
         fcT = NqSymUp() + " UP   (score +" + IntegerToString(g_s1.fcScore[i1]) + ")";
      else if(f < 0)
         fcT = NqSymDown() + " DOWN   (score " + IntegerToString(g_s1.fcScore[i1]) + ")";
      else
         fcT = "NO ARROW   (score " + IntegerToString(g_s1.fcScore[i1]) + ", votes split)";
      fcC = NqDirColor(f);
   }
   NqRow("e6", kx, vx, yr, "NEXT M1 FORECAST", fcT, fcC, cKey, fs);
   yr += rh;
   string hitT = "---";
   if(ok)
   {
      int cnt = 0;
      int hits = 0;
      NqForecastStats(g_s1, 0, cnt, hits);
      if(cnt > 0)
         hitT = DoubleToString(100.0 * hits / cnt, 1) + "%  (" + IntegerToString(hits) + " of " + IntegerToString(cnt) + ", " +
                NqEvidenceText(cnt) + ")";
      else
         hitT = "no resolved forecasts yet";
      if(NqChartSeries() == 0)
         hitT = hitT + "  - arrows need an M1/M5/M15 chart";
   }
   NqRow("e7", kx, vx, yr, "FORECAST HIT RATE", hitT, cVal, cKey, fs);
   y += tTopH + 6;

   // ---------------- BOTTOM TABLE: plan + auto scalp + risk ----------------
   NqRect("t2", tx, y, TW, tBotH, cTbl, cDim);
   NqLabel("h2", kx, y + 3, "PENDING ORDER PLAN  +  AUTO SCALP  +  RISK", cMetal, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   yr = y + rh + 3;
   int kinds[2];
   kinds[0] = NQ_PLAN_QML;
   kinds[1] = NQ_PLAN_PB;
   for(int q = 0; q < 2; q++)
   {
      string id = (q == 0) ? "q" : "p";
      string kn = (q == 0) ? "QML" : "PULLBACK";
      int k = ok ? NqLatestPlan(g_plans, g_nPlans, kinds[q]) : -1;
      string vOrd = "---";
      string vSt = "---";
      color cOrd = cDim;
      color cSt = cDim;
      if(ok && k < 0)
      {
         vOrd = "NONE  (no " + kn + " setup on M5 yet)";
         vSt = "waiting for a setup";
      }
      if(k >= 0)
      {
         NqPlan pl = g_plans[k];
         string typ = (pl.dir > 0) ? "BUY LIMIT " : "SELL LIMIT ";
         double lot = NqLotFor(g_riskMoney, pl.risk, g_tick, g_tickValue, g_volMin, g_volMax, g_volStep);
         vOrd = typ + NqPx(pl.entry) + "  SL " + NqPx(pl.sl) + "  TP1 " + NqPx(pl.tp1) + "  TP2 " + NqPx(pl.tp2) +
                "  lot " + ((lot > 0.0) ? DoubleToString(lot, 2) : "n/a");
         cOrd = NqDirColor(pl.dir);
         vSt = NqPlanStatusText(pl.status);
         cSt = (pl.status == NQ_PL_ACTIVE) ? cWait : cVal;
         if(pl.status == NQ_PL_ACTIVE)
         {
            ulong tk = NqFindPlanOrder(pl);
            if(tk != 0)
               vSt = "ORDER #" + IntegerToString((long)tk) + " PLACED";
            else if(InpPendingAuto)
               vSt = "NOT PLACED YET";
            else
               vSt = "PLACE IT YOURSELF";
            long expSec = (long)(g_s5.t[pl.idx] + (long)(InpPlanValidBars + 1) * g_s5.sec - nowS);
            vSt = vSt + ", expires in " + NqHhMm(expSec);
         }
         if(q == 0)
            vSt = vSt + "  (neck " + NqPx(pl.lvlA) + ", head " + NqPx(pl.lvlB) + ")";
         else
            vSt = vSt + "  (" + DoubleToString(InpPbRetrace * 100.0, 0) + "% of " + NqPx(pl.lvlA) + NqSymArrow() + NqPx(pl.lvlB) + ")";
      }
      NqRow(id + "1", kx, vx, yr, kn + " ORDER", vOrd, cOrd, cKey, fs);
      yr += rh;
      NqRow(id + "2", kx, vx, yr, kn + " STATUS", vSt, cSt, cKey, fs);
      yr += rh;
   }
   string gateT = (g_gate == 0) ? "OPEN" : NqGateAt(g_gate, 0);
   gateT = gateT + "   (scalp " + (InpScalpAuto ? "auto" : "manual") + ", pending " + (InpPendingAuto ? "auto" : "manual") +
           ", spread " + IntegerToString(g_spreadPts) + "/" + IntegerToString(InpMaxSpreadPoints) + ")";
   NqRow("b5", kx, vx, yr, "GATE", gateT, (g_gate == 0) ? cUp : cBlock, cKey, fs);
   yr += rh;
   string lotT = (ok && g_lotNext > 0.0) ? (DoubleToString(g_lotNext, 2) + " lots = " + DoubleToString(g_lossNext, 2) + " at SL")
                                         : "min lot risks too much";
   NqRow("b6", kx, vx, yr, "RISK / AUTO LOT", DoubleToString(InpRiskPct, 2) + "% = " + DoubleToString(g_riskMoney, 2) + " " + g_accCcy +
         "   next scalp " + lotT, (ok && g_lotNext > 0.0) ? cVal : cWait, cKey, fs);
   yr += rh;
   NqRow("b7", kx, vx, yr, "TODAY", NqMoney(g_dayPnl) + " closed, " + NqMoney(g_floating) + " open   cap -" + DoubleToString(g_capMoney, 2) +
         "   trades " + IntegerToString(g_tradesToday) + "/" + IntegerToString(InpMaxTradesPerDay),
         ((g_gate & NQ_K_DAILY_CAP) != 0) ? cBlock : cVal, cKey, fs);
   yr += rh;
   string openT = g_posText;
   if(g_pendCount > 0)
      openT = openT + "   pending " + IntegerToString(g_pendCount) + ": " + g_pendText;
   NqRow("b8", kx, vx, yr, "OPEN / PENDING", openT, (g_openCount + g_pendCount > 0) ? cVal : cDim, cKey, fs);
   yr += rh;
   string rec = "---";
   if(ok)
   {
      int done = 0;
      int won = 0;
      int lost = 0;
      NqSignalStats(g_sigs, g_nSig, done, won, lost);
      int qf = 0;
      int qw = 0;
      int ql = 0;
      NqPlanStats(g_plans, g_nPlans, NQ_PLAN_QML, qf, qw, ql);
      int pf = 0;
      int pw = 0;
      int plst = 0;
      NqPlanStats(g_plans, g_nPlans, NQ_PLAN_PB, pf, pw, plst);
      rec = "scalp " + IntegerToString(won) + "/" + IntegerToString(done) + " TP   QML " + IntegerToString(qw) + "/" +
            IntegerToString(qf) + "   pullback " + IntegerToString(pw) + "/" + IntegerToString(pf) + "   (" +
            NqEvidenceText(done) + ")";
   }
   NqRow("b9", kx, vx, yr, "RECORD " + IntegerToString(InpHistoryDays) + "d", rec, cVal, cKey, fs);
   y += tBotH + 4;

   NqLabel("f1", ox + pad, y, "Closed candles only. Arrows are forecasts: judge the hit rate, not one arrow. Last: " + g_lastTrade,
           cDim, fsH, "Arial", ANCHOR_LEFT_UPPER);
}
//+------------------------------------------------------------------+
