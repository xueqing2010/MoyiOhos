import fs from '@ohos.file.fs';
import { picker } from '@kit.CoreFileKit';
import { Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { ExportMode, ExportResult, ExportService } from './ExportService';
import { HistoryGroup, HistoryItem, HistoryService } from './HistoryService';

const TAG = 'HistoryExportService';

/** 历史导出结果（与 ExportService.ExportResult 对齐，增加 txt 场景字段）。 */
export class HistoryExportResult {
  uri: string = '';
  exported: number = 0;
  untranslated: number = 0;
  cancelled: boolean = false;
  fileName: string = '';
}

/**
 * 历史分组导出服务（task-6）：
 * - 漫画进程组：只读复用 ExportService.export(mangaId, mode, onProgress)，
 *   内部已 zlib.compressFile + 保存选择器 + 清理暂存，取消不留残缺 ZIP；
 * - 小说进程组：导出 txt（章节原文 + 译文对照）；
 * - 文本会话组：导出 txt（原文 + 译文）。
 * txt 先写 cache 暂存，DocumentViewPicker 选择位置后拷贝，finally 清理暂存；
 * 选择器取消时直接返回 cancelled，不产生任何目标文件。
 */
export class HistoryExportService {
  /** 漫画进程组导出 ZIP（复用 reader-dev 的 ExportService，只读调用）。 */
  static async exportMangaGroup(mangaId: number, mode: ExportMode,
    onProgress?: (done: number, total: number) => void): Promise<HistoryExportResult> {
    const result = new HistoryExportResult();
    const progress: (done: number, total: number) => void = onProgress === undefined
      ? (done: number, total: number): void => {
      }
      : onProgress;
    const exported: ExportResult = await ExportService.export(mangaId, mode, progress);
    result.uri = exported.uri;
    result.exported = exported.exported;
    result.untranslated = exported.untranslated;
    result.cancelled = exported.cancelled;
    return result;
  }

  /** 小说进程组导出 txt（原文 + 译文对照）。 */
  static async exportNovelGroup(novelId: number,
    onProgress?: (done: number, total: number) => void): Promise<HistoryExportResult> {
    await AppEnv.ready();
    const group: HistoryGroup | undefined =
      await HistoryService.loadGroup(HistoryService.novelGroupKey(novelId));
    if (group === undefined || group.items.length === 0) {
      throw new Error('该小说还没有已翻译章节');
    }
    HistoryExportService.notify(onProgress, 1, 1);
    const content = HistoryExportService.buildNovelText(group);
    const fileName = HistoryExportService.safeName('墨译-小说-' + group.title) + '.txt';
    const result = await HistoryExportService.saveTextFile(fileName, content);
    result.exported = group.items.length;
    result.fileName = fileName;
    return result;
  }

  /** 文本会话组导出 txt（原文 + 译文）。 */
  static async exportTextGroup(groupKey: string,
    onProgress?: (done: number, total: number) => void): Promise<HistoryExportResult> {
    await AppEnv.ready();
    const group: HistoryGroup | undefined = await HistoryService.loadGroup(groupKey);
    if (group === undefined || group.items.length === 0) {
      throw new Error('该组没有可导出的文本记录');
    }
    HistoryExportService.notify(onProgress, 1, 1);
    const content = HistoryExportService.buildTextsText(group);
    const fileName = HistoryExportService.safeName('墨译-文本-' + HistoryService.dayKey(group.latestTime)) + '.txt';
    const result = await HistoryExportService.saveTextFile(fileName, content);
    result.exported = group.items.length;
    result.fileName = fileName;
    return result;
  }

  // -------------------------------------------------------------------------
  // 文本内容构建
  // -------------------------------------------------------------------------

  private static buildNovelText(group: HistoryGroup): string {
    let text = '墨译 · 小说翻译历史导出\n';
    text += '书名：' + group.title + '\n';
    text += '导出时间：' + HistoryService.formatDateTime(Date.now()) + '\n';
    text += '章节数：' + group.items.length + ' 章\n';
    text += '========================================\n\n';
    for (const item of group.items) {
      text += HistoryExportService.buildChapterBlock(item);
    }
    return text;
  }

  private static buildChapterBlock(item: HistoryItem): string {
    const chapterLabel = '第 ' + (item.chapterIndex + 1) + ' 章' +
      (item.chapterTitle.length > 0 ? '　' + item.chapterTitle : '');
    let block = '【' + chapterLabel + '】\n\n';
    block += '【原文】\n' + (item.contentOriginal.length > 0 ? item.contentOriginal : '（章节原文缺失）') + '\n\n';
    block += '【译文】\n' + (item.contentTranslated.length > 0
      ? item.contentTranslated : '（本章暂无译文）') + '\n\n';
    block += '----------------------------------------\n\n';
    return block;
  }

  private static buildTextsText(group: HistoryGroup): string {
    let text = '墨译 · 文本翻译历史导出\n';
    text += '导出时间：' + HistoryService.formatDateTime(Date.now()) + '\n';
    text += '记录数：' + group.items.length + ' 条\n';
    text += '========================================\n\n';
    for (const item of group.items) {
      text += '[' + HistoryService.formatDateTime(item.time) + ']\n';
      text += '【原文】\n' + (item.contentOriginal.length > 0 ? item.contentOriginal : '（空）') + '\n\n';
      text += '【译文】\n' + (item.contentTranslated.length > 0 ? item.contentTranslated : '（空）') + '\n\n';
      text += '----------------------------------------\n\n';
    }
    return text;
  }

  // -------------------------------------------------------------------------
  // 文件保存
  // -------------------------------------------------------------------------

  private static async saveTextFile(fileName: string, content: string): Promise<HistoryExportResult> {
    const result = new HistoryExportResult();
    result.fileName = fileName;
    const cacheDir = AppEnv.getInstance().getContext().cacheDir;
    const stagingDir = cacheDir + '/history-export/' + Date.now();
    const stagingFile = stagingDir + '/' + fileName;
    fs.mkdirSync(stagingDir, true);
    try {
      HistoryExportService.writeText(stagingFile, content);
      const uri = await HistoryExportService.pickSave(fileName);
      if (uri.length === 0) {
        result.cancelled = true;
        return result;
      }
      try {
        HistoryExportService.copyToUri(stagingFile, uri);
      } catch (e) {
        // 目标写入失败时尽量回收残缺文件，保持“取消/失败不留残片”。
        try {
          fs.unlinkSync(uri);
        } catch (ignore) {
        }
        throw new Error('保存导出文件失败：' + HistoryExportService.readableError(e));
      }
      result.uri = uri;
      return result;
    } finally {
      HistoryExportService.rmRecursive(stagingDir);
    }
  }

  private static writeText(path: string, content: string): void {
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
  }

  private static async pickSave(fileName: string): Promise<string> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      const uris = await docPicker.save(options);
      if (uris === undefined || uris.length === 0) {
        return '';
      }
      return uris[0];
    } catch (e) {
      Log.warn(TAG, 'picker save failed: ' + HistoryExportService.readableError(e));
      return '';
    }
  }

  private static copyToUri(src: string, uri: string): void {
    const dest = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.copyFileSync(src, dest.fd);
    } finally {
      fs.closeSync(dest);
    }
  }

  private static rmRecursive(path: string): void {
    let isDir = false;
    try {
      isDir = fs.statSync(path).isDirectory();
    } catch (e) {
      return;
    }
    if (!isDir) {
      try {
        fs.unlinkSync(path);
      } catch (e) {
        Log.warn(TAG, 'unlink failed: ' + HistoryExportService.readableError(e));
      }
      return;
    }
    try {
      const children = fs.listFileSync(path);
      for (const child of children) {
        HistoryExportService.rmRecursive(path + '/' + child);
      }
      fs.rmdirSync(path);
    } catch (e) {
      Log.warn(TAG, 'rmdir failed: ' + HistoryExportService.readableError(e));
    }
  }

  private static notify(callback: ((done: number, total: number) => void) | undefined,
    done: number, total: number): void {
    if (callback !== undefined) {
      callback(done, total);
    }
  }

  private static safeName(raw: string): string {
    let name = raw;
    const illegal: Array<string> = ['/', '\\', ':', '*', '?', '"', '<', '>', '|', '\n', '\r', '\t'];
    for (const ch of illegal) {
      name = name.split(ch).join('_');
    }
    if (name.length > 48) {
      name = name.substring(0, 48);
    }
    return name;
  }

  private static readableError(e: Object): string {
    const err = e as Error;
    if (err !== undefined && err !== null && err.message !== undefined && err.message.length > 0) {
      return err.message;
    }
    return '未知错误';
  }
}
