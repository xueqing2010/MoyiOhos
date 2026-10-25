/**
 * 文本翻译 / 对话翻译页面（stage 2 / S108）。
 *
 * 顶部「翻译 / 对话」分段：
 *  翻译 — 源/目标语言、引擎（必应 / 6 个 AI 预设 / 本地）、输入、流式译文、
 *         复制 / 分享 / 清空、历史入口、引擎配置入口
 *  对话 — 消息气泡、流式回复、上下文轮次（5-20）、清空 / 会话列表、引擎选择
 * 错误按 网络 / 鉴权 / 限流 / 超时 / 配置 分类给出主因与建议，不崩溃。
 * 宽屏（平板 / PC）翻译页左右分栏，对话页限宽居中。
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Log, ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';
import {
  EnginePreset,
  EnginePresets,
  EngineType,
  LangCatalog,
  LangOption,
  ThinkingMode,
  describeThinking
} from 'coretranslate';
import { ChatSession, ChatMessageRecord } from 'coremodel';
import { AppEnv } from '../common/AppEnv';
import { Routes } from '../common/Routes';
import {
  ChatTranslateService,
  UiChatMessage,
  makeUiMessage
} from '../service/ChatTranslateService';
import { PromptTemplates } from '../service/PromptTemplates';
import { TextTranslateViewModel, TranslateSettings } from '../viewmodel/TextTranslateViewModel';
import { EngineConfigDialog } from '../components/EngineConfigDialog';
import { EmptyState } from '../components/EmptyState';
import { Artwork } from '../components/Artwork';

const TAG = 'TextTranslateView';

/** 对话快捷模板（一键填入提示词，对齐上游 ChatTemplates 的常用场景）。 */
class ChatQuickTemplate {
  readonly label: string;
  readonly prefix: string;

  constructor(label: string, prefix: string) {
    this.label = label;
    this.prefix = prefix;
  }
}

/** 引擎档位（UI 用）：0 必应 / 1 AI 预设 / 2 本地模型。 */
const ENGINE_KIND_BING: number = 0;
const ENGINE_KIND_AI: number = 1;
const ENGINE_KIND_LOCAL: number = 2;

@Component
export struct TextTranslateView {
  // —— 模式 ——
  @State mode: number = 0; // 0 翻译 / 1 对话
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;

  // —— 设置 ——
  @State provider: string = 'bing';
  @State sourceLang: string = 'auto';
  @State targetLang: string = 'zh';
  @State contextRounds: number = PromptTemplates.CONTEXT_DEFAULT;
  @State thinking: number = ThinkingMode.AUTO as number;
  @State temperature: number = 0.3;
  @State hasKey: boolean = false;
  @State lowSecurity: boolean = false;

  // —— 翻译 ——
  @State inputText: string = '';
  @State output: string = '';
  @State translating: boolean = false;
  @State message: string = '';
  @State messageOk: boolean = false;
  @State errTitle: string = '';
  @State errMsg: string = '';
  @State errAdvice: string = '';

  // —— 对话 ——
  @State messages: Array<UiChatMessage> = [];
  @State chatInput: string = '';
  @State streaming: boolean = false;
  @State streamText: string = '';
  @State sessionId: number = 0;
  @State sessions: Array<ChatSession> = [];
  @State showSessions: boolean = false;

  // —— 弹窗 ——
  @State showConfig: boolean = false;

  private stopBreakpoint: (() => void) | undefined = undefined;
  private navStack: NavPathStack = AppEnv.getInstance().navStack;
  private chatScroller: Scroller = new Scroller();
  private chatHistory: Array<ChatMessageRecord> = [];
  private seqCounter: number = 0;
  private srcOptions: Array<LangOption> = LangCatalog.sourceOptions();
  private tgtOptions: Array<LangOption> = LangCatalog.all();
  private presets: Array<EnginePreset> = EnginePresets.all();
  // Select 需要稳定的 options 数组（build 里每次 map 会重建 + 无法推断类型）
  private srcSelectOptions: Array<SelectOption> = [];
  private tgtSelectOptions: Array<SelectOption> = [];
  private presetSelectOptions: Array<SelectOption> = [];
  private optionsReady: boolean = false;
  private quickTemplates: Array<ChatQuickTemplate> = [];
  private lastVisibleReload: number = 0;

