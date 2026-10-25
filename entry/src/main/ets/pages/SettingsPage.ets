/**
 * 设置总览页标题栏使用默认 STANDARD + 沉浸材质（STACK 会遮挡内容，已移除）。
 */
import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { Routes } from '../common/Routes';
import { ReaderSettings, SettingsKeys, SettingsRepository, TranslateSettings } from '../data/SettingsRepository';
import { TextTranslateViewModel } from '../viewmodel/TextTranslateViewModel';

/** @Builder 按引用传递参数（摘要数值变化可刷新 UI）。 */
interface SummaryChipParams {
  label: string;
  value: string;
}

/** 设置汇总行。 */
interface SettingsEntry {
  title: string;
  desc: string;
  icon: Resource;
  route: string;
}

function makeEntry(title: string, desc: string, icon: Resource, route: string): SettingsEntry {
  const e: SettingsEntry = { title: title, desc: desc, icon: icon, route: route };
  return e;
}

/**
 * 设置总览页（stage-2 / S110）：把阅读/翻译/OCR/主题四个子页、
 * API 配置、模型管理、常见问题、关于与引导聚合到一处，
 * 顶部展示当前关键设置的实时摘要（读 SettingsRepository）。
 */
@Component
export struct SettingsPage {
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  @State bgLabel: string = '紫夜';
  @State fontLabel: string = '自动';
  @State engineLabel: string = '必应';
  @State targetLabel: string = '简体中文';
  @State themeLabel: string = '紫夜深色';
  @State ocrLabel: string = '日文';
  private navStack: NavPathStack = AppEnv.getInstance().navStack;
  private stopBreakpoint: (() => void) | undefined = undefined;

  private readingEntries: Array<SettingsEntry> = [
    makeEntry('阅读设置', '背景、字号、行距、边距、翻页与竖排', $r('app.media.ic_reading'),
      Routes.SETTINGS_READING),
    makeEntry('主题外观', '紫夜深色 / 紫夜纯黑 OLED / 跟随系统', $r('app.media.ic_theme'), Routes.SETTINGS_THEME)
  ];
  private translateEntries: Array<SettingsEntry> = [
    makeEntry('翻译设置', '引擎、目标语言、上下文轮次、提示词与温度', $r('app.media.ic_translate'),
      Routes.SETTINGS_TRANSLATE),
    makeEntry('API 配置', '必应 / OpenAI 兼容 / 本地 llama 与连通性测试', $r('app.media.ic_api'),
      Routes.API_CONFIG)
  ];
  private ocrEntries: Array<SettingsEntry> = [
    makeEntry('OCR 识别', '识别语言、引擎档位与能力探测', $r('app.media.ic_ocr'), Routes.SETTINGS_OCR)
  ];
  private otherEntries: Array<SettingsEntry> = [
    makeEntry('模型管理', 'GGUF 下载、导入与存储统计', $r('app.media.ic_model'), Routes.MODEL_MANAGER),
    makeEntry('常见问题', '使用疑问与故障排查', $r('app.media.ic_faq'), Routes.FAQ),
    makeEntry('开源致谢', '上游项目与第三方许可', $r('app.media.ic_github'), Routes.OPEN_SOURCE),
    makeEntry('关于星译', '版本、构建模块与许可', $r('app.media.ic_about'), Routes.ABOUT),
    makeEntry('重新查看引导', '3 页快速上手', $r('app.media.ic_star'), Routes.ONBOARDING)
  ];

