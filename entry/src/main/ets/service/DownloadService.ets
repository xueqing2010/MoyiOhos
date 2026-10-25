import fs from '@ohos.file.fs';
import statvfs from '@ohos.file.statvfs';
import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { DownloadStatus, DownloadTask } from 'coremodel';
import { ModelPresets } from 'coretranslate';
import { Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { DownloadRepository } from '../data/DownloadRepository';

const TAG = 'DownloadService';
const CHUNK = 1024 * 1024;

/** Observable download progress (superset of DownloadTask + speed). */
export class DownloadProgress {
  modelKey: string = '';
  displayName: string = '';
  status: DownloadStatus = DownloadStatus.NOT_DOWNLOADED;
  downloadedBytes: number = 0;
  totalBytes: number = 0;
  speedBps: number = 0;
  localPath: string = '';
  error: string = '';
}

/**
 * GGUF 下载服务（T038 / US-9 / plan D12）：rcp/http + Range 断点续传
 * （.part 记偏移、冷启动可续）、cryptoFramework MD5 流式校验、
 * 发起前剩余空间预检、pause/resume/remove（含清理）。
 */
export class DownloadService {
  private static instance: DownloadService = new DownloadService();
  private requests: Map<string, http.HttpRequest> = new Map();
  private paused: Set<string> = new Set();
  private states: Map<string, DownloadProgress> = new Map();
  private listeners: Array<(p: DownloadProgress) => void> = [];

  static getInstance(): DownloadService {
    return DownloadService.instance;
  }

  private static ensureDir(dir: string): void {
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      // Directory creation is best-effort; the following file operations
      // surface a readable error if the path is truly unusable.
      Log.warn('DownloadService', 'ensureDir failed for ' + dir + ': ' + e);
    }
  }

  static modelsDir(): string {
    return `${AppEnv.getInstance().getContext().filesDir}/models`;
  }

  static cacheModelsDir(): string {
    return `${AppEnv.getInstance().getContext().cacheDir}/models`;
  }

  static finalPath(fileName: string): string {
    return `${DownloadService.modelsDir()}/${fileName}`;
  }

  static partPath(modelKey: string): string {
    return `${DownloadService.cacheModelsDir()}/${modelKey}.part`;
  }

  onProgress(cb: (p: DownloadProgress) => void): void {
    this.listeners.push(cb);
  }

  offProgress(cb: (p: DownloadProgress) => void): void {
    const idx = this.listeners.indexOf(cb);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  getProgress(modelKey: string): DownloadProgress | undefined {
    return this.states.get(modelKey);
  }

  /** Start (or resume) a download. Throws readable error on space/HTTP issues. */
  async start(task: DownloadTask): Promise<void> {
    await AppEnv.ready();
    // mkdirSync(path, true) throws EEXIST on some HarmonyOS builds when the
    // target already exists; guard both directories explicitly.
    DownloadService.ensureDir(DownloadService.modelsDir());
    DownloadService.ensureDir(DownloadService.cacheModelsDir());
    this.paused.delete(task.modelKey);

    const finalPath = DownloadService.finalPath(task.fileName);
    const partPath = DownloadService.partPath(task.modelKey);
    if (fs.accessSync(finalPath)) {
      const p = this.ensureProgress(task);
      p.status = DownloadStatus.DOWNLOADED;
      p.localPath = finalPath;
      this.emit(p);
      await DownloadRepository.updateStatus(task.modelKey, DownloadStatus.DOWNLOADED);
      await DownloadRepository.updateLocalPath(task.modelKey, finalPath);
      return;
    }

    // Space precheck (US-9 scene 5).
    let total = task.totalBytes;
    if (total <= 0) {
      const preset = ModelPresets.byKey(task.modelKey);
      if (preset !== undefined) {
        total = preset.sizeBytes;
      }
    }
    if (total > 0) {
      const free = await statvfs.getFreeSize(AppEnv.getInstance().getContext().filesDir);
      if (free < total * 1.05) {
        throw new Error(`存储空间不足：需要约 ${ModelPresets.formatSize(total)}，可用 ${ModelPresets.formatSize(free)}`);
      }
    }

    let offset = 0;
    try {
      offset = fs.statSync(partPath).size;
    } catch (e) {
      offset = 0;
    }

    const progress = this.ensureProgress(task);
    progress.status = DownloadStatus.DOWNLOADING;
    progress.downloadedBytes = offset;
    progress.totalBytes = total;
    progress.error = '';
    this.emit(progress);
    await DownloadRepository.updateProgress(task.modelKey, offset, total, DownloadStatus.DOWNLOADING);

    await this.download(task, offset, partPath, finalPath, progress);
  }

  pause(modelKey: string): void {
    this.paused.add(modelKey);
    const req = this.requests.get(modelKey);
    if (req !== undefined) {
      try {
        req.destroy();
      } catch (e) {
        Log.warn(TAG, `destroy failed: ${e}`);
      }
      this.requests.delete(modelKey);
    }
    const p = this.states.get(modelKey);
    if (p !== undefined) {
      p.status = DownloadStatus.PAUSED;
      p.speedBps = 0;
      this.emit(p);
    } else {
      // 冷启动/重新进入页面后的旧任务在 states 中没有运行时记录：
      // 合成一条 PAUSED 进度通知 UI，否则卡片会永远停在「下载中」。
      const paused = new DownloadProgress();
      paused.modelKey = modelKey;
      paused.status = DownloadStatus.PAUSED;
      paused.speedBps = 0;
      this.emit(paused);
    }
    DownloadRepository.updateStatus(modelKey, DownloadStatus.PAUSED).catch((e: Object) => {
      Log.warn(TAG, `persist paused failed: ${e}`);
    });
  }

  async resume(task: DownloadTask): Promise<void> {
    await this.start(task);
  }

  async remove(modelKey: string): Promise<void> {
    this.pause(modelKey);
    this.paused.delete(modelKey);
    const p = this.states.get(modelKey);
    const partPath = DownloadService.partPath(modelKey);
    try {
      if (fs.accessSync(partPath)) {
        fs.unlinkSync(partPath);
      }
    } catch (e) {
      Log.warn(TAG, `unlink part failed: ${e}`);
    }
    // Only remove files that live inside the app-managed models directory.
    // Imported local GGUF models are merely *registered* by their original
    // path/URI; deleting the record must never touch the user's own file.
    if (p !== undefined && p.localPath.length > 0 &&
      p.localPath.startsWith(DownloadService.modelsDir())) {
      try {
        if (fs.accessSync(p.localPath)) {
          fs.unlinkSync(p.localPath);
        }
      } catch (e) {
        Log.warn(TAG, `unlink final failed: ${e}`);
      }
    } else if (p !== undefined && p.localPath.length > 0) {
      Log.info(TAG, `keep user file on remove: ${p.localPath}`);
    }
    this.states.delete(modelKey);
    await DownloadRepository.remove(modelKey);
    const cleared = new DownloadProgress();
    cleared.modelKey = modelKey;
    cleared.status = DownloadStatus.NOT_DOWNLOADED;
    this.emit(cleared);
  }

  private async download(task: DownloadTask, offset: number, partPath: string, finalPath: string,
    progress: DownloadProgress): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const req = http.createHttp();
      this.requests.set(task.modelKey, req);
      const file = fs.openSync(partPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      let downloaded = offset;
      let windowStart = Date.now();
      let windowBytes = offset;
      const headers: Record<string, string> = {};
      if (offset > 0) {
        headers['Range'] = `bytes=${offset}-`;
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 0
      };

      req.on('headersReceive', (h: Object) => {
        try {
          const rec = h as Record<string, Object>;
          let cl = rec['content-length'];
          if (cl === undefined || cl === null) {
            cl = rec['Content-Length'];
          }
          if (typeof cl === 'string') {
            const n = parseInt(cl as string);
            if (!isNaN(n)) {
              progress.totalBytes = offset + n;
              task.totalBytes = progress.totalBytes;
            }
          }
        } catch (e) {
          // header parse best-effort
        }
      });

      req.on('dataReceive', (chunk: ArrayBuffer) => {
        try {
          fs.writeSync(file.fd, chunk, { offset: downloaded });
          downloaded += chunk.byteLength;
          progress.downloadedBytes = downloaded;
          const now = Date.now();
          if (now - windowStart >= 300) {
            progress.speedBps = (downloaded - windowBytes) * 1000 / (now - windowStart);
            windowStart = now;
            windowBytes = downloaded;
            this.emit(progress);
            DownloadRepository.updateProgress(task.modelKey, downloaded, progress.totalBytes,
              DownloadStatus.DOWNLOADING).catch((e: Object) => {
            });
          }
        } catch (e) {
          Log.warn(TAG, `write chunk failed: ${e}`);
        }
      });

      req.on('dataEnd', () => {
        // finalization handled after requestInStream resolves
      });

      req.requestInStream(task.url, options).then((code: number) => {
        fs.closeSync(file);
        this.requests.delete(task.modelKey);
        if (this.paused.has(task.modelKey)) {
          progress.status = DownloadStatus.PAUSED;
          progress.speedBps = 0;
          this.emit(progress);
          resolve();
          return;
        }
        if (code !== 200 && code !== 206) {
          progress.error = `下载失败（HTTP ${code}）`;
          progress.status = DownloadStatus.NOT_DOWNLOADED;
          this.emit(progress);
          reject(new Error(progress.error));
          return;
        }
        this.finalize(task, partPath, finalPath, progress, downloaded).then(() => {
          resolve();
        }).catch((e: Object) => {
          reject(e);
        });
      }).catch((e: Object) => {
        fs.closeSync(file);
        this.requests.delete(task.modelKey);
        if (this.paused.has(task.modelKey)) {
          progress.status = DownloadStatus.PAUSED;
          progress.speedBps = 0;
          this.emit(progress);
          resolve();
          return;
        }
        progress.status = DownloadStatus.NOT_DOWNLOADED;
        progress.error = `网络中断：${e}`;
        this.emit(progress);
        reject(new Error(progress.error));
      });
    });
  }

  private async finalize(task: DownloadTask, partPath: string, finalPath: string,
    progress: DownloadProgress, downloaded: number): Promise<void> {
    try {
      fs.renameSync(partPath, finalPath);
    } catch (e) {
      // Some file systems refuse rename across dirs; fall back to copy + unlink.
      const src = fs.openSync(partPath, fs.OpenMode.READ_ONLY);
      try {
        fs.copyFileSync(src.fd, finalPath);
      } finally {
        fs.closeSync(src);
      }
      fs.unlinkSync(partPath);
    }
    progress.localPath = finalPath;
    progress.downloadedBytes = downloaded;

    const expected = task.expectedMd5;
    if (expected !== undefined && expected.length > 0) {
      progress.status = DownloadStatus.VERIFYING;
      this.emit(progress);
      await DownloadRepository.updateStatus(task.modelKey, DownloadStatus.VERIFYING);
      const actual = await DownloadService.md5OfFile(finalPath);
      if (actual.toLowerCase() !== expected.toLowerCase()) {
        progress.status = DownloadStatus.MD5_FAILED;
        progress.error = `MD5 校验失败（期望 ${expected}，实际 ${actual}）`;
        try {
          fs.unlinkSync(finalPath);
        } catch (e) {
          // ignore
        }
        await DownloadRepository.updateStatus(task.modelKey, DownloadStatus.MD5_FAILED);
        this.emit(progress);
        throw new Error(progress.error);
      }
    }

    progress.status = DownloadStatus.DOWNLOADED;
    progress.speedBps = 0;
    await DownloadRepository.updateProgress(task.modelKey, downloaded, progress.totalBytes,
      DownloadStatus.DOWNLOADED);
    await DownloadRepository.updateLocalPath(task.modelKey, finalPath);
    this.emit(progress);
    Log.info(TAG, `download complete: ${task.modelKey} -> ${finalPath}`);
  }

  private ensureProgress(task: DownloadTask): DownloadProgress {
    let p = this.states.get(task.modelKey);
    if (p === undefined) {
      p = new DownloadProgress();
      p.modelKey = task.modelKey;
      p.displayName = task.displayName;
      p.totalBytes = task.totalBytes;
      this.states.set(task.modelKey, p);
    }
    return p;
  }

  private emit(p: DownloadProgress): void {
    for (const cb of this.listeners) {
      try {
        cb(p);
      } catch (e) {
        Log.warn(TAG, `listener error: ${e}`);
      }
    }
  }

  /** Streaming MD5 over a file (chunked). */
  static async md5OfFile(path: string): Promise<string> {
    const md = cryptoFramework.createMd('MD5');
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const size = fs.statSync(path).size;
      let pos = 0;
      while (pos < size) {
        const len = Math.min(CHUNK, size - pos);
        const buf = new ArrayBuffer(len);
        const read = fs.readSync(file.fd, buf, { offset: pos, length: len });
        if (read <= 0) {
          break;
        }
        const data: cryptoFramework.DataBlob = { data: new Uint8Array(buf.slice(0, read)) };
        await md.update(data);
        pos += read;
      }
    } finally {
      fs.closeSync(file);
    }
    const out = await md.digest();
    return DownloadService.hex(out.data);
  }

  private static hex(bytes: Uint8Array): string {
    let s = '';
    for (let i = 0; i < bytes.length; i++) {
      const h = bytes[i].toString(16);
      s += h.length === 1 ? `0${h}` : h;
    }
    return s;
  }
}