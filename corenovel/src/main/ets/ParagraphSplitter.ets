import { NovelDisplayMode } from './NovelTypes';

/** 一个可翻译段落。 */
export class NovelParagraph {
  index: number = 0;
  text: string = '';
}

/**
 * 章节正文 → 段落（翻译与显示三态的唯一来源）。
 *
 * 对齐上游 NovelParagraphSplitter 的确定性要求：只做顺序扫描，同一文本两次切分
 * 必须给出相同的 index，否则译文会错位且难以发现。
 */
export class ParagraphSplitter {
  /** 短于此长度的段落不翻译（短对白、分隔符）。 */
  static readonly MIN_TRANSLATE_LENGTH: number = 4;

  /** 切段：优先按空行，退回按单换行（兼容未归一化的 txt）。 */
  static split(content: string): Array<NovelParagraph> {
    const out: Array<NovelParagraph> = [];
    if (content === undefined || content === null || content.trim().length === 0) {
      return out;
    }
    const normalized = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    let blocks: Array<string> = normalized.split('\n\n');
    if (blocks.length <= 1) {
      blocks = normalized.split('\n');
    }
    for (let i = 0; i < blocks.length; i++) {
      const text = blocks[i].trim();
      if (text.length === 0) {
        continue;
      }
      const paragraph = new NovelParagraph();
      paragraph.index = out.length;
      paragraph.text = text;
      out.push(paragraph);
    }
    return out;
  }

  /** 译文内容 → 段落数组（与 split 结果的 index 对齐）。 */
  static splitTranslated(translatedContent: string): Array<string> {
    const out: Array<string> = [];
    if (translatedContent === undefined || translatedContent === null || translatedContent.length === 0) {
      return out;
    }
    const normalized = translatedContent.replace(/\r\n/g, '\n');
    const blocks = normalized.split('\n\n');
    for (let i = 0; i < blocks.length; i++) {
      out.push(blocks[i].trim());
    }
    return out;
  }

  /** 段落数组 → 存储字符串。 */
  static join(paragraphs: Array<string>): string {
    const cleaned: Array<string> = [];
    for (let i = 0; i < paragraphs.length; i++) {
      cleaned.push(paragraphs[i]);
    }
    return cleaned.join('\n\n');
  }

  /**
   * 显示文本：分页与绘制只认这一份输出。
   * - 未翻译段落任何模式下都显示原文（避免用户以为丢内容）；
   * - 双语 = 原文 + 换行 + 译文（共用同一套字符区间，不接受两套排版）。
   */
  static displayText(original: string, translatedContent: string | undefined,
    mode: NovelDisplayMode): string {
    const paragraphs = ParagraphSplitter.split(original);
    if (paragraphs.length === 0) {
      return '';
    }
    const translated = translatedContent === undefined ? new Array<string>()
      : ParagraphSplitter.splitTranslated(translatedContent);
    const lines: Array<string> = [];
    for (let i = 0; i < paragraphs.length; i++) {
      const src = paragraphs[i].text;
      const trans = i < translated.length ? translated[i] : '';
      if (mode === NovelDisplayMode.ORIGINAL || trans.length === 0) {
        lines.push(src);
      } else if (mode === NovelDisplayMode.BILINGUAL) {
        lines.push(src + '\n' + trans);
      } else {
        lines.push(trans);
      }
    }
    return lines.join('\n\n');
  }
}
