import { Log } from 'commons';
import { EngineType, ErrorKind, TranslateError, TranslateRequest, Translator } from '../Translator';
import { GenOptions, LlamaBackend, LlamaError, makeGenOptions } from '../LlamaBackend';

const TAG = 'LocalLlamaTranslator';
const MAX_NEW_TOKENS = 512;

/**
 * Local llama.cpp engine facade (plan D6): resolves the injected
 * LlamaBackend lazily, loads the downloaded GGUF on first use, and
 * streams tokens through onDelta.
 *
 * The model path is provided by AppEnv (from DownloadDao once the
 * Hy-MT2 download completes); SpikeNapiPage drives LlamaBackend
 * directly for the P0-6 spike (independent of this facade).
 */
export class LocalLlamaTranslator implements Translator {
  readonly engineType: EngineType = EngineType.LOCAL_LLAMA;
  private backendGetter: () => LlamaBackend | undefined;
  private modelPath: string | undefined;
  private handle: number | undefined;

  constructor(backendGetter: () => LlamaBackend | undefined) {
    this.backendGetter = backendGetter;
  }

  /** Set (or clear) the downloaded GGUF path; reloads on next use. */
  setModelPath(path: string | undefined): void {
    if (path === this.modelPath) {
      return;
    }
    this.unloadModel();
    this.modelPath = path;
  }

  /** Release the loaded model handle (memory pressure / page close). */
  unloadModel(): void {
    if (this.handle === undefined) {
      return;
    }
    const backend = this.backendGetter();
    if (backend !== undefined) {
      try {
        backend.unloadModel(this.handle);
      } catch (e) {
        Log.warn(TAG, `unloadModel failed: ${e}`);
      }
    }
    this.handle = undefined;
  }

  isModelLoaded(): boolean {
    return this.handle !== undefined;
  }

  async translate(req: TranslateRequest): Promise<string> {
    return this.run(req, undefined);
  }

  async translateStream(req: TranslateRequest, onDelta: (delta: string) => void): Promise<string> {
    return this.run(req, onDelta);
  }

  private async run(req: TranslateRequest, onDelta: ((delta: string) => void) | undefined): Promise<string> {
    const backend = this.requireBackend();
    const handle = await this.ensureLoaded(backend);
    const opts = makeGenOptions(this.buildPrompt(req), MAX_NEW_TOKENS, 0.3);
    let result = '';
    try {
      const onToken = onDelta === undefined
        ? (t: string) => {
            result += t;
          }
        : (t: string) => {
            result += t;
            onDelta(t);
          };
      const finalText = await backend.generate(handle, opts, onToken);
      // Prefer backend-joined text when available (backend knows detokenization).
      const text = finalText.length > 0 ? finalText : result;
      const trimmed = text.trim();
      if (trimmed.length === 0) {
        throw new TranslateError(ErrorKind.CONTENT, '本地模型未产出译文');
      }
      return trimmed;
    } catch (e) {
      throw this.mapLlamaError(e);
    }
  }

  private requireBackend(): LlamaBackend {
    const backend = this.backendGetter();
    if (backend === undefined) {
      throw new TranslateError(
        ErrorKind.UNSUPPORTED,
        'llama.cpp 动态库未加载（当前构建为降级模式），本地翻译不可用'
      );
    }
    return backend;
  }

  private async ensureLoaded(backend: LlamaBackend): Promise<number> {
    if (this.handle !== undefined) {
      return this.handle;
    }
    if (this.modelPath === undefined || this.modelPath.length === 0) {
      throw new TranslateError(
        ErrorKind.NO_MODEL,
        '尚未下载本地模型，请前往「我的 → 模型管理」下载 Hy-MT2'
      );
    }
    try {
      const start = Date.now();
      this.handle = await backend.loadModel(this.modelPath);
      Log.info(TAG, `model loaded in ${Date.now() - start}ms`);
      return this.handle;
    } catch (e) {
      throw this.mapLlamaError(e);
    }
  }

  /**
   * Hy-MT2 (Hunyuan-MT) directive prompt — manual formatting per plan
   * (P3 replaces this with the minja chat-template system).
   */
  private buildPrompt(req: TranslateRequest): string {
    const toLang = this.langName(req.to);
    return `将下面的文本翻译成${toLang}，不要额外解释。\n\n${req.text}`;
  }

  private langName(code: string): string {
    const map: Record<string, string> = {
      'zh': '简体中文',
      'zh-Hans': '简体中文',
      'zh-Hant': '繁体中文',
      'ja': '日语',
      'ko': '韩语',
      'en': '英语',
      'fr': '法语',
      'de': '德语',
      'es': '西班牙语',
      'ru': '俄语',
      'it': '意大利语',
      'pt': '葡萄牙语',
      'th': '泰语',
      'vi': '越南语',
      'id': '印尼语',
      'ar': '阿拉伯语'
    };
    const name = map[code];
    if (name !== undefined) {
      return name;
    }
    return code;
  }

  private mapLlamaError(e: Object): TranslateError {
    const err = e as LlamaError;
    if (err.unsupported !== undefined && err.unsupported) {
      return new TranslateError(ErrorKind.UNSUPPORTED, err.message);
    }
    const msg = err.message ?? '本地模型运行失败';
    if (msg.indexOf('加载') >= 0 || msg.indexOf('load') >= 0 || msg.indexOf('GGUF') >= 0) {
      return new TranslateError(ErrorKind.NO_MODEL, msg);
    }
    return new TranslateError(ErrorKind.ENGINE, msg);
  }
}
