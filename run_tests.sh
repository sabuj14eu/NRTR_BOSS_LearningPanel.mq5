#!/usr/bin/env bash
# Full local test suite for all three indicators. See TESTING.md for what
# this does and does NOT prove.
set -euo pipefail
cd "$(dirname "$0")"
FLAGS="-std=c++17 -O1 -Wall -Wextra -Wno-unused-parameter -Werror"
mkdir -p build
rc=0

echo "================ NRTR_BOSS_LearningPanel.mq5 (Gold / Silver) ================"
SRC=NRTR_BOSS_LearningPanel.mq5
echo "== 1. safety scan (test 13) =="
python3 tests/check_safety.py "$SRC" || rc=1
echo "== 2. translate the real .mq5 source (syntax only) =="
python3 tests/mql2cpp.py "$SRC" build/engine.inc engine
python3 tests/mql2cpp.py "$SRC" build/full.inc full
echo "== 3. surrogate compile of the WHOLE indicator (g++ $FLAGS) =="
printf '#include "../tests/mt5_sim.h"\n#include "full.inc"\nint main(){return 0;}\n' > build/full_compile.cpp
g++ $FLAGS -fsyntax-only build/full_compile.cpp && echo "FULL FILE: 0 errors, 0 warnings" || rc=1
echo "== 4. engine tests =="
g++ $FLAGS -Ibuild tests/test_engine.cpp -o build/test_engine && ./build/test_engine || rc=1
echo "== 5. whole-indicator tests on a simulated MT5 terminal =="
g++ $FLAGS -Ibuild tests/test_indicator.cpp -o build/test_indicator && ./build/test_indicator || rc=1

echo
echo "================ NRTR_BOSS_Crypto_NYTrap.mq5 / NRTR_BOSS_Forex_NYTrap.mq5 ================"
echo "== 6. twin check: the two files differ only in header / description / NB_MARKET =="
python3 tests/check_twins.py NRTR_BOSS_Crypto_NYTrap.mq5 NRTR_BOSS_Forex_NYTrap.mq5 || rc=1
for m in crypto forex; do
   if [ $m = crypto ]; then SRC=NRTR_BOSS_Crypto_NYTrap.mq5; M=1; else SRC=NRTR_BOSS_Forex_NYTrap.mq5; M=2; fi
   echo "== 7.$m safety scan =="
   python3 tests/check_safety.py "$SRC" || rc=1
   echo "== 8.$m translate + surrogate compile of the WHOLE indicator =="
   python3 tests/mql2cpp.py "$SRC" build/engine_$m.inc engine
   python3 tests/mql2cpp.py "$SRC" build/full_$m.inc full
   printf '#include "../tests/mt5_sim.h"\n#include "full_%s.inc"\nint main(){return 0;}\n' $m > build/full_compile_$m.cpp
   g++ $FLAGS -fsyntax-only build/full_compile_$m.cpp && echo "FULL FILE ($m): 0 errors, 0 warnings" || rc=1
   echo "== 9.$m session engine tests =="
   g++ $FLAGS -Ibuild -DNB_TEST_MARKET=$M tests/test_session_engine.cpp -o build/test_session_engine_$m && ./build/test_session_engine_$m || rc=1
   echo "== 10.$m whole-indicator tests on a simulated MT5 terminal =="
   g++ $FLAGS -Ibuild -DNB_TEST_MARKET=$M tests/test_session_indicator.cpp -o build/test_session_indicator_$m && ./build/test_session_indicator_$m || rc=1
done

echo
[ $rc -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
echo "NOT RUN HERE: MetaEditor (F7) compile - run it in MT5, see TESTING.md"
exit $rc
