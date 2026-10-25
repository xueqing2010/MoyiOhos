import { preferences } from '@kit.ArkData';
import { Novel, NovelChapter, TranslateStatus } from 'coremodel';
import { EngineType } from 'coretranslate';
import { NovelDisplayMode, NovelPage, Paginator, ParagraphSplitter } from 'corenovel';
import { ThemeTokens, Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { NovelRepository, NovelShelfItem } from '../data/NovelRepository';
import { NovelTranslateResult, NovelTranslateService } from '../service/NovelTranslateService';

const TAG = 'NovelViewModel';
/** 阅读设置与漫画共用 starflow_reader 偏好文件；小说补充键放在同一文件内。 */
const PREF_READER = 'starflow_reader';
const PREF_SHELF = 'starflow_shelf';
const KEY_BG = 'reader_bg';
const KEY_FONT_SIZE = 'render_font_size';
const KEY_LINE_HEIGHT = 'novel_line_height';
const KEY_MARGIN = 'novel_margin';
const KEY_DISPLAY = 'novel_display_mode';
const KEY_VIEW_MODE = 'novel_view_mode';

/** 小说阅读设置（紫夜 6 档背景 + 字号/行距/边距 + 显示三态）。 */
export class NovelReaderSettings {
  fontSize: number = 17;
  lineHeight: number = 30;
  margin: number = 18;
  bgKey: string = 'nocturne';
  displayMode: NovelDisplayMode = NovelDisplayMode.ORIGINAL;
}

/** 阅读会话加载结果。 */
export class NovelReaderSession {
  novelName: string = '';
  chapters: Array<NovelChapter> = [];
  chapterIndex: number = 0;
  chapter: NovelChapter | undefined = undefined;
  offset: number = 0;
}

/** 批量翻译状态（页面用 @State 持有快照）。 */
export class NovelBatchState {
  running: boolean = false;
  cancelRequested: boolean = false;
  chapterIndex: number = 0;
  chapterTitle: string = '';
  chapterDone: number = 0;
  chapterTotal: number = 0;
  chaptersDone: number = 0;
  chaptersTotal: number = 0;
  failedChapters: number = 0;
  lastError: string = '';
}

/** 小说阅读背景六档（不依赖具体资源名，UI 侧按 key 取色）。 */
export class NovelBg {
  static readonly BLACK: string = 'black';
  static readonly NOCTURNE: string = 'nocturne';
  static readonly PLUM: string = 'plum';
  static readonly DEEP: string = 'deep';
  static readonly PAPER: string = 'paper';
  static readonly WHITE: string = 'white';
  static readonly KEYS: Array<string> = ['black', 'nocturne', 'plum', 'deep', 'paper', 'white'];

  static normalize(key: string): string {
    if (NovelBg.KEYS.indexOf(key) >= 0) {
      return key;
    }
    return NovelBg.NOCTURNE;
  }

  static color(key: string): string {
    if (key === NovelBg.BLACK) {
      return ThemeTokens.READER_BG_BLACK;
    }
    if (key === NovelBg.PLUM) {
      return ThemeTokens.READER_BG_PLUM;
    }
    if (key === NovelBg.DEEP) {
      return ThemeTokens.READER_BG_DEEP;
    }
    if (key === NovelBg.PAPER) {
      return ThemeTokens.READER_BG_PAPER;
    }
    if (key === NovelBg.WHITE) {
      return ThemeTokens.READER_BG_WHITE;
    }
    return ThemeTokens.READER_BG_NOCTURNE;
  }

  /** 文本色：纸色/白色底用深色字，其余用紫夜亮字。 */
  static textColor(key: string): string {
    if (key === NovelBg.PAPER || key === NovelBg.WHITE) {
      return '#2B2438';
    }
    return ThemeTokens.TEXT_PRIMARY;
  }

  static secondaryColor(key: string): string {
    if (key === NovelBg.PAPER || key === NovelBg.WHITE) {
      return '#6B6280';
    }
    return ThemeTokens.TEXT_HINT;
  }

  static label(key: string): string {
    if (key === NovelBg.BLACK) {
      return '纯黑';
    }
    if (key === NovelBg.PLUM) {
      return '紫梅';
    }
    if (key === NovelBg.DEEP) {
      return '深紫';
    }
    if (key === NovelBg.PAPER) {
      return '纸色';
    }
    if (key === NovelBg.WHITE) {
      return '纯白';
    }
    return '紫夜';
  }
}

/**
 * 小说 ViewModel：书架投影、阅读会话（目录/章节/进度）、阅读设置持久化、
 * 正文三态显示与分页，以及后续章节批量翻译的状态机。
 */
export class NovelViewModel {
  private static batchState: NovelBatchState = new NovelBatchState();
  private static batchCancelled: boolean = false;

  // ---------- 书架 ----------

  static async loadShelf(): Promise<Array<NovelShelfItem>> {
    return NovelRepository.getShelfItems();
  }

  static async deleteNovels(ids: Array<number>): Promise<number> {
    return NovelRepository.deleteCascade(ids);
  }

  static async loadShelfViewMode(): Promise<string> {
    try {
      const pref = await preferences.getPreferences(AppEnv.getInstance().getContext(), PREF_SHELF);
      const raw = pref.getSync(KEY_VIEW_MODE, 'grid') as string;
      return raw === 'list' ? 'list' : 'grid';
    } catch (e) {
      return 'grid';
    }
  }

  static async saveShelfViewMode(mode: string): Promise<void> {
    try {
      const pref = await preferences.getPreferences(AppEnv.getInstance().getContext(), PREF_SHELF);
      pref.putSync(KEY_VIEW_MODE, mode);
      await pref.flush();
    } catch (e) {
    }
  }

  // ---------- 阅读设置 ----------

  static async loadReaderSettings(): Promise<NovelReaderSettings> {
    const settings = new NovelReaderSettings();
    try {
      const pref = await preferences.getPreferences(AppEnv.getInstance().getContext(), PREF_READER);
      settings.fontSize = pref.getSync(KEY_FONT_SIZE, 17) as number;
      settings.lineHeight = pref.getSync(KEY_LINE_HEIGHT, 30) as number;
      settings.margin = pref.getSync(KEY_MARGIN, 18) as number;
      settings.bgKey = NovelBg.normalize(pref.getSync(KEY_BG, NovelBg.NOCTURNE) as string);
      const mode = pref.getSync(KEY_DISPLAY, NovelDisplayMode.ORIGINAL as number) as number;
      if (mode === NovelDisplayMode.TRANSLATED) {
        settings.displayMode = NovelDisplayMode.TRANSLATED;
      } else if (mode === NovelDisplayMode.BILINGUAL) {
        settings.displayMode = NovelDisplayMode.BILINGUAL;
      } else {
        settings.displayMode = NovelDisplayMode.ORIGINAL;
      }
    } catch (e) {
      // 默认值
    }
    if (settings.fontSize < 12) {
      settings.fontSize = 12;
    }
    if (settings.fontSize > 30) {
      settings.fontSize = 30;
    }
    if (settings.lineHeight < settings.fontSize * 1.2) {
      settings.lineHeight = settings.fontSize * 1.2;
    }
    if (settings.lineHeight > settings.fontSize * 3.2) {
      settings.lineHeight = settings.fontSize * 3.2;
    }
    if (settings.margin < 8) {
      settings.margin = 8;
    }
    if (settings.margin > 48) {
      settings.margin = 48;
    }
    return settings;
  }

  static async saveReaderSettings(settings: NovelReaderSettings): Promise<void> {
    try {
      const pref = await preferences.getPreferences(AppEnv.getInstance().getContext(), PREF_READER);
      pref.putSync(KEY_FONT_SIZE, settings.fontSize);
      pref.putSync(KEY_LINE_HEIGHT, settings.lineHeight);
      pref.putSync(KEY_MARGIN, settings.margin);
      pref.putSync(KEY_BG, settings.bgKey);
      pref.putSync(KEY_DISPLAY, settings.displayMode as number);
      await pref.flush();
    } catch (e) {
    }
  }

  // ---------- 阅读会话 ----------

  /** 加载会话：小说 + 目录 + 当前章 + 恢复进度偏移。 */
  static async loadSession(novelId: number, requestedChapter: number): Promise<NovelReaderSession> {
    const session = new NovelReaderSession();
    await AppEnv.ready();
    const novel: Novel | undefined = await NovelRepository.getById(novelId);
    if (novel === undefined) {
      return session;
    }
    session.novelName = novel.name;
    session.chapters = await NovelRepository.getToc(novelId);
    if (session.chapters.length === 0) {
      return session;
    }
    let index = requestedChapter >= 0 ? requestedChapter : novel.lastReadChapter;
    if (index < 0) {
      index = 0;
    }
    if (index > session.chapters.length - 1) {
      index = session.chapters.length - 1;
    }
    session.chapterIndex = index;
    session.chapter = await NovelRepository.getChapter(novelId, index);
    if (index === novel.lastReadChapter && novel.lastReadOffset > 0) {
      session.offset = novel.lastReadOffset;
    }
    return session;
  }

  static async loadChapter(novelId: number, chapterIndex: number): Promise<NovelChapter | undefined> {
    return NovelRepository.getChapter(novelId, chapterIndex);
  }

  /** 章节目录（轻量，不含正文）。 */
  static async loadChapterList(novelId: number): Promise<Array<NovelChapter>> {
    return NovelRepository.getToc(novelId);
  }

  static async saveProgress(novelId: number, chapterIndex: number, offset: number): Promise<void> {
    await NovelRepository.saveProgress(novelId, chapterIndex, offset);
  }

  // ---------- 显示与分页 ----------

  /** 正文显示文本（三态唯一来源，分页与绘制都只认它）。 */
  static displayText(chapter: NovelChapter | undefined, mode: NovelDisplayMode): string {
    if (chapter === undefined) {
      return '';
    }
    if (mode === NovelDisplayMode.ORIGINAL) {
      return chapter.content;
    }
    return ParagraphSplitter.displayText(chapter.content, chapter.translatedContent, mode);
  }

  /**
   * 分页。
   * @param text 显示文本
   * @param contentWidth 正文宽（vp）
   * @param contentHeight 正文高（vp）
   * @param settings 阅读设置
   * @param offset 恢复用的字符偏移
   */
  static paginate(text: string, contentWidth: number, contentHeight: number,
    settings: NovelReaderSettings, offset: number): Array<NovelPage> {
    return Paginator.paginate(text, contentWidth, contentHeight, settings.fontSize,
      settings.lineHeight, offset);
  }

  /** 页码展示：第 X/Y 页。 */
  static pageLabel(pageIndex: number, pageCount: number): string {
    return (pageIndex + 1) + ' / ' + (pageCount > 0 ? pageCount : 1);
  }

  static chapterLabel(chapter: NovelChapter | undefined, chapterIndex: number): string {
    if (chapter !== undefined && chapter.title !== undefined && chapter.title.length > 0) {
      return chapter.title;
    }
    return '第' + (chapterIndex + 1) + '章';
  }

  // ---------- 章节批量翻译 ----------

  static currentBatch(): NovelBatchState {
    return NovelViewModel.copyBatch(NovelViewModel.batchState);
  }

  static cancelBatch(): void {
    NovelViewModel.batchCancelled = true;
    NovelViewModel.batchState.cancelRequested = true;
  }

  /**
   * 批量翻译后续章节（从 fromChapter+1 开始，最多 count 章）。
   * 串行执行，逐章回调状态；取消时当前章收尾后停止。
   */
  static startBatch(novelId: number, fromChapter: number, count: number, engineType: EngineType,
    onState: (s: NovelBatchState) => void): void {
    if (NovelViewModel.batchState.running || novelId < 0) {
      return;
    }
    const state = new NovelBatchState();
    state.running = true;
    NovelViewModel.batchState = state;
    NovelViewModel.batchCancelled = false;
    NovelViewModel.runBatch(novelId, fromChapter, count, engineType, onState);
  }

  private static async runBatch(novelId: number, fromChapter: number, count: number,
    engineType: EngineType, onState: (s: NovelBatchState) => void): Promise<void> {
    const state = NovelViewModel.batchState;
    try {
      await NovelRepository.markTranslating(novelId);
      const toc = await NovelRepository.getToc(novelId);
      const start = fromChapter + 1;
      let total = toc.length - start;
      if (total < 0) {
        total = 0;
      }
      if (total > count) {
        total = count;
      }
      state.chaptersTotal = total;
      state.chaptersDone = 0;
      state.failedChapters = 0;
      onState(NovelViewModel.copyBatch(state));
      for (let k = 0; k < total; k++) {
        if (NovelViewModel.batchCancelled) {
          break;
        }
        const index = start + k;
        state.chapterIndex = index;
        state.chapterTitle = NovelViewModel.chapterTitleOf(toc, index);
        state.chapterDone = 0;
        state.chapterTotal = 0;
        onState(NovelViewModel.copyBatch(state));
        const chapter = await NovelRepository.getChapter(novelId, index);
        if (chapter === undefined) {
          continue;
        }
        const result: NovelTranslateResult = await NovelTranslateService.translateChapter(chapter,
          engineType, (done: number, paraTotal: number) => {
            state.chapterDone = done;
            state.chapterTotal = paraTotal;
            onState(NovelViewModel.copyBatch(state));
          }, () => NovelViewModel.batchCancelled);
        state.chaptersDone = k + 1;
        if (result.failedParagraphs > 0 || result.status === TranslateStatus.PARTIAL_FAILED) {
          state.failedChapters++;
          if (result.failReason.length > 0) {
            state.lastError = result.failReason;
          }
        }
        onState(NovelViewModel.copyBatch(state));
      }
      state.running = false;
      state.cancelRequested = NovelViewModel.batchCancelled;
      onState(NovelViewModel.copyBatch(state));
    } catch (e) {
      state.running = false;
      state.lastError = NovelTranslateService.readableError(e);
      onState(NovelViewModel.copyBatch(state));
      Log.error(TAG, 'batch translate failed: ' + e);
    }
  }

  private static chapterTitleOf(chapters: Array<NovelChapter>, index: number): string {
    if (index >= 0 && index < chapters.length) {
      const title = chapters[index].title;
      if (title !== undefined && title.length > 0) {
        return title;
      }
    }
    return '第' + (index + 1) + '章';
  }

  private static copyBatch(source: NovelBatchState): NovelBatchState {
    const copy = new NovelBatchState();
    copy.running = source.running;
    copy.cancelRequested = source.cancelRequested;
    copy.chapterIndex = source.chapterIndex;
    copy.chapterTitle = source.chapterTitle;
    copy.chapterDone = source.chapterDone;
    copy.chapterTotal = source.chapterTotal;
    copy.chaptersDone = source.chaptersDone;
    copy.chaptersTotal = source.chaptersTotal;
    copy.failedChapters = source.failedChapters;
    copy.lastError = source.lastError;
    return copy;
  }
}
