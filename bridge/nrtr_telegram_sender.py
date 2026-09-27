#!/usr/bin/env python3
"""NRTR BOSS data bridge -> Telegram (v1.07).

Reads the JSON files the MT5 indicators write to the terminals' COMMON
Files folder (NRTR_BRIDGE\\<SYMBOL>.json) and posts ONE Telegram message
per symbol whenever the MT5 conclusion changes (mt5_signal.change_key),
or when a file goes stale / comes back.

It only READS those files and SENDS text to your own Telegram chat.
It never talks to MT5, a broker, an executor or any trading bot; you read
the message and place (or skip) the trade yourself.

Setup (Windows, once):
    set TELEGRAM_BOT_TOKEN=<token from @BotFather>      (never put it in a file you share)
    set TELEGRAM_CHAT_ID=<your chat id>
    python nrtr_telegram_sender.py --test-message       (checks the connection)
    python nrtr_telegram_sender.py                      (runs; Ctrl+C stops)

Options:
    --dir PATH       bridge folder (default: %APPDATA%\\MetaQuotes\\Terminal\\Common\\Files\\NRTR_BRIDGE)
    --once           one pass over the files, then exit
    --dry-run        print the messages instead of sending (no token needed)
    --interval S     seconds between passes (default 5)
    --stale-sec S    a file not rewritten for this long is STALE (default 90)
    --state FILE     where the last sent keys are kept (default: next to this script)
    --candles N      candles per timeframe in the message (default 18, max 18)
Standard library only (Python 3.8+).
"""
import argparse
import html
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TELEGRAM_LIMIT = 4096
API = "https://api.telegram.org/bot{token}/sendMessage"


def default_dir() -> str:
    appdata = os.environ.get("APPDATA", os.path.expanduser("~"))
    return os.path.join(appdata, "MetaQuotes", "Terminal", "Common", "Files", "NRTR_BRIDGE")


def redact(text: str, token: str) -> str:
    """Never let the bot token reach a log line."""
    return text.replace(token, "<token>") if token else text


def load(path: str):
    """The parsed file, or None if it is missing or not valid JSON (next pass retries)."""
    try:
        with open(path, "r", encoding="ascii", errors="replace") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def file_stale(path: str, now: float, stale_sec: float) -> bool:
    try:
        return now - os.path.getmtime(path) > stale_sec
    except OSError:
        return True


def key_of(d: dict, stale: bool) -> str:
    """What decides whether a message is sent: the MT5 conclusion's key, or STALE."""
    if stale:
        return "FILE-STALE"
    return str(d.get("mt5_signal", {}).get("change_key", ""))


_DIGITS = [2]   # the symbol's digits, set per message


def _px(v) -> str:
    if v is None:
        return "---"
    if isinstance(v, float):
        return f"{v:.{_DIGITS[0]}f}"
    return str(v)


def _candles(raw_tf: dict, ind_tf: dict, n: int) -> list:
    closed = (raw_tf or {}).get("closed", [])[-n:]
    ind = {c.get("t"): c for c in (ind_tf or {}).get("per_closed_candle", [])}
    rows = []
    for c in closed:
        i = ind.get(c.get("t"), {})
        nr = {"BULLISH": "UP", "BEARISH": "DN"}.get(i.get("nrtr_dir"), "--")
        flip = " FLIP" if i.get("nrtr_flip") else ""
        body = {"BULLISH": "+", "BEARISH": "-", "DOJI": "="}.get(c.get("body"), "?")
        rows.append(f"{c.get('t', '')[-5:]} {body} O{_px(c.get('o'))} H{_px(c.get('h'))} L{_px(c.get('l'))} "
                    f"C{_px(c.get('c'))} {nr}{flip} ATR{i.get('atr', '---')}")
    fm = (raw_tf or {}).get("forming")
    if fm:
        rows.append(f"{fm.get('t', '')[-5:]} FORMING O{_px(fm.get('o'))} H{_px(fm.get('h'))} L{_px(fm.get('l'))} "
                    f"C{_px(fm.get('c'))} ({fm.get('preview_body', '?')} so far, {fm.get('seconds_left', '?')}s left) PREVIEW ONLY")
    return rows


