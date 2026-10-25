/**
 * Centralized Navigation route table and typed route params.
 * All NavDestination page names are declared here; push via
 * AppEnv.getInstance().navStack.pushPathByName(Routes.XXX, params).
 */
export class Routes {
  // MVP-1
  static readonly READER: string = 'ReaderPage';
  static readonly MODEL_MANAGER: string = 'ModelManagerPage';
  static readonly SPIKE_WORKBENCH: string = 'SpikeWorkbenchPage';
  static readonly SPIKE_IMPORT: string = 'SpikeImportPage';
  static readonly SPIKE_OCR: string = 'SpikeOcrPage';
  static readonly SPIKE_RENDER: string = 'SpikeRenderPage';
  static readonly SPIKE_NAPI: string = 'SpikeNapiPage';
  static readonly SPIKE_ENGINE: string = 'SpikeEnginePage';
  static readonly ABOUT: string = 'AboutPage';
  // MVP-2 (stage 2)
  static readonly NOVEL_READER: string = 'NovelReaderPage';
  static readonly NOVEL_TOC: string = 'NovelTocPage';
  static readonly MANGA_TOC: string = 'MangaTocPage';
  static readonly IMPORT_WIZARD: string = 'ImportWizardPage';
  static readonly HISTORY_DETAIL: string = 'HistoryDetailPage';
  static readonly HISTORY_FULLSCREEN: string = 'HistoryFullscreenPage';
  static readonly SETTINGS: string = 'SettingsPage';
  static readonly SETTINGS_READING: string = 'SettingsReadingPage';
  static readonly SETTINGS_TRANSLATE: string = 'SettingsTranslatePage';
  static readonly SETTINGS_OCR: string = 'SettingsOcrPage';
  static readonly SETTINGS_THEME: string = 'SettingsThemePage';
  static readonly API_CONFIG: string = 'ApiConfigPage';
  static readonly FAQ: string = 'FaqPage';
  static readonly OPEN_SOURCE: string = 'OpenSourcePage';
  static readonly ONBOARDING: string = 'OnboardingPage';
  static readonly IMAGE_VIEWER: string = 'ImageViewerPage';
  static readonly TEXT_HISTORY: string = 'TextHistoryPage';
}

/** Params for ReaderPage (manga). */
export interface ReaderParams {
  mangaId: number;
  /** Optional 0-based page to open directly (TOC / history jump). */
  startPage?: number;
}

/** Params for NovelReaderPage. */
export interface NovelReaderParams {
  novelId: number;
  chapterIndex?: number;
}

/** Params for history detail. */
export interface HistoryDetailParams {
  kind: number; // 0=manga page 1=novel chapter 2=text translation
  refId: number;
}

/** Params for import wizard. */
export interface ImportWizardParams {
  kind: number; // 0=manga 1=novel
}

/** Params for fullscreen history pager. */
export interface HistoryFullscreenParams {
  sessionId: string;
}

export function makeReaderParams(mangaId: number, startPage?: number): ReaderParams {
  const p: ReaderParams = { mangaId: mangaId };
  if (startPage !== undefined) {
    p.startPage = startPage;
  }
  return p;
}

export function asReaderParams(raw: Object): ReaderParams {
  const p = raw as ReaderParams;
  if (p !== undefined && p !== null && typeof p.mangaId === 'number') {
    return p;
  }
  return makeReaderParams(-1);
}

export function makeNovelReaderParams(novelId: number, chapterIndex?: number): NovelReaderParams {
  const p: NovelReaderParams = { novelId: novelId };
  if (chapterIndex !== undefined) {
    p.chapterIndex = chapterIndex;
  }
  return p;
}

export function asNovelReaderParams(raw: Object): NovelReaderParams {
  const p = raw as NovelReaderParams;
  if (p !== undefined && p !== null && typeof p.novelId === 'number') {
    return p;
  }
  return makeNovelReaderParams(-1);
}

export function makeHistoryDetailParams(kind: number, refId: number): HistoryDetailParams {
  const p: HistoryDetailParams = { kind: kind, refId: refId };
  return p;
}

export function asHistoryDetailParams(raw: Object): HistoryDetailParams {
  const p = raw as HistoryDetailParams;
  if (p !== undefined && p !== null && typeof p.refId === 'number') {
    return p;
  }
  return makeHistoryDetailParams(0, -1);
}

export function makeImportWizardParams(kind: number): ImportWizardParams {
  const p: ImportWizardParams = { kind: kind };
  return p;
}

export function asImportWizardParams(raw: Object): ImportWizardParams {
  const p = raw as ImportWizardParams;
  if (p !== undefined && p !== null && typeof p.kind === 'number') {
    return p;
  }
  return makeImportWizardParams(0);
}
