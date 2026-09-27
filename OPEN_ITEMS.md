# OPEN ITEMS

An item deferred in conversation is an item forgotten - if it is not in this file, it does not exist.
Delete an entry only when it is done and verified, and say where the proof is.

## 1. Spread-aware stop check on the 5-question plan - PROPOSAL, waiting for Shyam's go (2026-09-27)

LTCUSD: the plan put its SL 0.02 below the sweep low (risk 0.10). A BUY limit fills at the ask,
the SL triggers at the bid, so the spread eats a large part of such a stop, and the shadow replay
(bid candles, no spread) counts fills and wins a real account would not get. Proposal, display
only: warn "SL INSIDE SPREAD NOISE" when risk < 3 x spread, and show R:R after spread. Record the
spread on each replay so the evidence says how often it mattered. No strategy change without data.

## 2. Session TP / SL (Asia, London, London-NY, NY) - proposal, WAITING for Shyam's go

Measure first: session label on every shadow record + a per-session report (5M ATR, MFE / MAE,
TP1 / SL hit rate). Change TP / SL per session only after the numbers (n >= 20 per session).

## Done

* "Give me final crypto" (the metals v1.10 port to crypto / forex): done 2026-09-27. Proof:
  CHANGELOG "v1.10 crypto / forex", `test_session_indicator.cpp` I20, mutations 82-89, TESTING.md results.
