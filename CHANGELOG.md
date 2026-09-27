# CHANGELOG

## v1.10 metals (2026-09-27): the four audit fixes - click guard, broker-safe lots, first-bar arrow, pending wording

The engine is unchanged: same signals, same alerts, same NRTR / NY trap / 5-question / regime logic.
The crypto / forex files only got three pass-through bridge adapters (their output is unchanged).
**A small `v1.10` label now sits at the top right of the gold / silver left box**, so a compiled
update is visible.

### The findings (Shyam's audit, 2026-09-27) - all four confirmed in the code first

1. **CLICK could be stale.** The engine keeps a signal alive for `InpSignalValidBars` (6) closed
   5M bars, and the banner kept saying CLICK BUY with the old 5M entry price however far price had
   moved. "CLICK BUY 4300" at 4320 is not a safe click.
2. **Lots were not broker-safe.**
   * `NormalizeDouble(lots, 2)` after flooring to the volume step can round **up** for a step
     like 0.005 (0.035 -> 0.04, above the risk budget).
   * The risk used `SYMBOL_TRADE_TICK_VALUE` only, never MT5's loss tick value.
3. **The first NRTR-ready bar got a FLIP arrow** (`prevAd = 0 -> +/-1` counted as a flip).
4. **The pending-order line printed `---`** when the 15M boss had a direction but the 5M NRTR was
   against it. The calculation was consistent; the wording was misleading.

### The fixes

| # | Fix | Where |
|---|---|---|
| 1 | **CLICK GUARD.** New `InpClickBandR` = 0.5. The banner says **READY - CLICK BUY / SELL** only while the live price (ask for BUY, bid for SELL) is within 0.5 x the signal's risk of its entry reference, on either side. Otherwise it says **BUY / SELL SETUP - PRICE TOO FAR**, with the reason "PRICE x FROM ENTRY (0.8R > 0.5R)" and "WAIT FOR RE-ENTRY - DO NOT CHASE"; the banner does not blink. No live price = never READY. The ENTRY row gets `bar 4/6  now 4320.00  +20.00 (0.8R)`. The bridge `action` reads `READY - CLICK BUY` or `BUY SETUP - PRICE TOO FAR - WAIT FOR RE-ENTRY`, and `signal` gains `age_bars`, `valid_bars`, `price_now`, `distance`, `distance_r`, `click_band_r` and `click`. The change_key includes the click state, so Telegram posts once when READY turns TOO FAR (and back). The ladder (optional) follows the same rule. **Display only: `g_final`, alerts and signals are untouched.** | `NbClickState`, `NbDrawPanel` banner / reasons / ENTRY row, `NbLadderDraw`, adapters `NbBrAction`, `NbBrSigExtra`, `NbBrClickKey` |
| 2 | Lots are normalised to the **volume step's own decimals** (0.005 -> 3), with a guard that the result never exceeds the budget. `g_tickValue` = max(`SYMBOL_TRADE_TICK_VALUE`, `SYMBOL_TRADE_TICK_VALUE_LOSS`), so lots for x% risk and money at the SL are never understated. It is still an estimate: `OrderCalcProfit` is not available to indicators. | `NbLotsForRisk`, `NbReadSpec` |
| 3 | `flipHere = (prevAd != 0 && ad != prevAd)`: the first NRTR-ready bar is not a flip. | `NbFillBuffers` |
| 4 | 15M BUY + 5M not bullish: PULLBACK = `5M AGAINST - WAIT FOR 5M BULLISH RE-ALIGNMENT` (the BREAKOUT line keeps its price). The SELL mirror is the same. | `NbDrawPanel` pending rows |

### Tests (`./run_tests.sh`) - ALL SUITES PASSED

* **"Existing panel unchanged" (gold)** now compares against the v1.04 baseline **with the declared
  fixes applied** (`tests/baseline_patches.py`: arrow start, READY wording, pending wording; each
  anchored exactly once). Result: **identical** over 53 scenarios, apart from the new `k10n` and
  `ver` labels. So nothing else in the left box moved. The fixture has no TOO FAR moment; that
  state is tested directly (V2).
* `test_nyt.cpp`: **184 checks**.
  * **V1** checks lots at step 0.005 = 0.035 (not 0.04), steps 0.01 and 0.1, and that a minimum
    lot that risks too much gives 0.
  * **V2 (gold and silver)** proves that an active signal **cannot stay READY - CLICK when the
    price moves away**:
    * at the entry and at +0.3R it is READY;
    * at +0.8R it says SETUP - PRICE TOO FAR, the word CLICK is gone and the reason is shown;
    * the engine signal is untouched;
    * the bridge says PRICE TOO FAR and never READY, and the change_key changes;
    * at -0.8R it is also too far;
    * with no price it is never READY;
    * the age and distance appear on the ENTRY row.
  * **V3** checks the RE-ALIGNMENT wording, and that the limit keeps its price when aligned.
  * **V4** checks the loss tick value, larger vs smaller.
* `test_indicator.cpp`, updated to the new rules:
  * I2 puts the price at the entry to expect READY.
  * I6: an unfinished crash candle changes no signal (the banner may honestly say TOO FAR).
  * I9's reference no longer counts the first ready bar as a flip. It had the same bug the fix
    removes.
* `test_bridge*`: the metals action wording is allowed (READY / SETUP only with a BUY / SELL
  final).
* Mutations: **8 new, all caught**: band ignored, no price = READY, banner ignores the guard,
  bridge ignores it, 2-decimal lots, loss tick value ignored, first-bar flip, the `---` pending
  line.
  * The first run had M76 NOT RUNNABLE (an unused variable under `-Werror`). It was rewritten to
    compile and is CAUGHT.
  * M45 was re-anchored to the new bridge action code and is CAUGHT.
  * Run: `python3 tests/mutate_fq.py 45 73-80`. The other 72 were not re-run for this change.

### Notes for the crypto file (found, NOT changed)

The crypto / forex engine has **the same stale-CLICK behaviour** (a 6-bar signal, the old entry
reference), the same `NormalizeDouble(lots, 2)` and the same first-bar arrow. The fixes are
written so they can be ported. That is Shyam's call.

### Asked in the same message, NOT built: session-specific TP / SL (Asia, London, London-NY, NY)

Different TP / SL per session is a **strategy change**. The Evidence Law says: no live logic change
without data. The honest first step is to **measure** it. Label every shadow record (NY trap,
regime pullback, counter-trend watch) and the bridge with its session (Asia / London /
London-NY overlap / NY), then report per session the typical 5M ATR, MFE / MAE and how often TP1
/ SL is reached. After the 2-day window (and n >= 20 per session), the numbers can propose
per-session TP / SL. Waiting for Shyam's go.

## v1.09 metals / v1.08 twins (2026-09-27): REGIME PULLBACK WATCH (shadow) + the completed bridge schema

### What was asked (Shyam, 2026-09-27)

Keep the JSON -> Python -> Telegram architecture unchanged. Collect about **2 days of real / shadow
evidence before changing the main strategy**. Do not change the V18 execution signal. Do not
redesign NRTR, the NY trap, the council or execution. Then:

1. **The pullback logic (metals; crypto: note only).** The current `pullback_watch` (15M boss +
   5M NRTR flip against it) detects a counter-trend move but not the missed-entry problem. Needed:
   BEARISH REGIME (1H, 4H, 15M, 5M bearish) -> price pulls up -> WATCH PULLBACK. Monitor the pull
   distance / ATR, the previous 15M / 1H structure, the sweep / retest, a 5M rejection, a 5M
   bearish close, a valid SL and the minimum R:R. Only then: `SELL PULLBACK / RE-ENTRY
   CANDIDATE`. Never turn the pull-up into a BUY. A close above the bearish structure =
   `BEARISH THESIS INVALIDATED`, then wait for independent bullish confirmation. **Direction and
   entry location stay separate.**
2. **Final bridge fixes (all three files):**
   * JSON = the full source of truth: 18 closed M5 + M15 candles, separate forming candles,
     `forming` true / false, confirmed, age / seconds left, tick_volume, `real_volume` (null when
     MT5 gives none), bid, ask and spread (null when missing), fresh / stale, the conclusion,
     `MT5_ORDER_ACTION = NONE`.
   * Telegram stays change-only, and may show fewer candles if it labels `FULL DATA: JSON = 18
     CLOSED + FORMING`.
   * Tests prove each point.

### Findings first

1. **Confirmed: the existing watch cannot represent the missed entry.** `NbRunPw` fires when the
   15M boss is in full mode and the 5M NRTR flips against it. It never looks at 1H / 4H, at the
   structure the pull-up retests, at a rejection, or at R:R. So it cannot tell "a pull-up to sell
   again" from "the start of a reversal". The metals file did not even load 1H / 4H. It stays as
   what it is: the counter-trend BUY **hypothesis** recorder (unchanged, identical in all three
   files).
2. **The bridge schema was incomplete and not identical.** It had no `real_volume`, no ask /
   spread, no `forming` flag on closed candles, no top-level fresh flag and no
   `mt5_order_action`. The metals block differed from crypto by three substitutions.
3. **The simulator hid two things.** `SYMBOL_ASK` returned the bid when no ask was set, so
   "missing ask = null" could not be tested. `PERIOD_H1` returned 15M data, which would have made
   any 1H / 4H test meaningless. Both are fixed: the simulator now has 1H / 4H series (empty = MT5
   has none), `askMissing`, `spreadPts` and `moveFail`.
4. A test-harness bug: `start()` ran `OnInit` (which writes the file) before the simulated bid
   existed, so the first file had `"bid": null`. The indicator was right to write null for a
   missing bid; the harness now provides a quote first, as a live terminal does.

### The REGIME PULLBACK WATCH (metals, `NB_RP` engine block) - shadow only

**DIRECTION** (the regime) = 4H NRTR + 1H NRTR (the same custom NRTR maths, applied to CLOSED 1H /
4H bars) + the 15M boss in full mode, all known at the 5M close. Bearish = all three bearish; the
bullish regime is the mirror. 1H / 4H history missing = "1H / 4H data missing", never
substituted.

**ENTRY LOCATION** (5M), per closed bar, in a bearish regime:

| State | When |
|---|---|
| TREND | the regime is on; the leg low is tracked |
| PULLBACK WATCH (NO BUY) | close >= leg low + `InpRpStartAtr` (0.5) x 15M ATR, with a confirmed 15M swing high above price (the bearish structure; the 1H swing high is the second level) |
| checks | 1 pull distance / 15M ATR - 2 at structure (pull high within 0.25 x 15M ATR of the 15M / 1H level) - 3 sweep (wick above a level, close back below) - 4 rejection (the bar making the pull high closes in its lower half) - 5 confirming close (a later bearish 5M candle closes below the rejection low) - 6 SL = pull high + `InpSlBufferAtr` x 5M ATR (outward), target = the leg low, R:R >= `InpRpMinRR` (1.5) |
| SELL PULLBACK / RE-ENTRY CANDIDATE | 5 and 6, and 2 or 3. Fresh for `InpSignalValidBars` bars, then "candidate expired - do not chase". One candidate per pull (the next needs a new leg low). Recorded: target / SL / expired after 24 bars. |
| BEARISH THESIS INVALIDATED | a 5M close above the 15M structure. It stays that way until a new leg low; independent bullish confirmation is the main engine's job. Counted. |

