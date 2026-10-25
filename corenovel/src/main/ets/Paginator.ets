import { NovelPage } from './NovelTypes';

/**
 * 字符网格分页器（对齐上游 NovelPaginator 的语义）：
 * 按字符宽度/行高估算排版，CJK 与空白分别在宽处/窄处断行，不拆代理对，
 * 行首不留收尾标点（把标点拉回上一行/上一页）。
 *
 * 可选传入 measure 回调（字体测量）：默认按字号估算；阅读器可注入更精确的测量函数。
 *
 * 修复记录：上一版 skipLeadingPunctuation 在「页第一行」上把 cursor 直接回退到
 * pageStart 之后第一个非标点字符，导致整页内容被推到下一页（表现为页面只有一两个字符）。
 * 现在改为把「下一行/下一页开头的收尾标点」并入当前行/当前页，正文一个字都不丢。
 */
export class Paginator {
  /** 收尾标点：不允许出现在行首/页首。 */
  private static readonly CLOSING_PUNCT: string = '，。、；：？！）》」』】”’…—,.!?)]}%·';

  /** 估算字形宽度（vp）。measure 存在时优先用回调。 */
  private static charWidth(ch: string, fontSize: number, measure?: (ch: string) => number): number {
    if (measure !== undefined) {
      return measure(ch);
    }
    const code = ch.codePointAt(0) ?? 0;
    if (code > 0x2E80) {
      return fontSize;
    }
    if (ch === ' ') {
      return fontSize * 0.28;
    }
    return fontSize * 0.55;
  }

  /**
   * 分页。
   * @param text 章节显示文本（段间以空行分隔）
   * @param viewWidth 可用宽度（vp）
   * @param viewHeight 可用高度（vp）
   * @param fontSize 字号（fp）
   * @param lineHeight 行高（vp）
   * @param firstPageOffset 起始字符偏移（UTF-16 下标，用于进度恢复）
   * @param measure 可选字形宽度测量回调
   */
  static paginate(text: string, viewWidth: number, viewHeight: number, fontSize: number,
    lineHeight: number, firstPageOffset: number = 0,
    measure?: (ch: string) => number): Array<NovelPage> {
    const pages: Array<NovelPage> = [];
    if (text === undefined || text === null || text.length === 0) {
      pages.push(Paginator.makePage(0, 0, 0, ''));
      return pages;
    }
    const lineH = lineHeight > 0 ? lineHeight : fontSize * 1.8;
    const width = viewWidth > 0 ? viewWidth : 320;
    const height = viewHeight > 0 ? viewHeight : 0;
    if (height <= 0) {
      pages.push(Paginator.makePage(0, 0, text.length, text));
      return pages;
    }
    const linesPerPage = Math.max(1, Math.floor(height / Math.max(1, lineH)));
    const chars = Array.from(text);
    let pageStart = Paginator.charIndexFromCodeUnits(text, firstPageOffset);
    while (pageStart < chars.length && chars[pageStart] === '\n') {
      pageStart++;
    }
    let pageIndex = 0;
    while (pageStart < chars.length) {
      let line = 0;
      let cursor = pageStart;
      while (line < linesPerPage && cursor < chars.length) {
        let lineWidth = 0;
        const lineStart = cursor;
        while (cursor < chars.length) {
          const ch = chars[cursor];
          if (ch === '\n') {
            cursor++;
            break;
          }
          const w = Paginator.charWidth(ch, fontSize, measure);
          if (lineWidth + w > width && cursor > lineStart) {
            break;
          }
          lineWidth += w;
          cursor++;
        }
        // 行尾：把下一行开头的收尾标点拉回本行，避免行首标点。
        if (cursor < chars.length && cursor > lineStart) {
          let guard = 0;
          while (cursor < chars.length && guard < 6
            && Paginator.CLOSING_PUNCT.indexOf(chars[cursor]) >= 0) {
            cursor++;
            guard++;
          }
        }
        line++;
      }
      // 页尾：把下一页开头的收尾标点并入本页，避免页首标点。
      if (cursor < chars.length && cursor > pageStart) {
        let guard = 0;
        while (cursor < chars.length && guard < 6
          && Paginator.CLOSING_PUNCT.indexOf(chars[cursor]) >= 0) {
          cursor++;
          guard++;
        }
      }
      if (cursor <= pageStart) {
        cursor = Math.min(chars.length, pageStart + 1);
      }
      const startUnit = Paginator.codeUnitsFromCharIndex(text, pageStart);
      const endUnit = Paginator.codeUnitsFromCharIndex(text, cursor);
      const pageText = chars.slice(pageStart, cursor).join('').replace(/\n+$/, '');
      pages.push(Paginator.makePage(pageIndex, startUnit, endUnit, pageText));
      pageIndex++;
      pageStart = cursor;
      while (pageStart < chars.length && chars[pageStart] === '\n') {
        pageStart++;
      }
    }
    if (pages.length === 0) {
      pages.push(Paginator.makePage(0, 0, text.length, text));
    }
    return pages;
  }

  /** 找到包含某字符偏移的页下标。 */
  static pageOfOffset(pages: Array<NovelPage>, offset: number): number {
    for (let i = 0; i < pages.length; i++) {
      if (offset < pages[i].end) {
        return i;
      }
    }
    return Math.max(0, pages.length - 1);
  }

  /** 由页下标取起始字符偏移（用于进度保存/恢复）。 */
  static offsetOfPage(pages: Array<NovelPage>, pageIndex: number): number {
    if (pageIndex < 0 || pageIndex >= pages.length) {
      return 0;
    }
    return pages[pageIndex].start;
  }

  private static makePage(pageIndex: number, start: number, end: number, text: string): NovelPage {
    const page: NovelPage = { pageIndex: pageIndex, start: start, end: end, text: text };
    return page;
  }

  private static charIndexFromCodeUnits(text: string, offset: number): number {
    if (offset <= 0) {
      return 0;
    }
    if (offset >= text.length) {
      return Array.from(text).length;
    }
    return Array.from(text.substring(0, offset)).length;
  }

  private static codeUnitsFromCharIndex(text: string, charIndex: number): number {
    if (charIndex <= 0) {
      return 0;
    }
    return Array.from(text).slice(0, charIndex).join('').length;
  }
}
