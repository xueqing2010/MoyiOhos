import { ThemeTokens } from 'commons';
import { Artwork } from './Artwork';

/**
 * EmptyState — 统一空态视图（stage-2：SVG 插画优先，兼容旧 glyph 占位）。
 *
 * 用法：
 * - 推荐：EmptyState({ icon: Artwork.EMPTY_SHELF, title: '还没有漫画', hint: '导入 zip / 目录 / 相册' })
 * - 默认：不传 icon 时展示通用插画 empty_generic（不再出现 emoji）。
 * - 兼容：仍传 glyph 时按旧逻辑渲染文字/emoji（glyph 优先于 icon）。
 * 文字参数名保持 title / hint / glyph 不变。
 */
@Component
export struct EmptyState {
  /** 兼容参数：非空时渲染文字/emoji 占位（旧页面迁移期用）。 */
  glyph: string = '';
  /** 彩色插画资源；为空态主视觉，默认通用插画。 */
  icon: Resource = Artwork.EMPTY_GENERIC;
  title: string | Resource = '';
  hint: string | Resource = '';
  /** 插画显示尺寸（vp），默认 128。 */
  iconSize: number = 128;

  build() {
    Column({ space: ThemeTokens.PAGE_PADDING }) {
      if (this.glyph.length > 0) {
        Text(this.glyph)
          .fontSize(44)
          .fontColor(ThemeTokens.TEXT_TERTIARY)
      } else {
        Image(this.icon)
          .width(this.iconSize)
          .height(this.iconSize)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
      Text(this.title)
        .fontSize(ThemeTokens.FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .textAlign(TextAlign.Center)
      Text(this.hint)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_HINT)
        .textAlign(TextAlign.Center)
        .padding({ left: 12, right: 12 })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .padding({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING })
    .backgroundColor(ThemeTokens.SURFACE)
  }
}
