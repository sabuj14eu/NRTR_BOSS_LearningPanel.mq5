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
//|  SPIKE GUARD + VOLATILITY REGIME (news days, v1.7): ATR(M5)      |
//|  against its own average gates NEW entries (DEAD / EXTREME =     |
//|  none, EXPANSION = stronger confirmation); a spike of 4+ ATR     |
//|  inside an hour blocks pullback / scalp / breakout entries in    |
//|  its own direction (a retrace of a spike is not a pullback) and  |
//|  flashes EXIT WARNING on a position once half of it is given     |
//|  back. Closing is never blocked; only opening is.                |
//|                                                                  |
//|  Supported symbols: Gold (XAUUSD / GOLD) and Silver (XAGUSD /    |
//|  SILVER), any broker prefix/suffix. Nothing else.                |
//|  Personal tool. No network, no Telegram, no DLL, no files.       |
//+------------------------------------------------------------------+
#property copyright   "Personal use - demo trading tool"
#property version     "1.93"
#property description "Gold/Silver: M15 context, M5 regime+structure, M1 trigger, risk engine, auto lot."
#property description "Auto scalp + QML/pullback/NY-trap/radar plans, macro vote (DXY, bond, USD news, H4/H1), news guard, smart exit."
#property description "The MT5 Algo Trading button is the on/off switch. Only orders with this EA magic are ever touched."
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
#define NQ_PLAN_NY  3   // NY trap reversal
#define NQ_PLAN_RADAR 4 // impulse radar: STOP order beyond the nearest level
#define NQ_PLAN_SCALP 5 // journal only: the M1 scalp record

// NY trap state machine (per session, per side)
#define NQ_NY_NONE      0   // outside the session
#define NQ_NY_OPEN      1   // inside the session, range building, nothing swept
#define NQ_NY_SWEPT     2   // the pre-NY high (bull trap) / low (bear trap) was taken
#define NQ_NY_RETURNED  3   // a CLOSE came back inside the pre-NY range
#define NQ_NY_CONFIRMED 4   // M5 confirms against the sweep -> plan armed
#define NQ_NY_DONE      5   // this side is finished for the session
#define NQ_PL_ACTIVE   1
#define NQ_PL_FILLED   2
#define NQ_PL_TP1      3
#define NQ_PL_SL       4
#define NQ_PL_EXPIRED  5
#define NQ_PL_INVALID  6
#define NQ_PL_REPLACED 7
#define NQ_PL_FALSE    8   // radar: filled, then the close came back through the level

// impulse radar states (per direction)
#define NQ_RD_NO_LEVEL 0
#define NQ_RD_FAR      1   // level more than 2 ATR away
#define NQ_RD_BUILDING 2   // score below 5
#define NQ_RD_NEAR     3   // within 1 ATR, score 5-6
#define NQ_RD_READY    4   // score >= 7 within 1 ATR: plan armed

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
   double   planMinRiskAtr; // a plan's stop at least this many ATR away (0 = the structural stop as it is)
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
   int      kind;         // NQ_PLAN_QML / NQ_PLAN_PB / NQ_PLAN_NY
   int      tf;           // seconds of the timeframe that produced it (300 = M5, 900 = M15)
   int      dir;          // NQ_BUY (buy limit) / NQ_SELL (sell limit)
   int      idx;          // M5 bar at whose close the plan was created
   datetime keyTime;      // time of the key swing (unique id, survives restarts)
   datetime madeAt;       // close time of the bar that created the plan
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
   double   v[];          // tick volume (VWAP)
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
   ArrayResize(s.v, n);
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

//--- BIAS ARROW. At the close of candle i the votes are summed: higher-TF
//    (x2), own NRTR, close vs fast EMA, last body. An arrow is drawn ONLY
//    when |score| >= minScore (a strong, one-sided vote); a split vote is
//    no arrow. The arrow claims a MOVE, not a candle colour: it is a HIT
//    when the price reaches +0.5 ATR in its direction before -0.5 ATR
//    against it within the next 5 candles, a MISS when the opposite side
//    is reached first (both in one candle = miss), and UNRESOLVED (not
//    counted) if neither side is reached in 5 candles.
#define NQ_FC_HORIZON 5

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
   }
   for(int i = 0; i < n; i++)
   {
      if(s.fc[i] == 0 || s.atr[i] <= 0.0)
         continue;
      double up = s.c[i] + 0.5 * s.atr[i];
      double dn = s.c[i] - 0.5 * s.atr[i];
      for(int j = i + 1; j < n && j <= i + NQ_FC_HORIZON; j++)
      {
         bool hitUp = (s.h[j] >= up);
         bool hitDn = (s.l[j] <= dn);
         if(!hitUp && !hitDn)
            continue;
         if(hitUp && hitDn)
            s.fcHit[i] = -1;
         else if(s.fc[i] > 0)
            s.fcHit[i] = hitUp ? 1 : -1;
         else
            s.fcHit[i] = hitDn ? 1 : -1;
         break;
      }
   }
}

