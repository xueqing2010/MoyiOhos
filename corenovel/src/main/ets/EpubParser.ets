import { ParsedChapter, ParsedNovel, NovelTextFormat } from './NovelTypes';
import { TextEncoding } from './TextEncoding';
import { HtmlTextExtractor } from './HtmlTextExtractor';
import { ZipHtmlParser } from './ZipHtmlParser';

/** OPF manifest 条目。 */
class OpfItem {
  id: string = '';
  href: string = '';
  mediaType: string = '';
  properties: string = '';
}

/** OPF 解析结果。 */
class OpfData {
  title: string = '';
  creator: string = '';
  items: Array<OpfItem> = [];
  spine: Array<string> = [];
  ncxPath: string = '';
  navPath: string = '';
}

/**
 * EPUB 2/3 解析：container.xml → OPF（manifest/spine/metadata）→ 每章 XHTML 抽文本。
 *
 * 调用方先用 zlib 把 epub 解压到缓存临时目录，再把根目录交给本解析器
 * （ArkTS 侧没有可直接遍历 zip 的同步 API；解压到沙箱是任务约定的路径）。
 * 章节顺序以 spine 为权威；标题优先 NCX/nav 目录，其次章节内 h1-h3，最后「第N章」。
 */
export class EpubParser {
  private static readonly CONTAINER: string = 'META-INF/container.xml';
  private static readonly ENCRYPTION: string = 'META-INF/encryption.xml';

  /** 解析已解压的 EPUB 目录。 */
  static parse(bookDir: string, fallbackTitle: string): ParsedNovel {
    const containerPath = bookDir + '/' + EpubParser.CONTAINER;
    const containerText = EpubParser.readText(containerPath);
    if (containerText.length === 0) {
      throw new Error('EPUB 缺少 META-INF/container.xml（文件可能已损坏）');
    }
    const rootfile = EpubParser.findTagAttribute(containerText, 'rootfile', 'full-path');
    if (rootfile.length === 0) {
      throw new Error('EPUB container.xml 中缺少 rootfile');
    }
    EpubParser.rejectIfContentEncrypted(bookDir);
    const opfPath = EpubParser.resolvePath('', rootfile);
    const opfText = EpubParser.readText(bookDir + '/' + opfPath);
    if (opfText.length === 0) {
      throw new Error('EPUB 的 OPF 文件无法读取');
    }
    const opf = EpubParser.parseOpf(opfText);
    const opfDir = EpubParser.dirOf(opfPath);
    const base = opfDir.length > 0 ? opfDir + '/' : '';

    const idToHref = new Map<string, string>();
    for (let i = 0; i < opf.items.length; i++) {
      idToHref.set(opf.items[i].id, opf.items[i].href);
    }
    const chapterPaths: Array<string> = [];
    for (let i = 0; i < opf.spine.length; i++) {
      const href = idToHref.get(opf.spine[i]);
      if (href !== undefined && href.length > 0) {
        chapterPaths.push(EpubParser.resolvePath(base, href));
      }
    }
    if (chapterPaths.length === 0) {
      throw new Error('EPUB 的 spine 中没有正文章节');
    }

    const tocTitles = EpubParser.readTocTitles(bookDir, opf, base);
    const chapters: Array<ParsedChapter> = [];
    for (let i = 0; i < chapterPaths.length; i++) {
      const path = chapterPaths[i];
      let html = '';
      try {
        html = EpubParser.readText(bookDir + '/' + path);
      } catch (e) {
        continue;
      }
      if (html.length === 0) {
        continue;
      }
      let title = '';
      const tocTitle = tocTitles.get(path);
      if (tocTitle !== undefined) {
        title = tocTitle;
      }
      if (title.length === 0) {
        title = HtmlTextExtractor.headingOf(html);
      }
      if (title.length === 0) {
        title = '第' + (chapters.length + 1) + '章';
      }
      let content = HtmlTextExtractor.extract(html);
      content = EpubParser.stripLeadingTitle(content, title);
      if (content.trim().length === 0) {
        continue;
      }
      const chapter: ParsedChapter = {
        title: title,
        content: content,
        startOffset: 0
      };
      chapters.push(chapter);
    }
    if (chapters.length === 0) {
      throw new Error('EPUB 内没有可读文本章节');
    }
    let plainText = '';
    for (let i = 0; i < chapters.length; i++) {
      plainText += chapters[i].content;
      if (i + 1 < chapters.length) {
        plainText += '\n\n';
      }
    }
    const novel: ParsedNovel = {
      title: opf.title.length > 0 ? opf.title : fallbackTitle,
      format: NovelTextFormat.EPUB,
      chapters: chapters,
      plainText: plainText,
      author: opf.creator
    };
    return novel;
  }

