import fs from '@ohos.file.fs';
import { image } from '@kit.ImageKit';
import { taskpool } from '@kit.ArkTS';
import { OcrRegion, makeOcrRegion, makePixelRect } from 'coremodel';
import { Log, toMediaUri } from 'commons';
import { initRec as nativeInitRec, initDet as nativeInitDet } from 'libocrasync.so';
import { detectBoxesNative, recBoxesNative } from '../workers/OcrRecTask';

const TAG = 'OcrRecService';

/** 原生 det+rec：主线程只解码 RGBA，检测与识别都在 TaskPool 原生线程。 */
export class OcrRecService {
  private static recReady: boolean = false;
  private static detReady: boolean = false;

  static initNative(detPath: string, recPath: string): boolean {
    try {
      if (!OcrRecService.detReady) {
        OcrRecService.detReady = (nativeInitDet as (p: string) => boolean)(detPath);
      }
      if (!OcrRecService.recReady) {
        OcrRecService.recReady = (nativeInitRec as (p: string) => boolean)(recPath);
      }
      Log.info(TAG, 'native init det=' + OcrRecService.detReady + ' rec=' + OcrRecService.recReady);
      return OcrRecService.detReady && OcrRecService.recReady;
    } catch (e) {
      Log.warn(TAG, 'native init failed: ' + e);
      return false;
    }
  }

  static isReady(): boolean {
    return OcrRecService.detReady && OcrRecService.recReady;
  }

  static async recognizePage(pagePath: string, dict: string): Promise<Array<OcrRegion>> {
    if (!OcrRecService.isReady()) {
      Log.warn(TAG, 'native not ready');
      return [];
    }
    let source: image.ImageSource | undefined = undefined;
    let file: fs.File | undefined = undefined;
    let pm: image.PixelMap | undefined = undefined;
    try {
      try {
        source = image.createImageSource(toMediaUri(pagePath));
      } catch (e) {
        source = undefined;
      }
      if (source === undefined || source === null) {
        file = fs.openSync(pagePath, fs.OpenMode.READ_ONLY);
        source = image.createImageSource(file.fd);
      }
      if (source === undefined || source === null) {
        return [];
      }
      pm = await source.createPixelMap();
      const info = await pm.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      const buffer = new ArrayBuffer(w * h * 4);
      await pm.readPixelsToBuffer(buffer);
      const detBuffer = new Uint8Array(buffer).slice().buffer;
      const boxes = await taskpool.execute(detectBoxesNative, detBuffer, w, h) as Array<number>;
      Log.info(TAG, 'native det boxes=' + boxes.length);
      if (boxes.length === 0) {
        return [];
      }
      const recBuffer = new Uint8Array(buffer).slice().buffer;
      const texts = await taskpool.execute(recBoxesNative, recBuffer, w, h, boxes, dict) as Array<string>;
      const out: Array<OcrRegion> = [];
      const pageArea = w * h;
      for (let i = 0; i < texts.length; i++) {
        const text = texts[i].trim();
        const x = boxes[i * 4];
        const y = boxes[i * 4 + 1];
        const bw = boxes[i * 4 + 2];
        const bh = boxes[i * 4 + 3];
        const area = bw * bh;
        if (text.length === 0 || area > pageArea * 0.15
          || (text.length <= 2 && area > pageArea * 0.04)) {
          continue;
        }
        out.push(makeOcrRegion(text, makePixelRect(x, y, bw, bh)));
      }
      out.sort((a: OcrRegion, b: OcrRegion): number => {
        if (Math.abs(a.box.y - b.box.y) > 12) {
          return a.box.y - b.box.y;
        }
        return a.box.x - b.box.x;
      });
      Log.info(TAG, 'native det+rec regions=' + out.length);
      return out;
    } catch (e) {
      Log.warn(TAG, 'native det+rec failed: ' + e);
      return [];
    } finally {
      if (pm !== undefined) {
        pm.release();
      }
      if (source !== undefined) {
        source.release();
      }
      if (file !== undefined) {
        fs.closeSync(file);
      }
    }
  }
}
