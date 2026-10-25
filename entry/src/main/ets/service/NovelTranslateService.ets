import { preferences } from '@kit.ArkData';
import { NovelChapter, TranslateStatus } from 'coremodel';
import {
  EngineType,
  Translator,
  TranslateRequest,
  TranslateError,
  ErrorKind
} from 'coretranslate';
import { NovelParagraph, ParagraphSplitter } from 'corenovel';
import { Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { NovelRepository } from '../data/NovelRepository';

const TAG = 'NovelTranslateService';
const PREF_FILE = 'starflow_translate';
const KEY_ENGINE = 'text_engine';
const KEY_TARGET = 'target_lang';
const KEY_SOURCE = 'source_lang';

/** 单章翻译进度。 */
export class NovelTranslateProgress {
  done: number = 0;
  total: number = 0;
}

/** 单章翻译结果。 */
export class NovelTranslateResult {
  status: TranslateStatus = TranslateStatus.NONE;
  translatedParagraphs: number = 0;
  failedParagraphs: number = 0;
  totalParagraphs: number = 0;
  cancelled: boolean = false;
  failReason: string = '';
}

/**
 * 小说章节翻译服务（对齐上游 novel/translate）：
 * - 复用 coretranslate EngineRegistry（必应零 Key / OpenAI 兼容 / 本地 llama）；
 * - 章节按段落切分后逐段串行翻译（可靠性优先），短段不送翻直接保留原文；
 * - 译文按段落对齐（空行分隔）写回 novel_chapter.translated_content，
 *   段落对齐是「原文/译文/双语」三态不串段的前提；
 * - 无网络/未配置密钥时返回可读中文原因，不崩溃。
 */
export class NovelTranslateService {
  /** 读取翻译引擎（默认必应，零 Key 可用）。 */
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

  /** 目标语言（默认中文）。 */
  static async loadTargetLang(): Promise<string> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      const raw = pref.getSync(KEY_TARGET, 'zh') as string;
      return raw.length > 0 ? raw : 'zh';
    } catch (e) {
      return 'zh';
    }
  }

  /** 源语言（默认自动探测）。 */
  static async loadSourceLang(): Promise<string> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      const raw = pref.getSync(KEY_SOURCE, 'auto') as string;
      return raw.length > 0 ? raw : 'auto';
    } catch (e) {
      return 'auto';
    }
  }

  static engineLabel(type: EngineType): string {
    if (type === EngineType.OPENAI_COMPAT) {
      return 'OpenAI 兼容';
    }
    if (type === EngineType.LOCAL_LLAMA) {
      return '本地模型';
    }
    return '必应';
  }

  /**
   * 翻译一章并落库。
   * @param chapter 章节（须有 id/novelId/content）
   * @param engineType 引擎
   * @param onProgress 段落进度回调
   * @param isCancelled 取消判定（取消时保存已翻译部分，状态为部分失败）
   */
  static async translateChapter(chapter: NovelChapter, engineType: EngineType,
    onProgress?: (done: number, total: number) => void,
    isCancelled?: () => boolean): Promise<NovelTranslateResult> {
    await AppEnv.ready();
    const result = new NovelTranslateResult();
    const paragraphs: Array<NovelParagraph> = ParagraphSplitter.split(chapter.content);
    result.totalParagraphs = paragraphs.length;
    if (paragraphs.length === 0) {
      result.failReason = '本章没有可翻译的文字';
      return result;
    }
    let translator: Translator;
    try {
      translator = AppEnv.getInstance().engineRegistry.get(engineType);
    } catch (e) {
      result.failReason = NovelTranslateService.readableError(e);
      return result;
    }
    const target = await NovelTranslateService.loadTargetLang();
    const source = await NovelTranslateService.loadSourceLang();
    const translated: Array<string> = [];
    let firstError = '';
    for (let i = 0; i < paragraphs.length; i++) {
      if (isCancelled !== undefined && isCancelled()) {
        result.cancelled = true;
        break;
      }
      const text = paragraphs[i].text;
      if (text.length < ParagraphSplitter.MIN_TRANSLATE_LENGTH) {
        translated.push(text);
      } else {
        try {
          const req: TranslateRequest = { text: text, from: source, to: target };
          const out = await translator.translate(req);
          translated.push(out.length > 0 ? out : text);
          result.translatedParagraphs++;
        } catch (e) {
          result.failedParagraphs++;
          if (firstError.length === 0) {
            firstError = NovelTranslateService.readableError(e);
          }
          translated.push(text);
        }
      }
      if (onProgress !== undefined) {
        onProgress(i + 1, paragraphs.length);
      }
    }
    // 剩余段落（取消时）用原文占位，保证段落数量对齐。
    for (let i = translated.length; i < paragraphs.length; i++) {
      translated.push(paragraphs[i].text);
    }
    const joined = ParagraphSplitter.join(translated);
    let status = TranslateStatus.DONE;
    if (result.cancelled) {
      status = TranslateStatus.PARTIAL_FAILED;
      result.failReason = '已取消，保留已翻译部分';
    } else if (result.failedParagraphs > 0) {
      status = TranslateStatus.PARTIAL_FAILED;
      result.failReason = result.failedParagraphs + '/' + paragraphs.length
        + ' 段翻译失败：' + firstError;
    }
    result.status = status;
    try {
      await NovelRepository.saveChapterTranslation(chapter.id, joined, status,
        result.failReason.length > 0 ? result.failReason : undefined);
      await NovelRepository.refreshTranslateStatus(chapter.novelId);
    } catch (e) {
      Log.warn(TAG, 'save translation failed: ' + e);
    }
    Log.info(TAG, 'chapter ' + chapter.chapterIndex + ' translated: '
      + result.translatedParagraphs + '/' + paragraphs.length);
    return result;
  }

  /** 引擎错误 → 可读中文提示。 */
  static readableError(e: Object): string {
    if (e instanceof TranslateError) {
      const kind = e.kind;
      if (kind === ErrorKind.NETWORK) {
        return '网络不可用，请检查网络后重试';
      }
      if (kind === ErrorKind.AUTH) {
        return '翻译密钥无效或未配置，请在设置中填写';
      }
      if (kind === ErrorKind.RATE_LIMIT) {
        return '请求过于频繁，请稍后再试';
      }
      if (kind === ErrorKind.TIMEOUT) {
        return '翻译请求超时，请重试';
      }
      if (kind === ErrorKind.BAD_CONFIG) {
        return '翻译引擎配置不完整，请检查设置';
      }
      if (kind === ErrorKind.NO_MODEL) {
        return '本地模型未下载，请在模型管理中下载';
      }
      if (kind === ErrorKind.UNSUPPORTED) {
        return '当前引擎不支持该语言组合';
      }
      if (e.message !== undefined && e.message.length > 0) {
        return e.message;
      }
      return '翻译引擎不可用';
    }
    const plain = e as Error;
    if (plain !== undefined && plain !== null && plain.message !== undefined
      && plain.message.length > 0) {
      return plain.message;
    }
    return '翻译失败（未知错误）';
  }
}
