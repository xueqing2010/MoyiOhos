import { preferences } from '@kit.ArkData';
import { Log } from 'commons';
import { AppEnv } from '../common/AppEnv';

/**
 * SettingsRepository — 设置项统一读写入口（settings-dev 维护）。
 *
 * 设计（plan §6 共享契约 / QA-5）：
 *  · 新设置统一落在 preferences 文件 starflow_settings；
 *  · 兼容既有三个文件：starflow_reader（阅读/渲染）、starflow_shelf（书架视图）、
 *    starflow_translate（翻译引擎/目标语言/OCR 语言/OpenAI 配置）——按 key 自动路由，
 *    这样 reader-dev / translate-dev 既有的 preferences 读写无需迁移即可生效；
 *  · 所有方法先 await AppEnv.ready()，失败一律 try/catch 回退默认值，不崩溃；
 *  · 其他模块只读这里定义的键（需要新增键请先联系 settings-dev）。
 */

const TAG = 'SettingsRepository';
const FILE_SETTINGS = 'starflow_settings';
const FILE_READER = 'starflow_reader';
const FILE_SHELF = 'starflow_shelf';
const FILE_TRANSLATE = 'starflow_translate';

/**
 * 设置键常量与用途说明。
 * 命名前缀约定：reader_/render_/novel_ → starflow_reader；
 * openai_/translate_/prompt_/target_lang/text_engine/ocr_lang → starflow_translate；
 * shelf_/view_mode → starflow_shelf；其余 → starflow_settings。
 */
export class SettingsKeys {
  // ---------- starflow_settings：应用级设置 ----------
  /** 首次启动引导是否已完成（bool）。Lead 启动时读取；引导页完成/跳过后写 true。 */
  static readonly ONBOARDING_DONE: string = 'onboarding_done';
  /** 主题模式（string）：'blue' 蓝白（默认）| 'blueDark' 蓝黑夜间；旧 purple/oled/system 迁移到蓝白。 */
  static readonly THEME_MODE: string = 'theme_mode';
  /** OCR 引擎档位（string）：'system' 系统 Core Vision Kit（默认）| 'local' 本地 ONNX 模型（需下载模型）。 */
  static readonly OCR_ENGINE_TIER: string = 'ocr_engine_tier';
  /** 华为账号是否已登录（bool，仅本地会话标记；凭证不落盘）。 */
  static readonly HW_ACCOUNT_LOGGED_IN: string = 'hw_account_logged_in';
  /** 华为账号 OpenID（string，用于展示脱敏 ID 与云同步归属校验）。 */
  static readonly HW_ACCOUNT_OPEN_ID: string = 'hw_account_open_id';
  /** 华为账号 UnionID（string）。 */
  static readonly HW_ACCOUNT_UNION_ID: string = 'hw_account_union_id';
  /** 最近一次华为云备份时间（number，毫秒）。 */
  static readonly CLOUD_SYNC_LAST: string = 'cloud_sync_last';
  /** 最近选择的翻译厂商（string）：'bing'|'openai'|'deepseek'|'qwen'|'doubao'|'zhipu'|'custom'。 */
  static readonly API_PROVIDER: string = 'api_provider';
  /** OpenAI 兼容 API Key 的 AssetKeyStore alias（string，不是 preferences 键；与 translate-dev 共用）。 */
  static readonly OPENAI_KEY_ALIAS: string = 'openai_api_key';

