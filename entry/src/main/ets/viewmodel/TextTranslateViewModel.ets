/**
 * 文本 / 对话翻译 ViewModel（stage 2 / S107 + S108）。
 *
 * 职责：
 *  · 引擎与预设（必应 / 6 个 OpenAI 兼容预设 / 本地模型）的选择与持久化
 *  · 语言、上下文轮次、思考模式、温度、提示词覆盖的持久化
 *  · 提示词组装（PromptTemplates）+ 流式调用 + 错误分类
 *  · 文本翻译历史的读写（text_translation 表）
 *  · 引擎配置（preset / baseUrl / model / API Key）与「测试连接」
 *
 * 偏好契约（与 settings-dev 对齐，文件 starflow_translate）：
 *  target_lang / text_engine / openai_base_url / openai_model / openai_provider
 *  translate_context_turns(5-20) / translate_thinking_mode(0关1自动2开) / translate_temperature
 *  prompt_manga / prompt_novel / prompt_text / prompt_chat
 * 页内自有键：text_source_lang / text_target_lang（仅本页显式切换时写）
 * API Key：AssetKeyStore(alias=openai_api_key)，掩码不回显。
 */
import { preferences } from '@kit.ArkData';
import {
  CUSTOM_PRESET_ID,
  ChatMessage,
  EnginePreset,
  EnginePresets,
  EngineType,
  ErrorKind,
  LangCatalog,
  OpenAiConfig,
  ThinkingMode,
  TranslateError,
  TranslateRequest,
  clampTemperature,
  makeCompletionOptions,
  normalizeThinkingMode
} from 'coretranslate';
import { TextTranslationDao, TextTranslationRecord, makeTextTranslationRecord } from 'coremodel';
import { Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { PageTranslateService } from '../service/PageTranslateService';
import { PromptKind, PromptTemplates } from '../service/PromptTemplates';

const TAG = 'TextTranslateVM';
const PREF_FILE = 'starflow_translate';
// —— 与 settings-dev 约定的键 ——
const KEY_TARGET_LANG = 'target_lang';
const KEY_OPENAI_BASE = 'openai_base_url';
const KEY_OPENAI_MODEL = 'openai_model';
const KEY_OPENAI_PROVIDER = 'openai_provider';
const KEY_CONTEXT_TURNS = 'translate_context_turns';
const KEY_THINKING = 'translate_thinking_mode';
const KEY_TEMPERATURE = 'translate_temperature';
// —— 本页自有键 ——
const KEY_TEXT_TARGET_LANG = 'text_target_lang';
const KEY_TEXT_SOURCE_LANG = 'text_source_lang';
// —— 密钥 ——
const KEY_ALIAS = 'openai_api_key';

/** 当前翻译页的设置快照（一次性读出，避免多处 async 竞态）。 */
export class TranslateSettings {
  sourceLang: string = 'auto';
  targetLang: string = 'zh';
  engine: EngineType = EngineType.BING;
  /** 预设 id；'bing' 表示必应引擎。 */
  provider: string = 'deepseek';
  contextRounds: number = PromptTemplates.CONTEXT_DEFAULT;
  thinking: ThinkingMode = ThinkingMode.AUTO;
  temperature: number = 0.3;
}

/** 「测试连接」结果。 */
export class ConnectionTestResult {
  ok: boolean = false;
  message: string = '';
  models: Array<string> = [];
  latencyMs: number = 0;
}

/**
 * 静态工具类：所有方法 async & 无 UI 依赖，便于页面 / 对话框 / 历史页共用。
 */
export class TextTranslateViewModel {
  // ------------------------------------------------------------------ prefs
  private static async prefs(): Promise<preferences.Preferences> {
    const ctx = AppEnv.getInstance().getContext();
    return preferences.getPreferences(ctx, PREF_FILE);
  }

  private static async getString(key: string, def: string): Promise<string> {
    try {
      const pref = await TextTranslateViewModel.prefs();
      const raw = pref.getSync(key, def) as string;
      return raw === undefined || raw === null || raw.length === 0 ? def : raw;
    } catch (e) {
      return def;
    }
  }

  private static async getNumber(key: string, def: number): Promise<number> {
    try {
      const pref = await TextTranslateViewModel.prefs();
      const raw = pref.getSync(key, def) as number;
      return typeof raw === 'number' ? raw : def;
    } catch (e) {
      return def;
    }
  }

  private static async put(key: string, value: string | number): Promise<void> {
    try {
      const pref = await TextTranslateViewModel.prefs();
      pref.putSync(key, value);
      await pref.flush();
    } catch (e) {
      Log.warn(TAG, 'save pref failed: ' + key + ' ' + e);
    }
  }

  // ------------------------------------------------------------- settings
  /** 一次性读出当前页需要的全部设置。 */
  static async loadSettings(): Promise<TranslateSettings> {
    const s = new TranslateSettings();
    const provider = await TextTranslateViewModel.loadProvider();
    s.provider = provider;
    s.engine = await TextTranslateViewModel.resolveEngine(provider);
    s.sourceLang = LangCatalog.normalizeSource(await TextTranslateViewModel.loadSourceLang());
    s.targetLang = LangCatalog.normalizeTarget(await TextTranslateViewModel.loadTargetLang());
    s.contextRounds = PromptTemplates.clampRounds(
      await TextTranslateViewModel.loadContextRounds());
    s.thinking = normalizeThinkingMode(await TextTranslateViewModel.loadThinking());
    s.temperature = clampTemperature(await TextTranslateViewModel.loadTemperature());
    return s;
  }

  /** 引擎：provider='bing' -> 必应；'local' -> 本地；其它（预设 id）-> OpenAI 兼容。 */
  static async resolveEngine(provider: string): Promise<EngineType> {
    if (provider === 'bing') {
      return EngineType.BING;
    }
    if (provider === 'local') {
      return EngineType.LOCAL_LLAMA;
    }
    // loadProvider() 已负责把老数据（只有 text_engine）折算成 provider。
    return EngineType.OPENAI_COMPAT;
  }

  static async loadProvider(): Promise<string> {
    const raw = await TextTranslateViewModel.getString(KEY_OPENAI_PROVIDER, '');
    if (raw.length > 0) {
      return raw;
    }
    // 首次启动：按历史 text_engine 推断
    const legacy = await PageTranslateService.loadEngineType();
    if (legacy === EngineType.OPENAI_COMPAT) {
      return EnginePresets.defaultPreset().id;
    }
    if (legacy === EngineType.LOCAL_LLAMA) {
      return 'local';
    }
    return 'bing';
  }

  /**
   * 选引擎/预设：同时维护 openai_provider 与 text_engine（页面翻译兼容）。
   * 切换到**另一个**内置预设时把 baseUrl / 模型重置为该预设默认值，避免把
   * DeepSeek 的端点/模型名带到 OpenAI 上（自定义预设保留用户输入）。
   */
  static async saveEngineChoice(provider: string): Promise<void> {
    const previous = await TextTranslateViewModel.getString(KEY_OPENAI_PROVIDER, '');
    await TextTranslateViewModel.put(KEY_OPENAI_PROVIDER, provider);
    if (previous !== provider && EnginePresets.has(provider) && provider !== CUSTOM_PRESET_ID) {
      const preset = EnginePresets.byId(provider);
      await TextTranslateViewModel.put(KEY_OPENAI_BASE, preset.baseUrl);
      await TextTranslateViewModel.put(KEY_OPENAI_MODEL, preset.defaultModel);
    }
    const engine = await TextTranslateViewModel.resolveEngine(provider);
    await PageTranslateService.saveEngineType(engine);
    if (engine === EngineType.OPENAI_COMPAT) {
      await TextTranslateViewModel.applyOpenAiConfig();
    }
  }

  /** 旧 API（SpikeEnginePage / 其它模块在用）：读 text_engine。 */
  static async loadEngineType(): Promise<EngineType> {
    return PageTranslateService.loadEngineType();
  }

  static async saveEngineType(type: EngineType): Promise<void> {
    await PageTranslateService.saveEngineType(type);
  }

  /** 目标语言：本页显式选择 > 设置页 target_lang > zh。 */
  static async loadTargetLang(): Promise<string> {
    const own = await TextTranslateViewModel.getString(KEY_TEXT_TARGET_LANG, '');
    if (own.length > 0) {
      return own;
    }
    const global = await TextTranslateViewModel.getString(KEY_TARGET_LANG, 'zh');
    return LangCatalog.normalizeTarget(global);
  }

  static async saveTargetLang(lang: string): Promise<void> {
    await TextTranslateViewModel.put(KEY_TEXT_TARGET_LANG, lang);
  }

  static async loadSourceLang(): Promise<string> {
    return TextTranslateViewModel.getString(KEY_TEXT_SOURCE_LANG, 'auto');
  }

  static async saveSourceLang(lang: string): Promise<void> {
    await TextTranslateViewModel.put(KEY_TEXT_SOURCE_LANG, lang);
  }

  static async loadContextRounds(): Promise<number> {
    return TextTranslateViewModel.getNumber(KEY_CONTEXT_TURNS,
      PromptTemplates.CONTEXT_DEFAULT);
  }

  static async saveContextRounds(turns: number): Promise<void> {
    await TextTranslateViewModel.put(KEY_CONTEXT_TURNS,
      PromptTemplates.clampRounds(turns));
  }

  static async loadThinking(): Promise<number> {
    return TextTranslateViewModel.getNumber(KEY_THINKING, ThinkingMode.AUTO as number);
  }

  static async saveThinking(mode: ThinkingMode): Promise<void> {
    await TextTranslateViewModel.put(KEY_THINKING, mode as number);
  }

  static async loadTemperature(): Promise<number> {
    return TextTranslateViewModel.getNumber(KEY_TEMPERATURE, 0.3);
  }

  static async saveTemperature(value: number): Promise<void> {
    await TextTranslateViewModel.put(KEY_TEMPERATURE, clampTemperature(value));
  }

  /** 用户自定义提示词覆盖；空串返回 undefined（= 用内置模板）。 */
  static async loadPromptOverride(kind: PromptKind): Promise<string | undefined> {
    const key = PromptTemplates.overrideKey(kind);
    const raw = await TextTranslateViewModel.getString(key, '');
    return raw.trim().length === 0 ? undefined : raw;
  }

  // ------------------------------------------------------ engine config
  static async loadPreset(): Promise<EnginePreset> {
    const provider = await TextTranslateViewModel.loadProvider();
    const id = (provider === 'bing' || provider === 'local')
      ? EnginePresets.defaultPreset().id
      : provider;
    return EnginePresets.byId(id);
  }

  static async loadOpenAiBaseUrl(): Promise<string> {
    const saved = await TextTranslateViewModel.getString(KEY_OPENAI_BASE, '');
    if (saved.length > 0) {
      return saved;
    }
    const preset = await TextTranslateViewModel.loadPreset();
    return preset.baseUrl;
  }

  static async loadOpenAiModel(): Promise<string> {
    const saved = await TextTranslateViewModel.getString(KEY_OPENAI_MODEL, '');
    if (saved.length > 0) {
      return saved;
    }
    const preset = await TextTranslateViewModel.loadPreset();
    return preset.defaultModel;
  }

  /** 旧 API：保存 baseUrl + model（保留当前预设 id）。 */
  static async saveOpenAiConfig(baseUrl: string, model: string): Promise<void> {
    await TextTranslateViewModel.saveFullConfig(
      await TextTranslateViewModel.loadProvider(), baseUrl, model);
  }

  /** 完整保存：预设 id + baseUrl + 模型名（不动 Key）。 */
  static async saveFullConfig(provider: string, baseUrl: string, model: string): Promise<void> {
    await TextTranslateViewModel.put(KEY_OPENAI_PROVIDER, provider);
    await TextTranslateViewModel.put(KEY_OPENAI_BASE, baseUrl.trim());
    await TextTranslateViewModel.put(KEY_OPENAI_MODEL, model.trim());
  }

  static async loadApiKey(): Promise<string | undefined> {
    try {
      const v = await AppEnv.getInstance().getKeyStore().load(KEY_ALIAS);
      return v !== undefined && v.length > 0 ? v : undefined;
    } catch (e) {
      Log.warn(TAG, 'load key failed: ' + e);
      return undefined;
    }
  }

  static async saveApiKey(key: string): Promise<void> {
    await AppEnv.getInstance().getKeyStore().save(KEY_ALIAS, key);
  }

  static async clearApiKey(): Promise<void> {
    await AppEnv.getInstance().getKeyStore().remove(KEY_ALIAS);
  }

  static async hasApiKey(): Promise<boolean> {
    const key = await TextTranslateViewModel.loadApiKey();
    return key !== undefined;
  }

  static isLowSecurity(): boolean {
    return AppEnv.getInstance().getKeyStore().isLowSecurityMode();
  }

  /** 把持久化配置推给已注册的 OpenAI 兼容引擎实例。 */
  static async applyOpenAiConfig(): Promise<void> {
    try {
      await AppEnv.ready();
      const translator = AppEnv.getInstance().getOpenAiTranslator();
      if (translator === undefined) {
        return;
      }
      const preset = await TextTranslateViewModel.loadPreset();
      const baseUrl = await TextTranslateViewModel.loadOpenAiBaseUrl();
      const model = await TextTranslateViewModel.loadOpenAiModel();
      const key = await TextTranslateViewModel.loadApiKey();
      translator.applyPreset(preset, key === undefined ? '' : key, model);
      // 用户可能改过 baseUrl（自定义端点），以持久化值为准。
      if (baseUrl.trim().length > 0 && baseUrl.trim() !== preset.baseUrl) {
        translator.setConfig(new OpenAiConfig(baseUrl.trim(),
          key === undefined ? '' : key, model, preset.id));
      }
    } catch (e) {
      Log.warn(TAG, 'apply config failed: ' + e);
    }
  }

  /** 兼容别名（S107 之前叫 applyOpenAiConfig）。 */
  static async applyEngineConfig(): Promise<void> {
    await TextTranslateViewModel.applyOpenAiConfig();
  }

  static async listModels(): Promise<Array<string>> {
    await TextTranslateViewModel.applyOpenAiConfig();
    const translator = AppEnv.getInstance().getOpenAiTranslator();
    if (translator === undefined) {
      throw new Error('OpenAI 兼容引擎未注册');
    }
    return translator.listModels();
  }

  /**
   * 测试连接：先拉模型列表（快、信息量大）；不支持 /models 的中转再退化为
   * 一次短翻译。不会持久化任何改动，失败时给出分类可读错误。
   */
  static async testConnection(baseUrl: string, model: string,
    apiKey: string): Promise<ConnectionTestResult> {
    const result = new ConnectionTestResult();
    const started = Date.now();
    const translator = AppEnv.getInstance().getOpenAiTranslator();
    if (translator === undefined) {
      result.message = 'OpenAI 兼容引擎未注册，无法测试';
      return result;
    }
    const previous = translator.getConfig();
    const preset = await TextTranslateViewModel.loadPreset();
    translator.setConfig(new OpenAiConfig(baseUrl.trim(), apiKey.trim(),
      model.trim(), preset.id));
    let firstError: string = '';
    try {
      const models = await translator.listModels();
      result.models = models;
      result.ok = true;
      result.latencyMs = Date.now() - started;
      result.message = models.length > 0
        ? ('连接成功 · 可用模型 ' + models.length + ' 个（' + result.latencyMs + 'ms）')
        : ('连接成功，但该服务未返回模型列表（' + result.latencyMs + 'ms）');
      return result;
    } catch (e) {
      firstError = TextTranslateViewModel.readableError(e);
      Log.info(TAG, 'listModels failed, falling back to short translation: ' + firstError);
    }
    try {
      if (model.trim().length === 0) {
        result.message = '模型列表不可用，且未填写模型名：' + firstError;
        return result;
      }
      const opts = makeCompletionOptions(0.1, 32, ThinkingMode.OFF);
      const messages = PromptTemplates.simpleMessages('Hello', 'zh');
      const text = await translator.complete(messages, opts);
      result.ok = text.trim().length > 0;
      result.latencyMs = Date.now() - started;
      result.message = result.ok
        ? ('连接成功（模型列表不可用，短翻译通过，' + result.latencyMs + 'ms）')
        : '连接失败：模型返回空内容';
      return result;
    } catch (e) {
      result.ok = false;
      result.latencyMs = Date.now() - started;
      const second = TextTranslateViewModel.readableError(e);
      result.message = TextTranslateViewModel.preferBetterError(firstError, second);
      return result;
    } finally {
      // 还原调用前的配置，避免「测试」污染正式设置。
      translator.setConfig(previous);
    }
  }

  /** 两个错误里挑信息量更大的那个（鉴权/配置类优先）。 */
  private static preferBetterError(first: string, second: string): string {
    if (first.length === 0) {
      return second;
    }
    if (second.length === 0) {
      return first;
    }
    if (second.indexOf('鉴权') >= 0 || second.indexOf('API Key') >= 0) {
      return second;
    }
    return first.length >= second.length ? first : second;
  }

  // ------------------------------------------------------------ translate
  /**
   * 翻译入口（兼容旧签名）。OPENAI_COMPAT 走 PromptTemplates 组装的消息，
   * 必应/本地走各自引擎；有 onDelta 时流式。
   */
  static async translate(text: string, from: string, to: string, engine: EngineType,
    onDelta?: (delta: string) => void): Promise<string> {
    const settings = await TextTranslateViewModel.loadSettings();
    // 显式传入的 engine 优先（SpikeEnginePage / 批量翻译仍按调用方引擎执行）
    settings.engine = engine;
    return TextTranslateViewModel.translateWith(text, from, to, settings, onDelta);
  }

  /** 按给定设置翻译（页面用，避免与持久化竞态）。 */
  static async translateWith(text: string, from: string, to: string,
    settings: TranslateSettings, onDelta?: (delta: string) => void): Promise<string> {
    await AppEnv.ready();
    if (settings.engine === EngineType.OPENAI_COMPAT) {
      return TextTranslateViewModel.translateAi(text, from, to, settings, onDelta);
    }
    const translator = AppEnv.getInstance().engineRegistry.get(settings.engine);
    const req: TranslateRequest = { text: text, from: from, to: to };
    if (onDelta !== undefined && translator.translateStream !== undefined) {
      return translator.translateStream(req, onDelta);
    }
    const result = await translator.translate(req);
    if (onDelta !== undefined) {
      onDelta(result);
    }
    return result;
  }

  /** OpenAI 兼容：PromptTemplates + complete（流式）。 */
  private static async translateAi(text: string, from: string, to: string,
    settings: TranslateSettings, onDelta?: (delta: string) => void): Promise<string> {
    await TextTranslateViewModel.applyOpenAiConfig();
    const translator = AppEnv.getInstance().getOpenAiTranslator();
    if (translator === undefined) {
      throw new TranslateError(ErrorKind.ENGINE, 'OpenAI 兼容引擎未注册');
    }
    const model = (await TextTranslateViewModel.loadOpenAiModel()).trim();
    translator.setConfig(new OpenAiConfig(await TextTranslateViewModel.loadOpenAiBaseUrl(),
      (await TextTranslateViewModel.loadApiKey()) ?? '', model, translator.presetId()));
    const override = await TextTranslateViewModel.loadPromptOverride(PromptKind.TEXT);
    const messages: Array<ChatMessage> = PromptTemplates.textMessages(text, from, to,
      settings.thinking, model, override);
    const opts = makeCompletionOptions(settings.temperature, 2000, settings.thinking);
    const logger = (d: string) => {
      if (onDelta !== undefined) {
        onDelta(d);
      }
    };
    return translator.complete(messages, opts,
      onDelta === undefined ? undefined : logger);
  }

  // -------------------------------------------------------------- history
  /** 写入一条文本翻译历史（engineLabel 用于回显）。 */
  static async saveHistory(source: string, translated: string, from: string, to: string,
    engineType: number): Promise<number> {
    try {
      await AppEnv.ready();
      const rec: TextTranslationRecord = makeTextTranslationRecord(
        source, translated, engineType, from, to);
      return await TextTranslationDao.insert(rec);
    } catch (e) {
      Log.warn(TAG, 'save history failed: ' + e);
      return -1;
    }
  }

  static async loadHistory(limit: number): Promise<Array<TextTranslationRecord>> {
    try {
      await AppEnv.ready();
      if (limit > 0) {
        return await TextTranslationDao.queryRecent(limit);
      }
      return await TextTranslationDao.queryAll();
    } catch (e) {
      Log.warn(TAG, 'load history failed: ' + e);
      return [];
    }
  }

  static async deleteHistory(id: number): Promise<void> {
    await AppEnv.ready();
    await TextTranslationDao.deleteById(id);
  }

  static async clearHistory(): Promise<void> {
    await AppEnv.ready();
    await TextTranslationDao.clear();
  }

  // --------------------------------------------------------------- labels
  /** 引擎展示名（页面顶部 / 历史条目用）。 */
  static async engineLabel(): Promise<string> {
    const settings = await TextTranslateViewModel.loadSettings();
    return TextTranslateViewModel.labelOf(settings);
  }

  static labelOf(settings: TranslateSettings): string {
    if (settings.engine === EngineType.BING) {
      return '必应（免 Key）';
    }
    if (settings.engine === EngineType.LOCAL_LLAMA) {
      return '本地模型 Hy-MT2';
    }
    const preset = EnginePresets.byId(settings.provider);
    return preset.label;
  }

  /** 历史条目里的引擎名（按持久化的 engine_type 数值反查）。 */
  static engineNameOf(engineType: number): string {
    if (engineType === EngineType.BING as number) {
      return '必应';
    }
    if (engineType === EngineType.LOCAL_LLAMA as number) {
      return '本地模型';
    }
    return 'AI 引擎';
  }

  static languagePairLabel(from: string, to: string): string {
    return LangCatalog.displayName(from) + ' → ' + LangCatalog.displayName(to);
  }

  // --------------------------------------------------------------- errors
  static readableError(e: Object): string {
    const te = e as TranslateError;
    if (te !== undefined && te !== null && te.message !== undefined && te.message.length > 0) {
      return te.message;
    }
    const err = e as Error;
    if (err !== undefined && err !== null && err.message !== undefined
      && err.message.length > 0) {
      return err.message;
    }
    return '翻译失败，请重试';
  }

  /** 错误分类标题（网络 / 鉴权 / 限流 / 超时 / 配置 / 内容）。 */
  static errorTitle(e: Object): string {
    const te = e as TranslateError;
    if (te === undefined || te === null) {
      return '翻译失败';
    }
    if (te.kind === ErrorKind.NETWORK) {
      return '网络错误';
    }
    if (te.kind === ErrorKind.AUTH) {
      return '鉴权失败';
    }
    if (te.kind === ErrorKind.RATE_LIMIT) {
      return '请求限流';
    }
    if (te.kind === ErrorKind.TIMEOUT) {
      return '请求超时';
    }
    if (te.kind === ErrorKind.BAD_CONFIG) {
      return '配置有误';
    }
    if (te.kind === ErrorKind.NO_MODEL) {
      return '缺少模型';
    }
    if (te.kind === ErrorKind.UNSUPPORTED) {
      return '暂不支持';
    }
    if (te.kind === ErrorKind.CONTENT) {
      return '返回内容异常';
    }
    return '引擎错误';
  }

  /** 可操作建议（与 errorTitle 配套显示）。 */
  static errorAdvice(e: Object): string {
    const te = e as TranslateError;
    if (te === undefined || te === null) {
      return '请重试；若持续失败，换一个引擎试试。';
    }
    if (te.kind === ErrorKind.NETWORK) {
      return '检查网络后重试；必应需要可访问 cn.bing.com / edge.microsoft.com 的网络。';
    }
    if (te.kind === ErrorKind.AUTH) {
      return '打开「引擎配置」重新填写 API Key（注意不要带空格或引号）。';
    }
    if (te.kind === ErrorKind.RATE_LIMIT) {
      return '稍等几十秒再试，或更换 API Key / 引擎。';
    }
    if (te.kind === ErrorKind.TIMEOUT) {
      return '文本可能过长或服务较慢，缩短文本或稍后重试。';
    }
    if (te.kind === ErrorKind.BAD_CONFIG) {
      return '打开「引擎配置」检查 Base URL（需含 /v1 等版本路径）与模型名。';
    }
    if (te.kind === ErrorKind.NO_MODEL) {
      return '前往「我的 → 模型管理」下载本地模型，或切换到在线引擎。';
    }
    if (te.kind === ErrorKind.CONTENT) {
      return '模型返回异常，重试或更换模型/引擎。';
    }
    return '请稍后重试；若持续失败，检查服务商控制台。';
  }
}