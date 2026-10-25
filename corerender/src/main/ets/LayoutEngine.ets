import { DisplayRect } from './Geometry';

/** Text orientation inside bubbles. */
export enum RenderOrientation {
  HORIZONTAL = 0,
  VERTICAL = 1
}

/** Column flow direction for vertical text (manga default: RTL). */
export enum VerticalDirection {
  RTL = 0,
  LTR = 1
}

export enum FontSizeMode {
  AUTO = 0,
  FIXED = 1
}

/**
 * 全局渲染设置（preferences starflow_reader 持久化）。
 * lineSpacing / charSpacing 为可选增量（×字号），0 表示自然间距；
 * 作为可选字段保证既有调用方的对象字面量继续兼容。
 */
export interface RenderOptions {
  orientation: RenderOrientation;
  verticalDirection: VerticalDirection;
  fontSizeMode: FontSizeMode;
  fixedFontSize: number;
  padding: number;
  /** 额外行距（横排行距 / 竖排列距），单位 = ×字号，0 为自然间距。 */
  lineSpacing?: number;
  /** 额外字距（横排字距 / 竖排列内字距），单位 = ×字号，0 为自然间距。 */
  charSpacing?: number;
  /** 页面像素宽（可选）：用于把 OCR 框裁剪到页面内，避免白块越界。 */
  pageWidth?: number;
  /** 页面像素高（可选）。 */
  pageHeight?: number;
}

/** One positioned character; x/y mark the char cell CENTER (display/page coords). */
export interface LayoutRun {
  char: string;
  x: number;
  y: number;
  fontSize: number;
}

export interface TextLayout {
  runs: Array<LayoutRun>;
  truncated: boolean;
  measuredFontSize: number;
}

/** A bubble region; box is in PAGE pixel coordinates (renderer applies the fit transform). */
export interface OverlayRegion {
  box: DisplayRect;
  original: string;
  translated: string;
}

/** Character width measurer; default approximation is deterministic for tests. */
export interface CharMeasurer {
  measure(char: string, fontSize: number): number;
}

/**
 * 竖排列式回归自检（单测式，纯函数、无 UI 依赖）。
 * 供阅读器设置面板 / 开发者工作台直接调用展示；不通过时 detail 给出实测值。
 */
export class SelfTestResult {
  name: string = '';
  passed: boolean = false;
  detail: string = '';
}

export function makeSelfTestResult(name: string, passed: boolean, detail: string): SelfTestResult {
  const r: SelfTestResult = { name: name, passed: passed, detail: detail };
  return r;
}

const MIN_FONT_AUTO = 1;
const MIN_FONT_FIXED = 6;
const MAX_FONT = 72;
/** 横排自然行距系数。 */
const H_LINE_RATIO = 1.3;
/** 竖排列内自然字步进系数。 */
const V_CHAR_RATIO = 1.08;
/** 竖排列间自然步进系数。 */
const V_COL_RATIO = 1.1;
/** 竖排列距（列间空白）拉伸上限（×字号）：既能“列距拉伸铺满”，又不会散架。 */
const MAX_COL_GAP = 2.5;
const EPS = 0.01;
const ELLIPSIS = '…';
const NO_START_CHARS = '，。、！？；：…）」』】〉》,.!?;:)';

/** 汉字/全角统一按 1 字宽，拉丁按比例；确定性便于单测。 */
export class ApproxCharMeasurer implements CharMeasurer {
  measure(char: string, fontSize: number): number {
    if (char === ' ') {
      return fontSize * 0.3;
    }
    const code = char.charCodeAt(0);
    if (code < 0x80) {
      const isAlnum = (code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
      return isAlnum ? fontSize * 0.56 : fontSize * 0.5;
    }
    return fontSize;
  }
}

export function defaultRenderOptions(): RenderOptions {
  const o: RenderOptions = {
    orientation: RenderOrientation.VERTICAL,
    verticalDirection: VerticalDirection.RTL,
    fontSizeMode: FontSizeMode.AUTO,
    fixedFontSize: 16,
    padding: 4,
    lineSpacing: 0,
    charSpacing: 0
  };
  return o;
}

export function makeOverlayRegion(box: DisplayRect, original: string, translated: string): OverlayRegion {
  const r: OverlayRegion = { box: box, original: original, translated: translated };
  return r;
}

function emptyLayout(): TextLayout {
  const t: TextLayout = { runs: [], truncated: false, measuredFontSize: 0 };
  return t;
}

function isNoStart(c: string): boolean {
  return NO_START_CHARS.indexOf(c) >= 0;
}

/** 点串成员（用于“点串绝不跨行/跨列”规则）。 */
function isEllipsisDot(c: string): boolean {
  return c === '…' || c === '.' || c === '。';
}

/** 拆成字符数组（保留代理对，去掉换行；竖排里换行没有意义）。 */
function splitChars(text: string): Array<string> {
  const chars: Array<string> = [];
  let i = 0;
  while (i < text.length) {
    const code = text.charCodeAt(i);
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
      const next = text.charCodeAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        chars.push(text.substring(i, i + 2));
        i += 2;
        continue;
      }
    }
    const ch = text.charAt(i);
    if (ch !== '\n' && ch !== '\r') {
      chars.push(ch);
    }
    i++;
  }
  return chars;
}

