#!/bin/sh
# Simple module-by-module test runner using Icarus Verilog (iverilog/vvp).
# Each testbench prints PASS/FAIL lines; this script summarizes.
# Logs:
#   - PASS 測試：pass_logs/sim_<name>.log
#   - FAIL / BUILD FAIL / SIM FAIL：fail_logs/sim_<name>.log

run_one() {
  name="$1"
  shift
  build_cmd="$1"
  shift
  run_cmd="$1"
  shift

  echo "== Running $name =="

  mkdir -p pass_logs
  mkdir -p fail_logs

  log_file="sim_${name}.log"

  # Build phase
  if ! sh -c "$build_cmd" >"$log_file" 2>&1; then
    echo "  [BUILD FAIL] see fail_logs/$log_file"
    mv "$log_file" "fail_logs/$log_file"
    return 1
  fi

  # Simulation phase
  if ! sh -c "$run_cmd" >>"$log_file" 2>&1; then
    echo "  [SIM FAIL] see fail_logs/$log_file"
    mv "$log_file" "fail_logs/$log_file"
    cat "fail_logs/$log_file"
    return 1
  fi

  # Testbench 自行印出的 FAIL 行
  if grep -q "FAIL" "$log_file"; then
    echo "  [TEST FAIL]"
    mv "$log_file" "fail_logs/$log_file"
    cat "fail_logs/$log_file"
    return 1
  fi

  # 全部通過，歸類到 pass_logs
  mv "$log_file" "pass_logs/$log_file"
  cat "pass_logs/$log_file"
  echo "  [PASS]"
  return 0
}
status=0

# ALU
run_one alu \
  "iverilog -g2001 -o sim_alu tb_alu_int.v alu_int.v" \
  "vvp sim_alu" || status=1

# Regfiles
run_one regfile \
  "iverilog -g2001 -o sim_reg tb_regfile.v regfile_int.v regfile_fp.v" \
  "vvp sim_reg" || status=1

# Decoder
run_one decoder \
  "iverilog -g2001 -o sim_dec decoder.v tb_decoder.v define.v" \
  "vvp sim_dec" || status=1

# FPU
run_one fpu \
  "iverilog -g2001 -o sim_fpu fpu_unit.v tb_fpu_unit.v" \
  "vvp sim_fpu" || status=1

if [ "$status" -eq 0 ]; then
  echo "ALL MODULE TESTS PASSED"
else
  echo "Some module tests FAILED"
fi

exit $status
