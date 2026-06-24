#!/bin/bash
# 一键部署脚本（Mac版）

echo "=========================================="
echo "  头条API服务 - 一键部署"
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

CONDA_PYTHON=$(which python 2>/dev/null || echo "python")

# 1. 检查 Python
if [ ! -f "$CONDA_PYTHON" ]; then
    echo "❌ Python 不存在: $CONDA_PYTHON"
    echo "请确认 conda 环境 'playwright' 已激活"
    exit 1
fi
echo "✅ Python路径: $CONDA_PYTHON"
echo "✅ Python版本: $($CONDA_PYTHON --version)"

# 2. 检查并安装依赖
echo ""
echo "📦 检查依赖..."
$CONDA_PYTHON -c "import fastapi, uvicorn, playwright" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "⚠️  缺少依赖，正在安装..."
    pip install fastapi uvicorn playwright
    playwright install chromium
    echo "✅ 依赖安装完成"
else
    echo "✅ 依赖已安装"
fi

# 3. 创建日志目录
mkdir -p logs
echo "✅ 日志目录已创建"

# 4. 给脚本添加执行权限
chmod +x *.sh
echo "✅ 脚本权限已设置"

# 5. 停止旧服务
echo ""
echo "🔄 停止旧服务..."
./stop.sh 2>/dev/null
sleep 2

# 6. 启动新服务
echo ""
echo "🚀 启动新服务..."
./start.sh

echo ""
echo "=========================================="
echo "✅ 部署完成！"
echo ""
echo "📋 使用说明:"
echo "  ./status.sh    - 查看服务状态"
echo "  ./logs.sh      - 查看日志"
echo "  ./logs.sh -f   - 实时查看日志"
echo "  ./stop.sh      - 停止服务"
echo "  ./restart.sh   - 重启服务"
echo ""
echo "🌐 访问API文档: http://localhost:8000/docs"
echo "=========================================="