  /** 去掉正文开头与章节标题重复的那一行（EPUB 的 h1 常与目录标题相同）。 */
  private static stripLeadingTitle(content: string, title: string): string {
    if (title.length === 0 || content.length === 0) {
      return content;
    }
    const head = content.trim();
    if (!head.startsWith(title)) {
      return content;
    }
    const rest = head.substring(title.length);
    if (rest.length === 0) {
      return content;
    }
    const first = rest.charAt(0);
    if (first !== '\n') {
      return content;
    }
    return rest.trim();
  }

  // ---------- EPUB 内部实现 ----------

  private static readText(path: string): string {
    try {
      const bytes = ZipHtmlParser.readBytes(path);
      return TextEncoding.decode(bytes).text;
    } catch (e) {
      return '';
    }
  }

  /** 只在正文文档被加密时拒绝；字体混淆（商用 EPUB 常见）放行。 */
  private static rejectIfContentEncrypted(bookDir: string): void {
    const text = EpubParser.readText(bookDir + '/' + EpubParser.ENCRYPTION);
    if (text.length === 0) {
      return;
    }
    const lower = text.toLowerCase();
    const hasEncryptedContent = lower.indexOf('.xhtml') >= 0 || lower.indexOf('.html') >= 0
      || lower.indexOf('.htm') >= 0;
    if (hasEncryptedContent && lower.indexOf('cipherreference') >= 0) {
      throw new Error('EPUB 正文已加密（DRM 保护），暂不支持导入');
    }
  }

  private static parseOpf(opfText: string): OpfData {
    const opf = new OpfData();
    const lower = opfText.toLowerCase();

    // metadata: dc:title / dc:creator / <title>
    opf.title = EpubParser.elementText(opfText, 'dc:title');
    if (opf.title.length === 0) {
      opf.title = EpubParser.elementText(opfText, 'title');
    }
    opf.creator = EpubParser.elementText(opfText, 'dc:creator');

    // manifest items
    let from = 0;
    while (true) {
      const idx = lower.indexOf('<item', from);
      if (idx < 0) {
        break;
      }
      const after = idx + 5;
      if (after < lower.length && (lower.charAt(after) !== ' ' && lower.charAt(after) !== '/'
        && lower.charAt(after) !== '>')) {
        from = after;
        continue;
      }
      const gt = opfText.indexOf('>', idx);
      if (gt < 0) {
        break;
      }
      const tag = opfText.substring(idx, gt + 1);
      const item = new OpfItem();
      item.id = EpubParser.attrOf(tag, 'id');
      item.href = EpubParser.attrOf(tag, 'href');
      item.mediaType = EpubParser.attrOf(tag, 'media-type');
      item.properties = EpubParser.attrOf(tag, 'properties');
      if (item.id.length > 0 && item.href.length > 0) {
        opf.items.push(item);
        if (item.mediaType.toLowerCase().indexOf('dtbncx') >= 0) {
          opf.ncxPath = item.href;
        }
        if (item.properties.indexOf('nav') >= 0) {
          opf.navPath = item.href;
        }
      }
      from = gt + 1;
    }

    // spine itemref
    from = 0;
    while (true) {
      const idx = lower.indexOf('<itemref', from);
      if (idx < 0) {
        break;
      }
      const gt = opfText.indexOf('>', idx);
      if (gt < 0) {
        break;
      }
      const tag = opfText.substring(idx, gt + 1);
      const idref = EpubParser.attrOf(tag, 'idref');
      if (idref.length > 0) {
        opf.spine.push(idref);
      }
      from = gt + 1;
    }
    return opf;
  }

