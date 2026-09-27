# NRTR BOSS Learning Panels (MT5)

Four standalone MT5 **indicators**, one per market. Each one is a single `.mq5` file: copy,
compile with F7, drag onto the chart. None of them ever places, modifies or closes an order.

| File | Market | Extra |
|---|---|---|
| `NRTR_BOSS_LearningPanel.mq5` | Gold, Silver | the original 15M-boss / 5M-trigger panel **+ 5-question table (v1.05) + NY trap rows and lines (v1.06/v1.07)** |
| `NRTR_BOSS_Crypto_NYTrap.mq5` | BTC ETH SOL LTC XRP BNB ADA DOGE AVAX DOT LINK BCH (USD, USDT, USDC) | **+ NY-open trap module + 5-question table (v1.05)** |
| `NRTR_BOSS_Forex_NYTrap.mq5` | EURUSD USDJPY GBPUSD and every pair of USD EUR GBP JPY CHF AUD NZD CAD SGD NOK SEK DKK PLN ZAR MXN HKD CNH | **+ NY-open trap module + 5-question table (v1.05)** |
| `NRTR_BOSS_US100.mq5` (v1.11) | USTEC / US100 / NAS100 (stocks: phase 2) | **+ US session map in NY time (PDH/PDL, ONH/ONL, PMH/PML, open, OR 5/15/30, gap), news label; the NY trap is OFF** |

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
| 🟠 **EXIT / PROTECT** | You hold a position and the complete 15M boss MODE has turned against it. |

The NRTR inside is a **CUSTOM ATR-NRTR** (see *Honest limitations*); the panel says so.

**It never places, modifies or closes an order.** It reads your open positions on this
symbol only to show EXIT / PROTECT. You click, or you don't. "CLICK BUY" means *the defined
conditions are aligned for the educational setup*. It is **not** a profit signal.

Personal tool. No SignalMesh, no Telegram, no network, no DLLs, no files.

## v1.11: US100 / USTEC (new file, `NRTR_BOSS_US100.mq5`)

Built from the crypto file by `tests/make_us100.py` (every difference is declared there), so the
engine, the click guard, lots, MARKET chip, pullback watch and bridge are the same text. What is
different:

* **US SESSION MAP** (left box, where the NY trap rows were), all in **New York time**:
  * **PDH / PDL / close** of the previous **regular** session (09:30-16:00), not the broker day.
  * **ONH / ONL** (overnight 18:00-04:00) and **PMH / PML** (pre-market 04:00-09:30). They are
    shown only after their window has ended and never mix with the regular session.
  * The **09:30 open**, the opening range **OR 5 / 15 / 30** (each shown only once its window is
    complete), and the regular-session high / low so far.
  * **GAP** = open - previous close, in points, % and 15M ATR: UP / DOWN / NONE, FILLED / OPEN.
* **Session labels** (overnight, pre-market, open 0-5 / 5-15 / 15-30 min, morning, lunch, afternoon,
  final hour, after-hours, closed) are context only. They change no rule.
* The **5-question table** uses PDH / PDL, PMH / PML and the opening range (input
  `InpUsOrMinutes`, default 15) plus the 15M swings. **A level the price gapped over is never a
  sweep and never a breakout**, because nothing traded there.
* **News**: MT5's economic calendar (USD, high impact), shown as a label.
  * Its direction is always UNKNOWN.
  * An empty or unavailable calendar = UNKNOWN, never "no news".
  * It never changes a signal.
* **Clock**: every bar is converted to NY time **per bar**, through the broker server's DST rule
  (input `InpUsServerDst`, default US = the usual NY-close UTC+2/+3 broker; also EU or NONE) and
  the US DST calendar. It is never one scalar offset for the whole history.
* The NY trap module is OFF. VWAP is off (a CFD has tick volume only). Peers (NVDA, AMD, ...) and
  stocks come in phase 2.
* The starting values are the crypto file's and are **not validated for US100**. The order is
  read-only, record, shadow, test, validate.

## v1.10 crypto / forex: the same as gold / silver

