// Engine tests for the NY-trap twins. build/engine_<market>.inc is the ENGINE
// block of the real .mq5, translated syntax-only by mql2cpp.py. Compiled
// once per twin (NB_TEST_MARKET 1 = crypto, 2 = forex).
#include "../tests/mql_shim.h"
#if NB_TEST_MARKET == 2
#include "engine_forex.inc"
#else
#include "engine_crypto.inc"
#endif
#include "../tests/synth.h"
#include <cstdio>
#include <map>

static int g_pass = 0, g_fail = 0, g_sec = 0;
#define CHECK(cond, msg)                                                   \
   do {                                                                    \
      if(cond) g_pass++;                                                   \
      else { g_fail++; std::printf("    FAIL %s:%d  %s\n", __FILE__, __LINE__, msg); } \
   } while(0)
static void begin(const char *n) { g_sec = g_fail; std::printf("[ RUN  ] %s\n", n); }
static void end(const char *n) { std::printf("[ %s ] %s\n", g_fail == g_sec ? " OK " : "FAIL", n); }
static bool near(double a, double b, double eps = 1e-9) { return std::fabs(a - b) <= eps; }

static NbParams params(double tick, int digits, int validBars = 6)
{
   NbParams P;
   P.atrPeriod = 14; P.nrtrMult = 2.0; P.emaPeriod = 200; P.swing = 3; P.slBufAtr = 0.10;
   P.tp1R = 1.0; P.tp2R = 2.0; P.validBars = validBars; P.tick = tick; P.digits = digits;
   return P;
}
static NbSessCfg manualCfg(bool pause = true)
{
   NbSessCfg S;
   S.clockMode = NB_CLK_MANUAL; S.clockOk = true; S.offset = 0; S.manualOpenSec = 16 * 3600 + 1800;
   S.preHours = 4; S.winMin = 90; S.minRangeBars = 12; S.pauseFlow = pause;
   return S;
}
static NbSessCfg autoCfg(long off, bool pause = true)
{
   NbSessCfg S = manualCfg(pause);
   S.clockMode = NB_CLK_AUTO; S.offset = off;
   return S;
}
static long long dayOf(int y, int m, int d)   // UTC midnight
{
   // inverse of NbCivil, via a brute search around an estimate (test-only)
   long long guess = (long long)((y - 1970) * 365.2425 + (m - 1) * 30.4 + d - 1);
   for(long long k = guess - 40; k < guess + 40; k++)
   {
      int yy, mm, dd;
      NbCivil(k, yy, mm, dd);
      if(yy == y && mm == m && dd == d) return k;
   }
   return -1;
}

//--- crafted 5M day: pre-NY range then NY bars, MANUAL clock (16:30)
struct Day
{
   NbSeries s;
   std::vector<NbPivot> piv;
   std::vector<int> boss, bossR;
   std::vector<NbSignal> sigs;
   int nSig = 0;
   Day() { NbSeriesResize(s, 0); s.sec = 300; }
};
static const long long D0 = 1788220800LL;   // a UTC day boundary
// bar with an explicit OHLC appended at the next 5M slot
static void bar(Day &d, double o, double h, double l, double c)
{
   int n = d.s.n;
   NbSeriesResize(d.s, n + 1);
   d.s.t[(size_t)n] = D0 + 12 * 3600 + 1800 + (long long)n * 300;   // first bar 12:30 = preStart
   d.s.o[(size_t)n] = o; d.s.h[(size_t)n] = h; d.s.l[(size_t)n] = l; d.s.c[(size_t)n] = c;
}
static void preRange(Day &d, int bars = 48)   // 12:30 .. 16:25, flat: H 100.5 / L 99.5
{
   for(int i = 0; i < bars; i++)
      bar(d, 100.0, 100.5, 99.5, (i % 2 == 0) ? 100.2 : 99.8);
}
static std::vector<int> g_dir5Override;   // optional per-bar 5M NRTR direction
static void run(Day &d, const NbParams &P, const NbSessCfg &S, int boss = 0, int dir5 = 0, bool lastClosed = true)
{
   int n = d.s.n;
   d.s.sec = 300;
   ArrayResize(d.s.atr, n); ArrayInitialize(d.s.atr, 1.0);
   ArrayResize(d.s.dir, n); ArrayInitialize(d.s.dir, dir5);
   for(int i = 0; i < n && i < (int)g_dir5Override.size(); i++) d.s.dir[(size_t)i] = g_dir5Override[(size_t)i];
   d.boss.assign((size_t)n, boss);
   d.bossR.assign((size_t)n, boss == 0 ? NB_R_STRUCT_UNCONF : 0);
   d.s.np = NbFindPivots(d.s.h, d.s.l, n, P.swing, d.piv);
   NbRunSession(d.s, S);
   NbRunTrigger(d.s.o, d.s.h, d.s.l, d.s.c, d.s.atr, d.s.dir, d.boss, d.bossR, d.piv, d.s.np, n, lastClosed, P,
                d.s.ph, d.s.sid, d.s.rh, d.s.rl, d.s.rn, d.s.swH, d.s.swL, S,
                d.s.state, d.s.reasons, d.s.sigOf, d.sigs, d.nSig);
}

