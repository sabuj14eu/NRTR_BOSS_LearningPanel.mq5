# OPEN ITEMS

An item deferred in conversation is an item forgotten - if it is not in this file, it does not exist.
Delete an entry only when it is done and verified, and say where the proof is.

## 1. "Give me final crypto" - WAITING for Shyam's word (deferred 2026-09-27)

When Shyam says "give me final crypto", port to `NRTR_BOSS_Crypto_NYTrap.mq5` (the forex twin follows
via `tests/make_twin.py`) the four metals v1.10 audit fixes, with the same tests:
1. CLICK GUARD - READY - CLICK only within `InpClickBandR` x risk of the entry; else SETUP - PRICE
   TOO FAR (crypto banner also has the "CLICK BUY - NY TRAP" variant). The crypto `NbBrAction`,
   `NbBrSigExtra` and `NbBrClickKey` adapters become real.
2. Lots: volume-step decimals instead of `NormalizeDouble(lots, 2)` (line ~397); loss tick value.
3. First NRTR-ready bar is not a flip (`bool flipHere = (ad != prevAd);` line ~3780).
4. Pending line: "5M AGAINST - WAIT FOR 5M RE-ALIGNMENT" instead of `---` (line ~4652).
5. A small version label on the crypto panel.
The "existing panel unchanged" dump then needs crypto baseline patches (`tests/baseline_patches.py`).
NOT part of it unless asked: the regime pullback (1H/4H) and the MARKET chip - only after the
metals shadow records justify them.

## 2. Session TP / SL (Asia, London, London-NY, NY) - proposal, WAITING for Shyam's go

Measure first: session label on every shadow record + a per-session report (5M ATR, MFE / MAE,
TP1 / SL hit rate). Change TP / SL per session only after the numbers (n >= 20 per session).
