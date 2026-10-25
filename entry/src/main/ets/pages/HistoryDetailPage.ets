import { uiMaterial } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { preferences } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  DisplayRect,
  FontSizeMode,
  LayoutEngine,
  OverlayRenderer,
  RenderOptions,
  RenderOrientation,
  VerticalDirection,
  containFit,
  makeOverlayRegion,
  pixelToDisplay
} from 'corerender';
import { EngineType } from 'coretranslate';
import { Log, ThemeTokens, WindowSizeClass, observeBreakpoint, toMediaUri } from 'commons';
import { Artwork } from '../components/Artwork';
import { EmptyState } from '../components/EmptyState';
import { AppEnv } from '../common/AppEnv';
import {
  HistoryFullscreenParams,
  Routes,
  asHistoryDetailParams
} from '../common/Routes';
import { PageTranslateService } from '../service/PageTranslateService';
import { ExportMode } from '../service/ExportService';
import { HistoryDetailData, HistoryKind } from '../service/HistoryService';
import { HistoryExportResult, HistoryExportService } from '../service/HistoryExportService';
import { HistoryViewModel } from '../viewmodel/HistoryViewModel';

const PREF_FILE = 'starflow_reader';
const KEY_ORIENT = 'render_orientation';
const KEY_VDIR = 'render_direction';
const KEY_FONT_MODE = 'render_font_mode';
const KEY_FONT_SIZE = 'render_font_size';

/** 一行原文 / 译文对照。 */
class TranslationPair {
  original: string = '';
  translated: string = '';
}

/**
 * 历史详情页（task-6）：
 * 按 kind/refId 读取记录——漫画页展示原图 + 译文覆盖（corerender 只读排版），
 * 小说章节与文本翻译展示原文 / 译文对照；支持重新翻译（仅漫画页）、复制、
 * 导出所在组（漫画 ZIP / 小说与文本 TXT）与全屏浏览。
 */
@Component
export struct HistoryDetailPage {
  @State kind: number = HistoryKind.MANGA_PAGE;
  @State refId: number = -1;
  @State loading: boolean = true;
  @State found: boolean = false;
  @State detail: HistoryDetailData = new HistoryDetailData();
  @State pairs: Array<TranslationPair> = [];
  @State areaWidth: number = 0;
  @State areaHeight: number = 0;
  @State pageWidth: number = 0;
  @State pageHeight: number = 0;
  @State busy: boolean = false;
  @State busyText: string = '';
  @State toast: string = '';
  @State showExportModes: boolean = false;
  @State isWide: boolean = false;
  @State exportDone: number = 0;
  @State exportTotal: number = 0;
  private canvasReady: boolean = false;
  private immersiveSupported: boolean = false;
  private orientation: number = 1;
  private vdir: number = 0;
  private fontMode: number = 0;
  private fixedSize: number = 16;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private overlayCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToAppear(): void {
    this.immersiveSupported = uiMaterial.isImmersiveMaterialSupported();
    this.stopBreakpoint = observeBreakpoint((sizeClass: WindowSizeClass) => {
      this.isWide = sizeClass === WindowSizeClass.LG;
    });
  }

