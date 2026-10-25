import fs from '@ohos.file.fs';
import { fileShare } from '@kit.CoreFileKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { Manga, MangaDao, SourceType } from 'coremodel';
import { naturalSort, Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { MangaRepository } from '../data/MangaRepository';

const TAG = 'ImportService';
const IMAGE_EXTS: Array<string> = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];
const ALBUM_MAX = 500;

/** Progress payload for import UI (plan D: ImportProgress). */
export interface ImportProgress {
  phase: string;
  done: number;
  total: number;
  currentName: string;
}

export function makeImportProgress(phase: string, done: number, total: number, currentName: string): ImportProgress {
  const p: ImportProgress = { phase: phase, done: done, total: total, currentName: currentName };
  return p;
}

/** A skipped archive with its readable failure reason (US-2 场景 6). */
export class ImportFailure {
  readonly name: string;
  readonly reason: string;

  constructor(name: string, reason: string) {
    this.name = name;
    this.reason = reason;
  }
}

/** Result of a multi-archive import run. */
export class ImportArchivesResult {
  imported: Array<Manga> = [];
  failures: Array<ImportFailure> = [];
  cancelled: boolean = false;
}

/** 暂存导入的一页（向导预览用，尚未落库）。 */
export class StagedPage {
  readonly path: string;
  readonly label: string;

  constructor(path: string, label: string) {
    this.path = path;
    this.label = label;
  }
}

/** 一次暂存导入的上下文：向导确认后 commit，取消时 discard。 */
export class StagedManga {
  name: string = '';
  sourceType: SourceType = SourceType.ARCHIVE;
  sourceUri: string | undefined = undefined;
  pages: Array<StagedPage> = [];
  /** 解压/复制暂存目录；目录源与相册源为 undefined。 */
  tempDir: string | undefined = undefined;
}

/**
 * 三通道导入服务（T016 / plan D10 / stage-2 S102）：
 * - zip/cbz：DocumentViewPicker(FILE) URI → 拷入沙箱 → zlib.decompressFile
 *   → 递归过滤图片 → naturalSort 定页序 → 归一化迁移到 files/manga/<id>/
 * - 目录：persistPermission → URI 原位扫描（不入沙箱）→ sourceUri 建档
 * - 相册：PhotoViewPicker URI（≤500）→ 复制入沙箱
 * 进度回调 + 取消（临时物清理，不产生残缺记录）；损坏包跳过续处理。
 *
 * stage 系列与 commitStaged 为导入向导提供两段式：先暂存预览（可改名/选封面/调页序），
 * 确认后再落库迁移，保证「取消/返回」不产生残缺记录。
 */
export class ImportService {
  /** Root of per-manga sandbox files: <filesDir>/manga/<mangaId>/ */
  static mangaDir(mangaId: number): string {
    return `${AppEnv.getInstance().getContext().filesDir}/manga/${mangaId}`;
  }

  static async importArchives(uris: Array<string>, onProgress: (p: ImportProgress) => void,
    isCancelled: () => boolean): Promise<ImportArchivesResult> {
    const result = new ImportArchivesResult();
    for (let i = 0; i < uris.length; i++) {
      if (isCancelled()) {
        result.cancelled = true;
        break;
      }
      const uri = uris[i];
      const name = ImportService.archiveDisplayName(uri);
      onProgress(makeImportProgress('解压', i, uris.length, name));
      try {
        const manga = await ImportService.importOneArchive(uri, name, onProgress, isCancelled);
        if (manga === undefined) {
          result.cancelled = true;
          break;
        }
        result.imported.push(manga);
      } catch (e) {
        if (isCancelled()) {
          result.cancelled = true;
          break;
        }
        Log.warn(TAG, `archive ${name} failed: ${e}`);
        result.failures.push(new ImportFailure(name, ImportService.readableError(e)));
      }
    }
    return result;
  }

