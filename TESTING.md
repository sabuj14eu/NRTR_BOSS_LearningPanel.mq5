# Testing

Run everything with:

```
./run_tests.sh        # needs python3 and g++ (C++17)
```

## What was run, and what it proves

MetaQuotes' compiler (MetaEditor) only runs on Windows/Wine and could not be downloaded in
the build environment. The indicator was therefore verified like this:

1. **Safety scan** (`tests/check_safety.py`): the source is pure ASCII, is declared as an
   indicator, and contains none of 42 forbidden identifiers (all trade calls, `CTrade`,
   trade request structs, pending-order types, `WebRequest`, sockets, notifications, mail,
   FTP, `#import`, `#include`, file and global-variable writes). The only position calls are
   the five read-only ones.
2. **Surrogate compile of the whole file.** `tests/mql2cpp.py` rewrites *syntax only*
   (`input` → `const`, `T &a[]` → `std::vector<T>&`, `#property` removed). The **real
   `.mq5` text** is then compiled with `g++ -Wall -Wextra -Werror` against an MT5 API
   simulator (`tests/mt5_sim.h`). The simulator deliberately has **no trade API**, so if
   the indicator ever referenced one, the build would fail.
3. **Engine tests** (`tests/test_engine.cpp`) run the engine block of the real source.
4. **Whole-indicator tests** (`tests/test_indicator.cpp`) run the full file through
   `OnInit → OnCalculate → OnTimer → OnDeinit` on the simulated terminal and read the panel
   back from the chart objects it created.

**What this does NOT prove:** that MetaEditor accepts every MQL5-specific construct, and
how it looks on a real chart. **Press F7 in MetaEditor and do the two manual checks below
before relying on it.** If F7 reports anything, send me the exact message.

## Results (2026-09-25, v1.04 freshness fix)

```
SAFETY SCAN: PASS · FULL FILE g++ -Werror: 0 errors, 0 warnings
ENGINE TESTS:    145 checks passed, 0 failed   (new: 21 freshness by witnesses)
INDICATOR TESTS: 124 checks passed, 0 failed   (new: I11 Asia open after the metals break)
MetaEditor F7:   v1.04 NOT YET (v1.02 / v1.03 compiled in the user's MT5)
```

### Live finding (XAGUSD, broker Asia open, 2026-09-25 ~01:15 broker time)

Symptom: fresh M5 candles printing, panel WAIT with `DATA STALE / MARKET CLOSED`, both gates `DATA STALE`.

Root cause: `NbIsFresh` (v1.00–v1.03) required the last CLOSED 15M bar to be at most 30 min old and
the last closed 5M bar at most 15 min old, measured against the server clock. The broker closes
metals 00:00–01:00. From 01:00 to 01:15 the last closed 15M bar is 23:45 (age 75 min), and from
01:00 to 01:05 the last closed 5M bar is 23:55 (age 65 min): a live market judged stale by a
fixed distance across a session break. Engine test 21 reproduces the exact numbers.

Fix (freshness logic only; BOSS, NRTR, EMA, structure and gate policy untouched): freshness is
now judged by witnesses, any failure = STALE:

| Witness | Rule | Failure text |
|---|---|---|
| Broker's last tick (`SYMBOL_TIME` / `TimeCurrent`) | age ≤ `InpMaxTickAgeSec` (120 s) | NO RECENT TICK - FEED DEAD OR MARKET CLOSED |
| Forming 5M and 15M bars (`iTime(tf, 0)`) | not older than 2 bars vs the tick | FORMING BAR IS OLD - HISTORY NOT CURRENT |
| Tick clock vs server-clock estimate (`TimeTradeServer`) | tick not ahead by more than `InpMaxClockSkewSec` (300 s) | CLOCK MISMATCH |
| Closed bars we hold | forming bar must be newer than them | CLOSED BAR NOT LOADED YET - RELOADING (forces reload) |

