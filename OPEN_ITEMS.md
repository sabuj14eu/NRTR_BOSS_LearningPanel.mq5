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

## 3. US100 - built as v1.11 SHADOW; next steps waiting for evidence / Shyam

`NRTR_BOSS_US100.mq5` exists (CHANGELOG v1.11). Still open:
* **Evidence first:** record US100 plans per session label and gap state. No parameter changes
  before n >= 20 per cell (~100 to judge).
* **US holiday / half-day calendar:** not loaded; labels use the normal schedule. It needs a
  verified, dated source (a data table, as rates are in the accounting app).
* **Phase 2:** peers context (NVDA, AMD, AVGO, MSFT: display only, `not_a_signal`), then stocks
  with their own parameters, earnings-day labels and gap handling. Only after US100 is validated.
* MetaEditor F7 compile of the new file: not run here.

## 4. Gaps in the current metals / forex files - measure first

No gap concept today: ATR jumps after a weekend gap, a gap across a level can count as a sweep or a
breakout in the five-question engine, and the replay fills gapped SLs at the SL price. Details
and the measure-first proposal (`after_gap` on each record): `docs/US100_PLAN.md` section 5.

## 5. The existing files convert past NY opens with today's server offset (found 2026-09-27)

`NbNyOpenOf` (metals, crypto, forex) uses the witnesses' offset NOW for every historical bar. On a
broker whose server offset changes with DST, bars before a switch put the NY open one hour off.
That affects the NY trap phases and the pre-NY range for up to 10 days after a switch. US100 does
it per bar (`NbUsEt`, tested for all of 2026). Fix = a new version of those files with the same
per-bar conversion and tests. Not changed now, because the three files stay unchanged.

## 6. Crypto / forex legend lines are longer than MT5's 63-character label limit (found 2026-09-27)

`g1`..`g5`, `f1`, `hb` and `vd6` are 64-97 characters, so MT5 cuts them. US100 has shortened
versions (checked <= 63 in `test_us100`). The crypto / forex text is unchanged until Shyam says so.

## Done

* "Give me final crypto" (the metals v1.10 port to crypto / forex): done 2026-09-27. Proof:
  CHANGELOG "v1.10 crypto / forex", `test_session_indicator.cpp` I20, mutations 82-89, TESTING.md results.
