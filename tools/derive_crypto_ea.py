#!/usr/bin/env python3
"""Derive the CRYPTO twin from the METAL EA.

NRTR_QML_CryptoScalper.mq5 is NRTR_QML_MetalScalper.mq5 with (1) the asset
detector swapped for a coin-class detector (BTC / ETH / LTC / ALT), (2) a
per-class specialist profile (risk multiplier <= 1, SL-buffer and min-impulse
multipliers >= 1, a spread cap in ATR, radar on/off), (3) the spread cap
expressed as x ATR(M5) because crypto spreads are hundreds of points, and
(4) the macro filter turned into a graded BTC-LEAD filter (alts follow BTC:
a break BTC points against is blocked unless the coin's OWN structure is A+).
Everything else - the engine, the volatility regime, the spike guard, the
one-slot rule, the risk gate, the journal, the panel - is the same text.

The ENGINE block stays byte-identical apart from the detector + its defines,
and `run_tests.sh` proves it. The committed crypto files must equal this
derivation (`--check`), so a change to the metal EA is carried over by
running this script, never by hand-editing the twin.

usage: derive_crypto_ea.py            write the two files
       derive_crypto_ea.py --check    compare against the committed files
"""
import re
import sys

METAL = "NRTR_QML_MetalScalper.mq5"
CRYPTO = "NRTR_QML_CryptoScalper.mq5"
TEST_METAL = "tests/test_ea.cpp"
TEST_CRYPTO = "tests/test_ea_crypto.cpp"


def rep(text, old, new, count=1):
    n = text.count(old)
    if n != count:
        raise SystemExit(f"anchor found {n}x, expected {count}: {old[:80]!r}")
    return text.replace(old, new)


def rep_re(text, pat, new, count=1, flags=0):
    n = len(re.findall(pat, text, flags))
    if n != count:
        raise SystemExit(f"regex found {n}x, expected {count}: {pat[:80]!r}")
    return re.sub(pat, new, text, flags=flags)


HEADER = '''//+------------------------------------------------------------------+
//|                                      NRTR_QML_CryptoScalper.mq5  |
//|    BTC / ETH / LTC / ALTCOIN scalp + pending-order EA  (MT5)      |
//|                                                                  |
//|  The CRYPTO TWIN of NRTR_QML_MetalScalper.mq5: the same engine,  |
//|  the same one-slot rule, the same risk gate, the same journal,   |
//|  derived mechanically by tools/derive_crypto_ea.py. Only the     |
//|  asset side differs:                                             |
//|   * COIN CLASS: BTC, ETH, LTC or ALT (any other coin), detected   |
//|     from the symbol name or forced with InpCoinClass.            |
//|   * SPECIALIST PROFILE per class: risk multiplier (<= 1, never    |
//|     widens), SL-buffer and min-impulse multipliers (>= 1), a     |
//|     spread cap in ATR, radar on/off. Shown on the panel.         |
//|   * SPREAD CAP = x ATR(M5), not points: a BTC spread is hundreds  |
//|     of points, an altcoin's a handful - points mean nothing here. |
//|   * BTC-LEAD FILTER: the alts follow BTC. A radar break that      |
//|     BTC's M15 NRTR points against is blocked. The lead symbol is |
//|     the broker's BTC symbol, found automatically.                 |
//|   * 24/7: crypto never closes, so the session clock only shapes  |
//|     the levels (Asia / London / NY), it never stops the bot.     |
//|                                                                  |
//|  M15 = CONTEXT ONLY        (EMA200 + NRTR: shades, never gates)  |
//|   M5 = REGIME + STRUCTURE  (NRTR + confirmed HH/HL or LH/LL)     |
//|         -> BULLISH / BEARISH / CHOP-UNKNOWN                      |
//|   M1 = ENTRY TRIGGER       (NRTR realign + CLOSED candle)        |
//|         -> BUY / SELL / WAIT                                     |
//|   RISK ENGINE  -> AUTO LOT  -> MT5                               |
//|                                                                  |
//|  Supported symbols: BTC (BTCUSD / XBTUSD), ETH, LTC and any      |
//|  altcoin quoted in USD / USDT / USDC / BUSD, any broker prefix   |
//|  or suffix. A coin AUTO does not know: set InpCoinClass = ALT.   |
//|  Personal tool. No Telegram, no DLL. Network = the two optional  |
//|  SignalMesh POSTs (journal, telemetry), both off by default.     |
//+------------------------------------------------------------------+
#property copyright   "Personal use - demo trading tool"
#property version     "1.11"
#property description "BTC/ETH/LTC/altcoins: M15 context, M5 regime+structure, M1 trigger, risk engine, auto lot."
#property description "Auto scalp + QML/pullback/NY-trap/radar pending plans, coin-class specialist profile, BTC-lead filter."
#property description "The MT5 Algo Trading button is the on/off switch. Only orders with this EA magic are ever touched."
#property strict
'''

