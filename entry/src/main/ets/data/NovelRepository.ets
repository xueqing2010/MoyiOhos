import fs from '@ohos.file.fs';
import {
  Novel,
  NovelChapter,
  NovelFormat,
  TranslateStatus,
  NovelDao,
  NovelChapterDao,
  makeNovel,
  makeNovelChapter
} from 'coremodel';
import { ParsedNovel, ParsedChapter } from 'corenovel';
import { Log } from 'commons';
import { AppEnv } from '../common/AppEnv';

const TAG = 'NovelRepository';

/** 书架展示用的小说投影（避免 UI 直接遍历 DB 实体）。 */
export class NovelShelfItem {
  id: number = 0;
  name: string = '';
  format: number = 0;
  formatLabel: string = 'TXT';
  chapterCount: number = 0;
  doneChapters: number = 0;
  translateStatus: TranslateStatus = TranslateStatus.NONE;
  statusLabel: string = '未翻译';
  coverPath: string = '';
  lastReadChapter: number = 0;
  lastReadOffset: number = 0;
  createdAt: number = 0;
  updatedAt: number = 0;
  progressLabel: string = '';
}

/** 章节翻译状态统计。 */
export class ChapterStats {
  total: number = 0;
  done: number = 0;
  partial: number = 0;
}

/**
 * 小说数据仓库：封装 NovelDao / NovelChapterDao，负责建档、级联删除、
 * 进度与译文落库、书架投影；沙箱源文件目录由本类统一提供。
 */
export class NovelRepository {
  /** 每本小说的沙箱目录：<filesDir>/novel/<novelId>/ */
  static novelDir(novelId: number): string {
    return AppEnv.getInstance().getContext().filesDir + '/novel/' + novelId;
  }

  /** 解析结果落库：novel + 全部章节。 */
  static async createFromParsed(parsed: ParsedNovel, sourceUri: string, coverPath: string): Promise<Novel> {
    await AppEnv.ready();
    const format: NovelFormat = parsed.format as NovelFormat;
    const novel = makeNovel(parsed.title, format, parsed.chapters.length);
    novel.sourceUri = sourceUri;
    novel.coverPath = coverPath;
    novel.translateStatus = TranslateStatus.NONE;
    await NovelDao.insert(novel);

    const chapters: Array<NovelChapter> = [];
    for (let i = 0; i < parsed.chapters.length; i++) {
      const pc: ParsedChapter = parsed.chapters[i];
      const chapter = makeNovelChapter(novel.id, i, pc.title, pc.content);
      chapters.push(chapter);
    }
    await NovelChapterDao.insertBatch(chapters);
    Log.info(TAG, 'created novel ' + novel.id + ': ' + novel.name + ', chapters=' + chapters.length);
    return novel;
  }

  /** 把临时源文件移入小说沙箱目录，返回最终路径（失败返回空串，不影响阅读）。 */
  static async placeSource(novelId: number, tempPath: string, ext: string): Promise<string> {
    const dir = NovelRepository.novelDir(novelId);
    const dest = dir + '/source' + ext;
    try {
      fs.mkdirSync(dir, true);
      try {
        fs.renameSync(tempPath, dest);
      } catch (e) {
        fs.copyFileSync(tempPath, dest);
        try {
          fs.unlinkSync(tempPath);
        } catch (ignore) {
        }
      }
      return dest;
    } catch (e) {
      Log.warn(TAG, 'place source failed: ' + e);
      return '';
    }
  }

  static async list(): Promise<Array<Novel>> {
    await AppEnv.ready();
    return NovelDao.queryAll();
  }

  static async getById(novelId: number): Promise<Novel | undefined> {
    await AppEnv.ready();
    if (novelId < 0) {
      return undefined;
    }
    return NovelDao.queryById(novelId);
  }

  /** 章节目录（不带正文，轻量）。 */
  static async getToc(novelId: number): Promise<Array<NovelChapter>> {
    await AppEnv.ready();
    if (novelId < 0) {
      return [];
    }
    return NovelChapterDao.queryTocByNovelId(novelId);
  }

  /** 单章完整内容。 */
  static async getChapter(novelId: number, chapterIndex: number): Promise<NovelChapter | undefined> {
    await AppEnv.ready();
    return NovelChapterDao.queryByIndex(novelId, chapterIndex);
  }

  /** 全部章节（含正文；仅导入校验/导出等重场景使用）。 */
  static async getChapters(novelId: number): Promise<Array<NovelChapter>> {
    await AppEnv.ready();
    return NovelChapterDao.queryByNovelId(novelId);
  }

  /** 归档源文件后更新 source_uri（失败忽略）。 */
  static async updateSourceUri(novelId: number, sourcePath: string): Promise<void> {
    try {
      const novel = await NovelDao.queryById(novelId);
      if (novel !== undefined) {
        novel.sourceUri = sourcePath;
        await NovelDao.update(novel);
      }
    } catch (e) {
      Log.warn(TAG, 'update source uri failed: ' + e);
    }
  }

