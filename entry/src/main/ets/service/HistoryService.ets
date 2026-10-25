import { EngineType } from 'coretranslate';
import {
  MangaPage,
  PageTranslation,
  TextTranslationRecord,
  TranslateStatus
} from 'coremodel';
import { AppEnv } from '../common/AppEnv';
import { HistoryRepository, MangaHistoryRow, NovelHistoryRow } from '../data/HistoryRepository';

/** 历史记录类型（与 Routes.HistoryDetailParams.kind 对齐）。 */
export enum HistoryKind {
  MANGA_PAGE = 0,
  NOVEL_CHAPTER = 1,
  TEXT = 2
}

/** 历史列表中的一条记录。 */
export class HistoryItem {
  /** 列表内唯一键，如 m0:12 / n1:34 / t2:56。 */
  key: string = '';
  kind: number = HistoryKind.MANGA_PAGE;
  /** 漫画页 id / 小说章节 id / 文本记录 id。 */
  refId: number = 0;
  /** 进程组键：manga:<id> / novel:<id> / text:<yyyy-mm-dd>。 */
  groupKey: string = '';
  title: string = '';
  subtitle: string = '';
  /** 列表摘要（详情/全屏可用的短文本）。 */
  preview: string = '';
  coverPath: string = '';
  /** 漫画页原图（全屏翻页用）。 */
  imagePath: string = '';
  time: number = 0;
  status: number = TranslateStatus.DONE;
  engineType: number = 0;
  pageCount: number = 0;
  /** 漫画页码（0 基），全屏浏览角标用。 */
  pageIndex: number = 0;
  translatedCount: number = 0;
  translatedLines: number = 0;
  totalLines: number = 0;
  /** 小说章节序号与标题（导出 txt 时定位章节用）。 */
  chapterIndex: number = 0;
  chapterTitle: string = '';
  /** 全屏阅读用全文（小说章节原文/译文、文本翻译原文/译文）。 */
  contentOriginal: string = '';
  contentTranslated: string = '';
}

/** 一个分组（时间视图 = 同一天；进程视图 = 同一 manga/novel/文本日会话）。 */
export class HistoryGroup {
  key: string = '';
  /** 组内记录类型；时间视图为 -1（混合）。 */
  kind: number = -1;
  title: string = '';
  subtitle: string = '';
  coverPath: string = '';
  latestTime: number = 0;
  pageCount: number = 0;
  translatedCount: number = 0;
  items: Array<HistoryItem> = [];
}

/** 一次加载的完整历史快照（双视图共用同一份 items）。 */
export class HistorySnapshot {
  items: Array<HistoryItem> = [];
  timeGroups: Array<HistoryGroup> = [];
  processGroups: Array<HistoryGroup> = [];
  mangaCount: number = 0;
  novelCount: number = 0;
  textCount: number = 0;

  isEmpty(): boolean {
    return this.items.length === 0;
  }
}

/** 详情页数据（三类记录统一承载，按 kind 取用对应字段）。 */
export class HistoryDetailData {
  kind: number = HistoryKind.MANGA_PAGE;
  found: boolean = false;
  groupKey: string = '';
  title: string = '';
  subtitle: string = '';
  coverPath: string = '';
  time: number = 0;
  status: number = TranslateStatus.DONE;
  engineType: number = 0;
  // 漫画
  mangaId: number = 0;
  pageId: number = 0;
  pageIndex: number = 0;
  pageCount: number = 0;
  imagePath: string = '';
  translation: PageTranslation | undefined = undefined;
  // 小说
  novelId: number = 0;
  chapterId: number = 0;
  chapterIndex: number = 0;
  chapterCount: number = 0;
  chapterTitle: string = '';
  // 原文 / 译文（小说、文本）
  sourceText: string = '';
  translatedText: string = '';
  fromLang: string = '';
  toLang: string = '';
}

const HOST_PREFIX_MANGA: string = 'manga:';
const HOST_PREFIX_NOVEL: string = 'novel:';
const HOST_PREFIX_TEXT: string = 'text:';
const DAY_MS: number = 86400000;

/**
 * 历史业务服务（task-6）：
 * 聚合三类译文记录为统一 HistoryItem，提供时间/进程双视图分组、详情读取、
 * 单条/批量删除与清空；不修改任何书籍与页面原始数据。
 */