Closed-bar AGE is no longer a witness, because a session break makes it large without making the
data stale. The `DATA CLOCK` block on the panel prints every witness: BROKER TIME (last tick) and
its age, SERVER CLOCK and skew, LAST M5 CLOSED, LAST M15 CLOSED with ages, FORMING M5 / M15,
STALE THRESHOLD, DATA STATUS. The `5M CANDLE ... next` countdown now counts to the forming bar's
close (it showed `next 00:00` when MT5 had not yet opened the new bar).

Indicator test I11 rebuilds the exact situation (silver history with the 00:00–01:00 bars removed,
clock at 01:12:07): LIVE, gates not stale, LAST M15 CLOSED shows 23:45 with its 72-minute age
openly. The same clock time with a feed dead since 00:59 is STALE (`NO RECENT TICK`), and a tick
clock 10 minutes ahead of the server clock is STALE (`CLOCK MISMATCH`).

**Manual check for tonight:** attach v1.04 to XAGUSD M5 during the Asia open and read the DATA
CLOCK block. Expected 01:00–01:15: DATA STATUS `LIVE`, LAST M15 CLOSED `23:45` with an age over an
hour, banner no longer `DATA STALE`. During 00:00–01:00: `NO RECENT TICK` and `DATA STALE`.

## Results (2026-09-24, v1.03)

```
SAFETY SCAN: PASS · FULL FILE g++ -Werror: 0 errors, 0 warnings
ENGINE TESTS:    135 checks passed, 0 failed   (new: 20 NbPlanSide = trigger levels)
INDICATOR TESTS: 114 checks passed, 0 failed   (I9: one arrow per NRTR flip, preview marker + row,
                                                live box = engine plan, gates; I8: no preview when stale)
MetaEditor F7:   v1.02 compiled and ran in the user's MT5 (screenshot 2026-09-24); v1.03 NOT YET
```

## Results (2026-09-24, v1.02 display layer)

```
SAFETY SCAN: PASS
FULL FILE (g++ -Wall -Wextra -Werror): 0 errors, 0 warnings
ENGINE TESTS:    131 checks passed, 0 failed   (new: 19 lot sizing)
INDICATOR TESTS: 106 checks passed, 0 failed   (new: I9 arrows / NY alert / zigzag / blink; I2 lots, balance, swing TP)
MetaEditor F7:   NOT RUN here
```

I9 checks: the forming candle never carries an arrow; every closed candle carries exactly one
once the NRTR is ready; up arrows sit on the candle low; zigzag segments exist; a blink tick keeps
the banner text; the NY alert fires once inside the open minute on a Tuesday, never twice the same
day, never on Saturday; the session row counts down before the open and says WAIT after it.

Extra manual check in MT5 for v1.02: set *NY open time* to your broker's 09:30 New York (on the
chart in the screenshots that is 16:30) and confirm one pop-up + sound at that minute.

## Results (2026-09-24, v1.01 after the audit of blob f95f970)

```
SAFETY SCAN: PASS  (42 forbidden identifiers checked; position API = read-only only)
FULL FILE (g++ -Wall -Wextra -Werror): 0 errors, 0 warnings
ENGINE TESTS:    125 checks passed, 0 failed
INDICATOR TESTS:  88 checks passed, 0 failed
MetaEditor F7:   NOT RUN (Windows only; not available in the build environment)
Visual MT5 test: NOT RUN (no MT5 here) - see the manual checks below
NRTR vs MT5 NRTR side by side on real charts: NOT RUN - procedure below
```

### The acceptance list