function resolvePadding(box: DisplayRect, padding: number): number {
  const p = padding > 0 ? padding : 0;
  const cap = Math.min(box.w, box.h) / 4;
  return p < cap ? p : cap;
}

function spacingOf(raw: number | undefined): number {
  if (raw === undefined) {
    return 0;
  }
  return raw > 0 ? raw : 0;
}

/** 复制 RenderOptions 并覆盖间距（用于“保底不丢字”：放弃额外间距再排一次）。 */
function optionsWithSpacing(opts: RenderOptions, lineSpacing: number, charSpacing: number): RenderOptions {
  const o: RenderOptions = {
    orientation: opts.orientation,
    verticalDirection: opts.verticalDirection,
    fontSizeMode: opts.fontSizeMode,
    fixedFontSize: opts.fixedFontSize,
    padding: opts.padding,
    lineSpacing: lineSpacing,
    charSpacing: charSpacing
  };
  return o;
}

// ---------------- 横排 ----------------

/**
 * 横排贪心换行（含字距预算）：
 * k 个字的行实际占 sum(width) + (k-1)*tracking，断行必须把 tracking 算进去。
 */
function wrapLines(chars: Array<string>, m: CharMeasurer, fs: number, maxWidth: number,
  tracking: number): Array<Array<string>> {
  const lines: Array<Array<string>> = [];
  let cur: Array<string> = [];
  let curW = 0;
  for (let idx = 0; idx < chars.length; idx++) {
    const c = chars[idx];
    const w = m.measure(c, fs);
    const addW = cur.length > 0 ? w + tracking : w;
    if (cur.length > 0 && curW + addW > maxWidth + EPS) {
      const lastChar = cur[cur.length - 1];
      const lastW = m.measure(lastChar, fs);
      if (isNoStart(c) && cur.length >= 2 && lastW + w + tracking <= maxWidth + EPS) {
        cur.pop();
        lines.push(cur);
        cur = [lastChar];
        curW = lastW;
      } else {
        lines.push(cur);
        cur = [];
        curW = 0;
      }
    }
    if (cur.length > 0) {
      curW += w + tracking;
    } else {
      curW = w;
    }
    cur.push(c);
  }
  if (cur.length > 0) {
    lines.push(cur);
  }
  return lines;
}

/** 由已断好的行生成 runs：整块垂直居中、行内水平居中；字距/行距不做额外拉伸。 */
function buildHorizontalRuns(lines: Array<Array<string>>, m: CharMeasurer, box: DisplayRect,
  padding: number, fs: number, opts: RenderOptions): Array<LayoutRun> {
  const runs: Array<LayoutRun> = [];
  const bw = box.w - padding * 2;
  const bh = box.h - padding * 2;
  const tracking = spacingOf(opts.charSpacing) * fs;
  // 行距只由用户设置决定（自然 1.3 + 额外行距），不为铺满额外拉伸；剩余空白整块居中。
  const lead = fs * (H_LINE_RATIO + spacingOf(opts.lineSpacing));
  const n = lines.length;
  const blockH = (n - 1) * lead + fs;
  const vOff = blockH < bh ? (bh - blockH) / 2 : 0;
  for (let i = 0; i < n; i++) {
    const line = lines[i];
    let lw = 0;
    for (let k = 0; k < line.length; k++) {
      lw += m.measure(line[k], fs);
    }
    if (line.length > 1) {
      lw += tracking * (line.length - 1);
    }
    let xCur = lw < bw ? (bw - lw) / 2 : 0;
    const yCenter = vOff + fs / 2 + i * lead;
    for (let k = 0; k < line.length; k++) {
      const c = line[k];
      const w = m.measure(c, fs);
      const run: LayoutRun = {
        char: c,
        x: box.x + padding + xCur + w / 2,
        y: box.y + padding + yCenter,
        fontSize: fs
      };
      runs.push(run);
      xCur += w + tracking;
    }
  }
  return runs;
}

