/**
 * Local llama inference contract (plan D6). The interface lives in
 * coretranslate; the NAPI implementation lives in entry
 * (service/LlamaNapiBackend.ets) and is injected at startup.
 */
export interface GenOptions {
  prompt: string;
  maxTokens: number;
  temperature?: number;
}

export class LlamaError extends Error {
  readonly unsupported: boolean;

  constructor(message: string, unsupported: boolean) {
    super(message);
    this.unsupported = unsupported;
  }
}

export function makeGenOptions(prompt: string, maxTokens: number, temperature: number): GenOptions {
  const o: GenOptions = { prompt: prompt, maxTokens: maxTokens, temperature: temperature };
  return o;
}

export interface LlamaBackend {
  getVersion(): string;

  /** Load a GGUF model; returns a handle. Throws LlamaError with readable reason. */
  loadModel(path: string): Promise<number>;

  /** Stream tokens through onToken; resolves with the full text. */
  generate(handle: number, opts: GenOptions, onToken: (t: string) => void): Promise<string>;

  stopGeneration(handle: number): void;

  unloadModel(handle: number): void;
}