  /** 书架投影：章节数/翻译进度/上次阅读位置。 */
  static async getShelfItems(): Promise<Array<NovelShelfItem>> {
    const novels = await NovelRepository.list();
    const items: Array<NovelShelfItem> = [];
    for (let i = 0; i < novels.length; i++) {
      const novel = novels[i];
      const item = new NovelShelfItem();
      item.id = novel.id;
      item.name = novel.name;
      item.format = novel.format;
      item.formatLabel = NovelRepository.formatLabel(novel.format);
      item.coverPath = novel.coverPath !== undefined ? novel.coverPath : '';
      item.lastReadChapter = novel.lastReadChapter;
      item.lastReadOffset = novel.lastReadOffset;
      item.createdAt = novel.createdAt;
      item.updatedAt = novel.updatedAt;
      const stats = await NovelRepository.chapterStats(novel.id);
      item.chapterCount = stats.total > 0 ? stats.total : novel.chapterCount;
      item.doneChapters = stats.done;
      if (stats.total > 0 && stats.done === stats.total) {
        item.translateStatus = TranslateStatus.DONE;
        item.statusLabel = '已翻译';
      } else if (stats.done > 0 || stats.partial > 0) {
        item.translateStatus = TranslateStatus.PARTIAL_FAILED;
        item.statusLabel = '部分翻译';
      } else {
        item.translateStatus = TranslateStatus.NONE;
        item.statusLabel = '未翻译';
      }
      if (novel.lastReadChapter > 0) {
        item.progressLabel = '读到第' + (novel.lastReadChapter + 1) + '章';
      } else if (novel.lastReadOffset > 0) {
        item.progressLabel = '上次阅读第1章';
      }
      items.push(item);
    }
    return items;
  }

  /** 统计某本小说的章节翻译状态。 */
  static async chapterStats(novelId: number): Promise<ChapterStats> {
    const toc = await NovelChapterDao.queryTocByNovelId(novelId);
    const stats = new ChapterStats();
    stats.total = toc.length;
    for (let i = 0; i < toc.length; i++) {
      if (toc[i].translateStatus === TranslateStatus.DONE) {
        stats.done++;
      } else if (toc[i].translateStatus === TranslateStatus.PARTIAL_FAILED) {
        stats.partial++;
      }
    }
    return stats;
  }

  /** 多选删除：连带章节、译文与沙箱源文件。返回删除成功数量。 */
  static async deleteCascade(novelIds: Array<number>): Promise<number> {
    await AppEnv.ready();
    let deleted = 0;
    for (let i = 0; i < novelIds.length; i++) {
      const id = novelIds[i];
      try {
        await NovelChapterDao.deleteByNovelId(id);
        await NovelDao.deleteById(id);
        NovelRepository.rmDir(NovelRepository.novelDir(id));
        deleted++;
      } catch (e) {
        Log.warn(TAG, 'delete novel ' + id + ' failed: ' + e);
      }
    }
    return deleted;
  }

  /** 保存阅读进度。 */
  static async saveProgress(novelId: number, chapterIndex: number, offset: number): Promise<void> {
    try {
      await NovelDao.updateReadingProgress(novelId, chapterIndex, offset);
    } catch (e) {
      Log.error('NovelRepository', `saveProgress failed novel=${novelId}: ${e}`);
    }
  }

  /** 保存章节译文并同步小说级翻译状态。 */
  static async saveChapterTranslation(chapterId: number, translated: string,
    status: TranslateStatus, failReason?: string): Promise<void> {
    await NovelChapterDao.updateTranslation(chapterId, translated, status, failReason);
  }

  /** 依据章节状态重算小说级翻译状态。 */
  static async refreshTranslateStatus(novelId: number): Promise<TranslateStatus> {
    const stats = await NovelRepository.chapterStats(novelId);
    let status = TranslateStatus.NONE;
    if (stats.total > 0 && stats.done === stats.total) {
      status = TranslateStatus.DONE;
    } else if (stats.done > 0 || stats.partial > 0) {
      status = TranslateStatus.PARTIAL_FAILED;
    }
    await NovelDao.updateTranslateStatus(novelId, status);
    return status;
  }

  /** 更新小说级状态为翻译中。 */
  static async markTranslating(novelId: number): Promise<void> {
    try {
      await NovelDao.updateTranslateStatus(novelId, TranslateStatus.RUNNING);
    } catch (e) {
    }
  }

  // ---------- 工具 ----------

  static formatLabel(format: number): string {
    if (format === NovelFormat.EPUB) {
      return 'EPUB';
    }
    if (format === NovelFormat.ZIP_HTML) {
      return 'ZIP-HTML';
    }
    return 'TXT';
  }

  /** 递归删除目录（SDK rmdir 非递归）。 */
  static rmDir(path: string): void {
    let isDir = false;
    try {
      isDir = fs.statSync(path).isDirectory();
    } catch (e) {
      return;
    }
    if (!isDir) {
      try {
        fs.unlinkSync(path);
      } catch (e) {
      }
      return;
    }
    try {
      const children = fs.listFileSync(path);
      for (let i = 0; i < children.length; i++) {
        NovelRepository.rmDir(path + '/' + children[i]);
      }
      fs.rmdirSync(path);
    } catch (e) {
      Log.warn(TAG, 'rmDir failed: ' + path);
    }
  }
}
