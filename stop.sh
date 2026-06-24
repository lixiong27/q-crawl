#!/bin/bash
# 头条API服务停止脚本（Mac版）

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "正在停止头条API服务..."

if [ -f toutiao.pid ]; then
    PID=$(cat toutiao.pid)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID
        echo "✅ 服务已停止 (PID: $PID)"
        rm toutiao.pid
    else
        echo "进程不存在 (PID: $PID)"
        rm toutiao.pid
    fi
else
    PIDS=$(ps aux | grep "toutiao_api.py" | grep -v grep | grep -v "start.sh" | awk '{print $2}')
    if [ -n "$PIDS" ]; then
        kill $PIDS
        echo "✅ 服务已停止 (PIDs: $PIDS)"
    else
        echo "未找到运行中的服务"
    fi
fi

UVICORN_PIDS=$(ps aux | grep "uvicorn" | grep "toutiao_api" | grep -v grep | awk '{print $2}')
if [ -n "$UVICORN_PIDS" ]; then
    kill $UVICORN_PIDS 2>/dev/null
    echo "已清理 uvicorn 进程"
fi
