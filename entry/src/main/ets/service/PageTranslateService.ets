import fs from '@ohos.file.fs';
import { image } from '@kit.ImageKit';
import { preferences } from '@kit.ArkData';
import { OcrRegion, PageTranslation, TranslateStatus, makePageTranslation } from 'coremodel';
import { EngineType, TranslateRequest, Translator } from 'coretranslate';
import { OcrLang, OcrService } from 'coreocr';
import { Log, toMediaUri } from 'commons';
import { util } from '@kit.ArkTS';
import { AppEnv } from '../common/AppEnv';
import { PageRepository } from '../data/PageRepository';
import { SettingsKeys, SettingsRepository } from '../data/SettingsRepository';
import { OcrModelService } from './OcrModelService';
import { GlossaryService } from './GlossaryService';

const TAG = 'PageTranslateService';
const PREF_FILE = 'starflow_translate';
const KEY_OCR_LANG = 'ocr_lang';
const KEY_ENGINE = 'text_engine';

/**
 * 单页翻译闭环服务（T025 / plan D6/D13）：
 * 解码页图 → Core Vision OCR 行级识别 → 引擎逐行串行翻译 → 按序回填 →
 * 落库 page_translation（只存译文文本 + 原始坐标，FR-014）。
 *
 * 说明：PixelMap 非 Sendable，无法从 taskPool 返回，故图像解码走主线程
 * 异步链（image.createImageSource 为异步 API，不阻塞帧）；OCR 与引擎调用
 * 亦运行在 ArkTS 线程。
 */
export enum TranslatePhase {
  OCR = 0,
  TRANSLATE = 1,
  SAVING = 2
}

/** 单页翻译的可观察进度（OCR → 逐行翻译 → 落库）。 */
export class TranslateProgress {
  phase: TranslatePhase = TranslatePhase.OCR;
  done: number = 0;
  total: number = 0;
  percent: number = 0;
  detail: string = '';
}

export type TranslateProgressCallback = (p: TranslateProgress) => void;

export class PageTranslateService {
  private static dictText: string = '';
  /** 页内行级译文缓存：漫画气泡重复率高，命中可直接跳过网络/模型。 */
  private static lineCache: Map<string, string> = new Map<string, string>();
  private static readonly LINE_CACHE_MAX = 600;

  private static async configureOcr(): Promise<void> {
    const tier = await SettingsRepository.getString(SettingsKeys.OCR_ENGINE_TIER, 'system');
    const service = OcrService.getInstance();
    if (tier !== 'local') {
      service.setLocalEnabled(false);
      return;
    }
    if (!OcrModelService.localModelsReady()) {
      throw new Error('本地 OCR 模型未下载：请到「设置 → OCR」下载检测与识别模型');
    }
    if (PageTranslateService.dictText.length === 0) {
      const bytes = await AppEnv.getInstance().getContext().resourceManager.getRawFileContent('ppocrv6_dict.txt');
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      PageTranslateService.dictText = decoder.decodeToString(bytes);
    }
    const models = OcrModelService.list();
    service.configureLocal(OcrModelService.path(models[0]), OcrModelService.path(models[1]),
      PageTranslateService.dictText);
    service.setLocalEnabled(true);
  }

  /** 启动预热：系统 OCR 初始化或本地 OCR 会话加载，失败只记日志。 */
  static async prewarm(): Promise<void> {
    await AppEnv.ready();
    await PageTranslateService.configureOcr();
    await OcrService.getInstance().prewarmLocal();
    Log.info(TAG, 'OCR prewarm done, local=' + OcrService.getInstance().isLocalEnabled());
  }

  static async translatePage(pageId: number, engineType: EngineType,
    onProgress?: TranslateProgressCallback): Promise<PageTranslation> {
    return PageTranslateService.run(pageId, engineType, onProgress);
  }

  static async retryPage(pageId: number, engineType: EngineType,
    onProgress?: TranslateProgressCallback): Promise<PageTranslation> {
    return PageTranslateService.run(pageId, engineType, onProgress);
  }

