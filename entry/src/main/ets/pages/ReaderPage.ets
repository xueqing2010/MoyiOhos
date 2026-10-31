import {
  DisplayRect,
  FontSizeMode,
  OverlayColors,
  OverlayRegion,
  OverlayRenderer,
  OverlayItem,
  PageOverlay,
  RenderOptions,
  RenderOrientation,
  VerticalDirection,
  containFit
} from 'corerender';
import { MangaPage, PageTranslation } from 'coremodel';
import { EngineType } from 'coretranslate';
import { uiMaterial } from '@kit.ArkUI';
import { OcrService } from 'coreocr';
import { ThemeTokens, Log, WindowSizeClass, observeBreakpoint, toMediaUri } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { ReaderParams, Routes, asReaderParams } from '../common/Routes';
import {
  PageSize,
  ReaderAnimation,
  ReaderBg,
  ReaderFlow,
  ReaderMode,
  ReaderSettings,
  ReaderViewModel
} from '../viewmodel/ReaderViewModel';
import { ReaderMenuView } from '../views/ReaderMenuView';
import { ReaderSettingsSheet, cloneReaderSettings } from '../views/ReaderSettingsSheet';
import { BatchPanel } from '../views/BatchPanel';
import { PageTranslateService, TranslatePhase, TranslateProgress } from '../service/PageTranslateService';
import { Motion } from '../common/Motion';
import { PreTranslateService } from '../service/PreTranslateService';
import { OcrModelService } from '../service/OcrModelService';
import { PageImageCleaner } from '../service/PageImageCleaner';
import { SettingsKeys, SettingsRepository } from '../data/SettingsRepository';
import { BatchState } from '../service/BatchTranslateService';
import { ExportMode, ExportResult } from '../service/ExportService';
import { MangaTocJump, makeMangaTocParams } from './MangaTocPage';
import { ShelfViewModel } from '../viewmodel/ShelfViewModel';

/** 一个显示单元：单页（phone / 竖排 / Webtoon）或双页跨页（lg 宽屏）。 */
class DisplaySlot {
  primary: number = -1;
  left: number = -1;
  right: number = -1;
  double: boolean = false;

  key(): string {
    return this.primary + '-' + this.left + '-' + this.right;
  }
}

