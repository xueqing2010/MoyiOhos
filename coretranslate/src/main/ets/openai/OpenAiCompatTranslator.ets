import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Log } from 'commons';
import { EngineType, ErrorKind, TranslateError, TranslateRequest, Translator } from '../Translator';
import { SseParser } from './SseParser';
import { EnginePreset } from '../EnginePreset';
import {
  ChatMessage,
  CompletionOptions,
  ThinkingMode,
  assistantMessage,
  isReasoningModel,
  makeCompletionOptions,
  systemMessage,
  userMessage
} from './OpenAiTypes';

const TAG = 'OpenAiCompatTranslator';
const CONNECT_TIMEOUT_MS = 15000;
const READ_TIMEOUT_MS = 90000; // AI 端点冷启动/长文本可能超过 30s（上游经验值 90s）
const MODELS_TIMEOUT_MS = 15000;

/** OpenAI-compatible "thinking" switch (only sent for OFF / ON). */
interface ThinkingPayload {
  type: string;
}

/** chat/completions request body (ArkTS-safe typed literal). */
interface ChatCompletionBody {
  model: string;
  messages: Array<ChatMessage>;
  max_tokens: number;
  temperature: number;
  stream: boolean;
  thinking?: ThinkingPayload;
}

/** Mutable provider config, updated by the settings dialog (T037 / S107). */
export class OpenAiConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
  /** Preset id the config was derived from ('deepseek' | 'custom' | ...). */
  presetId: string;

  constructor(baseUrl: string, apiKey: string, model: string, presetId?: string) {
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    this.model = model;
    this.presetId = presetId === undefined ? 'openai' : presetId;
  }
}

/**
 * OpenAI-compatible engine (plan D6 / S107).
 *
 * Two entry points:
 *  · translate()/translateStream() — MVP-1 contract, prompt built internally
 *    (still used by PageTranslateService / batch translation).
 *  · complete(messages, opts) — stage-2 contract: the caller owns the prompt
 *    (PromptTemplates) and passes a full messages array; also used by the
 *    chat translation page so multi-turn history rides in the same stream.
 *
 * Streaming always consumes SSE with an incremental onDelta callback; servers
 * that ignore stream:true fall back to whole-body parsing.
 */
export class OpenAiCompatTranslator implements Translator {
  readonly engineType: EngineType = EngineType.OPENAI_COMPAT;
  private config: OpenAiConfig;

  constructor(config: OpenAiConfig) {
    this.config = config;
  }

  /** Update provider config at runtime (settings dialog save). */
  setConfig(config: OpenAiConfig): void {
    this.config = config;
  }

  getConfig(): OpenAiConfig {
    return this.config;
  }

  /** Current preset id (falls back to 'openai' for legacy configs). */
  presetId(): string {
    return this.config.presetId;
  }

  /**
   * Apply a preset template + the user's key. An explicit model override always
   * wins over the preset default, so a user who typed a model keeps it.
   */
  applyPreset(preset: EnginePreset, apiKey: string, modelOverride: string): void {
    const trimmed = modelOverride.trim();
    const model = trimmed.length > 0 ? trimmed : preset.defaultModel;
    this.config = new OpenAiConfig(preset.baseUrl, apiKey, model, preset.id);
    Log.info(TAG, `preset applied: ${preset.id} model=${model} url=${preset.baseUrl}`);
  }

  /** True when the configured model looks like a reasoning model. */
  isReasoning(): boolean {
    return isReasoningModel(this.config.model);
  }

  async translate(req: TranslateRequest): Promise<string> {
    const cfg = this.requireConfig();
    const messages = this.legacyMessages(req, cfg.model, ThinkingMode.AUTO);
    const opts = makeCompletionOptions(0.3, 1000, ThinkingMode.AUTO);
    const body = this.buildBody(messages, opts, false);
    const text = await this.postJson(this.chatEndpoint(cfg.baseUrl), cfg.apiKey, body, READ_TIMEOUT_MS);
    return this.parseCompletion(text);
  }

  async translateStream(req: TranslateRequest, onDelta: (delta: string) => void): Promise<string> {
    const cfg = this.requireConfig();
    const messages = this.legacyMessages(req, cfg.model, ThinkingMode.AUTO);
    const opts = makeCompletionOptions(0.3, 1000, ThinkingMode.AUTO);
    const body = this.buildBody(messages, opts, true);
    return this.runStream(body, onDelta);
  }

