# US EQUITIES / INDEX module - proposed architecture and test plan (US100 / USTEC first)

Status: **BUILT as v1.11 (shadow)** on 2026-09-27, after Shyam's four decisions (section 6: all four
recommended options). What differs from this plan: the NY clock converts per bar through the
server's DST rule (input `InpUsServerDst`); there is no holiday calendar yet (OPEN_ITEMS 3); and the
spread-aware stop check is still waiting for its go (OPEN_ITEMS 1).
Pipeline for this module: READ-ONLY -> RECORD -> SHADOW -> TEST -> VALIDATE. Evidence before
any rule change (n < 20 is luck, ~100 to judge).

## 0. The laws this module keeps (the same as the other three)

* Read-only indicator. MT5 -> JSON (FILE_COMMON) -> Python -> Telegram. No WebRequest, sockets,
  OrderSend, CTrade, position changes. `mt5_order_action: "NONE"`.
* No self-modification, no AI rewriting rules, no LLM in the decision path.
* Closed candles only. A forming candle is PREVIEW ONLY / NEVER A SIGNAL. Before the close = UNKNOWN.
* A level is a battlefield, never a BUY or SELL by itself.
* Stale data = no state (Freshness Law). Missing news = UNKNOWN, never "no risk".
* Correlation is not a signal. News direction is UNKNOWN unless validated.

## 1. Files

| File | What happens to it |
|---|---|
| `NRTR_BOSS_LearningPanel.mq5` (metals), `NRTR_BOSS_Crypto_NYTrap.mq5`, `NRTR_BOSS_Forex_NYTrap.mq5` | **Unchanged.** Proven by the existing "existing panel unchanged" dumps, twin check and all current suites, run unmodified. |
| **`NRTR_BOSS_US100.mq5`** (new) | The US index / equity panel. US100 first. |

The new file **reuses byte-identical shared blocks** (checked by `check_bridge_blocks.py` /
`check_fq_blocks.py`, extended to four files):
NRTR / ATR / EMA engine, the 15M boss + 5M timing (NbRun15 / NbRun5), the freshness gate (two
witnesses), the NY clock (server offset from two witnesses + US DST per day), the click guard, lots
(`NbLotsForRisk`), the MARKET chip (`NB_MK`), the bridge writer (`NB_BR`).

It gets **its own blocks**, which exist only in this file:
* `NB_US_SESS` - the US session calendar.
* `NB_US_LV` - the US level map.
* `NB_US_CTX` - context: peers and news (display only).
* `NB_US_PLAN` - location filter + entry / SL / TP / R:R.
* `NbUsParams` - all asset parameters (`InpUs*`), separate from the metals ones.

The symbol filter accepts USTEC, US100, NAS100, NDX, USTECH (and later a list of stocks); anything
else = "US INDEX / EQUITY ONLY", as the twins do.

## 2. The layers (one row each on the panel)

```
MARKET DATA -> REGIME / DIRECTION -> IMPORTANT LEVELS -> PRICE REACTION -> CONFIRMATION -> RISK / R:R -> WAIT or SETUP
```

### 2.1 Session (context label only - no rule changes by session at first)

All in **New York time**, converted per bar through the US DST calendar (never one scalar offset).

| State | ET | Note |
|---|---|---|
| OVERNIGHT | 18:00-04:00 | USTEC CFDs trade almost 23 h; this is futures overnight, labelled as such |
| PRE-MARKET | 04:00-09:30 | kept separate from the regular session everywhere |
| OPEN 0-5 / 5-15 / 15-30 min | 09:30-10:00 | three labels |
| MORNING | 10:00-11:30 | |
| LUNCH / LOW LIQUIDITY | 11:30-13:30 | |
| AFTERNOON | 13:30-15:00 | |
| FINAL HOUR | 15:00-16:00 | |
| CLOSE / AFTER-HOURS | 16:00-18:00 | includes the daily break |
| CLOSED | weekend, US holiday | holiday list = data, dated; missing year = "HOLIDAY CALENDAR UNKNOWN" |

Every shadow record carries its session label, so session TP / SL can be measured later
(OPEN_ITEMS item 2).

### 2.2 Direction

* The 15M boss is the primary intraday direction: **BUY / SELL / WAIT / MIXED / UNKNOWN**.
* It uses its own `InpUs*` parameters. The starting values equal the metals ones and are labelled
  "starting values, not validated for US100".