  aboutToAppear(): void {
    this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
      this.sizeClass = c;
    });
    this.loadSummary();
  }

  aboutToDisappear(): void {
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  private async loadSummary(): Promise<void> {
    try {
      const reader: ReaderSettings = await SettingsRepository.loadReaderSettings();
      this.bgLabel = SettingsPage.bgName(reader.bg);
      this.fontLabel = reader.fontSizeMode === 0 ? `自动（${reader.fontSize}fp）` : `${reader.fontSize}fp`;
      const translate: TranslateSettings = await SettingsRepository.loadTranslateSettings();
      this.engineLabel = SettingsPage.engineName(translate.engineType);
      // 与文本/对话翻译页共用同一 provider 真源，避免摘要与实际引擎不一致。
      try {
        const provider: string = await TextTranslateViewModel.loadProvider();
        this.engineLabel = provider === 'bing' ? '必应' : (provider === 'local' ? '本地 llama' : 'OpenAI 兼容');
      } catch (e) {
        // 保持 engineType 推断结果
      }
      this.targetLabel = SettingsPage.langName(translate.targetLang);
      const theme: string = await SettingsRepository.getString(SettingsKeys.THEME_MODE, 'purple');
      this.themeLabel = SettingsPage.themeName(theme);
      const ocr: string = await SettingsRepository.getString(SettingsKeys.OCR_LANG, 'ja');
      this.ocrLabel = SettingsPage.ocrName(ocr);
    } catch (e) {
      // 摘要加载失败不影响入口可用
    }
  }

  private static bgName(bg: string): string {
    if (bg === 'black') {
      return '黑';
    }
    if (bg === 'nocturne') {
      return '紫夜';
    }
    if (bg === 'plum') {
      return '紫梅';
    }
    if (bg === 'deep') {
      return '深紫';
    }
    if (bg === 'paper') {
      return '纸色';
    }
    if (bg === 'white') {
      return '白';
    }
    return '灰';
  }

  private static engineName(engine: number): string {
    if (engine === 1) {
      return 'OpenAI 兼容';
    }
    if (engine === 2) {
      return '本地 llama';
    }
    return '必应';
  }

  private static langName(lang: string): string {
    if (lang === 'zh-TW') {
      return '繁體中文';
    }
    if (lang === 'en') {
      return 'English';
    }
    if (lang === 'ja') {
      return '日本語';
    }
    if (lang === 'ko') {
      return '한국어';
    }
    return '简体中文';
  }

  private static themeName(theme: string): string {
    if (theme === 'oled') {
      return '紫夜纯黑 OLED';
    }
    if (theme === 'system') {
      return '跟随系统';
    }
    return '紫夜深色';
  }

  private static ocrName(lang: string): string {
    if (lang === 'en') {
      return '英文';
    }
    if (lang === 'zh-CN') {
      return '简体中文';
    }
    if (lang === 'ko') {
      return '韩文';
    }
    return '日文';
  }

  private isWide(): boolean {
    return this.sizeClass === WindowSizeClass.LG;
  }

  @Builder
  summaryCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Image($r('app.media.ic_settings'))
          .width(18)
          .height(18)
          .fillColor(ThemeTokens.PRIMARY)
        Text('当前设置摘要')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.summaryChip({ label: '阅读背景', value: this.bgLabel })
        this.summaryChip({ label: '字号', value: this.fontLabel })
      }
      .width('100%')

      Row({ space: 8 }) {
        this.summaryChip({ label: '翻译引擎', value: this.engineLabel })
        this.summaryChip({ label: '目标语言', value: this.targetLabel })
      }
      .width('100%')

      Row({ space: 8 }) {
        this.summaryChip({ label: 'OCR 语言', value: this.ocrLabel })
        this.summaryChip({ label: '主题', value: this.themeLabel })
      }
      .width('100%')
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  summaryChip(pp: SummaryChipParams) {
    Row({ space: 8 }) {
      Text(pp.label)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_HINT)
      Text(pp.value)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.PRIMARY_SOFT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
  }

  @Builder
  entryRow(entry: SettingsEntry) {
    Row({ space: 12 }) {
      Column() {
        Image(entry.icon)
          .width(19)
          .height(19)
          .fillColor(ThemeTokens.PRIMARY_SOFT)
      }
      .width(34)
      .height(34)
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(entry.title)
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text(entry.desc)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_arrow_right'))
        .width(14)
        .height(14)
        .fillColor(ThemeTokens.TEXT_TERTIARY)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.navStack.pushPathByName(entry.route, '');
    })
  }

  @Builder
  entryCard(entries: Array<SettingsEntry>) {
    Column() {
      ForEach(entries, (entry: SettingsEntry, index: number) => {
        if (index > 0) {
          Divider()
            .color(ThemeTokens.DIVIDER)
            .strokeWidth(0.5)
        }
        this.entryRow(entry)
      }, (entry: SettingsEntry) => entry.route)
    }
    .width('100%')
    .padding({ left: ThemeTokens.CARD_PADDING, right: ThemeTokens.CARD_PADDING, top: 4, bottom: 4 })
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          this.summaryCard()

          if (this.isWide()) {
            Row({ space: 12 }) {
              Column({ space: 12 }) {
                this.entryCard(this.readingEntries)
                this.entryCard(this.ocrEntries)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Column({ space: 12 }) {
                this.entryCard(this.translateEntries)
                this.entryCard(this.otherEntries)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            this.entryCard(this.readingEntries)
            this.entryCard(this.translateEntries)
            this.entryCard(this.ocrEntries)
            this.entryCard(this.otherEntries)
          }

          Text('设置修改后立即生效；阅读器与翻译页读取同一份 preferences。')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_TERTIARY)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 4, bottom: 12 })
        }
        .width('100%')
        .padding({
          left: ThemeTokens.PAGE_PADDING,
          right: ThemeTokens.PAGE_PADDING,
          top: 12,
          bottom: 24
        })
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
    .title('设置', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true,
        interactive: true,
        lightEffect: {}
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
    .onShown(() => {
      this.loadSummary();
    })
  }
}