#!/bin/bash
# 超级一键部署 - 生成所有脚本和Python代码（Mac适配版）

echo "=========================================="
echo "  头条API服务 - 超级一键部署 (Mac版)"
echo "=========================================="

# ============================================
# 关键改动：使用当前目录，不写死路径
# ============================================
WORK_DIR="$(pwd)"                          # 当前目录
CONDA_ENV="playwright"                     # conda环境名
# 动态获取当前conda环境的Python路径
CONDA_PYTHON=$(which python 2>/dev/null || echo "python")

echo "📁 工作目录: $WORK_DIR"
echo "🐍 Python路径: $CONDA_PYTHON"
echo ""

# ============================================
# 1. 生成 Python API 代码 toutiao_api.py
# ============================================
cat > toutiao_api.py << 'PYEOF'
#!/usr/bin/env python3
"""
头条用户文章列表抓取服务（FastAPI 版）
启动: python toutiao_api.py
"""

import asyncio
import logging
from typing import List, Optional
from fastapi import FastAPI, Query, HTTPException
from pydantic import BaseModel
import uvicorn
from playwright.async_api import async_playwright, Browser
from contextlib import asynccontextmanager

# ==================== 日志配置 ====================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("toutiao")

# ==================== 全局浏览器实例 ====================
browser_instance = None
playwright_instance = None

