import { ThemeTokens, WindowSizeClass, observeBreakpoint, Log } from 'commons';
import { NovelChapter, TranslateStatus } from 'coremodel';
import { EngineType } from 'coretranslate';
import { NovelDisplayMode, NovelPage, Paginator } from 'corenovel';
import { asNovelReaderParams, makeNovelReaderParams, Routes } from '../common/Routes';
import { Artwork } from '../components/Artwork';
import { AppEnv } from '../common/AppEnv';
import { NovelBg, NovelBatchState, NovelReaderSession, NovelReaderSettings, NovelViewModel } from '../viewmodel/NovelViewModel';
import { NovelTranslateResult, NovelTranslateService } from '../service/NovelTranslateService';
import { ShelfViewModel } from '../viewmodel/ShelfViewModel';

const TAG = 'NovelReaderPage';
const BATCH_CHAPTERS: number = 5;

/**
 * 小说阅读器（对齐上游 novel/reader）：
 * - corenovel Paginator 分页文本渲染（字号/行距/边距/紫夜 6 档背景）；
 * - 点击左/右 1/3 翻页、中间弹菜单；章节 TOC；进度记忆（novel.last_read_chapter/offset）；
 * - 显示三态：原文 / 译文 / 双语（按段落对齐，未翻译段落回落原文）；
 * - 「翻译本章」调 coretranslate EngineRegistry，译文按段落覆盖；可批量翻译后续章节并显示进度；
 * - 宽屏（MD/LG）正文限宽 720vp 居中。
 */
@Component
export struct NovelReaderPage {
  @StorageProp('starflow_novel_toc_jump') @Watch('onTocJump') tocJump: string = '';
  @State novelId: number = -1;
  @State novelName: string = '';
  @State chapterTitle: string = '';
  @State loaded: boolean = false;
  @State chapters: Array<NovelChapter> = [];
  @State chapterIndex: number = 0;
  @State chapter: NovelChapter | undefined = undefined;
  @State displayMode: NovelDisplayMode = NovelDisplayMode.ORIGINAL;
  @State fontSize: number = 17;
  @State lineHeight: number = 30;
  @State marginVp: number = 18;
  @State bgKey: string = NovelBg.NOCTURNE;
  @State pages: Array<NovelPage> = [];
  @State pageIndex: number = 0;
  @State menuVisible: boolean = false;
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  @State translating: boolean = false;
  @State engineLabel: string = '必应';
  @State translateDone: number = 0;
  @State translateTotal: number = 0;
  @State batch: NovelBatchState = new NovelBatchState();
  @State toast: string = '';
  private stopBreakpoint: (() => void) | undefined = undefined;
  private areaWidth: number = 0;
  private areaHeight: number = 0;
  private contentWidth: number = 0;
  private contentHeight: number = 0;
  private pendingOffset: number = 0;
  private paginated: boolean = false;
  private toastTimer: number = -1;
  private active: boolean = true;

  aboutToAppear(): void {
    this.active = true;
    this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
      this.sizeClass = c;
      this.onAreaChangedInternal();
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
    this.persistProgress();
    // 返回书架时让小说书架重载进度（读到第 N 章）；进度写入是异步的，延迟再通知一次避免读到旧值。
    ShelfViewModel.notifyChanged();
    setTimeout(() => {
      ShelfViewModel.notifyChanged();
    }, 500);
  }

  /** 从目录页跳章（AppStorage 桥接，避免依赖 pop 回调差异）。 */
  onTocJump(): void {
    if (this.tocJump.length === 0) {
      return;
    }
    const parts = this.tocJump.split(':');
    if (parts.length < 2) {
      return;
    }
    const id = Number(parts[0]);
    const index = Number(parts[1]);
    if (isNaN(id) || isNaN(index) || id !== this.novelId) {
      return;
    }
    this.menuVisible = false;
    this.loadChapter(index, 0);
  }