  aboutToAppear(): void {
    this.buildSelectOptions();
    this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
      this.sizeClass = c;
    });
    this.init();
  }

  private buildSelectOptions(): void {
    const src: Array<SelectOption> = [];
    for (const item of this.srcOptions) {
      const o: SelectOption = { value: item.label };
      src.push(o);
    }
    this.srcSelectOptions = src;
    const tgt: Array<SelectOption> = [];
    for (const item of this.tgtOptions) {
      const o: SelectOption = { value: item.label };
      tgt.push(o);
    }
    this.tgtSelectOptions = tgt;
    const pre: Array<SelectOption> = [];
    for (const p of this.presets) {
      const o: SelectOption = { value: p.label };
      pre.push(o);
    }
    this.presetSelectOptions = pre;
    this.optionsReady = true;
  }

  aboutToDisappear(): void {
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  /** 目标语言变化后重建快捷模板。 */
  private buildQuickTemplates(): void {
    const to = LangCatalog.displayName(this.targetLang);
    const list: Array<ChatQuickTemplate> = [];
    list.push(new ChatQuickTemplate('翻译成' + to, '翻译成' + to + '：\n'));
    list.push(new ChatQuickTemplate('润色', '把下面这段内容润色得更自然（保持原意）：\n'));
    list.push(new ChatQuickTemplate('解释', '解释下面内容的含义与用词：\n'));
    list.push(new ChatQuickTemplate('总结', '用' + to + '总结下面内容：\n'));
    this.quickTemplates = list;
  }

  /** Tab 切回本页时重读设置（设置页改了语言/思考/Key 后即时生效）。 */
  private onVisibleChange(isVisible: boolean): void {
    if (!isVisible) {
      return;
    }
    const now = Date.now();
    if (now - this.lastVisibleReload < 1500) {
      return;
    }
    this.lastVisibleReload = now;
    this.reloadSettings();
  }

  /** 只刷新设置与配置，不动输入/译文/对话内容。 */
  private async reloadSettings(): Promise<void> {
    try {
      const s: TranslateSettings = await TextTranslateViewModel.loadSettings();
      this.provider = s.provider;
      this.sourceLang = s.sourceLang;
      this.targetLang = s.targetLang;
      this.contextRounds = s.contextRounds;
      this.thinking = s.thinking as number;
      this.temperature = s.temperature;
      this.hasKey = await TextTranslateViewModel.hasApiKey();
      this.lowSecurity = TextTranslateViewModel.isLowSecurity();
      this.buildQuickTemplates();
      await TextTranslateViewModel.applyOpenAiConfig();
    } catch (e) {
      Log.warn(TAG, 'reload settings failed: ' + e);
    }
  }

  private async init(): Promise<void> {
    try {
      await AppEnv.ready();
      const s: TranslateSettings = await TextTranslateViewModel.loadSettings();
      this.provider = s.provider;
      this.sourceLang = s.sourceLang;
      this.targetLang = s.targetLang;
      this.contextRounds = s.contextRounds;
      this.thinking = s.thinking as number;
      this.temperature = s.temperature;
      this.hasKey = await TextTranslateViewModel.hasApiKey();
      this.lowSecurity = TextTranslateViewModel.isLowSecurity();
      this.buildQuickTemplates();
      await TextTranslateViewModel.applyOpenAiConfig();
    } catch (e) {
      this.setError(e);
    }
  }

  private isWide(): boolean {
    return this.sizeClass !== WindowSizeClass.SM;
  }

  private engineKind(): number {
    if (this.provider === 'bing') {
      return ENGINE_KIND_BING;
    }
    if (this.provider === 'local') {
      return ENGINE_KIND_LOCAL;
    }
    return ENGINE_KIND_AI;
  }

  private engineType(): EngineType {
    const kind = this.engineKind();
    if (kind === ENGINE_KIND_BING) {
      return EngineType.BING;
    }
    if (kind === ENGINE_KIND_LOCAL) {
      return EngineType.LOCAL_LLAMA;
    }
    return EngineType.OPENAI_COMPAT;
  }

  private currentSettings(): TranslateSettings {
    const s = new TranslateSettings();
    s.sourceLang = this.sourceLang;
    s.targetLang = this.targetLang;
    s.engine = this.engineType();
    s.provider = this.provider;
    s.contextRounds = this.contextRounds;
    s.thinking = this.thinking as ThinkingMode;
    s.temperature = this.temperature;
    return s;
  }

  private engineLabel(): string {
    return TextTranslateViewModel.labelOf(this.currentSettings());
  }

  /** 统一错误呈现：分类标题 + 原因 + 建议。 */
  private setError(e: Object): void {
    this.errTitle = TextTranslateViewModel.errorTitle(e);
    this.errMsg = TextTranslateViewModel.readableError(e);
    this.errAdvice = TextTranslateViewModel.errorAdvice(e);
    this.message = '';
    Log.warn(TAG, 'error: ' + this.errTitle + ' / ' + this.errMsg);
  }

  private clearError(): void {
    this.errTitle = '';
    this.errMsg = '';
    this.errAdvice = '';
  }

  private toast(text: string, ok: boolean): void {
    this.message = text;
    this.messageOk = ok;
    this.errTitle = '';
    this.errMsg = '';
    this.errAdvice = '';
  }

  // ------------------------------------------------------------- actions
  private async pickEngineKind(kind: number): Promise<void> {
    this.clearError();
    if (kind === ENGINE_KIND_BING) {
      this.provider = 'bing';
    } else if (kind === ENGINE_KIND_LOCAL) {
      this.provider = 'local';
    } else if (this.engineKind() !== ENGINE_KIND_AI) {
      this.provider = EnginePresets.defaultPreset().id;
    }
    await TextTranslateViewModel.saveEngineChoice(this.provider);
    if (this.engineKind() === ENGINE_KIND_AI) {
      this.hasKey = await TextTranslateViewModel.hasApiKey();
      if (!this.hasKey) {
        this.toast('尚未配置 API Key，点击右上角「配置」填写', false);
      }
    }
  }

  private async pickPreset(index: number): Promise<void> {
    const list = EnginePresets.all();
    if (index < 0 || index >= list.length) {
      return;
    }
    this.provider = list[index].id;
    await TextTranslateViewModel.saveEngineChoice(this.provider);
    this.hasKey = await TextTranslateViewModel.hasApiKey();
    if (list[index].custom) {
      this.showConfig = true;
    } else if (!this.hasKey) {
      this.toast('已选择 ' + list[index].label + '，请在「配置」中填写 API Key', false);
    } else {
      this.toast('已切换到 ' + list[index].label, true);
    }
  }

  private async pickSourceLang(index: number): Promise<void> {
    if (index < 0 || index >= this.srcOptions.length) {
      return;
    }
    const code = this.srcOptions[index].code;
    this.sourceLang = code;
    await TextTranslateViewModel.saveSourceLang(code);
  }

  private async pickTargetLang(index: number): Promise<void> {
    if (index < 0 || index >= this.tgtOptions.length) {
      return;
    }
    const code = this.tgtOptions[index].code;
    this.targetLang = code;
    this.buildQuickTemplates();
    await TextTranslateViewModel.saveTargetLang(code);
  }

  private async swapLangs(): Promise<void> {
    const oldSource = this.sourceLang;
    const oldTarget = this.targetLang;
    this.sourceLang = oldTarget;
    let nextTarget = oldSource === 'auto' ? 'zh' : oldSource;
    if (nextTarget === this.sourceLang) {
      nextTarget = this.sourceLang === 'zh' ? 'en' : 'zh';
      this.sourceLang = this.sourceLang === 'zh' ? 'en' : 'zh';
    }
    this.targetLang = nextTarget;
    await TextTranslateViewModel.saveSourceLang(this.sourceLang);
    await TextTranslateViewModel.saveTargetLang(this.targetLang);
  }

  private async doTranslate(): Promise<void> {
    if (this.translating) {
      return;
    }
    const text = this.inputText.trim();
    if (text.length === 0) {
      this.toast('请输入要翻译的文本', false);
      return;
    }
    if (this.engineKind() === ENGINE_KIND_AI && !this.hasKey) {
      this.toast('请先点击右上角「配置」填写 API Key', false);
      return;
    }
    this.translating = true;
    this.output = '';
    this.clearError();
    this.message = '';
    try {
      const settings = this.currentSettings();
      const result = await TextTranslateViewModel.translateWith(text, this.sourceLang,
        this.targetLang, settings, (delta: string) => {
          this.output += delta;
        });
      if (this.output.length === 0) {
        this.output = result;
      }
      await TextTranslateViewModel.saveHistory(text, this.output.trim(),
        this.sourceLang, this.targetLang, this.engineType() as number);
    } catch (e) {
      this.setError(e);
    }
    this.translating = false;
  }

  private async copyText(text: string): Promise<void> {
    if (text.length === 0) {
      this.toast('没有可复制的内容', false);
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.toast('已复制到剪贴板', true);
    } catch (e) {
      this.toast('复制失败：' + TextTranslateViewModel.readableError(e), false);
    }
  }

  private async shareText(text: string): Promise<void> {
    if (text.length === 0) {
      this.toast('没有可分享的内容', false);
      return;
    }
    try {
      const shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.TEXT,
        content: text,
        title: '译文'
      });
      const controller = new systemShare.ShareController(shareData);
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await controller.show(ctx, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
    } catch (e) {
      Log.warn(TAG, 'share failed: ' + e);
      await this.copyText(text);
    }
  }

  private clearAllTranslate(): void {
    this.inputText = '';
    this.output = '';
    this.clearError();
    this.message = '';
  }

  private openHistory(): void {
    this.navStack.pushPathByName(Routes.TEXT_HISTORY, '');
  }

  /** 配置弹窗保存后：重读 Key / 低安全标记 / 全部设置。 */
  private async refreshAfterConfig(): Promise<void> {
    this.showConfig = false;
    try {
      this.hasKey = await TextTranslateViewModel.hasApiKey();
      this.lowSecurity = TextTranslateViewModel.isLowSecurity();
      await this.init();
      this.toast('引擎配置已保存', true);
    } catch (e) {
      this.setError(e);
    }
  }

  // --------------------------------------------------------------- chat
  private async newChat(): Promise<void> {
    this.sessionId = 0;
    this.messages = [];
    this.chatHistory = [];
    this.streaming = false;
    this.streamText = '';
    this.showSessions = false;
  }

  private async loadSession(session: ChatSession): Promise<void> {
    this.showSessions = false;
    this.sessionId = session.id;
    this.messages = await ChatTranslateService.loadMessages(session.id);
    this.chatHistory = await ChatTranslateService.loadRawMessages(session.id);
    // ForEach key 用 seq：载入的历史用记录 id，新的气泡从这里继续自增，避免键冲突
    let maxSeq = 0;
    for (const m of this.messages) {
      if (m.seq > maxSeq) {
        maxSeq = m.seq;
      }
    }
    if (this.seqCounter < maxSeq) {
      this.seqCounter = maxSeq;
    }
    this.streamText = '';
    this.scrollChatToBottom();
  }

  private async openSessions(): Promise<void> {
    this.sessions = await ChatTranslateService.loadSessions();
    this.showSessions = true;
  }

  private async deleteSession(session: ChatSession): Promise<void> {
    try {
      await ChatTranslateService.deleteSession(session.id);
      if (this.sessionId === session.id) {
        await this.newChat();
      }
      this.sessions = await ChatTranslateService.loadSessions();
    } catch (e) {
      this.toast('删除会话失败：' + TextTranslateViewModel.readableError(e), false);
    }
  }

  private async changeRounds(delta: number): Promise<void> {
    const next = PromptTemplates.clampRounds(this.contextRounds + delta);
    if (next === this.contextRounds) {
      return;
    }
    this.contextRounds = next;
    await TextTranslateViewModel.saveContextRounds(next);
  }

  private scrollChatToBottom(): void {
    const count = this.messages.length + 1;
    setTimeout(() => {
      try {
        this.chatScroller.scrollToIndex(count - 1, true);
      } catch (e) {
      }
    }, 60);
  }

  private async doSend(): Promise<void> {
    if (this.streaming) {
      return;
    }
    const text = this.chatInput.trim();
    if (text.length === 0) {
      this.toast('请输入内容', false);
      return;
    }
    if (this.engineKind() !== ENGINE_KIND_AI) {
      this.toast('对话模式需要 AI 预设引擎，请切换引擎（必应 / 本地不支持多轮对话）', false);
      return;
    }
    if (!this.hasKey) {
      this.toast('请先在「配置」中填写 API Key', false);
      return;
    }
    const userMsg = makeUiMessage('user', text);
    userMsg.seq = ++this.seqCounter;
    this.messages.push(userMsg);
    this.chatInput = '';
    this.streaming = true;
    this.streamText = '';
    this.clearError();
    this.scrollChatToBottom();
    try {
      const settings = this.currentSettings();
      const result = await ChatTranslateService.send(this.sessionId, this.chatHistory,
        text, settings, (delta: string) => {
          this.streamText += delta;
        });
      this.sessionId = result.sessionId;
      const aiMsg = makeUiMessage('assistant', result.answer.trim());
      aiMsg.seq = ++this.seqCounter;
      this.messages.push(aiMsg);
      this.chatHistory = await ChatTranslateService.loadRawMessages(result.sessionId);
      this.streamText = '';
      this.scrollChatToBottom();
    } catch (e) {
      this.errTitle = TextTranslateViewModel.errorTitle(e);
      this.errMsg = TextTranslateViewModel.readableError(e);
      this.errAdvice = TextTranslateViewModel.errorAdvice(e);
    }
    this.streaming = false;
  }

  // ------------------------------------------------------------ builders
  @Builder
  segment(index: number, label: string) {
    Text(label)
      .fontSize(ThemeTokens.FONT_CAPTION)
      .fontWeight(this.mode === index ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.mode === index ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      .backgroundColor(this.mode === index ? ThemeTokens.PRIMARY : Color.Transparent)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .height(32)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .onClick(() => {
        this.mode = index;
        if (index === 1 && this.sessions.length === 0) {
          ChatTranslateService.loadSessions().then((list: Array<ChatSession>) => {
            this.sessions = list;
          });
        }
      });
  }

  @Builder
  headerActions() {
    Row({ space: 8 }) {
      Stack() {
        Image(Artwork.TAB_HISTORY)
          .width(20)
          .height(20)
          .fillColor(ThemeTokens.TEXT_SECONDARY);
      }
      .width(34)
      .height(34)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .onClick(() => {
        this.openHistory();
      });
      Stack() {
        Image(Artwork.ICON_SETTINGS)
          .width(20)
          .height(20)
          .fillColor(ThemeTokens.TEXT_SECONDARY);
      }
      .width(34)
      .height(34)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .onClick(() => {
        this.showConfig = true;
      });
    }
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  header() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.mode === 0 ? '文本翻译' : '对话翻译')
            .fontSize(ThemeTokens.FONT_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
          Text(this.engineLabel() + ' · '
            + LangCatalog.displayName(this.sourceLang) + ' → '
            + LangCatalog.displayName(this.targetLang))
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        this.headerActions();
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Row() {
        this.segment(0, '翻译');
        this.segment(1, '对话');
      }
      .width('100%')
      .padding(3)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT);
    }
    .width('100%')
  }

  @Builder
  engineChip(kind: number, label: string) {
    Text(label)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(this.engineKind() === kind ? ThemeTokens.TEXT_ON_PRIMARY
        : ThemeTokens.TEXT_SECONDARY)
      .backgroundColor(this.engineKind() === kind ? ThemeTokens.PRIMARY
        : ThemeTokens.SURFACE_VARIANT)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .height(30)
      .padding({ left: 12, right: 12 })
      .onClick(() => {
        this.pickEngineKind(kind);
      });
  }

  @Builder
  langSelectors() {
    Row({ space: 8 }) {
      Select(this.srcSelectOptions)
        .selected(LangCatalog.indexOf(this.srcOptions, this.sourceLang))
        .value(LangCatalog.displayName(this.sourceLang))
        .font({ size: ThemeTokens.FONT_SMALL })
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .height(32)
        .layoutWeight(1)
        .onSelect((index: number) => {
          this.pickSourceLang(index);
        });
      Stack() {
        Image(Artwork.ICON_TRANSLATE_SWAP)
          .width(16)
          .height(16)
          .fillColor(ThemeTokens.PRIMARY);
      }
      .width(32)
      .height(32)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .onClick(() => {
        this.swapLangs();
      });
      Select(this.tgtSelectOptions)
        .selected(LangCatalog.indexOf(this.tgtOptions, this.targetLang))
        .value(LangCatalog.displayName(this.targetLang))
        .font({ size: ThemeTokens.FONT_SMALL })
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .height(32)
        .layoutWeight(1)
        .onSelect((index: number) => {
          this.pickTargetLang(index);
        });
    }
    .width('100%');
  }

  @Builder
  engineSelector() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        this.engineChip(ENGINE_KIND_BING, '必应（免 Key）');
        this.engineChip(ENGINE_KIND_AI, 'AI 预设');
        this.engineChip(ENGINE_KIND_LOCAL, '本地模型');
      }
      .width('100%');
      if (this.engineKind() === ENGINE_KIND_AI) {
        Row({ space: 8 }) {
          Select(this.presetSelectOptions)
            .selected(EnginePresets.indexOf(this.provider))
            .value(EnginePresets.byId(this.provider).label)
            .font({ size: ThemeTokens.FONT_SMALL })
            .fontColor(ThemeTokens.TEXT_PRIMARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(32)
            .layoutWeight(1)
            .onSelect((index: number) => {
              this.pickPreset(index);
            });
          Text(this.hasKey ? 'Key 已配置' : 'Key 未配置')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(this.hasKey ? ThemeTokens.SUCCESS : ThemeTokens.WARN);
        }
        .width('100%');
        Text(describeThinking(this.thinking as ThinkingMode,
          EnginePresets.byId(this.provider).defaultModel))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_TERTIARY)
          .width('100%');
      } else if (this.engineKind() === ENGINE_KIND_LOCAL) {
        Text('本地 Hy-MT2 需要先在「我的 → 模型管理」下载模型；无网络时可用')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_TERTIARY)
          .width('100%');
      } else {
        Text('必应免 Key、无需配置；离线或网络受限时会给出可读错误')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_TERTIARY)
          .width('100%');
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  inputCard() {
    Column({ space: 8 }) {
      Row() {
        Text('原文')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .layoutWeight(1);
        if (this.inputText.length > 0) {
          Text('清空')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .onClick(() => {
              this.clearAllTranslate();
            });
        }
      }
      .width('100%');
      TextArea({ text: this.inputText, placeholder: '输入或粘贴要翻译的文本…' })
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .borderRadius(ThemeTokens.RADIUS_SMALL)
        .height(this.isWide() ? 180 : 120)
        .width('100%')
        .onChange((v: string) => {
          this.inputText = v;
        });
      Button(this.translating ? '翻译中…' : '翻译')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
        .backgroundColor(this.translating ? ThemeTokens.SURFACE_HIGH : ThemeTokens.PRIMARY)
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .height(40)
        .width('100%')
        .enabled(!this.translating)
        .onClick(() => {
          this.doTranslate();
        });
    }
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  outputBody() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text('译文')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .layoutWeight(1);
        if (this.translating) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(ThemeTokens.PRIMARY);
        }
        if (this.output.length > 0) {
          Stack() {
            Image(Artwork.ICON_SHARE)
              .width(16)
              .height(16)
              .fillColor(ThemeTokens.TEXT_SECONDARY);
          }
          .width(28)
          .height(28)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_HIGH)
          .onClick(() => {
            this.shareText(this.output.trim());
          });
          Stack() {
            Image(Artwork.ICON_COPY)
              .width(16)
              .height(16)
              .fillColor(ThemeTokens.PRIMARY);
          }
          .width(28)
          .height(28)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_HIGH)
          .onClick(() => {
            this.copyText(this.output.trim());
          });
        }
      }
      .width('100%');
      Scroll() {
        Text(this.output.length > 0 ? this.output : '译文将在此逐字显示')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(this.output.length > 0 ? ThemeTokens.TEXT_PRIMARY : ThemeTokens.TEXT_HINT)
          .width('100%');
      }
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .width('100%')
      .layoutWeight(1);
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  outputCard() {
    Column() {
      this.outputBody();
    }
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  errorBanner() {
    if (this.errTitle.length > 0) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(this.errTitle)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeTokens.RED);
          Blank();
          Text('关闭')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
            .onClick(() => {
              this.clearError();
            });
        }
        .width('100%');
        Text(this.errMsg)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .width('100%');
        Text(this.errAdvice)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%');
      }
      .padding(12)
      .width('100%')
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .backgroundColor('#33F26D7E')
      .alignItems(HorizontalAlign.Start);
    }
  }

  @Builder
  infoFooter() {
    if (this.message.length > 0) {
      Text(this.message)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(this.messageOk ? ThemeTokens.SUCCESS : ThemeTokens.WARN)
        .width('100%');
    }
    // 低安全模式提示只在「AI 预设引擎 + 确实降级」时显示，避免常驻噪音
    if (this.lowSecurity && this.engineKind() === ENGINE_KIND_AI) {
      Text('低安全模式：系统资产存储不可用，API Key 经 preferences 保存')
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.WARN)
        .width('100%');
    }
  }

  @Builder
  translatePane() {
    Column({ space: 10 }) {
      this.langSelectors();
      this.engineSelector();
      if (this.isWide()) {
        Row({ space: 12 }) {
          Column() {
            this.inputCard();
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);
          Column() {
            this.outputCard();
          }
          .layoutWeight(1)
          .height(320)
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%')
        .alignItems(VerticalAlign.Top);
        this.errorBanner();
        this.infoFooter();
      } else {
        this.inputCard();
        this.outputCard();
        this.errorBanner();
        this.infoFooter();
      }
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  messageBubble(msg: UiChatMessage) {
    Row() {
      if (msg.role === 'user') {
        Blank();
        Text(msg.content)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(ThemeTokens.PRIMARY_SOFT)
          .borderRadius(14)
          .constraintSize({ maxWidth: '82%' })
          .copyOption(CopyOptions.LocalDevice);
      } else {
        Text(msg.content)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(ThemeTokens.CARD_BG)
          .borderRadius(14)
          .constraintSize({ maxWidth: '82%' })
          .copyOption(CopyOptions.LocalDevice);
        Blank();
      }
    }
    .width('100%');
  }

  @Builder
  streamingBubble() {
    Row() {
      Column({ space: 4 }) {
        Text(this.streamText.length > 0 ? this.streamText : '正在思考…')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(this.streamText.length > 0 ? ThemeTokens.TEXT_PRIMARY
            : ThemeTokens.TEXT_HINT)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(ThemeTokens.CARD_BG)
          .borderRadius(14)
          .constraintSize({ maxWidth: '82%' });
      }
      .alignItems(HorizontalAlign.Start);
      Blank();
    }
    .width('100%');
  }

  /** 对话空态文案（引擎/Key/历史会话提示拼进 hint）。 */
  private chatHint(): string {
    let hint = '多轮上下文翻译 / 润色 / 解释；上下文 ' + this.contextRounds + ' 轮（5-20 可调）';
    if (this.engineKind() !== ENGINE_KIND_AI) {
      hint += '\n当前引擎不支持对话，请切换到「AI 预设」';
    } else if (!this.hasKey) {
      hint += '\n尚未配置 API Key，点击右上角「配置」填写';
    }
    if (this.sessions.length > 0) {
      hint += '\n历史会话 ' + this.sessions.length + ' 个，点上方「会话」继续';
    }
    return hint;
  }

  @Builder
  chatEmpty() {
    Column() {
      EmptyState({
        icon: Artwork.EMPTY_SEARCH,
        iconSize: 96,
        title: '对话翻译',
        hint: this.chatHint()
      })
    }
    .width('100%')
    .layoutWeight(1);
  }

  @Builder
  chatPane() {
    Column({ space: 8 }) {
      this.engineSelector();
      Row({ space: 8 }) {
        Text('上下文')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT);
        Text('−')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .onClick(() => {
            this.changeRounds(-1);
          });
        Text(this.contextRounds + ' 轮')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_PRIMARY);
        Text('+')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .onClick(() => {
            this.changeRounds(1);
          });
        Blank();
        Text('会话')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.PRIMARY)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .onClick(() => {
            this.openSessions();
          });
        Text('清空')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .onClick(() => {
            this.newChat();
          });
      }
      .width('100%');

      if (this.messages.length === 0 && !this.streaming) {
        this.chatEmpty();
      } else {
        List({ space: 10, scroller: this.chatScroller }) {
          ForEach(this.messages, (msg: UiChatMessage) => {
            ListItem() {
              this.messageBubble(msg);
            }
          }, (msg: UiChatMessage) => msg.seq.toString());
          if (this.streaming) {
            ListItem() {
              this.streamingBubble();
            }
          }
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .layoutWeight(1);
      }

      this.quickTemplatesRow();

      Row({ space: 8 }) {
        TextArea({ text: this.chatInput, placeholder: '输入内容，回车换行…' })
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
          .height(64)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.chatInput = v;
          });
        Button(this.streaming ? '…' : '发送')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          .backgroundColor(this.streaming ? ThemeTokens.SURFACE_HIGH
            : ThemeTokens.PRIMARY)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .height(44)
          .width(72)
          .enabled(!this.streaming)
          .onClick(() => {
            this.doSend();
          });
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom);

      if (this.errTitle.length > 0) {
        this.errorBanner();
      }
      this.infoFooter();
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start);
  }

  /** 一键填入对话提示词。 */
  private applyTemplate(tpl: ChatQuickTemplate): void {
    const current = this.chatInput.trim();
    this.chatInput = current.length === 0 ? tpl.prefix : (tpl.prefix + current);
  }

  @Builder
  quickTemplatesRow() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.quickTemplates, (tpl: ChatQuickTemplate) => {
          Text(tpl.label)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(28)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.applyTemplate(tpl);
            });
        }, (tpl: ChatQuickTemplate) => tpl.label);
      }
      .padding({ right: 8 });
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(30);
  }

  @Builder
  sessionsOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 8 }) {
        Row() {
          Text('会话列表')
            .fontSize(ThemeTokens.FONT_SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
            .layoutWeight(1);
          Text('新建')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.PRIMARY)
            .onClick(() => {
              this.newChat();
            });
          Text('关闭')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .margin({ left: 12 })
            .onClick(() => {
              this.showSessions = false;
            });
        }
        .width('100%');
        if (this.sessions.length === 0) {
          Text('还没有历史会话')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_HINT)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 24 });
        } else {
          List({ space: 6 }) {
            ForEach(this.sessions, (s: ChatSession) => {
              ListItem() {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(s.title)
                      .fontSize(ThemeTokens.FONT_CAPTION)
                      .fontColor(this.sessionId === s.id
                        ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_PRIMARY)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    Text(this.formatTime(s.updatedAt))
                      .fontSize(ThemeTokens.FONT_SMALL)
                      .fontColor(ThemeTokens.TEXT_HINT);
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .padding({ top: 6, bottom: 6 })
                  .onClick(() => {
                    this.loadSession(s);
                  });
                  Stack() {
                    Image(Artwork.ICON_DELETE)
                      .width(16)
                      .height(16)
                      .fillColor(ThemeTokens.RED);
                  }
                  .width(34)
                  .height(34)
                  .borderRadius(ThemeTokens.RADIUS_PILL)
                  .backgroundColor(ThemeTokens.SURFACE_HIGH)
                  .onClick(() => {
                    this.deleteSession(s);
                  });
                }
                .width('100%')
                .padding({ left: 10, right: 6, top: 4, bottom: 4 })
                .borderRadius(ThemeTokens.RADIUS_SMALL)
                .backgroundColor(ThemeTokens.SURFACE_VARIANT);
              }
            }, (s: ChatSession) => s.id.toString());
          }
          .width('100%')
          .layoutWeight(1);
        }
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('90%')
      .height('70%')
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000');
  }

  private formatTime(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const d = new Date(ms);
    const pad = (n: number): string => (n < 10 ? ('0' + n) : ('' + n));
    return pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' '
      + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  build() {
    Stack() {
      Column({ space: 12 }) {
        this.header();
        if (this.mode === 0) {
          this.translatePane();
        } else {
          this.chatPane();
        }
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start);

      if (this.showSessions) {
        this.sessionsOverlay();
      }
      if (this.showConfig) {
        EngineConfigDialog({
          onSaved: () => {
            this.refreshAfterConfig();
          },
          onClose: () => {
            this.showConfig = false;
          }
        });
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.SURFACE)
    .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
      this.onVisibleChange(isVisible && currentRatio > 0.2);
    });
  }
}