//--- arrow hit rate over RESOLVED arrows from bar `from` on
void NqForecastStats(const NqSeries &s, int from, int &count, int &hits)
{
   count = 0;
   hits = 0;
   if(from < 0)
      from = 0;
   for(int i = from; i < s.n; i++)
   {
      if(s.fc[i] == 0 || s.fcHit[i] == 0)
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

// a structural stop closer than planMinRiskAtr x ATR is inside the market's noise: it is
// pushed OUT to the floor (never in), and R follows, so TP1 / TP2 (1R / 2R) widen with it.
// 2026-10-08, gold: a QML stop 1.80 USD away with ATR(M5) 3.26 - a coin toss with costs. 0 = off.
void NqFloorRisk(int dir, double entry, double atr, const NqParams &P, double &sl, double &risk)
{
   if(P.planMinRiskAtr <= 0.0 || atr <= 0.0 || risk <= 0.0)
      return;
   double minRisk = P.planMinRiskAtr * atr;
   if(risk >= minRisk)
      return;
   sl = (dir > 0) ? NqRoundTick(entry - minRisk, P.tick, P.digits, -1) : NqRoundTick(entry + minRisk, P.tick, P.digits, 1);
   risk = NormalizeDouble(MathAbs(entry - sl), P.digits);
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
               NqFloorRisk(NQ_BUY, entry, s.atr[t], P, sl, risk);
               if(risk > 0.0 && s.c[t] > entry)
               {
                  NqPlan pl;
                  pl.kind = NQ_PLAN_PB;
                  pl.tf = s.sec;
                  pl.dir = NQ_BUY;
                  pl.idx = t;
                  pl.madeAt = s.t[t] + s.sec;
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
               NqFloorRisk(NQ_SELL, entry, s.atr[t], P, sl, risk);
               if(risk > 0.0 && s.c[t] < entry)
               {
                  NqPlan pl;
                  pl.kind = NQ_PLAN_PB;
                  pl.tf = s.sec;
                  pl.dir = NQ_SELL;
                  pl.idx = t;
                  pl.madeAt = s.t[t] + s.sec;
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
            NqFloorRisk(NQ_SELL, entry, s.atr[t], P, sl, risk);
            if(risk > 0.0 && s.c[t] < entry)
            {
               NqPlan pl;
               pl.kind = NQ_PLAN_QML;
               pl.tf = s.sec;
               pl.dir = NQ_SELL;
               pl.idx = t;
               pl.madeAt = s.t[t] + s.sec;
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
            NqFloorRisk(NQ_BUY, entry, s.atr[t], P, sl, risk);
            if(risk > 0.0 && s.c[t] > entry)
            {
               NqPlan pl;
               pl.kind = NQ_PLAN_QML;
               pl.tf = s.sec;
               pl.dir = NQ_BUY;
               pl.idx = t;
               pl.madeAt = s.t[t] + s.sec;
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

//--- NY TRAP state machine on closed M5 bars. Server minutes of day.
//    PRE-NY RANGE = high/low of the bars from rangeStart up to the NY open.
//    Inside NY: a bar's high above the pre-NY high is a SWEEP (bull trap
//    candidate), a later CLOSE back below that high is the RETURN, and a
//    bearish confirmation vote (conf[t] < 0, the M5 NRTR) CONFIRMS the trap:
//    SELL LIMIT at the swept level, SL beyond the sweep extreme, TP1 = 1R,
//    TP2 = 2R. Bear trap is the mirror. The sweep alone never decides a
//    direction. One trap per side per session; unfilled plans expire at the
//    session end.
struct NqNyState
{
   int      day;          // server day of the state below
   int      stBull;       // NQ_NY_* for the bull-trap side (sell plan)
   int      stBear;       // NQ_NY_* for the bear-trap side (buy plan)
   bool     inSession;    // last bar was inside the NY window
   double   preHi;
   double   preLo;
   bool     preOk;        // pre-NY range has at least one bar
   double   nyHi;
   double   nyLo;
   bool     nyOk;
   double   sweepHi;      // extreme of the high sweep
   double   sweepLo;      // extreme of the low sweep
   double   retCloseHi;   // the close that returned below the pre-NY high
   double   retCloseLo;
   int      planBull;     // index into plans (-1 none)
   int      planBear;
};

void NqNyReset(NqNyState &y, int day)
{
   y.day = day;
   y.stBull = NQ_NY_NONE;
   y.stBear = NQ_NY_NONE;
   y.inSession = false;
   y.preHi = 0.0;
   y.preLo = 0.0;
   y.preOk = false;
   y.nyHi = 0.0;
   y.nyLo = 0.0;
   y.nyOk = false;
   y.sweepHi = 0.0;
   y.sweepLo = 0.0;
   y.retCloseHi = 0.0;
   y.retCloseLo = 0.0;
   y.planBull = -1;
   y.planBear = -1;
}

int NqMinuteOfDay(datetime t)
{
   return (int)(((long)t % 86400) / 60);
}

int NqDayOf(datetime t)
{
   return (int)((long)t / 86400);
}

void NqRunNyTrap(const NqSeries &s, const int &conf[], const NqParams &P, int rangeStartMin, int nyStartMin,
                 int nyEndMin, NqPlan &plans[], int &nPlans, NqNyState &y)
{
   ArrayResize(plans, 0);
   nPlans = 0;
   NqNyReset(y, -1);
   int n = s.n;
   for(int t = 0; t < n; t++)
   {
      // 1) existing NY plans see this bar
      for(int k = 0; k < nPlans; k++)
         if((plans[k].status == NQ_PL_ACTIVE || plans[k].status == NQ_PL_FILLED) && t > plans[k].idx)
            NqPlanJudge(plans[k], s, t, P);

      int day = NqDayOf(s.t[t]);
      int mod = NqMinuteOfDay(s.t[t]);
      if(day != y.day)
      {
         // a new server day: unfilled NY plans of the old day expire
         for(int k = 0; k < nPlans; k++)
            if(plans[k].status == NQ_PL_ACTIVE)
               NqPlanClose(plans[k], NQ_PL_EXPIRED, t);
         NqNyReset(y, day);
      }
      bool inNy = (mod >= nyStartMin && mod < nyEndMin);
      if(y.inSession && !inNy)
      {
         // session just ended: unfilled plans expire, both sides are done
         for(int k = 0; k < nPlans; k++)
            if(plans[k].status == NQ_PL_ACTIVE)
               NqPlanClose(plans[k], NQ_PL_EXPIRED, t);
         if(y.stBull != NQ_NY_NONE)
            y.stBull = NQ_NY_DONE;
         if(y.stBear != NQ_NY_NONE)
            y.stBear = NQ_NY_DONE;
      }
      y.inSession = inNy;
      if(!inNy)
      {
         if(mod >= rangeStartMin && mod < nyStartMin)
         {
            if(!y.preOk || s.h[t] > y.preHi)
               y.preHi = s.h[t];
            if(!y.preOk || s.l[t] < y.preLo)
               y.preLo = s.l[t];
            y.preOk = true;
         }
         continue;
      }
      // inside the session
      if(!y.nyOk || s.h[t] > y.nyHi)
         y.nyHi = s.h[t];
      if(!y.nyOk || s.l[t] < y.nyLo)
         y.nyLo = s.l[t];
      y.nyOk = true;
      if(!y.preOk)
         continue;   // no pre-NY range today (data starts inside the session)
      if(y.stBull == NQ_NY_NONE)
         y.stBull = NQ_NY_OPEN;
      if(y.stBear == NQ_NY_NONE)
         y.stBear = NQ_NY_OPEN;

      // bull trap side -> SELL plan
      if(y.stBull == NQ_NY_OPEN && s.h[t] > y.preHi)
      {
         y.stBull = NQ_NY_SWEPT;
         y.sweepHi = s.h[t];
      }
      else if(y.stBull == NQ_NY_SWEPT || y.stBull == NQ_NY_RETURNED)
      {
         if(s.h[t] > y.sweepHi)
            y.sweepHi = s.h[t];
         if(y.stBull == NQ_NY_SWEPT && s.c[t] < y.preHi)
         {
            y.stBull = NQ_NY_RETURNED;
            y.retCloseHi = s.c[t];
         }
         if(y.stBull == NQ_NY_RETURNED && conf[t] < 0 && s.atr[t] > 0.0)
         {
            double entry = NqRoundTick(y.preHi, P.tick, P.digits, 0);
            double sl = NqRoundTick(y.sweepHi + P.qmlSlBufAtr * s.atr[t], P.tick, P.digits, 1);
            double risk = NormalizeDouble(sl - entry, P.digits);
            NqFloorRisk(NQ_SELL, entry, s.atr[t], P, sl, risk);
            if(risk > 0.0 && s.c[t] < entry)
            {
               NqPlan pl;
               pl.kind = NQ_PLAN_NY;
               pl.tf = s.sec;
               pl.dir = NQ_SELL;
               pl.idx = t;
               pl.madeAt = s.t[t] + s.sec;
               pl.keyTime = s.t[t];
               pl.entry = entry;
               pl.sl = sl;
               pl.tp1 = NqRoundTick(entry - P.planTp1R * risk, P.tick, P.digits, 0);
               pl.tp2 = NqRoundTick(entry - P.planTp2R * risk, P.tick, P.digits, 0);
               pl.risk = risk;
               pl.lvlA = y.preHi;
               pl.lvlB = y.sweepHi;
               pl.status = NQ_PL_ACTIVE;
               pl.statusIdx = t;
               pl.fillIdx = -1;
               y.planBull = NqPlanAdd(plans, nPlans, pl);
               y.stBull = NQ_NY_CONFIRMED;
            }
         }
      }
      // bear trap side -> BUY plan
      if(y.stBear == NQ_NY_OPEN && s.l[t] < y.preLo)
      {
         y.stBear = NQ_NY_SWEPT;
         y.sweepLo = s.l[t];
      }
      else if(y.stBear == NQ_NY_SWEPT || y.stBear == NQ_NY_RETURNED)
      {
         if(s.l[t] < y.sweepLo)
            y.sweepLo = s.l[t];
         if(y.stBear == NQ_NY_SWEPT && s.c[t] > y.preLo)
         {
            y.stBear = NQ_NY_RETURNED;
            y.retCloseLo = s.c[t];
         }
         if(y.stBear == NQ_NY_RETURNED && conf[t] > 0 && s.atr[t] > 0.0)
         {
            double entry = NqRoundTick(y.preLo, P.tick, P.digits, 0);
            double sl = NqRoundTick(y.sweepLo - P.qmlSlBufAtr * s.atr[t], P.tick, P.digits, -1);
            double risk = NormalizeDouble(entry - sl, P.digits);
            NqFloorRisk(NQ_BUY, entry, s.atr[t], P, sl, risk);
            if(risk > 0.0 && s.c[t] > entry)
            {
               NqPlan pl;
               pl.kind = NQ_PLAN_NY;
               pl.tf = s.sec;
               pl.dir = NQ_BUY;
               pl.idx = t;
               pl.madeAt = s.t[t] + s.sec;
               pl.keyTime = s.t[t];
               pl.entry = entry;
               pl.sl = sl;
               pl.tp1 = NqRoundTick(entry + P.planTp1R * risk, P.tick, P.digits, 0);
               pl.tp2 = NqRoundTick(entry + P.planTp2R * risk, P.tick, P.digits, 0);
               pl.risk = risk;
               pl.lvlA = y.preLo;
               pl.lvlB = y.sweepLo;
               pl.status = NQ_PL_ACTIVE;
               pl.statusIdx = t;
               pl.fillIdx = -1;
               y.planBear = NqPlanAdd(plans, nPlans, pl);
               y.stBear = NQ_NY_CONFIRMED;
            }
         }
      }
   }
}

//--- SESSION LEVELS + BREAKS on closed bars, for the current server day.
//    Asia / London / pre-NY / NY highs and lows and the previous day's
//    high and low. A level is ACTIVE once its session has ended (the
//    previous day's levels all day). A CLOSE above an active high that
//    the previous close was not above is a BREAKOUT; below an active low,
//    a BREAKDOWN. First cross only, per level, per day.
#define NQ_LV_PDH   0
#define NQ_LV_PDL   1
#define NQ_LV_ASH   2
#define NQ_LV_ASL   3
#define NQ_LV_LOH   4
#define NQ_LV_LOL   5
#define NQ_LV_PNH   6
#define NQ_LV_PNL   7
#define NQ_LV_NYH   8
#define NQ_LV_NYL   9
#define NQ_LV_COUNT 10
#define NQ_BRK_MAX  12

struct NqLevels
{
   int      day;
   double   px[10];       // level prices, index NQ_LV_*
   bool     ok[10];       // level exists
   bool     act[10];      // level is active (its session ended / previous day)
   bool     broken[10];   // already crossed today
   datetime from[10];     // time the level became active (line start)
};

struct NqBreak
{
   int      level;        // NQ_LV_*
   int      dir;          // +1 breakout above a high, -1 breakdown below a low
   int      idx;          // bar of the close that crossed
   double   close;
};

string NqLevelName(int lv)
{
   switch(lv)
   {
      case NQ_LV_PDH: return "PD HIGH";
      case NQ_LV_PDL: return "PD LOW";
      case NQ_LV_ASH: return "ASIA HIGH";
      case NQ_LV_ASL: return "ASIA LOW";
      case NQ_LV_LOH: return "LONDON HIGH";
      case NQ_LV_LOL: return "LONDON LOW";
      case NQ_LV_PNH: return "PRE-NY HIGH";
      case NQ_LV_PNL: return "PRE-NY LOW";
      case NQ_LV_NYH: return "NY HIGH";
      case NQ_LV_NYL: return "NY LOW";
   }
   return "";
}

void NqLevelsReset(NqLevels &L, int day)
{
   L.day = day;
   for(int i = 0; i < NQ_LV_COUNT; i++)
   {
      L.px[i] = 0.0;
      L.ok[i] = false;
      L.act[i] = false;
      L.broken[i] = false;
      L.from[i] = 0;
   }
}

void NqLevelGrow(NqLevels &L, int hiIdx, int loIdx, double h, double l)
{
   if(!L.ok[hiIdx] || h > L.px[hiIdx])
      L.px[hiIdx] = h;
   if(!L.ok[loIdx] || l < L.px[loIdx])
      L.px[loIdx] = l;
   L.ok[hiIdx] = true;
   L.ok[loIdx] = true;
}

void NqRunLevels(const NqSeries &s, int asiaS, int asiaE, int lonS, int lonE, int preS, int nyS, int nyE,
                 NqLevels &L, NqBreak &brk[], int &nBrk, double &resAbove[], double &supBelow[])
{
   ArrayResize(brk, 0);
   nBrk = 0;
   NqLevelsReset(L, -1);
   ArrayResize(resAbove, s.n);
   ArrayResize(supBelow, s.n);
   double dayHi = 0.0;
   double dayLo = 0.0;
   bool dayOk = false;
   int n = s.n;
   for(int t = 0; t < n; t++)
   {
      int day = NqDayOf(s.t[t]);
      int mod = NqMinuteOfDay(s.t[t]);
      if(day != L.day)
      {
         // roll the day: yesterday's range becomes today's PD levels
         NqLevelsReset(L, day);
         ArrayResize(brk, 0);
         nBrk = 0;
         if(dayOk)
         {
            L.px[NQ_LV_PDH] = dayHi;
            L.px[NQ_LV_PDL] = dayLo;
            L.ok[NQ_LV_PDH] = true;
            L.ok[NQ_LV_PDL] = true;
            L.act[NQ_LV_PDH] = true;
            L.act[NQ_LV_PDL] = true;
            L.from[NQ_LV_PDH] = s.t[t];
            L.from[NQ_LV_PDL] = s.t[t];
         }
         dayOk = false;
      }
      if(!dayOk || s.h[t] > dayHi)
         dayHi = s.h[t];
      if(!dayOk || s.l[t] < dayLo)
         dayLo = s.l[t];
      dayOk = true;
      // 1) breaks are judged BEFORE this bar can extend a level
      for(int lv = 0; lv < NQ_LV_COUNT; lv++)
      {
         if(!L.act[lv] || L.broken[lv] || t == 0)
            continue;
         bool isHigh = (lv % 2 == 0);
         bool cross = isHigh ? (s.c[t] > L.px[lv] && s.c[t - 1] <= L.px[lv]) : (s.c[t] < L.px[lv] && s.c[t - 1] >= L.px[lv]);
         if(cross && nBrk < NQ_BRK_MAX)
         {
            ArrayResize(brk, nBrk + 1, 16);
            brk[nBrk].level = lv;
            brk[nBrk].dir = isHigh ? 1 : -1;
            brk[nBrk].idx = t;
            brk[nBrk].close = s.c[t];
            nBrk++;
            L.broken[lv] = true;
         }
      }
      // 2) sessions grow while open and become active when they end
      bool inAsia = (mod >= asiaS && mod < asiaE);
      bool inLon = (mod >= lonS && mod < lonE);
      bool inPre = (mod >= preS && mod < nyS);
      bool inNy = (mod >= nyS && mod < nyE);
      if(inAsia)
         NqLevelGrow(L, NQ_LV_ASH, NQ_LV_ASL, s.h[t], s.l[t]);
      else if(L.ok[NQ_LV_ASH] && !L.act[NQ_LV_ASH] && mod >= asiaE)
      {
         L.act[NQ_LV_ASH] = true;
         L.act[NQ_LV_ASL] = true;
         L.from[NQ_LV_ASH] = s.t[t];
         L.from[NQ_LV_ASL] = s.t[t];
      }
      if(inLon)
         NqLevelGrow(L, NQ_LV_LOH, NQ_LV_LOL, s.h[t], s.l[t]);
      else if(L.ok[NQ_LV_LOH] && !L.act[NQ_LV_LOH] && mod >= lonE)
      {
         L.act[NQ_LV_LOH] = true;
         L.act[NQ_LV_LOL] = true;
         L.from[NQ_LV_LOH] = s.t[t];
         L.from[NQ_LV_LOL] = s.t[t];
      }
      if(inPre)
         NqLevelGrow(L, NQ_LV_PNH, NQ_LV_PNL, s.h[t], s.l[t]);
      else if(L.ok[NQ_LV_PNH] && !L.act[NQ_LV_PNH] && mod >= nyS)
      {
         L.act[NQ_LV_PNH] = true;
         L.act[NQ_LV_PNL] = true;
         L.from[NQ_LV_PNH] = s.t[t];
         L.from[NQ_LV_PNL] = s.t[t];
      }
      if(inNy)
         NqLevelGrow(L, NQ_LV_NYH, NQ_LV_NYL, s.h[t], s.l[t]);
      else if(L.ok[NQ_LV_NYH] && !L.act[NQ_LV_NYH] && mod >= nyE)
      {
         L.act[NQ_LV_NYH] = true;
         L.act[NQ_LV_NYL] = true;
         L.from[NQ_LV_NYH] = s.t[t];
         L.from[NQ_LV_NYL] = s.t[t];
      }
      // 3) nearest active level above / below this close (0 = none)
      double ra = 0.0;
      double sb = 0.0;
      for(int lv = 0; lv < NQ_LV_COUNT; lv++)
      {
         if(!L.act[lv])
            continue;
         if(L.px[lv] > s.c[t] && (ra == 0.0 || L.px[lv] < ra))
            ra = L.px[lv];
         if(L.px[lv] < s.c[t] && (sb == 0.0 || L.px[lv] > sb))
            sb = L.px[lv];
      }
      resAbove[t] = ra;
      supBelow[t] = sb;
   }
}

//--- IMPULSE RADAR. For each closed M5 bar and each direction it finds the
//    nearest level (session / previous-day level or confirmed M5 swing) and
//    scores the pre-break conditions out of 10:
//      structure   0-2  M5 regime (NRTR + HH/HL or LH/LL); last swing label alone = 1
//      compression 0-2  last 4 ranges vs the 12 before (<= 0.8) + repeated tests of the level
//      proximity   0-2  distance to the level <= 0.5 ATR (2) / <= 1 ATR (1)
//      efficiency  0-2  mean signed body/range of the last 4 bars >= 0.4 (1) / >= 0.6 (2)
//      momentum    0-1  three closes in a row in the direction
//      M15 boss    0-1  M15 context agrees
//    READY (score >= 7 within 1 ATR) arms a STOP order just beyond the level
//    with a structure SL (last confirmed swing on the other side, else 1.5 ATR),
//    TP1 = 1R, TP2 = 2R. Unfilled plans end when the pressure fails (score < 5),
//    on expiry, or when a newer level replaces them. A fill whose bar (or the
//    next) CLOSES back through the level is a FALSE BREAK.
struct NqRadar
{
   int      state;        // NQ_RD_*
   double   level;
   double   dist;         // ATR units, from the close
   int      score;
   int      sStruct;
   int      sComp;
   int      sProx;
   int      sEff;
   int      sMom;
   int      sM15;
   double   eff;          // mean signed efficiency of the last 4 bars
   int      plan;         // index of the active plan for this direction (-1)
};

void NqRadarReset(NqRadar &r)
{
   r.state = NQ_RD_NO_LEVEL;
   r.level = 0.0;
   r.dist = 0.0;
   r.score = 0;
   r.sStruct = 0;
   r.sComp = 0;
   r.sProx = 0;
   r.sEff = 0;
   r.sMom = 0;
   r.sM15 = 0;
   r.eff = 0.0;
   r.plan = -1;
}

string NqRadarStateText(int st)
{
   switch(st)
   {
      case NQ_RD_NO_LEVEL: return "NO LEVEL";
      case NQ_RD_FAR:      return "FAR";
      case NQ_RD_BUILDING: return "BUILDING";
      case NQ_RD_NEAR:     return "NEAR";
      case NQ_RD_READY:    return "READY";
   }
   return "";
}

string NqPressureText(int score)
{
   if(score >= 7)
      return "HIGH";
   if(score >= 5)
      return "MEDIUM";
   return "LOW";
}

// nearest confirmed swing beyond the close (kind +1 above, -1 below) within maxAge bars
double NqNearestSwing(const NqPivot &piv[], int np, int t, int kind, double close, int maxAge)
{
   double best = 0.0;
   for(int p = np - 1; p >= 0; p--)
   {
      if(piv[p].confirmIdx > t)
         continue;
      if(t - piv[p].idx > maxAge)
         break;
      if(piv[p].kind != kind)
         continue;
      if(kind > 0 && piv[p].price > close && (best == 0.0 || piv[p].price < best))
         best = piv[p].price;
      if(kind < 0 && piv[p].price < close && (best == 0.0 || piv[p].price > best))
         best = piv[p].price;
   }
   return best;
}

// score one direction at bar t; fills r (state, level, dist, components)
void NqRadarScore(const NqSeries &s, const NqPivot &piv[], int np, int t, int dir, double level, NqRadar &r)
{
   r.level = level;
   r.score = 0;
   r.sStruct = 0;
   r.sComp = 0;
   r.sProx = 0;
   r.sEff = 0;
   r.sMom = 0;
   r.sM15 = 0;
   r.eff = 0.0;
   double atr = s.atr[t];
   if(level <= 0.0 || atr <= 0.0 || t < 16)
   {
      r.state = NQ_RD_NO_LEVEL;
      r.dist = 0.0;
      return;
   }
   r.dist = ((dir > 0) ? (level - s.c[t]) : (s.c[t] - level)) / atr;
   // structure
   if(s.regime[t] == ((dir > 0) ? NQ_REG_BULL : NQ_REG_BEAR))
      r.sStruct = 2;
   else if((dir > 0 && s.hl[t] == NQ_L_HH) || (dir < 0 && s.ll[t] == NQ_L_LL))
      r.sStruct = 1;
   // compression
   double rNow = 0.0;
   double rPrev = 0.0;
   for(int i = t - 3; i <= t; i++)
      rNow += s.h[i] - s.l[i];
   for(int i = t - 15; i <= t - 4; i++)
      rPrev += s.h[i] - s.l[i];
   rNow /= 4.0;
   rPrev /= 12.0;
   if(rPrev > 0.0 && rNow <= 0.8 * rPrev)
      r.sComp++;
   int tests = 0;
   for(int i = t - 11; i <= t; i++)
   {
      if(dir > 0 && s.h[i] >= level - 0.3 * atr && s.c[i] <= level)
         tests++;
      if(dir < 0 && s.l[i] <= level + 0.3 * atr && s.c[i] >= level)
         tests++;
   }
   if(tests >= 2)
      r.sComp++;
   // proximity
   if(r.dist <= 0.5)
      r.sProx = 2;
   else if(r.dist <= 1.0)
      r.sProx = 1;
   // efficiency (signed body / range, mean of the last 4)
   double effSum = 0.0;
   for(int i = t - 3; i <= t; i++)
   {
      double rng = s.h[i] - s.l[i];
      double e = (rng > 0.0) ? (s.c[i] - s.o[i]) / rng : 0.0;
      effSum += (dir > 0) ? e : -e;
   }
   r.eff = effSum / 4.0;
   if(r.eff >= 0.6)
      r.sEff = 2;
   else if(r.eff >= 0.4)
      r.sEff = 1;
   // momentum persistence: three closes in a row in the direction
   int run = 0;
   for(int i = t; i >= 1 && run < 3; i--)
   {
      if((dir > 0 && s.c[i] > s.c[i - 1]) || (dir < 0 && s.c[i] < s.c[i - 1]))
         run++;
      else
         break;
   }
   if(run >= 3)
      r.sMom = 1;
   // M15 boss
   if(s.hi[t] == dir)
      r.sM15 = 1;
   r.score = r.sStruct + r.sComp + r.sProx + r.sEff + r.sMom + r.sM15;
   if(r.dist > 2.0)
      r.state = NQ_RD_FAR;
   else if(r.score >= 7 && r.dist <= 1.0 && r.dist >= 0.0)
      r.state = NQ_RD_READY;
   else if(r.dist <= 1.0 && r.score >= 5)
      r.state = NQ_RD_NEAR;
   else
      r.state = NQ_RD_BUILDING;
}

// judge a radar plan (STOP order) on closed bar t > idx
void NqRadarJudge(NqPlan &p, const NqSeries &s, int t, int score, const NqParams &P)
{
   if(p.status == NQ_PL_ACTIVE)
   {
      bool filled = (p.dir > 0) ? (s.h[t] >= p.entry) : (s.l[t] <= p.entry);
      if(filled)
      {
         p.status = NQ_PL_FILLED;
         p.fillIdx = t;
         p.statusIdx = t;
         if((p.dir > 0 && s.l[t] <= p.sl) || (p.dir < 0 && s.h[t] >= p.sl))
            NqPlanClose(p, NQ_PL_SL, t);
         else if((p.dir > 0 && s.c[t] < p.lvlA) || (p.dir < 0 && s.c[t] > p.lvlA))
            NqPlanClose(p, NQ_PL_FALSE, t);
         return;
      }
      if(score < 5)
      {
         NqPlanClose(p, NQ_PL_INVALID, t);   // pressure failed
         return;
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
         else if(t == p.fillIdx + 1 && s.c[t] < p.lvlA)
            NqPlanClose(p, NQ_PL_FALSE, t);
      }
      else
      {
         if(s.h[t] >= p.sl)
            NqPlanClose(p, NQ_PL_SL, t);
         else if(s.l[t] <= p.tp1)
            NqPlanClose(p, NQ_PL_TP1, t);
         else if(t == p.fillIdx + 1 && s.c[t] > p.lvlA)
            NqPlanClose(p, NQ_PL_FALSE, t);
      }
   }
}

void NqRunRadar(const NqSeries &s, const NqPivot &piv[], int np, const double &resAbove[], const double &supBelow[],
                const NqParams &P, double bufAtr, NqPlan &plans[], int &nPlans, NqRadar &up, NqRadar &dn)
{
   ArrayResize(plans, 0);
   nPlans = 0;
   NqRadarReset(up);
   NqRadarReset(dn);
   int n = s.n;
   int curUp = -1;
   int curDn = -1;
   for(int t = 0; t < n; t++)
   {
      // levels: nearest of session/previous-day level and confirmed swing
      double lvUp = resAbove[t];
      double swUp = NqNearestSwing(piv, np, t, 1, s.c[t], 120);
      if(swUp > 0.0 && (lvUp == 0.0 || swUp < lvUp))
         lvUp = swUp;
      double lvDn = supBelow[t];
      double swDn = NqNearestSwing(piv, np, t, -1, s.c[t], 120);
      if(swDn > 0.0 && (lvDn == 0.0 || swDn > lvDn))
         lvDn = swDn;
      NqRadarScore(s, piv, np, t, 1, lvUp, up);
      NqRadarScore(s, piv, np, t, -1, lvDn, dn);
      // existing plans see this bar. "Pressure failed" only applies while the
      // plan's own level is still the radar's target; a plan whose level the
      // price crawled through without reaching the stop is passed and dropped.
      for(int k = 0; k < nPlans; k++)
      {
         if((plans[k].status != NQ_PL_ACTIVE && plans[k].status != NQ_PL_FILLED) || t <= plans[k].idx)
            continue;
         double curLevel = (plans[k].dir > 0) ? up.level : dn.level;
         int curScore = (plans[k].dir > 0) ? up.score : dn.score;
         bool sameLevel = (MathAbs(curLevel - plans[k].lvlA) < P.tick * 0.5);
         if(plans[k].status == NQ_PL_ACTIVE && !sameLevel &&
            ((plans[k].dir > 0 && s.c[t] > plans[k].lvlA) || (plans[k].dir < 0 && s.c[t] < plans[k].lvlA)))
         {
            bool filled = (plans[k].dir > 0) ? (s.h[t] >= plans[k].entry) : (s.l[t] <= plans[k].entry);
            if(!filled)
            {
               NqPlanClose(plans[k], NQ_PL_INVALID, t);   // level passed without a break
               continue;
            }
         }
         NqRadarJudge(plans[k], s, t, sameLevel ? curScore : 10, P);
      }
      if(curUp >= 0 && plans[curUp].status != NQ_PL_ACTIVE && plans[curUp].status != NQ_PL_FILLED)
         curUp = -1;
      if(curDn >= 0 && plans[curDn].status != NQ_PL_ACTIVE && plans[curDn].status != NQ_PL_FILLED)
         curDn = -1;
      // arm
      for(int d = 0; d < 2; d++)
      {
         int dir = (d == 0) ? 1 : -1;
         NqRadar r;
         r = (d == 0) ? up : dn;
         int cur = (d == 0) ? curUp : curDn;
         if(r.state != NQ_RD_READY)
            continue;
         if(cur >= 0 && plans[cur].status == NQ_PL_FILLED)
            continue;
         if(cur >= 0 && MathAbs(plans[cur].lvlA - r.level) < P.tick * 0.5)
            continue;   // already armed at this level
         double atr = s.atr[t];
         double entry = (dir > 0) ? NqRoundTick(r.level + bufAtr * atr, P.tick, P.digits, 1)
                                  : NqRoundTick(r.level - bufAtr * atr, P.tick, P.digits, -1);
         double sw = NqNearestSwing(piv, np, t, -dir, s.c[t], 60);
         double sl = 0.0;
         if(sw > 0.0 && MathAbs(entry - sw) <= 2.5 * atr)
            sl = (dir > 0) ? NqRoundTick(sw - P.pbSlBufAtr * atr, P.tick, P.digits, -1)
                           : NqRoundTick(sw + P.pbSlBufAtr * atr, P.tick, P.digits, 1);
         else
            sl = (dir > 0) ? NqRoundTick(entry - P.scalpSlAtr * atr, P.tick, P.digits, -1)
                           : NqRoundTick(entry + P.scalpSlAtr * atr, P.tick, P.digits, 1);
         double risk = NormalizeDouble(MathAbs(entry - sl), P.digits);
         NqFloorRisk(dir, entry, atr, P, sl, risk);
         bool sideOk = (dir > 0) ? (entry > s.c[t]) : (entry < s.c[t]);
         if(risk <= 0.0 || !sideOk)
            continue;
         NqPlan pl;
         pl.kind = NQ_PLAN_RADAR;
         pl.tf = s.sec;
         pl.dir = dir;
         pl.idx = t;
         pl.madeAt = s.t[t] + s.sec;
         pl.keyTime = s.t[t];
         pl.entry = entry;
         pl.sl = sl;
         pl.tp1 = NqRoundTick(entry + dir * P.planTp1R * risk, P.tick, P.digits, 0);
         pl.tp2 = NqRoundTick(entry + dir * P.planTp2R * risk, P.tick, P.digits, 0);
         pl.risk = risk;
         pl.lvlA = r.level;
         pl.lvlB = (sw > 0.0) ? sw : 0.0;
         pl.status = NQ_PL_ACTIVE;
         pl.statusIdx = t;
         pl.fillIdx = -1;
         if(cur >= 0)
            NqPlanClose(plans[cur], NQ_PL_REPLACED, t);
         int k = NqPlanAdd(plans, nPlans, pl);
         if(d == 0)
            curUp = k;
         else
            curDn = k;
      }
      up.plan = curUp;
      dn.plan = curDn;
   }
}

//--- STRUCTURE S/R BREAKS on confirmed M5 swings: the first CLOSE above a
//    confirmed swing high (resistance) after its confirmation is a
//    BREAKOUT CONFIRMED; the first close below a confirmed swing low
//    (support) is a BREAKDOWN CONFIRMED. One event per swing.
struct NqSwingBreak
{
   int      pivIdx;       // index into the pivot array
   int      idx;          // bar of the confirming close
   int      dir;          // +1 breakout, -1 breakdown
   double   level;
   double   close;
};

void NqRunSwingBreaks(const NqSeries &s, const NqPivot &piv[], int np, int maxEvents, NqSwingBreak &out[], int &nOut)
{
   ArrayResize(out, 0);
   nOut = 0;
   for(int p = 0; p < np; p++)
   {
      for(int t = piv[p].confirmIdx + 1; t < s.n; t++)
      {
         bool cross = (piv[p].kind > 0) ? (s.c[t] > piv[p].price && s.c[t - 1] <= piv[p].price)
                                        : (s.c[t] < piv[p].price && s.c[t - 1] >= piv[p].price);
         if(!cross)
            continue;
         ArrayResize(out, nOut + 1, 64);
         out[nOut].pivIdx = p;
         out[nOut].idx = t;
         out[nOut].dir = (piv[p].kind > 0) ? 1 : -1;
         out[nOut].level = piv[p].price;
         out[nOut].close = s.c[t];
         nOut++;
         break;
      }
   }
   // keep the newest maxEvents
   if(maxEvents > 0 && nOut > maxEvents)
   {
      for(int i = 0; i < nOut - 1; i++)
         for(int j = i + 1; j < nOut; j++)
            if(out[j].idx > out[i].idx)
            {
               NqSwingBreak tmp = out[i];
               out[i] = out[j];
               out[j] = tmp;
            }
      ArrayResize(out, maxEvents);
      nOut = maxEvents;
   }
}

//--- day VWAP on closed bars: sum(typical x volume) / sum(volume) from the
//    first bar of the server day. 0.0 before any volume.
void NqCalcDayVwap(const NqSeries &s, double &vwap[])
{
   int n = s.n;
   ArrayResize(vwap, n);
   int day = -1;
   double pv = 0.0;
   double vv = 0.0;
   for(int i = 0; i < n; i++)
   {
      int d = NqDayOf(s.t[i]);
      if(d != day)
      {
         day = d;
         pv = 0.0;
         vv = 0.0;
      }
      double tp = (s.h[i] + s.l[i] + s.c[i]) / 3.0;
      double vol = (s.v[i] > 0.0) ? s.v[i] : 1.0;
      pv += tp * vol;
      vv += vol;
      vwap[i] = (vv > 0.0) ? pv / vv : 0.0;
   }
}

string NqNyStateText(int st)
{
   switch(st)
   {
      case NQ_NY_NONE:      return "NO NY";
      case NQ_NY_OPEN:      return "RANGE BUILDING";
      case NQ_NY_SWEPT:     return "SWEPT";
      case NQ_NY_RETURNED:  return "RETURNED INSIDE";
      case NQ_NY_CONFIRMED: return "TRAP CONFIRMED";
      case NQ_NY_DONE:      return "SESSION DONE";
   }
   return "";
}

// distance from the live price to a limit level, in ATR units (negative = past it)
double NqDistAtr(int dir, double entry, double bid, double ask, double atr)
{
   if(atr <= 0.0)
      return 0.0;
   double d = (dir > 0) ? (ask - entry) : (entry - bid);
   return d / atr;
}

// the same for a STOP order, which sits on the other side of the price
double NqDistAtrStop(int dir, double entry, double bid, double ask, double atr)
{
   if(atr <= 0.0)
      return 0.0;
   double d = (dir > 0) ? (entry - ask) : (bid - entry);
   return d / atr;
}

//--- index of the newest plan of `kind` that is ACTIVE or FILLED (-1 none)
int NqLatestPlan(const NqPlan &plans[], int nPlans, int kind)
{
   for(int k = nPlans - 1; k >= 0; k--)
      if(plans[k].kind == kind && (plans[k].status == NQ_PL_ACTIVE || plans[k].status == NQ_PL_FILLED))
         return k;
   return -1;
}

int NqLatestPlanDir(const NqPlan &plans[], int nPlans, int kind, int dir)
{
   for(int k = nPlans - 1; k >= 0; k--)
      if(plans[k].kind == kind && plans[k].dir == dir && (plans[k].status == NQ_PL_ACTIVE || plans[k].status == NQ_PL_FILLED))
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
      if(plans[k].status == NQ_PL_TP1 || plans[k].status == NQ_PL_SL || plans[k].status == NQ_PL_FILLED || plans[k].status == NQ_PL_FALSE)
         filled++;
      if(plans[k].status == NQ_PL_TP1)
         won++;
      if(plans[k].status == NQ_PL_SL || plans[k].status == NQ_PL_FALSE)
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

//--- CLOCK. Sessions are defined where they live (New York 09:30-16:00,
//    London 08:00, the Asian book from 22:00 UTC) and converted to the
//    broker's clock with its LIVE GMT offset (TimeTradeServer - TimeGMT:
//    two witnesses, never an assumed number). US and EU daylight-saving
//    rules are computed, so the server hour of the NY open is right in both
//    seasons and on any broker clock. Pure arithmetic, no terminal call.
struct NqClock
{
   int      offsetMin;    // server clock minus GMT, to the half hour
   bool     usDst;        // New York on daylight time
   bool     euDst;        // London on daylight time
   int      nyS;          // server minutes of the day
   int      nyE;
   int      lonS;         // London open; London ends at the NY open
   int      asiaS;
   int      asiaE;        // = London open
   int      preS;         // pre-NY range start (the server day start)
   int      roll;         // the daily rollover (17:00 New York)
   int      nyS0;         // the same minutes UNCLAMPED: a session may wrap the server midnight (start > end)
   int      nyE0;
   int      lonS0;
   int      asiaS0;
   int      asiaE0;
};

// civil date of a UTC timestamp (days since 1970-01-01)
void NqCivil(datetime t, int &y, int &m, int &d)
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

long NqDaysFromCivil(int y, int m, int d)
{
   long yy = (m <= 2) ? y - 1 : y;
   long era = ((yy >= 0) ? yy : yy - 399) / 400;
   long yoe = yy - era * 400;
   long mm = m;
   long doy = (153 * (mm + ((mm > 2) ? -3 : 9)) + 2) / 5 + d - 1;
   long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
   return era * 146097 + doe - 719468;
}

// 0 = Sunday ... 6 = Saturday (1970-01-01 was a Thursday)
int NqDow(datetime t)
{
   return (int)(((long)t / 86400 + 4) % 7);
}

// day of month of the n-th Sunday (n = 1..4) or the last Sunday (n = 0)
int NqSundayOf(int y, int m, int n)
{
   long d1 = NqDaysFromCivil(y, m, 1);
   int dow1 = (int)((d1 + 4) % 7);
   int firstSun = 1 + ((7 - dow1) % 7);
   if(n >= 1)
      return firstSun + 7 * (n - 1);
   int ny = (m == 12) ? y + 1 : y;
   int nm = (m == 12) ? 1 : m + 1;
   int dim = (int)(NqDaysFromCivil(ny, nm, 1) - d1);
   int last = firstSun;
   while(last + 7 <= dim)
      last += 7;
   return last;
}

// US daylight time: second Sunday of March 07:00 UTC to first Sunday of November 06:00 UTC
bool NqUsDst(datetime utc)
{
   int y = 0;
   int m = 0;
   int d = 0;
   NqCivil(utc, y, m, d);
   datetime a = (datetime)(NqDaysFromCivil(y, 3, NqSundayOf(y, 3, 2)) * 86400 + 7 * 3600);
   datetime b = (datetime)(NqDaysFromCivil(y, 11, NqSundayOf(y, 11, 1)) * 86400 + 6 * 3600);
   return (utc >= a && utc < b);
}

// EU daylight time: last Sunday of March 01:00 UTC to last Sunday of October 01:00 UTC
bool NqEuDst(datetime utc)
{
   int y = 0;
   int m = 0;
   int d = 0;
   NqCivil(utc, y, m, d);
   datetime a = (datetime)(NqDaysFromCivil(y, 3, NqSundayOf(y, 3, 0)) * 86400 + 3600);
   datetime b = (datetime)(NqDaysFromCivil(y, 10, NqSundayOf(y, 10, 0)) * 86400 + 3600);
   return (utc >= a && utc < b);
}

// inside a window of the day that may wrap midnight (start > end)
bool NqInWindow(int mod, int s, int e)
{
   if(s == e)
      return false;
   if(s < e)
      return (mod >= s && mod < e);
   return (mod >= s || mod < e);
}

int NqServerMin(int utcMin, int offsetMin)
{
   int m = (utcMin + offsetMin) % 1440;
   if(m < 0)
      m += 1440;
   return m;
}

// the day's session minutes on the SERVER clock. false = the sessions wrap
// the server day in a way the day-bound engine cannot hold (an exotic broker
// clock): the caller falls back to its manual inputs and says so. The *0 fields
//    keep the true windows for callers that can hold a wrap (the forex session gate).
bool NqClockFromGmt(datetime utcNow, long offsetSec, NqClock &c)
{
   c.usDst = NqUsDst(utcNow);
   c.euDst = NqEuDst(utcNow);
   c.offsetMin = (int)MathRound(offsetSec / 1800.0) * 30;
   int nyOpenUtc = c.usDst ? 13 * 60 + 30 : 14 * 60 + 30;   // 09:30 New York
   int nyCloseUtc = c.usDst ? 20 * 60 : 21 * 60;            // 16:00 New York
   int rollUtc = c.usDst ? 21 * 60 : 22 * 60;               // 17:00 New York
   int lonOpenUtc = c.euDst ? 7 * 60 : 8 * 60;               // 08:00 London
   int asiaOpenUtc = 22 * 60;                                // Sydney / Tokyo: the Asian book
   c.nyS = NqServerMin(nyOpenUtc, c.offsetMin);
   c.nyE = NqServerMin(nyCloseUtc, c.offsetMin);
   c.lonS = NqServerMin(lonOpenUtc, c.offsetMin);
   c.asiaS = NqServerMin(asiaOpenUtc, c.offsetMin);
   c.asiaE = c.lonS;
   c.roll = NqServerMin(rollUtc, c.offsetMin);
   c.preS = 0;
   c.nyS0 = c.nyS;                  // the true windows, kept for wrap-aware callers (the forex clock)
   c.nyE0 = c.nyE;
   c.lonS0 = c.lonS;
   c.asiaS0 = c.asiaS;
   c.asiaE0 = c.asiaE;
   if(c.nyE <= c.nyS)
      c.nyE = 1440;                 // NY runs into the server midnight: it ends with the day
   if(c.asiaS >= c.asiaE)
      c.asiaS = 0;                  // Asia started before the server midnight: its part after it
   if(c.asiaE <= c.asiaS || c.lonS >= c.nyS || c.nyS <= 0)
      return false;
   return true;
}

// position in the trading week on the server clock: the week opens at the
// Sunday rollover (17:00 New York) and closes at the Friday one. Minutes
// since the open and until the close; false = the weekend.
bool NqWeekPos(int dow, int mod, int rollMin, int &sinceOpen, int &untilClose)
{
   int weekMin = dow * 1440 + mod;
   int openMin = ((rollMin >= 720) ? 0 : 1440) + rollMin;
   int closeMin = ((rollMin >= 720) ? 5 : 6) * 1440 + rollMin;
   sinceOpen = weekMin - openMin;
   untilClose = closeMin - weekMin;
   return (weekMin >= openMin && weekMin < closeMin);
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
      case NQ_K_REAL_ACCOUNT:   return "REAL ACCOUNT NOT ALLOWED";
      case NQ_K_TRADE_DISABLED: return "ALGO TRADING OFF";
      case NQ_K_AUTO_OFF:       return "AUTO TRADE OFF";
      case NQ_K_DAILY_CAP:      return "DAILY LOSS CAP HIT";
      case NQ_K_MAX_TRADES:     return "MAX TRADES TODAY";
      case NQ_K_MAX_POS:        return "MAX POSITIONS";
      case NQ_K_SESSION:        return "OUTSIDE SESSION";
      case NQ_K_SPREAD:         return "SPREAD TOO WIDE";
      case NQ_K_STOPS_LEVEL:    return "SL/TP INSIDE STOPS LEVEL";
      case NQ_K_LOT_TOO_SMALL:  return "MIN LOT RISKS TOO MUCH";
      case NQ_K_MARGIN:         return "NO FREE MARGIN";
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
      case NQ_PL_FALSE:    return "FALSE BREAK";
   }
   return "";
}

string NqPlanKindText(int kind)
{
   if(kind == NQ_PLAN_QML)
      return "QML";
   if(kind == NQ_PLAN_NY)
      return "NY TRAP";
   if(kind == NQ_PLAN_RADAR)
      return "RADAR";
   if(kind == NQ_PLAN_SCALP)
      return "SCALP";
   return "PULLBACK";
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
const string NQ_CMT_NY    = "NQ-N";
const string NQ_CMT_SWQ   = "NQ-K";
const string NQ_CMT_SWP   = "NQ-L";
const string NQ_CMT_RD    = "NQ-R";
#define NQ_BOARD_BROKER_ROWS 6
#define NQ_PLAN_SLOTS 7
#define NQ_RGB(r, g, b) ((color)((r) | ((g) << 8) | ((b) << 16)))

enum ENUM_NQ_CORNER
{
   NQ_TOP_LEFT = 0,     // Top left
   NQ_BOTTOM_LEFT = 2   // Bottom left
};

enum ENUM_NQ_LAYOUT
{
   NQ_LAYOUT_SPLIT = 0,   // Trading board top-left, INFORMATION DESK bottom-middle: the chart stays in full view
   NQ_LAYOUT_ONE   = 1    // One column: the engine table above the board (the former layout)
};

enum ENUM_NQ_BOND
{
   NQ_BOND_AUTO  = 0,   // AUTO: NOTE/BOND/BUND/ZN = a price, US10Y / YIELD = a yield
   NQ_BOND_PRICE = 1,   // The bond symbol is a PRICE (up = yields down = metal up)
   NQ_BOND_YIELD = 2    // The bond symbol is a YIELD (up = metal down)
};

// volatility regime (terminal layer; the engine never sees it)
#define NQ_VOL_UNKNOWN   0
#define NQ_VOL_DEAD      1
#define NQ_VOL_NORMAL    2
#define NQ_VOL_EXPANSION 3
#define NQ_VOL_EXTREME   4
// two gate bits beyond the engine's NQ_K_* (named by NqGateAtX, OR-ed into g_gate after the engine's gate)
#define NQ_K_VOL_DEAD    0x800
#define NQ_K_VOL_EXTREME 0x1000
// v1.9 gate bits (news, the week, the portfolio) - named by NqGateAtX after the regime bits
#define NQ_K_NEWS         0x2000
#define NQ_K_NEWS_UNKNOWN 0x4000
#define NQ_K_ROLLOVER     0x10000
#define NQ_K_WEEK_EDGE    0x20000
#define NQ_K_PORTFOLIO    0x40000

input group "Engine (M15 context / M5 regime / M1 trigger are fixed)"
input int            InpNrtrAtrPeriod    = 14;          // NRTR ATR period
input double         InpNrtrMultiplier   = 2.0;         // NRTR ATR multiplier
input int            InpEmaSlow          = 200;         // M15 context EMA
input int            InpEmaFast          = 20;          // Fast EMA (M1 filter + forecast)
input int            InpSwingStrength    = 3;           // Structure lookback: bars each side of a swing
input int            InpHistoryDays      = 8;           // History used (days)
input group "Auto scalp (market order on the M1 trigger)"
input bool           InpScalpAuto        = true;        // Auto scalp (lowest priority: only when no plan order is waiting)
input double         InpScalpSlAtr       = 1.5;         // Scalp SL = x ATR(M5)  (1.5 validated)
input double         InpScalpTpAtr       = 1.0;         // Scalp TP = x ATR(M5)  (1.0 validated ladder)
input int            InpScalpValidBars   = 2;           // Trigger actionable for (M1 bars)
input int            InpScalpTimeStop    = 45;          // Scalp time stop (M1 bars)
input bool           InpScalpCloseOnFlip = true;        // Close a scalp when the M5 regime turns against it
input bool           InpPlanCloseOnFlip  = false;       // Also close QML/pullback/NY/swing positions when the M5 regime turns (else the board says EXIT and you decide)
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
input double         InpPlanMinRiskAtr   = 1.0;         // A plan's stop at least x ATR away (a structural stop inside the noise is pushed out; TP1/TP2 follow); 0 = off
input bool           InpTradeQml         = true;        // Trade M5 QML plans
input bool           InpTradePullback    = true;        // Trade M5 pullback plans
input bool           InpTradeNyTrap      = true;        // Trade NY trap plans
input bool           InpTradeSwing       = true;        // Trade M15 swing plans (QML + pullback)
input bool           InpTradeRadar       = true;        // Trade IMPULSE RADAR plans (STOP orders beyond the nearest level)
input double         InpRadarBufAtr      = 0.15;        // Radar stop order: buffer beyond the level (x ATR5)
input group "Macro vote (dollar index, a US 10-year bond, the news, H4 / H1): a strong vote AGAINST a trade blocks it unless the metal's own structure is A+"
input bool           InpMacroGate        = true;        // A strong macro vote AGAINST a trade blocks it (false = show the vote, gate nothing)
input int            InpMacroBlockLevel  = 2;           // ... strong = the vote against is at least this (every voter counts 1)
input int            InpMacroOverrideScore = 9;         // The metal's OWN A+ structure overrides it: M15 context + M5 regime agree, radar score at least this; 11 = never
input string         InpMacroSymbol      = "";          // Dollar index witness; empty = AUTO (USDX / DXY / USDOLLAR ...), "-" = off
input string         InpBondSymbol       = "";          // US 10-year bond witness; empty = AUTO (USTNOTE / TNOTE / US10Y ...), "-" = off
input ENUM_NQ_BOND   InpBondKind         = NQ_BOND_AUTO; // The bond symbol is a PRICE (up = yields down = metal up) or a YIELD (up = metal down)
input int            InpHtfBars          = 400;         // Closed H1 / H4 bars loaded for the higher-timeframe witnesses (EMA200 needs 200+)
input int            InpHtfChochBars     = 12;          // An H1 CHoCH within the last N H1 bars votes its direction (fresh change of character); 0 = off
input int            InpNewsVoteHours    = 4;           // USD releases of the last N hours vote (the calendar's own POSITIVE / NEGATIVE reading); 0 = off
input group "News guard (USD events on the MT5 economic calendar - built in, no network, no DLL)"
input bool           InpNewsGuard        = true;        // Close the gate around HIGH-impact USD events and pull resting orders
input int            InpNewsBeforeMin    = 30;          // ... from N minutes before the event
input int            InpNewsAfterMin     = 30;          // ... to N minutes after it
input int            InpNewsTopBeforeMin = 60;          // TOP TIER (FOMC, rate decisions, NFP, CPI, GDP, pressers): from N minutes before
input int            InpNewsTopAfterMin  = 60;          // ... to N minutes after
input double         InpNewsBankProfitR  = 0.2;         // When a window opens, a position at least this many R in profit is closed (banked); 0 = never
input bool           InpNewsMediumBlocks = false;       // MODERATE-impact events close the gate too (false = shown only)
input bool           InpNewsUnknownBlocks = true;       // A calendar that answers nothing = NEWS UNKNOWN = no new trade (false = trade blind, at your choice)
input group "Week edges + rollover (from the AUTO clock: the week opens / closes at 17:00 New York)"
input int            InpRolloverGuardMin = 15;          // No new trade from N minutes before the daily rollover to N minutes after (spreads widen)
input int            InpFridayStopMin    = 120;         // No new trade in the last N minutes before the Friday close; resting orders are pulled then
input bool           InpWeekendFlat      = true;        // At the Friday stop close every position that is in profit (losers keep their SL unless the next input)
input double         InpWeekendMinProfitR = 0.0;        // ... in profit = at least this many R (0 = any non-negative result)
input bool           InpWeekendCloseLosers = false;     // At the Friday stop close losing positions too (no weekend gap risk at all)
input int            InpWeekOpenGuardMin = 60;          // No new trade in the first N minutes after the week opens
input group "Smart exit (intelligent management: bank on a bias change, lock profit, never wait for the SL blindly)"
input bool           InpSmartExit        = true;        // Manage open positions on bias changes (below) instead of leaving everything to the SL / TP
input double         InpSmartFlipProfitR = 0.1;         // M5 regime flipped against a position at least this many R in profit: close and bank it
input bool           InpSmartFlipCutLoss = true;        // M5 regime flipped against a position under water: close now (a smaller loss than the SL); false = the SL decides
input double         InpSmartM1ProfitR   = 0.5;         // M1 bias turned against a position at least this many R in profit: close and bank it (0 = off)
input double         InpSmartLockAtR     = 0.7;         // Once a position is this many R in profit, move the SL to ... (0 = off)
input double         InpSmartLockR       = 0.1;         // ... entry + this many R (tightened only, never loosened)
input group "Portfolio (this EA on several charts with the same magic)"
input int            InpMaxOpenAcrossCharts = 2;        // Max open positions of this EA across ALL charts (0 = unlimited)
input group "Clock (sessions live in New York / London / Asia time; AUTO converts them with the broker's live GMT offset)"
input bool           InpClockAuto        = true;        // AUTO: NY 09:30-16:00, London 08:00, Asia 22:00 UTC from TimeTradeServer-TimeGMT + US/EU DST; false = the server hours below
input group "NY trap + swing (server hours - used when InpClockAuto = false)"
input int            InpNyStartHour      = 16;          // NY open, server hour   (EET broker: 16:30 all year)
input int            InpNyStartMin       = 30;          // NY open, server minute
input int            InpNyEndHour        = 23;          // NY close, server hour
input int            InpNyEndMin         = 0;           // NY close, server minute
input int            InpRangeStartHour   = 0;           // Pre-NY range starts at (server hour)
input int            InpAsiaStartHour    = 1;           // Asia session start (server hour)   EET: 01:00
input int            InpAsiaEndHour      = 10;          // Asia session end (server hour)     EET: 10:00 = London open
input int            InpLondonStartHour  = 10;          // London session start (server hour); it ends at the NY open
input bool           InpDrawLevels       = true;        // Draw session highs/lows, previous day, VWAP and break marks
input int            InpSwingValidBars   = 96;          // Swing plan lifetime (M15 bars)  96 = 24 hours
input double         InpNearAtr          = 0.5;         // "NEAR" when the price is within x ATR5 of a limit
input group "Volatility regime + spike guard (news days: no chasing, no fake pullbacks)"
input bool           InpVolGate          = true;        // Gate NEW entries on the regime (false = classify and show only)
input int            InpVolAvgBars       = 288;         // ATR(M5) average over N closed M5 bars (288 = 24 h)
input double         InpVolDead          = 0.5;         // DEAD below x the average: no new trade
input double         InpVolExpand        = 1.5;         // EXPANSION from x: a breakout needs InpVolExpandRadar, a scalp needs the M15 context
input double         InpVolExtreme       = 2.5;         // EXTREME from x: no new trade until a fresh confirmed M5 swing forms after it ends
input int            InpVolExpandRadar   = 8;           // Radar score (of 10) a breakout needs during EXPANSION
input bool           InpVolExpandScalpM15 = true;       // During EXPANSION a scalp needs the M15 context on its side
input bool           InpSpikeGuard       = true;        // Spike guard: no pullback / scalp / breakout entry in the direction of a spike; EXIT WARNING on the way back
input int            InpSpikeBars        = 12;          // A spike = the last N closed M5 bars (12 = 1 h) ...
input double         InpSpikeX           = 2.5;         // ... ranging at least x a NORMAL N-bar range (its average over the regime lookback)
input double         InpSpikeRetrace     = 0.5;         // EXIT WARNING once the close has given back this share of the spike
input group "Risk engine (explicit - the EA never widens these)"
input double         InpRiskPct          = 0.5;         // Risk per trade (% of balance)
input double         InpDailyLossCapPct  = 2.0;         // Daily loss cap (% of balance) stops new trades; 0 = off
input int            InpMaxOpenPositions = 1;           // Max open positions (ONE SLOT per asset is enforced regardless)
input int            InpMaxTradesPerDay  = 0;           // Max entries per day (0 = unlimited)
input int            InpMaxSpreadPoints  = 50;          // Max spread (points)
input int            InpSessionStartHour = 0;           // Session start (server hour); 0-24 = trade round the clock
input int            InpSessionEndHour   = 24;          // Session end (server hour)
input bool           InpAllowRealAccount = true;        // Trade on a REAL account (false = demo only). The MT5 Algo Trading button is the on/off switch
input int            InpMagic            = 180915;      // Magic number
input int            InpSlippagePoints   = 20;          // Max slippage (points)
input group "SignalMesh journal (every plan event, append-only)"
input bool           InpJournalToFile    = true;        // Append every event to MQL5/Files/NQ_events_<symbol>.jsonl
input string         InpSignalMeshUrl    = "";          // POST events here (e.g. https://app.signalmesh.dev/webhooks/brain/signal); empty = off
input string         InpSignalMeshSecret = "";          // X-Brain-Secret for that URL (never printed). Allow the URL in Tools > Options > Expert Advisors
input group "SignalMesh telemetry (ANALYSIS ONLY - a data witness for the METAL ANALYSIS page, never a signal)"
input string         InpTelemetryUrl     = "";          // POST a state snapshot here (e.g. https://app.signalmesh.dev/webhooks/metal/telemetry); empty = off
input int            InpTelemetrySec     = 60;          // Heartbeat every N seconds, and on every closed M1 candle (min 5)
input bool           InpTelemetryDemoOnly = true;       // Send telemetry from a DEMO account only: a REAL account is never the witness
input group "Forecast arrows"
input int            InpForecastMinScore = 3;           // Votes needed for a bias arrow (1-5); 3 = strong, one-sided
input int            InpArrowBars        = 300;         // Arrows drawn on the last N candles
input group "Display"
input double         InpPanelScale       = 1.0;         // Panel size (0.7 - 1.6)
input ENUM_NQ_CORNER InpPanelCorner      = NQ_TOP_LEFT; // Panel position (the trading board)
input ENUM_NQ_LAYOUT InpPanelLayout      = NQ_LAYOUT_SPLIT; // Panel layout: SPLIT = trading board top-left + information desk bottom-middle; ONE = one column
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
NqSeries g_s15r;       // M15 run as a regime series (swing plans, read-only)
NqSeries g_ctxEmpty;   // nothing above M15
NqPivot  g_piv15r[];
NqPlan   g_swing[];
int      g_nSwing;
NqPlan   g_ny[];
int      g_nNy;
NqNyState g_nyState;
NqLevels g_levels;
NqBreak  g_brk[];
int      g_nBrk;
double   g_resAbove[];
double   g_supBelow[];
NqPlan   g_radar[];
int      g_nRadar;
NqRadar  g_rdUp;
NqRadar  g_rdDn;
int      g_macroDir;   // M15 NRTR direction of the dollar-index witness (0 = none / not available)
string   g_macroSym;   // the dollar-index symbol in force ("" = none)
string   g_bondSym;    // the bond witness ("" = none) and its M15 NRTR direction
int      g_bondDir;
bool     g_bondYield;  // the bond symbol is a yield (else a price)
// the switches the tests flip; the inputs are the source of truth at OnInit
bool     g_macroGate;
bool     g_newsGuard;
bool     g_newsUnknownBlocks;
bool     g_newsMediumBlocks;
bool     g_clockGuards;
bool     g_smartExit;
// the calendar: USD events in a 3-day window (MODERATE and HIGH)
datetime g_evT[];
string   g_evCcy[];
int      g_evImp[];
string   g_evName[];
int      g_evImpact[];  // the calendar's reading once released: +1 positive for the dollar, -1 negative, 0 none / not released
bool     g_evTop[];     // top tier (FOMC, rate decisions, NFP, CPI ...)
int      g_nEv;
bool     g_newsOk;      // the calendar answered with events: from here "no event" means no event
int      g_newsErr;     // GetLastError() of the last failed calendar call (0 = none)
bool     g_newsTester;  // the Strategy Tester has no calendar
bool     g_newsBlock;   // inside a guarded window right now
bool     g_newsUnknown;
string   g_newsText;    // the NEWS panel row
string   g_newsWhy;     // the gate's words
datetime g_newsReadT;   // when the calendar was last read
datetime g_newsWinT;    // the event whose window is open (0 = none)
// the week and the rollover
int      g_sessOpen;    // bit set: 1 Asia, 2 London, 4 NY
bool     g_rollover;
bool     g_weekEdge;
bool     g_weekFriday;  // the Friday stop is in force (orders pulled, profits banked)
string   g_weekText;
int      g_dow;
// the portfolio: this EA on every chart (same magic)
int      g_portfolioPos;
bool     g_portfolioFull;
string   g_smartNote;   // the last smart-exit action (panel)
// higher timeframes: H1 and H4 context (EMA200 + NRTR), confirmed structure and its breaks (BOS / CHoCH)
NqSeries g_h1;
NqSeries g_h4;
NqPivot  g_pivH1[];
NqPivot  g_pivH4[];
NqSwingBreak g_sbH1[];
NqSwingBreak g_sbH4[];
int      g_nSbH1;
int      g_nSbH4;
bool     g_h1Ok;
bool     g_h4Ok;
NqClock  g_clk;        // the session minutes in force (AUTO from the GMT offset, or the manual inputs)
bool     g_clkAuto;    // AUTO succeeded
string   g_clkText;    // what the panel says about the clock
int      g_volClass;   // NQ_VOL_*: ATR(M5) against its own average
double   g_volRatio;   // ATR(M5) / average
double   g_volAvg;     // the average ATR(M5) itself
datetime g_volExtremeEndT; // M5 bar time of the last EXTREME reading
bool     g_volWaitFresh;   // after EXTREME: closed until a confirmed M5 swing forms after it
int      g_spikeDir;   // spike in the last InpSpikeBars M5 bars: +1 up, -1 down, 0 none
double   g_spikeAtr;   // its range in average-ATR units (display)
double   g_spikeX;     // its range against a normal InpSpikeBars-bar range (the test)
double   g_spikeNorm;  // a normal InpSpikeBars-bar range: the average over the regime lookback
double   g_spikeRetr;  // share of the spike the latest close has given back (0..1)
bool     g_spikeWarn;  // retrace >= InpSpikeRetrace: EXIT WARNING for a position in the spike direction
bool     g_warnOn;     // the verdict is an EXIT WARNING right now (chart marker)
bool     g_boardCollapsed;   // the trading board folded to its banner (click the title)
bool     g_deskCollapsed;    // the information desk folded to its header (click the header)
bool     g_newBar5;
NqSwingBreak g_sbrk[];
int      g_nSbrk;
// journal: last known status per plan (by signal id) so only CHANGES are emitted
#define NQ_EA_VERSION "1.9.3"
string   g_jrCmt[];
int      g_jrStatus[];
int      g_jrN;
bool     g_jrSeeded;
string   g_webUrl;      // from the input; a test may point it elsewhere
string   g_webSecret;
string   g_webQ[];      // events the platform has not accepted yet
int      g_webN;
datetime g_webLast;
int      g_webFails;
bool     g_jrFileWarned;
// telemetry (ANALYSIS ONLY): a heartbeat snapshot of the panel's state for the
// SignalMesh METAL ANALYSIS page. It reads state and sends it; it never
// changes a decision, a level or an order, and a failed POST is a Print.
string   g_telUrl;
int      g_telSec;
bool     g_telDemoOnly;
datetime g_telLast;
int      g_telFails;
int      g_telSent;
bool     g_telWarned;
datetime g_labelT;     // where level labels are drawn: the latest closed M1 bar (always on screen)
// the verdict for the human, recomputed every second
string   g_verdict;
color    g_verdictClr;
string   g_nearText;   // "" when nothing is near
double   g_nearPrice;
int      g_nearDir;
double   g_vwap1[];    // day VWAP per closed M1 bar
string   g_rejCmt;     // last rejected pending order (comment) and its retcode
int      g_rejCode;
datetime g_seen15;
datetime g_seen5;
datetime g_seen1;
bool     g_ready;
int      g_dataR;
bool     g_newBar1;

// account view (this EA's magic, this symbol)
int      g_manualPos;   // positions / orders on this symbol that are NOT this EA's: never touched
int      g_manualOrd;
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
bool   NqPlanIsStop(const NqPlan &p);
long   NqPlanOrderType(const NqPlan &p);
void   NqVerdict();
void   NqDrawNear();
bool   NqSlotPlan(int q, NqPlan &out);
bool   NqKindEnabled(const NqPlan &p);
ulong  NqFindPlanOrder(const NqPlan &p);
string NqKindOfComment(string cmt);
double NqDistAtrStop(int dir, double entry, double bid, double ask, double atr);
void   NqText(string name, datetime t, double price, string txt, color clr, int size, int anchor, string tip);
bool   NqIsOurs(long magic, string sym);
string NqMoney(double v);
void   NqEmitBroker(string comment, string event, string extra);
void   NqWebDrain();
void   NqTelemetry();
string NqTelemetryJson();
void   NqScalpAsPlan(int k, NqPlan &p);
void   NqJournalScan();
bool   NqPlanByComment(string cmt, NqPlan &out);
string NqJsonS(string key, string val);
string NqJsonN(string key, double val, int digits);
string NqJsonI(string key, long val);
void   NqVolRegime();
void   NqReadClock();
int    NqVolGateBits();
string NqVolClassText(int c);
string NqGateAtX(int g, int nth);
string NqGateNameX(int bit);
void   NqSpikeScan();
bool   NqSpikeBlocks(const NqPlan &pl);
bool   NqMacroBlocks(int dir, int score, bool isRadar, string &why);
int    NqMacroVote(int d, string &why);
void   NqResolveWitnesses();
void   NqReadWitnesses();
void   NqReadCalendar();
void   NqNewsState();
void   NqSessionScan(datetime now);
void   NqPortfolioScan();
int    NqMetalGateBits();
void   NqReadHtf();
string NqBreakText(const NqSeries &s, const NqSwingBreak &sb[], int n);
string NqBreakKind(const NqSeries &s, const NqSwingBreak &b);
string NqSessionName();
bool   NqSmartExit(ulong tk, int pdir, string cmt, bool isScalp, int reg5);
bool   NqRegimeAgreedSince(datetime opened, int pdir);
double NqPosR(double open, double sl, double px, int pdir, string cmt);
bool   NqModifySl(ulong ticket, double sl, double tp, string why);
bool   NqSend(MqlTradeRequest &req, string why);
bool   NqClosePosition(ulong ticket, string why);
string NqJsonB(string key, bool val);
void   NqDrawWarn();
void   NqLabelOne(string id, int x, int y, string txt, color clr, int size, string font, int anchor);
int    NqSplitLabel(string txt, string &parts[]);

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpNrtrAtrPeriod < 1 || InpNrtrMultiplier <= 0.0 || InpEmaSlow < 2 || InpEmaFast < 2 ||
      InpSwingStrength < 1 || InpSwingStrength > 20 || InpHistoryDays < 3 || InpScalpSlAtr <= 0.0 ||
      InpScalpTpAtr <= 0.0 || InpScalpValidBars < 1 || InpScalpTimeStop < 1 || InpQmlSlBufAtr < 0.0 ||
      InpQmlWaitBars < 1 || InpPlanValidBars < 1 || InpPbRetrace <= 0.0 || InpPbRetrace >= 1.0 ||
      InpPbMinImpulseAtr < 0.0 || InpPbSlBufAtr < 0.0 || InpPlanTp1R <= 0.0 || InpPlanTp2R <= 0.0 || InpPlanMinRiskAtr < 0.0 ||
      InpRiskPct <= 0.0 || InpRiskPct > 5.0 || InpDailyLossCapPct < 0.0 || InpMaxOpenPositions < 0 ||
      InpMaxTradesPerDay < 0 || InpMaxSpreadPoints < 0 ||
      InpMacroBlockLevel < 1 || InpMacroOverrideScore < 0 || InpMacroOverrideScore > 11 || InpHtfBars < 50 || InpHtfChochBars < 0 ||
      InpNewsVoteHours < 0 || InpNewsBeforeMin < 0 || InpNewsAfterMin < 0 || InpNewsTopBeforeMin < 0 || InpNewsTopAfterMin < 0 ||
      InpNewsBankProfitR < 0.0 || InpRolloverGuardMin < 0 || InpRolloverGuardMin > 360 || InpFridayStopMin < 0 || InpFridayStopMin > 1440 ||
      InpWeekOpenGuardMin < 0 || InpWeekOpenGuardMin > 720 || InpMaxOpenAcrossCharts < 0 || InpSmartFlipProfitR < 0.0 || InpSmartM1ProfitR < 0.0 ||
      InpSmartLockAtR < 0.0 || InpSmartLockR < 0.0 || (InpSmartLockAtR > 0.0 && InpSmartLockR >= InpSmartLockAtR) ||
      InpVolAvgBars < 20 || InpVolDead <= 0.0 || InpVolDead >= InpVolExpand || InpVolExpand >= InpVolExtreme ||
      InpVolExpandRadar < 0 || InpVolExpandRadar > 10 || InpSpikeBars < 2 || InpSpikeX < 1.0 || InpSpikeRetrace <= 0.0 ||
      InpSpikeRetrace > 1.0 || InpSessionStartHour < 0 || InpSessionStartHour > 24 ||
      InpSessionEndHour < 0 || InpSessionEndHour > 24 || InpMagic <= 0 || InpForecastMinScore < 1 ||
      InpArrowBars < 0 || InpNyStartHour < 0 || InpNyStartHour > 23 || InpNyStartMin < 0 || InpNyStartMin > 59 ||
      InpNyEndHour < 0 || InpNyEndHour > 24 || InpNyEndMin < 0 || InpNyEndMin > 59 || InpRangeStartHour < 0 ||
      InpRangeStartHour > 23 || InpSwingValidBars < 1 || InpNearAtr < 0.0 || InpAsiaStartHour < 0 || InpAsiaStartHour > 23 ||
      InpAsiaEndHour < 1 || InpAsiaEndHour > 24 || InpAsiaStartHour >= InpAsiaEndHour || InpLondonStartHour < 0 ||
      InpLondonStartHour > 23 || InpLondonStartHour * 60 >= InpNyStartHour * 60 + InpNyStartMin ||
      InpNyStartHour * 60 + InpNyStartMin >= InpNyEndHour * 60 + InpNyEndMin ||
      InpRangeStartHour * 60 >= InpNyStartHour * 60 + InpNyStartMin)
   {
      Print("NQ: invalid inputs (risk per trade is capped at 5%)");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_sym = _Symbol;
   g_metal = NqMetalOf(g_sym, SymbolInfoString(g_sym, SYMBOL_CURRENCY_BASE),
                       SymbolInfoString(g_sym, SYMBOL_CURRENCY_PROFIT));
   NqReadSpec();
   // the switches the tests flip; the inputs are the source of truth
   g_macroGate = InpMacroGate;
   g_newsGuard = InpNewsGuard;
   g_newsUnknownBlocks = InpNewsUnknownBlocks;
   g_newsMediumBlocks = InpNewsMediumBlocks;
   g_clockGuards = true;
   g_smartExit = InpSmartExit;
   NqResolveWitnesses();

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
   g_P.planMinRiskAtr = InpPlanMinRiskAtr;
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
   NqSeriesResize(g_s15r, 0);
   NqSeriesResize(g_ctxEmpty, 0);
   g_ctxEmpty.sec = PeriodSeconds(PERIOD_M15);
   ArrayResize(g_ctxEmpty.ctx, 0);
   ArrayResize(g_swing, 0);
   g_nSwing = 0;
   ArrayResize(g_ny, 0);
   g_nNy = 0;
   NqNyReset(g_nyState, -1);
   NqLevelsReset(g_levels, -1);
   ArrayResize(g_brk, 0);
   g_nBrk = 0;
   ArrayResize(g_radar, 0);
   g_nRadar = 0;
   NqRadarReset(g_rdUp);
   NqRadarReset(g_rdDn);
   g_macroDir = 0;
   g_bondDir = 0;
   ArrayResize(g_evT, 0);
   ArrayResize(g_evCcy, 0);
   ArrayResize(g_evImp, 0);
   ArrayResize(g_evName, 0);
   ArrayResize(g_evImpact, 0);
   ArrayResize(g_evTop, 0);
   g_nEv = 0;
   g_newsOk = false;
   g_newsErr = 0;
   g_newsTester = false;
   g_newsBlock = false;
   g_newsUnknown = false;
   g_newsText = "";
   g_newsWhy = "";
   g_newsReadT = 0;
   g_newsWinT = 0;
   g_sessOpen = 0;
   g_rollover = false;
   g_weekEdge = false;
   g_weekFriday = false;
   g_weekText = "";
   g_dow = 0;
   g_portfolioPos = 0;
   g_portfolioFull = false;
   g_smartNote = "";
   NqSeriesResize(g_h1, 0);
   NqSeriesResize(g_h4, 0);
   ArrayResize(g_pivH1, 0);
   ArrayResize(g_pivH4, 0);
   ArrayResize(g_sbH1, 0);
   ArrayResize(g_sbH4, 0);
   g_nSbH1 = 0;
   g_nSbH4 = 0;
   g_h1Ok = false;
   g_h4Ok = false;
   g_clkAuto = false;
   g_clkText = "";
   NqReadClock();
   g_volClass = NQ_VOL_UNKNOWN;
   g_volRatio = 0.0;
   g_volAvg = 0.0;
   g_volExtremeEndT = 0;
   g_volWaitFresh = false;
   g_spikeDir = 0;
   g_spikeAtr = 0.0;
   g_spikeX = 0.0;
   g_spikeNorm = 0.0;
   g_spikeRetr = 0.0;
   g_spikeWarn = false;
   g_warnOn = false;
   g_boardCollapsed = false;
   g_deskCollapsed = false;
   g_newBar5 = false;
   ArrayResize(g_sbrk, 0);
   g_nSbrk = 0;
   ArrayResize(g_jrCmt, 0);
   ArrayResize(g_jrStatus, 0);
   g_jrN = 0;
   g_jrSeeded = false;
   g_webUrl = InpSignalMeshUrl;
   g_webSecret = InpSignalMeshSecret;
   ArrayResize(g_webQ, 0);
   g_webN = 0;
   g_webLast = 0;
   g_webFails = 0;
   g_jrFileWarned = false;
   g_telUrl = InpTelemetryUrl;
   g_telSec = (InpTelemetrySec < 5) ? 5 : InpTelemetrySec;
   g_telDemoOnly = InpTelemetryDemoOnly;
   g_telLast = 0;
   g_telFails = 0;
   g_telSent = 0;
   g_telWarned = false;
   g_labelT = 0;
   g_verdict = "";
   g_verdictClr = 0;
   g_nearText = "";
   g_nearPrice = 0.0;
   g_nearDir = 0;
   ArrayResize(g_vwap1, 0);
   g_rejCmt = "";
   g_rejCode = 0;
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
   // a click on the board's title folds the board to its banner; a click on the desk's header folds the desk
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == NQ_PFX_P + "title" || StringFind(sparam, NQ_PFX_P + "title~") == 0)
         g_boardCollapsed = !g_boardCollapsed;
      else if(sparam == NQ_PFX_P + "h1" || StringFind(sparam, NQ_PFX_P + "h1~") == 0)
         g_deskCollapsed = !g_deskCollapsed;
      else
         return;
      ObjectsDeleteAll(0, NQ_PFX_P);
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
   g_newBar5 = false;
   if(g_metal != NQ_METAL_NONE)
   {
      datetime t15 = iTime(g_sym, PERIOD_M15, 1);
      datetime t5 = iTime(g_sym, PERIOD_M5, 1);
      datetime t1 = iTime(g_sym, PERIOD_M1, 1);
      if(!g_ready || t15 != g_seen15 || t5 != g_seen5 || t1 != g_seen1)
      {
         g_newBar1 = (t1 != g_seen1);
         g_newBar5 = (t5 != g_seen5);
         g_seen15 = t15;
         g_seen5 = t5;
         g_seen1 = t1;
         NqRecompute();
         // MT5 draws newer objects on top: recreate the panel after the
         // chart objects so labels and arrows never cover it
         ObjectsDeleteAll(0, NQ_PFX_P);
      }
   }
   NqReadAccount();
   NqEvaluate();
   if(g_newBar1 && g_ready)
      NqTrade();
   NqVerdict();
   NqDrawNear();
   NqDrawWarn();
   NqWebDrain();
   NqTelemetry();
   NqDrawPanel();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| THE VERDICT: one line that says what to do now, for a human.      |
//| Priority: a running position (HOLD / EXIT) > a level within NEAR  |
//| distance > a scalp trigger > waiting orders > nothing.            |
//+------------------------------------------------------------------+
void NqVerdict()
{
   color cUp = NQ_RGB(46, 204, 113);
   color cDn = NQ_RGB(231, 76, 60);
   color cWait = NQ_RGB(241, 196, 15);
   color cBlock = NQ_RGB(230, 126, 34);
   g_nearText = "";
   g_nearPrice = 0.0;
   g_nearDir = 0;
   g_warnOn = false;
   bool ok = (g_metal != NQ_METAL_NONE && g_ready && g_s5.n > 0 && g_s1.n > 0);
   if(g_metal == NQ_METAL_NONE)
   {
      g_verdict = NqSymDot() + "  GOLD / SILVER ONLY";
      g_verdictClr = cWait;
      return;
   }
   if(!ok)
   {
      g_verdict = NqSymDot() + "  WAIT - " + NqReasonAt(g_finalR, 0);
      g_verdictClr = cWait;
      return;
   }
   if(!g_fresh)
   {
      g_verdict = NqSymDot() + "  DATA STALE / MARKET CLOSED";
      g_verdictClr = cWait;
      return;
   }
   bool manual = ((g_gate & NQ_K_TRADE_DISABLED) != 0);
   string pre = manual ? "MANUAL:  " : "";
   int reg = g_s5.regime[g_s5.n - 1];
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double atr5 = g_s5.atr[g_s5.n - 1];

   // 1) a running position of this EA
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(!NqIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
         continue;
      int pdir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      string side = (pdir > 0) ? "BUY" : "SELL";
      double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      string kind = NqKindOfComment(PositionGetString(POSITION_COMMENT));
      double pxNow = (pdir > 0) ? bid : ask;
      double rNow = NqPosR(PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL), pxNow, pdir, PositionGetString(POSITION_COMMENT));
      bool agreed = NqRegimeAgreedSince((datetime)PositionGetInteger(POSITION_TIME), pdir);
      string pl = "  P/L " + NqMoney(pr) + " (" + ((rNow >= 0.0) ? "+" : "") + DoubleToString(rNow, 2) + "R)  SL " + NqPx(PositionGetDouble(POSITION_SL)) + "  TP " + NqPx(PositionGetDouble(POSITION_TP));
      if(reg != NQ_REG_CHOP && reg != pdir)
      {
         bool smartWill = g_smartExit && agreed && (rNow >= InpSmartFlipProfitR || (InpSmartFlipCutLoss && kind != "scalp"));
         bool botWill = smartWill || ((kind == "scalp") ? InpScalpCloseOnFlip : (kind == "radar" ? false : InpPlanCloseOnFlip));
         g_verdict = pre + "EXIT " + side + " #" + IntegerToString((long)tk) + " - M5 REGIME FLIPPED " + NqRegimeText(reg) +
                     (botWill && !manual ? (smartWill ? ((rNow >= InpSmartFlipProfitR) ? "  (SMART EXIT banks it at the next M1 close)" : "  (SMART EXIT cuts it at the next M1 close)") : "  (bot closes at the next M1 close)")
                                         : (agreed ? "  (you decide)" : "  (you decide - the regime never agreed with this reversal trade, the plan runs on its SL/TP)")) + pl;
         g_verdictClr = cBlock;
      }
      else if(InpSpikeGuard && g_spikeWarn && g_spikeDir == pdir)
      {
         g_verdict = pre + "EXIT WARNING " + side + " #" + IntegerToString((long)tk) + " - SPIKE REVERSAL: the " +
                     DoubleToString(g_spikeAtr, 1) + " ATR " + ((pdir > 0) ? "up" : "down") + "-spike (" + DoubleToString(g_spikeX, 1) + "x a normal hour) gave back " +
                     IntegerToString((int)MathRound(g_spikeRetr * 100.0)) + "% (news?)  - you decide" + pl;
         g_verdictClr = (((long)TimeTradeServer() % 2) == 0) ? cBlock : clrWhite;   // flashes every second
         g_warnOn = true;
      }
      else
      {
         string smart = "";
         if(g_smartExit && InpSmartLockAtR > 0.0)
            smart = (rNow >= InpSmartLockAtR) ? "  SL locked" : ("  lock at +" + DoubleToString(InpSmartLockAtR, 1) + "R");
         g_verdict = pre + "HOLD " + side + " #" + IntegerToString((long)tk) + " (" + kind + ") - M5 " +
                     ((reg == NQ_REG_CHOP) ? "CHOP, no flip" : "regime intact") + pl + smart;
         g_verdictClr = (pdir > 0) ? cUp : cDn;
      }
      return;
   }

   // 2) the nearest waiting order / armed plan
   double bestD = 1e9;
   string bestT = "";
   double bestP = 0.0;
   int bestDir = 0;
   bool bestPlaced = false;
   for(int q = 0; q < NQ_PLAN_SLOTS; q++)
   {
      NqPlan pl;
      if(!NqSlotPlan(q, pl) || pl.status != NQ_PL_ACTIVE || !NqKindEnabled(pl))
         continue;
      double d = NqPlanIsStop(pl) ? NqDistAtrStop(pl.dir, pl.entry, bid, ask, atr5) : NqDistAtr(pl.dir, pl.entry, bid, ask, atr5);
      if(atr5 <= 0.0 || d < 0.0)
         continue;
      if(d < bestD)
      {
         bestD = d;
         string side = (pl.dir > 0) ? (NqPlanIsStop(pl) ? "BUY STOP " : "BUY LIMIT ") : (NqPlanIsStop(pl) ? "SELL STOP " : "SELL LIMIT ");
         bestT = NqPlanKindText(pl.kind) + ((pl.tf == 900) ? " M15 " : " ") + side + NqPx(pl.entry) + "  SL " + NqPx(pl.sl) +
                 "  TP " + NqPx(InpPlanUseTp2 ? pl.tp2 : pl.tp1);
         bestP = pl.entry;
         bestDir = pl.dir;
         bestPlaced = (NqFindPlanOrder(pl) != 0);
      }
   }
   if(bestT != "" && bestD <= InpNearAtr)
   {
      g_nearText = bestT;
      g_nearPrice = bestP;
      g_nearDir = bestDir;
      g_verdict = pre + NqSymDot() + " PRICE NEAR  " + bestT + "  (" + DoubleToString(bestD, 2) + " ATR)" +
                  (bestPlaced ? "  order waiting" : (manual ? "  PLACE IT NOW" : "  not placed yet"));
      g_verdictClr = clrWhite;
      return;
   }

   // 3) scalp trigger on the just-closed candle
   int st1 = g_s1.state[g_s1.n - 1];
   if(st1 == NQ_BUY || st1 == NQ_SELL)
   {
      int cur = g_s1.sigOf[g_s1.n - 1];
      string side = (st1 > 0) ? "BUY" : "SELL";
      g_verdict = pre + "SCALP " + side + " NOW  entry " + NqPx(g_sigs[cur].entry) + "  SL " + NqPx(g_sigs[cur].sl) + "  TP " +
                  NqPx(g_sigs[cur].tp) + ((g_gate != 0 && !manual) ? ("  (" + NqGateAtX(g_gate, 0) + ")") : (InpScalpAuto && !manual ? "  (auto)" : ""));
      g_verdictClr = (st1 > 0) ? cUp : cDn;
      return;
   }

   // 4) waiting
   if(bestT != "")
   {
      g_verdict = pre + "WAIT  -  " + IntegerToString(g_pendCount) + " order(s) waiting, nearest " + bestT + "  " +
                  DoubleToString(bestD, 1) + " ATR away";
      g_verdictClr = cWait;
   }
   else
   {
      g_verdict = pre + "WAIT  -  no setup armed  (M5 " + NqRegimeText(reg) + ", " + NqReasonAt(g_s1.reasons[g_s1.n - 1], 0) + ")";
      g_verdictClr = cWait;
   }
}

// a big, bright marker at the level the price is approaching (every second)
void NqDrawNear()
{
   string nm = NQ_PFX_A + "NEAR";
   if(g_nearText == "" || !InpDrawChart || !g_ready)
   {
      if(ObjectFind(0, nm) >= 0)
         ObjectsDeleteAll(0, nm);
      return;
   }
   datetime t = g_s1.t[g_s1.n - 1] + g_s1.sec;
   NqText(nm, t, g_nearPrice, NqSymDot() + " NEAR  " + g_nearText, clrWhite, 11, (g_nearDir > 0) ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER,
          "the price is within " + DoubleToString(InpNearAtr, 2) + " ATR of this level");
}

// a flashing EXIT WARNING marker on the chart while the verdict says so
void NqDrawWarn()
{
   string nm = NQ_PFX_A + "WARN";
   if(!g_warnOn || !InpDrawChart || !g_ready)
   {
      if(ObjectFind(0, nm) >= 0)
         ObjectsDeleteAll(0, nm);
      return;
   }
   datetime t = g_s1.t[g_s1.n - 1] + g_s1.sec;
   double px = SymbolInfoDouble(g_sym, SYMBOL_BID);
   color c = (((long)TimeTradeServer() % 2) == 0) ? NQ_RGB(230, 126, 34) : clrWhite;
   NqText(nm, t, px, NqSymDot() + " EXIT WARNING - SPIKE REVERSAL", c, 12, (g_spikeDir > 0) ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER,
          "a " + DoubleToString(g_spikeAtr, 1) + " ATR spike (" + DoubleToString(g_spikeX, 1) + "x a normal hour) has given back " + IntegerToString((int)MathRound(g_spikeRetr * 100.0)) +
          "% - a news reversal looks like this; you decide");
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
bool NqLoadSym(string sym, ENUM_TIMEFRAMES tf, NqSeries &s, int &why)
{
   int sec = PeriodSeconds(tf);
   s.sec = sec;
   int shift = iBarShift(sym, tf, g_anchor, false);
   if(shift < 0)
      shift = Bars(sym, tf) - 1;
   if(shift < 1)
   {
      NqSeriesResize(s, 0);
      why = NQ_R_NO_DATA;
      return false;
   }
   if(shift > 50000)
      shift = 50000;
   MqlRates r[];
   int got = CopyRates(sym, tf, 1, shift, r);
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
      s.v[i] = (double)r[i].tick_volume;
   }
   if(n < 2)
   {
      why = NQ_R_NO_DATA;
      return false;
   }
   return true;
}

bool NqLoad(ENUM_TIMEFRAMES tf, NqSeries &s, int &why)
{
   return NqLoadSym(g_sym, tf, s, why);
}

// the dollar-index witness: the M15 NRTR direction of the resolved symbol
void NqReadMacro()
{
   g_macroDir = 0;
   if(g_macroSym == "")
      return;
   NqSeries m;
   NqSeriesResize(m, 0);
   int why = 0;
   if(!NqLoadSym(g_macroSym, PERIOD_M15, m, why))
      return;
   NqCalcATR(m.h, m.l, m.c, m.n, g_P.atrPeriod, m.atr);
   NqCalcNRTR(m.c, m.atr, m.n, g_P.nrtrMult, m.dir, m.stop, m.ext, m.flip);
   if(m.n > 0)
      g_macroDir = m.dir[m.n - 1];
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
      g_nSwing = 0;
      ArrayResize(g_swing, 0);
      g_nNy = 0;
      ArrayResize(g_ny, 0);
      g_nRadar = 0;
      ArrayResize(g_radar, 0);
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
   // NY trap on M5, confirmed by the M5 NRTR (read-only plans)
   NqReadClock();
   NqRunNyTrap(g_s5, g_s5.dir, g_P, g_clk.preS, g_clk.nyS, g_clk.nyE, g_ny, g_nNy, g_nyState);
   // session levels, breaks (M5 closes) and the day VWAP (M1)
   NqRunLevels(g_s5, g_clk.asiaS, g_clk.asiaE, g_clk.lonS, g_clk.nyS, g_clk.preS, g_clk.nyS, g_clk.nyE,
               g_levels, g_brk, g_nBrk, g_resAbove, g_supBelow);
   NqCalcDayVwap(g_s1, g_vwap1);
   NqRunSwingBreaks(g_s5, g_piv5, g_s5.np, 24, g_sbrk, g_nSbrk);
   g_labelT = g_s1.t[g_s1.n - 1];
   // impulse radar: pre-break pressure per direction, STOP-order plans
   NqRunRadar(g_s5, g_piv5, g_s5.np, g_resAbove, g_supBelow, g_P, InpRadarBufAtr, g_radar, g_nRadar, g_rdUp, g_rdDn);
   NqReadWitnesses();      // the dollar index + the bond: M15 NRTR of each, NO DATA = no vote
   NqReadCalendar();       // the MT5 economic calendar, USD events
   NqReadHtf();            // H1 / H4 context, structure, BOS / CHoCH
   // swing plans: the same QML / pullback engine on M15 structure
   NqSeriesResize(g_s15r, g_s15.n);
   g_s15r.sec = g_s15.sec;
   for(int i = 0; i < g_s15.n; i++)
   {
      g_s15r.t[i] = g_s15.t[i];
      g_s15r.o[i] = g_s15.o[i];
      g_s15r.h[i] = g_s15.h[i];
      g_s15r.l[i] = g_s15.l[i];
      g_s15r.c[i] = g_s15.c[i];
      g_s15r.v[i] = g_s15.v[i];
   }
   NqRunRegime(g_s15r, g_piv15r, g_ctxEmpty, g_P);
   NqParams Pswing = g_P;
   Pswing.planValidBars = InpSwingValidBars;
   NqFindPlans(g_s15r, g_piv15r, g_s15r.np, Pswing, g_swing, g_nSwing);
   g_ready = true;
   NqDrawChart();
   NqJournalScan();
}

//+------------------------------------------------------------------+
//| account view: this EA's positions, orders, today's closed P/L    |
//+------------------------------------------------------------------+
string NqPlanPrefix(const NqPlan &p)
{
   if(p.kind == NQ_PLAN_NY)
      return NQ_CMT_NY;
   if(p.kind == NQ_PLAN_RADAR)
      return NQ_CMT_RD;
   if(p.kind == NQ_PLAN_QML)
      return (p.tf == 900) ? NQ_CMT_SWQ : NQ_CMT_QML;
   return (p.tf == 900) ? NQ_CMT_SWP : NQ_CMT_PB;
}

string NqPlanComment(const NqPlan &p)
{
   return NqPlanPrefix(p) + IntegerToString((long)p.keyTime);
}

// kind label from an order / position comment
string NqKindOfComment(string cmt)
{
   if(StringFind(cmt, NQ_CMT_SCALP) == 0)
      return "scalp";
   if(StringFind(cmt, NQ_CMT_QML) == 0)
      return "QML";
   if(StringFind(cmt, NQ_CMT_PB) == 0)
      return "pullback";
   if(StringFind(cmt, NQ_CMT_NY) == 0)
      return "NY trap";
   if(StringFind(cmt, NQ_CMT_SWQ) == 0)
      return "swing QML";
   if(StringFind(cmt, NQ_CMT_SWP) == 0)
      return "swing PB";
   if(StringFind(cmt, NQ_CMT_RD) == 0)
      return "radar";
   return "other";
}

bool NqIsPlanComment(string cmt)
{
   return (StringFind(cmt, NQ_CMT_QML) == 0 || StringFind(cmt, NQ_CMT_PB) == 0 || StringFind(cmt, NQ_CMT_NY) == 0 ||
           StringFind(cmt, NQ_CMT_SWQ) == 0 || StringFind(cmt, NQ_CMT_SWP) == 0 || StringFind(cmt, NQ_CMT_RD) == 0);
}

// is trading of this plan kind enabled by the inputs?
bool NqKindEnabled(const NqPlan &p)
{
   if(p.kind == NQ_PLAN_NY)
      return InpTradeNyTrap;
   if(p.kind == NQ_PLAN_RADAR)
      return InpTradeRadar;
   if(p.tf == 900)
      return InpTradeSwing;
   return (p.kind == NQ_PLAN_QML) ? InpTradeQml : InpTradePullback;
}

bool NqIsOurs(long magic, string sym)
{
   return (magic == InpMagic && sym == g_sym);
}


//+------------------------------------------------------------------+
//| THE CLOCK. AUTO: the session minutes come from the broker's live  |
//| GMT offset and the US / EU daylight rules (engine: NqClockFromGmt)|
//| so NY 09:30 is NY 09:30 on any broker in both seasons. MANUAL:    |
//| the server-hour inputs, as before. The panel's NY SESSION line    |
//| shows which is in force and the offset it measured.              |
//+------------------------------------------------------------------+
void NqReadClock()
{
   g_clkAuto = false;
   g_clk.offsetMin = 0;
   g_clk.usDst = false;
   g_clk.euDst = false;
   g_clk.nyS = InpNyStartHour * 60 + InpNyStartMin;
   g_clk.nyE = InpNyEndHour * 60 + InpNyEndMin;
   g_clk.lonS = InpLondonStartHour * 60;
   g_clk.asiaS = InpAsiaStartHour * 60;
   g_clk.asiaE = InpAsiaEndHour * 60;
   g_clk.preS = InpRangeStartHour * 60;
   g_clk.roll = InpRangeStartHour * 60;
   g_clk.nyS0 = g_clk.nyS;
   g_clk.nyE0 = g_clk.nyE;
   g_clk.lonS0 = g_clk.lonS;
   g_clk.asiaS0 = g_clk.asiaS;
   g_clk.asiaE0 = g_clk.asiaE;
   g_clkText = "MANUAL server hours (InpClockAuto = false)";
   if(!InpClockAuto)
      return;
   datetime s = TimeTradeServer();
   datetime g = TimeGMT();
   NqClock c;
   bool ok = NqClockFromGmt(g, (long)s - (long)g, c);
   int off = c.offsetMin;
   string offT = "GMT";
   offT = offT + ((off >= 0) ? "+" : "-") + IntegerToString(MathAbs(off) / 60) + ((MathAbs(off) % 60 != 0) ? ":30" : "");
   if(!ok)
   {
      g_clkText = "AUTO FAILED - the sessions wrap the server day at " + offT + " - MANUAL inputs in use";
      return;
   }
   g_clk = c;
   g_clkAuto = true;
   g_clkText = "AUTO  server " + offT + "  NY DST " + (c.usDst ? "on" : "off") + "  EU DST " + (c.euDst ? "on" : "off");
}

//+------------------------------------------------------------------+
//| VOLATILITY REGIME. A news day goes from dead to wild without a    |
//| session boundary, so ATR(M5) is judged against its own average:   |
//| DEAD = no new trade; NORMAL = as configured; EXPANSION = allowed  |
//| with stronger confirmation (radar score, M15 for scalps); EXTREME |
//| = do not chase, and after it ends stay closed until a CONFIRMED   |
//| M5 swing has formed after the extreme bar (fresh structure). It   |
//| gates NEW entries only; closing is never blocked.                 |
//+------------------------------------------------------------------+
string NqVolClassText(int c)
{
   switch(c)
   {
      case NQ_VOL_DEAD:      return "DEAD";
      case NQ_VOL_NORMAL:    return "NORMAL";
      case NQ_VOL_EXPANSION: return "EXPANSION";
      case NQ_VOL_EXTREME:   return "EXTREME";
   }
   return "UNKNOWN";
}

void NqVolRegime()
{
   g_volClass = NQ_VOL_UNKNOWN;
   g_volRatio = 0.0;
   g_volAvg = 0.0;
   int n = g_s5.n;
   if(!g_ready || n < InpVolAvgBars + 2)
      return;
   double a = g_s5.atr[n - 1];
   if(a <= 0.0)
      return;
   double sum = 0.0;
   int cnt = 0;
   for(int i = n - 1 - InpVolAvgBars; i < n - 1; i++)
   {
      if(g_s5.atr[i] > 0.0)
      {
         sum += g_s5.atr[i];
         cnt++;
      }
   }
   if(cnt < InpVolAvgBars / 2)
      return;
   g_volAvg = sum / cnt;
   g_volRatio = a / g_volAvg;
   if(g_volRatio < InpVolDead)
      g_volClass = NQ_VOL_DEAD;
   else if(g_volRatio >= InpVolExtreme)
      g_volClass = NQ_VOL_EXTREME;
   else if(g_volRatio >= InpVolExpand)
      g_volClass = NQ_VOL_EXPANSION;
   else
      g_volClass = NQ_VOL_NORMAL;
   if(g_volClass == NQ_VOL_EXTREME)
   {
      g_volExtremeEndT = g_s5.t[n - 1];
      g_volWaitFresh = true;
      return;
   }
   if(g_volWaitFresh)
   {
      // fresh structure = a confirmed M5 swing whose bar is later than the extreme
      for(int p = 0; p < g_s5.np; p++)
      {
         if(g_s5.t[g_piv5[p].idx] > g_volExtremeEndT)
         {
            g_volWaitFresh = false;
            break;
         }
      }
   }
}

int NqVolGateBits()
{
   if(!InpVolGate)
      return 0;
   if(g_volClass == NQ_VOL_DEAD)
      return NQ_K_VOL_DEAD;
   if(g_volClass == NQ_VOL_EXTREME || g_volWaitFresh)
      return NQ_K_VOL_EXTREME;
   return 0;
}

// gate names: the engine's own bits first (its helper, untouched), then the two regime bits
string NqGateNameX(int bit)
{
   if(bit == NQ_K_VOL_DEAD)
      return "VOLATILITY DEAD - NO NEW TRADE";
   if(bit == NQ_K_VOL_EXTREME)
      return "VOLATILITY EXTREME - WAIT FOR FRESH STRUCTURE";
   if(bit == NQ_K_NEWS)
      return "NEWS GUARD - " + g_newsWhy;
   if(bit == NQ_K_NEWS_UNKNOWN)
      return "NEWS UNKNOWN - THE CALENDAR ANSWERED NOTHING, NOT TRADING BLIND";
   if(bit == NQ_K_ROLLOVER)
      return "ROLLOVER WINDOW - SPREADS WIDEN, NO NEW TRADE";
   if(bit == NQ_K_WEEK_EDGE)
      return "WEEK EDGE - " + g_weekText;
   if(bit == NQ_K_PORTFOLIO)
      return "PORTFOLIO FULL - " + IntegerToString(g_portfolioPos) + " POSITIONS ACROSS CHARTS (MAX " + IntegerToString(InpMaxOpenAcrossCharts) + ")";
   return NqGateName(bit);
}

string NqGateAtX(int g, int nth)
{
   int extras[7];
   extras[0] = NQ_K_VOL_DEAD;
   extras[1] = NQ_K_VOL_EXTREME;
   extras[2] = NQ_K_NEWS;
   extras[3] = NQ_K_NEWS_UNKNOWN;
   extras[4] = NQ_K_ROLLOVER;
   extras[5] = NQ_K_WEEK_EDGE;
   extras[6] = NQ_K_PORTFOLIO;
   int mask = 0;
   for(int i = 0; i < 7; i++)
      mask |= extras[i];
   int engine = g & ~mask;   // an int variable: ~ on a literal is uint in MQL5 (compiler warning)
   string s = NqGateAt(engine, nth);
   if(s != "")
      return s;
   int c = 0;
   while(NqGateAt(engine, c) != "")
      c++;
   int k = nth - c;
   for(int i = 0; i < 7; i++)
   {
      if((g & extras[i]) == 0)
         continue;
      if(k == 0)
         return NqGateNameX(extras[i]);
      k--;
   }
   return "";
}

//+------------------------------------------------------------------+
//| SPIKE GUARD. "Up, then pullback, then buy" on a news day is not a |
//| pullback - it is the other side of a spike. A spike = the last    |
//| InpSpikeBars closed M5 bars ranging InpSpikeX x a NORMAL such     |
//| window (a trending hour already spans ~4 ATR(M5): the ATR alone  |
//| would call every hour a spike, so the test is the hour itself)    |
//| ATR(M5) or more. While it is in the window: no pullback, scalp or |
//| breakout entry in ITS direction (reversal plans against it - QML, |
//| NY trap - stay allowed). Once the close has given back            |
//| InpSpikeRetrace of it: EXIT WARNING on a position in its          |
//| direction. The human decides; nothing is closed by this.          |
//+------------------------------------------------------------------+
void NqSpikeScan()
{
   g_spikeDir = 0;
   g_spikeAtr = 0.0;
   g_spikeX = 0.0;
   g_spikeNorm = 0.0;
   g_spikeRetr = 0.0;
   g_spikeWarn = false;
   int n = g_s5.n;
   if(!InpSpikeGuard || !g_ready || g_volAvg <= 0.0 || n < InpSpikeBars + 1)
      return;
   // a normal window: the average InpSpikeBars-bar range over the regime lookback (non-overlapping windows, the current one excluded)
   int wins = 0;
   double sumR = 0.0;
   for(int e = n - 1 - InpSpikeBars; e - InpSpikeBars + 1 >= 0 && wins < InpVolAvgBars / InpSpikeBars; e -= InpSpikeBars)
   {
      double wh = g_s5.h[e];
      double wl = g_s5.l[e];
      for(int j = e - InpSpikeBars + 1; j < e; j++)
      {
         if(g_s5.h[j] > wh)
            wh = g_s5.h[j];
         if(g_s5.l[j] < wl)
            wl = g_s5.l[j];
      }
      if(wh > wl)
      {
         sumR += wh - wl;
         wins++;
      }
   }
   if(wins < 4)
      return;
   g_spikeNorm = sumR / wins;
   int iHi = n - 1;
   int iLo = n - 1;
   for(int i = n - InpSpikeBars; i < n; i++)
   {
      if(g_s5.h[i] > g_s5.h[iHi])
         iHi = i;
      if(g_s5.l[i] < g_s5.l[iLo])
         iLo = i;
   }
   double range = g_s5.h[iHi] - g_s5.l[iLo];
   if(range < InpSpikeX * g_spikeNorm || iHi == iLo)
      return;
   double c = g_s5.c[n - 1];
   g_spikeAtr = range / g_volAvg;
   g_spikeX = range / g_spikeNorm;
   if(iHi > iLo)
   {
      g_spikeDir = 1;                                   // low first, then the high: an up-spike
      g_spikeRetr = (g_s5.h[iHi] - c) / range;
   }
   else
   {
      g_spikeDir = -1;
      g_spikeRetr = (c - g_s5.l[iLo]) / range;
   }
   if(g_spikeRetr < 0.0)
      g_spikeRetr = 0.0;
   if(g_spikeRetr > 1.0)
      g_spikeRetr = 1.0;
   g_spikeWarn = (g_spikeRetr >= InpSpikeRetrace);
}

// a plan the spike guard refuses: a pullback (M5 or swing) or a breakout STOP in the spike direction
// v1.7.3 - EVERY plan kind in the spike's direction is blocked, QML and the NY trap
// included. 2026-10-07, gold: a 17 ATR down-spike, then two QML SELL limits waiting
// above the price to sell the bounce. Selling the bounce of a crash is the mirror of
// "up, then pullback, then buy" - the case this guard exists for. Plans AGAINST the
// spike (a QML BUY after a down-spike) stay allowed: those are the reversal plans.
bool NqSpikeBlocks(const NqPlan &pl)
{
   if(!InpSpikeGuard || g_spikeDir == 0 || pl.dir != g_spikeDir)
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| THE MACRO VOTE (v1.9). Voters for a direction d (+1 = buy the     |
//| metal): the dollar index (up = metal down), a US 10-year bond     |
//| (a PRICE up = yields down = metal up; a YIELD up = metal down),   |
//| the calendar's reading of USD releases of the last hours (USD     |
//| positive = metal down), the H4 and H1 context and a fresh H1      |
//| CHoCH. Every voter contributes 1 or nothing (NO DATA votes        |
//| nothing). A vote against a trade of InpMacroBlockLevel or more    |
//| blocks it unless the metal's OWN structure is A+ (M15 context +   |
//| M5 regime with the trade, a radar break with a high score).       |
//+------------------------------------------------------------------+
const string NQ_NEWS_CCY = "USD";   // the metal is quoted in dollars: its news is the dollar's news

// the first candidate the broker serves; "" = none
string NqFindSym(string csv)
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

// a witness symbol: the input when typed ("-" = off; a name the broker cannot serve stays, shown
// as NO DATA and voting nothing), else the first AUTO candidate the broker has. Only resolved
// when it speaks for one of the pair's currencies.
string NqResolveWitness(string inp, string autoCsv, bool applies)
{
   if(!applies || inp == "-")
      return "";
   if(inp != "")
      return inp;
   return NqFindSym(autoCsv);
}

// a bond symbol: a PRICE (up = yields down = USD weaker) or a YIELD (up = USD stronger)
bool NqBondIsYield(string sym)
{
   if(InpBondKind == NQ_BOND_PRICE)
      return false;
   if(InpBondKind == NQ_BOND_YIELD)
      return true;
   string u = sym;
   StringToUpper(u);
   if(StringFind(u, "YIELD") >= 0 || StringFind(u, "YLD") >= 0)
      return true;
   if(StringFind(u, "NOTE") >= 0 || StringFind(u, "BOND") >= 0 || StringFind(u, "BUND") >= 0 || StringFind(u, "GILT") >= 0 ||
      StringFind(u, "ZN") >= 0 || StringFind(u, "ZB") >= 0 || StringFind(u, "UST") >= 0)
      return false;
   int n = StringLen(u);
   if(n >= 2 && StringGetCharacter(u, n - 1) == 'Y')
   {
      ushort d = StringGetCharacter(u, n - 2);
      if(d >= '0' && d <= '9')
         return true;                  // US10Y, US02Y
   }
   return false;
}

void NqResolveWitnesses()
{
   g_macroSym = NqResolveWitness(InpMacroSymbol, "USDX,DXY,USDOLLAR,DX,USDIDX,USIDX,DOLLAR,USDINDEX,USDOLLARINDEX", true);
   g_bondSym = NqResolveWitness(InpBondSymbol, "USTNOTE,TNOTE,US10YT,UST10,USTN10,ZN,TNOTEUSD,US10YB,US10Y,US10YR,USTBOND,TBOND,ZB", true);
   g_bondYield = NqBondIsYield(g_bondSym);
}

// the M15 NRTR direction of any symbol the broker serves; 0 = no data (nothing invented)
int NqDirOfSym(string sym)
{
   if(sym == "")
      return 0;
   NqSeries m;
   NqSeriesResize(m, 0);
   int why = 0;
   if(!NqLoadSym(sym, PERIOD_M15, m, why))
      return 0;
   NqCalcATR(m.h, m.l, m.c, m.n, g_P.atrPeriod, m.atr);
   NqCalcNRTR(m.c, m.atr, m.n, g_P.nrtrMult, m.dir, m.stop, m.ext, m.flip);
   return (m.n > 0) ? m.dir[m.n - 1] : 0;
}

void NqReadWitnesses()
{
   NqReadMacro();
   g_bondDir = NqDirOfSym(g_bondSym);
}

// one witness: its M15 NRTR direction times its sign is the METAL direction it implies
int NqWitnessVote(int d, string label, string sym, int wdir, int sign, int weight, string &why)
{
   if(sym == "" || wdir == 0)
      return 0;
   int s = sign * wdir * d * weight;
   why = why + ((why == "") ? "" : ", ") + label + " " + NqDirText(wdir) + " " + ((s > 0) ? "+" : "") + IntegerToString(s);
   return s;
}

// the USD releases of the last InpNewsVoteHours, read by the calendar itself: USD positive = metal down
int NqNewsVote(int d, string &why)
{
   if(InpNewsVoteHours <= 0 || !g_newsOk)
      return 0;
   datetime now = TimeTradeServer();
   int v = 0;
   for(int i = 0; i < g_nEv; i++)
   {
      if(g_evImpact[i] == 0 || g_evT[i] > now || now - g_evT[i] > (long)InpNewsVoteHours * 3600)
         continue;
      int s = -g_evImpact[i] * d;
      v += s;
      why = why + ((why == "") ? "" : ", ") + "news USD " + g_evName[i] + " " + ((g_evImpact[i] > 0) ? "POSITIVE" : "NEGATIVE") + " " + ((s > 0) ? "+1" : "-1");
   }
   return v;
}

//+------------------------------------------------------------------+
//| HIGHER TIMEFRAMES. H1 and H4 of this symbol: the same context     |
//| (EMA200 + NRTR), confirmed swings, structure and every close      |
//| through a confirmed swing, classified: a break WITH the structure |
//| in force before it is a BOS (break of structure), AGAINST it a    |
//| CHoCH (change of character); structure not confirmed = BREAK.     |
//| H4 and H1 context each vote 1; a fresh H1 CHoCH votes 1.          |
//+------------------------------------------------------------------+
bool NqLoadTail(string sym, ENUM_TIMEFRAMES tf, int count, NqSeries &s)
{
   int sec = PeriodSeconds(tf);
   s.sec = sec;
   MqlRates r[];
   int got = CopyRates(sym, tf, 1, count, r);
   if(got <= 0)
   {
      NqSeriesResize(s, 0);
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
      s.v[i] = (double)r[i].tick_volume;
   }
   return (n >= 2);
}

void NqRunHtf(NqSeries &s, NqPivot &piv[], NqSwingBreak &sb[], int &nSb)
{
   NqRunContext(s, g_P);
   s.np = NqFindPivots(s.h, s.l, s.n, g_P.swing, piv);
   NqStructureSeries(piv, s.np, s.n, s.st, s.hl, s.ll, s.lk);
   NqRunSwingBreaks(s, piv, s.np, 24, sb, nSb);
}

void NqReadHtf()
{
   g_h1Ok = NqLoadTail(g_sym, PERIOD_H1, InpHtfBars, g_h1);
   if(g_h1Ok)
      NqRunHtf(g_h1, g_pivH1, g_sbH1, g_nSbH1);
   else
      g_nSbH1 = 0;
   g_h4Ok = NqLoadTail(g_sym, PERIOD_H4, InpHtfBars, g_h4);
   if(g_h4Ok)
      NqRunHtf(g_h4, g_pivH4, g_sbH4, g_nSbH4);
   else
      g_nSbH4 = 0;
}

string NqBreakKind(const NqSeries &s, const NqSwingBreak &b)
{
   int st = (b.idx > 0 && b.idx - 1 < ArraySize(s.st)) ? s.st[b.idx - 1] : NQ_ST_UNKNOWN;
   if(st == NQ_ST_BULL)
      return (b.dir > 0) ? "BOS" : "CHoCH";
   if(st == NQ_ST_BEAR)
      return (b.dir < 0) ? "BOS" : "CHoCH";
   return "BREAK";
}

// the newest break of a series (-1 = none)
int NqLatestBreak(const NqSwingBreak &sb[], int n)
{
   int best = -1;
   for(int i = 0; i < n; i++)
      if(best < 0 || sb[i].idx > sb[best].idx)
         best = i;
   return best;
}

string NqBreakText(const NqSeries &s, const NqSwingBreak &sb[], int n)
{
   int b = NqLatestBreak(sb, n);
   if(b < 0)
      return "no break";
   return NqBreakKind(s, sb[b]) + ((sb[b].dir > 0) ? " up " : " down ") + NqPx(sb[b].level) + " @" + TimeToString(s.t[sb[b].idx] + s.sec, TIME_MINUTES);
}

string NqHtfText(const NqSeries &s, bool okS, const NqSwingBreak &sb[], int n, string tf)
{
   if(!okS || s.n < 2)
      return tf + " NO DATA";
   int i = s.n - 1;
   string ctxT = (s.emaS[i] > 0.0) ? NqContextText(s.ctx[i]) : ("EMA" + IntegerToString(InpEmaSlow) + " not ready (" + IntegerToString(s.n) + " bars)");
   return tf + " " + ctxT + " (NRTR " + NqDirText(s.dir[i]) + ")  " + NqStructText(s.st[i], s.hl[i], s.ll[i], s.lk[i]) + "  last " + NqBreakText(s, sb, n);
}

// the H1 / H4 voters: context (1 each) and a fresh H1 CHoCH (1)
int NqHtfVote(int d, string &why)
{
   int v = 0;
   if(g_h4Ok && g_h4.n > 0 && g_h4.ctx[g_h4.n - 1] != 0)
   {
      int s = g_h4.ctx[g_h4.n - 1] * d;
      v += s;
      why = why + ((why == "") ? "" : ", ") + "H4 " + NqContextText(g_h4.ctx[g_h4.n - 1]) + " " + ((s > 0) ? "+1" : "-1");
   }
   if(g_h1Ok && g_h1.n > 0 && g_h1.ctx[g_h1.n - 1] != 0)
   {
      int s = g_h1.ctx[g_h1.n - 1] * d;
      v += s;
      why = why + ((why == "") ? "" : ", ") + "H1 " + NqContextText(g_h1.ctx[g_h1.n - 1]) + " " + ((s > 0) ? "+1" : "-1");
   }
   if(InpHtfChochBars > 0 && g_h1Ok && g_nSbH1 > 0)
   {
      int b = NqLatestBreak(g_sbH1, g_nSbH1);
      if(b >= 0 && g_h1.n - 1 - g_sbH1[b].idx < InpHtfChochBars && NqBreakKind(g_h1, g_sbH1[b]) == "CHoCH")
      {
         int s = g_sbH1[b].dir * d;
         v += s;
         why = why + ((why == "") ? "" : ", ") + "H1 CHoCH " + ((g_sbH1[b].dir > 0) ? "up" : "down") + " " + ((s > 0) ? "+1" : "-1");
      }
   }
   return v;
}

int NqMacroVote(int d, string &why)
{
   int v = 0;
   why = "";
   v += NqWitnessVote(d, "DXY", g_macroSym, g_macroDir, -1, 1, why);
   v += NqWitnessVote(d, g_bondYield ? "yield" : "bond", g_bondSym, g_bondDir, g_bondYield ? -1 : 1, 1, why);
   v += NqNewsVote(d, why);
   v += NqHtfVote(d, why);
   return v;
}

// a strong vote AGAINST the direction is a block, unless the pair's OWN structure is A+:
// M15 context + M5 regime on the side of the trade, and for a radar break its score
bool NqMacroBlocks(int dir, int score, bool isRadar, string &why)
{
   why = "";
   if(!g_macroGate || dir == 0)
      return false;
   string voters = "";
   int v = NqMacroVote(dir, voters);
   if(v > -InpMacroBlockLevel)
      return false;
   bool own = (InpMacroOverrideScore <= 10 && g_s15.n > 0 && g_s5.n > 0 && g_s15.ctx[g_s15.n - 1] == dir &&
               g_s5.regime[g_s5.n - 1] == dir && (!isRadar || score >= InpMacroOverrideScore));
   if(own)
      return false;
   why = "MACRO AGAINST ";
   why = why + ((dir > 0) ? "BUY" : "SELL") + " (vote " + IntegerToString(v) + ": " + voters + ") - own structure not A+";
   return true;
}

//+------------------------------------------------------------------+
//| THE CALENDAR. MQL5's built-in economic calendar: one unfiltered   |
//| query over yesterday .. +2 days, kept for the pair's two          |
//| currencies at MODERATE and HIGH importance. The terminal's own    |
//| POSITIVE / NEGATIVE reading of a release (actual against the      |
//| forecast) is kept as the event's vote. A calendar that answers    |
//| nothing is UNKNOWN; the Strategy Tester has none at all.          |
//+------------------------------------------------------------------+
bool NqIsTopTier(string name)
{
   string u = name;
   StringToUpper(u);
   string keys = "FOMC,RATE DECISION,INTEREST RATE,CASH RATE,REFINANCING,NONFARM,NON-FARM,PAYROLL,CPI,CONSUMER PRICE,GDP,PRESS CONFERENCE,"
                 "MONETARY POLICY,FED CHAIR,ECB PRESIDENT,BOE GOVERNOR,BOJ,RBA,RBNZ,BOC ,SNB,PCE,UNEMPLOYMENT RATE,ISM MANUFACTURING,ISM SERVICES,RETAIL SALES";
   int pos = 0;
   int n = StringLen(keys);
   while(pos < n)
   {
      int c = StringFind(keys, ",", pos);
      if(c < 0)
         c = n;
      string k = StringSubstr(keys, pos, c - pos);
      pos = c + 1;
      if(k != "" && StringFind(u, k) >= 0)
         return true;
   }
   return false;
}

void NqReadCalendar()
{
   g_nEv = 0;
   g_newsOk = false;
   g_newsTester = (MQLInfoInteger(MQL_TESTER) != 0);
   g_newsReadT = TimeTradeServer();
   if(!g_newsGuard || g_newsTester)
      return;
   datetime now = TimeTradeServer();
   MqlCalendarValue vals[];
   ResetLastError();
   // the reference declares the call bool; the array is the authority either way: an empty
   // answer (a failed call, an error code, no values) is UNKNOWN, never "no news"
   bool okCall = CalendarValueHistory(vals, now - 86400, now + 2 * 86400, NULL, NULL);
   int n = ArraySize(vals);
   if(!okCall || n <= 0)
   {
      g_newsErr = GetLastError();
      return;
   }
   g_newsErr = 0;
   g_newsOk = true;
   for(int i = 0; i < n && g_nEv < 400; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev))
         continue;
      if(ev.importance < CALENDAR_IMPORTANCE_MODERATE)
         continue;
      MqlCalendarCountry co;
      if(!CalendarCountryById(ev.country_id, co))
         continue;
      string ccy = co.currency;
      StringToUpper(ccy);
      if(ccy != NQ_NEWS_CCY)
         continue;
      ArrayResize(g_evT, g_nEv + 1, 64);
      ArrayResize(g_evCcy, g_nEv + 1, 64);
      ArrayResize(g_evImp, g_nEv + 1, 64);
      ArrayResize(g_evName, g_nEv + 1, 64);
      ArrayResize(g_evImpact, g_nEv + 1, 64);
      ArrayResize(g_evTop, g_nEv + 1, 64);
      g_evT[g_nEv] = vals[i].time;
      g_evCcy[g_nEv] = ccy;
      g_evImp[g_nEv] = (int)ev.importance;
      g_evName[g_nEv] = ev.name;
      int impact = 0;
      if(vals[i].actual_value != LONG_MIN)
         impact = (vals[i].impact_type == CALENDAR_IMPACT_POSITIVE) ? 1 : ((vals[i].impact_type == CALENDAR_IMPACT_NEGATIVE) ? -1 : 0);
      g_evImpact[g_nEv] = impact;
      g_evTop[g_nEv] = NqIsTopTier(ev.name);
      g_nEv++;
   }
}

// the gate's view of this minute, from the cached events
void NqNewsState()
{
   g_newsBlock = false;
   g_newsUnknown = false;
   g_newsText = "";
   g_newsWhy = "";
   if(!g_newsGuard)
   {
      g_newsText = "news guard off";
      return;
   }
   if(g_newsTester)
   {
      g_newsText = "N/A in the Strategy Tester (no calendar there) - not gated";
      return;
   }
   if(!g_newsOk)
   {
      g_newsUnknown = true;
      g_newsText = "UNKNOWN - the calendar answered nothing" + ((g_newsErr != 0) ? (" (error " + IntegerToString(g_newsErr) + ")") : "");
      g_newsText = g_newsText + (g_newsUnknownBlocks ? " - not trading blind (InpNewsUnknownBlocks)" : " - trading anyway (InpNewsUnknownBlocks = false)");
      return;
   }
   datetime now = TimeTradeServer();
   datetime nextT = 0;
   int nextI = -1;
   string lastRel = "";
   for(int i = 0; i < g_nEv; i++)
   {
      bool hi = (g_evImp[i] >= (int)CALENDAR_IMPORTANCE_HIGH);
      bool guarded = hi || (g_newsMediumBlocks && g_evImp[i] >= (int)CALENDAR_IMPORTANCE_MODERATE);
      if(!guarded)
         continue;
      int before = g_evTop[i] ? InpNewsTopBeforeMin : InpNewsBeforeMin;
      int after = g_evTop[i] ? InpNewsTopAfterMin : InpNewsAfterMin;
      if(now >= g_evT[i] - (long)before * 60 && now < g_evT[i] + (long)after * 60)
      {
         if(!g_newsBlock)
         {
            g_newsBlock = true;
            g_newsWinT = g_evT[i];
            string imp = g_evTop[i] ? "TOP TIER" : (hi ? "HIGH" : "MODERATE");
            g_newsWhy = g_evCcy[i] + " " + g_evName[i] + " at " + TimeToString(g_evT[i], TIME_MINUTES) + " (" + imp + ", " +
                        ((now < g_evT[i]) ? ("in " + NqHhMm((long)g_evT[i] - (long)now)) : (NqHhMm((long)now - (long)g_evT[i]) + " ago")) +
                        ") - gate closed " + IntegerToString(before) + " min before to " + IntegerToString(after) + " min after";
         }
      }
      if(g_evT[i] > now && (nextI < 0 || g_evT[i] < nextT))
      {
         nextT = g_evT[i];
         nextI = i;
      }
   }
   for(int i = 0; i < g_nEv; i++)
      if(g_evImpact[i] != 0 && g_evT[i] <= now && now - g_evT[i] <= (long)InpNewsVoteHours * 3600)
         lastRel = lastRel + ((lastRel == "") ? "" : ", ") + g_evCcy[i] + " " + g_evName[i] + " " + ((g_evImpact[i] > 0) ? "POSITIVE" : "NEGATIVE");
   if(g_newsBlock)
      g_newsText = "GUARD - " + g_newsWhy;
   else if(nextI >= 0)
   {
      g_newsText = "clear - next ";
      g_newsText = g_newsText + (g_evTop[nextI] ? "TOP TIER " : "HIGH ") + g_evCcy[nextI] + " " + g_evName[nextI] + " in " + NqHhMm((long)nextT - (long)now) +
                   " (gate closes " + IntegerToString(g_evTop[nextI] ? InpNewsTopBeforeMin : InpNewsBeforeMin) + " min before)";
   }
   else
      g_newsText = "clear - no HIGH USD event in the next 48h";
   if(lastRel != "")
      g_newsText = g_newsText + "   released " + IntegerToString(InpNewsVoteHours) + "h: " + lastRel;
}

// the week's position and the rollover window on the server clock (engine NqWeekPos); the
// session name is for the panel - a metal has no home session, the levels are its clock
string NqSessionName()
{
   if((g_sessOpen & 4) != 0)
      return "NY";
   if((g_sessOpen & 2) != 0)
      return "LONDON";
   if((g_sessOpen & 1) != 0)
      return "ASIA";
   return "OFF";
}

void NqSessionScan(datetime now)
{
   int mod = NqMinuteOfDay(now);
   g_dow = NqDow(now);
   int open = 0;
   if(NqInWindow(mod, g_clk.nyS0, g_clk.nyE0))
      open |= 4;
   else if(NqInWindow(mod, g_clk.lonS0, g_clk.nyS0))
      open |= 2;
   else if(NqInWindow(mod, g_clk.asiaS0, g_clk.lonS0))
      open |= 1;
   g_sessOpen = open;
   int roll = g_clk.roll;
   int d = mod - roll;
   if(d > 720)
      d -= 1440;
   if(d < -720)
      d += 1440;
   g_rollover = g_clockGuards && InpRolloverGuardMin > 0 && d >= -InpRolloverGuardMin && d < InpRolloverGuardMin;
   g_weekEdge = false;
   g_weekFriday = false;
   g_weekText = "";
   if(!g_clockGuards)
      return;
   int sinceOpen = 0;
   int untilClose = 0;
   if(!NqWeekPos(g_dow, mod, roll, sinceOpen, untilClose))
   {
      g_weekEdge = true;
      g_weekText = "WEEKEND (the week opens Sunday 17:00 New York)";
   }
   else if(untilClose <= InpFridayStopMin)
   {
      g_weekEdge = true;
      g_weekFriday = true;
      g_weekText = "FRIDAY STOP - " + NqHhMm((long)untilClose * 60) + " to the close: orders pulled, profits banked";
   }
   else if(sinceOpen < InpWeekOpenGuardMin)
   {
      g_weekEdge = true;
      g_weekText = "FIRST " + IntegerToString(InpWeekOpenGuardMin) + " MIN OF THE WEEK - gaps and thin books";
   }
}

// this EA on every chart (same magic): positions across symbols
void NqPortfolioScan()
{
   g_portfolioPos = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic)
         g_portfolioPos++;
   }
   g_portfolioFull = (InpMaxOpenAcrossCharts > 0 && g_portfolioPos >= InpMaxOpenAcrossCharts);
}

int NqMetalGateBits()
{
   int g = 0;
   if(g_newsBlock)
      g |= NQ_K_NEWS;
   if(g_newsUnknown && g_newsUnknownBlocks)
      g |= NQ_K_NEWS_UNKNOWN;
   if(g_rollover)
      g |= NQ_K_ROLLOVER;
   if(g_weekEdge)
      g |= NQ_K_WEEK_EDGE;
   if(g_portfolioFull)
      g |= NQ_K_PORTFOLIO;
   return g;
}

//+------------------------------------------------------------------+
//| SMART EXIT. A position's result in R (its own SL distance, or the |
//| plan's risk when the SL is 0), whether the M5 regime ever agreed  |
//| with it since the open (a reversal plan's regime may never agree: |
//| then "flipped" means nothing and the plan runs on its SL/TP), and |
//| the three rules: lock the SL above entry at +InpSmartLockAtR,     |
//| bank on an M5 flip against a position in profit (cut under water, |
//| switchable), bank on an M1 bias turn with a decent profit.        |
//+------------------------------------------------------------------+
double NqPosR(double open, double sl, double px, int pdir, string cmt)
{
   double risk = (sl > 0.0) ? MathAbs(open - sl) : 0.0;
   if(risk <= 0.0)
   {
      NqPlan p;
      if(NqPlanByComment(cmt, p))
         risk = p.risk;
   }
   if(risk <= 0.0)
      return 0.0;
   return (px - open) * pdir / risk;
}

// the stop (and TP when the position has none) a position SHOULD carry, from its plan or scalp record; 0 = unknown
double NqPlanSlOf(string cmt, double &tp)
{
   if(StringFind(cmt, NQ_CMT_SCALP) == 0)
   {
      long t = StringToInteger(StringSubstr(cmt, StringLen(NQ_CMT_SCALP)));
      for(int k = g_nSig - 1; k >= 0; k--)
      {
         if((long)g_s1.t[g_sigs[k].idx] != t)
            continue;
         if(tp <= 0.0)
            tp = g_sigs[k].tp;
         return g_sigs[k].sl;
      }
      return 0.0;
   }
   NqPlan p;
   if(!NqPlanByComment(cmt, p))
      return 0.0;
   if(tp <= 0.0)
      tp = InpPlanUseTp2 ? p.tp2 : p.tp1;
   return p.sl;
}

bool NqRegimeAgreedSince(datetime opened, int pdir)
{
   for(int i = g_s5.n - 1; i >= 0; i--)
   {
      if(g_s5.t[i] + g_s5.sec <= opened)
         break;
      if(g_s5.regime[i] == pdir)
         return true;
   }
   return false;
}

bool NqModifySl(ulong ticket, double sl, double tp, string why)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   string posCmt = PositionGetString(POSITION_COMMENT);
   MqlTradeRequest req;
   ZeroMemory(req);
   req.action = TRADE_ACTION_SLTP;
   req.symbol = g_sym;
   req.magic = InpMagic;
   req.position = ticket;
   req.sl = sl;
   req.tp = tp;
   bool done = NqSend(req, why);
   if(done)
      NqEmitBroker(posCmt, "sl_moved", NqJsonI("ticket", (long)ticket) + "," + NqJsonN("sl", sl, g_digits) + "," + NqJsonS("reason", why));
   return done;
}

// true = the position was closed
bool NqSmartExit(ulong tk, int pdir, string cmt, bool isScalp, int reg5)
{
   if(!g_smartExit || !PositionSelectByTicket(tk))
      return false;
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
   double px = (pdir > 0) ? SymbolInfoDouble(g_sym, SYMBOL_BID) : SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double risk = (sl > 0.0) ? MathAbs(open - sl) : 0.0;
   if(risk <= 0.0)
   {
      NqPlan p;
      if(NqPlanByComment(cmt, p))
         risk = p.risk;
   }
   if(risk <= 0.0 || px <= 0.0)
      return false;
   double r = (px - open) * pdir / risk;
   string rT = ((r >= 0.0) ? "+" : "") + DoubleToString(r, 2) + "R";
   // a) the lock: SL to entry + InpSmartLockR once +InpSmartLockAtR is reached, tightened only
   if(InpSmartLockAtR > 0.0 && r >= InpSmartLockAtR)
   {
      double want = NqRoundTick(open + pdir * InpSmartLockR * risk, g_tick, g_digits, (pdir > 0) ? -1 : 1);
      bool better = (pdir > 0) ? (want > sl + g_tick * 0.5) : (sl <= 0.0 || want < sl - g_tick * 0.5);
      double minDist = g_stopsLevel * g_point;
      bool legal = (pdir > 0) ? (want < px - minDist) : (want > px + minDist);
      if(better && legal)
      {
         if(NqModifySl(tk, want, tp, "SMART LOCK: " + rT + " reached, SL to entry " + ((InpSmartLockR > 0.0) ? ("+" + DoubleToString(InpSmartLockR, 2) + "R") : "")))
            g_smartNote = "SMART LOCK #" + IntegerToString((long)tk) + " SL " + NqPx(want) + " (" + rT + ")";
      }
   }
   // b) the M5 regime flipped against it (it agreed at some point since the open)
   if(reg5 != NQ_REG_CHOP && reg5 != pdir && NqRegimeAgreedSince(opened, pdir))
   {
      if(r >= InpSmartFlipProfitR)
      {
         if(NqClosePosition(tk, "SMART EXIT: M5 regime flipped " + NqRegimeText(reg5) + " against the position, banking " + rT + " before the TP"))
         {
            g_smartNote = "SMART EXIT #" + IntegerToString((long)tk) + " banked " + rT + " (M5 flip)";
            return true;
         }
      }
      else if(InpSmartFlipCutLoss && !isScalp)
      {
         if(NqClosePosition(tk, "SMART EXIT: M5 regime flipped " + NqRegimeText(reg5) + " against the position at " + rT + " - cut before the SL"))
         {
            g_smartNote = "SMART EXIT #" + IntegerToString((long)tk) + " cut at " + rT + " (M5 flip)";
            return true;
         }
      }
   }
   // c) the M1 bias turned against it with a decent profit
   if(InpSmartM1ProfitR > 0.0 && r >= InpSmartM1ProfitR && g_s1.n > 0 && g_s1.dir[g_s1.n - 1] == -pdir)
   {
      if(NqClosePosition(tk, "SMART EXIT: M1 bias turned " + NqDirText(-pdir) + ", banking " + rT))
      {
         g_smartNote = "SMART EXIT #" + IntegerToString((long)tk) + " banked " + rT + " (M1 turn)";
         return true;
      }
   }
   return false;
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
   g_manualPos = 0;
   g_manualOrd = 0;
   g_posText = "";
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(!NqIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
      {
         if(PositionGetString(POSITION_SYMBOL) == g_sym)
            g_manualPos++;
         continue;
      }
      g_openCount++;
      double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      g_floating += pr;
      string cmt = PositionGetString(POSITION_COMMENT);
      string kind = NqKindOfComment(cmt);
      if(kind == "scalp")
         g_scalpCount++;
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
      {
         if(OrderGetString(ORDER_SYMBOL) == g_sym)
            g_manualOrd++;
         continue;
      }
      g_pendCount++;
      string cmt = OrderGetString(ORDER_COMMENT);
      string kind = NqKindOfComment(cmt);
      long oty = OrderGetInteger(ORDER_TYPE);
      string side = (oty == ORDER_TYPE_BUY_LIMIT) ? "buy limit" : ((oty == ORDER_TYPE_SELL_LIMIT) ? "sell limit" : ((oty == ORDER_TYPE_BUY_STOP) ? "buy stop" : "sell stop"));
      string one = kind + " " + side + " " + DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), g_digits);
      g_pendText = (g_pendText == "") ? one : (g_pendText + "  |  " + one);
   }
   if(g_pendText == "")
      g_pendText = "NONE";
   NqPortfolioScan();   // this EA on every chart: positions across symbols

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
   NqVolRegime();
   NqSpikeScan();
   g_gate |= NqVolGateBits();   // DEAD / EXTREME volatility close the gate for NEW entries (named by NqGateAtX)
   NqSessionScan(now);           // the rollover window, the week's edges
   if(g_newsGuard && !g_newsTester && (long)now - (long)g_newsReadT >= 60)
      NqReadCalendar();          // the calendar is re-read every minute on the timer too, not only on a new candle
   NqNewsState();                // the calendar's verdict for this minute
   g_gate |= NqMetalGateBits();  // news / week / portfolio bits (named by NqGateAtX)

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
      string side = "SELL LIMIT ";
      if(req.type == ORDER_TYPE_BUY_LIMIT)
         side = "BUY LIMIT ";
      else if(req.type == ORDER_TYPE_BUY_STOP)
         side = "BUY STOP ";
      else if(req.type == ORDER_TYPE_SELL_STOP)
         side = "SELL STOP ";
      what = side + DoubleToString(req.volume, 2) + " @ " + DoubleToString(req.price, g_digits);
   }
   else if(req.action == TRADE_ACTION_REMOVE)
      what = "CANCEL #" + IntegerToString((long)req.order);
   else if(req.action == TRADE_ACTION_SLTP)
      what = "MODIFY #" + IntegerToString((long)req.position);
   string line = "NQ " + what + " SL " + DoubleToString(req.sl, g_digits) + " TP " + DoubleToString(req.tp, g_digits) +
                 " | " + why + " | " + (done ? "OK" : "REJECTED") + " retcode " + IntegerToString((long)res.retcode) +
                 ((res.deal != 0) ? (" deal " + IntegerToString((long)res.deal)) : "") +
                 ((res.order != 0) ? (" order " + IntegerToString((long)res.order)) : "");
   Print(line);
   g_note = (done ? "SENT: " : "REJECTED: ") + what;
   if(req.action == TRADE_ACTION_PENDING)
   {
      if(done && g_rejCmt == req.comment)
         g_rejCmt = "";
      if(!done)
      {
         g_rejCmt = req.comment;
         g_rejCode = (int)res.retcode;
      }
      NqEmitBroker(req.comment, done ? "placed" : "rejected",
                   NqJsonI("ticket", (long)res.order) + "," + NqJsonI("retcode", (long)res.retcode) + "," + NqJsonN("lot", req.volume, 2));
   }
   else if(req.action == TRADE_ACTION_DEAL && req.position == 0)
      NqEmitBroker(req.comment, done ? "scalp_open" : "rejected",
                   NqJsonI("ticket", (long)res.order) + "," + NqJsonI("retcode", (long)res.retcode) + "," + NqJsonN("lot", req.volume, 2) +
                   "," + NqJsonN("price", req.price, g_digits));
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

bool NqPending(int dir, double price, double lot, double sl, double tp, string comment, string why, bool stop)
{
   MqlTradeRequest req;
   ZeroMemory(req);
   req.action = TRADE_ACTION_PENDING;
   req.symbol = g_sym;
   req.magic = InpMagic;
   req.volume = lot;
   if(stop)
      req.type = (dir > 0) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
   else
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
   string posCmt = PositionGetString(POSITION_COMMENT);
   double posPr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
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
   bool done = NqSend(req, why);
   if(done)
      NqEmitBroker(posCmt, "closed_by_ea", NqJsonI("ticket", (long)ticket) + "," + NqJsonS("reason", why) + "," + NqJsonN("pl", posPr, 2));
   return done;
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
   long want = NqPlanOrderType(p);
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

// the plan behind an order / position comment, from any of the three plan
// arrays (M5, NY, swing). false = no such plan in the loaded history
bool NqPlanByComment(string cmt, NqPlan &out)
{
   for(int k = g_nPlans - 1; k >= 0; k--)
      if(NqPlanComment(g_plans[k]) == cmt) { out = g_plans[k]; return true; }
   for(int k = g_nNy - 1; k >= 0; k--)
      if(NqPlanComment(g_ny[k]) == cmt) { out = g_ny[k]; return true; }
   for(int k = g_nSwing - 1; k >= 0; k--)
      if(NqPlanComment(g_swing[k]) == cmt) { out = g_swing[k]; return true; }
   for(int k = g_nRadar - 1; k >= 0; k--)
      if(NqPlanComment(g_radar[k]) == cmt) { out = g_radar[k]; return true; }
   return false;
}

// the plan the board / trade loop uses for slot q (0 QML M5, 1 PB M5, 2 NY, 3 swing QML, 4 swing PB)
bool NqSlotPlan(int q, NqPlan &out)
{
   int k = -1;
   if(q == 0)
      k = NqLatestPlan(g_plans, g_nPlans, NQ_PLAN_QML);
   else if(q == 1)
      k = NqLatestPlan(g_plans, g_nPlans, NQ_PLAN_PB);
   else if(q == 2)
      k = NqLatestPlan(g_ny, g_nNy, NQ_PLAN_NY);
   else if(q == 3)
      k = NqLatestPlan(g_swing, g_nSwing, NQ_PLAN_QML);
   else if(q == 4)
      k = NqLatestPlan(g_swing, g_nSwing, NQ_PLAN_PB);
   else if(q == 5)
      k = NqLatestPlanDir(g_radar, g_nRadar, NQ_PLAN_RADAR, NQ_BUY);
   else if(q == 6)
      k = NqLatestPlanDir(g_radar, g_nRadar, NQ_PLAN_RADAR, NQ_SELL);
   if(k < 0)
      return false;
   if(q == 2)
      out = g_ny[k];
   else if(q < 2)
      out = g_plans[k];
   else if(q >= 5)
      out = g_radar[k];
   else
      out = g_swing[k];
   return true;
}

// STOP for the radar, LIMIT for everything else
bool NqPlanIsStop(const NqPlan &p)
{
   return (p.kind == NQ_PLAN_RADAR);
}

long NqPlanOrderType(const NqPlan &p)
{
   if(NqPlanIsStop(p))
      return (p.dir > 0) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
   return (p.dir > 0) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
}

//+------------------------------------------------------------------+
//| JOURNAL. Every plan event is one JSON line: appended to a local  |
//| file and POSTed to SignalMesh's /webhooks/brain/signal, which     |
//| stores the raw payload verbatim (append-only) under a stable      |
//| signal_id and keeps a status timeline. The secret is a header     |
//| and is never printed. A failed POST is queued and retried; the    |
//| file is the durable record either way. Nothing here can block    |
//| or alter trading: a journal failure is a Print, never a return.  |
//+------------------------------------------------------------------+
string NqJsonEsc(string v)
{
   string out = v;
   StringReplace(out, "\\", "\\\\");
   StringReplace(out, "\"", "\\\"");
   return out;
}

string NqJsonS(string key, string val)
{
   return "\"" + key + "\":\"" + NqJsonEsc(val) + "\"";
}

string NqJsonN(string key, double val, int digits)
{
   return "\"" + key + "\":" + DoubleToString(val, digits);
}

string NqJsonI(string key, long val)
{
   return "\"" + key + "\":" + IntegerToString(val);
}

// the platform's status vocabulary (pending / executed / closed / cancelled),
// never "approved": that word fans out Telegram alerts to every user
string NqPlatformStatus(int st)
{
   switch(st)
   {
      case NQ_PL_ACTIVE:   return "pending";
      case NQ_PL_FILLED:   return "executed";
      case NQ_PL_TP1:      return "closed";
      case NQ_PL_SL:       return "closed";
      case NQ_PL_FALSE:    return "closed";
      case NQ_PL_EXPIRED:  return "cancelled";
      case NQ_PL_INVALID:  return "cancelled";
      case NQ_PL_REPLACED: return "cancelled";
   }
   return "pending";
}

string NqPlatformOutcome(int st)
{
   switch(st)
   {
      case NQ_PL_FILLED: return "open";
      case NQ_PL_TP1:    return "win";
      case NQ_PL_SL:     return "loss";
      case NQ_PL_FALSE:  return "loss";
   }
   return "";
}

string NqEventOfStatus(int st)
{
   switch(st)
   {
      case NQ_PL_ACTIVE:   return "armed";
      case NQ_PL_FILLED:   return "filled";
      case NQ_PL_TP1:      return "tp1";
      case NQ_PL_SL:       return "sl";
      case NQ_PL_FALSE:    return "false_break";
      case NQ_PL_EXPIRED:  return "expired";
      case NQ_PL_INVALID:  return "cancelled";
      case NQ_PL_REPLACED: return "replaced";
   }
   return "status";
}

string NqSignalIdOf(const NqPlan &p)
{
   string cmt = (p.kind == NQ_PLAN_SCALP) ? (NQ_CMT_SCALP + IntegerToString((long)p.keyTime)) : NqPlanComment(p);
   return "NQ:" + g_sym + ":" + cmt;
}

string NqEventJson(const NqPlan &p, string event, string extra)
{
   datetime now = TimeTradeServer();
   int n5 = g_s5.n;
   int n15 = g_s15.n;
   string j = "{" + NqJsonS("signal_id", NqSignalIdOf(p)) + "," + NqJsonS("system", "NQ-EA") + "," +
              NqJsonS("ea_version", NQ_EA_VERSION) + "," + NqJsonS("symbol", g_sym) + "," +
              NqJsonS("h4_ctx", (g_h4Ok && g_h4.n > 0) ? NqContextText(g_h4.ctx[g_h4.n - 1]) : "") + "," + NqJsonS("h1_ctx", (g_h1Ok && g_h1.n > 0) ? NqContextText(g_h1.ctx[g_h1.n - 1]) : "") + "," +
              NqJsonS("h1_break", g_h1Ok ? NqBreakText(g_h1, g_sbH1, g_nSbH1) : "") + "," + NqJsonS("m5_break", NqBreakText(g_s5, g_sbrk, g_nSbrk)) + "," +
              NqJsonS("vol_regime", NqVolClassText(g_volClass)) + "," + NqJsonN("spike_atr", g_spikeAtr * g_spikeDir, 1) + "," +
              NqJsonS("tf", (p.kind == NQ_PLAN_SCALP) ? "1" : ((p.tf == 900) ? "15" : "5")) + "," +
              NqJsonS("direction", (p.dir > 0) ? "BUY" : "SELL") + "," +
              NqJsonN("entry", p.entry, g_digits) + "," + NqJsonN("sl", p.sl, g_digits) + "," +
              NqJsonN("tp1", p.tp1, g_digits) + "," + NqJsonN("tp2", p.tp2, g_digits) + "," +
              NqJsonN("rr", (p.risk > 0.0) ? MathAbs(p.tp1 - p.entry) / p.risk : 0.0, 2) + "," +
              NqJsonS("grade", NqPlanKindText(p.kind)) + "," +
              NqJsonS("status", NqPlatformStatus(p.status)) + "," +
              NqJsonS("outcome", NqPlatformOutcome(p.status)) + "," +
              NqJsonI("fired_at", (long)p.madeAt) + "," + NqJsonI("ts", (long)now) + "," +
              NqJsonS("event", event) + "," + NqJsonS("plan_kind", NqPlanKindText(p.kind)) + "," +
              NqJsonS("plan_status", (p.kind == NQ_PLAN_SCALP) ? NqSignalStatusText(p.status) : NqPlanStatusText(p.status)) + "," +
              NqJsonI("plan_tf_sec", p.tf) + "," + NqJsonN("level", p.lvlA, g_digits) + "," +
              NqJsonN("level2", p.lvlB, g_digits) + "," + NqJsonN("risk", p.risk, g_digits) + "," +
              NqJsonS("account_mode", g_isDemo ? "demo" : "real") + "," + NqJsonI("magic", InpMagic) + "," +
              NqJsonS("regime5", (n5 > 0) ? NqRegimeText(g_s5.regime[n5 - 1]) : "") + "," +
              NqJsonS("ctx15", (n15 > 0) ? NqContextText(g_s15.ctx[n15 - 1]) : "") + "," +
              NqJsonN("risk_pct", InpRiskPct, 2);
   if(p.kind == NQ_PLAN_RADAR)
      j = j + "," + NqJsonI("radar_score", (p.dir > 0) ? g_rdUp.score : g_rdDn.score);
   if(extra != "")
      j = j + "," + extra;
   return j + "}";
}

void NqJournalWrite(string line)
{
   if(!InpJournalToFile)
      return;
   string name = "NQ_events_" + g_sym + ".jsonl";
   int h = FileOpen(name, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
   {
      if(!g_jrFileWarned)
         Print("NQ journal: cannot open MQL5/Files/" + name);
      g_jrFileWarned = true;
      return;
   }
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, line + "\n");
   FileClose(h);
}

// one POST; true when the platform answered 2xx. The secret travels in a
// header and never reaches the log.
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

void NqEmit(const NqPlan &p, string event, string extra)
{
   string json = NqEventJson(p, event, extra);
   NqJournalWrite(json);
   if(g_webUrl == "")
   {
      Print("NQ journal: " + event + " " + NqSignalIdOf(p));
      return;
   }
   bool okPost = (g_webN == 0) && NqPost(g_webUrl, json);   // keep order: never jump the queue
   if(okPost)
   {
      g_webFails = 0;
      Print("NQ journal: " + event + " " + NqSignalIdOf(p) + " -> platform ok");
      return;
   }
   if(g_webN < 300)
   {
      ArrayResize(g_webQ, g_webN + 1, 32);
      g_webQ[g_webN] = json;
      g_webN++;
   }
   g_webFails++;
   Print("NQ journal: " + event + " " + NqSignalIdOf(p) + " -> queued (" + IntegerToString(g_webN) + " waiting)");
}

// retry the oldest queued event, at most one every 5 seconds
void NqWebDrain()
{
   if(g_webN == 0 || g_webUrl == "")
      return;
   datetime now = TimeTradeServer();
   if(now - g_webLast < 5)
      return;
   g_webLast = now;
   if(!NqPost(g_webUrl, g_webQ[0]))
   {
      g_webFails++;
      return;
   }
   for(int i = 1; i < g_webN; i++)
      g_webQ[i - 1] = g_webQ[i];
   g_webN--;
   ArrayResize(g_webQ, g_webN);
   g_webFails = 0;
}

//+------------------------------------------------------------------+
//| TELEMETRY (ANALYSIS ONLY). A snapshot of what the panel shows,   |
//| POSTed to SignalMesh's /webhooks/metal/telemetry so the METAL     |
//| ANALYSIS page can display it. It is a DATA WITNESS: every field   |
//| is the EA's own observed state, labelled as such; SignalMesh      |
//| stores it verbatim and derives nothing from it. Nothing here can  |
//| block or alter trading: it runs after NqTrade, a failed POST is a |
//| Print, and there is no queue - the next heartbeat replaces it.    |
//+------------------------------------------------------------------+
string NqJsonB(string key, bool val)
{
   return "\"" + key + "\":" + (val ? "true" : "false");
}

// a reason / gate bit-set as a JSON array of the panel's own words
string NqJsonNames(string key, int bits, bool gate)
{
   string out = "\"" + key + "\":[";
   for(int nth = 0; nth < 24; nth++)
   {
      string nm = gate ? NqGateAtX(bits, nth) : NqReasonAt(bits, nth);
      if(nm == "")
         break;
      out = out + ((nth > 0) ? "," : "") + "\"" + NqJsonEsc(nm) + "\"";
   }
   return out + "]";
}

string NqTelemetryPlan(const NqPlan &p, string slot)
{
   return "{" + NqJsonS("slot", slot) + "," + NqJsonS("kind", NqPlanKindText(p.kind)) + "," +
          NqJsonS("tf", (p.tf == 900) ? "M15" : ((p.tf == 60) ? "M1" : "M5")) + "," +
          NqJsonS("side", (p.dir > 0) ? "BUY" : "SELL") + "," +
          NqJsonS("order", NqPlanIsStop(p) ? "STOP" : ((p.kind == NQ_PLAN_SCALP) ? "MARKET" : "LIMIT")) + "," +
          NqJsonS("status", (p.kind == NQ_PLAN_SCALP) ? NqSignalStatusText(p.status) : NqPlanStatusText(p.status)) + "," +
          NqJsonN("entry", p.entry, g_digits) + "," + NqJsonN("sl", p.sl, g_digits) + "," +
          NqJsonN("tp1", p.tp1, g_digits) + "," + NqJsonN("tp2", p.tp2, g_digits) + "," +
          NqJsonN("level", p.lvlA, g_digits) + "," + NqJsonN("level2", p.lvlB, g_digits) + "," +
          NqJsonI("made_at_server", (long)p.madeAt) + "," + NqJsonS("signal_id", NqSignalIdOf(p)) + "," +
          NqJsonB("placed", (p.kind != NQ_PLAN_SCALP) && (NqFindPlanOrder(p) != 0)) + "}";
}

string NqTelemetryRecord(string key, int done, int won, int lost)
{
   return "\"" + key + "\":{" + NqJsonI("done", done) + "," + NqJsonI("won", won) + "," + NqJsonI("lost", lost) + "," +
          NqJsonS("evidence", NqEvidenceText(done)) + "}";
}

string NqTelemetryJson()
{
   datetime nowS = TimeTradeServer();
   datetime nowG = TimeGMT();
   int n1 = g_s1.n;
   int n5 = g_s5.n;
   int n15 = g_s15.n;
   bool ok = (g_metal != NQ_METAL_NONE && g_ready && n1 > 0 && n5 > 0 && n15 > 0);
   string metal = (g_metal == NQ_METAL_GOLD) ? "GOLD" : ((g_metal == NQ_METAL_SILVER) ? "SILVER" : "NONE");
   string dataReason = "";
   if(!ok)
      dataReason = NqReasonAt(g_finalR, 0);
   else if(!g_fresh)
      dataReason = NqReasonName(NQ_R_STALE);
   string j = "{" + NqJsonS("system", "NQ-EA") + "," + NqJsonS("kind", "telemetry") + "," +
              NqJsonS("mode", "ANALYSIS_ONLY") + "," + NqJsonS("label", "ANALYSIS ONLY - DEMO - NOT A TRADE SIGNAL") + "," +
              NqJsonS("source", "NRTR_QML_MetalScalper") + "," + NqJsonS("ea_version", NQ_EA_VERSION) + "," +
              NqJsonS("symbol", g_sym) + "," + NqJsonS("metal", metal) + "," +
              NqJsonS("account_mode", g_isDemo ? "demo" : "real") + "," + NqJsonI("magic", InpMagic) + "," +
              NqJsonI("ts_server", (long)nowS) + "," + NqJsonI("ts_gmt", (long)nowG) + "," +
              NqJsonI("server_offset_sec", (long)nowS - (long)nowG) + "," + NqJsonI("heartbeat_sec", g_telSec) + "," +
              NqJsonS("clock", g_clkAuto ? "AUTO" : "MANUAL") + "," + NqJsonI("clock_offset_min", g_clk.offsetMin) + "," +
              NqJsonB("ny_dst", g_clk.usDst) + "," + NqJsonB("eu_dst", g_clk.euDst) + "," + NqJsonI("ny_open_min", g_clk.nyS) + "," +
              NqJsonI("ny_close_min", g_clk.nyE) + "," + NqJsonI("london_open_min", g_clk.lonS) + "," + NqJsonI("asia_open_min", g_clk.asiaS) + "," +
              NqJsonI("rollover_min", g_clk.roll) + "," +
              NqJsonB("ready", g_ready) + "," + NqJsonB("fresh", ok && g_fresh) + "," + NqJsonS("data_reason", dataReason) + "," +
              NqJsonS("vol_regime", NqVolClassText(g_volClass)) + "," + NqJsonN("vol_ratio", g_volRatio, 2) + "," +
              NqJsonI("spike_dir", g_spikeDir) + "," + NqJsonN("spike_atr", g_spikeAtr, 1) + "," + NqJsonN("spike_x", g_spikeX, 2) + "," + NqJsonN("spike_retrace", g_spikeRetr, 2) + ",";

   // candles / feed
   j = j + "\"candles\":{";
   if(ok)
   {
      datetime t1 = g_s1.t[n1 - 1];
      datetime t5 = g_s5.t[n5 - 1];
      datetime t15 = g_s15.t[n15 - 1];
      int k5 = g_s1.map[n1 - 1];
      double atr5 = (k5 >= 0) ? g_s5.atr[k5] : g_s5.atr[n5 - 1];
      j = j + NqJsonS("state", g_fresh ? "CLOSED FRESH" : "STALE") + "," +
          NqJsonI("m1_closed_server", (long)t1) + "," + NqJsonI("m1_age_sec", (long)nowS - (long)(t1 + g_s1.sec)) + "," +
          NqJsonI("m5_closed_server", (long)t5) + "," + NqJsonI("m5_age_sec", (long)nowS - (long)(t5 + g_s5.sec)) + "," +
          NqJsonI("m15_closed_server", (long)t15) + "," + NqJsonI("m15_age_sec", (long)nowS - (long)(t15 + g_s15.sec)) + "," +
          NqJsonN("atr5", atr5, g_digits) + "," + NqJsonN("atr1", g_s1.atr[n1 - 1], g_digits) + "," +
          NqJsonN("atr15", g_s15.atr[n15 - 1], g_digits) + "," + NqJsonI("atr_period", InpNrtrAtrPeriod) + "," +
          NqJsonN("bid", SymbolInfoDouble(g_sym, SYMBOL_BID), g_digits) + "," +
          NqJsonN("ask", SymbolInfoDouble(g_sym, SYMBOL_ASK), g_digits) + "," + NqJsonI("spread_pts", g_spreadPts);
   }
   else
      j = j + NqJsonS("state", "UNKNOWN");
   j = j + "},";

   // M15 context (never gates - the EA's own word)
   j = j + "\"m15\":{";
   if(ok)
      j = j + NqJsonS("context", NqContextText(g_s15.ctx[n15 - 1])) + "," + NqJsonS("nrtr_dir", NqDirText(g_s15.dir[n15 - 1])) + "," +
          NqJsonN("nrtr_level", g_s15.stop[n15 - 1], g_digits) + "," + NqJsonN("ema_slow", g_s15.emaS[n15 - 1], g_digits) + "," +
          NqJsonI("ema_slow_period", InpEmaSlow) + "," + NqJsonN("close", g_s15.c[n15 - 1], g_digits) + "," +
          NqJsonI("closed_server", (long)g_s15.t[n15 - 1]);
   else
      j = j + NqJsonS("context", "UNKNOWN");
   j = j + "},";

   // M5 regime + structure
   j = j + "\"m5\":{";
   if(ok)
   {
      int st = g_s5.st[n5 - 1];
      string stS = (st == NQ_ST_BULL) ? "BULL" : ((st == NQ_ST_BEAR) ? "BEAR" : ((st == NQ_ST_MIXED) ? "MIXED" : "NOT CONFIRMED"));
      j = j + NqJsonS("regime", NqRegimeText(g_s5.regime[n5 - 1])) + "," + NqJsonS("nrtr_dir", NqDirText(g_s5.dir[n5 - 1])) + "," +
          NqJsonN("nrtr_level", g_s5.stop[n5 - 1], g_digits) + "," +
          NqJsonS("structure", NqStructText(st, g_s5.hl[n5 - 1], g_s5.ll[n5 - 1], g_s5.lk[n5 - 1])) + "," +
          NqJsonS("structure_state", stS) + "," + NqJsonI("lookback", InpSwingStrength) + "," +
          NqJsonNames("reasons", g_s5.regR[n5 - 1], false) + "," +
          NqJsonN("close", g_s5.c[n5 - 1], g_digits) + "," + NqJsonI("closed_server", (long)g_s5.t[n5 - 1]);
      if(ArraySize(g_resAbove) >= n5 && ArraySize(g_supBelow) >= n5)
         j = j + "," + NqJsonN("res_above", g_resAbove[n5 - 1], g_digits) + "," + NqJsonN("sup_below", g_supBelow[n5 - 1], g_digits);
   }
   else
      j = j + NqJsonS("regime", "UNKNOWN");
   j = j + "},";

   // M1 trigger + forecast
   j = j + "\"m1\":{";
   if(ok)
   {
      int st1 = g_s1.state[n1 - 1];
      int fc = g_s1.fc[n1 - 1];
      int cnt = 0;
      int hits = 0;
      NqForecastStats(g_s1, 0, cnt, hits);
      j = j + NqJsonS("nrtr_dir", NqDirText(g_s1.dir[n1 - 1])) + "," + NqJsonN("nrtr_level", g_s1.stop[n1 - 1], g_digits) + "," +
          NqJsonS("trigger", (st1 == NQ_BUY) ? "BUY" : ((st1 == NQ_SELL) ? "SELL" : "WAIT")) + "," +
          NqJsonNames("reasons", g_s1.reasons[n1 - 1], false) + "," +
          NqJsonS("forecast_next", (fc > 0) ? "UP" : ((fc < 0) ? "DOWN" : "NONE")) + "," + NqJsonI("forecast_score", g_s1.fcScore[n1 - 1]) + "," +
          NqJsonI("forecast_resolved", cnt) + "," + NqJsonI("forecast_hits", hits) + "," + NqJsonS("forecast_evidence", NqEvidenceText(cnt)) + "," +
          NqJsonN("ema_fast", g_s1.emaF[n1 - 1], g_digits) + "," + NqJsonI("ema_fast_period", InpEmaFast) + "," +
          NqJsonN("close", g_s1.c[n1 - 1], g_digits) + "," + NqJsonI("closed_server", (long)g_s1.t[n1 - 1]);
   }
   else
      j = j + NqJsonS("trigger", "UNKNOWN");
   j = j + "},";

   // OBSERVED EA STATE: the verdict the panel shows a human, and the gates
   j = j + "\"observed\":{" + NqJsonS("label", "OBSERVED EA STATE - not a SignalMesh recommendation") + "," +
       NqJsonS("verdict", g_verdict) + "," + NqJsonS("near", g_nearText) + "," +
       NqJsonS("final", (g_final == NQ_BUY) ? "BUY" : ((g_final == NQ_SELL) ? "SELL" : "WAIT")) + "," +
       NqJsonS("final_reason", NqReasonAt(g_finalR, 0)) + "," + NqJsonNames("gate", g_gate, true) + "," +
       NqJsonB("algo_trading", (g_gate & NQ_K_TRADE_DISABLED) == 0) + "," + NqJsonB("auto_scalp", InpScalpAuto) + "," +
       NqJsonB("pending_auto", InpPendingAuto) + "," + NqJsonB("allow_real", InpAllowRealAccount) + "},";

   // the SCALP M1 row exactly as the board shows it
   j = j + "\"scalp_row\":{";
   if(ok)
   {
      int reg = g_s5.regime[n5 - 1];
      int k5 = g_s1.map[n1 - 1];
      double atr5 = (k5 >= 0) ? g_s5.atr[k5] : g_s5.atr[n5 - 1];
      double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
      double slD = NormalizeDouble(InpScalpSlAtr * atr5, g_digits);
      double tpD = NormalizeDouble(InpScalpTpAtr * atr5, g_digits);
      int st1 = g_s1.state[n1 - 1];
      string side = (reg == NQ_REG_BULL) ? "BUY MKT" : ((reg == NQ_REG_BEAR) ? "SELL MKT" : "NONE");
      string stT = "WAIT: M5 CHOP - no direction";
      double entry = bid;
      double sl = 0.0;
      double tp = 0.0;
      if(atr5 > 0.0 && (reg == NQ_REG_BULL || reg == NQ_REG_BEAR))
      {
         entry = (reg > 0) ? ask : bid;
         sl = (reg > 0) ? NqRoundTick(entry - slD, g_tick, g_digits, -1) : NqRoundTick(entry + slD, g_tick, g_digits, 1);
         tp = (reg > 0) ? NqRoundTick(entry + tpD, g_tick, g_digits, 1) : NqRoundTick(entry - tpD, g_tick, g_digits, -1);
         if(st1 == NQ_BUY || st1 == NQ_SELL)
            stT = "TRIGGER NOW" + (InpScalpAuto ? ((g_gate == 0) ? " - auto" : (" - " + NqGateAtX(g_gate, 0))) : " - manual");
         else
            stT = "WAIT: " + NqReasonAt(g_s1.reasons[n1 - 1], 0);
      }
      else if(atr5 <= 0.0)
         stT = "ATR not ready";
      j = j + NqJsonS("side", side) + "," + NqJsonN("entry", entry, g_digits) + "," + NqJsonN("sl", sl, g_digits) + "," +
          NqJsonN("tp", tp, g_digits) + "," + NqJsonN("lot", g_lotNext, 2) + "," + NqJsonN("loss_at_sl", g_lossNext, 2) + "," +
          NqJsonN("sl_atr", InpScalpSlAtr, 2) + "," + NqJsonN("tp_atr", InpScalpTpAtr, 2) + "," + NqJsonI("time_stop_bars", InpScalpTimeStop) + "," +
          NqJsonS("state", stT);
   }
   else
      j = j + NqJsonS("state", "UNKNOWN");
   j = j + "},";

   // impulse radar and NY trap state, as the board shows them
   j = j + "\"radar\":{\"up\":{" + NqJsonS("state", NqRadarStateText(g_rdUp.state)) + "," + NqJsonI("score", g_rdUp.score) + "," +
       NqJsonS("pressure", NqPressureText(g_rdUp.score)) + "," + NqJsonN("level", g_rdUp.level, g_digits) + "," + NqJsonN("dist_atr", g_rdUp.dist, 2) + "}," +
       "\"down\":{" + NqJsonS("state", NqRadarStateText(g_rdDn.state)) + "," + NqJsonI("score", g_rdDn.score) + "," +
       NqJsonS("pressure", NqPressureText(g_rdDn.score)) + "," + NqJsonN("level", g_rdDn.level, g_digits) + "," + NqJsonN("dist_atr", g_rdDn.dist, 2) + "}},";
   j = j + "\"ny\":{" + NqJsonS("high_side", NqNyStateText(g_nyState.stBull)) + "," + NqJsonS("low_side", NqNyStateText(g_nyState.stBear)) + "," +
       NqJsonB("in_session", g_nyState.inSession) + "," + NqJsonB("pre_range_ok", g_nyState.preOk) + "," +
       NqJsonN("pre_hi", g_nyState.preHi, g_digits) + "," + NqJsonN("pre_lo", g_nyState.preLo, g_digits) + "},";

   // every plan slot the board shows (latest per slot, whatever its status) + the latest scalp record
   j = j + "\"plans\":[";
   int shown = 0;
   for(int q = 0; q < NQ_PLAN_SLOTS; q++)
   {
      NqPlan pl;
      if(!NqSlotPlan(q, pl))
         continue;
      string slot = (q == 0) ? "QML M5" : ((q == 1) ? "PULLBACK M5" : ((q == 2) ? "NY TRAP" : ((q == 3) ? "QML M15" :
                    ((q == 4) ? "PULLBACK M15" : ((q == 5) ? "RADAR UP" : "RADAR DOWN")))));
      j = j + ((shown > 0) ? "," : "") + NqTelemetryPlan(pl, slot);
      shown++;
   }
   if(g_nSig > 0)
   {
      NqPlan sp;
      NqScalpAsPlan(g_nSig - 1, sp);
      j = j + ((shown > 0) ? "," : "") + NqTelemetryPlan(sp, "SCALP M1");
   }
   j = j + "],";

   // v1.9: the higher timeframes, the witnesses, the vote, the news, the week, the smart exit, the portfolio (every field observed)
   j = j + "\"htf\":{\"h4\":{" + NqJsonB("ok", g_h4Ok) + "," + NqJsonS("context", (g_h4Ok && g_h4.n > 0 && g_h4.emaS[g_h4.n - 1] > 0.0) ? NqContextText(g_h4.ctx[g_h4.n - 1]) : "NOT READY") + "," +
       NqJsonS("structure", (g_h4Ok && g_h4.n > 0) ? NqStructText(g_h4.st[g_h4.n - 1], g_h4.hl[g_h4.n - 1], g_h4.ll[g_h4.n - 1], g_h4.lk[g_h4.n - 1]) : "") + "," +
       NqJsonS("last_break", g_h4Ok ? NqBreakText(g_h4, g_sbH4, g_nSbH4) : "") + "," + NqJsonI("bars", g_h4Ok ? g_h4.n : 0) + "}," +
       "\"h1\":{" + NqJsonB("ok", g_h1Ok) + "," + NqJsonS("context", (g_h1Ok && g_h1.n > 0 && g_h1.emaS[g_h1.n - 1] > 0.0) ? NqContextText(g_h1.ctx[g_h1.n - 1]) : "NOT READY") + "," +
       NqJsonS("structure", (g_h1Ok && g_h1.n > 0) ? NqStructText(g_h1.st[g_h1.n - 1], g_h1.hl[g_h1.n - 1], g_h1.ll[g_h1.n - 1], g_h1.lk[g_h1.n - 1]) : "") + "," +
       NqJsonS("last_break", g_h1Ok ? NqBreakText(g_h1, g_sbH1, g_nSbH1) : "") + "," + NqJsonI("bars", g_h1Ok ? g_h1.n : 0) + "}," +
       "\"m5_last_break\":" + "\"" + NqJsonEsc(NqBreakText(g_s5, g_sbrk, g_nSbrk)) + "\"},";
   j = j + "\"witnesses\":{\"dxy\":{" + NqJsonS("symbol", g_macroSym) + "," + NqJsonS("dir", (g_macroDir == 0) ? "" : NqDirText(g_macroDir)) + "}," +
       "\"bond\":{" + NqJsonS("symbol", g_bondSym) + "," + NqJsonS("kind", g_bondYield ? "yield" : "price") + "," + NqJsonS("dir", (g_bondDir == 0) ? "" : NqDirText(g_bondDir)) + "}},";
   {
      string whyB = "";
      string whyS = "";
      int vb = NqMacroVote(1, whyB);
      int vs = NqMacroVote(-1, whyS);
      j = j + "\"macro\":{" + NqJsonI("buy_vote", vb) + "," + NqJsonI("sell_vote", vs) + "," + NqJsonS("buy_voters", whyB) + "," + NqJsonS("sell_voters", whyS) + "," +
          NqJsonB("gate", g_macroGate) + "," + NqJsonI("block_level", InpMacroBlockLevel) + "},";
   }
   j = j + "\"news\":{" + NqJsonS("state", g_newsTester ? "N/A" : (!g_newsGuard ? "OFF" : (g_newsUnknown ? "UNKNOWN" : (g_newsBlock ? "GUARD" : "CLEAR")))) + "," +
       NqJsonS("text", g_newsText) + "," + NqJsonB("block", g_newsBlock) + "," + NqJsonB("unknown", g_newsUnknown) + "," + NqJsonI("events_cached", g_nEv) + "," +
       NqJsonI("read_at_server", (long)g_newsReadT) + "," + NqJsonI("before_min", InpNewsBeforeMin) + "," + NqJsonI("after_min", InpNewsAfterMin) + ",\"events\":[";
   {
      int shownE = 0;
      for(int i = 0; i < g_nEv && shownE < 12; i++)
      {
         if(g_evT[i] < nowS - 6 * 3600)
            continue;
         j = j + ((shownE > 0) ? "," : "") + "{" + NqJsonS("ccy", g_evCcy[i]) + "," + NqJsonS("name", g_evName[i]) + "," + NqJsonI("time_server", (long)g_evT[i]) + "," +
             NqJsonI("importance", g_evImp[i]) + "," + NqJsonB("top_tier", g_evTop[i]) + "," + NqJsonI("impact", g_evImpact[i]) + "}";
         shownE++;
      }
   }
   j = j + "]},";
   j = j + "\"session\":{" + NqJsonS("now", NqSessionName()) + "," + NqJsonB("rollover", g_rollover) + "," + NqJsonB("week_edge", g_weekEdge) + "," +
       NqJsonS("week_text", g_weekText) + "," + NqJsonI("dow", g_dow) + "," + NqJsonS("clock", g_clkText) + "},";
   j = j + "\"portfolio\":{" + NqJsonI("positions", g_portfolioPos) + "," + NqJsonI("max", InpMaxOpenAcrossCharts) + "},";
   j = j + "\"smart_exit\":{" + NqJsonB("on", g_smartExit) + "," + NqJsonN("flip_profit_r", InpSmartFlipProfitR, 2) + "," + NqJsonB("flip_cut_loss", InpSmartFlipCutLoss) + "," +
       NqJsonN("m1_profit_r", InpSmartM1ProfitR, 2) + "," + NqJsonN("lock_at_r", InpSmartLockAtR, 2) + "," + NqJsonN("lock_r", InpSmartLockR, 2) + "," + NqJsonS("last", g_smartNote) + "},";
   // the account as the EA sees it (this magic, this symbol) - no identity, no credentials
   j = j + "\"account\":{" + NqJsonN("balance", g_balance, 2) + "," + NqJsonN("floating", g_floating, 2) + "," +
       NqJsonN("day_pnl", g_dayPnl, 2) + "," + NqJsonI("open_positions", g_openCount) + "," + NqJsonI("pending_orders", g_pendCount) + "," +
       NqJsonI("manual_positions", g_manualPos) + "," + NqJsonI("manual_orders", g_manualOrd) + "," + NqJsonI("trades_today", g_tradesToday) + "," +
       NqJsonN("risk_pct", InpRiskPct, 2) + "," + NqJsonN("risk_money", g_riskMoney, 2) + "," + NqJsonS("last_trade", g_lastTrade) + "},";

   // the RECORD rows: what the loaded history says happened to each engine
   int done = 0;
   int won = 0;
   int lost = 0;
   NqSignalStats(g_sigs, g_nSig, done, won, lost);
   j = j + "\"record\":{" + NqTelemetryRecord("scalp", done, won, lost);
   NqPlanStats(g_plans, g_nPlans, NQ_PLAN_QML, done, won, lost);
   j = j + "," + NqTelemetryRecord("qml", done, won, lost);
   NqPlanStats(g_plans, g_nPlans, NQ_PLAN_PB, done, won, lost);
   j = j + "," + NqTelemetryRecord("pullback", done, won, lost);
   NqPlanStats(g_ny, g_nNy, NQ_PLAN_NY, done, won, lost);
   j = j + "," + NqTelemetryRecord("ny_trap", done, won, lost);
   NqPlanStats(g_radar, g_nRadar, NQ_PLAN_RADAR, done, won, lost);
   j = j + "," + NqTelemetryRecord("radar", done, won, lost) + "}";
   return j + "}";
}

// one heartbeat: on every closed M1 candle and at least every g_telSec seconds
void NqTelemetry()
{
   if(g_telUrl == "")
      return;
   if(g_telDemoOnly && !g_isDemo)
   {
      if(!g_telWarned)
         Print("NQ telemetry: REAL account and demo-only is on - nothing is sent (the witness must be a DEMO account)");
      g_telWarned = true;
      return;
   }
   datetime now = TimeTradeServer();
   if(!g_newBar1 && g_telLast != 0 && now - g_telLast < g_telSec)
      return;
   g_telLast = now;
   if(NqPost(g_telUrl, NqTelemetryJson()))
   {
      if(g_telSent == 0 || g_telFails > 0)
         Print("NQ telemetry: snapshot accepted by SignalMesh (ANALYSIS ONLY)");
      g_telSent++;
      g_telFails = 0;
      return;
   }
   g_telFails++;
   if(g_telFails == 1 || g_telFails == 10 || g_telFails % 100 == 0)
      Print("NQ telemetry: POST failed (" + IntegerToString(g_telFails) + " in a row) - the page shows STALE; trading is unaffected");
}

int NqJrFind(string cmt)
{
   for(int i = 0; i < g_jrN; i++)
      if(g_jrCmt[i] == cmt)
         return i;
   return -1;
}

void NqJrSet(string cmt, int status)
{
   int i = NqJrFind(cmt);
   if(i < 0)
   {
      ArrayResize(g_jrCmt, g_jrN + 1, 64);
      ArrayResize(g_jrStatus, g_jrN + 1, 64);
      g_jrCmt[g_jrN] = cmt;
      g_jrStatus[g_jrN] = status;
      g_jrN++;
   }
   else
      g_jrStatus[i] = status;
}

// one plan: emit "armed" when first seen (after seeding), the status event on change
void NqJrPlan(const NqPlan &p)
{
   string cmt = NqSignalIdOf(p);
   int i = NqJrFind(cmt);
   if(i < 0)
   {
      NqJrSet(cmt, p.status);
      if(g_jrSeeded)
      {
         NqEmit(p, "armed", "");
         if(p.status != NQ_PL_ACTIVE)
            NqEmit(p, NqEventOfStatus(p.status), "");
      }
      return;
   }
   if(g_jrStatus[i] != p.status)
   {
      g_jrStatus[i] = p.status;
      NqEmit(p, NqEventOfStatus(p.status), "");
   }
}

void NqScalpAsPlan(int k, NqPlan &p)
{
   p.kind = NQ_PLAN_SCALP;
   p.tf = g_s1.sec;
   p.dir = g_sigs[k].dir;
   p.idx = g_sigs[k].idx;
   p.keyTime = g_s1.t[g_sigs[k].idx];
   p.madeAt = g_s1.t[g_sigs[k].idx] + g_s1.sec;
   p.entry = g_sigs[k].entry;
   p.sl = g_sigs[k].sl;
   p.tp1 = g_sigs[k].tp;
   p.tp2 = g_sigs[k].tp;
   p.risk = g_sigs[k].risk;
   p.lvlA = 0.0;
   p.lvlB = 0.0;
   int st = NQ_PL_ACTIVE;
   if(g_sigs[k].status == NQ_SIG_TP)
      st = NQ_PL_TP1;
   else if(g_sigs[k].status == NQ_SIG_SL)
      st = NQ_PL_SL;
   else if(g_sigs[k].status == NQ_SIG_TIMEOUT)
      st = NQ_PL_EXPIRED;
   p.status = st;
   p.statusIdx = g_sigs[k].statusIdx;
   p.fillIdx = g_sigs[k].idx;
}

// after every recompute: walk every plan record and the scalp records
void NqJournalScan()
{
   for(int k = 0; k < g_nPlans; k++)
      NqJrPlan(g_plans[k]);
   for(int k = 0; k < g_nNy; k++)
      NqJrPlan(g_ny[k]);
   for(int k = 0; k < g_nSwing; k++)
      NqJrPlan(g_swing[k]);
   for(int k = 0; k < g_nRadar; k++)
      NqJrPlan(g_radar[k]);
   for(int k = 0; k < g_nSig; k++)
   {
      NqPlan p;
      NqScalpAsPlan(k, p);
      NqJrPlan(p);
   }
   g_jrSeeded = true;
}

// broker-side events (placed / rejected / opened / closed by the EA)
void NqEmitBroker(string comment, string event, string extra)
{
   NqPlan p;
   if(StringFind(comment, NQ_CMT_SCALP) == 0)
   {
      long t = StringToInteger(StringSubstr(comment, StringLen(NQ_CMT_SCALP)));
      int found = -1;
      for(int k = g_nSig - 1; k >= 0; k--)
         if((long)g_s1.t[g_sigs[k].idx] == t) { found = k; break; }
      if(found < 0)
         return;
      NqScalpAsPlan(found, p);
      if(event == "scalp_open")
         p.status = NQ_PL_FILLED;
   }
   else if(!NqPlanByComment(comment, p))
      return;
   NqEmit(p, event, extra);
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

   // 0) the week's edge and a news window: resting orders are pulled, a position in profit is
   //    banked. Closing is never blocked by the gate; these run before anything else.
   bool bankNews = (g_newsBlock && InpNewsBankProfitR > 0.0 && g_newsWinT != 0);
   if(g_weekFriday || g_newsBlock)
   {
      int otE = OrdersTotal();
      for(int i = otE - 1; i >= 0; i--)
      {
         ulong tk = OrderGetTicket(i);
         if(tk == 0)
            continue;
         if(!NqIsOurs(OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
            continue;
         if(g_weekFriday)
            NqCancel(tk, "WEEKEND: resting orders are pulled before the Friday close");
         else
            NqCancel(tk, "NEWS GUARD: resting orders are pulled through " + g_newsWhy + " - the plan is re-placed when the window ends");
      }
   }
   if((g_weekFriday && InpWeekendFlat) || bankNews)
   {
      int totE = PositionsTotal();
      for(int i = totE - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if(tk == 0)
            continue;
         if(!NqIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
            continue;
         int pdir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         double px = (pdir > 0) ? SymbolInfoDouble(g_sym, SYMBOL_BID) : SymbolInfoDouble(g_sym, SYMBOL_ASK);
         double r = NqPosR(PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL), px, pdir, PositionGetString(POSITION_COMMENT));
         string rT = ((r >= 0.0) ? "+" : "") + DoubleToString(r, 2) + "R";
         if(g_weekFriday && InpWeekendFlat)
         {
            if(r >= InpWeekendMinProfitR)
               NqClosePosition(tk, "WEEKEND: banking " + rT + " before the Friday close");
            else if(InpWeekendCloseLosers)
               NqClosePosition(tk, "WEEKEND: closing " + rT + " before the Friday close (no gap risk)");
         }
         else if(bankNews && r >= InpNewsBankProfitR)
            NqClosePosition(tk, "NEWS: banking " + rT + " before " + g_newsWhy);
      }
   }

   // 1) manage open positions: radar false break, SMART EXIT (lock / bank / cut on a bias
   //    change), the scalp's time stop and flip rule, the optional hard flip rule for
   //    plans. Works even when the gate is closed - closing is never blocked, only opening is.
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(!NqIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
         continue;
      string cmt = PositionGetString(POSITION_COMMENT);
      int pdir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      // radar FALSE BREAK: the M5 bar that filled the stop, or the next one, CLOSED
      // back through the level -> out at once, whatever the SL says
      if(StringFind(cmt, NQ_CMT_RD) == 0)
      {
         NqPlan rp;
         if(g_newBar5 && g_fresh && NqPlanByComment(cmt, rp))
         {
            long ageBars5 = ((long)now - (long)opened) / g_s5.sec;
            double c5 = g_s5.c[n5 - 1];
            bool back = (pdir > 0) ? (c5 < rp.lvlA) : (c5 > rp.lvlA);
            if(ageBars5 <= 2 && back)
            {
               NqClosePosition(tk, "radar FALSE BREAK: M5 closed back through " + DoubleToString(rp.lvlA, g_digits));
               continue;
            }
         }
      }
      bool isScalp = (StringFind(cmt, NQ_CMT_SCALP) == 0);
      // SL GUARD: a position of ours without a stop (a broker that stripped it, a hand edit) gets the plan's
      // stop back; if the price is already beyond it, the position is closed now
      if(g_fresh && PositionGetDouble(POSITION_SL) <= 0.0)
      {
         double tpWant = PositionGetDouble(POSITION_TP);
         double want = NqPlanSlOf(cmt, tpWant);
         if(want > 0.0)
         {
            double pxG = (pdir > 0) ? SymbolInfoDouble(g_sym, SYMBOL_BID) : SymbolInfoDouble(g_sym, SYMBOL_ASK);
            bool beyond = (pdir > 0) ? (pxG <= want) : (pxG >= want);
            if(beyond)
            {
               NqClosePosition(tk, "SL MISSING and the price is already beyond the plan's stop " + NqPx(want) + " - closing");
               continue;
            }
            double minDistG = g_stopsLevel * g_point;
            bool legal = (pdir > 0) ? (want < pxG - minDistG) : (want > pxG + minDistG);
            if(legal)
               NqModifySl(tk, want, tpWant, "SL MISSING: the plan's stop " + NqPx(want) + " restored");
            PositionSelectByTicket(tk);
         }
      }
      if(g_fresh && NqSmartExit(tk, pdir, cmt, isScalp, reg5))
         continue;
      if(!isScalp)
      {
         // structure plans: optional hard close when the M5 regime turns against them
         if(InpPlanCloseOnFlip && g_newBar5 && g_fresh && NqIsPlanComment(cmt) && reg5 != NQ_REG_CHOP && reg5 != pdir)
            NqClosePosition(tk, "M5 regime turned " + NqRegimeText(reg5) + " against the " + NqKindOfComment(cmt) + " position");
         continue;
      }
      long ageBars = ((long)now - (long)opened) / g_s1.sec;
      if(ageBars >= InpScalpTimeStop)
         NqClosePosition(tk, "scalp time stop: " + IntegerToString(ageBars) + " M1 bars without TP/SL");
      else if(InpScalpCloseOnFlip && g_fresh && reg5 != NQ_REG_CHOP && reg5 != pdir)
         NqClosePosition(tk, "M5 regime turned " + NqRegimeText(reg5) + " against the scalp");
   }

   // 2) ONE SLOT PER ASSET: while any position of this EA is open on this
   //    symbol, every waiting limit order is cancelled and nothing new is
   //    opened. The first fill takes the slot; the market decides which of
   //    the armed plans was "better".
   if(g_openCount > 0)
   {
      // two limits can fill inside the same minute: the oldest position keeps
      // the slot, every later one is closed at once (the rule, not a choice)
      if(g_openCount > 1)
      {
         ulong keep = 0;
         datetime keepT = 0;
         int total2 = PositionsTotal();
         for(int i = 0; i < total2; i++)
         {
            ulong tk = PositionGetTicket(i);
            if(tk == 0)
               continue;
            if(!NqIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
               continue;
            datetime pt = (datetime)PositionGetInteger(POSITION_TIME);
            if(keep == 0 || pt < keepT || (pt == keepT && tk < keep))
            {
               keep = tk;
               keepT = pt;
            }
         }
         for(int i = total2 - 1; i >= 0; i--)
         {
            ulong tk = PositionGetTicket(i);
            if(tk == 0 || tk == keep)
               continue;
            if(!NqIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
               continue;
            NqClosePosition(tk, "one slot per asset: #" + IntegerToString((long)keep) + " was first");
         }
      }
      int ot = OrdersTotal();
      for(int i = ot - 1; i >= 0; i--)
      {
         ulong tk = OrderGetTicket(i);
         if(tk == 0)
            continue;
         if(!NqIsOurs(OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
            continue;
         NqCancel(tk, "slot taken: a position is already open on " + g_sym);
      }
      g_note = "SLOT TAKEN - " + g_posText;
      return;
   }

   // 3) pending plans <-> pending orders (slot free)
   if(g_fresh)
   {
      // cancel orders whose plan is gone, no longer active, or switched off
      int ot = OrdersTotal();
      for(int i = ot - 1; i >= 0; i--)
      {
         ulong tk = OrderGetTicket(i);
         if(tk == 0)
            continue;
         if(!NqIsOurs(OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
            continue;
         string cmt = OrderGetString(ORDER_COMMENT);
         if(!NqIsPlanComment(cmt))
            continue;   // not one of our plan orders
         NqPlan pl;
         if(!NqPlanByComment(cmt, pl))
            NqCancel(tk, "plan no longer exists (history window moved)");
         else if(pl.status != NQ_PL_ACTIVE)
            NqCancel(tk, "plan " + NqPlanStatusText(pl.status));
         else if(!NqKindEnabled(pl))
            NqCancel(tk, NqPlanKindText(pl.kind) + " trading switched off");
         else if(NqSpikeBlocks(pl))
            NqCancel(tk, "SPIKE GUARD: a " + NqPlanKindText(pl.kind) + " in the direction of a " + DoubleToString(g_spikeAtr, 1) + " ATR spike - the bounce of a spike is not a setup");
         else if(g_newsBlock)
            NqCancel(tk, "NEWS GUARD: resting orders are pulled through " + g_newsWhy + " - the plan is re-placed when the window ends");
      }
      // place orders for every armed plan of an enabled kind
      if(InpPendingAuto)
      {
         for(int q = 0; q < NQ_PLAN_SLOTS; q++)
         {
            NqPlan pl;
            if(!NqSlotPlan(q, pl) || pl.status != NQ_PL_ACTIVE || !NqKindEnabled(pl))
               continue;
            if(NqFindPlanOrder(pl) != 0)
               continue;
            // filled on an M1 bar but not yet seen by the engine: never place it twice
            if(NqPlanHasPosition(pl))
               continue;
            if(g_gate != 0)
               continue;
            if(NqSpikeBlocks(pl))
            {
               g_note = "SPIKE GUARD: " + NqPlanKindText(pl.kind) + " " + ((pl.dir > 0) ? "BUY" : "SELL") + " in the direction of a " +
                        DoubleToString(g_spikeAtr, 1) + " ATR spike - the bounce of a spike is not a setup, not placed";
               continue;
            }
            double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
            double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
            double minDist = g_stopsLevel * g_point;
            bool isStop = NqPlanIsStop(pl);
            bool sideOk = false;
            if(isStop)
               sideOk = (pl.dir > 0) ? (pl.entry > ask + minDist) : (pl.entry < bid - minDist);
            else
               sideOk = (pl.dir > 0) ? (pl.entry < ask - minDist) : (pl.entry > bid + minDist);
            if(!sideOk)
            {
               g_note = NqPlanKindText(pl.kind) + ": PRICE ALREADY PAST THE LEVEL - NOT PLACED";
               continue;
            }
            // MACRO VOTE (every plan kind): the dollar index, the bond, the news, H4 / H1. A strong vote AGAINST
            // the plan's direction is a block, unless the metal's OWN structure is A+
            int rdScore = (pl.dir > 0) ? g_rdUp.score : g_rdDn.score;
            string mwhy = "";
            if(NqMacroBlocks(pl.dir, rdScore, isStop, mwhy))
            {
               g_note = NqPlanKindText(pl.kind) + ": " + mwhy;
               continue;
            }
            // volatility EXPANSION: a breakout needs stronger confirmation
            if(isStop && g_volClass == NQ_VOL_EXPANSION && rdScore < InpVolExpandRadar)
            {
               g_note = "RADAR: VOLATILITY EXPANSION - needs score " + IntegerToString(InpVolExpandRadar) + " (" + IntegerToString(rdScore) + "/10)";
               continue;
            }
            double tp = InpPlanUseTp2 ? pl.tp2 : pl.tp1;
            double lot = 0.0;
            int og = NqOrderGate(pl.dir, pl.entry, pl.sl, tp, lot, (int)NqPlanOrderType(pl));
            if(og != 0)
            {
               g_note = NqPlanKindText(pl.kind) + ": " + NqGateAtX(og, 0);
               continue;
            }
            string tfT = (pl.tf == 900) ? "M15" : "M5";
            string why = NqPlanKindText(pl.kind) + " " + tfT + " plan, key " + TimeToString(pl.keyTime, TIME_DATE | TIME_MINUTES) +
                         (isStop ? (", level " + DoubleToString(pl.lvlA, g_digits) + ", score " + IntegerToString((pl.dir > 0) ? g_rdUp.score : g_rdDn.score) + "/10") : "") +
                         ", risk " + DoubleToString(InpRiskPct, 2) + "% = " + DoubleToString(g_riskMoney, 2) + " " + g_accCcy;
            NqPending(pl.dir, pl.entry, lot, pl.sl, tp, NqPlanComment(pl), why, isStop);
         }
      }
   }

   // 4) scalp entry on a fresh trigger (the just-closed M1 candle): lowest
   //    priority - never while a plan order is waiting for its level
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
   // live count, not the one read before this tick placed orders
   int waiting = 0;
   int otNow = OrdersTotal();
   for(int i = 0; i < otNow; i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk != 0 && NqIsOurs(OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
         waiting++;
   }
   if(waiting > 0)
   {
      g_note = "SCALP TRIGGER " + sideT + " - a plan order is waiting, scalp stands aside";
      return;
   }
   if(g_gate != 0)
   {
      g_note = "SCALP TRIGGER " + sideT + " - " + NqGateAtX(g_gate, 0);
      return;
   }
   if(InpSpikeGuard && g_spikeDir != 0 && st == g_spikeDir)
   {
      g_note = "SCALP TRIGGER " + sideT + " - SPIKE GUARD: " + DoubleToString(g_spikeAtr, 1) + " ATR spike in this direction, not chasing";
      return;
   }
   if(InpVolExpandScalpM15 && g_volClass == NQ_VOL_EXPANSION && g_s15.n > 0 && g_s15.ctx[g_s15.n - 1] != st)
   {
      g_note = "SCALP TRIGGER " + sideT + " - VOLATILITY EXPANSION: the M15 context must agree";
      return;
   }
   string mwhy = "";
   if(NqMacroBlocks(st, 0, false, mwhy))
   {
      g_note = "SCALP TRIGGER " + sideT + " - " + mwhy;
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
      g_note = "SCALP TRIGGER " + sideT + " - " + NqGateAtX(og, 0);
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

void NqArrow(string name, datetime t, double price, int dir, color clr, int width, string tip)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, (dir > 0) ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, (dir > 0) ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
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
   // the label sits at the newest bar, so it is on screen however far the line started
   datetime lt = (g_labelT > 0 && g_labelT > t) ? g_labelT : t;
   NqText(name + "_T", lt, price, txt + " " + DoubleToString(price, g_digits), clr, 8, ANCHOR_LEFT_LOWER, txt);
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
      string tip = tfName + " bias at " + TimeToString(s.t[i - 1] + s.sec, TIME_MINUTES) + ": " +
                   ((f > 0) ? "UP" : "DOWN") + " (score " + IntegerToString(s.fcScore[i - 1]) + ") - " +
                   ((hit > 0) ? "HIT +0.5 ATR" : ((hit < 0) ? "MISS -0.5 ATR" : "unresolved"));
      NqArrow(NQ_PFX_A + IntegerToString((long)s.t[i]), s.t[i], price, f, clr, 1, tip);
   }
   // the live arrow: forecast for the candle that is forming right now,
   // drawn big and white on the forming candle with a NEXT label
   int fl = s.fc[n - 1];
   if(fl != 0)
   {
      datetime tl = s.t[n - 1] + s.sec;
      double off = (s.atr[n - 1] > 0.0) ? s.atr[n - 1] * 0.25 : 0.0;
      double price = (fl > 0) ? s.l[n - 1] - off : s.h[n - 1] + off;
      string tip = "LIVE " + tfName + " forecast for the forming candle: " + ((fl > 0) ? "UP" : "DOWN") +
                   " (score " + IntegerToString(s.fcScore[n - 1]) + ")";
      NqArrow(NQ_PFX_A + "LIVE", tl, price, fl, clrWhite, 3, tip);
      double off2 = (s.atr[n - 1] > 0.0) ? s.atr[n - 1] * 1.2 : 0.0;
      NqText(NQ_PFX_A + "LIVE_T", tl, (fl > 0) ? price - off2 : price + off2, "NEXT " + ((fl > 0) ? NqSymUp() : NqSymDown()),
             clrWhite, 9, (fl > 0) ? ANCHOR_UPPER : ANCHOR_LOWER, tip);
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
   // session levels (support / resistance), break marks and the day VWAP
   if(InpDrawLevels && g_levels.day == NqDayOf(g_s5.t[n5 - 1]))
   {
      color cLv[10];
      cLv[0] = NQ_RGB(212, 175, 55);  cLv[1] = NQ_RGB(212, 175, 55);    // previous day: gold
      cLv[2] = NQ_RGB(0, 190, 190);   cLv[3] = NQ_RGB(0, 190, 190);     // Asia: teal
      cLv[4] = NQ_RGB(90, 150, 255);  cLv[5] = NQ_RGB(90, 150, 255);    // London: blue
      cLv[6] = NQ_RGB(170, 170, 170); cLv[7] = NQ_RGB(170, 170, 170);   // pre-NY: grey
      cLv[8] = NQ_RGB(200, 120, 255); cLv[9] = NQ_RGB(200, 120, 255);   // NY: purple
      for(int lv = 0; lv < NQ_LV_COUNT; lv++)
      {
         if(!g_levels.ok[lv])
            continue;
         datetime from = (g_levels.from[lv] > 0) ? g_levels.from[lv] : g_s5.t[n5 - 1];
         string tag = NqLevelName(lv) + (g_levels.act[lv] ? "" : " (building)") + (g_levels.broken[lv] ? " broken" : "");
         NqLevel(NQ_PFX_C + "LV_" + IntegerToString(lv), from, g_levels.px[lv], cLv[lv],
                 g_levels.act[lv] ? STYLE_SOLID : STYLE_DOT, tag);
      }
      // structure S/R: the two nearest confirmed swing highs above and lows below the
      // price, as rays from the swing, and every confirmed break of a swing
      double cNow = g_s5.c[n5 - 1];
      for(int side = 0; side < 2; side++)
      {
         int kind = (side == 0) ? 1 : -1;
         double bound = 0.0;
         for(int pass = 0; pass < 2; pass++)
         {
            double best = 0.0;
            int bestP = -1;
            for(int p = g_s5.np - 1; p >= 0 && g_s5.np - p <= 80; p--)
            {
               if(g_piv5[p].kind != kind || g_piv5[p].confirmIdx > n5 - 1)
                  continue;
               double px = g_piv5[p].price;
               if((kind > 0 && px <= cNow) || (kind < 0 && px >= cNow))
                  continue;
               if(bound > 0.0 && ((kind > 0 && px <= bound) || (kind < 0 && px >= bound)))
                  continue;
               if(bestP < 0 || (kind > 0 && px < best) || (kind < 0 && px > best))
               {
                  best = px;
                  bestP = p;
               }
            }
            if(bestP < 0)
               break;
            string nm = NQ_PFX_C + "SR_" + ((kind > 0) ? "R" : "S") + IntegerToString(pass);
            NqLevel(nm, g_s5.t[g_piv5[bestP].idx], best, (kind > 0) ? NQ_RGB(255, 120, 120) : NQ_RGB(120, 220, 140),
                    (pass == 0) ? STYLE_SOLID : STYLE_DASH, (kind > 0) ? "R" : "S");
            bound = best;
         }
      }
      for(int b = 0; b < g_nSbrk; b++)
      {
         int i = g_sbrk[b].idx;
         if(n5 - i > 300)
            continue;
         string kindB = NqBreakKind(g_s5, g_sbrk[b]);
         string txt = (g_sbrk[b].dir > 0) ? (kindB + " " + NqSymUp() + " R " + NqPx(g_sbrk[b].level))
                                          : (kindB + " " + NqSymDown() + " S " + NqPx(g_sbrk[b].level));
         double off = (g_s5.atr[i] > 0.0) ? g_s5.atr[i] * 1.2 : 0.0;
         NqText(NQ_PFX_C + "SB_" + IntegerToString(i), g_s5.t[i], (g_sbrk[b].dir > 0) ? g_s5.h[i] + off : g_s5.l[i] - off, txt,
                (g_sbrk[b].dir > 0) ? cUp : cDn, 8, (g_sbrk[b].dir > 0) ? ANCHOR_LOWER : ANCHOR_UPPER,
                txt + ": M5 close " + NqPx(g_sbrk[b].close) + " at " + TimeToString(g_s5.t[i] + g_s5.sec, TIME_MINUTES));
      }
      for(int b = 0; b < g_nBrk; b++)
      {
         int i = g_brk[b].idx;
         string txt = (g_brk[b].dir > 0) ? ("BREAKOUT CONFIRMED " + NqSymUp() + " " + NqLevelName(g_brk[b].level))
                                         : ("BREAKDOWN CONFIRMED " + NqSymDown() + " " + NqLevelName(g_brk[b].level));
         double off = (g_s5.atr[i] > 0.0) ? g_s5.atr[i] * 0.8 : 0.0;
         NqText(NQ_PFX_C + "BK_" + IntegerToString(i), g_s5.t[i], (g_brk[b].dir > 0) ? g_s5.h[i] + off : g_s5.l[i] - off, txt,
                (g_brk[b].dir > 0) ? cUp : cDn, 8, (g_brk[b].dir > 0) ? ANCHOR_LOWER : ANCHOR_UPPER,
                txt + " at " + NqPx(g_levels.px[g_brk[b].level]) + ", M5 close " + NqPx(g_brk[b].close) + " " +
                TimeToString(g_s5.t[i] + g_s5.sec, TIME_MINUTES));
      }
      // VWAP polyline for today, one segment per 5 closed M1 bars
      int dayNow = NqDayOf(g_s1.t[n1 - 1]);
      int first = n1 - 1;
      while(first > 0 && NqDayOf(g_s1.t[first - 1]) == dayNow)
         first--;
      color cVw = NQ_RGB(255, 210, 80);
      int seg = 0;
      for(int i = first; i + 5 < n1; i += 5)
      {
         if(g_vwap1[i] <= 0.0 || g_vwap1[i + 5] <= 0.0)
            continue;
         string nm = NQ_PFX_C + "VW_" + IntegerToString(seg++);
         if(ObjectFind(0, nm) < 0)
            ObjectCreate(0, nm, OBJ_TREND, 0, g_s1.t[i], g_vwap1[i], g_s1.t[i + 5], g_vwap1[i + 5]);
         ObjectSetInteger(0, nm, OBJPROP_TIME, 0, g_s1.t[i]);
         ObjectSetDouble(0, nm, OBJPROP_PRICE, 0, g_vwap1[i]);
         ObjectSetInteger(0, nm, OBJPROP_TIME, 1, g_s1.t[i + 5]);
         ObjectSetDouble(0, nm, OBJPROP_PRICE, 1, g_vwap1[i + 5]);
         ObjectSetInteger(0, nm, OBJPROP_COLOR, cVw);
         ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, nm, OBJPROP_BACK, true);
         ObjectSetString(0, nm, OBJPROP_TOOLTIP, "day VWAP");
      }
      if(g_vwap1[n1 - 1] > 0.0)
         NqText(NQ_PFX_C + "VW_T", g_s1.t[n1 - 1] + g_s1.sec, g_vwap1[n1 - 1], "VWAP " + NqPx(g_vwap1[n1 - 1]), cVw, 8,
                ANCHOR_LEFT_LOWER, "day VWAP from " + IntegerToString(0) + ":00 server");
   }

   // impulse radar: armed stop orders (both directions)
   for(int d = 0; d < 2; d++)
   {
      int kr = NqLatestPlanDir(g_radar, g_nRadar, NQ_PLAN_RADAR, (d == 0) ? NQ_BUY : NQ_SELL);
      if(kr < 0 || g_radar[kr].status != NQ_PL_ACTIVE)
         continue;
      color cRd = NQ_RGB(255, 90, 60);
      string id = (d == 0) ? "RU" : "RD";
      string nmk = (d == 0) ? "RADAR BUY STOP" : "RADAR SELL STOP";
      datetime ts = g_s5.t[g_radar[kr].idx];
      NqLevel(NQ_PFX_C + "L_" + id + "E", ts, g_radar[kr].entry, cRd, STYLE_SOLID, nmk);
      NqLevel(NQ_PFX_C + "L_" + id + "S", ts, g_radar[kr].sl, cDn, STYLE_DASH, nmk + " SL");
      NqLevel(NQ_PFX_C + "L_" + id + "1", ts, g_radar[kr].tp1, cUp, STYLE_DASH, nmk + " TP1");
   }

   // NY trap: the armed plan
   int kn = NqLatestPlan(g_ny, g_nNy, NQ_PLAN_NY);
   if(kn >= 0)
   {
      color cNy = NQ_RGB(200, 120, 255);
      string sideN = (g_ny[kn].dir > 0) ? "BUY LIMIT" : "SELL LIMIT";
      string nmk = "NY TRAP " + sideN;
      datetime ts = g_s5.t[g_ny[kn].idx];
      NqLevel(NQ_PFX_C + "L_NE", ts, g_ny[kn].entry, cNy, STYLE_SOLID, nmk);
      NqLevel(NQ_PFX_C + "L_NS", ts, g_ny[kn].sl, cDn, STYLE_DASH, nmk + " SL");
      NqLevel(NQ_PFX_C + "L_N1", ts, g_ny[kn].tp1, cUp, STYLE_DASH, nmk + " TP1");
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

// MT5 draws at most NQ_LBL_MAX characters of an OBJ_LABEL and silently drops the
// rest ("lead BTCUSD" became "lead BTC" on a live chart). Longer text is split at
// spaces into pieces placed side by side (TextGetSize measures each piece in the
// label's font); the first piece keeps the id, the others are id~1, id~2, ...
#define NQ_LBL_MAX 63
int NqSplitLabel(string txt, string &parts[])
{
   ArrayResize(parts, 0);
   int len = StringLen(txt);
   int pos = 0;
   while(len - pos > NQ_LBL_MAX)
   {
      int cut = -1;
      for(int i = pos + NQ_LBL_MAX; i > pos + NQ_LBL_MAX / 2; i--)
      {
         if(StringGetCharacter(txt, i) == ' ')
         {
            cut = i;
            break;
         }
      }
      if(cut < 0)
         cut = pos + NQ_LBL_MAX;
      int n = ArraySize(parts);
      ArrayResize(parts, n + 1);
      parts[n] = StringSubstr(txt, pos, cut - pos);
      pos = cut;                                         // the space leads the next piece: the gap is drawn
   }
   int n = ArraySize(parts);
   ArrayResize(parts, n + 1);
   parts[n] = StringSubstr(txt, pos);
   return n + 1;
}

void NqLabel(string id, int x, int y, string txt, color clr, int size, string font, int anchor)
{
   string parts[];
   int np = NqSplitLabel(txt, parts);
   if(np > 1)
   {
      int widths[];
      ArrayResize(widths, np);
      int total = 0;
      TextSetFont(font, -size * 10);                    // tenths of a point, like the label's point size
      for(int i = 0; i < np; i++)
      {
         uint w = 0, h = 0;                              // MQL5: TextGetSize(const string, uint&, uint&)
         if(!TextGetSize(parts[i], w, h) || w == 0)
            w = (uint)(StringLen(parts[i]) * size * 2 / 3);   // a guess only if the measure fails
         widths[i] = (int)w;
         total += (int)w;
      }
      int px = x;
      int a = anchor;
      if(anchor == ANCHOR_CENTER)
      {
         px = x - total / 2;                             // the pieces together stay centred on x
         a = ANCHOR_LEFT;
      }
      for(int i = 0; i < np; i++)
      {
         NqLabelOne(id + ((i == 0) ? "" : ("~" + IntegerToString(i))), px, y, parts[i], clr, size, font, a);
         px += widths[i];
      }
   }
   else
      NqLabelOne(id, x, y, txt, clr, size, font, anchor);
   for(int k = np; ; k++)                               // pieces of an earlier, longer text
   {
      string stale = NQ_PFX_P + id + "~" + IntegerToString(k);
      if(ObjectFind(0, stale) < 0)
         break;
      ObjectsDeleteAll(0, stale);
   }
}

void NqLabelOne(string id, int x, int y, string txt, color clr, int size, string font, int anchor)
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
   int W = (int)MathRound(790 * sc);
   int rh = (int)MathRound(17 * sc);
   int pad = (int)MathRound(10 * sc);
   int fs = (int)MathRound(9 * sc);
   int fsH = (int)MathRound(8 * sc);
   int fsT = (int)MathRound(13 * sc);
   int kOff = (int)MathRound(8 * sc);
   int vOff = (int)MathRound(122 * sc);
   int bannerH = (int)MathRound(38 * sc);
   int rowsTop = 12;
   // compact board: an empty plan slot is one line, broker rows only as many as there are (at least one)
   int slotLines = 0;
   for(int q = 0; q < NQ_PLAN_SLOTS; q++)
   {
      NqPlan plq;
      slotLines += (g_ready && NqSlotPlan(q, plq)) ? 2 : 1;
   }
   int brokerRows = (int)MathMax(1, (int)MathMin(NQ_BOARD_BROKER_ROWS, g_pendCount + g_openCount));
   int rowsBot = 8 + 1 + slotLines + 2 + brokerRows + 2;   // NY/level/radar lines, header, plan rows, scalp row, broker rows, footer
   bool deskOpen = !g_deskCollapsed;
   bool boardOpen = !g_boardCollapsed;
   int tTopH = deskOpen ? (rh + 3 + rowsTop * rh + 4) : (rh + 6);
   int tBotH = boardOpen ? (rh + 3 + rowsBot * rh + 8) : 0;
   bool split = (InpPanelLayout == NQ_LAYOUT_SPLIT);   // the engine rows become an INFORMATION DESK at the bottom middle
   int H = pad * 2 + (int)MathRound(rh * 1.4) + rh + 4 + bannerH + 4 + 2 * rh + (split ? 0 : tTopH + 6) + (boardOpen ? tBotH + 4 + rh : 0);

   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
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
   int xInfo = split ? (int)MathMax(0, (cw - W) / 2) : ox;
   int yInfo = split ? (int)MathMax(0, ch - (tTopH + 2 * pad) - 4) : oy;
   if(split && yInfo < oy + H + 4 && xInfo < ox + W + 4)
   {
      int xr = ox + W + 8;      // a short chart: the desk goes beside the board when it fits, else it overlaps (fold one of them)
      if(xr + W <= cw - 60)
         xInfo = xr;
   }
   if(split)
      NqRect("bgI", xInfo, yInfo, W, tTopH + 2 * pad, cBg, cMetal);
   else if(ObjectFind(0, NQ_PFX_P + "bgI") >= 0)
      ObjectsDeleteAll(0, NQ_PFX_P + "bgI");

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
   title = title + "   v" + NQ_EA_VERSION;   // the build on the chart, so the real file is recognisable
   title = title + (boardOpen ? "   (click: fold)" : "   (click: unfold)");
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

   // banner = THE VERDICT (what to do now)
   string st = g_verdict;
   color bc = g_verdictClr;
   if(g_metal == NQ_METAL_NONE)
   {
      st = NqSymDot() + "  GOLD / SILVER ONLY";
      bc = cWait;
   }
   else if((g_gate & NQ_K_REAL_ACCOUNT) != 0)
   {
      st = "!  REAL ACCOUNT - TRADING BLOCKED";
      bc = cBlock;
   }
   if(st == "")
   {
      st = NqSymDot() + "  WAIT";
      bc = cWait;
   }
   NqRect("banner", ox + pad, y, W - 2 * pad, bannerH, bc, bc);
   NqLabel("state", ox + W / 2, y + bannerH / 2, st, NQ_RGB(10, 12, 16), (StringLen(st) > 60) ? fs : fsT, "Arial Black", ANCHOR_CENTER);
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
      r2 = (g_gate != 0) ? NqGateAtX(g_gate, 0) : ("SL " + DoubleToString(InpScalpSlAtr, 1) + " x ATR5, TP " +
                                                     DoubleToString(InpScalpTpAtr, 1) + " x ATR5, time stop " +
                                                     IntegerToString(InpScalpTimeStop) + " M1 bars");
   }
   else
   {
      r1 = NqReasonAt(g_finalR, 0);
      r2 = NqReasonAt(g_finalR, 1);
   }
   if((g_gate & NQ_K_TRADE_DISABLED) != 0)
      r1 = "ALGO TRADING OFF - watch only, the verdict above is for your hands.  " + r1;
   if(g_note != "" && r2 == "")
      r2 = g_note;
   NqLabel("r1", ox + pad, y, "REASON: " + r1, cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   y += rh;
   NqLabel("r2", ox + pad, y, (r2 == "") ? " " : ("            " + r2), cVal, fs, "Arial", ANCHOR_LEFT_UPPER);
   y += rh;

   // ---------------- the engine table: the INFORMATION DESK (bottom middle in SPLIT, here in ONE) ----------------
   int txB = ox + pad;
   int TW = W - 2 * pad;
   int tx = split ? xInfo + pad : txB;
   int yI = split ? yInfo + pad : y;
   int kx = tx + kOff;
   int vx = tx + vOff;
   NqRect("t1", tx, yI, TW, tTopH, cTbl, cDim);
   string hdr = split ? "INFORMATION DESK   " : "";
   hdr = hdr + "ENGINE   M15 " + NqSymArrow() + " M5 " + NqSymArrow() + " M1" + (deskOpen ? "   (click: fold)" : "   (click: unfold)");
   NqLabel("h1", kx, yI + 3, hdr, cMetal, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   int yr = yI + rh + 3;
   if(deskOpen)
   {

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
   // ---- v1.9 rows: the higher timeframes, the macro vote, the news, the week ----
   string htfT = "---";
   color htfC = cDim;
   if(ok)
   {
      htfT = NqHtfText(g_h4, g_h4Ok, g_sbH4, g_nSbH4, "H4") + "   |   " + NqHtfText(g_h1, g_h1Ok, g_sbH1, g_nSbH1, "H1");
      int c4 = (g_h4Ok && g_h4.n > 0) ? g_h4.ctx[g_h4.n - 1] : 0;
      int c1 = (g_h1Ok && g_h1.n > 0) ? g_h1.ctx[g_h1.n - 1] : 0;
      htfC = (c4 != 0 && c4 == c1) ? NqDirColor(c4) : cVal;
   }
   NqRow("e0t", kx, vx, yr, "H4 / H1", htfT, htfC, cKey, fs);
   yr += rh;
   string macT = "---";
   color macC = cDim;
   if(ok)
   {
      string whyB = "";
      string whyS = "";
      int vb = NqMacroVote(1, whyB);
      int vs = NqMacroVote(-1, whyS);
      string wit = "   DXY " + ((g_macroSym == "") ? "-" : (g_macroSym + " " + ((g_macroDir == 0) ? "NO DATA" : NqDirText(g_macroDir)))) +
                   "   " + (g_bondYield ? "yield " : "bond ") + ((g_bondSym == "") ? "-" : (g_bondSym + " " + ((g_bondDir == 0) ? "NO DATA" : NqDirText(g_bondDir))));
      macT = "vote BUY ";
      macT = macT + ((vb >= 0) ? "+" : "") + IntegerToString(vb) + " / SELL " + ((vs >= 0) ? "+" : "") + IntegerToString(vs) +
             (g_macroGate ? ("  (blocks at -" + IntegerToString(InpMacroBlockLevel) + ", A+ structure overrides)") : "  (gate off)") +
             ((whyB == "") ? "   no voter has data" : ("   " + whyB)) + wit;
      macC = (vb >= InpMacroBlockLevel) ? cUp : ((vs >= InpMacroBlockLevel) ? cDn : cVal);
   }
   NqRow("e0m", kx, vx, yr, "MACRO VOTE", macT, macC, cKey, fs);
   yr += rh;
   string newsT = (g_newsText == "") ? "---" : g_newsText;
   color newsC = g_newsBlock ? cBlock : (g_newsUnknown ? (g_newsUnknownBlocks ? cBlock : cWait) : cVal);
   NqRow("e0n", kx, vx, yr, "NEWS (USD)", newsT, newsC, cKey, fs);
   yr += rh;
   string wkT = NqSessionName() + "   rollover " + IntegerToString(g_clk.roll / 60, 2, '0') + ":" + IntegerToString(g_clk.roll % 60, 2, '0') + (g_rollover ? " NOW" : "") +
                ((g_weekText == "") ? "   week open" : ("   " + g_weekText)) + (g_clockGuards ? "" : " (guards off)") +
                ((g_portfolioPos > 0) ? ("   portfolio " + IntegerToString(g_portfolioPos) + " pos (max " + IntegerToString(InpMaxOpenAcrossCharts) + ")") : "") +
                ((g_smartNote == "") ? "" : ("   last: " + g_smartNote));
   color wkC = (g_weekEdge || g_rollover || g_portfolioFull) ? cBlock : cVal;
   NqRow("e0h", kx, vx, yr, "WEEK / SMART", wkT, wkC, cKey, fs);
   yr += rh;
   string volT = "---";
   color volC = cDim;
   if(g_volClass != NQ_VOL_UNKNOWN)
   {
      volT = NqVolClassText(g_volClass) + "  ATR5 " + DoubleToString(g_volRatio, 2) + "x its " + IntegerToString(InpVolAvgBars / 12) + "h avg";
      if(g_volClass == NQ_VOL_DEAD)
         volT = volT + " - no new trade";
      if(g_volClass == NQ_VOL_EXPANSION)
         volT = volT + " - radar needs " + IntegerToString(InpVolExpandRadar) + "/10, scalp needs M15";
      if(g_volClass == NQ_VOL_EXTREME)
         volT = volT + " - do not chase";
      if(g_volWaitFresh)
         volT = volT + " - waiting for a fresh M5 swing";
      if(!InpVolGate)
         volT = volT + " (gate off)";
      volC = (g_volClass == NQ_VOL_NORMAL) ? cVal : ((g_volClass == NQ_VOL_EXPANSION) ? cWait : cBlock);
      if(g_volClass == NQ_VOL_DEAD)
         volC = cDim;
      if(g_spikeDir != 0)
      {
         volT = volT + "   SPIKE " + ((g_spikeDir > 0) ? "UP " : "DOWN ") + DoubleToString(g_spikeAtr, 1) + " ATR (" + DoubleToString(g_spikeX, 1) + "x normal), " +
                IntegerToString((int)MathRound(g_spikeRetr * 100.0)) + "% back" + (g_spikeWarn ? " - EXIT WARNING" : "");
         volC = cBlock;
      }
   }
   NqRow("e0v", kx, vx, yr, "VOL REGIME", volT, volC, cKey, fs);
   yr += rh;
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
         fcT = NqSymUp() + " UP   (score +" + IntegerToString(g_s1.fcScore[i1]) + ", strong)  target +0.5 ATR before -0.5 ATR in 5 candles";
      else if(f < 0)
         fcT = NqSymDown() + " DOWN   (score " + IntegerToString(g_s1.fcScore[i1]) + ", strong)  target -0.5 ATR before +0.5 ATR in 5 candles";
      else
         fcT = "NO ARROW   (score " + IntegerToString(g_s1.fcScore[i1]) + ", votes split - no bias)";
      fcC = NqDirColor(f);
   }
   NqRow("e6", kx, vx, yr, "NEXT M1 BIAS", fcT, fcC, cKey, fs);
   yr += rh;
   string hitT = "---";
   if(ok)
   {
      int cnt = 0;
      int hits = 0;
      NqForecastStats(g_s1, 0, cnt, hits);
      if(cnt > 0)
         hitT = DoubleToString(100.0 * hits / cnt, 1) + "%  (" + IntegerToString(hits) + " of " + IntegerToString(cnt) + " resolved, " +
                NqEvidenceText(cnt) + ")  50% = coin";
      else
         hitT = "no resolved arrows yet";
      if(NqChartSeries() == 0)
         hitT = hitT + "  - arrows need an M1/M5/M15 chart";
   }
   NqRow("e7", kx, vx, yr, "BIAS HIT RATE", hitT, cVal, cKey, fs);
   }
   if(!split)
      y += tTopH + 6;
   tx = txB;                 // back to the trading board's column
   kx = tx + kOff;
   vx = tx + vOff;

   // ---------------- the TRADING BOARD: NY TRAP + PENDING ORDERS (top-left) ----------------
   if(!boardOpen)
      return;
   NqRect("t2", tx, y, TW, tBotH, cTbl, cDim);
   NqLabel("h2", kx, y + 3, "NY TRAP  +  PENDING ORDER BOARD   (live, every second)", cMetal, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   yr = y + rh + 3;
   int n5 = ok ? g_s5.n : 0;
   double atr5 = (ok && n5 > 0) ? g_s5.atr[n5 - 1] : 0.0;
   int nowMod = NqMinuteOfDay(nowS);
   int nyStart = g_clk.nyS;
   int nyEnd = g_clk.nyE;
   bool nyNow = (nowMod >= nyStart && nowMod < nyEnd);
   string hhmmS = IntegerToString(nyStart / 60, 2, '0') + ":" + IntegerToString(nyStart % 60, 2, '0');
   string hhmmE = IntegerToString(nyEnd / 60, 2, '0') + ":" + IntegerToString(nyEnd % 60, 2, '0');
   string nyT = "NY SESSION  " + hhmmS + "-" + hhmmE + "  ";
   if(nyNow)
      nyT = nyT + "INSIDE, " + NqHhMm((long)(nyEnd - nowMod) * 60) + " left";
   else if(nowMod < nyStart)
      nyT = nyT + "opens in " + NqHhMm((long)(nyStart - nowMod) * 60);
   else
      nyT = nyT + "closed today";
   bool sameDay = ok && g_nyState.day == NqDayOf(nowS);
   if(sameDay && g_nyState.nyOk)
      nyT = nyT + "   NY range " + NqPx(g_nyState.nyLo) + " - " + NqPx(g_nyState.nyHi);
   nyT = nyT + "   clock " + g_clkText;
   NqLabel("ny1", kx, yr, nyT, cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   yr += rh;
   string preT = "PRE-NY RANGE  " + IntegerToString(g_clk.preS / 60, 2, '0') + ":" + IntegerToString(g_clk.preS % 60, 2, '0') + "-" + hhmmS + "  ";
   if(sameDay && g_nyState.preOk)
      preT = preT + "high " + NqPx(g_nyState.preHi) + "   low " + NqPx(g_nyState.preLo);
   else
      preT = preT + "not built yet";
   NqLabel("ny2", kx, yr, preT, cVal, fs, "Arial", ANCHOR_LEFT_UPPER);
   yr += rh;
   string sw = "SWEEP / TRAP  ";
   color swC = cDim;
   if(sameDay && g_nyState.preOk)
   {
      string hi = "HIGH: " + NqNyStateText(g_nyState.stBull);
      if(g_nyState.stBull >= NQ_NY_SWEPT && g_nyState.stBull != NQ_NY_DONE)
         hi = hi + " " + NqPx(g_nyState.sweepHi);
      if(g_nyState.stBull >= NQ_NY_RETURNED && g_nyState.stBull != NQ_NY_DONE)
         hi = hi + " (close " + NqPx(g_nyState.retCloseHi) + ")";
      string lo = "LOW: " + NqNyStateText(g_nyState.stBear);
      if(g_nyState.stBear >= NQ_NY_SWEPT && g_nyState.stBear != NQ_NY_DONE)
         lo = lo + " " + NqPx(g_nyState.sweepLo);
      if(g_nyState.stBear >= NQ_NY_RETURNED && g_nyState.stBear != NQ_NY_DONE)
         lo = lo + " (close " + NqPx(g_nyState.retCloseLo) + ")";
      sw = sw + hi + "   |   " + lo;
      swC = (g_nyState.stBull == NQ_NY_CONFIRMED || g_nyState.stBear == NQ_NY_CONFIRMED) ? cWait : cVal;
   }
   else
      sw = sw + "waiting for the session";
   NqLabel("ny3", kx, yr, sw, swC, fs, "Arial", ANCHOR_LEFT_UPPER);
   yr += rh;
   string act = "SLOT  ";
   color actC = cWait;
   if(g_openCount > 0)
   {
      act = act + "TAKEN  " + g_posText + "   (orders wait until it closes)";
      actC = cVal;
   }
   else
   {
      int armed = 0;
      for(int q = 0; q < NQ_PLAN_SLOTS; q++)
      {
         NqPlan pl;
         if(NqSlotPlan(q, pl) && pl.status == NQ_PL_ACTIVE && NqKindEnabled(pl))
            armed++;
      }
      act = act + "FREE  " + IntegerToString(armed) + " armed, " + IntegerToString(g_pendCount) +
            " waiting - the first fill takes it" + ((InpScalpAuto && g_pendCount == 0) ? ", scalp may fire" : "");
      actC = (armed > 0) ? cUp : cWait;
   }
   if(g_manualPos + g_manualOrd > 0)
      act = act + "   MANUAL " + IntegerToString(g_manualPos) + " pos / " + IntegerToString(g_manualOrd) + " ord untouched";
   NqLabel("ny4", kx, yr, act, actC, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   yr += rh;
   string lvT = "LEVELS  ";
   bool lvOk = ok && g_levels.day == NqDayOf(nowS);
   if(lvOk)
   {
      if(g_levels.ok[NQ_LV_PDH])
         lvT = lvT + "PD " + NqPx(g_levels.px[NQ_LV_PDH]) + "/" + NqPx(g_levels.px[NQ_LV_PDL]) + "  ";
      if(g_levels.ok[NQ_LV_ASH])
         lvT = lvT + "ASIA " + NqPx(g_levels.px[NQ_LV_ASH]) + "/" + NqPx(g_levels.px[NQ_LV_ASL]) + (g_levels.act[NQ_LV_ASH] ? "" : "*") + "  ";
      if(g_levels.ok[NQ_LV_LOH])
         lvT = lvT + "LON " + NqPx(g_levels.px[NQ_LV_LOH]) + "/" + NqPx(g_levels.px[NQ_LV_LOL]) + (g_levels.act[NQ_LV_LOH] ? "" : "*") + "  ";
      double vw = (g_s1.n > 0 && ArraySize(g_vwap1) == g_s1.n) ? g_vwap1[g_s1.n - 1] : 0.0;
      if(vw > 0.0)
         lvT = lvT + "VWAP " + NqPx(vw) + ((bid > vw) ? " (above)" : ((bid < vw) ? " (below)" : " (on)"));
      if(lvT == "LEVELS  ")
         lvT = lvT + "building (* = session still open)";
   }
   else
      lvT = lvT + "---";
   NqLabel("ny5", kx, yr, lvT, cVal, fs, "Arial", ANCHOR_LEFT_UPPER);
   yr += rh;
   string bkT = "BREAK  ";
   color bkC = cDim;
   if(lvOk && g_nBrk > 0)
   {
      int b = g_nBrk - 1;
      bkT = bkT + ((g_brk[b].dir > 0) ? "BREAKOUT above " : "BREAKDOWN below ") + NqLevelName(g_brk[b].level) + " " +
            NqPx(g_levels.px[g_brk[b].level]) + " @" + TimeToString(g_s5.t[g_brk[b].idx] + g_s5.sec, TIME_MINUTES);
      if(g_nBrk > 1)
      {
         int b2 = g_nBrk - 2;
         bkT = bkT + "   before: " + ((g_brk[b2].dir > 0) ? "breakout " : "breakdown ") + NqLevelName(g_brk[b2].level) +
               " @" + TimeToString(g_s5.t[g_brk[b2].idx] + g_s5.sec, TIME_MINUTES);
      }
      bkC = (g_brk[b].dir > 0) ? cUp : cDn;
   }
   else
      bkT = bkT + "no M5 close through an active level yet today";
   NqLabel("ny6", kx, yr, bkT, bkC, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   yr += rh;
   // IMPULSE RADAR block: both directions, measured components, never a guess
   string rdU = "RADAR " + NqSymUp() + "  ";
   string rdD = "RADAR " + NqSymDown() + "  ";
   color rdUC = cDim;
   color rdDC = cDim;
   if(ok)
   {
      if(g_rdUp.level > 0.0)
      {
         rdU = rdU + NqPx(g_rdUp.level) + "  dist " + DoubleToString(g_rdUp.dist, 2) + " ATR  score " + IntegerToString(g_rdUp.score) +
               "/10 " + NqPressureText(g_rdUp.score) + "  (struct " + IntegerToString(g_rdUp.sStruct) + " compr " + IntegerToString(g_rdUp.sComp) +
               " prox " + IntegerToString(g_rdUp.sProx) + " eff " + IntegerToString(g_rdUp.sEff) + " mom " + IntegerToString(g_rdUp.sMom) +
               " m15 " + IntegerToString(g_rdUp.sM15) + ")  " + NqRadarStateText(g_rdUp.state);
         rdUC = (g_rdUp.state == NQ_RD_READY) ? cUp : ((g_rdUp.state == NQ_RD_NEAR) ? cWait : cVal);
      }
      else
         rdU = rdU + "no resistance level above";
      if(g_rdDn.level > 0.0)
      {
         rdD = rdD + NqPx(g_rdDn.level) + "  dist " + DoubleToString(g_rdDn.dist, 2) + " ATR  score " + IntegerToString(g_rdDn.score) +
               "/10 " + NqPressureText(g_rdDn.score) + "  (struct " + IntegerToString(g_rdDn.sStruct) + " compr " + IntegerToString(g_rdDn.sComp) +
               " prox " + IntegerToString(g_rdDn.sProx) + " eff " + IntegerToString(g_rdDn.sEff) + " mom " + IntegerToString(g_rdDn.sMom) +
               " m15 " + IntegerToString(g_rdDn.sM15) + ")  " + NqRadarStateText(g_rdDn.state);
         rdDC = (g_rdDn.state == NQ_RD_READY) ? cDn : ((g_rdDn.state == NQ_RD_NEAR) ? cWait : cVal);
      }
      else
         rdD = rdD + "no support level below";
   }
   else
   {
      rdU = rdU + "---";
      rdD = rdD + "---";
   }
   NqLabel("rd1", kx, yr, rdU, rdUC, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   yr += rh;
   NqLabel("rd2", kx, yr, rdD, rdDC, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
   yr += rh + 2;

   // column header
   int cx0 = kx;
   int cx1 = tx + (int)MathRound(96 * sc);
   int cx2 = tx + (int)MathRound(172 * sc);
   int cx3 = tx + (int)MathRound(254 * sc);
   int cx4 = tx + (int)MathRound(336 * sc);
   int cx5 = tx + (int)MathRound(418 * sc);
   int cx6 = tx + (int)MathRound(486 * sc);
   NqLabel("bh0", cx0, yr, "TYPE", cKey, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   NqLabel("bh1", cx1, yr, "SIDE", cKey, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   NqLabel("bh2", cx2, yr, "ENTRY", cKey, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   NqLabel("bh3", cx3, yr, "SL", cKey, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   NqLabel("bh4", cx4, yr, "TP SENT", cKey, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   NqLabel("bh5", cx5, yr, "DIST", cKey, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   NqLabel("bh6", cx6, yr, "STATUS", cKey, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   yr += rh;

   // plan rows: M5 QML, M5 pullback, NY trap, M15 swing QML, M15 swing pullback
   double bidP = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double askP = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   for(int q = 0; q < NQ_PLAN_SLOTS; q++)
   {
      string id = "bp" + IntegerToString(q);
      string typ = "";
      int kind = NQ_PLAN_QML;
      int validBars = InpPlanValidBars;
      int secP = ok ? g_s5.sec : 300;
      bool useM5 = true;
      if(q == 0) { typ = "QML M5"; kind = NQ_PLAN_QML; }
      if(q == 1) { typ = "PULLBACK M5"; kind = NQ_PLAN_PB; }
      if(q == 2) { typ = "NY TRAP"; kind = NQ_PLAN_NY; }
      if(q == 3) { typ = "SWING QML"; kind = NQ_PLAN_QML; validBars = InpSwingValidBars; secP = ok ? g_s15r.sec : 900; useM5 = false; }
      if(q == 4) { typ = "SWING PB"; kind = NQ_PLAN_PB; validBars = InpSwingValidBars; secP = ok ? g_s15r.sec : 900; useM5 = false; }
      if(q == 5) { typ = "RADAR UP"; kind = NQ_PLAN_RADAR; }
      if(q == 6) { typ = "RADAR DOWN"; kind = NQ_PLAN_RADAR; }
      NqPlan pl;
      int k = (ok && NqSlotPlan(q, pl)) ? 1 : -1;
      bool autoPlan = (k >= 0) && NqKindEnabled(pl);
      string side = "-";
      string vE = "-";
      string vS = "-";
      string vT = "-";
      string vD = "-";
      string stT = ok ? "no setup yet" : "---";
      string det = " ";
      color cRow = cDim;
      color cSt = cDim;
      if(ok && k < 0 && kind == NQ_PLAN_RADAR)
      {
         NqRadar rr;
         rr = (q == 5) ? g_rdUp : g_rdDn;
         stT = (rr.level > 0.0) ? (NqRadarStateText(rr.state) + "  score " + IntegerToString(rr.score) + "/10  (armed at 7 within 1 ATR)") : "no level";
         cSt = (rr.state == NQ_RD_NEAR) ? cWait : cDim;
      }
      if(k >= 0)
      {
         side = (pl.dir > 0) ? (NqPlanIsStop(pl) ? "BUY STOP" : "BUY LMT") : (NqPlanIsStop(pl) ? "SELL STOP" : "SELL LMT");
         cRow = NqDirColor(pl.dir);
         vE = NqPx(pl.entry);
         vS = NqPx(pl.sl);
         double tpSent = InpPlanUseTp2 ? pl.tp2 : pl.tp1;
         vT = NqPx(tpSent);
         double dist = NqPlanIsStop(pl) ? NqDistAtrStop(pl.dir, pl.entry, bidP, askP, atr5) : NqDistAtr(pl.dir, pl.entry, bidP, askP, atr5);
         bool isNear = (atr5 > 0.0 && dist >= 0.0 && dist <= InpNearAtr && pl.status == NQ_PL_ACTIVE);
         vD = (atr5 > 0.0) ? ((isNear ? (NqSymDot() + " ") : "") + DoubleToString(dist, 2) + " ATR") : "-";
         datetime tPlan = useM5 ? g_s5.t[pl.idx] : g_s15r.t[pl.idx];
         long expSec = (long)(tPlan + (long)(validBars + 1) * secP - nowS);
         if(q == 2)
            expSec = (long)(nyEnd - nowMod) * 60;
         string cmt = NqPlanComment(pl);
         if(pl.status == NQ_PL_ACTIVE)
         {
            cSt = cWait;
            if(!autoPlan)
               stT = "ARMED - " + NqPlanKindText(pl.kind) + " off";
            else
            {
               if(NqPlanHasPosition(pl))
               {
                  int reg5 = g_s5.regime[n5 - 1];
                  stT = (reg5 != NQ_REG_CHOP && reg5 != pl.dir) ? "RUNNING - EXIT? regime flipped" : "RUNNING - HOLD";
                  cSt = (reg5 != NQ_REG_CHOP && reg5 != pl.dir) ? cBlock : cUp;
               }
               else
               {
                  ulong tk = NqFindPlanOrder(pl);
                  if(tk != 0)
                  {
                     stT = ((atr5 > 0.0 && dist >= 0.0 && dist <= InpNearAtr) ? "NEAR  #" : "PLACED  #") + IntegerToString((long)tk);
                     cSt = (dist >= 0.0 && dist <= InpNearAtr) ? cUp : cVal;
                  }
                  else if(g_rejCmt == cmt)
                  {
                     stT = "REJECTED  retcode " + IntegerToString(g_rejCode);
                     cSt = cBlock;
                  }
                  else if(!InpPendingAuto)
                     stT = "ARMED - auto pending off";
                  else if(g_openCount > 0)
                     stT = "ARMED - slot taken";
                  else if(g_gate != 0)
                  {
                     stT = "ARMED - " + NqGateAtX(g_gate, 0);
                     cSt = cBlock;
                  }
                  else if(dist < 0.0)
                     stT = "ARMED - price past level";
                  else
                     stT = "WAITING (next M1 close)";
               }
            }
            stT = stT + "  exp " + NqHhMm(expSec);
         }
         else if(pl.status == NQ_PL_FILLED)
         {
            if(NqPlanHasPosition(pl))
            {
               int reg5 = g_s5.regime[n5 - 1];
               stT = (reg5 != NQ_REG_CHOP && reg5 != pl.dir) ? "RUNNING - EXIT? regime flipped" : "RUNNING - HOLD";
               cSt = (reg5 != NQ_REG_CHOP && reg5 != pl.dir) ? cBlock : cUp;
            }
            else
            {
               stT = "FILLED (paper - no position)";
               cSt = cDim;
            }
         }
         else
         {
            stT = NqPlanStatusText(pl.status);
            cSt = (pl.status == NQ_PL_TP1) ? cUp : ((pl.status == NQ_PL_SL || pl.status == NQ_PL_FALSE) ? cDn : cVal);
         }
         string when = TimeToString(tPlan + secP, TIME_MINUTES);
         string tps = "  R " + NqPx(pl.risk) + "  TP1 " + NqPx(pl.tp1) + "  TP2 " + NqPx(pl.tp2) + (InpPlanUseTp2 ? "  (TP2 sent)" : "  (TP1 sent)");
         if(kind == NQ_PLAN_RADAR)
         {
            NqRadar rr;
            rr = (pl.dir > 0) ? g_rdUp : g_rdDn;
            det = "level " + NqPx(pl.lvlA) + "  SL " + ((pl.lvlB > 0.0) ? ("swing " + NqPx(pl.lvlB)) : "1.5 ATR") + "  score now " +
                  IntegerToString(rr.score) + "/10 " + NqPressureText(rr.score) + "  eff " + DoubleToString(rr.eff * 100.0, 0) + "%  armed @" + when + tps;
         }
         else if(kind == NQ_PLAN_QML)
            det = "head " + NqPx(pl.lvlB) + "  neck " + NqPx(pl.lvlA) + "  break " + NqPx(useM5 ? g_s5.c[pl.idx] : g_s15r.c[pl.idx]) +
                  " @" + when + tps;
         else if(kind == NQ_PLAN_PB)
            det = "leg " + NqPx(pl.lvlA) + NqSymArrow() + NqPx(pl.lvlB) + "  " + DoubleToString(InpPbRetrace * 100.0, 0) +
                  "% retrace @" + when + tps;
         else
            det = "level " + NqPx(pl.lvlA) + " swept to " + NqPx(pl.lvlB) + "  confirmed @" + when + tps;
      }
      NqLabel(id + "0", cx0, yr, typ, cKey, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel(id + "1", cx1, yr, side, cRow, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel(id + "2", cx2, yr, vE, cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel(id + "3", cx3, yr, vS, (k >= 0) ? cDn : cDim, fs, "Arial", ANCHOR_LEFT_UPPER);
      NqLabel(id + "4", cx4, yr, vT, (k >= 0) ? cUp : cDim, fs, "Arial", ANCHOR_LEFT_UPPER);
      bool nearRow = (StringFind(vD, NqSymDot()) == 0);
      NqLabel(id + "5", cx5, yr, vD, nearRow ? clrWhite : cVal, fs, nearRow ? "Arial Black" : "Arial", ANCHOR_LEFT_UPPER);
      NqLabel(id + "6", cx6, yr, stT, cSt, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      yr += rh;
      if(k >= 0)
      {
         NqLabel(id + "d", cx1, yr, det, cDim, fsH, "Arial", ANCHOR_LEFT_UPPER);
         yr += rh;
      }
      else if(ObjectFind(0, NQ_PFX_P + id + "d") >= 0)
         ObjectsDeleteAll(0, NQ_PFX_P + id + "d");
   }

   // SCALP row: always visible with the levels a scalp would use RIGHT NOW,
   // so it can be taken by hand even while the trigger is WAIT
   {
      string side = "-";
      string vE = "-";
      string vS = "-";
      string vT = "-";
      string vD = "-";
      string stT = ok ? "---" : "---";
      string det = " ";
      color cRow = cDim;
      color cSt = cDim;
      if(ok && atr5 > 0.0)
      {
         int reg = g_s5.regime[n5 - 1];
         int st1 = g_s1.state[g_s1.n - 1];
         double slD = NormalizeDouble(InpScalpSlAtr * atr5, g_digits);
         double tpD = NormalizeDouble(InpScalpTpAtr * atr5, g_digits);
         double lot = NqLotFor(g_riskMoney, slD, g_tick, g_tickValue, g_volMin, g_volMax, g_volStep);
         string lotT = (lot > 0.0) ? (DoubleToString(lot, 2) + " lot = " + DoubleToString(NqLossAt(lot, slD, g_tick, g_tickValue), 2) + " at SL") : "min lot too big";
         if(reg == NQ_REG_BULL || reg == NQ_REG_BEAR)
         {
            side = (reg > 0) ? "BUY MKT" : "SELL MKT";
            cRow = NqDirColor(reg);
            double entry = (reg > 0) ? askP : bidP;
            vE = NqPx(entry);
            vS = NqPx((reg > 0) ? NqRoundTick(entry - slD, g_tick, g_digits, -1) : NqRoundTick(entry + slD, g_tick, g_digits, 1));
            vT = NqPx((reg > 0) ? NqRoundTick(entry + tpD, g_tick, g_digits, 1) : NqRoundTick(entry - tpD, g_tick, g_digits, -1));
            vD = "live";
            if(st1 == NQ_BUY || st1 == NQ_SELL)
            {
               stT = "TRIGGER NOW" + (InpScalpAuto ? ((g_gate == 0) ? " - auto" : (" - " + NqGateAtX(g_gate, 0))) : " - manual");
               cSt = (g_gate == 0 || !InpScalpAuto) ? cUp : cBlock;
            }
            else
            {
               stT = "WAIT: " + NqReasonAt(g_s1.reasons[g_s1.n - 1], 0);
               cSt = cWait;
            }
         }
         else
         {
            side = "NONE";
            vE = NqPx(bidP);
            vS = NqSymDot() + " " + NqPx(slD);
            vT = NqSymDot() + " " + NqPx(tpD);
            vD = "dist";
            stT = "WAIT: M5 CHOP - no direction";
            cSt = cWait;
         }
         string regS = (reg == NQ_REG_BULL) ? "BULL" : ((reg == NQ_REG_BEAR) ? "BEAR" : "CHOP");
         det = "M1 NRTR " + NqDirText(g_s1.dir[g_s1.n - 1]) + "  M5 " + regS + "  ATR5 " + NqPx(atr5) +
               "  SL " + DoubleToString(InpScalpSlAtr, 1) + "x  TP " + DoubleToString(InpScalpTpAtr, 1) + "x  " + lotT +
               "  stop " + IntegerToString(InpScalpTimeStop) + " M1";
      }
      else if(ok)
      {
         stT = "ATR not ready";
         cSt = cWait;
      }
      NqLabel("bs0", cx0, yr, "SCALP M1", cKey, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel("bs1", cx1, yr, side, cRow, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel("bs2", cx2, yr, vE, cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel("bs3", cx3, yr, vS, (vS == "-") ? cDim : cDn, fs, "Arial", ANCHOR_LEFT_UPPER);
      NqLabel("bs4", cx4, yr, vT, (vT == "-") ? cDim : cUp, fs, "Arial", ANCHOR_LEFT_UPPER);
      NqLabel("bs5", cx5, yr, vD, cVal, fs, "Arial", ANCHOR_LEFT_UPPER);
      NqLabel("bs6", cx6, yr, stT, cSt, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      yr += rh;
      NqLabel("bsd", cx1, yr, det, cDim, fsH, "Arial", ANCHOR_LEFT_UPPER);
      yr += rh;
   }

   // broker rows: what MT5 actually holds for this EA (orders, then positions)
   int shown = 0;
   int ot = OrdersTotal();
   for(int i = 0; i < ot && shown < NQ_BOARD_BROKER_ROWS; i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0)
         continue;
      if(!NqIsOurs(OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
         continue;
      long oty = OrderGetInteger(ORDER_TYPE);
      int odir = (oty == ORDER_TYPE_BUY_LIMIT || oty == ORDER_TYPE_BUY_STOP) ? 1 : -1;
      bool oStop = (oty == ORDER_TYPE_BUY_STOP || oty == ORDER_TYPE_SELL_STOP);
      double op = OrderGetDouble(ORDER_PRICE_OPEN);
      string kindT = NqKindOfComment(OrderGetString(ORDER_COMMENT));
      double dist = oStop ? NqDistAtrStop(odir, op, bidP, askP, atr5) : NqDistAtr(odir, op, bidP, askP, atr5);
      long age = (long)nowS - (long)OrderGetInteger(ORDER_TIME_SETUP);
      string id = "bb" + IntegerToString(shown);
      NqLabel(id + "0", cx0, yr, "BROKER", cKey, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel(id + "1", cx1, yr, (odir > 0) ? (oStop ? "BUY STOP" : "BUY LMT") : (oStop ? "SELL STOP" : "SELL LMT"), NqDirColor(odir), fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel(id + "2", cx2, yr, NqPx(op), cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel(id + "3", cx3, yr, NqPx(OrderGetDouble(ORDER_SL)), cDn, fs, "Arial", ANCHOR_LEFT_UPPER);
      NqLabel(id + "4", cx4, yr, NqPx(OrderGetDouble(ORDER_TP)), cUp, fs, "Arial", ANCHOR_LEFT_UPPER);
      NqLabel(id + "5", cx5, yr, (atr5 > 0.0) ? (DoubleToString(dist, 2) + " ATR") : "-", cVal, fs, "Arial", ANCHOR_LEFT_UPPER);
      NqLabel(id + "6", cx6, yr, "#" + IntegerToString((long)tk) + " " + kindT + " " + DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT), 2) +
              " lot  " + NqHhMm(age) + ((atr5 > 0.0 && dist >= 0.0 && dist <= InpNearAtr) ? "  NEAR" : ""), cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      yr += rh;
      shown++;
   }
   int total = PositionsTotal();
   for(int i = 0; i < total && shown < NQ_BOARD_BROKER_ROWS; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(!NqIsOurs(PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
         continue;
      int pdir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      string kindT = NqKindOfComment(PositionGetString(POSITION_COMMENT));
      double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      long age = (long)nowS - (long)PositionGetInteger(POSITION_TIME);
      string id = "bb" + IntegerToString(shown);
      NqLabel(id + "0", cx0, yr, "POSITION", cKey, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel(id + "1", cx1, yr, (pdir > 0) ? "BUY" : "SELL", NqDirColor(pdir), fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel(id + "2", cx2, yr, NqPx(PositionGetDouble(POSITION_PRICE_OPEN)), cVal, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      NqLabel(id + "3", cx3, yr, NqPx(PositionGetDouble(POSITION_SL)), cDn, fs, "Arial", ANCHOR_LEFT_UPPER);
      NqLabel(id + "4", cx4, yr, NqPx(PositionGetDouble(POSITION_TP)), cUp, fs, "Arial", ANCHOR_LEFT_UPPER);
      NqLabel(id + "5", cx5, yr, NqMoney(pr), (pr >= 0.0) ? cUp : cDn, fs, "Arial", ANCHOR_LEFT_UPPER);
      NqLabel(id + "6", cx6, yr, "RUNNING  #" + IntegerToString((long)tk) + " " + kindT + " " + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) +
              " lot  " + NqHhMm(age), cUp, fs, "Arial Bold", ANCHOR_LEFT_UPPER);
      yr += rh;
      shown++;
   }
   if(shown == 0)
   {
      NqLabel("bb00", cx0, yr, "no broker orders or positions for this EA", cDim, fsH, "Arial", ANCHOR_LEFT_UPPER);
      for(int c = 1; c <= 6; c++)
         NqLabel("bb0" + IntegerToString(c), cx1, yr, " ", cDim, fsH, "Arial", ANCHOR_LEFT_UPPER);
      yr += rh;
      shown = 1;
   }
   for(int i = shown; i < NQ_BOARD_BROKER_ROWS; i++)
      if(ObjectFind(0, NQ_PFX_P + "bb" + IntegerToString(i) + "0") >= 0)
         ObjectsDeleteAll(0, NQ_PFX_P + "bb" + IntegerToString(i));

   // footer: today's plan lifecycle counts (M5 auto plans) + account + last update
   int cCan = 0;
   int cExp = 0;
   int cTp = 0;
   int cSl = 0;
   if(ok)
   {
      int dayNow = NqDayOf(nowS);
      for(int k = 0; k < g_nPlans; k++)
      {
         if(NqDayOf(g_s5.t[g_plans[k].statusIdx]) != dayNow)
            continue;
         if(g_plans[k].status == NQ_PL_REPLACED || g_plans[k].status == NQ_PL_INVALID)
            cCan++;
         if(g_plans[k].status == NQ_PL_EXPIRED)
            cExp++;
         if(g_plans[k].status == NQ_PL_TP1)
            cTp++;
         if(g_plans[k].status == NQ_PL_SL)
            cSl++;
      }
   }
   string gateT = (g_gate == 0) ? "GATE OPEN" : ("GATE: " + NqGateAtX(g_gate, 0));
   NqLabel("bf1", kx, yr, "ORDERS " + IntegerToString(g_pendCount) + "  POSITIONS " + IntegerToString(g_openCount) +
           "  TODAY M5: cancelled " + IntegerToString(cCan) + "  expired " + IntegerToString(cExp) + "  TP1 " +
           IntegerToString(cTp) + "  SL " + IntegerToString(cSl) + "   " + gateT, (g_gate == 0) ? cVal : cBlock, fsH, "Arial Bold", ANCHOR_LEFT_UPPER);
   yr += rh;
   string accT = g_isDemo ? "DEMO" : "REAL";
   NqLabel("bf2", kx, yr, accT + " " + g_accCcy + "  bal " + DoubleToString(g_balance, 2) +
           "  risk " + DoubleToString(InpRiskPct, 2) + "%=" + DoubleToString(g_riskMoney, 2) + "  day " + DoubleToString(g_dayPnl, 2) +
           "/" + DoubleToString(g_floating, 2) + "  cap " + ((g_capMoney > 0.0) ? ("-" + DoubleToString(g_capMoney, 2)) : "off") +
           "  scalp " + (InpScalpAuto ? "auto" : "off") + "  UPDATE " + TimeToString(nowS, TIME_SECONDS), cVal, fsH, "Arial", ANCHOR_LEFT_UPPER);
   y += tBotH + 4;

   NqLabel("f1", ox + pad, y, "Closed candles only. One slot per asset. Own orders only. Last " + g_lastTrade,
           cDim, fsH, "Arial", ANCHOR_LEFT_UPPER);
}
//+------------------------------------------------------------------+
