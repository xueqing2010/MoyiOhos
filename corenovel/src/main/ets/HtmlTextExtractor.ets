/**
 * HTML/XHTML → 纯文本（容错优先，不用 XML 解析器）。
 *
 * 电子书 XHTML 经常不是良构 XML（未闭合标签、裸 &、未声明实体），XML 解析会整章失败；
 * 这里只抽正文文字，不需要文档树。逻辑对齐上游 HtmlTextExtractor：
 * 剥 script/style/head → br 换行 → img 占位 → 块标签空行 → 剥标签 → 单趟实体解码 → 收敛空白。
 */
export class HtmlTextExtractor {
  /** 图片占位标记（翻译时跳过该段）。 */
  static readonly IMAGE_MARK: string = '📷 [图片]';

  private static readonly BLOCK_TAG: RegExp =
    /<\/?(p|div|h[1-6]|li|tr|blockquote|section|article|dd|dt|pre)\b[^>]*>/gi;
  private static readonly BR_TAG: RegExp = /<br\s*\/?>/gi;
  private static readonly IMG_TAG: RegExp = /<img\b[^>]*>/gi;
  private static readonly TITLE_TAG: RegExp = /<title\b[^>]*>([\s\S]*?)<\/title>/i;
  private static readonly INLINE_SPACE: RegExp = /[ \t]+/g;
  private static readonly LINE_PADDING: RegExp = /[ \t]*\n[ \t]*/g;
  private static readonly BLANK_LINES: RegExp = /\n{3,}/g;

  /** 抽取正文纯文本。 */
  static extract(html: string): string {
    if (html === undefined || html === null || html.trim().length === 0) {
      return '';
    }
    let s = html;
    s = HtmlTextExtractor.stripClosedBlock(s, 'script');
    s = HtmlTextExtractor.stripClosedBlock(s, 'style');
    s = HtmlTextExtractor.stripClosedBlock(s, 'head');
    s = s.replace(HtmlTextExtractor.BR_TAG, '\n');
    s = s.replace(HtmlTextExtractor.IMG_TAG, '\n' + HtmlTextExtractor.IMAGE_MARK + '\n');
    s = s.replace(HtmlTextExtractor.BLOCK_TAG, '\n\n');
    s = HtmlTextExtractor.stripTags(s);
    s = HtmlTextExtractor.decodeEntities(s);
    s = s.replace(HtmlTextExtractor.INLINE_SPACE, ' ');
    s = s.replace(HtmlTextExtractor.LINE_PADDING, '\n');
    s = s.replace(HtmlTextExtractor.BLANK_LINES, '\n\n');
    return s.trim();
  }

  /** 取 <title> 文本（元数据，不参与正文）。 */
  static titleOf(html: string): string {
    const matched = HtmlTextExtractor.TITLE_TAG.exec(html);
    if (matched === null || matched.length < 2) {
      return '';
    }
    return HtmlTextExtractor.decodeEntities(matched[1]).trim();
  }

  /** 取第一个标题级标签（h1/h2/h3）的文本，用于 EPUB 章节标题兜底。 */
  static headingOf(html: string): string {
    const patterns: Array<RegExp> = [
      /<h1\b[^>]*>([\s\S]*?)<\/h1>/i,
      /<h2\b[^>]*>([\s\S]*?)<\/h2>/i,
      /<h3\b[^>]*>([\s\S]*?)<\/h3>/i
    ];
    for (let i = 0; i < patterns.length; i++) {
      const matched = patterns[i].exec(html);
      if (matched !== null && matched.length > 1) {
        const text = HtmlTextExtractor.extract(matched[1]);
        if (text.length > 0) {
          return text;
        }
      }
    }
    return '';
  }

  // ---------- 内部实现 ----------