DETECTOR = '''//--- BTC / ETH / LTC / altcoins only. Broker prefixes/suffixes are fine
//    (BTCUSD.m, #ETHUSD, LTCUSDT, SOL/USD). The quote must be a dollar: USD,
//    USDT, USDC or BUSD. forced = NQ_COIN_BTC/ETH/LTC/ALT skips the name test
//    (the user vouches for the symbol with InpCoinClass); NQ_COIN_NONE = detect.
// true when the (upper-case, prefix-stripped) name starts with the ticker and a
// dollar quote or a separator follows, or the base currency IS the ticker
bool NqNameIs(string u, string b, string tk)
{
   if(b == tk)
      return true;
   if(StringFind(u, tk) != 0)
      return false;
   string rest = StringSubstr(u, StringLen(tk));
   if(rest == "" || StringFind(rest, "USD") == 0 || StringFind(rest, "BUSD") == 0)
      return true;
   ushort ch = StringGetCharacter(rest, 0);
   return !(ch >= 'A' && ch <= 'Z');
}

int NqCoinOf(string name, string base, string profitCcy, int forced)
{
   if(forced == NQ_COIN_BTC || forced == NQ_COIN_ETH || forced == NQ_COIN_LTC || forced == NQ_COIN_ALT)
      return forced;
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
   if(q != "" && q != "USD" && q != "USDT" && q != "USDC" && q != "BUSD")
      return NQ_COIN_NONE;
   if(NqNameIs(u, b, "BTC") || NqNameIs(u, b, "XBT") || StringFind(u, "BITCOIN") == 0)
      return NQ_COIN_BTC;
   if(NqNameIs(u, b, "ETH") || StringFind(u, "ETHEREUM") == 0)
      return NQ_COIN_ETH;
   if(NqNameIs(u, b, "LTC") || StringFind(u, "LITECOIN") == 0)
      return NQ_COIN_LTC;
   // altcoins: a known ticker at the start of the name (dollar quote after it) or as the base
   string alts = "XRP,SOL,ADA,DOGE,BNB,DOT,LINK,AVAX,MATIC,POL,BCH,XLM,TRX,UNI,ATOM,NEAR,ETC,SHIB,PEPE,APT,ARB,OP,SUI,TON,"
                 "FIL,AAVE,ALGO,EOS,XMR,DASH,ZEC,HBAR,ICP,VET,SAND,MANA,AXS,GRT,INJ,SEI,TIA,RNDR,RENDER,FET,KAS,WIF,BONK,"
                 "FLOKI,IMX,STX,MKR,LDO,CRV,RUNE,THETA,XTZ,NEO,QNT,KSM,EGLD,FLOW,MINA,ROSE,GALA,ENJ,CHZ,ONE,ZIL,IOTA,MIOTA,"
                 "DYDX,GMX,PENDLE,JUP,ENA,ONDO,WLD,TAO,ORDI,PYTH,JTO,STRK,BLUR,CFX,KAVA,COMP,SNX,SUSHI,YFI,1INCH,BAT,ZRX,"
                 "ANKR,STORJ,SKL,CELO,QTUM,ICX,ONT,WAVES,DGB,LRC,RVN,HNT,AR,CAKE,LUNA,LUNC,APE,BSV,XEM,NANO,OMG,ZEN,DCR,"
                 "BTT,HOT,SXP,TRB,BAND,OCEAN,NMR,AUDIO,CTSI,MASK,GLM,LPT,AGIX,WOO,JASMY,ASTR,BEAM,NEXO,TWT,OKB,CRO,LEO,KCS";
   int pos = 0;
   int n = StringLen(alts);
   while(pos < n)
   {
      int comma = StringFind(alts, ",", pos);
      if(comma < 0)
         comma = n;
      string tk = StringSubstr(alts, pos, comma - pos);
      if(tk != "" && NqNameIs(u, b, tk))
         return NQ_COIN_ALT;
      pos = comma + 1;
   }
   return NQ_COIN_NONE;
}

'''

PROFILE_FUNCS = '''
//+------------------------------------------------------------------+
//| COIN SPECIALIST PROFILE. The class decides how careful the bot is |
//| with this coin. Multipliers only ever REDUCE risk (<= 1) and only |
//| ever WIDEN buffers (>= 1); the panel shows the profile in force.   |
//+------------------------------------------------------------------+
void NqSetProfile()
{
   g_coinName = "NONE";
   g_profRisk = 1.0;
   g_profBuf = 1.0;
   g_profImp = 1.0;
   g_profSpread = 0.20;
   g_profRadar = true;
   if(g_coin == NQ_COIN_BTC)
   {
      g_coinName = "BTC";          // the lead: deepest book, tightest spread, trends cleanly
      g_profSpread = 0.15;
   }
   if(g_coin == NQ_COIN_ETH)
   {
      g_coinName = "ETH";          // higher beta than BTC: wicks run further past a level
      g_profBuf = 1.25;
      g_profSpread = 0.20;
   }
   if(g_coin == NQ_COIN_LTC)
   {
      g_coinName = "LTC";          // thinner book: wider stops, more impulse asked, less risk
      g_profRisk = 0.75;
      g_profBuf = 1.5;
      g_profImp = 1.25;
      g_profSpread = 0.25;
   }
   if(g_coin == NQ_COIN_ALT)
   {
      g_coinName = "ALT";          // anything else: half risk, widest buffers, no breakout stops
      g_profRisk = 0.5;
      g_profBuf = 1.5;
      g_profImp = 1.25;
      g_profSpread = 0.30;
      g_profRadar = false;
   }
   if(!InpSpecialist)
   {
      g_profRisk = 1.0;            // raw inputs; the ATR spread cap stays (points are meaningless here)
      g_profBuf = 1.0;
      g_profImp = 1.0;
      g_profRadar = true;
   }
}

// the lead symbol: the input when given ("-" = none), else the broker's BTC
// symbol spelled like this one (ETHUSD.m -> BTCUSD.m, #SOLUSDT -> #BTCUSDT);
// none for BTC itself. A symbol the broker does not have = no lead filter.
string NqResolveLead()
{
   if(InpMacroSymbol == "-")
      return "";
   if(InpMacroSymbol != "")
      return InpMacroSymbol;
   if(g_coin == NQ_COIN_BTC || g_coin == NQ_COIN_NONE)
      return "";
   string u = g_sym;
   StringToUpper(u);
   int len = StringLen(u);
   int a = 0;
   while(a < len)
   {
      ushort ch = StringGetCharacter(u, a);
      if(ch >= 'A' && ch <= 'Z')
         break;
      a++;
   }
   int q = StringFind(u, "USD", a);
   if(a >= len || q <= a)
      return "";
   string cand = StringSubstr(g_sym, 0, a) + "BTC" + StringSubstr(g_sym, q);
   if(cand == g_sym || !SymbolSelect(cand, true))
      return "";
   return cand;
}

// radar only: the alts follow BTC, so a break the lead's M15 NRTR points AGAINST
// is blocked (an INVERSE lead, DXY-like, blocks when it points the SAME way).
// NOT a master switch: a coin's OWN A+ structure overrides it - the radar score
// at least InpLeadOverrideScore AND its own M15 context AND its own M5 regime on
// the side of the trade. Weak setups stay blocked. The gate (spread, risk, the
// volatility regime) is applied before any order regardless.
bool NqLeadBlocks(int planDir, int score)
{
   if(!InpMacroBlocks || g_macroDir == 0 || planDir == 0)
      return false;
   bool against = InpMacroInverse ? (g_macroDir == planDir) : (g_macroDir == -planDir);
   if(!against)
      return false;
   if(InpLeadOverrideScore <= 10 && score >= InpLeadOverrideScore && g_s15.n > 0 && g_s5.n > 0 &&
      g_s15.ctx[g_s15.n - 1] == planDir && g_s5.regime[g_s5.n - 1] == planDir)
      return false;
   return true;
}

// the spread cap in points: the input when set, else x ATR(M5) (a BTC spread
// is hundreds of points and an altcoin's a handful - a fixed point cap is
// meaningless across the class, an ATR fraction is the same test for every coin)
int NqMaxSpreadPts()
{
   if(InpMaxSpreadPoints > 0)
      return InpMaxSpreadPoints;
   double frac = (InpMaxSpreadAtr > 0.0) ? InpMaxSpreadAtr : g_profSpread;
   if(!g_ready || g_s1.n < 1 || g_point <= 0.0)
      return 0;
   int k5 = g_s1.map[g_s1.n - 1];
   double atr5 = (k5 >= 0 && k5 < g_s5.n) ? g_s5.atr[k5] : 0.0;
   if(atr5 <= 0.0)
      return 0;
   int pts = (int)MathRound(frac * atr5 / g_point);
   return (pts < 1) ? 1 : pts;
}
'''


