import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Log } from 'commons';
import { EngineType, ErrorKind, TranslateError, TranslateRequest, Translator } from '../Translator';

const TAG = 'BingTranslator';
/**
 * Primary path (2024+): an anonymous JWT from edge.microsoft.com opens the
 * Azure-style api-edge endpoint — no HTML scraping, no anti-abuse token.
 */
const EDGE_AUTH_URL = 'https://edge.microsoft.com/translate/auth';
const EDGE_TRANSLATE_URL = 'https://api-edge.cognitive.microsofttranslator.com/translate';
/** Legacy path (kept as fallback): scrape the Translator page tokens. */
const BING_TRANSLATOR_URL = 'https://cn.bing.com/Translator';
const BING_TT_URL = 'https://cn.bing.com/ttranslatev3';

const UA_DESKTOP = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
/** Anonymous edge tokens live ~10 min; refresh a bit earlier to avoid 401 races. */
const EDGE_TOKEN_TTL_MS = 8 * 60 * 1000;
/** After consecutive legacy failures, skip it for this long before retrying. */
const LEGACY_COOLDOWN_MS = 60 * 1000;
/** Diagnostic log truncation for response bodies (hilog friendly). */
const LOG_HEAD_LEN = 160;
const LOG_FAIL_LEN = 500;

/** Anti-abuse tokens + session cookie scraped from the legacy Translator page. */
class BingSession {
  ig: string;
  iid: string;
  key: string;
  token: string;
  cookie: string;

  constructor(ig: string, iid: string, key: string, token: string, cookie: string) {
    this.ig = ig;
    this.iid = iid;
    this.key = key;
    this.token = token;
    this.cookie = cookie;
  }
}

/** One item of the api-edge request array. */
interface EdgeTranslateItem {
  Text: string;
}

/**
 * Bing translator (default, zero-config engine).
 *
 * Transport order (2026-10 revision, device-verified): the legacy
 * cn.bing.com/ttranslatev3 session path is now PRIMARY because
 *   · edge.microsoft.com/translate/auth is publicly returning 404 (endpoint
 *     retired / blocked), so every call used to waste one failed request;
 *   · legacy works as long as fromLang is the literal 'auto-detect'
 *     (fromLang=auto returns 200 + {"statusCode":400,"errorMessage":""}).
 * The anonymous-JWT api-edge path is kept as an optional fallback for
 * networks where it still works; a 404 on the auth endpoint disables it for
 * the rest of the session immediately.
 *
 * Robustness (device bug 2026-10-25): a 200 response whose body is NOT the
 * expected [{translations:[{text}]}] array used to reach `root[0]['translations']`
 * and blow up with "Cannot load property of null or undefined". Every response
 * body is now converted through resultToText() (string / ArrayBuffer /
 * Uint8Array / object) and parsed defensively with a fallback to the legacy
 * transport instead of surfacing a TypeError.
 */
export class BingTranslator implements Translator {
  readonly engineType: EngineType = EngineType.BING;
  private session: BingSession | undefined;
  private edgeToken: string = '';
  private edgeTokenAt: number = 0;
  /** Consecutive edge-path failures; after 2 we short-circuit to the legacy path. */
  private edgeFailures: number = 0;
  private edgeDisabled: boolean = false;
  /** Consecutive legacy failures; after 2 we skip legacy for a 60s cooldown. */
  private legacyFailures: number = 0;
  private legacyDisabledUntil: number = 0;

