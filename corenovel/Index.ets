/**
 * corenovel HAR entry：小说文本解析（TXT/EPUB/ZIP-HTML）、分章、分页、段落与三态显示。
 */
export { ParsedChapter, ParsedNovel, NovelPage, NovelTextFormat, NovelDisplayMode, DecodeResult } from './src/main/ets/NovelTypes';
export { TextEncoding } from './src/main/ets/TextEncoding';
export { ChapterMark, ChapterSplitter } from './src/main/ets/ChapterSplitter';
export { HtmlTextExtractor } from './src/main/ets/HtmlTextExtractor';
export { TxtParser, TxtParseResult } from './src/main/ets/TxtParser';
export { EpubParser } from './src/main/ets/EpubParser';
export { ZipHtmlParser } from './src/main/ets/ZipHtmlParser';
export { Paginator } from './src/main/ets/Paginator';
export { NovelParagraph, ParagraphSplitter } from './src/main/ets/ParagraphSplitter';
export { naturalCompare, naturalSortArray } from './src/main/ets/NaturalSort';