/** Webtoon 缩略图/页列表的懒加载数据源。 */
class ReaderThumbSource implements IDataSource {
  private pages: Array<MangaPage> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.pages.length;
  }

  getData(index: number): MangaPage {
    return this.pages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  setPages(pages: Array<MangaPage>): void {
    this.pages = pages;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}

/**
 * 单页渲染层：页图 + 译文覆盖 Canvas（页面坐标系排版 → contain-fit 变换逐字绘制）。
 * 每个可见页一个实例：翻页动画时覆盖层随页一起滑动，不会出现“图动字不动”。
 * Webtoon 模式 fitWidth=true（宽度铺满、高度由父组件按页高计算）。
 */
@Component
struct ReaderPageLayer {
  page: MangaPage = {
    id: -1,
    mangaId: -1,
    pageIndex: 0,
    imagePath: '',
    translateStatus: 0
  };
  pageIndex: number = 0;
  @Prop @Watch('onModeChanged') mode: string = ReaderMode.RAW;
  @Prop orientation: number = 1;
  @Prop vdir: number = 0;
  @Prop fontMode: number = 0;
  @Prop fixedSize: number = 16;
  @Prop lineHeight: number = 130;
  @Prop pageMargin: number = 8;
  @Prop whiteMerge: boolean = true;
  @Prop filterInvert: boolean = false;
  @Prop filterGrayscale: boolean = false;
  @Prop filterContrast: number = 100;
  @Prop dimBrightness: number = 100;
  @Prop fitWidth: boolean = false;
  @Prop @Watch('onRenderRev') renderRev: number = 0;
  @Prop @Watch('onTranslationRev') translationRev: number = 0;
  onSingleTap: (x: number, width: number) => void = () => {
  };
  /** 长按气泡：仅未合并的单行可校对，参数为 OCR 行索引与当前译文。 */
  onEditBubble: (lineIndex: number, text: string) => void = () => {
  };

  @State areaW: number = 0;
  @State areaH: number = 0;
  @State imageFailed: boolean = false;
  @State cleanedPath: string = '';
  @State cleanColors: Array<string> = [];
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private pageSize: PageSize = new PageSize();
  private translation: PageTranslation | undefined = undefined;
  private canvasReady: boolean = false;
  // 覆盖层排版计划缓存：翻页/缩放/亮度变化时避免重复做逐字排版（性能优化）。
  private planKey: string = '';
  private planItems: Array<OverlayItem> = [];
  private transLoaded: boolean = false;

  aboutToAppear(): void {
    this.loadSize();
    this.loadTranslation(false);
  }

  /** 渲染设置变化（字号/方向/行距/滤镜等）：实时重绘当前页，不重新 OCR。 */
  private onRenderRev(propName: string): void {
    if (this.mode !== ReaderMode.RAW && !this.transLoaded) {
      this.loadTranslation(false);
      return;
    }
    this.draw();
  }

  /** 译文版本变化（翻译完成/批量进度/重试）：重读该页译文并重绘。 */
  private onTranslationRev(propName: string): void {
    this.loadTranslation(true);
  }

  /** 显示三态变化：切到译文/原文时按需加载译文。 */
  private onModeChanged(propName: string): void {
    if (this.mode !== ReaderMode.RAW && !this.transLoaded) {
      this.loadTranslation(false);
      return;
    }
    if (this.mode === ReaderMode.RAW) {
      this.cleanedPath = '';
      this.cleanColors = [];
    } else {
      this.prepareClean();
    }
    this.draw();
  }

  private async loadSize(): Promise<void> {
    const size = await ReaderViewModel.getPageSize(this.page.imagePath);
    if (size !== undefined) {
      this.pageSize = size;
      this.draw();
    }
  }

  private async loadTranslation(force: boolean): Promise<void> {
    if (this.mode === ReaderMode.RAW) {
      this.translation = undefined;
      this.transLoaded = false;
      this.draw();
      return;
    }
    if (force) {
      ReaderViewModel.invalidateTranslation(this.page.id);
    }
    const pt = await ReaderViewModel.getTranslation(this.page.id);
    this.translation = pt;
    this.transLoaded = true;
    this.cleanedPath = '';
    this.cleanColors = [];
    this.prepareClean();
    this.draw();
  }

  /** 生成/复用去字底图；没有 repaired 图时继续用白块覆盖。 */
  private async prepareClean(): Promise<void> {
    const pt = this.translation;
    if (this.mode === ReaderMode.RAW || pt === undefined || pt.ocr.length === 0) {
      this.cleanedPath = '';
      return;
    }
    const path = await PageImageCleaner.ensure(this.page.id, this.page.imagePath, pt.ocr);
    if (path !== undefined && path.length > 0) {
      this.cleanedPath = path;
      this.cleanColors = PageImageCleaner.textColors(this.page.id);
      this.draw();
    }
  }

  private lineSpacingExtra(): number {
    const ratio = this.lineHeight / 100;
    const extra = ratio - 1.3;
    return extra > 0 ? extra : 0;
  }

  private buildOptions(): RenderOptions {
    const opts: RenderOptions = {
      orientation: this.orientation === 0 ? RenderOrientation.HORIZONTAL
        : (this.orientation === 2 ? RenderOrientation.AUTO : RenderOrientation.VERTICAL),
      verticalDirection: this.vdir === 0 ? VerticalDirection.RTL : VerticalDirection.LTR,
      fontSizeMode: this.fontMode === 0 ? FontSizeMode.AUTO : FontSizeMode.FIXED,
      fixedFontSize: this.fixedSize,
      padding: 4,
      lineSpacing: this.lineSpacingExtra(),
      charSpacing: 0
    };
    return opts;
  }

  private filterMatrix(): Array<number> {
    return ReaderViewModel.buildColorFilterMatrix(this.filterInvert, this.filterGrayscale, this.filterContrast);
  }

  /** 覆盖层绘制：页面坐标排版 + contain-fit（或宽度铺满）变换，逐字直接光栅化。 */
  private draw(): void {
    if (!this.canvasReady) {
      return;
    }
    const ctx = this.ctx;
    const w = this.areaW;
    const h = this.areaH;
    if (w > 0 && h > 0) {
      ctx.clearRect(0, 0, w, h);
    }
    if (this.mode === ReaderMode.RAW) {
      return;
    }
    const pt = this.translation;
    if (pt === undefined || pt.ocr.length === 0 || w <= 0 || h <= 0) {
      return;
    }
    if (this.pageSize.width <= 0 || this.pageSize.height <= 0) {
      return;
    }
    let scale = 0;
    let dx = 0;
    let dy = 0;
    if (this.fitWidth) {
      scale = w / this.pageSize.width;
      dx = 0;
      dy = 0;
    } else {
      const fit = containFit(this.pageSize.width, this.pageSize.height, w, h);
      scale = fit.scale;
      dx = fit.dx;
      dy = fit.dy;
    }
    const opts = this.buildOptions();
    // 页面像素边界：把 OCR 框裁剪到页面内，避免白块越界（页面渲染错位）。
    opts.pageWidth = this.pageSize.width;
    opts.pageHeight = this.pageSize.height;
    const useTranslated = this.mode === ReaderMode.TRANS;
    const regions: Array<OverlayRegion> = [];
    for (let i = 0; i < pt.ocr.length; i++) {
      const region = pt.ocr[i];
      const text = useTranslated
        ? (i < pt.translations.length ? pt.translations[i] : '')
        : region.text;
      if (text.length === 0) {
        continue;
      }
      // 旧译文里可能残留“整页大框”，不参与绘制/去字，避免覆盖整页。
      const pageArea = this.pageSize.width * this.pageSize.height;
      if (region.box.w * region.box.h > pageArea * 0.15
        || (region.text.length <= 2 && region.box.w * region.box.h > pageArea * 0.04)) {
        continue;
      }
      const box: DisplayRect = {
        x: region.box.x,
        y: region.box.y,
        w: region.box.w,
        h: region.box.h
      };
      const textColor = i < this.cleanColors.length ? this.cleanColors[i] : '';
      const item: OverlayRegion = { box: box, original: region.text, translated: text };
      if (textColor.length > 0) {
        item.textColor = textColor;
      }
      regions.push(item);
    }
    // 仅当页/译文/排版参数变化时重新 build；尺寸变化只需重新 paint。
    const key = this.page.id + '|' + this.mode + '|' + this.renderRev + '|' + this.translationRev
      + '|' + this.whiteMerge + '|' + this.fontMode + '|' + this.fixedSize + '|' + this.orientation
      + '|' + this.vdir + '|' + this.lineHeight + '|' + this.pageSize.width + 'x' + this.pageSize.height
      + '|' + useTranslated + '|' + this.cleanedPath + '|' + this.cleanColors.length
      + '|' + (this.cleanColors.length > 0 ? this.cleanColors[0] : '');
    if (key !== this.planKey) {
      this.planItems = PageOverlay.build(regions, opts, useTranslated, this.whiteMerge);
      this.planKey = key;
    }
    const items = this.planItems;
    const boxFill = this.cleanedPath.length > 0 ? 'none' : (this.filterInvert ? '#15121F' : '#FFFFFF');
    const colors = this.filterInvert
      ? OverlayColors.make(boxFill, '#E8E4F5')
      : OverlayColors.make(boxFill, '#1A1A1A');
    // 画布可能覆盖整页容器（含留白），把覆盖层裁剪到页面图像矩形内，
    // 避免任何越界 OCR 框把白块画到页外（页面渲染错位）。
    ctx.save();
    ctx.beginPath();
    ctx.rect(dx, dy, this.pageSize.width * scale, this.pageSize.height * scale);
    ctx.clip();
    OverlayRenderer.paintPlan(ctx, items, scale, dx, dy, colors);
    ctx.restore();
  }

  /** 长按位置命中单个 OCR 行时回调校对；合并块暂不支持。 */
  private handleLongPress(localX: number, localY: number): void {
    if (this.mode === ReaderMode.RAW || this.pageSize.width <= 0 || this.areaW <= 0 || this.areaH <= 0) {
      return;
    }
    let scale = 0;
    let dx = 0;
    let dy = 0;
    if (this.fitWidth) {
      scale = this.areaW / this.pageSize.width;
    } else {
      const fit = containFit(this.pageSize.width, this.pageSize.height, this.areaW, this.areaH);
      scale = fit.scale;
      dx = fit.dx;
      dy = fit.dy;
    }
    if (scale <= 0) {
      return;
    }
    const pageX = (localX - dx) / scale;
    const pageY = (localY - dy) / scale;
    for (const item of this.planItems) {
      if (item.merged !== 1 || item.indices === undefined || item.indices.length !== 1) {
        continue;
      }
      const box = item.box;
      if (pageX >= box.x && pageX <= box.x + box.w && pageY >= box.y && pageY <= box.y + box.h) {
        this.onEditBubble(item.indices[0], item.text);
        return;
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(toMediaUri(this.mode !== ReaderMode.RAW && this.cleanedPath.length > 0
        ? this.cleanedPath : this.page.imagePath))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.Medium)
        .colorFilter(new ColorFilter(this.filterMatrix()))
        .draggable(false)
        .onError(() => {
          this.imageFailed = true;
          Log.error('ReaderPageLayer', 'page image load failed: ' + this.page.imagePath);
        })

      if (this.imageFailed) {
        Column({ space: 6 }) {
          Image($r('app.media.ic_image'))
            .width(28)
            .height(28)
            .fillColor(ThemeTokens.TEXT_HINT)
          Text('页图加载失败')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      }

      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        .onReady(() => {
          this.canvasReady = true;
          this.draw();
        })
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.areaW = newArea.width as number;
          this.areaH = newArea.height as number;
          this.draw();
        })

      if (this.dimBrightness < 100) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
          .opacity((100 - this.dimBrightness) / 100 * 0.75)
          .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .padding(this.fitWidth ? 0 : this.pageMargin)
    .onClick((event: ClickEvent) => {
      this.onSingleTap(event.x, this.areaW);
    })
    .gesture(LongPressGesture().onAction((event: GestureEvent) => {
      if (event.fingerList.length > 0) {
        this.handleLongPress(event.fingerList[0].localX, event.fingerList[0].localY);
      }
    }))
  }
}

/**
 * 漫画阅读器（全模式）：
 * 4 阅读模式（左到右 / 右到左 / 竖排整页 / 连续 Webtoon）、4 翻页动画（无/滑动/封面叠放/卷曲简化）、
 * 6 背景 + 反色/灰度/亮度/对比、进度胶囊 + 缩略图网格（bindSheet）、页码/TOC、
 * 自动翻页、点击分区、旋转重排、lg 宽屏双页并排、进度记忆；
 * 译文覆盖层在页面坐标系排版，随页滑动；翻译本页 / 批量翻译 / 导出 ZIP 保持可用。
 */
@Component
export struct ReaderPage {
  @State mangaId: number = -1;
  @State mangaName: string = '';
  @State pages: Array<MangaPage> = [];
  @State loaded: boolean = false;
  @State currentIndex: number = 0;
  @State settings: ReaderSettings = new ReaderSettings();
  @State slots: Array<DisplaySlot> = [];
  @State swiperIndex: number = 0;
  @State stageW: number = 0;
  @State stageH: number = 0;
  @State renderRev: number = 0;
  @State transRev: number = 0;
  @State currentTranslated: boolean = true;
  @State menuVisible: boolean = false;
  @State settingsVisible: boolean = false;
  @State thumbVisible: boolean = false;
  @State pageSizes: Array<PageSize> = [];
  @State webtoonHeights: Array<number> = [];
  @State translating: boolean = false;
  @State translatePhase: TranslatePhase = TranslatePhase.OCR;
  @State translatePct: number = 0;
  @State translateDone: number = 0;
  @State translateTotal: number = 0;
  @State translateDetail: string = '';
  @State ocrAvailable: boolean = true;
  @State autoTurning: boolean = false;
  @State batchRunning: boolean = false;
  @State batchTotal: number = 0;
  @State batchDone: number = 0;
  @State batchFailed: number = 0;
  @State batchCurrent: number = 0;
  @State batchPhaseDetail: string = '';
  @State batchError: string = '';
  @State batchFailedIds: Array<number> = [];
  @State exportBusy: boolean = false;
  @State showExportModes: boolean = false;
  @State exportDone: number = 0;
  @State exportTotal: number = 0;
  @State toast: string = '';
  @State editVisible: boolean = false;
  @State editLine: number = -1;
  @State editText: string = '';
  @State editBusy: boolean = false;
  @State animScale: Array<number> = [];
  @State animOpacity: Array<number> = [];
  @State animTranslate: Array<number> = [];
  @State animRotate: Array<number> = [];
  @State animZ: Array<number> = [];

  private swiperController: SwiperController = new SwiperController();
  private webtoonScroller: Scroller = new Scroller();
  private thumbSource: ReaderThumbSource = new ReaderThumbSource();
  private autoTimer: number = -1;
  private toastTimer: number = -1;
  private saveTimer: number = -1;
  private exportTimer: number = -1;
  private lastBatchDone: number = -1;
  /** Webtoon 切模式/首次进入时程序化滚动的锁：避免中间态 onScrollIndex 覆盖进度。 */
  private webtoonScrollLocked: boolean = false;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private batchHandler: (s: BatchState) => void = (s: BatchState) => {
    this.onBatchState(s);
  };

  aboutToAppear(): void {
    this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
      // 断点变化时用 onAreaChange 的 vp 宽度做双页判定，这里仅触发一次重排
      if (this.loaded) {
        this.rebuildSlots(this.currentIndex);
      }
    });
  }

  aboutToDisappear(): void {
    this.stopAutoTurn();
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
      ReaderViewModel.saveSettings(this.settings);
    }
    if (this.exportTimer >= 0) {
      clearTimeout(this.exportTimer);
      this.exportTimer = -1;
    }
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
    ReaderViewModel.offBatchChange(this.batchHandler);
    // 返回书架时刷新阅读进度（读到 X/Y 页）；保存是异步的，延迟再通知一次。
    ShelfViewModel.notifyChanged();
    setTimeout(() => {
      ShelfViewModel.notifyChanged();
    }, 500);
  }

  // ---------------- 初始化 ----------------

  private async init(params: ReaderParams): Promise<void> {
    if (this.loaded && this.mangaId === params.mangaId) {
      return;
    }
    this.mangaId = params.mangaId;
    this.settings = await ReaderViewModel.loadSettings();
    const result = await ReaderViewModel.load(params.mangaId);
    this.mangaName = result.mangaName;
    this.pages = result.pages;
    this.pageSizes = [];
    for (let i = 0; i < this.pages.length; i++) {
      this.pageSizes.push(new PageSize());
    }
    this.thumbSource.setPages(this.pages);
    let start = result.startIndex;
    if (params.startPage !== undefined && params.startPage >= 0 && params.startPage < this.pages.length) {
      start = params.startPage;
    }
    this.currentIndex = start;
    this.loaded = true;
    this.refreshCurrentTranslation();
    this.detectOcr();
    ReaderViewModel.onBatchChange(this.batchHandler);
    this.onBatchState(ReaderViewModel.batchState());
    if (this.stageW > 0) {
      this.rebuildSlots(start);
    }
    if (this.settings.flow === ReaderFlow.WEBTOON) {
      this.ensureWebtoonSizes();
      // 列表首帧后再定位到记忆页（List 尚未测量时 scrollToIndex 无效）
      this.scrollWebtoonTo(this.currentIndex);
    }
    // 首帧后再启动后台预翻译，避免和页面解码/排版争主线程。
    setTimeout(() => {
      PreTranslateService.prefetchManga(this.mangaId, this.currentIndex);
    }, 800);
  }

  /** Webtoon：等 List 完成首帧测量后滚到目标页，并在滚动落定前忽略 onScrollIndex。 */
  private scrollWebtoonTo(real: number): void {
    this.webtoonScrollLocked = true;
    setTimeout(() => {
      this.webtoonScroller.scrollToIndex(real);
      setTimeout(() => {
        this.webtoonScrollLocked = false;
      }, 260);
    }, 120);
  }

  /** 当前页是否已有译文（决定“仅译文”态提示层）。 */
  private async refreshCurrentTranslation(): Promise<void> {
    const page = this.pages[this.currentIndex];
    if (page === undefined) {
      this.currentTranslated = true;
      return;
    }
    const pt = await ReaderViewModel.getTranslation(page.id);
    this.currentTranslated = pt !== undefined && pt.ocr.length > 0
      && pt.translations.length > 0;
  }

  private async detectOcr(): Promise<void> {
    try {
      const tier = await SettingsRepository.getString(SettingsKeys.OCR_ENGINE_TIER, 'system');
      if (tier === 'local') {
        this.ocrAvailable = OcrModelService.localModelsReady();
        return;
      }
      this.ocrAvailable = await OcrService.getInstance().probe();
    } catch (e) {
      this.ocrAvailable = false;
    }
  }

  // ---------------- 显示单元与排版 ----------------

  /** lg（>=840vp，onAreaChange 的 vp 宽）且非竖排/Webtoon 时双页并排。 */
  private needDouble(): boolean {
    if (this.stageW < 840 || this.pages.length < 2) {
      return false;
    }
    return this.settings.flow === ReaderFlow.LTR || this.settings.flow === ReaderFlow.RTL;
  }

  private pairCount(): number {
    return Math.ceil(this.pages.length / 2);
  }

  private slotIndexOfReal(real: number): number {
    if (this.slots.length === 0) {
      return 0;
    }
    let d = real;
    if (this.needDouble()) {
      const k = Math.floor(real / 2);
      d = ReaderFlow.isRtl(this.settings.flow) ? this.pairCount() - 1 - k : k;
    } else if (ReaderFlow.isRtl(this.settings.flow) && this.settings.flow !== ReaderFlow.WEBTOON) {
      d = this.pages.length - 1 - real;
    }
    if (d < 0) {
      d = 0;
    }
    if (d > this.slots.length - 1) {
      d = this.slots.length - 1;
    }
    return d;
  }

  /** 依据当前模式/宽度重建显示单元（保留当前阅读位置）。 */
  private rebuildSlots(keepReal: number): void {
    if (this.pages.length === 0) {
      return;
    }
    const slots: Array<DisplaySlot> = [];
    if (this.needDouble()) {
      const count = this.pairCount();
      for (let d = 0; d < count; d++) {
        const k = ReaderFlow.isRtl(this.settings.flow) ? count - 1 - d : d;
        const slot = new DisplaySlot();
        slot.double = true;
        slot.primary = 2 * k;
        if (ReaderFlow.isRtl(this.settings.flow)) {
          slot.right = 2 * k;
          slot.left = 2 * k + 1 < this.pages.length ? 2 * k + 1 : -1;
        } else {
          slot.left = 2 * k;
          slot.right = 2 * k + 1 < this.pages.length ? 2 * k + 1 : -1;
        }
        slots.push(slot);
      }
    } else {
      const rtl = ReaderFlow.isRtl(this.settings.flow) && this.settings.flow !== ReaderFlow.WEBTOON;
      for (let d = 0; d < this.pages.length; d++) {
        const slot = new DisplaySlot();
        slot.primary = rtl ? this.pages.length - 1 - d : d;
        slot.left = slot.primary;
        slot.right = slot.primary;
        slot.double = false;
        slots.push(slot);
      }
    }
    this.resetAnimArrays(slots.length);
    this.slots = slots;
    this.swiperIndex = this.slotIndexOfReal(keepReal);
    this.updateWebtoonHeights();
  }

  private resetAnimArrays(size: number): void {
    const scale: Array<number> = [];
    const opacity: Array<number> = [];
    const translate: Array<number> = [];
    const rotate: Array<number> = [];
    const z: Array<number> = [];
    for (let i = 0; i < size; i++) {
      scale.push(1);
      opacity.push(1);
      translate.push(0);
      rotate.push(0);
      z.push(0);
    }
    this.animScale = scale;
    this.animOpacity = opacity;
    this.animTranslate = translate;
    this.animRotate = rotate;
    this.animZ = z;
  }

  private animScaleAt(i: number): number {
    return i >= 0 && i < this.animScale.length ? this.animScale[i] : 1;
  }

  private animOpacityAt(i: number): number {
    return i >= 0 && i < this.animOpacity.length ? this.animOpacity[i] : 1;
  }

  private animTranslateAt(i: number): number {
    return i >= 0 && i < this.animTranslate.length ? this.animTranslate[i] : 0;
  }

  private animRotateAt(i: number): number {
    return i >= 0 && i < this.animRotate.length ? this.animRotate[i] : 0;
  }

  private animZAt(i: number): number {
    return i >= 0 && i < this.animZ.length ? this.animZ[i] : 0;
  }

  private isVerticalFlow(): boolean {
    return this.settings.flow === ReaderFlow.VERTICAL;
  }

  // ---------------- 翻页动画（Swiper customContentTransition） ----------------

  private resetAnimSlot(index: number): void {
    if (index < 0 || index >= this.animScale.length) {
      return;
    }
    this.animScale[index] = 1;
    this.animOpacity[index] = 1;
    this.animTranslate[index] = 0;
    this.animRotate[index] = 0;
    this.animZ[index] = 0;
  }

  /**
   * 4 种翻页动画：
   * - none/slide：交给 Swiper 原生滑动；
   * - cover（封面叠放）：向中心收拢 + 缩放 + 淡出 + 层级，形成卡片叠放；
   * - curl（卷曲简化）：绕页面边缘 rotateY（竖排模式绕 X 轴）+ 透视 + 淡出。
   */
  private applyTransition(proxy: SwiperContentTransitionProxy): void {
    const index = proxy.index;
    if (index < 0 || index >= this.animScale.length) {
      return;
    }
    const anim = this.settings.animation;
    if (anim === ReaderAnimation.NONE || anim === ReaderAnimation.SLIDE
      || this.settings.flow === ReaderFlow.WEBTOON) {
      this.resetAnimSlot(index);
      return;
    }
    const pos = proxy.position;
    const abs = Math.abs(pos);
    if (abs <= 0.001 || abs >= 1) {
      this.resetAnimSlot(index);
      return;
    }
    const len = proxy.mainAxisLength;
    if (anim === ReaderAnimation.COVER) {
      this.animScale[index] = 1 - 0.12 * abs;
      this.animOpacity[index] = 1 - 0.18 * abs;
      this.animTranslate[index] = -pos * len * 0.45;
      this.animRotate[index] = 0;
      this.animZ[index] = 1;
    } else {
      this.animScale[index] = 1;
      this.animOpacity[index] = 1 - 0.2 * abs;
      this.animTranslate[index] = 0;
      this.animRotate[index] = pos * 78;
      this.animZ[index] = 1;
    }
  }

  private curlCenterX(index: number): string {
    return this.animRotateAt(index) >= 0 ? '0%' : '100%';
  }

  private curlCenterY(index: number): string {
    return this.animRotateAt(index) >= 0 ? '0%' : '100%';
  }

  // ---------------- 显示状态与设置 ----------------

  private commitSettings(next: ReaderSettings): void {
    const prevFlow = this.settings.flow;
    const prevMode = this.settings.mode;
    const prevInterval = this.settings.autoInterval;
    const prevAnim = this.settings.animation;
    this.settings = next;
    this.renderRev++;
    this.scheduleSave();
    if (prevAnim !== next.animation) {
      // 切换动画时清掉上一动画残留的位移/缩放/透明度，避免“粘住”。
      this.resetAnimArrays(this.slots.length);
    }
    if (prevFlow !== next.flow) {
      this.rebuildSlots(this.currentIndex);
      if (next.flow === ReaderFlow.WEBTOON) {
        this.ensureWebtoonSizes();
        this.scrollWebtoonTo(this.currentIndex);
      }
      this.updateWebtoonHeights();
    }
    if (next.mode !== ReaderMode.RAW && (prevMode === ReaderMode.RAW || prevFlow !== next.flow)) {
      this.transRev++;
    }
    if (this.autoTurning && prevInterval !== next.autoInterval) {
      this.scheduleAutoTurn();
    }
  }

  /** 滑杆连续拖动时合并落盘（300ms 去抖），避免每帧 flush preferences。 */
  private scheduleSave(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      ReaderViewModel.saveSettings(this.settings);
    }, 300);
  }

  private mutateSettings(mutator: (s: ReaderSettings) => void): void {
    const next = cloneReaderSettings(this.settings);
    mutator(next);
    this.commitSettings(next);
  }

  private bgColor(): string {
    return ReaderBg.colorOf(this.settings.bg);
  }

  private isLightBg(): boolean {
    return ReaderBg.isLight(this.settings.bg);
  }

  private fgColor(): string {
    return this.isLightBg() ? '#2A2140' : '#EDE8FA';
  }

  private chipBg(): string {
    return this.isLightBg() ? '#E4DAF5' : '#66000000';
  }

  private pageMetaText(): string {
    if (this.pages.length === 0) {
      return '0 / 0';
    }
    if (this.settings.flow === ReaderFlow.WEBTOON) {
      return (this.currentIndex + 1) + ' / ' + this.pages.length;
    }
    const slot = this.slots.length > 0 ? this.slots[this.swiperIndex] : undefined;
    if (slot !== undefined && slot.double) {
      const end = slot.primary + 2 <= this.pages.length ? slot.primary + 2 : this.pages.length;
      return (slot.primary + 1) + '-' + end + ' / ' + this.pages.length;
    }
    return (this.currentIndex + 1) + ' / ' + this.pages.length;
  }

  private progressRatio(): number {
    if (this.pages.length <= 1) {
      return 1;
    }
    return (this.currentIndex + 1) / this.pages.length;
  }

  private showToast(msg: string): void {
    this.toast = msg;
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout(() => {
      this.toast = '';
      this.toastTimer = -1;
    }, 3200);
  }

  // ---------------- 翻页/跳页/自动翻页 ----------------

  private goSlot(target: number): void {
    if (this.slots.length === 0) {
      return;
    }
    let t = target;
    if (t < 0) {
      t = 0;
    }
    if (t > this.slots.length - 1) {
      t = this.slots.length - 1;
    }
    if (t === this.swiperIndex) {
      return;
    }
    if (t === this.swiperIndex + 1) {
      this.swiperController.showNext();
    } else if (t === this.swiperIndex - 1) {
      this.swiperController.showPrevious();
    } else {
      this.swiperIndex = t;
    }
  }

  /** 阅读前进方向的下一个显示单元：RTL 的显示序列是反转的，前进 = 下标 -1。 */
  private forwardSlot(): number {
    return ReaderFlow.isRtl(this.settings.flow) ? this.swiperIndex - 1 : this.swiperIndex + 1;
  }

  private onSlotChanged(index: number): void {
    if (index < 0 || index >= this.slots.length) {
      return;
    }
    this.swiperIndex = index;
    const slot = this.slots[index];
    if (this.currentIndex !== slot.primary) {
      this.currentIndex = slot.primary;
      this.refreshCurrentTranslation();
    }
    this.persistProgress();
    PreTranslateService.prefetchManga(this.mangaId, this.currentIndex);
  }

  private persistProgress(): void {
    if (this.mangaId >= 0) {
      ReaderViewModel.saveProgress(this.mangaId, this.currentIndex);
    }
  }

  /** 跳到真实页（TOC / 缩略图 / 历史）；自动处理 RTL 与双页映射。 */
  private jumpToReal(real: number): void {
    if (this.pages.length === 0) {
      return;
    }
    let target = real;
    if (target < 0) {
      target = 0;
    }
    if (target > this.pages.length - 1) {
      target = this.pages.length - 1;
    }
    if (this.settings.flow === ReaderFlow.WEBTOON) {
      this.currentIndex = target;
      this.webtoonScroller.scrollToIndex(target);
      this.refreshCurrentTranslation();
      this.persistProgress();
      PreTranslateService.prefetchManga(this.mangaId, this.currentIndex);
      return;
    }
    this.currentIndex = target;
    this.swiperIndex = this.slotIndexOfReal(target);
    this.refreshCurrentTranslation();
    this.persistProgress();
    PreTranslateService.prefetchManga(this.mangaId, this.currentIndex);
  }

  /** 打开菜单时重新读取偏好：确保「我的 → 阅读设置」页的改动在回到阅读器后生效。 */
  private async reloadSettings(): Promise<void> {
    const next = await ReaderViewModel.loadSettings();
    const prevFlow = this.settings.flow;
    this.settings = next;
    this.renderRev++;
    if (prevFlow !== next.flow) {
      this.rebuildSlots(this.currentIndex);
      if (next.flow === ReaderFlow.WEBTOON) {
        this.ensureWebtoonSizes();
        this.scrollWebtoonTo(this.currentIndex);
      }
      this.updateWebtoonHeights();
    }
  }

  private tapZone(ratio: number): void {
    if (this.menuVisible) {
      this.menuVisible = false;
      return;
    }
    if (this.settingsVisible) {
      this.settingsVisible = false;
      return;
    }
    if (this.settings.flow === ReaderFlow.WEBTOON) {
      if (ratio < 0.32) {
        this.jumpToReal(this.currentIndex - 1);
      } else if (ratio > 0.68) {
        this.jumpToReal(this.currentIndex + 1);
      } else {
        this.menuVisible = true;
        this.reloadSettings();
      }
      return;
    }
    if (ratio < 0.32) {
      this.goSlot(this.swiperIndex - 1);
    } else if (ratio > 0.68) {
      this.goSlot(this.swiperIndex + 1);
    } else {
      this.menuVisible = true;
      this.reloadSettings();
    }
  }

  private toggleAutoTurn(): void {
    if (this.autoTurning) {
      this.stopAutoTurn();
      return;
    }
    this.autoTurning = true;
    this.scheduleAutoTurn();
    this.showToast('自动翻页：每 ' + this.settings.autoInterval + ' 秒');
  }

  private scheduleAutoTurn(): void {
    this.stopAutoTurn();
    if (!this.autoTurning) {
      return;
    }
    this.autoTimer = setInterval(() => {
      if (this.settings.flow === ReaderFlow.WEBTOON) {
        const next = this.currentIndex + 1;
        if (next >= this.pages.length) {
          this.stopAutoTurn();
          return;
        }
        this.jumpToReal(next);
        return;
      }
      const target = this.forwardSlot();
      if (target < 0 || target > this.slots.length - 1) {
        this.stopAutoTurn();
        return;
      }
      this.goSlot(target);
    }, this.settings.autoInterval * 1000);
  }

  private stopAutoTurn(): void {
    if (this.autoTimer >= 0) {
      clearInterval(this.autoTimer);
      this.autoTimer = -1;
    }
    this.autoTurning = false;
  }

  // ---------------- Webtoon ----------------

  private async ensureWebtoonSizes(): Promise<void> {
    if (this.pages.length === 0) {
      return;
    }
    const sizes: Array<PageSize> = this.pageSizes.slice();
    let changed = false;
    for (let i = 0; i < this.pages.length; i++) {
      const cached = await ReaderViewModel.getPageSize(this.pages[i].imagePath);
      if (cached !== undefined && sizes[i].width !== cached.width) {
        sizes[i] = cached;
        changed = true;
      }
    }
    if (changed) {
      this.pageSizes = sizes;
      this.updateWebtoonHeights();
    }
  }

  private updateWebtoonHeights(): void {
    if (this.settings.flow !== ReaderFlow.WEBTOON) {
      return;
    }
    const w = this.stageW > 0 ? this.stageW : 360;
    const heights: Array<number> = [];
    for (let i = 0; i < this.pages.length; i++) {
      const size = this.pageSizes[i];
      if (size !== undefined && size.width > 0 && size.height > 0) {
        heights.push(w * size.height / size.width);
      } else {
        heights.push(w * 1.45);
      }
    }
    this.webtoonHeights = heights;
  }

  private webtoonHeight(index: number): number {
    if (index >= 0 && index < this.webtoonHeights.length) {
      return this.webtoonHeights[index];
    }
    return (this.stageW > 0 ? this.stageW : 360) * 1.45;
  }

  private onWebtoonScroll(start: number): void {
    if (this.webtoonScrollLocked) {
      return;
    }
    if (start >= 0 && start < this.pages.length && start !== this.currentIndex) {
      this.currentIndex = start;
      this.refreshCurrentTranslation();
      this.persistProgress();
    }
  }

  // ---------------- 翻译 / 批量 / 导出 ----------------

  private async translateCurrentPage(): Promise<void> {
    if (this.translating || this.pages.length === 0) {
      return;
    }
    const page = this.pages[this.currentIndex];
    if (page === undefined) {
      return;
    }
    this.translating = true;
    this.menuVisible = false;
    this.settingsVisible = false;
    this.translatePhase = TranslatePhase.OCR;
    this.translatePct = 0;
    this.translateDone = 0;
    this.translateTotal = 0;
    this.translateDetail = '准备 OCR';
    try {
      const engine: EngineType = await PageTranslateService.loadEngineType();
      const onProgress = (p: TranslateProgress): void => {
        this.translatePhase = p.phase;
        this.translatePct = p.percent;
        this.translateDone = p.done;
        this.translateTotal = p.total;
        this.translateDetail = p.detail;
      };
      const pt = await PageTranslateService.translatePage(page.id, engine, onProgress);
      ReaderViewModel.putTranslation(pt);
      this.currentTranslated = pt.ocr.length > 0 && pt.translations.length > 0;
      this.transRev++;
      if (this.settings.mode !== ReaderMode.TRANS) {
        this.mutateSettings((s: ReaderSettings) => {
          s.mode = ReaderMode.TRANS;
        });
      }
      this.showToast(pt.failReason !== undefined && pt.failReason.length > 0
        ? '翻译完成（部分失败）：' + pt.failReason
        : '本页翻译完成');
    } catch (e) {
      this.showToast('翻译失败：' + e);
      Log.error('ReaderPage', 'translate page failed: ' + e);
    }
    this.translating = false;
  }

  private openBubbleEditor(lineIndex: number, text: string): void {
    this.editLine = lineIndex;
    this.editText = text;
    this.editVisible = true;
    this.editBusy = false;
    this.menuVisible = false;
    this.settingsVisible = false;
  }

  private async saveBubbleEdit(): Promise<void> {
    if (this.editBusy || this.editLine < 0) {
      return;
    }
    const page = this.pages[this.currentIndex];
    if (page === undefined) {
      return;
    }
    this.editBusy = true;
    try {
      await ReaderViewModel.updateTranslationLine(page.id, this.editLine, this.editText.trim());
      this.transRev++;
      this.currentTranslated = true;
      this.editVisible = false;
      this.showToast('译文已保存');
    } catch (e) {
      this.showToast('保存失败：' + e);
    }
    this.editBusy = false;
  }

  private onBatchState(s: BatchState): void {
    this.batchRunning = s.running;
    this.batchTotal = s.total;
    this.batchDone = s.done;
    this.batchFailed = s.failed;
    this.batchCurrent = s.currentPage;
    this.batchPhaseDetail = s.currentDetail;
    this.batchError = s.lastError;
    this.batchFailedIds = s.failedPageIds.slice();
    if (s.done !== this.lastBatchDone) {
      this.lastBatchDone = s.done;
      this.transRev++;
      this.refreshCurrentTranslation();
    }
  }

  private onBatchTap(): void {
    if (this.batchRunning) {
      ReaderViewModel.cancelBatch();
      this.showToast('已请求取消批量翻译（当前页收尾后停止）');
      return;
    }
    if (this.mangaId < 0) {
      return;
    }
    PageTranslateService.loadEngineType().then((engine: EngineType) => {
      ReaderViewModel.startBatch(this.mangaId, engine);
      this.showToast('已开始批量翻译');
    });
  }

  private retryBatchPage(pageId: number): void {
    ReaderViewModel.retryBatchPage(pageId).then(() => {
      this.transRev++;
      this.showToast('单页重试成功');
    }).catch((e: Object) => {
      this.showToast('单页重试失败：' + e);
    });
  }

  private runExport(mode: ExportMode): void {
    this.showExportModes = false;
    // 关闭阅读菜单/设置浮层：避免系统保存选择器返回时与页面内浮层状态互相干扰。
    this.menuVisible = false;
    this.settingsVisible = false;
    this.exportBusy = true;
    this.exportDone = 0;
    this.exportTotal = this.pages.length;
    Log.info('ReaderPage', 'export begin mode=' + mode + ' pages=' + this.pages.length);
    if (this.exportTimer >= 0) {
      clearTimeout(this.exportTimer);
    }
    // UI 兜底看门狗：ExportService 内部各阶段均有超时，这里再兜一层，绝不停在“正在导出”。
    this.exportTimer = setTimeout(() => {
      this.exportTimer = -1;
      if (this.exportBusy) {
        this.exportBusy = false;
        this.showToast('导出超时，请重试（详见 ExportService 日志）');
        Log.error('ReaderPage', 'export watchdog fired');
      }
    }, 180000);
    ReaderViewModel.exportManga(this.mangaId, mode, (done: number, total: number) => {
      this.exportDone = done;
      this.exportTotal = total;
    }).then((result: ExportResult) => {
      this.clearExportTimer();
      this.exportBusy = false;
      if (result.cancelled) {
        this.showToast('导出已取消');
        return;
      }
      Log.info('ReaderPage', 'export done: mode=' + mode + ' pages=' + result.exported
        + ' fallback=' + result.savedToAppDir);
      if (result.savedToAppDir) {
        this.showToast('导出完成（' + result.exported + ' 页），系统保存不可用，已存到应用目录 exports/'
          + ReaderPage.lastSegment(result.appDirPath));
        return;
      }
      this.showToast(result.untranslated > 0
        ? '导出完成（' + result.exported + ' 页），其中 ' + result.untranslated + ' 页未翻译以原图导出'
        : '导出完成（' + result.exported + ' 页）');
    }).catch((e: Object) => {
      this.clearExportTimer();
      this.exportBusy = false;
      this.showToast('导出失败：' + e);
      Log.error('ReaderPage', 'export failed: ' + e);
    });
  }

  private clearExportTimer(): void {
    if (this.exportTimer >= 0) {
      clearTimeout(this.exportTimer);
      this.exportTimer = -1;
    }
  }

  private static lastSegment(path: string): string {
    const idx = path.lastIndexOf('/');
    if (idx < 0) {
      return path;
    }
    return path.substring(idx + 1);
  }

  private openToc(): void {
    if (this.mangaId < 0) {
      return;
    }
    const params = makeMangaTocParams(this.mangaId, this.currentIndex);
    AppEnv.getInstance().navStack.pushPathByName(Routes.MANGA_TOC, params,
      (info: PopInfo) => {
        const jump = info.result as MangaTocJump;
        if (jump !== undefined && jump !== null && typeof jump.page === 'number' && jump.page >= 0) {
          this.menuVisible = false;
          this.jumpToReal(jump.page);
        }
      }, true);
  }

  // ---------------- Builders ----------------

  @Builder
  pageLayer(real: number) {
    if (real >= 0 && real < this.pages.length) {
      Column() {
        ReaderPageLayer({
        page: this.pages[real],
        pageIndex: real,
        mode: this.settings.mode,
        orientation: this.settings.orientation,
        vdir: this.settings.verticalDirection,
        fontMode: this.settings.fontSizeMode,
        fixedSize: this.settings.fixedFontSize,
        lineHeight: this.settings.lineHeightPercent,
        pageMargin: this.settings.margin,
        whiteMerge: this.settings.whiteMerge,
        filterInvert: this.settings.invert,
        filterGrayscale: this.settings.grayscale,
        filterContrast: this.settings.contrast,
        dimBrightness: this.settings.brightness,
        fitWidth: false,
        renderRev: this.renderRev,
        translationRev: this.transRev,
          onSingleTap: (x: number, width: number) => {
            this.tapZone(width > 0 ? x / width : 0.5);
          },
          onEditBubble: (lineIndex: number, text: string) => {
            this.openBubbleEditor(lineIndex, text);
          }
        })
          .width('100%')
          .height('100%')
      }
      .layoutWeight(1)
      .height('100%')
    }
  }

  @Builder
  slotView(slot: DisplaySlot, index: number) {
    Stack() {
      if (slot.double && slot.left >= 0 && slot.right >= 0) {
        Row() {
          this.pageLayer(slot.left)
          this.pageLayer(slot.right)
        }
        .width('100%')
        .height('100%')
      } else {
        Row() {
          this.pageLayer(slot.primary)
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .opacity((this.settings.animation === ReaderAnimation.COVER
      || this.settings.animation === ReaderAnimation.CURL) ? this.animOpacityAt(index) : 1)
    .scale({
      x: this.settings.animation === ReaderAnimation.COVER ? this.animScaleAt(index) : 1,
      y: this.settings.animation === ReaderAnimation.COVER ? this.animScaleAt(index) : 1
    })
    .translate(this.settings.animation === ReaderAnimation.COVER
      ? (this.isVerticalFlow()
        ? { x: 0, y: this.animTranslateAt(index) }
        : { x: this.animTranslateAt(index), y: 0 })
      : { x: 0, y: 0 })
    .rotate({
      x: this.isVerticalFlow() ? 1 : 0,
      y: this.isVerticalFlow() ? 0 : 1,
      z: 0,
      angle: this.settings.animation === ReaderAnimation.CURL ? this.animRotateAt(index) : 0,
      centerX: this.isVerticalFlow() ? '50%' : this.curlCenterX(index),
      centerY: this.isVerticalFlow() ? this.curlCenterY(index) : '50%',
      perspective: 900
    })
    .zIndex((this.settings.animation === ReaderAnimation.COVER
      || this.settings.animation === ReaderAnimation.CURL) ? this.animZAt(index) : 0)
  }

  @Builder
  webtoonItem(page: MangaPage, index: number) {
    Column() {
      ReaderPageLayer({
      page: page,
      pageIndex: index,
      mode: this.settings.mode,
      orientation: this.settings.orientation,
      vdir: this.settings.verticalDirection,
      fontMode: this.settings.fontSizeMode,
      fixedSize: this.settings.fixedFontSize,
      lineHeight: this.settings.lineHeightPercent,
      pageMargin: 0,
      whiteMerge: this.settings.whiteMerge,
      filterInvert: this.settings.invert,
      filterGrayscale: this.settings.grayscale,
      filterContrast: this.settings.contrast,
      dimBrightness: this.settings.brightness,
      fitWidth: true,
      renderRev: this.renderRev,
      translationRev: this.transRev,
        onSingleTap: (x: number, width: number) => {
          this.tapZone(width > 0 ? x / width : 0.5);
        },
        onEditBubble: (lineIndex: number, text: string) => {
          this.openBubbleEditor(lineIndex, text);
        }
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height(this.webtoonHeight(index))
  }

  @Builder
  stage() {
    if (this.settings.flow === ReaderFlow.WEBTOON) {
      List({ scroller: this.webtoonScroller }) {
        ForEach(this.pages, (page: MangaPage, index: number) => {
          ListItem() {
            this.webtoonItem(page, index)
          }
          .width('100%')
        }, (page: MangaPage) => page.id + '-w')
      }
      .cachedCount(2)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .onScrollIndex((start: number, end: number) => {
        this.onWebtoonScroll(start);
      })
    } else {
      Swiper(this.swiperController) {
        ForEach(this.slots, (slot: DisplaySlot, index: number) => {
          this.slotView(slot, index)
        }, (slot: DisplaySlot, index: number) => slot.key() + '-' + index + '-' + this.settings.flow)
      }
      .index(this.swiperIndex)
      .loop(false)
      .indicator(false)
      .cachedCount(1)
      .vertical(this.isVerticalFlow())
      .duration(this.settings.animation === ReaderAnimation.NONE ? 0 : 280)
      .curve(Curve.EaseOut)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.onSlotChanged(index);
      })
      .customContentTransition({
        timeout: 1000,
        transition: (proxy: SwiperContentTransitionProxy) => {
          this.applyTransition(proxy);
        }
      })
    }
  }

  private translatePhaseLabel(): string {
    if (this.translatePhase === TranslatePhase.OCR) {
      return 'OCR 识别阶段';
    }
    if (this.translatePhase === TranslatePhase.TRANSLATE) {
      return '翻译阶段';
    }
    return '保存译文';
  }

  @Builder
  translateProgressOverlay() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.translatePhaseLabel())
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(this.translatePct + '%')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.PRIMARY)
      }
      .width('100%')
      Progress({ value: this.translatePct, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(4)
        .color(ThemeTokens.PRIMARY)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      Text(this.translateDetail)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('78%')
    .padding(16)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.SURFACE)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: false,
      lightEffect: {}
    }))
    .border({ width: 1, color: ThemeTokens.SURFACE_VARIANT })
    .shadow({ radius: 18, color: '#26000000', offsetY: 6 })
  }

  @Builder
  progressPill() {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        Text(this.pageMetaText())
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(this.isLightBg() ? '#3A2E5C' : '#EDE8FA')
        if (this.autoTurning) {
          Text('自动')
            .fontSize(9)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY)
            .borderRadius(6)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        }
      }
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(3)
          .backgroundColor(this.isLightBg() ? '#22000000' : '#40FFFFFF')
          .borderRadius(2)
        Row()
          .width(Math.round(this.progressRatio() * 100) + '%')
          .height(3)
          .backgroundColor(ThemeTokens.PRIMARY)
          .borderRadius(2)
      }
      .width(96)
      .height(3)
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .borderRadius(ThemeTokens.RADIUS_PILL)
    .backgroundColor(this.chipBg())
    .onClick(() => {
      this.thumbVisible = true;
    })
  }

  @Builder
  transHint() {
    Column({ space: 10 }) {
      Text(this.ocrAvailable ? '该页尚未翻译' : '系统 OCR 能力不可用')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(this.fgColor())
        .textAlign(TextAlign.Center)
      if (this.ocrAvailable) {
        Button('翻译本页')
          .fontSize(ThemeTokens.FONT_SMALL)
          .height(32)
          .backgroundColor(ThemeTokens.PRIMARY)
          .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          .borderRadius(16)
          .padding({ left: 18, right: 18 })
          .onClick(() => {
            this.translateCurrentPage();
          })
      }
    }
    .width('70%')
    .padding(14)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(this.chipBg())
  }

  @Builder
  menuOverlay() {
    Column() {
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          this.menuVisible = false;
        })
      Column() {
        if (this.batchRunning || this.batchFailedIds.length > 0) {
          BatchPanel({
            running: this.batchRunning,
            total: this.batchTotal,
            done: this.batchDone,
            failed: this.batchFailed,
            currentPage: this.batchCurrent,
            phaseDetail: this.batchPhaseDetail,
            lastError: this.batchError,
            failedPageIds: this.batchFailedIds,
            onCancel: () => {
              ReaderViewModel.cancelBatch();
            },
            onRetryPage: (pageId: number) => {
              this.retryBatchPage(pageId);
            }
          })
            .margin({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING, bottom: 8 })
        }
        ReaderMenuView({
          title: this.mangaName,
          settings: this.settings,
          current: this.currentIndex,
          total: this.pages.length,
          translating: this.translating,
          ocrAvailable: this.ocrAvailable,
          batchRunning: this.batchRunning,
          exportBusy: this.exportBusy,
          autoTurning: this.autoTurning,
          onFlowChange: (flow: string) => {
            this.mutateSettings((s: ReaderSettings) => {
              s.flow = flow;
            });
          },
          onAnimChange: (anim: string) => {
            this.mutateSettings((s: ReaderSettings) => {
              s.animation = anim;
            });
          },
          onBgChange: (bg: string) => {
            this.mutateSettings((s: ReaderSettings) => {
              s.bg = bg;
            });
          },
          onModeChange: (mode: string) => {
            this.mutateSettings((s: ReaderSettings) => {
              s.mode = mode;
            });
          },
          onJump: (page: number) => {
            this.jumpToReal(page);
          },
          onOpenSettings: () => {
            this.menuVisible = false;
            this.settingsVisible = true;
          },
          onOpenThumbnails: () => {
            this.menuVisible = false;
            this.thumbVisible = true;
          },
          onOpenToc: () => {
            this.menuVisible = false;
            this.openToc();
          },
          onTranslatePage: () => {
            this.translateCurrentPage();
          },
          onBatch: () => {
            this.onBatchTap();
          },
          onExport: () => {
            this.showExportModes = true;
          },
          onToggleAuto: () => {
            this.toggleAutoTurn();
          },
          onBack: () => {
            this.menuVisible = false;
            AppEnv.getInstance().navStack.pop();
          },
          onClose: () => {
            this.menuVisible = false;
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .transition(Motion.overlay())
  }

  @Builder
  settingsOverlay() {
    Column() {
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          this.settingsVisible = false;
        })
      Column() {
        ReaderSettingsSheet({
          settings: this.settings,
          onSettingsChange: (next: ReaderSettings) => {
            this.commitSettings(next);
          },
          onClose: () => {
            this.settingsVisible = false;
          }
        })
          .height('78%')
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .transition(Motion.overlay())
  }

  @Builder
  thumbnailSheet() {
    Column({ space: 8 }) {
      Row() {
        Text('页面缩略图')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('第 ' + (this.currentIndex + 1) + ' / ' + this.pages.length + ' 页')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .width('100%')

      Grid() {
        LazyForEach(this.thumbSource, (page: MangaPage, index: number) => {
          GridItem() {
            Column({ space: 3 }) {
              Image(toMediaUri(page.imagePath))
                .width('100%')
                .aspectRatio(0.7)
                .objectFit(ImageFit.Cover)
                .borderRadius(ThemeTokens.RADIUS_SMALL)
                .border({
                  width: index === this.currentIndex ? 2 : 0,
                  color: ThemeTokens.PRIMARY,
                  radius: ThemeTokens.RADIUS_SMALL
                })
              Text('' + (index + 1))
                .fontSize(10)
                .fontColor(index === this.currentIndex ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_HINT)
            }
            .width('100%')
            .onClick(() => {
              this.thumbVisible = false;
              this.jumpToReal(index);
            })
          }
        }, (page: MangaPage) => 'thumb-' + page.id)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
      .columnsGap(8)
      .rowsGap(10)
      .cachedCount(10)
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .padding(ThemeTokens.PAGE_PADDING)
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
  }

  @Builder
  exportModeButton(label: string, desc: string, mode: ExportMode) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      Text(desc)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_HINT)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .onClick(() => {
      this.runExport(mode);
    })
  }

  @Builder
  exportModeDialog() {
    Column() {
      Column({ space: 14 }) {
        Text('导出 ZIP')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text('选择导出模式（命名沿用原页序）')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
        this.exportModeButton('仅原文', '原始页图直接归集', ExportMode.ORIGINAL_ONLY)
        this.exportModeButton('仅译文', '原图 + 译文覆盖合成', ExportMode.TRANSLATED_ONLY)
        this.exportModeButton('双语对照', '原文页与译文页按页序交替', ExportMode.BILINGUAL)
        Button('取消')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(16)
          .height(34)
          .padding({ left: 24, right: 24 })
          .onClick(() => {
            this.showExportModes = false;
          })
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('80%')
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  bubbleEditOverlay() {
    Column() {
      Column({ space: 12 }) {
        Text('校对译文')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        TextArea({ text: this.editText, placeholder: '输入译文' })
          .width('100%')
          .height(120)
          .fontSize(ThemeTokens.FONT_BODY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
          .onChange((value: string) => {
            this.editText = value;
          })
        Row({ space: 10 }) {
          Button('取消')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.editVisible = false;
            })
          Button(this.editBusy ? '保存中…' : '保存')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(34)
            .layoutWeight(1)
            .enabled(!this.editBusy)
            .onClick(() => {
              this.saveBubbleEdit();
            })
        }
        .width('100%')
      }
      .width('86%')
      .padding(ThemeTokens.PAGE_PADDING)
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor(ThemeTokens.SURFACE)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
    })
  }

  build() {
    NavDestination() {
      if (!this.loaded) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(ThemeTokens.PRIMARY)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.pages.length === 0) {
        Column({ space: 8 }) {
          Image($r('app.media.ic_tab_shelf'))
            .width(40)
            .height(40)
            .fillColor(ThemeTokens.TEXT_HINT)
          Text('没有页面数据')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.Bottom }) {
          this.stage()

          // 仅译文态且该页尚无译文：居中提示 + 一键翻译
          if (this.settings.mode === ReaderMode.TRANS && !this.currentTranslated && !this.translating
            && !this.menuVisible && !this.settingsVisible) {
            Column() {
              this.transHint()
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .hitTestBehavior(HitTestMode.Transparent)
          }

          if (this.translating) {
            Column() {
              this.translateProgressOverlay()
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .hitTestBehavior(HitTestMode.Transparent)
          }

          if (!this.menuVisible && !this.settingsVisible) {
            Column() {
              this.progressPill()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .margin({ bottom: 22 })
            .hitTestBehavior(HitTestMode.Transparent)
          }

          if (this.toast.length > 0) {
            Text(this.toast)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.WHITE)
              .textAlign(TextAlign.Center)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius(ThemeTokens.RADIUS_CARD)
              .backgroundColor('#CC000000')
              .align(Alignment.Top)
              .margin({ top: 24 })
              .onClick(() => {
                this.toast = '';
              })
          }

          if (this.exportBusy) {
            Text('正在导出 ' + this.exportDone + '/' + this.exportTotal + ' …')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.WHITE)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius(14)
              .backgroundColor('#CC000000')
              .margin({ top: 72 })
              .align(Alignment.Top)
          }

          if (this.menuVisible) {
            this.menuOverlay()
          }
          if (this.settingsVisible) {
            this.settingsOverlay()
          }
          if (this.showExportModes) {
            this.exportModeDialog()
          }
          if (this.editVisible) {
            this.bubbleEditOverlay()
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.bgColor())
        .onAreaChange((oldArea: Area, newArea: Area) => {
          const oldDouble = this.needDouble();
          this.stageW = newArea.width as number;
          this.stageH = newArea.height as number;
          if (this.loaded) {
            const newDouble = this.needDouble();
            if (newDouble !== oldDouble || this.slots.length === 0) {
              this.rebuildSlots(this.currentIndex);
            } else if (this.settings.flow === ReaderFlow.WEBTOON) {
              this.updateWebtoonHeights();
            }
          }
        })
        .bindSheet($$this.thumbVisible, this.thumbnailSheet(), {
          height: SheetSize.MEDIUM,
          dragBar: true,
          backgroundColor: ThemeTokens.SURFACE_SECONDARY,
          onDisappear: () => {
            this.thumbVisible = false;
          }
        })
      }
    }
    .hideTitleBar(true)
    .backgroundColor(this.bgColor())
    .onReady((ctx: NavDestinationContext) => {
      const params = asReaderParams(ctx.pathInfo.param as Object);
      this.init(params);
    })
    .onHidden(() => {
      this.persistProgress();
      this.stopAutoTurn();
    })
  }
}
