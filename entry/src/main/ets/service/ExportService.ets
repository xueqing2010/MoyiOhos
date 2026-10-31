import fs from '@ohos.file.fs';
import { image } from '@kit.ImageKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { pdfService } from '@kit.PDFKit';
import { Manga, MangaPage, PageTranslation } from 'coremodel';
import {
  DisplayRect,
  FontSizeMode,
  OverlayColors,
  OverlayItem,
  OverlayRenderer,
  OverlayRegion,
  PageOverlay,
  RenderOptions,
  RenderOrientation,
  VerticalDirection,
  makeOverlayRegion
} from 'corerender';
import { Log, toMediaUri } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { MangaRepository } from '../data/MangaRepository';
import { PageRepository } from '../data/PageRepository';

const TAG = 'ExportService';
const PREF_FILE = 'starflow_reader';
const KEY_ORIENT = 'render_orientation';
const KEY_VDIR = 'render_direction';
const KEY_FONT_MODE = 'render_font_mode';
const KEY_FONT_SIZE = 'render_font_size';
const KEY_LINE_HEIGHT = 'reader_line_height';
const KEY_WHITE_MERGE = 'reader_white_merge';

export enum ExportMode {
  ORIGINAL_ONLY = 0,
  TRANSLATED_ONLY = 1,
  BILINGUAL = 2
}

export class ExportResult {
  exported: number = 0;
  untranslated: number = 0;
  uri: string = '';
  cancelled: boolean = false;
  /** 保存选择器不可用/超时/写目标失败时，回退写入应用沙箱 files/exports。 */
  savedToAppDir: boolean = false;
  /** 回退时的应用沙箱文件路径（用于提示用户去哪找）。 */
  appDirPath: string = '';
}

/** 回退保存结果（沙箱路径 + file:// URI）。 */
class AppDirSave {
  uri: string = '';
  path: string = '';
}

const PICKER_TIMEOUT_MS = 20000;
const COMPRESS_TIMEOUT_MS = 120000;
const COPY_TIMEOUT_MS = 60000;

/**
 * 三模式导出（T031 / US-7 / plan D9）：
 * - 仅原文 = 归集原图；
 * - 仅译文 = 离屏合成（解码 PixelMap → OffscreenCanvas drawImage →
 *   OverlayRenderer 覆盖 → getImageData → createPixelMap → ImagePacker JPEG）；
 * - 双语 = 原文页与译文页按页序交替。
 * 暂存 cache/export → zlib.compressFile → 保存选择器 → 清理暂存；
 * 未翻译页以原图导出并计数；取消不留残缺 ZIP。合成图仅存在于导出产物。
 */
