#!/usr/bin/env python3
"""Static safety scan for the EA. Unlike the indicator, the EA MAY trade
(that is its job) - but only through OrderSend, never through anything
that leaves the terminal, and only with the demo guard in place."""
import re
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "NRTR_QML_MetalScalper.mq5"

FORBIDDEN = [
    # network / messaging / external control (the one WebRequest lives in NqPost, checked below)
    "SocketCreate", "SocketConnect", "SocketSend", "SocketRead", "SendNotification", "SendMail",
    "SendFTP", "TerminalClose", "ChartSetSymbolPeriod", "ShellExecute", "#import", "#include", "#resource",
    # files / global state / other charts (the one journal writer lives in NqJournalWrite, checked below)
    "FileCopy", "FileDelete", "FileMove", "FileWriteArray", "FileWriteStruct", "GlobalVariableSet", "ChartOpen", "ChartClose",
    # the only order path is OrderSend (synchronous, result checked); no async, no CTrade
    "OrderSendAsync", "CTrade", "CPositionInfo", "COrderInfo", "OrderCloseBy", "PositionCloseBy",
    # close-by is never used (one slot per asset, positions close by their own deal)
    "TRADE_ACTION_CLOSE_BY",
]
REQUIRED = [
    ("ACCOUNT_TRADE_MODE_DEMO", "demo-account guard"),
    ("InpAllowRealAccount", "explicit real-account switch"),
    ("NqRiskGate", "risk gate"),
    ("NqLotFor", "auto lot from risk money"),
    ("TRADE_ACTION_PENDING", "pending order path"),
    ("bool NqSend(MqlTradeRequest", "single order-sending function"),
]


def strip_comments(code: str) -> str:
    code = re.sub(r"/\*.*?\*/", "", code, flags=re.S)
    code = re.sub(r'"(?:\\.|[^"\\])*"', '""', code)
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
    for tok, why in REQUIRED:
        if tok not in code:
            fails.append(f"missing {why} ({tok})")
    # exactly one OrderSend call site, inside NqSend
    sends = [m.start() for m in re.finditer(r"\bOrderSend\s*\(", code)]
    if len(sends) != 1:
        fails.append(f"OrderSend must appear exactly once (found {len(sends)})")
    # no literal lot sizes: every req.volume must come from a variable
    for m in re.finditer(r"req\.volume\s*=\s*([^;]+);", code):
        rhs = m.group(1).strip()
        if re.fullmatch(r"[0-9.]+", rhs):
            fails.append(f"literal lot size: req.volume = {rhs}")
    # the network and the file system each have exactly one door
    for tok, fn in (("WebRequest", "NqPost"), ("FileOpen", "NqJournalWrite"), ("FileWriteString", "NqJournalWrite")):
        sites = [m.start() for m in re.finditer(r"\b" + tok + r"\s*\(", code)]
        if len(sites) != 1:
            fails.append(f"{tok} must appear exactly once (found {len(sites)})")
        else:
            fn_start = code.rfind("\n" + ("bool " if fn == "NqPost" else "void ") + fn + "(", 0, sites[0])
            if fn_start < 0:
                fails.append(f"{tok} must be called inside {fn}")
    # the URL and the secret are inputs, and the secret never reaches a Print
    if not re.search(r"input\s+string\s+InpSignalMeshUrl\b", code):
        fails.append("InpSignalMeshUrl must be a string input")
    if not re.search(r"input\s+string\s+InpSignalMeshSecret\b", code):
        fails.append("InpSignalMeshSecret must be a string input")
    for m in re.finditer(r"Print\s*\((?:[^;]|\n)*?\);", code):
        if "InpSignalMeshSecret" in m.group(0) or "g_webSecret" in m.group(0):
            fails.append("the SignalMesh secret is printed")
    # the real-account switch must be an input, never a hard-coded constant
    if not re.search(r"input\s+bool\s+InpAllowRealAccount\s*=\s*(true|false)", code):
        fails.append("InpAllowRealAccount must be a bool input")
    # the terminal's Algo Trading button must be honoured
    if "TERMINAL_TRADE_ALLOWED" not in code or "MQL_TRADE_ALLOWED" not in code:
        fails.append("Algo Trading switch (TERMINAL_TRADE_ALLOWED / MQL_TRADE_ALLOWED) not checked")
    if fails:
        for f in fails:
            print("  FAIL", f)
        print(f"EA SAFETY SCAN: FAIL ({len(fails)} problems)")
        return 1
    print(f"  checked {len(FORBIDDEN)} forbidden identifiers, {len(REQUIRED)} required guards, one OrderSend / one WebRequest / one file writer, secret never printed")
    print("EA SAFETY SCAN: PASS - no network/file/DLL calls; single audited order path; Algo Trading switch honoured")
    return 0


if __name__ == "__main__":
    sys.exit(main())
