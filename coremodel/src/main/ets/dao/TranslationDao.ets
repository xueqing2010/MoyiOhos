import { relationalStore } from '@kit.ArkData';
import { MangaPage, OcrRegion, PageTranslation, TranslateStatus, makePageTranslation } from '../model/Entities';
import { RdbHelper } from '../db/RdbHelper';

/**
 * page_translation table CRUD.
 * ocr_json / translations_json carry ONLY text + coordinates (FR-014).
 */
export class TranslationDao {
  /** Insert or replace by page_id. */
  static async upsert(pt: PageTranslation): Promise<void> {
    const store = RdbHelper.get();
    pt.updatedAt = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'page_id': pt.pageId,
      'engine_type': pt.engineType,
      'ocr_json': JSON.stringify(pt.ocr),
      'translations_json': JSON.stringify(pt.translations),
      'status': pt.status as number,
      'fail_reason': pt.failReason !== undefined ? pt.failReason : null,
      'updated_at': pt.updatedAt
    };
    const pred = new relationalStore.RdbPredicates('page_translation');
    pred.equalTo('page_id', pt.pageId);
    const existing = await store.query(pred, ['id']);
    let exists = false;
    try {
      exists = existing.goToNextRow();
    } finally {
      existing.close();
    }
    if (exists) {
      await store.update(bucket, pred);
    } else {
      await store.insert('page_translation', bucket);
    }
  }

  static async queryByPageId(pageId: number): Promise<PageTranslation | undefined> {
    const pred = new relationalStore.RdbPredicates('page_translation');
    pred.equalTo('page_id', pageId);
    const rs = await RdbHelper.get().query(pred);
    try {
      if (rs.goToNextRow()) {
        return TranslationDao.mapRow(rs);
      }
      return undefined;
    } finally {
      rs.close();
    }
  }

  static async deleteByPageId(pageId: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates('page_translation');
    pred.equalTo('page_id', pageId);
    await RdbHelper.get().delete(pred);
  }

  static async deleteByPageIds(pageIds: Array<number>): Promise<void> {
    if (pageIds.length === 0) {
      return;
    }
    const pred = new relationalStore.RdbPredicates('page_translation');
    pred.in('page_id', pageIds);
    await RdbHelper.get().delete(pred);
  }

  private static mapRow(rs: relationalStore.ResultSet): PageTranslation {
    const pt = makePageTranslation(rs.getLong(rs.getColumnIndex('page_id')));
    pt.engineType = rs.getLong(rs.getColumnIndex('engine_type'));
    const ocrIdx = rs.getColumnIndex('ocr_json');
    if (!rs.isColumnNull(ocrIdx)) {
      const parsed: Object | null = JSON.parse(rs.getString(ocrIdx));
      if (parsed !== null) {
        pt.ocr = parsed as Array<OcrRegion>;
      }
    }
    const trIdx = rs.getColumnIndex('translations_json');
    if (!rs.isColumnNull(trIdx)) {
      const parsed: Object | null = JSON.parse(rs.getString(trIdx));
      if (parsed !== null) {
        pt.translations = parsed as Array<string>;
      }
    }
    pt.status = rs.getLong(rs.getColumnIndex('status')) as TranslateStatus;
    const frIdx = rs.getColumnIndex('fail_reason');
    if (!rs.isColumnNull(frIdx)) {
      pt.failReason = rs.getString(frIdx);
    }
    pt.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    return pt;
  }
}

/** Convenience alias used by page-oriented services. */
export type PageRow = MangaPage;