export class HistoryService {
  // -------------------------------------------------------------------------
  // 加载与分组
  // -------------------------------------------------------------------------

  /** 加载全部历史并生成双视图分组。 */
  static async load(): Promise<HistorySnapshot> {
    await AppEnv.ready();
    const snapshot = new HistorySnapshot();
    const mangaRows: Array<MangaHistoryRow> = await HistoryRepository.queryMangaRows();
    const novelRows: Array<NovelHistoryRow> = await HistoryRepository.queryNovelRows();
    const textRows: Array<TextTranslationRecord> = await HistoryRepository.queryTextRows();

    for (const row of mangaRows) {
      snapshot.items.push(HistoryService.buildMangaItem(row));
      snapshot.mangaCount++;
    }
    for (const row of novelRows) {
      snapshot.items.push(HistoryService.buildNovelItem(row));
      snapshot.novelCount++;
    }
    for (const rec of textRows) {
      snapshot.items.push(HistoryService.buildTextItem(rec));
      snapshot.textCount++;
    }
    snapshot.items.sort((a: HistoryItem, b: HistoryItem) => b.time - a.time);
    snapshot.timeGroups = HistoryService.groupByTime(snapshot.items);
    snapshot.processGroups = HistoryService.groupByProcess(snapshot.items);
    return snapshot;
  }

  /** 按组键加载一组记录（全屏翻页 / 组导出用）。 */
  static async loadGroup(groupKey: string): Promise<HistoryGroup | undefined> {
    await AppEnv.ready();
    if (groupKey.startsWith(HOST_PREFIX_MANGA)) {
      const mangaId = HistoryService.toNumber(groupKey.substring(HOST_PREFIX_MANGA.length));
      if (mangaId < 0) {
        return undefined;
      }
      const rows = await HistoryRepository.queryMangaRowsByManga(mangaId);
      const items: Array<HistoryItem> = [];
      for (const row of rows) {
        items.push(HistoryService.buildMangaItem(row));
      }
      return HistoryService.buildGroupFromItems(groupKey, items, rows.length > 0 ? rows[0] : undefined);
    }
    if (groupKey.startsWith(HOST_PREFIX_NOVEL)) {
      const novelId = HistoryService.toNumber(groupKey.substring(HOST_PREFIX_NOVEL.length));
      if (novelId < 0) {
        return undefined;
      }
      const rows = await HistoryRepository.queryNovelRowsByNovel(novelId);
      const items: Array<HistoryItem> = [];
      for (const row of rows) {
        const item = HistoryService.buildNovelItem(row);
        item.contentOriginal = row.content;
        item.contentTranslated = row.translatedContent;
        items.push(item);
      }
      return HistoryService.buildGroupFromItems(groupKey, items, undefined);
    }
    if (groupKey.startsWith(HOST_PREFIX_TEXT)) {
      const range = HistoryService.dayRange(groupKey.substring(HOST_PREFIX_TEXT.length));
      if (range === undefined) {
        return undefined;
      }
      const rows = await HistoryRepository.queryTextRowsByRange(range[0], range[1]);
      const items: Array<HistoryItem> = [];
      for (const rec of rows) {
        const item = HistoryService.buildTextItem(rec);
        item.contentOriginal = rec.sourceText;
        item.contentTranslated = rec.translatedText;
        items.push(item);
      }
      return HistoryService.buildGroupFromItems(groupKey, items, undefined);
    }
    return undefined;
  }

