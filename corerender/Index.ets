/**
 * corerender HAR entry.
 * 排版（页面坐标系）+ 覆盖绘制（contain-fit 变换）+ 页面覆盖规划 + 压测场景。
 */
export { DisplayRect, containFit, pixelToDisplay } from './src/main/ets/Geometry';
export {
  RenderOrientation,
  VerticalDirection,
  FontSizeMode,
  RenderOptions,
  LayoutRun,
  TextLayout,
  OverlayRegion,
  CharMeasurer,
  ApproxCharMeasurer,
  LayoutEngine,
  LayoutSelfTest,
  SelfTestResult,
  makeSelfTestResult,
  defaultRenderOptions,
  makeOverlayRegion
} from './src/main/ets/LayoutEngine';
export { OverlayRenderer, OverlayColors } from './src/main/ets/OverlayRenderer';
export { PageOverlay, OverlayItem } from './src/main/ets/PageOverlay';
export { FpsMeter } from './src/main/ets/FpsMeter';
export { StressScene } from './src/main/ets/StressScene';