The crypto and forex files now have everything below: the click guard (also for READY - NY TRAP),
the lots fix, the MARKET chip on the symbol line, the two PULLBACK WATCH rows on top of the watch
strip (shadow only, needs MT5's 1H / 4H history) and the `v1.10` label at the top right.

## v1.10: the click guard (gold / silver)

* **READY - CLICK BUY / SELL** only while the live price is within 0.5 x the signal's risk of its
  entry (`InpClickBandR`). Further away it reads **BUY / SELL SETUP - PRICE TOO FAR - WAIT FOR
  RE-ENTRY**. The ENTRY row shows the signal's age and distance, e.g.
  `bar 4/6  now 4320.00  +20.00 (0.8R)`.
* Lots for x% risk use the broker's own volume step and the larger of MT5's profit / loss tick
  value.
* No FLIP arrow on the first NRTR-ready candle. "5M AGAINST - WAIT FOR 5M RE-ALIGNMENT" replaces a
  pending line with `---`.
* The version is shown small at the top right of the left box.

## v1.09: REGIME PULLBACK WATCH (gold / silver) - shadow only

**Direction and entry location are separate.**

* **DIRECTION** = the regime: 4H NRTR + 1H NRTR + the 15M boss, all bearish (or all bullish).
* **LOCATION** = 5M. In a bearish regime, a pull-up is a **WATCH, never a BUY**. The NY strip
  shows two rows:

```
PULLBACK WATCH - SHADOW ONLY          PULL-UP 1.3 ATR in BEARISH regime - WATCH, NO BUY
1 pull 1.3 ATR   2 at 15M high 2560.27: YES      3 sweep no   4 reject YES   5 close no   6 R:R --
```

When all six checks pass, the rows read **SELL PULLBACK / RE-ENTRY CANDIDATE** with entry, SL,
target (the leg low) and R:R. The six checks are:
1. the pull distance / ATR;
2. price is at the 15M / 1H structure, or
3. it swept it;
4. a 5M rejection;
5. a bearish 5M close below the rejection;
6. an SL beyond the pull high and R:R >= 1.5.

A 5M close above the structure reads **BEARISH THESIS INVALIDATED - wait for bullish
confirmation**. Everything here is **shadow**: it never changes CLICK / WAIT, never sends
anything, and is recorded (target / SL / expired, invalidations) so ~2 days of evidence, then n
>= 20 / ~100, can judge it. It is in the bridge file as `mt5_signal.regime_pullback`
(`direction` apart from `location`) and in the Telegram message.

## v1.08: NY clock, MARKET state, data bridge (gold / silver)

* **MARKET chip** at the top of the left box: **SUPER BULLISH / TREND UP / RANGE / CHOP /
  TRANSITION / TREND DOWN / SUPER BEARISH**, from the last closed 15M bars (boss mode, 5M NRTR,
  distance from EMA200 in ATRs, NRTR flips and width over 6 h). The line under it shows the
  numbers, e.g. `6h: 0 flips  width 7.9 ATR  EMA -0.9 ATR`. **A description, never a signal**:
  it does not change CLICK / WAIT. Stale data = `MARKET ---`.
* **NY clock AUTO** (`InpNyAutoClock`, on): NY = 09:30 New York with the US daylight-saving
  calendar, converted with the broker offset that the server and PC clocks agree on. A typed
  `16:30` is an hour wrong for ~3 weeks a year (late March, late October), because the US and the
  EU switch on different Sundays. The NY rows also show the window on **your PC's clock**:
  `NY TRAP 16:30-18:00 (PC 15:30-17:00)`.
* **NY trap window** = `InpNytWindowMin` (90). In Poland summer time that is 15:30-17:00. If you
  trade later in the NY morning, set it longer (e.g. 120 = until 17:30 Poland). The default is
  unchanged.
* **Data bridge + counter-trend WATCH**: the same as crypto / forex (see section 2), plus the NY
  trap rows and the market state in the file and in the Telegram message.

## v1.07: the NY trap on the bottom-middle table (gold / silver)

The top-right corner is left free, so MT5's price scale shows the current price. The NY trap sits in
four rows **on top of the bottom-middle table**:

```
NY TRAP  16:30-18:00          PRE-NY H ....  L ....     NY H ....  L ....
SELL  <WAIT / VALID / TRIGGERED / INVALID - why>     ENTRY  SL  TP1  TP2
BUY   <WAIT / VALID / TRIGGERED / INVALID - why>     ENTRY  SL  TP1  TP2
<verdict: CLICK only WITH the 15M boss; CONFLICT - NO TRADE against it>
```

* **Chart lines (as in the crypto file):** PRE-NY HIGH / LOW (dash-dot purple; these ARE the NY
  TRAP SELL / BUY lines, and the trap state is written on them), NY HIGH / LOW (blue dotted, the
  closed NY-window bars so far), and a side's SL / TP1 / TP2 only while it is swept or in play,
  plus a solid ENTRY line once triggered.
* **NY trap rule:** the range is the 4 hours before `InpNyOpenTime`. In the 90-minute NY window, a
  wick beyond the range = VALID (swept). A **closed** 5M candle back inside, with a body in the
  trap's direction = TRIGGERED: entry = that close, SL beyond the sweep, TP1/TP2 = 1R/2R. Silver
  uses a wider stop and a stronger close back inside (the same inputs as the 5-question table).
* **The 15M boss always decides.** A trap against it = CONFLICT, NO TRADE. Boss in WAIT = NO TRADE.
* **Stale data shows no trap at all** ("---").
* `InpLadderShow = true` brings back the v1.06 DECISION LADDER box (top right: 15M -> 5M -> NY trap
  -> one action, scalp reference, open position). It is off by default because it covers the price
  scale.
* `InpSimpleView = true` hides the main panel and the table; the NY rows move to the bottom.
* **No evidence yet** for the NY trap rule on real data. Judge it after n >= 20, ~100 to decide.
  Details: [CHANGELOG.md](CHANGELOG.md).

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

**EXIT / PROTECT** (read only) is judged on the **complete 15M BOSS mode** (NRTR + EMA200 +
confirmed structure), never on the NRTR direction alone:

| You hold | 15M boss is | Position row |
|---|---|---|
| BUY | BUY MODE | **HOLD** – 15M REGIME INTACT |
| SELL | SELL MODE | **HOLD** – 15M REGIME INTACT |
| BUY | SELL MODE | **EXIT / PROTECT** (banner turns orange) |
| SELL | BUY MODE | **EXIT / PROTECT** (banner turns orange) |
| either | WAIT | **PROTECT – 15M BOSS WAIT, NOT INVALIDATED** + the boss reason. Not an automatic EXIT. |
| either | data stale / missing | **CANNOT JUDGE** |

The EXIT reason is *15M TREND INVALIDATED (BOSS FLIPPED)* if the position was opened while
the boss was in its mode, or *POSITION AGAINST 15M BOSS* if it never was. A single NRTR flip
only moves the boss to WAIT, so on its own it can never produce EXIT. Nothing is closed for you.

**Same-candle rule (frozen):** the learning signal's outcome is judged on closed 5M candles
after the entry. If one candle touches both the SL and TP1, tick order is unknown, so the
outcome is **SL**. This is deliberately conservative and is tested; it will not change quietly.

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

## v1.04 freshness fix (found live at the Asia open)

The old stale rule measured the age of the last **closed** bar, so for the first 15 minutes after
the broker's 00:00–01:00 metals break the panel said `DATA STALE` while fresh candles printed.
Freshness is now judged by witnesses: the broker's last tick is recent, the **forming** 5M and 15M
bars are current, the tick clock and the server clock agree, and the closed bars we hold are the
newest ones. Any failing witness is STALE (fail closed). A `DATA CLOCK` block on the panel shows
each witness with its age, so a STALE verdict can always be checked. Nothing in the trading rules
changed. See TESTING.md for the exact numbers.

## v1.03 (after the first MT5 screenshot)

* **Arrows only where the NRTR flips.** One big arrow on the closed candle that changed the NRTR
  direction. `Also a small arrow on every closed candle` is an input, off by default.
* **LIVE CANDLE (PREVIEW).** A yellow `▲ ?` / `▼ ?` on the forming 5M candle and a panel line:
  *IF IT CLOSED NOW: 5M NRTR FLIPS BEARISH / STAYS BULLISH*, with the exact stop price it would
  have to close beyond. It is recomputed every second from the live price, never stored, and no
  decision reads it. The real arrow and the real state arrive at the close. This is how you
  "see it before" without repainting history.
* **LIVE BOX.** BUY and SELL columns side by side: ENTRY, STOP LOSS, TP1, TP2, SWING TP, LOTS,
  and a GATE line per side (*READY - CLICK*, or the one reason it is not). Both columns come from
  the same engine function the signal uses, so the numbers can never disagree with the banner.
* Countdown in h:mm:ss, wider panel, shorter legend lines, default panel size 0.9.

## v1.02 display layer (no new decision rule, still read-only)

* **Arrow on every closed candle**: the NRTR direction of the chart's timeframe class (5M NRTR on
  M1–M5 charts, 15M NRTR above). Bright green/red = agrees with the 15M boss mode, dim = against
  it. The forming candle never gets one.
