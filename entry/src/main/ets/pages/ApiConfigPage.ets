import fs from '@ohos.file.fs';
import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens, WindowSizeClass, observeBreakpoint, Log } from 'commons';
import { EngineType, OpenAiConfig, TranslateRequest } from 'coretranslate';
import { AppEnv } from '../common/AppEnv';
import { Routes } from '../common/Routes';
import { DownloadRepository } from '../data/DownloadRepository';
import { SettingsKeys, SettingsRepository } from '../data/SettingsRepository';

const KEY_ALIAS_OPENAI = SettingsKeys.OPENAI_KEY_ALIAS;
const TAG = 'ApiConfigPage';

/** OpenAI 兼容厂商预设。 */
class ProviderPreset {
  id: string;
  name: string;
  baseUrl: string;
  model: string;
  desc: string;

  constructor(id: string, name: string, baseUrl: string, model: string, desc: string) {
    this.id = id;
    this.name = name;
    this.baseUrl = baseUrl;
    this.model = model;
    this.desc = desc;
  }
}

/** 引擎状态徽标。 */
class EngineStatus {
  text: string;
  color: string;

  constructor(text: string, color: string) {
    this.text = text;
    this.color = color;
  }
}

/** @Builder 按引用传递参数（引擎状态/选中态变化可刷新 UI）。 */
interface EngineBadgeParams {
  status: EngineStatus;
}

interface EngineRowParams {
  title: string;
  desc: string;
  icon: Resource;
  status: EngineStatus;
  active: boolean;
  onTap: () => void;
}

/** 设置卡片容器。 */
@Component
struct ApiCard {
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
 * API 配置页（S107）：引擎列表（必应 / OpenAI 兼容 / 本地 llama）+ 厂商预设、
 * Base URL / 模型 / Key 掩码配置弹窗、连通性测试与状态徽标。
 * Key 存 AssetKeyStore（alias=openai_api_key，与 translate-dev 一致，掩码不回显）。
 */
@Component
export struct ApiConfigPage {
  @State engineType: number = 0;
  @State provider: string = 'openai';
  @State baseUrl: string = '';
  @State model: string = '';
  @State hasKey: boolean = false;
  @State lowSecurity: boolean = false;
  @State showConfig: boolean = false;
  @State draftProvider: string = 'openai';
  @State draftBaseUrl: string = '';
  @State draftModel: string = '';
  @State draftKey: string = '';
  @State testing: boolean = false;
  @State testOk: boolean = false;
  @State testMessage: string = '';
  @State testingEngine: boolean = false;
  @State engineTestOk: boolean = false;
  @State engineTestMessage: string = '';
  @State localModelLabel: string = '';
  @State localModelReady: boolean = false;
  @State hint: string = '';
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  private navStack: NavPathStack = AppEnv.getInstance().navStack;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private providers: Array<ProviderPreset> = [
    new ProviderPreset('openai', 'OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini', 'OpenAI 官方或同协议端点'),
    new ProviderPreset('deepseek', 'DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat', '深度求索，中文表现好'),
    new ProviderPreset('qwen', '通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus', '阿里云 DashScope 兼容模式'),
    new ProviderPreset('doubao', '豆包', 'https://ark.cn-beijing.volces.com/api/v3', 'doubao-pro-32k', '火山方舟 Ark 兼容端点'),
    new ProviderPreset('zhipu', '智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash', '智谱开放平台'),
    new ProviderPreset('custom', '自定义', '', '', '任意 OpenAI 兼容 Base URL 与模型名')
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
    this.engineType = await SettingsRepository.getNumber(SettingsKeys.ENGINE_TYPE, 0);
    this.provider = await SettingsRepository.getString(SettingsKeys.API_PROVIDER, 'openai');
    this.baseUrl = await SettingsRepository.getString(SettingsKeys.OPENAI_BASE_URL, 'https://api.openai.com/v1');
    this.model = await SettingsRepository.getString(SettingsKeys.OPENAI_MODEL, '');
    const key = await AppEnv.getInstance().getKeyStore().load(KEY_ALIAS_OPENAI);
    this.hasKey = key !== undefined && key.length > 0;
    this.lowSecurity = AppEnv.getInstance().getKeyStore().isLowSecurityMode();
    await this.detectLocalModel();
  }

