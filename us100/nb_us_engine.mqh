//=== NB_US_BEGIN === (US100 only: the US session calendar + the US level map - never a signal)
//+------------------------------------------------------------------+
//| US SESSION + LEVEL MAP (v1.11 US100)                             |
//| Every bar's time is converted to NEW YORK wall-clock time PER    |
//| BAR (US DST calendar), never with one scalar offset. Sessions    |
//| (context labels only - they change no rule):                     |
//|   OVERNIGHT 18:00-04:00  PRE-MARKET 04:00-09:30                  |
//|   OPEN 0-5 / 5-15 / 15-30 min  MORNING 10:00-11:30               |
//|   LUNCH 11:30-13:30  AFTERNOON 13:30-15:00  FINAL HOUR 15-16     |
//|   AFTER-HOURS 16:00-18:00  CLOSED (Fri 17:00 - Sun 18:00)        |
//| A trading day starts at 18:00 NY the evening before.             |
//| Levels are REFERENCE levels (battlefield), never a BUY / SELL:   |
//|   PDH / PDL / PREV CLOSE = the last REGULAR session (09:30-16:00)|
//|   with >= NB_US_RTH_MIN_BARS closed 5M bars - not the broker day |
//|   ON H/L (overnight) and PM H/L (pre-market): published when the |
//|   window has ENDED; pre-market never mixes with the regular      |
//|   session and vice versa                                         |
//|   OPEN = the 09:30 bar's open (unknown if that bar is missing)   |
//|   OR5 / OR15 / OR30: published at 09:35 / 09:45 / 10:00, only    |
//|   when every bar of the window exists                            |
//|   RTH H/L so far, GAP = OPEN - PREV CLOSE (x 15M ATR), FILLED    |
//|   when the regular session trades back to the previous close     |
//| Causal: bar i uses bars <= i; an unfinished bar is never used.   |
//+------------------------------------------------------------------+
#define NB_US_UNKNOWN   0   // no clock: never guessed
#define NB_US_CLOSED    1   // weekend
#define NB_US_OVERNIGHT 2
#define NB_US_PRE       3
#define NB_US_OPEN5     4
#define NB_US_OPEN15    5
#define NB_US_OPEN30    6
#define NB_US_MORNING   7
#define NB_US_LUNCH     8
#define NB_US_AFTERNOON 9
#define NB_US_FINAL     10
#define NB_US_AFTER     11

#define NB_US_RTH_MIN_BARS 36   // a regular session needs >= 36 closed 5M bars (3 h) to be "the previous day"
#define NB_US_WIN_MIN_BARS 12   // overnight / pre-market ranges need >= 12 closed 5M bars

struct NbUsBar
{
   long     et;            // bar start in NY wall-clock seconds (0 = clock unknown)
   int      sess;          // NB_US_*
   long     tday;          // trading day (NY date the session belongs to), -1 = unknown
   double   pdh;           // previous regular session high / low / close (0 = not known)
   double   pdl;
   double   pcl;
   double   onh;           // overnight high / low (published at 04:00 NY)
   double   onl;
   double   pmh;           // pre-market high / low (published at 09:30 NY)
   double   pml;
   double   open;          // regular-session open (the 09:30 bar), 0 = not known yet / missing
   double   or5h;
   double   or5l;
   double   or15h;
   double   or15l;
   double   or30h;
   double   or30l;
   double   rthH;          // regular session so far (0 before the open)
   double   rthL;
   double   gap;           // open - previous close (0 = not known)
   double   gapAtr;        // gap in 15M ATR
   int      gapDir;        // +1 up, -1 down, 0 none (below the threshold) or unknown
   bool     gapFilled;     // the regular session traded back to the previous close
};

void NbUsReset(NbUsBar &b)
{
   b.et = 0;
   b.sess = NB_US_UNKNOWN;
   b.tday = -1;
   b.pdh = 0.0;
   b.pdl = 0.0;
   b.pcl = 0.0;
   b.onh = 0.0;
   b.onl = 0.0;
   b.pmh = 0.0;
   b.pml = 0.0;
   b.open = 0.0;
   b.or5h = 0.0;
   b.or5l = 0.0;
   b.or15h = 0.0;
   b.or15l = 0.0;
   b.or30h = 0.0;
   b.or30l = 0.0;
   b.rthH = 0.0;
   b.rthL = 0.0;
   b.gap = 0.0;
   b.gapAtr = 0.0;
   b.gapDir = 0;
   b.gapFilled = false;
}

