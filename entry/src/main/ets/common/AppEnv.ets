import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { RdbHelper, DownloadDao, DownloadStatus } from 'coremodel';
import {
  EngineRegistry,
  EngineType,
  LlamaBackend,
  BingTranslator,
  LocalLlamaTranslator,
  OpenAiCompatTranslator,
  OpenAiConfig,
  AssetKeyStore
} from 'coretranslate';
import { Log } from 'commons';
import { LlamaNapiBackend } from '../service/LlamaNapiBackend';

/**
 * Application-wide singleton assembly (plan: common/AppEnv.ets).
 * Holds the UIAbility context, initializes the RDB, owns the global
 * NavPathStack and the EngineRegistry; the llama NAPI backend is
 * injected at startup (T042) so coretranslate never depends on entry.
 */
export class AppEnv {
  private static instance: AppEnv = new AppEnv();

  private context: common.Context | undefined = undefined;
  private initPromise: Promise<void> | undefined = undefined;
  private initialized: boolean = false;

  /** Global navigation stack shared by tabs and pages. */
  readonly navStack: NavPathStack = new NavPathStack();
  /** Translation engine registry (all engines registered at init). */
  readonly engineRegistry: EngineRegistry = new EngineRegistry();
  private llamaBackend: LlamaBackend | undefined = undefined;
  private localTranslator: LocalLlamaTranslator | undefined = undefined;
  private openaiTranslator: OpenAiCompatTranslator | undefined = undefined;
  private keyStore: AssetKeyStore = new AssetKeyStore();

  private constructor() {
  }

  static getInstance(): AppEnv {
    return AppEnv.instance;
  }

  /**
   * Idempotent initialization, called from EntryAbility.onCreate.
   * Safe to call multiple times; concurrent callers await the same promise.
   */
  static async init(context: common.Context): Promise<void> {
    const env = AppEnv.getInstance();
    if (env.initPromise === undefined) {
      env.context = context;
      env.initPromise = AppEnv.doInit(env);
    }
    await env.initPromise;
  }

  private static async doInit(env: AppEnv): Promise<void> {
    const started = Date.now();
    await RdbHelper.init(env.getContext());
    AppEnv.cleanupExportCache(env.getContext());
    // Secure key storage (Asset Store Kit with preferences fallback, plan D7).
    env.keyStore.bind(env.getContext());
    // Default engine: Bing (no key required).
    env.engineRegistry.register(new BingTranslator());
    // OpenAI-compatible engine with empty config; settings dialog fills it (T037).
    env.openaiTranslator = new OpenAiCompatTranslator(new OpenAiConfig('https://api.openai.com/v1', '', ''));
    env.engineRegistry.register(env.openaiTranslator);
    // Local llama facade with lazy backend lookup (backend injected by T042).
    // Native NAPI backend injected here (coretranslate stays entry-free, plan D6).
    env.setLlamaBackend(new LlamaNapiBackend());
    env.localTranslator = new LocalLlamaTranslator(() => {
      return env.getLlamaBackend();
    });
    env.engineRegistry.register(env.localTranslator);
    // Restore downloaded model path so local translation survives restarts.
    await env.restoreLocalModelPath();
    env.initialized = true;
    Log.info('AppEnv', `initialized in ${Date.now() - started}ms (RDB + engines)`);
  }

  /**
   * Remove stale export staging (cache/export/<ts>/ and <ts>.zip) left behind by
   * a force-stop or crash mid-export. Runs at startup; user-visible exports are
   * already copied to the chosen save location, so this only reclaims cache.
   */
  private static cleanupExportCache(context: common.Context): void {
    const dir = context.cacheDir + '/export';
    try {
      if (!fs.accessSync(dir)) {
        return;
      }
      const names = fs.listFileSync(dir);
      for (const name of names) {
        const full = dir + '/' + name;
        try {
          const stat = fs.statSync(full);
          if (stat.isDirectory()) {
            fs.rmdirSync(full);
          } else {
            fs.unlinkSync(full);
          }
        } catch (e) {
          // Best-effort: ignore one entry and continue with the rest.
        }
      }
      Log.info('AppEnv', 'stale export cache cleaned');
    } catch (e) {
      Log.warn('AppEnv', `cleanup export cache failed: ${e}`);
    }
  }

  /** Point the local engine at the newest completed GGUF download, if any. */
  private async restoreLocalModelPath(): Promise<void> {
    const tasks = await DownloadDao.queryAll();
    for (const task of tasks) {
      // 只恢复 GGUF 翻译模型；OCR 的 .onnx 任务也在同一张表里，不能误当成本地翻译模型。
      if (task.status !== DownloadStatus.DOWNLOADED || task.localPath === undefined) {
        continue;
      }
      if (!task.fileName.toLowerCase().endsWith('.gguf')) {
        continue;
      }
      try {
        if (!fs.accessSync(task.localPath) || fs.statSync(task.localPath).size < 1024 * 1024) {
          continue;
        }
      } catch (e) {
        continue;
      }
      this.localTranslator?.setModelPath(task.localPath);
      Log.info('AppEnv', `local model restored: ${task.displayName}`);
      return;
    }
  }

  /** Await this from pages before touching the database. */
  static async ready(): Promise<void> {
    const env = AppEnv.getInstance();
    if (env.initPromise === undefined) {
      throw new Error('AppEnv 尚未初始化（EntryAbility 未调用 init）');
    }
    await env.initPromise;
  }

  getContext(): common.Context {
    const ctx = this.context;
    if (ctx === undefined) {
      throw new Error('AppEnv 尚未初始化：context 缺失');
    }
    return ctx;
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  /** Injected by entry at startup (LlamaNapiBackend, T042). */
  setLlamaBackend(backend: LlamaBackend): void {
    this.llamaBackend = backend;
  }

  getLlamaBackend(): LlamaBackend | undefined {
    return this.llamaBackend;
  }

  getLocalTranslator(): LocalLlamaTranslator | undefined {
    return this.localTranslator;
  }

  getOpenAiTranslator(): OpenAiCompatTranslator | undefined {
    return this.openaiTranslator;
  }

  getKeyStore(): AssetKeyStore {
    return this.keyStore;
  }

  /** Update the local engine model path (called by ModelManager on success). */
  updateLocalModelPath(path: string | undefined): void {
    this.localTranslator?.setModelPath(path);
  }
}