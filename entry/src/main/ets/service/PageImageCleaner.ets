import fs from '@ohos.file.fs';
import { image } from '@kit.ImageKit';
import { OcrRegion } from 'coremodel';
import { Log, toMediaUri } from 'commons';
import { AppEnv } from '../common/AppEnv';

const TAG = 'PageImageCleaner';

/**
 * 轻量去字：不引入大模型，先用检测框周围的底色做梯度填充，生成“无字底图”缓存。
 * 对白底气泡效果最好；复杂背景是近似修复，后续可替换为 ONNX LaMa。
 */
export class PageImageCleaner {
  private static pending: Map<number, Promise<string | undefined>> = new Map();

  static cleanPath(pageId: number): string {
    const ctx = AppEnv.getInstance().getContext();
    return ctx.cacheDir + '/clean/page_' + pageId + '_v6.jpg';
  }

  static async ensure(pageId: number, imagePath: string,
    regions: Array<OcrRegion>): Promise<string | undefined> {
    const cached = PageImageCleaner.cleanPath(pageId);
    try {
      if (fs.accessSync(cached) && fs.statSync(cached).size > 1024) {
        return cached;
      }
    } catch (e) {
      // not cached
    }
    const existing = PageImageCleaner.pending.get(pageId);
    if (existing !== undefined) {
      return existing;
    }
    const task = PageImageCleaner.build(pageId, imagePath, regions);
    PageImageCleaner.pending.set(pageId, task);
    try {
      return await task;
    } finally {
      PageImageCleaner.pending.delete(pageId);
    }
  }

  private static async build(pageId: number, imagePath: string,
    regions: Array<OcrRegion>): Promise<string | undefined> {
    let source: image.ImageSource | undefined = undefined;
    let file: fs.File | undefined = undefined;
    let pm: image.PixelMap | undefined = undefined;
    try {
      try {
        source = image.createImageSource(toMediaUri(imagePath));
      } catch (e) {
        source = undefined;
      }
      if (source === undefined || source === null) {
        file = fs.openSync(imagePath, fs.OpenMode.READ_ONLY);
        source = image.createImageSource(file.fd);
      }
      if (source === undefined || source === null) {
        return undefined;
      }
      pm = await source.createPixelMap();
      if (pm === undefined || pm === null) {
        return undefined;
      }
      const info = await pm.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      if (w <= 0 || h <= 0) {
        return undefined;
      }
      const buffer = new ArrayBuffer(w * h * 4);
      await pm.readPixelsToBuffer(buffer);
      const rgba = new Uint8Array(buffer);
      PageImageCleaner.erase(rgba, w, h, regions);
      const out = await image.createPixelMap(buffer, {
        size: { width: w, height: h },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        alphaType: image.AlphaType.UNPREMUL,
        editable: false
      } as image.InitializationOptions);
      if (out === undefined || out === null) {
        return undefined;
      }
      const dir = AppEnv.getInstance().getContext().cacheDir + '/clean';
      try {
        if (!fs.accessSync(dir)) {
          fs.mkdirSync(dir, true);
        }
      } catch (e) {
      }
      const path = PageImageCleaner.cleanPath(pageId);
      const packer = image.createImagePacker();
      const packed = await packer.packing(out, { format: 'image/jpeg', quality: 88 });
      const dst = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(dst.fd, packed);
      } finally {
        fs.closeSync(dst);
      }
      packer.release();
      out.release();
      Log.info(TAG, 'cleaned page ' + pageId + ' -> ' + path);
      return path;
    } catch (e) {
      Log.warn(TAG, 'clean page failed: ' + e);
      return undefined;
    } finally {
      if (pm !== undefined) {
        try {
          pm.release();
        } catch (e) {
        }
      }
      if (source !== undefined) {
        try {
          source.release();
        } catch (e) {
        }
      }
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (e) {
        }
      }
    }
  }

  /** 用框外上下左右四条边的平均色做双线性填充，边缘保留原像素。 */
  private static erase(rgba: Uint8Array, w: number, h: number, regions: Array<OcrRegion>): void {
    const pageArea = w * h;
    for (const region of regions) {
      const box = region.box;
      // 与 OCR 侧一致：整页级伪框不参与去字，否则会把半页涂白。
      if (box.w * box.h > pageArea * 0.15
        || (region.text.length <= 2 && box.w * box.h > pageArea * 0.04)) {
        continue;
      }
      const pad = 4;
      const x0 = Math.max(2, Math.floor(box.x) - pad);
      const y0 = Math.max(2, Math.floor(box.y) - pad);
      const x1 = Math.min(w - 2, Math.ceil(box.x + box.w) + pad);
      const y1 = Math.min(h - 2, Math.ceil(box.y + box.h) + pad);
      if (x1 <= x0 || y1 <= y0) {
        continue;
      }
      const horizontal = box.w >= box.h;
      const left = PageImageCleaner.avgColumn(rgba, w, x0 - 1, y0, y1);
      const right = PageImageCleaner.avgColumn(rgba, w, x1 + 1, y0, y1);
      const top = PageImageCleaner.avgRow(rgba, w, y0 - 1, x0, x1);
      const bottom = PageImageCleaner.avgRow(rgba, w, y1 + 1, x0, x1);
      const dw = x1 - x0;
      const dh = y1 - y0;
      for (let y = y0; y <= y1; y++) {
        const ty = dh === 0 ? 0.5 : (y - y0) / dh;
        for (let x = x0; x <= x1; x++) {
          const tx = dw === 0 ? 0.5 : (x - x0) / dw;
          const i = (y * w + x) * 4;
          // 横排文字用左右两侧底色插值，竖排文字用上下两侧；
          // 避免把靠近文字的上/下边黑像素混进填充色，形成灰条。
          const cR = horizontal
            ? top[0] * (1 - ty) + bottom[0] * ty
            : left[0] * (1 - tx) + right[0] * tx;
          const cG = horizontal
            ? top[1] * (1 - ty) + bottom[1] * ty
            : left[1] * (1 - tx) + right[1] * tx;
          const cB = horizontal
            ? top[2] * (1 - ty) + bottom[2] * ty
            : left[2] * (1 - tx) + right[2] * tx;
          rgba[i] = Math.round(cR);
          rgba[i + 1] = Math.round(cG);
          rgba[i + 2] = Math.round(cB);
          rgba[i + 3] = 255;
        }
      }
    }
  }

  private static avgColumn(rgba: Uint8Array, w: number, x: number, y0: number, y1: number): number[] {
    let r = 0;
    let g = 0;
    let b = 0;
    let n = 0;
    for (let y = y0; y <= y1; y++) {
      const i = (y * w + x) * 4;
      r += rgba[i];
      g += rgba[i + 1];
      b += rgba[i + 2];
      n++;
    }
    if (n === 0) {
      return [255, 255, 255];
    }
    return [r / n, g / n, b / n];
  }

  private static avgRow(rgba: Uint8Array, w: number, y: number, x0: number, x1: number): number[] {
    let r = 0;
    let g = 0;
    let b = 0;
    let n = 0;
    for (let x = x0; x <= x1; x++) {
      const i = (y * w + x) * 4;
      r += rgba[i];
      g += rgba[i + 1];
      b += rgba[i + 2];
      n++;
    }
    if (n === 0) {
      return [255, 255, 255];
    }
    return [r / n, g / n, b / n];
  }
}