  // ---------- starflow_reader：阅读与显示（与 reader-dev 契约一致） ----------
  /** 阅读背景（string），6 档：'black'|'nocturne'|'plum'|'deep'|'paper'|'white'；兼容旧值 'gray'。默认 'nocturne'。 */
  static readonly READER_BG: string = 'reader_bg';
  /** 阅读显示三态（string）：'trans' 仅译文 | 'orig' 仅原文 | 'raw' 纯原图。默认 'raw'。 */
  static readonly READER_MODE: string = 'reader_mode';
  /** 翻页动画（string）：'none' 无 | 'slide' 滑动 | 'cover' 封面叠放 | 'curl' 卷曲简化。默认 'slide'。 */
  static readonly READER_PAGE_ANIM: string = 'reader_page_anim';
  /** 页面文字方向（number）：0 横排 | 1 竖排（corerender RenderOrientation）。默认 1。 */
  static readonly RENDER_ORIENTATION: string = 'render_orientation';
  /** 竖排列序（number）：0 右到左 RTL | 1 左到右 LTR（corerender VerticalDirection）。默认 0。 */
  static readonly RENDER_DIRECTION: string = 'render_direction';
  /** 字号模式（number）：0 自动适配气泡 | 1 固定字号（corerender FontSizeMode）。默认 0。 */
  static readonly RENDER_FONT_MODE: string = 'render_font_mode';
  /** 固定字号（number，fp）：12–40，默认 16。仅在 render_font_mode=1 时生效。 */
  static readonly RENDER_FONT_SIZE: string = 'render_font_size';
  /** 行距百分比（number）：100–200，默认 130（阅读/小说排版行高）。 */
  static readonly READER_LINE_HEIGHT: string = 'reader_line_height';
  /** 页边距（number，vp）：0–32，默认 8。 */
  static readonly READER_MARGIN: string = 'reader_margin';
  /** 自动翻页间隔（number，秒）：3–60，默认 5；自动翻页开关在阅读器内单独控制。 */
  static readonly READER_AUTO_INTERVAL: string = 'reader_auto_interval';
  /** 白块合并（bool）：译文与原文区域重叠时合并成一个白块。默认 true。 */
  static readonly READER_WHITE_MERGE: string = 'reader_white_merge';
  /** 阅读流（string，reader-dev）：'rtl'|'ltr'|'vertical'|'webtoon'，默认 'rtl'。 */
  static readonly READER_FLOW: string = 'reader_flow';
  /** 阅读亮度（number，reader-dev）：20–100，默认 100。 */
  static readonly READER_BRIGHTNESS: string = 'reader_brightness';
  /** 阅读对比度（number，reader-dev）：50–150，默认 100。 */
  static readonly READER_CONTRAST: string = 'reader_contrast';
  /** 反色阅读（bool，reader-dev）：默认 false。 */
  static readonly READER_INVERT: string = 'reader_invert';
  /** 灰度阅读（bool，reader-dev）：默认 false。 */
  static readonly READER_GRAYSCALE: string = 'reader_grayscale';
  /** 阅读器 TOC 缩略图（bool，reader-dev）：默认 true。 */
  static readonly READER_TOC_THUMBNAIL: string = 'reader_toc_thumbnail';
  /** 小说行高（number，vp，novel-dev）：默认 30。 */
  static readonly NOVEL_LINE_HEIGHT: string = 'novel_line_height';
  /** 小说左右边距（number，vp，novel-dev）：默认 18。 */
  static readonly NOVEL_MARGIN: string = 'novel_margin';
  /** 小说默认显示模式（number，novel-dev）：0 译文 | 1 原文 | 2 双语，默认 1。 */
  static readonly NOVEL_DISPLAY_MODE: string = 'novel_display_mode';

  // ---------- starflow_translate：翻译与引擎 ----------
  /** 目标语言（string）：'zh'|'zh-TW'|'en'|'ja'|'ko'，默认 'zh'。 */
  static readonly TARGET_LANG: string = 'target_lang';
  /** 源语言（string）：'auto' 自动识别或具体语言码，默认 'auto'。 */
  static readonly SOURCE_LANG: string = 'source_lang';
  /** 文本翻译页源语言（string，translate-dev 契约）：'auto'|'ja'|'en'|'zh'|'ko'，默认 'auto'。 */
  static readonly TEXT_SOURCE_LANG: string = 'text_source_lang';
  /** 文本翻译页显式目标语言（string，translate-dev 契约，读取优先 target_lang）；设置页会同时写两个键保持一致。 */
  static readonly TEXT_TARGET_LANG: string = 'text_target_lang';
  /** 默认翻译引擎（number，EngineType）：0 必应 | 1 OpenAI 兼容 | 2 本地 llama，默认 0。 */
  static readonly ENGINE_TYPE: string = 'text_engine';
  /** OCR 语言（string，OcrLang）：'ja'|'en'|'ko'|'zh-CN'，默认 'ja'。 */
  static readonly OCR_LANG: string = 'ocr_lang';
  /** OpenAI 兼容 Base URL（string）。 */
  static readonly OPENAI_BASE_URL: string = 'openai_base_url';
  /** OpenAI 兼容模型名（string）。 */
  static readonly OPENAI_MODEL: string = 'openai_model';
  /** 对话/上下文翻译保留轮次（number）：5–20，默认 8。 */
  static readonly TRANSLATE_CONTEXT_TURNS: string = 'translate_context_turns';
  /** 思考模式（number）：0 关 | 1 自动 | 2 开，默认 1。 */
  static readonly TRANSLATE_THINKING_MODE: string = 'translate_thinking_mode';
  /** 采样温度（number）：0.0–2.0，默认 0.3。 */
  static readonly TRANSLATE_TEMPERATURE: string = 'translate_temperature';
  /** 漫画提示词覆盖（string，空=用内置模板）。 */
  static readonly PROMPT_MANGA: string = 'prompt_manga';
  /** 游戏提示词覆盖（string，空=用内置模板）。 */
  static readonly PROMPT_GAME: string = 'prompt_game';
  /** 小说提示词覆盖（string，空=用内置模板）。 */
  static readonly PROMPT_NOVEL: string = 'prompt_novel';
  /** 文本翻译提示词覆盖（string，空=用内置模板）。 */
  static readonly PROMPT_TEXT: string = 'prompt_text';

