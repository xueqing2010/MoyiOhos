import fs from '@ohos.file.fs';
import { preferences } from '@kit.ArkData';
import { image } from '@kit.ImageKit';
import { Manga, MangaPage, PageTranslation } from 'coremodel';
import { EngineType } from 'coretranslate';
import { RenderOptions, RenderOrientation, FontSizeMode, VerticalDirection } from 'corerender';
import { ThemeTokens, Log, toMediaUri } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { MangaRepository } from '../data/MangaRepository';
import { PageRepository } from '../data/PageRepository';
import { BatchState, BatchTranslateService } from '../service/BatchTranslateService';
import { ExportMode, ExportResult, ExportService } from '../service/ExportService';

const TAG = 'ReaderViewModel';
const PREF_FILE = 'starflow_reader';

/** preferences 键（与 settings-dev / SettingsReadingPage 契约一致，禁止改名）。 */
export class ReaderPrefKeys {
  static readonly BG: string = 'reader_bg';
  static readonly MODE: string = 'reader_mode';
  static readonly FLOW: string = 'reader_flow';
  static readonly ANIM: string = 'reader_page_anim';
  static readonly ORIENT: string = 'render_orientation';
  static readonly DIRECTION: string = 'render_direction';
  static readonly FONT_MODE: string = 'render_font_mode';
  static readonly FONT_SIZE: string = 'render_font_size';
  static readonly LINE_HEIGHT: string = 'reader_line_height';
  static readonly MARGIN: string = 'reader_margin';
  static readonly AUTO_INTERVAL: string = 'reader_auto_interval';
  static readonly WHITE_MERGE: string = 'reader_white_merge';
  static readonly BRIGHTNESS: string = 'reader_brightness';
  static readonly CONTRAST: string = 'reader_contrast';
  static readonly INVERT: string = 'reader_invert';
  static readonly GRAYSCALE: string = 'reader_grayscale';
  static readonly TOC_THUMB: string = 'reader_toc_thumbnail';
}

/** Intrinsic image size in original pixels (for contain-fit mapping). */
export class PageSize {
  width: number = 0;
  height: number = 0;
}

/** 显示三态（FR-011）：仅译文 / 仅原文 / 纯原图。 */
export class ReaderMode {
  static readonly TRANS: string = 'trans';
  static readonly ORIG: string = 'orig';
  static readonly RAW: string = 'raw';

  static normalize(raw: string): string {
    if (raw === ReaderMode.TRANS || raw === ReaderMode.ORIG) {
      return raw;
    }
    return ReaderMode.RAW;
  }
}

/** 4 阅读模式（对齐上游 mode: 0 LTR / 1 RTL / 2 竖排整页 / 3 连续 Webtoon）。 */
export class ReaderFlow {
  static readonly LTR: string = 'ltr';
  static readonly RTL: string = 'rtl';
  static readonly VERTICAL: string = 'vertical';
  static readonly WEBTOON: string = 'webtoon';

  static normalize(raw: string): string {
    if (raw === ReaderFlow.LTR || raw === ReaderFlow.VERTICAL || raw === ReaderFlow.WEBTOON) {
      return raw;
    }
    return ReaderFlow.RTL;
  }

  static isRtl(flow: string): boolean {
    return flow === ReaderFlow.RTL;
  }

  static isContinuous(flow: string): boolean {
    return flow === ReaderFlow.WEBTOON;
  }

  static label(flow: string): string {
    if (flow === ReaderFlow.LTR) {
      return '左到右';
    }
    if (flow === ReaderFlow.VERTICAL) {
      return '竖排整页';
    }
    if (flow === ReaderFlow.WEBTOON) {
      return '连续 Webtoon';
    }
    return '右到左';
  }
}

/** 4 翻页动画（对齐上游 animation: 0 无 / 1 滑动 / 2 封面叠放 / 3 卷曲简化）。 */
export class ReaderAnimation {
  static readonly NONE: string = 'none';
  static readonly SLIDE: string = 'slide';
  static readonly COVER: string = 'cover';
  static readonly CURL: string = 'curl';

  static normalize(raw: string): string {
    if (raw === ReaderAnimation.NONE || raw === ReaderAnimation.COVER || raw === ReaderAnimation.CURL) {
      return raw;
    }
    return ReaderAnimation.SLIDE;
  }

