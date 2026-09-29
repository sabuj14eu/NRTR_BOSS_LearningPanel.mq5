# NRTR QML Metal Scalper (MT5, Gold & Silver)

One standalone Expert Advisor, `NRTR_QML_MetalScalper.mq5`, for **XAUUSD / Gold** and
**XAGUSD / Silver** only. Nothing else. No SignalMesh, no Telegram, no network, no DLLs, no
files. It replaces the earlier learning-panel indicator (removed from this repository; git
history keeps it). **Remove the old indicator from your chart.**

```
M15 context -> M5 regime + structure -> M1 trigger -> risk engine -> auto lot -> MT5
```

The bot has full power over six setups and **one slot per asset**: M5 **QML**, M5
**pullback**, **NY trap**, M15 **swing QML / pullback** (limit orders), the **IMPULSE RADAR**
(stop orders beyond the nearest level, armed only when measured pressure is high) and the M1
**scalp** (market order, lowest priority). Every armed plan waits at the broker; **the first
fill takes the slot**, every other waiting order is cancelled at once, and nothing new is
opened until the position closes. One position, buy or sell, never both. The **NY TRAP +
PENDING ORDER BOARD** on the panel shows every plan, every real broker order and position,
the TP actually sent, the distance to each level and the live status, refreshed every second.

Decisions on **CLOSED candles only**, never repainted. Tests and exact results are in
[TESTING.md](TESTING.md).

---

## Install

1. MT5 → **File → Open Data Folder** → `MQL5/Experts/`. Copy `NRTR_QML_MetalScalper.mq5` there.
2. MetaEditor → open → **F7**. Expect `0 errors`.
3. Open an **XAUUSD M1** or **XAGUSD M1** chart (M5 or M15 also work; arrows are drawn only on
   M1/M5/M15 charts). Drag the EA on. Tick **Allow Algo Trading** in the dialog and the
   **Algo Trading** button in the toolbar.
4. The **Algo Trading** button in the toolbar is the on/off switch. Green = the bot trades
   (real or demo); off = watch only.

On any other symbol the panel shows **GOLD / SILVER ONLY** and does nothing.

---

## The pipeline

```
M15  CONTEXT ONLY          EMA200 + NRTR  ->  BULLISH / BEARISH / NEUTRAL
                           (shades the panel, feeds the forecast, never gates)
M5   REGIME + STRUCTURE    NRTR + confirmed swings (HH/HL or LH/LL)
                           ->  BULLISH / BEARISH / CHOP-UNKNOWN (reason named)
M1   ENTRY TRIGGER         M1 NRTR realigns with the M5 regime, first CLOSED candle
                           with a body in that direction on the right side of EMA20
                           ->  BUY / SELL / WAIT (reason named)
RISK ENGINE                demo guard, autotrading, spread, daily loss cap, max open,
                           max trades/day, session, broker stops level, margin
AUTO LOT                   risk% of balance  /  loss per lot at the SL, floored to the
                           volume step. If even the minimum lot risks more: NO TRADE.
MT5 DEMO                   one audited OrderSend path; every order printed with its reason
```

Every "why not" is shown as text: `REASON:` under the banner, `M5 REGIME (…)`,
`M1 TRIGGER WAIT (…)`, `GATE …`.

---

## 1. Auto scalp (market order on the M1 trigger, lowest priority)

The scalp only fires when the slot is free **and no plan order is waiting at the broker**;
structure plans come first. The board's `SCALP M1` row is **always visible** with the levels a
scalp would use right now (side from the M5 regime, live entry, SL, TP, lot) and either
`TRIGGER NOW` or the exact `WAIT:` reason, so you can take it by hand at any time. This is the
trade in the picture (4155.59 → 4152.12 = +3.47 and so on): a small move in
the direction of the 5-minute regime, taken and closed within minutes.

| | Rule | Default |
|---|---|---|
| Entry | market, on the close of the trigger candle | |
| SL | `1.5 × ATR14(M5)` beyond the entry | validated stop from the system's own evidence |
| TP | `1.0 × ATR14(M5)` | the validated small-R ladder |
| Time stop | close if neither is hit after N M1 bars | 45 |
| Regime flip | close if the M5 regime turns against the scalp | on |
| One at a time | a second scalp is never opened while one is running | |
| One per episode | after a trigger fires, the next needs M1 to pull back against the regime and realign | |

