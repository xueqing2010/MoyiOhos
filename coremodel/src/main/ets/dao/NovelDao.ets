import { relationalStore } from '@kit.ArkData';
import { Novel, NovelFormat, TranslateStatus, makeNovel } from '../model/Entities';
import { RdbHelper } from '../db/RdbHelper';

/** novel table CRUD. */
export class NovelDao {
  static async insert(novel: Novel): Promise<number> {
    const bucket: relationalStore.ValuesBucket = {
      'name': novel.name,
      'format': novel.format as number,
      'source_uri': novel.sourceUri !== undefined ? novel.sourceUri : null,
      'cover_path': novel.coverPath !== undefined ? novel.coverPath : null,
      'chapter_count': novel.chapterCount,
      'last_read_chapter': novel.lastReadChapter,
      'last_read_offset': novel.lastReadOffset,
      'translate_status': novel.translateStatus as number,
      'created_at': novel.createdAt,
      'updated_at': novel.updatedAt
    };
    const id = await RdbHelper.get().insert('novel', bucket);
    novel.id = id;
    return id;
  }

  static async update(novel: Novel): Promise<void> {
    novel.updatedAt = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'name': novel.name,
      'format': novel.format as number,
      'source_uri': novel.sourceUri !== undefined ? novel.sourceUri : null,
      'cover_path': novel.coverPath !== undefined ? novel.coverPath : null,
      'chapter_count': novel.chapterCount,
      'last_read_chapter': novel.lastReadChapter,
      'last_read_offset': novel.lastReadOffset,
      'translate_status': novel.translateStatus as number,
      'updated_at': novel.updatedAt
    };
    const pred = new relationalStore.RdbPredicates('novel');
    pred.equalTo('id', novel.id);
    await RdbHelper.get().update(bucket, pred);
  }

  static async deleteById(id: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates('novel');
    pred.equalTo('id', id);
    await RdbHelper.get().delete(pred);
  }

  static async queryAll(): Promise<Array<Novel>> {
    const pred = new relationalStore.RdbPredicates('novel');
    pred.orderByDesc('updated_at');
    const rs = await RdbHelper.get().query(pred);
    const out: Array<Novel> = [];
    try {
      while (rs.goToNextRow()) {
        out.push(NovelDao.mapRow(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async queryById(id: number): Promise<Novel | undefined> {
    const pred = new relationalStore.RdbPredicates('novel');
    pred.equalTo('id', id);
    const rs = await RdbHelper.get().query(pred);
    try {
      if (rs.goToNextRow()) {
        return NovelDao.mapRow(rs);
      }
      return undefined;
    } finally {
      rs.close();
    }
  }

  static async updateReadingProgress(id: number, chapter: number, offset: number): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'last_read_chapter': chapter,
      'last_read_offset': offset,
      'updated_at': Date.now()
    };
    const pred = new relationalStore.RdbPredicates('novel');
    pred.equalTo('id', id);
    await RdbHelper.get().update(bucket, pred);
  }

  static async updateTranslateStatus(id: number, status: TranslateStatus): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'translate_status': status as number,
      'updated_at': Date.now()
    };
    const pred = new relationalStore.RdbPredicates('novel');
    pred.equalTo('id', id);
    await RdbHelper.get().update(bucket, pred);
  }

  private static mapRow(rs: relationalStore.ResultSet): Novel {
    const n = makeNovel(
      rs.getString(rs.getColumnIndex('name')),
      rs.getLong(rs.getColumnIndex('format')) as NovelFormat,
      rs.getLong(rs.getColumnIndex('chapter_count'))
    );
    n.id = rs.getLong(rs.getColumnIndex('id'));
    n.lastReadChapter = rs.getLong(rs.getColumnIndex('last_read_chapter'));
    n.lastReadOffset = rs.getLong(rs.getColumnIndex('last_read_offset'));
    n.translateStatus = rs.getLong(rs.getColumnIndex('translate_status')) as TranslateStatus;
    n.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    n.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    const uriIdx = rs.getColumnIndex('source_uri');
    if (!rs.isColumnNull(uriIdx)) {
      n.sourceUri = rs.getString(uriIdx);
    }
    const coverIdx = rs.getColumnIndex('cover_path');
    if (!rs.isColumnNull(coverIdx)) {
      n.coverPath = rs.getString(coverIdx);
    }
    return n;
  }
}