The pull-up **never** produces a BUY record or a BUY state. A BUY re-entry exists only in a
bullish regime (the mirror). The layer never changes CLICK / WAIT, the NY trap, the 5-question
table, alerts or the V18 signal. The forming bar is never evaluated. **No threshold here has
evidence yet**: it exists to collect the 2 days (and more) of shadow records.

On the chart: two rows on the NY strip, "PULLBACK WATCH - SHADOW ONLY" plus the state, then the
six checks (or the shadow record). In the file: `mt5_signal.regime_pullback` with `direction`
(regime, h4, h1, m15_boss, m5) **separate from** `location` (pull_atr, leg / pull extreme,
structure_15m / 1h, at_structure, swept, rejection, confirming_close, rr, min_rr), `candidate`,
`record` and `not_a_signal: true`. With stale data it is `SUPPRESSED - DATA STALE`. The change_key
includes the regime pullback state, so Telegram posts when a WATCH starts, a candidate appears or
the thesis is invalidated, and not on every tick of the pull.

### Every change (line numbers in the NEW files)

`NRTR_BOSS_LearningPanel.mq5` (1.08 -> 1.09):

| Lines | What |
|---|---|
| 125-137, 139 | Header, `#property version "1.09"`. |
| 3121-3560 | **`NB_RP` engine**: `NbRpCfg`, `NbRpBar`, `NbRpRec`, `NbRunRp`, `NbRpStats`, `NbRpWhyText`. |
| 3634-3636 | Inputs: `InpRpShow` (true), `InpRpStartAtr` (0.5), `InpRpMinRR` (1.5). |
| 3719 on | Globals: the 1H / 4H series, per-5M direction / ATR / structure arrays, records. |
| 4216 | `NbRpRecompute()` after every recompute. |
| 6903-7298 | **`NB_BR`**: the completed schema, identical text in all three files (`NbJv` for volumes MT5 reports as 0). |
| 7444-7670 | `NbRpRecompute` (loads 1H / 4H, NRTR, 1H swings, maps to each 5M bar), `NbRpRows` (the two strip rows), `NbBrRegime` / `NbBrRegimeKey` (the bridge). |

`NRTR_BOSS_Crypto_NYTrap.mq5` / `NRTR_BOSS_Forex_NYTrap.mq5` (1.07 -> 1.08):
* Lines 115-119 are the header. Lines 5494-5889 are the same `NB_BR` block.
* Lines 6063-6086 are the adapters `NbBrLabel`, `NbBrSigKind`, `NbBrMarketState` (null),
  `NbBrRegime` (null) and `NbBrRegimeKey`.
* **The panels are unchanged** (dump tests).

`bridge/nrtr_telegram_sender.py`: new lines `MT5 ORDER ACTION: NONE`, `DIRECTION: ...`,
`PULLBACK WATCH (shadow, not a signal): ...` with the six checks, the candidate line, and
`FULL DATA: JSON = 18 CLOSED + FORMING per timeframe (M5, M15) - this message may show fewer`.
`NY VERDICT:` replaces a doubled "NY TRAP vs 15M BOSS". Still change-only.

### The JSON schema (append-only; `schema: nrtr_bridge/1`)

New in every file:
* **Top level:** `ask`, `spread_points`, `spread_price` (all null without an ask), `fresh`,
  `freshness`, `mt5_order_action: "NONE"`, `read_only: true`, `full_data`.
* **Every candle:** `real_volume` (null when MT5 reports 0, as CFD brokers do), `forming`,
  `confirmed`.
* **Forming candles:** `age_seconds`, and the note `FORMING / PREVIEW ONLY / NEVER A SIGNAL`.
* **`mt5_signal`:** `market_state` and `regime_pullback` (null in the twins).

Nothing was renamed or removed.

### Tests (`./run_tests.sh`, 2026-09-27) - ALL SUITES PASSED

The main panels of all three files are identical to v1.04 (metals except its two MARKET labels).

* `test_nyt.cpp`: **146 checks** (+R1-R7, +Y7).
  * **R1** is the textbook bearish re-entry, by hand: entry 100.60, SL 101.97, target 98.50,
    R:R 1.53, target reached.
  * **R2** invalidation.
  * **R3** has 30 bullish candles in a bearish regime, and there is **never a BUY**.
  * **R4** checks the cases that are not taken (away from structure, R:R below the minimum, one
    candidate per pull, do-not-chase).
  * **R5** checks the direction alignment, and that missing 1H / 4H is said.
  * **R6** checks that the forming bar never confirms.
  * **R7** is the bullish mirror.
  * **Y7**: over 240 moments per metal, the regime / state / why / structure / leg / record equal
    an **independent** 1H / 4H / 15M / 5M run (our own bars, mapping and swings). The candidate
    and the invalidation are injected into the strip and the bridge. Missing 1H / 4H is said;
    stale data shows no watch.
* `test_bridge.cpp`, gold / silver / crypto / forex: **70 / 70 / 67 / 67 checks**.
  * B1 checks the schema flags.
  * **B8**: both forming candles spiking 3% leave change_key, final / action / signal, watch,
    regime pullback and plan unchanged.
  * **B9**: real volume is copied when the broker has it and null when not; a missing ask gives
    ask / spread null.
  * **B10**: a failed rename leaves the previous JSON whole and says WRITE FAILED.
* `test_bridge_py.py`: **11 of 11**. New: the same schema (key sets) in all four files, forming /
  confirmed on every candle, real_volume null, and the FULL DATA and ORDER ACTION lines in the
  message.
* `check_bridge_blocks.py`: `NB_PW` and `NB_BR` identical in all three files, 9 adapters each.
* Mutations (`python3 tests/mutate_fq.py`): **73 planted, 73 caught** in one full run, nothing re-run. 12 are new: a pull-up recorded as BUY, 4H ignored, the forming bar evaluated, no invalidation, a candidate without location, min R:R ignored, an unconfirmed 15M swing (look-ahead), stale not suppressed, the forming candle marked confirmed, missing real volume written as 0, spread invented without an ask, a non-atomic write.

### Notes for the crypto file (found, NOT changed - Shyam's decision after the 2-day evidence)

1. **The same pullback gap.** Crypto's only pullback logic is `NbRunPw` (15M boss + 5M flip). It
   has no 1H / 4H, no structure, no rejection and no R:R, so it cannot flag the missed BTC-type
   re-entry. The `NB_RP` engine is written to be portable: the crypto file would need 1H / 4H
   loading and the adapter `NbBrRegime`. Port it only once the metals shadow records say it is
   worth it.
2. **The crypto session clock uses today's witness offset for all 10 history days.**
   `NbNyOpenOf` applies one scalar offset, so sessions from before an EU DST change inside the
   10-day window are drawn an hour off. This happens twice a year and affects **history only**:
   the live session is right. The metals clock has the same limit for its history. A per-day
   broker offset would need the broker's own DST calendar, which MT5 does not expose; guessing it
   would break "a clock needs two witnesses".
3. Crypto has no market state (`null`): metals only so far.

## v1.08 metals (2026-09-27): the NY clock, the data bridge, the market state (crypto / forex unchanged)

### What was asked (Shyam, 2026-09-27, 17:22 Poland time)

"Check time before start metal. Keep crypto like this. Now Poland time 17:22 so now NY hot time.
So metal update with proper everything. Me trade mainly gold and silver." Then: "also need to
understand trend, range, super bullish. Left box can update", with a screenshot of another
dashboard showing RANGE / CHOP per asset.

### The time check (findings first)

| | New York | broker server | Poland |
|---|---|---|---|
| NY open | 09:30 | 16:30 | 15:30 |
| NY trap window ends (`InpNytWindowMin` 90) | 11:00 | 18:00 | 17:00 |
| "now" in the message | 11:22 | 18:22 | 17:22 |

1. At 17:22 Poland the NY session is running, but **the 90-minute trap window closed at 17:00
   Poland**. So the NY rows correctly say "window over". Making the window longer is an input
   (`InpNytWindowMin`, 5-480). It was **not changed**, because a threshold is never moved as a side
   effect. It is Shyam's call; 120 would end the window at 17:30 Poland.
2. **A real bug, fixed:** the metals file placed NY at a **typed `"16:30"` broker time**. The EU
   and the US change daylight saving on different Sundays. From 25 Oct to 1 Nov 2026 and from 14 to
   28 Mar 2027, NY opens at **15:30** broker time, so the typed time would put the NY trap window,
   the pre-NY range, the NY row and the alert an hour late. The crypto / forex files already used
   an AUTO clock; now metals does too (below).
3. The broker clock of the screenshots is UTC+3 (the crypto panel's clock row, proven by two
   witnesses). Poland is UTC+2 until 25 Oct.

### What changed in `NRTR_BOSS_LearningPanel.mq5` (1.07 -> 1.08; line numbers in the NEW file)

| Lines | What |
|---|---|
| 108-125, 127 | Header paragraph, `#property version "1.08"`. |
| 2667-2720 | **NY clock:** `NbCivil` and `NbUsDst` (the same text as the crypto / forex session clock). `NbNytOpenOf`: AUTO = 09:30 New York (13:30 UTC in US summer, 14:30 in winter) + the broker offset; TYPED = `InpNyOpenTime`. `NbNytCfg` gains `autoClock` and `offset`. `NbRunNyt` takes the open from it. |
| 3154 | `InpNyAutoClock = true` (new). `InpNyOpenTime` is now used only when it is false. |
| 5472 on | `NbNytConfig`: AUTO takes the offset only when the two witnesses agree (`NbFqWitnessClock`, server vs PC GMT, on a half hour). Otherwise there is **no clock**: the NY trap is OFF and says "NY clock unknown - never guessed". |
| 3584-3640 | The main panel's **NY row and NY alert** use the same clock (`NbNyOpenToday`). The text format is unchanged, so in normal weeks the left box prints exactly what it did (dump test). |
| 2889-3033 | **`NB_PW`**, the counter-trend watch engine: identical text to crypto / forex. |
| 3035-3115 | **`NbMarketState`** (engine): the MARKET STATE, see below. |
| 3121, 3184-3188 | `NB_BR_VERSION "1.08"`. Inputs `InpBridgeOn`, `InpBridgeCandles`, `InpBridgeEverySec`, `InpPwShow` (same as the twins). |
| 4259 | **Left box:** the MARKET chip on the title line (right aligned) + a detail line on the symbol line. These are the **only two new labels in the left box**; nothing else moved (dump test excludes exactly `P_mk` and `P_mkd`). |
| 6216-6410 | NY strip: the header also shows the window on **your PC's clock** ("NY TRAP 16:30-18:00 (PC 15:30-17:00)"). Two new rows: the COUNTER-TREND WATCH and its record + the bridge status. `NbNytVerdict` is the verdict row as a function, so the strip and the bridge file say the same words. |
| 6413-6782 | **`NB_BR`**, the data bridge: the crypto block with exactly three named adapters (`NbBrLabel`, `NbBrSigKind`, and the `market_state` field). `tests/check_bridge_blocks.py` enforces that. |
| 6790-6921 | Metals adapters: `NbPwRecompute`. `NbBrNy`: clock, verdict, window, phase, pre-NY H/L, NY H/L, and SELL / BUY with state, why, entry (flagged as reference before the trigger), SL, TP1, TP2, in_play. `NbMarketChip`, `NbBrMarketState`. |

