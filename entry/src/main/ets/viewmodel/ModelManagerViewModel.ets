import fs from '@ohos.file.fs';
import statvfs from '@ohos.file.statvfs';
import { DownloadStatus, DownloadTask, makeDownloadTask } from 'coremodel';
import { ModelPreset, ModelPresets } from 'coretranslate';
import { AppEnv } from '../common/AppEnv';
import { DownloadRepository } from '../data/DownloadRepository';
import { DownloadProgress, DownloadService } from '../service/DownloadService';

/** Presentation projection of a model entry (preset or custom). */
export class ModelItem {
  modelKey: string = '';
  displayName: string = '';
  quant: string = '';
  sizeLabel: string = '';
  status: DownloadStatus = DownloadStatus.NOT_DOWNLOADED;
  progressPct: number = 0;
  speedLabel: string = '';
  supported: boolean = true;
  localPath: string = '';
  url: string = '';
  fileName: string = '';
  expectedMd5: string = '';
  sizeBytes: number = 0;
  isCustom: boolean = false;
  /** 是否内置预置模型（用于分组展示）。 */
  isPreset: boolean = false;
  /** 是否为「导入本地 GGUF」：删除时只移除记录，不删除原文件。 */
  isImported: boolean = false;
}

/** 模型存储统计（用于模型管理页顶部卡片）。 */
export class StorageStats {
  /** models 目录已占用字节。 */
  usedBytes: number = 0;
  /** filesDir 剩余空间字节（statvfs）。 */
  freeBytes: number = 0;
  /** models 目录文件数。 */
  fileCount: number = 0;
  /** download_task 中状态为已下载的数量。 */
  downloadedCount: number = 0;
}

/**
 * 模型管理 VM（S111 / US-9）：预置列表 + 自定义 URL + GGUF 导入 +
 * 存储统计；状态随 download_task 与运行时进度合并（1.25bit 标注暂不支持）。
 * 不修改 DownloadService / DownloadRepository 的 API，仅调用。
 */
export class ModelManagerViewModel {
  static async loadItems(): Promise<Array<ModelItem>> {
    await AppEnv.ready();
    const rows: Array<DownloadTask> = await DownloadRepository.listAll();
    const byKey = new Map<string, DownloadTask>();
    for (const r of rows) {
      byKey.set(r.modelKey, r);
    }
    const items: Array<ModelItem> = [];
    const seen = new Set<string>();
    for (const preset of ModelPresets.all()) {
      const item = ModelManagerViewModel.fromPreset(preset);
      const row = byKey.get(preset.modelKey);
      if (row !== undefined) {
        ModelManagerViewModel.mergeRow(item, row);
        seen.add(preset.modelKey);
      }
      const live = DownloadService.getInstance().getProgress(preset.modelKey);
      if (live !== undefined) {
        ModelManagerViewModel.applyLive(item, live);
      }
      items.push(item);
    }
    for (const row of rows) {
      if (seen.has(row.modelKey)) {
        continue;
      }
      const item = ModelManagerViewModel.fromRow(row);
      const live = DownloadService.getInstance().getProgress(row.modelKey);
      if (live !== undefined) {
        ModelManagerViewModel.applyLive(item, live);
      }
      items.push(item);
    }
    return items;
  }

  /** 只读统计 models 目录占用与剩余空间；失败回退 0，不抛错。 */
  static async loadStorageStats(): Promise<StorageStats> {
    const stats = new StorageStats();
    await AppEnv.ready();
    const dirs: Array<string> = [DownloadService.modelsDir(), DownloadService.cacheModelsDir()];
    for (const dir of dirs) {
      try {
        if (!fs.accessSync(dir)) {
          fs.mkdirSync(dir, true);
        }
        const names: Array<string> = fs.listFileSync(dir);
        for (const name of names) {
          try {
            const size: number = fs.statSync(`${dir}/${name}`).size;
            stats.usedBytes += size;
            stats.fileCount += 1;
          } catch (e) {
            // 单个文件读取失败跳过
          }
        }
      } catch (e) {
        // 目录不存在或不可读
      }
    }
    try {
      stats.freeBytes = await statvfs.getFreeSize(AppEnv.getInstance().getContext().filesDir);
    } catch (e) {
      stats.freeBytes = 0;
    }
    try {
      const rows: Array<DownloadTask> = await DownloadRepository.listAll();
      for (const r of rows) {
        if (r.status === DownloadStatus.DOWNLOADED) {
          stats.downloadedCount += 1;
        }
      }
    } catch (e) {
      stats.downloadedCount = 0;
    }
    return stats;
  }