  // ---------- starflow_shelf：书架 ----------
  /** 书架视图（string）：'grid' 网格 | 'list' 列表，默认 'grid'。 */
  static readonly SHELF_VIEW_MODE: string = 'view_mode';
  /** 小说书架视图（string，novel-dev）：'grid'|'list'，默认 'grid'，存 starflow_shelf。 */
  static readonly NOVEL_VIEW_MODE: string = 'novel_view_mode';
}

/** 阅读设置快照（SettingsReadingPage 加载/保存用）。 */
export class ReaderSettings {
  bg: string = 'nocturne';
  mode: string = 'raw';
  pageAnim: string = 'slide';
  orientation: number = 1;
  direction: number = 0;
  fontSizeMode: number = 0;
  fontSize: number = 16;
  lineHeight: number = 130;
  margin: number = 8;
  autoInterval: number = 5;
  whiteMerge: boolean = true;
}

/** 翻译设置快照（SettingsTranslatePage 加载/保存用）。 */
export class TranslateSettings {
  targetLang: string = 'zh';
  engineType: number = 0;
  contextTurns: number = 8;
  thinkingMode: number = 1;
  temperature: number = 0.3;
}

/**
 * Preferences 统一封装。
 * 所有键按 scope 自动路由到 4 个 preferences 文件；写操作立即 flush。
 */
export class SettingsRepository {
  private static prefCache: Map<string, preferences.Preferences> = new Map();

  /** 取（并缓存）指定 preferences 文件句柄。 */
  private static async prefsOf(file: string): Promise<preferences.Preferences> {
    await AppEnv.ready();
    const cached = SettingsRepository.prefCache.get(file);
    if (cached !== undefined) {
      return cached;
    }
    const ctx = AppEnv.getInstance().getContext();
    const pref = await preferences.getPreferences(ctx, file);
    SettingsRepository.prefCache.set(file, pref);
    return pref;
  }

  /** key → preferences 文件（兼容既有三个文件）。 */
  private static fileOf(key: string): string {
    // novel_view_mode 虽然前缀是 novel_，但按 novel-dev 契约存 starflow_shelf。
    if (key === SettingsKeys.NOVEL_VIEW_MODE) {
      return FILE_SHELF;
    }
    if (key.startsWith('reader_') || key.startsWith('render_') || key.startsWith('novel_')) {
      return FILE_READER;
    }
    if (key === SettingsKeys.TARGET_LANG || key === SettingsKeys.SOURCE_LANG
      || key === SettingsKeys.OCR_LANG || key === SettingsKeys.ENGINE_TYPE) {
      return FILE_TRANSLATE;
    }
    if (key.startsWith('openai_') || key.startsWith('translate_') || key.startsWith('prompt_')
      || key.startsWith('text_')) {
      return FILE_TRANSLATE;
    }
    if (key === SettingsKeys.SHELF_VIEW_MODE || key.startsWith('shelf_')) {
      return FILE_SHELF;
    }
    return FILE_SETTINGS;
  }

  /** 目标 preferences 文件名（诊断/测试用）。 */
  static fileNameFor(key: string): string {
    return SettingsRepository.fileOf(key);
  }

  // ---------- 通用读 ----------

  /** 读 bool；缺失/类型异常回退 def。 */
  static async getBool(key: string, def: boolean): Promise<boolean> {
    try {
      const pref = await SettingsRepository.prefsOf(SettingsRepository.fileOf(key));
      const raw = pref.getSync(key, def);
      if (typeof raw === 'boolean') {
        return raw;
      }
      if (typeof raw === 'string') {
        return raw === 'true' || raw === '1';
      }
      if (typeof raw === 'number') {
        return raw !== 0;
      }
      return def;
    } catch (e) {
      Log.warn(TAG, `getBool(${key}) failed: ${e}`);
      return def;
    }
  }

