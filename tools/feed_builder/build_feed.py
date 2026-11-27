#!/usr/bin/env python3
"""
零依赖静态普法资讯生成器（纯 Python 3 标准库）。
读取 tools/feed_builder/sources.json：
1. 拉取已启用的公开 RSS/Atom 源（单源超时/失败自动跳过，不中断整体构建）；
2. 仅保留元数据（标题、来源、时间、分类、短摘要、原文链接与关联法条），绝不全文转载版权正文；
3. 与 curated 精选条目合并去重、按发布时间倒序输出 docs/feed.json。
"""

from __future__ import annotations

import datetime as dt
import email.utils
import hashlib
import html
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES_PATH = ROOT / "tools" / "feed_builder" / "sources.json"
OUTPUT_PATH = ROOT / "docs" / "feed.json"
TIMEOUT_SECONDS = 12
USER_AGENT = "LaborLawAI-FeedBuilder/1.0 (+https://github.com/cnbq517-tech/LaborLaw-AI-Agent-AI-)"

LABOR_KEYWORDS = (
    "劳动", "工资", "欠薪", "社保", "医保", "工伤", "失业", "养老",
    "加班", "休假", "年假", "试用期", "辞退", "解雇", "裁员", "仲裁",
    "就业", "职工", "新就业形态", "竞业", "最低工资", "生育津贴", "女职工",
)

CATEGORY_RULES: list[tuple[str, tuple[str, ...], list[str]]] = [
    ("欠薪", ("欠薪", "拖欠工资", "克扣", "工资支付", "发薪", "最低工资"), ["《中华人民共和国劳动法》第五十条", "《中华人民共和国劳动合同法》第三十条"]),
    ("辞退", ("辞退", "解雇", "违法解除", "裁员", "调岗", "降薪", "经济补偿", "赔偿金", "逼退"), ["《中华人民共和国劳动合同法》第四十七条", "《中华人民共和国劳动合同法》第八十七条"]),
    ("试用期", ("试用期", "录用条件", "转正"), ["《中华人民共和国劳动合同法》第十九条", "《中华人民共和国劳动合同法》第二十一条"]),
    ("加班", ("加班", "工时", "休息休假", "年休假", "调休"), ["《中华人民共和国劳动法》第四十四条", "《中华人民共和国劳动合同法》第三十一条"]),
    ("社保", ("社保", "社会保险", "五险一金", "公积金", "工伤", "医保", "生育"), ["《中华人民共和国社会保险法》第五十八条", "《中华人民共和国劳动合同法》第三十八条"]),
    ("合同", ("劳动合同", "未签合同", "二倍工资", "竞业", "押金", "违约金"), ["《中华人民共和国劳动合同法》第十条", "《中华人民共和国劳动合同法》第八十二条"]),
]


def strip_html(raw: str) -> str:
    text = re.sub(r"<[^>]+>", " ", raw or "")
    text = html.unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def truncate(text: str, limit: int = 100) -> str:
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip("，,。；; ") + "…"


def classify(title: str, summary: str, default_category: str = "政策") -> tuple[str, list[str]]:
    haystack = f"{title} {summary}"
    for cat, keywords, laws in CATEGORY_RULES:
        if any(kw in haystack for kw in keywords):
            return cat, laws
    return default_category, ["《中华人民共和国劳动合同法》"]


def is_labor_related(title: str, summary: str) -> bool:
    haystack = f"{title} {summary}"
    return any(kw in haystack for kw in LABOR_KEYWORDS)


def parse_date(raw: str) -> str:
    raw = (raw or "").strip()
    if not raw:
        return dt.date.today().isoformat()
    # ISO-like date: 2026-11-27...
    m = re.search(r"(\d{4})-(\d{1,2})-(\d{1,2})", raw)
    if m:
        return f"{int(m.group(1)):04d}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
    # RFC 2822 date
    try:
        parsed = email.utils.parsedate_to_datetime(raw)
        return parsed.date().isoformat()
    except Exception:
        return dt.date.today().isoformat()


def stable_id(url: str, title: str) -> str:
    digest = hashlib.sha256(f"{url}|{title}".encode("utf-8")).hexdigest()[:12]
    return f"feed-{digest}"


def fetch_rss(feed_cfg: dict[str, Any]) -> list[dict[str, Any]]:
    url = feed_cfg["url"]
    name = feed_cfg["name"]
    default_cat = feed_cfg.get("defaultCategory", "政策")
    filter_labor = bool(feed_cfg.get("filterLaborOnly", True))

    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
            data = resp.read()
    except Exception as exc:
        print(f"[WARN] Skip feed '{name}' ({url}): {exc}", file=sys.stderr)
        return []

    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        print(f"[WARN] Invalid XML from '{name}': {exc}", file=sys.stderr)
        return []

    items: list[dict[str, Any]] = []
    # Support RSS 2.0 <item> and Atom <entry>
    entries = root.findall(".//item")
    if not entries:
        entries = root.findall(".//{http://www.w3.org/2005/Atom}entry")

    for entry in entries:
        title = strip_html(entry.findtext("title") or entry.findtext("{http://www.w3.org/2005/Atom}title") or "")
        link = (entry.findtext("link") or "").strip()
        if not link:
            link_el = entry.find("{http://www.w3.org/2005/Atom}link")
            if link_el is not None:
                link = (link_el.attrib.get("href") or "").strip()
        desc = strip_html(
            entry.findtext("description")
            or entry.findtext("{http://www.w3.org/2005/Atom}summary")
            or ""
        )
        pub_raw = (
            entry.findtext("pubDate")
            or entry.findtext("{http://www.w3.org/2005/Atom}updated")
            or entry.findtext("{http://www.w3.org/2005/Atom}published")
            or ""
        )
        if not title or not link:
            continue
        if filter_labor and not is_labor_related(title, desc):
            continue

        category, laws = classify(title, desc, default_cat)
        items.append({
            "id": stable_id(link, title),
            "title": title,
            "source": name,
            "category": category,
            "publishedAt": parse_date(pub_raw),
            "summary": truncate(desc or title, 100),
            "url": link,
            "relatedLaws": laws,
        })
    print(f"[INFO] Fetched {len(items)} labor items from '{name}'")
    return items


def main() -> int:
    cfg = json.loads(SOURCES_PATH.read_text(encoding="utf-8"))
    max_items = int(cfg.get("maxItems", 60))

    collected: list[dict[str, Any]] = []
    for feed_cfg in cfg.get("feeds", []):
        if feed_cfg.get("enabled", True):
            collected.extend(fetch_rss(feed_cfg))

    for curated in cfg.get("curated", []):
        item = dict(curated)
        item.setdefault("id", stable_id(item.get("url", ""), item.get("title", "")))
        item["publishedAt"] = parse_date(item.get("publishedAt", ""))
        collected.append(item)

    # Deduplicate by (title) preserving curated metadata priority on tie
    seen_titles: set[str] = set()
    unique: list[dict[str, Any]] = []
    # Sort newest first
    collected.sort(key=lambda x: (x.get("publishedAt", ""), x.get("id", "")), reverse=True)
    for item in collected:
        key = item["title"].strip()
        if key in seen_titles:
            continue
        seen_titles.add(key)
        unique.append(item)
        if len(unique) >= max_items:
            break

    payload = {
        "version": 1,
        "updatedAt": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "items": unique,
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[OK] Wrote {len(unique)} items to {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
