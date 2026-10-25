import { MangaPage, TranslateStatus } from 'coremodel';
import { ThemeTokens, WindowSizeClass, observeBreakpoint, toMediaUri } from 'commons';
import { uiMaterial } from '@kit.ArkUI';
import { PageRepository } from '../data/PageRepository';
import { AppEnv } from '../common/AppEnv';
import { ReaderViewModel } from '../viewmodel/ReaderViewModel';
import { BatchState } from '../service/BatchTranslateService';
import { Log } from 'commons';

/** 目录页参数（ReaderPage push 时传入）。 */
export interface MangaTocParams {
  mangaId: number;
  current: number;
}

export function makeMangaTocParams(mangaId: number, current: number): MangaTocParams {
  const p: MangaTocParams = { mangaId: mangaId, current: current };
  return p;
}

export function asMangaTocParams(raw: Object): MangaTocParams {
  const p = raw as MangaTocParams;
  if (p !== undefined && p !== null && typeof p.mangaId === 'number') {
    return p;
  }
  return makeMangaTocParams(-1, 0);
}

/** 目录页回传给阅读器的跳页结果（NavPathStack.pop(result)）。 */
export class MangaTocJump {
  page: number = -1;
}

/** LazyForEach 数据源（大目录按需构建缩略图）。 */
class TocPageSource implements IDataSource {
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

  updateOne(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }
}

/**
 * 漫画目录（MangaTocPage）：页缩略图网格（LazyForEach 懒加载）、
 * 翻译状态角标、当前页高亮、页码跳转；点击缩略图 pop 回阅读器并带的跳页结果。
 */
@Component
export struct MangaTocPage {
  @State loaded: boolean = false;
  @State pages: Array<MangaPage> = [];
  @State current: number = 0;
  @State columns: number = 2;
  @State jumpText: string = '';
  @State translatedCount: number = 0;
  @State dropColumns: number = 2;
  private source: TocPageSource = new TocPageSource();
  private mangaId: number = -1;
  private lastBatchDone: number = -1;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private batchHandler: (s: BatchState) => void = (s: BatchState) => {
    if (s.running || s.done !== this.lastBatchDone) {
      const changed = s.done !== this.lastBatchDone;
      this.lastBatchDone = s.done;
      if (changed && this.mangaId >= 0 && this.loaded) {
        this.load(this.mangaId, this.current);
      }
    }
  };