  private static fromPreset(preset: ModelPreset): ModelItem {
    const item = new ModelItem();
    item.modelKey = preset.modelKey;
    item.displayName = preset.displayName;
    item.quant = preset.quant;
    item.sizeBytes = preset.sizeBytes;
    item.sizeLabel = ModelPresets.formatSize(preset.sizeBytes);
    item.supported = preset.supported;
    item.url = preset.url;
    item.expectedMd5 = preset.md5 ?? '';
    item.fileName = ModelManagerViewModel.fileNameOf(preset.url);
    item.status = preset.supported ? DownloadStatus.NOT_DOWNLOADED : DownloadStatus.UNSUPPORTED;
    item.isPreset = true;
    return item;
  }

  private static fromRow(row: DownloadTask): ModelItem {
    const item = new ModelItem();
    item.isCustom = true;
    ModelManagerViewModel.mergeRow(item, row);
    item.supported = true;
    // IMPORT_ 前缀（或“无下载 URL 且登记了本地路径”）视为导入模型：
    // 文件在用户目录，删除只移除记录（DownloadService 已同步改为不删外部文件）。
    item.isImported = row.modelKey.startsWith('IMPORT_')
      || (row.url.length === 0 && (row.localPath ?? '').length > 0);
    return item;
  }

  private static mergeRow(item: ModelItem, row: DownloadTask): void {
    item.modelKey = row.modelKey;
    if (row.displayName.length > 0) {
      item.displayName = row.displayName;
    }
    item.url = row.url;
    item.fileName = row.fileName;
    item.sizeBytes = row.totalBytes > 0 ? row.totalBytes : item.sizeBytes;
    if (item.sizeBytes > 0) {
      item.sizeLabel = ModelPresets.formatSize(item.sizeBytes);
    }
    item.expectedMd5 = row.expectedMd5 ?? '';
    item.localPath = row.localPath ?? '';
    item.status = row.status;
    if (row.totalBytes > 0 && row.downloadedBytes > 0) {
      item.progressPct = Math.min(100, Math.round(row.downloadedBytes * 100 / row.totalBytes));
    }
  }

  private static applyLive(item: ModelItem, live: DownloadProgress): void {
    item.status = live.status;
    if (live.totalBytes > 0) {
      item.progressPct = Math.min(100, Math.round(live.downloadedBytes * 100 / live.totalBytes));
    }
    item.speedLabel = ModelManagerViewModel.speedLabel(live.speedBps);
    if (live.localPath.length > 0) {
      item.localPath = live.localPath;
    }
  }

  /** 用运行时进度原地刷新列表项（不查库），返回是否有命中。 */
  static patchLive(items: Array<ModelItem>, p: DownloadProgress): boolean {
    let hit = false;
    for (const item of items) {
      if (item.modelKey !== p.modelKey) {
        continue;
      }
      hit = true;
      item.status = p.status;
      if (p.totalBytes > 0) {
        item.progressPct = Math.min(100, Math.round(p.downloadedBytes * 100 / p.totalBytes));
      }
      item.speedLabel = ModelManagerViewModel.speedLabel(p.speedBps);
      if (p.localPath.length > 0) {
        item.localPath = p.localPath;
      }
    }
    return hit;
  }

  private static speedLabel(speedBps: number): string {
    if (speedBps <= 0) {
      return '';
    }
    return `${ModelPresets.formatSize(speedBps)}/s`;
  }

