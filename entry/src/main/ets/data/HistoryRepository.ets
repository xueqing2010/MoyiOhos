import { relationalStore } from '@kit.ArkData';
import {
  Manga,
  MangaPage,
  NovelChapter,
  PageTranslation,
  TextTranslationRecord,
  RdbHelper,
  MangaDao,
  NovelChapterDao,
  TranslationDao,
  TextTranslationDao,
  makeTextTranslationRecord
} from 'coremodel';
import { PageRepository } from './PageRepository';

/** 列表单类记录上限（防止历史无限增长拖垮首屏；详情/全屏按组查询不受限）。 */
const MAX_LIST_ROWS = 500;

/** 漫画页翻译历史行（page_translation ⋈ manga_page ⋈ manga）。 */
export class MangaHistoryRow {
  pageId: number = 0;
  mangaId: number = 0;
  mangaName: string = '';
  coverPath: string = '';
  pageIndex: number = 0;
  imagePath: string = '';
  status: number = 0;
  engineType: number = 0;
  updatedAt: number = 0;
  failReason: string = '';
  pageCount: number = 0;
  translatedCount: number = 0;
  translatedLines: number = 0;
  totalLines: number = 0;
}

/** 小说章节翻译历史行（novel_chapter ⋈ novel，只取已译章节）。 */
export class NovelHistoryRow {
  chapterId: number = 0;
  novelId: number = 0;
  novelName: string = '';
  coverPath: string = '';
  chapterIndex: number = 0;
  chapterTitle: string = '';
  status: number = 0;
  updatedAt: number = 0;
  failReason: string = '';
  chapterCount: number = 0;
  translatedCount: number = 0;
  translatedChars: number = 0;
  content: string = '';
  translatedContent: string = '';
}

const MANGA_SELECT: string = 'SELECT t.page_id AS page_id, ' +
  't.engine_type AS engine_type, ' +
  't.status AS status, ' +
  't.updated_at AS updated_at, ' +
  't.fail_reason AS fail_reason, ' +
  't.translations_json AS translations_json, ' +
  'p.manga_id AS manga_id, ' +
  'p.page_index AS page_index, ' +
  'p.image_path AS image_path, ' +
  'm.name AS manga_name, ' +
  'm.cover_path AS cover_path, ' +
  'm.page_count AS page_count, ' +
  '(SELECT COUNT(*) FROM page_translation t2 ' +
  '  INNER JOIN manga_page p2 ON t2.page_id = p2.id ' +
  '  WHERE p2.manga_id = m.id) AS translated_count ' +
  'FROM page_translation t ' +
  'INNER JOIN manga_page p ON t.page_id = p.id ' +
  'INNER JOIN manga m ON p.manga_id = m.id';

const NOVEL_COLUMNS: string = 'SELECT c.id AS chapter_id, ' +
  'c.novel_id AS novel_id, ' +
  'c.chapter_index AS chapter_index, ' +
  'c.title AS title, ' +
  'c.translate_status AS translate_status, ' +
  'c.updated_at AS updated_at, ' +
  'c.fail_reason AS fail_reason, ' +
  'LENGTH(c.translated_content) AS translated_chars, ' +
  'n.name AS novel_name, ' +
  'n.cover_path AS cover_path, ' +
  'n.chapter_count AS chapter_count, ' +
  '(SELECT COUNT(*) FROM novel_chapter c2 ' +
  '  WHERE c2.novel_id = n.id ' +
  '    AND c2.translated_content IS NOT NULL ' +
  "    AND c2.translated_content <> '') AS translated_count";

const NOVEL_FROM: string = ' FROM novel_chapter c ' +
  'INNER JOIN novel n ON c.novel_id = n.id ' +
  "WHERE c.translated_content IS NOT NULL AND c.translated_content <> ''";

/** 列表用：不取章节全文，避免一次加载 500 章正文。 */
const NOVEL_SELECT: string = NOVEL_COLUMNS + NOVEL_FROM;

/** 详情 / 组导出用：额外取原文与译文全文（此前漏选导致详情显示「暂无内容」）。 */
const NOVEL_SELECT_FULL: string = NOVEL_COLUMNS +
  ', c.content AS content, c.translated_content AS translated_content' + NOVEL_FROM;

/**
 * 历史数据访问层（task-6）：
 * 以只读 JOIN SQL 聚合三类记录——漫画页译文（page_translation ⋈ manga_page ⋈ manga）、
 * 小说章节译文（novel_chapter.translated_content 非空）、文本翻译（text_translation）。
 * 写操作仅限“删除译文记录 / 清空历史”所需的表，不动书籍、页面与章节原文。
 */
export class HistoryRepository {
  // -------------------------------------------------------------------------
  // 查询
  // -------------------------------------------------------------------------

