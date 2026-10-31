import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { Routes } from '../common/Routes';
import { SettingsKeys, SettingsRepository, TranslateSettings } from '../data/SettingsRepository';
import { EnginePresets } from 'coretranslate';
import { picker } from '@kit.CoreFileKit';
import { TextTranslateViewModel } from '../viewmodel/TextTranslateViewModel';
import { GlossaryService } from '../service/GlossaryService';

/** 单选选项。 */
class Choice {
  value: string;
  label: string;

  constructor(value: string, label: string) {
    this.value = value;
    this.label = label;
  }
}

/** 提示词种类。 */
class PromptKind {
  key: string;
  label: string;
  placeholder: string;

  constructor(key: string, label: string, placeholder: string) {
    this.key = key;
    this.label = label;
    this.placeholder = placeholder;
  }
}

/** @Builder 按引用传递参数（状态改变可刷新 UI）。 */
interface ChipParams {
  label: string;
  active: boolean;
  onTap: () => void;
}

interface SliderParams {
  label: string;
  valueText: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (v: number) => void;
}

/** 设置卡片容器。 */
@Component
struct TranslateSettingCard {
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * 翻译设置页（S107 设置侧）：默认引擎、目标/源语言、上下文轮次、
 * 思考模式、温度与提示词覆盖编辑。
 * 写入 starflow_translate（SettingsRepository 路由），translate-dev 读同一份键。
 */
@Component
export struct SettingsTranslatePage {
  @State engineType: number = 0;
  @State targetLang: string = 'zh';
  @State sourceLang: string = 'auto';
  @State contextTurns: number = 8;
  @State thinkingMode: number = 1;
  @State temperature: number = 0.3;
  @State promptKind: number = 0;
  @State promptDraft: string = '';
  @State savedPrompt: string = '';
  @State hint: string = '';
  @State glossaryCount: number = 0;
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  private navStack: NavPathStack = AppEnv.getInstance().navStack;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private engines: Array<Choice> = [
    new Choice('0', '必应'),
    new Choice('1', 'OpenAI 兼容'),
    new Choice('2', '本地 llama')
  ];
  private targetLangs: Array<Choice> = [
    new Choice('zh', '简体中文'),
    new Choice('zh-TW', '繁體中文'),
    new Choice('en', 'English'),
    new Choice('ja', '日本語'),
    new Choice('ko', '한국어')
  ];
  private sourceLangs: Array<Choice> = [
    new Choice('auto', '自动识别'),
    new Choice('ja', '日本語'),
    new Choice('en', 'English'),
    new Choice('zh', '中文'),
    new Choice('ko', '한국어')
  ];
  private thinkings: Array<Choice> = [
    new Choice('0', '关'),
    new Choice('1', '自动'),
    new Choice('2', '开')
  ];
  private promptKinds: Array<PromptKind> = [
    new PromptKind(SettingsKeys.PROMPT_MANGA, '漫画',
      '留空使用内置漫画模板；可含 %TARGET_LANG% / %SOURCE_LANG% 占位符'),
    new PromptKind(SettingsKeys.PROMPT_GAME, '游戏',
      '留空使用内置游戏模板；可含 %TARGET_LANG% / %SOURCE_LANG% 占位符'),
    new PromptKind(SettingsKeys.PROMPT_NOVEL, '小说',
      '留空使用内置小说模板；可含 %TARGET_LANG% / %SOURCE_LANG% 占位符'),
    new PromptKind(SettingsKeys.PROMPT_TEXT, '文本',
      '留空使用内置文本模板；可含 %TARGET_LANG% / %SOURCE_LANG% 占位符')
  ];

