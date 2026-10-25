/**
 * Core entities & enums — field-for-field aligned with plan.md Data Model.
 * Persistence rule (FR-014): PageTranslation stores ONLY text + coordinates.
 */

/** manga.source_type */
export enum SourceType {
  ARCHIVE = 0,
  DIRECTORY = 1,
  ALBUM = 2
}

/** manga.translate_status / manga_page.translate_status / page_translation.status */
export enum TranslateStatus {
  NONE = 0,
  RUNNING = 1,
  DONE = 2,
  PARTIAL_FAILED = 3
}

/** download_task.status */
export enum DownloadStatus {
  NOT_DOWNLOADED = 0,
  DOWNLOADING = 1,
  PAUSED = 2,
  DOWNLOADED = 3,
  VERIFYING = 4,
  MD5_FAILED = 5,
  UNSUPPORTED = 6
}

/** spike_result.result */
export enum SpikeOutcome {
  NOT_RUN = 0,
  PASS = 1,
  FAIL = 2,
  DEGRADED = 3
}

/** Axis-aligned rect in ORIGINAL image pixel coordinates. */
export interface PixelRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** One OCR line region: text + original-pixel bounding box. */
export interface OcrRegion {
  text: string;
  box: PixelRect;
}

export interface Manga {
  id: number;
  name: string;
  sourceType: SourceType;
  sourceUri?: string;
  coverPath?: string;
  pageCount: number;
  lastReadPage: number;
  translateStatus: TranslateStatus;
  createdAt: number;
  updatedAt: number;
}

export interface MangaPage {
  id: number;
  mangaId: number;
  pageIndex: number;
  imagePath: string;
  width?: number;
  height?: number;
  translateStatus: TranslateStatus;
}

/**
 * Persisted per-page translation record. ocr_json = OcrRegion[] and
 * translations_json = string[] are index-aligned; NO composed bitmaps
 * ever reach the persistent layer (FR-014).
 */
export interface PageTranslation {
  pageId: number;
  engineType: number;
  ocr: Array<OcrRegion>;
  translations: Array<string>;
  status: TranslateStatus;
  failReason?: string;
  updatedAt: number;
}

export interface DownloadTask {
  id: number;
  modelKey: string;
  displayName: string;
  url: string;
  fileName: string;
  totalBytes: number;
  downloadedBytes: number;
  status: DownloadStatus;
  expectedMd5?: string;
  localPath?: string;
  createdAt: number;
  updatedAt: number;
}

export interface SpikeResult {
  spikeKey: string;
  result: SpikeOutcome;
  detail?: string;
  updatedAt: number;
}

/** Safe factories (avoid untyped object literals at call sites). */
export function makeManga(name: string, sourceType: SourceType, pageCount: number): Manga {
  const now = Date.now();
  const m: Manga = {
    id: 0,
    name: name,
    sourceType: sourceType,
    sourceUri: undefined,
    coverPath: undefined,
    pageCount: pageCount,
    lastReadPage: 0,
    translateStatus: TranslateStatus.NONE,
    createdAt: now,
    updatedAt: now
  };
  return m;
}

export function makeMangaPage(mangaId: number, pageIndex: number, imagePath: string): MangaPage {
  const p: MangaPage = {
    id: 0,
    mangaId: mangaId,
    pageIndex: pageIndex,
    imagePath: imagePath,
    width: undefined,
    height: undefined,
    translateStatus: TranslateStatus.NONE
  };
  return p;
}

export function makePageTranslation(pageId: number): PageTranslation {
  const t: PageTranslation = {
    pageId: pageId,
    engineType: 0,
    ocr: [],
    translations: [],
    status: TranslateStatus.NONE,
    failReason: undefined,
    updatedAt: Date.now()
  };
  return t;
}

