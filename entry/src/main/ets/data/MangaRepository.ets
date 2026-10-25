import {
  Manga,
  MangaPage,
  SourceType,
  TranslateStatus,
  makeManga,
  makeMangaPage,
  MangaDao,
  PageDao,
  TranslationDao
} from 'coremodel';

/**
 * Manga data repository (T017): 建档/页写入/列表/删除连带级联。
 * Pure DB concerns — sandbox file movement lives in ImportService.
 */
export class MangaRepository {
  /** Create a manga record with pages (paths already finalized). */
  static async createManga(name: string, sourceType: SourceType, sourceUri: string | undefined,
    pagePaths: Array<string>): Promise<Manga> {
    const manga = await MangaRepository.createMangaShell(name, sourceType, sourceUri, pagePaths.length);
    await MangaRepository.replacePages(manga, pagePaths);
    return manga;
  }

  /** Insert the manga row only (id assignment); pages come via setPages. */
  static async createMangaShell(name: string, sourceType: SourceType, sourceUri: string | undefined,
    pageCount: number): Promise<Manga> {
    const manga = makeManga(name, sourceType, pageCount);
    manga.sourceUri = sourceUri;
    await MangaDao.insert(manga);
    return manga;
  }

  static async listAll(): Promise<Array<Manga>> {
    return MangaDao.queryAll();
  }

  static async getById(id: number): Promise<Manga | undefined> {
    return MangaDao.queryById(id);
  }

  /** Refresh page list + count + cover after a rescan or staged import. */
  static async replacePages(manga: Manga, pagePaths: Array<string>): Promise<void> {
    const oldPageIds = await PageDao.queryPageIdsByMangaId(manga.id);
    if (oldPageIds.length > 0) {
      await TranslationDao.deleteByPageIds(oldPageIds);
      await PageDao.deleteByMangaId(manga.id);
    }
    const pages: Array<MangaPage> = [];
    for (let i = 0; i < pagePaths.length; i++) {
      pages.push(makeMangaPage(manga.id, i, pagePaths[i]));
    }
    await PageDao.insertBatch(pages);
    manga.pageCount = pagePaths.length;
    manga.coverPath = pagePaths.length > 0 ? pagePaths[0] : undefined;
    await MangaDao.update(manga);
  }

  /**
   * Cascade delete: translations → pages → manga row.
   * Sandbox file cleanup for ARCHIVE/ALBUM is the caller's job
   * (ImportService.mangaDir(id)); DIRECTORY sources keep their grant.
   */
  static async deleteCascade(id: number): Promise<Manga | undefined> {
    const manga = await MangaDao.queryById(id);
    const pageIds = await PageDao.queryPageIdsByMangaId(id);
    await TranslationDao.deleteByPageIds(pageIds);
    await PageDao.deleteByMangaId(id);
    await MangaDao.deleteById(id);
    return manga;
  }

  static async updateLastReadPage(id: number, page: number): Promise<void> {
    await MangaDao.updateLastReadPage(id, page);
  }

  static async updateTranslateStatus(id: number, status: TranslateStatus): Promise<void> {
    await MangaDao.updateTranslateStatus(id, status);
  }
}