  async translate(req: TranslateRequest): Promise<string> {
    // Same-language request: nothing to translate (Bing would 400).
    if (req.from !== 'auto' && req.from === req.to) {
      return req.text;
    }
    let legacyError: TranslateError | undefined = undefined;

    // ---- primary: legacy ttranslatev3 (fromLang already mapped to 'auto-detect') ----
    if (Date.now() >= this.legacyDisabledUntil) {
      try {
        const text = await this.translateViaLegacy(req);
        this.legacyFailures = 0;
        this.legacyDisabledUntil = 0;
        return text;
      } catch (e) {
        const kind = BingTranslator.errorKindOf(e);
        legacyError = BingTranslator.asTranslateError(e);
        Log.warn(TAG, 'legacy path failed (' + BingTranslator.reasonOf(e)
          + '), trying edge fallback');
        this.session = undefined;
        if (kind === ErrorKind.RATE_LIMIT) {
          // Do not hammer the fallback when the service asked us to slow down.
          throw legacyError;
        }
        this.legacyFailures++;
        if (this.legacyFailures >= 2) {
          // Cooldown (not permanent): a transient network blip must not brick
          // the primary path until the app restarts.
          this.legacyDisabledUntil = Date.now() + LEGACY_COOLDOWN_MS;
          this.legacyFailures = 0;
          Log.warn(TAG, 'legacy path cooling down for ' + LEGACY_COOLDOWN_MS + 'ms');
        }
      }
    }

    // ---- fallback: anonymous-JWT api-edge (may be retired, see class comment) ----
    if (!this.edgeDisabled) {
      try {
        const text = await this.translateViaEdge(req);
        this.edgeFailures = 0;
        return text;
      } catch (e) {
        this.edgeToken = '';
        this.edgeTokenAt = 0;
        this.edgeFailures++;
        const edgeError = BingTranslator.asTranslateError(e);
        Log.warn(TAG, 'edge fallback failed (' + BingTranslator.reasonOf(e) + ')');
        // Prefer the legacy message when both failed: it is the path users expect.
        throw legacyError !== undefined ? legacyError : edgeError;
      }
    }
    if (legacyError !== undefined) {
      throw legacyError;
    }
    throw new TranslateError(ErrorKind.NETWORK,
      '必应翻译通道不可用（主通道失败，备用通道已下线），请检查网络后重试或更换引擎');
  }

  /** Bing has no incremental API: emit the full result once. */
  async translateStream(req: TranslateRequest, onDelta: (delta: string) => void): Promise<string> {
    const text = await this.translate(req);
    onDelta(text);
    return text;
  }

  // -------------------------------------------------------------------------
  // Primary: api-edge.cognitive.microsofttranslator.com
  // -------------------------------------------------------------------------

  private async translateViaEdge(req: TranslateRequest): Promise<string> {
    if (!BingTranslator.isSupportedPair(req.from, req.to)) {
      throw new TranslateError(ErrorKind.UNSUPPORTED, '必应暂不支持该语言组合，请改用其它引擎');
    }
    const token = await this.ensureEdgeToken();
    const url = BingTranslator.buildEdgeUrl(req.from, req.to);
    const item: EdgeTranslateItem = { Text: req.text };
    const payloadArr: Array<EdgeTranslateItem> = [item];
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + token,
      'User-Agent': UA_DESKTOP
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: JSON.stringify(payloadArr),
      connectTimeout: 15000,
      readTimeout: 30000,
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
    if (resp.responseCode === 401 || resp.responseCode === 403) {
      // Token expired between issue and use: drop it so the next call re-auths.
      this.edgeToken = '';
      this.edgeTokenAt = 0;
      throw new TranslateError(ErrorKind.AUTH, '必应临时令牌已失效，请重试');
    }
    if (resp.responseCode === 429) {
      throw new TranslateError(ErrorKind.RATE_LIMIT, '必应请求过于频繁，请稍后再试');
    }
    if (resp.responseCode !== 200) {
      throw new TranslateError(ErrorKind.ENGINE, '必应服务返回错误（HTTP '
        + resp.responseCode + '）');
    }
    this.edgeFailures = 0;
    // Diagnostic: one compact line per call (type + length + head).
    const raw: Object | string | ArrayBuffer | undefined = resp.result;
    const body = BingTranslator.resultToText(raw);
    // 只在形状异常时打印内容（正常响应体含用户译文，不落日志）
    const canonical = body.trim().startsWith('[');
    Log.info(TAG, 'edge 200: rawType=' + typeof raw + ' textLen=' + body.length
      + ' canonicalArray=' + canonical);
    if (!canonical) {
      Log.warn(TAG, 'edge non-array body(' + LOG_FAIL_LEN + '): '
        + BingTranslator.clip(body, LOG_FAIL_LEN));
    }
    return BingTranslator.parseEdgeResponse(body);
  }