  aboutToAppear(): void {
    this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
      this.sizeClass = c;
    });
    this.load();
  }

  aboutToDisappear(): void {
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  private async load(): Promise<void> {
    const s: TranslateSettings = await SettingsRepository.loadTranslateSettings();
    this.engineType = s.engineType;
    // 文本/对话翻译页以 openai_provider 为单一真源；这里读同一份，避免设置页与
    // 翻译页显示不一致（如设置页显示 OpenAI、翻译页却是必应）。
    try {
      const provider: string = await TextTranslateViewModel.loadProvider();
      this.engineType = provider === 'bing' ? 0 : (provider === 'local' ? 2 : 1);
    } catch (e) {
      // 保持 SettingsRepository 中的值
    }
    this.targetLang = s.targetLang;
    if (this.targetLang !== await SettingsRepository.getString(SettingsKeys.TARGET_LANG, 'zh')) {
      // 文本翻译页显式选择过目标语言：以 text_target_lang 为准并回写单一真源。
      await SettingsRepository.set(SettingsKeys.TARGET_LANG, this.targetLang);
    }
    this.sourceLang = await SettingsRepository.getString(SettingsKeys.TEXT_SOURCE_LANG, 'auto');
    this.contextTurns = s.contextTurns;
    this.thinkingMode = s.thinkingMode;
    this.temperature = s.temperature;
    await GlossaryService.load();
    this.glossaryCount = GlossaryService.count();
    await this.loadPrompt();
  }

  private async loadPrompt(): Promise<void> {
    const kind: PromptKind = this.promptKinds[this.promptKind];
    const raw: string = await SettingsRepository.getString(kind.key, '');
    this.savedPrompt = raw;
    this.promptDraft = raw;
  }

  private flash(text: string): void {
    this.hint = text;
    setTimeout(() => {
      if (this.hint === text) {
        this.hint = '';
      }
    }, 1400);
  }

  private async pickEngine(value: string): Promise<void> {
    this.engineType = Number.parseInt(value);
    await SettingsRepository.set(SettingsKeys.ENGINE_TYPE, this.engineType);
    // 与文本/对话翻译页共享同一份 provider，避免两处引擎选择不同步。
    try {
      let provider = this.engineType === 0 ? 'bing' : (this.engineType === 2 ? 'local' : '');
      if (provider.length === 0) {
        const current: string = await TextTranslateViewModel.loadProvider();
        provider = (current === 'bing' || current === 'local') ? EnginePresets.defaultPreset().id : current;
      }
      await TextTranslateViewModel.saveEngineChoice(provider);
      await SettingsRepository.set(SettingsKeys.API_PROVIDER, this.engineType === 0 ? 'bing' : 'openai');
    } catch (e) {
      // 忽略：provider 同步失败不影响设置保存
    }
    this.flash('默认引擎已更新');
  }

  private async pickTarget(value: string): Promise<void> {
    this.targetLang = value;
    await SettingsRepository.set(SettingsKeys.TARGET_LANG, value);
    // translate-dev 读取顺序 text_target_lang > target_lang；写两份保持一致。
    await SettingsRepository.set(SettingsKeys.TEXT_TARGET_LANG, value);
    this.flash('目标语言已更新');
  }

  private async pickSource(value: string): Promise<void> {
    this.sourceLang = value;
    await SettingsRepository.set(SettingsKeys.SOURCE_LANG, value);
    await SettingsRepository.set(SettingsKeys.TEXT_SOURCE_LANG, value);
    this.flash('源语言已更新');
  }

  private async pickThinking(value: string): Promise<void> {
    this.thinkingMode = Number.parseInt(value);
    await SettingsRepository.set(SettingsKeys.TRANSLATE_THINKING_MODE, this.thinkingMode);
    this.flash('思考模式已更新');
  }

  private async changeContext(v: number): Promise<void> {
    this.contextTurns = Math.round(v);
    await SettingsRepository.set(SettingsKeys.TRANSLATE_CONTEXT_TURNS, this.contextTurns);
  }

  private async changeTemperature(v: number): Promise<void> {
    this.temperature = Math.round(v * 10) / 10;
    await SettingsRepository.set(SettingsKeys.TRANSLATE_TEMPERATURE, this.temperature);
  }

  private async pickPromptKind(index: number): Promise<void> {
    if (this.promptDraft !== this.savedPrompt) {
      this.flash('上一类提示词尚未保存');
    }
    this.promptKind = index;
    await this.loadPrompt();
  }

  private async savePrompt(): Promise<void> {
    const kind: PromptKind = this.promptKinds[this.promptKind];
    await SettingsRepository.set(kind.key, this.promptDraft.trim());
    this.savedPrompt = this.promptDraft.trim();
    this.flash(`${kind.label}提示词已保存`);
  }

  private async resetPrompt(): Promise<void> {
    const kind: PromptKind = this.promptKinds[this.promptKind];
    await SettingsRepository.remove(kind.key);
    this.promptDraft = '';
    this.savedPrompt = '';
    this.flash(`${kind.label}提示词已恢复内置模板`);
  }

  private isWide(): boolean {
    return this.sizeClass === WindowSizeClass.LG;
  }

  @Builder
  sectionTitle(title: string, desc: string) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      if (desc.length > 0) {
        Text(desc)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 6, bottom: 2 })
  }

  @Builder
  optionChip(pp: ChipParams) {
    Text(pp.label)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(pp.active ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(pp.active ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_VARIANT)
      .margin({ right: 8, bottom: 6 })
      .onClick(() => {
        pp.onTap();
      })
  }

  @Builder
  sliderRow(pp: SliderParams) {
    Column({ space: 4 }) {
      Row() {
        Text(pp.label)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
        Blank()
        Text(pp.valueText)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.PRIMARY_SOFT)
      }
      .width('100%')

      Slider({
        value: pp.value,
        min: pp.min,
        max: pp.max,
        step: pp.step,
        style: SliderStyle.OutSet
      })
        .selectedColor(ThemeTokens.PRIMARY)
        .trackColor(ThemeTokens.SURFACE_VARIANT)
        .blockColor(ThemeTokens.PRIMARY_SOFT)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          interactive: true,
          lightEffect: {}
        }))
        .width('100%')
        .onChange((v: number) => {
          pp.onChange(v);
        })
    }
    .width('100%')
    .margin({ top: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  private async importGlossary(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['术语表 JSON|.json'];
      opts.selectMode = picker.DocumentSelectMode.FILE;
      const uris = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      const count = await GlossaryService.importFromUri(uris[0]);
      this.glossaryCount = count;
      this.hint = '术语表已导入：' + count + ' 条';
    } catch (e) {
      this.hint = '导入术语表失败：' + e;
    }
  }

  private async clearGlossary(): Promise<void> {
    await GlossaryService.clear();
    this.glossaryCount = 0;
    this.hint = '术语表已清空';
  }

  build() {
    NavDestination() {
      Scroll() {
        Row() {
          Column({ space: 12 }) {
            Row() {
              Column({ space: 2 }) {
                Text('翻译与引擎')
                  .fontSize(ThemeTokens.FONT_TITLE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeTokens.TEXT_PRIMARY)
                Text('与文本/对话翻译、阅读器批量翻译共享同一份设置')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_HINT)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (this.hint.length > 0) {
                Text(this.hint)
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.SUCCESS)
                  .maxLines(1)
              }
            }
            .width('100%')

            this.sectionTitle('默认翻译引擎', '必应免 Key；OpenAI 兼容与本地 llama 需在 API 配置/模型管理中准备')
            TranslateSettingCard() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.engines, (opt: Choice) => {
                  this.optionChip({ label: opt.label, active: this.engineType === Number.parseInt(opt.value), onTap: () => {
                    this.pickEngine(opt.value);
                  } })
                }, (opt: Choice) => opt.value)
              }
              .width('100%')

              Text(SettingsTranslatePage.engineNote(this.engineType))
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
                .width('100%')
                .lineHeight(17)
                .margin({ top: 2 })

              Divider()
                .color(ThemeTokens.DIVIDER)
                .strokeWidth(0.5)
                .margin({ top: 10, bottom: 10 })

              Row() {
                Text('API 配置')
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .fontColor(ThemeTokens.TEXT_SECONDARY)
                Blank()
                Text('Base URL / 模型 / Key 与连通性测试')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_HINT)
                  .maxLines(1)
                Image($r('app.media.ic_arrow_right'))
                  .width(12)
                  .height(12)
                  .fillColor(ThemeTokens.TEXT_TERTIARY)
                  .margin({ left: 4 })
              }
              .width('100%')
              .onClick(() => {
                this.navStack.pushPathByName(Routes.API_CONFIG, '');
              })
            }

            this.sectionTitle('目标语言', '文本、对话与阅读器页面翻译的默认目标语言')
            TranslateSettingCard() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.targetLangs, (opt: Choice) => {
                  this.optionChip({ label: opt.label, active: this.targetLang === opt.value, onTap: () => {
                    this.pickTarget(opt.value);
                  } })
                }, (opt: Choice) => opt.value)
              }
              .width('100%')
            }

            this.sectionTitle('源语言', '默认自动识别；也可固定源语言提高识别准确率')
            TranslateSettingCard() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.sourceLangs, (opt: Choice) => {
                  this.optionChip({ label: opt.label, active: this.sourceLang === opt.value, onTap: () => {
                    this.pickSource(opt.value);
                  } })
                }, (opt: Choice) => opt.value)
              }
              .width('100%')
            }

            this.sectionTitle('术语表', '导入 JSON 数组 [{"s":"原文","t":"译文"}]，翻译前按最长优先替换')
            TranslateSettingCard() {
              Row({ space: 8 }) {
                Text(this.glossaryCount > 0 ? this.glossaryCount + ' 条术语' : '尚未导入')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(this.glossaryCount > 0 ? ThemeTokens.SUCCESS : ThemeTokens.TEXT_HINT)
                  .layoutWeight(1)
                Button('导入')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .height(30)
                  .borderRadius(ThemeTokens.RADIUS_PILL)
                  .backgroundColor(ThemeTokens.PRIMARY)
                  .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                  .onClick(() => {
                    this.importGlossary();
                  })
                if (this.glossaryCount > 0) {
                  Button('清空')
                    .fontSize(ThemeTokens.FONT_SMALL)
                    .height(30)
                    .borderRadius(ThemeTokens.RADIUS_PILL)
                    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
                    .fontColor(ThemeTokens.TEXT_SECONDARY)
                    .onClick(() => {
                      this.clearGlossary();
                    })
                }
              }
              .width('100%')
            }

            this.sectionTitle('对话上下文轮次', '对话翻译携带的历史轮数（5–20 轮）')
            TranslateSettingCard() {
              this.sliderRow({ label: '轮次', valueText: `${this.contextTurns} 轮`, value: this.contextTurns, min: 5, max: 20, step: 1, onChange: (v: number) => {
                this.changeContext(v);
              } })
            }

            this.sectionTitle('思考模式', '对推理模型：关 / 自动 / 强制开启思考')
            TranslateSettingCard() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.thinkings, (opt: Choice) => {
                  this.optionChip({ label: opt.label, active: this.thinkingMode === Number.parseInt(opt.value), onTap: () => {
                    this.pickThinking(opt.value);
                  } })
                }, (opt: Choice) => opt.value)
              }
              .width('100%')
              Text('关=不请求思考；自动=由模型决定；开=请求思考内容。')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
                .width('100%')
            }

            this.sectionTitle('温度', '采样温度，越低越稳定，越高越发散（0.0–2.0）')
            TranslateSettingCard() {
              this.sliderRow({ label: '温度', valueText: `${this.temperature.toFixed(1)}`, value: this.temperature, min: 0, max: 2, step: 0.1, onChange: (v: number) => {
                this.changeTemperature(v);
              } })
            }

            this.sectionTitle('提示词编辑', '漫画 / 游戏 / 小说 / 文本四类独立模板，留空回退内置')
            TranslateSettingCard() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.promptKinds, (kind: PromptKind, index: number) => {
                  this.optionChip({ label: kind.label, active: this.promptKind === index, onTap: () => {
                    this.pickPromptKind(index);
                  } })
                }, (kind: PromptKind) => kind.key)
              }
              .width('100%')

              TextArea({
                text: this.promptDraft,
                placeholder: this.promptKinds[this.promptKind].placeholder
              })
                .fontSize(ThemeTokens.FONT_CAPTION)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
                .placeholderColor(ThemeTokens.TEXT_HINT)
                .backgroundColor(ThemeTokens.SURFACE_VARIANT)
                .borderRadius(ThemeTokens.RADIUS_SMALL)
                .width('100%')
                .height(140)
                .margin({ top: 4 })
                .onChange((v: string) => {
                  this.promptDraft = v;
                })

              Row({ space: 10 }) {
                Button('保存提示词')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                  .backgroundColor(ThemeTokens.PRIMARY)
                  .borderRadius(ThemeTokens.RADIUS_PILL)
                  .height(34)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.savePrompt();
                  })
                Button('恢复内置')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_SECONDARY)
                  .backgroundColor(ThemeTokens.SURFACE_VARIANT)
                  .borderRadius(ThemeTokens.RADIUS_PILL)
                  .height(34)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.resetPrompt();
                  })
              }
              .width('100%')
              .margin({ top: 10 })

              if (this.savedPrompt.length > 0) {
                Text('当前使用自定义提示词；恢复内置后使用应用内置模板。')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.WARN)
                  .width('100%')
                  .margin({ top: 6 })
              }
            }

            Text('提示：提示词仅影响使用该模板的翻译场景；改完即时生效，无需重启。')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_TERTIARY)
              .width('100%')
              .lineHeight(18)
              .margin({ top: 2, bottom: 12 })
          }
          .width(this.isWide() ? 760 : '100%')
          .padding({
            left: ThemeTokens.PAGE_PADDING,
            right: ThemeTokens.PAGE_PADDING,
            top: 12,
            bottom: 24
          })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Top)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
    .title('翻译设置', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true,
        interactive: true,
        lightEffect: {}
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
  }

  private static engineNote(engine: number): string {
    if (engine === 1) {
      return 'OpenAI 兼容：支持 DeepSeek / 通义千问 / 豆包 / 智谱等厂商预设，需在 API 配置填写 Base URL、模型与 Key。';
    }
    if (engine === 2) {
      return '本地 llama：需先在模型管理下载 Hy-MT2 GGUF 模型；完全离线推理，首次加载较慢。';
    }
    return '必应：免 Key 在线翻译，网络异常时会给出可读错误提示。';
  }
}