| Acceptance item | Where | Result |
|---|---|---|
| MetaEditor 0 errors / 0 warnings | MT5 | **NOT RUN** here. The surrogate g++ -Werror build of the whole file is clean. |
| Gold works | indicator I2 | PASS: CLICK BUY and CLICK SELL rendered with the engine's exact levels |
| Silver works | indicator I4 | PASS: 3 dp, 0.001 tick, money row from tick value |
| EURUSD / US100 / BTCUSD / ETHUSD → GOLD / SILVER ONLY | indicator I1 | PASS (all four) |
| 15M forming candle never enters a 5M decision | engine 11, 15, xx; indicator I6 | PASS |
| 5M forming candle never creates a signal | engine 07; indicator I6 | PASS |
| Confirmed pivot unusable before its confirmation bar | engine 16 (explicit), 11 | PASS |
| Historical structure / signals never repaint | engine 11; indicator I6 | PASS: 117 cut points, a different future changes no past decision |
| BUY invariant SL < Entry < TP1 < TP2 | engine 16 | PASS on all 74 signals of both fixtures |
| SELL invariant TP2 < TP1 < Entry < SL | engine 16 | PASS on all 74 signals |
| TP2 strictly > TP1 or inputs rejected | engine 16 (`NbParamsValid`), `OnInit` | PASS (==, <, and <=0 rejected) |
| Stale data fails closed to WAIT / UNKNOWN | engine 15; indicator I8 | PASS |
| Restart → identical state | engine 14; indicator I7 | PASS in simulation (202 objects); **confirm once in MT5** |
| Same-candle SL + TP1 → SL | engine 17 | PASS (BUY and SELL; TP1-only still TP1; entry candle never judged) |
| Read-only position inspection | indicator I5 | PASS: positions read, never changed |
| No OrderSend / OrderSendAsync / CTrade / PositionClose / PositionModify / OrderDelete / WebRequest / socket / Telegram | safety scan + surrogate compile | PASS |
| EXIT uses the FULL 15M BOSS mode | engine 09, 10; indicator I5 | PASS: the six-row truth table; NRTR flip alone → PROTECT, never EXIT |
| NRTR definition frozen and labelled | engine 18; indicator I5; file header | PASS: labelled CUSTOM ATR-NRTR; differs from the classic percentage NRTR on 6–13 % of bars |
| Actual visual MT5 test on Gold and Silver | MT5 | **NOT RUN** here |

### EXIT / PROTECT truth table (engine 09 / 10, indicator I5)

| Position | 15M BOSS mode now | Advice |
|---|---|---|
| BUY | BUY MODE | HOLD |
| SELL | SELL MODE | HOLD |
| BUY | SELL MODE | EXIT / PROTECT |
| SELL | BUY MODE | EXIT / PROTECT |
| any | WAIT | UNKNOWN / PROTECT (position row: `PROTECT - 15M BOSS WAIT, NOT INVALIDATED: <reason>`) |
| any | stale / missing | UNKNOWN (`CANNOT JUDGE`) |

Indicator test I5(b) finds a real moment in the fixture where the 15M NRTR has flipped against
the position while EMA200 and structure still agree with it: the banner stays WAIT and the
position row reads PROTECT. Under v1.00 that moment showed EXIT.

### NRTR comparison (engine 18) - synthetic data, NOT real MT5 charts

Reference: the classic Nick Rypock Trailing Reverse (dynamic look-back on closes, percentage
band K, as published for MT4/MT5), K set so its band is about 2 ATR.

| Series | bars | direction differs | flips custom / classic / same bar | mean line diff |
|---|---|---|---|---|
| XAUUSD M15 | 1336 | 111 (8.3 %) | 23 / 47 / 6 | 3.10 |
| XAUUSD M5 | 4408 | 366 (8.3 %) | 128 / 81 / 36 | 1.02 |
| XAGUSD M15 | 1336 | 170 (12.7 %) | 25 / 66 / 6 | 0.050 |
| XAGUSD M5 | 4408 | 277 (6.3 %) | 118 / 110 / 51 | 0.011 |

Conclusion: the panel's NRTR is **not** the classic NRTR, so it is labelled CUSTOM ATR-NRTR
(panel header, indicator short name, file header). Which NRTR your MT5 carries is unknown to
this suite; do the side-by-side below.

### The tests can fail

Realistic bugs injected into copies of the indicator, every one caught:

| Injected bug | Caught by |
|---|---|
| 5M decisions read the still-forming 15M bar | engine 11, 15, xx |
| The unfinished 5M candle is evaluated | engine 07 |
| A swing counts as confirmed before its right side exists | engine 11 |
| SELL mode ignores EMA200 | engine 05 |
| An `OrderSend` call is added | safety scan **and** the full-file compile |
| EXIT on any boss disagreement (WAIT treated as EXIT) | engine 09/10 (6 checks), indicator I5 (7 checks) |
| Terminal layer judges EXIT on raw NRTR direction again | indicator I5 (7 checks) |
| TP1 tested before SL on the same candle | engine 17 (3 checks) |
| TP2 <= TP1 accepted | engine 16 (3 checks) |