  private async ensureEdgeToken(): Promise<string> {
    const now = Date.now();
    if (this.edgeToken.length > 0 && now - this.edgeTokenAt < EDGE_TOKEN_TTL_MS) {
      return this.edgeToken;
    }
    const headers: Record<string, string> = {
      'User-Agent': UA_DESKTOP,
      'Accept': '*/*'
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 15000,
      readTimeout: 20000,
      expectDataType: http.HttpDataType.STRING
    };
    let resp: http.HttpResponse;
    try {
      const httpRequest = http.createHttp();
      resp = await httpRequest.request(EDGE_AUTH_URL, options);
      httpRequest.destroy();
    } catch (e) {
      throw this.classifyHttpError(e);
    }
    if (resp.responseCode === 404) {
      // Endpoint retired/blocked (verified publicly returning 404 on 2026-10):
      // stop paying a failed round-trip on every translation.
      this.edgeDisabled = true;
      this.edgeFailures = 3;
      Log.warn(TAG, 'edge auth endpoint returned 404, edge path disabled for this session');
      throw new TranslateError(ErrorKind.UNSUPPORTED, '必应备用通道已下线（HTTP 404）');
    }
    if (resp.responseCode !== 200) {
      throw new TranslateError(ErrorKind.ENGINE, '无法获取必应令牌（HTTP '
        + resp.responseCode + '）');
    }
    let token = BingTranslator.resultToText(resp.result).trim();
    // Some gateways wrap the JWT in quotes.
    if (token.length > 1 && token.startsWith('\"') && token.endsWith('\"')) {
      token = token.substring(1, token.length - 1).trim();
    }
    // The token is a JWT: three dot-separated segments.
    if (token.length < 20 || token.indexOf('.') < 0) {
      Log.warn(TAG, 'edge auth body(' + LOG_FAIL_LEN + '>=): '
        + BingTranslator.clip(token, LOG_FAIL_LEN));
      throw new TranslateError(ErrorKind.ENGINE, '必应令牌格式异常');
    }
    this.edgeToken = token;
    this.edgeTokenAt = Date.now();
    Log.info(TAG, 'edge token refreshed, len=' + token.length);
    return token;
  }

  /** api-edge URL: from is omitted for auto-detection. */
  static buildEdgeUrl(from: string, to: string): string {
    const toLang = BingTranslator.mapLangStatic(to);
    const base = EDGE_TRANSLATE_URL + '?api-version=3.0&to=' + encodeURIComponent(toLang);
    if (from.length === 0 || from === 'auto') {
      return base;
    }
    return base + '&from=' + encodeURIComponent(BingTranslator.mapLangStatic(from));
  }

  // -------------------------------------------------------------------------
  // Response decoding / parsing (hardened — see class comment)
  // -------------------------------------------------------------------------

  /**
   * Convert an HttpResponse.result (string | ArrayBuffer | Uint8Array | object)
   * into text. Never throws: returns '' when the value cannot be decoded.
   */
  static resultToText(raw: Object | string | ArrayBuffer | undefined | null): string {
    if (raw === undefined || raw === null) {
      return '';
    }
    if (typeof raw === 'string') {
      return raw as string;
    }
    // Binary bodies (expectDataType ignored / gateway): decode as UTF-8.
    try {
      if (raw instanceof ArrayBuffer) {
        const u8: Uint8Array = new Uint8Array(raw as ArrayBuffer);
        return util.TextDecoder.create('utf-8').decodeToString(u8);
      }
    } catch (e) {
      // fall through
    }
    try {
      if (raw instanceof Uint8Array) {
        return util.TextDecoder.create('utf-8').decodeToString(raw as Uint8Array);
      }
    } catch (e) {
      // fall through
    }
    // Already-parsed object (no expectDataType): stringify back to JSON text.
    try {
      return JSON.stringify(raw);
    } catch (e) {
      return '';
    }
  }

  /** Truncate for logs, escaping newlines so one entry stays one hilog line. */
  static clip(text: string, max: number): string {
    if (text.length === 0) {
      return '';
    }
    const flat = text.replace(/\r?\n/g, ' ');
    return flat.length <= max ? flat : (flat.substring(0, max) + '…');
  }

  /**
   * Extract translations[0].text from one translation node.
   * Returns undefined instead of throwing so callers can pick the right error.
   */
  private static extractTranslation(node: Object | undefined | null): string | undefined {
    if (node === undefined || node === null) {
      return undefined;
    }
    if (typeof node !== 'object') {
      return undefined;
    }
    const rec = node as Record<string, Object>;
    const translations = rec['translations'];
    if (translations === undefined || translations === null || !Array.isArray(translations)) {
      return undefined;
    }
    const list = translations as Array<Object>;
    if (list.length === 0) {
      return undefined;
    }
    const first = list[0];
    if (first === undefined || first === null || typeof first !== 'object') {
      return undefined;
    }
    const text = (first as Record<string, Object>)['text'];
    if (typeof text !== 'string') {
      return undefined;
    }
    const out = text as string;
    return out.length > 0 ? out : undefined;
  }