### MARKET STATE (the left box) - a description, never a signal

It uses only what the panel already computes: the 15M boss mode, the 5M NRTR, the distance of the
15M close from EMA200 in 15M ATRs, and the NRTR flips and high-low width over the last 24 closed
15M bars (6 h). There is no new indicator.

| State | Rule |
|---|---|
| SUPER BULLISH | 15M BUY MODE + 5M bullish + >= 1.5 ATR above EMA200 + no 15M NRTR flip in 6 h |
| TREND UP | 15M BUY MODE, anything less |
| CHOP | boss WAIT + >= 3 NRTR flips in 6 h |
| RANGE | boss WAIT + 6 h high-low width <= 4 ATR |
| TRANSITION | boss WAIT, neither |
| TREND DOWN / SUPER BEARISH | the mirror |

The thresholds (1.5 ATR, 3 flips, 4 ATR, 6 h) describe the chart; **no backtest has shown an edge
for them**. The state never changes CLICK / WAIT. Stale data shows `MARKET ---`, never the last
known state.

### Data bridge on metals

It is the same file as crypto / forex (`bridge/README.md`), with the metals NY trap layer inside
`mt5_signal.ny` (both sides with prices, the verdict, the clock used) and `mt5_signal.market_state`.
The Telegram message now also prints the MARKET line, the NY window and the verdict
("NY TRAP vs 15M BOSS: ..."), and every NY trap side with its state and why.

**Crypto and forex files: not changed** (Shyam: "keep crypto like this"; `git diff` = 0 lines).

### Tests (`./run_tests.sh`, 2026-09-27)

* `tests/test_nyt.cpp` default build: **99 checks, 0 failed.**
  * **N8** checks the AUTO clock on 5 dates: 28 Sep 2026 16:30, **26 Oct 2026 15:30**, 2 Nov 2026
    16:30, **15 Mar 2027 15:30**, 29 Mar 2027 16:30. It also checks that the typed clock stays at
    16:30, and that the trap engine opens its window at 15:30 on 26 Oct.
  * **N9** checks the market state on hand-built 15M bars: every state, and unknown without EMA.
  * **Y5**: the chip equals an independent engine run over 131 moments per metal, and stale data
    gives no state.
  * **Y6** runs the whole indicator on 27 Oct 2026 (broker UTC+2, PC in Poland UTC+1): the main
    panel says NY OPEN 15:30, the NY rows say 15:30-17:00 (PC 14:30-16:00), and the bridge names
    its clock. When the witnesses disagree by 7 minutes, the NY trap is OFF and the NY row says
    NY CLOCK UNKNOWN.
* `tests/test_bridge.cpp` on XAUUSD and XAGUSD: **50 checks each** (the twins' B-tests plus B7, a
  moment in the NY window).
* `tests/test_bridge_py.py` (gold, silver, crypto, forex): **10 of 10**. The metals NY sides,
  pre-NY range and market state equal the independent engine; stale data gives no state and no NY
  prices; the metals Telegram message layout is checked.
* `tests/check_bridge_blocks.py`: `NB_PW` is identical in all three files; `NB_BR` metals = crypto
  + the three adapters.
* All earlier suites PASS. The left box is identical to v1.04 except the two MARKET labels (53
  scenarios).
* Mutations (`python3 tests/mutate_fq.py`): **61 planted, 61 caught.** That includes 9 new for
  metals: AUTO ignores US DST, the typed time used with AUTO on, the offset assumed when the
  witnesses disagree, the main panel's NY row on the typed time, the PC time shifted the wrong
  way, SUPER without the no-flip rule, CHOP never named, the market state from stale data, the NY
  SL written from TP1.
  * The full run gave 58 of 61. None of the three was a test gap:
    * M39 and M40 pointed at verdict code that moved into `NbNytVerdict`;
    * M54 did not compile (an unused variable under `-Werror`), which the harness correctly calls
      NOT RUNNABLE, not caught.
  * All three were re-anchored and re-run (`python3 tests/mutate_fq.py 39 40 54`): CAUGHT.

## v1.07 twins (2026-09-27): DATA BRIDGE to Telegram + COUNTER-TREND WATCH (crypto and forex; metals next)

### What was asked (Shyam, 2026-09-27)

A v18 council BUY on BITSTAMP:BTCUSD (entry 84508.1, SL 84266.4, TP 84713.2, grade A) came while
the crypto panel stayed silent. 1H, 4H, 15M and 5M were all bearish, and BTC pulled up from 84580
to 85156 in under 15 minutes. "When all bearish signal come pull up sell but we miss pull up buy
position." Then, quoted from another reviewer: "the next developer change should be the data
bridge, not another redesign". All three files should send the last 18 closed 5M and 15M candles,
the forming candle, NRTR, ATR, EMA where applicable, structure, the signal/state and the NY trap,
with **the MT5 conclusion separate from the raw data**, "for I will entry in telegram". "Do now
crypto, so confirm, then metal."

Decisions Shyam made when asked (2026-09-27):
* **Destination:** Telegram chat only; he enters trades by hand. Nothing goes to the v18 brain or
  the v7 bot.
* **Transport:** the indicator writes a JSON file, and a separate Python sender posts it. The token
  lives in an environment variable.
* **When:** only on change. The file updates every closed 5M candle; Telegram gets a message when
  the conclusion changes.
* **The missed pull-up BUY:** a WATCH row, recorded as a hypothesis. It is not a signal.

### Why the BTC BUY was not caught (and why it still is not a CLICK)

The panel's rule: BUY only when the 15M boss is in BUY MODE. With every timeframe bearish, a BUY
is counter-trend by definition, so the panel waited **by design**. Counter-trend entries are the #1
documented loss driver in this system (the SELL bleed, -406). This one BUY probably won (TP 84713
was below the 85156 high), but that is n = 1. The Evidence Law calls n < 20 luck. So v1.07 records
every such pull-up as a **WATCH**, with its reference prices and outcome, and lets the count decide.
The fixture's watch record (23 cases, 2 TP1 / 6 SL / 15 expired, -4R) is random synthetic data and
says nothing about BTC.

### What changed (crypto and forex are twins: same text, `tests/make_twin.py` regenerates forex)

| Lines (crypto file) | What |
|---|---|
| 102-114 | Header paragraph for v1.07. Line 29-30: "no network" now says the file is written for a separate sender. |
| 117 | `#property version "1.07"`. |
| 169 | `NB_BR_VERSION "1.07"` (written into the file). |
| 2855-2999 | **Engine block `NB_PW`:** `NbRunPw` (the WATCH on closed bars only), `NbPwStats`, `NbPwStatusText`. The rule, frozen: the 15M boss is in full SELL MODE (BUY MODE) and the 5M NRTR flips up (down) on a closed bar. Ref entry = that close. Ref SL = the new 5M NRTR stop -/+ `InpSlBufferAtr` x 5M ATR, rounded outward. Ref TP1 = `InpTp1R` x risk. Later bars: SL first, then TP1, else EXPIRED after `InpSignalValidBars`. One watch at a time. |
| 3011 | Prefix `NBSP_W_` (the watch strip). |
| 3077-3081 | Inputs: `InpBridgeOn` true, `InpBridgeCandles` 18 (5-100), `InpBridgeEverySec` 10 (1-3600), `InpPwShow` true. |
| 3151-3161 | Globals (watch records, bridge status / last write / key). |
| 3195-3204 | Prototypes. |
| 3245 | `OnInit` range check for the bridge inputs. |
| 3401, 3573 | Calls: `NbBridgeUpdate` + `NbPwDrawStrip` every refresh, `NbPwRecompute` after each recompute. A failed recompute clears the watch. |
| 5484-5853 | **Bridge block `NB_BR`** (made to be shared with the metals file next): JSON helpers, `NbBrTf` (raw + indicators of one timeframe via `CopyRates`, forming candle separate), `NbBrBuild` (the whole file, conclusion last and apart), `NbBrWrite` (temp file + atomic rename, `FILE_COMMON`), `NbBridgeUpdate` (on each new closed 5M bar, else every `InpBridgeEverySec` s). |
| 5861-6023 | Twin terminal code: `NbPwRecompute`, `NbPwDrawStrip` (two rows on top of the table), bridge adapters `NbBrSource` / `NbBrMarket` / `NbBrNy` / `NbBrNyKey`. |

New files:
* `bridge/nrtr_telegram_sender.py`: standard library only. It reads the folder, posts one message
  per `change_key` change (or one DATA STALE), redacts the token from every output line, and does
  not remember a failed send (so it is resent). It has `--dry-run`, `--once` and `--test-message`.
* `bridge/README.md`: setup in six steps.

The main panel of both twins is still byte-identical to v1.04 (53 scenarios each, bridge
running). The 5-question blocks are still identical in all three files. The metals file is not
touched by this change.

### Safety

* **File access**, which the indicator never had before, is allowed only inside the `NB_BR` block.
  Only `FileOpen` (write, `FILE_COMMON`), `FileWriteString`, `FileClose` and `FileMove` may be
  used, and only on paths declared as `"NRTR_BRIDGE\\" + g_sym + ".json" / ".tmp"`.
  `tests/check_safety.py` enforces this. `tests/check_safety_neg.py` plants 7 violations (a foreign
  folder, a READ, a file call outside the block, a delete, a WebRequest, an order, broken markers),
  and all 7 are rejected.
* No network, no order, no position change: the indicator writes a file. The sender only talks to
  `api.telegram.org`, and its test proves it (it fails the test on any other URL).

### Tests

* `tests/test_bridge.cpp`, per twin: **48 checks, 0 failed** (crypto and forex).
  * P1-P5: the watch engine on hand-built bars with prices worked out by hand (BUY 101.00 / SL
    99.30 / TP1 102.70; SELL mirror; SL beats TP1 in one candle; expiry; no watch with the boss,
    with the boss in WAIT, or without a flip; one at a time; the forming bar; the stop on the
    wrong side; the record).
  * B1: the file name, folder, flags, ASCII and section order, and no conclusion inside the raw
    data.
  * B2: when it writes: timer, and a new bar within 10 s of the last write.
  * B2b: market closed: exactly 18 closed candles, forming null.
  * B3: stale data.
  * B4: a failing disk; an unsupported symbol.
  * B5: 160 moments, the strip docked on the table, the watch prices and record equal an
    independent engine run, an open watch never gives a CLICK, 63 characters.
  * B6: an open-watch moment written out for the Python check.
