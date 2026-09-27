# Data bridge: MT5 → Telegram (v1.07)

The indicator on your MT5 chart **writes a file**. This small Python script **reads the file and
posts a message to your own Telegram chat** when the MT5 conclusion changes. You read the message
and place the trade yourself, or skip it.

```
MT5 chart (indicator)  ──writes──►  ...\Common\Files\NRTR_BRIDGE\BTCUSD.json
                                             │
nrtr_telegram_sender.py  ──reads──┘  ──posts──►  your Telegram chat  ──►  you decide
```

* MT5 does **not** let an indicator use the internet, so the indicator never sends anything. It
  only writes the file.
* The script only reads the files and talks to `api.telegram.org`. It never talks to MT5, a broker,
  an executor or any trading bot. No order is ever placed by anything here.

## What the file contains (kept apart on purpose)

| Section | What |
|---|---|
| `raw` | the last **18 CLOSED** candles of M5 and M15 (time, O/H/L/C, tick volume, body), plus the **FORMING** candle, marked `confirmed: false` and "PREVIEW ONLY" |
| `indicators` | one row per closed candle: NRTR direction / stop / flip, ATR; on M15 also EMA200 and the boss; on M5 the 5M state and the 15M boss at that bar |
| `structure` | M15: HH/HL or LH/LL, last swing high / low, boss mode and why. M5: the same, from its own confirmed swings |
| `mt5_signal` | **the MT5 CONCLUSION**, separate from the data above: boss, timing, `action` (CLICK BUY / CLICK SELL / WAIT / NO TRADE - DATA STALE), the signal's entry / SL / TP1 / TP2, the NY module, the 5-question pending plan, the counter-trend WATCH (`not_a_signal: true`), your open positions (read only), and `change_key` |

The file is rewritten on every new closed 5M candle and every 10 seconds (input
`InpBridgeEverySec`), so the forming candle stays current. Stale data is written as stale.

## Gold / silver (v1.08)

The metals file writes the same file, plus `mt5_signal.ny`: the clock it used, the verdict
("NY TRAP vs 15M BOSS = CONFLICT - NO TRADE", "... VALID - CLICK ...", ...), the window, the
pre-NY and NY high / low, and NY TRAP SELL and BUY with state, why, entry (`entry_is_reference`
before the trigger), SL, TP1 and TP2. It also writes `mt5_signal.market_state` (SUPER BULLISH ...
SUPER BEARISH: a description, never a signal). The message prints them in the conclusion part.

## Setup (Windows, once)

1. **Make a Telegram bot:** in Telegram, talk to **@BotFather** → `/newbot` → copy the token.
2. **Find your chat id:** send any message to your new bot, then open
   `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser and copy `"chat":{"id": ...}`.
3. **Install Python 3.8+** (python.org). Nothing else is needed; the script uses the standard
   library only.
4. **Set the two values** in a Command Prompt. Never put the token in a file you share or commit:
   ```
   setx TELEGRAM_BOT_TOKEN "123456:ABC..."
   setx TELEGRAM_CHAT_ID "987654321"
   ```
   Then close the window and open a new one.
5. **Test:** `python nrtr_telegram_sender.py --test-message` should put "connection OK" in your chat.
6. **Run:** `python nrtr_telegram_sender.py`. Leave the window open; Ctrl+C stops it.

The script looks in `%APPDATA%\MetaQuotes\Terminal\Common\Files\NRTR_BRIDGE` by default. That is
MT5's shared folder for all terminals (the indicator writes there with `FILE_COMMON`). A different
folder: `--dir "D:\path\NRTR_BRIDGE"`.

## When a message comes

* **One message per change** of `mt5_signal.change_key`: the final action, the live signal, the
  15M boss, the 5M timing, the 5-question plan, an open WATCH, the NY phase, fresh / stale, or the
  number of positions. The same state is never posted twice. The last sent keys are kept in
  `nrtr_sender_state.json` next to the script.
* **DATA STALE** once if a file stops being rewritten for 90 s (`--stale-sec`): the chart is
  closed, the terminal is off, or there are no ticks. It never repeats an old action.
* If Telegram cannot be reached, nothing is remembered, so the same message is sent on the next
  pass.

## Try it without Telegram

```
python nrtr_telegram_sender.py --dry-run --once
```
prints exactly what would be posted.

## Honest limits

* The **counter-trend WATCH** is a hypothesis, never a signal. Counter-trend entries are the #1
  documented loss driver in this system. It is recorded (n, TP1, SL, expired, net R) so the
  Evidence Law can judge it: n < 20 is luck, about 100 to decide.
* A Telegram message can arrive seconds late. The price in it is the price when the file was
  written (`written_server`).
* The script must run on a PC that can see the MT5 Common Files folder, normally the same PC as MT5.
