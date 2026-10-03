#!/usr/bin/env bash
# Full local test suite for BOTH EAs (metal + crypto twin). See TESTING.md
# for what this does and does NOT prove.
set -euo pipefail
cd "$(dirname "$0")"
FLAGS="-std=c++17 -O1 -Wall -Wextra -Wno-unused-parameter -Werror"
mkdir -p build
rc=0

echo "== 0. crypto twin is the derivation of the metal EA (engine identical apart from the asset detector) =="
python3 tools/derive_crypto_ea.py --check || rc=1

for EA in NRTR_QML_MetalScalper.mq5 NRTR_QML_CryptoScalper.mq5; do
  case "$EA" in
    NRTR_QML_MetalScalper.mq5)  TAG=ea;        TEST=tests/test_ea.cpp ;;
    NRTR_QML_CryptoScalper.mq5) TAG=ea_crypto; TEST=tests/test_ea_crypto.cpp ;;
  esac
  echo
  echo "=================== EA: $EA ==================="
  echo "== 1. EA safety scan (no network/file/DLL beyond the two POSTs; one OrderSend; demo guard) =="
  python3 tests/check_safety_ea.py "$EA" || rc=1

  echo "== 2. translate the real EA source (syntax only) =="
  python3 tests/mql2cpp.py "$EA" "build/${TAG}_engine.inc" engine
  python3 tests/mql2cpp.py "$EA" "build/${TAG}_full.inc" full
  [ "$TAG" = ea ] && cp "build/${TAG}_engine.inc" build/ea_engine.inc && cp "build/${TAG}_full.inc" build/ea_full.inc
  [ "$TAG" = ea_crypto ] && cp "build/${TAG}_full.inc" build/ea_full_crypto.inc

  echo "== 3. surrogate compile of the WHOLE EA (g++ $FLAGS) =="
  printf '#include "../tests/mt5_sim_ea.h"\n#include "%s_full.inc"\nint main(){return 0;}\n' "$TAG" > "build/${TAG}_compile.cpp"
  g++ $FLAGS -fsyntax-only "build/${TAG}_compile.cpp" && echo "EA FULL FILE: 0 errors, 0 warnings" || rc=1

  if [ "$TAG" = ea ]; then
    echo "== 4. EA engine tests (regime, trigger, QML/pullback plans, forecast, risk, lot) =="
    g++ $FLAGS -Ibuild tests/test_ea_engine.cpp -o build/test_ea_engine && ./build/test_ea_engine || rc=1
  else
    echo "== 4. EA engine tests: the crypto engine block is byte-identical to the tested metal engine (step 0) =="
  fi

  echo "== 5. whole-EA tests on a simulated MT5 terminal WITH a trade API =="
  g++ $FLAGS -Ibuild "$TEST" -o "build/test_${TAG}" && "./build/test_${TAG}" || rc=1
done

echo
[ $rc -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
echo "NOT RUN HERE: MetaEditor (F7) compile - run it in MT5, see TESTING.md"
exit $rc
