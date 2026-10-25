/**
 * 文本翻译历史页（stage 2 / S108）。
 *
 * TextTranslationDao 列表（原文 / 译文 / 引擎 / 时间）：
 *  · 点击条目 → 详情弹层（复制原文 / 复制译文 / 重新翻译 / 删除）
 *  · 顶部「清空」带二次确认
 *  · 空态为 SVG 图标 + 文案（无 emoji）
 *  · NavDestination 标题栏使用 uiMaterial 沉浸材质
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';
import { TextTranslationRecord } from 'coremodel';
import { EngineType } from 'coretranslate';
import { AppEnv } from '../common/AppEnv';
import { EmptyState } from '../components/EmptyState';
import { Artwork } from '../components/Artwork';
import { TextTranslateViewModel, TranslateSettings } from '../viewmodel/TextTranslateViewModel';
import { Log } from 'commons';

const TAG = 'TextHistoryPage';

/** 空占位记录（详情弹层未选中时的默认值）。 */
function emptyHistoryRecord(): TextTranslationRecord {
  const rec: TextTranslationRecord = {
    id: 0,
    sourceText: '',
    translatedText: '',
    engineType: 0,
    fromLang: 'auto',
    toLang: 'zh',
    createdAt: 0
  };
  return rec;
}

@Component
export struct TextHistoryPage {
  @State records: Array<TextTranslationRecord> = [];
  @State loading: boolean = true;
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  @State showDetail: boolean = false;
  @State showClearConfirm: boolean = false;
  @State busy: boolean = false;
  /** 详情弹层当前条目（showDetail=false 时内容无意义）。 */
  @State detail: TextTranslationRecord = emptyHistoryRecord();
  @State retranslated: string = '';

  private stopBreakpoint: (() => void) | undefined = undefined;
  private navStack: NavPathStack = AppEnv.getInstance().navStack;