/** 横排试排；装不下返回 undefined（不做截断）。 */
function tryHorizontal(chars: Array<string>, m: CharMeasurer, box: DisplayRect,
  padding: number, fs: number, opts: RenderOptions): TextLayout | undefined {
  const bw = box.w - padding * 2;
  const bh = box.h - padding * 2;
  if (bw <= 0 || bh <= 0) {
    return undefined;
  }
  const tracking = spacingOf(opts.charSpacing) * fs;
  const lines = wrapLines(chars, m, fs, bw, tracking);
  if (lines.length === 0) {
    return undefined;
  }
  const lead = fs * (H_LINE_RATIO + spacingOf(opts.lineSpacing));
  const blockH = (lines.length - 1) * lead + fs;
  if (blockH > bh + EPS) {
    return undefined;
  }
  const runs = buildHorizontalRuns(lines, m, box, padding, fs, opts);
  const t: TextLayout = { runs: runs, truncated: false, measuredFontSize: fs };
  return t;
}

// ---------------- 竖排 ----------------

/** 竖排每列可容纳字符数：末字下边缘必须落在可用高内。 */
function verticalCapacity(bh: number, fs: number, charStep: number): number {
  if (charStep <= 0 || bh < fs) {
    return 0;
  }
  return Math.floor((bh - fs) / charStep) + 1;
}

/**
 * 按列容量切分，列内自上而下逐字（顺序即 runs 顺序）；
 * 切点绝不落在点串内部（三个点的省略号整串进下一列）。
 */
function wrapColumns(chars: Array<string>, cap: number): Array<Array<string>> {
  const cols: Array<Array<string>> = [];
  if (cap < 1) {
    return cols;
  }
  let i = 0;
  while (i < chars.length) {
    let end = i + cap < chars.length ? i + cap : chars.length;
    if (end < chars.length && isEllipsisDot(chars[end - 1]) && isEllipsisDot(chars[end])) {
      let runStart = end - 1;
      while (runStart > i && isEllipsisDot(chars[runStart - 1])) {
        runStart--;
      }
      if (runStart > i) {
        end = runStart;
      }
    }
    const col: Array<string> = [];
    for (let k = i; k < end; k++) {
      col.push(chars[k]);
    }
    cols.push(col);
    i = end;
  }
  return cols;
}

/**
 * 竖排试排（页面坐标）：列从右到左（RTL）或左到右（LTR），列内自上而下；
 * 列块水平+垂直居中，列距拉伸铺满但 gap 上限 2.5×字号；装不下返回 undefined。
 */
function tryVertical(chars: Array<string>, box: DisplayRect, opts: RenderOptions,
  fs: number): TextLayout | undefined {
  const padding = resolvePadding(box, opts.padding);
  const bw = box.w - padding * 2;
  const bh = box.h - padding * 2;
  if (bw <= 0 || bh <= 0) {
    return undefined;
  }
  const charStep = fs * (V_CHAR_RATIO + spacingOf(opts.charSpacing));
  const cap = verticalCapacity(bh, fs, charStep);
  if (cap < 1) {
    return undefined;
  }
  const cols = wrapColumns(chars, cap);
  const nCols = cols.length;
  if (nCols === 0) {
    return undefined;
  }
  // 列距（列间空白）：自然列距 → 铺满可用宽的 rawGap，上限 2.5×字号；整块居中。
  const naturalGap = fs * (V_COL_RATIO - 1 + spacingOf(opts.lineSpacing));
  let gap = naturalGap;
  if (nCols > 1) {
    const rawGap = (bw - nCols * fs) / (nCols - 1);
    if (rawGap > gap) {
      gap = rawGap < fs * MAX_COL_GAP ? rawGap : fs * MAX_COL_GAP;
    }
  }
  const colStep = fs + gap;
  const totalW = (nCols - 1) * colStep + fs;
  if (totalW > bw + EPS) {
    return undefined;
  }
  let maxChars = 0;
  for (let j = 0; j < nCols; j++) {
    if (cols[j].length > maxChars) {
      maxChars = cols[j].length;
    }
  }
  const colH = (maxChars - 1) * charStep + fs;
  if (colH > bh + EPS) {
    return undefined;
  }
  // 列内逐字按自然步进，不做纵向拉伸；短列时整块垂直居中。
  const blockLeft = (bw - totalW) / 2;
  const topOff = (bh - colH) / 2;
  const rtl = opts.verticalDirection === VerticalDirection.RTL;
  const runs: Array<LayoutRun> = [];
  for (let j = 0; j < nCols; j++) {
    const col = cols[j];
    const xCenter = rtl
      ? blockLeft + totalW - fs / 2 - j * colStep
      : blockLeft + fs / 2 + j * colStep;
    for (let i = 0; i < col.length; i++) {
      const run: LayoutRun = {
        char: col[i],
        x: box.x + padding + xCenter,
        y: box.y + padding + topOff + fs / 2 + i * charStep,
        fontSize: fs
      };
      runs.push(run);
    }
  }
  const t: TextLayout = { runs: runs, truncated: false, measuredFontSize: fs };
  return t;
}