def format_message(d: dict, stale: bool, candles: int = 18) -> str:
    """Telegram HTML text: the MT5 CONCLUSION first, then the raw data, kept apart."""
    sym = d.get("symbol", "?")
    _DIGITS[0] = int(d.get("digits", 2)) if str(d.get("digits", "")).isdigit() else 2
    head = f"NRTR BOSS  {sym}  ({d.get('market', '?')})  {d.get('written_server', '')} server"
    if stale:
        body = (f"<b>{html.escape(head)}</b>\n<b>DATA STALE</b> - MT5 has not rewritten this file lately "
                f"(chart closed, terminal off, or no ticks). Treat everything as NO TRADE until it comes back.")
        return body
    s = d.get("mt5_signal", {})
    lines = ["== MT5 SIGNAL (conclusion) =="]
    lines.append(f"ACTION: {s.get('action', '?')}")
    lines.append(f"MT5 ORDER ACTION: {d.get('mt5_order_action', 'NONE')} (read only - you place the order)")
    lines.append(f"15M BOSS: {s.get('boss_15m', '?')}   5M TIMING: {s.get('timing_5m', '?')}")
    if s.get("reason"):
        lines.append(f"why: {s.get('reason')}")
    if not s.get("fresh", False):
        lines.append(f"freshness: {s.get('freshness', '')}")
    sig = s.get("signal")
    if sig:
        lines.append(f"SIGNAL {sig.get('kind')} {sig.get('side')}  entry {_px(sig.get('entry'))}  SL {_px(sig.get('sl'))}  "
                     f"TP1 {_px(sig.get('tp1'))}  TP2 {_px(sig.get('tp2'))}")
    fq = s.get("five_question") or {}
    if fq:
        plan = fq.get("plan")
        if plan:
            lines.append(f"5-Q PLAN {fq.get('status')}: {plan.get('order')} {_px(plan.get('entry'))}  SL {_px(plan.get('sl'))}  "
                         f"TP1 {_px(plan.get('tp1'))}  TP2 {_px(plan.get('tp2'))}  R:R {plan.get('rr1')}")
        else:
            lines.append(f"5-Q PLAN: {fq.get('status')} - {fq.get('why')}")
    rp = s.get("regime_pullback")
    if isinstance(rp, dict) and rp.get("applicable"):
        dr = rp.get("direction") or {}
        lines.append(f"DIRECTION: {dr.get('regime')}  (4H {dr.get('h4')}, 1H {dr.get('h1')}, 15M {dr.get('m15_boss')})")
        why = f" - {rp.get('why')}" if rp.get("why") else ""
        lines.append(f"PULLBACK WATCH (shadow, not a signal): {rp.get('state')}{why}")
        loc = rp.get("location")
        if isinstance(loc, dict):
            yn = lambda v: "YES" if v else "no"
            lines.append(f"  1 pull {loc.get('pull_atr')} ATR  2 at structure {yn(loc.get('at_structure'))} ({_px(loc.get('structure_15m'))})  "
                         f"3 sweep {yn(loc.get('swept'))}  4 reject {yn(loc.get('rejection'))}  5 close {yn(loc.get('confirming_close'))}  "
                         f"6 R:R {loc.get('rr') if loc.get('rr') is not None else '--'} (min {loc.get('min_rr')})")
        cand = rp.get("candidate")
        if isinstance(cand, dict):
            lines.append(f"  {cand.get('side')} RE-ENTRY CANDIDATE: entry {_px(cand.get('entry'))}  SL {_px(cand.get('sl'))}  "
                         f"target {_px(cand.get('target'))}  R:R {cand.get('rr')}  (shadow)")
    ms = s.get("market_state")
    if isinstance(ms, dict):
        lines.append(f"MARKET: {ms.get('state')}  ({ms.get('detail')})  - a description, not a signal")
    ny = s.get("ny")
    if isinstance(ny, dict):
        if "phase" in ny:
            win = f" {ny.get('window')}" if ny.get("window") else ""
            lines.append(f"NY:{win} {ny.get('phase')}  pre-NY H {_px(ny.get('pre_ny_high'))} L {_px(ny.get('pre_ny_low'))}")
        if ny.get("verdict"):
            lines.append(f"NY VERDICT: {ny.get('verdict')}")
        for side in ("sell", "buy"):
            t = ny.get(side)
            if isinstance(t, dict):
                ref = " (ref)" if t.get("entry_is_reference") and t.get("entry") is not None else ""
                lines.append(f"NY TRAP {side.upper()}: {t.get('state')} - {t.get('why')}  E {_px(t.get('entry'))}{ref} SL {_px(t.get('sl'))} "
                             f"TP1 {_px(t.get('tp1'))} TP2 {_px(t.get('tp2'))}")
    pw = s.get("pullback_watch") or {}
    rec = pw.get("record", {})
    rtxt = f"record n={rec.get('n', 0)} TP1 {rec.get('tp1', 0)} / SL {rec.get('sl', 0)}  net {rec.get('net_r', 0)}R ({pw.get('evidence', '')})"
    if pw.get("state") == "OPEN":
        lines.append(f"WATCH (NOT A SIGNAL): counter-trend {pw.get('side')} ref {_px(pw.get('ref_entry'))} "
                     f"SL {_px(pw.get('ref_sl'))} TP1 {_px(pw.get('ref_tp1'))}  {rtxt}")
    else:
        lines.append(f"WATCH (NOT A SIGNAL): none  {rtxt}")
    pos = s.get("positions") or {}
    if pos.get("buy_count") or pos.get("sell_count"):
        lines.append(f"OPEN: BUY {pos.get('buy_count')} ({pos.get('buy_lots')} lots)  SELL {pos.get('sell_count')} ({pos.get('sell_lots')} lots)")
    st = d.get("structure", {})
    raw = d.get("raw", {})
    ind = d.get("indicators", {})
    m15i = (ind.get("m15", {}).get("per_closed_candle") or [{}])[-1]
    data = ["", "== RAW DATA ==", f"FULL DATA: JSON = {d.get('full_data', '18 CLOSED + FORMING')} - this message may show fewer"]
    data.append(f"15M structure: {st.get('m15', {}).get('state')}  swing H {_px(st.get('m15', {}).get('swing_high'))} "
                f"L {_px(st.get('m15', {}).get('swing_low'))}  EMA200 {_px(m15i.get('ema200'))}")
    data.append(f"5M structure: {st.get('m5', {}).get('state')}  swing H {_px(st.get('m5', {}).get('swing_high'))} "
                f"L {_px(st.get('m5', {}).get('swing_low'))}")
    for n in range(max(1, min(candles, 18)), 0, -1):
        m15 = _candles(raw.get("m15"), ind.get("m15"), n)
        m5 = _candles(raw.get("m5"), ind.get("m5"), n)
        block = data + ["-- M15 (closed, oldest first) --"] + m15 + ["-- M5 (closed, oldest first) --"] + m5
        text = (f"<b>{html.escape(head)}</b>\n<pre>" + html.escape("\n".join(lines)) + "</pre>\n<pre>" +
                html.escape("\n".join(block)) + "</pre>\nRead only. You decide and you place the order. Nothing was sent to any broker.")
        if len(text) <= TELEGRAM_LIMIT:
            if n < candles:
                text = text.replace("oldest first) --", f"oldest first, last {n}) --")
            return text
    return text[:TELEGRAM_LIMIT]


