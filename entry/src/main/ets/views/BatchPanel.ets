import { ThemeTokens } from 'commons';
import { ProgressCard } from '../components/ProgressCard';

/**
 * 批量翻译进度面板（T030 / US-6）：当前页/总数/失败数、取消、
 * 失败页单页重试入口。
 */
@Component
export struct BatchPanel {
  running: boolean = false;
  total: number = 0;
  done: number = 0;
  failed: number = 0;
  currentPage: number = 0;
  lastError: string = '';
  failedPageIds: Array<number> = [];
  onCancel: () => void = () => {
  };
  onRetryPage: (pageId: number) => void = () => {
  };

  build() {
    Column({ space: 8 }) {
      ProgressCard({
        title: this.running ? '批量翻译中' : '批量翻译完成',
        phase: `当前第 ${this.currentPage}/${this.total} 页 · 成功 ${this.done} · 失败 ${this.failed}`,
        done: this.done,
        total: this.total,
        currentName: '',
        cancelable: this.running,
        onCancel: () => {
          this.onCancel();
        }
      })

      if (this.lastError.length > 0) {
        Text(`最近错误：${this.lastError}`)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.RED)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.failedPageIds.length > 0) {
        Text(`失败页（可单页重试）：`)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.failedPageIds, (pageId: number) => {
              Button(`重试页#${pageId}`)
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.WHITE)
                .backgroundColor(ThemeTokens.WARN)
                .borderRadius(14)
                .height(30)
                .padding({ left: 12, right: 12 })
                .onClick(() => {
                  this.onRetryPage(pageId);
                })
            }, (pageId: number) => `${pageId}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .alignItems(HorizontalAlign.Start)
  }
}
