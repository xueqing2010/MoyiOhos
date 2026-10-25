import fs from '@ohos.file.fs';
import { BusinessError } from '@kit.BasicServicesKit';
import { Manga, SourceType, PageDao } from 'coremodel';
import { Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { MangaRepository } from '../data/MangaRepository';
import { ImportService } from './ImportService';

const TAG = 'DemoDataService';

/** 示例漫画固定名称：重复点击时检出同一条记录并复用。 */
export const DEMO_MANGA_NAME: string = '示例漫画 · 紫夜';
/** rawfile/demo/manga 下的示例页数（page_01..page_06.png）。 */
const DEMO_PAGE_COUNT: number = 6;
const DEMO_RAWFILE_DIR: string = 'demo/manga';

/** 示例数据生成结果（供导入面板/工作台回显）。 */
export class DemoDataResult {
  manga: Manga | undefined = undefined;
  created: boolean = false;
  message: string = '';
}

/**
 * 示例数据服务（stage-2 / S102 / QA-4）：
 * 无外部物料时端到端验证导入→书架→阅读器。把 rawfile/demo/manga/page_01..06.png
 * 复制进应用沙箱（files/manga/demo-<ts>/），建档 Manga（ARCHIVE 来源）+ 6 页并回写封面。
 * 幂等：已存在且页面文件完整时直接复用，不重复生成；记录损坏时清理后重建。
 * 小说示例由 novel 模块负责，本服务不做。
 */
export class DemoDataService {
  /** 生成中的单飞控制：避免连点/双入口并发建出两条示例记录。 */
  private static inFlight: Promise<DemoDataResult> | undefined = undefined;

  /** 生成（或复用）示例漫画，返回结果与提示文案（并发调用复用同一 Promise）。 */
  static async generateSampleManga(): Promise<DemoDataResult> {
    const running = DemoDataService.inFlight;
    if (running !== undefined) {
      return running;
    }
    const task = DemoDataService.doGenerateSampleManga();
    DemoDataService.inFlight = task;
    try {
      return await task;
    } finally {
      DemoDataService.inFlight = undefined;
    }
  }

  private static async doGenerateSampleManga(): Promise<DemoDataResult> {
    await AppEnv.ready();
    const result = new DemoDataResult();
    const existing = await DemoDataService.findSampleManga();
    if (existing !== undefined) {
      const intact = await DemoDataService.sampleIntact(existing);
      if (intact) {
        result.manga = existing;
        result.created = false;
        result.message = `示例漫画已存在（${existing.pageCount} 页），可直接阅读`;
        return result;
      }
      Log.warn(TAG, 'sample manga record is broken, rebuilding');
      await DemoDataService.removeManga(existing);
    }
    const manga = await DemoDataService.createSample();
    result.manga = manga;
    result.created = true;
    result.message = `已生成「${DEMO_MANGA_NAME}」（${manga.pageCount} 页）`;
    return result;
  }

  /** 是否已有可用的示例漫画。 */
  static async hasSampleManga(): Promise<boolean> {
    const m = await DemoDataService.findSampleManga();
    if (m === undefined) {
      return false;
    }
    return await DemoDataService.sampleIntact(m);
  }

  /** 按名称查找示例漫画记录（不校验文件）。 */
  static async findSampleManga(): Promise<Manga | undefined> {
    try {
      await AppEnv.ready();
      const list = await MangaRepository.listAll();
      for (const m of list) {
        if (m.name === DEMO_MANGA_NAME) {
          return m;
        }
      }
    } catch (e) {
      Log.warn(TAG, `find sample failed: ${e}`);
    }
    return undefined;
  }

  /** 显式移除示例漫画（含沙箱目录/页面/译文级联）；书架删除也走同一清理路径。 */
  static async removeSampleManga(): Promise<void> {
    const m = await DemoDataService.findSampleManga();
    if (m !== undefined) {
      await DemoDataService.removeManga(m);
    }
  }

  private static async removeManga(m: Manga): Promise<void> {
    try {
      await MangaRepository.deleteCascade(m.id);
    } catch (e) {
      Log.warn(TAG, `delete sample rows failed: ${e}`);
    }
    const dir = DemoDataService.sandboxDemoDir(m);
    if (dir.length > 0) {
      ImportService.rmRecursive(dir);
    }
  }

  /** 记录里的页面是否全部存在（用于幂等判定与损坏自愈）。 */
  private static async sampleIntact(m: Manga): Promise<boolean> {
    if (m.pageCount < DEMO_PAGE_COUNT) {
      return false;
    }
    try {
      const pages = await PageDao.queryByMangaId(m.id);
      if (pages.length < DEMO_PAGE_COUNT) {
        return false;
      }
      for (const p of pages) {
        if (!fs.accessSync(p.imagePath)) {
          return false;
        }
      }
      return true;
    } catch (e) {
      Log.warn(TAG, `sample intact check failed: ${e}`);
      return false;
    }
  }

  /** 真正生成：复制 rawfile → 沙箱 → 建档 + 页记录 + 封面。 */
  private static async createSample(): Promise<Manga> {
    const ctx = AppEnv.getInstance().getContext();
    const demoDir = `${ctx.filesDir}/manga/demo-${Date.now()}`;
    let shell: Manga | undefined = undefined;
    try {
      fs.mkdirSync(demoDir, true);
      const pagePaths: Array<string> = [];
      for (let i = 1; i <= DEMO_PAGE_COUNT; i++) {
        const rawName = `${DEMO_RAWFILE_DIR}/page_${DemoDataService.pad2(i)}.png`;
        const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(rawName);
        const dest = `${demoDir}/page-${DemoDataService.pad4(i)}.png`;
        DemoDataService.writeBytes(dest, bytes.buffer as ArrayBuffer);
        pagePaths.push(dest);
      }
      // ARCHIVE 来源；sourceUri 记录示例沙箱目录，删除时据此清理。
      shell = await MangaRepository.createMangaShell(DEMO_MANGA_NAME, SourceType.ARCHIVE, demoDir,
        pagePaths.length);
      // replacePages 会写回 page_count/cover_path（首页封面）。
      await MangaRepository.replacePages(shell, pagePaths);
      Log.info(TAG, `sample manga created: id=${shell.id}, pages=${pagePaths.length}`);
      return shell;
    } catch (e) {
      if (shell !== undefined) {
        try {
          await MangaRepository.deleteCascade(shell.id);
        } catch (e2) {
          Log.warn(TAG, `rollback sample rows failed: ${e2}`);
        }
      }
      ImportService.rmRecursive(demoDir);
      throw new Error(`生成示例漫画失败：${DemoDataService.readableError(e)}`);
    }
  }

  /** 仅当 sourceUri 位于本应用沙箱内时才返回目录（避免误删公共目录）。 */
  private static sandboxDemoDir(m: Manga): string {
    const uri = m.sourceUri;
    if (uri === undefined || uri.length === 0) {
      return '';
    }
    const filesDir = AppEnv.getInstance().getContext().filesDir;
    if (uri.startsWith(filesDir)) {
      return uri;
    }
    return '';
  }

  private static writeBytes(dest: string, bytes: ArrayBuffer): void {
    const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes);
    } finally {
      fs.closeSync(file);
    }
  }

  private static pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  private static pad4(n: number): string {
    if (n < 10) {
      return `000${n}`;
    }
    if (n < 100) {
      return `00${n}`;
    }
    if (n < 1000) {
      return `0${n}`;
    }
    return `${n}`;
  }

  private static readableError(e: Object): string {
    const err = e as BusinessError;
    if (err.code === 13900002) {
      return '示例页面资源缺失（rawfile/demo/manga）';
    }
    if (err.code === 13900025) {
      return '存储空间不足';
    }
    if (err.message !== undefined && err.message.length > 0) {
      return err.message;
    }
    return `${e}`;
  }
}
