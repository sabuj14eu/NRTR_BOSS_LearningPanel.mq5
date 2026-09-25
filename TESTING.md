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

---

# The NY-trap twins (`NRTR_BOSS_Crypto_NYTrap.mq5`, `NRTR_BOSS_Forex_NYTrap.mq5`)

Same method as above, run **once per twin**: safety scan, twin check, surrogate compile of the
whole file with `-Wall -Wextra -Werror`, engine tests on the real engine block, whole-indicator
tests on the simulated terminal (which now also simulates `TimeGMT()` so the two-witness clock
can be exercised).

## Results (2026-09-25)

```
TWIN CHECK:      PASS  (2579 lines, 4 differ: header, 2 descriptions, NB_MARKET)
SAFETY SCAN:     PASS  (both files; 42 forbidden identifiers; position API = read-only only)
FULL FILE crypto (g++ -Wall -Wextra -Werror): 0 errors, 0 warnings
FULL FILE forex  (g++ -Wall -Wextra -Werror): 0 errors, 0 warnings
SESSION ENGINE TESTS:    crypto 106 checks passed / forex 104, 0 failed
SESSION INDICATOR TESTS: crypto  84 checks passed / forex  83, 0 failed
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
| I1-I9 | Whole indicator: symbol filter, flow CLICK rendered with the engine's levels, trap CLICK rendered with sweep levels and markers, paused window text, clock UNKNOWN in words and negative offsets, EXIT / PROTECT read-only, forming spike candle changes nothing (flow and trap), restart identical (208 objects), missing / stale data | PASS |

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
