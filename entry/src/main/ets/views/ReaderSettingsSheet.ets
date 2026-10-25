import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens } from 'commons';
import { LayoutSelfTest, SelfTestResult } from 'corerender';
import {
  ReaderAnimation,
  ReaderBg,
  ReaderFlow,
  ReaderSettings
} from '../viewmodel/ReaderViewModel';

/** 复制设置对象（V1 状态需要新对象引用才会触发 @Prop 更新）。 */
export function cloneReaderSettings(src: ReaderSettings): ReaderSettings {
  const s = new ReaderSettings();
  s.bg = src.bg;
  s.mode = src.mode;
  s.flow = src.flow;
  s.animation = src.animation;
  s.orientation = src.orientation;
  s.verticalDirection = src.verticalDirection;
  s.fontSizeMode = src.fontSizeMode;
  s.fixedFontSize = src.fixedFontSize;
  s.lineHeightPercent = src.lineHeightPercent;
  s.margin = src.margin;
  s.whiteMerge = src.whiteMerge;
  s.autoInterval = src.autoInterval;
  s.brightness = src.brightness;
  s.contrast = src.contrast;
  s.invert = src.invert;
  s.grayscale = src.grayscale;
  return s;
}

/**
 * 阅读设置面板（ReaderSettingsSheet，新建）：
 * 4 阅读模式 / 4 翻页动画 / 6 背景 / 反色灰度 / 亮度对比 /
 * 竖排方向 / 字号自动+固定 / 行距 / 边距 / 白块合并 / 自动翻页间隔 / 排版自检。
 * 每次改动立即 onSettingsChange（父页面持久化并实时重绘当前页）。
 */
@Component
export struct ReaderSettingsSheet {
  @Prop settings: ReaderSettings = new ReaderSettings();
  onSettingsChange: (s: ReaderSettings) => void = () => {
  };
  onClose: () => void = () => {
  };
  @State selfTestDone: boolean = false;
  @State selfTestPassed: boolean = false;
  @State selfTestSummary: string = '';
  @State selfTestItems: Array<SelfTestResult> = [];

  private update(mutator: (s: ReaderSettings) => void): void {
    const next = cloneReaderSettings(this.settings);
    mutator(next);
    this.onSettingsChange(next);
  }