void NbUsCopy(NbUsBar &d, const NbUsBar &s)
{
   d.et = s.et;
   d.sess = s.sess;
   d.tday = s.tday;
   d.pdh = s.pdh;
   d.pdl = s.pdl;
   d.pcl = s.pcl;
   d.onh = s.onh;
   d.onl = s.onl;
   d.pmh = s.pmh;
   d.pml = s.pml;
   d.open = s.open;
   d.or5h = s.or5h;
   d.or5l = s.or5l;
   d.or15h = s.or15h;
   d.or15l = s.or15l;
   d.or30h = s.or30h;
   d.or30l = s.or30l;
   d.rthH = s.rthH;
   d.rthL = s.rthL;
   d.gap = s.gap;
   d.gapAtr = s.gapAtr;
   d.gapDir = s.gapDir;
   d.gapFilled = s.gapFilled;
}

// the broker server clock's own DST rule (it moves the server time, not NY's)
#define NB_SRVDST_US   0   // server offset changes with US DST (the usual NY-close UTC+2/+3 MT5 broker)
#define NB_SRVDST_EU   1   // server offset changes with EU DST (last Sunday March / October, 01:00 UTC)
#define NB_SRVDST_NONE 2   // server offset never changes

//--- is the server's summer hour in force at this UTC time?
bool NbSrvDstOn(int rule, long utc)
{
   if(rule == NB_SRVDST_NONE)
      return false;
   long day = utc / 86400;
   if(rule == NB_SRVDST_US)
      return NbUsDst(day);
   int y = 0;
   int m = 0;
   int d = 0;
   NbCivil(day, y, m, d);
   if(m < 3 || m > 10)
      return false;
   if(m > 3 && m < 10)
      return true;
   int dow = (int)((day + 4) % 7);            // 0 = Sunday
   int dow31 = (dow + (31 - d)) % 7;          // weekday of the 31st (March and October have 31 days)
   int lastSun = 31 - dow31;
   int hr = (int)((utc % 86400) / 3600);
   if(m == 3)
      return (d > lastSun) || (d == lastSun && hr >= 1);
   return (d < lastSun) || (d == lastSun && hr < 1);
}

//--- the server's WINTER offset from today's two-witness offset: history
//    is converted PER BAR through the server's DST rule, never with one
//    scalar (a 10-day history can cross a switch)
long NbSrvBase(long offsetNow, long nowUtc, int rule)
{
   return offsetNow - (NbSrvDstOn(rule, nowUtc) ? 3600 : 0);
}

//--- server time -> NY wall-clock seconds, PER BAR. AUTO: server -> UTC
//    through the server's DST rule, UTC -> NY through the US DST rule.
//    MANUAL: the typed 09:30 NY in server time (fixed - the user retypes
//    it when a clock changes). Unknown clock = 0 (never guessed).
long NbUsEt(datetime t, bool clockOk, int mode, long offBase, int srvRule, int manualOpenSec)
{
   if(!clockOk)
      return 0;
   if(mode == NB_CLK_MANUAL)
      return (long)t + (9 * 3600 + 1800) - manualOpenSec;
   long utc = (long)t - offBase - 3600;      // try the summer hour first
   if(!NbSrvDstOn(srvRule, utc))
      utc = (long)t - offBase;
   return utc - (NbUsDst(utc / 86400) ? 4 : 5) * 3600;
}

int NbUsSessOf(long et)
{
   if(et <= 0)
      return NB_US_UNKNOWN;
   long day = et / 86400;
   int mn = (int)((et % 86400) / 60);
   int dow = (int)((day + 4) % 7);   // 0 = Sunday
   if(dow == 6 || (dow == 0 && mn < 18 * 60) || (dow == 5 && mn >= 17 * 60))
      return NB_US_CLOSED;
   if(mn >= 18 * 60 || mn < 4 * 60)
      return NB_US_OVERNIGHT;
   if(mn < 9 * 60 + 30)
      return NB_US_PRE;
   if(mn < 9 * 60 + 35)
      return NB_US_OPEN5;
   if(mn < 9 * 60 + 45)
      return NB_US_OPEN15;
   if(mn < 10 * 60)
      return NB_US_OPEN30;
   if(mn < 11 * 60 + 30)
      return NB_US_MORNING;
   if(mn < 13 * 60 + 30)
      return NB_US_LUNCH;
   if(mn < 15 * 60)
      return NB_US_AFTERNOON;
   if(mn < 16 * 60)
      return NB_US_FINAL;
   return NB_US_AFTER;
}