  /** 读取单条记录详情。 */
  static async loadDetail(kind: number, refId: number): Promise<HistoryDetailData> {
    await AppEnv.ready();
    const data = new HistoryDetailData();
    data.kind = kind;
    data.found = false;
    if (kind === HistoryKind.MANGA_PAGE) {
      const row = await HistoryRepository.queryMangaRowByPage(refId);
      if (row === undefined) {
        return data;
      }
      const page: MangaPage | undefined = await HistoryRepository.queryPageById(refId);
      const translation: PageTranslation | undefined = await HistoryRepository.queryPageTranslation(refId);
      data.found = true;
      data.groupKey = HistoryService.mangaGroupKey(row.mangaId);
      data.title = row.mangaName.length > 0 ? row.mangaName : '未命名漫画';
      data.subtitle = '漫画 · 第 ' + (row.pageIndex + 1) + ' 页';
      data.coverPath = row.coverPath;
      data.time = row.updatedAt;
      data.status = row.status;
      data.engineType = row.engineType;
      data.mangaId = row.mangaId;
      data.pageId = row.pageId;
      data.pageIndex = row.pageIndex;
      data.pageCount = row.pageCount;
      data.imagePath = page !== undefined ? page.imagePath : row.imagePath;
      data.translation = translation;
      return data;
    }
    if (kind === HistoryKind.NOVEL_CHAPTER) {
      const row = await HistoryRepository.queryNovelRowByChapter(refId);
      if (row === undefined) {
        return data;
      }
      data.found = true;
      data.groupKey = HistoryService.novelGroupKey(row.novelId);
      data.title = row.novelName.length > 0 ? row.novelName : '未命名小说';
      data.subtitle = '小说 · 第 ' + (row.chapterIndex + 1) + ' 章' +
        (row.chapterTitle.length > 0 ? ' · ' + row.chapterTitle : '');
      data.coverPath = row.coverPath;
      data.time = row.updatedAt;
      data.status = row.status;
      data.engineType = 0;
      data.novelId = row.novelId;
      data.chapterId = row.chapterId;
      data.chapterIndex = row.chapterIndex;
      data.chapterCount = row.chapterCount;
      data.chapterTitle = row.chapterTitle;
      data.sourceText = row.content;
      data.translatedText = row.translatedContent;
      return data;
    }
    if (kind === HistoryKind.TEXT) {
      const rec = await HistoryRepository.queryTextRowById(refId);
      if (rec === undefined) {
        return data;
      }
      data.found = true;
      data.groupKey = HistoryService.textGroupKey(rec.createdAt);
      data.title = '文本翻译';
      data.subtitle = '文本 · ' + (rec.fromLang.length > 0 ? rec.fromLang : 'auto') +
        ' → ' + (rec.toLang.length > 0 ? rec.toLang : 'zh');
      data.time = rec.createdAt;
      data.status = TranslateStatus.DONE;
      data.engineType = rec.engineType;
      data.sourceText = rec.sourceText;
      data.translatedText = rec.translatedText;
      data.fromLang = rec.fromLang;
      data.toLang = rec.toLang;
      return data;
    }
    return data;
  }

  // -------------------------------------------------------------------------
  // 删除 / 清空
  // -------------------------------------------------------------------------

  /** 批量删除记录（只删译文，保留书籍/页面/章节原文）。返回删除条数。 */
  static async deleteItems(items: Array<HistoryItem>): Promise<number> {
    await AppEnv.ready();
    const pageIds: Array<number> = [];
    const chapterIds: Array<number> = [];
    const textIds: Array<number> = [];
    for (const item of items) {
      if (item.kind === HistoryKind.MANGA_PAGE) {
        pageIds.push(item.refId);
      } else if (item.kind === HistoryKind.NOVEL_CHAPTER) {
        chapterIds.push(item.refId);
      } else if (item.kind === HistoryKind.TEXT) {
        textIds.push(item.refId);
      }
    }
    await HistoryRepository.deleteMangaPageRecords(pageIds);
    await HistoryRepository.deleteNovelChapterRecords(chapterIds);
    await HistoryRepository.deleteTextRecords(textIds);
    return pageIds.length + chapterIds.length + textIds.length;
  }

  /** 清空三类历史（保留书籍/页面/章节原文）。 */
  static async clearAll(): Promise<void> {
    await AppEnv.ready();
    await HistoryRepository.clearAll();
  }

  /** 按时间清理：删除早于 days 天前的译文记录。 */
  static async clearBeforeDays(days: number): Promise<void> {
    await AppEnv.ready();
    const safeDays = days < 1 ? 1 : Math.floor(days);
    const cutoff = Date.now() - safeDays * DAY_MS;
    await HistoryRepository.clearBefore(cutoff);
  }

  // -------------------------------------------------------------------------
  // 组键与展示工具
  // -------------------------------------------------------------------------

  static mangaGroupKey(mangaId: number): string {
    return HOST_PREFIX_MANGA + mangaId;
  }

  static novelGroupKey(novelId: number): string {
    return HOST_PREFIX_NOVEL + novelId;
  }