**Worked example, gold at 4154 with ATR14(M5) = 3.50** (typical for today's gold; the panel
shows the live value):

```
SELL trigger at 4155.60
SL  = 4155.60 + 1.5 × 3.50 = 4160.85
TP  = 4155.60 - 1.0 × 3.50 = 4152.10        <- the +3.5 scalp from the picture
risk 0.5% of 10 000 = 50 USD; loss per lot at SL = 5.25 / 0.01 × 1.00 = 525 USD
lot = 50 / 525 = 0.095 -> 0.09 lots (floored, never rounded up)
```

**Silver at 60.89 with ATR14(M5) = 0.060**, tick 0.001 worth 5 USD per lot:

```
BUY trigger at 60.890   SL 60.800   TP 60.950
loss per lot at SL = 0.090 / 0.001 × 5 = 450 USD   ->  lot = 50 / 450 = 0.11
```

The RR of a scalp is 0.67 by design (high win rate, small R). The panel's `RECORD` row shows
how many scalps in the loaded history reached TP, hit SL or timed out, with the evidence
label (`n<20 = luck`, `n<100 = early`).

## 2. Pending order plans (set it and go to work)

Five plans, one slot. Each is a limit order with SL and TP computed from structure; the EA
places and cancels them (`InpPendingAuto`, default on), or you type the board's line in
yourself.

### QML (Quasimodo) reversal, on M5 and on M15 (swing)

```
bearish:  swing high A (left shoulder)  ->  swing low B (neck)  ->  higher high C (head)
          ->  a CLOSE below B
          SELL LIMIT at A     SL = C + 0.2 x ATR     TP1 = 1R     TP2 = 2R
bullish:  the mirror image  ->  BUY LIMIT at the left-shoulder low, SL below the head
```

Swings are confirmed only after `Structure lookback` (3) more bars have closed. The plan
appears at the close that breaks the neck and is keyed by the head's time, so a restart finds
the same plan and the same order. The board shows HEAD / NECK / BREAK close so you can see why
the order is there.

### Pullback in the regime, on M5 and on M15 (swing)

```
BULLISH regime and a new HH just confirmed, leg HL -> HH at least 2 x ATR long:
   BUY LIMIT at HL + 50% x (HH - HL)     SL = HL - 0.2 x ATR     TP1 = 1R   TP2 = 2R
BEARISH: mirror (SELL LIMIT at the 50% retrace of LH -> LL)
```

### NY trap (state machine, never a direction guess)

```
NO NY  ->  RANGE BUILDING  ->  SWEPT  ->  RETURNED INSIDE  ->  TRAP CONFIRMED  ->  plan
```

* Pre-NY range = high/low from `InpRangeStartHour` (00:00) to the NY open
  (`16:30` server, which is 09:30 New York all year on an EET broker; change the inputs
  for another broker clock).
* Inside NY, an M5 bar's high above the pre-NY high is a **sweep** (bull-trap candidate).
  A later M5 **close** back below that high is the **return**. Only when the M5 NRTR is
  **bearish** is the trap **confirmed**: `SELL LIMIT` at the swept high, SL beyond the sweep
  extreme + 0.2 ATR, TP1 = 1R, TP2 = 2R. The bear trap is the mirror.
* The sweep alone never decides anything. One trap per side per session; an unfilled plan
  expires when the session ends. Both sides are shown on the board with their state.

### Lifetime and the slot

* M5 plans live 72 M5 bars (6 h), swing plans 96 M15 bars (24 h), NY plans until the
  session ends. A newer setup of the same kind and side **replaces** the older one; a
  pullback plan is cancelled when its regime turns.
* An unfilled limit sits between the price and its own stop, so the price cannot close past
  the stop without filling it. That is a fact about limit orders, not a choice.
* **One slot per asset.** While any position of this EA is open on the symbol, every waiting
  order is cancelled and nothing is opened. If two limits fill inside the same minute, the
  first keeps the slot and the second is closed immediately. Each kind can be switched off
  (`InpTradeQml`, `InpTradePullback`, `InpTradeNyTrap`, `InpTradeSwing`).