  /** 删除 <tag>…</tag> 闭合块；找不到闭合标签时不做删除（畸形文档宁可不剥）。 */
  private static stripClosedBlock(html: string, tag: string): string {
    const lower = html.toLowerCase();
    const open = '<' + tag;
    const close = '</' + tag;
    let from = 0;
    let search = 0;
    let out = '';
    let changed = false;
    while (true) {
      const openAt = HtmlTextExtractor.indexOfTag(lower, open, search);
      if (openAt < 0) {
        break;
      }
      const openEnd = lower.indexOf('>', openAt + open.length);
      if (openEnd < 0) {
        break;
      }
      const closeAt = HtmlTextExtractor.indexOfTag(lower, close, openEnd + 1);
      if (closeAt < 0) {
        break;
      }
      const closeEnd = lower.indexOf('>', closeAt + close.length);
      if (closeEnd < 0) {
        break;
      }
      out += html.substring(from, openAt);
      from = closeEnd + 1;
      search = from;
      changed = true;
    }
    if (!changed) {
      return html;
    }
    out += html.substring(from);
    return out;
  }

  /** 删除所有 <…> 标签（'<>' 保留）。 */
  private static stripTags(html: string): string {
    let lt = html.indexOf('<');
    if (lt < 0) {
      return html;
    }
    let out = '';
    let from = 0;
    while (lt >= 0) {
      const gt = html.indexOf('>', lt + 1);
      if (gt < 0) {
        break;
      }
      if (gt === lt + 1) {
        lt = html.indexOf('<', lt + 1);
        continue;
      }
      out += html.substring(from, lt);
      from = gt + 1;
      lt = html.indexOf('<', from);
    }
    out += html.substring(from);
    return out;
  }

  /** 不区分大小写查找标签，并检查标签名后的单词边界。 */
  private static indexOfTag(lower: string, needle: string, from: number): number {
    let i = from;
    while (true) {
      i = lower.indexOf(needle, i);
      if (i < 0) {
        return -1;
      }
      const after = i + needle.length;
      if (after >= lower.length || !HtmlTextExtractor.isWordChar(lower.charAt(after))) {
        return i;
      }
      i++;
    }
  }

  private static isWordChar(ch: string): boolean {
    if (ch >= 'a' && ch <= 'z') {
      return true;
    }
    if (ch >= 'A' && ch <= 'Z') {
      return true;
    }
    if (ch >= '0' && ch <= '9') {
      return true;
    }
    return ch === '_';
  }

  /** 单趟实体解码（避免二次解码）。 */
  private static decodeEntities(s: string): string {
    if (s.indexOf('&') < 0) {
      return s;
    }
    let out = '';
    let i = 0;
    while (i < s.length) {
      const amp = s.indexOf('&', i);
      if (amp < 0) {
        out += s.substring(i);
        break;
      }
      out += s.substring(i, amp);
      const semi = s.indexOf(';', amp + 1);
      if (semi < 0 || semi - amp > 12) {
        out += '&';
        i = amp + 1;
        continue;
      }
      const body = s.substring(amp + 1, semi);
      const decoded = HtmlTextExtractor.decodeEntity(body);
      if (decoded === undefined) {
        out += s.substring(amp, semi + 1);
      } else {
        out += decoded;
      }
      i = semi + 1;
    }
    return out;
  }

  private static decodeEntity(body: string): string | undefined {
    if (body.length === 0) {
      return undefined;
    }
    if (body.charAt(0) === '#') {
      let code = -1;
      if (body.length > 2 && (body.charAt(1) === 'x' || body.charAt(1) === 'X')) {
        code = parseInt(body.substring(2), 16);
      } else {
        code = parseInt(body.substring(1), 10);
      }
      if (isNaN(code) || code <= 0 || code > 0x10FFFF) {
        return undefined;
      }
      return String.fromCharCode(code);
    }
    const key = body.toLowerCase();
    if (key === 'nbsp') {
      return ' ';
    }
    if (key === 'lt') {
      return '<';
    }
    if (key === 'gt') {
      return '>';
    }
    if (key === 'quot') {
      return '"';
    }
    if (key === 'apos') {
      return "'";
    }
    if (key === 'amp') {
      return '&';
    }
    if (key === 'mdash') {
      return '—';
    }
    if (key === 'ndash') {
      return '–';
    }
    if (key === 'hellip') {
      return '…';
    }
    if (key === 'middot') {
      return '·';
    }
    if (key === 'ldquo' || key === 'rdquo') {
      return '“';
    }
    if (key === 'lsquo' || key === 'rsquo') {
      return '‘';
    }
    return undefined;
  }
}
