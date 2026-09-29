# NRTR Gold & Silver tools for MT5

Two standalone files for **XAUUSD / Gold** and **XAGUSD / Silver** only. Nothing else. No
SignalMesh, no Telegram, no network, no DLLs, no files.

| File | Type | What it does |
|---|---|---|
| `NRTR_QML_MetalScalper.mq5` | **Expert Advisor** (the final tool) | M15 context → M5 regime + structure → M1 trigger → risk engine → auto lot → MT5 **demo**. Auto scalps, places/cancels **QML** and **pullback** pending orders, draws a **forecast arrow on every candle**, one compact panel. |
| `NRTR_BOSS_LearningPanel.mq5` | Indicator (learning tool, unchanged) | 15M boss / 5M trigger CLICK BUY / CLICK SELL panel. Never trades. |

Both decide on **CLOSED candles only** and never repaint. Tests and exact results are in
[TESTING.md](TESTING.md).

---

## Install (EA)

1. MT5 → **File → Open Data Folder** → `MQL5/Experts/`. Copy `NRTR_QML_MetalScalper.mq5` there.
2. MetaEditor → open → **F7**. Expect `0 errors`.
3. Open an **XAUUSD M1** or **XAGUSD M1** chart (M5 or M15 also work; arrows are drawn only on
   M1/M5/M15 charts). Drag the EA on. Tick **Allow Algo Trading** in the dialog and the
   **Algo Trading** button in the toolbar.
4. The account must be a **DEMO** account. On a real account the EA shows
   **REAL ACCOUNT - TRADING BLOCKED** and sends nothing, unless you set
   `InpAllowRealAccount = true` yourself.

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

## 1. Auto scalp (market order on the M1 trigger)

This is the trade in the picture (4155.59 → 4152.12 = +3.47 and so on): a small move in
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

## 2. Pending order plan (set it and go to work)

Two plans, always computed on closed **M5** bars, each shown as one line you can type into
a pending order — or let the EA place and cancel it (`InpPendingAuto`, default on).

### QML (Quasimodo) reversal

```
bearish:  swing high A (left shoulder)  ->  swing low B (neck)  ->  higher high C (head)
          ->  a CLOSE below B
          SELL LIMIT at A     SL = C + 0.2 × ATR5     TP1 = 1R     TP2 = 2R
bullish:  the mirror image  ->  BUY LIMIT at the left-shoulder low, SL below the head
```

Swings are confirmed only after `Structure lookback` (3) more bars have closed, so the head
is known 15 minutes after it printed; the plan appears at the close that breaks the neck.
It is keyed by the head's time, so a restart finds the same plan and the same order.

### Pullback in the regime

```
BULLISH regime and a new HH just confirmed, leg HL -> HH at least 2 × ATR5 long:
   BUY LIMIT at HL + 50% × (HH - HL)     SL = HL - 0.2 × ATR5     TP1 = 1R   TP2 = 2R
BEARISH: mirror (SELL LIMIT at the 50% retrace of LH -> LL)
```

### Lifetime

* A plan lives `InpPlanValidBars` M5 bars (72 = 6 hours), then it expires and its order is
  cancelled.
* A newer setup of the same kind and side **replaces** the older one (the order moves to
  the new level). A pullback plan is also cancelled when its regime turns.
* An unfilled limit sits between the price and its own stop, so the price cannot close past
  the stop without filling it: an unfilled plan ends only by fill, expiry, replacement or
  regime turn. That is a fact about limit orders, not a choice.
* Filled orders are managed by their SL/TP only (`InpPlanUseTp2` puts the TP at 2R).

The panel line reads, for example:

```
QML ORDER     SELL LIMIT 4158.40  SL 4163.90  TP1 4152.90  TP2 4147.40  lot 0.09
QML STATUS    ORDER #12345 PLACED, expires in 4h10m  (neck 4149.30, head 4161.20)
```

Copy the first line into MT5 if you prefer to place it yourself (`InpPendingAuto = false`).

## 3. Forecast arrow on every candle

Every candle carries an arrow with the forecast for the **next** candle, made at this
candle's close:

```
score = 2 × higher-TF vote  +  own NRTR direction  +  close vs EMA20  +  this candle's body
arrow UP if score >= 2, DOWN if <= -2, none if the votes split
```

* On an M1 chart the higher vote is the M5 regime; on M5 it is the M15 context; on M15
  there is none.