  /**
   * Stage-2 entry point: caller-supplied messages (PromptTemplates) with
   * per-call sampling options. With onDelta the answer streams.
   */
  async complete(messages: Array<ChatMessage>, opts: CompletionOptions,
    onDelta?: (delta: string) => void): Promise<string> {
    const cfg = this.requireConfig();
    if (messages.length === 0) {
      throw new TranslateError(ErrorKind.BAD_CONFIG, '提示词为空，无法发起翻译');
    }
    if (onDelta !== undefined) {
      const body = this.buildBody(messages, opts, true);
      return this.runStream(body, onDelta);
    }
    const body = this.buildBody(messages, opts, false);
    const text = await this.postJson(this.chatEndpoint(cfg.baseUrl), cfg.apiKey, body, READ_TIMEOUT_MS);
    return this.parseCompletion(text);
  }

  /**
   * Conversation variant of translateStream(): the caller supplies the whole
   * messages array (history + current turn) and receives incremental deltas.
   */
  async translateMessagesStream(messages: Array<ChatMessage>,
    onDelta: (delta: string) => void, opts?: CompletionOptions): Promise<string> {
    const options = opts === undefined
      ? makeCompletionOptions(0.3, 1000, ThinkingMode.AUTO)
      : opts;
    return this.complete(messages, options, onDelta);
  }

  /** Non-streaming messages variant (batch / connection test). */
  async translateMessages(messages: Array<ChatMessage>, opts?: CompletionOptions): Promise<string> {
    const options = opts === undefined
      ? makeCompletionOptions(0.3, 1000, ThinkingMode.AUTO)
      : opts;
    return this.complete(messages, options);
  }

  /** GET {baseUrl}/models for the provider dialog (T037 / S107). */
  async listModels(): Promise<Array<string>> {
    const cfg = this.requireConfig();
    const headers: Record<string, string> = {
      'Authorization': `Bearer ${cfg.apiKey}`
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: MODELS_TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING
    };
    const url = cfg.baseUrl.endsWith('/') ? `${cfg.baseUrl}models` : `${cfg.baseUrl}/models`;
    let resp: http.HttpResponse;
    try {
      const httpRequest = http.createHttp();
      resp = await httpRequest.request(url, options);
      httpRequest.destroy();
    } catch (e) {
      throw this.classifyHttpError(e);
    }
    if (resp.responseCode >= 400) {
      throw this.httpError(resp.responseCode, resp.result as string);
    }
    const parsed = JSON.parse(resp.result as string) as Record<string, Object>;
    const data = parsed['data'] as Array<Record<string, Object>>;
    const models: Array<string> = [];
    if (data !== undefined && data !== null) {
      for (const item of data) {
        const id = item['id'] as string;
        if (id !== undefined && id !== null && id.length > 0) {
          models.push(id);
        }
      }
    }
    return models;
  }

  private requireConfig(): OpenAiConfig {
    if (this.config.apiKey.trim().length === 0) {
      throw new TranslateError(ErrorKind.BAD_CONFIG, '请先在引擎配置中填写 API Key');
    }
    if (this.config.model.trim().length === 0) {
      throw new TranslateError(ErrorKind.BAD_CONFIG, '请先在引擎配置中选择或填写模型名');
    }
    if (this.config.baseUrl.trim().length === 0) {
      throw new TranslateError(ErrorKind.BAD_CONFIG, '请先在引擎配置中填写 Base URL');
    }
    return this.config;
  }

  private chatEndpoint(baseUrl: string): string {
    const trimmed = baseUrl.trim();
    if (trimmed.endsWith('/chat/completions')) {
      return trimmed;
    }
    return trimmed.endsWith('/') ? `${trimmed}chat/completions` : `${trimmed}/chat/completions`;
  }

  /**
   * MVP-1 prompt (kept verbatim so page translation outcomes do not change).
   * Stage-2 text translation always goes through complete() + PromptTemplates.
   */
  private legacyMessages(req: TranslateRequest, model: string, thinking: ThinkingMode): Array<ChatMessage> {
    const toLang = this.langName(req.to);
    const fromLang = this.langName(req.from);
    const system: ChatMessage = systemMessage(
      `You are a professional translation engine. Translate the user's text into ${toLang}. Output ONLY the translated text, without any explanation or quotes.`);
    const user: ChatMessage = userMessage(req.from === 'auto'
      ? req.text
      : `Translate the following ${fromLang} text into ${toLang}:\n${req.text}`);
    const out: Array<ChatMessage> = [system, user];
    return out;
  }

  private buildBody(messages: Array<ChatMessage>, opts: CompletionOptions, stream: boolean): string {
    const body: ChatCompletionBody = {
      model: this.config.model,
      messages: messages,
      max_tokens: opts.maxTokens,
      temperature: opts.temperature,
      stream: stream
    };
    if (opts.thinking === ThinkingMode.ON) {
      const t: ThinkingPayload = { type: 'enabled' };
      body.thinking = t;
    } else if (opts.thinking === ThinkingMode.OFF) {
      const t: ThinkingPayload = { type: 'disabled' };
      body.thinking = t;
    }
    // AUTO deliberately sends NO thinking field: several gateways reject it.
    return JSON.stringify(body);
  }

