# Testing

Run everything with:

```
./run_tests.sh        # needs python3 and g++ (C++17); about 90 s
```

## What was run, and what it proves

MetaQuotes' compiler (MetaEditor) only runs on Windows/Wine and could not be downloaded in
the build environment. The EA was therefore verified like this:

1. **Safety scan** (`tests/check_safety_ea.py`): pure ASCII; none of 30 forbidden
   identifiers (network, files, DLLs, async/`CTrade` order paths, stop orders); the required
   guards present (`InpAllowRealAccount` as a bool input, the Algo Trading switch honoured,
   `NqRiskGate`, `NqLotFor`); **exactly one `OrderSend` call site**; no literal lot size
   anywhere.
2. **Surrogate compile of the whole file.** `tests/mql2cpp.py` rewrites *syntax only*
   (`input` → `const`, `T &a[]` → `std::vector<T>&`, `#property` removed). The **real
   `.mq5` text** is compiled with `g++ -Wall -Wextra -Werror` against a simulated terminal
   (`tests/mt5_sim_ea.h`: in-memory positions, pending orders, deal history, account, and a
   matching engine that fills limits and stops bar by bar, SL first).
3. **Engine tests** run the engine block of the real source on crafted and synthetic data.
4. **Whole-EA tests** run `OnInit → OnTick → OnTimer → OnDeinit` on the simulated terminal
   and read the panel, arrows and orders back.

**What this does NOT prove:** that MetaEditor accepts every MQL5-specific construct, and how
it behaves on a real broker feed. **Press F7 in MetaEditor and do the manual checks below
before relying on it.** If F7 reports anything, send the exact message.

## Results (2026-09-29)

```
EA SAFETY SCAN: PASS
EA FULL FILE (g++ -Wall -Wextra -Werror): 0 errors, 0 warnings
EA ENGINE TESTS:  76 checks passed, 0 failed
EA TESTS:         69 checks passed, 0 failed
MetaEditor F7:    NOT RUN (not available in the build environment)
```

### EA engine tests (`tests/test_ea_engine.cpp`)

| # | Case | Result |
|---|---|---|
| E01 | M5 regime: NRTR + confirmed structure → BULL/BEAR, else CHOP with the reason; M15 context | PASS |
| E02 | Forecast: score = 2·higher + NRTR + body + EMA side; below the threshold the tie-break (NRTR, body, previous) gives every candle an arrow; hit judged only at the next close; equal close = miss; newest arrow unresolved | PASS |
| E03 | Auto lot: risk / loss-per-lot, floored to the step; min lot too risky → 0 (no trade); volMax clamp; silver tick value 5 | PASS |
| E04 | Risk gate bits (real account, autotrading, spread, daily cap at and inside the limit, max open, max trades, session incl. overnight) | PASS |
| E05 | Bearish QML on crafted bars: created on the neck-break close (never before), SELL LIMIT = left shoulder, SL = head + 0.2 ATR, TP1 1R / TP2 2R, keyed by head time; filled on the shoulder touch, reached TP1; a gap through shoulder and head = fill and stop on the same bar | PASS |
| E06 | Bullish QML mirror | PASS |
| E07 | Synthetic 6-day market (34 pullback + 35 QML plans, 94 scalp signals): every plan obeys its geometry and regime, fills/expiries match the bars, one live plan per kind+side; every scalp signal is the first candle of an aligned episode with SL 1.5 ATR5 / TP 1.0 ATR5, judged SL-first then time stop; BUY/SELL state only while a signal is young; WAIT always has a reason | PASS |
| E08 | No repaint: 12 cut points over 8640 M1 bars, silver spec; all past states, arrows, signals and plans equal the full run | PASS |
| E09 | Freshness (M1 4 min old = stale), metal detection, every reason/gate bit named, stale named first | PASS |
| E10 | NY trap state machine on a crafted server day: pre-NY range, sweep, return, plan armed only on the confirmation bar (SELL LIMIT at the swept high, SL beyond the extreme), filled and TP1; sweep + return without confirmation is not a trade; an unfilled plan expires at the session end; next day starts fresh; distance in ATR units | PASS |

### Whole-EA tests (`tests/test_ea.cpp`, gold-like and silver-like synthetic markets)

| # | Case | Result |
|---|---|---|
| A1 | Demo account: every scalp maps to an engine signal (side, SL, TP, magic, symbol); lot within the risk allowance; one order per signal; scalps are the lowest priority (none while a plan order waits); exits by SL/TP; engine table + board | PASS |
| A2 | Plans over five days (49 limits placed, 5 filled; QML, pullback, NY trap and swing kinds all placed): each order matches an ACTIVE plan of an enabled kind (entry, SL, TP1, side); a plan never has two orders nor an order beside its own position (this caught a real bug); every order risks ≤ 0.5 % at the SL; **one slot**: never two positions and no waiting order while a position is open (caught a same-tick scalp-after-limit bug); fills at the plan entry with the plan's SL/TP carried into the position or its exit | PASS |
| A3 | REAL account trades (default); Algo Trading off: nothing sent, banner `ALGO TRADING OFF - WATCH ONLY`; a manual position and a foreign-magic order on the symbol are never modified, closed or cancelled, do not block the bot, and are listed as untouched | PASS |
| A4 | Daily loss cap: no new entries, a stale scalp still closed by the time stop; spread 500: no entries; terminal autotrading off: no entries | PASS |
| A5 | Regime flip closes an open scalp against the new M5 regime on the next closed candle, logged with the reason | PASS |
| A6 | Restart on the same day: same plans/signals, 378 panel + chart objects identical, no request sent, no duplicate orders afterwards | PASS |
| A7 | Frozen feed: banner DATA STALE, nothing sent. EURUSD: nothing at all | PASS |
| A8 | Arrows: one per candle in the window + the wide white live one with its NEXT label (301 = 301), no candle without an arrow; 50 candles later every past arrow unchanged; hit-rate row shows % and n | PASS |
| A9 | Panel: 7 engine rows, no key twice, every row has a value; board with TYPE/SIDE/ENTRY/SL/TP SENT/DIST/STATUS for 5 plan slots + 6 broker rows, NY session / pre-NY range / sweep-trap / slot lines, LAST UPDATE; a planted broker order and position appear as rows within one refresh with ticket, kind, NEAR and RUNNING; slot line reads TAKEN | PASS |
| A10 | Silver (3 digits, tick value 5): SL/TP on the 0.001 grid, lots from the real tick value; with every order rejected: rejections logged, a rejected scalp is not re-sent for the same trigger | PASS |

## Manual checks in MT5 (10 minutes)

1. **Compile:** MetaEditor → open the file → **F7**. Expect `0 errors, 0 warnings`.
2. **Switch:** attach the EA to XAUUSD M1; with Algo Trading off the banner must read
   `ALGO TRADING OFF - WATCH ONLY` and nothing may be sent; turn it on and the footer must
   read `GATE OPEN`.
3. **Restart:** note the plan lines, the last scalp marker and the `RECORD` row; close and
   reopen MT5 the same day; they must be identical and no order must be duplicated.
4. **Arrows:** watch one M1 candle close: the big white `NEXT` arrow must turn into a small
   green or red one and a new white `NEXT` arrow must appear on the new candle.
5. Optional: attach to EURUSD. It must show **GOLD / SILVER ONLY**.