* Filled orders are managed by their SL/TP only. `InpPlanUseTp2` sends TP2 instead of TP1;
  the board's **TP SENT** column always shows the TP that actually went to MT5.

## 3. IMPULSE RADAR (breakout / breakdown BEFORE the break, STOP orders)

The pullback plans wait for a retracement that a one-way day may never give. The radar asks
the other question: *is pressure building against the nearest level, and where is the trigger
just beyond it?* It runs on closed M5 bars, for both directions at once, and scores measured
conditions out of 10. No percentage is invented.

| Component | Points | Measured how |
|---|---|---|
| Structure | 0-2 | M5 regime agrees (NRTR + HH/HL or LH/LL) = 2; last swing label alone (HH / LL) = 1 |
| Compression | 0-2 | mean range of the last 4 bars ≤ 0.8 × the 12 before (+1); ≥ 2 tests of the level within 0.3 ATR without closing through it (+1) |
| Proximity | 0-2 | close within 0.5 ATR of the level (2) / within 1 ATR (1) |
| Candle efficiency | 0-2 | mean signed body ÷ range of the last 4 bars ≥ 0.6 (2) / ≥ 0.4 (1); wicks count against |
| Momentum persistence | 0-1 | three closes in a row in the direction (▲▲▲, not ▲▼▲) |
| M15 boss | 0-1 | M15 context agrees |

The **level** is the nearest of: previous-day high/low, Asia / London / pre-NY / NY highs and
lows once their session has ended, and the nearest confirmed M5 swing. States: `NO LEVEL`,
`FAR` (> 2 ATR), `BUILDING` (< 5), `NEAR` (≤ 1 ATR, 5-6), **`READY`** (≥ 7 within 1 ATR).

`READY` arms the plan: **BUY STOP at level + 0.15 ATR** (SELL STOP mirrored), SL below the
last confirmed swing on the other side (else 1.5 ATR), TP1 = 1R, TP2 = 2R. If the price never
breaks, nothing happens. Unfilled plans end when the pressure fails (score < 5 while the level
is still the target), when the price crawls through the level without reaching the stop, on
expiry, or when a newer level replaces them.

**False-break filter.** A fill whose M5 bar, or the next one, **closes back through the
level** is closed at once (`FALSE BREAK`), whatever the SL says. The record counts it as a
loss.

**Macro filter (optional).** Set `InpMacroSymbol` to your broker's dollar-index symbol
(`USDX`, `DXY`, ...). The board shows its M15 NRTR direction, and with `InpMacroBlocks` a
radar order is not placed while the index moves the same way as the metal's intended break
(gold up + DXY up = blocked; gold up + DXY down = allowed). Empty = no macro filter.

The board shows two `RADAR` lines (level, distance, score with its six components, state) and
two plan rows `RADAR UP` / `RADAR DOWN` with the armed stop order and its live status. The
scalp remains the lowest priority; the radar is one more limit/stop plan inside the one-slot
rule.

## 4. Session levels, breakouts, VWAP (to read the day)

Drawn on the chart and summarised on the board's `LEVELS` and `BREAK` lines, for the current
server day:

| Level | Window (server, EET broker defaults) | Line |
|---|---|---|
| PD HIGH / LOW | previous day's range | gold, active all day |
| ASIA HIGH / LOW | 01:00-10:00 | teal |
| LONDON HIGH / LOW | 10:00-NY open | blue |
| PRE-NY HIGH / LOW | 00:00-NY open | grey |
| NY HIGH / LOW | 16:30-23:00 | purple |
| VWAP | from 00:00, typical price x tick volume | yellow polyline + label |

A level is **dotted while its session is still building** and **solid once the session has
ended** (only then can it be broken). A **BREAKOUT** mark is printed at the first M5 **close**
above an active high; a **BREAKDOWN** at the first close below an active low; once per level
per day. The `BREAK` line names the latest one with its time, the `LEVELS` line lists the
prices (`*` = still building) and whether the price is above or below VWAP. These are for
reading the day; they do not open trades by themselves.

## 5. Forecast arrow on every candle

Every candle carries an arrow with the forecast for the **next** candle, made at this
candle's close:

