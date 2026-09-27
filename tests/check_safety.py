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
    # global state (not needed by a panel)
    "GlobalVariableSet",
]
# v1.07 data bridge: the ONLY file access allowed, and only between these markers
BR_BEGIN, BR_END = "//=== NB_BR_BEGIN ===", "//=== NB_BR_END ==="
BRIDGE_FILE_API = {"FileOpen", "FileWriteString", "FileClose", "FileMove"}
BRIDGE_FILE_CONST = {"FILE_WRITE", "FILE_TXT", "FILE_ANSI", "FILE_COMMON", "FILE_REWRITE"}
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
    # the bridge block is scanned on its own; everything outside it may not touch files at all
    b0, b1 = text.find(BR_BEGIN), text.find(BR_END)
    bridge = ""
    if b0 >= 0 or b1 >= 0:
        if not (0 <= b0 < b1) or text.count(BR_BEGIN) != 1 or text.count(BR_END) != 1:
            fails.append("bridge markers NB_BR_BEGIN / NB_BR_END broken")
        else:
            bridge = text[b0:b1]
            text_out = text[:b0] + text[b1:]
    outside = strip_comments(text_out if bridge else text)
    for tok in sorted(set(re.findall(r"\bFile\w*|\bFolder\w*|\bFILE_\w+", outside))):
        fails.append(f"file access outside the bridge block: {tok}")
    if bridge:
        bcode = strip_comments(bridge)
        used = set(re.findall(r"\bFile\w*|\bFolder\w*", bcode))
        for tok in sorted(used - BRIDGE_FILE_API):
            fails.append(f"bridge block uses a file call it may not: {tok}")
        for tok in sorted(set(re.findall(r"\bFILE_\w+", bcode)) - BRIDGE_FILE_CONST):
            fails.append(f"bridge block uses a file mode it may not: {tok}")
        for m in re.finditer(r"FileOpen\(([^;]*)\);", bcode):
            if "FILE_WRITE" not in m.group(1) or "FILE_COMMON" not in m.group(1):
                fails.append("bridge FileOpen is not write-only into the common folder")
        # every path the bridge opens or renames is a variable declared exactly as
        # "NRTR_BRIDGE\\" + g_sym + ".json" / ".tmp"
        paths = dict(re.findall(r'string\s+(\w+)\s*=\s*("NRTR_BRIDGE\\\\"\s*\+\s*g_sym\s*\+\s*"\.(?:json|tmp)")\s*;', bridge))
        args = []
        for m in re.finditer(r"FileOpen\(\s*(\w+)\s*,", bridge):
            args.append(m.group(1))
        for m in re.finditer(r"FileMove\(\s*(\w+)\s*,[^,]*,\s*(\w+)\s*,", bridge):
            args += [m.group(1), m.group(2)]
        if not args:
            fails.append("bridge block has no FileOpen / FileMove to check")
        for a_ in args:
            if a_ not in paths:
                fails.append(f"bridge file path '{a_}' is not a NRTR_BRIDGE\\<symbol>.json/.tmp variable")
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
    print("SAFETY SCAN: PASS - no trading, network, messaging or DLL calls; file writes only in the bridge block"
          " (write-only, NRTR_BRIDGE folder)" if bridge else
          "SAFETY SCAN: PASS - no trading, network, messaging, file or DLL calls; ASCII source; indicator type")
    return 0


if __name__ == "__main__":
    sys.exit(main())