  static label(anim: string): string {
    if (anim === ReaderAnimation.NONE) {
      return '无';
    }
    if (anim === ReaderAnimation.COVER) {
      return '封面叠放';
    }
    if (anim === ReaderAnimation.CURL) {
      return '卷曲';
    }
    return '滑动';
  }
}

/** 6 背景档（紫夜阅读，含紫调纸色）。 */
export class ReaderBg {
  static readonly BLACK: string = 'black';
  static readonly NOCTURNE: string = 'nocturne';
  static readonly PLUM: string = 'plum';
  static readonly DEEP: string = 'deep';
  static readonly PAPER: string = 'paper';
  static readonly WHITE: string = 'white';
  /** 旧值兼容（MVP-1：gray/black/white）。 */
  static readonly LEGACY_GRAY: string = 'gray';

  static normalize(raw: string): string {
    if (raw === ReaderBg.BLACK || raw === ReaderBg.PLUM || raw === ReaderBg.DEEP
      || raw === ReaderBg.PAPER || raw === ReaderBg.WHITE) {
      return raw;
    }
    // gray / nocturne / 未知值 → 紫夜
    return ReaderBg.NOCTURNE;
  }

  static colorOf(key: string): string {
    if (key === ReaderBg.BLACK) {
      return ThemeTokens.READER_BG_BLACK;
    }
    if (key === ReaderBg.PLUM) {
      return ThemeTokens.READER_BG_PLUM;
    }
    if (key === ReaderBg.DEEP) {
      return ThemeTokens.READER_BG_DEEP;
    }
    if (key === ReaderBg.PAPER) {
      return ThemeTokens.READER_BG_PAPER;
    }
    if (key === ReaderBg.WHITE) {
      return ThemeTokens.READER_BG_WHITE;
    }
    return ThemeTokens.READER_BG_NOCTURNE;
  }

  static labelOf(key: string): string {
    if (key === ReaderBg.BLACK) {
      return '黑';
    }
    if (key === ReaderBg.PLUM) {
      return '紫梅';
    }
    if (key === ReaderBg.DEEP) {
      return '深紫';
    }
    if (key === ReaderBg.PAPER) {
      return '纸色';
    }
    if (key === ReaderBg.WHITE) {
      return '白';
    }
    return '紫夜';
  }

  /** 浅色背景（纸色/白）用于切换图标与文字的对比色。 */
  static isLight(key: string): boolean {
    return key === ReaderBg.PAPER || key === ReaderBg.WHITE;
  }

  static keys(): Array<string> {
    return [ReaderBg.BLACK, ReaderBg.NOCTURNE, ReaderBg.PLUM, ReaderBg.DEEP, ReaderBg.PAPER, ReaderBg.WHITE];
  }
}

/** 持久化渲染设置（行距/边距/白块合并也在这里，实时生效）。 */
export class RenderSettingsModel {
  orientation: number = 2; // RenderOrientation.AUTO（按检测框宽高逐块判断）
  verticalDirection: number = 0; // VerticalDirection.RTL
  fontSizeMode: number = 0; // FontSizeMode.AUTO
  fixedFontSize: number = 16;
  lineHeightPercent: number = 130;
  margin: number = 8;
  whiteMerge: boolean = true;

  /** 行距增量（×字号）：100%=1.0 → 相对引擎自然行距 1.3 的差值，负值由引擎夹到 0。 */
  lineSpacingExtra(): number {
    const ratio = this.lineHeightPercent / 100;
    const extra = ratio - 1.3;
    return extra > 0 ? extra : 0;
  }
}

/** 阅读器全量设置快照（一次读出，避免多次 prefs IO）。 */
export class ReaderSettings {
  bg: string = ReaderBg.NOCTURNE;
  mode: string = ReaderMode.RAW;
  flow: string = ReaderFlow.RTL;
  animation: string = ReaderAnimation.SLIDE;
  orientation: number = 2;
  verticalDirection: number = 0;
  fontSizeMode: number = 0;
  fixedFontSize: number = 16;
  lineHeightPercent: number = 130;
  margin: number = 8;
  whiteMerge: boolean = true;
  autoInterval: number = 5;
  brightness: number = 100;
  contrast: number = 100;
  invert: boolean = false;
  grayscale: boolean = false;

