import { SpikeOutcome } from 'coremodel';
import { uiMaterial } from '@kit.ArkUI';
import {
  DisplayRect,
  FpsMeter,
  FontSizeMode,
  LayoutEngine,
  OverlayRenderer,
  RenderOptions,
  RenderOrientation,
  StressScene,
  VerticalDirection,
  containFit,
  pixelToDisplay
} from 'corerender';
import { ThemeTokens, Log } from 'commons';
import { SpikeKeys, SpikeViewModel } from '../viewmodel/SpikeViewModel';

/**
 * P0-5 渲染压测页（T028 / US-5）：内置 24 气泡场景连续渲染（竖排为主，
 * 可切横排），FpsMeter 实时帧率显示与记录（目标 ≥50fps 如实记录）。
 */
@Component
export struct SpikeRenderPage {
  @State fps: number = 0;
  @State running: boolean = false;
  @State forceHorizontal: boolean = false;
  @State status: string = '未执行';
  @State detail: string = '';
  @State areaWidth: number = 0;
  @State areaHeight: number = 0;
  private canvasReady: boolean = false;
  private bubbles = StressScene.build();
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private meter: FpsMeter = new FpsMeter();
  private timerId: number = -1;
  private lastFps: number = 0;

  private renderOptions(orientation: RenderOrientation): RenderOptions {
    const o: RenderOptions = {
      orientation: orientation,
      verticalDirection: VerticalDirection.RTL,
      fontSizeMode: FontSizeMode.AUTO,
      fixedFontSize: 16,
      padding: 4
    };
    return o;
  }

  private draw(): void {
    if (!this.canvasReady) {
      return;
    }
    const w = this.areaWidth;
    const h = this.areaHeight;
    if (w <= 0 || h <= 0) {
      return;
    }
    const ctx = this.ctx;
    ctx.fillStyle = '#101014';
    ctx.fillRect(0, 0, w, h);
    const fit = containFit(StressScene.CANVAS_W, StressScene.CANVAS_H, w, h);
    for (const bubble of this.bubbles) {
      const box: DisplayRect = pixelToDisplay(
        { x: bubble.region.box.x, y: bubble.region.box.y, w: bubble.region.box.w, h: bubble.region.box.h },
        fit.scale, fit.dx, fit.dy);
      const orientation = this.forceHorizontal ? RenderOrientation.HORIZONTAL : bubble.orientation;
      const opts = this.renderOptions(orientation);
      const layout = LayoutEngine.layout(bubble.region.translated, box, opts);
      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect(box.x, box.y, box.w, box.h);
      OverlayRenderer.drawText(ctx, layout, '#1A1A1A');
    }
  }

  private start(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    this.status = '执行中';
    this.meter.start((value: number) => {
      this.fps = value;
      this.lastFps = value;
    });
    this.timerId = setInterval(() => {
      this.draw();
    }, 16);
  }

  private stop(): void {
    this.running = false;
    this.meter.stop();
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private async record(): Promise<void> {
    const measured = this.lastFps;
    let outcome: SpikeOutcome = SpikeOutcome.DEGRADED;
    if (measured >= 50) {
      outcome = SpikeOutcome.PASS;
    }
    if (measured <= 0) {
      this.detail = '未采集到帧率（displaySync 不可用或未开始压测），模拟器实测值待补';
    } else {
      this.detail = `模拟器实测 ${measured.toFixed(1)}fps（24 气泡场景，${
        this.forceHorizontal ? '横排' : '竖排为主'}），目标 ≥50fps`;
    }
    this.status = outcome === SpikeOutcome.PASS ? '通过' : '降级';
    try {
      await SpikeViewModel.makeResultPair(SpikeKeys.P0_5, outcome, this.detail);
    } catch (e) {
      Log.error('SpikeRenderPage', `record failed: ${e}`);
    }
  }

  private toggleOrientation(): void {
    this.forceHorizontal = !this.forceHorizontal;
    this.draw();
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        Row() {
          Text(`P0-5 渲染压测  ${this.status}`)
            .fontSize(ThemeTokens.FONT_SUBTITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.status === '通过' ? ThemeTokens.SUCCESS : ThemeTokens.TEXT_PRIMARY)
            .layoutWeight(1)
          Text(`${this.fps.toFixed(1)} fps`)
            .fontSize(ThemeTokens.FONT_SUBTITLE)
            .fontColor(this.fps >= 50 ? ThemeTokens.SUCCESS : ThemeTokens.WARN)
        }
        .width('100%')

        Text('24 气泡场景（竖排为主）连续重绘，displaySync 驱动帧率统计；目标 ≥50fps（SC-004）')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')

        Canvas(this.ctx)
          .width('100%')
          .height(360)
          .onReady(() => {
            this.canvasReady = true;
            this.draw();
          })
          .onAreaChange((oldArea: Area, newArea: Area) => {
            this.areaWidth = newArea.width as number;
            this.areaHeight = newArea.height as number;
            this.draw();
          })

        if (this.detail.length > 0) {
          Text(this.detail)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
            .width('100%')
        }

        Row({ space: 10 }) {
          Button(this.running ? '停止' : '开始压测')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .backgroundColor(this.running ? ThemeTokens.RED : ThemeTokens.PRIMARY)
            .fontColor(ThemeTokens.WHITE)
            .borderRadius(18)
            .height(36)
            .padding({ left: 20, right: 20 })
            .onClick(() => {
              if (this.running) {
                this.stop();
              } else {
                this.start();
              }
            })
          Button(this.forceHorizontal ? '切回竖排' : '切横排')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .borderRadius(18)
            .height(36)
            .padding({ left: 20, right: 20 })
            .onClick(() => {
              this.toggleOrientation();
            })
          Button('记录结论')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .backgroundColor(ThemeTokens.SUCCESS)
            .fontColor(ThemeTokens.WHITE)
            .borderRadius(18)
            .height(36)
            .padding({ left: 20, right: 20 })
            .onClick(() => {
              this.record();
            })
        }
        .width('100%')
        Blank()
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .title('渲染压测（P0-5）', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true,
        interactive: true,
        lightEffect: {}
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
    .onHidden(() => {
      this.stop();
    })
  }
}