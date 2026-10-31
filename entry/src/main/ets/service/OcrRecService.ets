import fs from '@ohos.file.fs';
import { image } from '@kit.ImageKit';
import { taskpool } from '@kit.ArkTS';
import { OcrRegion, makeOcrRegion, makePixelRect } from 'coremodel';
import { Log, toMediaUri } from 'commons';
import { initRec as nativeInitRec } from 'libocrasync.so';
import { recBoxesNative } from '../workers/OcrRecTask';

const TAG = 'OcrRecService';

/** 原生 rec 的 ArkTS 封装：det 仍在 coreocr，rec 走 TaskPool + ONNX Runtime C API。 */
export class OcrRecService {
  private static initialized: boolean = false;

  static initRec(modelPath: string): boolean {
    if (OcrRecService.initialized) {
      return true;
    }
    try {
      const ok: boolean = (nativeInitRec as (path: string) => boolean)(modelPath);
      OcrRecService.initialized = ok;
      return ok;
    } catch (e) {
      Log.warn(TAG, 'native rec init failed: ' + e);
      return false;
    }
  }

  static async recognizeRegions(pagePath: string, boxes: Array<number>,
    dict: string): Promise<Array<OcrRegion>> {
    if (!OcrRecService.initialized || boxes.length < 4) {
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
      const texts = await taskpool.execute(recBoxesNative, buffer, w, h, boxes, dict) as Array<string>;
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
      Log.info(TAG, 'native rec regions=' + out.length);
      return out;
    } catch (e) {
      Log.warn(TAG, 'native rec failed: ' + e);
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