//--- full pipeline over synthetic data
struct Run
{
   NbSeries s15, s5;
   std::vector<NbPivot> p15, p5;
   std::vector<NbSignal> sigs;
   int nSig = 0;
};
static void fill(NbSeries &s, const std::vector<SBar> &v, int sec)
{
   NbSeriesResize(s, (int)v.size());
   s.sec = sec;
   for(size_t i = 0; i < v.size(); i++) { s.t[i] = v[i].t; s.o[i] = v[i].o; s.h[i] = v[i].h; s.l[i] = v[i].l; s.c[i] = v[i].c; }
}
static void runAt(Run &r, const std::vector<SBar> &m5, const std::vector<SBar> &m15, int first5, int last5,
                  long long first15t, const NbParams &P, const NbSessCfg &S)
{
   std::vector<SBar> a(m5.begin() + first5, m5.begin() + last5 + 1);
   long long known = m5[(size_t)last5].t + 300;
   std::vector<SBar> b;
   for(const SBar &x : m15) if(x.t >= first15t && x.t + 900 <= known) b.push_back(x);
   fill(r.s5, a, 300);
   fill(r.s15, b, 900);
   NbRun15(r.s15, r.p15, P);
   NbRun5(r.s5, r.p5, r.s15, true, P, S, r.sigs, r.nSig);
}