  /**
   * Parse an api-edge body. Accepts every shape seen in the wild:
   *   [{translations:[{text}]}]        — canonical
   *   {translations:[{text}]}          — some proxies unwrap the array
   *   {error:{code,message}}           — HTTP 200 error envelope
   * Anything else throws a readable TranslateError (never a TypeError).
   */
  static parseEdgeResponse(body: string): string {
    const trimmed = body.trim();
    if (trimmed.length === 0) {
      throw new TranslateError(ErrorKind.CONTENT, '必应返回了空响应，请重试');
    }
    let parsed: Object | undefined = undefined;
    try {
      parsed = JSON.parse(trimmed) as Object;
    } catch (e) {
      Log.warn(TAG, 'edge body is not JSON(' + LOG_FAIL_LEN + '>=): '
        + BingTranslator.clip(trimmed, LOG_FAIL_LEN));
      throw new TranslateError(ErrorKind.CONTENT, '必应返回内容不是 JSON，请重试或更换引擎');
    }
    if (parsed === undefined || parsed === null) {
      throw new TranslateError(ErrorKind.CONTENT, '必应返回了空结果');
    }
    // 1) canonical array shape
    if (Array.isArray(parsed)) {
      const arr = parsed as Array<Object>;
      if (arr.length === 0) {
        throw new TranslateError(ErrorKind.CONTENT, '必应返回了空结果');
      }
      const text = BingTranslator.extractTranslation(arr[0]);
      if (text !== undefined) {
        return text;
      }
      BingTranslator.logShape('array-without-translations', trimmed);
      throw new TranslateError(ErrorKind.CONTENT, '必应返回结构异常（缺少 translations）');
    }
    // 2) object shape: either {translations:[...]} or an error envelope
    const obj = parsed as Record<string, Object>;
    const direct = BingTranslator.extractTranslation(parsed);
    if (direct !== undefined) {
      Log.info(TAG, 'edge body was object-wrapped translations (compat path)');
      return direct;
    }
    const err = obj['error'];
    if (err !== undefined && err !== null && typeof err === 'object') {
      const code = (err as Record<string, Object>)['code'];
      const message = (err as Record<string, Object>)['message'];
      const codeText = typeof code === 'number' ? ('' + (code as number)) : ('' + code);
      const msgText = typeof message === 'string' ? (message as string) : '未知错误';
      Log.warn(TAG, 'edge error envelope: code=' + codeText + ' message=' + msgText);
      if (codeText === '401' || codeText === '403' || codeText === '401000') {
        throw new TranslateError(ErrorKind.AUTH, '必应鉴权失败：' + msgText);
      }
      if (codeText === '429' || codeText === '429001') {
        throw new TranslateError(ErrorKind.RATE_LIMIT, '必应请求过于频繁：' + msgText);
      }
      if (codeText === '400035' || codeText === '400041') {
        throw new TranslateError(ErrorKind.UNSUPPORTED, '必应不支持该语言组合：' + msgText);
      }
      throw new TranslateError(ErrorKind.ENGINE, '必应接口错误（' + codeText + '）：' + msgText);
    }
    BingTranslator.logShape('unknown-object', trimmed);
    throw new TranslateError(ErrorKind.CONTENT, '必应返回结构无法识别，请重试或更换引擎');
  }

  /** Log the unexpected body shape once per failure (keeps hilog useful). */
  private static logShape(reason: string, body: string): void {
    Log.warn(TAG, 'edge unexpected body [' + reason + ']: '
      + BingTranslator.clip(body, LOG_FAIL_LEN));
  }

  /** Language sanity check (edge rejects unknown codes with a 400). */
  static isSupportedPair(from: string, to: string): boolean {
    const known: Array<string> = [
      'auto', 'auto-detect', 'zh', 'zh-CN', 'zh-Hans', 'zh-TW', 'zh-HK', 'zh-Hant',
      'en', 'ja', 'ko', 'fr', 'de', 'es', 'ru', 'it', 'pt', 'th', 'vi', 'id', 'ar',
      'nl', 'pl', 'tr', 'uk', 'ms', 'hi'
    ];
    return known.indexOf(from) >= 0 && known.indexOf(to) >= 0 && from !== to;
  }

  // -------------------------------------------------------------------------
  // Fallback: legacy cn.bing.com/ttranslatev3 session scrape
  // -------------------------------------------------------------------------

