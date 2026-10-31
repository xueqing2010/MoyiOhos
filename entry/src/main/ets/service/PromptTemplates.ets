/**
 * 提示词模板中心（stage 2 / S107）—— 漫画 / 小说 / 文本 / 对话 四套模板。
 *
 *  · 目标语言注入：%TARGET_LANG% / %SOURCE_LANG% / %TEXT% 占位符
 *  · 思考模式三态附加约束（off / auto / on；auto 只对推理模型追加）
 *  · 对话上下文轮次 5–20 收敛
 *  · 用户自定义提示词覆盖（prompt_manga / prompt_novel / prompt_text / prompt_chat）
 *
 * 本类不读写偏好：覆盖串由调用方传入，便于单测与 reader / novel 模块复用。
 */
import {
  ChatMessage,
  LangCatalog,
  ThinkingMode,
  assistantMessage,
  isReasoningModel,
  normalizeThinkingMode,
  systemMessage,
  userMessage
} from 'coretranslate';
import { Log } from 'commons';

const TAG = 'PromptTemplates';

/** Which prompt family to build. */
export enum PromptKind {
  /** 漫画：编号批量 + 续写格式控制 */
  MANGA = 0,
  /** 小说：段落对齐 */
  NOVEL = 1,
  /** 文本翻译页：单段 */
  TEXT = 2,
  /** 对话翻译：多轮上下文助手 */
  CHAT = 3
}

/** One completed (user, assistant) exchange kept as chat context. */
export interface ContextTurn {
  user: string;
  assistant: string;
}

/** Placeholder tokens users may keep in their edited prompts. */
const PH_TARGET: string = '%TARGET_LANG%';
const PH_SOURCE: string = '%SOURCE_LANG%';
const PH_TEXT: string = '%TEXT%';

/** 文本翻译（单段）系统提示词。 */
const TEXT_SYSTEM: string = '你是专业翻译引擎。将用户提供的文本翻译为%TARGET_LANG%。\n' +
  '规则：\n' +
  '1. 只输出译文，不输出解释、标注、引号或任何附加内容\n' +
  '2. 完整保留原文的换行、段落与标点风格（含省略号、引号、破折号）\n' +
  '3. 译文自然流畅，符合目标语言的表达习惯\n' +
  '4. 人名、地名、作品名等专有名词保留原文或使用通用译名\n' +
  '5. 若原文已经是%TARGET_LANG%，原样返回';

/**
 * 漫画系统提示词 —— 续写格式控制是硬约束：
 * 编号列表、一句一译、不解释、保留标点与省略号。
 */
const MANGA_SYSTEM: string = '你是漫画翻译引擎。将用户给出的编号文本逐条翻译为%TARGET_LANG%。\n' +
  '输出格式（强约束，必须全部遵守）：\n' +
  '1. 只输出编号列表，每条占一行，格式严格为：[序号] 译文\n' +
  '2. 序号与输入一一对应，不合并、不拆分、不增删条目；漏译的条目保留原编号与原文\n' +
  '3. 不要输出任何解释、注释、标题、JSON 或 markdown 代码块\n' +
  '4. 保留原文的标点与省略号（…… / ... / 、— / ！？），标点数量与位置尽量一致\n' +
  '5. 译文口语化、简短，符合漫画对话语气；象声词按%TARGET_LANG%习惯改写\n' +
  '6. 若某条已经是%TARGET_LANG%，原样返回该条';

/** 小说系统提示词 —— 段落对齐优先，不合并/拆分段落。 */
const NOVEL_SYSTEM: string = '你是小说翻译引擎。将用户提供的正文按段落翻译为%TARGET_LANG%。\n' +
  '规则：\n' +
  '1. 只输出译文，不输出解释、标注、标题或章节名\n' +
  '2. 保持原有的段落划分与空行，不合并、不拆分段落\n' +
  '3. 保留原文标点、省略号、破折号与引号风格\n' +
  '4. 人称、称谓、术语前后一致；专有名词首次出现时保留原文\n' +
  '5. 若原文已经是%TARGET_LANG%，原样返回';

/** 对话翻译系统提示词 —— 多轮上下文、术语与语气一致。 */
const CHAT_SYSTEM: string = '你是「墨译」的翻译助手，帮助用户在%TARGET_LANG%与其它语言之间翻译、解释与润色。\n' +
  '规则：\n' +
  '1. 回答使用%TARGET_LANG%，简洁、准确、口语化\n' +
  '2. 需要给出译文时只给译文本体，不要附加解释；用户明确要求解释时才解释\n' +
  '3. 保持多轮上下文一致：人称、称谓、术语、语气与前面几轮对齐\n' +
  '4. 用户以「翻译：」开头时，直接把后面的内容翻译为%TARGET_LANG%';

