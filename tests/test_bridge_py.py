#!/usr/bin/env python3
"""v1.07 data bridge, the Python side.

1. The JSON the indicator wrote under the simulator (build/bridge_<tag>.json,
   written by tests/test_bridge.cpp) is compared, number by number, with the
   EXPECTED file the same test wrote from the raw simulated history and an
   independent engine run (build/bridge_expect_<tag>.json).
2. bridge/nrtr_telegram_sender.py: message layout and length, one message
   per change, stale files, broken files, dry run, and the bot token never
   reaching the output. No test touches the network: urlopen is replaced by
   a function that fails the test if it is ever called unexpectedly.

usage: python3 tests/test_bridge_py.py crypto [forex ...]   (after test_bridge.cpp ran)
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "bridge"))
import nrtr_telegram_sender as snd  # noqa: E402

TAGS = []
SIDE = {1: "BUY", -1: "SELL", 0: "WAIT"}
MODE = {1: "BUY MODE", -1: "SELL MODE", 0: "WAIT"}
DIR = {1: "BULLISH", -1: "BEARISH", 0: None}


def load(name):
    with open(os.path.join(ROOT, "build", name), encoding="ascii") as f:
        return json.load(f)


def keys_deep(o):
    if isinstance(o, dict):
        for k, v in o.items():
            yield k
            yield from keys_deep(v)
    elif isinstance(o, list):
        for v in o:
            yield from keys_deep(v)


class BridgeFile(unittest.TestCase):
    """The file = the history and the engine, exactly."""

    def check_pair(self, tag, got_name, exp_name):
        d, e = load(got_name), load(exp_name)
        eps = 0.5 * 10 ** -e["digits"]
        self.assertEqual(d["schema"], "nrtr_bridge/1")
        self.assertEqual((d["symbol"], d["market"], d["digits"]), (e["symbol"], e["market"], e["digits"]))
        self.assertEqual(list(d.keys())[-4:], ["raw", "indicators", "structure", "mt5_signal"])
        for sec in ("raw", "indicators", "structure"):
            self.assertFalse({"action", "final", "signal", "change_key"} & set(keys_deep(d[sec])),
                             f"{tag}: a conclusion key inside '{sec}' - the MT5 conclusion must stay separate")
        for tf in ("m5", "m15"):
            got, exp = d["raw"][tf]["closed"], e[f"{tf}_closed"]
            self.assertEqual(len(got), 18, f"{tag} {tf}: 18 closed candles")
            self.assertEqual([c["ts"] for c in got], [c["ts"] for c in exp], f"{tag} {tf}: the LAST 18 CLOSED bars, oldest first")
            for g, x in zip(got, exp):
                for k in "ohlc":
                    self.assertLessEqual(abs(g[k] - x[k]), eps, f"{tag} {tf} {g['t']} {k}")
                self.assertIn(g["body"], ("BULLISH", "BEARISH", "DOJI"))
            fm, xf = d["raw"][tf]["forming"], e[f"{tf}_forming"]
            self.assertIsNotNone(fm)
            self.assertEqual(fm["ts"], xf["ts"], f"{tag} {tf}: forming = the bar containing now")
            self.assertNotIn(fm["ts"], [c["ts"] for c in got], f"{tag} {tf}: the forming bar is never in 'closed'")
            self.assertIs(fm["confirmed"], False)
            self.assertIn("PREVIEW ONLY", fm["note"])
            for k in "ohlc":
                self.assertLessEqual(abs(fm[k] - xf[k]), eps)
            self.assertTrue(0 < fm["seconds_left"] <= (300 if tf == "m5" else 900))
            ind = d["indicators"][tf]["per_closed_candle"]
            xi = e[f"{tf}_ind"]
            self.assertEqual([c["t"] for c in ind], [c["t"] for c in got], f"{tag} {tf}: one indicator row per raw candle, same times")
            self.assertEqual(len(xi), 18)
            for g, x in zip(ind, xi):
                self.assertEqual(g["nrtr_dir"], DIR[x["dir"]])
                self.assertLessEqual(abs(g["nrtr_stop"] - x["stop"]), eps)
                self.assertLessEqual(abs(g["atr"] - x["atr"]), 0.5 * 10 ** -(e["digits"] + 1))
                if tf == "m15":
                    self.assertLessEqual(abs(g["ema200"] - x["ema"]), eps)
                    self.assertEqual(g["boss"], SIDE[x["mode"]])
                else:
                    self.assertNotIn("ema200", g, "the 5M engine has no EMA - none is invented")
                    self.assertEqual(g["state"], SIDE[x["state"]])
                    self.assertEqual(g["boss_15m"], SIDE[x["boss"]])
        s = d["mt5_signal"]
        self.assertEqual(s["boss_15m"], MODE[e["boss"]])
        self.assertEqual(s["timing_5m"], SIDE[e["state"]])
        self.assertEqual(d["structure"]["m15"]["boss"], MODE[e["boss"]])
        self.assertTrue(s["fresh"])
        allowed = ("CLICK BUY", "CLICK SELL", "WAIT - NO TRADE", "READY - CLICK BUY", "READY - CLICK SELL",
                   "BUY SETUP - PRICE TOO FAR - WAIT FOR RE-ENTRY", "SELL SETUP - PRICE TOO FAR - WAIT FOR RE-ENTRY")
        self.assertIn(s["action"], allowed)
        self.assertEqual(s["action"] != "WAIT - NO TRADE", s["final"] in ("BUY", "SELL"), "a BUY / SELL action only with a BUY / SELL final")
        pw = s["pullback_watch"]
        self.assertIs(pw["not_a_signal"], True)
        for k in ("n", "tp1", "sl", "expired"):
            self.assertEqual(pw["record"][k], e["pw_record"][k], f"{tag}: watch record {k}")
        if e["pw_open"] is None:
            self.assertEqual(pw["state"], "NONE")
        else:
            self.assertEqual(pw["state"], "OPEN")
            self.assertEqual(pw["side"], SIDE[e["pw_open"]["dir"]])
            for k, x in (("ref_entry", "entry"), ("ref_sl", "sl"), ("ref_tp1", "tp1")):
                self.assertLessEqual(abs(pw[k] - e["pw_open"][x]), eps)
        self.assertTrue(s["change_key"].startswith("F|"))
        if e["market"] == "METALS":
            self.check_metals(tag, d, e, eps)
        return d

    def check_metals(self, tag, d, e, eps):
        """Gold / silver: the NY trap layer and the market state = the independent engine run."""
        self.assertEqual(d["source"], "NRTR_BOSS_LearningPanel")
        s = d["mt5_signal"]
        ny = s["ny"]
        self.assertTrue(ny["clock"].startswith("AUTO: server = UTC+3.0"), f"{tag}: the clock says how it was proven: {ny['clock']}")
        self.assertIn("verdict", ny)
        if s["boss_15m"] == "WAIT":
            self.assertNotIn("CLICK", ny["verdict"], "no CLICK with the 15M boss in WAIT")
        if e["ny_session"]:
            for side in ("sell", "buy"):
                g, x = ny[side], e["ny_" + side]
                self.assertEqual((g["state"], g["why"]), (x["state"], x["why"]), f"{tag} NY {side}: state and why")
                if x["has_prices"]:
                    for k in ("entry", "sl", "tp1", "tp2"):
                        self.assertLessEqual(abs(g[k] - x[k]), eps, f"{tag} NY {side} {k}")
                    self.assertEqual(g["entry_is_reference"], x["ref"])
                else:
                    self.assertIsNone(g["entry"])
            if e["pre_ny_high"] > 0:
                self.assertLessEqual(abs(ny["pre_ny_high"] - e["pre_ny_high"]), eps)
                self.assertLessEqual(abs(ny["pre_ny_low"] - e["pre_ny_low"]), eps)
        ms = s["market_state"]
        self.assertEqual(ms["state"], e["market_state"], f"{tag}: market state = the engine's")
        self.assertIn("never a signal", ms["note"])

    def test_files(self):
        for tag in TAGS:
            with self.subTest(tag=tag):
                self.check_pair(tag, f"bridge_{tag}.json", f"bridge_expect_{tag}.json")
                d = self.check_pair(tag, f"bridge_watch_{tag}.json", f"bridge_expect_watch_{tag}.json")
                self.assertEqual(d["mt5_signal"]["pullback_watch"]["state"], "OPEN", "the watch fixture really has an open watch")
                if tag in ("gold", "silver"):
                    d = self.check_pair(tag, f"bridge_ny_{tag}.json", f"bridge_expect_ny_{tag}.json")
                    states = {d["mt5_signal"]["ny"]["sell"]["state"], d["mt5_signal"]["ny"]["buy"]["state"]}
                    self.assertTrue(states & {"VALID", "TRIGGERED"}, "the NY fixture really has a swept / triggered trap with prices")

    def test_same_schema_in_all_files(self):
        """One bridge schema for crypto, forex and metals (null where a file has nothing)."""
        files = [load(f"bridge_{t}.json") for t in TAGS]
        top = [list(d.keys()) for d in files]
        self.assertTrue(all(k == top[0] for k in top), f"top-level keys differ: {top}")
        sig = [list(d["mt5_signal"].keys()) for d in files]
        self.assertTrue(all(k == sig[0] for k in sig), f"mt5_signal keys differ: {sig}")
        for part in ("closed", "forming"):
            ks = [list((d["raw"]["m5"][part][0] if part == "closed" else d["raw"]["m5"][part]).keys()) for d in files]
            self.assertTrue(all(k == ks[0] for k in ks), f"raw {part} candle keys differ")
        for d in files:
            self.assertEqual(d["mt5_order_action"], "NONE")
            self.assertIs(d["read_only"], True)
            for tf in ("m5", "m15"):
                for c in d["raw"][tf]["closed"]:
                    self.assertEqual((c["forming"], c["confirmed"]), (False, True))
                    self.assertIsNone(c["real_volume"], "no real volume in the fixture: null, never 0")
                f = d["raw"][tf]["forming"]
                self.assertEqual((f["forming"], f["confirmed"]), (True, False))
                self.assertEqual(f["note"], "FORMING / PREVIEW ONLY / NEVER A SIGNAL")
                self.assertTrue(0 <= f["age_seconds"] < (300 if tf == "m5" else 900))
            self.assertIsNotNone(d["bid"])
            self.assertTrue(d["spread_points"] is None or isinstance(d["spread_points"], int))

    def test_stale_file(self):
        for tag in TAGS:
            with self.subTest(tag=tag):
                s = load(f"bridge_stale_{tag}.json")["mt5_signal"]
                self.assertIs(s["fresh"], False)
                self.assertEqual(s["action"], "NO TRADE - DATA STALE / MARKET CLOSED")
                self.assertIsNone(s["signal"])
                self.assertEqual(s["pullback_watch"]["state"], "NONE")
                # v1.10: every file - no market state and no regime pullback from stale data
                self.assertEqual(s["market_state"]["state"], "---")
                self.assertEqual(s["regime_pullback"]["state"], "SUPPRESSED - DATA STALE")
                self.assertIsNone(s["regime_pullback"]["candidate"])
                if tag in ("gold", "silver"):   # the metals NY trap layer: no NY prices from stale data
                    self.assertIsNone(s["ny"]["sell"])
                    self.assertIn("DATA STALE", s["ny"]["verdict"])


def no_network(*a, **k):
    raise AssertionError("the network was touched")


class Sender(unittest.TestCase):
    def setUp(self):
        self._orig = urllib.request.urlopen
        urllib.request.urlopen = no_network
        self.tmp = tempfile.mkdtemp()
        self.src = load(f"bridge_watch_{TAGS[0]}.json")

    def tearDown(self):
        urllib.request.urlopen = self._orig

    def put(self, d, name=None, age=0.0):
        p = os.path.join(self.tmp, name or (d["symbol"] + ".json"))
        with open(p, "w", encoding="ascii") as f:
            json.dump(d, f)
        t = time.time() - age
        os.utime(p, (t, t))
        return p

    def test_message_layout(self):
        m = snd.format_message(self.src, False)
        self.assertLessEqual(len(m), snd.TELEGRAM_LIMIT)
        a, b = m.find("== MT5 SIGNAL (conclusion) =="), m.find("== RAW DATA ==")
        self.assertTrue(0 < a < b, "the conclusion first, the raw data after it, apart")
        self.assertIn("ACTION: " + self.src["mt5_signal"]["action"], m)
        self.assertIn("WATCH (NOT A SIGNAL): counter-trend", m)
        self.assertIn("PREVIEW ONLY", m)
        body = m[m.find("-- M5"):]
        self.assertEqual(sum(1 for ln in body.splitlines() if " O" in ln and "FORMING" not in ln), 18, "18 closed M5 lines")
        self.assertIn("Nothing was sent to any broker", m)
        self.assertIn("FULL DATA: JSON = 18 CLOSED + FORMING per timeframe (M5, M15)", m, "a shortened message is labelled")
        self.assertIn("MT5 ORDER ACTION: NONE", m)

    def test_metals_message(self):
        if not os.path.exists(os.path.join(ROOT, "build", "bridge_ny_gold.json")):
            self.skipTest("metals files not built")
        d = load("bridge_ny_gold.json")
        m = snd.format_message(d, False)
        self.assertLessEqual(len(m), snd.TELEGRAM_LIMIT)
        ny = d["mt5_signal"]["ny"]
        self.assertIn("NY VERDICT: " + ny["verdict"], m)
        self.assertIn(f"NY TRAP SELL: {ny['sell']['state']}", m)
        self.assertIn(f"NY TRAP BUY: {ny['buy']['state']}", m)
        self.assertIn("MARKET: " + d["mt5_signal"]["market_state"]["state"], m)
        self.assertIn("a description, not a signal", m)
        rp = d["mt5_signal"]["regime_pullback"]
        self.assertIn("PULLBACK WATCH (shadow, not a signal): " + rp["state"], m)
        self.assertIn("DIRECTION: " + rp["direction"]["regime"], m)
        self.assertLess(m.find("== MT5 SIGNAL"), m.find("NY VERDICT"), "NY and market state sit in the conclusion part")
        self.assertLess(m.find("NY VERDICT"), m.find("== RAW DATA =="))

    def test_message_fits_telegram(self):
        d = json.loads(json.dumps(self.src))
        for c in d["raw"]["m5"]["closed"] + d["raw"]["m15"]["closed"]:
            c["o"] = c["h"] = c["l"] = c["c"] = 123456789.123456
        d["mt5_signal"]["reason"] = "X" * 900
        m = snd.format_message(d, False)
        self.assertLessEqual(len(m), snd.TELEGRAM_LIMIT)
        self.assertIn("== MT5 SIGNAL", m, "the conclusion survives; candles are cut first")

    def test_one_message_per_change(self):
        p = self.put(self.src)
        out, state = [], {}
        self.assertEqual(snd.one_pass(self.tmp, state, out.append, time.time(), 90, 18), 1, "first sight: one message")
        self.assertEqual(snd.one_pass(self.tmp, state, out.append, time.time(), 90, 18), 0, "nothing changed: silent")
        d = json.loads(json.dumps(self.src))
        d["mt5_signal"]["change_key"] = "F|1|7.1|1|1|-|-|0|0"
        d["mt5_signal"]["action"] = "CLICK BUY"
        self.put(d)
        self.assertEqual(snd.one_pass(self.tmp, state, out.append, time.time(), 90, 18), 1, "the conclusion changed: one message")
        self.assertIn("ACTION: CLICK BUY", out[-1])
        t = time.time() - 600
        os.utime(p, (t, t))
        self.assertEqual(snd.one_pass(self.tmp, state, out.append, time.time(), 90, 18), 1, "file stopped updating: one STALE message")
        self.assertIn("DATA STALE", out[-1])
        self.assertNotIn("CLICK", out[-1], "a stale file never repeats an old action")
        self.assertEqual(snd.one_pass(self.tmp, state, out.append, time.time(), 90, 18), 0, "still stale: silent")
        self.put(d)
        self.assertEqual(snd.one_pass(self.tmp, state, out.append, time.time(), 90, 18), 1, "back: one message")

    def test_broken_and_foreign_files_are_skipped(self):
        with open(os.path.join(self.tmp, "BAD.json"), "w") as f:
            f.write('{"schema": "nrtr_bridge/1", "raw": ')     # half written
        self.put({"hello": 1}, "OTHER.json")
        out = []
        self.assertEqual(snd.one_pass(self.tmp, {}, out.append, time.time(), 90, 18), 0)

    def test_dry_run_prints_and_never_sends(self):
        self.put(self.src)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = snd.main(["--dir", self.tmp, "--once", "--dry-run", "--state", os.path.join(self.tmp, "st.json")])
        self.assertEqual(rc, 0)
        self.assertIn("== MT5 SIGNAL", buf.getvalue())

    def test_token_never_printed(self):
        token = "123456:SECRET-TOKEN-abcdef"
        os.environ["TELEGRAM_BOT_TOKEN"] = token
        os.environ["TELEGRAM_CHAT_ID"] = "42"
        calls = []

        def fail(req, timeout=0):
            calls.append(req.full_url)
            raise urllib.error.URLError(f"could not reach {req.full_url}")

        urllib.request.urlopen = fail
        self.put(self.src)
        st = os.path.join(self.tmp, "st.json")
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                snd.main(["--dir", self.tmp, "--once", "--state", st])
        finally:
            del os.environ["TELEGRAM_BOT_TOKEN"], os.environ["TELEGRAM_CHAT_ID"]
        self.assertEqual(len(calls), 1, "it tried to send once")
        self.assertTrue(calls[0].startswith("https://api.telegram.org/bot"), "only Telegram's API")
        self.assertNotIn(token, buf.getvalue(), "the token never reaches the output")
        self.assertIn("<token>", buf.getvalue())
        self.assertFalse(os.path.exists(st), "a failed send is not remembered: it is sent again next time")

    def test_no_credentials_no_run(self):
        os.environ.pop("TELEGRAM_BOT_TOKEN", None)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = snd.main(["--dir", self.tmp, "--once", "--state", os.path.join(self.tmp, "st.json")])
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    TAGS[:] = [a for a in sys.argv[1:] if not a.startswith("-")] or ["crypto"]
    sys.argv = sys.argv[:1] + [a for a in sys.argv[1:] if a.startswith("-")]
    r = unittest.main(exit=False, verbosity=1).result
    n = r.testsRun
    bad = len(r.failures) + len(r.errors)
    print(f"BRIDGE PYTHON TESTS ({', '.join(TAGS)}): {n - bad} of {n} passed")
    sys.exit(0 if bad == 0 and n > 0 else 1)
