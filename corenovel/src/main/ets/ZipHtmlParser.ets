import fs from '@ohos.file.fs';
import { ParsedChapter, ParsedNovel, NovelTextFormat } from './NovelTypes';
import { TextEncoding } from './TextEncoding';
import { HtmlTextExtractor } from './HtmlTextExtractor';
import { naturalSortArray } from './NaturalSort';

/** ZIP 小说包解析结果：条目名 → 标题/正文，由调用方（已解压到缓存目录）直接读取。 */
export class ZipHtmlParser {
  private static readonly TEXT_EXTS: Array<string> = ['.html', '.htm', '.xhtml', '.txt'];

  /**
   * 解析已解压的 zip-html 目录：每个 html/xhtml/txt 条目 = 一章，按自然序排序。
   * @param bookDir 解压后的根目录
   * @param fallbackTitle 书名兜底
   */
  static parse(bookDir: string, fallbackTitle: string): ParsedNovel {
    let names: Array<string> = [];
    try {
      names = fs.listFileSync(bookDir, { recursion: true });
    } catch (e) {
      throw new Error('无法读取压缩包内容（文件可能已损坏）');
    }
    const textFiles: Array<string> = [];
    for (let i = 0; i < names.length; i++) {
      const lower = names[i].toLowerCase();
      for (let k = 0; k < ZipHtmlParser.TEXT_EXTS.length; k++) {
        if (lower.endsWith(ZipHtmlParser.TEXT_EXTS[k])) {
          textFiles.push(names[i]);
          break;
        }
      }
    }
    // 过滤明显的元数据文件（readme/license/copyright），仅当还有正文文件时生效。
    let contentFiles: Array<string> = [];
    for (let i = 0; i < textFiles.length; i++) {
      if (!ZipHtmlParser.isMetaFile(textFiles[i])) {
        contentFiles.push(textFiles[i]);
      }
    }
    if (contentFiles.length === 0) {
      contentFiles = textFiles;
    }
    const sorted = naturalSortArray(contentFiles.slice());
    const chapters: Array<ParsedChapter> = [];
    for (let i = 0; i < sorted.length; i++) {
      const rel = sorted[i];
      const full = bookDir + '/' + rel;
      let content = '';
      let heading = '';
      try {
        const bytes = ZipHtmlParser.readBytes(full);
        const decoded = TextEncoding.decode(bytes);
        if (rel.toLowerCase().endsWith('.txt')) {
          content = ZipHtmlParser.toParagraphs(decoded.text);
        } else {
          heading = HtmlTextExtractor.headingOf(decoded.text);
          content = HtmlTextExtractor.extract(decoded.text);
        }
      } catch (e) {
        continue;
      }
      if (content.trim().length === 0) {
        continue;
      }
      let title = heading.trim();
      if (title.length === 0) {
        title = ZipHtmlParser.chapterTitle(rel, chapters.length + 1);
      }
      content = ZipHtmlParser.stripLeadingTitle(content, title);
      const chapter: ParsedChapter = {
        title: title,
        content: content,
        startOffset: 0
      };
      chapters.push(chapter);
    }
    if (chapters.length === 0) {
      throw new Error('压缩包内没有可读文本章节');
    }
    let plainText = '';
    for (let i = 0; i < chapters.length; i++) {
      plainText += chapters[i].content;
      if (i + 1 < chapters.length) {
        plainText += '\n\n';
      }
    }
    const novel: ParsedNovel = {
      title: fallbackTitle,
      format: NovelTextFormat.ZIP_HTML,
      chapters: chapters,
      plainText: plainText,
      author: ''
    };
    return novel;
  }

  // ---------- 内部实现 ----------

  static readBytes(path: string): Uint8Array {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const size = fs.statSync(path).size;
      const buffer = new ArrayBuffer(size);
      let read = 0;
      while (read < size) {
        const n = fs.readSync(file.fd, buffer, { offset: read, length: size - read });
        if (n <= 0) {
          break;
        }
        read += n;
      }
      return new Uint8Array(buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  /** 去掉正文开头与标题重复的一行（HTML 的 h1 常与章节标题相同）。 */
  private static stripLeadingTitle(content: string, title: string): string {
    if (title.length === 0) {
      return content;
    }
    const head = content.trim();
    if (!head.startsWith(title)) {
      return content;
    }
    const rest = head.substring(title.length);
    if (rest.length === 0 || rest.charAt(0) !== '\n') {
      return content;
    }
    return rest.trim();
  }

  private static isMetaFile(rel: string): boolean {
    let name = rel;
    const slash = name.lastIndexOf('/');
    if (slash >= 0) {
      name = name.substring(slash + 1);
    }
    const dot = name.lastIndexOf('.');
    if (dot > 0) {
      name = name.substring(0, dot);
    }
    const lower = name.toLowerCase();
    return lower === 'readme' || lower === 'license' || lower === 'copyright'
      || lower.indexOf('readme.') === 0;
  }

  private static chapterTitle(rel: string, fallbackIndex: number): string {
    let name = rel;
    const slash = name.lastIndexOf('/');
    if (slash >= 0) {
      name = name.substring(slash + 1);
    }
    const dot = name.lastIndexOf('.');
    if (dot > 0) {
      name = name.substring(0, dot);
    }
    name = name.trim();
    if (name.length === 0) {
      return '第' + fallbackIndex + '章';
    }
    return name;
  }

  private static toParagraphs(text: string): string {
    const normalized = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
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
}
