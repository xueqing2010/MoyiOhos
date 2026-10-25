/**
 * 引擎配置弹窗（stage 2 / S107）。
 *
 *  · 预设下拉：DeepSeek / 通义千问 / 豆包 / 智谱 / OpenAI / 自定义
 *  · Base URL + 模型名（随预设自动填默认值，自定义可手改）
 *  · API Key：掩码、不回显；存 AssetKeyStore(alias=openai_api_key)，重启可用
 *  · 测试连接：先 GET /models，失败再退化一次短翻译，结果分类可读
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { ThemeTokens } from 'commons';
import { EnginePreset, EnginePresets, ThinkingMode, describeThinking, isReasoningModel } from 'coretranslate';
import { ConnectionTestResult, TextTranslateViewModel } from '../viewmodel/TextTranslateViewModel';

@Component
export struct EngineConfigDialog {
  onSaved: () => void = () => {
  };
  onClose: () => void = () => {
  };

  @State provider: string = 'deepseek';
  @State presetIndex: number = 0;
  @State baseUrl: string = '';
  @State model: string = '';
  @State apiKey: string = '';
  @State hasKey: boolean = false;
  @State lowSecurity: boolean = false;
  @State message: string = '';
  @State messageOk: boolean = false;
  @State loading: boolean = true;
  @State testing: boolean = false;
  @State testDone: boolean = false;
  @State models: Array<string> = [];
  /** 思考模式三态（0 关 / 1 自动 / 2 开）。 */
  @State thinking: number = ThinkingMode.AUTO as number;

  private presetOptions: Array<SelectOption> = [];
  /** 打开弹窗时的引擎选择（bing/local 时保存不得改写 openai_provider）。 */
  private originalProvider: string = '';

  aboutToAppear(): void {
    this.buildOptions();
    this.init();
  }

  private buildOptions(): void {
    const opts: Array<SelectOption> = [];
    for (const p of EnginePresets.all()) {
      const o: SelectOption = { value: p.label };
      opts.push(o);
    }
    this.presetOptions = opts;
  }

  private async init(): Promise<void> {
    try {
      this.originalProvider = await TextTranslateViewModel.loadProvider();
      this.provider = this.originalProvider;
      if (this.provider === 'bing' || this.provider === 'local') {
        // 引擎不是 AI 时：仍展示「上次配置的端点」所属预设，但不改引擎选择
        const storedBase = await TextTranslateViewModel.loadOpenAiBaseUrl();
        const matched = EnginePresets.findByBaseUrl(storedBase);
        this.provider = matched === undefined
          ? EnginePresets.defaultPreset().id : matched.id;
      }
      this.presetIndex = EnginePresets.indexOf(this.provider);
      this.baseUrl = await TextTranslateViewModel.loadOpenAiBaseUrl();
      this.model = await TextTranslateViewModel.loadOpenAiModel();
      this.hasKey = await TextTranslateViewModel.hasApiKey();
      this.lowSecurity = TextTranslateViewModel.isLowSecurity();
      this.thinking = await TextTranslateViewModel.loadThinking();
    } catch (e) {
      this.message = '读取配置失败：' + TextTranslateViewModel.readableError(e);
    }
    this.loading = false;
  }

  private preset(): EnginePreset {
    return EnginePresets.byId(this.provider);
  }

  private async copyText(text: string): Promise<void> {
    if (text.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.message = '已复制';
      this.messageOk = true;
    } catch (e) {
      this.message = '复制失败，请手动记录：' + text;
      this.messageOk = false;
    }
  }

  /** 切换预设：填默认 baseUrl / 模型（自定义预设保留用户输入）。 */
  private pickPreset(index: number): void {
    const list = EnginePresets.all();
    if (index < 0 || index >= list.length) {
      return;
    }
    const p = list[index];
    this.provider = p.id;
    this.presetIndex = index;
    this.testDone = false;
    this.models = [];
    if (!p.custom) {
      this.baseUrl = p.baseUrl;
      this.model = p.defaultModel;
    } else if (this.baseUrl.trim().length === 0) {
      this.baseUrl = p.baseUrl;
    }
  }

  /** 测试连接：优先用输入框里的 Key，未填则用已保存的。 */
  private async testConnection(): Promise<void> {
    if (this.testing) {
      return;
    }
    const key = this.apiKey.trim().length > 0
      ? this.apiKey.trim()
      : ((await TextTranslateViewModel.loadApiKey()) ?? '');
    if (key.length === 0) {
      this.message = '请先填写 API Key 再测试';
      this.messageOk = false;
      return;
    }
    this.testing = true;
    this.testDone = false;
    this.message = '正在测试连接…';
    this.messageOk = false;
    try {
      const result: ConnectionTestResult = await TextTranslateViewModel.testConnection(
        this.baseUrl.trim(), this.model.trim(), key);
      this.message = result.message;
      this.messageOk = result.ok;
      this.testDone = result.ok;
      this.models = result.models;
    } catch (e) {
      this.message = '测试失败：' + TextTranslateViewModel.readableError(e);
      this.messageOk = false;
    }
    this.testing = false;
  }

  private async save(): Promise<void> {
    if (this.baseUrl.trim().length === 0) {
      this.message = 'Base URL 不能为空';
      this.messageOk = false;
      return;
    }
    if (this.model.trim().length === 0) {
      this.message = '模型名不能为空（可点「测试连接」自动拉取）';
      this.messageOk = false;
      return;
    }
    try {
      if (this.apiKey.trim().length > 0) {
        await TextTranslateViewModel.saveApiKey(this.apiKey.trim());
        this.apiKey = '';
        this.hasKey = true;
      }
      // bing / local 引擎下只保存端点与 Key，不改写用户的引擎选择
      const providerToSave = (this.originalProvider === 'bing'
        || this.originalProvider === 'local')
        ? this.originalProvider : this.provider;
      await TextTranslateViewModel.saveFullConfig(providerToSave, this.baseUrl, this.model);
      await TextTranslateViewModel.saveThinking(this.thinking as ThinkingMode);
      await TextTranslateViewModel.applyOpenAiConfig();
      this.onSaved();
    } catch (e) {
      this.message = '保存失败：' + TextTranslateViewModel.readableError(e);
      this.messageOk = false;
    }
  }

  private async clearKey(): Promise<void> {
    try {
      await TextTranslateViewModel.clearApiKey();
      this.hasKey = false;
      this.apiKey = '';
      this.message = '已清除保存的 API Key';
      this.messageOk = true;
    } catch (e) {
      this.message = '清除失败：' + TextTranslateViewModel.readableError(e);
      this.messageOk = false;
    }
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(ThemeTokens.TEXT_HINT)
      .width('100%')
      .margin({ top: 6 });
  }

  @Builder
  modelChip(name: string) {
    Text(name)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(this.model === name ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      .backgroundColor(this.model === name ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_HIGH)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .height(28)
      .padding({ left: 10, right: 10 })
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.model = name;
      });
  }

  @Builder
  thinkingChip(value: number, label: string) {
    Text(label)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(this.thinking === value ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      .backgroundColor(this.thinking === value ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_HIGH)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .height(30)
      .padding({ left: 14, right: 14 })
      .onClick(() => {
        this.thinking = value;
      });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Column({ space: 2 }) {
          Text('引擎配置')
            .fontSize(ThemeTokens.FONT_SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
            .width('100%')
          Text('选择预设后填入 API Key 即可使用；Key 本地加密保存，不回显')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
            .width('100%')
        }
        .width('100%')
        .margin({ bottom: 8 });

        Scroll() {
          Column({ space: 2 }) {
            this.fieldLabel('厂商预设');
            Select(this.presetOptions)
              .selected(this.presetIndex)
              .value(this.preset().label)
              .font({ size: ThemeTokens.FONT_CAPTION })
              .fontColor(ThemeTokens.TEXT_PRIMARY)
              .backgroundColor(ThemeTokens.SURFACE_VARIANT)
              .width('100%')
              .onSelect((index: number) => {
                this.pickPreset(index);
              });
            Text(this.preset().hint)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_TERTIARY)
              .width('100%');
            if (this.preset().consoleUrl.length > 0) {
              Row({ space: 6 }) {
                Text('获取 Key：' + this.preset().consoleUrl)
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.PRIMARY_SOFT)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
                Text('复制')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_SECONDARY)
                  .onClick(() => {
                    this.copyText(this.preset().consoleUrl);
                  });
              }
              .width('100%')
              .alignItems(VerticalAlign.Center);
            }

            this.fieldLabel('Base URL');
            if (!this.preset().custom) {
              Text('预设端点固定；需要代理 / 中转请选择「自定义」')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_TERTIARY)
                .width('100%');
            }
            TextInput({ text: this.baseUrl, placeholder: 'https://api.example.com/v1' })
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
              .backgroundColor(ThemeTokens.SURFACE_VARIANT)
              .borderRadius(ThemeTokens.RADIUS_SMALL)
              .width('100%')
              .enabled(!this.preset().custom ? false : true)
              .onChange((v: string) => {
                this.baseUrl = v;
              });

            this.fieldLabel('模型名');
            TextInput({ text: this.model, placeholder: '如 deepseek-chat / qwen-plus' })
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
              .backgroundColor(ThemeTokens.SURFACE_VARIANT)
              .borderRadius(ThemeTokens.RADIUS_SMALL)
              .width('100%')
              .onChange((v: string) => {
                this.model = v;
              });
            if (this.model.length > 0 && isReasoningModel(this.model)) {
              Text('推理模型：响应更慢，自动思考模式下只加简短思考约束')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.WARN)
                .width('100%');
            }

            this.fieldLabel('思考模式');
            Row({ space: 8 }) {
              this.thinkingChip(ThinkingMode.OFF as number, '关闭');
              this.thinkingChip(ThinkingMode.AUTO as number, '自动');
              this.thinkingChip(ThinkingMode.ON as number, '开启');
            }
            .width('100%');
            Text(describeThinking(this.thinking as ThinkingMode, this.model))
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_TERTIARY)
              .width('100%');

            this.fieldLabel('API Key');
            TextInput({
              text: this.apiKey,
              placeholder: this.hasKey ? '已保存（••••••••，如需更换请输入）' : '粘贴 API Key'
            })
              .type(InputType.Password)
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
              .backgroundColor(ThemeTokens.SURFACE_VARIANT)
              .borderRadius(ThemeTokens.RADIUS_SMALL)
              .width('100%')
              .onChange((v: string) => {
                this.apiKey = v;
              });
            Row() {
              if (this.hasKey) {
                Text('已保存 Key：••••••••')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.SUCCESS)
                  .layoutWeight(1);
                Text('清除')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.RED)
                  .onClick(() => {
                    this.clearKey();
                  });
              } else {
                Text('尚未保存 Key')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_HINT)
                  .layoutWeight(1);
              }
            }
            .width('100%')
            .margin({ top: 4 });

            Button(this.testing ? '测试中…' : '测试连接')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.SURFACE_HIGH)
              .borderRadius(ThemeTokens.RADIUS_PILL)
              .height(34)
              .width('100%')
              .margin({ top: 8 })
              .enabled(!this.testing)
              .onClick(() => {
                this.testConnection();
              });

            if (this.testDone && this.models.length > 0) {
              this.fieldLabel('可用模型（点击填入，最多显示 12 个）');
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.models.slice(0, 12), (name: string) => {
                  this.modelChip(name);
                }, (name: string) => name);
              }
              .width('100%');
            }

            if (this.lowSecurity) {
              Text('低安全模式：系统资产存储不可用，Key 经 preferences 保存')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.WARN)
                .width('100%')
                .margin({ top: 6 });
            }

            if (this.message.length > 0) {
              Text(this.message)
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(this.messageOk ? ThemeTokens.SUCCESS : ThemeTokens.RED)
                .width('100%')
                .margin({ top: 8 });
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(40)
            .layoutWeight(1)
            .onClick(() => {
              this.onClose();
            });
          Button('保存')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(40)
            .layoutWeight(1)
            .enabled(!this.loading)
            .onClick(() => {
              this.save();
            });
        }
        .width('100%')
        .margin({ top: 10 });
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('92%')
      .height('78%')
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
  }
}