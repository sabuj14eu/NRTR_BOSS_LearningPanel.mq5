# Testing

Run everything with:

```
./run_tests.sh        # needs python3 and g++ (C++17); about 90 s
```

## What was run, and what it proves

MetaQuotes' compiler (MetaEditor) only runs on Windows/Wine and could not be downloaded in
the build environment. Both files were therefore verified like this:

1. **Safety scans.** `tests/check_safety.py` (indicator): pure ASCII, declared as an
   indicator, none of 42 forbidden identifiers (all trade calls, `CTrade`, `WebRequest`,
   sockets, notifications, mail, FTP, `#import`, `#include`, file and global-variable
   writes); position API read-only. `tests/check_safety_ea.py` (EA): none of 30 forbidden
   identifiers (network, files, DLLs, async/`CTrade` order paths, stop orders); the required
   guards present (`ACCOUNT_TRADE_MODE_DEMO` check, `InpAllowRealAccount` defaulting to
   `false`, `NqRiskGate`, `NqLotFor`); **exactly one `OrderSend` call site**; no literal lot
   size anywhere.
2. **Surrogate compile of the whole file.** `tests/mql2cpp.py` rewrites *syntax only*
   (`input` → `const`, `T &a[]` → `std::vector<T>&`, `#property` removed). The **real
   `.mq5` text** is compiled with `g++ -Wall -Wextra -Werror` against a simulated terminal:
   `tests/mt5_sim.h` (indicator, deliberately **no trade API**) and `tests/mt5_sim_ea.h`
   (EA: in-memory positions, pending orders, deal history, account, matching engine that
   fills limits and stops bar by bar, SL first).
3. **Engine tests** run the engine block of each real source on crafted and synthetic data.
4. **Whole-file tests** run `OnInit → OnTick/OnCalculate → OnTimer → OnDeinit` on the
   simulated terminal and read the panel and orders back.

**What this does NOT prove:** that MetaEditor accepts every MQL5-specific construct, and how
it behaves on a real broker feed. **Press F7 in MetaEditor and do the manual checks below
before relying on either file.** If F7 reports anything, send the exact message.

## Results (2026-09-29)

```
INDICATOR  safety scan PASS · full file g++ 0 errors · engine 96 passed · indicator 74 passed
EA         safety scan PASS · full file g++ 0 errors · engine 65 passed · whole-EA 50 passed
MetaEditor F7: NOT RUN (not available in the build environment)
```

### EA engine tests (`tests/test_ea_engine.cpp`)

| # | Case | Result |
|---|---|---|
| E01 | M5 regime: NRTR + confirmed structure → BULL/BEAR, else CHOP with the reason; M15 context | PASS |
| E02 | Forecast: score = 2·higher + NRTR + body + EMA side; arrow at |score| ≥ 2; hit judged only at the next close; equal close = miss; newest arrow unresolved | PASS |
| E03 | Auto lot: risk / loss-per-lot, floored to the step; min lot too risky → 0 (no trade); volMax clamp; silver tick value 5 | PASS |
| E04 | Risk gate bits (real account, autotrading, spread, daily cap at and inside the limit, max open, max trades, session incl. overnight) | PASS |
| E05 | Bearish QML on crafted bars: created on the neck-break close (never before), SELL LIMIT = left shoulder, SL = head + 0.2 ATR, TP1 1R / TP2 2R, keyed by head time; filled on the shoulder touch, reached TP1; a gap through shoulder and head = fill and stop on the same bar | PASS |
| E06 | Bullish QML mirror | PASS |
| E07 | Synthetic 6-day market (34 pullback + 35 QML plans, 94 scalp signals): every plan obeys its geometry and regime, fills/expiries match the bars, one live plan per kind+side; every scalp signal is the first candle of an aligned episode with SL 1.5 ATR5 / TP 1.0 ATR5, judged SL-first then time stop; BUY/SELL state only while a signal is young; WAIT always has a reason | PASS |
| E08 | No repaint: 12 cut points over 8640 M1 bars, silver spec; all past states, arrows, signals and plans equal the full run | PASS |
| E09 | Freshness (M1 4 min old = stale), metal detection, every reason/gate bit named, stale named first | PASS |

### Whole-EA tests (`tests/test_ea.cpp`, gold-like and silver-like synthetic markets)

| # | Case | Result |
|---|---|---|
| A1 | Demo account: 20 scalps sent; each maps to an engine signal (side, SL, TP, magic, symbol); lot within the risk allowance; one order per signal; at most one scalp open; exits by SL/TP; two panel tables, not three | PASS |
| A2 | Pending plans over five days (30 placed, 4 filled): both kinds placed; each order matches an ACTIVE plan (entry, SL, TP1, side); a plan whose limit already filled is never placed twice (this caught a real bug); every order risks ≤ 0.5 % at the SL; cancelled only when the plan ended; live orders always belong to a live plan; fills at the plan entry with the plan's SL/TP | PASS |
| A3 | REAL account: zero requests; banner and gate row say so | PASS |
| A4 | Daily loss cap: no new entries, a stale scalp still closed by the time stop; spread 500: no entries; terminal autotrading off: no entries | PASS |
| A5 | Regime flip closes an open scalp against the new M5 regime on the next closed candle, logged with the reason | PASS |
| A6 | Restart on the same day: same plans/signals, 378 panel + chart objects identical, no request sent, no duplicate orders afterwards | PASS |
| A7 | Frozen feed: banner DATA STALE, nothing sent. EURUSD: nothing at all | PASS |
| A8 | Arrows: one per forecast candle in the window + the live one (212 = 212); 50 candles later every past arrow unchanged; hit-rate row shows % and n | PASS |
| A9 | Panel: 16 rows (7 engine + 9 plan/scalp/risk), no key twice, every row has a value, single column under 500 px | PASS |
| A10 | Silver (3 digits, tick value 5): SL/TP on the 0.001 grid, lots from the real tick value; with every order rejected: rejections logged, a rejected scalp is not re-sent for the same trigger | PASS |

### Indicator (unchanged, still green)

The 15 required cases of the learning panel are listed in the previous version of this file
and still pass: engine 96 / 96, indicator 74 / 74.

## Manual checks in MT5 (10 minutes)

1. **Compile:** MetaEditor → open each file → **F7**. Expect `0 errors, 0 warnings`.
2. **Demo guard:** attach the EA to XAUUSD M1 on a demo account: the price line shows `DEMO`
   and the `GATE` row `OPEN` (with Algo Trading on). On a real account the banner must read
   `REAL ACCOUNT - TRADING BLOCKED`.
3. **Restart:** note the plan lines, the last scalp marker and the `RECORD` row; close and
   reopen MT5 the same day; they must be identical and no order must be duplicated.
4. **Arrows:** watch one M1 candle close: the white live arrow must turn green or red and a
   new white arrow must appear on the new candle.
5. Optional: attach to EURUSD. It must show **GOLD / SILVER ONLY**.