* **White arrow on the forming candle = the live forecast.** It is made at the previous
  close and does not move until the candle closes.
* When the candle closes, its arrow turns **green (hit)** or **red (miss)**: hit = the close
  went the forecast way; an unchanged close counts as a miss.
* `NEXT M1 FORECAST` and `FORECAST HIT RATE` on the panel show the live arrow and the
  measured accuracy over the loaded history with its evidence label. **It is a forecast:
  judge it by the hit rate, never by one arrow.** Its expected accuracy is modest; it does
  not open trades on its own and it does not override the trigger.

## The panel (one column, two tables)

```
 GOLD  -  NRTR QML SCALPER
 XAUUSD   4153.90 / 4154.15   DEMO   M1 closes in 00:31
 [ ▲  SCALP BUY  (AUTO) ]                         <- banner: state + gate
 REASON: M5 BULLISH + M1 NRTR REALIGNED + CANDLE CLOSED IN DIRECTION
         SL 1.5 x ATR5, TP 1.0 x ATR5, time stop 45 M1 bars
 ENGINE  M15 -> M5 -> M1
  M15 CONTEXT         BULLISH  (NRTR BULLISH, above EMA200 4120.5)
  M5 REGIME           BULLISH  (NRTR stop 4149.20)
  M5 STRUCTURE        HL -> HH
  M5 ATR14            3.20   scalp SL 4.80  TP 3.20
  M1 TRIGGER          BUY  entry 4153.90  SL 4149.10  TP 4157.10
  NEXT M1 FORECAST    ▲ UP  (score +4)
  FORECAST HIT RATE   53.8%  (612 of 1138, n>=100)
 PENDING ORDER PLAN  +  AUTO SCALP  +  RISK
  QML ORDER           SELL LIMIT 4158.40  SL 4163.90  TP1 4152.90  TP2 4147.40  lot 0.09
  QML STATUS          ORDER #12345 PLACED, expires in 4h10m  (neck 4149.30, head 4161.20)
  PULLBACK ORDER      BUY LIMIT 4151.20  SL 4145.90  TP1 4156.50  TP2 4161.80  lot 0.09
  PULLBACK STATUS     NOT PLACED YET, expires in 5h55m  (50% of 4146.10->4156.30)
  GATE                OPEN  (scalp auto, pending auto, spread 23/50)
  RISK / AUTO LOT     0.50% = 50.00 USD   next scalp 0.10 lots = 48.00 at SL
  TODAY               +12.30 USD closed, +2.10 USD open   cap -200.00   trades 3/10
  OPEN / PENDING      BUY 0.10 @ 4153.10 (scalp) +2.10   pending 1: QML sell limit 4158.40
  RECORD 8d           scalp 24/40 TP   QML 7/12   pullback 3/5   (n<100 = early)
```

Banner states: `SCALP BUY/SELL (AUTO|MANUAL)` · `BUY/SELL TRIGGER - BLOCKED` (gate) ·
`WAIT - NO TRADE` · `DATA STALE / MARKET CLOSED` · `REAL ACCOUNT - TRADING BLOCKED` ·
`GOLD / SILVER ONLY`.

**On the chart:** forecast arrows (M1/M5/M15 charts), confirmed M5 `HH HL LH LL` labels,
`▲ S` / `▼ S` scalp markers (hover for levels and outcome), the levels of the active scalp
and of the latest QML (orange) and pullback (blue) plans.

## Risk engine (nothing here is ever widened by the EA)

| Input | Default | |
|---|---|---|
| `InpRiskPct` | 0.5 % | of balance per trade; hard-capped at 5 % in `OnInit` |
| `InpDailyLossCapPct` | 2 % | closed + open result today ≤ −cap → no new entries (closing still works) |
| `InpMaxOpenPositions` | 2 | this EA, this symbol |
| `InpMaxTradesPerDay` | 10 | entries per server day |
| `InpMaxSpreadPoints` | 50 | |
| `InpSessionStartHour / EndHour` | 0 / 24 | server hours, overnight ranges allowed |
| `InpAllowRealAccount` | **false** | the only way to trade on a real account |
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
| Plan lifetime | 72 M5 bars | |
| Pullback retrace / min impulse / SL buffer | 50 % / 2 × ATR5 / 0.2 × ATR5 | |
| Plan TP1 / TP2 | 1R / 2R | |
| Forecast min score / arrows drawn | 2 / last 300 candles | |
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
