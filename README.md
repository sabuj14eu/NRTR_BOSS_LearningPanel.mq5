# NRTR BOSS Learning Panel (MT5, Gold & Silver)

One standalone MT5 **indicator**, `NRTR_BOSS_LearningPanel.mq5`, for **XAUUSD / Gold** and
**XAGUSD / Silver** only. Open the chart and the panel answers one question:

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