  private async init(params: number, chapterIndex: number): Promise<void> {
    this.novelId = params;
    const session: NovelReaderSession = await NovelViewModel.loadSession(params, chapterIndex);
    this.novelName = session.novelName;
    this.chapters = session.chapters;
    this.chapterIndex = session.chapterIndex;
    this.chapter = session.chapter;
    this.pendingOffset = session.offset;
    this.chapterTitle = NovelViewModel.chapterLabel(session.chapter, session.chapterIndex);
    const settings = await NovelViewModel.loadReaderSettings();
    this.fontSize = settings.fontSize;
    this.lineHeight = settings.lineHeight;
    this.marginVp = settings.margin;
    this.bgKey = settings.bgKey;
    this.displayMode = settings.displayMode;
    try {
      const engine: EngineType = await NovelTranslateService.loadEngineType();
      this.engineLabel = NovelTranslateService.engineLabel(engine);
    } catch (e) {
      this.engineLabel = '必应';
    }
    this.loaded = true;
    this.onAreaChangedInternal();
  }

  private buildSettings(): NovelReaderSettings {
    const settings = new NovelReaderSettings();
    settings.fontSize = this.fontSize;
    settings.lineHeight = this.lineHeight;
    settings.margin = this.marginVp;
    settings.bgKey = this.bgKey;
    settings.displayMode = this.displayMode;
    return settings;
  }

  private bgColor(): string {
    return NovelBg.color(this.bgKey);
  }

  private fgColor(): string {
    return NovelBg.textColor(this.bgKey);
  }

  private hintColor(): string {
    return NovelBg.secondaryColor(this.bgKey);
  }

  // ---------- 布局与分页 ----------

  private onAreaChangedInternal(): void {
    this.computeContentSize();
    if (!this.loaded || this.chapter === undefined) {
      return;
    }
    if (this.paginated) {
      const offset = this.currentOffset();
      this.repaginate(offset);
    } else {
      this.repaginate(this.pendingOffset);
    }
  }

  private computeContentSize(): void {
    const limit = 720;
    let width = this.areaWidth;
    if (width <= 0) {
      width = 320;
    }
    if (width > limit) {
      width = limit;
    }
    this.contentWidth = Math.max(80, width - this.marginVp * 2);
    const bodyHeight = this.areaHeight > 0 ? this.areaHeight : 480;
    // 底部进度条 30vp + 上下内边距 14vp + 半行余量，避免最后一行被裁切。
    this.contentHeight = Math.max(100, bodyHeight - 52);
  }

  private currentOffset(): number {
    if (this.pageIndex >= 0 && this.pageIndex < this.pages.length) {
      return this.pages[this.pageIndex].start;
    }
    return 0;
  }

  private repaginate(offset: number): void {
    if (this.chapter === undefined) {
      this.pages = [];
      return;
    }
    this.computeContentSize();
    const text = NovelViewModel.displayText(this.chapter, this.displayMode);
    const settings = this.buildSettings();
    const pages = NovelViewModel.paginate(text, this.contentWidth, this.contentHeight, settings, 0);
    this.pages = pages;
    this.pageIndex = Paginator.pageOfOffset(pages, offset);
    if (this.pageIndex < 0) {
      this.pageIndex = 0;
    }
    if (this.pageIndex > pages.length - 1) {
      this.pageIndex = Math.max(0, pages.length - 1);
    }
    this.paginated = true;
    this.saveProgress();
  }

  private async loadChapter(index: number, offset: number): Promise<void> {
    if (this.chapters.length === 0) {
      return;
    }
    let target = index;
    if (target < 0) {
      target = 0;
    }
    if (target > this.chapters.length - 1) {
      target = this.chapters.length - 1;
    }
    this.chapterIndex = target;
    const chapter = await NovelViewModel.loadChapter(this.novelId, target);
    this.chapter = chapter;
    this.chapterTitle = NovelViewModel.chapterLabel(chapter, target);
    this.paginated = false;
    this.repaginate(0);
    if (offset < 0) {
      // 打开上一章最后一页
      this.pageIndex = Math.max(0, this.pages.length - 1);
    } else if (offset === 0) {
      this.pageIndex = 0;
    } else {
      this.pageIndex = Paginator.pageOfOffset(this.pages, offset);
    }
    this.saveProgress();
  }