* `tests/test_bridge_py.py`: **9 of 9**.
  * The file is compared number by number with an EXPECTED file built from the raw simulated
    history and an independent engine run: the last 18 closed bars oldest first, the forming bar
    never in "closed", indicators per candle, no invented 5M EMA, the watch.
  * The sender: layout (conclusion first), at most 4096 characters, one message per change,
    stale once, broken files skipped, dry run, the token never printed, a failed send not
    remembered, no credentials = no run.
* Mutations (`python3 tests/mutate_fq.py`): **52 planted, 52 caught.** That includes 10 new for the
  bridge and the watch: fires WITH the boss, the forming bar evaluated, TP1 before SL, a watch
  shown as CLICK, the forming candle counted as closed, 19 candles, stale written as live, no
  rewrite on a new bar, indicators from the wrong candle, the strip not docked.
  * The first run of the ten found **two real test gaps**. M47 (19 candles) only shows when there
    is no forming candle (market closed), which no test covered; B2b now does. M49 (no rewrite on
    a new bar) hid behind the 10 s timer; B2 now closes a bar within 10 s of the last write.
  * In the full run M11 was NOT RUNNABLE: the strip copies the table's "step aside" code, so its
    anchor matched twice. The anchor was made unique and M11 re-run: CAUGHT.

## v1.07 metals (2026-09-27): clean screen - NY trap on the bottom-middle table, PRE-NY / NY lines

### What was asked (Shyam, 2026-09-27, with an MT5 screenshot of XAUUSD M5 on v1.06)

"Full block screen. You have [the] bottom middle box, you can add this NY entry, SL, TP1 and TP2, no
need more information, is that right? Make line similar how you do in crypto file - line NY low
high, pre NY low high. Line NY trap buy or sell. So screen will keep more clean. MT5 top right only
see current price."

### What the screenshot showed

* The v1.06 DECISION LADDER box (top right, 31 rows) sat over MT5's price scale. The current price
  (4286.10) was hidden behind it. That is a real usability bug, whatever the tests said: the tests
  checked that the box stayed clear of the main panel and the table, but never that MT5's own price
  scale stayed visible.
* The data was stale in that screenshot (23:56, the metals daily break): every panel said NO TRADE /
  DATA STALE. That is correct behaviour.

### Answer to "is that right?"

Yes. The bottom-middle table is the place for the pending prices, and the NY trap belongs next to
it. The main panel on the left and the table in the middle already carry the 15M boss, the 5M
timing, CLICK BUY / SELL, the pending plan and the position. The ladder repeated them in a third
place. So v1.07:

1. **Turns the big ladder box OFF by default** (`InpLadderShow = false`). Nothing of this indicator
   sits in the top-right corner any more, so MT5's price scale shows the current price. The ladder
   still exists: set it to `true` if you want it. It is still tested (step 5d2).
2. **Docks four NY rows on TOP of the bottom-middle table**, with the same x and width, so it reads
   as one box. `NBLP_Y_*`, switch `InpNyStripShow`:
   ```
   NY TRAP  16:30-18:00                PRE-NY H 4315.82  L 4277.94     NY H <high>  L <low>
   SELL  INVALID - NY window over ...  ref E 4315.82   SL 4322.33   TP1 4309.31   TP2 4302.80
   BUY   INVALID - SL hit              ENTRY 4280.05   SL 4272.85   TP1 4287.25   TP2 4294.45
   NY TRAP: nothing in play  -  15M BOSS WAIT                  you place it - NOTHING IS SENT
   ```
   (Layout only. The prices are the ones the v1.06 ladder showed in the screenshot. With the data
   stale, as it was there, v1.07 shows "---" in every row instead.)
   `ref E` = the reference entry (the range level) before the trigger. `ENTRY` = the real 5M close
   once TRIGGERED. The verdict row keeps the hierarchy. Against the 15M boss it reads **CONFLICT -
   NO TRADE**. With the boss in WAIT it reads NO TRADE. A swept trap that has not triggered reads
   "wait for the 5M close back inside". Only a triggered trap WITH the boss reads "... VALID - CLICK
   ...". Stale data shows no state and no price at all ("---", NO TRADE - DATA STALE).
3. **Draws the lines the way the crypto file does:**
   * `PRE-NY HIGH 4315.82  =  NY TRAP SELL <state>` and `PRE-NY LOW ...  =  NY TRAP BUY <state>`,
     dash-dot purple, from the range start to the end of the NY window. These ARE the trap lines, so
     the trap state is written on them instead of drawing a second line at the same price;
   * `NY HIGH` / `NY LOW`: blue dotted lines at the high and low of the CLOSED 5M bars inside the NY
     window so far;
   * SL / TP1 / TP2 lines of a side **only while it is swept (VALID, dashed "(ref)") or in play
     (TRIGGERED)**, plus a solid ENTRY line only in play. A WAIT or INVALID side draws nothing extra.
     v1.06 drew all eight lines all day.

### Every change to `NRTR_BOSS_LearningPanel.mq5` (1.06 -> 1.07; line numbers in the NEW file)

| Lines | What |
|---|---|
| 99-108 | Header paragraph for v1.07. |
| 110 | `#property version "1.07"`. |
| 2827 | New prefix `NBLP_Y_` (the NY rows). |
| 2885-2886 | `InpLadderShow` default `true` -> **`false`**. New `InpNyStripShow = true`. |
| 5170 | `NbNytDrawSide`: lines only while VALID or in play; the ENTRY line only in play. |
| 5198 | New `NbNytSessionHL`: high / low of the closed 5M bars inside the NY window. |
| 5223 | `NbNytDrawChart`: PRE-NY HIGH / LOW with the trap state in the text, NY HIGH / LOW, and it also deletes the NY rows so they are recreated after the markers (drawn on top). |
| 5278-5319 | `NbORect` / `NbOLabel`: the old ladder helpers made prefix-generic; `NbLRect` / `NbLLabel` now call them (identical objects). |
| 5812-5979 | New `NbYLabel`, `NbYSide`, `NbNyStripDraw`: the four NY rows. The position repeats the table's geometry (`NbFqDrawTable`, inside the shared block, which cannot change); test Y1 checks that the rows' bottom edge equals the table's top edge. |
| 3007, 3169, 3218 | Prototype and the two calls (refresh + chart resize), after the ladder. |

The engine (`NB_NYT` block), the main panel, the 5-question table, the NRTR maths, EMA200 and
structure code are unchanged. The main panel is still byte-identical to v1.04 (step 5c).

### Tests (`./run_tests.sh`, 2026-09-27)

* 5d, default view: **69 checks, 0 failed**.
  * N1-N7 engine. **N7 is new**: a close back inside with the body the wrong way, or a doji, is
    not a trigger. Mutation M23 escaped the first v1.06 run; this test closes that gap.
  * Y1-Y4 per metal:
    * Y1: no box in the top-right corner; the NY rows share the table's x and width and touch
      its top edge.
    * Y2: every 5th bar of 5 days. Rows and lines are compared with the engine and with NY H/L
      computed independently from the raw bars. PRE-NY lines carry the state. The side-line rule
      holds. Nothing is over 63 characters.
    * Y3: the verdict row, injected for swept / in play x BUY / SELL x boss BUY / SELL / WAIT
      (12 cases) plus "nothing in play".
    * Y4: 01:00 reopen not stale; with a dead feed there is no state and no price.
* 5d2, the ladder build (`InpLadderShow = true`): **77 checks, 0 failed**. L2 also checks now that
  "TIMING = CONFIRMED" appears exactly when the engine's closed-candle decision is BUY / SELL.
* 5e, simple view: **14 checks, 0 failed**. The NY rows move to the bottom when the table is hidden.
* All earlier suites PASS. All three "existing panel unchanged" dumps PASS (`NBLP_Y_` excluded like
  the other new prefixes).
* Mutations (`python3 tests/mutate_fq.py`): **42 planted, 42 caught**. That is 7 new for v1.07:
  ladder back on by default, NY rows not docked, the NY rows' stale gate removed, CONFLICT not shown,
  a swept trap shown as CLICK, SL/TP lines left after INVALID, NY H/L counting after the window.
  * The full run gave 40 of 42. The other two were harness problems, not test gaps, and both were
    fixed and re-run (`python3 tests/mutate_fq.py 22 36`, both CAUGHT):
    * M22's anchor now matched twice (the new NY rows start with the same line as the table's
      stale gate), so it was NOT RUNNABLE;
    * M36 switches the ladder on, which removed the anchor the harness uses to make the ladder
      build.
  * The harness now builds `test_nyt` twice for the metals file: the default view and the ladder
    build. It also takes mutation numbers as arguments.

## v1.06 metals (2026-09-27): NY TRAP layer + DECISION LADDER on the gold / silver panel

(v1.07 above turned the ladder box off by default and moved the NY trap onto the bottom-middle table.)

This is the full audit record of this change. Every claim below has a command that reproduces it
(`./run_tests.sh` steps 5d and 5e, and `python3 tests/mutate_fq.py`).

### What was asked (Shyam, 2026-09-27)

Keep the metals architecture. Do NOT replace the 15M Boss / 5M confirmation system, the custom
NRTR maths, EMA200, structure, or the S/R and liquidity logic. No new indicators. Then add:

1. an **NY trap layer** for gold and silver: NY TRAP BUY / NY TRAP SELL, each with entry, SL, TP1
   and TP2, states WAIT / VALID / TRIGGERED / INVALID, and lines on the chart. It is a separate
   layer and never silently overrides the 15M boss;
2. **timeframe clarity**: "15M = BOSS / DIRECTION" and "5M = ENTRY / SCALP TIMING". The forming
   candle may show "IF IT CLOSED NOW" only as a preview, never as a confirmed signal;
3. a **simple scalp display**: gold about 5-20, silver about 0.30-1.00, with no guarantee, and money
   taken from the broker's contract size, tick size and lot;
4. **one obvious action**: PENDING ORDER PLAN, BUY/SELL VALID - CLICK, or POSITION ACTIVE. The panel
   stays read only;
5. the **hierarchy** 15M boss -> 5M confirmation -> NY trap / pending -> BUY or SELL -> entry ->
   SL / TP, with "NY TRAP vs 15M BOSS = CONFLICT" when they disagree, never READY;
6. **tests on XAUUSD and XAGUSD separately**, covering ten points (table below).

### What changed in `NRTR_BOSS_LearningPanel.mq5` (1.05 -> 1.06; line numbers in the NEW file)

**Nothing that already existed was changed in behaviour.** The main panel, its chart objects,
buffers, alerts and log are byte-identical to the v1.04 baseline over 53 scenarios (step 5c, test
below). The 5-question table is unchanged, and its shared blocks are still byte-identical to the
twins (step 6b). The NRTR maths, EMA200 and structure code were not touched.