  /** 单包导入（向导外的直通路径）。取消时返回 undefined（暂存/临时记录已清理）。 */
  private static async importOneArchive(uri: string, name: string,
    onProgress: (p: ImportProgress) => void, isCancelled: () => boolean): Promise<Manga | undefined> {
    const staged = await ImportService.stageArchive(uri, onProgress, isCancelled);
    if (isCancelled()) {
      ImportService.discardStaged(staged);
      return undefined;
    }
    return await ImportService.commitStaged(staged, name, 0, onProgress, isCancelled);
  }

  // ---------------------------------------------------------------------
  // 两段式：stage（暂存）→ commit（落库）
  // ---------------------------------------------------------------------

  /** 解压 zip/cbz 到缓存暂存目录（不落库，可预览/取消）。 */
  static async stageArchive(uri: string, onProgress: (p: ImportProgress) => void,
    isCancelled: () => boolean): Promise<StagedManga> {
    const ctx = AppEnv.getInstance().getContext();
    const name = ImportService.archiveDisplayName(uri);
    const tempDir = `${ctx.cacheDir}/wizard/${Date.now()}-${Math.floor(Math.random() * 10000)}`;
    let keepTempDir = false;
    try {
      fs.mkdirSync(tempDir, true);
      const zipPath = `${tempDir}/src.zip`;
      onProgress(makeImportProgress('解压', 0, 0, name));
      // zlib.decompressFile 只接受沙箱路径：先把 Picker URI 拷进来。
      ImportService.copyUriToFile(uri, zipPath);
      const outDir = `${tempDir}/out`;
      fs.mkdirSync(outDir, true);
      await zlib.decompressFile(zipPath, outDir);
      if (isCancelled()) {
        throw new Error('已取消导入');
      }
      const imagePaths = ImportService.listImagesRecursive(outDir);
      if (imagePaths.length === 0) {
        throw new Error('压缩包内没有图片');
      }
      const sorted = naturalSort(imagePaths);
      onProgress(makeImportProgress('准备页面', sorted.length, sorted.length, name));
      const staged = new StagedManga();
      staged.name = name;
      staged.sourceType = SourceType.ARCHIVE;
      staged.tempDir = tempDir;
      staged.pages = ImportService.makeStagedPages(sorted);
      keepTempDir = true;
      return staged;
    } finally {
      if (!keepTempDir) {
        ImportService.rmRecursive(tempDir);
      }
    }
  }

  /** 扫描图片目录（持久化授权，原位读取不入沙箱）。 */
  static async stageDirectory(uri: string): Promise<StagedManga> {
    const dirUri = uri.endsWith('/') ? uri.substring(0, uri.length - 1) : uri;
    try {
      const policy: fileShare.PolicyInfo = {
        uri: dirUri,
        operationMode: fileShare.OperationMode.READ_MODE
      };
      await fileShare.persistPermission([policy]);
    } catch (e) {
      Log.warn(TAG, `persistPermission failed: ${e}`);
      // Non-fatal: this session still has temp grant; rescan may fail later.
    }
    const imagePaths = ImportService.listImagesRecursive(dirUri);
    if (imagePaths.length === 0) {
      throw new Error('目录内没有图片');
    }
    const sorted = naturalSort(imagePaths);
    const staged = new StagedManga();
    staged.name = ImportService.lastSegment(dirUri);
    staged.sourceType = SourceType.DIRECTORY;
    staged.sourceUri = dirUri;
    staged.pages = ImportService.makeStagedPages(sorted);
    return staged;
  }

  /** 相册多选暂存（≤500，确认后才复制进沙箱）。 */
  static async stagePhotos(uris: Array<string>, onProgress: (p: ImportProgress) => void): Promise<StagedManga> {
    const limited = uris.length > ALBUM_MAX ? uris.slice(0, ALBUM_MAX) : uris;
    if (limited.length === 0) {
      throw new Error('未选择任何图片');
    }
    onProgress(makeImportProgress('准备', limited.length, limited.length, ''));
    const staged = new StagedManga();
    staged.name = `相册导入 ${ImportService.shortDate(Date.now())}`;
    staged.sourceType = SourceType.ALBUM;
    staged.pages = ImportService.makeStagedPages(limited);
    return staged;
  }

