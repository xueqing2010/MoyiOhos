import { relationalStore } from '@kit.ArkData';
import { Manga, SourceType, TranslateStatus, makeManga } from '../model/Entities';
import { RdbHelper } from '../db/RdbHelper';

/** manga table CRUD. */
export class MangaDao {
  static async insert(manga: Manga): Promise<number> {
    const bucket: relationalStore.ValuesBucket = {
      'name': manga.name,
      'source_type': manga.sourceType as number,
      'source_uri': manga.sourceUri !== undefined ? manga.sourceUri : null,
      'cover_path': manga.coverPath !== undefined ? manga.coverPath : null,
      'page_count': manga.pageCount,
      'last_read_page': manga.lastReadPage,
      'translate_status': manga.translateStatus as number,
      'created_at': manga.createdAt,
      'updated_at': manga.updatedAt
    };
    const id = await RdbHelper.get().insert('manga', bucket);
    manga.id = id;
    return id;
  }

  static async update(manga: Manga): Promise<void> {
    manga.updatedAt = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'name': manga.name,
      'source_type': manga.sourceType as number,
      'source_uri': manga.sourceUri !== undefined ? manga.sourceUri : null,
      'cover_path': manga.coverPath !== undefined ? manga.coverPath : null,
      'page_count': manga.pageCount,
      'last_read_page': manga.lastReadPage,
      'translate_status': manga.translateStatus as number,
      'updated_at': manga.updatedAt
    };
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', manga.id);
    await RdbHelper.get().update(bucket, pred);
  }

  static async deleteById(id: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    await RdbHelper.get().delete(pred);
  }

  static async queryAll(): Promise<Array<Manga>> {
    const pred = new relationalStore.RdbPredicates('manga');
    pred.orderByDesc('updated_at');
    const rs = await RdbHelper.get().query(pred);
    const out: Array<Manga> = [];
    try {
      while (rs.goToNextRow()) {
        out.push(MangaDao.mapRow(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async queryById(id: number): Promise<Manga | undefined> {
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    const rs = await RdbHelper.get().query(pred);
    try {
      if (rs.goToNextRow()) {
        return MangaDao.mapRow(rs);
      }
      return undefined;
    } finally {
      rs.close();
    }
  }

  static async updateLastReadPage(id: number, page: number): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'last_read_page': page,
      'updated_at': Date.now()
    };
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    await RdbHelper.get().update(bucket, pred);
  }

  static async updateTranslateStatus(id: number, status: TranslateStatus): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'translate_status': status as number,
      'updated_at': Date.now()
    };
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    await RdbHelper.get().update(bucket, pred);
  }

  private static mapRow(rs: relationalStore.ResultSet): Manga {
    const m = makeManga(
      rs.getString(rs.getColumnIndex('name')),
      rs.getLong(rs.getColumnIndex('source_type')) as SourceType,
      rs.getLong(rs.getColumnIndex('page_count'))
    );
    m.id = rs.getLong(rs.getColumnIndex('id'));
    m.lastReadPage = rs.getLong(rs.getColumnIndex('last_read_page'));
    m.translateStatus = rs.getLong(rs.getColumnIndex('translate_status')) as TranslateStatus;
    m.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    m.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    const uriIdx = rs.getColumnIndex('source_uri');
    if (!rs.isColumnNull(uriIdx)) {
      m.sourceUri = rs.getString(uriIdx);
    }
    const coverIdx = rs.getColumnIndex('cover_path');
    if (!rs.isColumnNull(coverIdx)) {
      m.coverPath = rs.getString(coverIdx);
    }
    return m;
  }
}