```
score = 2 × higher-TF vote  +  own NRTR direction  +  close vs EMA20  +  this candle's body
arrow UP if score >= 2, DOWN if <= -2, none if the votes split
```

* On an M1 chart the higher vote is the M5 regime; on M5 it is the M15 context; on M15
  there is none.
* When the votes split, the tie is broken by the candle's own NRTR, then its body, then the
  previous arrow, so **every candle carries an arrow**. The panel says `tie-break` when that
  happened; a tie-break arrow is weaker than a full-score one and is counted in the same
  hit rate.
* **The big white arrow with the `NEXT` label on the forming candle = the live forecast.**
  It is made at the previous close and does not move until the candle closes.
* When the candle closes, its arrow turns **green (hit)** or **red (miss)**: hit = the close
  went the forecast way; an unchanged close counts as a miss.
* `NEXT M1 FORECAST` and `FORECAST HIT RATE` on the panel show the live arrow and the
  measured accuracy over the loaded history with its evidence label. **It is a forecast:
  judge it by the hit rate, never by one arrow.** Its expected accuracy is modest; it does
  not open trades on its own and it does not override the trigger.

## The panel: engine table + NY TRAP / PENDING ORDER BOARD

```
 GOLD  -  NRTR QML SCALPER
 XAUUSD   4153.90 / 4154.15   DEMO   M1 closes in 00:31
 [ ●  WAIT - NO TRADE ]                                  <- banner: trigger + gate
 REASON: M1 AGAINST M5 REGIME
 ENGINE  M15 -> M5 -> M1
  M15 CONTEXT       BULLISH  (NRTR BULLISH, above EMA200 4120.5)
  M5 REGIME         BULLISH  (NRTR stop 4149.20)
  M5 STRUCTURE      HL -> HH
  M5 ATR14          3.20   scalp SL 4.80  TP 3.20
  M1 TRIGGER        WAIT  (M1 NRTR BEARISH; M1 AGAINST M5 REGIME)
  NEXT M1 BIAS      ▲ UP  (score +2)
  BIAS HIT RATE     53.8%  (612 of 1138, n>=100)
 NY TRAP  +  PENDING ORDER BOARD   (live, refreshes every second)
  NY SESSION  16:30-23:00 server   INSIDE, 2h18m left   NY range 4264.8 - 4291.3
  PRE-NY RANGE  high 4291.30   low 4264.80   (00:00 - 16:30)
  SWEEP / TRAP  HIGH side TRAP CONFIRMED 4296.50 (close back 4288.90)   |   LOW side RANGE BUILDING
  SLOT  FREE  3 armed, 2 waiting - the first fill takes it
  LEVELS  PD 4170.10/4120.50  ASIA 4145.20/4130.00  LON 4161.30/4128.40  VWAP 4150.20 (above)
  BREAK  BREAKOUT above LONDON HIGH 4161.30 @15:10   before: breakdown ASIA LOW @09:40
  RADAR ▲  4161.29  dist 0.30 ATR  score 8/10 HIGH  (struct 2 compr 2 prox 2 eff 1 mom 1 m15 0)  READY
  RADAR ▼  4113.49  dist 8.70 ATR  score 3/10 LOW   (struct 0 compr 1 prox 0 eff 1 mom 1 m15 0)  FAR   macro USDX BEARISH
  TYPE         SIDE      ENTRY     SL        TP SENT   DIST       STATUS
  QML M5       SELL LMT  4285.20   4297.80   4272.60   0.42 ATR   PLACED  #1234   exp 4h10m
               head 4302.10   neck 4288.40   break close 4286.90 at 15:05   R 12.60   TP1 4272.60  TP2 4260.00   (sends TP1)
  PULLBACK M5  BUY LMT   4268.50   4258.20   4278.80   1.10 ATR   NEAR  #1235   exp 5h55m
               leg 4246.10 -> 4290.90   50% retrace at 14:35   ...
  NY TRAP      SELL LMT  4291.30   4298.00   4284.60   0.20 ATR   WAITING (placed at the next M1 close)   exp 2h18m
               pre-NY level 4291.30 swept to 4296.50   confirmed at 15:10   R 6.70   TP2 4277.90
  SWING QML    -         -         -         -         -          no setup yet
  SWING PB     BUY LMT   4230.00   4212.00   4248.00   7.5 ATR    ARMED - SWING off
  RADAR UP     BUY STOP  4161.80   4152.30   4171.30   0.30 ATR   PLACED  #1240  exp 5h40m
               level 4161.29  SL swing 4152.90  score now 8/10 HIGH  eff 71%  armed @15:05  R 9.50 ...
  RADAR DOWN                                                       BUILDING  score 3/10  (armed at 7 within 1 ATR)
  SCALP M1     BUY MKT   4154.15   4149.35   4157.35   live       WAIT: M1 AGAINST M5 REGIME
               M1 NRTR BEARISH  regime BULLISH  ATR5 3.20  SL 1.5xATR  TP 1.0xATR  0.10 lot = 48.00 at SL  time stop 45 M1
  BROKER       SELL LMT  4285.20   4297.80   4272.60   0.42 ATR   #1234  QML  0.09 lots  age 0h25m
  BROKER       BUY LMT   4268.50   4258.20   4278.80   1.10 ATR   #1235  pullback  0.10 lots  age 1h02m  NEAR
  BROKER ORDERS 2   POSITIONS 0   TODAY M5 PLANS: cancelled 2  expired 1  TP1 3  SL 1   GATE OPEN
  DEMO  USD  balance 10048.50   risk 0.50% = 50.24   today +12.30 closed ...   LAST UPDATE 15:09:21
```

