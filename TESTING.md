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

## Results (2026-09-24)

```
SAFETY SCAN: PASS  (42 forbidden identifiers checked; position API = read-only only)
FULL FILE (g++ -Wall -Wextra -Werror): 0 errors, 0 warnings
ENGINE TESTS:    96 checks passed, 0 failed
INDICATOR TESTS: 74 checks passed, 0 failed
MetaEditor F7:   NOT RUN (not available in the build environment)
```

### The 15 required cases

| # | Case | Where | Result |
|---|---|---|---|
| 1 | 15M bullish + 5M bullish → BUY | engine 01, indicator I2 | PASS: exact Entry/SL/TP1/TP2/Risk |
| 2 | 15M bearish + 5M bearish → SELL | engine 02, indicator I2 | PASS |
| 3 | 15M bullish + 5M bearish → WAIT | engine 03, indicator I3 | PASS: reason "5M AGAINST 15M" |
| 4 | 15M bearish + 5M bullish → WAIT | engine 04 | PASS |
| 5 | EMA conflict → WAIT | engine 05 | PASS, and a 5M candle cannot override it |
| 6 | Structure mixed → WAIT | engine 06 | PASS; unconfirmed → NOT CONFIRMED |
| 7 | Unfinished candle → WAIT | engine 07, indicator I6 | PASS: a forming crash candle changes nothing |
| 8 | Confirmed candle → eligible | engine 08 | PASS |
| 9 | BUY position + 15M reversal → EXIT/PROTECT | engine 09, indicator I5 | PASS: position untouched |
| 10 | SELL position + 15M reversal → EXIT/PROTECT | engine 10, indicator I5 | PASS |
| 11 | Historical signals don't repaint | engine 11, indicator I6 | PASS: 117 cut points over 16 days, and a different future leaves every past decision unchanged |
| 12 | Digits / tick from the symbol | engine 12, indicator I2/I4 | PASS for 2dp, 3dp, 5dp and a 0.05 tick |
| 13 | No trading function can execute | safety scan + surrogate compile | PASS |
| 14 | Restart → identical state | engine 14, indicator I7 | PASS in simulation (202 objects + all buffers identical); **confirm once in real MT5** |
| 15 | Missing / incomplete data → WAIT | engine 15, indicator I8 | PASS: no history, failed copy, short history, stale feed |

### The tests can fail

To show the suite is not a rubber stamp, five realistic bugs were injected into copies of the
indicator. Every one was caught:

| Injected bug | Caught by |
|---|---|
| 5M decisions read the still-forming 15M bar | engine 11, 15, xx |
| The unfinished 5M candle is evaluated | engine 07 |
| A swing counts as confirmed before its right side exists | engine 11 |
| SELL mode ignores EMA200 | engine 05 |
| An `OrderSend` call is added | safety scan **and** the full-file compile |

## Manual checks in MT5 (5 minutes)

1. **Compile:** MetaEditor → open the file → **F7**. Expect `0 errors, 0 warnings`.
2. **Restart:** attach to XAGUSD M5, note the banner, reason, Entry/SL/TP values and the
   last BUY/SELL marker. Close MT5, reopen it (same day), and compare. They must be
   identical.
3. Optional: attach it to EURUSD. It must show **GOLD / SILVER ONLY**.
