   // US SESSION MAP (v1.11 US100): reference levels and context, NY time -
   // never a BUY / SELL. Stale data = nothing shown as live (Freshness Law).
   NbLabel("hny", ox + kx, y + (int)MathRound(3 * sc), "US SESSION MAP  -  NY TIME, LEVELS = REFERENCE ONLY", cNy, fsH, "Arial Black", ANCHOR_LEFT_UPPER);
   y += rh + (int)MathRound(3 * sc);
   NbRow("kn1", "vn1", ox + kx, ox + vx, y, "SESSION CLOCK", NbUsClockText(), g_S.clockOk ? cVal : cWait, cKey, fs);
   y += rh;
   string u2 = "---";
   string u3 = "---";
   string u4 = "---";
   string u5 = "---";
   string u6 = "---";
   string u7 = "---";
   color u4c = cVal;
   bool uok = (ok && ArraySize(g_us) == g_s5.n && g_us[i5].et > 0);
   if(ok && !g_fresh)
      u2 = "DATA STALE - NOT SHOWN AS LIVE";
   else if(ok && !uok)
      u2 = "NY CLOCK UNKNOWN - NO US LEVELS (never guessed)";
   else if(uok)
   {
      NbUsBar ub;
      NbUsCopy(ub, g_us[i5]);
      u2 = (ub.pdh > 0.0) ? ("H " + NbPx(ub.pdh) + "  L " + NbPx(ub.pdl) + "  CLOSE " + NbPx(ub.pcl)) : "NOT KNOWN YET (needs one full session)";
      u3 = "ONH/ONL " + NbUsHL(ub.onh, ub.onl) + "  PMH/PML " + NbUsHL(ub.pmh, ub.pml);
      u4 = NbUsGapText(ub);
      u4c = (ub.gapDir != 0 && !ub.gapFilled) ? cWait : cVal;
      u5 = "5m " + NbUsHL(ub.or5h, ub.or5l) + "  15m " + NbUsHL(ub.or15h, ub.or15l);
      u6 = "30m " + NbUsHL(ub.or30h, ub.or30l) + "   (map uses " + IntegerToString(InpUsOrMinutes) + "m)";
      u7 = (ub.rthH > 0.0) ? ("H " + NbPx(ub.rthH) + "  L " + NbPx(ub.rthL) + "  (so far)") : "NOT OPEN YET";
   }
   NbRow("kn2", "vn2", ox + kx, ox + vx, y, "PREV DAY (09:30-16:00)", u2, cVal, cKey, fs);
   y += rh;
   NbRow("kn3", "vn3", ox + kx, ox + vx, y, "ONH/ONL  PMH/PML", u3, cVal, cKey, fs);
   y += rh;
   NbRow("kn4", "vn4", ox + kx, ox + vx, y, "OPEN / GAP", u4, u4c, cKey, fs);
   y += rh;
   NbRow("kn5", "vn5", ox + kx, ox + vx, y, "OPENING RANGE H/L", u5, cVal, cKey, fs);
   y += rh;
   NbRow("kn6", "vn6", ox + kx, ox + vx, y, " ", u6, cVal, cKey, fs);
   y += rh;
   NbRow("kn7", "vn7", ox + kx, ox + vx, y, "REGULAR SESSION", u7, cVal, cKey, fs);
   y += rh;
   NbRow("kn8", "vn8", ox + kx, ox + vx, y, "NEWS (DIR. UNKNOWN)", ok ? g_usNewsTxt : "---",
         (g_usNewsState == NB_NEWS_WINDOW) ? cWait : ((g_usNewsState == NB_NEWS_UNKNOWN) ? cDim : cVal), cKey, fs);
   y += rh;