  aboutToDisappear(): void {
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  // -------------------------------------------------------------------------
  // 加载
  // -------------------------------------------------------------------------

  private async init(kind: number, refId: number): Promise<void> {
    this.kind = kind;
    this.refId = refId;
    this.loading = true;
    try {
      this.detail = await HistoryViewModel.loadDetail(kind, refId);
      this.found = this.detail.found;
      if (this.found) {
        await this.loadRenderSettings();
        this.syncPairs();
        if (kind === HistoryKind.MANGA_PAGE) {
          await this.loadImageSize(this.detail.imagePath);
        }
      }
    } catch (e) {
      this.showToast('加载失败：' + HistoryDetailPage.readableError(e));
    }
    this.loading = false;
    this.drawOverlay();
  }

  private async loadRenderSettings(): Promise<void> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      this.orientation = pref.getSync(KEY_ORIENT, 1) as number;
      this.vdir = pref.getSync(KEY_VDIR, 0) as number;
      this.fontMode = pref.getSync(KEY_FONT_MODE, 0) as number;
      this.fixedSize = pref.getSync(KEY_FONT_SIZE, 16) as number;
    } catch (e) {
      // 使用默认排版设置
    }
  }

  private async loadImageSize(path: string): Promise<void> {
    let source: image.ImageSource | undefined = undefined;
    try {
      source = image.createImageSource(toMediaUri(path));
      if (source === undefined || source === null) {
        return;
      }
      const info = await source.getImageInfo();
      this.pageWidth = info.size.width;
      this.pageHeight = info.size.height;
    } catch (e) {
      Log.warn('HistoryDetailPage', 'image size failed: ' + HistoryDetailPage.readableError(e));
    } finally {
      if (source !== undefined) {
        try {
          source.release();
        } catch (ignore) {
        }
      }
    }
  }

  private syncPairs(): void {
    const pairs: Array<TranslationPair> = [];
    const pt = this.detail.translation;
    if (pt !== undefined) {
      for (let i = 0; i < pt.ocr.length; i++) {
        const pair = new TranslationPair();
        pair.original = pt.ocr[i].text;
        pair.translated = i < pt.translations.length ? pt.translations[i] : '';
        pairs.push(pair);
      }
    }
    this.pairs = pairs;
  }

  private buildRenderOptions(): RenderOptions {
    const options: RenderOptions = {
      orientation: this.orientation === 0 ? RenderOrientation.HORIZONTAL : RenderOrientation.VERTICAL,
      verticalDirection: this.vdir === 0 ? VerticalDirection.RTL : VerticalDirection.LTR,
      fontSizeMode: this.fontMode === 0 ? FontSizeMode.AUTO : FontSizeMode.FIXED,
      fixedFontSize: this.fixedSize,
      padding: 4
    };
    return options;
  }

  /** 译文覆盖：OCR 原始像素坐标 → contain 显示坐标 → 白块 + 译文（只读渲染）。 */
  private drawOverlay(): void {
    if (!this.canvasReady) {
      return;
    }
    const width = this.areaWidth;
    const height = this.areaHeight;
    const ctx = this.overlayCtx;
    if (width > 0 && height > 0) {
      ctx.clearRect(0, 0, width, height);
    }
    if (this.kind !== HistoryKind.MANGA_PAGE || width <= 0 || height <= 0) {
      return;
    }
    if (this.pageWidth <= 0 || this.pageHeight <= 0) {
      return;
    }
    const translation = this.detail.translation;
    if (translation === undefined || translation.ocr.length === 0) {
      return;
    }
    const fit = containFit(this.pageWidth, this.pageHeight, width, height);
    const options = this.buildRenderOptions();
    for (let i = 0; i < translation.ocr.length; i++) {
      const region = translation.ocr[i];
      const text = i < translation.translations.length ? translation.translations[i] : '';
      if (text.length === 0) {
        continue;
      }
      const box: DisplayRect = pixelToDisplay(region.box, fit.scale, fit.dx, fit.dy);
      const overlayRegion = makeOverlayRegion(box, region.text, text);
      const layout = LayoutEngine.layout(text, box, options);
      OverlayRenderer.drawRegion(ctx, overlayRegion, layout);
    }
  }

  // -------------------------------------------------------------------------
  // 操作
  // -------------------------------------------------------------------------

  private async retranslatePage(): Promise<void> {
    if (this.busy || this.kind !== HistoryKind.MANGA_PAGE) {
      return;
    }
    this.busy = true;
    this.busyText = '正在重新翻译…';
    try {
      const engine: EngineType = await PageTranslateService.loadEngineType();
      const pt = await PageTranslateService.retryPage(this.detail.pageId, engine);
      this.detail.translation = pt;
      await this.loadRenderSettings();
      this.syncPairs();
      this.drawOverlay();
      const fail = pt.failReason !== undefined && pt.failReason.length > 0;
      this.showToast(fail ? '重新翻译完成（部分失败）：' + pt.failReason : '重新翻译完成');
    } catch (e) {
      this.showToast('重新翻译失败：' + HistoryDetailPage.readableError(e));
      // 失败时 PageTranslateService 会落一条失败记录，重新读取以呈现数据库真实状态。
      try {
        const latest = await HistoryViewModel.loadDetail(this.kind, this.refId);
        if (latest.found) {
          this.detail = latest;
          this.syncPairs();
          this.drawOverlay();
        }
      } catch (ignore) {
      }
    } finally {
      this.busy = false;
    }
  }

  private async copyContent(): Promise<void> {
    const text = this.buildCopyText();
    if (text.length === 0) {
      this.showToast('暂无译文可复制');
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.showToast('已复制到剪贴板');
    } catch (e) {
      this.showToast('复制失败：' + HistoryDetailPage.readableError(e));
    }
  }

  private buildCopyText(): string {
    if (this.kind === HistoryKind.MANGA_PAGE) {
      let text = '';
      for (const pair of this.pairs) {
        if (pair.translated.length === 0) {
          continue;
        }
        text += pair.original + '\n' + pair.translated + '\n\n';
      }
      return text;
    }
    if (this.kind === HistoryKind.NOVEL_CHAPTER) {
      if (this.detail.translatedText.length > 0) {
        return this.detail.translatedText;
      }
      return this.detail.sourceText;
    }
    return '【原文】\n' + this.detail.sourceText + '\n\n【译文】\n' + this.detail.translatedText;
  }

  private async exportGroup(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.kind === HistoryKind.MANGA_PAGE) {
      this.showExportModes = true;
      return;
    }
    this.busy = true;
    this.busyText = '正在生成 TXT…';
    try {
      let result: HistoryExportResult;
      if (this.kind === HistoryKind.NOVEL_CHAPTER) {
        result = await HistoryExportService.exportNovelGroup(this.detail.novelId);
      } else {
        result = await HistoryExportService.exportTextGroup(this.detail.groupKey);
      }
      if (result.cancelled) {
        this.showToast('已取消导出');
      } else {
        this.showToast('已导出 ' + result.exported + ' 条记录');
      }
    } catch (e) {
      this.showToast('导出失败：' + HistoryDetailPage.readableError(e));
    } finally {
      this.busy = false;
    }
  }

  private async exportManga(mode: ExportMode): Promise<void> {
    this.showExportModes = false;
    this.busy = true;
    this.busyText = '正在导出…';
    this.exportDone = 0;
    this.exportTotal = 0;
    try {
      const result: HistoryExportResult = await HistoryExportService.exportMangaGroup(
        this.detail.mangaId, mode,
        (done: number, total: number) => {
          this.exportDone = done;
          this.exportTotal = total;
          this.busyText = '正在导出 ' + done + '/' + total + ' 页…';
        });
      if (result.cancelled) {
        this.showToast('已取消导出');
      } else if (result.untranslated > 0) {
        this.showToast('已导出 ' + result.exported + ' 页（' + result.untranslated + ' 页未翻译，已用原图）');
      } else {
        this.showToast('已导出 ' + result.exported + ' 页');
      }
    } catch (e) {
      this.showToast('导出失败：' + HistoryDetailPage.readableError(e));
    } finally {
      this.busy = false;
      this.exportTotal = 0;
      this.exportDone = 0;
    }
  }

  private openFullscreen(): void {
    if (this.detail.groupKey.length === 0) {
      return;
    }
    const params: HistoryFullscreenParams = { sessionId: this.detail.groupKey };
    AppEnv.getInstance().navStack.pushPathByName(Routes.HISTORY_FULLSCREEN, params);
  }

  private showToast(message: string): void {
    this.toast = message;
    setTimeout(() => {
      if (this.toast === message) {
        this.toast = '';
      }
    }, 2600);
  }

  private static readableError(e: Object): string {
    const err = e as Error;
    if (err !== undefined && err !== null && err.message !== undefined && err.message.length > 0) {
      return err.message;
    }
    return '未知错误';
  }

  // -------------------------------------------------------------------------
  // 构建
  // -------------------------------------------------------------------------

  @Builder
  summaryCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(HistoryViewModel.kindName(this.detail.kind))
          .fontSize(10)
          .fontColor(ThemeTokens.ACCENT)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(5)
          .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
        Text(HistoryViewModel.statusText(this.detail.status))
          .fontSize(10)
          .fontColor(HistoryViewModel.statusColor(this.detail.status))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(5)
          .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
        Blank()
        Text(HistoryViewModel.formatDateTime(this.detail.time))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .width('100%')

      Text(this.detail.title)
        .fontSize(ThemeTokens.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.detail.subtitle)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .width('100%')

      Row({ space: 10 }) {
        if (this.kind === HistoryKind.MANGA_PAGE) {
          Text('引擎：' + HistoryViewModel.engineName(this.detail.engineType))
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
          Text('译文行：' + this.translatedLineCount())
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        } else if (this.kind === HistoryKind.NOVEL_CHAPTER) {
          Text('章节：第 ' + (this.detail.chapterIndex + 1) + ' / ' + this.detail.chapterCount + ' 章')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        } else {
          Text(this.detail.fromLang + ' → ' + this.detail.toLang)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
          Text('引擎：' + HistoryViewModel.engineName(this.detail.engineType))
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BG)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .border({ width: 1, color: ThemeTokens.DIVIDER })
    .alignItems(HorizontalAlign.Start)
  }

  private translatedLineCount(): number {
    let count = 0;
    for (const pair of this.pairs) {
      if (pair.translated.length > 0) {
        count++;
      }
    }
    return count;
  }

  @Builder
  mangaImageCard() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text('原图 + 译文覆盖')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
        Blank()
        Text(this.translatedLineCount() === 0 ? '尚无译文' : '只读排版')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .width('100%')

      Stack({ alignContent: Alignment.Center }) {
        Image(toMediaUri(this.detail.imagePath))
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
        Canvas(this.overlayCtx)
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
          .onReady(() => {
            this.canvasReady = true;
            this.drawOverlay();
          })
      }
      .width('100%')
      .height(this.isWide ? 520 : 400)
      .backgroundColor(ThemeTokens.BLACK)
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .clip(true)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.areaWidth = newArea.width as number;
        this.areaHeight = newArea.height as number;
        this.drawOverlay();
      })
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BG)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .border({ width: 1, color: ThemeTokens.DIVIDER })
  }

  @Builder
  pairListCard() {
    Column({ space: 8 }) {
      Row() {
        Text('译文对照')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
        Blank()
        Text(this.pairs.length + ' 行')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .width('100%')

      if (this.pairs.length === 0) {
        Text('该页还没有译文，可点击「重新翻译」生成。')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
      } else {
        Column({ space: 8 }) {
          ForEach(this.pairs, (pair: TranslationPair, index: number) => {
            Column({ space: 3 }) {
              Text(pair.original)
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
                .width('100%')
              Text(pair.translated.length > 0 ? pair.translated : '（本行未译出）')
                .fontSize(ThemeTokens.FONT_BODY - 1)
                .fontColor(pair.translated.length > 0 ? ThemeTokens.TEXT_PRIMARY : ThemeTokens.RED)
                .width('100%')
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
            .borderRadius(ThemeTokens.RADIUS_SMALL)
          }, (pair: TranslationPair, index: number) => index + ':' + pair.original.length + ':' +
            pair.translated.length)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BG)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .border({ width: 1, color: ThemeTokens.DIVIDER })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  textBlock(label: string, content: string, accent: boolean) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(accent ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_SECONDARY)
      Text(content.length > 0 ? content : '（暂无内容）')
        .fontSize(ThemeTokens.FONT_BODY)
        .fontColor(content.length > 0 ? ThemeTokens.TEXT_PRIMARY : ThemeTokens.TEXT_HINT)
        .lineHeight(24)
        .copyOption(CopyOptions.LocalDevice)
        .width('100%')
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BG)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .border({ width: 1, color: ThemeTokens.DIVIDER })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  contentArea() {
    if (this.kind === HistoryKind.MANGA_PAGE) {
      if (this.isWide) {
        Row({ space: 12 }) {
          Column() {
            this.mangaImageCard()
          }
          .layoutWeight(3)
          Column() {
            this.pairListCard()
          }
          .layoutWeight(2)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      } else {
        Column({ space: 12 }) {
          this.mangaImageCard()
          this.pairListCard()
        }
        .width('100%')
      }
    } else if (this.kind === HistoryKind.NOVEL_CHAPTER) {
      if (this.isWide) {
        Row({ space: 12 }) {
          Column() {
            this.textBlock('原文', this.detail.sourceText, false)
          }
          .layoutWeight(1)
          Column() {
            this.textBlock('译文', this.detail.translatedText, true)
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      } else {
        Column({ space: 12 }) {
          this.textBlock('原文', this.detail.sourceText, false)
          this.textBlock('译文', this.detail.translatedText, true)
        }
        .width('100%')
      }
    } else {
      if (this.isWide) {
        Row({ space: 12 }) {
          Column() {
            this.textBlock('原文', this.detail.sourceText, false)
          }
          .layoutWeight(1)
          Column() {
            this.textBlock('译文', this.detail.translatedText, true)
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      } else {
        Column({ space: 12 }) {
          this.textBlock('原文', this.detail.sourceText, false)
          this.textBlock('译文', this.detail.translatedText, true)
        }
        .width('100%')
      }
    }
  }

  @Builder
  actionBtn(icon: Resource, label: string, accent: boolean, action: () => void) {
    Row({ space: 5 }) {
      Image(icon)
        .width(14)
        .height(14)
        .fillColor(accent ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_PRIMARY)
      Text(label)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(accent ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_PRIMARY)
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(ThemeTokens.RADIUS_PILL)
    .backgroundColor(accent ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_VARIANT)
    .margin({ right: 8, bottom: 8 })
    .onClick(action)
  }

  @Builder
  actionRow() {
    Flex({ wrap: FlexWrap.Wrap }) {
      if (this.kind === HistoryKind.MANGA_PAGE) {
        this.actionBtn(Artwork.ICON_REFRESH, '重新翻译', true, () => {
          this.retranslatePage();
        })
      }
      this.actionBtn(Artwork.ICON_COPY, '复制', false, () => {
        this.copyContent();
      })
      this.actionBtn(Artwork.ICON_READER_EXPORT, '导出该组', false, () => {
        this.exportGroup();
      })
      this.actionBtn(Artwork.ICON_IMAGE, '全屏浏览', false, () => {
        this.openFullscreen();
      })
    }
    .width('100%')
  }

  @Builder
  missingState() {
    EmptyState({
      icon: Artwork.EMPTY_HISTORY,
      title: '记录不存在或已删除',
      hint: '返回历史列表下拉刷新后再试'
    })
  }

  @Builder
  exportModeOption(title: string, hint: string, mode: ExportMode) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      Text(hint)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_HINT)
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BG)
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.exportManga(mode);
    })
  }

  @Builder
  exportSheet() {
    Column() {
      Column({ space: 10 }) {
        Text('导出漫画翻译组')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text('按当前阅读器的译文排版设置合成，保存为 ZIP。')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
        this.exportModeOption('仅译文', '导出译文覆盖合成图', ExportMode.TRANSLATED_ONLY)
        this.exportModeOption('原文 + 译文', '每页原图与译文合成图各一份', ExportMode.BILINGUAL)
        this.exportModeOption('仅原文', '只导出原图', ExportMode.ORIGINAL_ONLY)
        Text('取消')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(40)
          .lineHeight(40)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
          .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
          .onClick(() => {
            this.showExportModes = false;
          })
      }
      .width('100%')
      .padding(18)
      .borderRadius({ topLeft: 22, topRight: 22 })
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .border({ width: 1, color: ThemeTokens.DIVIDER })
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor(ThemeTokens.SCRIM)
    .onClick(() => {
      this.showExportModes = false;
    })
  }

  @Builder
  toastView() {
    Text(this.toast)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(ThemeTokens.WHITE)
      .textAlign(TextAlign.Center)
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor('#D91A142C')
      .constraintSize({ maxWidth: '86%' })
      .align(Alignment.Bottom)
      .margin({ bottom: 32 })
      .onClick(() => {
        this.toast = '';
      })
  }

  @Builder
  busyView() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(34)
        .height(34)
        .color(ThemeTokens.PRIMARY)
      Text(this.busyText)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .textAlign(TextAlign.Center)
    }
    .padding(20)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .border({ width: 1, color: ThemeTokens.DIVIDER })
    .align(Alignment.Center)
  }

  build() {
    NavDestination() {
      // 顶部对齐：内容从标题栏下方开始排布，内容不足一屏时不垂直居中。
      Stack({ alignContent: Alignment.Top }) {
        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(ThemeTokens.PRIMARY)
            Text('正在加载记录…')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_HINT)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (!this.found) {
          this.missingState()
        } else {
          Scroll() {
            Column({ space: 12 }) {
              this.summaryCard()
              this.contentArea()
              this.actionRow()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Start)
            .padding({
              left: ThemeTokens.PAGE_PADDING,
              right: ThemeTokens.PAGE_PADDING,
              top: 10,
              bottom: 28
            })
          }
          .width('100%')
          .height('100%')
          // 有高度限制的 Scroll 在内容不足一屏时默认居中，必须显式顶部对齐。
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
        }

        if (this.toast.length > 0) {
          this.toastView()
        }
        if (this.showExportModes) {
          this.exportSheet()
        }
        if (this.busy) {
          this.busyView()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeTokens.SURFACE)
    }
    // 默认 STANDARD 标题栏（不设 barStyle: STACK）会把内容排在标题栏下方，避免首行被遮挡；
    // 沉浸光感材质仍在标题栏生效。
    .title('历史详情', {
      systemMaterial: this.immersiveSupported
        ? new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          colorInvert: true,
        interactive: true,
        lightEffect: {}
        })
        : undefined
    })
    .backgroundColor(ThemeTokens.SURFACE)
    .onReady((ctx: NavDestinationContext) => {
      const params = asHistoryDetailParams(ctx.pathInfo.param as Object);
      this.init(params.kind, params.refId);
    })
  }
}
