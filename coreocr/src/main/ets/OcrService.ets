import { textRecognition } from '@kit.CoreVisionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { OcrRegion, PixelRect, makeOcrRegion, makePixelRect } from 'coremodel';
import { Log } from 'commons';
import { taskpool } from '@kit.ArkTS';
import { LocalOcrConfig, LocalOcrEngine } from './LocalOcrEngine';
import { recognizeLocalTask } from './LocalOcrTask';

/**
 * App-level OCR language hint. The system textRecognition engine is
 * multi-lingual by itself (no per-call language parameter exists in the
 * SDK); this enum is kept as a user-facing preference and for diagnostics.
 */
export enum OcrLang {
  JPN = 'ja',
  ENG = 'en',
  KOR = 'ko',
  CHN = 'zh-CN'
}

/**
 * Thin wrapper over Core Vision Kit textRecognition (plan D4).
 * Recognition unit = TextLine; cornerPoints (clockwise, first top-left)
 * are collapsed into an axis-aligned PixelRect in ORIGINAL image pixels.
 */
export class OcrService {
  private static instance: OcrService = new OcrService();

  private initialized: boolean = false;
  private lastProbeDetail: string = '未探测';
  private lastLang: OcrLang = OcrLang.JPN;
  private localEnabled: boolean = false;
  private localConfig: LocalOcrConfig | undefined = undefined;

  static getInstance(): OcrService {
    return OcrService.instance;
  }

  configureLocal(detPath: string, recPath: string, dictText: string): void {
    this.localConfig = { detPath: detPath, recPath: recPath, dictText: dictText };
  }

  setLocalEnabled(enabled: boolean): void {
    this.localEnabled = enabled;
  }

  isLocalEnabled(): boolean {
    return this.localEnabled;
  }

  /** 直接对图片路径跑本地模型（自测/批处理用，不依赖 PixelMap）。 */
  async recognizeLocal(pagePath: string): Promise<Array<OcrRegion>> {
    if (this.localConfig === undefined) {
      throw new Error('本地模型未配置');
    }
    const engine = LocalOcrEngine.getInstance();
    await engine.init(this.localConfig);
    this.localEnabled = true;
    this.lastProbeDetail = '本地 PP-OCRv6（ONNX Runtime）';
    return await engine.recognize(pagePath);
  }

  /** 本地 OCR 的 worker 版本：主线程不跑 ONNX，只做结果解码。 */
  async recognizeLocalAsync(pagePath: string): Promise<Array<OcrRegion>> {
    const config = this.localConfig;
    if (config === undefined) {
      throw new Error('本地模型未配置');
    }
    try {
      const rows = await taskpool.execute(recognizeLocalTask, pagePath,
        config.detPath, config.recPath, config.dictText) as Array<string>;
      const out: Array<OcrRegion> = [];
      for (const row of rows) {
        const obj = JSON.parse(row) as Record<string, Object>;
        const text = obj['t'] as string;
        const x = obj['x'] as number;
        const y = obj['y'] as number;
        const w = obj['w'] as number;
        const h = obj['h'] as number;
        out.push(makeOcrRegion(text, makePixelRect(x, y, w, h)));
      }
      this.lastProbeDetail = '本地 PP-OCRv6（ONNX Runtime / TaskPool）';
      return out;
    } catch (e) {
      // TaskPool 在部分设备/模拟器上不可用：回退主线程，保证本地 OCR 仍可用。
      Log.warn('OcrService', 'taskpool local OCR failed, fallback main: ' + e);
      return await this.recognizeLocal(pagePath);
    }
  }

  /** 启动预热本地模型（仅在用户选择 local 档位时）；失败不抛到 UI。 */
  async prewarmLocal(): Promise<void> {
    if (!this.localEnabled || this.localConfig === undefined) {
      return;
    }
    await LocalOcrEngine.getInstance().init(this.localConfig);
  }

