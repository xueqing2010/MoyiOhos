import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens, toMediaUri } from 'commons';
import { Artwork } from '../components/Artwork';
import { AppEnv } from '../common/AppEnv';
import { HistoryFullscreenParams } from '../common/Routes';
import { HistoryGroup, HistoryItem, HistoryKind } from '../service/HistoryService';
import { HistoryViewModel } from '../viewmodel/HistoryViewModel';

/**
 * 历史全屏浏览页（task-6）：
 * 一组记录（同一漫画 / 小说 / 文本会话）全屏 Swiper 翻页；点击内容显隐工具栏；
 * 工具栏提供进度滑块、上一页/下一页、原文/译文切换（小说、文本）与退出。
 * 漫画组只读展示页原图；小说/文本组按阅读宽度展示全文。
 */
@Component
export struct HistoryFullscreenPage {
  @State loading: boolean = true;
  @State groupTitle: string = '';
  @State groupSubtitle: string = '';
  @State groupKind: number = -1;
  @State items: Array<HistoryItem> = [];
  @State index: number = 0;
  @State toolbarVisible: boolean = true;
  @State showTranslated: boolean = true;
  @State toast: string = '';
  private async init(sessionId: string): Promise<void> {
    this.loading = true;
    try {
      const group: HistoryGroup | undefined = await HistoryViewModel.loadGroup(sessionId);
      if (group !== undefined && group.items.length > 0) {
        this.groupTitle = group.title;
        this.groupSubtitle = group.subtitle;
        this.groupKind = group.kind;
        this.items = group.items;
        this.index = 0;
      }
    } catch (e) {
      this.showToast('加载失败：' + HistoryFullscreenPage.readableError(e));
    }
    this.loading = false;
  }

  private currentItem(): HistoryItem | undefined {
    if (this.index < 0 || this.index >= this.items.length) {
      return undefined;
    }
    return this.items[this.index];
  }

  private isManga(): boolean {
    return this.groupKind === HistoryKind.MANGA_PAGE;
  }

  private currentBody(item: HistoryItem): string {
    if (this.showTranslated) {
      return item.contentTranslated.length > 0 ? item.contentTranslated : item.contentOriginal;
    }
    return item.contentOriginal;
  }

  private maxIndex(): number {
    return this.items.length > 0 ? this.items.length - 1 : 0;
  }

  private goTo(target: number): void {
    if (this.items.length === 0) {
      return;
    }
    let next = target;
    if (next < 0) {
      next = 0;
    }
    if (next > this.maxIndex()) {
      next = this.maxIndex();
    }
    if (next !== this.index) {
      this.index = next;
    }
  }

  private toggleToolbar(): void {
    this.toolbarVisible = !this.toolbarVisible;
  }

  private close(): void {
    AppEnv.getInstance().navStack.pop();
  }

  private showToast(message: string): void {
    this.toast = message;
    setTimeout(() => {
      if (this.toast === message) {
        this.toast = '';
      }
    }, 2400);
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
  mangaPage(item: HistoryItem) {
    Stack({ alignContent: Alignment.Center }) {
      Image(toMediaUri(item.imagePath))
        .objectFit(ImageFit.Contain)
        .width('100%')
        .height('100%')
      Text('第 ' + (item.pageIndex + 1) + ' 页')
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor('#B3FFFFFF')
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .backgroundColor('#66000000')
        .align(Alignment.TopEnd)
        .margin({ top: 10, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.READER_BG_BLACK)
    .onClick(() => {
      this.toggleToolbar();
    })
  }

  @Builder
  textPage(item: HistoryItem) {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: 10 }) {
          Text(item.subtitle)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
            .width('100%')
          Text(this.currentBody(item))
            .fontSize(ThemeTokens.FONT_BODY + 1)
            .lineHeight(28)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .padding({ left: 20, right: 20, top: 20, bottom: 90 })
      }
      .width('100%')
      .height('100%')
      // 内容不足一屏时保持顶部对齐（同样用于小说/文本全屏页）。
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.READER_BG_NOCTURNE)
    .onClick(() => {
      this.toggleToolbar();
    })
  }

  @Builder
  topBar() {
    Row({ space: 10 }) {
      Image(Artwork.ICON_CLOSE)
        .width(20)
        .height(20)
        .padding(8)
        .fillColor(ThemeTokens.TEXT_PRIMARY)
        .onClick(() => {
          this.close();
        })
      Column({ space: 1 }) {
        Text(this.groupTitle.length > 0 ? this.groupTitle : '全屏浏览')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.groupSubtitle)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text((this.index + 1) + ' / ' + this.items.length)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
    }
    .width('100%')
    .padding({ left: 8, right: 14, top: 6, bottom: 6 })
    .backgroundColor('#CC0B0813')
  }

