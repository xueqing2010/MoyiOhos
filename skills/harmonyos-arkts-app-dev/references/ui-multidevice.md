# 多端 UI：手机 / 平板 / 2in1

## 1. 断点策略

不要用设备类型写死，按窗口宽度：

| 宽度 | 布局 |
|---|---|
| < 600vp | 手机：底部悬浮 Tab，单列 |
| 600–840vp | 平板竖屏 / 分屏：左侧 rail + 单列/双列 |
| > 840vp | 平板横屏 / 2in1：左侧 rail + 双列/双页 |

实现方式：
- 在根组件监听窗口尺寸：`window.on('windowSizeChange')`；
- 或使用系统断点 API（按 SDK 版本可用性）；
- 断点变化时只重排 shell，不重建所有页面状态。

## 2. 全屏与安全区

目标：内容铺满、顶部不被状态栏裁、底部不留白。

步骤：
1. `windowStage.getMainWindow().setWindowLayoutFullScreen(true)`；
2. 获取 `AvoidAreaType.TYPE_SYSTEM` 的 top 高度；
3. 根容器 padding-top = 状态栏高度（动态测量，不写死）；
4. 底部 Tab 设置 `barBottomMargin: 0`；
5. 监听横竖屏/分屏，重新测量并更新 padding。

常见坑：
- 只设置全屏，不加 padding → 标题被时间/信号遮挡；
- 加了固定 48vp padding → 平板/折叠屏太厚；
- Tab 同时加安全区和 bottomMargin → 底部空一条；
- 2in1 拖拽窗口后不重新测量 → 状态栏区域错位。

## 3. 沉浸光感

API 26 的材质：

```ts
import { uiMaterial } from '@kit.ArkUI';

@Builder
function GlassBar() {
  Column() {}
    .backgroundColor(Color.Transparent)
    .backgroundMaterial(uiMaterial.ImmersiveMaterial({
      style: uiMaterial.MaterialStyle.ULTRA_THIN,
      interactive: true,
      lightEffect: {}
    }))
}
```

使用位置：
- 底部悬浮 Tab 容器；
- NavDestination 标题栏；
- Slider/Toggle 等控件底板；
- 平板左侧 rail。

不要：
- 用普通半透明白 + blur 模拟，浅色背景会发灰；
- 给每个文字加材质；
- 材质叠太多层，性能下降。

## 4. 主题 Token

```ts
export class ThemeTokens {
  static readonly bg: ResourceColor = '#F7F9FF';
  static readonly card: ResourceColor = '#FFFFFF';
  static readonly primary: ResourceColor = '#2E6BFF';
  static readonly text: ResourceColor = '#111827';
  static readonly subText: ResourceColor = '#6B7280';
}
```

规则：
- 所有颜色/字号/间距走 token；
- 默认蓝白，夜间蓝黑；
- 旧紫色主题要迁移，不要只是隐藏入口；
- 切换主题重建 shell，避免缓存旧色；
- 深色模式检查对比度，尤其是白块译文。

## 5. 导航

- 手机：底部 Tab + NavDestination；
- 平板：左侧 rail + 右侧内容；
- 宽屏可双列（书架/历史）；
- 返回栈要统一，不要让 Tab 切换重置阅读页；
- 阅读器全屏时隐藏 Tab，退出恢复。

## 6. 动画

- Tabs 内容切换 320ms；
- 阅读器进入/退出 260–320ms；
- 覆盖层出现用淡入+轻微上移；
- 动画期间禁止重新 OCR/重新排版；
- 使用 `animateTo` 时注意 API 26 弃用警告，后续迁移。

## 7. 列表与图片

- `LazyForEach` 用于长列表；
- 图片解码放异步，列表快速滚动不要阻塞；
- 封面使用固定比例 + `objectFit`，避免抖动；
- 阅读器预加载前后 1–2 页，不要整本 decode；
- 大图缩放用 `ImageFit`/矩阵，不要反复重建 PixelMap。

## 8. 文字与无障碍

- 支持系统字体缩放，关键按钮不截断；
- 对比度至少 4.5:1；
- 图标加 accessibilityText；
- 触控区域不小于 44vp。

## 9. 2in1 特别项

- 可拖拽窗口，最小宽度要限制；
- 键盘/鼠标 hover 态要处理；
- 关闭按钮/窗口控制不要被自绘标题栏遮挡；
- 断点切换时保留滚动位置；
- 不要假设有状态栏（PC 可能没有）。

## 10. 三端验收清单

- [ ] 手机竖屏：底部 Tab 贴底，内容不被遮挡
- [ ] 平板横屏：左侧 rail，双列不错位
- [ ] 2in1 拖拽到窄/宽：布局实时切换
- [ ] 浅色/深色：文字与材质都可读
- [ ] 系统字体放大：按钮不截断
- [ ] 横竖屏切换：阅读进度不丢
- [ ] 截图留档到 docs/images