  private async translateViaLegacy(req: TranslateRequest): Promise<string> {
    let session = await this.ensureSession();
    let resp = await this.postLegacy(session, req);
    if (resp.responseCode === 401 || resp.responseCode === 403) {
      // Anti-abuse token rotated: refresh the session and retry exactly once.
      Log.warn(TAG, 'legacy session rejected (HTTP ' + resp.responseCode + '), refreshing');
      this.session = undefined;
      session = await this.ensureSession();
      resp = await this.postLegacy(session, req);
    }
    if (resp.responseCode === 429) {
      this.session = undefined;
      throw new TranslateError(ErrorKind.RATE_LIMIT, '必应请求过于频繁，请稍后再试');
    }
    if (resp.responseCode === 401 || resp.responseCode === 403) {
      this.session = undefined;
      throw new TranslateError(ErrorKind.AUTH, '必应拒绝了本次会话，请重试');
    }
    if (resp.responseCode !== 200) {
      this.session = undefined;
      throw new TranslateError(ErrorKind.ENGINE, '必应服务返回错误（HTTP '
        + resp.responseCode + '）');
    }
    const bodyText = BingTranslator.resultToText(resp.result);
    const canonicalLegacy = bodyText.trim().startsWith('[');
    Log.info(TAG, 'legacy 200: textLen=' + bodyText.length
      + ' canonicalArray=' + canonicalLegacy);
    if (!canonicalLegacy) {
      Log.warn(TAG, 'legacy non-array body(' + LOG_FAIL_LEN + '): '
        + BingTranslator.clip(bodyText, LOG_FAIL_LEN));
    }
    return BingTranslator.parseTranslationResponse(bodyText);
  }