  /** 检测本地 GGUF 是否已下载/导入（只读 DownloadRepository）。 */
  private async detectLocalModel(): Promise<void> {
    try {
      await AppEnv.ready();
      const tasks = await DownloadRepository.listAll();
      for (const task of tasks) {
        const path = task.localPath ?? '';
        if (path.length === 0) {
          continue;
        }
        let exists = false;
        try {
          exists = fs.accessSync(path);
        } catch (e) {
          exists = false;
        }
        if (exists) {
          this.localModelLabel = task.displayName.length > 0 ? task.displayName : path;
          this.localModelReady = true;
          return;
        }
      }
      this.localModelLabel = '';
      this.localModelReady = false;
    } catch (e) {
      this.localModelLabel = '';
      this.localModelReady = false;
    }
  }

  private flash(text: string): void {
    this.hint = text;
    setTimeout(() => {
      if (this.hint === text) {
        this.hint = '';
      }
    }, 1600);
  }

  private bingStatus(): EngineStatus {
    return new EngineStatus('免 Key · 在线', ThemeTokens.SUCCESS);
  }

  private openAiStatus(): EngineStatus {
    if (this.baseUrl.length === 0 || this.model.length === 0) {
      return new EngineStatus('未配置', ThemeTokens.WARN);
    }
    if (!this.hasKey) {
      return new EngineStatus('缺 API Key', ThemeTokens.WARN);
    }
    return new EngineStatus('已配置', ThemeTokens.SUCCESS);
  }

  private localStatus(): EngineStatus {
    if (this.localModelReady) {
      return new EngineStatus('模型就绪', ThemeTokens.SUCCESS);
    }
    return new EngineStatus('未下载模型', ThemeTokens.TEXT_HINT);
  }

  private providerName(id: string): string {
    for (const p of this.providers) {
      if (p.id === id) {
        return p.name;
      }
    }
    if (id === 'bing') {
      return '未选择厂商';
    }
    return '自定义';
  }

  /** 应用已持久化的 OpenAI 配置到运行时引擎（取消/测试后回滚用）。 */
  private async applySavedConfig(): Promise<void> {
    const base = await SettingsRepository.getString(SettingsKeys.OPENAI_BASE_URL, '');
    const model = await SettingsRepository.getString(SettingsKeys.OPENAI_MODEL, '');
    const key = await AppEnv.getInstance().getKeyStore().load(KEY_ALIAS_OPENAI);
    const translator = AppEnv.getInstance().getOpenAiTranslator();
    if (translator !== undefined) {
      translator.setConfig(new OpenAiConfig(base, key ?? '', model));
    }
  }

  /** 取消配置弹窗：把测试时写入运行时的草稿配置回滚为已保存配置。 */
  private async cancelConfig(): Promise<void> {
    await this.applySavedConfig();
    this.showConfig = false;
  }

  /** 测试当前默认引擎连通性（必应实译一词 / OpenAI 兼容列模型 / 本地查模型文件）。 */
  private async testCurrent(): Promise<void> {
    if (this.testingEngine) {
      return;
    }
    this.testingEngine = true;
    try {
      await AppEnv.ready();
    } catch (ignore) {
      // 引擎/数据库未就绪时继续走下面的失败分支
    }
    this.engineTestMessage = '';
    this.engineTestOk = false;
    try {
      if (this.engineType === 0) {
        const translator = AppEnv.getInstance().engineRegistry.get(EngineType.BING);
        const req: TranslateRequest = { text: 'hello', from: 'en', to: 'zh' };
        const result = await translator.translate(req);
        this.engineTestOk = true;
        this.engineTestMessage = `必应连通：hello → ${result}`;
      } else if (this.engineType === 1) {
        await this.applySavedConfig();
        const translator = AppEnv.getInstance().getOpenAiTranslator();
        if (translator === undefined) {
          throw new Error('OpenAI 兼容引擎未注册');
        }
        const models = await translator.listModels();
        this.engineTestOk = true;
        this.engineTestMessage = `OpenAI 兼容连通：端点返回 ${models.length} 个模型`;
      } else {
        if (this.localModelReady) {
          this.engineTestOk = true;
          this.engineTestMessage = `本地模型已就绪：${this.localModelLabel}`;
        } else {
          throw new Error('尚未下载本地 GGUF 模型');
        }
      }
    } catch (e) {
      const err = e as Error;
      this.engineTestOk = false;
      this.engineTestMessage = `测试失败：${err !== undefined && err.message !== undefined ? err.message : e}`;
      Log.warn(TAG, `testCurrent failed: ${this.engineTestMessage}`);
    }
    this.testingEngine = false;
  }

