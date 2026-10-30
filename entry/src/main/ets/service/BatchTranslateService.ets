import { MangaPage, TranslateStatus } from 'coremodel';
import { EngineType } from 'coretranslate';
import { Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { PageRepository } from '../data/PageRepository';
import { MangaRepository } from '../data/MangaRepository';
import { PageTranslateService, TranslatePhase, TranslateProgress } from './PageTranslateService';

const TAG = 'BatchTranslateService';

/** Observable batch queue state (plan D13). */
export class BatchState {
  running: boolean = false;
  finished: boolean = false;
  cancelled: boolean = false;
  total: number = 0;
  done: number = 0;
  failed: number = 0;
  currentPage: number = 0;
  currentPhase: TranslatePhase = TranslatePhase.OCR;
  currentPercent: number = 0;
  currentDetail: string = '';
  lastError: string = '';
  failedPageIds: Array<number> = [];
}

/**
 * 批量翻译队列（T029 / US-6 / plan D13）：应用内串行状态机。
 * start(mangaId, engine, range?) / cancel / onStateChange；
 * 逐页复用 PageTranslateService，失败页记 fail_reason 并续跑；
 * 完成后汇总 manga.translate_status（已翻译 / 部分失败）。
 */
export class BatchTranslateService {
  private static instance: BatchTranslateService = new BatchTranslateService();

  private state: BatchState = new BatchState();
  private listeners: Array<(s: BatchState) => void> = [];
  private cancelRequested: boolean = false;
  private running: boolean = false;
  private pageIds: Array<number> = [];
  private engine: EngineType = EngineType.BING;
  private mangaId: number = -1;

  static getInstance(): BatchTranslateService {
    return BatchTranslateService.instance;
  }

  getState(): BatchState {
    return this.state;
  }

  onStateChange(cb: (s: BatchState) => void): void {
    this.listeners.push(cb);
  }

  offStateChange(cb: (s: BatchState) => void): void {
    const idx = this.listeners.indexOf(cb);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  isRunning(): boolean {
    return this.running;
  }

  /** Start整本 or a [start,end] page range (1-based inclusive). */
  start(mangaId: number, engineType: EngineType, range?: Array<number>): void {
    if (this.running) {
      Log.warn(TAG, 'batch already running, ignored');
      return;
    }
    this.mangaId = mangaId;
    this.engine = engineType;
    this.cancelRequested = false;
    this.running = true;
    this.state = new BatchState();
    this.state.running = true;
    this.pageIds = [];
    this.run(range);
  }

  cancel(): void {
    if (!this.running) {
      return;
    }
    this.cancelRequested = true;
    this.emit();
  }

  /** Single-page retry reusing the page pipeline (US-6 scene 5). */
  async retryPage(pageId: number): Promise<void> {
    try {
      await PageTranslateService.retryPage(pageId, this.engine);
      const idx = this.state.failedPageIds.indexOf(pageId);
      if (idx >= 0) {
        this.state.failedPageIds.splice(idx, 1);
        if (this.state.failed > 0) {
          this.state.failed--;
        }
        this.state.done++;
      }
      this.emit();
    } catch (e) {
      this.state.lastError = `${e}`;
      this.emit();
      throw new Error(`${e}`);
    }
  }

  private async run(range?: Array<number>): Promise<void> {
    try {
      await AppEnv.ready();
      const pages: Array<MangaPage> = await PageRepository.getPages(this.mangaId);
      let selected: Array<MangaPage> = pages;
      if (range !== undefined && range.length === 2) {
        const from = Math.max(1, range[0]);
        const to = Math.min(pages.length, range[1]);
        selected = [];
        for (let i = from - 1; i < to; i++) {
          if (i >= 0 && i < pages.length) {
            selected.push(pages[i]);
          }
        }
      }
      this.pageIds = [];
      for (const p of selected) {
        this.pageIds.push(p.id);
      }
      this.state.total = this.pageIds.length;
      this.emit();

      if (this.pageIds.length === 0) {
        await this.finish();
        return;
      }

      await MangaRepository.updateTranslateStatus(this.mangaId, TranslateStatus.RUNNING);

      for (let i = 0; i < this.pageIds.length; i++) {
        if (this.cancelRequested) {
          this.state.cancelled = true;
          break;
        }
        this.state.currentPage = i + 1;
        this.state.currentPhase = TranslatePhase.OCR;
        this.state.currentPercent = 0;
        this.state.currentDetail = '准备 OCR';
        this.emit();
        const pageId = this.pageIds[i];
        try {
          const onProgress = (p: TranslateProgress): void => {
            this.state.currentPhase = p.phase;
            this.state.currentPercent = p.percent;
            this.state.currentDetail = p.detail;
            this.emit();
          };
          await PageTranslateService.translatePage(pageId, this.engine, onProgress);
          this.state.done++;
        } catch (e) {
          this.state.failed++;
          this.state.failedPageIds.push(pageId);
          this.state.lastError = `${e}`;
          Log.warn(TAG, `page ${pageId} failed: ${e}`);
        }
        this.emit();
      }
      await this.finish();
    } catch (e) {
      this.state.lastError = `${e}`;
      Log.error(TAG, `batch run failed: ${e}`);
      this.running = false;
      this.state.running = false;
      this.state.finished = true;
      this.emit();
    }
  }

  private async finish(): Promise<void> {
    this.running = false;
    this.state.running = false;
    this.state.finished = true;
    let status = TranslateStatus.NONE;
    if (this.state.failed > 0) {
      status = TranslateStatus.PARTIAL_FAILED;
    } else if (this.state.done >= this.state.total && this.state.total > 0) {
      status = TranslateStatus.DONE;
    } else if (this.state.done > 0) {
      status = TranslateStatus.PARTIAL_FAILED;
    }
    try {
      await MangaRepository.updateTranslateStatus(this.mangaId, status);
    } catch (e) {
      Log.warn(TAG, `update manga status failed: ${e}`);
    }
    this.emit();
  }

  private emit(): void {
    for (const cb of this.listeners) {
      try {
        cb(this.state);
      } catch (e) {
        Log.warn(TAG, `listener error: ${e}`);
      }
    }
  }
}
