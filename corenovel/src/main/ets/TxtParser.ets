import { ParsedNovel, NovelTextFormat, DecodeResult } from './NovelTypes';
import { TextEncoding } from './TextEncoding';
import { ChapterSplitter } from './ChapterSplitter';

/** TXT 解析结果（携带编码信息，供导入 UI 提示「已按 GBK 近似解码」）。 */
export class TxtParseResult {
  novel: ParsedNovel = { title: '', format: 0, chapters: [], plainText: '', author: '' };
  encoding: string = 'utf-8';
  lossy: boolean = false;
}

/** TXT 解析：编码探测 → 分章 → 一行一段归一化。 */
export class TxtParser {
  /** 解析原始字节（自动探测 UTF-8/UTF-16 BOM、GBK/GB18030、Big5）。 */
  static parse(bytes: Uint8Array, fallbackTitle: string): TxtParseResult {
    const decoded: DecodeResult = TextEncoding.decode(bytes);
    const result = new TxtParseResult();
    result.encoding = decoded.encoding;
    result.lossy = decoded.lossy;
    result.novel = TxtParser.parseText(decoded.text, fallbackTitle);
    return result;
  }

  /** 解析已解码文本。 */
  static parseText(text: string, fallbackTitle: string): ParsedNovel {
    let normalized = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    if (normalized.length > 0 && normalized.charCodeAt(0) === 0xFEFF) {
      normalized = normalized.substring(1);
    }
    const chapters = ChapterSplitter.split(normalized);
    if (chapters.length === 0) {
      throw new Error('文件中没有可读文本');
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
      format: NovelTextFormat.TXT,
      chapters: chapters,
      plainText: plainText,
      author: ''
    };
    return novel;
  }
}
