//+------------------------------------------------------------------+
//| US100 terminal side (v1.11): the NY-time session row, the US map |
//| text, the news label and the bridge adapters. Context only:      |
//| nothing here reaches g_final, a signal, a plan or a record.      |
//+------------------------------------------------------------------+
//--- MT5's economic calendar, read at most once a minute. The result is
//    a LABEL: its direction is always UNKNOWN and no rule reads it.
void NbUsNewsRead(datetime now)
{
   if(!InpUsNews)
   {
      g_usNewsState = NB_NEWS_UNKNOWN;
      g_usNewsTxt = "UNKNOWN - CALENDAR OFF (input)";
      g_usNewsName = "";
      g_usNewsTime = 0;
      return;
   }
   if(g_usNewsAt > 0 && now >= g_usNewsAt && now - g_usNewsAt < 60)
      return;
   g_usNewsAt = now;
   g_usNewsName = "";
   g_usNewsTime = 0;
   MqlCalendarValue v[];
   if(!CalendarValueHistory(v, now - 7 * 86400, now + 7 * 86400, "US", "USD"))
   {
      g_usNewsState = NB_NEWS_UNKNOWN;
      g_usNewsTxt = "UNKNOWN - CALENDAR NOT AVAILABLE";
      return;
   }
   int n = ArraySize(v);
   int hi = 0;
   long best = -1;
   long win = (long)InpUsNewsMinutes * 60;
   string nextName = "";
   datetime nextTime = 0;
   for(int k = 0; k < n; k++)
   {
      MqlCalendarEvent e;
      if(!CalendarEventById(v[k].event_id, e))
         continue;
      if(e.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      hi++;
      long d = (long)v[k].time - (long)now;
      long ad = (d < 0) ? -d : d;
      if(ad <= win && (best < 0 || ad < best))
      {
         best = ad;
         g_usNewsName = e.name;
         g_usNewsTime = v[k].time;
      }
      if(d > win && (nextTime == 0 || v[k].time < nextTime))
      {
         nextTime = v[k].time;
         nextName = e.name;
      }
   }
   if(hi == 0)
   {
      g_usNewsState = NB_NEWS_UNKNOWN;
      g_usNewsTxt = "UNKNOWN - NO HIGH-IMPACT USD EVENT LISTED";
      return;
   }
   if(best >= 0)
   {
      g_usNewsState = NB_NEWS_WINDOW;
      g_usNewsTxt = "WINDOW: " + StringSubstr(g_usNewsName, 0, 22) + " " + TimeToString(g_usNewsTime, TIME_MINUTES) +
                    " - DIRECTION UNKNOWN";
      return;
   }
   g_usNewsState = NB_NEWS_CLEAR;
   g_usNewsTxt = "NONE +/-" + IntegerToString(InpUsNewsMinutes) + " MIN" +
                 ((nextTime > 0) ? ("  (next " + StringSubstr(nextName, 0, 18) + " " + TimeToString(nextTime, TIME_DATE | TIME_MINUTES) + ")") : "");
   g_usNewsTxt = StringSubstr(g_usNewsTxt, 0, 60);
}

string NbUsNewsStateText(int s)
{
   if(s == NB_NEWS_WINDOW)
      return "EVENT WINDOW";
   if(s == NB_NEWS_CLEAR)
      return "NO HIGH-IMPACT USD EVENT IN WINDOW";
   return "UNKNOWN";
}

string NbUsHL(double h, double l)
{
   if(h <= 0.0 || l <= 0.0)
      return "---";
   return NbPx(h) + "/" + NbPx(l);
}

//--- the NY wall clock now (live), for the session row
long NbUsEtNow()
{
   return NbUsEt(TimeTradeServer(), g_C.clockOk, g_C.usMode, g_C.usOffBase, g_C.usSrvDst, g_C.usOpenSec);
}

string NbUsSrvDstText(int r)
{
   if(r == NB_SRVDST_EU)
      return "EU";
   if(r == NB_SRVDST_NONE)
      return "NONE";
   return "US";
}

//--- the clock row: the witnesses' offset now and the server's DST rule
string NbUsClockText()
{
   if(g_S.clockMode == NB_CLK_MANUAL)
      return "MANUAL: 09:30 NY = " + IntegerToString(InpNyOpenHour, 2, '0') + ":" + IntegerToString(InpNyOpenMinute, 2, '0') + " SERVER (fixed)";
   if(!g_S.clockOk)
      return "UNKNOWN - BROKER vs PC CLOCK DISAGREE, SET MANUAL";
   long h = g_S.offset / 3600;
   string sgn = (g_S.offset >= 0) ? "+" : "-";
   return "AUTO: SERVER = UTC" + sgn + IntegerToString(MathAbs(h)) + " now, server DST " + NbUsSrvDstText(InpUsServerDst) + " (per bar)";
}

string NbUsNowText()
{
   long et = NbUsEtNow();
   if(et <= 0)
      return "UNKNOWN - SESSION CLOCK NOT PROVEN";
   int s = NbUsSessOf(et);
   string t = NbUsSessText(s) + "  (NY " + TimeToString((datetime)et, TIME_MINUTES) + ")";
   if(s == NB_US_PRE || s == NB_US_OVERNIGHT)
   {
      long mn = (et % 86400) / 60;
      long left = (mn < 9 * 60 + 30) ? (9 * 60 + 30 - mn) : (24 * 60 - mn + 9 * 60 + 30);
      t = t + "  open in " + IntegerToString((int)(left / 60)) + "h" + IntegerToString((int)(left % 60)) + "m";
   }
   return t;
}

string NbUsGapText(const NbUsBar &b)
{
   if(b.pcl <= 0.0)
      return "--- (no previous regular close yet)";
   if(b.open <= 0.0)
      return "prev close " + NbPx(b.pcl) + "  -  open not yet";
   string sg = (b.gap >= 0.0) ? "+" : "";
   string pct = DoubleToString(100.0 * b.gap / b.pcl, 2);
   string sz = sg + NbPx(b.gap) + " (" + sg + pct + "%, " + DoubleToString(MathAbs(b.gapAtr), 1) + " ATR)";
   if(b.gapDir == 0)
      return "open " + NbPx(b.open) + "  NO GAP " + sz;
   return ((b.gapDir > 0) ? "GAP UP " : "GAP DOWN ") + sz + (b.gapFilled ? "  FILLED" : "  OPEN");
}

//--- which previous levels the regular-session open jumped over (nothing traded there)
string NbUsGappedList(const NbUsBar &b)
{
   if(b.open <= 0.0 || b.pcl <= 0.0 || b.gapDir == 0)
      return "";
   string t = "";
   if(b.pdh > 0.0 && NbUsGapped(b.pcl, b.open, b.pdh))
      t = t + ((t == "") ? "" : ",") + "PDH";
   if(b.pdl > 0.0 && NbUsGapped(b.pcl, b.open, b.pdl))
      t = t + ((t == "") ? "" : ",") + "PDL";
   if(b.pmh > 0.0 && NbUsGapped(b.pcl, b.open, b.pmh))
      t = t + ((t == "") ? "" : ",") + "PMH";
   if(b.pml > 0.0 && NbUsGapped(b.pcl, b.open, b.pml))
      t = t + ((t == "") ? "" : ",") + "PML";
   return t;
}

//--- per-file bridge adapters (US100)
string NbBrSource()
{
   return "NRTR_BOSS_US100";
}

string NbBrMarket()
{
   return "US_INDEX";
}

//--- the US module lives under "ny" (the New York session): session,
//    levels, gap, news. Reference levels and context, never a signal.
string NbBrNy()
{
   if(!g_ready || g_s5.n < 1 || ArraySize(g_us) != g_s5.n)
      return "null";
   int i = g_s5.n - 1;
   NbUsBar b;
   NbUsCopy(b, g_us[i]);
   string j = "{" + NbJk("module") + "\"US SESSION MAP\"," + NbJk("not_a_signal") + "true," + NbJk("clock_ok") + (g_S.clockOk ? "true" : "false");
   if(!g_fresh)
      return j + "," + NbJk("state") + "\"SUPPRESSED - DATA STALE\"}";
   j = j + "," + NbJk("session_now") + NbJs(NbUsNowText());
   j = j + "," + NbJk("session_last_closed_bar") + NbJs(NbUsSessText(b.sess));
   j = j + "," + NbJk("ny_time_last_closed_bar") + ((b.et > 0) ? NbJs(TimeToString((datetime)b.et, TIME_DATE | TIME_MINUTES)) : "null");
   j = j + "," + NbJk("levels") + "{" + NbJk("prev_day_high") + NbJp(b.pdh) + "," + NbJk("prev_day_low") + NbJp(b.pdl) + "," + NbJk("prev_close") +
       NbJp(b.pcl) + "," + NbJk("overnight_high") + NbJp(b.onh) + "," + NbJk("overnight_low") + NbJp(b.onl) + "," + NbJk("premarket_high") + NbJp(b.pmh) +
       "," + NbJk("premarket_low") + NbJp(b.pml) + "," + NbJk("open") + NbJp(b.open) + "," + NbJk("or5_high") + NbJp(b.or5h) + "," + NbJk("or5_low") +
       NbJp(b.or5l) + "," + NbJk("or15_high") + NbJp(b.or15h) + "," + NbJk("or15_low") + NbJp(b.or15l) + "," + NbJk("or30_high") + NbJp(b.or30h) + "," +
       NbJk("or30_low") + NbJp(b.or30l) + "," + NbJk("rth_high_so_far") + NbJp(b.rthH) + "," + NbJk("rth_low_so_far") + NbJp(b.rthL) + "," +
       NbJk("vwap") + "null," + NbJk("vwap_note") + NbJs("off: an index CFD has tick volume only") + "," + NbJk("note") +
       NbJs("reference levels (battlefield), never a BUY or SELL; 0 = not known yet") + "}";
   string gd = (b.gapDir > 0) ? "\"UP\"" : ((b.gapDir < 0) ? "\"DOWN\"" : ((b.open > 0.0 && b.pcl > 0.0) ? "\"NONE\"" : "null"));
   j = j + "," + NbJk("gap") + "{" + NbJk("direction") + gd + "," + NbJk("points") + ((b.open > 0.0 && b.pcl > 0.0) ? NbJd(b.gap, g_digits) : "null") + "," +
       NbJk("atr15") + ((b.open > 0.0 && b.pcl > 0.0) ? NbJd(b.gapAtr, 2) : "null") + "," + NbJk("filled") + (b.gapFilled ? "true" : "false") + "," +
       NbJk("gapped_through") + NbJs(NbUsGappedList(b)) + "," + NbJk("rule") +
       NbJs("a level the gap jumped over is neither a sweep nor a breakout") + "}";
   j = j + "," + NbJk("news") + "{" + NbJk("state") + NbJs(NbUsNewsStateText(g_usNewsState)) + "," + NbJk("text") + NbJs(g_usNewsTxt) + "," +
       NbJk("event") + ((g_usNewsName != "") ? NbJs(g_usNewsName) : "null") + "," + NbJk("direction") + "\"UNKNOWN\"," + NbJk("rule") +
       NbJs("news is a label, never a direction; an empty calendar is UNKNOWN") + "}";
   j = j + "," + NbJk("context") + "null," + NbJk("context_rule") + NbJs("correlation is not a signal (peers: phase 2)");
   return j + "}";
}

string NbBrNyKey()
{
   if(!g_ready || g_s5.n < 1 || ArraySize(g_us) != g_s5.n)
      return "-";
   int i = g_s5.n - 1;
   return IntegerToString(g_us[i].sess) + "." + IntegerToString(g_us[i].gapDir) + "." + (g_us[i].gapFilled ? "F" : "O") + "." +
          IntegerToString(g_usNewsState);
}