// ---------------- 字号二分 / 截断 ----------------

function findMaxFont(chars: Array<string>, m: CharMeasurer, box: DisplayRect, opts: RenderOptions,
  padding: number): number {
  let lo = MIN_FONT_AUTO;
  let hi = MAX_FONT;
  let best = 0;
  while (lo <= hi) {
    const mid = Math.floor((lo + hi) / 2);
    const ok = opts.orientation === RenderOrientation.HORIZONTAL
      ? tryHorizontal(chars, m, box, padding, mid, opts) !== undefined
      : tryVertical(chars, box, opts, mid) !== undefined;
    if (ok) {
      best = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return best;
}

function tryLayout(chars: Array<string>, m: CharMeasurer, box: DisplayRect, opts: RenderOptions,
  padding: number, fs: number): TextLayout | undefined {
  if (opts.orientation === RenderOrientation.HORIZONTAL) {
    return tryHorizontal(chars, m, box, padding, fs, opts);
  }
  return tryVertical(chars, box, opts, fs);
}

/**
 * 固定字号溢出时截断：从长到短找最大前缀 + 省略号仍能装下者。
 * 省略号位于最后一行/最后一列末尾，绝不拆开。
 */
function truncatePrefixes(chars: Array<string>, m: CharMeasurer, box: DisplayRect,
  opts: RenderOptions, padding: number, fs: number): TextLayout | undefined {
  for (let p = chars.length - 1; p >= 0; p--) {
    const sub: Array<string> = [];
    for (let i = 0; i < p; i++) {
      sub.push(chars[i]);
    }
    sub.push(ELLIPSIS);
    const t = tryLayout(sub, m, box, opts, padding, fs);
    if (t !== undefined) {
      t.truncated = true;
      return t;
    }
  }
  return undefined;
}

/**
 * 固定字号溢出时截断：从长到短找最大前缀 + 省略号仍能装下者。
 * 省略号位于最后一行/最后一列末尾，绝不拆开。
 * 极小气泡里连「省略号」都放不下时，保底把字号折半再试（宁可略小，也要有可读的省略号）。
 */
function truncateLayout(chars: Array<string>, m: CharMeasurer, box: DisplayRect, opts: RenderOptions,
  padding: number, fs: number): TextLayout {
  const direct = truncatePrefixes(chars, m, box, opts, padding, fs);
  if (direct !== undefined) {
    return direct;
  }
  let shrink = Math.floor(fs / 2);
  if (shrink < MIN_FONT_AUTO) {
    shrink = MIN_FONT_AUTO;
  }
  const shrunk = truncatePrefixes(chars, m, box, opts, padding, shrink);
  if (shrunk !== undefined) {
    return shrunk;
  }
  return emptyLayout();
}

/**
 * 纯排版内核（plan D5，页面坐标系）：
 * - HORIZONTAL：字号二分取可容纳的最大字号，行内居中、块内垂直居中；
 * - VERTICAL：按列容量分列，RTL/LTR，列内逐字、列距拉伸、字号二分；
 * - AUTO 模式绝不截断（宁可字小不丢字）；FIXED 模式装不下时省略号截断。
 * runs 的 x/y 是绝对页面坐标（box 原点 + padding + 字格中心），
 * 渲染端只需把 canvas 平移到 (dx,dy) 再 scale(scale)，即可 1:1 还原。
 */
export class LayoutEngine {
  static layout(text: string, box: DisplayRect, opts: RenderOptions,
    measurer?: CharMeasurer): TextLayout {
    const m: CharMeasurer = measurer !== undefined ? measurer : new ApproxCharMeasurer();
    if (text.length === 0 || box.w <= 0 || box.h <= 0) {
      return emptyLayout();
    }
    const padding = resolvePadding(box, opts.padding);
    if (box.w - padding * 2 <= 0 || box.h - padding * 2 <= 0) {
      return emptyLayout();
    }
    const chars = splitChars(text);
    if (chars.length === 0) {
      return emptyLayout();
    }
    if (opts.fontSizeMode === FontSizeMode.FIXED) {
      let fs = opts.fixedFontSize;
      if (fs < MIN_FONT_FIXED) {
        fs = MIN_FONT_FIXED;
      }
      if (fs > MAX_FONT) {
        fs = MAX_FONT;
      }
      const fitted = tryLayout(chars, m, box, opts, padding, fs);
      if (fitted !== undefined) {
        return fitted;
      }
      // 用户拉大间距导致装不下时，先放弃额外间距再排一次（不丢字优先）。
      const plain = optionsWithSpacing(opts, 0, 0);
      const relaxed = tryLayout(chars, m, box, plain, padding, fs);
      if (relaxed !== undefined) {
        return relaxed;
      }
      return truncateLayout(chars, m, box, plain, padding, fs);
    }
    const fs = findMaxFont(chars, m, box, opts, padding);
    if (fs > 0) {
      const auto = tryLayout(chars, m, box, opts, padding, fs);
      if (auto !== undefined) {
        return auto;
      }
    }
    // 保底：最小字号（确保全部字符都在，不截断）。
    const fallback = tryLayout(chars, m, box, opts, padding, MIN_FONT_AUTO);
    if (fallback !== undefined) {
      return fallback;
    }
    const plain = optionsWithSpacing(opts, 0, 0);
    const fallback2 = tryLayout(chars, m, box, plain, padding, MIN_FONT_AUTO);
    if (fallback2 !== undefined) {
      return fallback2;
    }
    // 病态小矩形兜底：宁可省略号截断，也不要整页空白。
    const safe = truncateLayout(chars, m, box, plain, padding, MIN_FONT_AUTO);
    if (safe.runs.length > 0) {
      return safe;
    }
    return emptyLayout();
  }
}

/** 找到某字符第一个 run（自检用）。 */
function findRun(layout: TextLayout, ch: string): LayoutRun | undefined {
  for (let i = 0; i < layout.runs.length; i++) {
    if (layout.runs[i].char === ch) {
      return layout.runs[i];
    }
  }
  return undefined;
}

/**
 * 竖排/横排排版自检（可在阅读器“设置 → 排版自检”里看结果）。
 * 覆盖：RTL 列序、LTR 列序、AUTO 不截断、铺满率、横排不溢出、
 * 固定字号溢出省略号、单字居中、RTL/LTR 镜像一致。
 */
export class LayoutSelfTest {
  static run(): Array<SelfTestResult> {
    const results: Array<SelfTestResult> = [];
    const m = new ApproxCharMeasurer();

    // 1) 竖排 RTL：第一列在最右，列内自上而下。
    {
      const opts: RenderOptions = {
        orientation: RenderOrientation.VERTICAL,
        verticalDirection: VerticalDirection.RTL,
        fontSizeMode: FontSizeMode.FIXED,
        fixedFontSize: 20,
        padding: 4
      };
      const box: DisplayRect = { x: 0, y: 0, w: 80, h: 80 };
      const layout = LayoutEngine.layout('一二三四五六七八', box, opts, m);
      const r1 = findRun(layout, '一');
      const r2 = findRun(layout, '二');
      const r5 = findRun(layout, '五');
      let ok = r1 !== undefined && r2 !== undefined && r5 !== undefined;
      let detail = 'runs=' + layout.runs.length;
      if (r1 !== undefined && r2 !== undefined && r5 !== undefined) {
        ok = ok && r1.x > r5.x && r2.y > r1.y && r2.x === r1.x;
        detail = '一.x=' + r1.x.toFixed(1) + ' 五.x=' + r5.x.toFixed(1) + ' 二.y=' + r2.y.toFixed(1);
      }
      results.push(makeSelfTestResult('竖排RTL列序(右到左)', ok, detail));
    }

    // 2) 竖排 LTR：第一列在最左。
    {
      const opts: RenderOptions = {
        orientation: RenderOrientation.VERTICAL,
        verticalDirection: VerticalDirection.LTR,
        fontSizeMode: FontSizeMode.FIXED,
        fixedFontSize: 20,
        padding: 4
      };
      const box: DisplayRect = { x: 0, y: 0, w: 80, h: 80 };
      const layout = LayoutEngine.layout('一二三四五六七八', box, opts, m);
      const r1 = findRun(layout, '一');
      const r5 = findRun(layout, '五');
      const ok = r1 !== undefined && r5 !== undefined && r1.x < r5.x;
      const detail = r1 !== undefined && r5 !== undefined
        ? '一.x=' + r1.x.toFixed(1) + ' 五.x=' + r5.x.toFixed(1)
        : 'runs=' + layout.runs.length;
      results.push(makeSelfTestResult('竖排LTR列序(左到右)', ok, detail));
    }

    // 3) AUTO 绝不截断：压测页缩小后的小气泡（52.6x37.9）装 11 字全显示。
    {
      const opts: RenderOptions = {
        orientation: RenderOrientation.VERTICAL,
        verticalDirection: VerticalDirection.RTL,
        fontSizeMode: FontSizeMode.AUTO,
        fixedFontSize: 16,
        padding: 4
      };
      const box: DisplayRect = { x: 0, y: 0, w: 52.6, h: 37.9 };
      const layout = LayoutEngine.layout('希望今天也是美好的一天', box, opts, m);
      const ok = layout.runs.length === 11 && !layout.truncated;
      const detail = 'runs=' + layout.runs.length + ' fs=' + layout.measuredFontSize + ' truncated=' + layout.truncated;
      results.push(makeSelfTestResult('AUTO小气泡不截断(11字全显示)', ok, detail));
    }

    // 4) 铺满率：同一气泡里列块宽/高应接近可用区。
    {
      const opts: RenderOptions = {
        orientation: RenderOrientation.VERTICAL,
        verticalDirection: VerticalDirection.RTL,
        fontSizeMode: FontSizeMode.AUTO,
        fixedFontSize: 16,
        padding: 4
      };
      const box: DisplayRect = { x: 10, y: 10, w: 52.6, h: 37.9 };
      const layout = LayoutEngine.layout('希望今天也是美好的一天', box, opts, m);
      let minX = 1e9;
      let maxX = -1e9;
      let minY = 1e9;
      let maxY = -1e9;
      for (let i = 0; i < layout.runs.length; i++) {
        const r = layout.runs[i];
        const half = r.fontSize / 2;
        if (r.x - half < minX) {
          minX = r.x - half;
        }
        if (r.x + half > maxX) {
          maxX = r.x + half;
        }
        if (r.y - half < minY) {
          minY = r.y - half;
        }
        if (r.y + half > maxY) {
          maxY = r.y + half;
        }
      }
      const bw = 52.6 - 8;
      const bh = 37.9 - 8;
      const wRatio = (maxX - minX) / bw;
      const hRatio = (maxY - minY) / bh;
      const ok = layout.runs.length > 0 && wRatio >= 0.85 && hRatio >= 0.8;
      const detail = 'wFill=' + wRatio.toFixed(2) + ' hFill=' + hRatio.toFixed(2);
      results.push(makeSelfTestResult('竖排列块铺满率(宽85%/高80%)', ok, detail));
    }

    // 5) 横排 AUTO 不溢出（全部字都在可用区内）。
    {
      const opts: RenderOptions = {
        orientation: RenderOrientation.HORIZONTAL,
        verticalDirection: VerticalDirection.RTL,
        fontSizeMode: FontSizeMode.AUTO,
        fixedFontSize: 16,
        padding: 4
      };
      const box: DisplayRect = { x: 20, y: 30, w: 200, h: 100 };
      const layout = LayoutEngine.layout('这是一段用于验证横排自动字号与换行不会溢出的较长译文内容', box, opts, m);
      let maxRight = 0;
      let maxBottom = 0;
      for (let i = 0; i < layout.runs.length; i++) {
        const r = layout.runs[i];
        const right = r.x + r.fontSize / 2;
        const bottom = r.y + r.fontSize / 2;
        if (right > maxRight) {
          maxRight = right;
        }
        if (bottom > maxBottom) {
          maxBottom = bottom;
        }
      }
      const ok = layout.runs.length > 0 && !layout.truncated
        && maxRight <= box.x + box.w + 0.5 && maxBottom <= box.y + box.h + 0.5;
      const detail = 'runs=' + layout.runs.length + ' fs=' + layout.measuredFontSize
        + ' right=' + maxRight.toFixed(1) + ' bottom=' + maxBottom.toFixed(1);
      results.push(makeSelfTestResult('横排AUTO居中不溢出', ok, detail));
    }

    // 6) 固定字号溢出 → 省略号结尾。
    {
      const opts: RenderOptions = {
        orientation: RenderOrientation.HORIZONTAL,
        verticalDirection: VerticalDirection.RTL,
        fontSizeMode: FontSizeMode.FIXED,
        fixedFontSize: 24,
        padding: 4
      };
      const box: DisplayRect = { x: 0, y: 0, w: 40, h: 28 };
      const layout = LayoutEngine.layout('这是一段很长很长的译文需要被截断处理不能拆行', box, opts, m);
      let last = '';
      if (layout.runs.length > 0) {
        last = layout.runs[layout.runs.length - 1].char;
      }
      const ok = layout.truncated && last === ELLIPSIS;
      results.push(makeSelfTestResult('固定字号溢出省略号截断', ok,
        'truncated=' + layout.truncated + ' last=' + last));
    }

    // 7) 单字竖排：水平+垂直都居中。
    {
      const opts: RenderOptions = {
        orientation: RenderOrientation.VERTICAL,
        verticalDirection: VerticalDirection.RTL,
        fontSizeMode: FontSizeMode.AUTO,
        fixedFontSize: 16,
        padding: 4
      };
      const box: DisplayRect = { x: 0, y: 0, w: 120, h: 120 };
      const layout = LayoutEngine.layout('好', box, opts, m);
      let ok = layout.runs.length === 1;
      let detail = 'runs=' + layout.runs.length;
      if (layout.runs.length === 1) {
        const r = layout.runs[0];
        ok = Math.abs(r.x - box.w / 2) <= 1.5 && Math.abs(r.y - box.h / 2) <= 1.5;
        detail = 'x=' + r.x.toFixed(1) + ' y=' + r.y.toFixed(1) + ' fs=' + r.fontSize;
      }
      results.push(makeSelfTestResult('单字居中', ok, detail));
    }

    // 8) 竖排方向切换后列序镜像成立。
    {
      const rtlOpts: RenderOptions = {
        orientation: RenderOrientation.VERTICAL,
        verticalDirection: VerticalDirection.RTL,
        fontSizeMode: FontSizeMode.FIXED,
        fixedFontSize: 18,
        padding: 4
      };
      const ltrOpts: RenderOptions = {
        orientation: RenderOrientation.VERTICAL,
        verticalDirection: VerticalDirection.LTR,
        fontSizeMode: FontSizeMode.FIXED,
        fixedFontSize: 18,
        padding: 4
      };
      const box: DisplayRect = { x: 0, y: 0, w: 100, h: 100 };
      const text = '甲乙丙丁戊己庚辛壬癸';
      const rtl = LayoutEngine.layout(text, box, rtlOpts, m);
      const ltr = LayoutEngine.layout(text, box, ltrOpts, m);
      let ok = rtl.runs.length === ltr.runs.length && rtl.runs.length > 0;
      let detail = 'rtlRuns=' + rtl.runs.length + ' ltrRuns=' + ltr.runs.length;
      if (ok) {
        for (let i = 0; i < rtl.runs.length; i++) {
          if (Math.abs(rtl.runs[i].x - (box.w - ltr.runs[i].x)) > 0.5
            || rtl.runs[i].char !== ltr.runs[i].char) {
            ok = false;
            detail += ' mismatch@' + i;
            break;
          }
        }
      }
      results.push(makeSelfTestResult('竖排RTL/LTR镜像一致', ok, detail));
    }

    // 9) 横排 3 字短句（430x320 气泡）：AUTO 取大字、字距=自然字宽（不额外拉开）、整块居中。
    {
      const opts: RenderOptions = {
        orientation: RenderOrientation.HORIZONTAL,
        verticalDirection: VerticalDirection.RTL,
        fontSizeMode: FontSizeMode.AUTO,
        fixedFontSize: 16,
        padding: 4
      };
      const box: DisplayRect = { x: 90, y: 200, w: 430, h: 320 };
      const layout = LayoutEngine.layout('等一下', box, opts, m);
      let ok = layout.runs.length === 3 && layout.measuredFontSize >= 60;
      let detail = 'fs=' + layout.measuredFontSize;
      if (layout.runs.length === 3) {
        const gap1 = layout.runs[1].x - layout.runs[0].x;
        const gap2 = layout.runs[2].x - layout.runs[1].x;
        const mid = (layout.runs[0].x + layout.runs[2].x) / 2;
        ok = ok && Math.abs(gap1 - layout.measuredFontSize) <= 0.5
          && Math.abs(gap2 - layout.measuredFontSize) <= 0.5
          && Math.abs(mid - (box.x + box.w / 2)) <= 1.5;
        detail += ' gap=' + gap1.toFixed(1) + ' mid=' + mid.toFixed(1);
      }
      results.push(makeSelfTestResult('横排3字短句字号最大化/无额外字距/居中', ok, detail));
    }

    // 10) 竖排 3 字短句：同列、字步进为自然值（不被拉伸）、整块垂直居中。
    {
      const opts: RenderOptions = {
        orientation: RenderOrientation.VERTICAL,
        verticalDirection: VerticalDirection.RTL,
        fontSizeMode: FontSizeMode.AUTO,
        fixedFontSize: 16,
        padding: 4
      };
      const box: DisplayRect = { x: 90, y: 200, w: 430, h: 320 };
      const layout = LayoutEngine.layout('等一下', box, opts, m);
      let ok = layout.runs.length === 3 && layout.measuredFontSize >= 60;
      let detail = 'fs=' + layout.measuredFontSize;
      if (layout.runs.length === 3) {
        const fs = layout.measuredFontSize;
        const step = layout.runs[1].y - layout.runs[0].y;
        const step2 = layout.runs[2].y - layout.runs[1].y;
        const mid = (layout.runs[0].y + layout.runs[2].y) / 2;
        ok = ok && layout.runs[0].x === layout.runs[1].x
          && Math.abs(step - fs * 1.08) <= 0.5 && Math.abs(step2 - fs * 1.08) <= 0.5
          && Math.abs(mid - (box.y + box.h / 2)) <= 1.5;
        detail += ' step=' + step.toFixed(1) + ' mid=' + mid.toFixed(1);
      }
      results.push(makeSelfTestResult('竖排3字短句同列/自然字步进/居中', ok, detail));
    }

    // 11) 竖排 11 字长句（580x240）：不截断，列距 gap ≤ 2.5×字号。
    {
      const opts: RenderOptions = {
        orientation: RenderOrientation.VERTICAL,
        verticalDirection: VerticalDirection.RTL,
        fontSizeMode: FontSizeMode.AUTO,
        fixedFontSize: 16,
        padding: 4
      };
      const box: DisplayRect = { x: 80, y: 200, w: 580, h: 240 };
      const text = '早上好今天天气也不错呢';
      const layout = LayoutEngine.layout(text, box, opts, m);
      const fs = layout.measuredFontSize;
      let maxGap = 0;
      for (let i = 1; i < layout.runs.length; i++) {
        const prev = layout.runs[i - 1];
        const cur = layout.runs[i];
        if (prev.x !== cur.x) {
          const g = Math.abs(prev.x - cur.x) - fs;
          if (g > maxGap) {
            maxGap = g;
          }
        }
      }
      const ok = layout.runs.length === text.length && !layout.truncated && maxGap <= fs * 2.5 + 0.5;
      const detail = 'runs=' + layout.runs.length + ' fs=' + fs + ' maxGap=' + maxGap.toFixed(1);
      results.push(makeSelfTestResult('竖排11字长句不截断且列距<=2.5字号', ok, detail));
    }

    return results;
  }

  static passed(results: Array<SelfTestResult>): boolean {
    for (let i = 0; i < results.length; i++) {
      if (!results[i].passed) {
        return false;
      }
    }
    return results.length > 0;
  }

  static summary(results: Array<SelfTestResult>): string {
    let passed = 0;
    for (let i = 0; i < results.length; i++) {
      if (results[i].passed) {
        passed++;
      }
    }
    return passed + '/' + results.length + ' PASS';
  }
}
