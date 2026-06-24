#!/bin/bash
# 头条API服务状态检查

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "=========================================="
echo "  头条API服务状态"
echo "=========================================="

if [ -f toutiao.pid ]; then
    PID=$(cat toutiao.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "✅ 服务运行中 (PID: $PID)"
        echo ""
        echo "进程信息:"
        ps -p $PID -o pid,ppid,user,%cpu,%mem,etime,cmd | grep -v "CMD"
        echo ""
        echo "端口监听:"
        if command -v lsof &> /dev/null; then
            lsof -i :8000 | grep LISTEN || echo "  端口 8000 未被监听"
        else
            netstat -an | grep 8000 | grep LISTEN || echo "  端口 8000 未被监听"
        fi
        echo ""
        echo "健康检查:"
        HEALTH=$(curl -s http://localhost:8000/health 2>/dev/null)
        if [ -n "$HEALTH" ]; then
            echo "  ✅ 服务响应正常"
            echo "  $HEALTH"
        else
            echo "  ❌ 服务无响应"
        fi
    else
        echo "❌ PID文件存在但进程已停止 (PID: $PID)"
        rm toutiao.pid
    fi
else
    echo "❌ 服务未运行"
    PIDS=$(ps aux | grep "toutiao_api.py" | grep -v grep | awk '{print $2}')
    if [ -n "$PIDS" ]; then
        echo "⚠️  发现残留进程: $PIDS"
    fi
fi

echo ""
echo "最近日志 (最后5行):"
tail -5 logs/toutiao.log 2>/dev/null || echo "  暂无日志"
echo "=========================================="