  static textGroupKey(timestamp: number): string {
    return HOST_PREFIX_TEXT + HistoryService.dayKey(timestamp);
  }

  /** 类型名称（列表徽标/详情标题）。 */
  static kindName(kind: number): string {
    if (kind === HistoryKind.MANGA_PAGE) {
      return '漫画页';
    }
    if (kind === HistoryKind.NOVEL_CHAPTER) {
      return '小说章节';
    }
    return '文本翻译';
  }

  /** 译文状态文案。 */
  static statusText(status: number): string {
    if (status === TranslateStatus.DONE) {
      return '已完成';
    }
    if (status === TranslateStatus.PARTIAL_FAILED) {
      return '部分失败';
    }
    if (status === TranslateStatus.RUNNING) {
      return '翻译中';
    }
    return '未翻译';
  }

  /** 状态色（紫夜主题语义色）。 */
  static statusColor(status: number): string {
    if (status === TranslateStatus.DONE) {
      return '#5FD3A6';
    }
    if (status === TranslateStatus.PARTIAL_FAILED) {
      return '#F0B95C';
    }
    if (status === TranslateStatus.RUNNING) {
      return '#A78BFA';
    }
    return '#7D7398';
  }

  /** 引擎名称。 */
  static engineName(engineType: number): string {
    if (engineType === (EngineType.BING as number)) {
      return '必应翻译';
    }
    if (engineType === (EngineType.OPENAI_COMPAT as number)) {
      return 'OpenAI 兼容';
    }
    if (engineType === (EngineType.LOCAL_LLAMA as number)) {
      return '本地模型';
    }
    return '未知引擎';
  }

  /** 单行截断（列表摘要用）。 */
  static truncate(raw: string, max: number): string {
    const text = raw.replace(/\s+/g, ' ').trim();
    if (text.length <= max) {
      return text;
    }
    return text.substring(0, max) + '…';
  }

  /** 列表时间：刚刚 / N 分钟前 / 今天 HH:mm / 昨天 HH:mm / M月D日 HH:mm / 完整日期。 */
  static formatTime(timestamp: number): string {
    const now = Date.now();
    const diff = now - timestamp;
    if (diff < 0) {
      return HistoryService.formatDateTime(timestamp);
    }
    if (diff < 60000) {
      return '刚刚';
    }
    if (diff < 3600000) {
      return Math.floor(diff / 60000) + ' 分钟前';
    }
    const key = HistoryService.dayKey(timestamp);
    const clock = HistoryService.clock(timestamp);
    const currentYear = new Date(now).getFullYear();
    const parts = HistoryService.parseDayKey(key);
    if (key === HistoryService.dayKey(now)) {
      return '今天 ' + clock;
    }
    if (key === HistoryService.dayKey(now - DAY_MS)) {
      return '昨天 ' + clock;
    }
    if (parts.length === 3 && parts[0] === currentYear) {
      return parts[1] + '月' + parts[2] + '日 ' + clock;
    }
    return HistoryService.formatDateTime(timestamp);
  }

  /** 完整时间戳 yyyy-MM-dd HH:mm。 */
  static formatDateTime(timestamp: number): string {
    const d = new Date(timestamp);
    return d.getFullYear() + '-' + HistoryService.pad2(d.getMonth() + 1) + '-' +
      HistoryService.pad2(d.getDate()) + ' ' + HistoryService.pad2(d.getHours()) + ':' +
      HistoryService.pad2(d.getMinutes());
  }

  /** 日期键 yyyy-MM-dd（本地时区）。 */
  static dayKey(timestamp: number): string {
    const d = new Date(timestamp);
    return d.getFullYear() + '-' + HistoryService.pad2(d.getMonth() + 1) + '-' + HistoryService.pad2(d.getDate());
  }

  /** 日期标签：今天 / 昨天 / M月D日 / yyyy年M月D日。 */
  static dayLabel(dayKey: string): string {
    const now = Date.now();
    if (dayKey === HistoryService.dayKey(now)) {
      return '今天';
    }
    if (dayKey === HistoryService.dayKey(now - DAY_MS)) {
      return '昨天';
    }
    const parts = HistoryService.parseDayKey(dayKey);
    if (parts.length !== 3) {
      return dayKey;
    }
    if (parts[0] === new Date(now).getFullYear()) {
      return parts[1] + '月' + parts[2] + '日';
    }
    return parts[0] + '年' + parts[1] + '月' + parts[2] + '日';
  }

