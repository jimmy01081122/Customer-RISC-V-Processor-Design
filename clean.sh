#!/bin/sh
# Clean simulation executables and log files

echo "Cleaning simulation artifacts..."

# 刪除 iverilog 產生的執行檔（統一用 sim_* 比較彈性）
rm -f sim_*

# 刪除 log 目錄
rm -rf pass_logs fail_logs

echo "Done."