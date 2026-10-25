import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { uiMaterial } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { OcrRegion, PixelRect, SpikeOutcome } from 'coremodel';
import { DisplayRect, containFit, pixelToDisplay } from 'corerender';
import { OcrLang, OcrService } from 'coreocr';
import { ThemeTokens, Log } from 'commons';
import { SpikeKeys, SpikeViewModel } from '../viewmodel/SpikeViewModel';
import { PageTranslateService } from '../service/PageTranslateService';

/**
 * P0-4 OCR 诊断页（T027 / US-5）：选图 → 行级识别 → 画布标注全部
 * 包围盒 + 文本清单 + 耗时；能力缺失时显示探测结论（FR-016）。
 */
@Component
export struct SpikeOcrPage {
  @State status: string = '未执行';
  @State detail: string = '';
  @State busy: boolean = false;
  @State regions: Array<OcrRegion> = [];
  @State elapsed: number = 0;
  @State areaWidth: number = 0;
  @State areaHeight: number = 0;
  @State hasImage: boolean = false;
  private canvasReady: boolean = false;
  private imageW: number = 0;
  private imageH: number = 0;
  private pixelMap: image.PixelMap | undefined = undefined;
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  private async record(outcome: SpikeOutcome, text: string): Promise<void> {
    try {
      await SpikeViewModel.makeResultPair(SpikeKeys.P0_4, outcome, text);
    } catch (e) {
      Log.error('SpikeOcrPage', `record failed: ${e}`);
    }
  }

  private async run(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.status = '执行中';
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const opts = new photoAccessHelper.PhotoSelectOptions();
      opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 1;
      const result = await picker.select(opts);
      if (result.photoUris.length === 0) {
        this.status = '未执行';
        this.busy = false;
        return;
      }
      await this.process(result.photoUris[0]);
    } catch (e) {
      this.status = '失败';
      this.detail = `${e}`;
      await this.record(SpikeOutcome.FAIL, this.detail);
    }
    this.busy = false;
  }

  private async process(uri: string): Promise<void> {
    const lang = await PageTranslateService.loadOcrLang();
    let pm: image.PixelMap | undefined = undefined;
    try {
      pm = await PageTranslateService.decode(uri);
      const info = await pm.getImageInfo();
      this.imageW = info.size.width;
      this.imageH = info.size.height;
      // OCR 能力探测（不可用时抛可读错误）
      await OcrService.getInstance().ensureInit(lang);
      const t0 = Date.now();
      const found = await OcrService.getInstance().recognize(pm, lang);
      this.elapsed = Date.now() - t0;
      if (this.pixelMap !== undefined) {
        try {
          this.pixelMap.release();
        } catch (ignore) {
        }
      }
      this.pixelMap = pm;
      this.regions = found;
      this.hasImage = true;
      this.draw();
      if (found.length > 0) {
        this.status = '通过';
        this.detail = `识别 ${found.length} 行，耗时 ${this.elapsed}ms`;
        await this.record(SpikeOutcome.PASS, this.detail);
      } else {
        this.status = '降级';
        this.detail = `OCR 可用但未识别到文字（耗时 ${this.elapsed}ms）`;
        await this.record(SpikeOutcome.DEGRADED, this.detail);
      }
    } catch (e) {
      if (pm !== undefined) {
        try {
          pm.release();
        } catch (ignore) {
        }
      }
      this.status = '降级';
      this.detail = `${e}`;
      await this.record(SpikeOutcome.DEGRADED, `OCR 能力不可用：${this.detail}`);
    }
  }

  private draw(): void {
    if (!this.canvasReady || this.pixelMap === undefined) {
      return;
    }
    const w = this.areaWidth;
    const h = this.areaHeight;
    if (w <= 0 || h <= 0 || this.imageW <= 0 || this.imageH <= 0) {
      return;
    }
    const ctx = this.ctx;
    ctx.clearRect(0, 0, w, h);
    const fit = containFit(this.imageW, this.imageH, w, h);
    ctx.drawImage(this.pixelMap, fit.dx, fit.dy, this.imageW * fit.scale, this.imageH * fit.scale);
    ctx.strokeStyle = '#FF3B30';
    ctx.lineWidth = 2;
    ctx.fillStyle = '#FF3B30';
    ctx.font = '12px sans-serif';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    for (let i = 0; i < this.regions.length; i++) {
      const box: DisplayRect = pixelToDisplay(this.regions[i].box, fit.scale, fit.dx, fit.dy);
      ctx.strokeRect(box.x, box.y, box.w, box.h);
      ctx.fillText(`${i + 1}`, box.x + 2, box.y + 2);
    }
  }

  @Builder
  boxRow(r: OcrRegion, idx: number) {
    Column({ space: 2 }) {
      Text(`#${idx + 1}  [x${Math.round(r.box.x)}, y${Math.round(r.box.y)}, ${Math.round(r.box.w)}×${Math.round(r.box.h)}]`)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_HINT)
      Text(r.text)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4, bottom: 4 })
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        Row() {
          Text(`P0-4 OCR 诊断  ${this.status}`)
            .fontSize(ThemeTokens.FONT_SUBTITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.status === '通过' ? ThemeTokens.SUCCESS
              : (this.status === '失败' ? ThemeTokens.RED : ThemeTokens.TEXT_PRIMARY))
            .layoutWeight(1)
          Button('选择图片')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .backgroundColor(this.busy ? ThemeTokens.SURFACE_VARIANT : ThemeTokens.PRIMARY)
            .fontColor(this.busy ? ThemeTokens.TEXT_HINT : ThemeTokens.WHITE)
            .borderRadius(16)
            .height(32)
            .padding({ left: 14, right: 14 })
            .enabled(!this.busy)
            .onClick(() => {
              this.run();
            })
        }
        .width('100%')

        if (this.detail.length > 0) {
          Text(this.detail)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(this.status === '失败' ? ThemeTokens.RED : ThemeTokens.TEXT_HINT)
            .width('100%')
        }

        Stack() {
          Canvas(this.ctx)
            .width('100%')
            .height('100%')
            .onReady(() => {
              this.canvasReady = true;
              this.draw();
            })
          if (!this.hasImage) {
            Text('点击右上「选择图片」执行识别')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_HINT)
          }
        }
        .width('100%')
        .height(300)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.areaWidth = newArea.width as number;
          this.areaHeight = newArea.height as number;
          this.draw();
        })

        if (this.regions.length > 0) {
          Text(`识别文本清单（${this.regions.length} 行，耗时 ${this.elapsed}ms）`)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .width('100%')
          List({ space: 2 }) {
            ForEach(this.regions, (r: OcrRegion, idx: number) => {
              ListItem() {
                this.boxRow(r, idx)
              }
            }, (r: OcrRegion, idx: number) => `${idx}-${r.text.length}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        } else {
          Blank()
        }
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .title('OCR 诊断（P0-4）', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
  }
}