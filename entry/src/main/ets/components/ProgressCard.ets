import { ThemeTokens } from 'commons';

/**
 * 通用进度卡片（T020）：导入 / 下载 / 批量翻译复用。
 * phase 文案 + 当前项名 + 进度条（total<=0 时转为不定态）+ 取消按钮。
 * 对外参数保持不变；stage-2 仅做紫夜视觉收敛（描边、百分比、状态行）。
 */
@Component
export struct ProgressCard {
  title: string = '';
  phase: string = '';
  done: number = 0;
  total: number = 0;
  currentName: string = '';
  cancelable: boolean = false;
  onCancel: () => void = () => {
  };

  /** 进度百分比（0-100，total<=0 时返回 0）。 */
  private percent(): number {
    if (this.total <= 0) {
      return 0;
    }
    const value: number = Math.round(this.done * 100 / this.total);
    if (value < 0) {
      return 0;
    }
    return value > 100 ? 100 : value;
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text(this.title)
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        if (this.total > 0) {
          Text(this.percent() + '%')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.PRIMARY)
            .margin({ right: this.cancelable ? 8 : 2 })
        }
        if (this.cancelable) {
          Button('取消')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.RED)
            .backgroundColor(Color.Transparent)
            .borderWidth(1)
            .borderColor(ThemeTokens.RED)
            .borderRadius(14)
            .height(28)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.onCancel();
            })
        }
      }
      .width('100%')

      if (this.phase.length > 0) {
        Text(this.phase + (this.currentName.length > 0 ? '：' + this.currentName : ''))
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (this.total > 0) {
        Progress({ value: this.done, total: this.total, type: ProgressType.Linear })
          .color(ThemeTokens.PRIMARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .height(6)
          .borderRadius(3)
          .width('100%')
        Row() {
          Text('正在处理')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
          Blank()
          Text(this.done + '/' + this.total)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        .width('100%')
      } else {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(ThemeTokens.PRIMARY)
          Text('准备中…')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        .width('100%')
      }
    }
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .border({ width: 1, color: ThemeTokens.DIVIDER })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