def derive_ea(m: str) -> str:
    t = m
    # 1. header
    i = t.index("#property strict\n") + len("#property strict\n")
    t = HEADER + t[i:]
    # 2. asset defines
    t = rep_re(t, r"// supported metals\n#define NQ_METAL_NONE\s+0\n#define NQ_METAL_GOLD\s+1\n#define NQ_METAL_SILVER\s+2\n",
               "// supported coin classes (the specialist profile follows the class)\n"
               "#define NQ_COIN_NONE 0\n#define NQ_COIN_BTC  1\n#define NQ_COIN_ETH  2\n#define NQ_COIN_LTC  3\n#define NQ_COIN_ALT  4\n")
    # 3. detector (inside the engine block: pure, tested)
    a = t.index("//--- Gold / Silver only. Broker prefixes/suffixes are fine")
    b = t.index("//--- text helpers")
    t = t[:a] + DETECTOR + t[b:]
    # 4. reason text
    t = rep(t, 'case NQ_R_UNSUPPORTED:     return "GOLD / SILVER ONLY";',
            'case NQ_R_UNSUPPORTED:     return "CRYPTO ONLY - BTC / ETH / LTC / ALTCOIN (set InpCoinClass)";')
    # 5. enum for the input
    t = rep(t, "enum ENUM_NQ_CORNER\n{\n   NQ_TOP_LEFT = 0,     // Top left\n   NQ_BOTTOM_LEFT = 2   // Bottom left\n};\n",
            "enum ENUM_NQ_CORNER\n{\n   NQ_TOP_LEFT = 0,     // Top left\n   NQ_BOTTOM_LEFT = 2   // Bottom left\n};\n\n"
            "enum ENUM_NQ_COIN\n{\n"
            "   NQ_COIN_AUTO_SEL = 0,   // AUTO: detect from the symbol name\n"
            "   NQ_COIN_BTC_SEL  = 1,   // BTC specialist\n"
            "   NQ_COIN_ETH_SEL  = 2,   // ETH specialist\n"
            "   NQ_COIN_LTC_SEL  = 3,   // LTC specialist\n"
            "   NQ_COIN_ALT_SEL  = 4    // ALTCOIN specialist (any other coin)\n};\n")
    # 6. inputs
    t = rep_re(t, r"(input int\s+InpHistoryDays\s+= 8;\s+// History used \(days\)\n)",
               r"\1"
               'input group "Coin specialist (BTC / ETH / LTC / ALT - the profile follows the class)"\n'
               "input ENUM_NQ_COIN   InpCoinClass        = NQ_COIN_AUTO_SEL; // Coin class: AUTO detects it; set ALT to trade a coin AUTO does not know\n"
               "input bool           InpSpecialist       = true;        // Apply the class profile (risk x, SL buffers x, min impulse x, radar on/off); false = raw inputs\n"
               "input int            InpLeadOverrideScore = 9;         // Lead against: the coin's OWN A+ structure overrides it at this radar score (M15 context + M5 regime must agree); 11 = never\n")
    t = rep_re(t, r'input string\s+InpMacroSymbol\s+= "";\s+// Macro filter symbol \(e\.g\. USDX / DXY\); empty = off\n'
                  r'input bool\s+InpMacroBlocks\s+= true;\s+// Block a radar order when the macro symbol\'s M15 NRTR points the same way\n',
               'input string         InpMacroSymbol      = "";          // BTC-lead symbol; empty = AUTO (the broker\'s BTC symbol for ETH/LTC/ALT, none for BTC); "-" = off\n'
               'input bool           InpMacroBlocks      = true;        // Block a radar order when the lead\'s M15 NRTR points AGAINST the break (alts follow BTC)\n'
               'input bool           InpMacroInverse     = false;       // The lead moves INVERSELY (e.g. DXY): block when it points the SAME way instead\n')
    t = rep_re(t, r'input int\s+InpMaxSpreadPoints\s+= 50;\s+// Max spread \(points\)\n',
               'input int            InpMaxSpreadPoints  = 0;           // Max spread (points); 0 = the ATR rule below (crypto spreads are hundreds of points)\n'
               'input double         InpMaxSpreadAtr     = 0.0;         // Max spread as x ATR(M5); 0 = the class profile (BTC 0.15, ETH 0.20, LTC 0.25, ALT 0.30)\n')
    t = rep_re(t, r'(input int\s+InpMagic\s+= )180915;', r"\g<1>180916;")
    t = rep(t, "METAL ANALYSIS page", "CRYPTO ANALYSIS page", count=t.count("METAL ANALYSIS page"))
    t = rep(t, "webhooks/metal/telemetry", "webhooks/crypto/telemetry", count=t.count("webhooks/metal/telemetry"))
    t = rep(t, "METAL ANALYSIS", "CRYPTO ANALYSIS", count=t.count("METAL ANALYSIS"))
    t = rep(t, "/webhooks/crypto/telemetry so the METAL     |", "/webhooks/crypto/telemetry so the CRYPTO    |")
    # 7. globals
    t = rep(t, "int      g_metal;\n",
            "int      g_coin;\n"
            "string   g_coinName;   // BTC / ETH / LTC / ALT\n"
            "string   g_macroSym;   // the lead symbol in force (\"\" = none)\n"
            "double   g_profRisk;   // class profile: risk multiplier (<= 1, never widens)\n"
            "double   g_profBuf;    // SL-buffer multiplier (>= 1)\n"
            "double   g_profImp;    // pullback min-impulse multiplier (>= 1)\n"
            "double   g_profSpread; // spread cap as x ATR(M5)\n"
            "bool     g_profRadar;  // radar (breakout STOP) plans allowed for this class\n")
    t = rep(t, 'string NqJsonI(string key, long val);\n',
            'string NqJsonI(string key, long val);\n'
            'void   NqSetProfile();\nstring NqResolveLead();\nint    NqMaxSpreadPts();\n')
    t = rep(t, "bool   NqMacroBlocks(int planDir, int score);\n", "bool   NqLeadBlocks(int planDir, int score);\n")
    # 8. OnInit
    t = rep(t, "InpMaxTradesPerDay < 0 || InpMaxSpreadPoints < 0 ||",
            "InpMaxTradesPerDay < 0 || InpMaxSpreadPoints < 0 || InpMaxSpreadAtr < 0.0 || InpLeadOverrideScore < 0 || InpLeadOverrideScore > 11 ||")
    t = rep(t, "   g_metal = NqMetalOf(g_sym, SymbolInfoString(g_sym, SYMBOL_CURRENCY_BASE),\n"
               "                       SymbolInfoString(g_sym, SYMBOL_CURRENCY_PROFIT));\n   NqReadSpec();\n",
            "   g_coin = NqCoinOf(g_sym, SymbolInfoString(g_sym, SYMBOL_CURRENCY_BASE),\n"
            "                     SymbolInfoString(g_sym, SYMBOL_CURRENCY_PROFIT), (int)InpCoinClass);\n"
            "   NqSetProfile();\n   g_macroSym = NqResolveLead();\n   NqReadSpec();\n")
    t = rep(t, "   g_P.qmlSlBufAtr = InpQmlSlBufAtr;\n", "   g_P.qmlSlBufAtr = InpQmlSlBufAtr * g_profBuf;      // class profile: wider, never tighter\n")
    t = rep(t, "   g_P.pbMinImpulseAtr = InpPbMinImpulseAtr;\n", "   g_P.pbMinImpulseAtr = InpPbMinImpulseAtr * g_profImp;\n")
    t = rep(t, "   g_P.pbSlBufAtr = InpPbSlBufAtr;\n", "   g_P.pbSlBufAtr = InpPbSlBufAtr * g_profBuf;\n")
    # 9. risk money
    t = rep(t, "   g_riskMoney = NqRiskMoney(g_balance, InpRiskPct);\n",
            "   g_riskMoney = NqRiskMoney(g_balance, InpRiskPct * g_profRisk);   // the class never widens risk\n")
    # 10. spread cap
    t = rep(t, "   g_gate = NqRiskGate(InpScalpAuto || InpPendingAuto, g_isDemo, InpAllowRealAccount, tradeAllowed,\n"
               "                       g_spreadPts, InpMaxSpreadPoints, dayTotal,",
            "   int maxSpr = NqMaxSpreadPts();\n"
            "   g_gate = NqRiskGate(InpScalpAuto || InpPendingAuto, g_isDemo, InpAllowRealAccount, tradeAllowed,\n"
            "                       g_spreadPts, maxSpr, dayTotal,")
    # 11. lead symbol
    t = rep(t, "// macro filter: the M15 NRTR direction of another symbol (e.g. the dollar index)\n",
            "// lead filter: the M15 NRTR direction of the lead symbol (BTC for the alts)\n")
    t = rep(t, '   g_macroDir = 0;\n   if(InpMacroSymbol == "")\n      return;\n', '   g_macroDir = 0;\n   if(g_macroSym == "")\n      return;\n')
    t = rep(t, "   if(!NqLoadSym(InpMacroSymbol, PERIOD_M15, m, why))\n", "   if(!NqLoadSym(g_macroSym, PERIOD_M15, m, why))\n")
    t = rep(t, "            // macro filter (radar only): the dollar index moving with the metal's intended break is a block\n"
               "            int rdScore = (pl.dir > 0) ? g_rdUp.score : g_rdDn.score;\n"
               "            if(isStop && NqMacroBlocks(pl.dir, rdScore))\n"
               "            {\n"
               '               g_note = "RADAR: MACRO AGAINST (" + InpMacroSymbol + " M15 NRTR " + NqDirText(g_macroDir) + ")";\n',
            "            // lead filter (radar only): the alts follow BTC - a break the lead points against is a block,\n"
            "            // unless the coin's OWN structure is A+ (radar score, M15 context and M5 regime all agree)\n"
            "            int rdScore = (pl.dir > 0) ? g_rdUp.score : g_rdDn.score;\n"
            "            if(isStop && NqLeadBlocks(pl.dir, rdScore))\n"
            "            {\n"
            '               g_note = "RADAR: LEAD AGAINST (" + g_macroSym + " M15 NRTR " + NqDirText(g_macroDir) + ") - own structure " +\n'
            '                        IntegerToString(rdScore) + "/10, needs " + IntegerToString(InpLeadOverrideScore) + " + M15 + M5";\n')
    t = rep(t, '      string mac = (InpMacroSymbol == "") ? "" : ("   macro " + InpMacroSymbol + " " + ((g_macroDir == 0) ? "n/a" : NqDirText(g_macroDir)));\n',
            '      string mac = (g_macroSym == "") ? "" : ("   lead " + g_macroSym + " " + ((g_macroDir == 0) ? "n/a" : NqDirText(g_macroDir)));\n')
    t = rep(t, "      return InpTradeRadar;\n", "      return InpTradeRadar && g_profRadar;   // the class profile can switch breakout stops off\n")
    # 12. journal + telemetry
    t = rep(t, '              NqJsonS("ea_version", NQ_EA_VERSION) + "," + NqJsonS("symbol", g_sym) + "," +\n'
               '              NqJsonS("vol_regime",',
            '              NqJsonS("ea_version", NQ_EA_VERSION) + "," + NqJsonS("symbol", g_sym) + "," +\n'
            '              NqJsonS("engine", "NQ-CRYPTO") + "," + NqJsonS("coin", g_coinName) + "," +\n'
            '              NqJsonS("vol_regime",')
    t = rep(t, '   string metal = (g_metal == NQ_METAL_GOLD) ? "GOLD" : ((g_metal == NQ_METAL_SILVER) ? "SILVER" : "NONE");\n', "")
    t = rep(t, 'NqJsonS("source", "NRTR_QML_MetalScalper")', 'NqJsonS("source", "NRTR_QML_CryptoScalper")')
    t = rep(t, 'NqJsonS("symbol", g_sym) + "," + NqJsonS("metal", metal) + "," +',
            'NqJsonS("symbol", g_sym) + "," + NqJsonS("asset_class", "crypto") + "," + NqJsonS("coin", g_coinName) + "," +')
    # 13. verdict / panel texts
    t = rep(t, 'NqSymDot() + "  GOLD / SILVER ONLY"', 'NqSymDot() + "  CRYPTO ONLY  (BTC / ETH / LTC / ALT - set InpCoinClass)"', count=2)
    t = rep(t, "   color cMetal = (g_metal == NQ_METAL_SILVER) ? NQ_RGB(200, 206, 214) : NQ_RGB(212, 175, 55);\n",
            "   color cMetal = NQ_RGB(247, 147, 26);          // BTC orange\n"
            "   if(g_coin == NQ_COIN_ETH)\n      cMetal = NQ_RGB(140, 160, 255);\n"
            "   if(g_coin == NQ_COIN_LTC)\n      cMetal = NQ_RGB(190, 198, 210);\n"
            "   if(g_coin == NQ_COIN_ALT)\n      cMetal = NQ_RGB(60, 210, 190);\n")
    t = rep(t, '   string title = "NRTR QML METAL SCALPER";\n'
               '   if(g_metal == NQ_METAL_GOLD)\n      title = "GOLD  -  NRTR QML SCALPER";\n'
               '   if(g_metal == NQ_METAL_SILVER)\n      title = "SILVER  -  NRTR QML SCALPER";\n',
            '   string title = "NRTR QML CRYPTO SCALPER";\n'
            '   if(g_coin == NQ_COIN_BTC)\n      title = "BTC  -  NRTR QML CRYPTO SCALPER";\n'
            '   if(g_coin == NQ_COIN_ETH)\n      title = "ETH  -  NRTR QML CRYPTO SCALPER";\n'
            '   if(g_coin == NQ_COIN_LTC)\n      title = "LTC  -  NRTR QML CRYPTO SCALPER";\n'
            '   if(g_coin == NQ_COIN_ALT)\n      title = "ALTCOIN  -  NRTR QML CRYPTO SCALPER";\n')
    t = rep(t, '   title = title + "   v" + NQ_EA_VERSION;', '   title = title + "   v" + NQ_EA_VERSION;')
    t = rep(t, "   int rowsTop = 8;\n", "   int rowsTop = 9;\n")
    t = rep(t, '   string volT = "---";\n',
            '   string sprT = (InpMaxSpreadPoints > 0) ? (IntegerToString(InpMaxSpreadPoints) + " pts")\n'
            '                 : (DoubleToString((InpMaxSpreadAtr > 0.0) ? InpMaxSpreadAtr : g_profSpread, 2) + " ATR");\n'
            '   string profT = g_coinName + (InpSpecialist ? "" : " (profile off)") + "   risk x" + DoubleToString(g_profRisk, 2) +\n'
            '                  "   SL buf x" + DoubleToString(g_profBuf, 2) + "   spread <= " + sprT + (g_profRadar ? "" : "   radar off") +\n'
            '                  ((g_macroSym == "") ? "   lead none" : ("   lead " + g_macroSym));\n'
            '   NqRow("e0", kx, vx, yr, "COIN PROFILE", profT, (g_coin == NQ_COIN_NONE) ? cDim : cMetal, cKey, fs);\n'
            '   yr += rh;\n'
            '   string volT = "---";\n')
    # 14. version + helper functions (after NqReadAccount's spread read block: append before NqEvaluate's doc comment)
    t = rep(t, '#define NQ_EA_VERSION "1.7.1"', '#define NQ_EA_VERSION "1.1.1"')
    t = rep(t, "// macro filter (radar only). Metals: the dollar index moving the SAME way as the\n"
               "// intended break is a block. The score is unused here; the crypto twin grades it.\n"
               "bool NqMacroBlocks(int planDir, int score)\n{\n"
               "   if(!InpMacroBlocks || g_macroDir == 0 || planDir == 0)\n      return false;\n"
               "   return g_macroDir == planDir;\n}\n\n", "")
    t = rep(t, "// account view (this EA's magic, this symbol)\n", "// account view (this EA's magic, this symbol)\n")
    t = rep(t, "\nvoid NqReadAccount()\n{\n", PROFILE_FUNCS + "\nvoid NqReadAccount()\n{\n")
    # 15. renames
    t = t.replace("g_metal", "g_coin").replace("NQ_METAL_NONE", "NQ_COIN_NONE")
    # 16. comment wording
    t = rep(t, "the metal's intended break", "the coin's intended break", count=t.count("the metal's intended break"))
    for bad in ("NQ_METAL", "NqMetalOf", "GOLD / SILVER", 'InpMacroSymbol == ""', "XAUUSD", "XAGUSD", "NqMacroBlocks"):
        if bad in t:
            raise SystemExit(f"leftover metal token in the crypto EA: {bad}")
    return t


