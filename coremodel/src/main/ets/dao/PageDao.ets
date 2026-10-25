import { relationalStore } from '@kit.ArkData';
import { MangaPage, TranslateStatus, makeMangaPage } from '../model/Entities';
import { RdbHelper } from '../db/RdbHelper';

/** manga_page table CRUD. */
export class PageDao {
  static async insertBatch(pages: Array<MangaPage>): Promise<void> {
    if (pages.length === 0) {
      return;
    }
    const store = RdbHelper.get();
    for (const p of pages) {
      const bucket: relationalStore.ValuesBucket = {
        'manga_id': p.mangaId,
        'page_index': p.pageIndex,
        'image_path': p.imagePath,
        'width': p.width !== undefined ? p.width : null,
        'height': p.height !== undefined ? p.height : null,
        'translate_status': p.translateStatus as number
      };
      const id = await store.insert('manga_page', bucket);
      p.id = id;
    }
  }

  static async queryByMangaId(mangaId: number): Promise<Array<MangaPage>> {
    const pred = new relationalStore.RdbPredicates('manga_page');
    pred.equalTo('manga_id', mangaId);
    pred.orderByAsc('page_index');
    const rs = await RdbHelper.get().query(pred);
    const out: Array<MangaPage> = [];
    try {
      while (rs.goToNextRow()) {
        out.push(PageDao.mapRow(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async queryById(id: number): Promise<MangaPage | undefined> {
    const pred = new relationalStore.RdbPredicates('manga_page');
    pred.equalTo('id', id);
    const rs = await RdbHelper.get().query(pred);
    try {
      if (rs.goToNextRow()) {
        return PageDao.mapRow(rs);
      }
      return undefined;
    } finally {
      rs.close();
    }
  }

  static async updateTranslateStatus(pageId: number, status: TranslateStatus): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'translate_status': status as number
    };
    const pred = new relationalStore.RdbPredicates('manga_page');
    pred.equalTo('id', pageId);
    await RdbHelper.get().update(bucket, pred);
  }

  static async deleteByMangaId(mangaId: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates('manga_page');
    pred.equalTo('manga_id', mangaId);
    await RdbHelper.get().delete(pred);
  }

  /** All page ids of a manga (used for cascade deletes of translations). */
  static async queryPageIdsByMangaId(mangaId: number): Promise<Array<number>> {
    const pred = new relationalStore.RdbPredicates('manga_page');
    pred.equalTo('manga_id', mangaId);
    const rs = await RdbHelper.get().query(pred, ['id']);
    const out: Array<number> = [];
    try {
      while (rs.goToNextRow()) {
        out.push(rs.getLong(rs.getColumnIndex('id')));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  private static mapRow(rs: relationalStore.ResultSet): MangaPage {
    const p = makeMangaPage(
      rs.getLong(rs.getColumnIndex('manga_id')),
      rs.getLong(rs.getColumnIndex('page_index')),
      rs.getString(rs.getColumnIndex('image_path'))
    );
    p.id = rs.getLong(rs.getColumnIndex('id'));
    p.translateStatus = rs.getLong(rs.getColumnIndex('translate_status')) as TranslateStatus;
    const wIdx = rs.getColumnIndex('width');
    if (!rs.isColumnNull(wIdx)) {
      p.width = rs.getLong(wIdx);
    }
    const hIdx = rs.getColumnIndex('height');
    if (!rs.isColumnNull(hIdx)) {
      p.height = rs.getLong(hIdx);
    }
    return p;
  }
}
