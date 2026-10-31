import { DisplayRect } from './Geometry';
import {
  LayoutEngine,
  LayoutRun,
  OverlayRegion,
  RenderOptions,
  RenderOrientation,
  TextLayout,
  VerticalDirection
} from './LayoutEngine';

/**
 * 一个待绘制的覆盖块：白块矩形（页面坐标）+ 文本 + 已完成的排版。
 * box/layout 均为**页面像素坐标**，渲染端按 contain-fit 变换后逐字绘制。
 */
export interface OverlayItem {
  box: DisplayRect;
  text: string;
  layout: TextLayout;
  /** 合并了多少个 OCR 行（1 = 未合并）。 */
  merged: number;
  /** 该块文字色；空串表示用调用方默认色。 */
  textColor?: string;
  /** 该块对应的 OCR 行索引（用于气泡级人工校对）。 */
  indices?: Array<number>;
}

function makeOverlayItem(box: DisplayRect, text: string, layout: TextLayout, merged: number,
  textColor?: string, indices?: Array<number>): OverlayItem {
  const item: OverlayItem = { box: box, text: text, layout: layout, merged: merged };
  if (textColor !== undefined) {
    item.textColor = textColor;
  }
  if (indices !== undefined) {
    item.indices = indices;
  }
  return item;
}

/** 矩形并集。 */
function unionRect(a: DisplayRect, b: DisplayRect): DisplayRect {
  const x = Math.min(a.x, b.x);
  const y = Math.min(a.y, b.y);
  const right = Math.max(a.x + a.w, b.x + b.w);
  const bottom = Math.max(a.y + a.h, b.y + b.h);
  const r: DisplayRect = { x: x, y: y, w: right - x, h: bottom - y };
  return r;
}

function overlapX(a: DisplayRect, b: DisplayRect): number {
  const left = Math.max(a.x, b.x);
  const right = Math.min(a.x + a.w, b.x + b.w);
  return right - left;
}

function overlapY(a: DisplayRect, b: DisplayRect): number {
  const top = Math.max(a.y, b.y);
  const bottom = Math.min(a.y + a.h, b.y + b.h);
  return bottom - top;
}

function gapX(a: DisplayRect, b: DisplayRect): number {
  const left = Math.max(a.x, b.x);
  const right = Math.min(a.x + a.w, b.x + b.w);
  return left - right;
}

function gapY(a: DisplayRect, b: DisplayRect): number {
  const top = Math.max(a.y, b.y);
  const bottom = Math.min(a.y + a.h, b.y + b.h);
  return top - bottom;
}

/** 白块合并容差（页面像素）：OCR 同一气泡的多行盒之间常见 1-6px 缝隙。 */
const MERGE_GAP = 6;
/** 垂直/水平重叠比例下限，避免把并排的两个气泡错误合并。 */
const MERGE_OVERLAP_RATIO = 0.7;

/**
 * 判断两个 OCR 行盒是否属于同一“白块”：
 * - 严格相交（有面积重叠）→ 合并；
 * - 同处一行（Y 重叠 ≥70%）且水平缝隙 ≤ MERGE_GAP → 合并；
 * - 同处一列（X 重叠 ≥70%）且垂直缝隙 ≤ MERGE_GAP → 合并。
 */
function shouldMerge(a: DisplayRect, b: DisplayRect): boolean {
  const ox = overlapX(a, b);
  const oy = overlapY(a, b);
  if (ox > 0 && oy > 0) {
    return true;
  }
  const minH = Math.min(a.h, b.h);
  const minW = Math.min(a.w, b.w);
  const sameRow = minH > 0 && oy >= minH * MERGE_OVERLAP_RATIO && gapX(a, b) <= MERGE_GAP;
  const sameCol = minW > 0 && ox >= minW * MERGE_OVERLAP_RATIO && gapY(a, b) <= MERGE_GAP;
  return sameRow || sameCol;
}