  // ---------- 翻页与进度 ----------

  private nextPage(): void {
    if (this.pages.length === 0) {
      return;
    }
    if (this.pageIndex + 1 < this.pages.length) {
      this.pageIndex++;
      this.saveProgress();
      return;
    }
    if (this.chapterIndex + 1 < this.chapters.length) {
      this.loadChapter(this.chapterIndex + 1, 0);
    } else {
      this.showToast('已是最后一章');
    }
  }

  private prevPage(): void {
    if (this.pages.length === 0) {
      return;
    }
    if (this.pageIndex > 0) {
      this.pageIndex--;
      this.saveProgress();
      return;
    }
    if (this.chapterIndex > 0) {
      this.loadChapter(this.chapterIndex - 1, -1);
    } else {
      this.showToast('已是第一章');
    }
  }

  private saveProgress(): void {
    if (this.novelId < 0) {
      return;
    }
    NovelViewModel.saveProgress(this.novelId, this.chapterIndex, this.currentOffset());
  }

  private persistProgress(): void {
    this.saveProgress();
  }

  private onStageClick(x: number): void {
    if (this.menuVisible) {
      this.menuVisible = false;
      return;
    }
    const width = this.areaWidth > 0 ? this.areaWidth : 360;
    const third = width / 3;
    if (x < third) {
      this.prevPage();
    } else if (x > third * 2) {
      this.nextPage();
    } else {
      this.menuVisible = true;
    }
  }

  private showToast(msg: string): void {
    this.toast = msg;
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout(() => {
      this.toast = '';
      this.toastTimer = -1;
    }, 2600);
  }

  // ---------- 设置 ----------

  private applySettings(): void {
    const offset = this.currentOffset();
    NovelViewModel.saveReaderSettings(this.buildSettings());
    this.repaginate(offset);
  }

  private changeFontSize(delta: number): void {
    let size = this.fontSize + delta;
    if (size < 12) {
      size = 12;
    }
    if (size > 30) {
      size = 30;
    }
    this.fontSize = size;
    let lh = this.lineHeight;
    if (lh < size * 1.3) {
      lh = size * 1.7;
    }
    if (lh > size * 3.2) {
      lh = size * 3.2;
    }
    this.lineHeight = Math.round(lh);
    this.applySettings();
  }

  private changeLineHeight(delta: number): void {
    let lh = this.lineHeight + delta;
    const min = this.fontSize * 1.25;
    const max = this.fontSize * 3.2;
    if (lh < min) {
      lh = min;
    }
    if (lh > max) {
      lh = max;
    }
    this.lineHeight = Math.round(lh);
    this.applySettings();
  }

  private changeMargin(delta: number): void {
    let m = this.marginVp + delta;
    if (m < 8) {
      m = 8;
    }
    if (m > 48) {
      m = 48;
    }
    this.marginVp = m;
    this.applySettings();
  }

  private changeBg(key: string): void {
    this.bgKey = key;
    NovelViewModel.saveReaderSettings(this.buildSettings());
  }

  private setDisplayMode(mode: NovelDisplayMode): void {
    this.displayMode = mode;
    if (mode !== NovelDisplayMode.ORIGINAL && !this.chapterHasTranslation()) {
      this.showToast('本章尚未翻译，暂时显示原文');
    }
    this.applySettings();
  }

  private chapterHasTranslation(): boolean {
    const chapter = this.chapter;
    if (chapter === undefined || chapter.translatedContent === undefined) {
      return false;
    }
    return chapter.translatedContent.length > 0;
  }

  private chapterStatusShort(): string {
    const chapter = this.chapter;
    if (chapter === undefined) {
      return '';
    }
    if (chapter.translateStatus === TranslateStatus.DONE) {
      return '已译';
    }
    if (chapter.translateStatus === TranslateStatus.PARTIAL_FAILED) {
      return '部分译';
    }
    return '';
  }