def derive_test(s: str) -> str:
    t = s
    t = rep(t, "// Whole-EA tests: the complete NRTR_QML_MetalScalper.mq5 (translated\n",
            "// GENERATED by tools/derive_crypto_ea.py from tests/test_ea.cpp - do not edit.\n"
            "// Whole-EA tests: the complete NRTR_QML_CryptoScalper.mq5 (translated\n")
    t = rep(t, '#include "ea_full.inc"', '#include "ea_full_crypto.inc"')
    t = t.replace("XAUUSD", "BTCUSD").replace('"XAU"', '"BTC"').replace("NQ_METAL_GOLD", "NQ_COIN_BTC").replace("g_metal", "g_coin")
    # a BTC-sized synthetic market: ~0.05% per M1 bar like the real coin, so spreads and offsets are in proportion
    t = rep(t, "Market gold = makeMarket(7, 4150.0, 0.01, 0.35, (int)DAYS);", "Market gold = makeMarket(7, 61500.0, 0.01, 30.0, (int)DAYS);")
    t = rep(t, 'find("GOLD / SILVER ONLY")', 'find("CRYPTO ONLY")')
    t = rep(t, '"\\"metal\\":\\"GOLD\\""', '"\\"coin\\":\\"BTC\\""')
    t = rep(t, '"\\"source\\":\\"NRTR_QML_MetalScalper\\""', '"\\"source\\":\\"NRTR_QML_CryptoScalper\\""')
    t = rep(t, '"\\"ea_version\\":\\"1.7.1\\""', '"\\"ea_version\\":\\"1.1.1\\""')
    t = rep(t, 'CHECK(rows == 8, "8 engine rows (VOL REGIME + the 7 engine rows)");', 'CHECK(rows == 9, "9 engine rows (COIN PROFILE + VOL REGIME + the 7 engine rows)");')
    t = rep(t, "   SIM.tickValue = tickValue;\n", "   SIM.tickValue = tickValue;\n   SIM.contract = 1.0;   // crypto CFD: one coin per lot\n")
    # price offsets of the hand-made broker items, scaled from a $4,150 metal to a $61,500 coin
    # a crypto CFD: 1 lot = 1 coin, so a 0.01 tick is worth 0.01 (not 1.0 as on a 100 oz gold lot)
    t = t.replace('"BTC", 2, 0.01, 1.0)', '"BTC", 2, 0.01, 0.01)')
    t = rep(t, "NqLossAt(r.volume, slDist, 0.01, 1.0)", "NqLossAt(r.volume, slDist, 0.01, 0.01)")
    t = rep(t, "NqLossAt(r.volume, p.risk, 0.01, 1.0)", "NqLossAt(r.volume, p.risk, 0.01, 0.01)")
    # the spread guard is an ATR fraction here: $200 on a ~$70 ATR(M5) is far over the 0.15 cap
    t = rep(t, "      SIM.spreadPts = 500;\n", "      SIM.spreadPts = 20000;\n")
    t = rep(t, '"spread 500 > 50: no entries"', '"spread 20000 pts = $200, over 0.15 x ATR(M5): no entries"')
    t = rep(t, "mo.price = SIM.bid - 50;", "mo.price = SIM.bid - 5000;")
    t = rep(t, "ps.sl = SIM.bid - 5; ps.tp = SIM.bid + 5;", "ps.sl = SIM.bid - 500; ps.tp = SIM.bid + 500;")
    t = rep(t, "so.price = SIM.bid + 0.10; so.sl = SIM.bid + 6; so.tp = SIM.bid - 4;", "so.price = SIM.bid + 10.0; so.sl = SIM.bid + 600; so.tp = SIM.bid - 400;")
    t = rep(t, "Market silver = makeMarket(5, 60.9, 0.001, 0.006, (int)DAYS);", "Market silver = makeMarket(5, 112.9, 0.001, 0.05, (int)DAYS);")
    t = t.replace("XAGUSD", "LTCUSD").replace('"XAG"', '"LTC"')
    t = t.replace("silver", "ltc").replace("gold,", "btc,").replace("Market gold", "Market btc").replace("(gold)", "(btc)")
    t = rep(t, "A10 ltc spec (3 digits, tick value 5)", "A10 LTC spec (3 digits, tick value 5)")
    # crypto-only checks before the summary
    t = rep(t, '   std::printf("\\nEA TESTS: %d checks passed, %d failed\\n", g_pass, g_fail);\n', CRYPTO_CHECKS +
            '   std::printf("\\nCRYPTO EA TESTS: %d checks passed, %d failed\\n", g_pass, g_fail);\n')
    for bad in ('load(btc, "XAU', "GOLD / SILVER", "NQ_METAL", "ea_full.inc"):
        if bad in t:
            raise SystemExit(f"leftover metal token in the crypto test: {bad}")
    return t