Status vocabulary: `WAITING` (placed at the next M1 close) · `PLACED #ticket` · `NEAR #ticket`
(within `InpNearAtr` = 0.5 ATR of the level) · `FILLED > RUNNING` · `RUNNING` · `TP1 HIT` /
`SL HIT` · `expired unfilled` · `cancelled - regime turned` · `replaced by newer` ·
`REJECTED retcode N` · `ARMED - slot taken` / `ARMED - <gate reason>` / `ARMED - price already
past the level` / `ARMED - <kind> trading switched off`.

Banner states: `SCALP BUY/SELL (AUTO|MANUAL)` · `BUY/SELL TRIGGER - BLOCKED` (gate) ·
`WAIT - NO TRADE` · `DATA STALE / MARKET CLOSED` · `ALGO TRADING OFF - WATCH ONLY` ·
`REAL ACCOUNT - TRADING BLOCKED` (only if you set `InpAllowRealAccount = false`) · `GOLD / SILVER ONLY`.

**On the chart (everything the EA draws, prefix `NQEA_`):** small green/red bias arrows on
past candles and the big white `NEXT` arrow on the forming one (M1/M5/M15 charts), confirmed
M5 `HH HL LH LL` labels, `▲ S` / `▼ S` scalp markers (hover for levels and outcome), and the
level lines of the active scalp, the latest QML (orange), pullback (blue) and NY trap
(purple) plans. Anything else on the chart comes from another indicator or template.

## Risk engine (nothing here is ever widened by the EA)

| Input | Default | |
|---|---|---|
| `InpRiskPct` | 0.5 % | of balance per trade; hard-capped at 5 % in `OnInit` |
| `InpDailyLossCapPct` | 2 % | closed + open result today ≤ −cap → no new entries (closing still works); 0 = off |
| `InpMaxOpenPositions` | 1 | one slot per asset is enforced regardless of this value |
| `InpMaxTradesPerDay` | 0 = unlimited | entries per server day |
| `InpMaxSpreadPoints` | 50 | |
| `InpSessionStartHour / EndHour` | 0 / 24 | server hours, overnight ranges allowed |
| `InpAllowRealAccount` | **true** | false restricts the EA to demo accounts |
| `InpMagic` | 180915 | |

Per order the EA also refuses (and says why) when the SL/TP sit inside the broker's stops
level, when the minimum lot would risk more than the allowance, or when free margin is short.

Every order is printed to the **Experts** log, e.g.
`NQ MARKET BUY 0.10 SL 4149.10 TP 4157.10 | M5 BULLISH, M1 NRTR realigned + candle closed
10:36, ATR5 3.20, risk 0.50% = 50.00 USD -> lot 0.10 | OK retcode 10009 deal 123`.

## Other settings