/** 拉丁词之间补空格，CJK 直接相连（译文拼接后仍然可读）。 */
function joinText(prev: string, next: string): string {
  if (prev.length === 0) {
    return next;
  }
  if (next.length === 0) {
    return prev;
  }
  const a = prev.charCodeAt(prev.length - 1);
  const b = next.charCodeAt(0);
  const aLatin = (a >= 0x30 && a <= 0x39) || (a >= 0x41 && a <= 0x5A) || (a >= 0x61 && a <= 0x7A);
  const bLatin = (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A);
  if (aLatin && bLatin) {
    return prev + ' ' + next;
  }
  return prev + next;
}

/** 单个框的横/竖排推断：竖长框→竖排，横宽框→横排；近似方形时参考文本长度。 */
function inferOrientation(box: DisplayRect, text: string): RenderOrientation {
  if (box.w <= 0 || box.h <= 0) {
    return RenderOrientation.HORIZONTAL;
  }
  const ratio = box.h / box.w;
  if (ratio >= 1.35) {
    return RenderOrientation.VERTICAL;
  }
  if (box.w / box.h >= 1.35) {
    return RenderOrientation.HORIZONTAL;
  }
  // 近方形：多字且不宽于高，按日漫常见的竖排处理。
  if (text.length >= 3 && box.h >= box.w) {
    return RenderOrientation.VERTICAL;
  }
  return RenderOrientation.HORIZONTAL;
}

/** 把 AUTO 解析成 concrete options；非 AUTO 直接复用。 */
function resolveOptions(opts: RenderOptions, box: DisplayRect, text: string): RenderOptions {
  if (opts.orientation !== RenderOrientation.AUTO) {
    return opts;
  }
  const out: RenderOptions = {
    orientation: inferOrientation(box, text),
    verticalDirection: opts.verticalDirection,
    fontSizeMode: opts.fontSizeMode,
    fixedFontSize: opts.fixedFontSize,
    padding: opts.padding,
    lineSpacing: opts.lineSpacing,
    charSpacing: opts.charSpacing,
    pageWidth: opts.pageWidth,
    pageHeight: opts.pageHeight
  };
  return out;
}

/** 排序键：横排按 行(y)→列(x)；竖排按 列(x)→行(y)（RTL 列从右到左）。 */
function sortMembers(members: Array<number>, boxes: Array<DisplayRect>, opts: RenderOptions): void {
  const vertical = opts.orientation === RenderOrientation.VERTICAL;
  const rtl = opts.verticalDirection === VerticalDirection.RTL;
  members.sort((ia: number, ib: number) => {
    const a = boxes[ia];
    const b = boxes[ib];
    if (vertical) {
      const ax = rtl ? -a.x : a.x;
      const bx = rtl ? -b.x : b.x;
      if (Math.abs(ax - bx) > 1) {
        return ax < bx ? -1 : 1;
      }
      return a.y < b.y ? -1 : (a.y > b.y ? 1 : 0);
    }
    if (Math.abs(a.y - b.y) > 1) {
      return a.y < b.y ? -1 : 1;
    }
    return a.x < b.x ? -1 : (a.x > b.x ? 1 : 0);
  });
}

/**
 * 覆盖层规划器（阅读器屏幕渲染与导出离屏合成都走这一条路径，plan D9）：
 * 1) 按“白块合并”开关把重叠/紧邻的 OCR 行盒合并成一个矩形；
 * 2) 合并后的文本按阅读顺序拼接；
 * 3) 在**页面坐标系**里对每个矩形做 LayoutEngine 排版。
 * 渲染端只负责 contain-fit 变换后逐字绘制（OverlayRenderer.paintPlan）。
 */