/** Thinking-mode addenda (appended to the system prompt). */
const THINK_OFF: string = '\n\n思考模式：关闭。不要进行任何思考或分析，直接给出最终结果。';
const THINK_AUTO_REASONING: string =
  '\n\n思考提示：如确需推理，最多用一句话简述，随后立即给出最终结果；不要输出长篇思考过程。';
const THINK_ON: string =
  '\n\n思考提示：可以充分推理，但最终输出只包含结果本身，不要输出思考过程或标注。';

/**
 * Prompt template centre.
 *
 * All builders are static & pure: persistence (which override string to use)
 * stays in TextTranslateViewModel. Every template is Chinese UI text; the
 * injected language names are English so the model cannot misread a code.
 */
export class PromptTemplates {
  /** 对话上下文轮次下限（settings 契约 5-20）。 */
  static readonly CONTEXT_MIN: number = 5;
  /** 对话上下文轮次上限。 */
  static readonly CONTEXT_MAX: number = 20;
  /** 默认上下文轮次。 */
  static readonly CONTEXT_DEFAULT: number = 8;

  /** Clamp a persisted context-round value into 5..20. */
  static clampRounds(value: number): number {
    if (Number.isNaN(value)) {
      return PromptTemplates.CONTEXT_DEFAULT;
    }
    if (value < PromptTemplates.CONTEXT_MIN) {
      return PromptTemplates.CONTEXT_MIN;
    }
    if (value > PromptTemplates.CONTEXT_MAX) {
      return PromptTemplates.CONTEXT_MAX;
    }
    return Math.round(value);
  }

  /** Preference key holding the user's override for a prompt family. */
  static overrideKey(kind: PromptKind): string {
    if (kind === PromptKind.MANGA) {
      return 'prompt_manga';
    }
    if (kind === PromptKind.NOVEL) {
      return 'prompt_novel';
    }
    if (kind === PromptKind.CHAT) {
      return 'prompt_chat';
    }
    return 'prompt_text';
  }

  /** Built-in template before placeholder substitution / thinking addenda. */
  static builtinSystem(kind: PromptKind): string {
    if (kind === PromptKind.MANGA) {
      return MANGA_SYSTEM;
    }
    if (kind === PromptKind.NOVEL) {
      return NOVEL_SYSTEM;
    }
    if (kind === PromptKind.CHAT) {
      return CHAT_SYSTEM;
    }
    return TEXT_SYSTEM;
  }

  /** Replace %TARGET_LANG% / %SOURCE_LANG% / %TEXT% placeholders. */
  static applyPlaceholders(template: string, targetLang: string, sourceLang: string,
    text: string): string {
    let out = template;
    out = out.replace(PH_TARGET, LangCatalog.promptName(targetLang));
    out = out.replace(PH_SOURCE, LangCatalog.promptName(sourceLang));
    out = out.replace(PH_TEXT, text);
    return out;
  }

  /**
   * Final system prompt: template (override wins) -> placeholders -> thinking
   * addendum. Safe to put into messages[0].
   */
  static systemPrompt(kind: PromptKind, targetLang: string, sourceLang: string,
    thinking: ThinkingMode, model: string, override?: string): string {
    const hasOverride = override !== undefined && override.trim().length > 0;
    const base = hasOverride ? (override as string) : PromptTemplates.builtinSystem(kind);
    let out = PromptTemplates.applyPlaceholders(base, targetLang, sourceLang, '');
    out += PromptTemplates.thinkingHint(kind, thinking, model);
    Log.info(TAG, 'system prompt: kind=' + kind + ' target=' + targetLang
      + ' thinking=' + thinking + ' override=' + hasOverride + ' chars=' + out.length);
    return out;
  }

  /** Thinking addendum for a family (CHAT keeps answers conversational). */
  static thinkingHint(kind: PromptKind, thinking: ThinkingMode, model: string): string {
    const mode = normalizeThinkingMode(thinking as number);
    if (mode === ThinkingMode.OFF) {
      return THINK_OFF;
    }
    if (mode === ThinkingMode.ON) {
      return THINK_ON;
    }
    if (kind === PromptKind.CHAT) {
      return '';
    }
    return isReasoningModel(model) ? THINK_AUTO_REASONING : '';
  }