  /**
   * 确认暂存导入：按最终名称/页序/封面建档并把页文件迁入沙箱。
   * 目录源原位读取不复制；压缩包源从缓存目录 move；相册源复制（≤500）。
   */
  static async commitStaged(staged: StagedManga, name: string, coverIndex: number,
    onProgress?: (p: ImportProgress) => void, isCancelled?: () => boolean): Promise<Manga> {
    const pageCount = staged.pages.length;
    if (pageCount === 0) {
      throw new Error('没有可导入的图片');
    }
    const finalName = name.trim().length > 0 ? name.trim() : staged.name;
    const shell = await MangaRepository.createMangaShell(finalName, staged.sourceType, staged.sourceUri, pageCount);
    const destDir = ImportService.mangaDir(shell.id);
    const finalPaths: Array<string> = [];
    let createdDir = false;
    try {
      if (staged.sourceType === SourceType.DIRECTORY) {
        for (const p of staged.pages) {
          finalPaths.push(p.path);
        }
      } else {
        fs.mkdirSync(destDir, true);
        createdDir = true;
        for (let i = 0; i < pageCount; i++) {
          if (isCancelled !== undefined && isCancelled()) {
            throw new Error('已取消导入');
          }
          const srcPath = staged.pages[i].path;
          const ext = ImportService.extOf(srcPath);
          const destPath = `${destDir}/page-${ImportService.pad4(i)}${ext}`;
          if (staged.sourceType === SourceType.ALBUM) {
            ImportService.copyUriToFile(srcPath, destPath);
          } else {
            ImportService.moveOrCopy(srcPath, destPath);
          }
          finalPaths.push(destPath);
          if (onProgress !== undefined) {
            onProgress(makeImportProgress(staged.sourceType === SourceType.ALBUM ? '复制' : '整理',
              i + 1, pageCount, staged.pages[i].label));
          }
        }
      }
      await MangaRepository.replacePages(shell, finalPaths);
      const safeCover = coverIndex >= 0 && coverIndex < finalPaths.length ? coverIndex : 0;
      shell.coverPath = finalPaths[safeCover];
      await MangaDao.update(shell);
      ImportService.discardStaged(staged);
      Log.info(TAG, `staged import committed: id=${shell.id}, pages=${finalPaths.length}`);
      return shell;
    } catch (e) {
      if (createdDir) {
        ImportService.rmRecursive(destDir);
      }
      try {
        await MangaRepository.deleteCascade(shell.id);
      } catch (e2) {
        Log.warn(TAG, `rollback manga ${shell.id} failed: ${e2}`);
      }
      ImportService.discardStaged(staged);
      const err = e as BusinessError;
      const msg = err.message !== undefined && err.message.length > 0 ? err.message : String(e);
      throw new Error(msg);
    }
  }

  /** 丢弃暂存（删除缓存临时目录；幂等）。 */
  static discardStaged(staged: StagedManga): void {
    if (staged.tempDir !== undefined) {
      ImportService.rmRecursive(staged.tempDir);
      staged.tempDir = undefined;
    }
  }

  /**
   * Directory import: persist READ permission, scan images in place
   * (原位读取不入沙箱), record source_uri (plan D10 / P0-2).
   */
  static async importDirectory(uri: string): Promise<Manga> {
    const staged = await ImportService.stageDirectory(uri);
    return await ImportService.commitStaged(staged, staged.name, 0);
  }

