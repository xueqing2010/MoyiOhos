import { ThemeTokens } from 'commons';
import {
  ReaderAnimation,
  ReaderBg,
  ReaderFlow,
  ReaderMode,
  ReaderSettings
} from '../viewmodel/ReaderViewModel';

/**
 * 阅读器菜单（底部面板）：显示三态、4 阅读模式、4 翻页动画、6 背景、
 * 进度跳页、缩略图入口、翻译本页 / 批量翻译 / 导出 / 目录 / 设置 / 自动翻页。
 * 详细排版与滤镜参数在 ReaderSettingsSheet 中。
 */
@Component
export struct ReaderMenuView {
  @Prop title: string = '';
  @Prop settings: ReaderSettings = new ReaderSettings();
  @Prop current: number = 0;
  @Prop total: number = 0;
  @Prop translating: boolean = false;
  @Prop ocrAvailable: boolean = true;
  @Prop batchRunning: boolean = false;
  @Prop exportBusy: boolean = false;
  @Prop autoTurning: boolean = false;
  onFlowChange: (flow: string) => void = () => {
  };
  onAnimChange: (anim: string) => void = () => {
  };
  onBgChange: (bg: string) => void = () => {
  };
  onModeChange: (mode: string) => void = () => {
  };
  onJump: (page: number) => void = () => {
  };
  onOpenSettings: () => void = () => {
  };
  onOpenThumbnails: () => void = () => {
  };
  onOpenToc: () => void = () => {
  };
  onTranslatePage: () => void = () => {
  };
  onBatch: () => void = () => {
  };
  onExport: () => void = () => {
  };
  onToggleAuto: () => void = () => {
  };
  onBack: () => void = () => {
  };
  onClose: () => void = () => {
  };

  @Builder
  chip(label: string, active: boolean, onTap: () => void, enabled: boolean = true) {
    Text(label)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(active ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      .backgroundColor(active ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_VARIANT)
      .borderRadius(14)
      .height(30)
      .padding({ left: 12, right: 12 })
      .opacity(enabled ? 1 : 0.45)
      .margin({ right: 6, bottom: 4 })
      .onClick(() => {
        if (enabled) {
          onTap();
        }
      })
  }

  @Builder
  labelChip(icon: Resource, label: string, active: boolean, onTap: () => void, enabled: boolean = true) {
    Row({ space: 4 }) {
      Image(icon)
        .width(14)
        .height(14)
        .fillColor(active ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      Text(label)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(active ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
    }
    .backgroundColor(active ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_VARIANT)
    .borderRadius(14)
    .height(30)
    .padding({ left: 10, right: 12 })
    .opacity(enabled ? 1 : 0.45)
    .onClick(() => {
      if (enabled) {
        onTap();
      }
    })
  }

  @Builder
  bgSwatch(key: string) {
    Column({ space: 3 }) {
      Stack() {
        Circle()
          .width(26)
          .height(26)
          .fill(ReaderBg.colorOf(key))
          .stroke(ThemeTokens.DIVIDER)
          .strokeWidth(1)
        if (this.settings.bg === key) {
          Circle()
            .width(26)
            .height(26)
            .fill(Color.Transparent)
            .stroke(ThemeTokens.PRIMARY)
            .strokeWidth(2.5)
        }
      }
      Text(ReaderBg.labelOf(key))
        .fontSize(10)
        .fontColor(this.settings.bg === key ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_HINT)
    }
    .onClick(() => {
      this.onBgChange(key);
    })
  }

  @Builder
  actionButton(icon: Resource, label: string, enabled: boolean, tint: string, onTap: () => void) {
    Column({ space: 5 }) {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(enabled ? tint : ThemeTokens.TEXT_HINT)
      Text(label)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(enabled ? ThemeTokens.TEXT_SECONDARY : ThemeTokens.TEXT_HINT)
    }
    .layoutWeight(1)
    .padding({ top: 9, bottom: 9 })
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .opacity(enabled ? 1 : 0.55)
    .onClick(() => {
      if (enabled) {
        onTap();
      }
    })
  }

  private progressText(): string {
    if (this.total <= 0) {
      return '0 / 0';
    }
    return (this.current + 1) + ' / ' + this.total;
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_arrow_left'))
            .width(18)
            .height(18)
            .fillColor(ThemeTokens.TEXT_PRIMARY)
        }
        .width(32)
        .height(32)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .onClick(() => {
          this.onBack();
        })
        Text(this.title.length > 0 ? this.title : '阅读')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.progressText())
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.PRIMARY)
      }
      .width('100%')

