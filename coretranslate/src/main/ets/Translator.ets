/**
 * Translation engine contracts (plan D6).
 * Engines register into EngineRegistry; the local llama engine is a
 * facade injected from entry via LlamaBackend (no HAR→entry dependency).
 */

export enum EngineType {
  BING = 0,
  OPENAI_COMPAT = 1,
  LOCAL_LLAMA = 2
}

export interface TranslateRequest {
  text: string;
  /** Source language code, e.g. 'auto' | 'ja' | 'en'. */
  from: string;
  /** Target language code, e.g. 'zh'. */
  to: string;
}

/** Error classification for readable UI messages (US-8 scene 4). */
export enum ErrorKind {
  NETWORK = 0,
  AUTH = 1,
  RATE_LIMIT = 2,
  TIMEOUT = 3,
  BAD_CONFIG = 4,
  ENGINE = 5,
  NO_MODEL = 6,
  UNSUPPORTED = 7,
  CONTENT = 8
}

export class TranslateError extends Error {
  readonly kind: ErrorKind;

  constructor(kind: ErrorKind, message: string) {
    super(message);
    this.kind = kind;
  }
}

export function makeTranslateRequest(text: string, from: string, to: string): TranslateRequest {
  const r: TranslateRequest = { text: text, from: from, to: to };
  return r;
}

/** Every engine implements this contract. */
export interface Translator {
  readonly engineType: EngineType;
  translate(req: TranslateRequest): Promise<string>;
  translateStream?(req: TranslateRequest, onDelta: (delta: string) => void): Promise<string>;
}

/** Registry of available engines (Bing at init, local llama injected later). */
export class EngineRegistry {
  private map: Map<EngineType, Translator> = new Map();

  register(t: Translator): void {
    this.map.set(t.engineType, t);
  }

  get(type: EngineType): Translator {
    const t = this.map.get(type);
    if (t === undefined) {
      throw new TranslateError(ErrorKind.ENGINE, '该翻译引擎未注册或不可用');
    }
    return t;
  }

  has(type: EngineType): boolean {
    return this.map.has(type);
  }
}
