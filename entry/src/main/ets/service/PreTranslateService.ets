import { MangaPage, NovelChapter, TranslateStatus } from 'coremodel';
import { EngineType } from 'coretranslate';
import { Log } from 'commons';
import { PageRepository } from '../data/PageRepository';
import { NovelRepository } from '../data/NovelRepository';
import { SettingsKeys, SettingsRepository } from '../data/SettingsRepository';
import { PageTranslateService } from './PageTranslateService';
import { NovelTranslateService } from './NovelTranslateService';
import { BatchTranslateService } from './BatchTranslateService';

const TAG = 'PreTranslateService';

/**
 * 阅读预翻译：打开阅读器后，在后台串行翻译后续 N 页/章。
 * 与整本翻译的 BatchTranslateService 互斥；关闭开关或切换书籍时取消。
 */
export class PreTranslateService {
  private static running: boolean = false;
  private static generation: number = 0;

  static async isEnabled(): Promise<boolean> {
    try {
      return await SettingsRepository.getBool(SettingsKeys.PRETRANSLATE_ENABLED, true);
    } catch (e) {
      return false;
    }
  }

  static async aheadCount(): Promise<number> {
    try {
      const n = await SettingsRepository.getNumber(SettingsKeys.PRETRANSLATE_AHEAD, 3);
      return Math.max(1, Math.min(10, Math.round(n)));
    } catch (e) {
      return 3;
    }
  }

  static cancel(): void {
    PreTranslateService.generation++;
    PreTranslateService.running = false;
  }

  static async prefetchManga(mangaId: number, currentIndex: number): Promise<void> {
    if (PreTranslateService.running || !(await PreTranslateService.isEnabled())) {
      return;
    }
    if (BatchTranslateService.getInstance().isRunning()) {
      return;
    }
    const gen = ++PreTranslateService.generation;
    PreTranslateService.running = true;
    try {
      const pages: Array<MangaPage> = await PageRepository.getPages(mangaId);
      const ahead = await PreTranslateService.aheadCount();
      const engine: EngineType = await PageTranslateService.loadEngineType();
      for (let i = currentIndex + 1; i < pages.length && i <= currentIndex + ahead; i++) {
        if (gen !== PreTranslateService.generation) {
          return;
        }
        const page = pages[i];
        if (page.translateStatus === TranslateStatus.DONE) {
          continue;
        }
        try {
          await PageTranslateService.translatePage(page.id, engine);
          Log.info(TAG, 'prefetched page ' + page.pageIndex);
        } catch (e) {
          Log.warn(TAG, 'prefetch page failed: ' + e);
        }
      }
    } catch (e) {
      Log.warn(TAG, 'prefetch manga failed: ' + e);
    } finally {
      if (gen === PreTranslateService.generation) {
        PreTranslateService.running = false;
      }
    }
  }

  static async prefetchNovel(novelId: number, currentChapter: number): Promise<void> {
    if (PreTranslateService.running || !(await PreTranslateService.isEnabled())) {
      return;
    }
    const gen = ++PreTranslateService.generation;
    PreTranslateService.running = true;
    try {
      const toc: Array<NovelChapter> = await NovelRepository.getToc(novelId);
      const ahead = await PreTranslateService.aheadCount();
      const engine: EngineType = await NovelTranslateService.loadEngineType();
      for (let i = currentChapter + 1; i < toc.length && i <= currentChapter + ahead; i++) {
        if (gen !== PreTranslateService.generation) {
          return;
        }
        const item = toc[i];
        if (item.translateStatus === TranslateStatus.DONE) {
          continue;
        }
        const chapter = await NovelRepository.getChapter(novelId, i);
        if (chapter === undefined) {
          continue;
        }
        try {
          await NovelTranslateService.translateChapter(chapter, engine);
          Log.info(TAG, 'prefetched chapter ' + i);
        } catch (e) {
          Log.warn(TAG, 'prefetch chapter failed: ' + e);
        }
      }
    } catch (e) {
      Log.warn(TAG, 'prefetch novel failed: ' + e);
    } finally {
      if (gen === PreTranslateService.generation) {
        PreTranslateService.running = false;
      }
    }
  }
}
