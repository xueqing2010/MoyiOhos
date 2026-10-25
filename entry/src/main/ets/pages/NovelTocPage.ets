import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens } from 'commons';
import { NovelChapter, TranslateStatus } from 'coremodel';
import { asNovelReaderParams } from '../common/Routes';
import { AppEnv } from '../common/AppEnv';
import { NovelViewModel } from '../viewmodel/NovelViewModel';

/**
 * 小说目录（TOC）：章节列表 + 翻译状态 + 当前章标记。
 * 点击章节写入 AppStorage('starflow_novel_toc_jump') 并返回阅读器，
 * 阅读器通过 @StorageProp @Watch 跳章（避免依赖不同 API 版本的 pop 回调）。
 */
@Component
export struct NovelTocPage {
  @State novelId: number = -1;
  @State chapterIndex: number = 0;
  @State chapters: Array<NovelChapter> = [];
  @State loaded: boolean = false;
  @State doneCount: number = 0;
  @State failedCount: number = 0;
  private listScroller: Scroller = new Scroller();

  private async init(novelId: number, chapterIndex: number): Promise<void> {
    this.novelId = novelId;
    this.chapterIndex = chapterIndex;
    try {
      this.chapters = await NovelViewModel.loadChapterList(novelId);
    } catch (e) {
      this.chapters = [];
    }
    let done = 0;
    let failed = 0;
    for (let i = 0; i < this.chapters.length; i++) {
      if (this.chapters[i].translateStatus === TranslateStatus.DONE) {
        done++;
      } else if (this.chapters[i].translateStatus === TranslateStatus.PARTIAL_FAILED) {
        failed++;
      }
    }
    this.doneCount = done;
    this.failedCount = failed;
    this.loaded = true;
  }

  private chapterTitle(chapter: NovelChapter, index: number): string {
    if (chapter.title !== undefined && chapter.title.length > 0) {
      return chapter.title;
    }
    return '第' + (index + 1) + '章';
  }

  private statusLabel(chapter: NovelChapter): string {
    if (chapter.translateStatus === TranslateStatus.DONE) {
      return '已译';
    }
    if (chapter.translateStatus === TranslateStatus.PARTIAL_FAILED) {
      return '部分';
    }
    return '';
  }

  private jumpTo(index: number): void {
    // 附带时间戳：重复选择同一章也能触发阅读器 @Watch（阅读器只解析前两段）。
    AppStorage.setOrCreate('starflow_novel_toc_jump', this.novelId + ':' + index + ':' + Date.now());
    AppEnv.getInstance().navStack.pop();
  }

  @Builder
  tocRow(chapter: NovelChapter, index: number) {
    Row({ space: 10 }) {
      Text('' + (index + 1))
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(index === this.chapterIndex ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_TERTIARY)
        .width(30)
        .textAlign(TextAlign.Center)
      Text(this.chapterTitle(chapter, index))
        .fontSize(ThemeTokens.FONT_BODY)
        .fontColor(index === this.chapterIndex ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_PRIMARY)
        .fontWeight(index === this.chapterIndex ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.statusLabel(chapter).length > 0) {
        Text(this.statusLabel(chapter))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(chapter.translateStatus === TranslateStatus.DONE ? ThemeTokens.SUCCESS : ThemeTokens.WARN)
      }
      if (index === this.chapterIndex) {
        Text('当前')
          .fontSize(10)
          .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .borderRadius(6)
          .backgroundColor(ThemeTokens.PRIMARY)
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .backgroundColor(index === this.chapterIndex ? ThemeTokens.CARD_BG : Color.Transparent)
    .onClick(() => {
      this.jumpTo(index);
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
      } else {
        Column() {
          Row({ space: 8 }) {
            Text('共 ' + this.chapters.length + ' 章')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_SECONDARY)
            if (this.doneCount > 0) {
              Text('已译 ' + this.doneCount)
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.SUCCESS)
            }
            if (this.failedCount > 0) {
              Text('部分失败 ' + this.failedCount)
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.WARN)
            }
            Blank()
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 6 })

          List({ scroller: this.listScroller }) {
            ForEach(this.chapters, (chapter: NovelChapter) => {
              ListItem() {
                this.tocRow(chapter, chapter.chapterIndex)
              }
            }, (chapter: NovelChapter) => chapter.id + ':' + chapter.translateStatus)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: 8, right: 8, bottom: 12 })
          .onAppear(() => {
            if (this.chapterIndex > 0) {
              this.listScroller.scrollToIndex(this.chapterIndex);
            }
          })
        }
        .width('100%')
        .height('100%')
      }
    }
    .title('目录', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
    .onReady((ctx: NavDestinationContext) => {
      const params = asNovelReaderParams(ctx.pathInfo.param as Object);
      this.init(params.novelId, params.chapterIndex !== undefined ? params.chapterIndex : 0);
    })
  }
}