  private static async run(pageId: number, engineType: EngineType,
    onProgress?: TranslateProgressCallback): Promise<PageTranslation> {
    await AppEnv.ready();
    const page = await PageRepository.getPage(pageId);
    if (page === undefined) {
      throw new Error('页面记录不存在');
    }
    const lang = await PageTranslateService.loadOcrLang();
    const targetLang = await PageTranslateService.loadTargetLang();
    await GlossaryService.load();
    const tStart = Date.now();
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      PageTranslateService.emitProgress(onProgress, TranslatePhase.OCR, 2, 0, 0, '准备 OCR');
      await PageTranslateService.configureOcr();

      // 本地 OCR 直接读文件；系统 OCR 才需要先解码 PixelMap。
      const localOcr = OcrService.getInstance().isLocalEnabled();
      if (!localOcr) {
        PageTranslateService.emitProgress(onProgress, TranslatePhase.OCR, 8, 0, 0, '解码页面');
        pixelMap = await PageTranslateService.decode(page.imagePath);
      }
      PageTranslateService.emitProgress(onProgress, TranslatePhase.OCR, 15, 0, 0, '识别文字');
      const tOcr = Date.now();
      // ONNX Runtime 的环境/会话在 TaskPool 中会与其他 worker 冲突
      // （Session is closed / OnnxEnvironment already initialized），
      // 当前版本回到主线程；后续用单一专用 Worker 再迁移。
      const regions: Array<OcrRegion> = await OcrService.getInstance()
        .recognize(localOcr ? undefined : pixelMap, lang, page.imagePath);
      const ocrMs = Date.now() - tOcr;
      PageTranslateService.emitProgress(onProgress, TranslatePhase.TRANSLATE, 35, 0, regions.length,
        '识别完成 ' + regions.length + ' 行');

      const translator: Translator = AppEnv.getInstance().engineRegistry.get(engineType);
      const translations: Array<string> = [];
      for (let i = 0; i < regions.length; i++) {
        translations.push('');
      }
      let failed = 0;
      let firstError = '';
      let completed = 0;
      const tTrans = Date.now();
      const translateLine = async (idx: number): Promise<void> => {
        const region = regions[idx];
        const source = GlossaryService.preReplace(region.text);
        const remembered = GlossaryService.lookup(source);
        if (remembered !== undefined) {
          translations[idx] = remembered;
          return;
        }
        const req: TranslateRequest = { text: source, from: 'auto', to: targetLang };
        const key = engineType + '|' + targetLang + '|' + source;
        const cached = PageTranslateService.lineCache.get(key);
        if (cached !== undefined) {
          translations[idx] = cached;
          return;
        }
        const translated = await translator.translate(req);
        translations[idx] = translated;
        if (PageTranslateService.lineCache.size >= PageTranslateService.LINE_CACHE_MAX) {
          PageTranslateService.lineCache.clear();
        }
        PageTranslateService.lineCache.set(key, translated);
      };
      const markProgress = (n: number): void => {
        completed = Math.min(regions.length, completed + n);
        const pct = regions.length === 0 ? 95
          : 35 + Math.round(60 * completed / regions.length);
        PageTranslateService.emitProgress(onProgress, TranslatePhase.TRANSLATE, pct,
          completed, regions.length, '翻译 ' + completed + '/' + regions.length + ' 行');
      };

      if (engineType === EngineType.LOCAL_LLAMA && regions.length > 1) {
        // 本地 llama 串行成本高：按空间位置合并成气泡/段落，一次生成后按换行拆回。
        const groups = PageTranslateService.buildRegionGroups(regions);
        for (const group of groups) {
          let assigned = false;
          if (group.length > 1) {
            const text = group.map((idx: number): string => GlossaryService.preReplace(regions[idx].text)).join('\n');
            const key = 'batch|' + engineType + '|' + targetLang + '|' + text;
            try {
              let joined = PageTranslateService.lineCache.get(key);
              if (joined === undefined) {
                joined = await translator.translate({ text: text, from: 'auto', to: targetLang });
                if (PageTranslateService.lineCache.size >= PageTranslateService.LINE_CACHE_MAX) {
                  PageTranslateService.lineCache.clear();
                }
                PageTranslateService.lineCache.set(key, joined);
              }
              const lines = joined.split('\n').map((s: string): string => s.trim())
                .filter((s: string): boolean => s.length > 0);
              if (lines.length === group.length) {
                for (let k = 0; k < group.length; k++) {
                  translations[group[k]] = lines[k];
                }
                assigned = true;
              }
            } catch (e) {
              Log.warn(TAG, 'batch translate failed, fallback per-line: ' + e);
            }
          }
          if (!assigned) {
            for (const idx of group) {
              try {
                await translateLine(idx);
              } catch (e) {
                failed++;
                if (firstError.length === 0) {
                  firstError = PageTranslateService.readableError(e);
                }
              }
            }
          }
          markProgress(group.length);
        }
      } else {
        // 网络引擎 6 路并发；单行引擎或只有一行时走逐行。
        const concurrency = Math.max(1, Math.min(engineType === EngineType.LOCAL_LLAMA ? 1 : 6,
          regions.length));
        let cursor = 0;
        const worker = async (): Promise<void> => {
          while (cursor < regions.length) {
            const idx = cursor++;
            try {
              await translateLine(idx);
            } catch (e) {
              failed++;
              if (firstError.length === 0) {
                firstError = PageTranslateService.readableError(e);
              }
            }
            markProgress(1);
          }
        };
        const workers: Array<Promise<void>> = [];
        for (let i = 0; i < concurrency; i++) {
          workers.push(worker());
        }
        await Promise.all(workers);
      }
      Log.info(TAG, 'page ' + pageId + ' timings: ocr=' + ocrMs + 'ms, translate='
        + (Date.now() - tTrans) + 'ms, total=' + (Date.now() - tStart) + 'ms');

      const pt = makePageTranslation(pageId);
      pt.engineType = engineType as number;
      pt.ocr = regions;
      pt.translations = translations;
      if (regions.length === 0) {
        pt.status = TranslateStatus.PARTIAL_FAILED;
        pt.failReason = '未识别到任何文字行';
      } else if (failed > 0) {
        pt.status = TranslateStatus.PARTIAL_FAILED;
        pt.failReason = `${failed}/${regions.length} 行翻译失败：${firstError}`;
      } else {
        pt.status = TranslateStatus.DONE;
      }
      PageTranslateService.emitProgress(onProgress, TranslatePhase.SAVING, 98,
        completed, regions.length, '保存译文');
      await PageRepository.saveTranslation(pt);
      const sources: Array<string> = [];
      for (const r of regions) {
        sources.push(r.text);
      }
      GlossaryService.rememberPage(sources, translations).catch((e: Object) => {
        Log.warn(TAG, 'remember translation failed: ' + e);
      });
      PageTranslateService.emitProgress(onProgress, TranslatePhase.SAVING, 100,
        completed, regions.length, '完成');
      Log.info(TAG, `page ${pageId}: ${regions.length} lines, ${failed} failed`);
      return pt;
    } catch (e) {
      const reason = PageTranslateService.readableError(e);
      const pt = makePageTranslation(pageId);
      pt.engineType = engineType as number;
      pt.status = TranslateStatus.PARTIAL_FAILED;
      pt.failReason = reason;
      try {
        await PageRepository.saveTranslation(pt);
      } catch (ignore) {
        // 落库失败不掩盖原始错误
      }
      Log.error(TAG, `page ${pageId} failed: ${reason}`);
      throw new Error(reason);
    } finally {
      if (pixelMap !== undefined) {
        try {
          pixelMap.release();
        } catch (ignore) {
          // release 失败忽略
        }
      }
    }
  }

  /**
   * 解码页图：沙箱绝对路径需先转媒体 URI（Image/ImageSource 不认裸路径），
   * 失败再退回 fd 打开（目录授权的 content:// 等场景）。
   */
  static async decode(path: string): Promise<image.PixelMap> {
    let source: image.ImageSource | undefined = undefined;
    let file: fs.File | undefined = undefined;
    try {
      try {
        source = image.createImageSource(toMediaUri(path));
      } catch (e) {
        source = undefined;
      }
      if (source === undefined || source === null) {
        file = fs.openSync(path, fs.OpenMode.READ_ONLY);
        source = image.createImageSource(file.fd);
      }
      if (source === undefined || source === null) {
        throw new Error('无法解码图片');
      }
      const pm = await source.createPixelMap();
      if (pm === undefined || pm === null) {
        throw new Error('无法创建像素图');
      }
      return pm;
    } finally {
      if (source !== undefined) {
        try {
          source.release();
        } catch (ignore) {
        }
      }
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (ignore) {
        }
      }
    }
  }

  /** 漫画页目标语言：沿用设置页 target_lang，不再硬编码中文。 */
  static async loadTargetLang(): Promise<string> {
    try {
      const raw = await SettingsRepository.getString(SettingsKeys.TARGET_LANG, 'zh');
      return raw.length > 0 ? raw : 'zh';
    } catch (e) {
      return 'zh';
    }
  }

  static async loadOcrLang(): Promise<OcrLang> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      const raw = pref.getSync(KEY_OCR_LANG, OcrLang.JPN as string) as string;
      if (raw === OcrLang.ENG) {
        return OcrLang.ENG;
      }
      if (raw === OcrLang.KOR) {
        return OcrLang.KOR;
      }
      if (raw === OcrLang.CHN) {
        return OcrLang.CHN;
      }
      return OcrLang.JPN;
    } catch (e) {
      return OcrLang.JPN;
    }
  }

  static async saveOcrLang(lang: OcrLang): Promise<void> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      pref.putSync(KEY_OCR_LANG, lang as string);
      await pref.flush();
    } catch (e) {
      // 偏好保存失败不影响当次翻译
    }
  }

  /** Persisted default translation engine (Bing when unset). */
  static async loadEngineType(): Promise<EngineType> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      const raw = pref.getSync(KEY_ENGINE, EngineType.BING as number) as number;
      if (raw === EngineType.OPENAI_COMPAT) {
        return EngineType.OPENAI_COMPAT;
      }
      if (raw === EngineType.LOCAL_LLAMA) {
        return EngineType.LOCAL_LLAMA;
      }
      return EngineType.BING;
    } catch (e) {
      return EngineType.BING;
    }
  }

  static async saveEngineType(type: EngineType): Promise<void> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      pref.putSync(KEY_ENGINE, type as number);
      await pref.flush();
    } catch (e) {
      // ignore
    }
  }

  /** 规则气泡/段落合并：垂直间距小且水平重叠的相邻行视为同组。 */
  private static buildRegionGroups(regions: Array<OcrRegion>): Array<Array<number>> {
    const groups: Array<Array<number>> = [];
    let current: Array<number> = [];
    let chars = 0;
    for (let i = 0; i < regions.length; i++) {
      const box = regions[i].box;
      let same = false;
      if (current.length > 0) {
        const prev = regions[current[current.length - 1]].box;
        const vgap = box.y - (prev.y + prev.h);
        const overlap = Math.min(prev.x + prev.w, box.x + box.w) - Math.max(prev.x, box.x);
        const minW = Math.min(prev.w, box.w);
        same = vgap <= Math.max(8, prev.h * 0.8) && overlap > minW * 0.25
          && current.length < 4 && chars + regions[i].text.length <= 600;
      }
      if (!same && current.length > 0) {
        groups.push(current);
        current = [];
        chars = 0;
      }
      current.push(i);
      chars += regions[i].text.length + 1;
    }
    if (current.length > 0) {
      groups.push(current);
    }
    return groups;
  }

  private static emitProgress(cb: TranslateProgressCallback | undefined, phase: TranslatePhase,
    percent: number, done: number, total: number, detail: string): void {
    if (cb === undefined) {
      return;
    }
    const p = new TranslateProgress();
    p.phase = phase;
    p.percent = Math.max(0, Math.min(100, percent));
    p.done = done;
    p.total = total;
    p.detail = detail;
    try {
      cb(p);
    } catch (e) {
      Log.warn(TAG, 'progress callback failed: ' + e);
    }
  }

  static readableError(e: Object): string {
    const err = e as Error;
    if (err !== undefined && err !== null && err.message !== undefined && err.message.length > 0) {
      return err.message;
    }
    return '页面翻译失败';
  }
}