  private chapterStatusLabel(): string {
    const chapter = this.chapter;
    if (chapter === undefined) {
      return '';
    }
    if (chapter.translateStatus === TranslateStatus.DONE) {
      return '本章已翻译';
    }
    if (chapter.translateStatus === TranslateStatus.PARTIAL_FAILED) {
      return chapter.failReason !== undefined && chapter.failReason.length > 0
        ? '本章部分失败：' + chapter.failReason
        : '本章部分翻译';
    }
    return '本章未翻译';
  }

  // ---------- 翻译 ----------

  private async translateChapter(): Promise<void> {
    if (this.translating) {
      return;
    }
    const chapter = this.chapter;
    if (chapter === undefined) {
      return;
    }
    this.translating = true;
    this.translateDone = 0;
    this.translateTotal = 0;
    try {
      const engine: EngineType = await NovelTranslateService.loadEngineType();
      const result: NovelTranslateResult = await NovelTranslateService.translateChapter(chapter, engine,
        (done: number, total: number) => {
          this.translateDone = done;
          this.translateTotal = total;
        }, () => false);
      const fresh = await NovelViewModel.loadChapter(this.novelId, this.chapterIndex);
      this.chapter = fresh;
      this.chapters = await NovelViewModel.loadChapterList(this.novelId);
      if (result.translatedParagraphs > 0) {
        this.displayMode = NovelDisplayMode.TRANSLATED;
        this.applySettings();
        this.showToast(result.failedParagraphs > 0
          ? '本章翻译完成（' + result.failedParagraphs + ' 段失败：' + result.failReason + '）'
          : '本章翻译完成');
      } else {
        this.showToast('翻译失败：' + (result.failReason.length > 0 ? result.failReason : '引擎无返回'));
      }
    } catch (e) {
      this.showToast('翻译失败：' + e);
      Log.error(TAG, 'translate chapter failed: ' + e);
    }
    this.translating = false;
  }

  private startBatch(): void {
    if (this.batch.running || this.novelId < 0) {
      return;
    }
    const self = this;
    NovelTranslateService.loadEngineType().then((engine: EngineType) => {
      NovelViewModel.startBatch(self.novelId, self.chapterIndex, BATCH_CHAPTERS, engine,
        (s: NovelBatchState) => {
          if (!self.active) {
            return;
          }
          self.batch = s;
          if (!s.running) {
            if (s.chaptersTotal === 0) {
              self.showToast('后面没有更多章节了');
            } else if (s.failedChapters > 0) {
              self.showToast('批量翻译结束：' + s.chaptersDone + ' 章，' + s.failedChapters
                + ' 章部分失败');
            } else {
              self.showToast('批量翻译完成：' + s.chaptersDone + ' 章');
            }
            self.refreshToc();
          }
        });
      self.showToast('已开始翻译后续 ' + BATCH_CHAPTERS + ' 章');
    });
  }

  private cancelBatch(): void {
    NovelViewModel.cancelBatch();
    this.showToast('已请求取消（当前段收尾后停止）');
  }

  private async refreshToc(): Promise<void> {
    try {
      this.chapters = await NovelViewModel.loadChapterList(this.novelId);
    } catch (e) {
    }
  }

  // ---------- UI ----------