int main()
{
   std::printf("market under test: %s\n", NB_MARKET == NB_MKT_CRYPTO ? "CRYPTO" : "FOREX");
   NbParams P = params(0.01, 2);

   begin("S1 civil calendar and the US DST rule, computed per day");
   {
      int y, m, d;
      NbCivil(0, y, m, d);
      CHECK(y == 1970 && m == 1 && d == 1, "day 0 = 1970-01-01");
      NbCivil(D0 / 86400, y, m, d);
      std::printf("    D0 = %04d-%02d-%02d\n", y, m, d);
      long long mar7 = dayOf(2026, 3, 7), mar8 = dayOf(2026, 3, 8), oct31 = dayOf(2026, 10, 31), nov1 = dayOf(2026, 11, 1);
      CHECK(mar7 > 0 && !NbUsDst(mar7) && NbUsDst(mar8), "2026: DST starts Sunday 8 March (second Sunday)");
      CHECK(NbUsDst(oct31) && !NbUsDst(nov1), "2026: DST ends Sunday 1 November (first Sunday)");
      CHECK(!NbUsDst(dayOf(2025, 3, 8)) && NbUsDst(dayOf(2025, 3, 9)), "2025: DST starts 9 March");
      CHECK(NbUsDst(dayOf(2025, 11, 1)) && !NbUsDst(dayOf(2025, 11, 2)), "2025: DST ends 2 November");
      CHECK(!NbUsDst(dayOf(2026, 1, 15)) && NbUsDst(dayOf(2026, 7, 4)) && !NbUsDst(dayOf(2026, 12, 25)), "plain months");
      CHECK((dayOf(2026, 9, 25) + 4) % 7 == 5, "2026-09-25 is a Friday (weekday arithmetic)");
   }
   end("S1");

   begin("S2 NY open in broker time: offset + US DST per day, MANUAL typed");
   {
      long sid = 0;
      // EEST broker (+3): NY open 13:30 UTC in summer -> 16:30 server
      long long t = dayOf(2026, 9, 25) * 86400 + 3 * 3600 + 10 * 3600;   // 10:00 server on 25 Sep
      NbSessCfg S = autoCfg(3 * 3600);
      datetime open = NbNyOpenOf(t, S, sid);
      CHECK(open == dayOf(2026, 9, 25) * 86400 + 16 * 3600 + 1800, "summer, UTC+3 server: NY open 16:30 server");
      CHECK(sid == dayOf(2026, 9, 25), "session id = UTC day");
      // EET broker (+2) in January: 14:30 UTC + 2 = 16:30 server
      S = autoCfg(2 * 3600);
      t = dayOf(2026, 1, 20) * 86400 + 2 * 3600 + 10 * 3600;
      CHECK(NbNyOpenOf(t, S, sid) == dayOf(2026, 1, 20) * 86400 + 16 * 3600 + 1800, "winter, UTC+2 server: still 16:30 server");
      // the odd weeks: US on DST, Europe not (8-29 March 2026): 13:30 UTC + 2 = 15:30 server
      t = dayOf(2026, 3, 16) * 86400 + 2 * 3600 + 10 * 3600;
      CHECK(NbNyOpenOf(t, S, sid) == dayOf(2026, 3, 16) * 86400 + 15 * 3600 + 1800, "US DST but EU not yet: 15:30 server");
      // a bar late in the server day still belongs to the same UTC day session
      t = dayOf(2026, 9, 25) * 86400 + 3 * 3600 + 23 * 3600 + 1800;   // 23:30 server = 20:30 UTC
      S = autoCfg(3 * 3600);
      CHECK(NbNyOpenOf(t, S, sid) == dayOf(2026, 9, 25) * 86400 + 16 * 3600 + 1800 && sid == dayOf(2026, 9, 25), "late bar: same session");
      // 01:00 server = 22:00 UTC previous day -> previous UTC day's session (already over)
      t = dayOf(2026, 9, 26) * 86400 + 3600;
      CHECK(sid != -1 && NbNyOpenOf(t, S, sid) == dayOf(2026, 9, 25) * 86400 + 16 * 3600 + 1800, "01:00 server belongs to the UTC day before");
      // MANUAL: server day + typed time, no offset involved
      S = manualCfg();
      t = dayOf(2026, 9, 25) * 86400 + 5 * 3600;
      CHECK(NbNyOpenOf(t, S, sid) == dayOf(2026, 9, 25) * 86400 + 16 * 3600 + 1800 && sid == dayOf(2026, 9, 25), "MANUAL 16:30 on the server day");
      // negative offset (a UTC-5 broker): 13:30 UTC = 08:30 server
      S = autoCfg(-5 * 3600);
      t = dayOf(2026, 9, 25) * 86400 - 5 * 3600 + 3 * 3600;
      CHECK(NbNyOpenOf(t, S, sid) == dayOf(2026, 9, 25) * 86400 + 13 * 3600 + 1800 - 5 * 3600, "UTC-5 server: 08:30 server");
   }
   end("S2");

   begin("S3 clock from two witnesses: half-hour offsets only, else OFF");
   {
      long off = 0;
      CHECK(NbClockFromWitnesses(1000000 + 3 * 3600, 1000000, off) && off == 3 * 3600, "+3h exactly");
      CHECK(NbClockFromWitnesses(1000000 + 3 * 3600 + 200, 1000000, off) && off == 3 * 3600, "+3h with a 200s PC drift -> +3h");
      CHECK(NbClockFromWitnesses(1000000 + 5 * 3600 + 1800, 1000000, off) && off == 5 * 3600 + 1800, "+5:30 (a half-hour zone)");
      CHECK(NbClockFromWitnesses(1000000 - 5 * 3600, 1000000, off) && off == -5 * 3600, "-5h");
      CHECK(!NbClockFromWitnesses(1000000 + 3 * 3600 + 600, 1000000, off) && off == 0, "10 min off a half hour: the witnesses disagree -> OFF");
      CHECK(!NbClockFromWitnesses(1000000 + 20 * 3600, 1000000, off), "+20h is not a time zone -> OFF");
      CHECK(!NbClockFromWitnesses(1000000, 0, off), "no PC time -> OFF");
      CHECK(!NbClockFromWitnesses(0, 1000000, off), "no server time -> OFF");
   }
   end("S3");

   begin("S4 session pass: phases, pre-NY range, sweeps (causal)");
   {
      Day d;
      preRange(d);                              // 48 bars 12:30..16:25
      bar(d, 100.2, 100.9, 100.0, 100.7);       // 16:30 sweeps the high, closes ABOVE
      bar(d, 100.7, 100.8, 99.2, 99.4);         // 16:35 sweeps both sides? no: low 99.2 < 99.5 too
      for(int i = 0; i < 16; i++) bar(d, 100.0, 100.4, 99.6, 100.0);   // rest of the window to 18:00
      bar(d, 100.0, 100.4, 99.6, 100.0);        // 18:00 -> OUT
      run(d, P, manualCfg());
      CHECK(d.s.ph[0] == NB_PH_PRE && d.s.ph[47] == NB_PH_PRE, "12:30-16:25 = PRE");
      CHECK(d.s.ph[48] == NB_PH_NY && d.s.ph[65] == NB_PH_NY, "16:30-17:55 = NY window");
      CHECK(d.s.ph[66] == NB_PH_OUT, "18:00 = OUT");
      CHECK(d.s.rn[47] == 48 && near(d.s.rh[47], 100.5) && near(d.s.rl[47], 99.5), "range at the last PRE bar");
      CHECK(d.s.rn[11] == 12 && d.s.rn[5] == 6, "range bar count grows causally");
      CHECK(near(d.s.rh[48], 100.5) && d.s.rn[48] == 48, "NY bars carry the finished range");
      CHECK(near(d.s.swH[48], 100.9) && d.s.swL[48] == 0.0, "first NY bar: high swept to 100.9, low not");
      CHECK(near(d.s.swH[49], 100.9) && near(d.s.swL[49], 99.2), "second bar: high sweep remembered, low now swept too");
      CHECK(d.s.rn[66] == 0 && d.s.swH[66] == 0.0, "outside: nothing");
      // a short pre window does not count
      Day e;
      for(int i = 0; i < 40; i++) bar(e, 100.0, 100.4, 99.6, 100.0);   // 12:30..15:45 OUT-of-range? no: still PRE
      run(e, P, manualCfg());
      CHECK(e.s.ph[39] == NB_PH_PRE && e.s.rn[39] == 40, "partial pre window still builds");
      // clock OFF -> everything OUT
      NbSessCfg off = manualCfg();
      off.clockOk = false;
      run(d, P, off);
      bool allOut = true;
      for(int i = 0; i < d.s.n; i++) allOut = allOut && d.s.ph[(size_t)i] == NB_PH_OUT && d.s.rn[(size_t)i] == 0;
      CHECK(allOut, "clock unknown -> the session module is OFF, never guessed");
      // AUTO clock, +3h offset, on a summer day: the same bars (server 12:30..) map to the same phases
      Day f;
      preRange(f);
      bar(f, 100.2, 100.9, 100.0, 99.9);
      NbSessCfg A = autoCfg(3 * 3600);
      run(f, P, A);
      int yy, mm, dd;
      NbCivil(D0 / 86400, yy, mm, dd);
      bool summer = NbUsDst(D0 / 86400);
      std::printf("    D0 is %04d-%02d-%02d, US DST %s\n", yy, mm, dd, summer ? "on" : "off");
      CHECK(summer ? (f.s.ph[48] == NB_PH_NY && f.s.ph[0] == NB_PH_PRE) : (f.s.ph[48] == NB_PH_PRE), "AUTO +3h: 16:30 server is the NY open in summer");
   }
   end("S4");

   begin("S5 NY SELL trap: sweep of the pre-NY high, close back inside -> CLICK SELL with levels");
   {
      // one-bar version: the sweep candle itself closes back inside, bearish
      Day d;
      preRange(d);
      bar(d, 100.2, 100.9, 100.0, 99.9);        // 16:30: sweep to 100.9, bearish close 99.9 < 100.5
      bar(d, 99.9, 100.1, 99.7, 99.8);          // 16:35
      bar(d, 99.8, 99.9, 98.7, 98.9);           // 16:40: low 98.7 <= TP1 98.80 -> reached TP1
      bar(d, 98.9, 101.5, 98.8, 99.0);          // 16:45: sweeps AGAIN, closes inside bearish -> NO second trap
      for(int i = 0; i < 14; i++) bar(d, 99.0, 99.4, 98.6, 99.0);
      bar(d, 99.0, 99.4, 98.6, 99.0);           // 18:00 OUT
      run(d, P, manualCfg());
      CHECK(d.s.state[47] == NB_WAIT && (d.s.reasons[47] & NB_R_NY_WINDOW) == 0, "PRE bars: no NY reason");
      CHECK(d.s.state[48] == NB_SELL && d.nSig == 1, "sweep + bearish close inside = CLICK SELL on that bar");
      CHECK(d.sigs[0].kind == NB_K_TRAP && d.sigs[0].dir == NB_SELL && d.sigs[0].idx == 48, "trap signal at 16:30");
      CHECK(near(d.sigs[0].entry, 99.9), "entry = close of the reclaim candle");
      CHECK(near(d.sigs[0].sl, 101.0), "SL = sweep 100.9 + 0.1*ATR, rounded UP to tick");
      CHECK(near(d.sigs[0].risk, 1.10) && near(d.sigs[0].tp1, 98.80) && near(d.sigs[0].tp2, 97.70), "R = 1.10, TP1 = 1R, TP2 = 2R");
      CHECK(near(d.sigs[0].level, 100.5) && near(d.sigs[0].sweep, 100.9), "level swept and sweep extreme recorded");
      CHECK(d.s.state[49] == NB_SELL, "still clickable next bar");
      CHECK(d.sigs[0].status == NB_SIG_TP1 && d.sigs[0].statusIdx == 50, "TP1 reached at 16:40");
      CHECK(d.s.state[50] == NB_WAIT && (d.s.reasons[50] & NB_R_SIG_TP1) != 0, "after TP1: WAIT, TOO LATE");
      CHECK(d.nSig == 1 && d.s.state[51] == NB_WAIT, "second sweep in the same session: no second SELL trap");
      CHECK(d.s.sigOf[65] == 0 && (d.s.reasons[65] & NB_R_SIG_TP1) != 0, "reason stays until the window ends");
      CHECK(d.s.sigOf[66] == -1 && (d.s.reasons[66] & NB_R_SIG_TP1) == 0, "window over: trap released");
      CHECK(NbReasonAt(d.s.reasons[66], 0) == "15M STRUCTURE NOT CONFIRMED", "outside: back to the boss's reasons");

      // two-bar version: sweep candle closes above; the NEXT bearish close inside is the trigger
      Day e;
      preRange(e);
      bar(e, 100.2, 100.9, 100.0, 100.7);       // 16:30 sweep, closes above the range (bullish) -> not yet
      bar(e, 100.7, 100.8, 100.1, 100.3);       // 16:35 bearish close back inside -> SELL
      run(e, P, manualCfg());
      CHECK(e.s.state[48] == NB_WAIT && (e.s.reasons[48] & NB_R_NY_WINDOW) != 0, "sweep bar closing above: WAIT, watching");
      CHECK(e.s.state[49] == NB_SELL && e.nSig == 1 && e.sigs[0].idx == 49, "reclaim bar triggers");
      CHECK(near(e.sigs[0].entry, 100.3) && near(e.sigs[0].sl, 101.0) && near(e.sigs[0].risk, 0.70), "SL from the sweep extreme of the earlier bar");
      CHECK(near(e.sigs[0].tp1, 99.60) && near(e.sigs[0].tp2, 98.90), "TPs");
      CHECK(NbReasonAt(e.s.reasons[48], 0) == "NY OPEN WINDOW - FLOW PAUSED, WATCHING FOR SWEEP", "plain-English reason inside the window");

      // a bearish close that is still ABOVE the range high is not a reclaim
      Day f;
      preRange(f);
      bar(f, 100.9, 101.2, 100.6, 100.7);       // bearish body but closed above 100.5
      run(f, P, manualCfg());
      CHECK(f.s.state[48] == NB_WAIT && f.nSig == 0, "bearish close still above the range: no trap");
      // a bullish close inside after a high sweep is not a SELL trap either
      Day g;
      preRange(g);
      bar(g, 100.0, 100.9, 99.9, 100.3);        // swept, closed inside, but bullish body
      run(g, P, manualCfg());
      CHECK(g.s.state[48] == NB_WAIT && g.nSig == 0, "bullish body: not a SELL trap");
   }
   end("S5");

   begin("S6 NY BUY trap: mirror image");
   {
      Day d;
      preRange(d);
      bar(d, 100.0, 100.4, 99.9, 100.1);        // 16:30 nothing
      bar(d, 99.8, 100.0, 99.1, 100.1);         // 16:35 sweep low to 99.1, bullish close 100.1 > 99.5 -> BUY
      bar(d, 100.1, 100.3, 99.9, 100.2);
      bar(d, 100.2, 100.3, 98.9, 99.0);         // 16:45 high stays < TP1, low 98.9 <= SL 99.00 -> SL
      run(d, P, manualCfg());
      CHECK(d.s.state[49] == NB_BUY && d.nSig == 1 && d.sigs[0].kind == NB_K_TRAP && d.sigs[0].dir == NB_BUY, "CLICK BUY - NY TRAP");
      CHECK(near(d.sigs[0].entry, 100.1) && near(d.sigs[0].sl, 99.00) && near(d.sigs[0].risk, 1.10), "SL = sweep 99.1 - 0.1, rounded DOWN");
      CHECK(near(d.sigs[0].tp1, 101.20) && near(d.sigs[0].tp2, 102.30), "TPs above");
      CHECK(d.sigs[0].status == NB_SIG_SL && d.sigs[0].statusIdx == 51, "SL hit at 16:45");
      CHECK(d.s.state[51] == NB_WAIT && (d.s.reasons[51] & NB_R_SIG_SL) != 0, "after SL: STAND ASIDE");
      // after the BUY trap failed, a SELL trap in the same session is still allowed (other side)
      bar(d, 99.4, 100.9, 98.9, 99.2);          // 16:50 sweep high, bearish close inside
      run(d, P, manualCfg());
      CHECK(d.nSig == 2 && d.sigs[1].dir == NB_SELL && d.sigs[1].idx == 52 && d.s.state[52] == NB_SELL, "other side: one trap per side per session");
   }
   end("S6");

   begin("S7 no pre-NY range -> NO RANGE, nothing to sweep");
   {
      Day d;
      for(int i = 0; i < 44; i++) bar(d, 100.0, 100.4, 99.6, 100.0);   // start 12:30 but only... wait: still 44 PRE bars
      // trim: keep only the last 8 PRE bars by moving the start -> emulate a late feed: build 8 PRE bars at 15:50
      Day e;
      {
         int n = 0;
         for(int i = 0; i < 8; i++)
         {
            NbSeriesResize(e.s, n + 1);
            e.s.t[(size_t)n] = D0 + 15 * 3600 + 50 * 60 + (long long)i * 300;
            e.s.o[(size_t)n] = 100.0; e.s.h[(size_t)n] = 100.5; e.s.l[(size_t)n] = 99.5; e.s.c[(size_t)n] = 100.1;
            n++;
         }
         NbSeriesResize(e.s, n + 1);   // 16:30: a textbook sweep + bearish reclaim
         e.s.t[(size_t)n] = D0 + 16 * 3600 + 1800;
         e.s.o[(size_t)n] = 100.2; e.s.h[(size_t)n] = 100.9; e.s.l[(size_t)n] = 100.0; e.s.c[(size_t)n] = 99.9;
      }
      run(e, P, manualCfg());
      CHECK(e.s.rn[8] == 8 && e.s.ph[8] == NB_PH_NY, "8 pre bars < 12 minimum");
      CHECK(e.s.swH[8] == 0.0, "no valid range -> no sweep recorded");
      CHECK(e.s.state[8] == NB_WAIT && e.nSig == 0, "no trap without a range");
      CHECK((e.s.reasons[8] & NB_R_NY_NO_RANGE) != 0 && (e.s.reasons[8] & NB_R_NY_WINDOW) != 0, "reason: NY window + no range");
      CHECK(NbReasonAt(e.s.reasons[8], 1) == "NO PRE-NY RANGE (NOT ENOUGH 5M BARS BEFORE OPEN)", "plain-English");
   }
   end("S7");

   begin("S8 flow and trap: the window pauses new flow, a trap cancels an active flow signal");
   {
      // 15M BUY mode all day, 5M bullish. Pre bars: a confirmed swing low at bar 5 for the flow SL,
      // bearish bodies, then one bullish body at bar 9 -> flow BUY.
      auto build = [](Day &d)
      {
         for(int i = 0; i < 48; i++)
         {
            double lo = (i == 5) ? 98.0 : 99.5;
            if(i == 9) bar(d, 99.9, 100.5, lo, 100.1);      // bullish body
            else bar(d, 100.2, 100.5, lo, 100.0);           // bearish body
         }
      };
      NbParams PL = params(0.01, 2, 400);   // long validity so the flow signal is still active at 16:30
      Day d;
      build(d);
      bar(d, 100.2, 100.9, 100.0, 99.9);    // 16:30 SELL trap
      for(int i = 0; i < 17; i++) bar(d, 99.9, 100.2, 99.8, 100.0);   // window runs out (trap expires? validity 400 -> no)
      run(d, PL, manualCfg(true), 1, 1);
      CHECK(d.nSig == 2 && d.sigs[0].kind == NB_K_FLOW && d.sigs[0].idx == 9 && d.sigs[0].dir == NB_BUY, "flow BUY at bar 9");
      CHECK(near(d.sigs[0].sl, 97.90), "flow SL from the confirmed swing low 98 - 0.1");
      CHECK(d.s.state[47] == NB_BUY, "flow signal still clickable at the last PRE bar");
      CHECK(d.sigs[1].kind == NB_K_TRAP && d.sigs[1].idx == 48 && d.s.state[48] == NB_SELL, "16:30: the trap fires");
      CHECK(d.sigs[0].status == NB_SIG_CANCELLED && d.sigs[0].statusIdx == 48, "the active flow BUY is CANCELLED by the trap");
      CHECK(d.s.state[60] == NB_SELL, "trap stays clickable for its validity");

      // pause on, no sweep: aligned bullish candles inside the window do NOT start a flow signal
      Day e;
      build(e);
      for(int i = 0; i < 18; i++) bar(e, 99.9, 100.4, 99.6, 100.1);   // bullish bodies inside the window, no sweep
      bar(e, 99.9, 100.4, 99.6, 100.1);                                // 18:00 OUT
      run(e, params(0.01, 2, 6), manualCfg(true), 1, 1);
      CHECK(e.nSig >= 1 && e.sigs[0].idx == 9 && e.sigs[0].status == NB_SIG_EXPIRED, "flow BUY expired long before the window");
      bool noneInWindow = true;
      for(int k = 0; k < e.nSig; k++) if(e.sigs[(size_t)k].idx >= 48 && e.sigs[(size_t)k].idx < 66) noneInWindow = false;
      CHECK(noneInWindow, "no flow signal starts inside the window while paused");
      CHECK(e.s.state[50] == NB_WAIT && (e.s.reasons[50] & NB_R_NY_WINDOW) != 0, "reason inside: NY OPEN WINDOW");
      // (the flow's episode never changed, so no new signal after the window either: same rule as before)

      // the 5M realigns with the boss INSIDE the window: without the pause that is a flow signal,
      // with the pause (default) it is not - the window only knows the trap
      for(int pause = 1; pause >= 0; pause--)
      {
         Day h;
         build(h);
         for(int i = 0; i < 4; i++) bar(h, 100.2, 100.4, 99.6, 100.0);   // 16:30-16:45 bearish, no sweep
         bar(h, 99.9, 100.4, 99.6, 100.1);                                // 16:50 bullish body, 5M turns back up
         g_dir5Override.assign(52, 1);
         for(int i = 48; i < 52; i++) g_dir5Override[(size_t)i] = -1;    // 5M against the boss 16:30-16:45
         run(h, params(0.01, 2, 6), manualCfg(pause == 1), 1, 1);
         g_dir5Override.clear();
         bool fired = false;
         for(int k = 0; k < h.nSig; k++) if(h.sigs[(size_t)k].kind == NB_K_FLOW && h.sigs[(size_t)k].idx == 52) fired = true;
         if(pause == 1)
         {
            CHECK(!fired && h.s.state[52] == NB_WAIT && (h.s.reasons[52] & NB_R_NY_WINDOW) != 0, "pause ON: realignment inside the window starts NO flow signal");
         }
         else
            CHECK(fired && h.s.state[52] == NB_BUY, "pause OFF: the same realignment is a flow BUY");
      }

      // pause OFF: the flow works inside the window, and a trap still overrides it
      Day f;
      build(f);
      bar(f, 100.2, 100.5, 99.9, 100.0);    // 16:30 bearish, no sweep: 5M pulls back? dir5 fixed +1 here
      run(f, PL, manualCfg(false), 1, 1);
      CHECK(f.s.state[48] == NB_BUY && (f.s.reasons[48] & NB_R_NY_WINDOW) == 0, "pause off: flow signal continues, no NY reason");

      // after a trap resolves and the window closes, the flow starts a fresh episode
      Day g;
      build(g);
      bar(g, 100.2, 100.9, 100.0, 99.9);    // 16:30 SELL trap (entry 99.9, TP1 98.8)
      bar(g, 99.9, 100.0, 98.7, 98.8);      // 16:35 TP1
      for(int i = 0; i < 16; i++) bar(g, 99.0, 99.3, 98.9, 99.1);     // to 18:00 (bullish bodies but window)
      bar(g, 99.1, 99.4, 99.0, 99.3);       // 18:00 OUT, bullish body, aligned -> new flow BUY? needs a swing low within 60 bars
      run(g, params(0.01, 2, 6), manualCfg(true), 1, 1);
      CHECK(g.nSig == 3 && g.sigs[1].kind == NB_K_TRAP && g.sigs[1].status == NB_SIG_TP1, "trap reached TP1");
      CHECK(g.sigs[2].kind == NB_K_FLOW && g.sigs[2].idx == 66 && g.s.state[66] == NB_BUY, "18:00: flow resumes with a fresh episode");
      CHECK(g.sigs[2].swingIdx == 49 || g.sigs[2].swingIdx == 5, "flow SL from a confirmed 5M swing low");
   }
   end("S8");

   begin("S9 forming candle: a sweep that has not closed is not a trap");
   {
      Day d;
      preRange(d);
      bar(d, 100.2, 100.9, 100.0, 99.9);    // the textbook trap bar, but still forming
      run(d, P, manualCfg(), 0, 0, false);
      CHECK(d.s.state[48] == NB_WAIT && d.nSig == 0 && (d.s.reasons[48] & NB_R_CANDLE_OPEN) != 0, "forming: WAIT, candle not closed");
      run(d, P, manualCfg(), 0, 0, true);
      CHECK(d.s.state[48] == NB_SELL && d.nSig == 1, "same bar once closed: CLICK SELL - NY TRAP");
   }
   end("S9");

   //------------------------------------------------------------------
   std::vector<SBar> m5 = gen5m(7, 16 * 288, D0, 60000.0, 0.01, 40.0);
   std::vector<SBar> m15 = agg(m5, 900);
   int N5 = (int)m5.size();
   NbSessCfg SA = autoCfg(3 * 3600);

   begin("S10 full pipeline on 16 days: both signal kinds occur, restart identical, clock OFF = flow only");
   {
      Run full;
      runAt(full, m5, m15, 0, N5 - 1, D0, P, SA);
      int flow = 0, trap = 0, tb = 0, ts = 0;
      for(int k = 0; k < full.nSig; k++)
      {
         if(full.sigs[(size_t)k].kind == NB_K_TRAP) { trap++; (full.sigs[(size_t)k].dir > 0 ? tb : ts)++; }
         else flow++;
      }
      std::printf("    %d 5M bars, %d signals: %d flow, %d NY traps (%d BUY / %d SELL)\n", full.s5.n, full.nSig, flow, trap, tb, ts);
      CHECK(flow > 0 && trap > 0, "fixture exercises flow and trap");
      bool ordered = true, inWindow = true, oneSide = true;
      std::map<long long, int> perSess[2];
      for(int k = 0; k < full.nSig; k++)
      {
         const NbSignal &g = full.sigs[(size_t)k];
         if(g.dir > 0 && !(g.sl < g.entry && g.entry < g.tp1 && g.tp1 < g.tp2)) ordered = false;
         if(g.dir < 0 && !(g.sl > g.entry && g.entry > g.tp1 && g.tp1 > g.tp2)) ordered = false;
         if(g.kind == NB_K_TRAP)
         {
            if(full.s5.ph[(size_t)g.idx] != NB_PH_NY) inWindow = false;
            if(++perSess[g.dir > 0][full.s5.sid[(size_t)g.idx]] > 1) oneSide = false;
            if(g.dir < 0 && !(g.sweep > g.level && g.entry < g.level)) ordered = false;
            if(g.dir > 0 && !(g.sweep < g.level && g.entry > g.level)) ordered = false;
         }
      }
      CHECK(ordered, "every signal's levels correctly ordered; traps sit inside the range they reclaimed");
      CHECK(inWindow, "every trap is inside an NY window");
      CHECK(oneSide, "at most one trap per side per session");
      Run again;
      runAt(again, m5, m15, 0, N5 - 1, D0, P, SA);
      CHECK(again.nSig == full.nSig && again.s5.state == full.s5.state && again.s5.reasons == full.s5.reasons &&
            again.s5.ph == full.s5.ph && again.s5.swH == full.s5.swH, "restart: bit-identical");
      NbSessCfg off = SA;
      off.clockOk = false;
      Run noclk;
      runAt(noclk, m5, m15, 0, N5 - 1, D0, P, off);
      bool noNy = true;
      for(int s = 0; s < noclk.s5.n; s++)
         if(noclk.s5.ph[(size_t)s] != NB_PH_OUT || (noclk.s5.reasons[(size_t)s] & (NB_R_NY_WINDOW | NB_R_NY_NO_RANGE)) != 0) noNy = false;
      int traps = 0;
      for(int k = 0; k < noclk.nSig; k++) if(noclk.sigs[(size_t)k].kind == NB_K_TRAP) traps++;
      CHECK(noNy && traps == 0 && noclk.nSig > 0, "clock unknown: no phases, no traps, no NY reasons, flow still works");
   }
   end("S10");

   begin("S11 historical decisions never repaint (flow and trap)");
   {
      Run full;
      runAt(full, m5, m15, 0, N5 - 1, D0, P, SA);
      int cuts = 0;
      bool same = true, sameSig = true;
      for(int cut = 300; cut < N5 - 1; cut += 41)
      {
         Run p;
         runAt(p, m5, m15, 0, cut, D0, P, SA);
         cuts++;
         for(int s = 0; s <= cut; s++)
            if(p.s5.state[(size_t)s] != full.s5.state[(size_t)s] || p.s5.reasons[(size_t)s] != full.s5.reasons[(size_t)s] ||
               p.s5.ph[(size_t)s] != full.s5.ph[(size_t)s] || p.s5.rh[(size_t)s] != full.s5.rh[(size_t)s] ||
               p.s5.swH[(size_t)s] != full.s5.swH[(size_t)s] || p.s5.swL[(size_t)s] != full.s5.swL[(size_t)s])
               same = false;
         int inFull = 0;
         for(int k = 0; k < full.nSig; k++) if(full.sigs[(size_t)k].idx <= cut) inFull++;
         if(inFull != p.nSig) sameSig = false;
         for(int k = 0; k < p.nSig && sameSig; k++)
         {
            const NbSignal &a = p.sigs[(size_t)k], &b = full.sigs[(size_t)k];
            if(a.idx != b.idx || a.dir != b.dir || a.kind != b.kind || a.entry != b.entry || a.sl != b.sl ||
               a.tp1 != b.tp1 || a.level != b.level || a.sweep != b.sweep)
               sameSig = false;
            if(a.status != NB_SIG_ACTIVE && (a.status != b.status || a.statusIdx != b.statusIdx)) sameSig = false;
         }
      }
      std::printf("    compared %d cut points against the full run\n", cuts);
      CHECK(same, "every past state / reason / phase / range / sweep identical at every cut");
      CHECK(sameSig, "every past signal identical at every cut");
      std::vector<SBar> alt = m5;
      std::vector<SBar> other = gen5m(99, N5, D0, 60000.0, 0.01, 90.0);
      int cut = N5 / 2;
      double shift = alt[(size_t)cut].c - other[(size_t)cut].c;
      for(int i = cut + 1; i < N5; i++)
      {
         SBar b = other[(size_t)i];
         alt[(size_t)i] = {m5[(size_t)i].t, b.o + shift, b.h + shift, b.l + shift, b.c + shift};
      }
      Run r2;
      runAt(r2, alt, agg(alt, 900), 0, N5 - 1, D0, P, SA);
      bool past = true;
      for(int s = 0; s <= cut; s++)
         if(r2.s5.state[(size_t)s] != full.s5.state[(size_t)s] || r2.s5.reasons[(size_t)s] != full.s5.reasons[(size_t)s]) past = false;
      CHECK(past, "a different future leaves every past decision unchanged");
   }
   end("S11");

   begin("S12 market filter for this twin");
   {
      if(NB_MARKET == NB_MKT_CRYPTO)
      {
         CHECK(NbMarketLabel("BTCUSD", "BTC", "USD") == "BTC", "BTCUSD");
         CHECK(NbMarketLabel("ETHUSD.m", "ETH", "USD") == "ETH", "suffix");
         CHECK(NbMarketLabel("#SOLUSD", "", "") == "SOL", "prefix, no symbol info");
         CHECK(NbMarketLabel("ltcusd", "", "") == "LTC", "lower case");
         CHECK(NbMarketLabel("BTCUSDT", "BTC", "USDT") == "BTC", "USDT quote");
         CHECK(NbMarketLabel("XRPUSD", "XRP", "USD") == "XRP" && NbMarketLabel("DOGEUSD", "", "") == "DOGE", "XRP, DOGE");
         CHECK(NbMarketLabel("Bitcoin", "", "USD") == "BTC" && NbMarketLabel("Litecoin", "", "") == "LTC", "spelled-out aliases");
         CHECK(NbMarketLabel("BTCEUR", "BTC", "EUR") == "", "crypto in EUR rejected");
         CHECK(NbMarketLabel("EURUSD", "EUR", "USD") == "" && NbMarketLabel("XAUUSD", "XAU", "USD") == "" &&
               NbMarketLabel("US100", "USD", "USD") == "", "forex, gold, index rejected");
         CHECK(NbReasonName(NB_R_UNSUPPORTED) == "CRYPTO ONLY (BTC ETH SOL LTC ...)", "reason text");
      }
      else
      {
         CHECK(NbMarketLabel("EURUSD", "EUR", "USD") == "EURUSD", "EURUSD");
         CHECK(NbMarketLabel("USDJPY.m", "USD", "JPY") == "USDJPY", "USDJPY with suffix");
         CHECK(NbMarketLabel("#gbpjpy", "", "") == "GBPJPY", "prefix, lower case, no symbol info");
         CHECK(NbMarketLabel("AUDNZD", "AUD", "NZD") == "AUDNZD" && NbMarketLabel("USDCAD", "USD", "CAD") == "USDCAD", "crosses");
         CHECK(NbMarketLabel("XAUUSD", "XAU", "USD") == "" && NbMarketLabel("XAGUSD", "", "") == "", "metals rejected");
         CHECK(NbMarketLabel("BTCUSD", "BTC", "USD") == "" && NbMarketLabel("US100", "USD", "USD") == "", "crypto, index rejected");
         CHECK(NbMarketLabel("USDUSD", "USD", "USD") == "", "same currency twice rejected");
         CHECK(NbReasonName(NB_R_UNSUPPORTED) == "FOREX ONLY (EURUSD USDJPY ...)", "reason text");
      }
      bool named = true;
      for(int k = 0; k < NB_R_COUNT; k++) named = named && NbReasonName(NbReasonBit(k)) != "";
      CHECK(named, "every reason code has plain-English text");
      CHECK(NbReasonAt(NB_R_NY_WINDOW | NB_R_STALE, 0) == "DATA STALE / MARKET CLOSED", "staleness outranks the NY window");
      CHECK(NbReasonAt(NB_R_NY_WINDOW | NB_R_STRUCT_UNCONF, 0) == "NY OPEN WINDOW - FLOW PAUSED, WATCHING FOR SWEEP", "NY window is read before the boss's reasons");
   }
   end("S12");

   std::printf("\nSESSION ENGINE TESTS (%s): %d checks passed, %d failed\n", NB_MARKET == NB_MKT_CRYPTO ? "crypto" : "forex", g_pass, g_fail);
   return g_fail == 0 ? 0 : 1;
}