  private async selectBing(): Promise<void> {
    this.engineType = 0;
    await SettingsRepository.set(SettingsKeys.ENGINE_TYPE, 0);
    await SettingsRepository.set(SettingsKeys.API_PROVIDER, 'bing');
    this.flash('默认引擎已切换为必应');
  }

  private async selectLocal(): Promise<void> {
    this.engineType = 2;
    await SettingsRepository.set(SettingsKeys.ENGINE_TYPE, 2);
    this.flash(this.localModelReady ? '默认引擎已切换为本地 llama' : '请先在模型管理下载 GGUF 模型');
  }

  private openConfigDialog(): void {
    this.draftProvider = this.provider === 'bing' ? 'openai' : this.provider;
    this.draftBaseUrl = this.baseUrl;
    this.draftModel = this.model;
    this.draftKey = '';
    this.testMessage = '';
    this.testOk = false;
    this.showConfig = true;
  }

  private pickProvider(id: string): void {
    this.draftProvider = id;
    for (const p of this.providers) {
      if (p.id === id) {
        if (id !== 'custom') {
          this.draftBaseUrl = p.baseUrl;
          this.draftModel = p.model;
        }
        return;
      }
    }
  }

  /** 用当前草稿 + 已保存 Key 测试 OpenAI 兼容端点。 */
  private async testConnection(): Promise<void> {
    if (this.testing) {
      return;
    }
    this.testing = true;
    this.testMessage = '';
    this.testOk = false;
    try {
      await AppEnv.ready();
      const translator = AppEnv.getInstance().getOpenAiTranslator();
      if (translator === undefined) {
        throw new Error('OpenAI 兼容引擎未注册');
      }
      let key = this.draftKey.trim();
      if (key.length === 0) {
        const saved = await AppEnv.getInstance().getKeyStore().load(KEY_ALIAS_OPENAI);
        key = saved ?? '';
      }
      if (this.draftBaseUrl.trim().length === 0) {
        throw new Error('请填写 Base URL');
      }
      if (key.length === 0) {
        throw new Error('请填写 API Key');
      }
      translator.setConfig(new OpenAiConfig(this.draftBaseUrl.trim(), key, this.draftModel.trim()));
      const models = await translator.listModels();
      this.testOk = true;
      this.testMessage = models.length > 0
        ? `连接成功：端点返回 ${models.length} 个模型`
        : '连接成功：端点可达（未返回模型列表）';
    } catch (e) {
      const err = e as Error;
      this.testOk = false;
      this.testMessage = `连接失败：${err !== undefined && err.message !== undefined ? err.message : e}`;
      Log.warn(TAG, `test connection failed: ${this.testMessage}`);
    }
    this.testing = false;
  }

  private async saveConfig(): Promise<void> {
    try {
      const base = this.draftBaseUrl.trim();
      const model = this.draftModel.trim();
      if (base.length === 0) {
        this.testMessage = '请填写 Base URL';
        return;
      }
      if (model.length === 0) {
        this.testMessage = '请填写模型名';
        return;
      }
      if (this.draftKey.trim().length > 0) {
        await AppEnv.getInstance().getKeyStore().save(KEY_ALIAS_OPENAI, this.draftKey.trim());
      }
      await SettingsRepository.set(SettingsKeys.OPENAI_BASE_URL, base);
      await SettingsRepository.set(SettingsKeys.OPENAI_MODEL, model);
      await SettingsRepository.set(SettingsKeys.API_PROVIDER, this.draftProvider);
      await SettingsRepository.set(SettingsKeys.ENGINE_TYPE, 1);
      // 同步运行时引擎实例。
      const translator = AppEnv.getInstance().getOpenAiTranslator();
      const savedKey = await AppEnv.getInstance().getKeyStore().load(KEY_ALIAS_OPENAI);
      if (translator !== undefined) {
        translator.setConfig(new OpenAiConfig(base, savedKey ?? '', model));
      }
      this.engineType = 1;
      this.provider = this.draftProvider;
      this.baseUrl = base;
      this.model = model;
      this.hasKey = savedKey !== undefined && savedKey.length > 0;
      this.showConfig = false;
      this.flash(`已保存 ${this.providerName(this.draftProvider)} 配置`);
    } catch (e) {
      this.testMessage = `保存失败：${e}`;
    }
  }

