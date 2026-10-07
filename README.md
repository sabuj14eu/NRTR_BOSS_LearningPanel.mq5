# NRTR QML Metal Scalper (MT5, Gold & Silver) + the Crypto twin (BTC, ETH, LTC, altcoins)

One standalone Expert Advisor, `NRTR_QML_MetalScalper.mq5`, for **XAUUSD / Gold** and
**XAGUSD / Silver** only. Nothing else. No Telegram, no DLLs. The only network use is two
outbound POSTs to SignalMesh, both optional and both off by default: the append-only event
journal and the ANALYSIS ONLY telemetry heartbeat (see the two SignalMesh sections). It replaces the earlier learning-panel indicator (removed from this repository; git
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

## The CRYPTO twin: `NRTR_QML_CryptoScalper.mq5` (BTC / ETH / LTC / altcoins)

The same bot for crypto. It is **derived mechanically** from the metal EA by
`tools/derive_crypto_ea.py` (the test runner proves the committed file IS that derivation
and that the engine block is byte-identical apart from the asset detector), so every rule
below - the pipeline, the six setups, one slot per asset, the risk gate, the journal, the
panel, the verdict - is the same text. Only the asset side differs:

| | Metal EA | Crypto EA |
|---|---|---|
| Symbols | XAUUSD / XAGUSD | **BTC** (BTCUSD, XBTUSD), **ETH**, **LTC**, any **altcoin** quoted in USD / USDT / USDC / BUSD; any prefix/suffix. A coin AUTO does not know: `InpCoinClass = ALT` |
| Specialist profile | - | per class, shown on the panel (`COIN PROFILE` row): BTC risk x1.0 / SL buffers x1.0 / spread cap 0.15 ATR; ETH buffers x1.25, cap 0.20; LTC risk x0.75, buffers x1.5, min impulse x1.25, cap 0.25; ALT risk x0.5, buffers x1.5, impulse x1.25, cap 0.30, **radar (breakout STOP) plans off**. Multipliers only ever reduce risk and widen buffers. `InpSpecialist = false` = raw inputs |
| Spread cap | 50 points | **x ATR(M5)** (`InpMaxSpreadAtr`, 0 = the class value); a BTC spread is hundreds of points and an altcoin's a handful, so a point cap means nothing here. `InpMaxSpreadPoints > 0` overrides |
| Macro filter (radar only) | DXY, blocks when it points the **same** way | **BTC-lead filter, graded - not a master switch**: the alts follow BTC, so a break that BTC's M15 NRTR points **against** is blocked **unless the coin's OWN structure is A+**: radar score ≥ `InpLeadOverrideScore` (9 of 10) **and** its own M15 context **and** its own M5 regime on the side of the trade (spread, risk and the volatility regime are gated before it regardless; 11 = never override). Weak setups stay blocked. The lead is found automatically: this symbol's spelling with BTC in place of the coin (`#ETHUSD.m` -> `#BTCUSD.m`), so BTCUSD / BTCUSDm / BTCUSD.a are one class under the broker's exact name; none for BTC itself; `InpMacroSymbol = "-"` = off; `InpMacroInverse = true` for a DXY-like lead |
| Volatility regime + spike guard | same (v1.7, common layer) | same - crypto goes from dead to wild without a session boundary, which is exactly what the regime measures |
| Sessions | metals break at the rollover | **24/7**: the session clock only shapes the levels (Asia / London / NY, previous day, VWAP), it never stops the bot. The NY trap still uses the NY open on the server clock |
| Magic | 180915 | 180916 |
| Journal | `system: NQ-EA` | the same keys plus `engine: NQ-CRYPTO` and `coin: BTC/ETH/LTC/ALT` (append-only) |
| Telemetry | METAL ANALYSIS page (`/webhooks/metal/telemetry`) | CRYPTO ANALYSIS page (`/webhooks/crypto/telemetry`, SignalMesh v5.107): the same snapshot plus `asset_class: crypto`, `coin`, the class profile (`specialist`, `prof_risk`, `prof_buf`, `prof_imp`, `prof_spread_atr`, `prof_radar`) and the BTC lead (`lead_symbol`, `lead_dir`) |

One chart per coin, one EA per chart; the metal and crypto EAs never see each other's orders
(magic + symbol). Everything else in this README applies to both files. It replaces the
old crypto learning-panel indicator (`NRTR_BOSS_Crypto_NYTrap.mq5`, which lived on another
branch): remove that indicator from your charts.

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
ended** (only then can it be broken). Every level label is drawn at the **newest candle**, so
it stays on screen however far back the line started. **Structure S/R** is drawn too: the two
nearest confirmed M5 swing highs above the price (`R`, red) and swing lows below it (`S`,
green), as rays from the swing. A **BREAKOUT CONFIRMED ▲** mark is printed at the first M5
**close** above an active session level or a confirmed swing high; **BREAKDOWN CONFIRMED ▼**
at the first close below an active low or a confirmed swing low; once per level. The `BREAK`
line names the latest session-level break with its time, the `LEVELS` line lists the prices
(`*` = still building) and whether the price is above or below VWAP. These are for reading the
day; they do not open trades by themselves. The radar (above) is what forecasts a break
*before* it happens; the marks confirm it *after* the close.

## 5. Bias arrow (strong votes only, judged on a real move)

At each candle close the votes are summed: higher-timeframe vote × 2, own NRTR, close vs
EMA20, the candle's body. An arrow is drawn **only when the vote is strong and one-sided**
(`|score| ≥ InpForecastMinScore`, default 3); a split vote draws nothing. An arrow claims a
**move**, not a candle colour: it is a **hit** when the price reaches +0.5 ATR in its direction
before −0.5 ATR against it within the next 5 candles, a **miss** when the opposite side comes
first (both in one candle = miss), and **unresolved** (not counted) if neither side is reached.
On the chart: small green/red arrows on past candles, a big white `NEXT` arrow on the forming
candle when the vote is strong. On the panel: `NEXT M1 BIAS` and `BIAS HIT RATE` over the
resolved arrows with the evidence label; 50 % is a coin. The arrow never opens a trade.

## The verdict (the banner) and the NEAR alert

The banner is one line that says **what to do now**, recomputed every second, in this order:

| Situation | Banner |
|---|---|
| a position of this EA is open and the M5 regime is with it (or CHOP) | `HOLD BUY #ticket (QML) - M5 regime intact  P/L ...  SL ...  TP ...` |
| a position is open and the M5 regime has flipped against it | `EXIT BUY #ticket - M5 REGIME FLIPPED BEARISH  (you decide)` (or `bot closes at the next M1 close` when `InpScalpCloseOnFlip` / `InpPlanCloseOnFlip` applies) |
| a position is open in the direction of a **spike** that has given back `InpSpikeRetrace` (50 %) of itself | **`EXIT WARNING BUY #ticket - SPIKE REVERSAL: the 15.2 ATR up-spike (3.1x a normal hour) gave back 60% (news?)  - you decide`**, flashing orange / white every second, with a flashing `EXIT WARNING - SPIKE REVERSAL` label on the chart. Nothing is closed by this |
| a waiting order or armed plan is within `InpNearAtr` (0.5 ATR) of the price | `● PRICE NEAR  QML BUY LIMIT 60.709  SL ...  TP ...  (0.30 ATR)  order waiting` |
| the M1 trigger fired on the candle that just closed | `SCALP BUY NOW  entry ... SL ... TP ...` |
| orders are waiting but far | `WAIT - 2 order(s) waiting, nearest PULLBACK BUY LIMIT ... 4.5 ATR away` |
| nothing armed | `WAIT - no setup armed (M5 CHOP, ...)` |

With **Algo Trading off** the same verdict is prefixed `MANUAL:` and the reason line says the
verdict is for your hands (`PLACE IT NOW` when a level is near and no order waits). On the
board the row's DIST cell turns bright with a `●` when its level is near, a running row reads
`RUNNING - HOLD` or `RUNNING - EXIT? regime flipped`, and a plan that filled in the record
while no position exists reads `FILLED (paper - no position)`. On the chart a big white
`● NEAR ...` label sits at the level the price is approaching. Scalps close on a regime flip by
default; structure plans do not (`InpPlanCloseOnFlip = false`) because their SL/TP is the
plan, so the board says EXIT and you decide.

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

## Volatility regime + spike guard (news days - v1.7, both EAs)

On an NFP day the metal (or the coin) jumps, comes back, and the "pullback buy" that follows
is not a pullback - it is the other side of a spike (silver 62 → 59.80 on 2026-10-02). Two
measurements in the common terminal layer (the engine is untouched) deal with it; both gate
**new entries only** - closing is never blocked, and nothing is closed by them.

**Volatility regime** - `ATR(M5)` against its own average over `InpVolAvgBars` (288 = 24 h),
shown on the `VOL REGIME` panel row and in every journal line (`vol_regime`):

| Regime | Ratio | Effect |
|---|---|---|
| DEAD | < 0.5 | no new trade (gate reason `VOLATILITY DEAD - NO NEW TRADE`) |
| NORMAL | 0.5 - 1.5 | as configured |
| EXPANSION | 1.5 - 2.5 | allowed with stronger confirmation: a radar breakout needs score ≥ `InpVolExpandRadar` (8 of 10), a scalp needs the M15 context on its side |
| EXTREME | ≥ 2.5 | do not chase: no new trade, and after it ends the gate stays closed (`WAIT FOR FRESH STRUCTURE`) until a **confirmed M5 swing has formed after the extreme bar** |

`InpVolGate = false` keeps the classification and the row but opens the gate.

**Spike guard** - the last `InpSpikeBars` closed M5 bars (12 = 1 h) ranging at least
`InpSpikeX` (2.5) times a **normal** such window (the average 12-bar range over the same
lookback; a trending hour already spans ~4 ATR(M5), so the ATR alone would call every hour a
spike). While the spike is in the window: **no plan of any kind, and no scalp, in its
direction** - pullback, radar breakout, QML and NY trap alike (a waiting order in that direction
is cancelled with the reason). Selling the bounce of a crash is the mirror of buying the dip of a
spike. Plans **against** the spike (a QML BUY after a down-spike) stay allowed: those are the
reversal plans. (v1.7.3 - until 1.7.2 QML plans were exempt; 2026-10-07 gold showed two QML SELL
limits waiting to sell the bounce of a 17 ATR down-spike.) Once the close has given
back `InpSpikeRetrace` (50 %) of it, a position in its direction gets the flashing
**EXIT WARNING** above. The panel row reads e.g. `SPIKE UP 15.2 ATR (3.1x normal), 60% back -
EXIT WARNING`; telemetry carries `spike_dir / spike_atr / spike_x / spike_retrace`. The EA has
no news calendar - the spike is the evidence, the human decides.

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
| Vol gate / average bars / DEAD / EXPANSION / EXTREME | on / 288 / 0.5 / 1.5 / 2.5 | ATR(M5) against its own average, see above |
| Expansion radar score / scalp needs M15 | 8 / on | stronger confirmation during EXPANSION |
| Spike guard / bars / x normal / retrace | on / 12 / 2.5 / 0.5 | the EXIT WARNING threshold |
| NEAR distance | 0.5 ATR5 | |
| Asia start / end, London start | 01 / 10 / 10 server hours | London ends at the NY open |
| Draw levels | on | session highs/lows, previous day, S/R swings, VWAP, confirmed break marks |
| Plan close on regime flip | off | scalps always close on a flip; plans say EXIT and wait for you |
| Journal to file / SignalMesh URL / secret | on / empty / empty | see the journal section |
| Telemetry URL / every N s / demo only | empty / 60 / on | see the telemetry section; empty = off |
| Pullback retrace / min impulse / SL buffer | 50 % / 2 × ATR5 / 0.2 × ATR5 | |
| Plan TP1 / TP2 | 1R / 2R | |
| Bias arrow: votes needed / arrows drawn | 3 / last 300 candles | strong, one-sided votes only |
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

## SignalMesh journal (the performance matrix's raw material)

Every plan event is one JSON line, **appended** to `MQL5/Files/NQ_events_<symbol>.jsonl`
(`InpJournalToFile`) and, when `InpSignalMeshUrl` is set, POSTed to the platform's
`/webhooks/brain/signal` with `X-Brain-Secret: <InpSignalMeshSecret>` (allow the URL in
Tools → Options → Expert Advisors → WebRequest). The secret travels in a header and is never
printed. A POST the platform does not accept is queued (up to 300) and retried one every five
seconds, in order; the file is the durable record either way. The journal can never block or
change trading.

Events: `armed`, `placed` (with ticket and lot), `rejected` (with retcode), `filled`, `tp1`,
`sl`, `false_break`, `expired`, `cancelled`, `replaced`, `closed_by_ea` (with reason and P/L),
`scalp_open`; scalp records use the same fields with `plan_kind: SCALP`. Every event carries the
plan's stable `signal_id` (`NQ:<symbol>:<comment>`), `system: NQ-EA`, symbol, tf, direction,
entry / SL / TP1 / TP2 / rr, `grade` = plan kind, the platform status (`pending`, `executed`,
`closed`, `cancelled`, never `approved`), the outcome (`win` / `loss` / `open`), `fired_at` (plan
creation) and `ts` (event time), plus `plan_status`, `level`, `level2`, `risk`, `account_mode`,
`magic`, `regime5`, `ctx15`, `risk_pct`, and `radar_score` for radar plans. The contract is
APPEND-ONLY: fields are added, never renamed or removed. The platform side (`docs/EA_EVENTS.md`
in the SignalMesh repo) reads these into a per-kind performance matrix.

## SignalMesh telemetry (ANALYSIS ONLY - the METAL ANALYSIS page)

Since 1.6.0 the EA can also act as a **data witness**: when `InpTelemetryUrl` is set (e.g.
`https://app.signalmesh.dev/webhooks/metal/telemetry`, allowed under Tools → Options →
Expert Advisors → WebRequest) it POSTs one JSON **snapshot of what the panel shows** on every
closed M1 candle and at least every `InpTelemetrySec` seconds (default 60), with the same
`X-Brain-Secret` header as the journal. SignalMesh stores the snapshot verbatim and renders it
on its **METAL ANALYSIS** page under the fixed label
`ANALYSIS ONLY - DEMO - NOT A TRADE SIGNAL`. Nothing flows back: the platform never sends
anything to the EA, and the EA never reads anything from the platform.

What a snapshot carries, every field the EA's own observed state and labelled as such:

| section | fields |
|---|---|
| identity | `system: NQ-EA`, `kind: telemetry`, `mode: ANALYSIS_ONLY`, `label`, `source`, `ea_version`, `symbol`, `metal`, `account_mode` (demo / real), `magic` |
| regime | `vol_regime`, `vol_ratio`, `spike_dir`, `spike_atr`, `spike_x`, `spike_retrace` (v1.7) |
| clocks | `ts_server` (broker clock), `ts_gmt` (the PC's GMT clock), `server_offset_sec` - two witnesses, so the platform can measure skew instead of assuming an offset; bar stamps stay in **server time, never converted** |
| `candles` | state (`CLOSED FRESH` / `STALE` / `UNKNOWN`), closed M1 / M5 / M15 server stamps **with their ages in seconds on the EA's own clock**, ATR1 / ATR5 / ATR15, bid, ask, spread |
| `m15` | context (`BULLISH` / `BEARISH` / `NEUTRAL`), NRTR direction and level, EMA200, close, closed stamp |
| `m5` | regime (`BULLISH` / `BEARISH` / `CHOP / UNKNOWN`), NRTR direction and level, structure text and state, lookback, the regime's own reason words, nearest active resistance above / support below |
| `m1` | NRTR direction and level, trigger (`BUY` / `SELL` / `WAIT`) with its reason words, next-bar forecast, score, resolved count, hits and the evidence label |
| `observed` | the banner verdict, the NEAR text, the final state and reason, the gate words, whether Algo Trading / auto scalp / pending auto / allow-real are on - labelled `OBSERVED EA STATE - not a SignalMesh recommendation` |
| `scalp_row`, `radar`, `ny` | the board's SCALP M1 row (side, live entry, SL, TP, lot, state), both radar sides (state, score, pressure, level, distance), both NY trap sides |
| `plans` | the latest plan per board slot (QML M5, PULLBACK M5, NY TRAP, QML M15, PULLBACK M15, RADAR UP / DOWN) and the latest scalp record: kind, tf, side, order type, status, entry / SL / TP1 / TP2, levels, `signal_id`, whether a broker order is placed |
| `account` | balance, floating, day P/L, open / pending counts, manual counts, trades today, risk % and money, last trade - no login, no server name, no credentials |
| `record` | done / won / lost and the evidence label per engine (scalp, QML, pullback, NY trap, radar) |

Ages are computed by the EA on its own clock before they leave the terminal, so the platform
never has to subtract a broker stamp from its own clock. When the EA's data is stale the
snapshot says `fresh: false` with the reason; when the platform stops receiving snapshots its
page shows STALE; when it never received one it shows UNKNOWN. **A missing snapshot is never
a neutral reading.**

**Demo only by default.** `InpTelemetryDemoOnly` (default on) means a REAL account never sends
telemetry: the witness for the analysis page is a separate DEMO account. To stand one up on the
Windows server: log a second MT5 terminal into a DEMO account, open XAUUSD M1 and XAGUSD M1, drop
the EA on each chart with `InpTelemetryUrl` and `InpSignalMeshSecret` set, `InpAllowRealAccount =
false` for good measure, and leave the **Algo Trading button OFF** so the EA is a pure witness
(everything is computed and reported; nothing is sent to the broker). The Experts log prints
`NQ telemetry: snapshot accepted by SignalMesh (ANALYSIS ONLY)` once, and a failure count if the
platform stops answering. Telemetry runs after `NqTrade()` and has no queue; it can never block
or alter a decision, and a failed POST costs one `Print`.

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