  /**
   * POST with stream:true and incremental SSE consumption.
   * Cross-chunk UTF-8 is handled inside SseParser's Utf8ChunkDecoder, so a
   * multi-byte character split across two TCP chunks is never mangled.
   */
  private async runStream(body: string, onDelta: (delta: string) => void): Promise<string> {
    const cfg = this.requireConfig();
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${cfg.apiKey}`,
      'Accept': 'text/event-stream'
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS
    };
    const httpRequest = http.createHttp();
    let result = '';
    let sawSseEvent = false;
    let rawBytes: Array<number> = [];
    const parser = new SseParser({
      onEvent: (data: string) => {
        sawSseEvent = true;
        const delta = this.extractDelta(data);
        if (delta.length > 0) {
          result += delta;
          onDelta(delta);
        }
      },
      onDone: () => {
        sawSseEvent = true;
      }
    });
    httpRequest.on('dataReceive', (chunk: ArrayBuffer) => {
      const bytes = new Uint8Array(chunk);
      for (let i = 0; i < bytes.length; i++) {
        rawBytes.push(bytes[i]);
      }
      parser.push(chunk);
    });
    let streamEnded = false;
    httpRequest.on('dataEnd', () => {
      streamEnded = true;
      parser.flush();
    });
    let respCode = -1;
    try {
      // requestInStream resolves with the HTTP status code once the body ends.
      respCode = await httpRequest.requestInStream(this.chatEndpoint(cfg.baseUrl), options);
    } catch (e) {
      throw this.classifyHttpError(e);
    } finally {
      httpRequest.destroy();
    }
    if (respCode >= 400) {
      throw this.httpError(respCode, this.rawText(rawBytes));
    }
    if (result.length > 0) {
      return result;
    }
    // Server ignored stream:true (or plain JSON body): whole-body parse.
    const whole = this.rawText(rawBytes);
    if (!streamEnded) {
      parser.flush();
    }
    if (sawSseEvent && whole.trim().length === 0) {
      throw new TranslateError(ErrorKind.CONTENT, '模型未返回任何内容');
    }
    const content = this.parseCompletion(whole);
    if (content.length > 0) {
      onDelta(content);
    }
    return content;
  }

  /** Non-stream completion parse: choices[0].message.content. */
  private parseCompletion(text: string): string {
    const parsed = this.parseJson(text);
    const err = this.serverError(parsed);
    if (err !== undefined) {
      throw new TranslateError(ErrorKind.ENGINE, err);
    }
    const choices = parsed['choices'] as Array<Record<string, Object>>;
    if (choices === undefined || choices === null || choices.length === 0) {
      throw new TranslateError(ErrorKind.CONTENT, '模型未返回翻译结果');
    }
    const message = choices[0]['message'] as Record<string, Object>;
    if (message === undefined || message === null) {
      throw new TranslateError(ErrorKind.CONTENT, '模型响应缺少 message 字段');
    }
    const content = (message['content'] as string) ?? '';
    const trimmed = content.trim();
    if (trimmed.length === 0) {
      throw new TranslateError(ErrorKind.CONTENT, '模型返回了空译文');
    }
    return trimmed;
  }

  /** SSE chunk parse: choices[0].delta.content (may be absent/empty). */
  private extractDelta(data: string): string {
    const parsed = this.parseJson(data);
    const choices = parsed['choices'] as Array<Record<string, Object>>;
    if (choices === undefined || choices === null || choices.length === 0) {
      return '';
    }
    const delta = choices[0]['delta'] as Record<string, Object>;
    if (delta === undefined || delta === null) {
      return '';
    }
    // Some providers stream reasoning_content separately — it must NOT be
    // appended to the translation result.
    const content = delta['content'] as string;
    if (content === undefined || content === null) {
      return '';
    }
    return content;
  }

  private parseJson(text: string): Record<string, Object> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(text.trim()) as Record<string, Object>;
    } catch (e) {
      throw new TranslateError(ErrorKind.CONTENT, '服务端返回内容无法解析');
    }
    if (parsed === null || parsed === undefined) {
      throw new TranslateError(ErrorKind.CONTENT, '服务端返回内容无法解析');
    }
    return parsed;
  }

  /** OpenAI-compatible {"error":{"message":"..."}} extraction (upstream). */
  private serverError(parsed: Record<string, Object>): string | undefined {
    const err = parsed['error'] as Record<string, Object>;
    if (err === undefined || err === null) {
      return undefined;
    }
    const message = (err['message'] as string) ?? '';
    const type = (err['type'] as string) ?? 'unknown';
    return `OpenAI API error (${type}): ${message}`;
  }

  private async postJson(url: string, apiKey: string, body: string, timeoutMs: number): Promise<string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: timeoutMs,
      expectDataType: http.HttpDataType.STRING
    };
    let resp: http.HttpResponse;
    try {
      const httpRequest = http.createHttp();
      resp = await httpRequest.request(url, options);
      httpRequest.destroy();
    } catch (e) {
      throw this.classifyHttpError(e);
    }
    if (resp.responseCode >= 400) {
      throw this.httpError(resp.responseCode, resp.result as string);
    }
    return resp.result as string;
  }

  /** Classify HTTP status into readable TranslateError (US-8 场景4). */
  private httpError(code: number, body: string): TranslateError {
    let serverMessage = '';
    try {
      const parsed = JSON.parse(body) as Record<string, Object>;
      const err = parsed['error'] as Record<string, Object>;
      if (err !== undefined && err !== null) {
        const m = err['message'] as string;
        if (m !== undefined && m !== null) {
          serverMessage = m;
        }
      }
    } catch (e) {
      // Non-JSON body (gateway HTML etc.) — fall back to raw snippet.
    }
    if (serverMessage.length === 0) {
      serverMessage = body.length > 200 ? body.substring(0, 200) : body;
    }
    if (code === 401 || code === 403) {
      return new TranslateError(ErrorKind.AUTH, `鉴权失败（HTTP ${code}）：API Key 无效或无权限。${serverMessage}`);
    }
    if (code === 429) {
      return new TranslateError(ErrorKind.RATE_LIMIT, `请求过于频繁（HTTP 429）：${serverMessage}`);
    }
    if (code === 404) {
      return new TranslateError(ErrorKind.BAD_CONFIG,
        `接口不存在（HTTP 404）：请检查 Base URL 是否包含正确的 API 版本路径。/v1。${serverMessage}`);
    }
    if (code === 400) {
      return new TranslateError(ErrorKind.BAD_CONFIG, `请求被拒绝（HTTP 400）：${serverMessage}`);
    }
    if (code === 408 || code === 504) {
      return new TranslateError(ErrorKind.TIMEOUT, `服务端超时（HTTP ${code}）：${serverMessage}`);
    }
    if (code >= 500) {
      return new TranslateError(ErrorKind.ENGINE, `服务端故障（HTTP ${code}）：${serverMessage}`);
    }
    return new TranslateError(ErrorKind.ENGINE, `服务端错误（HTTP ${code}）：${serverMessage}`);
  }

  private rawBytesToText(bytes: Array<number>): Uint8Array {
    const out: Uint8Array = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) {
      out[i] = bytes[i];
    }
    return out;
  }

  private rawText(bytes: Array<number>): string {
    if (bytes.length === 0) {
      return '';
    }
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(this.rawBytesToText(bytes));
  }

  private langName(code: string): string {
    const map: Record<string, string> = {
      'auto': 'auto-detected language',
      'zh': 'Simplified Chinese',
      'zh-Hans': 'Simplified Chinese',
      'zh-Hant': 'Traditional Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'en': 'English',
      'fr': 'French',
      'de': 'German',
      'es': 'Spanish',
      'ru': 'Russian',
      'it': 'Italian',
      'pt': 'Portuguese',
      'th': 'Thai',
      'vi': 'Vietnamese',
      'id': 'Indonesian',
      'ar': 'Arabic'
    };
    const name = map[code];
    if (name !== undefined) {
      return name;
    }
    return code;
  }

  /** Map @ohos.net.http / libcurl failures into readable TranslateError kinds. */
  private classifyHttpError(e: Object): TranslateError {
    const err = e as BusinessError;
    const code: number = err.code;
    if (code === 2300028) {
      return new TranslateError(ErrorKind.TIMEOUT, '请求超时：网络较慢或服务端无响应，请重试');
    }
    if (code === 2300006 || code === 2300007 || code === 2300005) {
      return new TranslateError(ErrorKind.NETWORK, `无法连接服务器（${code}）：请检查网络与 Base URL`);
    }
    if (code === 2300060 || code === 2300058) {
      return new TranslateError(ErrorKind.NETWORK, `安全连接失败（${code}）：证书校验或代理异常`);
    }
    if (code !== undefined && code >= 2300000 && code < 2301000) {
      return new TranslateError(ErrorKind.NETWORK, `网络错误（${code}）：${err.message ?? ''}`);
    }
    return new TranslateError(ErrorKind.NETWORK, `网络请求失败：${err.message ?? '未知错误'}`);
  }
}