      // 显示三态
      Row({ space: 8 }) {
        this.labelChip($r('app.media.ic_reader_text'), '仅译文', this.settings.mode === ReaderMode.TRANS, () => {
          this.onModeChange(ReaderMode.TRANS);
        })
        this.labelChip($r('app.media.ic_reader_text'), '仅原文', this.settings.mode === ReaderMode.ORIG, () => {
          this.onModeChange(ReaderMode.ORIG);
        })
        this.labelChip($r('app.media.ic_image'), '纯原图', this.settings.mode === ReaderMode.RAW, () => {
          this.onModeChange(ReaderMode.RAW);
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // 4 阅读模式
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach([ReaderFlow.LTR, ReaderFlow.RTL, ReaderFlow.VERTICAL, ReaderFlow.WEBTOON], (flow: string) => {
          this.chip(ReaderFlow.label(flow), this.settings.flow === flow, () => {
            this.onFlowChange(flow);
          })
        }, (flow: string) => flow)
      }
      .width('100%')

      // 4 翻页动画
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach([ReaderAnimation.NONE, ReaderAnimation.SLIDE, ReaderAnimation.COVER, ReaderAnimation.CURL],
          (anim: string) => {
            this.chip(ReaderAnimation.label(anim), this.settings.animation === anim, () => {
              this.onAnimChange(anim);
            }, this.settings.flow !== ReaderFlow.WEBTOON)
          }, (anim: string) => anim)
      }
      .width('100%')

      // 6 背景
      Row({ space: 8 }) {
        ForEach(ReaderBg.keys(), (key: string) => {
          this.bgSwatch(key)
        }, (key: string) => key)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 进度跳页
      Column({ space: 2 }) {
        Slider({
          value: this.current,
          min: 0,
          max: this.total > 1 ? this.total - 1 : 1,
          step: 1,
          style: SliderStyle.OutSet
        })
          .selectedColor(ThemeTokens.PRIMARY)
          .trackColor(ThemeTokens.SURFACE_VARIANT)
          .blockColor(ThemeTokens.PRIMARY)
          .width('100%')
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.onJump(Math.round(value));
            }
          })
        Row() {
          Text('第 ' + (this.current + 1) + ' 页')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
            .layoutWeight(1)
          Text('共 ' + this.total + ' 页')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        .width('100%')
      }
      .width('100%')

      // 功能入口
      Row({ space: 8 }) {
        this.actionButton(this.translating ? $r('app.media.ic_reader_refresh') : $r('app.media.ic_translate'),
          this.translating ? '翻译中' : '翻译本页', this.ocrAvailable && !this.translating,
          ThemeTokens.PRIMARY, () => {
            this.onTranslatePage();
          })
        this.actionButton($r('app.media.ic_reader_batch'), this.batchRunning ? '批量中' : '批量翻译',
          this.ocrAvailable, ThemeTokens.ACCENT, () => {
            this.onBatch();
          })
        this.actionButton($r('app.media.ic_reader_export'), this.exportBusy ? '导出中' : '导出ZIP',
          !this.exportBusy, ThemeTokens.SUCCESS, () => {
            this.onExport();
          })
        this.actionButton($r('app.media.ic_reader_toc'), '目录', true, ThemeTokens.TEXT_SECONDARY, () => {
          this.onOpenToc();
        })
      }
      .width('100%')

      Row({ space: 8 }) {
        this.actionButton($r('app.media.ic_reader_settings'), '设置', true, ThemeTokens.TEXT_SECONDARY, () => {
          this.onOpenSettings();
        })
        this.actionButton($r('app.media.ic_view_grid'), '缩略图', true, ThemeTokens.TEXT_SECONDARY, () => {
          this.onOpenThumbnails();
        })
        this.actionButton(this.autoTurning ? $r('app.media.ic_pause') : $r('app.media.ic_play'),
          this.autoTurning ? '停止自动' : '自动翻页', true,
          this.autoTurning ? ThemeTokens.WARN : ThemeTokens.TEXT_SECONDARY, () => {
            this.onToggleAuto();
          })
        this.actionButton($r('app.media.ic_chevron_down'), '收起', true, ThemeTokens.TEXT_SECONDARY, () => {
          this.onClose();
        })
      }
      .width('100%')

      if (!this.ocrAvailable) {
        Text('系统 OCR 能力不可用（工作台 → P0-4 诊断）')
          .fontSize(10)
          .fontColor(ThemeTokens.WARN)
          .width('100%')
      }
    }
    .padding({
      left: ThemeTokens.PAGE_PADDING,
      right: ThemeTokens.PAGE_PADDING,
      top: ThemeTokens.PAGE_PADDING,
      bottom: 20
    })
    .width('100%')
    .borderRadius({ topLeft: ThemeTokens.RADIUS_CARD, topRight: ThemeTokens.RADIUS_CARD })
    .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
    .alignItems(HorizontalAlign.Center)
  }
}
