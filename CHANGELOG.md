# CHANGELOG

## v1.05 (2026-09-26): FIVE-QUESTION PLAN table for the crypto (and forex) twin

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
