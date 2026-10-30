import fs from '@ohos.file.fs';
import { picker } from '@kit.CoreFileKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { Novel, TranslateStatus } from 'coremodel';
import { ParsedNovel, TxtParser, TxtParseResult, EpubParser, ZipHtmlParser } from 'corenovel';
import { Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { NovelRepository } from '../data/NovelRepository';

const TAG = 'NovelImportService';
const SUPPORTED_EXTS: Array<string> = ['.txt', '.epub', '.zip'];
const MAX_TXT_BYTES: number = 100 * 1024 * 1024;

/** 导入进度载荷。 */
export class NovelImportProgress {
  phase: string = '';
  done: number = 0;
  total: number = 0;
  currentName: string = '';
}

export function makeNovelProgress(phase: string, done: number, total: number,
  currentName: string): NovelImportProgress {
  const p = new NovelImportProgress();
  p.phase = phase;
  p.done = done;
  p.total = total;
  p.currentName = currentName;
  return p;
}

/** 单本导入失败（给用户可读原因）。 */
export class NovelImportFailure {
  name: string = '';
  reason: string = '';
}

export function makeNovelFailure(name: string, reason: string): NovelImportFailure {
  const f = new NovelImportFailure();
  f.name = name;
  f.reason = reason;
  return f;
}

/** 一批导入结果。 */
export class NovelImportResult {
  imported: Array<Novel> = [];
  failures: Array<NovelImportFailure> = [];
  warnings: Array<string> = [];
  cancelled: boolean = false;
}

/** 解析中间产物（携带编码告警）。 */
class NovelParseOutcome {
  novel: ParsedNovel = { title: '', format: 0, chapters: [], plainText: '', author: '' };
  lossy: boolean = false;
  encoding: string = 'utf-8';
}

/**
 * 小说导入服务（对齐上游 novel/data/NovelImportManager）：
 * - 文件通道：DocumentViewPicker(FILE) 多选 txt/epub/zip-html；
 * - 目录通道：DocumentViewPicker(FOLDER)，目录内每个支持的文件各建一本；
 * - 流程：拷入缓存 → 格式嗅探（PK 头/扩展名）→ 解压/解析 → 编码探测 → 分章 →
 *   Novel + NovelChapter 建档 → 源文件归档到沙箱 → 清理临时目录；
 * - 支持进度回调与取消；取消/失败不留残缺记录；损坏包给出可读失败原因。
 */
export class NovelImportService {
  /** 打开文件选择器（txt/epub/zip 可多选）。 */
  static async pickFiles(): Promise<Array<string>> {
    const docPicker = new picker.DocumentViewPicker();
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 50;
    opts.fileSuffixFilters = ['小说文件 (.txt, .epub, .zip)|.txt,.epub,.zip'];
    opts.selectMode = picker.DocumentSelectMode.FILE;
    return docPicker.select(opts);
  }

  /** 打开目录选择器。 */
  static async pickFolder(): Promise<Array<string>> {
    const docPicker = new picker.DocumentViewPicker();
    const opts = new picker.DocumentSelectOptions();
    opts.selectMode = picker.DocumentSelectMode.FOLDER;
    opts.maxSelectNumber = 1;
    return docPicker.select(opts);
  }

  /** 多文件导入（每个文件一本）。 */
  static async importFiles(uris: Array<string>, onProgress: (p: NovelImportProgress) => void,
    isCancelled: () => boolean): Promise<NovelImportResult> {
    const result = new NovelImportResult();
    for (let i = 0; i < uris.length; i++) {
      if (isCancelled()) {
        result.cancelled = true;
        break;
      }
      const name = NovelImportService.displayName(uris[i]);
      onProgress(makeNovelProgress('准备', i, uris.length, name));
      try {
        const novel = await NovelImportService.importOne(uris[i], name, onProgress, isCancelled,
          result.warnings);
        if (novel === undefined) {
          result.cancelled = true;
          break;
        }
        result.imported.push(novel);
      } catch (e) {
        Log.warn(TAG, 'import ' + name + ' failed: ' + e);
        result.failures.push(makeNovelFailure(name, NovelImportService.readableError(e)));
      }
    }
    return result;
  }

  /** 目录导入：目录内每个 txt/epub/zip 各建一本。 */
  static async importFolder(uri: string, onProgress: (p: NovelImportProgress) => void,
    isCancelled: () => boolean): Promise<NovelImportResult> {
    const result = new NovelImportResult();
    const dir = uri.endsWith('/') ? uri.substring(0, uri.length - 1) : uri;
    let files: Array<string> = [];
    try {
      files = NovelImportService.listNovelFiles(dir);
    } catch (e) {
      result.failures.push(makeNovelFailure(NovelImportService.lastSegment(dir),
        '无法读取目录（授权可能已失效）'));
      return result;
    }
    if (files.length === 0) {
      result.failures.push(makeNovelFailure(NovelImportService.lastSegment(dir),
        '目录内没有 txt / epub / zip 小说文件'));
      return result;
    }
    for (let i = 0; i < files.length; i++) {
      if (isCancelled()) {
        result.cancelled = true;
        break;
      }
      const filePath = files[i];
      const name = NovelImportService.lastSegment(filePath);
      onProgress(makeNovelProgress('目录导入', i, files.length, name));
      try {
        const novel = await NovelImportService.importOne(filePath, name, onProgress, isCancelled,
          result.warnings);
        if (novel === undefined) {
          result.cancelled = true;
          break;
        }
        result.imported.push(novel);
      } catch (e) {
        Log.warn(TAG, 'folder import ' + name + ' failed: ' + e);
        result.failures.push(makeNovelFailure(name, NovelImportService.readableError(e)));
      }
    }
    return result;
  }

  // ---------- 单本导入 ----------

  /** 返回 undefined 表示中途取消（不留残缺记录）。 */
  private static async importOne(uri: string, displayName: string,
    onProgress: (p: NovelImportProgress) => void, isCancelled: () => boolean,
    warnings: Array<string>): Promise<Novel | undefined> {
    const cacheDir = AppEnv.getInstance().getContext().cacheDir;
    const tmpDir = cacheDir + '/novel_import/' + Date.now() + '-' + Math.floor(Math.random() * 10000);
    const baseName = NovelImportService.stripExt(displayName);
    let novel: Novel | undefined = undefined;
    try {
      fs.mkdirSync(tmpDir, true);
      const ext = NovelImportService.extOf(displayName);
      const tempPath = tmpDir + '/source' + (ext.length > 0 ? ext : '.bin');
      onProgress(makeNovelProgress('复制', 0, 1, displayName));
      NovelImportService.copyUriToFile(uri, tempPath);
      if (isCancelled()) {
        return undefined;
      }
      onProgress(makeNovelProgress('解析', 0, 1, displayName));
      const outcome = await NovelImportService.parseFile(tempPath, baseName, ext, tmpDir);
      if (isCancelled()) {
        return undefined;
      }
      // 编码提示：「失败尝试 GBK 近似/替换并提示」——非 UTF-8 或存在替换符时告知用户。
      const encodingLabel = NovelImportService.encodingLabel(outcome.encoding);
      if (outcome.lossy) {
        warnings.push('「' + displayName + '」编码无法完整识别，已按 ' + encodingLabel
          + ' 近似解码，可能出现替换字符');
      } else if (outcome.encoding !== 'utf-8' && outcome.encoding.length > 0) {
        warnings.push('「' + displayName + '」已按 ' + encodingLabel + ' 解码');
      }
      if (outcome.novel.chapters.length === 0) {
        throw new Error('没有可读文本章节');
      }
      const coverPath = NovelImportService.coverNameFor(baseName);
      novel = await NovelRepository.createFromParsed(outcome.novel, '', coverPath);
      if (isCancelled()) {
        await NovelRepository.deleteCascade([novel.id]);
        return undefined;
      }
      const finalSource = await NovelRepository.placeSource(novel.id, tempPath, ext.length > 0 ? ext : '.bin');
      if (finalSource.length > 0) {
        novel.sourceUri = finalSource;
        await NovelRepository.updateSourceUri(novel.id, finalSource);
      }
      onProgress(makeNovelProgress('完成', outcome.novel.chapters.length,
        outcome.novel.chapters.length, novel.name));
      return novel;
    } finally {
      NovelRepository.rmDir(tmpDir);
    }
  }

  /** 嗅探格式并解析。 */
  private static async parseFile(tempPath: string, title: string, ext: string,
    tmpDir: string): Promise<NovelParseOutcome> {
    const outcome = new NovelParseOutcome();
    const head = NovelImportService.readHead(tempPath, 8);
    const isZip = head.length >= 4 && head[0] === 0x50 && head[1] === 0x4B;
    if (isZip || ext === '.zip' || ext === '.epub') {
      if (!isZip) {
        throw new Error('文件不是有效的 ZIP/EPUB 压缩包（可能已损坏）');
      }
      const unzipDir = tmpDir + '/unzip';
      fs.mkdirSync(unzipDir, true);
      await zlib.decompressFile(tempPath, unzipDir);
      if (NovelImportService.exists(unzipDir + '/META-INF/container.xml')) {
        outcome.novel = EpubParser.parse(unzipDir, title);
      } else {
        outcome.novel = ZipHtmlParser.parse(unzipDir, title);
      }
      return outcome;
    }
    // 非压缩包：按 TXT 解码（编码探测在 TxtParser 内部）。
    const size = fs.statSync(tempPath).size;
    if (size > MAX_TXT_BYTES) {
      throw new Error('文件太大（超过 100MB），无法导入');
    }
    const bytes = NovelImportService.readAll(tempPath, size);
    const parsed: TxtParseResult = TxtParser.parse(bytes, title);
    outcome.novel = parsed.novel;
    outcome.lossy = parsed.lossy;
    outcome.encoding = parsed.encoding;
    return outcome;
  }

  // ---------- 文件工具 ----------

  /** 拷贝选择器 URI 到沙箱路径。 */
  static copyUriToFile(uri: string, destPath: string): void {
    const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      fs.copyFileSync(src.fd, destPath);
    } finally {
      fs.closeSync(src);
    }
  }

  static readAll(path: string, size: number): Uint8Array {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(size);
      let read = 0;
      while (read < size) {
        const n = fs.readSync(file.fd, buffer, { offset: read, length: size - read });
        if (n <= 0) {
          break;
        }
        read += n;
      }
      return new Uint8Array(buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  static readHead(path: string, count: number): Uint8Array {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(count);
      const read = fs.readSync(file.fd, buffer, { offset: 0, length: count });
      const view = new Uint8Array(buffer);
      return read === count ? view : view.slice(0, read);
    } finally {
      fs.closeSync(file);
    }
  }

  static exists(path: string): boolean {
    try {
      fs.accessSync(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 列出目录内的支持文件（先直接子项，没有则递归）。 */
  static listNovelFiles(dir: string): Array<string> {
    const out: Array<string> = [];
    let names: Array<string> = [];
    try {
      names = fs.listFileSync(dir);
    } catch (e) {
      throw new Error('无法读取目录（授权可能已失效）');
    }
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      const ext = NovelImportService.extOf(name);
      if (SUPPORTED_EXTS.indexOf(ext) >= 0) {
        out.push(dir + '/' + name);
      }
    }
    if (out.length > 0) {
      return out;
    }
    let recursiveNames: Array<string> = [];
    try {
      recursiveNames = fs.listFileSync(dir, { recursion: true });
    } catch (e) {
      return out;
    }
    for (let i = 0; i < recursiveNames.length; i++) {
      const rel = recursiveNames[i];
      const ext = NovelImportService.extOf(rel);
      if (SUPPORTED_EXTS.indexOf(ext) >= 0) {
        const full = rel.startsWith('/') ? dir + rel : dir + '/' + rel;
        out.push(full);
      }
    }
    return out;
  }

  static extOf(name: string): string {
    const cleaned = NovelImportService.stripFragment(name);
    const idx = cleaned.lastIndexOf('.');
    if (idx < 0) {
      return '';
    }
    return cleaned.substring(idx).toLowerCase();
  }

  static stripExt(name: string): string {
    const cleaned = NovelImportService.stripFragment(name);
    const idx = cleaned.lastIndexOf('.');
    if (idx <= 0) {
      return cleaned;
    }
    return cleaned.substring(0, idx);
  }

  static displayName(uri: string): string {
    return NovelImportService.lastSegment(uri);
  }

  static lastSegment(uri: string): string {
    let trimmed = NovelImportService.stripFragment(uri);
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    const idx = trimmed.lastIndexOf('/');
    const name = idx < 0 ? trimmed : trimmed.substring(idx + 1);
    try {
      return decodeURIComponent(name);
    } catch (e) {
      return name;
    }
  }

  private static stripFragment(uri: string): string {
    const hash = uri.indexOf('#');
    return hash < 0 ? uri : uri.substring(0, hash);
  }

  /**
   * 封面占位资源名。art-dev 提供 cover_placeholder_2/3 SVG 后由书架按名引用；
   * 未提供时返回空串，书架自绘紫色占位封面。
   */
  private static coverNameFor(title: string): string {
    if (NovelImportService.coverResourcesReady) {
      let sum = 0;
      for (let i = 0; i < title.length; i++) {
        sum += title.charCodeAt(i);
      }
      return sum % 2 === 0 ? 'cover_placeholder_2' : 'cover_placeholder_3';
    }
    return '';
  }

  /** art-dev 已提供 cover_placeholder_1..4 SVG（novel/NovelUi.ets 按资源名渲染）。 */
  static coverResourcesReady: boolean = true;

  private static encodingLabel(encoding: string): string {
    if (encoding === 'gb18030') {
      return 'GBK/GB18030';
    }
    if (encoding === 'big5') {
      return 'Big5';
    }
    if (encoding === 'utf-16le' || encoding === 'utf-16be') {
      return encoding.toUpperCase();
    }
    if (encoding.length === 0) {
      return 'UTF-8';
    }
    return encoding.toUpperCase();
  }

  private static readableError(e: Object): string {
    const err = e as BusinessError;
    if (err !== undefined && err !== null) {
      if (err.code === 9000003) {
        return '压缩包损坏或不是有效的 zip 格式';
      }
      if (err.code === 13900002) {
        return '文件或目录不存在';
      }
      if (err.code === 13900012) {
        return '没有访问权限（授权可能已失效）';
      }
      if (err.code === 13900025) {
        return '存储空间不足';
      }
      if (err.message !== undefined && err.message.length > 0) {
        return err.message;
      }
    }
    const plain = e as Error;
    if (plain !== undefined && plain !== null && plain.message !== undefined
      && plain.message.length > 0) {
      return plain.message;
    }
    return '导入失败（未知错误）';
  }
}