  /**
   * User message for a single-block family (text / novel / chat).
   * The body is wrapped in markers so content inside the source cannot
   * rewrite the rules above.
   */
  static userPrompt(kind: PromptKind, text: string, sourceLang: string, targetLang: string): string {
    if (kind === PromptKind.CHAT) {
      return text;
    }
    const from = LangCatalog.promptName(sourceLang);
    const to = LangCatalog.promptName(targetLang);
    const fromLine = sourceLang === 'auto' ? '（原文语言自动检测）' : ('原文语言：' + from);
    return fromLine + '\n目标语言：' + to + '\n\n【待翻译文本开始】\n' + text + '\n【待翻译文本结束】';
  }

  /** Numbered batch body for manga pages: "[1] line" per OCR line. */
  static numberedText(texts: Array<string>): string {
    const out: Array<string> = [];
    for (let i = 0; i < texts.length; i++) {
      out.push('[' + (i + 1) + '] ' + texts[i]);
    }
    return out.join('\n');
  }

  /** Manga user message (numbered list; formatting rules live in system). */
  static mangaUserPrompt(texts: Array<string>, sourceLang: string, targetLang: string): string {
    const fromLine = sourceLang === 'auto'
      ? '（原文语言自动检测）'
      : ('原文语言：' + LangCatalog.promptName(sourceLang));
    return fromLine + '\n目标语言：' + LangCatalog.promptName(targetLang) + '\n\n'
      + PromptTemplates.numberedText(texts);
  }

  /** Full messages for text translation (single block, streaming). */
  static textMessages(text: string, sourceLang: string, targetLang: string,
    thinking: ThinkingMode, model: string, override?: string): Array<ChatMessage> {
    const out: Array<ChatMessage> = [];
    out.push(systemMessage(PromptTemplates.systemPrompt(PromptKind.TEXT, targetLang,
      sourceLang, thinking, model, override)));
    out.push(userMessage(PromptTemplates.userPrompt(PromptKind.TEXT, text, sourceLang, targetLang)));
    return out;
  }

  /** Full messages for manga page translation (numbered batch). */
  static mangaMessages(texts: Array<string>, sourceLang: string, targetLang: string,
    thinking: ThinkingMode, model: string, override?: string): Array<ChatMessage> {
    const out: Array<ChatMessage> = [];
    out.push(systemMessage(PromptTemplates.systemPrompt(PromptKind.MANGA, targetLang,
      sourceLang, thinking, model, override)));
    out.push(userMessage(PromptTemplates.mangaUserPrompt(texts, sourceLang, targetLang)));
    return out;
  }

  /** Full messages for novel paragraph translation. */
  static novelMessages(text: string, sourceLang: string, targetLang: string,
    thinking: ThinkingMode, model: string, override?: string): Array<ChatMessage> {
    const out: Array<ChatMessage> = [];
    out.push(systemMessage(PromptTemplates.systemPrompt(PromptKind.NOVEL, targetLang,
      sourceLang, thinking, model, override)));
    out.push(userMessage(PromptTemplates.userPrompt(PromptKind.NOVEL, text, sourceLang, targetLang)));
    return out;
  }

  /**
   * 对话 messages: system + last `rounds` exchanges + current input.
   * Rounds are clamped to 5..20; history is trimmed oldest-first so the most
   * recent exchange always survives.
   */
  static chatMessages(turns: Array<ContextTurn>, input: string, targetLang: string,
    thinking: ThinkingMode, model: string, rounds: number, override?: string): Array<ChatMessage> {
    const out: Array<ChatMessage> = [];
    out.push(systemMessage(PromptTemplates.systemPrompt(PromptKind.CHAT, targetLang,
      'auto', thinking, model, override)));
    const keep = PromptTemplates.clampRounds(rounds);
    const start = turns.length > keep ? turns.length - keep : 0;
    for (let i = start; i < turns.length; i++) {
      const t = turns[i];
      if (t.user.length > 0 && t.assistant.length > 0) {
        out.push(userMessage(t.user));
        out.push(assistantMessage(t.assistant));
      }
    }
    out.push(userMessage(input));
    return out;
  }

  /** Single-shot messages for the "测试连接" short translation. */
  static simpleMessages(text: string, targetLang: string): Array<ChatMessage> {
    const out: Array<ChatMessage> = [];
    out.push(systemMessage(PromptTemplates.applyPlaceholders(TEXT_SYSTEM, targetLang, 'auto', '')));
    out.push(userMessage(text));
    return out;
  }
}