def send(token: str, chat: str, text: str, timeout: float = 15.0) -> None:
    data = urllib.parse.urlencode({"chat_id": chat, "text": text, "parse_mode": "HTML",
                                   "disable_web_page_preview": "true"}).encode()
    req = urllib.request.Request(API.format(token=token), data=data, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        if r.status != 200:
            raise RuntimeError(f"Telegram answered HTTP {r.status}")


def load_state(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            v = json.load(f)
            return v if isinstance(v, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(path: str, state: dict) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


def one_pass(folder: str, state: dict, emit, now: float, stale_sec: float, candles: int) -> int:
    """Look at every <SYMBOL>.json once; emit(text) for each change. Returns the number emitted."""
    sent = 0
    try:
        names = sorted(n for n in os.listdir(folder) if n.lower().endswith(".json"))
    except OSError:
        return 0
    for name in names:
        path = os.path.join(folder, name)
        d = load(path)
        if d is None or d.get("schema") != "nrtr_bridge/1":
            continue
        stale = file_stale(path, now, stale_sec)
        key = key_of(d, stale)
        sym = d.get("symbol", name[:-5])
        if state.get(sym) == key:
            continue
        emit(format_message(d, stale, candles))
        state[sym] = key
        sent += 1
    return sent


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="NRTR BOSS bridge files -> your Telegram chat (read only).")
    ap.add_argument("--dir", default=default_dir())
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--test-message", action="store_true")
    ap.add_argument("--interval", type=float, default=5.0)
    ap.add_argument("--stale-sec", type=float, default=90.0)
    ap.add_argument("--state", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "nrtr_sender_state.json"))
    ap.add_argument("--candles", type=int, default=18)
    a = ap.parse_args(argv)
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat = os.environ.get("TELEGRAM_CHAT_ID", "")
    if not a.dry_run and (not token or not chat):
        print("Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID first (or use --dry-run).")
        return 2

    def emit(text: str) -> None:
        if a.dry_run:
            print(text)
            print("-" * 60)
            return
        try:
            send(token, chat, text)
        except (urllib.error.URLError, OSError, RuntimeError) as e:
            print(redact(f"send failed: {e}", token))
            raise

    if a.test_message:
        try:
            emit("NRTR BOSS bridge: connection OK. Messages arrive when the MT5 conclusion changes.")
        except Exception:
            return 1
        print("test message sent" if not a.dry_run else "")
        return 0
    print(f"watching {a.dir} (stale after {a.stale_sec:.0f}s)")
    state = load_state(a.state)
    while True:
        try:
            n = one_pass(a.dir, state, emit, time.time(), a.stale_sec, a.candles)
            if n:
                save_state(a.state, state)
        except (urllib.error.URLError, OSError, RuntimeError):
            pass   # not saved: the same change is sent again on the next pass
        if a.once:
            return 0
        time.sleep(a.interval)


if __name__ == "__main__":
    sys.exit(main())