* **Blinking banner**: CLICK BUY / CLICK SELL alternates bright and dark every second. It is a
  light, not a button. MT5 does not let an indicator trade, and this one never will; you click
  Buy or Sell on the broker's own panel.
* **LOTS FOR x% RISK**: `balance × risk% ÷ money lost per lot at the SL`, rounded **down** to the
  volume step. Balance and equity are read from the account (read only). If even the minimum lot
  risks more than x%, the row says SKIP. Default 1.0 %, allowed 0.1–5.0 %. It is a suggestion you
  type yourself.
* **SWING TP**: entry ± a fixed distance per metal (default gold 20.00, silver 2.00), drawn on the
  chart and printed, so you can type a pending order or a far take-profit by hand.
* **Pending-order reference**: in BUY mode, a pullback limit near the 5M NRTR stop and a breakout
  stop above the 15M channel; mirrored in SELL mode. Reference prices only. Nothing is sent.
* **NEW YORK OPEN**: at the broker time you set (default `16:30`, check your broker's clock) one MT5
  pop-up plus sound, weekdays only, once per day. The panel counts down before it and shows
  *WAIT, LET IT PRINT* for the first 15 minutes after it. Local only, no Telegram, no network.
* **ZigZag** (blue): confirmed 15M swings joined by a line, plus a **HOW TO READ THE CHART** block
  explaining the NRTR channel, the ZigZag structure and the EMA200 filter in one line each.

## Settings

| Input | Default | |
|---|---|---|
| NRTR ATR period | 14 | |
| NRTR ATR multiplier | 2.0 | NRTR flips when a close moves this many ATRs against the trend extreme |
| EMA period | 200 | on 15M |
| Structure lookback | 3 | bars each side of a swing; a swing is confirmed only after that many bars close after it |
| SL buffer | 0.10 | × 5M ATR beyond the swing |
| TP1 / TP2 | 1.0 / 2.0 | R multiples. **TP2 must be strictly greater than TP1**, otherwise the indicator refuses to start (`invalid inputs` in the Experts log). |
| Signal valid for | 6 | closed 5M bars |
| History used | 10 | days |
| Panel size / position / X / Y | 1.0 / top-left / 12 / 24 | |
| Draw chart objects | on | |
| Candle arrows / blink | on / on | v1.02 |
| Risk per trade | 1.0 % | lot suggestion only; 0.1–5.0 accepted |
| Gold / Silver swing distance | 20.00 / 2.00 | price units |
| NY alert / NY open time / quiet minutes | on / 16:30 / 15 | broker clock |

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

* **CUSTOM ATR-NRTR.** The NRTR here is frozen as: extreme = highest (lowest) *close* since
  the flip, stop = extreme −/+ `multiplier × ATR(14, Wilder)`, ratchets only, flips on a
  *close* beyond the stop. It uses no highs/lows, no dynamic look-back period and no
  percentage band, so it is **not** guaranteed to match any MT5 CodeBase "NRTR" in direction,
  flip candle or line value. On the synthetic test data it disagrees with the classic
  percentage NRTR on 6–13 % of bars (engine test 18). Run the side-by-side described in
  TESTING.md on your own XAUUSD / XAGUSD M15 and M5 charts before comparing it to another NRTR.
* If MT5 is restarted on a *later* day, the window starts one day later, so EMA200 and NRTR
  are seeded again. In the tests the last four days were still identical bar for bar, but
  that depends on the data and is not guaranteed.
* The money row trusts your broker's `SYMBOL_TRADE_TICK_VALUE`.
* The panel uses coloured banners and the ● ▲ ▼ symbols rather than emoji, because MT5 chart
  fonts draw emoji as empty boxes.

Tests and exact results: see [TESTING.md](TESTING.md).

---

# 2. The NY-trap twins (crypto & forex)

`NRTR_BOSS_Crypto_NYTrap.mq5` and `NRTR_BOSS_Forex_NYTrap.mq5` are the **v1.04 gold panel
for other markets**, plus a session module for the New York open. Everything in section 1
is in them: CUSTOM ATR-NRTR, EXIT / PROTECT on the complete 15M boss mode, the same-candle
rule, arrows on NRTR flips (every-candle arrows as an option), the LIVE CANDLE (PREVIEW)
line and yellow marker, the two-column LIVE BOX with a GATE per side, LOTS FOR x% RISK,
SWING TP and the pending-order reference rows, the ZigZag, the blinking banner, freshness
by witnesses with the DATA CLOCK block, and the HOW TO READ lines.

Two things are new on top of the gold panel:

* **LAST 5 x 5M CLOSED / LAST 5 x 15M CLOSED**: five arrows, oldest on the left, one per
  closed candle (body direction), then the up/down count and the net move from the first
  open to the last close in price and in ATRs, e.g. `▲ ▲ ▼ ▲ ▲   4 UP / 1 DOWN   net +0.35
  (+0.9 ATR)`. Green when more candles closed up, red when more closed down. The forming
  candle is not in it; the PREVIEW line is where the forming candle lives.
* **SWING TP** distance is typed (`Swing TP distance in price`) or, when left at 0,
  automatic = `Automatic swing TP distance` x the last closed 15M ATR (default 3.0), because
  there is no fixed dollar distance that fits BTC, LTC, EURUSD and USDJPY at once.

## v1.07: data bridge to Telegram + counter-trend WATCH (crypto and forex; metals next)

* **Data bridge.** The indicator writes `Files\Common\NRTR_BRIDGE\<SYMBOL>.json`: the last 18
  closed M5 and M15 candles plus the forming candle (RAW), NRTR / ATR / EMA200 per candle
  (INDICATORS), HH/HL or LH/LL (STRUCTURE), and, **kept separate**, the MT5 CONCLUSION (boss,
  timing, CLICK / WAIT / NO TRADE, the signal's entry / SL / TP1 / TP2, NY, 5-question plan). A
  small script, [bridge/nrtr_telegram_sender.py](bridge/README.md), posts it to **your** Telegram
  chat when the conclusion changes. MT5 itself sends nothing (indicators cannot use the internet),
  and nothing places an order. Setup: [bridge/README.md](bridge/README.md).
* **COUNTER-TREND WATCH** (a strip of two rows on top of the bottom-middle table): when the 15M
  boss is in full SELL MODE and the 5M NRTR flips up on a closed candle, it records a **BUY WATCH**
  with a ref entry (that close), a ref SL (the 5M NRTR stop + buffer) and a ref TP1 (1R). The
  mirror is a SELL WATCH in BUY MODE. It is **never a signal**: no CLICK, no alert, no READY.
  Counter-trend entries are the #1 documented loss driver, so it is counted instead (n, TP1, SL,
  expired, net R) until n >= 20 / ~100 can say whether those pull-ups pay.
* Inputs: `InpBridgeOn` (true), `InpBridgeCandles` (18), `InpBridgeEverySec` (10), `InpPwShow` (true).

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

The `NY SESSION - THE WILDLIFE` block sits under the 5M rows; the LIVE BOX, pending-order
reference, position, DATA CLOCK and HOW TO READ blocks follow exactly as on the gold panel.

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
| Swing TP distance in price | 0 | 0 = automatic |
| Automatic swing TP distance | 3.0 | x last closed 15M ATR |
| Session clock | AUTO | AUTO (two witnesses + US DST) or MANUAL |
| NY open hour / minute | 16 / 30 | MANUAL only, broker server time |
| Pre-NY range: hours before the open | 4 | roughly the London morning |
| NY window: minutes after the open | 90 | the wildlife |
| Pre-NY range needs at least | 12 | closed 5M bars (1 hour); fewer = `NO RANGE` |
| Pause structure-flow signals inside the NY window | on | off = flow and trap both run; a trap still cancels the flow signal |
| MT5 pop-up + sound at the NY open | on | fires once per session at the open the session clock computes, weekdays only |

The gold panel's own inputs (risk %, data clock thresholds, arrows, preview, blink) are there
too, with the same meaning. The gold panel's `NY open time HH:MM` input does not exist in the
twins: the session clock owns the open, and the top `NEW YORK OPEN` row shows the countdown to
it, then `NY OPEN - WINDOW 0:12:30 / 90 MIN: FLOW PAUSED, TRAP ARMED`, then `NEW YORK SESSION -
h:mm:ss since the open - STRUCTURE FLOW`.

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

---

# 3. v1.05 / v1.06: the FIVE-QUESTION PLAN table (all three files)

**Gold / silver panel (v1.05 of `NRTR_BOSS_LearningPanel.mq5`) has the same table** at the bottom
middle. The code is the same text in all three files, and a test proves it. It works with pending
orders (READY = a BUY LIMIT / SELL LIMIT at the level) and scalps on 5M timing with the 15M as the
map. **Silver** gets a wider stop (SL buffer x 2.0) and a stronger confirmation (the close must pass by
+0.25 x 5M ATR), because silver false-breaks more. Both numbers are inputs and are shown on the
table. Asia / London levels appear only when the broker clock and your PC clock agree on a
half-hour offset.

**v1.06 (after the first MT5 screenshot):** MT5 cuts object text at 63 characters, so every label
now fits (tested). The table's chart markers are drawn behind the candles, so they never cover the
panels. The history row shows **NET R**. Read that row: on the first BTC screenshot it said
`TP1 8 / SL 36`, which means **no edge there, do not trade it** until a new count says otherwise.


A **new table at the bottom middle of the chart**. The main panel on the left is unchanged: a
test builds the v1.04 file from git and requires every one of its objects to be identical.
The table asks five questions on every **closed** 5M candle, using the 15M chart as the map:

| # | Question | YES means |
|---|---|---|
| 1 | **TREND** | 15M confirmed structure is HH + HL (BUY side only) or LH + LL (SELL side only). Mixed = NO TRADE. |
| 2 | **LOCATION** | price is at a mapped level: previous day high / low, Asia high / low, London high / low, or one of the last confirmed 15M swings. Not in the middle. |
| 3 | **LIQUIDITY** | the level was **swept** (pierced, then back) or **broken by a 5M close** (breakout / breakdown). |
| 4 | **CONFIRMATION** | after a sweep, a 5M candle **closes** beyond the sweep candle's high (low) with its body. A breakout close counts as its own confirmation. |
| 5 | **REWARD** | the next mapped level is at least **1.5R** away. |

All five YES = **READY**, and the table prints what to type:

```
 BTC  -  15M BULLISH                         5-QUESTION PLAN  -  15M MAP + 5M TIMING  -  PENDING ORDERS
 [            READY  -  BUY LIMIT 63120.00            ]
  1  TREND          YES  HL -> HH  = BUY SIDE ONLY           ORDER    BUY LIMIT 63120.00
  2  LOCATION       YES  AT SUPPORT 63120.00 (ASIA L)        SL       63040.00   below sweep low
  3  LIQUIDITY      YES  SWEPT TO 63050.00, BACK ABOVE       TP1      63580.00   PDH
  4  CONFIRMATION   YES  5M CLOSED ABOVE 63210.00            TP2      63900.00   SWING H
  5  REWARD         YES  TP1 = 2.10R   (NEED 1.5R)           R:R      1 : 2.10    /    1 : 3.05
                                                             LOTS 1.0%  0.05   (risks 98.00 USD)
                                                             VALID    not filled by 17:35 = cancel it
 NEXT: type BUY LIMIT 63120.00  SL 63040.00  TP 63580.00  -  not filled in time = cancel, no chasing.
 SUPPORT 63120.00 (ASIA L)  0.4 ATR below     |     RESISTANCE 63580.00 (PDH)  1.1 ATR above
 15M MAP   PDH 63580.00  PDL 62900.00   |   ASIA H 63400.00  L 63120.00   |   LONDON H 63510.00  L 63210.00
 LAST PLAN: BUY SWEEP @ 14:35   limit 63120.00  -  HIT TP1
 HISTORY (10 days): 7 plans  -  TP1 3 / SL 2 / not filled 2 / open 0     n<20 = luck, ~100 to judge
 MAIN PANEL (NRTR rules): WAIT - 5M AGAINST 15M
```

(The numbers above show the layout. They are not a real signal.)

Other banners: **SETTING UP** (swept, waiting for the confirmation close; the NEXT line names
the exact price), **WATCH** (trend yes, but price is in the middle, at support with no sweep yet,
or at the breakout line), **SKIP** (confirmed but only 0.9R to TP1, no stop structure, or no
target mapped), **FILLED** (the limit was touched; SL / TP running), **NO TRADE** (no 15M
structure, or **stale data**: when the DATA CLOCK says STALE the table is NO TRADE and the plan
lines leave the chart).

**On the chart (drawn in advance):** the nearest **RESISTANCE** (red) and **SUPPORT** (green) as
thick lines with a shaded zone that runs 6 hours past the last candle, labelled with their name
(`RESISTANCE 64200.00 (PREV DAY HIGH)`) and what they mean right now, in words:

| 15M trend | Resistance says | Support says |
|---|---|---|
| bullish | `5M close ABOVE = BREAKOUT -> possible BUY on the retest` | `sweep below + 5M close back ABOVE = possible BUY` (hover: a real BREAKDOWN = against the trend, no trade) |
| bearish | `sweep above + 5M close back BELOW = possible SELL` (hover: a real BREAKOUT = against the trend, no trade) | `5M close BELOW = BREAKDOWN -> possible SELL on the retest` |
| unclear | `15M unclear: breakout or rejection - just watch` | `15M unclear: breakdown or bounce - just watch` |

Plus a dashed **MIDDLE - NO ENTRY HERE** line, thin dotted lines for the other mapped levels,
a **BREAKOUT / BREAKDOWN** tag on the candle that closed through a level (*with 15M* or
*against 15M - no trade*), a **SWEEP** tag while a sweep waits for confirmation, the live
plan's LIMIT / SL / TP1 / TP2 lines, and a `PLAN BUY (SWEEP)` marker for every plan in the
loaded history (hover it: levels and what happened).

"In advance" means the **levels and the pending order** exist before price comes back. It
does not mean the file guesses the direction. "Possible" is always a condition you can read.

**Settings** (a new group at the bottom of the inputs):

| Input | Default | |
|---|---|---|
| Show the 5-question table | on | |
| Draw big support / resistance lines, zones and the plan | on | |
| Level zone and merge width | 0.25 | x 15M ATR |
| Sweep / breakout must be within | 12 | closed 5M bars (1 hour) |
| Minimum reward to TP1 | 1.5 | R; less = SKIP |
| Pending limit valid for | 12 | closed 5M bars; then EXPIRED |
| Asia range | 0 - 7 | UTC hours |
| London range | 7 - 12 | UTC hours |
| Table distance from the chart bottom | 16 | px |

**Honest limits:** it is a hypothesis, not a validated edge, so count the plans (n<20 is luck).
Spread is ignored when judging fills. Asia / London need the AUTO session clock and are not
shown with MANUAL / UNKNOWN. FVG, order blocks, breakers, PO3 and QML are not in it. Every
change and every test is listed in [CHANGELOG.md](CHANGELOG.md).

