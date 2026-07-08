#!/usr/bin/env bash
# HyperConv - run all testcases through Vivado xsim.
# Usage: sim/run_all.sh [test_name ...]   (no args = all tests)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIV="${XILINX_VIVADO:-/tools/2025.2/Vivado}/bin"
# Vivado's bundled gcc can't find the system C runtime (crt1.o) on Ubuntu
export LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LIBRARY_PATH:-}"
SIM="$ROOT/sim"
LOGS="$SIM/logs"

cd "$SIM"
rm -rf xsim.dir "$LOGS"
mkdir -p "$LOGS"

echo "== xvlog: compiling RTL + TB =="
"$VIV/xvlog" "$ROOT"/rtl/*.v "$ROOT"/tb/tb_conv_top.v > "$LOGS/xvlog.log" 2>&1 || {
    echo "COMPILE FAILED - see $LOGS/xvlog.log"; tail -30 "$LOGS/xvlog.log"; exit 1; }

if [ $# -gt 0 ]; then
    TESTS=("$@")
else
    TESTS=($(ls -d tests/*/ | xargs -n1 basename))
fi

pass=0; fail=0; failed=""
for name in "${TESTS[@]}"; do
    d="tests/$name"
    # shellcheck disable=SC1091
    source "$d/params.sh"    # sets N W H KSEL GAPS
    snap="tb_$name"

    "$VIV/xelab" tb_conv_top -s "$snap" --incr \
        -generic_top "N=$N" -generic_top "IMG_W=$W" -generic_top "IMG_H=$H" \
        -generic_top "KSEL=$KSEL" > "$LOGS/xelab_$name.log" 2>&1 || {
            echo "ELAB FAILED: $name - see $LOGS/xelab_$name.log"
            tail -20 "$LOGS/xelab_$name.log"; fail=$((fail+1)); failed="$failed $name"; continue; }

    extra=""
    [ "${GAPS:-0}" = "1" ] && extra="-testplusarg GAPS"
    "$VIV/xsim" "$snap" -R \
        -testplusarg "IMG=$d/img.hex" -testplusarg "KER=$d/kernel.hex" \
        -testplusarg "EXP=$d/expected.hex" -testplusarg "OUT=$d/dut_out.hex" \
        $extra > "$LOGS/xsim_$name.log" 2>&1

    if grep -q "TB: PASS" "$LOGS/xsim_$name.log"; then
        lat=$(grep -o "latency.*" "$LOGS/xsim_$name.log")
        printf "PASS  %-16s (%s)\n" "$name" "$lat"
        pass=$((pass+1))
    else
        printf "FAIL  %-16s - see %s\n" "$name" "$LOGS/xsim_$name.log"
        grep -E "MISMATCH|SPURIOUS|TIMEOUT|Error" "$LOGS/xsim_$name.log" | head -5
        fail=$((fail+1)); failed="$failed $name"
    fi
done

echo "=================================================="
echo "RESULT: $pass passed, $fail failed${failed:+ (failed:$failed)}"
[ "$fail" -eq 0 ]
