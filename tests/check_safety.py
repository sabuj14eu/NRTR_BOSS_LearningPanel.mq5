#!/usr/bin/env python3
"""Static safety scan (test #13): the indicator must be unable to trade,
talk to the network, or touch anything outside its own chart objects."""
import re
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "NRTR_BOSS_LearningPanel.mq5"

FORBIDDEN = [
    # trading
    "OrderSend", "OrderSendAsync", "OrderCheck", "OrderModify", "OrderDelete", "OrderClose",
    "PositionOpen", "PositionClose", "PositionClosePartial", "PositionCloseBy", "PositionModify",
    "CTrade", "CPositionInfo", "COrderInfo", "MqlTradeRequest", "MqlTradeResult", "MqlTradeCheckResult",
    "TRADE_ACTION_DEAL", "TRADE_ACTION_PENDING", "TRADE_ACTION_SLTP", "TRADE_ACTION_MODIFY",
    "TRADE_ACTION_REMOVE", "TRADE_ACTION_CLOSE_BY", "BuyStop", "SellStop", "BuyLimit", "SellLimit",
    # network / messaging / external control
    "WebRequest", "SocketCreate", "SocketConnect", "SocketSend", "SendNotification", "SendMail",
    "SendFTP", "TerminalClose", "ChartSetSymbolPeriod", "ShellExecute", "#import", "#include",
    # files / global state (not needed by a panel)
    "FileOpen", "FileWrite", "GlobalVariableSet",
]
READ_ONLY_POSITION_API = {"PositionsTotal", "PositionGetTicket", "PositionGetString",
                          "PositionGetInteger", "PositionGetDouble"}


def strip_comments(code: str) -> str:
    code = re.sub(r"/\*.*?\*/", "", code, flags=re.S)
    code = re.sub(r'"(?:\\.|[^"\\])*"', '""', code)   # string literals can't call anything
    return re.sub(r"//[^\n]*", "", code)


def main() -> int:
    raw = open(SRC, "rb").read()
    fails = []
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError:
        fails.append("source is not pure ASCII")
        text = raw.decode("utf-8", "replace")
    code = strip_comments(text)
    for tok in FORBIDDEN:
        pat = re.escape(tok) if tok.startswith("#") else r"\b" + re.escape(tok) + r"\b"
        if re.search(pat, code):
            fails.append(f"forbidden identifier: {tok}")
    pos_calls = set(re.findall(r"\bPosition\w*", code))
    extra = pos_calls - READ_ONLY_POSITION_API - {"POSITION_SYMBOL", "POSITION_TYPE"}
    extra = {x for x in extra if not x.startswith("POSITION_")}
    if extra:
        fails.append(f"non read-only position API used: {sorted(extra)}")
    if "#property indicator_chart_window" not in text:
        fails.append("not declared as an indicator (MT5 blocks trade calls only in indicators)")
    if re.search(r"#property\s+script_show_inputs|OnTick\s*\(", code):
        fails.append("EA/script entry point present")
    if fails:
        for f in fails:
            print("  FAIL", f)
        print(f"SAFETY SCAN: FAIL ({len(fails)} problems)")
        return 1
    print(f"  checked {len(FORBIDDEN)} forbidden identifiers, position API = {sorted(pos_calls & READ_ONLY_POSITION_API)}")
    print("SAFETY SCAN: PASS - no trading, network, messaging, file or DLL calls; ASCII source; indicator type")
    return 0


if __name__ == "__main__":
    sys.exit(main())
