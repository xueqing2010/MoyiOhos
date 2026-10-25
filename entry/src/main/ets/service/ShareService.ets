import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor, unifiedDataChannel } from '@kit.ArkData';
import { systemShare, harmonyShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import { Log } from 'commons';
import { Manga, MangaDao, PageDao } from 'coremodel';
import { AppEnv } from '../common/AppEnv';
import { ImportService } from './ImportService';

const TAG = 'ShareService';

/**
 * Share Kit 封装：
 *  · 漫画华为分享：把最多 50 页图片作为一批 SharedRecord 交给系统分享面板；
 *  · 碰一碰分享：harmonyShare.on('knockShare') 检测到碰一碰后分享当前漫画；
 *  · 碰一碰导入：harmonyShare.on('dataReceive') 把收到的文件落到缓存目录并回调导入。
 * 设备/模拟器不支持 Harmony Share 时全部降级为日志，不影响其它功能。
 */
export class ShareService {
  private static knockMangaId: number = -1;
  private static receiverRegistered: boolean = false;
  private static senderRegistered: boolean = false;

  /** 书架长按/菜单里设置「碰一碰要分享的漫画」。 */
  static setKnockManga(id: number): void {
    ShareService.knockMangaId = id;
  }

  static async shareManga(context: common.UIAbilityContext, mangaId: number): Promise<number> {
    const manga = await MangaDao.queryById(mangaId);
    if (manga === undefined) {
      throw new Error('漫画不存在');
    }
    const pages = await PageDao.queryByMangaId(mangaId);
    if (pages.length === 0) {
      throw new Error('漫画没有页面');
    }
    const data = ShareService.buildMangaData(manga, pages.map(p => p.imagePath));
    const controller = new systemShare.ShareController(data);
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.BATCH,
      previewMode: systemShare.SharePreviewMode.DETAIL
    });
    return pages.length;
  }

  private static buildMangaData(manga: Manga, paths: Array<string>): systemShare.SharedData {
    const max = paths.length > 50 ? 50 : paths.length;
    if (max === 0) {
      throw new Error('没有可分享页面');
    }
    const first: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.IMAGE,
      uri: fileUri.getUriFromPath(paths[0]),
      title: manga.name + ' · 第 1 页',
      description: '来自星译 StarFlow 的漫画页面',
      label: 'IMAGE'
    };
    const data = new systemShare.SharedData(first);
    for (let i = 1; i < max; i++) {
      data.addRecord({
        utd: uniformTypeDescriptor.UniformDataType.IMAGE,
        uri: fileUri.getUriFromPath(paths[i]),
        title: manga.name + ' · 第 ' + (i + 1) + ' 页',
        description: '来自星译 StarFlow 的漫画页面',
        label: 'IMAGE'
      });
    }
    return data;
  }

  /** 碰一碰发送：注册后轻碰另一台设备即调用 target.share。 */
  static registerKnockSender(): void {
    if (ShareService.senderRegistered) {
      return;
    }
    try {
      harmonyShare.on('knockShare', (target: harmonyShare.SharableTarget) => {
        ShareService.handleKnock(target);
      });
      ShareService.senderRegistered = true;
    } catch (e) {
      Log.warn(TAG, 'knockShare register failed: ' + JSON.stringify(e));
    }
  }

  private static async handleKnock(target: harmonyShare.SharableTarget): Promise<void> {
    const id = ShareService.knockMangaId;
    if (id <= 0) {
      try {
        await target.clarifyNonShare({ message: '请先打开一本漫画，再轻碰分享' });
      } catch (e) {
      }
      return;
    }
    try {
      const manga = await MangaDao.queryById(id);
      const pages = await PageDao.queryByMangaId(id);
      if (manga === undefined || pages.length === 0) {
        await target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR);
        return;
      }
      await target.share(ShareService.buildMangaData(manga, pages.map(p => p.imagePath)));
    } catch (e) {
      Log.warn(TAG, 'knock share failed: ' + JSON.stringify(e));
    }
  }

  /**
   * 碰一碰/隔空投送导入：注册 dataReceive，把收到的文件保存到缓存目录后回调。
   * 仅 API 20+ 且设备支持 Harmony Share 时生效。
   */
  static async registerKnockReceiver(context: common.UIAbilityContext, windowId: number,
    onImported: (uris: Array<string>) => void): Promise<boolean> {
    if (ShareService.receiverRegistered) {
      return true;
    }
    try {
      const registry: harmonyShare.RecvCapabilityRegistry = {
        windowId: windowId,
        capabilities: [
          { utd: uniformTypeDescriptor.UniformDataType.FILE, maxSupportedCount: 500 },
          { utd: uniformTypeDescriptor.UniformDataType.IMAGE, maxSupportedCount: 500 }
        ]
      };
      harmonyShare.on('dataReceive', registry, (target: harmonyShare.ReceivableTarget) => {
        const dir = context.cacheDir + '/knock-import/' + Date.now();
        try {
          fs.mkdirSync(dir, true);
        } catch (e) {
          Log.warn(TAG, 'prepare receive dir failed: ' + JSON.stringify(e));
        }
        target.receive(dir, {
          onDataReceived: (data: systemShare.SharedData) => {
            const uris: Array<string> = [];
            const records = data.getRecords();
            for (const record of records) {
              try {
                const file = record as Object as unifiedDataChannel.File;
                if (file.uri !== undefined && file.uri.length > 0) {
                  uris.push(file.uri);
                }
              } catch (e) {
              }
            }
            if (uris.length > 0) {
              onImported(uris);
            }
          },
          onResult: (code: harmonyShare.ShareResultCode) => {
            Log.info(TAG, 'knock receive result: ' + code);
          }
        }).catch((e: BusinessError) => {
          Log.warn(TAG, 'receive failed: ' + JSON.stringify(e));
        });
      });
      ShareService.receiverRegistered = true;
      return true;
    } catch (e) {
      Log.warn(TAG, 'dataReceive register failed (device may not support): ' + JSON.stringify(e));
      return false;
    }
  }

  static isReceiverRegistered(): boolean {
    return ShareService.receiverRegistered;
  }

  /** 把收到的 URI 交给 ImportService 导入，并刷新书架。 */
  static async importReceived(uris: Array<string>): Promise<number> {
    try {
      const result = await ImportService.importDropped(uris, () => {
      });
      if (result.length > 0) {
        AppStorage.setOrCreate('starflow_shelf_dirty', Date.now());
      }
      return result.length;
    } catch (e) {
      Log.error(TAG, 'import received failed: ' + JSON.stringify(e));
      return 0;
    }
  }
}