  private static readTocTitles(bookDir: string, opf: OpfData, base: string): Map<string, string> {
    const map = new Map<string, string>();
    if (opf.ncxPath.length > 0) {
      const ncxText = EpubParser.readText(bookDir + '/' + EpubParser.resolvePath(base, opf.ncxPath));
      EpubParser.parseNcx(ncxText, base, map);
    }
    if (map.size === 0 && opf.navPath.length > 0) {
      const navText = EpubParser.readText(bookDir + '/' + EpubParser.resolvePath(base, opf.navPath));
      EpubParser.parseNav(navText, base, map);
    }
    return map;
  }

  private static parseNcx(text: string, base: string, map: Map<string, string>): void {
    const lower = text.toLowerCase();
    let from = 0;
    while (true) {
      const navIdx = lower.indexOf('<navpoint', from);
      if (navIdx < 0) {
        break;
      }
      const navEnd = lower.indexOf('</navpoint>', navIdx);
      const scopeEnd = navEnd < 0 ? text.length : navEnd;
      const scope = text.substring(navIdx, scopeEnd);
      const scopeLower = scope.toLowerCase();
      const textIdx = scopeLower.indexOf('<text');
      if (textIdx >= 0) {
        const openEnd = scope.indexOf('>', textIdx);
        const closeIdx = scopeLower.indexOf('</text>', openEnd + 1);
        if (openEnd >= 0 && closeIdx > openEnd) {
          const title = HtmlTextExtractor.extract(scope.substring(openEnd + 1, closeIdx)).trim();
          const contentIdx = scopeLower.indexOf('<content', closeIdx);
          if (title.length > 0 && contentIdx >= 0) {
            const contentEnd = scope.indexOf('>', contentIdx);
            if (contentEnd >= 0) {
              const tag = scope.substring(contentIdx, contentEnd + 1);
              const src = EpubParser.attrOf(tag, 'src');
              if (src.length > 0) {
                map.set(EpubParser.resolvePath(base, src), title);
              }
            }
          }
        }
      }
      from = navIdx + 9;
    }
  }

  private static parseNav(text: string, base: string, map: Map<string, string>): void {
    const lower = text.toLowerCase();
    let from = 0;
    while (true) {
      const aIdx = lower.indexOf('<a', from);
      if (aIdx < 0) {
        break;
      }
      const after = aIdx + 2;
      if (after < lower.length && (lower.charAt(after) !== ' ' && lower.charAt(after) !== '>')) {
        from = after;
        continue;
      }
      const gt = text.indexOf('>', aIdx);
      if (gt < 0) {
        break;
      }
      const tag = text.substring(aIdx, gt + 1);
      const href = EpubParser.attrOf(tag, 'href');
      const closeIdx = lower.indexOf('</a>', gt + 1);
      if (href.length > 0 && closeIdx > gt) {
        const title = HtmlTextExtractor.extract(text.substring(gt + 1, closeIdx)).trim();
        if (title.length > 0) {
          map.set(EpubParser.resolvePath(base, href), title);
        }
      }
      from = gt + 1;
    }
  }

  /** 取指定标签名的元素文本（含嵌套标签时抽纯文本）。 */
  private static elementText(text: string, tagName: string): string {
    const lower = text.toLowerCase();
    const openTag = '<' + tagName.toLowerCase();
    const closeTag = '</' + tagName.toLowerCase() + '>';
    const idx = lower.indexOf(openTag);
    if (idx < 0) {
      return '';
    }
    const after = idx + openTag.length;
    if (after < lower.length) {
      const ch = lower.charAt(after);
      if (ch !== ' ' && ch !== '>' && ch !== '/') {
        return '';
      }
    }
    const gt = text.indexOf('>', idx);
    if (gt < 0) {
      return '';
    }
    const closeIdx = lower.indexOf(closeTag, gt + 1);
    if (closeIdx < 0) {
      return '';
    }
    return HtmlTextExtractor.extract(text.substring(gt + 1, closeIdx)).trim();
  }

