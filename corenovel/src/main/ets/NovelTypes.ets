/**
 * corenovel 公共类型定义。
 * 与 coremodel 的 NovelFormat 数值保持一致：TXT=0 / EPUB=1 / ZIP_HTML=2。
 */

/** 解析出的单章（content 为纯文本，段间以空行分隔）。 */
export interface ParsedChapter {
  title: string;
  content: string;
  /** 在原始全文中的字符起始下标（仅 TXT 有意义；EPUB/ZIP 为 0）。 */
  startOffset: number;
}

/** 解析器输出的一本书。 */
export interface ParsedNovel {
  title: string;
  /** NovelTextFormat 数值。 */
  format: number;
  chapters: Array<ParsedChapter>;
  /** 所有章节正文按顺序拼接（用于预览/兜底分页）。 */
  plainText: string;
  /** 作者（EPUB metadata 可提供，其余为空）。 */
  author: string;
}

/** 分页后的单页（start/end 为章节显示文本的 UTF-16 下标）。 */
export interface NovelPage {
  pageIndex: number;
  start: number;
  end: number;
  text: string;
}

/** 小说文本格式（与 coremodel NovelFormat 数值对齐）。 */
export class NovelTextFormat {
  static readonly TXT: number = 0;
  static readonly EPUB: number = 1;
  static readonly ZIP_HTML: number = 2;
}

/** 正文显示三态：仅译文 / 仅原文 / 双语（原文+译文）。 */
export enum NovelDisplayMode {
  TRANSLATED = 0,
  ORIGINAL = 1,
  BILINGUAL = 2
}

/** 编码探测结果。lossy 为 true 表示有无法解码的字节被替换，UI 应提示用户。 */
export class DecodeResult {
  text: string = '';
  encoding: string = 'utf-8';
  lossy: boolean = false;
}
