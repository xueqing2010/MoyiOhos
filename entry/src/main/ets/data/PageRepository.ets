import {
  MangaPage,
  PageTranslation,
  TranslateStatus,
  PageDao,
  TranslationDao
} from 'coremodel';

/**
 * Page + page-translation repository (T017): 页与页翻译记录读写。
 * FR-014: PageTranslation 只含文本与坐标，永不落合成图。
 */
export class PageRepository {
  static async getPages(mangaId: number): Promise<Array<MangaPage>> {
    return PageDao.queryByMangaId(mangaId);
  }

  static async getPage(pageId: number): Promise<MangaPage | undefined> {
    return PageDao.queryById(pageId);
  }

  static async getTranslation(pageId: number): Promise<PageTranslation | undefined> {
    return TranslationDao.queryByPageId(pageId);
  }

  /** Upsert a translation record and sync the page status. */
  static async saveTranslation(pt: PageTranslation): Promise<void> {
    await TranslationDao.upsert(pt);
    await PageDao.updateTranslateStatus(pt.pageId, pt.status);
  }

  static async updatePageStatus(pageId: number, status: TranslateStatus): Promise<void> {
    await PageDao.updateTranslateStatus(pageId, status);
  }

  /** Remove translations for every page of a manga (used by cascade). */
  static async deleteTranslationsByMangaId(mangaId: number): Promise<void> {
    const pageIds = await PageDao.queryPageIdsByMangaId(mangaId);
    await TranslationDao.deleteByPageIds(pageIds);
  }
}
