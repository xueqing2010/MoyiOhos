import fs from '@ohos.file.fs';
import { image } from '@kit.ImageKit';
import { preferences } from '@kit.ArkData';
import { OcrRegion, PageTranslation, TranslateStatus, makePageTranslation } from 'coremodel';
import { EngineType, TranslateRequest, Translator } from 'coretranslate';
import { OcrLang, OcrService } from 'coreocr';
import { Log, toMediaUri } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { PageRepository } from '../data/PageRepository';

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
export class PageTranslateService {
  static async translatePage(pageId: number, engineType: EngineType): Promise<PageTranslation> {
    return PageTranslateService.run(pageId, engineType);
  }

  static async retryPage(pageId: number, engineType: EngineType): Promise<PageTranslation> {
    return PageTranslateService.run(pageId, engineType);
  }

  private static async run(pageId: number, engineType: EngineType): Promise<PageTranslation> {
    await AppEnv.ready();
    const page = await PageRepository.getPage(pageId);
    if (page === undefined) {
      throw new Error('页面记录不存在');
    }
    const lang = await PageTranslateService.loadOcrLang();
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      pixelMap = await PageTranslateService.decode(page.imagePath);
      const regions: Array<OcrRegion> = await OcrService.getInstance().recognize(pixelMap, lang);
      const translator: Translator = AppEnv.getInstance().engineRegistry.get(engineType);

      const translations: Array<string> = [];
      let failed = 0;
      let firstError = '';
      // 页内行级请求串行（plan D6，MVP 可靠性优先）。
      for (const region of regions) {
        try {
          const req: TranslateRequest = { text: region.text, from: 'auto', to: 'zh' };
          const translated = await translator.translate(req);
          translations.push(translated);
        } catch (e) {
          failed++;
          if (firstError.length === 0) {
            firstError = PageTranslateService.readableError(e);
          }
          translations.push('');
        }
      }

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
      await PageRepository.saveTranslation(pt);
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

  static readableError(e: Object): string {
    const err = e as Error;
    if (err !== undefined && err !== null && err.message !== undefined && err.message.length > 0) {
      return err.message;
    }
    return '页面翻译失败';
  }
}
