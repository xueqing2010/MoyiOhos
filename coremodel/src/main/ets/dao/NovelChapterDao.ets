import { relationalStore } from '@kit.ArkData';
import { NovelChapter, TranslateStatus, makeNovelChapter } from '../model/Entities';
import { RdbHelper } from '../db/RdbHelper';

/** novel_chapter table CRUD. Chapters hold their full plain text. */
export class NovelChapterDao {
  static async insertBatch(chapters: Array<NovelChapter>): Promise<void> {
    const store = RdbHelper.get();
    for (const c of chapters) {
      const bucket: relationalStore.ValuesBucket = {
        'novel_id': c.novelId,
        'chapter_index': c.chapterIndex,
        'title': c.title,
        'content': c.content,
        'translate_status': c.translateStatus as number,
        'translated_content': c.translatedContent !== undefined ? c.translatedContent : null,
        'fail_reason': c.failReason !== undefined ? c.failReason : null,
        'updated_at': c.updatedAt
      };
      const id = await store.insert('novel_chapter', bucket);
      c.id = id;
    }
  }

  static async queryByNovelId(novelId: number): Promise<Array<NovelChapter>> {
    const pred = new relationalStore.RdbPredicates('novel_chapter');
    pred.equalTo('novel_id', novelId);
    pred.orderByAsc('chapter_index');
    const rs = await RdbHelper.get().query(pred);
    const out: Array<NovelChapter> = [];
    try {
      while (rs.goToNextRow()) {
        out.push(NovelChapterDao.mapRow(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** TOC-lite query without loading chapter bodies. */
  static async queryTocByNovelId(novelId: number): Promise<Array<NovelChapter>> {
    const pred = new relationalStore.RdbPredicates('novel_chapter');
    pred.equalTo('novel_id', novelId);
    pred.orderByAsc('chapter_index');
    const rs = await RdbHelper.get().query(pred, ['id', 'novel_id', 'chapter_index', 'title', 'translate_status', 'updated_at']);
    const out: Array<NovelChapter> = [];
    try {
      while (rs.goToNextRow()) {
        const c = makeNovelChapter(rs.getLong(rs.getColumnIndex('novel_id')),
          rs.getLong(rs.getColumnIndex('chapter_index')),
          rs.getString(rs.getColumnIndex('title')), '');
        c.id = rs.getLong(rs.getColumnIndex('id'));
        c.translateStatus = rs.getLong(rs.getColumnIndex('translate_status')) as TranslateStatus;
        c.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
        out.push(c);
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async queryByIndex(novelId: number, chapterIndex: number): Promise<NovelChapter | undefined> {
    const pred = new relationalStore.RdbPredicates('novel_chapter');
    pred.equalTo('novel_id', novelId);
    pred.equalTo('chapter_index', chapterIndex);
    const rs = await RdbHelper.get().query(pred);
    try {
      if (rs.goToNextRow()) {
        return NovelChapterDao.mapRow(rs);
      }
      return undefined;
    } finally {
      rs.close();
    }
  }

  static async updateTranslation(chapterId: number, translated: string, status: TranslateStatus,
    failReason?: string): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'translated_content': translated,
      'translate_status': status as number,
      'fail_reason': failReason !== undefined ? failReason : null,
      'updated_at': Date.now()
    };
    const pred = new relationalStore.RdbPredicates('novel_chapter');
    pred.equalTo('id', chapterId);
    await RdbHelper.get().update(bucket, pred);
  }

  static async deleteByNovelId(novelId: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates('novel_chapter');
    pred.equalTo('novel_id', novelId);
    await RdbHelper.get().delete(pred);
  }

  private static mapRow(rs: relationalStore.ResultSet): NovelChapter {
    const c = makeNovelChapter(
      rs.getLong(rs.getColumnIndex('novel_id')),
      rs.getLong(rs.getColumnIndex('chapter_index')),
      rs.getString(rs.getColumnIndex('title')),
      rs.getString(rs.getColumnIndex('content'))
    );
    c.id = rs.getLong(rs.getColumnIndex('id'));
    c.translateStatus = rs.getLong(rs.getColumnIndex('translate_status')) as TranslateStatus;
    c.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    const trIdx = rs.getColumnIndex('translated_content');
    if (!rs.isColumnNull(trIdx)) {
      c.translatedContent = rs.getString(trIdx);
    }
    const fIdx = rs.getColumnIndex('fail_reason');
    if (!rs.isColumnNull(fIdx)) {
      c.failReason = rs.getString(fIdx);
    }
    return c;
  }
}