  aboutToAppear(): void {
    this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
      this.sizeClass = c;
    });
    this.reload();
  }

  aboutToDisappear(): void {
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  private async reload(): Promise<void> {
    this.loading = true;
    try {
      this.records = await TextTranslateViewModel.loadHistory(0);
    } catch (e) {
      Log.warn(TAG, 'load failed: ' + e);
      this.records = [];
    }
    this.loading = false;
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1500 });
    } catch (e) {
      Log.info(TAG, text);
    }
  }

  private async copyText(text: string): Promise<void> {
    if (text.length === 0) {
      this.toast('没有可复制的内容');
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.toast('已复制到剪贴板');
    } catch (e) {
      this.toast('复制失败：' + TextTranslateViewModel.readableError(e));
    }
  }

  private openDetail(rec: TextTranslationRecord): void {
    this.detail = rec;
    this.retranslated = '';
    this.showDetail = true;
  }

  private async deleteRecord(rec: TextTranslationRecord): Promise<void> {
    try {
      await TextTranslateViewModel.deleteHistory(rec.id);
      this.showDetail = false;
      await this.reload();
      this.toast('已删除');
    } catch (e) {
      this.toast('删除失败：' + TextTranslateViewModel.readableError(e));
    }
  }

  private async clearAll(): Promise<void> {
    this.showClearConfirm = false;
    try {
      await TextTranslateViewModel.clearHistory();
      await this.reload();
      this.toast('已清空文本翻译历史');
    } catch (e) {
      this.toast('清空失败：' + TextTranslateViewModel.readableError(e));
    }
  }

  /** 重新翻译：用当前引擎再翻一次，成功则新增一条记录并展示。 */
  private async retranslate(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.retranslated = '';
    try {
      const settings: TranslateSettings = await TextTranslateViewModel.loadSettings();
      const result = await TextTranslateViewModel.translateWith(this.detail.sourceText,
        this.detail.fromLang, this.detail.toLang, settings, (delta: string) => {
          this.retranslated += delta;
        });
      if (this.retranslated.length === 0) {
        this.retranslated = result;
      }
      const engineType: EngineType = settings.engine;
      await TextTranslateViewModel.saveHistory(this.detail.sourceText,
        this.retranslated.trim(), this.detail.fromLang, this.detail.toLang,
        engineType as number);
      await this.reload();
    } catch (e) {
      this.retranslated = TextTranslateViewModel.errorTitle(e) + '：'
        + TextTranslateViewModel.readableError(e);
    }
    this.busy = false;
  }

  private formatTime(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const d = new Date(ms);
    const pad = (n: number): string => (n < 10 ? ('0' + n) : ('' + n));
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate())
      + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  private subtitleOf(rec: TextTranslationRecord): string {
    return TextTranslateViewModel.engineNameOf(rec.engineType) + ' · '
      + TextTranslateViewModel.languagePairLabel(rec.fromLang, rec.toLang)
      + ' · ' + this.formatTime(rec.createdAt);
  }

  @Builder
  emptyState() {
    Column() {
      EmptyState({
        icon: Artwork.EMPTY_HISTORY,
        title: '还没有文本翻译记录',
        hint: '在「翻译」页输入文本并翻译，记录会自动保存在这里'
      })
    }
    .width('100%')
    .layoutWeight(1);
  }

  @Builder
  recordRow(rec: TextTranslationRecord) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(TextTranslateViewModel.engineNameOf(rec.engineType))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.PRIMARY)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_HIGH);
        Text(TextTranslateViewModel.languagePairLabel(rec.fromLang, rec.toLang))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .layoutWeight(1);
        Text(this.formatTime(rec.createdAt))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_TERTIARY);
      }
      .width('100%');
      Text(rec.sourceText)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');
      Text(rec.translatedText.length > 0 ? rec.translatedText : '（无译文）')
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(rec.translatedText.length > 0
          ? ThemeTokens.TEXT_SECONDARY : ThemeTokens.TEXT_HINT)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');
    }
    .width('100%')
    .padding(11)
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .backgroundColor(ThemeTokens.CARD_BG)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.openDetail(rec);
    });
  }

  @Builder
  detailOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 8 }) {
        Text('翻译详情')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .width('100%');
        Text(this.subtitleOf(this.detail))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%');
        Scroll() {
          Column({ space: 8 }) {
            Text('原文')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_HINT)
              .width('100%');
            Text(this.detail.sourceText)
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
              .width('100%')
              .copyOption(CopyOptions.LocalDevice);
            Text('译文')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_HINT)
              .width('100%')
              .margin({ top: 6 });
            Text(this.retranslated.length > 0
              ? this.retranslated
              : (this.detail.translatedText.length > 0
                ? this.detail.translatedText : '（无译文）'))
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(this.retranslated.length > 0
                ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_PRIMARY)
              .width('100%')
              .copyOption(CopyOptions.LocalDevice);
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%');
        Row({ space: 8 }) {
          Button('复制原文')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.copyText(this.detail.sourceText);
            });
          Button('复制译文')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.copyText(this.retranslated.length > 0
                ? this.retranslated : this.detail.translatedText);
            });
        }
        .width('100%');
        Row({ space: 8 }) {
          Button(this.busy ? '重翻中…' : '重新翻译')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(36)
            .layoutWeight(1)
            .enabled(!this.busy)
            .onClick(() => {
              this.retranslate();
            });
          Button('删除')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.RED)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.deleteRecord(this.detail);
            });
          Button('关闭')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.showDetail = false;
            });
        }
        .width('100%');
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('92%')
      .height('72%')
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000');
  }

  @Builder
  clearConfirmOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 10 }) {
        Text('清空文本翻译历史？')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .width('100%');
        Text('将删除全部 ' + this.records.length + ' 条记录，且不可恢复')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .width('100%');
        Row({ space: 10 }) {
          Button('取消')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(38)
            .layoutWeight(1)
            .onClick(() => {
              this.showClearConfirm = false;
            });
          Button('清空')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.RED)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(38)
            .layoutWeight(1)
            .onClick(() => {
              this.clearAll();
            });
        }
        .width('100%');
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('84%')
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000');
  }

  build() {
    NavDestination() {
      Stack() {
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            Text('共 ' + this.records.length + ' 条')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_HINT)
              .layoutWeight(1);
            Text('刷新')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.PRIMARY)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(ThemeTokens.RADIUS_PILL)
              .backgroundColor(ThemeTokens.SURFACE_VARIANT)
              .onClick(() => {
                this.reload();
              });
            if (this.records.length > 0) {
              Text('清空')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.RED)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(ThemeTokens.RADIUS_PILL)
                .backgroundColor(ThemeTokens.SURFACE_VARIANT)
                .onClick(() => {
                  this.showClearConfirm = true;
                });
            }
          }
          .width('100%');

          if (this.loading) {
            Column({ space: 8 }) {
              LoadingProgress()
                .width(28)
                .height(28)
                .color(ThemeTokens.PRIMARY);
              Text('读取中…')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT);
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center);
          } else if (this.records.length === 0) {
            this.emptyState();
          } else {
            List({ space: 8 }) {
              ForEach(this.records, (rec: TextTranslationRecord) => {
                ListItem() {
                  this.recordRow(rec);
                }
              }, (rec: TextTranslationRecord) => rec.id.toString());
            }
            .scrollBar(BarState.Off)
            .width('100%')
            .layoutWeight(1);
          }
        }
        .padding(ThemeTokens.PAGE_PADDING)
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start);

        if (this.showDetail) {
          this.detailOverlay();
        }
        if (this.showClearConfirm) {
          this.clearConfirmOverlay();
        }
      }
      .width('100%')
      .height('100%');
    }
    // 标题栏：默认 STANDARD（内容自动排在标题栏下方，避免首行被遮挡），
    // 仅保留沉浸材质，不改变布局模式。
    .title('文本翻译历史', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE);
  }
}