  /** Album import: copy ≤500 picked photos into the sandbox (场景 5). */
  static async importPhotos(uris: Array<string>, onProgress: (p: ImportProgress) => void,
    isCancelled?: () => boolean): Promise<Manga> {
    const staged = await ImportService.stagePhotos(uris, onProgress);
    return await ImportService.commitStaged(staged, staged.name, 0, onProgress, isCancelled);
  }

  /**
   * Rescan a DIRECTORY manga without re-auth (P0-2 关键验收 SC-003).
   * Throws a readable error when the persisted grant has been revoked.
   */
  static async rescanDirectory(mangaId: number): Promise<Manga> {
    const manga = await MangaRepository.getById(mangaId);
    if (manga === undefined) {
      throw new Error('漫画记录不存在');
    }
    if (manga.sourceType !== SourceType.DIRECTORY || manga.sourceUri === undefined) {
      throw new Error('该漫画不是目录来源，无法重扫');
    }
    const imagePaths = ImportService.listImagesRecursive(manga.sourceUri);
    const sorted = naturalSort(imagePaths);
    if (sorted.length === 0) {
      throw new Error('目录内没有图片');
    }
    await MangaRepository.replacePages(manga, sorted);
    return manga;
  }

  /** Grant-health probe (R10): true when the persisted grant still works. */
  static async probeDirectoryAuth(mangaId: number): Promise<boolean> {
    const manga = await MangaRepository.getById(mangaId);
    if (manga === undefined || manga.sourceType !== SourceType.DIRECTORY || manga.sourceUri === undefined) {
      return false;
    }
    try {
      const policy: fileShare.PolicyInfo = {
        uri: manga.sourceUri,
        operationMode: fileShare.OperationMode.READ_MODE
      };
      const persisted = await fileShare.checkPersistentPermission([policy]);
      if (persisted.length > 0 && !persisted[0]) {
        return false;
      }
    } catch (e) {
      Log.warn(TAG, `checkPersistentPermission unsupported/failed: ${e}`);
      // API-dependent; fall through to the access probe below.
    }
    try {
      fs.listFileSync(manga.sourceUri);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 删除目录源漫画时取消持久化授权（尽力而为，失败不阻断删除）。 */
  static async releaseDirectoryPermission(uri: string | undefined): Promise<void> {
    if (uri === undefined || uri.length === 0) {
      return;
    }
    try {
      const policy: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE
      };
      await fileShare.revokePermission([policy]);
    } catch (e) {
      Log.warn(TAG, `revokePermission failed: ${e}`);
    }
  }

  // ---------- helpers ----------

  /** Copy a (picker) URI into a sandbox path via fd (fs.open supports URIs). */
  static copyUriToFile(uri: string, destPath: string): void {
    const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      fs.copyFileSync(src.fd, destPath);
    } finally {
      fs.closeSync(src);
    }
  }

  /** 同盘 move，跨盘/异常时退化为 copy（用于压缩包暂存 → 沙箱）。 */
  static moveOrCopy(srcPath: string, destPath: string): void {
    try {
      fs.renameSync(srcPath, destPath);
    } catch (e) {
      Log.warn(TAG, `rename ${srcPath} failed, fallback to copy: ${e}`);
      ImportService.copyUriToFile(srcPath, destPath);
    }
  }

  private static makeStagedPages(paths: Array<string>): Array<StagedPage> {
    const pages: Array<StagedPage> = [];
    for (const p of paths) {
      pages.push(new StagedPage(p, ImportService.lastSegment(p)));
    }
    return pages;
  }

  /**
   * Recursively list image files. For sandbox paths returns full paths;
   * for directory URIs returns relative paths ('/sub/a.jpg') to be joined
   * by the caller (listFile URI behavior is validated on device by P0-2).
   */
  static listImagesRecursive(dir: string): Array<string> {
    let names: Array<string> = [];
    try {
      names = fs.listFileSync(dir, { recursion: true });
    } catch (e) {
      throw new Error(`无法读取目录（授权可能已失效）：${ImportService.readableError(e)}`);
    }
    const out: Array<string> = [];
    for (const n of names) {
      const lower = n.toLowerCase();
      for (const ext of IMAGE_EXTS) {
        if (lower.endsWith(ext)) {
          out.push(ImportService.joinDirPath(dir, n));
          break;
        }
      }
    }
    return out;
  }

