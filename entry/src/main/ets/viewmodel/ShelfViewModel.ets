import { Manga, MangaDao, PageDao, SourceType } from 'coremodel';
import { preferences } from '@kit.ArkData';
import { AppEnv } from '../common/AppEnv';
import { MangaRepository } from '../data/MangaRepository';
import { ImportService } from '../service/ImportService';
import { PageTranslateService } from '../service/PageTranslateService';
import { BatchTranslateService } from '../service/BatchTranslateService';
import { ExportMode, ExportResult, ExportService } from '../service/ExportService';
import {
  encodeShelfSortMode,
  parseShelfSortMode,
  ShelfSegment,
  ShelfSortMode
} from '../model/UiModels';

const PREF_FILE = 'starflow_shelf';
const KEY_VIEW_MODE = 'view_mode';
const KEY_SORT_MODE = 'sort_mode';
const KEY_SEGMENT = 'segment';
/** 跨 Tab/页面刷新信号：导入/向导/示例数据完成后 setOrCreate，书架与小说分段 @Watch 刷新。 */
export const SHELF_DIRTY_KEY = 'starflow_shelf_dirty';

/** 目录源增量刷新结果（书架刷新菜单回显）。 */
export class DirectoryRefreshResult {
  refreshed: number = 0;
  failed: number = 0;
  detail: string = '';
}

/**
 * 书架 VM（stage-2 S101）：列表加载/排序、列表/网格/分段视图记忆、
 * 删除连带沙箱与 URI 授权清理、目录源重扫与批量刷新、改名/换封面、批翻/导出入口。
 */
export class ShelfViewModel {
  /** 通知书架/小说分段刷新（AppStorage 键见 SHELF_DIRTY_KEY）。 */
  static notifyChanged(): void {
    AppStorage.setOrCreate(SHELF_DIRTY_KEY, Date.now());
  }

  static async loadMangas(): Promise<Array<Manga>> {
    await AppEnv.ready();
    return MangaRepository.listAll();
  }