  static async buildTask(item: ModelItem): Promise<DownloadTask> {
    const existing = await DownloadRepository.get(item.modelKey);
    if (existing !== undefined) {
      if (item.sizeBytes > 0 && existing.totalBytes <= 0) {
        existing.totalBytes = item.sizeBytes;
      }
      return existing;
    }
    const fileName = item.fileName.length > 0 ? item.fileName : ModelManagerViewModel.fileNameOf(item.url);
    const task = makeDownloadTask(item.modelKey, item.displayName, item.url, fileName);
    task.totalBytes = item.sizeBytes;
    if (item.expectedMd5.length > 0) {
      task.expectedMd5 = item.expectedMd5;
    }
    return task;
  }

  static async startDownload(item: ModelItem): Promise<void> {
    if (!item.supported) {
      throw new Error('该量化档本版暂不支持（上游 STQ1_0 补丁缺失）');
    }
    const task = await ModelManagerViewModel.buildTask(item);
    await DownloadRepository.upsert(task);
    await DownloadService.getInstance().start(task);
    const finalPath = DownloadService.finalPath(task.fileName);
    if (ModelManagerViewModel.fileExists(finalPath)) {
      AppEnv.getInstance().updateLocalModelPath(finalPath);
    }
  }

  static pause(modelKey: string): void {
    DownloadService.getInstance().pause(modelKey);
  }

  static async resume(item: ModelItem): Promise<void> {
    const task = await ModelManagerViewModel.buildTask(item);
    await DownloadService.getInstance().resume(task);
    const finalPath = DownloadService.finalPath(task.fileName);
    if (ModelManagerViewModel.fileExists(finalPath)) {
      AppEnv.getInstance().updateLocalModelPath(finalPath);
    }
  }

  /** 文件存在性探测（下载失败/暂停时不把不存在的路径设为当前模型）。 */
  private static fileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  static async remove(modelKey: string): Promise<void> {
    await DownloadService.getInstance().remove(modelKey);
  }

  /** Add a custom model by URL (any GGUF). Returns the new item. */
  static async addCustom(url: string, displayName: string): Promise<ModelItem> {
    const clean = url.trim();
    if (clean.length === 0) {
      throw new Error('请输入模型下载 URL');
    }
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      throw new Error('下载 URL 需以 http:// 或 https:// 开头');
    }
    const fileName = ModelManagerViewModel.fileNameOf(clean);
    const key = `CUSTOM_${Date.now()}`;
    const item = new ModelItem();
    item.isCustom = true;
    item.modelKey = key;
    item.displayName = displayName.trim().length > 0 ? displayName.trim() : fileName;
    item.quant = '自定义';
    item.url = clean;
    item.fileName = fileName;
    item.supported = true;
    item.status = DownloadStatus.NOT_DOWNLOADED;
    const task = makeDownloadTask(key, item.displayName, clean, fileName);
    await DownloadRepository.upsert(task);
    return item;
  }

  /** Register an imported local GGUF (no copy; path referenced in place). */
  static async importGguf(uri: string): Promise<void> {
    if (!uri.toLowerCase().endsWith('.gguf')) {
      throw new Error('请选择 .gguf 模型文件');
    }
    const fileName = ModelManagerViewModel.fileNameOf(uri);
    const key = `IMPORT_${Date.now()}`;
    const task = makeDownloadTask(key, fileName, '', fileName);
    task.status = DownloadStatus.DOWNLOADED;
    task.localPath = uri;
    await DownloadRepository.upsert(task);
    AppEnv.getInstance().updateLocalModelPath(uri);
  }

  static fileNameOf(url: string): string {
    const trimmed = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    const idx = trimmed.lastIndexOf('/');
    const seg = idx >= 0 ? trimmed.substring(idx + 1) : trimmed;
    try {
      return decodeURIComponent(seg);
    } catch (e) {
      return seg;
    }
  }
}