export class ExportService {
  static async export(mangaId: number, mode: ExportMode,
    onProgress: (done: number, total: number) => void,
    isCancelled?: () => boolean): Promise<ExportResult> {
    const result = new ExportResult();
    await AppEnv.ready();
    const manga: Manga | undefined = await MangaRepository.getById(mangaId);
    if (manga === undefined) {
      throw new Error('漫画记录不存在');
    }
    const pages: Array<MangaPage> = await PageRepository.getPages(mangaId);
    if (pages.length === 0) {
      throw new Error('没有可导出的页面');
    }
    const opts = await ExportService.loadRenderOptions();
    const whiteMerge = await ExportService.loadWhiteMerge();

    const cacheDir = AppEnv.getInstance().getContext().cacheDir;
    const stamp = Date.now();
    const staging = `${cacheDir}/export/${stamp}`;
    const zipPath = `${cacheDir}/export/${stamp}.zip`;
    const total = pages.length;
    const beginAt = Date.now();
    Log.info(TAG, `[export] begin manga=${mangaId} mode=${mode} pages=${total}`);
    fs.mkdirSync(staging, true);
    try {
      let done = 0;
      const loopAt = Date.now();
      for (let i = 0; i < total; i++) {
        if (isCancelled !== undefined && isCancelled()) {
          result.cancelled = true;
          return result;
        }
        const page = pages[i];
        const base = `page-${ExportService.pad4(i + 1)}`;
        if (mode === ExportMode.ORIGINAL_ONLY) {
          ExportService.copyOriginal(page, `${staging}/${base}${ExportService.extOf(page.imagePath)}`);
          done++;
        } else if (mode === ExportMode.TRANSLATED_ONLY) {
          const pt = await PageRepository.getTranslation(page.id);
          if (pt !== undefined && pt.translations.length > 0) {
            try {
              await ExportService.composeTranslated(page, pt, `${staging}/${base}.jpg`, opts, whiteMerge);
              if (ExportService.sizeOf(`${staging}/${base}.jpg`) <= 0) {
                throw new Error('合成页为空');
              }
            } catch (e) {
              result.untranslated++;
              Log.warn(TAG, `[export] compose page ${page.id} failed, fallback to original: ${e}`);
              ExportService.copyOriginal(page, `${staging}/${base}${ExportService.extOf(page.imagePath)}`);
            }
          } else {
            result.untranslated++;
            ExportService.copyOriginal(page, `${staging}/${base}${ExportService.extOf(page.imagePath)}`);
          }
          done++;
        } else {
          ExportService.copyOriginal(page, `${staging}/${base}-orig${ExportService.extOf(page.imagePath)}`);
          const pt = await PageRepository.getTranslation(page.id);
          if (pt !== undefined && pt.translations.length > 0) {
            try {
              await ExportService.composeTranslated(page, pt, `${staging}/${base}-trans.jpg`, opts, whiteMerge);
              if (ExportService.sizeOf(`${staging}/${base}-trans.jpg`) <= 0) {
                throw new Error('合成页为空');
              }
            } catch (e) {
              result.untranslated++;
              Log.warn(TAG, `[export] compose page ${page.id} failed, fallback to original: ${e}`);
              ExportService.copyOriginal(page, `${staging}/${base}-trans${ExportService.extOf(page.imagePath)}`);
            }
          } else {
            result.untranslated++;
            ExportService.copyOriginal(page, `${staging}/${base}-trans${ExportService.extOf(page.imagePath)}`);
          }
          done++;
        }
        onProgress(done, total);
        if (mode !== ExportMode.ORIGINAL_ONLY) {
          Log.info(TAG, `[export] page ${done}/${total} composed (${Date.now() - loopAt}ms)`);
        }
      }
      Log.info(TAG, `[export] compose loop done: ${total} pages in ${Date.now() - loopAt}ms`);

      if (isCancelled !== undefined && isCancelled()) {
        result.cancelled = true;
        return result;
      }

      // 压缩前清点暂存内容（定位“0 字节合成页/空目录”类问题）
      ExportService.logStaging(staging);

      // 显式压缩参数 + 超时保护：压缩是 zip 阶段唯一的 await，不能无限挂起。
      const zipOptions: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
      };
      const compressAt = Date.now();
      Log.info(TAG, `[export] compress start -> ${zipPath}`);
      await ExportService.withTimeout(zlib.compressFile(staging, zipPath, zipOptions),
        COMPRESS_TIMEOUT_MS, '压缩 ZIP');
      Log.info(TAG, `[export] compress done in ${Date.now() - compressAt}ms, size=${ExportService.sizeOf(zipPath)}`);

      // 保存选择器：必须传 UIAbilityContext（无参构造官方标注有失败风险）；
      // 超时/异常也不能让 UI 永远停在“导出中”，回退应用目录并如实提示。
      let uri = '';
      let pickerFailed = false;
      const pickerAt = Date.now();
      Log.info(TAG, '[export] picker start');
      let pickerTimedOut = false;
      try {
        uri = await ExportService.withTimeout(ExportService.saveZip(manga.name),
          PICKER_TIMEOUT_MS, '保存位置选择');
      } catch (e) {
        const msg = `${e}`;
        if (msg.indexOf('超时') >= 0) {
          // The system save picker never settles when the user taps cancel, so a
          // picker timeout is treated as "user cancelled" (no auto fallback).
          pickerTimedOut = true;
          Log.info(TAG, `[export] picker closed/cancelled after ${Date.now() - pickerAt}ms`);
        } else {
          pickerFailed = true;
          Log.error(TAG, `[export] picker failed after ${Date.now() - pickerAt}ms: ${e}`);
        }
        uri = '';
      }
      Log.info(TAG, `[export] picker end in ${Date.now() - pickerAt}ms, uri=${uri.length > 0 ? 'ok' : 'none'}`);
      if (uri.length === 0 && (pickerTimedOut || !pickerFailed)) {
        result.cancelled = true;
        Log.info(TAG, '[export] cancelled by user (picker cancelled or empty result)');
        return result;
      }
      if (uri.length === 0) {
        const fallback = ExportService.saveToAppDir(zipPath, manga.name);
        result.uri = fallback.uri;
        result.savedToAppDir = true;
        result.appDirPath = fallback.path;
        result.exported = total;
        Log.warn(TAG, `[export] picker unavailable, saved to app dir: ${fallback.path}`);
        return result;
      }

      const copyAt = Date.now();
      Log.info(TAG, '[export] copy start');
      let copyOk = true;
      try {
        await ExportService.withTimeout(ExportService.copyToUri(zipPath, uri),
          COPY_TIMEOUT_MS, '写入 ZIP 到目标位置');
        Log.info(TAG, `[export] copy done in ${Date.now() - copyAt}ms`);
      } catch (e) {
        copyOk = false;
        Log.error(TAG, `[export] copy failed after ${Date.now() - copyAt}ms: ${e}`);
      }
      if (!copyOk) {
        const fallback = ExportService.saveToAppDir(zipPath, manga.name);
        result.uri = fallback.uri;
        result.savedToAppDir = true;
        result.appDirPath = fallback.path;
        result.exported = total;
        Log.warn(TAG, `[export] copy failed, saved to app dir: ${fallback.path}`);
        return result;
      }

      result.uri = uri;
      result.exported = total;
      Log.info(TAG, `exported ${total} pages (mode=${mode}) to ${uri} in ${Date.now() - beginAt}ms`);
      return result;
    } finally {
      // 完成即清理暂存；异常同样清理，不留残缺 ZIP。
      const cleanAt = Date.now();
      ExportService.rmRecursive(staging);
      try {
        if (fs.accessSync(zipPath)) {
          fs.unlinkSync(zipPath);
        }
      } catch (e) {
        // ignore
      }
      Log.info(TAG, `[export] cleanup done in ${Date.now() - cleanAt}ms`);
    }
  }

  /**
   * 导出译文 PDF：先把每页合成为 JPEG，再用 PDF Kit 按图片比例生成页面。
   * 不依赖 ZIP/选择器，先写入应用沙箱 files/exports。
   */
  static async exportPdf(mangaId: number,
    onProgress: (done: number, total: number) => void,
    isCancelled?: () => boolean): Promise<ExportResult> {
    const result = new ExportResult();
    await AppEnv.ready();
    const manga: Manga | undefined = await MangaRepository.getById(mangaId);
    if (manga === undefined) {
      throw new Error('漫画记录不存在');
    }
    const pages: Array<MangaPage> = await PageRepository.getPages(mangaId);
    if (pages.length === 0) {
      throw new Error('没有可导出的页面');
    }
    const opts = await ExportService.loadRenderOptions();
    const whiteMerge = await ExportService.loadWhiteMerge();
    const cacheDir = AppEnv.getInstance().getContext().cacheDir;
    const staging = cacheDir + '/pdf/' + Date.now();
    fs.mkdirSync(staging, true);
    const total = pages.length;
    try {
      const images: Array<string> = [];
      for (let i = 0; i < total; i++) {
        if (isCancelled !== undefined && isCancelled()) {
          result.cancelled = true;
          return result;
        }
        const page = pages[i];
        const dest = staging + '/page-' + ExportService.pad4(i + 1) + '.jpg';
        const pt = await PageRepository.getTranslation(page.id);
        if (pt !== undefined && pt.translations.length > 0) {
          await ExportService.composeTranslated(page, pt, dest, opts, whiteMerge);
        } else {
          ExportService.copyOriginal(page, dest);
          result.untranslated++;
        }
        if (ExportService.sizeOf(dest) <= 0) {
          throw new Error('PDF 页面合成为空：page ' + page.id);
        }
        images.push(dest);
        onProgress(i + 1, total);
      }

      const doc = new pdfService.PdfDocument();
      try {
        const firstInfo = await ExportService.imageSize(images[0]);
        let pageW = Math.max(1, firstInfo.size.width * 0.75);
        let pageH = Math.max(1, firstInfo.size.height * 0.75);
        if (!doc.createDocument(pageW, pageH)) {
          throw new Error('PDF 创建失败');
        }
        for (let i = 0; i < images.length; i++) {
          const info = await ExportService.imageSize(images[i]);
          const w = Math.max(1, info.size.width * 0.75);
          const h = Math.max(1, info.size.height * 0.75);
          let page = i === 0 ? doc.getPage(0) : doc.insertBlankPage(i, w, h);
          if (page === undefined || page === null) {
            throw new Error('PDF 页面创建失败');
          }
          page.addImageObject(images[i], 0, 0, w, h);
        }
        const outDir = AppEnv.getInstance().getContext().filesDir + '/exports';
        try {
          if (!fs.accessSync(outDir)) {
            fs.mkdirSync(outDir, true);
          }
        } catch (e) {
        }
        const safeName = manga.name.replace(/[\\/:*?"<>|]/g, '_');
        const outPath = outDir + '/' + safeName + '-' + Date.now() + '.pdf';
        if (!doc.saveDocument(outPath)) {
          throw new Error('PDF 保存失败');
        }
        result.uri = fileUri.getUriFromPath(outPath);
        result.appDirPath = outPath;
        result.exported = total;
        result.savedToAppDir = true;
        Log.info(TAG, 'PDF exported: ' + outPath);
        return result;
      } finally {
        try {
          doc.releaseDocument();
        } catch (e) {
        }
      }
    } finally {
      ExportService.rmRecursive(staging);
    }
  }

  private static async imageSize(path: string): Promise<image.ImageInfo> {
    let src: image.ImageSource | undefined = undefined;
    let file: fs.File | undefined = undefined;
    try {
      try {
        src = image.createImageSource(toMediaUri(path));
      } catch (e) {
        src = undefined;
      }
      if (src === undefined || src === null) {
        file = fs.openSync(path, fs.OpenMode.READ_ONLY);
        src = image.createImageSource(file.fd);
      }
      return await src.getImageInfo();
    } finally {
      if (src !== undefined) {
        src.release();
      }
      if (file !== undefined) {
        fs.closeSync(file);
      }
    }
  }

  /**
   * 导出与阅读器共用同一套渲染设置（starflow_reader）：方向/字号/行距。
   * 导出在**页面像素坐标系**排版（scale=1），与屏幕端 OverlayRenderer.paintPlan 同一路径。
   */
  private static async loadRenderOptions(): Promise<RenderOptions> {
    let orientation = 1;
    let vdir = 0;
    let fontMode = 0;
    let fixedSize = 16;
    let lineHeight = 130;
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      orientation = pref.getSync(KEY_ORIENT, 1) as number;
      vdir = pref.getSync(KEY_VDIR, 0) as number;
      fontMode = pref.getSync(KEY_FONT_MODE, 0) as number;
      fixedSize = pref.getSync(KEY_FONT_SIZE, 16) as number;
      lineHeight = pref.getSync(KEY_LINE_HEIGHT, 130) as number;
    } catch (e) {
      // defaults
    }
    const extraLine = lineHeight / 100 - 1.3;
    const o: RenderOptions = {
      orientation: orientation === 0 ? RenderOrientation.HORIZONTAL : RenderOrientation.VERTICAL,
      verticalDirection: vdir === 0 ? VerticalDirection.RTL : VerticalDirection.LTR,
      fontSizeMode: fontMode === 0 ? FontSizeMode.AUTO : FontSizeMode.FIXED,
      fixedFontSize: fixedSize,
      padding: 4,
      lineSpacing: extraLine > 0 ? extraLine : 0,
      charSpacing: 0
    };
    return o;
  }

  /** 白块合并开关（导出与阅读显示一致）。 */
  private static async loadWhiteMerge(): Promise<boolean> {
    try {
      const ctx = AppEnv.getInstance().getContext();
      const pref = await preferences.getPreferences(ctx, PREF_FILE);
      return pref.getSync(KEY_WHITE_MERGE, true) as boolean;
    } catch (e) {
      return true;
    }
  }

  private static copyOriginal(page: MangaPage, dest: string): void {
    let src: fs.File;
    try {
      src = fs.openSync(toMediaUri(page.imagePath), fs.OpenMode.READ_ONLY);
    } catch (e) {
      src = fs.openSync(page.imagePath, fs.OpenMode.READ_ONLY);
    }
    try {
      fs.copyFileSync(src.fd, dest);
    } finally {
      fs.closeSync(src);
    }
  }

  private static async composeTranslated(page: MangaPage, pt: PageTranslation, dest: string,
    opts: RenderOptions, whiteMerge: boolean): Promise<void> {
    const startedAt = Date.now();
    const pm = await ExportService.decodeForExport(page.imagePath);
    try {
      const info = await pm.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      // ⚠️ OffscreenCanvas 默认单位是 vp（会按屏幕密度放大后备缓冲），必须显式用 PX，
      // 否则 getImageData 拿到的行宽 ≠ w*4，createPixelMap 按 w 解释就会出现横向条纹/花屏。
      const off = new OffscreenCanvas(w, h, LengthMetricsUnit.PX);
      const ctx = off.getContext('2d');
      if (ctx === undefined || ctx === null) {
        throw new Error('离屏画布初始化失败');
      }
      ctx.drawImage(pm, 0, 0, w, h);
      const regions: Array<OverlayRegion> = [];
      for (let i = 0; i < pt.ocr.length; i++) {
        const text = i < pt.translations.length ? pt.translations[i] : '';
        if (text.length === 0) {
          continue;
        }
        const r = pt.ocr[i];
        const box: DisplayRect = { x: r.box.x, y: r.box.y, w: r.box.w, h: r.box.h };
        regions.push(makeOverlayRegion(box, r.text, text));
      }
      // 页面像素坐标系排版 → 逐字绘制（scale=1）；合并白块与屏幕端一致。
      // 传入页面像素边界，PageOverlay 会把越界 OCR 框裁剪到页面内，避免导出图白块越界。
      const pageOpts: RenderOptions = {
        orientation: opts.orientation,
        verticalDirection: opts.verticalDirection,
        fontSizeMode: opts.fontSizeMode,
        fixedFontSize: opts.fixedFontSize,
        padding: opts.padding,
        lineSpacing: opts.lineSpacing,
        charSpacing: opts.charSpacing,
        pageWidth: w,
        pageHeight: h
      };
      const items: Array<OverlayItem> = PageOverlay.build(regions, pageOpts, true, whiteMerge);
      const colors: OverlayColors = OverlayColors.make('#FFFFFF', '#1A1A1A');
      // 离屏画布用 LengthMetricsUnit.PX 创建，字号单位必须是 px（与页面像素 1:1）。
      OverlayRenderer.paintPlan(ctx, items, 1, 0, 0, colors, 'px');

      // 优先直接取 canvas 的 PixelMap（避免 ImageData→PixelMap 的 stride/缓冲转换差异）；
      // 失败再退回 getImageData（显式拷贝成 w*h*4 的紧凑 RGBA 缓冲）。
      let out: image.PixelMap | undefined = undefined;
      try {
        out = ctx.getPixelMap(0, 0, w, h);
      } catch (e) {
        Log.warn(TAG, `[export] getPixelMap failed, fallback to getImageData: ${e}`);
        out = undefined;
      }
      if (out === undefined || out === null) {
        const imageData = ctx.getImageData(0, 0, w, h);
        const expected = w * h * 4;
        const raw = new ArrayBuffer(expected);
        const dst = new Uint8Array(raw);
        const src = new Uint8Array(imageData.data.buffer);
        const copyLen = src.length < expected ? src.length : expected;
        for (let i = 0; i < copyLen; i++) {
          dst[i] = src[i];
        }
        const initOpts: image.InitializationOptions = {
          size: { width: w, height: h },
          srcPixelFormat: image.PixelMapFormat.RGBA_8888,
          pixelFormat: image.PixelMapFormat.RGBA_8888,
          alphaType: image.AlphaType.OPAQUE,
          editable: false
        };
        out = await image.createPixelMap(raw, initOpts);
      }
      if (out === undefined || out === null) {
        throw new Error('无法生成合成像素图');
      }
      const outInfo = await out.getImageInfo();
      if (outInfo.size.width !== w || outInfo.size.height !== h) {
        throw new Error('合成像素图尺寸不符：' + outInfo.size.width + 'x' + outInfo.size.height);
      }
      const packer = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/jpeg', quality: 90 };
      try {
        const jpg: ArrayBuffer = await packer.packToData(out, packOpts);
        if (jpg.byteLength <= 0) {
          throw new Error('JPEG 合成结果为空');
        }
        ExportService.writeBytes(dest, jpg);
        Log.info(TAG, `[export] compose page=${page.pageIndex} ${w}x${h} regions=${regions.length} ` +
          `jpg=${jpg.byteLength} in ${Date.now() - startedAt}ms`);
      } finally {
        packer.release();
        out.release();
      }
    } finally {
      pm.release();
    }
  }

  /** 解码页图（导出）：优先媒体 URI，失败退回 fd；合成与 copyOriginal 共用同一路径约定。 */
  private static async decodeForExport(path: string): Promise<image.PixelMap> {
    let imageSource: image.ImageSource | undefined = undefined;
    let src: fs.File | undefined = undefined;
    try {
      try {
        imageSource = image.createImageSource(toMediaUri(path));
      } catch (e) {
        imageSource = undefined;
      }
      if (imageSource === undefined || imageSource === null) {
        src = fs.openSync(path, fs.OpenMode.READ_ONLY);
        imageSource = image.createImageSource(src.fd);
      }
      const pm = await imageSource.createPixelMap();
      if (pm === undefined || pm === null) {
        throw new Error('无法解码图片');
      }
      return pm;
    } finally {
      if (imageSource !== undefined) {
        try {
          imageSource.release();
        } catch (ignore) {
        }
      }
      if (src !== undefined) {
        try {
          fs.closeSync(src);
        } catch (ignore) {
        }
      }
    }
  }

  private static writeBytes(dest: string, bytes: ArrayBuffer): void {
    const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes);
    } finally {
      fs.closeSync(file);
    }
  }

  /**
   * 保存位置选择器。
   * 1) 必须传 UIAbilityContext：文档明确「无参构造存在操作失败风险」（实测表现为 save 永不 resolve）；
   * 2) 调用前让出一帧，等图像解码/打包资源释放完再拉起系统 picker；
   * 3) 返回值空数组代表用户取消，抛错/超时由调用方回退应用目录。
   */
  private static async saveZip(name: string): Promise<string> {
    await ExportService.sleep(40);
    const context = AppEnv.getInstance().getContext() as common.UIAbilityContext;
    const docPicker = new picker.DocumentViewPicker(context);
    const opts = new picker.DocumentSaveOptions();
    // 默认文件名必须唯一：与已有文件重名时系统保存选择器会提示“已有重名文件”并禁用确认，
    // save() 永不 resolve（这就是之前“仅译文卡死”的根因，并非 API 问题）。
    const uniqueName = ExportService.uniqueZipName(name);
    opts.newFileNames = [uniqueName];
    opts.fileSuffixChoices = ['压缩文件|.zip'];
    Log.info(TAG, `[export] picker file name: ${uniqueName}`);
    const uris = await docPicker.save(opts);
    Log.info(TAG, `[export] picker resolved with ${uris.length} uri(s)`);
    if (uris.length === 0) {
      return '';
    }
    return uris[0];
  }

  /**
   * 把 ZIP 写入 picker 返回的目标 URI（异步，可被超时打断，避免同步 open/copy 卡死 UI 线程）。
   * 优先 path→URI 直接拷；失败再退回 fd 拷贝。
   */
  private static async copyToUri(zipPath: string, uri: string): Promise<void> {
    // 1) 快速路径：异步 copyFile 直接写目标 URI（20s 内不完成就改流式，避免 FUSE/文档 URI 长阻塞）
    try {
      await ExportService.withTimeout(fs.copyFile(zipPath, uri), 20000, 'copyFile(uri)');
      Log.info(TAG, '[export] copy via copyFile(uri) ok');
      return;
    } catch (e) {
      Log.warn(TAG, `[export] copyFile(uri) failed/slow, fallback to stream copy: ${e}`);
    }
    // 2) 流式逐块读写：对 documents/FUSE 目标最稳（copy_file_range 类优化调用在文档 URI 上可能不可用）
    const src = await fs.open(zipPath, fs.OpenMode.READ_ONLY);
    const dest = await fs.open(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      const buffer = new ArrayBuffer(64 * 1024);
      let copied = 0;
      while (true) {
        const readLen = await fs.read(src.fd, buffer);
        if (readLen <= 0) {
          break;
        }
        // 先整块写；极小概率的“部分写”再按剩余字节切片续写（write 的 offset 是相对 filePointer 的，不能直接复用）。
        let written = await fs.write(dest.fd, buffer, { length: readLen });
        while (written < readLen) {
          const remain = readLen - written;
          const chunk = new ArrayBuffer(remain);
          const chunkView = new Uint8Array(chunk);
          const srcView = new Uint8Array(buffer);
          for (let k = 0; k < remain; k++) {
            chunkView[k] = srcView[written + k];
          }
          const n = await fs.write(dest.fd, chunk);
          if (n <= 0) {
            throw new Error('写入目标文件失败（write 返回 0）');
          }
          written += n;
        }
        copied += written;
      }
      try {
        await fs.fsync(dest.fd);
      } catch (ignore) {
      }
      Log.info(TAG, `[export] copy via stream ok, bytes=${copied}`);
    } finally {
      await fs.close(src);
      await fs.close(dest);
    }
  }

  /** 默认保存名：墨译-<漫画名>-yyyyMMdd-HHmmss.zip（唯一，避免 picker 重名拦截）。 */
  private static uniqueZipName(name: string): string {
    const safe = ExportService.safeFileName(name.length > 0 ? name : '漫画');
    return `墨译-${safe}-${ExportService.timeStamp()}.zip`;
  }

  /** yyyyMMdd-HHmmss。 */
  private static timeStamp(): string {
    const d = new Date();
    return `${d.getFullYear()}${ExportService.pad2(d.getMonth() + 1)}${ExportService.pad2(d.getDate())}`
      + `-${ExportService.pad2(d.getHours())}${ExportService.pad2(d.getMinutes())}`
      + `${ExportService.pad2(d.getSeconds())}`;
  }

  private static pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  /** picker 不可用时的兜底：写入应用沙箱 files/exports，返回 file:// URI。 */
  private static saveToAppDir(zipPath: string, name: string): AppDirSave {
    const out = new AppDirSave();
    try {
      const ctx = AppEnv.getInstance().getContext();
      const dir = `${ctx.filesDir}/exports`;
      fs.mkdirSync(dir, true);
      const safe = ExportService.safeFileName(name.length > 0 ? name : '漫画');
      out.path = `${dir}/${safe}-${ExportService.timeStamp()}.zip`;
      fs.copyFileSync(zipPath, out.path);
      out.uri = fileUri.getUriFromPath(out.path);
      Log.info(TAG, `[export] fallback zip written: ${out.path}`);
    } catch (e) {
      Log.error(TAG, `[export] fallback save failed: ${e}`);
    }
    return out;
  }

  /** Promise 超时包装：任何外部异步阶段都不允许无限挂起。 */
  private static async withTimeout<T>(task: Promise<T>, timeoutMs: number, label: string): Promise<T> {
    let timer: number = -1;
    const timeout: Promise<T> = new Promise<T>((resolve: (value: T) => void,
      reject: (reason: Error) => void) => {
      timer = setTimeout(() => {
        reject(new Error(label + ' 超时（' + timeoutMs + 'ms）'));
      }, timeoutMs);
    });
    try {
      return await Promise.race<T>([task, timeout]);
    } finally {
      if (timer >= 0) {
        clearTimeout(timer);
      }
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /** 压缩前打印暂存目录的文件数与总字节（诊断用）。 */
  private static logStaging(path: string): void {
    try {
      const files = fs.listFileSync(path);
      let totalBytes = 0;
      for (let i = 0; i < files.length; i++) {
        totalBytes += ExportService.sizeOf(path + '/' + files[i]);
      }
      Log.info(TAG, `[export] staging files=${files.length} bytes=${totalBytes}`);
    } catch (e) {
      Log.warn(TAG, `[export] staging inspect failed: ${e}`);
    }
  }

  private static sizeOf(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (e) {
      return -1;
    }
  }

  /** picker/文件名安全化（去掉路径分隔符等非法字符）。 */
  private static safeFileName(name: string): string {
    let safe = '';
    for (let i = 0; i < name.length; i++) {
      const ch = name.charAt(i);
      if (ch === '/' || ch === '\\' || ch === ':' || ch === '*' || ch === '?' || ch === '"'
        || ch === '<' || ch === '>' || ch === '|' || ch === '\n' || ch === '\r') {
        safe += '_';
      } else {
        safe += ch;
      }
    }
    if (safe.length === 0) {
      return 'starflow-export';
    }
    return safe;
  }

  private static extOf(path: string): string {
    const idx = path.lastIndexOf('.');
    if (idx < 0) {
      return '.jpg';
    }
    return path.substring(idx).toLowerCase();
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

  private static rmRecursive(path: string): void {
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
        Log.warn(TAG, `unlink ${path} failed: ${e}`);
      }
      return;
    }
    try {
      const children = fs.listFileSync(path);
      for (const child of children) {
        ExportService.rmRecursive(`${path}/${child}`);
      }
      fs.rmdirSync(path);
    } catch (e) {
      Log.warn(TAG, `rmdir ${path} failed: ${e}`);
    }
  }
}