  /** 全部漫画页译文，按更新时间倒序（列表用）。 */
  static async queryMangaRows(): Promise<Array<MangaHistoryRow>> {
    return HistoryRepository.queryMangaRowsWith(MANGA_SELECT + ' ORDER BY t.updated_at DESC LIMIT ?',
      HistoryRepository.numberArgs([MAX_LIST_ROWS]));
  }

  /** 某一本漫画的全部已译页，按页序升序（进程组 / 全屏用）。 */
  static async queryMangaRowsByManga(mangaId: number): Promise<Array<MangaHistoryRow>> {
    return HistoryRepository.queryMangaRowsWith(MANGA_SELECT + ' WHERE p.manga_id = ? ORDER BY p.page_index ASC',
      HistoryRepository.numberArgs([mangaId]));
  }

  /** 单页详情（含 manga 元信息）。 */
  static async queryMangaRowByPage(pageId: number): Promise<MangaHistoryRow | undefined> {
    const rows = await HistoryRepository.queryMangaRowsWith(MANGA_SELECT + ' WHERE t.page_id = ?',
      HistoryRepository.numberArgs([pageId]));
    if (rows.length === 0) {
      return undefined;
    }
    return rows[0];
  }

  /** 全部已译小说章节，按更新时间倒序（列表用）。 */
  static async queryNovelRows(): Promise<Array<NovelHistoryRow>> {
    return HistoryRepository.queryNovelRowsWith(NOVEL_SELECT + ' ORDER BY c.updated_at DESC LIMIT ?',
      HistoryRepository.numberArgs([MAX_LIST_ROWS]), false);
  }

  /** 某一本小说的全部已译章节（进程组 / 全屏用），含原文与译文全文。 */
  static async queryNovelRowsByNovel(novelId: number): Promise<Array<NovelHistoryRow>> {
    return HistoryRepository.queryNovelRowsWith(
      NOVEL_SELECT_FULL + ' AND c.novel_id = ? ORDER BY c.chapter_index ASC',
      HistoryRepository.numberArgs([novelId]), true);
  }

  /** 单章节详情（含原文与译文全文）。 */
  static async queryNovelRowByChapter(chapterId: number): Promise<NovelHistoryRow | undefined> {
    const rows = await HistoryRepository.queryNovelRowsWith(NOVEL_SELECT_FULL + ' AND c.id = ?',
      HistoryRepository.numberArgs([chapterId]), true);
    if (rows.length === 0) {
      return undefined;
    }
    return rows[0];
  }

  /** 小说全部章节（全屏翻页读取译文用；含未翻译章节以便定位章号）。 */
  static async queryNovelChapters(novelId: number): Promise<Array<NovelChapter>> {
    return NovelChapterDao.queryByNovelId(novelId);
  }

  /** 全部文本翻译记录，按时间倒序（列表用）。 */
  static async queryTextRows(): Promise<Array<TextTranslationRecord>> {
    const all = await TextTranslationDao.queryAll();
    if (all.length <= MAX_LIST_ROWS) {
      return all;
    }
    return all.slice(0, MAX_LIST_ROWS);
  }