| Lines | What |
|---|---|
| 81-98 | Header paragraph for v1.06. |
| 101 | `#property version "1.06"`. |
| 2380-2804 | **New engine block `NB_NYT`** (between `NB_FQ_END` and `NB_ENGINE_END`; metals only, so it is not part of the twin check). |
| 2425 / 2442 / 2459 | `NbNytCfg` (the settings), `NbNytSide` (one side: state, why, level, sweep, entry, SL, TP1, TP2, risk, estimate, trigger / outcome bar), `NbNytBar` (per 5M bar: phase, session id, range H/L/count, both sides, forming flag). |
| 2511 | `NbNytRefs`: reference prices while WAIT / VALID. Entry ref = the range level. SL = the sweep extreme + buffer, or the level + `InpNytRefAtr` x ATR before any sweep. TP = R multiples. Marked `estimate`. |
| 2530 | `NbNytStep`: one closed bar for one side. Triggered: SL first (the tick order inside a candle is unknown, so SL wins a candle that touches both), then TP1, then expiry after 6 bars. Untriggered: BEFORE/PRE = WAIT; NY window without a range = INVALID (NO RANGE); a wick beyond the range = VALID (the sweep extreme is recorded); a CLOSED candle back inside by `confirmAtr` x ATR **with a body in the trap's direction** = TRIGGERED, entry = that close, SL = sweep +/- `slBufAtr` x `slBufMult` x ATR (rounded outward on the tick grid), TP1/TP2 = `InpTp1R`/`InpTp2R` x risk. After the window = INVALID (OVER). |
| 2638 | `NbRunNyt`: all 5M bars. Session day = UTC date of the bar in the server clock, NY open = `InpNyOpenTime`, range = `InpNytRangeHours` before it (needs `InpNytMinBars` bars), window = `InpNytWindowMin`. Weekend or no NY time = OFF, never guessed. **The forming bar is never evaluated** (`nEvalNy`); it carries the last closed answer. One trap per side per day. |
| 2800 | `NbNytLive`: TRIGGERED and still ACTIVE (not TP1 / SL / expired). |
| 2816-2817 | New prefixes `NBLP_N_` (trap lines) and `NBLP_L_` (ladder). |
| 2874 on | New input group "NY TRAP + DECISION LADDER": `InpLadderShow`, `InpNytDraw`, `InpNytRangeHours` 4, `InpNytWindowMin` 90, `InpNytMinBars` 12, `InpNytRefAtr` 1.0, scalp refs gold 5.00 / 20.00 and silver 0.30 / 1.00, `InpSimpleView` false. |
| 2955 | Globals `g_N`, `g_nt[]`. |
| 3041 | `OnInit` refuses an NY open earlier than the range hours (the range would cross midnight). |
| 3151, 3194 | `InpSimpleView`: hides the main panel and the table and keeps the ladder and the chart. Default off, so the existing view is unchanged. |
| 2993-2995, 3156, 3204, 3363 | Recompute and draw calls. On a failed recompute the trap state and its lines are cleared. |
| 5096 | `NbNytConfig`: silver uses the SAME wider stop and stronger confirmation as the 5Q table (`NbFqAsset`), and the broker's tick size and digits. |
| 5117-5258 | `NbNytRecompute`, `NbNytDrawSide`, `NbNytDrawChart`: range H/L lines, and per side ENTRY / SL / TP1 / TP2 lines labelled `NY TRAP SELL  <STATE>`. Solid = triggered, dashed = reference. Trigger markers are drawn in the background. |
| 5260 | `NbMoneyFor`: \|move\| / tick size x tick value x lots. These are the broker's own figures, read from `SymbolInfo`. |
| 5268 | `NbLTrapRows`: the two trap rows of the ladder. |
| 5292 | `NbLadderDraw`: the DECISION LADDER, top right (top left when the main panel is on the right). |

### The DECISION LADDER, exactly (read top to bottom)

```
1  15M = BOSS / DIRECTION        NRTR, EMA200, HH/HL or LH/LL -> BOSS = BUY / SELL MODE / WAIT
2  5M = ENTRY / SCALP TIMING     last CLOSED 5M candle, NRTR -> TIMING = CONFIRMED / WAIT: reason
   FORMING 5M - PREVIEW ONLY, NOT A SIGNAL:  IF IT CLOSED NOW: BULLISH / BEARISH BODY
3  NY TRAP / PENDING LOCATION    NY window, range H/L; NY TRAP SELL / BUY rows with state + prices
   NY TRAP vs 15M BOSS = CONFLICT | ... AGREES WITH THE 15M BOSS | ... 15M BOSS NOT IN MODE
   PENDING PLAN: BUY LIMIT <price> (5-question READY) | none
4  ACTION (exactly one)          + TYPE / ENTRY / SL / TP1 / TP2 / R:R / LOTS, scalp reference
```

The action has exactly one value. The first rule that matches wins:

1. unsupported symbol -> GOLD / SILVER ONLY;
2. no data -> WAIT;
3. **a position on this symbol -> POSITION ACTIVE**: direction, volume, entry, SL and TP with the
   distance in price AND money, and EXIT / PROTECT / HOLD from the 15M boss. READ ONLY, nothing is
   changed. A position is always shown first, even when the data is stale;
4. stale data -> **NO TRADE**;
5. the main engine is BUY/SELL (15M boss + 5M confirmed close) -> **BUY VALID - CLICK BUY** with the
   engine's own entry / SL / TP1 / TP2 / lots;
6. a live NY trap. If the boss agrees -> **BUY/SELL VALID - CLICK**, source "NY TRAP ... + 15M BOSS".
   If the boss is opposite -> **NY TRAP vs 15M BOSS = CONFLICT**, "NO TRADE - THE LAYERS DISAGREE".
   If the boss is in WAIT -> WAIT, "NO TRADE UNTIL THE 15M BOSS AGREES";
7. a READY 5-question plan. If the boss agrees -> **PENDING ORDER PLAN**: BUY/SELL LIMIT, entry,
   SL, TP1, TP2, R:R, "PLACE MANUALLY - NOTHING IS SENT". If the boss is opposite -> CONFLICT;
8. otherwise WAIT, with the 15M or 5M reason.

**Why only LIMIT and never STOP:** the only pending plan in this file is the 5-question retest of a
level, and that is a limit order by construction. A BUY STOP / SELL STOP plan would need a new rule
(a breakout entry), and the Evidence Law says that is not added without data. It is not built.

### The ten verification points

Runs are separate for XAUUSD (tick 0.01, 2 digits, tick value 1, contract 100) and XAGUSD (tick 0.001,
3 digits, tick value 5, contract 5000). Source: `tests/test_nyt.cpp`, `./run_tests.sh` steps 5d/5e.

| # | Point | Test | Result |
|---|---|---|---|
| 1 | 15M is always the boss | L2: every hour of 5 days (120 moments per metal). Step 1 always shows the engine's 15M mode, and no BUY/SELL action ever appears against or without it. L5: trap vs boss injected for all 6 combinations | PASS |
| 2 | 5M is always the timing layer | L2: a CLICK from the main engine only with a confirmed closed 5M; L3: its prices are the engine's | PASS |
| 3 | forming candle never confirms | N6 (engine: a trigger candle still forming stays VALID, and turns TRIGGERED only once closed). L6 (indicator: a huge forming candle changes only the PREVIEW row; action, 5M rows and both trap states are unchanged) | PASS |
| 4 | NY trap lines correct | N1-N5 (exact prices by hand); L4: every 7th bar, the ENTRY / SL / TP1 / TP2 lines are compared with the engine and the states named, and the fixture shows all four states | PASS |
| 5 | pending prices correct | L2 (PENDING ORDER PLAN only with the boss) + the 5Q suites (Q-tests: plan prices) | PASS |
| 6 | SL/TP on the broker's tick grid / digits | L3, L4 `onGrid`; SL rounded outward (mutation M-series below) | PASS |
| 7 | gold and silver use their own parameters | N4 (silver stop x2, confirm +0.25 ATR); L8 (config, scalp ref, money from tick value, contract shown) | PASS |
| 8 | 01:00 metals reopen is not DATA STALE | L9: the 00:00-01:00 bars removed, now 01:12:07 -> LIVE, and the ladder is not NO TRADE; the last tick at 23:59 yesterday -> NO TRADE, DATA STALE | PASS |
| 9 | no order is ever sent | safety scan (step 1: no trade / network / file API in the source); the simulator has no trade API, so a call would not compile; L7: the position is unchanged after drawing | PASS |
| 10 | MetaEditor compilation | **NOT RUN HERE.** g++ -Werror surrogate compile of the whole file passes (step 3). Your F7 in MetaEditor is the real test | NOT TESTED |

### Tests (`./run_tests.sh`, 2026-09-27)

* 5d `tests/test_nyt.cpp`: **105 checks, 0 failed** (N1-N6 engine by hand, L1-L9 x XAUUSD and XAGUSD, L10).
* 5e the same test built with `InpSimpleView = true`: **12 checks, 0 failed** (main panel and table
  hidden, ladder drawn, still hidden after a refresh).