CRYPTO_CHECKS = r'''
   begin("C1 coin detector: BTC / ETH / LTC / ALT by name or base, dollar quote only, InpCoinClass forces");
   {
      CHECK(NqCoinOf("BTCUSD", "BTC", "USD", 0) == NQ_COIN_BTC && NqCoinOf("#BTCUSD.m", "", "USD", 0) == NQ_COIN_BTC &&
            NqCoinOf("XBTUSD", "XBT", "USD", 0) == NQ_COIN_BTC && NqCoinOf("BITCOIN", "", "", 0) == NQ_COIN_BTC &&
            NqCoinOf("btcusdt", "", "USDT", 0) == NQ_COIN_BTC, "BTC spellings");
      CHECK(NqCoinOf("ETHUSD", "ETH", "USD", 0) == NQ_COIN_ETH && NqCoinOf("ETH/USD", "", "", 0) == NQ_COIN_ETH &&
            NqCoinOf("LTCUSDT", "LTC", "USDT", 0) == NQ_COIN_LTC && NqCoinOf("LITECOIN", "", "", 0) == NQ_COIN_LTC, "ETH / LTC spellings");
      CHECK(NqCoinOf("SOLUSD", "SOL", "USD", 0) == NQ_COIN_ALT && NqCoinOf("DOGEUSDT", "", "USDT", 0) == NQ_COIN_ALT &&
            NqCoinOf("#XRPUSD.c", "", "USD", 0) == NQ_COIN_ALT && NqCoinOf("ADAUSD", "ADA", "USD", 0) == NQ_COIN_ALT, "altcoins by ticker");
      CHECK(NqCoinOf("EURUSD", "EUR", "USD", 0) == NQ_COIN_NONE && NqCoinOf("XAUUSD", "XAU", "USD", 0) == NQ_COIN_NONE &&
            NqCoinOf("ETHEUR", "ETH", "EUR", 0) == NQ_COIN_NONE && NqCoinOf("ETHW", "", "", 0) == NQ_COIN_NONE &&
            NqCoinOf("AUDUSD", "AUD", "USD", 0) == NQ_COIN_NONE && NqCoinOf("FOOUSD", "FOO", "USD", 0) == NQ_COIN_NONE,
            "forex, metals, a non-dollar quote and an unknown coin are refused");
      CHECK(NqCoinOf("FOOUSD", "FOO", "USD", NQ_COIN_ALT) == NQ_COIN_ALT && NqCoinOf("ETHUSD", "ETH", "USD", NQ_COIN_LTC) == NQ_COIN_LTC &&
            NqCoinOf("EURUSD", "EUR", "USD", NQ_COIN_BTC) == NQ_COIN_BTC, "InpCoinClass forces the class (the user vouches)");
   }
   end("C1");

   begin("C2 specialist profile: the class only reduces risk and widens buffers; the panel shows it");
   {
      load(btc, "BTCUSD", "BTC", 2, 0.01, 1.0);
      startAt(START);
      run(START + 1, START + 3);
      CHECK(g_coinName == "BTC" && near(g_profRisk, 1.0) && near(g_profBuf, 1.0) && g_profRadar && near(g_profSpread, 0.15), "BTC profile");
      CHECK(near(g_riskMoney, NqRiskMoney(SIM.balance, InpRiskPct)) && near(g_P.qmlSlBufAtr, InpQmlSlBufAtr), "BTC: raw risk and buffers");
      CHECK(lbl("v_e0").find("BTC") == 0 && lbl("v_e0").find("risk x1.00") != std::string::npos && lbl("v_e0").find("spread <= 0.15 ATR") != std::string::npos,
            "COIN PROFILE row on the panel");
      OnDeinit(0);

      Market eth = makeMarket(11, 2450.0, 0.01, 1.2, (int)DAYS);
      load(eth, "ETHUSD.m", "ETH", 2, 0.01, 0.01);
      startAt(START);
      run(START + 1, START + 3);
      CHECK(g_coinName == "ETH" && near(g_profBuf, 1.25) && near(g_P.qmlSlBufAtr, InpQmlSlBufAtr * 1.25) &&
            near(g_P.pbSlBufAtr, InpPbSlBufAtr * 1.25) && near(g_profRisk, 1.0), "ETH: buffers x1.25, full risk");
      OnDeinit(0);

      Market sol = makeMarket(13, 148.0, 0.001, 0.07, (int)DAYS);
      load(sol, "SOLUSD", "SOL", 3, 0.001, 0.001);
      startAt(START);
      run(START + 1, START + 3);
      CHECK(g_coinName == "ALT" && near(g_profRisk, 0.5) && near(g_riskMoney, NqRiskMoney(SIM.balance, InpRiskPct) * 0.5), "ALT: half the risk money");
      CHECK(near(g_P.qmlSlBufAtr, InpQmlSlBufAtr * 1.5) && near(g_P.pbMinImpulseAtr, InpPbMinImpulseAtr * 1.25) && !g_profRadar,
            "ALT: buffers x1.5, impulse x1.25, radar plans off");
      NqPlan rp;
      rp.kind = NQ_PLAN_RADAR;
      rp.dir = 1;
      CHECK(!NqKindEnabled(rp), "ALT: a radar plan is not tradable");
      CHECK(lbl("v_e0").find("ALT") == 0 && lbl("v_e0").find("radar off") != std::string::npos, "panel says radar off for an altcoin");
      OnDeinit(0);
      load(btc, "BTCUSD", "BTC", 2, 0.01, 1.0);   // leave the shared market loaded for the next sections
   }
   end("C2");

   begin("C3 spread cap in ATR: a BTC spread of hundreds of points passes, one point over the cap blocks");
   {
      load(btc, "BTCUSD", "BTC", 2, 0.01, 1.0);
      SIM.spreadPts = 600;   // $6 on a $61,500 coin
      startAt(START);
      run(START + 1, START + 30);
      int cap = NqMaxSpreadPts();
      int k5 = g_s1.map[g_s1.n - 1];
      double atr5 = g_s5.atr[k5];
      CHECK(cap > 0 && near((double)cap, std::round(0.15 * atr5 / 0.01)), "the cap is 0.15 x ATR(M5) in points");
      CHECK(cap > 600 && (g_gate & NQ_K_SPREAD) == 0, "600 points is inside the cap: no spread block");
      SIM.spreadPts = cap + 1;
      stepTo(START + 31);
      CHECK((g_gate & NQ_K_SPREAD) != 0, "one point over the cap: SPREAD TOO WIDE");
      SIM.spreadPts = 20;
      OnDeinit(0);
   }
   end("C3");

   begin("C4 BTC-lead filter: the lead symbol is found from the symbol spelling; an alt break BTC points against is blocked");
   {
      Market eth = makeMarket(11, 2450.0, 0.01, 1.2, (int)DAYS);
      load(eth, "#ETHUSD.m", "ETH", 2, 0.01, 0.01);
      startAt(START);
      CHECK(g_macroSym == "", "no BTC symbol at the broker: no lead filter, nothing invented");
      OnDeinit(0);

      load(eth, "#ETHUSD.m", "ETH", 2, 0.01, 0.01);
      SIM.macro15 = toRates(btc.m15);
      startAt(START);
      run(START + 1, START + 16);
      CHECK(g_macroSym == "#BTCUSD.m", "lead = this symbol's spelling with BTC in place of ETH");
      CHECK(g_macroDir != 0, "the lead's M15 NRTR direction is read");
      int saved = g_macroDir;
      g_macroDir = -1;
      CHECK(NqLeadBlocks(1, 0) && !NqLeadBlocks(-1, 0), "lead BEARISH: a weak UP break is blocked, a DOWN break is not");
      g_macroDir = 1;
      CHECK(!NqLeadBlocks(1, 0) && NqLeadBlocks(-1, 0), "lead BULLISH: a weak DOWN break is blocked, an UP break is not");
      g_macroDir = 0;
      CHECK(!NqLeadBlocks(1, 0) && !NqLeadBlocks(-1, 0), "no lead reading: nothing is blocked");
      g_macroDir = saved;
      CHECK(lbl("v_e0").find("lead #BTCUSD.m") != std::string::npos, "panel names the lead");
      OnDeinit(0);
      SIM.macro15.clear();

      load(btc, "BTCUSD", "BTC", 2, 0.01, 1.0);
      SIM.macro15 = toRates(btc.m15);
      startAt(START);
      CHECK(g_macroSym == "", "BTC itself has no lead");
      OnDeinit(0);
      SIM.macro15.clear();
   }
   end("C4");

   begin("C5 journal: every event carries engine NQ-CRYPTO and the coin; the platform keys are unchanged");
   {
      load(btc, "BTCUSD", "BTC", 2, 0.01, 1.0);
      startAt(START);
      run(START + 1, END);
      auto it = SIM.files.find("NQ_events_BTCUSD.jsonl");
      bool have = it != SIM.files.end() && !it->second.empty();
      int missing = 0, lines = 0;
      if(have)
      {
         std::string s = it->second;
         size_t p = 0;
         while(p < s.size())
         {
            size_t e = s.find('\n', p);
            if(e == std::string::npos) e = s.size();
            std::string l = s.substr(p, e - p);
            if(!l.empty())
            {
               lines++;
               for(const char *k : {"\"engine\":\"NQ-CRYPTO\"", "\"coin\":\"BTC\"", "\"system\":\"NQ-EA\"", "\"symbol\":\"BTCUSD\"", "\"signal_id\":\"NQ:BTCUSD:"})
                  if(l.find(k) == std::string::npos) missing++;
            }
            p = e + 1;
         }
      }
      CHECK(have && lines > 0 && missing == 0, "engine + coin on every journal line, platform keys intact");
      OnDeinit(0);
   }
   end("C5");

   begin("C6 lead override: the coin's own A+ structure (score, M15 context, M5 regime) beats a lead against; a weak one does not");
   {
      Market eth = makeMarket(11, 2450.0, 0.01, 1.2, (int)DAYS);
      load(eth, "#ETHUSD.m", "ETH", 2, 0.01, 0.01);
      SIM.macro15 = toRates(btc.m15);
      startAt(START);
      run(START + 1, START + 16);
      size_t i15 = (size_t)g_s15.n - 1, i5 = (size_t)g_s5.n - 1;
      int c15 = g_s15.ctx[i15], r5 = g_s5.regime[i5], md = g_macroDir;
      g_macroDir = -1; g_s15.ctx[i15] = 1; g_s5.regime[i5] = NQ_REG_BULL;
      CHECK(NqLeadBlocks(1, 8) && !NqLeadBlocks(1, 9) && !NqLeadBlocks(1, 10), "lead BEARISH: score 8 blocked, 9+ with M15 and M5 agreeing allowed");
      g_s15.ctx[i15] = -1;
      CHECK(NqLeadBlocks(1, 10), "own M15 context against the trade: no override however high the score");
      g_s15.ctx[i15] = 1; g_s5.regime[i5] = NQ_REG_CHOP;
      CHECK(NqLeadBlocks(1, 10), "own M5 regime not on side: no override");
      g_s5.regime[i5] = NQ_REG_BULL; g_macroDir = 1;
      CHECK(!NqLeadBlocks(1, 0), "lead agrees: nothing to override");
      g_macroDir = md; g_s15.ctx[i15] = c15; g_s5.regime[i5] = r5;
      OnDeinit(0);
      SIM.macro15.clear();
   }
   end("C6");
'''