  renderModel(): RenderSettingsModel {
    const m = new RenderSettingsModel();
    m.orientation = this.orientation;
    m.verticalDirection = this.verticalDirection;
    m.fontSizeMode = this.fontSizeMode;
    m.fixedFontSize = this.fixedFontSize;
    m.lineHeightPercent = this.lineHeightPercent;
    m.margin = this.margin;
    m.whiteMerge = this.whiteMerge;
    return m;
  }

  /** 引擎渲染选项：排版在页面坐标系完成，padding 由页面边距设置换算。 */
  toRenderOptions(): RenderOptions {
    const opts: RenderOptions = {
      orientation: this.orientation === 0 ? RenderOrientation.HORIZONTAL
        : (this.orientation === 2 ? RenderOrientation.AUTO : RenderOrientation.VERTICAL),
      verticalDirection: this.verticalDirection === 0 ? VerticalDirection.RTL : VerticalDirection.LTR,
      fontSizeMode: this.fontSizeMode === 0 ? FontSizeMode.AUTO : FontSizeMode.FIXED,
      fixedFontSize: this.fixedFontSize,
      padding: 4,
      lineSpacing: this.renderModel().lineSpacingExtra(),
      charSpacing: 0
    };
    return opts;
  }
}

/** 已加载的阅读会话数据。 */
export class ReaderLoadResult {
  mangaName: string = '';
  pages: Array<MangaPage> = [];
  startIndex: number = 0;
  manga: Manga | undefined = undefined;
}

/**
 * 阅读器 VM：
 * - 全量设置读写（starflow_reader，键名与 settings-dev 契约一致）；
 * - 页图固有尺寸缓存（contain-fit 用）、译文缓存（避免重复 DB 查询）；
 * - 进度的读写、批量翻译/导出委托。
 */
export class ReaderViewModel {
  private static sizeCache: Map<string, PageSize> = new Map<string, PageSize>();
  private static translationCache: Map<number, PageTranslation> = new Map<number, PageTranslation>();

  static async load(mangaId: number): Promise<ReaderLoadResult> {
    await AppEnv.ready();
    const result = new ReaderLoadResult();
    if (mangaId < 0) {
      return result;
    }
    const manga = await MangaRepository.getById(mangaId);
    if (manga === undefined) {
      return result;
    }
    result.manga = manga;
    result.mangaName = manga.name;
    result.pages = await PageRepository.getPages(mangaId);
    let start = manga.lastReadPage;
    if (start < 0) {
      start = 0;
    }
    if (start > result.pages.length - 1) {
      start = result.pages.length - 1;
    }
    result.startIndex = start;
    return result;
  }

  static async saveProgress(mangaId: number, pageIndex: number): Promise<void> {
    try {
      await MangaRepository.updateLastReadPage(mangaId, pageIndex);
    } catch (e) {
      // 进度保存失败不打断阅读
    }
  }

  // ---------------- 设置读写 ----------------

