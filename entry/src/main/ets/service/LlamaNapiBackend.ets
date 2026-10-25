import {
  generate as nativeGenerate,
  getVersion as nativeGetVersion,
  loadModel as nativeLoadModel,
  stopGeneration as nativeStopGeneration,
  unloadModel as nativeUnloadModel
} from 'libllamacpp.so';
import { GenOptions, LlamaBackend, LlamaError } from 'coretranslate';
import { Log } from 'commons';

const TAG = 'LlamaNapiBackend';

/**
 * LlamaBackend implementation over the libllamacpp.so NAPI module
 * (T042 / plan D11). Injected into AppEnv at startup so coretranslate
 * never depends on entry. When the native lib is absent (degraded
 * build), all calls surface a readable error and isAvailable() = false.
 */
export class LlamaNapiBackend implements LlamaBackend {
  /** Probe the native module (false in degraded builds). */
  static isAvailable(): boolean {
    try {
      const v: string = nativeGetVersion();
      return v !== undefined && v.length > 0;
    } catch (e) {
      return false;
    }
  }

  getVersion(): string {
    try {
      const v: string = nativeGetVersion();
      return v;
    } catch (e) {
      return '未加载（native 库不可用）';
    }
  }

  async loadModel(path: string): Promise<number> {
    try {
      // Synchronous native load; surfaced through a Promise for the contract.
      const handle: number = nativeLoadModel(path);
      if (handle <= 0) {
        throw new LlamaError('模型加载失败', false);
      }
      return handle;
    } catch (e) {
      throw LlamaNapiBackend.mapError(e);
    }
  }

  generate(handle: number, opts: GenOptions, onToken: (t: string) => void): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const temperature = opts.temperature !== undefined ? opts.temperature : 0.3;
      try {
        nativeGenerate(handle, opts.prompt, opts.maxTokens, temperature,
          (token: string) => {
            try {
              onToken(token);
            } catch (e) {
              Log.warn(TAG, `onToken callback error: ${e}`);
            }
          },
          (text: string, isError: boolean) => {
            if (isError) {
              reject(new LlamaError(text, false));
            } else {
              resolve(text);
            }
          });
      } catch (e) {
        reject(LlamaNapiBackend.mapError(e));
      }
    });
  }

  stopGeneration(handle: number): void {
    try {
      nativeStopGeneration(handle);
    } catch (e) {
      Log.warn(TAG, `stopGeneration failed: ${e}`);
    }
  }

  unloadModel(handle: number): void {
    try {
      nativeUnloadModel(handle);
    } catch (e) {
      Log.warn(TAG, `unloadModel failed: ${e}`);
    }
  }

  private static mapError(e: Object): LlamaError {
    const err = e as Error;
    const msg = err !== undefined && err.message !== undefined && err.message.length > 0
      ? err.message
      : '本地模型运行失败';
    const unsupported = msg.indexOf('1.25bit') >= 0 || msg.indexOf('STQ1_0') >= 0 || msg.indexOf('暂不支持') >= 0;
    return new LlamaError(msg, unsupported);
  }
}