def engine_core(text: str, metal: bool) -> str:
    a, b = text.index("//=== NB_ENGINE_BEGIN ==="), text.index("//=== NB_ENGINE_END ===")
    core = text[a:b]
    if metal:
        core = re.sub(r"// supported metals\n(#define NQ_METAL_\w+\s+\d\n)+", "", core)
        i, j = core.index("//--- Gold / Silver only."), core.index("//--- text helpers")
    else:
        core = re.sub(r"// supported coin classes[^\n]*\n(#define NQ_COIN_\w+\s+\d\n)+", "", core)
        i, j = core.index("//--- BTC / ETH / LTC / altcoins only."), core.index("//--- text helpers")
    core = core[:i] + core[j:]
    # the one engine string that names the asset class
    return re.sub(r'case NQ_R_UNSUPPORTED:\s+return "[^"]*";', 'case NQ_R_UNSUPPORTED: return "<asset>";', core)


def main() -> int:
    metal = open(METAL, encoding="ascii").read()
    test = open(TEST_METAL, encoding="ascii").read()
    ea = derive_ea(metal)
    tst = derive_test(test)
    ea.encode("ascii")
    tst.encode("ascii")
    if engine_core(metal, True) != engine_core(ea, False):
        raise SystemExit("ENGINE DRIFT: the crypto engine block differs beyond the asset detector")
    if "--check" in sys.argv:
        ok = True
        for path, want in ((CRYPTO, ea), (TEST_CRYPTO, tst)):
            try:
                have = open(path, encoding="ascii").read()
            except OSError:
                have = None
            if have != want:
                ok = False
                print(f"DRIFT: {path} is not the derivation of its metal twin - run tools/derive_crypto_ea.py")
        print("crypto twin: derived files match, engine block identical apart from the asset detector" if ok else "crypto twin: DRIFT")
        return 0 if ok else 1
    open(CRYPTO, "w", encoding="ascii").write(ea)
    open(TEST_CRYPTO, "w", encoding="ascii").write(tst)
    print(f"wrote {CRYPTO} ({ea.count(chr(10))} lines) and {TEST_CRYPTO}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