  // -------------------------------------------------------------------------
  // 内部实现
  // -------------------------------------------------------------------------

  private static buildMangaItem(row: MangaHistoryRow): HistoryItem {
    const item = new HistoryItem();
    item.key = 'm0:' + row.pageId;
    item.kind = HistoryKind.MANGA_PAGE;
    item.refId = row.pageId;
    item.groupKey = HistoryService.mangaGroupKey(row.mangaId);
    item.title = row.mangaName.length > 0 ? row.mangaName : '未命名漫画';
    item.subtitle = '第 ' + (row.pageIndex + 1) + ' 页 · ' + row.translatedLines + ' 行译文';
    item.preview = row.failReason;
    item.coverPath = row.coverPath.length > 0 ? row.coverPath : row.imagePath;
    item.imagePath = row.imagePath;
    item.time = row.updatedAt;
    item.status = row.status;
    item.engineType = row.engineType;
    item.pageCount = row.pageCount;
    item.pageIndex = row.pageIndex;
    item.translatedCount = row.translatedCount;
    item.translatedLines = row.translatedLines;
    item.totalLines = row.totalLines;
    return item;
  }

  private static buildNovelItem(row: NovelHistoryRow): HistoryItem {
    const item = new HistoryItem();
    item.key = 'n1:' + row.chapterId;
    item.kind = HistoryKind.NOVEL_CHAPTER;
    item.refId = row.chapterId;
    item.groupKey = HistoryService.novelGroupKey(row.novelId);
    item.title = row.novelName.length > 0 ? row.novelName : '未命名小说';
    const chapterLabel = row.chapterTitle.length > 0 ? HistoryService.truncate(row.chapterTitle, 16) : '';
    item.subtitle = '第 ' + (row.chapterIndex + 1) + ' 章' +
      (chapterLabel.length > 0 ? ' · ' + chapterLabel : '') + ' · ' + row.translatedChars + ' 字译文';
    item.preview = HistoryService.truncate(row.translatedContent, 60);
    item.coverPath = row.coverPath;
    item.time = row.updatedAt;
    item.status = row.status;
    item.engineType = 0;
    item.pageCount = row.chapterCount;
    item.translatedCount = row.translatedCount;
    item.chapterIndex = row.chapterIndex;
    item.chapterTitle = row.chapterTitle;
    return item;
  }

  private static buildTextItem(rec: TextTranslationRecord): HistoryItem {
    const item = new HistoryItem();
    item.key = 't2:' + rec.id;
    item.kind = HistoryKind.TEXT;
    item.refId = rec.id;
    item.groupKey = HistoryService.textGroupKey(rec.createdAt);
    const sourceLine = HistoryService.truncate(rec.sourceText, 24);
    item.title = sourceLine.length > 0 ? sourceLine : '文本翻译';
    item.subtitle = HistoryService.truncate(rec.translatedText, 30);
    item.preview = rec.sourceText;
    item.coverPath = '';
    item.time = rec.createdAt;
    item.status = TranslateStatus.DONE;
    item.engineType = rec.engineType;
    item.pageCount = 1;
    item.translatedCount = 1;
    return item;
  }

  private static groupByTime(items: Array<HistoryItem>): Array<HistoryGroup> {
    const groups: Array<HistoryGroup> = [];
    let current: HistoryGroup | undefined = undefined;
    for (const item of items) {
      const key = 'time:' + HistoryService.dayKey(item.time);
      if (current === undefined || current.key !== key) {
        current = new HistoryGroup();
        current.key = key;
        current.kind = -1;
        current.title = HistoryService.dayLabel(HistoryService.dayKey(item.time));
        current.latestTime = item.time;
        groups.push(current);
      }
      current.items.push(item);
      if (item.time > current.latestTime) {
        current.latestTime = item.time;
      }
    }
    for (const group of groups) {
      group.pageCount = group.items.length;
      group.translatedCount = group.items.length;
      group.subtitle = group.items.length + ' 条记录';
    }
    return groups;
  }

