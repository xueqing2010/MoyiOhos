import { ThemeTokens } from 'commons';
import { uiMaterial } from '@kit.ArkUI';

/**
 * 图片预览 — stage-2 page (owned by feature module; scaffold placeholder).
 */
@Component
export struct ImageViewerPage {
  build() {
    NavDestination() {
      Column({ space: 10 }) {
        Text('图片预览')
          .fontSize(ThemeTokens.FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text('功能接入中')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')
    }
    .title('图片预览', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
  }
}