  /** 读 string；数字会转字符串，缺失回退 def。 */
  static async getString(key: string, def: string): Promise<string> {
    try {
      const pref = await SettingsRepository.prefsOf(SettingsRepository.fileOf(key));
      const raw = pref.getSync(key, def);
      if (typeof raw === 'string') {
        return raw;
      }
      if (typeof raw === 'number') {
        return `${raw}`;
      }
      if (typeof raw === 'boolean') {
        return raw ? 'true' : 'false';
      }
      return def;
    } catch (e) {
      Log.warn(TAG, `getString(${key}) failed: ${e}`);
      return def;
    }
  }

  /** 读 number；字符串数字会解析，缺失回退 def。 */
  static async getNumber(key: string, def: number): Promise<number> {
    try {
      const pref = await SettingsRepository.prefsOf(SettingsRepository.fileOf(key));
      const raw = pref.getSync(key, def);
      if (typeof raw === 'number') {
        return raw;
      }
      if (typeof raw === 'string') {
        const n = Number.parseFloat(raw);
        return Number.isNaN(n) ? def : n;
      }
      return def;
    } catch (e) {
      Log.warn(TAG, `getNumber(${key}) failed: ${e}`);
      return def;
    }
  }

  // ---------- 通用写 ----------

  /** 写值（bool/string/number），立即落盘；失败仅日志，不打断 UI。 */
  static async set(key: string, value: boolean | string | number): Promise<boolean> {
    try {
      const pref = await SettingsRepository.prefsOf(SettingsRepository.fileOf(key));
      if (typeof value === 'boolean') {
        pref.putSync(key, value);
      } else if (typeof value === 'number') {
        pref.putSync(key, value);
      } else {
        pref.putSync(key, value);
      }
      await pref.flush();
      return true;
    } catch (e) {
      Log.warn(TAG, `set(${key}) failed: ${e}`);
      return false;
    }
  }

  /** 删除键（回退默认值）。 */
  static async remove(key: string): Promise<void> {
    try {
      const pref = await SettingsRepository.prefsOf(SettingsRepository.fileOf(key));
      pref.deleteSync(key);
      await pref.flush();
    } catch (e) {
      Log.warn(TAG, `remove(${key}) failed: ${e}`);
    }
  }

  // ---------- 阅读设置快照 ----------

  /** 一次性加载阅读设置（缺省回退 ReaderSettings 默认值）。 */
  static async loadReaderSettings(): Promise<ReaderSettings> {
    const s = new ReaderSettings();
    s.bg = SettingsRepository.normalizeBg(await SettingsRepository.getString(SettingsKeys.READER_BG, s.bg));
    s.mode = SettingsRepository.normalizeMode(await SettingsRepository.getString(SettingsKeys.READER_MODE, s.mode));
    s.pageAnim = SettingsRepository.normalizeAnim(
      await SettingsRepository.getString(SettingsKeys.READER_PAGE_ANIM, s.pageAnim));
    s.orientation = await SettingsRepository.getNumber(SettingsKeys.RENDER_ORIENTATION, s.orientation);
    s.direction = await SettingsRepository.getNumber(SettingsKeys.RENDER_DIRECTION, s.direction);
    s.fontSizeMode = await SettingsRepository.getNumber(SettingsKeys.RENDER_FONT_MODE, s.fontSizeMode);
    s.fontSize = await SettingsRepository.getNumber(SettingsKeys.RENDER_FONT_SIZE, s.fontSize);
    s.lineHeight = await SettingsRepository.getNumber(SettingsKeys.READER_LINE_HEIGHT, s.lineHeight);
    s.margin = await SettingsRepository.getNumber(SettingsKeys.READER_MARGIN, s.margin);
    s.autoInterval = await SettingsRepository.getNumber(SettingsKeys.READER_AUTO_INTERVAL, s.autoInterval);
    s.whiteMerge = await SettingsRepository.getBool(SettingsKeys.READER_WHITE_MERGE, s.whiteMerge);
    return s;
  }