# ==================== 应用生命周期管理 ====================
@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用启动时创建浏览器，关闭时销毁"""
    global browser_instance, playwright_instance
    
    logger.info("Starting Playwright and launching browser...")
    playwright_instance = await async_playwright().start()
    browser_instance = await playwright_instance.chromium.launch(
        headless=True,
        args=[
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-gpu',
            '--disable-dev-shm-usage'
        ]
    )
    logger.info("Browser launched successfully (reuse mode)")
    
    yield
    
    logger.info("Shutting down browser...")
    if browser_instance:
        await browser_instance.close()
    if playwright_instance:
        await playwright_instance.stop()
    logger.info("Browser closed")

# ==================== FastAPI 应用 ====================
app = FastAPI(
    title="头条文章抓取API",
    version="1.0.0",
    lifespan=lifespan
)

# ==================== 数据模型 ====================
class ArticleItem(BaseModel):
    """单篇文章数据结构"""
    title: str
    abstract: str
    url: str
    source: str
    publish_time: int
    group_id: str
    article_genre: str

class ApiResponse(BaseModel):
    """统一返回结构"""
    code: int
    msg: str
    data: List[ArticleItem]
    total: int

# ==================== JavaScript 提取脚本 ====================
EXTRACT_JS = """
() => {
    const items = [];
    const cards = document.querySelectorAll('.profile-article-card-wrapper');
    const now = Math.floor(Date.now() / 1000);

    const authorEl = document.querySelector('[class*="profile"] .name');
    const sourceName = authorEl ? authorEl.textContent.trim() : '';

    cards.forEach(card => {
        const titleEl = card.querySelector('a.title');
        if (!titleEl) return;
        const title = titleEl.textContent.trim();
        if (!title) return;

        const href = titleEl.getAttribute('href') || '';
        const url = href.startsWith('/') ? 'https://www.toutiao.com' + href : href;

        let abstract = '';
        const abstractEl = card.querySelector('[class*="abstract"], [class*="summary"], [class*="desc"]');
        if (abstractEl) {
            abstract = abstractEl.textContent.trim();
        }
        if (!abstract) {
            const contentEl = card.querySelector('[class*="content"], [class*="text"]');
            if (contentEl) {
                const text = contentEl.textContent.trim();
                abstract = text.substring(0, 50) + (text.length > 50 ? '...' : '');
            }
        }

        const timeEl = card.querySelector('.feed-card-footer-time-cmp');
        const timeStr = timeEl ? timeEl.textContent.trim() : '';
        let publishTime = now;
        const mMin = timeStr.match(/(\\d+)分钟前/);
        if (mMin) publishTime = now - parseInt(mMin[1]) * 60;
        const mHour = timeStr.match(/(\\d+)小时前/);
        if (mHour) publishTime = now - parseInt(mHour[1]) * 3600;
        const mDay = timeStr.match(/(\\d+)天前/);
        if (mDay) publishTime = now - parseInt(mDay[1]) * 86400;

        let groupId = '';
        const gid = url.match(/\\/(?:article|group)\\/(\\d+)/);
        if (gid) groupId = gid[1];

        items.push({
            title: title,
            abstract: abstract,
            url: url,
            source: sourceName,
            publish_time: publishTime,
            group_id: groupId,
            article_genre: 'article',
        });
    });
    return items;
}
"""

# ==================== 核心抓取函数 ====================
async def fetch_user_articles(token: str, max_articles: int = 20) -> dict:
    """抓取用户文章"""
    global browser_instance
    
    url = f"https://www.toutiao.com/c/user/token/{token}/"
    logger.info("Loading: %s", url[:60])
    
    if browser_instance is None:
        return {"code": 1, "msg": "Browser not initialized", "data": [], "total": 0}
    
    context = await browser_instance.new_context(
        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        locale="zh-CN",
        viewport={"width": 1920, "height": 1080},
    )
    page = await context.new_page()
    
    try:
        await page.goto(url, wait_until="networkidle", timeout=30000)
        await page.wait_for_timeout(2000)
        
        tab = page.locator('[aria-label="文章"]')
        if await tab.count() > 0:
            await tab.click()
            logger.info("Clicked '文章' tab")
        else:
            tab2 = page.locator('[class*="tab"]:has-text("文章")').first
            if await tab2.count() > 0:
                await tab2.click()
                logger.info("Clicked '文章' tab (fallback)")
        await page.wait_for_timeout(3000)
        
        all_items = []
        seen_urls = set()
        no_new = 0
        
        for scroll in range(50):
            if len(all_items) >= max_articles:
                break
            
            items = await page.evaluate(EXTRACT_JS)
            new_count = 0
            for item in items:
                u = item.get("url", "")
                if u and u not in seen_urls:
                    seen_urls.add(u)
                    all_items.append(item)
                    new_count += 1
            
            logger.info("  scroll %d: page=%d new=%d total=%d/%d",
                        scroll, len(items), new_count, len(all_items), max_articles)
            
            if new_count == 0:
                no_new += 1
            else:
                no_new = 0
            if no_new >= 3:
                break
            
            await page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
            await page.wait_for_timeout(2000)
        
        result = all_items[:max_articles]
        logger.info("Fetched %d articles", len(result))
        return {"code": 0, "msg": "success", "data": result, "total": len(result)}
    
    except Exception as e:
        logger.error("Failed: %s", e, exc_info=True)
        return {"code": 1, "msg": str(e), "data": [], "total": 0}
    finally:
        await context.close()

# ==================== API 路由 ====================
@app.get("/")
async def root():
    return {
        "service": "头条文章抓取API",
        "version": "1.0.0",
        "endpoints": {
            "/health": "健康检查",
            "/api/v1/toutiao/user/articles": "获取用户文章列表",
            "/status": "服务状态",
            "/docs": "API文档"
        }
    }

@app.get("/health")
async def health_check():
    return {"status": "ok", "browser_ready": browser_instance is not None}

@app.get("/status")
async def status_check():
    return {
        "browser_initialized": browser_instance is not None,
        "playwright_initialized": playwright_instance is not None,
        "message": "Browser reuse mode is active"
    }

@app.get("/api/v1/toutiao/user/articles", response_model=ApiResponse)
async def get_user_articles(
    token: str = Query(..., description="用户token，例如: MS4wLjABAAAAFhuod-Bd5eUvbaGT4iLDU0T1gzo8G5IlV_IV6eDZPt4"),
    max_articles: int = Query(20, ge=1, le=100, description="最大抓取文章数(1-100)")
):
    """获取头条用户文章列表（GET方式）"""
    if not token:
        raise HTTPException(status_code=400, detail="token参数不能为空")
    
    try:
        result = await fetch_user_articles(token, max_articles)
        if result["code"] != 0:
            raise HTTPException(status_code=500, detail=result["msg"])
        return result
    except Exception as e:
        logger.error("API error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/toutiao/user/articles", response_model=ApiResponse)
async def post_user_articles(
    token: str = Query(..., description="用户token"),
    max_articles: int = Query(20, ge=1, le=100)
):
    """获取头条用户文章列表（POST方式）"""
    return await get_user_articles(token, max_articles)

# ==================== 启动入口 ====================
if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        reload=False
    )
PYEOF

echo "✅ Python代码已生成: toutiao_api.py"

# ============================================
# 2. 生成 start.sh（使用当前目录）
# ============================================
cat > start.sh << 'EOF'
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
EOF

# ============================================
# 3. 生成 stop.sh（使用当前目录）
# ============================================
cat > stop.sh << 'EOF'
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
EOF

# ============================================
# 4. 生成 restart.sh
# ============================================
cat > restart.sh << 'EOF'
#!/bin/bash
# 头条API服务重启脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "正在重启头条API服务..."
./stop.sh
sleep 2
./start.sh
EOF

# ============================================
# 5. 生成 status.sh
# ============================================
cat > status.sh << 'EOF'
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
EOF

# ============================================
# 6. 生成 logs.sh
# ============================================
cat > logs.sh << 'EOF'
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
EOF

# ============================================
# 7. 生成 deploy.sh（一键部署，Mac适配）
# ============================================
cat > deploy.sh << 'EOF'
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
EOF

# ============================================
# 8. 生成 commands.txt（命令参考，Mac适配）
# ============================================
cat > commands.txt << 'EOF'
============================================
  头条API服务 - 常用命令 (Mac版)
============================================

一、服务管理
------------
./deploy.sh      # 首次部署（自动安装依赖）
./start.sh       # 启动服务
./stop.sh        # 停止服务
./restart.sh     # 重启服务
./status.sh      # 查看状态
./logs.sh        # 查看日志
./logs.sh -f     # 实时查看日志

二、测试接口
------------
# 健康检查
curl http://localhost:8000/health

# 获取文章列表
curl "http://localhost:8000/api/v1/toutiao/user/articles?token=YOUR_TOKEN&max_articles=5"

# 查看API文档
浏览器打开: http://localhost:8000/docs

三、Conda 环境管理
------------
# 激活环境
conda activate playwright

# 退出环境
conda deactivate

四、故障排查
------------
# 查看端口占用 (Mac)
lsof -i :8000

# 查看进程
ps aux | grep toutiao_api.py

# 查看完整日志
cat logs/toutiao.log

# 手动启动（前台运行，便于调试）
python toutiao_api.py
============================================
EOF

# ============================================
# 9. 生成 requirements.txt
# ============================================
cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
playwright==1.40.0
pydantic==2.5.0
EOF

# ============================================
# 10. 生成 .gitignore
# ============================================
cat > .gitignore << 'EOF'
# 日志
logs/
*.log

# PID
*.pid

# Python
__pycache__/
*.pyc
*.pyo
.pytest_cache/

# 环境
.env
.env.local
venv/
.venv/

# IDE
.vscode/
.idea/
*.swp
*.swo

# 临时
tmp/
temp/
*.tmp
.DS_Store
EOF

# ============================================
# 设置执行权限
# ============================================
chmod +x start.sh stop.sh restart.sh status.sh logs.sh deploy.sh

# ============================================
# 创建日志目录
# ============================================
mkdir -p logs

# ============================================
# 完成提示
# ============================================
echo ""
echo "=========================================="
echo "✅ 所有文件已生成！"
echo "=========================================="
echo ""
echo "📁 生成的文件:"
ls -la *.py *.sh *.txt 2>/dev/null
echo ""
echo "=========================================="
echo "📋 下一步操作:"
echo "1. 运行部署: ./deploy.sh"
echo "   或直接启动: ./start.sh"
echo ""
echo "2. 查看API文档: http://localhost:8000/docs"
echo ""
echo "3. 查看命令参考: cat commands.txt"
echo "=========================================="

# 给自身加执行权限
chmod +x bootstrap.sh