## Manual checks in MT5 (do these before relying on it)

1. **Compile:** MetaEditor → open the file → **F7**. Expect `0 errors, 0 warnings`. Send me the
   exact text if it reports anything.
2. **Inputs:** set TP2 (R) = 1.0 with TP1 (R) = 1.0. The indicator must refuse to start and the
   Experts tab must show `NRTR BOSS: invalid inputs - TP2 (R) must be strictly greater than TP1 (R)`.
   Set TP2 back to 2.0.
3. **Gold and Silver visual:** attach to XAUUSD M15 and XAGUSD M15 (and M5). Check the panel
   header reads `15M BOSS - DIRECTION (CUSTOM ATR-NRTR)`, that markers, WAIT labels and levels
   appear, and that the banner reason is readable.
4. **Restart:** on XAGUSD M5 note banner, reason, Entry/SL/TP and the last BUY/SELL marker.
   Close MT5, reopen it (same day), compare. Must be identical.
5. **Unsupported:** attach to EURUSD, US100, BTCUSD, ETHUSD → `GOLD / SILVER ONLY`.
6. **Position (demo only):** with a demo BUY open on XAUUSD, the position row must show HOLD,
   PROTECT (boss WAIT) or EXIT / PROTECT according to the 15M DECISION row - never EXIT while
   the 15M DECISION row reads WAIT.
7. **NRTR side by side (XAUUSD M15, XAUUSD M5, XAGUSD M15, XAGUSD M5):** attach your MT5 NRTR
   indicator to the same chart. For the last ~100 closed bars compare (a) direction, (b) the
   candle on which each flips, (c) the line value against the panel's `NRTR UPPER / LOWER` row
   and the thick 15M NRTR line. Expect differences - the panel is a CUSTOM ATR-NRTR. Note how
   many bars disagree; if you want them identical, that is a new versioned engine, not an edit.
1. **Compile:** MetaEditor → open the file → **F7**. Expect `0 errors, 0 warnings`.
2. **Restart:** attach to XAGUSD M5, note the banner, reason, Entry/SL/TP values and the
   last BUY/SELL marker. Close MT5, reopen it (same day), and compare. They must be
   identical.
3. Optional: attach it to EURUSD. It must show **GOLD / SILVER ONLY**.

---

# The NY-trap twins (`NRTR_BOSS_Crypto_NYTrap.mq5`, `NRTR_BOSS_Forex_NYTrap.mq5`)

The twins are built on the v1.04 gold file (merged, not re-implemented: the gold v1.04 engine
and display text are inside them, plus the session module and the candle strips). Same method
as above, run **once per twin**: safety scan, twin check, surrogate compile of the whole file
with `-Wall -Wextra -Werror`, engine tests on the real engine block, whole-indicator tests on
the simulated terminal (which also simulates `TimeGMT()` so the two-witness session clock can
be exercised, alongside the v1.04 tick clock).

## Results (2026-09-25)

```
TWIN CHECK:      PASS  (3327 lines, 4 differ: header, 2 descriptions, NB_MARKET)
SAFETY SCAN:     PASS  (both files; 42 forbidden identifiers; position API = read-only only)
FULL FILE crypto (g++ -Wall -Wextra -Werror): 0 errors, 0 warnings
FULL FILE forex  (g++ -Wall -Wextra -Werror): 0 errors, 0 warnings
SESSION ENGINE TESTS:    crypto 106 checks passed / forex 104, 0 failed
SESSION INDICATOR TESTS: crypto 104 checks passed / forex 103, 0 failed
(gold v1.04 suites on the same simulator: 145 engine + 124 indicator checks, 0 failed)
MetaEditor F7:   NOT RUN (not available in the build environment)
```