  static async loadSettings(): Promise<ReaderSettings> {
    const s = new ReaderSettings();
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      s.bg = ReaderBg.normalize(pref.getSync(ReaderPrefKeys.BG, ReaderBg.NOCTURNE) as string);
      s.mode = ReaderMode.normalize(pref.getSync(ReaderPrefKeys.MODE, ReaderMode.RAW) as string);
      s.flow = ReaderFlow.normalize(pref.getSync(ReaderPrefKeys.FLOW, ReaderFlow.RTL) as string);
      s.animation = ReaderAnimation.normalize(pref.getSync(ReaderPrefKeys.ANIM, ReaderAnimation.SLIDE) as string);
      s.orientation = ReaderViewModel.clampInt(pref.getSync(ReaderPrefKeys.ORIENT, 2) as number, 0, 2);
      s.verticalDirection = ReaderViewModel.clampInt(pref.getSync(ReaderPrefKeys.DIRECTION, 0) as number, 0, 1);
      s.fontSizeMode = ReaderViewModel.clampInt(pref.getSync(ReaderPrefKeys.FONT_MODE, 0) as number, 0, 1);
      s.fixedFontSize = ReaderViewModel.clampInt(pref.getSync(ReaderPrefKeys.FONT_SIZE, 16) as number, 12, 40);
      s.lineHeightPercent = ReaderViewModel.clampInt(pref.getSync(ReaderPrefKeys.LINE_HEIGHT, 130) as number, 100, 200);
      s.margin = ReaderViewModel.clampInt(pref.getSync(ReaderPrefKeys.MARGIN, 8) as number, 0, 32);
      s.autoInterval = ReaderViewModel.clampInt(pref.getSync(ReaderPrefKeys.AUTO_INTERVAL, 5) as number, 3, 60);
      s.whiteMerge = pref.getSync(ReaderPrefKeys.WHITE_MERGE, true) as boolean;
      s.brightness = ReaderViewModel.clampInt(pref.getSync(ReaderPrefKeys.BRIGHTNESS, 100) as number, 20, 100);
      s.contrast = ReaderViewModel.clampInt(pref.getSync(ReaderPrefKeys.CONTRAST, 100) as number, 50, 150);
      s.invert = pref.getSync(ReaderPrefKeys.INVERT, false) as boolean;
      s.grayscale = pref.getSync(ReaderPrefKeys.GRAYSCALE, false) as boolean;
    } catch (e) {
      Log.warn(TAG, 'loadSettings failed, use defaults');
    }
    return s;
  }

  /** 全量落盘（设置面板每改一项调用一次，键数少、开销可接受）。 */
  static async saveSettings(s: ReaderSettings): Promise<void> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      pref.putSync(ReaderPrefKeys.BG, s.bg);
      pref.putSync(ReaderPrefKeys.MODE, s.mode);
      pref.putSync(ReaderPrefKeys.FLOW, s.flow);
      pref.putSync(ReaderPrefKeys.ANIM, s.animation);
      pref.putSync(ReaderPrefKeys.ORIENT, s.orientation);
      pref.putSync(ReaderPrefKeys.DIRECTION, s.verticalDirection);
      pref.putSync(ReaderPrefKeys.FONT_MODE, s.fontSizeMode);
      pref.putSync(ReaderPrefKeys.FONT_SIZE, s.fixedFontSize);
      pref.putSync(ReaderPrefKeys.LINE_HEIGHT, s.lineHeightPercent);
      pref.putSync(ReaderPrefKeys.MARGIN, s.margin);
      pref.putSync(ReaderPrefKeys.AUTO_INTERVAL, s.autoInterval);
      pref.putSync(ReaderPrefKeys.WHITE_MERGE, s.whiteMerge);
      pref.putSync(ReaderPrefKeys.BRIGHTNESS, s.brightness);
      pref.putSync(ReaderPrefKeys.CONTRAST, s.contrast);
      pref.putSync(ReaderPrefKeys.INVERT, s.invert);
      pref.putSync(ReaderPrefKeys.GRAYSCALE, s.grayscale);
      await pref.flush();
    } catch (e) {
      Log.warn(TAG, 'saveSettings failed');
    }
  }

  private static clampInt(value: number, min: number, max: number): number {
    let v = Math.round(value);
    if (v < min) {
      v = min;
    }
    if (v > max) {
      v = max;
    }
    return v;
  }

  // ---------------- 页尺寸 / 译文缓存 ----------------

  /** 读取页图固有像素尺寸（带缓存，供 contain-fit 使用）。 */
  static async getPageSize(path: string): Promise<PageSize | undefined> {
    const cached = ReaderViewModel.sizeCache.get(path);
    if (cached !== undefined) {
      return cached;
    }
    let source: image.ImageSource | undefined = undefined;
    let file: fs.File | undefined = undefined;
    try {
      // 沙箱绝对路径不能被 Image/ImageSource 直接识别，先转媒体 URI；失败再退回 fd 打开。
      try {
        source = image.createImageSource(toMediaUri(path));
      } catch (e) {
        source = undefined;
      }
      if (source === undefined || source === null) {
        file = fs.openSync(path, fs.OpenMode.READ_ONLY);
        source = image.createImageSource(file.fd);
      }
      if (source === undefined || source === null) {
        return undefined;
      }
      const info = await source.getImageInfo();
      const size = new PageSize();
      size.width = info.size.width;
      size.height = info.size.height;
      ReaderViewModel.sizeCache.set(path, size);
      return size;
    } catch (e) {
      return undefined;
    } finally {
      if (source !== undefined) {
        try {
          source.release();
        } catch (ignore) {
        }
      }
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (ignore) {
        }
      }
    }
  }

  static async getTranslation(pageId: number): Promise<PageTranslation | undefined> {
    const cached = ReaderViewModel.translationCache.get(pageId);
    if (cached !== undefined) {
      return cached;
    }
    try {
      const pt = await PageRepository.getTranslation(pageId);
      if (pt !== undefined) {
        ReaderViewModel.translationCache.set(pageId, pt);
      }
      return pt;
    } catch (e) {
      return undefined;
    }
  }

  static putTranslation(pt: PageTranslation): void {
    ReaderViewModel.translationCache.set(pt.pageId, pt);
  }

  static invalidateTranslation(pageId: number): void {
    ReaderViewModel.translationCache.delete(pageId);
  }

  static clearTranslationCache(): void {
    ReaderViewModel.translationCache.clear();
  }

  // ---------------- 批量翻译（US-6） ----------------

  static startBatch(mangaId: number, engineType: EngineType): void {
    ReaderViewModel.clearTranslationCache();
    BatchTranslateService.getInstance().start(mangaId, engineType);
  }

  static cancelBatch(): void {
    BatchTranslateService.getInstance().cancel();
  }

  static batchState(): BatchState {
    return BatchTranslateService.getInstance().getState();
  }

  static onBatchChange(cb: (s: BatchState) => void): void {
    BatchTranslateService.getInstance().onStateChange(cb);
  }

  static offBatchChange(cb: (s: BatchState) => void): void {
    BatchTranslateService.getInstance().offStateChange(cb);
  }

  static async retryBatchPage(pageId: number): Promise<void> {
    ReaderViewModel.invalidateTranslation(pageId);
    await BatchTranslateService.getInstance().retryPage(pageId);
  }

  // ---------------- 导出（US-7） ----------------

  static async exportManga(mangaId: number, mode: ExportMode,
    onProgress: (done: number, total: number) => void,
    isCancelled?: () => boolean): Promise<ExportResult> {
    return ExportService.export(mangaId, mode, onProgress, isCancelled);
  }

  // ---------------- 显示滤镜 ----------------

  /**
   * 4x5 颜色矩阵（偏移量归一化 0..1）：反色 → 灰度 → 对比度 依次复合。
   * 用于 Image.colorFilter，让反色/灰度/对比在图片上即时生效。
   */
  static buildColorFilterMatrix(invert: boolean, grayscale: boolean, contrastPercent: number): Array<number> {
    let matrix: Array<number> = ReaderViewModel.identityMatrix();
    if (grayscale) {
      matrix = ReaderViewModel.compose(ReaderViewModel.grayscaleMatrix(), matrix);
    }
    const c = Math.max(0.5, Math.min(1.5, contrastPercent / 100));
    if (Math.abs(c - 1) > 0.001) {
      matrix = ReaderViewModel.compose(ReaderViewModel.contrastMatrix(c), matrix);
    }
    if (invert) {
      matrix = ReaderViewModel.compose(ReaderViewModel.invertMatrix(), matrix);
    }
    return matrix;
  }

  static identityMatrix(): Array<number> {
    return [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
  }

  static grayscaleMatrix(): Array<number> {
    return [
      0.299, 0.587, 0.114, 0, 0,
      0.299, 0.587, 0.114, 0, 0,
      0.299, 0.587, 0.114, 0, 0,
      0, 0, 0, 1, 0
    ];
  }

  static contrastMatrix(c: number): Array<number> {
    const offset = 0.5 * (1 - c);
    return [
      c, 0, 0, 0, offset,
      0, c, 0, 0, offset,
      0, 0, c, 0, offset,
      0, 0, 0, 1, 0
    ];
  }

  static invertMatrix(): Array<number> {
    return [
      -1, 0, 0, 0, 1,
      0, -1, 0, 0, 1,
      0, 0, -1, 0, 1,
      0, 0, 0, 1, 0
    ];
  }

  /** 复合颜色矩阵：先应用 inner，再应用 outer。 */
  static compose(outer: Array<number>, inner: Array<number>): Array<number> {
    const out: Array<number> = [];
    for (let i = 0; i < 4; i++) {
      for (let j = 0; j < 4; j++) {
        let sum = 0;
        for (let k = 0; k < 4; k++) {
          sum += outer[i * 5 + k] * inner[k * 5 + j];
        }
        out.push(sum);
      }
      let offset = outer[i * 5 + 4];
      for (let k = 0; k < 4; k++) {
        offset += outer[i * 5 + k] * inner[k * 5 + 4];
      }
      out.push(offset);
    }
    return out;
  }
}
