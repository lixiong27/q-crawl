#!/bin/bash
# 头条API服务启动脚本（Mac版）

# 使用脚本所在目录作为工作目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

mkdir -p logs
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
echo "[$TIMESTAMP] 正在启动头条API服务..."

# 使用当前conda环境中的python
CONDA_PYTHON=$(which python 2>/dev/null || echo "python")

if [ ! -f "$CONDA_PYTHON" ]; then
    echo "错误: 找不到 Python"
    exit 1
fi

nohup $CONDA_PYTHON toutiao_api.py > logs/toutiao.log 2>&1 &
echo $! > toutiao.pid

echo "[$TIMESTAMP] ✅ 服务已启动"
echo "  PID: $(cat toutiao.pid)"
echo "  日志: $SCRIPT_DIR/logs/toutiao.log"
echo "  查看日志: ./logs.sh"
echo "  停止服务: ./stop.sh"
