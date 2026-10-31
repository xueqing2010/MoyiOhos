#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fallback manual PDF renderer using Pillow + Noto Sans CJK.

This avoids Pages export issues and guarantees no blank pages. The DOCX remains
the editable master; this PDF is generated from its paragraphs/tables in order.
"""
from __future__ import annotations

import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from docx import Document
from docx.table import Table
from docx.text.paragraph import Paragraph
from docx.oxml.ns import qn

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "softcopyright"
FONT = ROOT / "entry/src/main/resources/rawfile/fonts/NotoSansSC.otf"
IMAGES = ROOT / "docs/images"
W, H = 1240, 1754  # A4 @150dpi
MARGIN = 84
BODY_TOP = 112
BODY_BOTTOM = H - 80
FONT_BODY = 23
FONT_H1 = 34
FONT_H2 = 28
FONT_TABLE = 18
FONT_HEADER = 16
LINE = 34
TITLE = "墨译漫画小说智能翻译软件"
VERSION = "V1.1.0"


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT), size)


def new_page() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)
    d.text((MARGIN, 34), TITLE + " " + VERSION + "  软件说明书", font=font(FONT_HEADER), fill=(60, 60, 60))
    d.text((W - MARGIN, 34), "第 1 页", font=font(FONT_HEADER), fill=(60, 60, 60), anchor="ra")
    return img, d


def wrap(text: str, f: ImageFont.FreeTypeFont, max_w: int) -> list[str]:
    lines: list[str] = []
    cur = ""
    for ch in text:
        if ch == "\n":
            lines.append(cur)
            cur = ""
            continue
        candidate = cur + ch
        if f.getlength(candidate) <= max_w or not cur:
            cur = candidate
        else:
            lines.append(cur)
            cur = ch
    if cur:
        lines.append(cur)
    return lines


def add_page_number(img: Image.Image, n: int) -> None:
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, 84), fill="white")
    d.text((MARGIN, 34), TITLE + " " + VERSION + "  软件说明书", font=font(FONT_HEADER), fill=(60, 60, 60))
    d.text((W - MARGIN, 34), f"第 {n} 页", font=font(FONT_HEADER), fill=(60, 60, 60), anchor="ra")


def draw_cover() -> Image.Image:
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)
    d.text((W // 2, 360), TITLE, font=font(44), fill=(0, 0, 0), anchor="ma")
    d.text((W // 2, 440), "软件说明书", font=font(34), fill=(0, 0, 0), anchor="ma")
    d.text((W // 2, 500), "（计算机软件著作权登记文档鉴别材料）", font=font(21), fill=(80, 80, 80), anchor="ma")
    d.line((MARGIN, 600, W - MARGIN, 600), fill=(180, 180, 180), width=1)
    rows = [("软件版本", VERSION), ("著作权人", "薛朝坤"), ("编制日期", "2026年10月")]
    y = 760
    for k, v in rows:
        d.text((W // 2 - 60, y), k + "：", font=font(22), fill=(0, 0, 0), anchor="ra")
        d.text((W // 2 - 40, y), v, font=font(22), fill=(0, 0, 0))
        y += 48
    d.text((W // 2, H - 120), "中国版权保护中心 计算机软件著作权登记", font=font(16), fill=(120, 120, 120), anchor="ma")
    return img


def iter_blocks(doc: Document):
    body = doc.element.body
    for child in body.iterchildren():
        if child.tag == qn("w:p"):
            yield Paragraph(child, doc)
        elif child.tag == qn("w:tbl"):
            yield Table(child, doc)


def main() -> None:
    doc = Document(str(OUT / "01-软件说明书.docx"))
    pages: list[Image.Image] = [draw_cover()]
    img, d = new_page()
    y = BODY_TOP
    page_no = 1
    started = False

    def flush() -> None:
        nonlocal img, d, y, page_no
        add_page_number(img, page_no)
        pages.append(img)
        page_no += 1
        img, d = new_page()
        y = BODY_TOP

    def need(h: int) -> None:
        nonlocal y
        if y + h > BODY_BOTTOM:
            flush()

    for block in iter_blocks(doc):
        if isinstance(block, Table):
            rows: list[list[str]] = []
            for row in block.rows:
                cells = [c.text.replace("\n", " ").strip() for c in row.cells]
                rows.append(wrap("  |  ".join(cells), font(FONT_TABLE), W - 2 * MARGIN))
            total = sum(max(1, len(r)) * 28 + 4 for r in rows) + 8
            if y + total > BODY_BOTTOM:
                flush()
            for row_lines in rows:
                for ln in row_lines:
                    d.text((MARGIN, y), ln, font=font(FONT_TABLE), fill=(30, 30, 30))
                    y += 28
                y += 4
            y += 8
            continue
        text = block.text.strip()
        if not text:
            continue
        if not started:
            if text == "目录":
                started = True
            else:
                continue
        is_h1 = bool(re.match(r"^\d+\s", text)) or text.startswith("附录")
        is_h2 = bool(re.match(r"^\d+\.\d+\s", text)) or bool(re.match(r"^[A-Z]\.\d+\s", text))
        if is_h1:
            if y > BODY_TOP + 60:
                flush()
            d.text((MARGIN, y), text, font=font(FONT_H1), fill=(0, 0, 0))
            y += 56
        elif is_h2:
            need(42)
            d.text((MARGIN, y), text, font=font(FONT_H2), fill=(0, 0, 0))
            y += 42
        else:
            f = font(FONT_BODY)
            for ln in wrap(text, f, W - 2 * MARGIN):
                need(LINE)
                d.text((MARGIN, y), ln, font=f, fill=(30, 30, 30))
                y += LINE
            y += 6


    # Screenshot appendix: continue on the current page, 2 x 2 grid.
    if y > BODY_BOTTOM - 100:
        flush()
    d.text((MARGIN, y), "附录 E 界面截图", font=font(FONT_H1), fill=(0, 0, 0))
    y += 60
    items = [
        ("phone-shelf.jpg", "手机书架与导入入口"),
        ("reader-original.jpg", "漫画阅读原文"),
        ("ocr-overlay.jpg", "译文覆盖层"),
        ("text-translate.jpg", "文本翻译页面"),
    ]
    for page_start in range(0, len(items), 4):
        if page_start > 0:
            flush()
            y = BODY_TOP
        for j in range(4):
            idx = page_start + j
            if idx >= len(items):
                break
            name, cap = items[idx]
            path = IMAGES / name
            if not path.exists():
                continue
            im = Image.open(path).convert("RGB")
            maxw, maxh = 470, 430
            if im.width > maxw:
                im = im.resize((maxw, int(im.height * maxw / im.width)))
            if im.height > maxh:
                im = im.resize((int(im.width * maxh / im.height), maxh))
            col = j % 2
            row = j // 2
            iy = y + row * 480
            x = MARGIN + col * 520 + (470 - im.width) // 2
            img.paste(im, (x, iy))
            d.text((x + 235, iy + im.height + 8), "图：" + cap, font=font(18),
                   fill=(100, 100, 100), anchor="ma")
    if y > BODY_TOP:
        flush()

    for i, p in enumerate(pages):
        p.save(f"/tmp/manual-page-{i+1:02d}.png")

    out = OUT / "01-软件说明书.pdf"
    pages[0].save(out, "PDF", resolution=150.0, save_all=True,
                  append_images=pages[1:])
    print("wrote", out, "pages", len(pages))


if __name__ == "__main__":
    main()