* 1H / 4H come from the regime engine (`NB_RP`), as context.

### 2.3 US level map (all causal, each published only once its window has ENDED)

| Level | Definition |
|---|---|
| PDH / PDL | previous **regular session** (09:30-16:00 ET) high / low, not the broker day |
| PREV CLOSE | the last regular-session close (the 15:55 ET 5M bar) |
| PM H / L | pre-market 04:00-09:30 ET high / low, labelled PRE-MARKET |
| OPEN | the 09:30 ET open |
| OR5 / OR15 / OR30 | opening range high / low, published at 09:35 / 09:45 / 10:00 |
| RTH H / L | regular-session high / low so far (live, labelled "so far") |
| Swing H / L | confirmed 5M / 15M swings |
| GAP | OPEN vs PREV CLOSE, in points, % and ATR: GAP UP / DOWN / NONE, and FILLED / OPEN |
| VWAP | **OFF by default for USTEC**: an index CFD has tick volume only, so a VWAP would be a tick-volume proxy and must be labelled so. For stocks, only when `real_volume` > 0. |

### 2.4 Price reaction and confirmation (5M, closed candles only)

* The reaction types are sweep, rejection, breakout (close beyond the level with a body), retest,
  continuation and reversal.
* **Gap rule (new):** a level crossed by the opening gap is marked GAPPED THROUGH. It is never a
  sweep and never a breakout confirmation, because no trade printed between the two prices. See
  section 5: the current files lack this rule.

### 2.5 Location and risk

* **PRICE IN THE MIDDLE - NO ENTRY HERE** when the close is more than `InpUsMidAtr` from the
  nearest mapped level on both sides.
* **PRICE TOO FAR - WAIT FOR RE-ENTRY - DO NOT CHASE**: the existing click guard.
* The plan shows ENTRY -> SL -> TP1 -> TP2 -> R:R.
  * The SL sits beyond the reaction extreme plus a buffer.
  * TP1 / TP2 = the next mapped levels.
  * Below `InpUsMinRR` the plan is rejected ("REWARD TOO SMALL").
* Spread-aware check (OPEN_ITEMS item 1): risk < 3 x spread = "SL INSIDE SPREAD NOISE". This
  matters more on the US100 open, where spreads widen.
* Lots use the broker volume step and its decimals (index 0.1 / 0.01, stocks 1 share).

### 2.6 Context layer (optional, display + JSON only)

* **Peers** (`InpUsPeers` = "NVDA,AMD,AVGO,MSFT", off by default): each peer's % from its previous
  close and its 15M boss, when MT5 has the symbol. JSON `context.peers[]` with
  `"not_a_signal": true`.
  * **The decision code never reads it.** A test proves the panel and signal are identical with
    peers on, off or garbage.
* **News:** from MT5's economic calendar (USD, high importance: CPI, NFP, FOMC, Fed speakers).
  * Shown as "NEWS WINDOW: CPI 08:30 ET - direction UNKNOWN".
  * An empty or unavailable calendar = NEWS UNKNOWN, never "no news".
  * Earnings (for stocks) are not in the MT5 calendar. They come from a dated input list; a stock
    with no list = EARNINGS UNKNOWN.
  * Direction is always UNKNOWN. The only outcome is a label; it never flips direction.

### 2.7 Records (the evidence)

* Each plan is replayed to TP1 / SL / expired, as the five-question table does.
* Each record carries the session label, gap state, level source, spread at the signal, and
  whether news was inside the window.
* No record changes a rule. The report shows n per cell (Evidence Law; split sample = smaller sample).

## 3. Phase 2 - individual AI / semiconductor stocks (after US100 is validated)

* The same file, with per-symbol parameter sets.
* Stock CFDs usually trade only the regular session. Pre-market is then UNKNOWN (not "none").
* Earnings gaps: the gap rule plus an "EARNINGS DAY" label. Plans on earnings day are recorded
  separately, never pooled.

## 4. Test plan (new suite `tests/test_us100.cpp`, simulator with an ET calendar)