  private static groupByProcess(items: Array<HistoryItem>): Array<HistoryGroup> {
    const groups: Array<HistoryGroup> = [];
    for (const item of items) {
      let group: HistoryGroup | undefined = undefined;
      for (const candidate of groups) {
        if (candidate.key === item.groupKey) {
          group = candidate;
          break;
        }
      }
      if (group === undefined) {
        group = new HistoryGroup();
        group.key = item.groupKey;
        group.kind = item.kind;
        group.title = item.kind === HistoryKind.TEXT ? '文本翻译' : item.title;
        group.coverPath = item.coverPath;
        group.pageCount = item.pageCount;
        group.translatedCount = item.translatedCount;
        group.latestTime = item.time;
        groups.push(group);
      }
      group.items.push(item);
      if (item.time > group.latestTime) {
        group.latestTime = item.time;
      }
    }
    for (const group of groups) {
      if (group.kind === HistoryKind.TEXT) {
        group.pageCount = group.items.length;
        group.translatedCount = group.items.length;
        group.subtitle = HistoryService.dayLabel(HistoryService.dayKey(group.latestTime)) +
          ' · ' + group.items.length + ' 条';
      } else if (group.kind === HistoryKind.MANGA_PAGE) {
        group.subtitle = '漫画 · ' + group.translatedCount + '/' + group.pageCount + ' 页已译';
      } else {
        group.subtitle = '小说 · ' + group.translatedCount + '/' + group.pageCount + ' 章已译';
      }
    }
    groups.sort((a: HistoryGroup, b: HistoryGroup) => b.latestTime - a.latestTime);
    return groups;
  }

  private static buildGroupFromItems(groupKey: string, items: Array<HistoryItem>,
    firstRow: MangaHistoryRow | undefined): HistoryGroup {
    const group = new HistoryGroup();
    group.key = groupKey;
    group.items = items;
    if (items.length === 0) {
      return group;
    }
    const first = items[0];
    group.kind = first.kind;
    group.title = first.kind === HistoryKind.TEXT ? '文本翻译' : first.title;
    group.coverPath = first.coverPath;
    group.pageCount = first.pageCount;
    group.translatedCount = first.translatedCount;
    group.latestTime = first.time;
    for (const item of items) {
      if (item.time > group.latestTime) {
        group.latestTime = item.time;
      }
    }
    if (group.kind === HistoryKind.MANGA_PAGE) {
      if (firstRow !== undefined) {
        group.pageCount = firstRow.pageCount;
        group.translatedCount = firstRow.translatedCount;
      }
      group.subtitle = '漫画 · ' + group.translatedCount + '/' + group.pageCount + ' 页已译';
    } else if (group.kind === HistoryKind.NOVEL_CHAPTER) {
      group.subtitle = '小说 · ' + group.translatedCount + '/' + group.pageCount + ' 章已译';
    } else {
      group.pageCount = items.length;
      group.translatedCount = items.length;
      group.subtitle = HistoryService.dayLabel(HistoryService.dayKey(group.latestTime)) +
        ' · ' + items.length + ' 条';
    }
    return group;
  }

  private static dayRange(dayKey: string): Array<number> | undefined {
    const parts = HistoryService.parseDayKey(dayKey);
    if (parts.length !== 3) {
      return undefined;
    }
    const start = new Date(parts[0], parts[1] - 1, parts[2], 0, 0, 0, 0).getTime();
    const end = start + DAY_MS;
    return [start, end];
  }

  private static parseDayKey(dayKey: string): Array<number> {
    const pieces = dayKey.split('-');
    if (pieces.length !== 3) {
      return [];
    }
    const year = Number(pieces[0]);
    const month = Number(pieces[1]);
    const day = Number(pieces[2]);
    if (isNaN(year) || isNaN(month) || isNaN(day)) {
      return [];
    }
    return [year, month, day];
  }

  private static toNumber(raw: string): number {
    const value = Number(raw);
    if (isNaN(value)) {
      return -1;
    }
    return value;
  }

  private static clock(timestamp: number): string {
    const d = new Date(timestamp);
    return HistoryService.pad2(d.getHours()) + ':' + HistoryService.pad2(d.getMinutes());
  }

  private static pad2(value: number): string {
    if (value < 10) {
      return '0' + value;
    }
    return '' + value;
  }
}