  /** 某一天的文本翻译记录（按时间升序，进程组 / 全屏用）。 */
  static async queryTextRowsByRange(startMs: number, endMs: number): Promise<Array<TextTranslationRecord>> {
    const rs = await RdbHelper.get().querySql(
      'SELECT id, source_text, translated_text, engine_type, from_lang, to_lang, created_at ' +
        'FROM text_translation WHERE created_at >= ? AND created_at < ? ORDER BY created_at ASC',
      HistoryRepository.numberArgs([startMs, endMs]));
    const out: Array<TextTranslationRecord> = [];
    try {
      while (rs.goToNextRow()) {
        out.push(HistoryRepository.mapTextRow(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** 单条文本翻译详情。 */
  static async queryTextRowById(id: number): Promise<TextTranslationRecord | undefined> {
    const rs = await RdbHelper.get().querySql(
      'SELECT id, source_text, translated_text, engine_type, from_lang, to_lang, created_at ' +
        'FROM text_translation WHERE id = ?',
      HistoryRepository.numberArgs([id]));
    try {
      if (rs.goToNextRow()) {
        return HistoryRepository.mapTextRow(rs);
      }
      return undefined;
    } finally {
      rs.close();
    }
  }

  /** 漫画页译文（含 OCR 行与译文行）。 */
  static async queryPageTranslation(pageId: number): Promise<PageTranslation | undefined> {
    return TranslationDao.queryByPageId(pageId);
  }

  /** 漫画实体（详情页展示书名 / 封面 / 页数）。 */
  static async queryMangaById(mangaId: number): Promise<Manga | undefined> {
    return MangaDao.queryById(mangaId);
  }

  /** 漫画页实体（详情页展示原图路径）。 */
  static async queryPageById(pageId: number): Promise<MangaPage | undefined> {
    return PageRepository.getPage(pageId);
  }

  // -------------------------------------------------------------------------
  // 写操作（仅删除译文记录，不删书籍 / 页面 / 章节原文）
  // -------------------------------------------------------------------------

  /** 删除若干漫画页译文并复位页状态。 */
  static async deleteMangaPageRecords(pageIds: Array<number>): Promise<void> {
    if (pageIds.length === 0) {
      return;
    }
    const marks = HistoryRepository.placeholders(pageIds.length);
    await RdbHelper.get().executeSql('DELETE FROM page_translation WHERE page_id IN (' + marks + ')',
      HistoryRepository.numberArgs(pageIds));
    await RdbHelper.get().executeSql('UPDATE manga_page SET translate_status = 0 WHERE id IN (' + marks + ')',
      HistoryRepository.numberArgs(pageIds));
  }

  /** 清空全部漫画页译文并复位页面与书籍翻译状态。 */
  static async clearMangaRecords(): Promise<void> {
    await RdbHelper.get().executeSql('DELETE FROM page_translation');
    await RdbHelper.get().executeSql('UPDATE manga_page SET translate_status = 0');
    await RdbHelper.get().executeSql('UPDATE manga SET translate_status = 0');
  }

  /** 删除若干小说章节译文（置空 translated_content 并复位状态）。 */
  static async deleteNovelChapterRecords(chapterIds: Array<number>): Promise<void> {
    if (chapterIds.length === 0) {
      return;
    }
    const marks = HistoryRepository.placeholders(chapterIds.length);
    const args: Array<relationalStore.ValueType> = [Date.now()];
    for (const id of chapterIds) {
      args.push(id);
    }
    await RdbHelper.get().executeSql(
      'UPDATE novel_chapter SET translated_content = NULL, translate_status = 0, fail_reason = NULL, ' +
        'updated_at = ? WHERE id IN (' + marks + ')', args);
  }

  /** 清空全部小说章节译文并复位书籍翻译状态。 */
  static async clearNovelRecords(): Promise<void> {
    await RdbHelper.get().executeSql(
      'UPDATE novel_chapter SET translated_content = NULL, translate_status = 0, fail_reason = NULL');
    await RdbHelper.get().executeSql('UPDATE novel SET translate_status = 0');
  }

  /** 删除若干文本翻译记录。 */
  static async deleteTextRecords(ids: Array<number>): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const marks = HistoryRepository.placeholders(ids.length);
    await RdbHelper.get().executeSql('DELETE FROM text_translation WHERE id IN (' + marks + ')',
      HistoryRepository.numberArgs(ids));
  }

  /** 清空全部文本翻译记录。 */
  static async clearTextRecords(): Promise<void> {
    await RdbHelper.get().executeSql('DELETE FROM text_translation');
  }

  /** 清空三类历史。 */
  static async clearAll(): Promise<void> {
    await HistoryRepository.clearMangaRecords();
    await HistoryRepository.clearNovelRecords();
    await HistoryRepository.clearTextRecords();
  }

  /**
   * 按时间清理：删除早于 cutoff 的译文记录（spec §D「清空 / 按时间清理」）。
   * 只清译文，保留书籍 / 页面 / 章节原文；并复位失去译文的页与书籍聚合状态。
   */
  static async clearBefore(cutoff: number): Promise<void> {
    const args = HistoryRepository.numberArgs([cutoff]);
    await RdbHelper.get().executeSql('DELETE FROM page_translation WHERE updated_at < ?', args);
    await RdbHelper.get().executeSql(
      'UPDATE manga_page SET translate_status = 0 WHERE id NOT IN (SELECT page_id FROM page_translation)');
    await RdbHelper.get().executeSql(
      'UPDATE novel_chapter SET translated_content = NULL, translate_status = 0, fail_reason = NULL ' +
        'WHERE updated_at < ?', args);
    await RdbHelper.get().executeSql('DELETE FROM text_translation WHERE created_at < ?', args);
    await RdbHelper.get().executeSql(
      'UPDATE manga SET translate_status = 0 WHERE id NOT IN (' +
        'SELECT DISTINCT p.manga_id FROM page_translation t INNER JOIN manga_page p ON t.page_id = p.id)');
    await RdbHelper.get().executeSql(
      "UPDATE novel SET translate_status = 0 WHERE id NOT IN (" +
        "SELECT DISTINCT novel_id FROM novel_chapter WHERE translated_content IS NOT NULL AND translated_content <> '')");
  }

  // -------------------------------------------------------------------------
  // 内部工具
  // -------------------------------------------------------------------------

  private static async queryMangaRowsWith(sql: string,
    args: Array<relationalStore.ValueType>): Promise<Array<MangaHistoryRow>> {
    const rs = await RdbHelper.get().querySql(sql, args);
    const out: Array<MangaHistoryRow> = [];
    try {
      while (rs.goToNextRow()) {
        out.push(HistoryRepository.mapMangaRow(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  private static async queryNovelRowsWith(sql: string, args: Array<relationalStore.ValueType>,
    withContent: boolean): Promise<Array<NovelHistoryRow>> {
    const rs = await RdbHelper.get().querySql(sql, args);
    const out: Array<NovelHistoryRow> = [];
    try {
      while (rs.goToNextRow()) {
        out.push(HistoryRepository.mapNovelRow(rs, withContent));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  private static mapMangaRow(rs: relationalStore.ResultSet): MangaHistoryRow {
    const row = new MangaHistoryRow();
    row.pageId = rs.getLong(rs.getColumnIndex('page_id'));
    row.engineType = rs.getLong(rs.getColumnIndex('engine_type'));
    row.status = rs.getLong(rs.getColumnIndex('status'));
    row.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    row.mangaId = rs.getLong(rs.getColumnIndex('manga_id'));
    row.pageIndex = rs.getLong(rs.getColumnIndex('page_index'));
    row.pageCount = rs.getLong(rs.getColumnIndex('page_count'));
    row.translatedCount = rs.getLong(rs.getColumnIndex('translated_count'));
    row.mangaName = HistoryRepository.readString(rs, 'manga_name');
    row.coverPath = HistoryRepository.readString(rs, 'cover_path');
    row.imagePath = HistoryRepository.readString(rs, 'image_path');
    row.failReason = HistoryRepository.readString(rs, 'fail_reason');
    const trIdx = rs.getColumnIndex('translations_json');
    if (!rs.isColumnNull(trIdx)) {
      // 单条坏 JSON 不应拖垮整个历史列表：解析失败按 0 行处理。
      try {
        const parsed: Object | null = JSON.parse(rs.getString(trIdx));
        if (parsed !== null) {
          const lines = parsed as Array<string>;
          row.totalLines = lines.length;
          let filled = 0;
          for (const line of lines) {
            if (line !== undefined && line !== null && line.length > 0) {
              filled++;
            }
          }
          row.translatedLines = filled;
        }
      } catch (ignore) {
        row.totalLines = 0;
        row.translatedLines = 0;
      }
    }
    return row;
  }

  private static mapNovelRow(rs: relationalStore.ResultSet, withContent: boolean): NovelHistoryRow {
    const row = new NovelHistoryRow();
    row.chapterId = rs.getLong(rs.getColumnIndex('chapter_id'));
    row.novelId = rs.getLong(rs.getColumnIndex('novel_id'));
    row.chapterIndex = rs.getLong(rs.getColumnIndex('chapter_index'));
    row.status = rs.getLong(rs.getColumnIndex('translate_status'));
    row.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    row.chapterCount = rs.getLong(rs.getColumnIndex('chapter_count'));
    row.translatedCount = rs.getLong(rs.getColumnIndex('translated_count'));
    row.translatedChars = rs.getLong(rs.getColumnIndex('translated_chars'));
    row.chapterTitle = HistoryRepository.readString(rs, 'title');
    row.novelName = HistoryRepository.readString(rs, 'novel_name');
    row.coverPath = HistoryRepository.readString(rs, 'cover_path');
    row.failReason = HistoryRepository.readString(rs, 'fail_reason');
    if (withContent) {
      row.content = HistoryRepository.readString(rs, 'content');
      row.translatedContent = HistoryRepository.readString(rs, 'translated_content');
    }
    return row;
  }

  private static mapTextRow(rs: relationalStore.ResultSet): TextTranslationRecord {
    const rec = makeTextTranslationRecord(
      HistoryRepository.readString(rs, 'source_text'),
      HistoryRepository.readString(rs, 'translated_text'),
      rs.getLong(rs.getColumnIndex('engine_type')),
      HistoryRepository.readString(rs, 'from_lang'),
      HistoryRepository.readString(rs, 'to_lang')
    );
    rec.id = rs.getLong(rs.getColumnIndex('id'));
    rec.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    return rec;
  }

  private static readString(rs: relationalStore.ResultSet, column: string): string {
    const idx = rs.getColumnIndex(column);
    if (idx < 0 || rs.isColumnNull(idx)) {
      return '';
    }
    return rs.getString(idx);
  }

  private static placeholders(n: number): string {
    let s = '';
    for (let i = 0; i < n; i++) {
      if (i > 0) {
        s += ',';
      }
      s += '?';
    }
    return s;
  }

  private static numberArgs(values: Array<number>): Array<relationalStore.ValueType> {
    const args: Array<relationalStore.ValueType> = [];
    for (const v of values) {
      args.push(v);
    }
    return args;
  }
}
