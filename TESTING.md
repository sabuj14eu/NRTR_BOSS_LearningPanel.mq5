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