  /** POST ttranslatev3 for one session (network errors become TranslateError). */
  private async postLegacy(session: BingSession, req: TranslateRequest): Promise<http.HttpResponse> {
    const body = BingTranslator.buildFormBody(req.from, req.to, req.text, session.token, session.key);
    const headers: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': UA_DESKTOP,
      'Referer': BING_TRANSLATOR_URL,
      'Cookie': session.cookie
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      connectTimeout: 15000,
      readTimeout: 30000,
      expectDataType: http.HttpDataType.STRING
    };
    try {
      const httpRequest = http.createHttp();
      const resp = await httpRequest.request(BING_TT_URL + '?isVertical=1&IG=' + session.ig
        + '&IID=' + session.iid, options);
      httpRequest.destroy();
      return resp;
    } catch (e) {
      Log.warn(TAG, 'ttranslatev3 failed (' + BingTranslator.reasonOf(e) + ')');
      this.session = undefined;
      throw this.classifyHttpError(e);
    }
  }

  /** Parse the legacy ttranslatev3 body: [{translations:[{text}]}]. */
  static parseTranslationResponse(body: string): string {
    const trimmed = body.trim();
    if (trimmed.length === 0) {
      throw new TranslateError(ErrorKind.CONTENT, '必应返回了空响应，请重试');
    }
    let parsed: Object | undefined = undefined;
    try {
      parsed = JSON.parse(trimmed) as Object;
    } catch (e) {
      BingTranslator.logShape('legacy-not-json', trimmed);
      throw new TranslateError(ErrorKind.CONTENT, '必应返回内容不是 JSON，请重试');
    }
    if (parsed === undefined || parsed === null) {
      throw new TranslateError(ErrorKind.CONTENT, '必应返回了空结果');
    }
    if (Array.isArray(parsed)) {
      const arr = parsed as Array<Object>;
      if (arr.length === 0) {
        throw new TranslateError(ErrorKind.CONTENT, '必应返回了空结果');
      }
      const text = BingTranslator.extractTranslation(arr[0]);
      if (text !== undefined) {
        return text;
      }
    } else {
      const direct = BingTranslator.extractTranslation(parsed);
      if (direct !== undefined) {
        return direct;
      }
    }
    // Legacy error envelope: {"statusCode":400,"errorMessage":""} (HTTP 200!)
    const obj = parsed as Record<string, Object>;
    const statusCode = obj['statusCode'];
    if (statusCode !== undefined && statusCode !== null && typeof statusCode === 'number') {
      const code = statusCode as number;
      const rawMessage = obj['errorMessage'];
      const message = (typeof rawMessage === 'string' && (rawMessage as string).length > 0)
        ? (rawMessage as string) : '';
      Log.warn(TAG, 'legacy statusCode envelope: code=' + code + ' message=' + message);
      if (code === 401 || code === 403) {
        throw new TranslateError(ErrorKind.AUTH, '必应拒绝了本次请求（' + code + '）：'
          + (message.length > 0 ? message : '请重试'));
      }
      if (code === 429) {
        throw new TranslateError(ErrorKind.RATE_LIMIT, '必应请求过于频繁，请稍后再试');
      }
      if (code === 400) {
        throw new TranslateError(ErrorKind.UNSUPPORTED, '必应不支持该语言组合或参数（400）'
          + (message.length > 0 ? '：' + message : ''));
      }
      throw new TranslateError(ErrorKind.ENGINE, '必应接口错误（' + code + '）'
        + (message.length > 0 ? '：' + message : ''));
    }
    BingTranslator.logShape('legacy-bad-shape', trimmed);
    throw new TranslateError(ErrorKind.CONTENT, '必应返回结构异常，请重试或更换引擎');
  }

  private async ensureSession(): Promise<BingSession> {
    if (this.session !== undefined) {
      return this.session;
    }
    const headers: Record<string, string> = {
      'User-Agent': UA_DESKTOP,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 15000,
      readTimeout: 20000,
      expectDataType: http.HttpDataType.STRING
    };
    let resp: http.HttpResponse;
    try {
      const httpRequest = http.createHttp();
      resp = await httpRequest.request(BING_TRANSLATOR_URL, options);
      httpRequest.destroy();
    } catch (e) {
      throw this.classifyHttpError(e);
    }
    if (resp.responseCode !== 200) {
      throw new TranslateError(ErrorKind.ENGINE, '无法获取必应会话（HTTP '
        + resp.responseCode + '）');
    }
    const html = BingTranslator.resultToText(resp.result);
    if (html.length === 0) {
      throw new TranslateError(ErrorKind.ENGINE, '必应会话页面为空');
    }
    const ig = this.firstMatch(html, /IG:"(.*?)"/);
    const iid = this.firstMatch(html, /<div id="tta_outGDCont" data-iid="(.*?)">/);
    const abuseRaw = this.firstMatch(html, /var params_AbusePreventionHelper = (.*?);/);
    if (ig === undefined || iid === undefined || abuseRaw === undefined) {
      BingTranslator.logShape('legacy-session-html', html);
      throw new TranslateError(ErrorKind.ENGINE, '必应页面结构已变化，令牌解析失败');
    }
    const inner = abuseRaw.replace('[', '').replace(']', '');
    const parts = inner.split(',');
    if (parts.length < 2) {
      throw new TranslateError(ErrorKind.ENGINE, '必应防滥用令牌解析失败');
    }
    const key = parts[0].trim().replace(/^"|"$/g, '');
    const tokenPart = parts[1].trim().replace(/^"|"$/g, '');
    const cookie = this.collectCookies(resp.header);
    if (key.length === 0 || tokenPart.length === 0) {
      throw new TranslateError(ErrorKind.ENGINE, '必应防滥用令牌为空');
    }
    this.session = new BingSession(ig, iid, key, tokenPart, cookie);
    Log.info(TAG, 'legacy Bing session refreshed');
    return this.session;
  }

  private collectCookies(header: Object): string {
    if (header === undefined || header === null) {
      return '';
    }
    const record = header as Record<string, Object>;
    let raw: Object | undefined = record['set-cookie'];
    if (raw === undefined || raw === null) {
      raw = record['Set-Cookie'];
    }
    if (raw === undefined || raw === null) {
      return '';
    }
    if (typeof raw === 'string') {
      return this.cookiePairsFrom(raw as string);
    }
    if (!Array.isArray(raw)) {
      return '';
    }
    const arr = raw as Array<Object>;
    const parts: Array<string> = [];
    for (const item of arr) {
      if (typeof item === 'string') {
        parts.push(item as string);
      }
    }
    if (parts.length > 0) {
      return this.cookiePairsFrom(parts.join('\n'));
    }
    return '';
  }

  /** Keep only name=value pairs (strip attributes like Path=/; HttpOnly). */
  private cookiePairsFrom(raw: string): string {
    const pairs: Array<string> = [];
    const chunks = raw.split(/\n|,(?=[^;]+?=)/);
    for (const chunk of chunks) {
      const first = chunk.split(';')[0].trim();
      if (first.length > 0 && first.indexOf('=') > 0) {
        pairs.push(first);
      }
    }
    return pairs.join('; ');
  }

  /**
   * Pure form-body assembly (unit-tested): the ttranslatev3 payload shape
   * with anti-abuse token/key and gender-debiasing flag.
   */
  static buildFormBody(from: string, to: string, text: string, token: string, key: string): string {
    const fromLang = BingTranslator.mapLangStatic(from);
    const toLang = BingTranslator.mapLangStatic(to);
    return 'fromLang=' + encodeURIComponent(fromLang)
      + '&to=' + encodeURIComponent(toLang)
      + '&text=' + encodeURIComponent(text)
      + '&tryFetchingGenderDebiasedTranslations=true'
      + '&token=' + encodeURIComponent(token)
      + '&key=' + encodeURIComponent(key);
  }

  /**
   * Bing language-code mapping (device-verified 2026-10):
   *  · auto / '' / 'auto-detect' -> 'auto-detect'
   *    (fromLang=auto returns HTTP 200 + {"statusCode":400,"errorMessage":""}!)
   *  · zh / zh-CN / zh-Hans       -> 'zh-Hans'
   *  · zh-TW / zh-HK / zh-Hant    -> 'zh-Hant'
   *  · everything else passes through unchanged.
   */
  static mapLangStatic(lang: string): string {
    const v = lang.trim();
    if (v.length === 0 || v === 'auto' || v === 'auto-detect') {
      return 'auto-detect';
    }
    if (v === 'zh' || v === 'zh-CN' || v === 'zh-Hans' || v === 'zh-hans') {
      return 'zh-Hans';
    }
    if (v === 'zh-TW' || v === 'zh-HK' || v === 'zh-Hant' || v === 'zh-hant') {
      return 'zh-Hant';
    }
    return v;
  }

  private firstMatch(text: string, pattern: RegExp): string | undefined {
    if (text.length === 0) {
      return undefined;
    }
    const m = text.match(pattern);
    if (m === null || m.length < 2) {
      return undefined;
    }
    return m[1];
  }

  /** Kind of a caught error (undefined for non-TranslateError throwables). */
  private static errorKindOf(e: Object | undefined | null): ErrorKind | undefined {
    if (e === undefined || e === null) {
      return undefined;
    }
    const te = e as TranslateError;
    if (typeof te.kind === 'number') {
      return te.kind;
    }
    return undefined;
  }

  /** Never surface a raw TypeError to the UI: wrap unknown throwables. */
  private static asTranslateError(e: Object | undefined | null): TranslateError {
    if (e !== undefined && e !== null) {
      const te = e as TranslateError;
      if (typeof te.kind === 'number' && te.message !== undefined) {
        return te;
      }
      const err = e as Error;
      const raw = (err !== undefined && err !== null && err.message !== undefined)
        ? err.message : '';
      if (raw.length > 0) {
        Log.warn(TAG, 'converted unexpected error: ' + raw);
        return new TranslateError(ErrorKind.ENGINE, '必应接口返回异常，请重试或更换引擎');
      }
    }
    return new TranslateError(ErrorKind.ENGINE, '必应翻译失败，请重试');
  }

  /** Short reason string for logs (never leaks the whole error object). */
  private static reasonOf(e: Object | undefined | null): string {
    if (e === undefined || e === null) {
      return 'unknown';
    }
    const te = e as TranslateError;
    const kind = typeof te.kind === 'number' ? ('' + (te.kind as number)) : '?';
    const err = e as Error;
    const message = (err !== undefined && err !== null && err.message !== undefined)
      ? err.message : '';
    return 'kind=' + kind + ' msg=' + message;
  }

  private classifyHttpError(e: Object): TranslateError {
    const err = e as BusinessError;
    if (err === undefined || err === null) {
      return new TranslateError(ErrorKind.NETWORK, '网络请求失败，请重试');
    }
    if (err.code === 2300028) {
      return new TranslateError(ErrorKind.TIMEOUT, '必应请求超时，请稍后重试');
    }
    if (err.code !== undefined && err.code >= 2300000 && err.code < 2301000) {
      return new TranslateError(ErrorKind.NETWORK, '网络错误（' + err.code + '）：请检查网络连接');
    }
    const msg = err.message !== undefined ? err.message : '未知错误';
    return new TranslateError(ErrorKind.NETWORK, '网络请求失败：' + msg);
  }
}