* All earlier suites still pass, and all three "existing panel unchanged" dumps PASS.
* `tests/mutate_fq.py` now also builds `test_nyt` for the metals file, and plants 13 new v1.06 mutations (35 in total). **First run: 33 of 35 caught.**
  M23 (a trigger without a body in the trap's direction) ESCAPED, a real test gap, closed in v1.07 by
  N7. M35 did not compile (it used `iClose`, which the simulator lacks), so it proved nothing and was
  replaced by a mutation that builds. The final run is recorded in TESTING.md.
* The harness had a weakness, now fixed: a mutation that did not compile used to count as CAUGHT.
  It now counts as NOT RUNNABLE, which is a failure.
* L5 was rewritten before commit. The first version only checked inside an `if` that the random
  fixture might never satisfy. It now injects the boss and the trap side and checks all six
  combinations on every run.

### Honest limits

* **The NY trap rule has no evidence yet.** It is the textbook "sweep of the pre-NY range, then close
  back inside" pattern, built so it can be journaled, not because it was validated. n = 0 on real
  data. Evidence Law: judge nothing before n >= 20, ~100 to decide. Treat every VALID - CLICK from
  the trap layer as a hypothesis.
* The BTC screenshot (v1.05 table: TP1 8 / SL 36) is a reminder that a clean-looking rule can have no
  edge. The same may be true here.
* The session day is the UTC date of the server clock. The range is the `InpNytRangeHours` hours
  before `InpNyOpenTime` in SERVER time. If your broker's server time is not what you typed, the
  window is wrong: check the NY line on the ladder against the chart.
* The scalp reference (5-20 / 0.30-1.00) is a display range from your message, not a tested target.
* The ladder's SCALP money is for 1.00 lot. Your size changes it linearly.
* MetaEditor F7 and a live chart are not run here.

## v1.06 twins + v1.05 metals (2026-09-27): screenshot fixes, and the table on the gold / silver panel

This is the full audit record of this change. Every claim below has a command that reproduces it.

### What was asked (Shyam, 2026-09-27, with an MT5 screenshot of BTCUSD M5)

"Do you think ok? Then update metal - NRTR_BOSS_LearningPanel. I use pending order also, I want
scalp gold and silver."

### What the screenshot showed (read before trusting anything else here)

1. **It compiled and ran in MT5.** This is the first real-terminal evidence for v1.05.
2. **The table's own history says the plan lost on that BTC chart:** `106 plans - TP1 8 / SL 36 /
   not filled 62`. 44 plans were filled, and 36 of them hit SL. That is above the n >= 20 floor, so
   it is evidence, not luck. **Do not trade this rule on BTC as it stands.** The table was built to
   produce exactly this kind of answer, and "no edge" is a valid result. v1.06 adds **NET R** to that
   row so the sign is visible at a glance.
3. **MT5 cuts object text at 63 characters.** The screenshot shows `... ran to TP1 wi`,
   `... not filled 62` (the rest missing) and `... typed by you. A`. The simulator had no such limit, so
   no test could see it. **This was a real bug in v1.05**, and it is now tested (Q9).
4. **Chart markers were drawn over the tables** (`▲ BUY` over row 4 of the new table,
   `PLAN BUY (SWEEP)` over the main panel's LIVE BOX), and `LOTS 1.0%` overlapped its value.
5. `SKIP - NO MAPPED TARGET BEYOND - REWARD UNKNOWN` was correct. Price was above every mapped
   level, so there was no target, and the table refused to guess one.

### What changed

**Twins `NRTR_BOSS_Crypto_NYTrap.mq5` / `NRTR_BOSS_Forex_NYTrap.mq5`, v1.05 → v1.06**

* Every table and chart label is now at or under 63 characters. Long rows became two labels (a left
  half and a right half at a fixed x). NEXT now takes two lines. Level names shorten to codes when
  long (`NbLvName`, `NbLvTag`: at most two codes plus a count, strongest source first).
* Chart texts of the table's drawing are drawn in the **background** (`NbFText` sets
  `OBJPROP_BACK`), so they never cover a panel.
* `NbFqDrawChart` deletes the table's objects after redrawing the markers, and the same refresh
  recreates them. The table is therefore created **after** the main panel's chart markers and drawn
  on top of them (MT5 draws later objects above earlier ones; tested with a creation counter in the
  simulator).
* The history row shows **NET R** (TP1 = +its R, SL = -1, not filled = 0), coloured once n >= 20.
* `LOTS` key shortened; the value reads `0.20   (7.74 USD = 1.0%)`.
* Engine: two per-asset settings in `NbFqCfg`, **neutral in the twins** (`slBufMult` 1.0, `confirmAtr`
  0.0). They are proven neutral: the synthetic run still makes exactly the same 53 plans.
* **Code organisation:** the engine part is now between `//=== NB_FQ_BEGIN ===` and
  `//=== NB_FQ_END ===`, and the terminal part between `//=== NB_FQT_BEGIN ===` and
  `//=== NB_FQT_END ===`. Both blocks are **byte-identical in all three files**
  (`tests/check_fq_blocks.py`). Only five small adapters per file differ: `NbFqLabel`,
  `NbFqOnlyText`, `NbFqAccent`, `NbFqClock` and `NbFqAsset`.

**Metals `NRTR_BOSS_LearningPanel.mq5`, v1.04 → v1.05 (new: the five-question table)**

* The same table and the same big support / resistance lines as the twins (the same two blocks,
  byte for byte), at the bottom middle. **The existing gold panel is unchanged.** The v1.04 file
  from git and this file give byte-identical objects, buffers, alerts and log lines over 53 scenarios
  (16431 object records).
* **Pending orders:** READY = a BUY LIMIT / SELL LIMIT at the level (the retest), exactly as in the
  twins. SL goes beyond the structure, TP1 / TP2 are the next mapped levels, and lots come from the SL
  distance.
* **Scalping:** the timing is the 5M chart with the 15M as the map, the same as the twins.
* **Gold vs silver** (from your framework: "silver is more explosive and prone to false breaks,
  so require stronger confirmation and/or wider volatility-adjusted stops"):
  * GOLD: the plain rules.
  * SILVER: SL buffer x `InpFqSilverSlMult` (default **2.0**), and the confirmation close (and a
    breakout close) must pass the level / trigger by `InpFqSilverConfirmAtr` x 5M ATR (default
    **0.25**). The table's footer states which setting is in force.
  * These two numbers are **explicit choices, not validated values.** Change them only with evidence.
* **Clock:** this file has no session clock of its own, so Asia / London use the broker offset
  only when two witnesses agree (`NbFqWitnessClock`: server vs PC GMT, on a half hour within 5 min).
  Otherwise those two levels are not shown. The day levels and swings always work.
* The metals daily break (00:00-01:00 server) and the weekend make the main panel's DATA CLOCK
  say STALE, and then the table says NO TRADE.

### Every change to the source files (line numbers in the NEW files)

`git diff 3f046ef -- <file> | grep '^-' | grep -v '^---'` prints only the `#property version` line
for all three files. Everything else is inserted.

| | Metals (`NRTR_BOSS_LearningPanel.mq5`) | Crypto (`..._Crypto_NYTrap.mq5`) |
|---|---|---|
| header comment | 69-80 | 82-100 (v1.05 + v1.06 paragraphs) |
| `#property version` | 83: `1.04` → `1.05` | 103: `1.04` → `1.06` |
| engine block `NB_FQ` | 1211-2360 (`NbRunFq` 1811) | 1689-2838 (`NbRunFq` 2289) |
| object prefixes | 2370-2371 (`NBLP_Q_`, `NBLP_F_`) | 2848-2849 (`NBSP_Q_`, `NBSP_F_`) |
| inputs (new group at the end) | 2414-2427 (incl. 2 silver inputs) | 2903-2914 |
| globals | 2490-2495 | 2977-2982 |
| prototypes | 2519-2528 | 3009-3018 |
| `OnInit` validation / init | 2558-2566 / 2632-2635 | 3051-3058 / 3122-3125 |
| `OnChartEvent`, `NbUpdate` | 2672, 2711 (`NbFqDrawTable();`) | 3160, 3199 |
| `NbRecompute` | 2856-2859, 2866-2867 | 3351-3354, 3365-3366 |
| adapters | 3845-3890 | 4547-4582 |
| terminal block `NB_FQT` | 3892-4583 (`NbFqDrawChart` 3981, `NbFqDrawTable` 4151) | 4584-5275 (4673, 4843) |

Forex = crypto (twin check: 5276 lines, 4 differ).

### Tests (`./run_tests.sh`, 2026-09-27)

```
existing suites (unchanged, all pass): gold 145 + 124, crypto 106 + 104, forex 104 + 103, safety x3
TWIN CHECK: PASS          FQ BLOCK CHECK: PASS (NB_FQ 1150 lines, NB_FQT 692 lines, identical x3)
FIVE-QUESTION ENGINE TESTS:    metals 106 / crypto 106 / forex 106 passed, 0 failed
FIVE-QUESTION INDICATOR TESTS: metals 122 / crypto 115 / forex 115 passed, 0 failed
EXISTING PANEL UNCHANGED:      gold 16431 / crypto 17596 / forex 17382 object records, 53 scenarios each
python3 tests/mutate_fq.py:    22 planted (17 crypto, 5 metals), 22 caught
MetaEditor F7: v1.05 twins compiled and ran in the user's MT5 (screenshot 2026-09-27); v1.06 / metals v1.05 NOT YET
```

New checks:
* **Q9:** every table and chart text over 78 chart moments (39 times x 2 chart widths; ~7000 texts) is at most 63 characters,
  counted in code points as MT5 does. Every chart text of the drawing is in the background. After
  the next closed candle, the table is created after the main panel's markers. **Mutation M17 first
  escaped:** Q9 only looked at startup, and the ordering bug appears at the next candle. Q9 was
  strengthened, and M17 is now caught.
* **Q10 (metals):** on a silver market the READY SL equals sweep extreme -/+ 0.10 x 5M ATR x 2.0, the
  table shows it, and the footer states the silver settings. On gold there is no silver note.
* **Q3:** the 15M map row shows the engine's PDH, Asia and London values (catches a guessed clock:
  M20).
* **F19:** the silver options change the answer exactly where they should (stop 99.52; a confirmation
  that needs +0.6 ATR stays SETTING UP; a stricter breakout is refused). Also covered: NET R
  arithmetic, the witness clock, and level tags.

Mutations added: M15 (a row over 63 characters), M16 (markers in the foreground), M17 (table not
recreated), M18 / M19 (silver stop / confirmation ignored), M20 (clock assumed instead of
witnessed), M21 (existing gold panel touched), M22 (metals stale gate removed). All caught.

### Found, NOT changed (the existing main panel; your decision)

These **existing** main-panel labels are longer than 63 characters, so MT5 cuts them today (measured
from the simulator dump):

| File | Label | Length | Text starts |
|---|---|---|---|
| all | `g1` ... `g4` (HOW TO READ) | 79-90 | `NRTR CHANNEL: thick stop line ...`, `ZIGZAG (blue) ...`, `EMA200 ...`, `ARROW = NRTR flip ...` |
| all | `hb` (LIVE BOX header) | 64 | `LIVE BOX  -  BOTH SIDES FROM THE SAME RULES  -  THE GATE DECIDES` |
| all | `vd6` (STALE THRESHOLD) | 64 | `tick > 120s  or  forming bar > 2 bars old ...` |
| twins | `g5`, `f1` | 97, 75 | `NY TRAP (purple) ...`, `Learning tool. Aligned conditions ...` |
| twins | `vpv2` (preview line 2) | up to 65 | `price 65728.41 is above the 5M stop ...` |

You asked not to change the existing panel, so they are left as they are. Fixing them means
shortening those strings. Say the word and it will be a separate, tested change.

### Honest limits (in addition to the v1.05 list below)

* The BTC count in the screenshot (8 TP1 / 36 SL) is the only real-market evidence so far, and it
  is negative. Gold and silver have no count yet. Treat the table as a counter until the metals
  history row shows n >= 20 with a positive NET R, and then check it again at ~100.
* Do not tune the rules to make those 10 days look good. That is the "best of N" trap. A changed
  rule is a new version, and it gets counted from zero.
* The silver multipliers (2.0 / 0.25) are judgement defaults from the framework, not fitted values.
* Draw order: MT5 draws objects in creation order, and the simulator checks the creation order.
  Please confirm on your chart that no marker covers the tables.

---

## v1.05 (2026-09-26): FIVE-QUESTION PLAN table for the crypto (and forex) twin

(Line numbers in this section refer to commit `86a8ee2`; v1.06 above moved them.)

This is the full audit record of this change. Every edit to the `.mq5` is listed below with its
line numbers, and every claim has a command that reproduces it. Nothing here was checked in
MetaEditor or on a live MT5 chart (see [Not verified](#not-verified)).

### What was asked (Shyam, 2026-09-26, paraphrased)

* A **new table at the bottom middle** of the chart. **Do not change the existing panel.**
* It answers the "preferred framework" questions: 15M structure (HH/HL or LH/LL), location at
  a meaningful level (previous day high/low, Asia high/low, London high/low, major S/R), a
  liquidity sweep, confirmation (a structure break), and at least ~1.5R to the next level.
  If one of them is badly missing, NO TRADE. Pending orders rather than chasing. SL goes
  beyond the structure, not a fixed number of points. Target = the next level. It ends in
  a READY / NO TRADE line with BUY LIMIT, SL, TP1, TP2 and R:R.
* **Big support / resistance lines** that a beginner can understand, showing **breakout /
  breakdown** and **possible BUY / SELL**, drawn **in advance** (before price gets there,
  not after the move).
* **No fake tests.** Write down every change so Fable 5 can audit it.

### The answer to "draw in advance, is that a good idea?"

Yes, for the parts that can honestly be known in advance:

* **Levels are known before price arrives.** Yesterday's high/low, the Asia and London ranges
  and confirmed 15M swings exist before the market returns to them. The S/R lines and zones
  are drawn from these and run into the future (the zones reach 6 h past the last candle, the
  lines continue to the right edge).
* **The plan is a pending order.** READY means you type a BUY LIMIT / SELL LIMIT at the level
  *before* price comes back to it (the retest). That is the "in advance" part, and it is
  what "use pending orders rather than chasing" means.
* **Direction is not predicted.** "Possible BUY" is always a condition written in words: *"5M
  close ABOVE = BREAKOUT → possible BUY on the retest"*, *"sweep below + 5M close back ABOVE =
  possible BUY"*. Drawing an arrow before the candle closes would be a guess that repaints,
  so the file does not do it.

### Why the forex file changed too

`NRTR_BOSS_Crypto_NYTrap.mq5` and `NRTR_BOSS_Forex_NYTrap.mq5` are **twins**. `tests/check_twins.py`
(written before this change) requires them to be the same text except the header filename
line, the three `#property description` lines and `#define NB_MARKET`. Editing only the crypto
file would break that rule, and weakening the check to let it pass is not acceptable. So the
forex file carries the identical v1.05 text. The gold panel `NRTR_BOSS_LearningPanel.mq5` was
**not touched**.

---

### The rules, exactly as implemented (frozen for v1.05)

The table is a **second, separate rule set**. It never reads or changes the main panel's
decision; it only prints the main panel's answer in one row, so any disagreement is visible.
It is evaluated on every **closed** 5M bar.

**Levels (the 15M map), known at the close of bar i:**

| Level | Definition | Needs |
|---|---|---|
| PDH / PDL | high / low of the latest **complete** broker day before bar i's day (server 00:00-24:00, the same day as MT5's D1 bar). A day with < 12 closed 5M bars is never used. | nothing |
| ASIA H / L | high / low of the latest **ended** UTC window `[InpFqAsiaStartUtc, InpFqAsiaEndUtc)` (default 00-07 UTC), >= 12 bars | the AUTO session clock (two witnesses) |
| LONDON H / L | same for `[InpFqLondonStartUtc, InpFqLondonEndUtc)` (default 07-12 UTC) | the AUTO session clock |
| 15M SWING H / L | the last 4 confirmed 15M swing highs and the last 4 lows (confirmed = `confirmIdx` <= the last closed 15M bar) | nothing |

Levels closer than `zone = InpFqZoneAtr x 15M ATR` (default 0.25 ATR) to the first member of
their group become **one** level. It is priced at the stronger source (day > London > Asia >
swing) and carries all source names. A running (unfinished) Asia or London window is **never**
a level. In MANUAL or UNKNOWN clock mode Asia/London are **not known** and the table says so,
because the UTC offset is never guessed.

**The five questions** (for a BUY; SELL is the exact mirror):

1. **TREND**: the 15M confirmed structure at the last closed 15M bar is BULL (last high HH and
   last low HL). BEAR = SELL side only. MIXED / NOT CONFIRMED = **NO TRADE**. No plan is ever
   made against the 15M structure.
2. **LOCATION**: a candidate exists at a level **below** the current close (support). Without
   a sweep or break, the location is reported as *AT SUPPORT* (close or low within `zone` of
   the nearest support), *AT THE BREAKOUT LINE* (close or high within `zone` of the nearest
   resistance) or *MIDDLE - NO ENTRY HERE*.
3. **LIQUIDITY**, one of two kinds:
   * **SWEEP**: inside the last `InpFqWindowBars` (12) closed 5M bars, a bar pierced the level
     (low < level) while the bar before it closed above the level, and the current close is back
     above it. The **earliest** unused pierce in the window starts the sweep, so a re-dip inside
     the same sweep never moves the stop up. Sweep extreme = the lowest low from the pierce to now.
   * **BREAKOUT**: the latest 5M close through the level from below (close > level, previous
     close <= level) with a bullish body, inside the window, and no close back below since.
4. **CONFIRMATION**:
   * SWEEP: a later 5M candle **closes above** max(high of the candle that made the sweep low,
     level), with a bullish body. Until then the status is **SETTING UP**.
   * BREAKOUT: the breakout close itself (a body close beyond, not a wick).
5. **REWARD**: entry = the level (the retest), SL = sweep low - 0.10 x 5M ATR (sweep) or the
   latest confirmed 5M swing low below the level - 0.10 x 5M ATR (breakout; none = SKIP, no
   stop). All prices are rounded outward to the symbol's tick. TP1 = the first mapped level
   above both `entry + zone` and the current close; TP2 = the next mapped level after TP1.
   `R = (TP1 - entry) / (entry - SL)` must be >= `InpFqMinRR` (1.5), otherwise **SKIP**. No
   level mapped above = the reward is **UNKNOWN**, which is a SKIP and never a YES.

All five YES = **READY**. The plan (entry, SL, TP1, TP2, R) is **frozen** at that close. Only
one plan is live at a time, and a new plan needs a newer event (pierce / breakout bar).

**What happens to a plan (recorded, never assumed):**

| Outcome | Rule |
|---|---|
| FILLED | a later closed 5M bar's low touches the limit. On the **fill candle only the SL is judged** (tick order unknown, so a TP1 touch there is not counted). |
| HIT SL | SL touched. If one candle touches SL and TP1, **SL wins** (the main panel's same-candle rule). |
| HIT TP1 | TP1 touched on a bar after the fill. |
| MISSED | TP1 reached before the limit filled (no chase). |
| EXPIRED | not filled within `InpFqValidBars` (12) closed 5M bars. |
| CANCELLED | the 15M structure stopped agreeing while the limit was pending. |
| TIMED OUT | filled, neither TP1 nor SL within 144 closed 5M bars (12 h). |

The table prints the last plan and the count of every outcome over the loaded history
(`n<20 = luck, ~100 to judge`).

**Freshness:** when the main panel's freshness witnesses say STALE, the table says
**NO TRADE - DATA STALE / MARKET CLOSED**, all answers become `---`, and the live plan lines
are removed from the chart. They come back by themselves when the data is live again.

---

### Every change to `NRTR_BOSS_Crypto_NYTrap.mq5` (line numbers in the NEW file)

The diff against v1.04 (`git diff 3f046ef -- NRTR_BOSS_Crypto_NYTrap.mq5`) is **1733 insertions
and 1 deletion** in git's count. The single deletion is the old `#property version "1.04"` line;
its replacement is one of the insertions. No other existing line was deleted or rewritten.

| # | New lines | Where | What |
|---|---|---|---|
| 1 | 82-94 | file header | v1.05 paragraph describing the table (comment only). |
| 2 | 97 | `#property version` | `"1.04"` → `"1.05"`. **The only changed line.** |
| 3 | 1682-2740 | engine block, before `//=== NB_ENGINE_END ===` | the whole v1.05 engine (pure functions, no terminal calls, compiled and run by the tests): defines `NB_LV_*`, `NB_FQ_*`, `NB_PK_*`, `NB_FW_*`, `NB_PO_*`; structs `NbFqCfg` (1761), `NbLv` (1776), `NbFqPlan` (1783), `NbFqBar` (1808); `NbFqReset` 1850, `NbFqCopy` 1882, `NbFqFromPlan` 1914, `NbFqNewPlan` 1934, `NbFqWindow` 1963, `NbFqSessions` 2012, `NbLvAdd` 2074, `NbFqLevels` 2090, `NbFqNearest` 2157, `NbLvBeyond` 2187, `NbFqCross` 2204, `NbFqTrack` 2222, **`NbRunFq` 2280** (the five questions per bar), `NbFqLevelsAt` 2562, `NbFqTally` 2578, and the text functions `NbLvSrcText` 2602, `NbLvSrcShort` 2626, `NbFqStatusText` 2650, `NbFqWhyText` 2663, `NbFqOutcomeText` 2684, `NbFqKindText` 2700, `NbFqHint` 2711, `NbFqHint2` 2729. |
| 4 | 2750-2751 | after `NB_PFX_C` | two new object prefixes: `NB_PFX_Q = "NBSP_Q_"` (table) and `NB_PFX_F = "NBSP_F_"` (its chart drawing). Both start with `NBSP_`, so the existing `OnDeinit` cleanup removes them. |
| 5 | 2805-2816 | after the last existing input | a new input group **at the end** (the existing input order is unchanged): `InpFqShow` true, `InpFqDraw` true, `InpFqZoneAtr` 0.25, `InpFqWindowBars` 12, `InpFqMinRR` 1.5, `InpFqValidBars` 12, `InpFqAsiaStartUtc` 0, `InpFqAsiaEndUtc` 7, `InpFqLondonStartUtc` 7, `InpFqLondonEndUtc` 12, `InpFqBottomY` 16. |
| 6 | 2879-2884 | after `g_swingDist` | globals `g_C`, `g_fq[]`, `g_fqPlans[]`, `g_nFqPlan`. |
| 7 | 2911-2920 | after the existing prototypes | prototypes of the new terminal functions (C++ needs them; MQL5 accepts them). |
| 8 | 2953-2960 | `OnInit`, after the existing input validation | range check of the new inputs → `INIT_PARAMETERS_INCORRECT` with its own message. |
| 9 | 3024-3027 | `OnInit`, after `g_swingDist = ...` | initial empty state + `NbFqConfig()`. |
| 10 | 3062 | `OnChartEvent` | `NbFqDrawTable();` after `NbDrawPanel();` (reposition on resize). |
| 11 | 3101 | `NbUpdate` | `NbFqDrawTable();` after `NbDrawPanel();` (every second). |
| 12 | 3253-3256 | `NbRecompute`, missing-data branch | clear the plan state and the `NBSP_F_` drawing. |
| 13 | 3267-3268 | `NbRecompute`, end | `NbFqRecompute(); NbFqDrawChart();` after the existing `NbDrawChart();`. |
| 14 | 4449-5057 | end of file, after `NbRow` | terminal functions: `NbFqConfig` 4457, `NbFqRecompute` 4474, `NbFLine` 4481, `NbFZone` 4499, **`NbFqDrawChart`** 4518, `NbQRect` 4630, `NbQLabel` 4650, `NbQAnsColor` 4670, **`NbFqDrawTable`** 4683. |

`NRTR_BOSS_Forex_NYTrap.mq5`: the identical edits (the twin check proves it: 5058 lines, 4
differ, all of them header / description / `NB_MARKET`).

**Not touched:** `NbDrawPanel`, `NbDrawChart`, `NbEvaluate`, `NbFillBuffers`, the whole
existing engine (NRTR, EMA, structure, BOSS, trigger, NY trap, freshness, exit advice), the
existing inputs and their order, and the gold file.

### What is drawn

* **Table** (`NBSP_Q_*`), bottom middle: title (`BTC - 15M BULLISH`), a STATUS banner
  (READY / FILLED / SETTING UP / SKIP / WATCH / NO TRADE with the reason), the five questions
  with YES / NO / ?? and a detail each, the order column (ORDER `BUY LIMIT x`, SL and why,
  TP1 / TP2 and which level, R:R, LOTS for the risk % from the SL distance using the existing
  `NbLotsForRisk`, VALID until), a one-line NEXT instruction, the support / resistance
  row with distances in 15M ATR, the 15M map row (PDH / PDL / Asia / London), the last plan
  and its outcome, the history tally, the main panel's own answer, and a footer. It is centred
  horizontally. If the centre would cover the main panel, it moves sideways just enough to
  clear it.
* **Chart** (`NBSP_F_*`, redrawn on every new closed bar): every mapped level as a thin dotted
  line with its name; the **nearest RESISTANCE and SUPPORT as width-3 lines with filled zones**
  (±zone) from 12 h back to 6 h ahead, labelled `RESISTANCE 64200.00 (PREV DAY HIGH)`, each
  with its meaning in words for the current 15M trend (`5M close ABOVE = BREAKOUT → possible
  BUY on the retest` / `sweep below + 5M close back ABOVE = possible BUY`; hovering shows the
  counter-trend side, e.g. `a real BREAKDOWN below = against the 15M trend, no trade`); a dashed
  **MIDDLE - NO ENTRY HERE** line; **BREAKOUT / BREAKDOWN** markers on the candle whose close
  went through the nearest level, marked *with 15M* or *against 15M - no trade*; a **SWEEP**
  marker while a sweep is waiting for confirmation; the live plan's BUY/SELL LIMIT, SL, TP1,
  TP2 lines running ahead; and a `PLAN BUY (SWEEP)` style marker for every plan in the loaded
  history. Hovering a marker shows its levels and outcome.

---

### Other files

| File | Change |
|---|---|
| `tests/mt5_sim.h` | test simulator only: `OBJ_RECTANGLE`, `OBJPROP_FILL`, `ANCHOR_RIGHT_LOWER`, `ANCHOR_RIGHT_UPPER` added at the ends of their enums, and a configurable chart size (`SIM.chartW/H`, default 1400 x 900 as before). All the old suites still pass unchanged. |
| `tests/test_fq_engine.cpp` | new: 96 engine checks per twin (below). |
| `tests/test_fq_indicator.cpp` | new: 106 whole-indicator checks per twin (below). |
| `tests/dump_objects.cpp` | new: the "existing panel unchanged" proof (below). |
| `tests/mutate_fq.py` | new: plants 14 bugs one at a time; every one must be caught. |
| `run_tests.sh` | steps 11-13 per twin; a `NOT RUNNABLE` is reported as such, never as a pass. |
| `README.md`, `TESTING.md` | a v1.05 section each. |

### Tests, and why they are not fake

Run `./run_tests.sh` (python3 + g++; git for step 13). Results on 2026-09-26:

```
EXISTING SUITES (unchanged, all still pass):
  gold 145 engine + 124 indicator; crypto 106 + 104; forex 104 + 103; twin check; safety scans
FIVE-QUESTION ENGINE TESTS:    crypto 96 passed / forex 96 passed, 0 failed
FIVE-QUESTION INDICATOR TESTS: crypto 106 passed / forex 106 passed, 0 failed
EXISTING PANEL UNCHANGED:      crypto 53 scenarios, 17596 object records + buffers + alerts + log identical
                               forex  53 scenarios, 17382 object records ... identical
MUTATION TESTS (tests/mutate_fq.py): 14 planted, 14 caught, 0 escaped
MetaEditor F7: NOT RUN (not available in this environment)
```

What makes them real:

* **The shipped text is what runs.** `tests/mql2cpp.py` rewrites syntax only; the engine tests
  compile the real engine block and the indicator tests compile the whole real file against an
  MT5 simulator that has **no trade API**.
* **Hand-computed expectations.** F1 to F14 use hand-made candles whose answers were worked out
  on paper first (for example F1: sweep low 99.60, SL 99.60 - 0.1 x 0.4 = 99.56, risk 0.44,
  TP1 103.00 = 6.82R). The first run of these tests found a real design flaw: the sweep was
  anchored at the *latest* pierce, so a re-dip moved the stop up to 99.91. The engine was fixed
  (earliest pierce), and mutation M09 re-plants the flaw to prove the test still catches it.
* **An independent oracle.** F16 recomputes PDH / PDL / Asia / London on every bar of a
  16-day market by brute force (a different algorithm) and requires equality on every bar.
* **No repaint.** F18 cuts history at 31 points and also replaces everything after the cut
  with a different future; every earlier bar's answer must be bit-identical. Terminal test Q7:
  a forming crash candle changes nothing in the table or on the chart, and a restart gives
  identical objects.
* **The stale gate is proven, not assumed.** In Q5 the engine's last closed bar **is** READY
  (asserted), the feed stops, and the table must say NO TRADE with no plan lines.
* **"Existing panel unchanged" is measured.** `tests/dump_objects.cpp` is built against the
  v1.04 file from git (`3f046ef`) and against the new file, runs 53 scenarios (two chart
  timeframes, a position, stale feed, missing history then recovery, unsupported symbol) and
  prints every existing object property, buffer hash, alert and log line. The outputs are
  byte-compared. M14 adds a single space to the old panel's REASON row and this check catches it.
* **The tests can fail.** `python3 tests/mutate_fq.py` plants these bugs one at a time. Every
  one is caught:

| # | Planted bug | Caught by (failing sections) |
|---|---|---|
| M01 | READY without the confirmation close | engine F1 F2 F3 F9 F11 F12 F15, indicator Q4 |
| M02 | reward gate removed | engine F3 F15, indicator Q2 Q4 |
| M03 | trend gate removed | engine F5 |
| M04 | Asia / London published 1 h before the window ends | engine F14, F16 (the oracle) |
| M05 | SL on the fill candle ignored | engine F10 |
| M06 | forming candle evaluated | engine F12 |
| M07 | 15M swings used 3 bars before confirmation (look-ahead) | engine F17, F18 (no repaint) |
| M08 | stale gate removed from the table | indicator Q5 |
| M09 | sweep anchored at the latest pierce | engine F1 |
| M10 | pending plan not cancelled on a 15M turn | engine F11 |
| M11 | table covers the main panel | indicator Q1 |
| M12 | plan lines left on a stale chart | indicator Q5 |
| M13 | counter-trend SELL plans in a bullish 15M | engine F1 F6 F8 |
| M14 | one space added to the EXISTING panel | unchanged dump (step 13) |

**About the synthetic numbers:** on the synthetic random-walk market, crypto gives 53 plans
(TP1 6, SL 14, not filled 32, timed out 1). That is expected: a random walk has no edge. It
tests the mechanics and says **nothing** about real performance. The only evidence that counts
is the tally on your own charts, and it needs n >= 20 before it means anything.

### Not verified

* **MetaEditor F7 compile:** NOT RUN (Windows only). The whole file compiles under
  `g++ -Wall -Wextra -Werror` through the syntax translation. Only MQL5 constructs the file
  already used were added, plus `OBJ_RECTANGLE`, `OBJPROP_FILL`, `ANCHOR_RIGHT_LOWER` and
  `ANCHOR_RIGHT_UPPER`, which are standard MQL5. **Press F7 and send the exact message if it
  reports anything.**
* **Visual check on a real chart:** NOT RUN. Font widths in MT5 differ from any estimate here,
  so long rows (the NEXT line, the level row) may need shortening at your panel scale.
* **Real-market evidence:** none yet. The table is a hypothesis generator until it has counted
  its own plans.

### Known limitations (honest list)

* **Spread is ignored.** A plan is counted as filled when the chart's (bid) low touches a BUY
  LIMIT. A real BUY LIMIT fills on the ask, so BUY fills are slightly optimistic, and a SELL's SL
  (bought back on the ask) is judged slightly optimistically too.
* **One plan at a time**, and a new plan needs a newer pierce / breakout than the last plan's.
* **Asia / London need the AUTO clock.** With MANUAL or UNKNOWN they are not shown (never
  guessed). The AUTO offset is read now and applied to the 10-day history, so in the week of
  the broker's own DST switch, older bars are an hour off (the same limitation the NY module
  documents).
* **London window 07-12 UTC** is fixed in UTC: it matches London's 08:00 open in UK summer
  and starts an hour before it in winter. It can be changed in the inputs.
* **Not built:** FVG, IFVG, order blocks, breaker / mitigation blocks, PO3 and QML from the
  video list. Only the liquidity sweep is part of the five questions. Any of the others would
  be a new rule that should ship dark and be counted first.
* **Gold vs silver treatment** from the framework does not apply to this file (crypto /
  forex twins). The gold panel was not changed.

### Audit checklist for Fable 5

1. `git diff 3f046ef -- NRTR_BOSS_Crypto_NYTrap.mq5 | grep '^-' | grep -v '^---'` should print
   only the `#property version "1.04"` line.
2. `./run_tests.sh` should end with `ALL SUITES PASSED` and step 13 should print `EXISTING PANEL
   UNCHANGED ... PASS` for both twins.
3. `python3 tests/mutate_fq.py` should end with `14 planted, 14 caught, 0 escaped`.
4. Read `NbRunFq` (line 2280) against *The rules* above. Every branch sets exactly one
   `status` / `why`.
5. Look for look-ahead: session levels (`NbFqWindow` publishes only when `t + sec >= wEnd`),
   swings (`pc` counts only `confirmIdx <= k15`), 5M stop swings (`NbFindStopSwing` skips
   `confirmIdx > s`), and the forming bar (`nEvalFq`).
6. In MT5: F7, then attach to BTCUSD M5 and check the table sits at the bottom middle, the
   five answers match the chart, and the lines are readable.
