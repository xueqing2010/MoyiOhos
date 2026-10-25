import { Manga, SourceType, TranslateStatus } from 'coremodel';
import { naturalCompare, WindowSizeClass } from 'commons';

/**
 * 书架展示模型（stage-2 / S101）：
 * Manga 的展示层投影，供封面卡片/列表直接渲染，避免在 build 里做枚举分支。
 * 除 MVP-1 字段外，新增导入时间、最近阅读进度、封面占位序号等书架排序/徽标所需信息。
 */
export class MangaDisplay {
  id: number = 0;
  name: string = '';
  pageCount: number = 0;
  coverPath: string = '';
  /** 翻译状态文案（未翻译 / 翻译中 / 已翻译 / 部分失败）。 */
  statusLabel: string = '';
  statusDone: boolean = false;
  statusRunning: boolean = false;
  /** 来源文案（压缩包 / 目录 / 相册）。 */
  sourceLabel: string = '';
  isDirectory: boolean = false;
  /** 导入时间（排序用）。 */
  createdAt: number = 0;
  /** 最近活动时间（最近阅读排序用）。 */
  updatedAt: number = 0;
  /** 上次阅读页（0 基），书架展示「读至 x/y」。 */
  lastReadPage: number = 0;
  /** 封面占位序号 1..4（按 manga.id % 4 取模）。 */
  coverIndex: number = 1;
  /** 阅读进度文案，未开始阅读时为空。 */
  progressLabel: string = '';
  /** 原生日志：目录源授权是否健康（默认未知 true，探测失败后置 false）。 */
  authHealthy: boolean = true;
}

/** 书架排序方式（对齐上游 mangaimport shelf 排序菜单）。 */
export enum ShelfSortMode {
  RECENT = 0,
  NAME = 1,
  IMPORT_TIME = 2
}

/** 书架分段：漫画 / 小说。 */
export enum ShelfSegment {
  MANGA = 0,
  NOVEL = 1
}

/** 导入通道：压缩包 / 目录 / 相册。 */
export enum ImportChannel {
  ARCHIVE = 0,
  DIRECTORY = 1,
  ALBUM = 2
}

export function shelfSortModeLabel(mode: ShelfSortMode): string {
  if (mode === ShelfSortMode.NAME) {
    return '名称';
  }
  if (mode === ShelfSortMode.IMPORT_TIME) {
    return '导入时间';
  }
  return '最近阅读';
}

/** 由持久化值还原排序方式（兼容旧版本/异常值）。 */
export function parseShelfSortMode(raw: string): ShelfSortMode {
  if (raw === 'name') {
    return ShelfSortMode.NAME;
  }
  if (raw === 'import_time') {
    return ShelfSortMode.IMPORT_TIME;
  }
  return ShelfSortMode.RECENT;
}

export function encodeShelfSortMode(mode: ShelfSortMode): string {
  if (mode === ShelfSortMode.NAME) {
    return 'name';
  }
  if (mode === ShelfSortMode.IMPORT_TIME) {
    return 'import_time';
  }
  return 'recent';
}

/** Manga → 展示模型（含封面占位序号与阅读进度文案）。 */
export function makeMangaDisplay(m: Manga): MangaDisplay {
  const d = new MangaDisplay();
  d.id = m.id;
  d.name = m.name;
  d.pageCount = m.pageCount;
  d.coverPath = m.coverPath === undefined ? '' : m.coverPath;
  d.statusDone = m.translateStatus === TranslateStatus.DONE;
  d.statusRunning = m.translateStatus === TranslateStatus.RUNNING;
  if (m.translateStatus === TranslateStatus.NONE) {
    d.statusLabel = '未翻译';
  } else if (m.translateStatus === TranslateStatus.RUNNING) {
    d.statusLabel = '翻译中';
  } else if (m.translateStatus === TranslateStatus.DONE) {
    d.statusLabel = '已翻译';
  } else {
    d.statusLabel = '部分失败';
  }
  if (m.sourceType === SourceType.ARCHIVE) {
    d.sourceLabel = '压缩包';
  } else if (m.sourceType === SourceType.DIRECTORY) {
    d.sourceLabel = '目录';
  } else {
    d.sourceLabel = '相册';
  }
  d.isDirectory = m.sourceType === SourceType.DIRECTORY;
  d.createdAt = m.createdAt;
  d.updatedAt = m.updatedAt;
  d.lastReadPage = m.lastReadPage;
  d.coverIndex = (m.id % 4) + 1;
  if (m.lastReadPage > 0 && m.pageCount > 0) {
    const pageNo = m.lastReadPage + 1 > m.pageCount ? m.pageCount : m.lastReadPage + 1;
    d.progressLabel = `读至 ${pageNo}/${m.pageCount}`;
  }
  return d;
}

