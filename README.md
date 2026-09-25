# NRTR BOSS Learning Panels (MT5)

Three standalone MT5 **indicators**, one per market. Each one is a single `.mq5` file: copy,
compile with F7, drag onto the chart. None of them ever places, modifies or closes an order.

| File | Market | Extra |
|---|---|---|
| `NRTR_BOSS_LearningPanel.mq5` | Gold, Silver | the original 15M-boss / 5M-trigger panel |
| `NRTR_BOSS_Crypto_NYTrap.mq5` | BTC ETH SOL LTC XRP BNB ADA DOGE AVAX DOT LINK BCH (USD, USDT, USDC) | **+ NY-open trap module** |
| `NRTR_BOSS_Forex_NYTrap.mq5` | EURUSD USDJPY GBPUSD and every pair of USD EUR GBP JPY CHF AUD NZD CAD SGD NOK SEK DKK PLN ZAR MXN HKD CNH | **+ NY-open trap module** |

The crypto and forex files are twins: the same text except one `#define` (the market filter)
and the description lines. `tests/check_twins.py` enforces that. The NY-trap module is
documented in [its own section](#the-ny-trap-twins-crypto--forex) below the gold panel.

---

# 1. Gold / Silver panel (`NRTR_BOSS_LearningPanel.mq5`)

For **XAUUSD / Gold** and **XAGUSD / Silver** only. Open the chart and the panel answers one
question:

| Banner | Meaning |
|---|---|
| 🟢 **CLICK BUY** | Every rule for the learning BUY setup is aligned **right now**. |
| 🔴 **CLICK SELL** | Every rule for the learning SELL setup is aligned **right now**. |
| 🟡 **WAIT – NO TRADE** | Something disagrees. The reason line says exactly what. |
| 🟠 **EXIT / PROTECT** | You hold a position and the 15M boss has turned against it. |

**It never places, modifies or closes an order.** It reads your open positions on this
symbol only to show EXIT / PROTECT. You click, or you don't. "CLICK BUY" means *the defined
conditions are aligned for the educational setup*. It is **not** a profit signal.

Personal tool. No SignalMesh, no Telegram, no network, no DLLs, no files.

---

## Install

1. MT5 → **File → Open Data Folder** → `MQL5/Indicators/`
2. Copy `NRTR_BOSS_LearningPanel.mq5` there.
3. Open it in MetaEditor and press **F7** (Compile). Expect `0 errors`.
4. Open an XAUUSD or XAGUSD chart (any timeframe; 5M or 15M is easiest to read) and drag
   the indicator onto it.

On any other symbol the panel only shows **GOLD / SILVER ONLY** and calculates nothing.
Broker prefixes/suffixes are fine (`XAUUSD.m`, `#XAGUSD`, `GOLD`, `SILVER`). Metals quoted
in anything other than USD are rejected.

## The rules (fixed timeframes)

The engine always reads **15M** and **5M** itself, whatever timeframe the chart shows.
There is no setting that can switch it to 1M or 5M-only.

**15M = BOSS / DIRECTION** (on the last *closed* 15M bar)

| Mode | NRTR | Close vs EMA200 | Confirmed structure |
|---|---|---|---|
| BUY MODE | bullish | above | last high **HH** and last low **HL** |
| SELL MODE | bearish | below | last high **LH** and last low **LL** |
| WAIT | anything else, with the reason named (NRTR conflict, EMA conflict, structure against NRTR, mixed structure, structure not confirmed, not enough history) |

**5M = ENTRY TRIGGER** (only on *closed* 5M candles)

* 15M must be in BUY (or SELL) mode.
* 5M NRTR must point the same way. If it doesn't → **WAIT – 5M AGAINST 15M**.
* A 5M candle must **close** in that direction (bullish body for BUY, bearish for SELL).
  A candle that is still forming is never used.
* There must be a confirmed 5M swing low (BUY) / swing high (SELL) for the stop.

Then the panel shows **CLICK BUY / CLICK SELL** with reference levels:

* **Entry** = close of the trigger candle
* **SL** = the most recent confirmed 5M swing low (BUY) / high (SELL), plus a small buffer
  (0.10 × 5M ATR), rounded outward to the symbol's real tick size
* **TP1** = 1R, **TP2** = 2R (R = entry − SL)
* **Risk** in price, and in money per 1 lot and per minimum lot (from MT5's tick value)

One signal per setup. The CLICK state lasts 6 closed 5M candles (30 min), or until the
price reaches TP1 ("too late") or the SL ("stand aside"), whichever is first. The next
signal needs a new setup: 5M pulls back against the 15M, then turns back with it.

**EXIT / PROTECT** (read only): if you hold a BUY and the 15M NRTR turns bearish (or a SELL
and it turns bullish), the banner shows **EXIT / PROTECT** with the reason:
*15M TREND INVALIDATED* if the position was opened while the 15M agreed with it, or
*POSITION AGAINST 15M BOSS* if it never did. Nothing is closed for you.

**Stale data is never a signal.** If the last closed 5M bar is more than 15 min old (or
15M more than 30 min), for example in the daily metals break, at the weekend or on a
frozen feed, the panel shows **WAIT – DATA STALE / MARKET CLOSED**.

## Reading the panel

```
 SILVER NRTR BOSS
 XAGUSD   PRICE 30.412
 [   CLICK BUY   ]                 <- final state, big and coloured
 REASON: 15M BULLISH + HH/HL + ABOVE EMA200
         5M NRTR BULLISH + CANDLE CLOSED
 15M BOSS - DIRECTION
  15M NRTR              ● BULLISH
  NRTR UPPER / LOWER    30.455 / 30.391
  LAST 15M NRTR FLIP    BULL @ 09:45  30.402
  15M CLOSE vs EMA200   ABOVE (30.120)
  15M STRUCTURE         HL → HH
  15M DECISION          BUY MODE
 5M TRIGGER - TIMING
  5M NRTR               ● BULLISH
  5M CANDLE             CLOSED 10:35   next 03:12
  5M CONFIRM            READY - WITH 15M
 LEARNING LEVELS - NO ORDER IS SENT
  ENTRY / SL / TP1 / TP2 / RISK / RISK (money)
 POSITION - READ ONLY
  OPEN ON XAGUSD        NO POSITION
```

**On the chart:** the 15M EMA200 (blue), the 15M NRTR stop (green bullish / red bearish,
thick) with its extreme (grey dotted) forming the NRTR channel, the 5M NRTR stop (thin
dotted), confirmed **HH / HL / LH / LL** labels, one **▲ BUY / ▼ SELL** marker per signal
(hover it for its levels and what happened afterwards), a small **WAIT** where the 15M boss
drops out of a mode, and Entry / SL / TP1 / TP2 lines for the currently clickable signal
only.

## Settings

| Input | Default | |
|---|---|---|
| NRTR ATR period | 14 | |
| NRTR ATR multiplier | 2.0 | NRTR flips when a close moves this many ATRs against the trend extreme |
| EMA period | 200 | on 15M |
| Structure lookback | 3 | bars each side of a swing; a swing is confirmed only after that many bars close after it |
| SL buffer | 0.10 | × 5M ATR beyond the swing |
| TP1 / TP2 | 1.0 / 2.0 | R multiples |
| Signal valid for | 6 | closed 5M bars |
| History used | 10 | days |
| Panel size / position / X / Y | 1.0 / top-left / 12 / 24 | |
| Draw chart objects | on | |

## Why it cannot repaint

* The terminal's bar 0 (the forming candle) is never read, on 15M or on 5M.
* A 5M bar only sees the 15M bars that had **closed** when that 5M bar closed.
* A swing is used only after `Structure lookback` more bars have closed after it. The
  HH/HL label is drawn at the swing, but it **appears** that many bars later and never
  moves. That delay is the cost of not guessing. Until two highs and two lows are
  confirmed, the structure reads **NOT CONFIRMED**.
* The history window starts at a calendar day, so reopening MT5 on the same day recomputes
  exactly the same bars and shows exactly the same state.

## Honest limitations

* This NRTR is the ATR-scaled variant on closing prices. Commercial NRTR indicators differ
  in details, so flips will not match another NRTR bar for bar.
* If MT5 is restarted on a *later* day, the window starts one day later, so EMA200 and NRTR
  are seeded again. In the tests the last four days were still identical bar for bar, but
  that depends on the data and is not guaranteed.
* The money row trusts your broker's `SYMBOL_TRADE_TICK_VALUE`.
* The panel uses coloured banners and the ● ▲ ▼ symbols rather than emoji, because MT5 chart
  fonts draw emoji as empty boxes.

Tests and exact results: see [TESTING.md](TESTING.md).

---

# 2. The NY-trap twins (crypto & forex)

`NRTR_BOSS_Crypto_NYTrap.mq5` and `NRTR_BOSS_Forex_NYTrap.mq5` are the same panel as the
gold one (15M boss, 5M trigger, EXIT / PROTECT, learning levels, freshness gate), for other
markets, **plus a session module for the New York open**. Everything in section 1 about
non-repainting, freshness, the money row and the position rows applies unchanged.

## Why a separate NY module

Outside the NY open, price mostly *flows*: the 15M structure is respected and the 5M
trigger works. In the first hour or so after New York opens it does not: the market looks
bullish into the open, takes out the morning's high, and sells. The structure panel is
exactly what gets run over there, because it is built to follow the last confirmed move.

So the twins split the day in two:

| Phase | What the panel does |
|---|---|
| **OUTSIDE NY** (most of the day) | structure flow, exactly as in section 1 |
| **PRE-NY RANGE** (default: the 4 hours before the NY open) | flow continues; in the background the panel records the high and low of these closed 5M bars |
| **NY WINDOW** (default: the first 90 minutes after the open) | **flow signals are paused**. One setup only, defined below. A flow signal that was already clickable when the window opened keeps its own SL / TP / expiry. |

This is not a cheat and it is not intelligence. It is one more **rule**, written down so it
can be counted. Every trap that fires leaves a marker on the chart with what happened after
it; after a few weeks you will know whether *this* pattern has an edge on *your* symbols, and
until the count is at least 20 it is luck either way (n<20 is luck, ~100 to judge).

## The NY trap rule

Inside the NY window, with a valid pre-NY range (at least `Pre-NY range needs` closed 5M bars,
default 12):

**SELL trap** (the "everything looked bullish and then it sold" case)
1. Price trades **above the pre-NY range high** at any point since the open (a sweep).
   The highest high of the sweep is remembered.
2. A 5M candle **closes back below the range high with a bearish body**.
   That candle can be the sweep candle itself (a wick above, close below) or a later one.
3. Then: **CLICK SELL - NY TRAP**. Entry = that close, SL = the sweep high + 0.10 x 5M ATR
   (rounded outward to the tick), TP1 = 1R, TP2 = 2R. Same validity as a flow signal.

**BUY trap** is the mirror: sweep of the pre-NY range low, bullish close back above it.

One trap per side per session. A trap that fires cancels any flow signal still active. A
bearish close that is still *above* the range high is not a reclaim, and a bullish close after
a high sweep is not a SELL trap - the tests pin both. When the trap is done (TP1, SL or expiry)
the panel says so for the rest of the window and the flow resumes after the window with a fresh
episode.

The reason line tells you what the 15M boss was saying at that moment
(`... 15M WAS BUY MODE`) so you can see the trap fading the obvious.

## The session clock - a clock needs two witnesses

The NY open is 09:30 New York time, which is 13:30 UTC in US summer and 14:30 UTC in US
winter, and your broker's chart runs on the *broker's* clock. The panel never guesses that
offset from a price bar.

**AUTO** (default): it compares two independent clocks, the broker's (`TimeTradeServer`) and
your PC's (`TimeGMT`). The difference must sit on a half hour (within 5 minutes) and be a
plausible time zone. Then, **per day**, it applies the US daylight-saving calendar (second
Sunday of March to first Sunday of November). The panel prints what it uses:
`SESSION CLOCK  AUTO: SERVER = UTC+3  (US DST PER DAY)`. If the two clocks disagree it prints
`UNKNOWN - BROKER vs PC CLOCK DISAGREE, SET MANUAL` and the NY module switches itself **off**
(the flow keeps working; no trap, no pause, no guessing).

**MANUAL**: type the NY open in broker server time (`NY open hour / minute`, default 16:30,
which is what most EET/EEST brokers show for most of the year). Verify it once: look at a 5M
chart and find the candle where the NY volume arrives.

Known limitation of AUTO: the broker's offset is read *now* and applied to the whole history
window (10 days). In the one week a year when the broker's own DST switch falls inside that
window, bars before the switch are read an hour off. The current day is always right.

## Reading the extra panel rows

```
 BTC NRTR BOSS  (CRYPTO + NY TRAP)
 BTCUSD   PRICE 63412.50
 [  CLICK SELL - NY TRAP  ]                 <- purple banner = trap, green/red = flow
 REASON: NY SWEPT PRE-NY HIGH 63580.00 (to 63644.10)
         5M CLOSED BACK INSIDE - FADE THE TRAP. 15M WAS BUY MODE
 ...
 NY SESSION - THE WILDLIFE
  SESSION CLOCK         AUTO: SERVER = UTC+3  (US DST PER DAY)
  PHASE                 NY WINDOW - THE WILDLIFE  (until 18:00)
  PRE-NY RANGE          H 63580.00  /  L 63120.00   (48 bars)
  NY TRAP               SELL TRAP @ 16:45 - active
 LEARNING LEVELS - NO ORDER IS SENT
  ENTRY / SL (sweep) / TP1 / TP2 / RISK / RISK (money)
```

Other values of the **NY TRAP** row: `WATCHING - RANGE NOT SWEPT YET`, `HIGH SWEPT TO ... -
WAIT BEARISH 5M CLOSE INSIDE`, `NO RANGE - NOTHING TO SWEEP`, `ARMED AT THE NEXT NY OPEN`,
`LAST TRAP SELL - reached TP1`.

Inside the window without a trap the banner is `WAIT - NO TRADE` with the reason
`NY OPEN WINDOW - FLOW PAUSED, WATCHING FOR SWEEP` and the 5M row reads `PAUSED - NY WINDOW`.

**On the chart:** everything from section 1, plus the pre-NY range high / low of the latest
session as dashed purple segments, and purple `▼ NY TRAP SELL` / `▲ NY TRAP BUY` markers
(hover: levels, what was swept, and the outcome).

## Extra settings

| Input | Default | |
|---|---|---|
| Session clock | AUTO | AUTO (two witnesses + US DST) or MANUAL |
| NY open hour / minute | 16 / 30 | MANUAL only, broker server time |
| Pre-NY range: hours before the open | 4 | roughly the London morning |
| NY window: minutes after the open | 90 | the wildlife |
| Pre-NY range needs at least | 12 | closed 5M bars (1 hour); fewer = `NO RANGE` |
| Pause structure-flow signals inside the NY window | on | off = flow and trap both run; a trap still cancels the flow signal |

Crypto trades through the weekend, so the freshness gate rarely trips there; forex shows
`DATA STALE / MARKET CLOSED` from Friday close to Sunday open, as it should.

## Honest limitations of the twins

* The trap is a **hypothesis**, not a validated edge. It ships because it can now be counted.
  Read the markers, keep a tally per symbol, and expect the answer "no edge here" to be a
  valid result.
* A one-tick poke above the range counts as a sweep. The reclaim close is the real condition.
* TP1 / TP2 are R-multiples like the flow signals; the opposite side of the range is drawn
  but not used as a target.
* The money row trusts your broker's `SYMBOL_TRADE_TICK_VALUE`; for crypto CFDs with odd
  contract sizes check it once against the specification.
* MetaEditor was not available where this was built. Both files compile under the surrogate
  C++ build with all warnings as errors; **press F7 and send the exact message if it reports
  anything.**

Tests and exact results: see [TESTING.md](TESTING.md).
