import { ParsedChapter } from './NovelTypes';

/** 一行章节标记：起始字符下标 + 标题。 */
export class ChapterMark {
  start: number = 0;
  title: string = '';
}

/**
 * TXT 分章器（对齐上游 TxtChapterSplitter 的启发式语义）：
 * - 第X章/节/话/回/卷/篇/部、序章/楔子/番外等特殊章名、Chapter N、数字标题、方括号卷章标签；
 * - 首个标记之前的内容单独成「前言」，不丢字；
 * - 一个标记都没有时按固定长度切（默认 4000 字），在段落边界处断开。
 *
 * 正则一律锚定行首，避免正文里「他在第 3 章看到过」这类句子被当成标题。
 */
export class ChapterSplitter {
  /** 章节标题最长字符数，超出视为正文。 */
  static readonly MAX_TITLE_LEN: number = 40;
  /** 无章节标记时的固定切片长度。 */
  static readonly FIXED_CHUNK_SIZE: number = 4000;
  static readonly PREFACE_TITLE: string = '前言';

  private static readonly PATTERN_CHAPTER: RegExp =
    /^\s*第\s*[零一二三四五六七八九十百千万两0-9０-９]+\s*[章节節話话回卷篇部]\s*[：:、.．\-—]?\s*.{0,30}$/;
  private static readonly PATTERN_SPECIAL: RegExp =
    /^\s*(序章|序言|序|楔子|引子|前言|后记|後記|尾声|尾聲|终章|終章|结局|結局|番外)\s*[：:、.．\-—]?\s*.{0,30}$/;
  private static readonly PATTERN_CHAPTER_EN: RegExp =
    /^\s*(chapter|part)\b(\s+[0-9ivxlcdm]+)?\s*[：:、.．\-—]?\s*.{0,30}$/i;
  private static readonly PATTERN_NUMBER: RegExp =
    /^\s*\d{1,4}\s*[.、．:：]\s*\S.{0,30}$/;
  private static readonly PATTERN_NUMBER_SPACE: RegExp =
    /^\s*\d{1,4}\s+\S.{0,30}$/;
  private static readonly PATTERN_BRACKET: RegExp =
    /^\s*[【\[](.{1,30})[】\]]\s*$/;
  private static readonly PATTERN_BRACKET_HINT: RegExp =
    /[卷章节節回话話篇部]|序|楔|番外|后记|後記|尾声|尾聲|终章|終章|结局|結局|引子|前言|장|절|권|화|회|편|[Cc]hapter/;
  private static readonly PROSE_PUNCT: string = '。！？，、；：…';

  /** 把整本纯文本切成章节。（换行需已归一化为 \n） */
  static split(text: string, fixedChunkSize: number = ChapterSplitter.FIXED_CHUNK_SIZE): Array<ParsedChapter> {
    const chapters: Array<ParsedChapter> = [];
    if (text === undefined || text === null || text.trim().length === 0) {
      return chapters;
    }
    const marks = ChapterSplitter.findChapterStarts(text);
    if (marks.length === 0) {
      return ChapterSplitter.splitFixed(text, fixedChunkSize);
    }
    if (marks[0].start > 0) {
      const preface = text.substring(0, marks[0].start).trim();
      if (preface.length > 0) {
        const chapter: ParsedChapter = {
          title: ChapterSplitter.PREFACE_TITLE,
          content: ChapterSplitter.normalizeBody(preface),
          startOffset: 0
        };
        chapters.push(chapter);
      }
    }
    for (let i = 0; i < marks.length; i++) {
      const start = marks[i].start;
      const end = i + 1 < marks.length ? marks[i + 1].start : text.length;
      const bodyStart = ChapterSplitter.bodyStartOf(text, start, end);
      const body = text.substring(bodyStart, end).trim();
      const chapter: ParsedChapter = {
        title: marks[i].title,
        content: ChapterSplitter.normalizeBody(body),
        startOffset: bodyStart
      };
      chapters.push(chapter);
    }
    return chapters;
  }

