#!/usr/bin/env bash
# Full local test suite for the EA. See TESTING.md for what this does
# and does NOT prove.
set -euo pipefail
cd "$(dirname "$0")"
EA=NRTR_QML_MetalScalper.mq5
FLAGS="-std=c++17 -O1 -Wall -Wextra -Wno-unused-parameter -Werror"
mkdir -p build
rc=0

echo "=================== EA: $EA ==================="
echo "== 1. EA safety scan (no network/file/DLL; one OrderSend; demo guard) =="
python3 tests/check_safety_ea.py "$EA" || rc=1

echo "== 2. translate the real EA source (syntax only) =="
python3 tests/mql2cpp.py "$EA" build/ea_engine.inc engine
python3 tests/mql2cpp.py "$EA" build/ea_full.inc full

echo "== 3. surrogate compile of the WHOLE EA (g++ $FLAGS) =="
printf '#include "../tests/mt5_sim_ea.h"\n#include "ea_full.inc"\nint main(){return 0;}\n' > build/ea_compile.cpp
g++ $FLAGS -fsyntax-only build/ea_compile.cpp && echo "EA FULL FILE: 0 errors, 0 warnings" || rc=1

echo "== 4. EA engine tests (regime, trigger, QML/pullback plans, forecast, risk, lot) =="
g++ $FLAGS -Ibuild tests/test_ea_engine.cpp -o build/test_ea_engine && ./build/test_ea_engine || rc=1

echo "== 5. whole-EA tests on a simulated MT5 terminal WITH a trade API =="
g++ $FLAGS -Ibuild tests/test_ea.cpp -o build/test_ea && ./build/test_ea || rc=1

echo
[ $rc -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
echo "NOT RUN HERE: MetaEditor (F7) compile - run it in MT5, see TESTING.md"
exit $rc
