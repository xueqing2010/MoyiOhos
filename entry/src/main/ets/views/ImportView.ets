import { ThemeTokens } from 'commons';
import { ImportSheet } from './ImportSheet';
import { NovelImportPanel } from '../novel/NovelImportPanel';

/**
 * 导入 Tab (stage-2, 对齐上游 import_manga + novel_import)：
 * 漫画三通道（压缩包/目录/相册）与小说三格式（txt/epub/zip-html）入口。
 * 具体通道实现分别由 ImportSheet / NovelImportPanel 承载。
 */
@Component
export struct ImportView {
  build() {
    Column() {
      Text('导入')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 4, bottom: 10 })
      Scroll() {
        Column({ space: 16 }) {
          ImportSheet({ compactTop: true })
          NovelImportPanel()
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .layoutWeight(1)
      .width('100%')
    }
    .padding({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING })
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.SURFACE)
    .alignItems(HorizontalAlign.Start)
  }
}