export class PageOverlay {
  static build(regions: Array<OverlayRegion>, opts: RenderOptions, useTranslated: boolean,
    mergeWhite: boolean): Array<OverlayItem> {
    const boxes: Array<DisplayRect> = [];
    const texts: Array<string> = [];
    const colors: Array<string> = [];
    for (let i = 0; i < regions.length; i++) {
      const region = regions[i];
      const text = useTranslated ? region.translated : region.original;
      if (text === undefined || text === null || text.length === 0) {
        continue;
      }
      if (region.box.w <= 0 || region.box.h <= 0) {
        continue;
      }
      let bx = region.box.x;
      let by = region.box.y;
      let bw = region.box.w;
      let bh = region.box.h;
      // OCR/导入的框可能越出页面（例如示例数据或误识别），先裁剪到页面内，
      // 否则白块会画到漫画页面之外，表现为“页面渲染错位/白块越界”。
      const pageW = opts.pageWidth !== undefined ? opts.pageWidth : 0;
      const pageH = opts.pageHeight !== undefined ? opts.pageHeight : 0;
      if (pageW > 0 && pageH > 0) {
        const left = Math.max(0, Math.min(bx, pageW));
        const top = Math.max(0, Math.min(by, pageH));
        const right = Math.max(0, Math.min(bx + bw, pageW));
        const bottom = Math.max(0, Math.min(by + bh, pageH));
        bx = left;
        by = top;
        bw = right - left;
        bh = bottom - top;
        if (bw <= 0 || bh <= 0) {
          continue;
        }
      }
      const box: DisplayRect = { x: bx, y: by, w: bw, h: bh };
      boxes.push(box);
      texts.push(text);
      colors.push(region.textColor !== undefined ? region.textColor : '');
    }
    const count = boxes.length;
    const items: Array<OverlayItem> = [];
    if (count === 0) {
      return items;
    }
    if (!mergeWhite || count === 1) {
      for (let i = 0; i < count; i++) {
        const layout = LayoutEngine.layout(texts[i], boxes[i], resolveOptions(opts, boxes[i], texts[i]));
        items.push(makeOverlayItem(boxes[i], texts[i], layout, 1, colors[i], [i]));
      }
      return items;
    }

    // 并查集分组
    const parent: Array<number> = [];
    for (let i = 0; i < count; i++) {
      parent.push(i);
    }
    const findRoot = (i: number): number => {
      let cur = i;
      while (parent[cur] !== cur) {
        parent[cur] = parent[parent[cur]];
        cur = parent[cur];
      }
      return cur;
    };
    for (let i = 0; i < count; i++) {
      for (let j = i + 1; j < count; j++) {
        if (shouldMerge(boxes[i], boxes[j])) {
          const ri = findRoot(i);
          const rj = findRoot(j);
          if (ri !== rj) {
            parent[rj] = ri;
          }
        }
      }
    }
    // 收集分组
    const roots: Array<number> = [];
    const groups: Array<Array<number>> = [];
    for (let i = 0; i < count; i++) {
      const root = findRoot(i);
      let gi = roots.indexOf(root);
      if (gi < 0) {
        roots.push(root);
        const members: Array<number> = [];
        groups.push(members);
        gi = groups.length - 1;
      }
      groups[gi].push(i);
    }
    for (let g = 0; g < groups.length; g++) {
      const members = groups[g];
      let box: DisplayRect = boxes[members[0]];
      let text = '';
      let textColor = '';
      const indices: Array<number> = [];
      for (let k = 0; k < members.length; k++) {
        const idx = members[k];
        box = unionRect(box, boxes[idx]);
        text = joinText(text, texts[idx]);
        indices.push(idx);
        if (textColor.length === 0 && colors[idx].length > 0) {
          textColor = colors[idx];
        }
      }
      // 合并后按整块宽高重新推断方向，再按该方向排序成员。
      const groupOpts = resolveOptions(opts, box, text);
      sortMembers(members, boxes, groupOpts);
      const layout = LayoutEngine.layout(text, box, groupOpts);
      items.push(makeOverlayItem(box, text, layout, members.length, textColor, indices));
    }
    return items;
  }

  /** 自检用：返回的每个 item 的 run 数总和（应等于字符总数，AUTO 不丢字）。 */
  static totalRuns(items: Array<OverlayItem>): number {
    let total = 0;
    for (let i = 0; i < items.length; i++) {
      total += items[i].layout.runs.length;
    }
    return total;
  }

  /** 排版后的字符 runs（供导出/测试复用）。 */
  static allRuns(items: Array<OverlayItem>): Array<LayoutRun> {
    const runs: Array<LayoutRun> = [];
    for (let i = 0; i < items.length; i++) {
      const itemRuns = items[i].layout.runs;
      for (let k = 0; k < itemRuns.length; k++) {
        runs.push(itemRuns[k]);
      }
    }
    return runs;
  }
}