  /** 查找指定标签的某个属性值（简化的手动扫描，避免动态正则转义问题）。 */
  private static findTagAttribute(text: string, tagName: string, attrName: string): string {
    const lower = text.toLowerCase();
    const openTag = '<' + tagName.toLowerCase();
    let from = 0;
    while (true) {
      const idx = lower.indexOf(openTag, from);
      if (idx < 0) {
        return '';
      }
      const after = idx + openTag.length;
      // 必须确保是完整标签名（<rootfiles> 不能匹配 <rootfile）
      if (after < lower.length) {
        const ch = lower.charAt(after);
        if (ch !== ' ' && ch !== '\t' && ch !== '\n' && ch !== '\r' && ch !== '/' && ch !== '>') {
          from = after;
          continue;
        }
      }
      const gt = text.indexOf('>', idx);
      if (gt < 0) {
        return '';
      }
      return EpubParser.attrOf(text.substring(idx, gt + 1), attrName);
    }
  }

  /** 解析一个标签字符串里的属性值。 */
  private static attrOf(tag: string, name: string): string {
    const lower = tag.toLowerCase();
    const needle = name.toLowerCase();
    let from = 0;
    while (true) {
      const idx = lower.indexOf(needle, from);
      if (idx < 0) {
        return '';
      }
      const before = idx === 0 ? ' ' : lower.charAt(idx - 1);
      const boundaryOk = before === ' ' || before === '\t' || before === '\n' || before === '\r'
        || before === '<';
      if (!boundaryOk) {
        from = idx + needle.length;
        continue;
      }
      let p = idx + needle.length;
      while (p < tag.length) {
        const c = tag.charAt(p);
        if (c === ' ' || c === '\t' || c === '\n' || c === '\r') {
          p++;
          continue;
        }
        break;
      }
      if (tag.charAt(p) !== '=') {
        from = idx + needle.length;
        continue;
      }
      p++;
      while (p < tag.length) {
        const c = tag.charAt(p);
        if (c === ' ' || c === '\t' || c === '\n' || c === '\r') {
          p++;
          continue;
        }
        break;
      }
      if (p >= tag.length) {
        return '';
      }
      const quote = tag.charAt(p);
      if (quote === '"' || quote === "'") {
        const end = tag.indexOf(quote, p + 1);
        if (end < 0) {
          return '';
        }
        return tag.substring(p + 1, end);
      }
      let end = p;
      while (end < tag.length) {
        const c = tag.charAt(end);
        if (c === ' ' || c === '\t' || c === '\n' || c === '\r' || c === '>') {
          break;
        }
        end++;
      }
      return tag.substring(p, end);
    }
  }

  private static dirOf(path: string): string {
    const idx = path.lastIndexOf('/');
    if (idx < 0) {
      return '';
    }
    return path.substring(0, idx);
  }

  /** 把 href 解析成相对 zip 根目录的路径（去掉片段、解析 ./ 与 ../）。 */
  private static resolvePath(baseDir: string, href: string): string {
    let raw = href.trim();
    const hash = raw.indexOf('#');
    if (hash >= 0) {
      raw = raw.substring(0, hash);
    }
    try {
      raw = decodeURIComponent(raw);
    } catch (e) {
      // 保持原样
    }
    let combined = raw;
    if (raw.length > 0 && raw.charAt(0) !== '/' && baseDir.length > 0) {
      combined = baseDir + raw;
    }
    const parts = combined.split('/');
    const stack: Array<string> = [];
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (part.length === 0 || part === '.') {
        continue;
      }
      if (part === '..') {
        if (stack.length > 0) {
          stack.pop();
        }
        continue;
      }
      stack.push(part);
    }
    return stack.join('/');
  }
}