### What the session tests cover

| # | Case | Result |
|---|---|---|
| S1 | Civil calendar and the US DST rule per day (2025 and 2026 switch dates) | PASS |
| S2 | NY open in broker time: UTC+3 summer -> 16:30, UTC+2 winter -> 16:30, the March weeks where US and EU DST differ -> 15:30, UTC-5 broker, late-night bars belong to the right session, MANUAL | PASS |
| S3 | Two-witness clock: half-hour offsets accepted (with 200 s drift), 10 min off -> OFF, +20 h -> OFF, missing witness -> OFF | PASS |
| S4 | Phases, range built causally, sweep extremes remembered, clock OFF -> everything OUT | PASS |
| S5 | SELL trap: exact entry / SL / R / TP1 / TP2 / level / sweep; one-bar and two-bar versions; no second trap on the same side; bearish close still above the range is not a reclaim; bullish body is not a SELL trap; reason persists to the end of the window then releases | PASS |
| S6 | BUY trap mirror; SL hit; the other side may still fire in the same session | PASS |
| S7 | Fewer pre-NY bars than the minimum -> `NO RANGE`, no trap even on a textbook sweep | PASS |
| S8 | Flow vs trap: an active flow signal is CANCELLED by a trap; paused window starts no flow signal even when the 5M realigns; pause off -> it does; after the trap resolves and the window closes, the flow starts a fresh episode | PASS |
| S9 | The trap candle still forming -> WAIT; the same candle closed -> CLICK SELL | PASS |
| S10 | 16 days of synthetic 5M bars: 46 flow + 8 trap signals; every level ordered; every trap inside a window, inside the range it reclaimed, one per side per session; restart bit-identical; clock unknown -> flow only | PASS |
| S11 | 106 cut points and a different future: no past state, reason, phase, range, sweep or signal changes | PASS |
| S12 | Market filter for the twin under test (BTCUSD, ETHUSD.m, #SOLUSD, ltcusd, BTCUSDT, Bitcoin ... / EURUSD, USDJPY.m, #gbpjpy, crosses); gold, index, the other market rejected | PASS |
| I1-I9 | Whole indicator: symbol filter, flow CLICK rendered with the engine's levels plus the v1.04 rows (live box plan and READY - CLICK gate, lots for 1% risk, automatic swing TP, LAST 5 candle strips, DATA CLOCK = LIVE, NEW YORK OPEN row), trap CLICK rendered with sweep levels and markers, paused window text on both NY rows, clock UNKNOWN in words and negative offsets, EXIT / PROTECT on the complete boss mode (read-only), forming spike candle changes nothing (flow and trap), restart identical (343 objects), missing / stale data with the failing witness named and no preview | PASS |

### The tests can fail (twins)

Eight realistic bugs were injected into copies of the crypto file. Every one was caught by
the session engine tests (two of them by the indicator tests as well):

| Injected bug | Caught |
|---|---|
| Trap fires on any bearish close, no sweep required | yes |
| Trap fires on a bearish close that never came back inside the range | yes |
| Two traps per side per session | yes |
| Pre-NY range keeps growing with NY-window bars | yes |
| US DST ignored (13:30 UTC all year) | yes |
| Structure flow not paused inside the window | yes (after S8 was extended; it escaped the first version) |
| Clock accepted whatever the PC said (no half-hour check) | yes |
| The forming 5M bar evaluated for a trap | yes |

## Manual checks in MT5 (twins)

1. **Compile both files** with F7. Expect `0 errors`.
2. Drop the crypto file on BTCUSD M5 and the forex file on EURUSD M5. The `SESSION CLOCK` row
   must print `AUTO: SERVER = UTC+N` with the offset your broker really has (EET/EEST brokers:
   +2 or +3). If it prints UNKNOWN, set the clock to MANUAL and type the NY open as your
   chart shows it.
3. At 16:30 server time (EET/EEST brokers, most of the year) the PHASE row must switch to
   `NY WINDOW`. If it switches at a different time, the offset is wrong: use MANUAL.
4. Same restart check as for the gold file.