  /** Capability probe; throws a readable Error when OCR is unavailable (US-5 scene 7). */
  async ensureInit(lang: OcrLang = OcrLang.JPN): Promise<void> {
    this.lastLang = lang;
    if (this.initialized) {
      return;
    }
    try {
      const ok: boolean = await textRecognition.init();
      if (!ok) {
        this.lastProbeDetail = 'init() 返回 false：设备可能缺少文字识别服务';
        throw new Error(this.lastProbeDetail);
      }
      this.initialized = true;
      try {
        const langs: Array<string> = await textRecognition.getSupportedLanguages();
        this.lastProbeDetail = `init 成功，支持语言：${langs.join(',')}`;
      } catch (e) {
        this.lastProbeDetail = 'init 成功（语言列表查询失败）';
      }
      Log.info('OcrService', `ensureInit ok, lang hint=${lang}`);
    } catch (e) {
      const be = e as BusinessError;
      const detail = be.code !== undefined
        ? `code=${be.code}, msg=${be.message}`
        : '初始化调用异常';
      this.lastProbeDetail = `系统 OCR 能力不可用（${detail}）。部分模拟器缺少文字识别服务，请换真机验证。`;
      Log.error('OcrService', `ensureInit failed: ${this.lastProbeDetail}`);
      throw new Error(this.lastProbeDetail);
    }
  }

  /** Non-throwing probe for spike/diagnostics pages. */
  async probe(): Promise<boolean> {
    try {
      await this.ensureInit(this.lastLang);
      return true;
    } catch (e) {
      return false;
    }
  }

  getProbeDetail(): string {
    return this.lastProbeDetail;
  }

  /** Run line-level recognition; returns regions in original-pixel coords. */
  async recognize(pixelMap: image.PixelMap | undefined, lang: OcrLang = OcrLang.JPN,
    pagePath?: string): Promise<Array<OcrRegion>> {
    if (this.localEnabled && this.localConfig !== undefined && pagePath !== undefined) {
      const engine = LocalOcrEngine.getInstance();
      await engine.init(this.localConfig);
      this.lastProbeDetail = '本地 PP-OCRv6（ONNX Runtime）';
      return await engine.recognize(pagePath);
    }
    await this.ensureInit(lang);
    if (pixelMap === undefined) {
      throw new Error('系统 OCR 缺少页面像素图');
    }
    const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
    const result: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText(visionInfo);
    const regions: Array<OcrRegion> = [];
    const blocks = result.blocks;
    for (const block of blocks) {
      for (const line of block.lines) {
        const text = line.value.trim();
        if (text.length === 0) {
          continue;
        }
        regions.push(makeOcrRegion(text, OcrService.cornerPointsToRect(line.cornerPoints)));
      }
    }
    Log.info('OcrService', `recognize: ${regions.length} lines`);
    return regions;
  }

  async release(): Promise<void> {
    LocalOcrEngine.getInstance().release();
    if (!this.initialized) {
      return;
    }
    try {
      await textRecognition.release();
      this.initialized = false;
      this.lastProbeDetail = '已释放';
    } catch (e) {
      const be = e as BusinessError;
      Log.warn('OcrService', `release failed: code=${be.code}`);
    }
  }

  /** Collapse clockwise corner points into an axis-aligned rect (first point = top-left). */
  private static cornerPointsToRect(points: Array<textRecognition.PixelPoint>): PixelRect {
    if (points.length === 0) {
      return makePixelRect(0, 0, 0, 0);
    }
    let minX = points[0].x;
    let minY = points[0].y;
    let maxX = points[0].x;
    let maxY = points[0].y;
    for (const p of points) {
      if (p.x < minX) {
        minX = p.x;
      }
      if (p.y < minY) {
        minY = p.y;
      }
      if (p.x > maxX) {
        maxX = p.x;
      }
      if (p.y > maxY) {
        maxY = p.y;
      }
    }
    return makePixelRect(minX, minY, maxX - minX, maxY - minY);
  }
}
