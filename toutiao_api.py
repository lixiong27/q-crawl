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