  /**
   * 把 listFileSync 的返回项拼成可访问路径。
   * recursion=true 时接口返回以 '/' 开头的相对路径（如 '/sub/a.jpg'），
   * 非递归时返回纯文件名；个别实现会直接返回绝对路径，此时原样使用。
   */
  static joinDirPath(dir: string, name: string): string {
    if (name.startsWith(dir)) {
      return name;
    }
    const base = dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir;
    if (name.startsWith('/')) {
      return `${base}${name}`;
    }
    return `${base}/${name}`;
  }

  /** Manual recursive delete (SDK rmdir is not recursive). */
  static rmRecursive(path: string): void {
    let isDir = false;
    try {
      const stat = fs.statSync(path);
      isDir = stat.isDirectory();
    } catch (e) {
      return; // already gone
    }
    if (!isDir) {
      try {
        fs.unlinkSync(path);
      } catch (e) {
        Log.warn(TAG, `unlink ${path} failed: ${e}`);
      }
      return;
    }
    try {
      const children = fs.listFileSync(path);
      for (const child of children) {
        ImportService.rmRecursive(`${path}/${child}`);
      }
      fs.rmdirSync(path);
    } catch (e) {
      Log.warn(TAG, `rmdir ${path} failed: ${e}`);
    }
  }

  static extOf(path: string): string {
    const idx = path.lastIndexOf('.');
    if (idx < 0) {
      return '.jpg';
    }
    const ext = path.substring(idx).toLowerCase();
    for (const e of IMAGE_EXTS) {
      if (e === ext) {
        return ext;
      }
    }
    return ext;
  }

  static archiveDisplayName(uri: string): string {
    const seg = ImportService.lastSegment(uri);
    if (seg.length === 0) {
      return `压缩包-${ImportService.shortDate(Date.now())}`;
    }
    const dot = seg.lastIndexOf('.');
    if (dot > 0 && (seg.toLowerCase().endsWith('.zip') || seg.toLowerCase().endsWith('.cbz'))) {
      return seg.substring(0, dot);
    }
    return seg;
  }

  static lastSegment(uri: string): string {
    const trimmed = uri.endsWith('/') ? uri.substring(0, uri.length - 1) : uri;
    const idx = trimmed.lastIndexOf('/');
    if (idx < 0) {
      return trimmed;
    }
    let seg = trimmed.substring(idx + 1);
    try {
      seg = decodeURIComponent(seg);
    } catch (e) {
      // keep raw segment when it is not URI encoded
    }
    return seg;
  }

  private static pad4(n: number): string {
    if (n < 10) {
      return `000${n}`;
    }
    if (n < 100) {
      return `00${n}`;
    }
    if (n < 1000) {
      return `0${n}`;
    }
    return `${n}`;
  }

  private static shortDate(ts: number): string {
    const d = new Date(ts);
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getMonth() + 1}${pad(d.getDate())} ${pad(d.getHours())}${pad(d.getMinutes())}`;
  }

  private static readableError(e: Object): string {
    const err = e as BusinessError;
    if (err.code === 9000003) {
      return '压缩包损坏或不是有效的 zip 格式';
    }
    if (err.code === 13900002) {
      return '文件或目录不存在';
    }
    if (err.code === 13900012) {
      return '没有访问权限（授权可能已失效）';
    }
    if (err.code === 13900020) {
      return '参数无效';
    }
    if (err.code === 13900025) {
      return '存储空间不足';
    }
    if (err.message !== undefined && err.message.length > 0) {
      return err.message;
    }
    return '未知错误';
  }
}