  aboutToAppear(): void {
    ReaderViewModel.onBatchChange(this.batchHandler);
    this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
      if (c === WindowSizeClass.LG) {
        this.columns = 6;
      } else if (c === WindowSizeClass.MD) {
        this.columns = 4;
      } else {
        this.columns = 2;
      }
    });
  }

  aboutToDisappear(): void {
    ReaderViewModel.offBatchChange(this.batchHandler);
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  private async load(mangaId: number, current: number): Promise<void> {
    this.mangaId = mangaId;
    this.current = current;
    try {
      await AppEnv.ready();
      const pages = await PageRepository.getPages(mangaId);
      this.pages = pages;
      this.source.setPages(pages);
      let translated = 0;
      for (let i = 0; i < pages.length; i++) {
        if (pages[i].translateStatus === TranslateStatus.DONE) {
          translated++;
        }
      }
      this.translatedCount = translated;
      this.loaded = true;
    } catch (e) {
      Log.error('MangaTocPage', 'load failed: ' + e);
      this.loaded = true;
    }
  }

  private columnsTemplate(): string {
    let tpl = '';
    for (let i = 0; i < this.columns; i++) {
      tpl += i === 0 ? '1fr' : ' 1fr';
    }
    return tpl;
  }

  private pageRatio(page: MangaPage): number {
    if (page.width !== undefined && page.height !== undefined && page.height > 0) {
      return page.width / page.height;
    }
    return 0.7;
  }

  private statusLabel(page: MangaPage): string {
    if (page.translateStatus === TranslateStatus.DONE) {
      return '已译';
    }
    if (page.translateStatus === TranslateStatus.PARTIAL_FAILED) {
      return '部分';
    }
    if (page.translateStatus === TranslateStatus.RUNNING) {
      return '翻译中';
    }
    return '';
  }

  private statusColor(page: MangaPage): string {
    if (page.translateStatus === TranslateStatus.DONE) {
      return ThemeTokens.SUCCESS;
    }
    if (page.translateStatus === TranslateStatus.PARTIAL_FAILED) {
      return ThemeTokens.WARN;
    }
    if (page.translateStatus === TranslateStatus.RUNNING) {
      return ThemeTokens.PRIMARY;
    }
    return ThemeTokens.TEXT_HINT;
  }

  private jumpTo(page: number): void {
    let target = page;
    if (target < 0) {
      target = 0;
    }
    if (target > this.pages.length - 1) {
      target = this.pages.length - 1;
    }
    if (this.pages.length === 0) {
      return;
    }
    const result = new MangaTocJump();
    result.page = target;
    AppEnv.getInstance().navStack.pop(result, true);
  }

  private submitJump(): void {
    const n = Number.parseInt(this.jumpText);
    if (Number.isNaN(n)) {
      return;
    }
    this.jumpTo(n - 1);
  }

  @Builder
  thumbItem(page: MangaPage, index: number) {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(toMediaUri(page.imagePath))
          .width('100%')
          .aspectRatio(this.pageRatio(page))
          .objectFit(ImageFit.Cover)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        if (index === this.current) {
          Text('当前')
            .fontSize(9)
            .fontColor(ThemeTokens.WHITE)
            .backgroundColor(ThemeTokens.PRIMARY_DEEP)
            .borderRadius(6)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .margin(4)
        }
        if (this.statusLabel(page).length > 0) {
          Text(this.statusLabel(page))
            .fontSize(9)
            .fontColor(ThemeTokens.WHITE)
            .backgroundColor(this.statusColor(page))
            .borderRadius(6)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .align(Alignment.TopEnd)
            .margin(4)
        }
      }
      .width('100%')
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .border({
        width: index === this.current ? 2 : 0,
        color: ThemeTokens.PRIMARY,
        radius: ThemeTokens.RADIUS_SMALL
      })
      .onClick(() => {
        this.jumpTo(index);
      })
      Text('第 ' + (index + 1) + ' 页')
        .fontSize(10)
        .fontColor(index === this.current ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_HINT)
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        if (!this.loaded) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(ThemeTokens.PRIMARY)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.pages.length === 0) {
          Column({ space: 8 }) {
            Text('目录为空')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_HINT)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Row({ space: 10 }) {
            Text('共 ' + this.pages.length + ' 页 · 已译 ' + this.translatedCount)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_HINT)
              .layoutWeight(1)
            TextInput({ placeholder: '页码', text: this.jumpText })
              .width(76)
              .height(32)
              .fontSize(ThemeTokens.FONT_SMALL)
              .backgroundColor(ThemeTokens.SURFACE_VARIANT)
              .borderRadius(10)
              .type(InputType.Number)
              .onChange((value: string) => {
                this.jumpText = value;
              })
            Button('跳转')
              .fontSize(ThemeTokens.FONT_SMALL)
              .height(32)
              .backgroundColor(ThemeTokens.PRIMARY)
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .borderRadius(10)
              .padding({ left: 14, right: 14 })
              .onClick(() => {
                this.submitJump();
              })
          }
          .width('100%')
          .padding({ left: 2, right: 2 })

          Grid() {
            LazyForEach(this.source, (page: MangaPage) => {
              GridItem() {
                this.thumbItem(page, page.pageIndex)
              }
            }, (page: MangaPage) => page.id + '-' + page.translateStatus + '-' + page.pageIndex)
          }
          .columnsTemplate(this.columnsTemplate())
          .columnsGap(10)
          .rowsGap(12)
          .cachedCount(8)
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .title('目录', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true,
        interactive: true,
        lightEffect: {}
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
    .onReady((ctx: NavDestinationContext) => {
      const p = asMangaTocParams(ctx.pathInfo.param as Object);
      this.load(p.mangaId, p.current);
    })
  }
}