  @Builder
  menuHeader() {
    Row({ space: 8 }) {
      Button() {
        Image(Artwork.ICON_ARROW_LEFT)
          .width(18)
          .height(18)
          .fillColor(ThemeTokens.TEXT_PRIMARY)
      }
      .backgroundColor(ThemeTokens.SURFACE_HIGH)
      .borderRadius(16)
      .height(32)
      .width(38)
      .padding(0)
      .onClick(() => {
        this.menuVisible = false;
        this.persistProgress();
        AppEnv.getInstance().navStack.pop();
      })
      Column({ space: 1 }) {
        Text(this.chapterTitle)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.novelName + ' · 第 ' + (this.chapterIndex + 1) + '/' + this.chapters.length + ' 章')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.engineLabel)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_TERTIARY)
    }
    .width('100%')
  }

  @Builder
  menuPanel() {
    Column({ space: 12 }) {
      this.menuHeader()
      Row({ space: 10 }) {
        Button() {
          Row({ space: 5 }) {
            Image(Artwork.ICON_READER_TOC)
              .width(14)
              .height(14)
              .fillColor(ThemeTokens.TEXT_PRIMARY)
            Text('目录')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
          }
        }
        .backgroundColor(ThemeTokens.SURFACE_HIGH)
        .borderRadius(16)
        .height(32)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          this.menuVisible = false;
          AppEnv.getInstance().navStack.pushPathByName(Routes.NOVEL_TOC,
            makeNovelReaderParams(this.novelId, this.chapterIndex));
        })
        Button() {
          Row({ space: 5 }) {
            Image(Artwork.ICON_READER_TEXT)
              .width(14)
              .height(14)
              .fillColor(this.translating ? ThemeTokens.TEXT_HINT : ThemeTokens.WHITE)
            Text(this.translating ? '翻译中…' : '翻译本章')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(this.translating ? ThemeTokens.TEXT_HINT : ThemeTokens.WHITE)
          }
        }
        .backgroundColor(this.translating ? ThemeTokens.SURFACE_HIGH : ThemeTokens.PRIMARY)
        .borderRadius(16)
        .height(32)
        .padding({ left: 12, right: 12 })
        .enabled(!this.translating)
        .onClick(() => {
          this.translateChapter();
        })
        Blank()
        Text(this.chapterStatusShort())
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text('显示')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width(34)
        this.modeButton('原文', NovelDisplayMode.ORIGINAL)
        this.modeButton('译文', NovelDisplayMode.TRANSLATED)
        this.modeButton('双语', NovelDisplayMode.BILINGUAL)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text('字号')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width(34)
        this.stepButton('-', () => {
          this.changeFontSize(-1);
        })
        Text('' + this.fontSize)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .width(30)
          .textAlign(TextAlign.Center)
        this.stepButton('+', () => {
          this.changeFontSize(1);
        })
        Text('行距')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .margin({ left: 10 })
          .width(30)
        this.stepButton('-', () => {
          this.changeLineHeight(-2);
        })
        Text('' + this.lineHeight)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .width(30)
          .textAlign(TextAlign.Center)
        this.stepButton('+', () => {
          this.changeLineHeight(2);
        })
      }
      .width('100%')

      Row({ space: 8 }) {
        Text('边距')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width(34)
        this.stepButton('-', () => {
          this.changeMargin(-4);
        })
        Text('' + this.marginVp)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .width(30)
          .textAlign(TextAlign.Center)
        this.stepButton('+', () => {
          this.changeMargin(4);
        })
        Blank()
        Text('正文 ' + this.fontSize + 'fp / 行高 ' + this.lineHeight + 'vp')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .width('100%')

      Row({ space: 10 }) {
        Text('背景')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width(34)
        ForEach(NovelBg.KEYS, (key: string) => {
          Stack() {
            Circle()
              .width(22)
              .height(22)
              .fill(NovelBg.color(key))
              .stroke(this.bgKey === key ? ThemeTokens.PRIMARY : ThemeTokens.DIVIDER)
              .strokeWidth(this.bgKey === key ? 2 : 1)
            if (this.bgKey === key) {
              Text('✓')
                .fontSize(10)
                .fontColor(this.bgKey === NovelBg.PAPER || this.bgKey === NovelBg.WHITE
                  ? ThemeTokens.PRIMARY : ThemeTokens.WHITE)
            }
          }
          .width(28)
          .height(28)
          .onClick(() => {
            this.changeBg(key);
          })
        }, (key: string) => key)
        Text(NovelBg.label(this.bgKey))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
      }
      .width('100%')

      Row({ space: 10 }) {
        Text(this.chapterStatusLabel())
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.translating) {
          Text('已翻译 ' + this.translateDone + '/' + this.translateTotal + ' 段')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.PRIMARY_SOFT)
        }
      }
      .width('100%')

      if (this.batch.running) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('批量翻译：' + this.batch.chapterTitle)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text((this.batch.chaptersDone + 1) + '/' + this.batch.chaptersTotal)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_HINT)
            Button('取消')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.RED)
              .backgroundColor(Color.Transparent)
              .borderWidth(1)
              .borderColor(ThemeTokens.RED)
              .borderRadius(12)
              .height(26)
              .padding({ left: 10, right: 10 })
              .onClick(() => {
                this.cancelBatch();
              })
          }
          .width('100%')
          Progress({
            value: this.batch.chapterDone,
            total: this.batch.chapterTotal > 0 ? this.batch.chapterTotal : 1,
            type: ProgressType.Linear
          })
            .color(ThemeTokens.PRIMARY)
            .backgroundColor(ThemeTokens.SURFACE_HIGH)
            .height(4)
            .borderRadius(2)
            .width('100%')
        }
        .width('100%')
      } else {
        Button('批量翻译后续 ' + BATCH_CHAPTERS + ' 章')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(ThemeTokens.SURFACE_HIGH)
          .borderRadius(14)
          .height(30)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            this.startBatch();
          })
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: 720 })
    .padding({ left: 16, right: 16, top: 14, bottom: 22 })
    .borderRadius({ topLeft: 20, topRight: 20 })
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  modeButton(label: string, mode: NovelDisplayMode) {
    Text(label)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(this.displayMode === mode ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      .backgroundColor(this.displayMode === mode ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_HIGH)
      .borderRadius(14)
      .height(28)
      .padding({ left: 14, right: 14 })
      .onClick(() => {
        this.setDisplayMode(mode);
      })
  }

  @Builder
  stepButton(label: string, onTap: () => void) {
    Text(label)
      .fontSize(ThemeTokens.FONT_CAPTION)
      .fontColor(ThemeTokens.TEXT_PRIMARY)
      .width(28)
      .height(28)
      .textAlign(TextAlign.Center)
      .borderRadius(8)
      .backgroundColor(ThemeTokens.SURFACE_HIGH)
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  bodyText() {
    Text(this.pages.length > 0 && this.pageIndex < this.pages.length
      ? this.pages[this.pageIndex].text : '本章内容为空')
      .fontSize(this.fontSize)
      .lineHeight(this.lineHeight)
      .fontColor(this.fgColor())
      .textAlign(TextAlign.Start)
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .padding({ top: 6 })
      .copyOption(CopyOptions.LocalDevice)
      .onClick((event: ClickEvent) => {
        this.onStageClick(event.x);
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
      } else if (this.chapter === undefined) {
        Column({ space: 8 }) {
          Text('没有可阅读的章节')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.Bottom }) {
          Row() {
            Column() {
              this.bodyText()
              Row() {
                Text(this.chapterTitle)
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(this.hintColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(NovelViewModel.pageLabel(this.pageIndex, this.pages.length)
                  + ' · ' + (this.chapterIndex + 1) + '/' + this.chapters.length)
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(this.hintColor())
              }
              .width('100%')
              .height(30)
              .padding({ left: 2, right: 2 })
            }
            .width('100%')
            .height('100%')
            .padding({ left: this.marginVp, right: this.marginVp, top: 8, bottom: 6 })
            .constraintSize({ maxWidth: 720 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)

          if (this.toast.length > 0) {
            Text(this.toast)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.WHITE)
              .textAlign(TextAlign.Center)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius(ThemeTokens.RADIUS_CARD)
              .backgroundColor('#CC000000')
              .align(Alignment.Top)
              .margin({ top: 14 })
              .onClick(() => {
                this.toast = '';
              })
          }

          if (this.menuVisible) {
            Column() {
              Blank()
              Row() {
                this.menuPanel()
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
            .width('100%')
            .height('100%')
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.bgColor())
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.areaWidth = newArea.width as number;
          this.areaHeight = newArea.height as number;
          this.onAreaChangedInternal();
        })
      }
    }
    .hideTitleBar(true)
    .backgroundColor(this.bgColor())
    .onReady((ctx: NavDestinationContext) => {
      const params = asNovelReaderParams(ctx.pathInfo.param as Object);
      this.init(params.novelId, params.chapterIndex !== undefined ? params.chapterIndex : -1);
    })
    .onHidden(() => {
      this.persistProgress();
    })
  }
}