/** 排序副本（不改动原数组，保证 UI 状态可回退）。 */
export function sortMangaDisplays(list: Array<MangaDisplay>, mode: ShelfSortMode): Array<MangaDisplay> {
  const out: Array<MangaDisplay> = list.slice();
  if (mode === ShelfSortMode.NAME) {
    out.sort((a: MangaDisplay, b: MangaDisplay): number => naturalCompare(a.name, b.name));
  } else if (mode === ShelfSortMode.IMPORT_TIME) {
    out.sort((a: MangaDisplay, b: MangaDisplay): number => b.createdAt - a.createdAt);
  } else {
    out.sort((a: MangaDisplay, b: MangaDisplay): number => b.updatedAt - a.updatedAt);
  }
  return out;
}

/** 网格列数：SM 2 列 / MD 3 列 / LG 5 列（一次开发，多端部署）。 */
export function shelfGridColumns(sizeClass: WindowSizeClass): number {
  if (sizeClass === WindowSizeClass.LG) {
    return 5;
  }
  if (sizeClass === WindowSizeClass.MD) {
    return 3;
  }
  return 2;
}

/** 按实际 vp 宽度计算网格列数：<600→2，600-839→3，840-999→4，>=1000→5。 */
export function shelfColumnsForWidth(vp: number): number {
  if (vp >= 1000) {
    return 5;
  }
  if (vp >= 840) {
    return 4;
  }
  if (vp >= 600) {
    return 3;
  }
  return 2;
}

/** 列表模式列数：窄屏单列，宽屏双列（plan §5）。 */
export function shelfListColumns(sizeClass: WindowSizeClass): number {
  return sizeClass === WindowSizeClass.SM ? 1 : 2;
}

/** 由列数生成 Grid columnsTemplate。 */
export function gridColumnsTemplate(columns: number): string {
  const safe = columns < 1 ? 1 : columns;
  let template = '1fr';
  for (let i = 1; i < safe; i++) {
    template += ' 1fr';
  }
  return template;
}

/** 导入向导中待确认页的展示行（页序预览/封面选择）。 */
export class WizardPageRow {
  /** 页在暂存列表中的稳定键（路径唯一）。 */
  key: string = '';
  /** 当前页序（0 基，随排序更新）。 */
  order: number = 0;
  path: string = '';
  /** 原始文件名，用于页序预览。 */
  label: string = '';
}

export function makeWizardRow(path: string, order: number): WizardPageRow {
  const r = new WizardPageRow();
  r.key = path;
  r.order = order;
  r.path = path;
  r.label = lastPathSegment(path);
  return r;
}

/** 生成向导页序行（按给定路径顺序）。 */
export function makeWizardRows(paths: Array<string>): Array<WizardPageRow> {
  const rows: Array<WizardPageRow> = [];
  for (let i = 0; i < paths.length; i++) {
    rows.push(makeWizardRow(paths[i], i));
  }
  return rows;
}

/** 路径末段（兼容沙箱路径与 file:// URI）。 */
export function lastPathSegment(path: string): string {
  const clean = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  const idx = clean.lastIndexOf('/');
  const seg = idx < 0 ? clean : clean.substring(idx + 1);
  try {
    return decodeURIComponent(seg);
  } catch (e) {
    return seg;
  }
}
