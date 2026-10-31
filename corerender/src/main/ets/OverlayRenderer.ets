import { DisplayRect } from './Geometry';
import { LayoutEngine, OverlayRegion, RenderOptions, TextLayout } from './LayoutEngine';
import { OverlayItem } from './PageOverlay';

type Ctx2D = CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;

/** 覆盖层配色（白块底 + 文字色）；反色模式由调用方传入深底浅字。 */
export class OverlayColors {
  boxFill: string = '#FFFFFF';
  textColor: string = '#1A1A1A';

  static make(boxFill: string, textColor: string): OverlayColors {
    const colors = new OverlayColors();
    colors.boxFill = boxFill;
    colors.textColor = textColor;
    return colors;
  }
}

/**
 * Overlay painter.
 *
 * 坐标约定（QA-1 修复的关键）：
 * - LayoutRun.x/y 是**页面坐标系**下字格中心的绝对坐标（由 LayoutEngine 算出）；
 * - 屏幕绘制走 paintPlan：逐字做 x' = dx + x*scale、y' = dy + y*scale、
 *   fontSize' = fontSize*scale，从而在目标分辨率上直接光栅化（文字清晰，不会被位图缩放糊掉）；
 * - 导出离屏合成直接传 scale=1/dx=0/dy=0，像素坐标 1:1。
 *
 * ⚠️ 字体单位坑（本轮 AUTO 字号偏小/字距巨大的根因）：
 * ArkUI Canvas 的**绘制坐标默认单位是 vp**，但 ctx.font 中不带单位的字号按 **px（物理像素）**
 * 解释（官方 FAQ 示例写作 'bold 18vp sans-serif' 即为此意）。若在 vp 画布上写 '21px'，
 * 实际只有 21 物理 px ≈ 6vp，而逐字坐标仍是 vp → 表现为“字号小了 density 倍、间距显得巨大”。
 * 因此 paintPlan/drawText 需要显式指定字号单位：
 * - 屏幕 Canvas（默认 vp 单位）→ fontUnit='vp'；
 * - 导出 OffscreenCanvas（用 LengthMetricsUnit.PX 创建）→ fontUnit='px'。
 */
export class OverlayRenderer {
  /**
   * 组装 canvas font 字符串。
   * ArkUI Canvas 的 ctx.font 字号按 **物理 px** 解释（坐标则是 vp），
   * 所以屏幕路径要把 vp 字号换算成 px；导出 PX 画布本来就是 px，直接使用。
   */
  static fontOf(fontSize: number, fontUnit: string): string {
    if (fontUnit === 'px') {
      return fontSize + 'px sans-serif';
    }
    return vp2px(fontSize) + 'px sans-serif';
  }

  /** White base block covering the bubble area (display/page coords). */
  static drawBox(ctx: Ctx2D, box: DisplayRect, fill: string = '#FFFFFF'): void {
    ctx.fillStyle = fill;
    ctx.fillRect(box.x, box.y, box.w, box.h);
  }

  /** Draw already-laid-out characters (runs use the same coordinate space as the canvas). */
  static drawText(ctx: Ctx2D, layout: TextLayout, color: string = '#1A1A1A',
    fontUnit: string = 'vp'): void {
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = color;
    let lastFs = -1;
    for (let i = 0; i < layout.runs.length; i++) {
      const run = layout.runs[i];
      if (Math.abs(run.fontSize - lastFs) > 0.01) {
        ctx.font = OverlayRenderer.fontOf(run.fontSize, fontUnit);
        lastFs = run.fontSize;
      }
      ctx.fillText(run.char, run.x, run.y);
    }
  }

  /** White block + text in one call (legacy display-space path, vp canvas). */
  static drawRegion(ctx: Ctx2D, region: OverlayRegion, layout: TextLayout,
    color: string = '#1A1A1A', boxFill: string = '#FFFFFF', fontUnit: string = 'vp'): void {
    OverlayRenderer.drawBox(ctx, region.box, boxFill);
    OverlayRenderer.drawText(ctx, layout, color, fontUnit);
  }