  /** Persisted shelf layout ('list' | 'grid')，记忆用户上次的选择。 */
  static async loadViewMode(): Promise<string> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      const mode = pref.getSync(KEY_VIEW_MODE, 'grid') as string;
      return mode === 'grid' ? 'grid' : 'list';
    } catch (e) {
      return 'grid';
    }
  }

  static async saveViewMode(mode: string): Promise<void> {
    await ShelfViewModel.putPref(KEY_VIEW_MODE, mode === 'grid' ? 'grid' : 'list');
  }

  static async loadSortMode(): Promise<ShelfSortMode> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      const raw = pref.getSync(KEY_SORT_MODE, 'recent') as string;
      return parseShelfSortMode(raw);
    } catch (e) {
      return ShelfSortMode.RECENT;
    }
  }

  static async saveSortMode(mode: ShelfSortMode): Promise<void> {
    await ShelfViewModel.putPref(KEY_SORT_MODE, encodeShelfSortMode(mode));
  }

  static async loadSegment(): Promise<ShelfSegment> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      const raw = pref.getSync(KEY_SEGMENT, 'manga') as string;
      return raw === 'novel' ? ShelfSegment.NOVEL : ShelfSegment.MANGA;
    } catch (e) {
      return ShelfSegment.MANGA;
    }
  }

  static async saveSegment(segment: ShelfSegment): Promise<void> {
    await ShelfViewModel.putPref(KEY_SEGMENT, segment === ShelfSegment.NOVEL ? 'novel' : 'manga');
  }

  private static async putPref(key: string, value: string): Promise<void> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      pref.putSync(key, value);
      await pref.flush();
    } catch (e) {
      // 持久化失败不影响当次使用
    }
  }

  /**
   * 删除单本：DB 级联（译文→页→漫画）+ 文件清理。
   * 目录源释放持久化 URI 授权（不快照文件）；压缩包/相册/示例数据删除沙箱页目录
   * （示例数据的目录记录在 sourceUri，仅当位于本应用沙箱内才删除）。
   */
  static async deleteManga(id: number): Promise<void> {
    const manga = await MangaRepository.deleteCascade(id);
    if (manga === undefined) {
      return;
    }
    if (manga.sourceType === SourceType.DIRECTORY) {
      await ImportService.releaseDirectoryPermission(manga.sourceUri);
      return;
    }
    ImportService.rmRecursive(ImportService.mangaDir(id));
    const filesDir = AppEnv.getInstance().getContext().filesDir;
    if (manga.sourceUri !== undefined && manga.sourceUri.startsWith(filesDir)) {
      ImportService.rmRecursive(manga.sourceUri);
    }
  }

  /** Multi-select delete (US-3)：逐本删除，失败跳过续删。 */
  static async deleteMangas(ids: Array<number>): Promise<number> {
    let deleted = 0;
    for (const id of ids) {
      try {
        await ShelfViewModel.deleteManga(id);
        deleted++;
      } catch (e) {
        // 单本失败不阻断批量
      }
    }
    return deleted;
  }

  /** 重命名（书架长按菜单）。 */
  static async renameManga(id: number, newName: string): Promise<Manga> {
    await AppEnv.ready();
    const manga = await MangaRepository.getById(id);
    if (manga === undefined) {
      throw new Error('漫画记录不存在');
    }
    const trimmed = newName.trim();
    if (trimmed.length === 0) {
      throw new Error('名称不能为空');
    }
    manga.name = trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed;
    await MangaDao.update(manga);
    return manga;
  }

  /** 更换封面（从页列表选择，0 基页序）。 */
  static async updateCover(mangaId: number, pageIndex: number): Promise<void> {
    await AppEnv.ready();
    const manga = await MangaRepository.getById(mangaId);
    if (manga === undefined) {
      throw new Error('漫画记录不存在');
    }
    const pages = await PageDao.queryByMangaId(mangaId);
    if (pages.length === 0) {
      throw new Error('该漫画没有页面');
    }
    const safe = pageIndex >= 0 && pageIndex < pages.length ? pageIndex : 0;
    manga.coverPath = pages[safe].imagePath;
    await MangaDao.update(manga);
  }

  /** 读取页面列表（换封面预览）。 */
  static async loadPages(mangaId: number): Promise<Array<string>> {
    await AppEnv.ready();
    const pages = await PageDao.queryByMangaId(mangaId);
    const paths: Array<string> = [];
    for (const p of pages) {
      paths.push(p.imagePath);
    }
    return paths;
  }

  /** Rescan a DIRECTORY manga; readable error when 授权失效 (R10). */
  static async rescan(mangaId: number): Promise<Manga> {
    await AppEnv.ready();
    return ImportService.rescanDirectory(mangaId);
  }

  /** 批量刷新全部目录源（增量扫描，不重新授权）。 */
  static async refreshDirectorySources(): Promise<DirectoryRefreshResult> {
    await AppEnv.ready();
    const result = new DirectoryRefreshResult();
    const list = await MangaRepository.listAll();
    for (const m of list) {
      if (m.sourceType !== SourceType.DIRECTORY) {
        continue;
      }
      try {
        await ImportService.rescanDirectory(m.id);
        result.refreshed++;
      } catch (e) {
        result.failed++;
        if (result.detail.length === 0) {
          result.detail = `「${m.name}」${e}`;
        }
      }
    }
    return result;
  }

  static async probeAuth(mangaId: number): Promise<boolean> {
    await AppEnv.ready();
    return ImportService.probeDirectoryAuth(mangaId);
  }

  /** 从书架发起整本批量翻译（US-6）。 */
  static async startBatch(mangaId: number): Promise<void> {
    await AppEnv.ready();
    const engine = await PageTranslateService.loadEngineType();
    BatchTranslateService.getInstance().start(mangaId, engine);
  }

  /** 从书架发起导出（US-7）。 */
  static async exportManga(mangaId: number, mode: ExportMode,
    onProgress: (done: number, total: number) => void,
    isCancelled?: () => boolean): Promise<ExportResult> {
    await AppEnv.ready();
    return ExportService.export(mangaId, mode, onProgress, isCancelled);
  }
}