  @Builder
  iconButton(icon: Resource, enabled: boolean, action: () => void) {
    Image(icon)
      .width(20)
      .height(20)
      .padding(9)
      .fillColor(enabled ? ThemeTokens.TEXT_PRIMARY : ThemeTokens.TEXT_TERTIARY)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor('#661A142C')
      .opacity(enabled ? 1 : 0.6)
      .onClick(() => {
        if (enabled) {
          action();
        }
      })
  }

  @Builder
  bottomBar() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Text((this.index + 1) + ' / ' + this.items.length)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
        if (this.items.length > 1) {
          Slider({
            value: this.index,
            min: 0,
            max: this.maxIndex(),
            step: 1,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .selectedColor(ThemeTokens.PRIMARY)
            .trackColor('#33FFFFFF')
            .blockColor(ThemeTokens.PRIMARY)
            .systemMaterial(new uiMaterial.ImmersiveMaterial({
              style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
              interactive: true,
              lightEffect: {}
            }))
            .trackThickness(3)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.goTo(Math.round(value));
            })
        } else {
          Blank()
            .layoutWeight(1)
        }
      }
      .width('100%')

      Row({ space: 10 }) {
        this.iconButton(Artwork.ICON_READER_PREV, this.index > 0, () => {
          this.goTo(this.index - 1);
        })
        if (!this.isManga()) {
          Row({ space: 5 }) {
            Text(this.showTranslated ? '译文' : '原文')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.PRIMARY)
          .onClick(() => {
            this.showTranslated = !this.showTranslated;
          })
        } else {
          Text('原图')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        }
        this.iconButton(Artwork.ICON_READER_NEXT, this.index < this.maxIndex(), () => {
          this.goTo(this.index + 1);
        })
        Blank()
        Text('退出')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor('#661A142C')
          .onClick(() => {
            this.close();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 12 })
    .backgroundColor('#CC0B0813')
  }

  @Builder
  emptyView() {
    Column({ space: 12 }) {
      Image(Artwork.EMPTY_HISTORY)
        .width(120)
        .height(120)
        .objectFit(ImageFit.Contain)
        .draggable(false)
      Text('该组记录已不存在')
        .fontSize(ThemeTokens.FONT_SUBTITLE)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      Text('可能已在历史页被删除，返回后可下拉刷新')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_HINT)
        .textAlign(TextAlign.Center)
      Text('返回')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
        .padding({ left: 22, right: 22, top: 9, bottom: 9 })
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .backgroundColor(ThemeTokens.PRIMARY)
        .margin({ top: 6 })
        .onClick(() => {
          this.close();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24)
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
      .margin({ bottom: 96 })
      .onClick(() => {
        this.toast = '';
      })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(ThemeTokens.PRIMARY)
            Text('正在加载…')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_HINT)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(ThemeTokens.READER_BG_BLACK)
        } else if (this.items.length === 0) {
          Column() {
            this.emptyView()
          }
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeTokens.READER_BG_BLACK)
        } else {
          Swiper() {
            ForEach(this.items, (item: HistoryItem) => {
              if (this.isManga()) {
                this.mangaPage(item)
              } else {
                this.textPage(item)
              }
            }, (item: HistoryItem) => item.key + ':' + (this.showTranslated ? 't' : 'o'))
          }
          .index(this.index)
          .loop(false)
          .indicator(false)
          .width('100%')
          .height('100%')
          .onChange((index: number) => {
            this.index = index;
          })

          if (this.toolbarVisible) {
            Column() {
              this.topBar()
              Blank()
              this.bottomBar()
            }
            .width('100%')
            .height('100%')
          }
        }

        if (this.toast.length > 0) {
          this.toastView()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeTokens.READER_BG_BLACK)
    }
    .hideTitleBar(true)
    .backgroundColor(ThemeTokens.READER_BG_BLACK)
    .onReady((ctx: NavDestinationContext) => {
      const params = ctx.pathInfo.param as HistoryFullscreenParams;
      if (params !== undefined && params !== null && typeof params.sessionId === 'string') {
        this.init(params.sessionId);
      } else {
        this.loading = false;
      }
    })
  }
}