  /** Layout + draw a bubble's text with the given render options (legacy path, vp canvas). */
  static renderRegionText(ctx: Ctx2D, text: string, region: OverlayRegion,
    opts: RenderOptions, color: string = '#1A1A1A', boxFill: string = '#FFFFFF',
    fontUnit: string = 'vp'): TextLayout {
    const layout = LayoutEngine.layout(text, region.box, opts);
    OverlayRenderer.drawRegion(ctx, region, layout, color, boxFill, fontUnit);
    return layout;
  }

  /** 页面坐标 → 显示坐标（contain-fit）。 */
  static toDisplayRect(box: DisplayRect, scale: number, dx: number, dy: number): DisplayRect {
    const r: DisplayRect = {
      x: dx + box.x * scale,
      y: dy + box.y * scale,
      w: box.w * scale,
      h: box.h * scale
    };
    return r;
  }

  /**
   * 绘制页面坐标系排版结果：逐字变换到显示坐标后直接光栅化。
   * @param scale contain-fit 比例（vp/页面px 或 px/页面px）
   * @param dx/@param dy 居中偏移
   * @param fontUnit 字号单位：vp 画布用 'vp'，PX 画布（导出）用 'px'
   */
  static paintPlan(ctx: Ctx2D, items: Array<OverlayItem>, scale: number, dx: number, dy: number,
    colors: OverlayColors, fontUnit: string = 'vp'): void {
    if (scale <= 0 || items.length === 0) {
      return;
    }
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const box = item.box;
      if (colors.boxFill !== 'none') {
        ctx.fillStyle = colors.boxFill;
        ctx.fillRect(dx + box.x * scale, dy + box.y * scale, box.w * scale, box.h * scale);
      }
      const itemColor = item.textColor !== undefined && item.textColor.length > 0
        ? item.textColor : colors.textColor;
      const outline = itemColor.toUpperCase() === '#1A1A1A' ? '#FFFFFF' : '#1A1A1A';
      ctx.fillStyle = itemColor;
      let lastFs = -1;
      const runs = item.layout.runs;
      for (let k = 0; k < runs.length; k++) {
        const run = runs[k];
        const fs = run.fontSize * scale;
        if (fs <= 0) {
          continue;
        }
        if (Math.abs(fs - lastFs) > 0.01) {
          ctx.font = OverlayRenderer.fontOf(fs, fontUnit);
          lastFs = fs;
        }
        // 1px 级描边保证浅底黑字/深底白字都能读清。
        ctx.lineWidth = Math.max(1, fs * 0.06);
        ctx.lineJoin = 'round';
        ctx.strokeStyle = outline;
        ctx.strokeText(run.char, dx + run.x * scale, dy + run.y * scale);
        ctx.fillText(run.char, dx + run.x * scale, dy + run.y * scale);
      }
    }
  }

  /**
   * 单气泡便捷入口：在页面坐标排版后按 fit 变换绘制。
   * 返回排版结果（供调试/自检查看 measuredFontSize 等）。
   */
  static paintFitted(ctx: Ctx2D, text: string, box: DisplayRect, opts: RenderOptions,
    scale: number, dx: number, dy: number, colors: OverlayColors,
    fontUnit: string = 'vp'): TextLayout {
    const layout = LayoutEngine.layout(text, box, opts);
    const item: OverlayItem = { box: box, text: text, layout: layout, merged: 1 };
    const items: Array<OverlayItem> = [item];
    OverlayRenderer.paintPlan(ctx, items, scale, dx, dy, colors, fontUnit);
    return layout;
  }

  /** 绘制一个 OCR 框的版面（页面坐标排版 + fit 变换）。 */
  static paintPageRegions(ctx: Ctx2D, text: string, pageBox: DisplayRect, opts: RenderOptions,
    scale: number, dx: number, dy: number, colors: OverlayColors,
    fontUnit: string = 'vp'): TextLayout {
    return OverlayRenderer.paintFitted(ctx, text, pageBox, opts, scale, dx, dy, colors, fontUnit);
  }
}