  /** 找出所有章节起始行。 */
  static findChapterStarts(text: string): Array<ChapterMark> {
    const marks: Array<ChapterMark> = [];
    let lineStart = 0;
    while (lineStart <= text.length) {
      let lineEnd = text.indexOf('\n', lineStart);
      if (lineEnd < 0) {
        lineEnd = text.length;
      }
      const line = text.substring(lineStart, lineEnd).trim();
      if (line.length > 0 && line.length <= ChapterSplitter.MAX_TITLE_LEN) {
        const title = ChapterSplitter.matchTitle(line);
        if (title.length > 0) {
          const mark = new ChapterMark();
          mark.start = lineStart;
          mark.title = title;
          marks.push(mark);
        }
      }
      if (lineEnd >= text.length) {
        break;
      }
      lineStart = lineEnd + 1;
    }
    return marks;
  }

  // ---------- 内部实现 ----------

  private static matchTitle(line: string): string {
    if (ChapterSplitter.PATTERN_CHAPTER.test(line)) {
      return ChapterSplitter.cleanTitle(line);
    }
    if (ChapterSplitter.PATTERN_SPECIAL.test(line)) {
      return ChapterSplitter.cleanTitle(line);
    }
    if (ChapterSplitter.PATTERN_CHAPTER_EN.test(line)) {
      return ChapterSplitter.cleanTitle(line);
    }
    // 数字标题：要求短行且不含句读，避免把正文的「2024 年…」误判成标题。
    if ((ChapterSplitter.PATTERN_NUMBER.test(line) || ChapterSplitter.PATTERN_NUMBER_SPACE.test(line))
      && !ChapterSplitter.hasProsePunct(line)) {
      return ChapterSplitter.cleanTitle(line);
    }
    const bracket = ChapterSplitter.matchBracketTitle(line);
    if (bracket.length > 0) {
      return bracket;
    }
    return '';
  }

  private static matchBracketTitle(line: string): string {
    const matched = ChapterSplitter.PATTERN_BRACKET.exec(line);
    if (matched === null) {
      return '';
    }
    const open = line.trim().charAt(0);
    const close = line.trim().charAt(line.trim().length - 1);
    const paired = (open === '【' && close === '】') || (open === '[' && close === ']');
    if (!paired) {
      return '';
    }
    const inner = matched.length > 1 ? matched[1] : '';
    if (inner.length === 0 || ChapterSplitter.hasProsePunct(inner)) {
      return '';
    }
    if (!ChapterSplitter.PATTERN_BRACKET_HINT.test(inner)) {
      return '';
    }
    return ChapterSplitter.cleanTitle(line);
  }

  private static hasProsePunct(line: string): boolean {
    for (let i = 0; i < line.length; i++) {
      if (ChapterSplitter.PROSE_PUNCT.indexOf(line.charAt(i)) >= 0) {
        return true;
      }
    }
    return false;
  }

  private static cleanTitle(line: string): string {
    let out = line.trim();
    while (out.indexOf('  ') >= 0) {
      out = out.replace('  ', ' ');
    }
    return out;
  }

  private static bodyStartOf(text: string, start: number, end: number): number {
    const nl = text.indexOf('\n', start);
    if (nl < 0 || nl >= end) {
      return end;
    }
    return nl + 1;
  }

  /** 一章正文归一化：一行一段 → 段间空行（对齐上游 linesToParagraphs）。 */
  private static normalizeBody(body: string): string {
    const normalized = body.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const lines = normalized.split('\n');
    const paragraphs: Array<string> = [];
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length > 0) {
        paragraphs.push(line);
      }
    }
    return paragraphs.join('\n\n');
  }

  /** 无章节标记：按固定长度切，尽量在段落边界断开。 */
  private static splitFixed(text: string, chunkSize: number): Array<ParsedChapter> {
    const chapters: Array<ParsedChapter> = [];
    const size = chunkSize > 200 ? chunkSize : 200;
    let start = 0;
    let index = 0;
    while (start < text.length) {
      let end = start + size;
      if (end >= text.length) {
        end = text.length;
      } else {
        // 在切片末尾 1/4 范围内找最近的换行，避免把段落拦腰截断。
        const searchFrom = start + Math.floor(size * 0.75);
        const nl = text.indexOf('\n', searchFrom);
        if (nl > 0 && nl < start + size + 200) {
          end = nl;
        }
      }
      const chunk = text.substring(start, end).trim();
      if (chunk.length > 0) {
        index++;
        const chapter: ParsedChapter = {
          title: '第' + index + '节',
          content: ChapterSplitter.normalizeBody(chunk),
          startOffset: start
        };
        chapters.push(chapter);
      }
      start = end;
      if (end >= text.length) {
        break;
      }
      while (start < text.length && text.charAt(start) === '\n') {
        start++;
      }
    }
    return chapters;
  }
}