export function makeDownloadTask(modelKey: string, displayName: string, url: string, fileName: string): DownloadTask {
  const now = Date.now();
  const t: DownloadTask = {
    id: 0,
    modelKey: modelKey,
    displayName: displayName,
    url: url,
    fileName: fileName,
    totalBytes: 0,
    downloadedBytes: 0,
    status: DownloadStatus.NOT_DOWNLOADED,
    expectedMd5: undefined,
    localPath: undefined,
    createdAt: now,
    updatedAt: now
  };
  return t;
}

export function makeSpikeResult(spikeKey: string, result: SpikeOutcome): SpikeResult {
  const r: SpikeResult = {
    spikeKey: spikeKey,
    result: result,
    detail: undefined,
    updatedAt: Date.now()
  };
  return r;
}

export function makeOcrRegion(text: string, box: PixelRect): OcrRegion {
  const r: OcrRegion = { text: text, box: box };
  return r;
}

export function makePixelRect(x: number, y: number, w: number, h: number): PixelRect {
  const r: PixelRect = { x: x, y: y, w: w, h: h };
  return r;
}

// ---------------------------------------------------------------------------
// MVP-2 (stage 2): novel / text-translation / chat entities.
// ---------------------------------------------------------------------------

/** novel.format */
export enum NovelFormat {
  TXT = 0,
  EPUB = 1,
  ZIP_HTML = 2
}

export interface Novel {
  id: number;
  name: string;
  format: NovelFormat;
  sourceUri?: string;
  coverPath?: string;
  chapterCount: number;
  lastReadChapter: number;
  lastReadOffset: number;
  translateStatus: TranslateStatus;
  createdAt: number;
  updatedAt: number;
}

export interface NovelChapter {
  id: number;
  novelId: number;
  chapterIndex: number;
  title: string;
  content: string;
  translateStatus: TranslateStatus;
  translatedContent?: string;
  failReason?: string;
  updatedAt: number;
}

export interface TextTranslationRecord {
  id: number;
  sourceText: string;
  translatedText: string;
  engineType: number;
  fromLang: string;
  toLang: string;
  createdAt: number;
}

export interface ChatSession {
  id: number;
  title: string;
  engineType: number;
  createdAt: number;
  updatedAt: number;
}

export interface ChatMessageRecord {
  id: number;
  sessionId: number;
  role: string; // 'user' | 'assistant' | 'system'
  content: string;
  createdAt: number;
}

export function makeNovel(name: string, format: NovelFormat, chapterCount: number): Novel {
  const now = Date.now();
  const n: Novel = {
    id: 0,
    name: name,
    format: format,
    sourceUri: undefined,
    coverPath: undefined,
    chapterCount: chapterCount,
    lastReadChapter: 0,
    lastReadOffset: 0,
    translateStatus: TranslateStatus.NONE,
    createdAt: now,
    updatedAt: now
  };
  return n;
}

export function makeNovelChapter(novelId: number, chapterIndex: number, title: string, content: string): NovelChapter {
  const c: NovelChapter = {
    id: 0,
    novelId: novelId,
    chapterIndex: chapterIndex,
    title: title,
    content: content,
    translateStatus: TranslateStatus.NONE,
    translatedContent: undefined,
    failReason: undefined,
    updatedAt: Date.now()
  };
  return c;
}

export function makeTextTranslationRecord(sourceText: string, translatedText: string, engineType: number,
  fromLang: string, toLang: string): TextTranslationRecord {
  const r: TextTranslationRecord = {
    id: 0,
    sourceText: sourceText,
    translatedText: translatedText,
    engineType: engineType,
    fromLang: fromLang,
    toLang: toLang,
    createdAt: Date.now()
  };
  return r;
}

export function makeChatSession(title: string, engineType: number): ChatSession {
  const now = Date.now();
  const s: ChatSession = {
    id: 0,
    title: title,
    engineType: engineType,
    createdAt: now,
    updatedAt: now
  };
  return s;
}

export function makeChatMessage(sessionId: number, role: string, content: string): ChatMessageRecord {
  const m: ChatMessageRecord = {
    id: 0,
    sessionId: sessionId,
    role: role,
    content: content,
    createdAt: Date.now()
  };
  return m;
}

