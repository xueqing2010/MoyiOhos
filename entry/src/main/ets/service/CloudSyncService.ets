import fs from '@ohos.file.fs';
import { cloudStorage } from '@kit.CloudFoundationKit';
import { common } from '@kit.AbilityKit';
import { Log } from 'commons';
import { MangaDao, NovelDao } from 'coremodel';
import { AppEnv } from '../common/AppEnv';
import { SettingsKeys, SettingsRepository } from '../data/SettingsRepository';
import { AccountService } from './AccountService';

const TAG = 'CloudSyncService';
const BACKUP_FILE = 'starflow-backup.json';
const CLOUD_PATH = 'starflow/starflow-backup.json';

interface BackupSettings {
  theme: string;
  targetLang: string;
  ocrLang: string;
  engine: number;
}

interface MangaBackup {
  name: string;
  pageCount: number;
  lastReadPage: number;
  translateStatus: number;
}

interface NovelBackup {
  name: string;
  chapterCount: number;
  lastReadChapter: number;
}

interface BackupPayload {
  version: number;
  savedAt: number;
  openId: string;
  settings: BackupSettings;
  mangas: Array<MangaBackup>;
  novels: Array<NovelBackup>;
}

export interface CloudBackupInfo {
  mangas: number;
  novels: number;
  savedAt: number;
}

/**
 * 华为云盘同步（Cloud Foundation Kit 云存储）：保存书架索引、进度与设置到应用云存储桶。
 * 前置条件：AGC 已开通云存储、签名与 AGC 项目匹配、已登录华为账号；
 * 任一不满足时返回可读错误，不影响本地使用。
 */
export class CloudSyncService {
  static async backup(context: common.UIAbilityContext): Promise<CloudBackupInfo> {
    if (!(await AccountService.isLoggedIn())) {
      throw new Error('请先登录华为账号');
    }
    const mangas = await MangaDao.queryAll();
    const novels = await NovelDao.queryAll();
    const settings: BackupSettings = {
      theme: await SettingsRepository.getString(SettingsKeys.THEME_MODE, 'purple'),
      targetLang: await SettingsRepository.getString(SettingsKeys.TARGET_LANG, 'zh'),
      ocrLang: await SettingsRepository.getString(SettingsKeys.OCR_LANG, 'ja'),
      engine: await SettingsRepository.getNumber(SettingsKeys.ENGINE_TYPE, 0)
    };
    const mangaItems: Array<MangaBackup> = mangas.map((m): MangaBackup => {
      const item: MangaBackup = {
        name: m.name,
        pageCount: m.pageCount,
        lastReadPage: m.lastReadPage,
        translateStatus: m.translateStatus as number
      };
      return item;
    });
    const novelItems: Array<NovelBackup> = novels.map((n): NovelBackup => {
      const item: NovelBackup = {
        name: n.name,
        chapterCount: n.chapterCount,
        lastReadChapter: n.lastReadChapter
      };
      return item;
    });
    const payload: BackupPayload = {
      version: 1,
      savedAt: Date.now(),
      openId: await AccountService.openId(),
      settings: settings,
      mangas: mangaItems,
      novels: novelItems
    };
    const json = JSON.stringify(payload);
    const cachePath = AppEnv.getInstance().getContext().cacheDir;
    const localPath = cachePath + '/' + BACKUP_FILE;
    const file = fs.openSync(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, json);
    } finally {
      fs.closeSync(file);
    }
    try {
      const task = await cloudStorage.bucket().uploadFile(context, {
        localPath: BACKUP_FILE,
        cloudPath: CLOUD_PATH
      });
      // 上传任务由 request.agent 管理；监听完成/失败，最多等 20s。
      await new Promise<void>((resolve, reject) => {
        let settled = false;
        const timer = setTimeout(() => {
          if (!settled) {
            settled = true;
            resolve();
          }
        }, 20000);
        task.on('completed', () => {
          if (!settled) {
            settled = true;
            clearTimeout(timer);
            resolve();
          }
        });
        task.on('failed', () => {
          if (!settled) {
            settled = true;
            clearTimeout(timer);
            reject(new Error('云存储上传失败'));
          }
        });
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      Log.warn(TAG, 'cloud upload failed: ' + msg);
      throw new Error('云同步不可用：请在 AGC 开通云存储并使用匹配签名的正式应用（' + msg + '）');
    }
    await SettingsRepository.set(SettingsKeys.CLOUD_SYNC_LAST, Date.now());
    const info: CloudBackupInfo = { mangas: mangas.length, novels: novels.length, savedAt: Date.now() };
    return info;
  }

  /** 下载云端最近备份并恢复设置（书架文件仍需本机存在，故只恢复偏好）。 */
  static async restore(context: common.UIAbilityContext): Promise<string> {
    if (!(await AccountService.isLoggedIn())) {
      throw new Error('请先登录华为账号');
    }
    const cachePath = AppEnv.getInstance().getContext().cacheDir;
    try {
      await cloudStorage.bucket().downloadFile(context, {
        localPath: BACKUP_FILE,
        cloudPath: CLOUD_PATH
      });
      const text = fs.readTextSync(cachePath + '/' + BACKUP_FILE);
      const data = JSON.parse(text) as BackupPayload;
      if (data.settings !== undefined) {
        await SettingsRepository.set(SettingsKeys.THEME_MODE, data.settings.theme);
        await SettingsRepository.set(SettingsKeys.TARGET_LANG, data.settings.targetLang);
        await SettingsRepository.set(SettingsKeys.OCR_LANG, data.settings.ocrLang);
      }
      return '已从华为云恢复设置备份';
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      throw new Error('云端恢复失败：' + msg);
    }
  }

  static async lastSyncAt(): Promise<number> {
    return await SettingsRepository.getNumber(SettingsKeys.CLOUD_SYNC_LAST, 0);
  }
}