| ID | Test | Proof |
|---|---|---|
| U1 | Pre-market vs regular session | a pre-market spike never moves PDH / PDL, RTH H/L or OR; PM H/L never includes 09:30+ bars |
| U2 | Previous-day H/L | = previous 09:30-16:00 ET session, across a weekend, a US holiday and both DST switches (hand-computed) |
| U3 | Opening range | OR5/15/30 are 0 until the window ends and exact after it; a missing bar = not published |
| U4 | Gap handling | gap up / down / none in points, %, ATR; FILLED when price trades back to prev close; a level crossed by the gap = GAPPED THROUGH, never a sweep or breakout |
| U5 | Sweep vs confirmed break | a pierce and close back = sweep; a close beyond with a body that holds = break; a wick-only = neither |
| U6 | Retest | a limit at the broken level fills on the retest only; TP1 before fill = MISSED |
| U7 | 15M / 5M causal alignment | a 5M bar only sees the 15M bar that has CLOSED; append-future-bars test: nothing in the past changes |
| U8 | Stale data | frozen feed / weekend / holiday -> WAIT, no levels as live, no chip, no context |
| U9 | Price too far | READY only within the band; +/-0.8R = TOO FAR; no price = never READY; PRICE IN THE MIDDLE when away from all levels |
| U10 | No forming-candle signal | a forming crash / spike bar changes no signal, level or record |
| U11 | Broker volume step | steps 1, 0.1, 0.01, 0.005: never above budget, never rounded up; loss tick value used |
| U12 | SL / TP / R:R | hand-computed levels; SL on the wrong side = rejected; R:R below min = rejected; TP = next mapped level |
| U13 | No cross-asset inference | the signal, panel and records are identical with peers on / off / garbage values |
| U14 | News direction UNKNOWN | an empty calendar = NEWS UNKNOWN; a CPI in the window = label only; the direction output never changes with news on / off |
| U15 | DST | the week the US and EU switch on different dates: the OPEN stays 09:30 ET |
| U16 | No execution | the source contains no OrderSend / CTrade / WebRequest / socket; JSON `mt5_order_action` "NONE" |
| U17 | The other three are unchanged | every existing suite, dump, twin and block check passes unmodified |

Plus mutations for each of U1-U14 (a planted bug must be caught), as for the other files.

## 5. Finding in the CURRENT metals / forex files: they have no gap concept

Asked by Shyam on 2026-09-27 ("today Asia EURUSD gap down"). This is in the code today and is
**not changed by this proposal**:

1. **ATR jumps after a gap.** Wilder ATR uses the true range with the previous close
   (`NbCalcATR`). Monday's first bar carries the whole weekend gap, so ATR, the NRTR trail and the
   SL buffers are wider for the first hours, until the ATR decays (period 14).
2. **A gap across a level can count as a sweep or a breakout** in the five-question engine.
   * Sweep: `s5.l[j] < L && s5.c[j - 1] > L`, where `c[j-1]` is Friday's close.
   * Breakout: `s5.c[j] < L && s5.c[j - 1] >= L`, with a body.
   * A gap below Friday's low (PDL) satisfies both, although nobody traded between the two prices.
3. **The replay fills at the level's price even when the price gapped through.**
   * A gapped SL fills worse in reality, so the recorded -1R is optimistic.
   * A gapped buy limit fills better in reality.
4. **Handled already:** freshness (a session break is not stale data). PDH / PDL on Monday = Friday
   on a UTC+2 / +3 broker. On a UTC+0 broker, the 2-hour Sunday session would become the "previous
   day". That is not Shyam's broker, but it is noted.

**Proposal (measure first):** record `after_gap` on each plan (the first N bars after a gap larger
than X ATR), and count those plans separately. Only if they behave differently (n >= 20 per cell),
add a GAPPED-THROUGH rule to the metals / forex files as a new, tested version.

## 6. Decisions needed before building

1. **Pre-market for USTEC:** label OVERNIGHT (18:00-04:00 ET) and PRE-MARKET (04:00-09:30 ET)
   separately? (recommended), or one "pre-market" from 18:00?
2. **VWAP on USTEC:** keep it off (recommended; tick volume only), or show it labelled "tick-volume
   proxy"?
3. **The NY trap on US100:** do not copy it (recommended). The US level map (PM H/L, OR, gap) covers
   the same idea with US definitions, and it runs as a shadow first.
4. **Peers context in v1:** off by default and US100 only (recommended), with the peer list added
   in phase 2.
