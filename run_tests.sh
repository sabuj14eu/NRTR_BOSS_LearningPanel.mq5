#!/usr/bin/env bash
# Full local test suite for all three indicators. See TESTING.md for what
# this does and does NOT prove.
set -euo pipefail
cd "$(dirname "$0")"
FLAGS="-std=c++17 -O1 -Wall -Wextra -Wno-unused-parameter -Werror"
mkdir -p build
rc=0
nr=0
BASELINE=3f046ef   # last commit before v1.05 (all three files at v1.04)

# existing panel unchanged: the v1.04 file from git vs this file, byte for byte
unchanged() {   # $1 = tag, $2 = source file, $3 = NB_TEST_MARKET, $4 = full .inc of the current file
   local m=$1 src=$2 mk=$3 inc=$4
   if git cat-file -e "$BASELINE:$src" 2>/dev/null; then
      git show "$BASELINE:$src" > build/baseline_$m.mq5
      python3 tests/mql2cpp.py build/baseline_$m.mq5 build/baseline_$m.inc full
      if g++ $FLAGS -Ibuild -DNB_TEST_MARKET=$mk -DDUMP_INC="\"baseline_$m.inc\"" tests/dump_objects.cpp -o build/dump_base_$m &&
         g++ $FLAGS -Ibuild -DNB_TEST_MARKET=$mk -DDUMP_INC="\"$inc\"" tests/dump_objects.cpp -o build/dump_new_$m; then
         ./build/dump_base_$m > build/dump_base_$m.txt 2>/dev/null
         ./build/dump_new_$m > build/dump_new_$m.txt 2>/dev/null
         if cmp -s build/dump_base_$m.txt build/dump_new_$m.txt; then
            echo "EXISTING PANEL UNCHANGED ($m): PASS - $(grep -c '^=== ' build/dump_base_$m.txt) scenarios, $(grep -c '^O ' build/dump_base_$m.txt) object records + buffers + alerts + log identical"
         else
            echo "EXISTING PANEL UNCHANGED ($m): FAIL - first difference:"; diff build/dump_base_$m.txt build/dump_new_$m.txt | head -5; rc=1
         fi
      else
         echo "EXISTING PANEL UNCHANGED ($m): FAIL - dump does not build"; rc=1
      fi
   else
      echo "EXISTING PANEL UNCHANGED ($m): NOT RUNNABLE - baseline commit $BASELINE is not in this clone"; nr=1
   fi
}

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
echo "== 5a. v1.05 five-question plan (metals): engine tests =="
g++ $FLAGS -Ibuild -DNB_TEST_MARKET=0 tests/test_fq_engine.cpp -o build/test_fq_engine_gold && ./build/test_fq_engine_gold || rc=1
echo "== 5b. v1.05 five-question plan (metals): whole-indicator tests, gold and silver =="
g++ $FLAGS -Ibuild -DNB_TEST_MARKET=0 tests/test_fq_indicator.cpp -o build/test_fq_indicator_gold && ./build/test_fq_indicator_gold || rc=1
echo "== 5c. existing gold panel unchanged: v1.04 baseline (git $BASELINE) vs this file, byte for byte =="
unchanged gold NRTR_BOSS_LearningPanel.mq5 0 full.inc
echo "== 5d. v1.06 NY trap + decision ladder (metals): engine + whole-indicator tests, XAUUSD and XAGUSD =="
g++ $FLAGS -Ibuild tests/test_nyt.cpp -o build/test_nyt && ./build/test_nyt || rc=1
echo "== 5e. v1.06 simple view (InpSimpleView = true): ladder only, main panel + table hidden =="
sed 's/^const bool           InpSimpleView      = false;/const bool           InpSimpleView      = true; /' build/full.inc > build/full_simple.inc
if grep -q 'InpSimpleView      = true;' build/full_simple.inc; then
   g++ $FLAGS -Ibuild -DNYT_SIMPLE -DNYT_INC='"full_simple.inc"' tests/test_nyt.cpp -o build/test_nyt_simple && ./build/test_nyt_simple || rc=1
else echo "SIMPLE VIEW: FAIL - input anchor not found"; rc=1; fi

echo
echo "================ NRTR_BOSS_Crypto_NYTrap.mq5 / NRTR_BOSS_Forex_NYTrap.mq5 ================"
echo "== 6. twin check: the two files differ only in header / description / NB_MARKET =="
python3 tests/check_twins.py NRTR_BOSS_Crypto_NYTrap.mq5 NRTR_BOSS_Forex_NYTrap.mq5 || rc=1
echo "== 6b. the five-question plan blocks are identical in all three files =="
python3 tests/check_fq_blocks.py || rc=1
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
   echo "== 11.$m v1.05 five-question plan: engine tests =="
   g++ $FLAGS -Ibuild -DNB_TEST_MARKET=$M tests/test_fq_engine.cpp -o build/test_fq_engine_$m && ./build/test_fq_engine_$m || rc=1
   echo "== 12.$m v1.05 five-question plan: whole-indicator tests (table + chart drawing) =="
   g++ $FLAGS -Ibuild -DNB_TEST_MARKET=$M tests/test_fq_indicator.cpp -o build/test_fq_indicator_$m && ./build/test_fq_indicator_$m || rc=1
   echo "== 13.$m existing panel unchanged: v1.04 baseline (git $BASELINE) vs this file, byte for byte =="
   unchanged $m "$SRC" $M full_$m.inc
done

echo
if [ $rc -ne 0 ]; then echo "SOME SUITES FAILED"
elif [ $nr -ne 0 ]; then echo "ALL RUNNABLE SUITES PASSED - but at least one check was NOT RUNNABLE (see above); that is not a pass"
else echo "ALL SUITES PASSED"; fi
echo "NOT RUN HERE: MetaEditor (F7) compile - run it in MT5, see TESTING.md"
echo "SEPARATE (slow): python3 tests/mutate_fq.py - plants bugs one at a time, every one must be caught"
exit $rc
