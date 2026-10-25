import { Manga } from 'coremodel';
import { ThemeTokens } from 'commons';
import { MangaImportPanel } from './MangaImportPanel';

/**
 * 导入面板薄封装（stage-2 S102）：对对外保持 @Component export struct ImportSheet
 * 且可无参使用（ImportView 在导入 Tab 内无参调用；书架以 bindSheet 使用并接收回调）。
 * 实际三通道/进度/失败原因/示例数据/向导入口由 MangaImportPanel 承载；
 * 小说导入面板（NovelImportPanel）保持独立，不在此处混排。
 */
@Component
export struct ImportSheet {
  /** 导入/示例数据完成回调（默认空实现，保证可无参使用）。 */
  onImported: (mangas: Array<Manga>) => void = () => {
  };
  /** 打开导入向导的可选回调（未提供时由面板默认跳转）。 */
  onWizard?: () => void = undefined;

  build() {
    Column() {
      MangaImportPanel({
        onImported: (mangas: Array<Manga>) => {
          this.onImported(mangas);
        },
        onWizard: this.onWizard
      })
    }
    .padding({
      left: ThemeTokens.PAGE_PADDING,
      right: ThemeTokens.PAGE_PADDING,
      top: ThemeTokens.PAGE_PADDING,
      bottom: 30
    })
    .width('100%')
    .backgroundColor(ThemeTokens.SURFACE)
    .alignItems(HorizontalAlign.Start)
  }
}