  /** 保存整份阅读设置（逐键写入，任意一键失败不阻断其余）。 */
  static async saveReaderSettings(s: ReaderSettings): Promise<void> {
    await SettingsRepository.set(SettingsKeys.READER_BG, s.bg);
    await SettingsRepository.set(SettingsKeys.READER_MODE, s.mode);
    await SettingsRepository.set(SettingsKeys.READER_PAGE_ANIM, s.pageAnim);
    await SettingsRepository.set(SettingsKeys.RENDER_ORIENTATION, s.orientation);
    await SettingsRepository.set(SettingsKeys.RENDER_DIRECTION, s.direction);
    await SettingsRepository.set(SettingsKeys.RENDER_FONT_MODE, s.fontSizeMode);
    await SettingsRepository.set(SettingsKeys.RENDER_FONT_SIZE, s.fontSize);
    await SettingsRepository.set(SettingsKeys.READER_LINE_HEIGHT, s.lineHeight);
    await SettingsRepository.set(SettingsKeys.READER_MARGIN, s.margin);
    await SettingsRepository.set(SettingsKeys.READER_AUTO_INTERVAL, s.autoInterval);
    await SettingsRepository.set(SettingsKeys.READER_WHITE_MERGE, s.whiteMerge);
  }

  // ---------- 翻译设置快照 ----------

  /** 一次性加载翻译设置。 */
  static async loadTranslateSettings(): Promise<TranslateSettings> {
    const s = new TranslateSettings();
    // translate-dev 契约：text_target_lang（文本页显式选择）优先于 target_lang。
    const textTarget = await SettingsRepository.getString(SettingsKeys.TEXT_TARGET_LANG, '');
    s.targetLang = textTarget.length > 0
      ? textTarget
      : await SettingsRepository.getString(SettingsKeys.TARGET_LANG, s.targetLang);
    s.engineType = await SettingsRepository.getNumber(SettingsKeys.ENGINE_TYPE, s.engineType);
    s.contextTurns = await SettingsRepository.getNumber(SettingsKeys.TRANSLATE_CONTEXT_TURNS, s.contextTurns);
    s.thinkingMode = await SettingsRepository.getNumber(SettingsKeys.TRANSLATE_THINKING_MODE, s.thinkingMode);
    s.temperature = await SettingsRepository.getNumber(SettingsKeys.TRANSLATE_TEMPERATURE, s.temperature);
    return s;
  }

  /** 保存整份翻译设置。 */
  static async saveTranslateSettings(s: TranslateSettings): Promise<void> {
    await SettingsRepository.set(SettingsKeys.TARGET_LANG, s.targetLang);
    await SettingsRepository.set(SettingsKeys.ENGINE_TYPE, s.engineType);
    await SettingsRepository.set(SettingsKeys.TRANSLATE_CONTEXT_TURNS, s.contextTurns);
    await SettingsRepository.set(SettingsKeys.TRANSLATE_THINKING_MODE, s.thinkingMode);
    await SettingsRepository.set(SettingsKeys.TRANSLATE_TEMPERATURE, s.temperature);
  }

  // ---------- 引导 ----------

  /** 引导是否已完成（默认为 false → 首次启动展示引导）。 */
  static async isOnboardingDone(): Promise<boolean> {
    return SettingsRepository.getBool(SettingsKeys.ONBOARDING_DONE, false);
  }

  /** 标记引导完成（Lead 首启接入用；完成/跳过都调用）。 */
  static async setOnboardingDone(): Promise<void> {
    await SettingsRepository.set(SettingsKeys.ONBOARDING_DONE, true);
  }

  /** 兼容别名。 */
  static async markOnboardingDone(): Promise<void> {
    await SettingsRepository.setOnboardingDone();
  }

  // ---------- 规范化 ----------

  /** 背景 id 白名单：6 档新值；旧值 gray 归一到默认 nocturne（避免设置页无选中项）。 */
  static normalizeBg(raw: string): string {
    if (raw === 'gray') {
      return 'nocturne';
    }
    if (raw === 'black' || raw === 'nocturne' || raw === 'plum' || raw === 'deep'
      || raw === 'paper' || raw === 'white') {
      return raw;
    }
    return 'nocturne';
  }

  static normalizeMode(raw: string): string {
    if (raw === 'trans' || raw === 'orig' || raw === 'raw') {
      return raw;
    }
    return 'raw';
  }

  static normalizeAnim(raw: string): string {
    if (raw === 'none' || raw === 'slide' || raw === 'cover' || raw === 'curl') {
      return raw;
    }
    return 'slide';
  }
}