string NbUsSessText(int s)
{
   switch(s)
   {
      case NB_US_CLOSED:    return "CLOSED (WEEKEND)";
      case NB_US_OVERNIGHT: return "OVERNIGHT (FUTURES HOURS)";
      case NB_US_PRE:       return "PRE-MARKET";
      case NB_US_OPEN5:     return "OPEN - FIRST 5 MIN";
      case NB_US_OPEN15:    return "OPEN - 5 TO 15 MIN";
      case NB_US_OPEN30:    return "OPEN - 15 TO 30 MIN";
      case NB_US_MORNING:   return "MORNING";
      case NB_US_LUNCH:     return "LUNCH - LOW LIQUIDITY";
      case NB_US_AFTERNOON: return "AFTERNOON";
      case NB_US_FINAL:     return "FINAL HOUR";
      case NB_US_AFTER:     return "AFTER-HOURS / CLOSE";
   }
   return "UNKNOWN - NO CLOCK";
}

bool NbUsIsRth(int s)
{
   return (s >= NB_US_OPEN5 && s <= NB_US_FINAL);
}

//--- a level lies strictly between the previous close and this bar's
//    open: nothing traded at it (a GAP), so crossing it is neither a
//    sweep nor a breakout
bool NbUsGapped(double prevClose, double open, double lvl)
{
   return (prevClose < lvl && open > lvl) || (prevClose > lvl && open < lvl);
}