  private isWide(): boolean {
    return this.sizeClass === WindowSizeClass.LG;
  }

  @Builder
  statusBadge(pp: EngineBadgeParams) {
    Text(pp.status.text)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(pp.status.color)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
  }

  @Builder
  engineRow(pp: EngineRowParams) {
    Row({ space: 12 }) {
      Column() {
        Image(pp.icon)
          .width(20)
          .height(20)
          .fillColor(pp.active ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_SECONDARY)
      }
      .width(38)
      .height(38)
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .justifyContent(FlexAlign.Center)

      Column({ space: 3 }) {
        Row({ space: 8 }) {
          Text(pp.title)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
          if (pp.active) {
            Text('当前默认')
              .fontSize(10)
              .fontColor(ThemeTokens.PRIMARY)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(ThemeTokens.RADIUS_PILL)
              .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          }
        }
        Text(pp.desc)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .lineHeight(16)
          .maxLines(3)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.statusBadge({ status: pp.status })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .onClick(() => {
      pp.onTap();
    })
  }

  @Builder
  configDialog() {
    Column() {
      Column({ space: 10 }) {
        Text('OpenAI 兼容引擎配置')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .width('100%')

        Text('厂商预设')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.providers, (p: ProviderPreset) => {
            Text(p.name)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(this.draftProvider === p.id ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(ThemeTokens.RADIUS_PILL)
              .backgroundColor(this.draftProvider === p.id ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_VARIANT)
              .margin({ right: 6, bottom: 6 })
              .onClick(() => {
                this.pickProvider(p.id);
              })
          }, (p: ProviderPreset) => p.id)
        }
        .width('100%')

        Text('Base URL')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
        TextInput({ text: this.draftBaseUrl, placeholder: 'https://api.example.com/v1' })
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .width('100%')
          .onChange((v: string) => {
            this.draftBaseUrl = v;
          })

        Text('模型名')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
        TextInput({ text: this.draftModel, placeholder: '如 deepseek-chat / qwen-plus' })
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .width('100%')
          .onChange((v: string) => {
            this.draftModel = v;
          })

        Text(this.hasKey ? 'API Key（已保存，不回显；留空则保持不变）' : 'API Key')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
        TextInput({
          text: this.draftKey,
          placeholder: this.hasKey ? '••••••••（已保存）' : '输入 API Key'
        })
          .type(InputType.Password)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .width('100%')
          .onChange((v: string) => {
            this.draftKey = v;
          })

        if (this.lowSecurity) {
          Text('当前 Key 为低安全模式存储（Asset 不可用，降级 preferences）')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.WARN)
            .width('100%')
        }

        if (this.testMessage.length > 0) {
          Text(this.testMessage)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(this.testOk ? ThemeTokens.SUCCESS : ThemeTokens.RED)
            .width('100%')
            .lineHeight(17)
        }

        Row({ space: 8 }) {
          Button(this.testing ? '测试中…' : '测试连接')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(36)
            .layoutWeight(1)
            .enabled(!this.testing)
            .onClick(() => {
              this.testConnection();
            })
          Button('保存')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.saveConfig();
            })
        }
        .width('100%')

        Button('取消')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .backgroundColor(Color.Transparent)
          .width('100%')
          .height(32)
          .onClick(() => {
            this.showConfig = false;
          })
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('90%')
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    NavDestination() {
      Stack() {
        Scroll() {
          Row() {
            Column({ space: 12 }) {
              Row() {
                Column({ space: 2 }) {
                  Text('API 配置')
                    .fontSize(ThemeTokens.FONT_TITLE)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeTokens.TEXT_PRIMARY)
                  Text('翻译引擎与密钥；Key 存 Asset，界面只显示掩码')
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

              ApiCard() {
                Row({ space: 8 }) {
                  Text('当前默认引擎')
                    .fontSize(ThemeTokens.FONT_SMALL)
                    .fontColor(ThemeTokens.TEXT_HINT)
                  Blank()
                  Text(this.engineType === 1 ? `OpenAI 兼容 · ${this.providerName(this.provider)}`
                    : (this.engineType === 2 ? '本地 llama' : '必应'))
                    .fontSize(ThemeTokens.FONT_SMALL)
                    .fontColor(ThemeTokens.PRIMARY_SOFT)
                }
                .width('100%')
                Row({ space: 8 }) {
                  Button(this.testingEngine ? '测试中…' : '测试当前引擎')
                    .fontSize(ThemeTokens.FONT_SMALL)
                    .fontColor(ThemeTokens.TEXT_SECONDARY)
                    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
                    .borderRadius(ThemeTokens.RADIUS_PILL)
                    .height(32)
                    .padding({ left: 14, right: 14 })
                    .enabled(!this.testingEngine)
                    .onClick(() => {
                      this.testCurrent();
                    })
                  Blank()
                }
                .width('100%')
                if (this.engineTestMessage.length > 0) {
                  Text(this.engineTestMessage)
                    .fontSize(ThemeTokens.FONT_SMALL)
                    .fontColor(this.engineTestOk ? ThemeTokens.SUCCESS : ThemeTokens.RED)
                    .width('100%')
                    .lineHeight(17)
                }
              }

              Text('引擎列表')
                .fontSize(ThemeTokens.FONT_BODY)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
                .width('100%')
                .margin({ top: 4 })

              ApiCard() {
                this.engineRow({
                  title: '必应翻译',
                  desc: '免 Key 在线翻译，开箱即用；网络异常会给出可读错误。',
                  icon: $r('app.media.ic_tab_translate'),
                  status: this.bingStatus(),
                  active: this.engineType === 0,
                  onTap: () => {
                    this.selectBing();
                  }
                })
                Divider()
                  .color(ThemeTokens.DIVIDER)
                  .strokeWidth(0.5)
                this.engineRow({
                  title: `OpenAI 兼容 · ${this.providerName(this.provider)}`,
                  desc: `Base URL：${this.baseUrl.length > 0 ? this.baseUrl : '未配置'}\n模型：${this.model.length > 0 ? this.model : '未配置'}`,
                  icon: $r('app.media.ic_api'),
                  status: this.openAiStatus(),
                  active: this.engineType === 1,
                  onTap: () => {
                    this.openConfigDialog();
                  }
                })
                Divider()
                  .color(ThemeTokens.DIVIDER)
                  .strokeWidth(0.5)
                this.engineRow({
                  title: '本地 llama.cpp',
                  desc: this.localModelReady ? `已就绪：${this.localModelLabel}` : '未下载模型，请前往模型管理下载 Hy-MT2 GGUF。',
                  icon: $r('app.media.ic_storage'),
                  status: this.localStatus(),
                  active: this.engineType === 2,
                  onTap: () => {
                    this.selectLocal();
                  }
                })
              }

              Row({ space: 10 }) {
                Button('配置 OpenAI 兼容')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                  .backgroundColor(ThemeTokens.PRIMARY)
                  .borderRadius(ThemeTokens.RADIUS_PILL)
                  .height(36)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.openConfigDialog();
                  })
                Button('模型管理')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_SECONDARY)
                  .backgroundColor(ThemeTokens.SURFACE_VARIANT)
                  .borderRadius(ThemeTokens.RADIUS_PILL)
                  .height(36)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.navStack.pushPathByName(Routes.MODEL_MANAGER, '');
                  })
              }
              .width('100%')

              ApiCard() {
                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Image($r('app.media.ic_key'))
                      .width(14)
                      .height(14)
                      .fillColor(ThemeTokens.PRIMARY)
                    Text('密钥安全')
                      .fontSize(ThemeTokens.FONT_CAPTION)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(ThemeTokens.TEXT_PRIMARY)
                  }
                  .alignItems(VerticalAlign.Center)
                  Text('API Key 优先写入 HarmonyOS Asset Store（设备首次解锁可用），Asset 不可用时降级 preferences 并提示低安全模式；界面不回显已保存的 Key。')
                    .fontSize(ThemeTokens.FONT_SMALL)
                    .fontColor(ThemeTokens.TEXT_HINT)
                    .lineHeight(17)
                  Text('隐私：翻译请求仅发送当前文本到所选引擎；应用不上传图片、不收集账号数据。')
                    .fontSize(ThemeTokens.FONT_SMALL)
                    .fontColor(ThemeTokens.TEXT_HINT)
                    .lineHeight(17)
                }
                .alignItems(HorizontalAlign.Start)
              }

              Text('提示：切换默认引擎也会同步到文本/对话翻译页；阅读器批量翻译可在阅读器内单独选择引擎。')
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

        if (this.showConfig) {
          this.configDialog()
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('API 配置', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
    .onShown(() => {
      this.load();
    })
  }
}