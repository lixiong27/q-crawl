#!/bin/bash
# 查看日志

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

if [ "$1" == "-f" ] || [ "$1" == "--follow" ]; then
    echo "📋 实时查看日志 (Ctrl+C 退出)..."
    tail -f logs/toutiao.log
else
    echo "📋 最近50行日志:"
    echo "=========================================="
    tail -50 logs/toutiao.log
    echo "=========================================="
    echo ""
    echo "实时查看: ./logs.sh -f"
fi