| Input | Default | |
|---|---|---|
| NRTR ATR period / multiplier | 14 / 2.0 | on every timeframe |
| M15 context EMA / fast EMA | 200 / 20 | |
| Structure lookback | 3 | bars each side of a swing |
| Scalp SL / TP (× ATR5) | 1.5 / 1.0 | |
| Scalp actionable for / time stop | 2 / 45 M1 bars | |
| QML SL buffer / wait bars | 0.2 × ATR5 / 36 M5 bars | head confirmation → neck break |
| Plan lifetime (M5 / swing) | 72 M5 bars / 96 M15 bars | |
| NY open / close / pre-range start | 16:30 / 23:00 / 00:00 server | EET broker = New York 09:30-16:00 |
| Trade QML / pullback / NY trap / swing / radar | on | each kind can be switched off |
| Radar stop buffer | 0.15 ATR5 | beyond the level |
| Macro symbol / macro blocks | empty / on | e.g. USDX; empty = no macro filter |
| NEAR distance | 0.5 ATR5 | |
| Asia start / end, London start | 01 / 10 / 10 server hours | London ends at the NY open |
| Draw levels | on | session highs/lows, previous day, VWAP, break marks |
| Pullback retrace / min impulse / SL buffer | 50 % / 2 × ATR5 / 0.2 × ATR5 | |
| Plan TP1 / TP2 | 1R / 2R | |
| Forecast votes before tie-break / arrows drawn | 1 / last 300 candles | |
| History used | 8 days | |
| Panel size / corner / X / Y | 1.0 / top-left / 12 / 24 | bottom-left is the other option |

## Why it cannot repaint

* Bar 0 (the forming candle) is never read on any timeframe. An M1 bar only sees the M5
  and M15 bars that had **closed** when it closed.
* A swing exists only after `Structure lookback` more bars have closed after it.
* A forecast is scored at the close that made it and judged once, at the next close.
* The history window starts at a calendar day, so a restart on the same day recomputes the
  same bars, the same plans (keyed by swing time) and finds its own orders by comment.
* Trading happens once per closed M1 candle, never intra-bar. An old trigger is never
  re-fired after a restart: only the candle that just closed can open a scalp.

## Live account and the on/off switch

The EA trades on **real and demo accounts alike** (`InpAllowRealAccount` defaults to true;
set it to false to restrict it to demo). **The MT5 Algo Trading button is the switch**: green
= the bot trades, off = the banner reads `ALGO TRADING OFF - WATCH ONLY`, everything is still
computed and drawn, nothing is sent. No sleep: the session filter defaults to round the clock
and the trades-per-day limit defaults to unlimited. The daily loss cap (2 % of balance) is the
only limit left on by default; set `InpDailyLossCapPct = 0` to remove it. The EA never widens
a risk input on its own and every order is logged. Before the first live day: F7 must compile
with 0 errors and a demo run should show a plan record you are prepared to fund.

## Only its own orders

Everything the EA reads or changes is filtered by its magic number (`InpMagic`). A position
or pending order you placed by hand, or one from another EA, is **never modified, closed or
cancelled**, does not occupy the slot, and is listed on the SLOT line as
`MANUAL n pos / n ord untouched` so you can see it is there.

## Which sessions

The QML, pullback, swing and scalp plans run in every session (Asia, London, New York) and
the BROKER rows show every live order and position of this EA at any hour. Only the NY trap
is session-bound: it needs a pre-NY range and the NY window. There is no Asia or London trap
state machine.

## Honest limitations

* This NRTR is the ATR-scaled variant on closes; flips will not match another NRTR bar for bar.
* If MT5 restarts on a **later** day, the window starts a day later and EMA/NRTR are seeded
  again; states can differ near the start of the window.
* Money rows trust the broker's `SYMBOL_TRADE_TICK_VALUE`; the daily result trusts the deal
  history (commission and swap included when the broker reports them).
* Some brokers rewrite order comments; a plan's order is then matched by type and price.
* The forecast is a momentum vote. Its hit rate is measured and shown; nothing else is
  claimed for it.
* MetaEditor was not available in the build environment: the file is compiled and run under
  g++ against a simulated terminal (see TESTING.md). **Press F7 and run it on a demo chart
  before trusting it.**