  @Builder
  titleRow(title: string) {
    Text(title)
      .fontSize(ThemeTokens.FONT_CAPTION)
      .fontColor(ThemeTokens.TEXT_HINT)
      .width('100%')
      .margin({ top: 6, bottom: 2 })
  }

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
      this.update((s: ReaderSettings) => {
        s.bg = key;
      });
    })
  }

  @Builder
  switchRow(label: string, value: boolean, onToggle: () => void) {
    Row() {
      Text(label)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(ThemeTokens.PRIMARY)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          interactive: true,
          lightEffect: {}
        }))
        .onChange((isOn: boolean) => {
          if (isOn !== value) {
            onToggle();
          }
        })
    }
    .width('100%')
    .height(40)
  }

  @Builder
  sliderRow(label: string, value: number, min: number, max: number, step: number, suffix: string,
    onChange: (v: number) => void) {
    Column({ space: 2 }) {
      Row() {
        Text(label)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .layoutWeight(1)
        Text(value + suffix)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .width('100%')
      Slider({ value: value, min: min, max: max, step: step, style: SliderStyle.OutSet })
        .selectedColor(ThemeTokens.PRIMARY)
        .trackColor(ThemeTokens.SURFACE_VARIANT)
        .blockColor(ThemeTokens.PRIMARY)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          interactive: true,
          lightEffect: {}
        }))
        .width('100%')
        .onChange((v: number, mode: SliderChangeMode) => {
          onChange(Math.round(v));
        })
    }
    .width('100%')
  }

  @Builder
  sectionLayout() {
    this.titleRow('排版')
    Row({ space: 8 }) {
      this.chip('横排', this.settings.orientation === 0, () => {
        this.update((s: ReaderSettings) => {
          s.orientation = 0;
        });
      })
      this.chip('竖排', this.settings.orientation === 1, () => {
        this.update((s: ReaderSettings) => {
          s.orientation = 1;
        });
      })
      Blank()
      this.chip('右到左', this.settings.verticalDirection === 0, () => {
        this.update((s: ReaderSettings) => {
          s.verticalDirection = 0;
        });
      })
      this.chip('左到右', this.settings.verticalDirection === 1, () => {
        this.update((s: ReaderSettings) => {
          s.verticalDirection = 1;
        });
      })
    }
    .width('100%')
    Row({ space: 8 }) {
      Text('字号')
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_HINT)
        .width(40)
      this.chip('自动', this.settings.fontSizeMode === 0, () => {
        this.update((s: ReaderSettings) => {
          s.fontSizeMode = 0;
        });
      })
      this.chip('固定', this.settings.fontSizeMode === 1, () => {
        this.update((s: ReaderSettings) => {
          s.fontSizeMode = 1;
        });
      })
    }
    .width('100%')
    .margin({ top: 6 })
    if (this.settings.fontSizeMode === 1) {
      this.sliderRow('固定字号', this.settings.fixedFontSize, 12, 40, 1, ' px', (v: number) => {
        this.update((s: ReaderSettings) => {
          s.fixedFontSize = v;
        });
      })
    }
    this.sliderRow('行距', this.settings.lineHeightPercent, 100, 200, 5, '%', (v: number) => {
      this.update((s: ReaderSettings) => {
        s.lineHeightPercent = v;
      });
    })
    this.sliderRow('页边距', this.settings.margin, 0, 32, 1, ' vp', (v: number) => {
      this.update((s: ReaderSettings) => {
        s.margin = v;
      });
    })
    this.switchRow('白块合并', this.settings.whiteMerge, () => {
      this.update((s: ReaderSettings) => {
        s.whiteMerge = !s.whiteMerge;
      });
    })
  }

  @Builder
  sectionFilter() {
    this.titleRow('滤镜与亮度')
    Row({ space: 8 }) {
      Blank()
      this.chip('反色', this.settings.invert, () => {
        this.update((s: ReaderSettings) => {
          s.invert = !s.invert;
        });
      })
      this.chip('灰度', this.settings.grayscale, () => {
        this.update((s: ReaderSettings) => {
          s.grayscale = !s.grayscale;
        });
      })
      Blank()
    }
    .width('100%')
    this.sliderRow('亮度', this.settings.brightness, 20, 100, 1, '%', (v: number) => {
      this.update((s: ReaderSettings) => {
        s.brightness = v;
      });
    })
    this.sliderRow('对比度', this.settings.contrast, 50, 150, 1, '%', (v: number) => {
      this.update((s: ReaderSettings) => {
        s.contrast = v;
      });
    })
  }

  @Builder
  sectionSelfTest() {
    this.titleRow('排版自检（竖排 QA-1 回归）')
    Row({ space: 10 }) {
      Button('运行自检')
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
        .backgroundColor(ThemeTokens.PRIMARY)
        .borderRadius(14)
        .height(30)
        .padding({ left: 14, right: 14 })
        .onClick(() => {
          this.runSelfTest();
        })
      if (this.selfTestDone) {
        Text(this.selfTestSummary)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(this.selfTestPassed ? ThemeTokens.SUCCESS : ThemeTokens.RED)
      }
    }
    .width('100%')
    if (this.selfTestDone) {
      Column({ space: 3 }) {
        ForEach(this.selfTestItems, (item: SelfTestResult) => {
          Row({ space: 6 }) {
            Text(item.passed ? 'PASS' : 'FAIL')
              .fontSize(10)
              .fontColor(item.passed ? ThemeTokens.SUCCESS : ThemeTokens.RED)
              .width(34)
            Text(item.name)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_SECONDARY)
              .layoutWeight(1)
            Text(item.detail)
              .fontSize(10)
              .fontColor(ThemeTokens.TEXT_HINT)
          }
          .width('100%')
        }, (item: SelfTestResult) => item.name)
      }
      .width('100%')
      .padding(8)
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    }
  }

  private runSelfTest(): void {
    const items = LayoutSelfTest.run();
    this.selfTestItems = items;
    this.selfTestDone = true;
    this.selfTestPassed = LayoutSelfTest.passed(items);
    this.selfTestSummary = LayoutSelfTest.summary(items);
  }

  build() {
    Column() {
      Row() {
        Text('阅读设置')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_close'))
            .width(18)
            .height(18)
            .fillColor(ThemeTokens.TEXT_SECONDARY)
        }
        .width(34)
        .height(34)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .margin({ bottom: 4 })

      Scroll() {
        Column({ space: 2 }) {
          this.titleRow('阅读模式（翻页方式）')
          Flex({ wrap: FlexWrap.Wrap }) {
            this.chip('左到右', this.settings.flow === ReaderFlow.LTR, () => {
              this.update((s: ReaderSettings) => {
                s.flow = ReaderFlow.LTR;
              });
            })
            this.chip('右到左', this.settings.flow === ReaderFlow.RTL, () => {
              this.update((s: ReaderSettings) => {
                s.flow = ReaderFlow.RTL;
              });
            })
            this.chip('竖排整页', this.settings.flow === ReaderFlow.VERTICAL, () => {
              this.update((s: ReaderSettings) => {
                s.flow = ReaderFlow.VERTICAL;
              });
            })
            this.chip('连续Webtoon', this.settings.flow === ReaderFlow.WEBTOON, () => {
              this.update((s: ReaderSettings) => {
                s.flow = ReaderFlow.WEBTOON;
              });
            })
          }
          .width('100%')

          this.titleRow('翻页动画')
          Flex({ wrap: FlexWrap.Wrap }) {
            this.chip('无', this.settings.animation === ReaderAnimation.NONE, () => {
              this.update((s: ReaderSettings) => {
                s.animation = ReaderAnimation.NONE;
              });
            }, this.settings.flow !== ReaderFlow.WEBTOON)
            this.chip('滑动', this.settings.animation === ReaderAnimation.SLIDE, () => {
              this.update((s: ReaderSettings) => {
                s.animation = ReaderAnimation.SLIDE;
              });
            }, this.settings.flow !== ReaderFlow.WEBTOON)
            this.chip('封面叠放', this.settings.animation === ReaderAnimation.COVER, () => {
              this.update((s: ReaderSettings) => {
                s.animation = ReaderAnimation.COVER;
              });
            }, this.settings.flow !== ReaderFlow.WEBTOON)
            this.chip('卷曲', this.settings.animation === ReaderAnimation.CURL, () => {
              this.update((s: ReaderSettings) => {
                s.animation = ReaderAnimation.CURL;
              });
            }, this.settings.flow !== ReaderFlow.WEBTOON)
          }
          .width('100%')
          if (this.settings.flow === ReaderFlow.WEBTOON) {
            Text('连续滑动模式下翻页动画不生效')
              .fontSize(10)
              .fontColor(ThemeTokens.TEXT_HINT)
              .width('100%')
          }

          this.titleRow('背景（6 档）')
          Row({ space: 12 }) {
            ForEach(ReaderBg.keys(), (key: string) => {
              this.bgSwatch(key)
            }, (key: string) => key)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)

          this.sectionLayout()
          this.sectionFilter()

          this.titleRow('自动翻页')
          this.sliderRow('间隔', this.settings.autoInterval, 3, 60, 1, ' 秒', (v: number) => {
            this.update((s: ReaderSettings) => {
              s.autoInterval = v;
            });
          })
          Text('自动翻页开关在阅读菜单里（菜单 → 自动翻页）')
            .fontSize(10)
            .fontColor(ThemeTokens.TEXT_HINT)
            .width('100%')

          this.sectionSelfTest()
          Row().height(12)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING, top: 12, bottom: 12 })
    .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
    .borderRadius({ topLeft: ThemeTokens.RADIUS_CARD, topRight: ThemeTokens.RADIUS_CARD })
  }
}
