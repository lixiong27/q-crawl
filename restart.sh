#!/bin/bash
# 头条API服务重启脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "正在重启头条API服务..."
./stop.sh
sleep 2
./start.sh