//--- the US map for every 5M bar. s5.map must align s5 to s15 (NbRun5).
//    lastClosed = false: the last bar is still forming and is NOT used.
void NbRunUs(const NbSeries &s5, const NbSeries &s15, bool lastClosed, bool clockOk, int mode, long offBase,
             int srvRule, int manualOpenSec, double gapMinAtr, NbUsBar &us[])
{
   int n = s5.n;
   ArrayResize(us, n);
   int nEval = lastClosed ? n : n - 1;
   long curDay = -1;
   // the last complete regular session
   double pdh = 0.0;
   double pdl = 0.0;
   double pcl = 0.0;
   // today's windows
   double onH = 0.0;
   double onL = 0.0;
   int onN = 0;
   bool onPub = false;
   double pmH = 0.0;
   double pmL = 0.0;
   int pmN = 0;
   bool pmPub = false;
   double rH = 0.0;
   double rL = 0.0;
   int rN = 0;
   double rC = 0.0;
   double op = 0.0;
   bool opSeen = false;
   double oH[3];
   double oL[3];
   int oN[3];
   bool oPub[3];
   double kH[3];
   double kL[3];
   int orMin[3];
   orMin[0] = 5;
   orMin[1] = 15;
   orMin[2] = 30;
   for(int q = 0; q < 3; q++)
   {
      oH[q] = 0.0;
      oL[q] = 0.0;
      oN[q] = 0;
      oPub[q] = false;
      kH[q] = 0.0;
      kL[q] = 0.0;
   }
   double gap = 0.0;
   double gapAtr = 0.0;
   int gapDir = 0;
   bool gapFilled = false;
   double onKH = 0.0;
   double onKL = 0.0;
   double pmKH = 0.0;
   double pmKL = 0.0;
   for(int i = 0; i < n; i++)
   {
      NbUsReset(us[i]);
      if(i >= nEval)
      {
         // unfinished candle: carry the last CLOSED answer, never use it
         if(i > 0)
            NbUsCopy(us[i], us[i - 1]);
         continue;
      }
      long et = NbUsEt(s5.t[i], clockOk, mode, offBase, srvRule, manualOpenSec);
      int ss = NbUsSessOf(et);
      us[i].et = et;
      us[i].sess = ss;
      if(et <= 0)
         continue;
      long day = et / 86400;
      int mn = (int)((et % 86400) / 60);
      long tday = (mn >= 18 * 60) ? day + 1 : day;
      us[i].tday = tday;
      if(tday != curDay)
      {
         // a new trading day: the finished regular session becomes "the previous day"
         if(curDay >= 0 && rN >= NB_US_RTH_MIN_BARS)
         {
            pdh = rH;
            pdl = rL;
            pcl = rC;
         }
         curDay = tday;
         onH = 0.0;
         onL = 0.0;
         onN = 0;
         onPub = false;
         onKH = 0.0;
         onKL = 0.0;
         pmH = 0.0;
         pmL = 0.0;
         pmN = 0;
         pmPub = false;
         pmKH = 0.0;
         pmKL = 0.0;
         rH = 0.0;
         rL = 0.0;
         rN = 0;
         rC = 0.0;
         op = 0.0;
         opSeen = false;
         for(int q = 0; q < 3; q++)
         {
            oH[q] = 0.0;
            oL[q] = 0.0;
            oN[q] = 0;
            oPub[q] = false;
            kH[q] = 0.0;
            kL[q] = 0.0;
         }
         gap = 0.0;
         gapAtr = 0.0;
         gapDir = 0;
         gapFilled = false;
      }
      long base = tday * 86400;
      long endEt = et + s5.sec;
      double hi = s5.h[i];
      double lo = s5.l[i];
      if(ss == NB_US_OVERNIGHT)
      {
         onH = (onN == 0) ? hi : MathMax(onH, hi);
         onL = (onN == 0) ? lo : MathMin(onL, lo);
         onN++;
      }
      if(ss == NB_US_PRE)
      {
         pmH = (pmN == 0) ? hi : MathMax(pmH, hi);
         pmL = (pmN == 0) ? lo : MathMin(pmL, lo);
         pmN++;
      }
      if(!onPub && endEt >= base + 4 * 3600)
      {
         onPub = true;
         if(onN >= NB_US_WIN_MIN_BARS)
         {
            onKH = onH;
            onKL = onL;
         }
      }
      if(!pmPub && endEt >= base + 9 * 3600 + 1800)
      {
         pmPub = true;
         if(pmN >= NB_US_WIN_MIN_BARS)
         {
            pmKH = pmH;
            pmKL = pmL;
         }
      }
      if(NbUsIsRth(ss))
      {
         if(!opSeen)
         {
            opSeen = true;
            // the open is the 09:30 bar's open; a later first bar = open unknown
            if(et == base + 9 * 3600 + 1800)
               op = s5.o[i];
         }
         rH = (rN == 0) ? hi : MathMax(rH, hi);
         rL = (rN == 0) ? lo : MathMin(rL, lo);
         rC = s5.c[i];
         rN++;
         for(int q = 0; q < 3; q++)
         {
            if(et < base + 9 * 3600 + 1800 + orMin[q] * 60)
            {
               oH[q] = (oN[q] == 0) ? hi : MathMax(oH[q], hi);
               oL[q] = (oN[q] == 0) ? lo : MathMin(oL[q], lo);
               oN[q]++;
            }
         }
         if(op > 0.0 && pcl > 0.0 && gap == 0.0 && gapDir == 0 && !gapFilled)
         {
            gap = op - pcl;
            int k15 = s5.map[i];
            double a15 = (k15 >= 0) ? s15.atr[k15] : 0.0;
            gapAtr = (a15 > 0.0) ? gap / a15 : 0.0;
            if(a15 > 0.0 && MathAbs(gap) >= gapMinAtr * a15)
               gapDir = (gap > 0.0) ? 1 : -1;
         }
         if(gapDir > 0 && lo <= pcl)
            gapFilled = true;
         if(gapDir < 0 && hi >= pcl)
            gapFilled = true;
      }
      for(int q = 0; q < 3; q++)
      {
         if(!oPub[q] && endEt >= base + 9 * 3600 + 1800 + orMin[q] * 60)
         {
            oPub[q] = true;
            if(op > 0.0 && oN[q] == orMin[q] / 5)
            {
               kH[q] = oH[q];
               kL[q] = oL[q];
            }
         }
      }
      us[i].pdh = pdh;
      us[i].pdl = pdl;
      us[i].pcl = pcl;
      us[i].onh = onKH;
      us[i].onl = onKL;
      us[i].pmh = pmKH;
      us[i].pml = pmKL;
      us[i].open = op;
      us[i].or5h = kH[0];
      us[i].or5l = kL[0];
      us[i].or15h = kH[1];
      us[i].or15l = kL[1];
      us[i].or30h = kH[2];
      us[i].or30l = kL[2];
      us[i].rthH = (rN > 0) ? rH : 0.0;
      us[i].rthL = (rN > 0) ? rL : 0.0;
      us[i].gap = gap;
      us[i].gapAtr = gapAtr;
      us[i].gapDir = gapDir;
      us[i].gapFilled = gapFilled;
   }
}

//=== NB_US_END ===
