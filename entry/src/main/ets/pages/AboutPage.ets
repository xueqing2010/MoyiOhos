import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { BuildInfo } from '../common/BuildInfo';
import { Routes } from '../common/Routes';

/** 信息行。 */
class InfoRow {
  label: string;
  value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

/** 卡片容器。 */
@Component
struct AboutCard {
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * 关于页（S110）：品牌、版本、构建模块清单（1 HAP + 6 HAR）、技术栈、
 * 许可与来源、快捷入口（开源致谢 / 常见问题 / 重新查看引导）。
 */
@Component
export struct AboutPage {
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  private navStack: NavPathStack = AppEnv.getInstance().navStack;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private rows: Array<InfoRow> = [
    new InfoRow('应用版本', `v${BuildInfo.APP_VERSION}`),
    new InfoRow('Bundle 名称', BuildInfo.BUNDLE_NAME),
    new InfoRow('API Level', `HarmonyOS ${BuildInfo.HARMONY_API_LEVEL}`),
    new InfoRow('构建日期', BuildInfo.BUILD_DATE),
    new InfoRow('设备形态', 'phone · tablet · 2in1')
  ];

  aboutToAppear(): void {
    this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
      this.sizeClass = c;
    });
  }

  aboutToDisappear(): void {
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  private isWide(): boolean {
    return this.sizeClass === WindowSizeClass.LG;
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(ThemeTokens.FONT_BODY)
      .fontWeight(FontWeight.Medium)
      .fontColor(ThemeTokens.TEXT_PRIMARY)
      .width('100%')
      .margin({ top: 6, bottom: 2 })
  }

  @Builder
  infoLine(row: InfoRow) {
    Row() {
      Text(row.label)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
      Blank()
      Text(row.value)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  moduleChip(name: string, hap: boolean) {
    Text(name)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(hap ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.PRIMARY_SOFT)
      .padding({ left: 9, right: 9, top: 5, bottom: 5 })
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(hap ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_VARIANT)
      .margin({ right: 6, bottom: 6 })
  }

  @Builder
  hero() {
    Column({ space: 8 }) {
      Image($r('app.media.logo_starflow'))
        .width(72)
        .height(72)
        .borderRadius(20)
      Text('墨译 Moyi')
        .fontSize(ThemeTokens.FONT_DISPLAY)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      Text('漫画 · 小说 · 文本翻译 · 本地模型')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
      Row({ space: 8 }) {
        Text(`v${BuildInfo.APP_VERSION}`)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.PRIMARY)
          .padding({ left: 9, right: 9, top: 3, bottom: 3 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        Text('HarmonyOS · 蓝白阅读')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .padding({ left: 9, right: 9, top: 3, bottom: 3 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 10 })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    NavDestination() {
      Scroll() {
        Row() {
          Column({ space: 12 }) {
            this.hero()

            this.sectionTitle('版本与构建')
            AboutCard() {
              ForEach(this.rows, (row: InfoRow, index: number) => {
                if (index > 0) {
                  Divider()
                    .color(ThemeTokens.DIVIDER)
                    .strokeWidth(0.5)
                }
                this.infoLine(row)
              }, (row: InfoRow) => row.label)
            }

            this.sectionTitle(`构建模块（1 HAP + ${BuildInfo.MODULES.length - 1} HAR）`)
            AboutCard() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(BuildInfo.MODULES, (m: string) => {
                  this.moduleChip(m, m.indexOf('(HAP)') >= 0)
                }, (m: string) => m)
              }
              .width('100%')
              Text(`共 ${BuildInfo.MODULE_COUNT} 个模块；entry 为 HAP，其余为可复用 HAR。构建产物由 devecocli（DevEco 26 / API 26）生成。`)
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
                .width('100%')
                .lineHeight(17)
                .margin({ top: 2 })
            }

            this.sectionTitle('技术栈')
            AboutCard() {
              Text('ArkTS + ArkUI 声明式开发（V1 状态管理）· 关系型数据库 RDB · Preferences 设置持久化 · Asset Store Kit 密钥存储 · uiMaterial 沉浸光感（API 26）· Core Vision Kit 文字识别 · llama.cpp NAPI 端侧推理。')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_SECONDARY)
                .width('100%')
                .lineHeight(19)
            }

            this.sectionTitle('许可与来源')
            AboutCard() {
              Text('本应用参照上游开源项目 StarFlow（星译，LGPL-3.0）的信息架构与行为，在 HarmonyOS 上以 ArkTS 独立重写实现，未直接复制上游代码文本。')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_SECONDARY)
                .width('100%')
                .lineHeight(19)
              Divider()
                .color(ThemeTokens.DIVIDER)
                .strokeWidth(0.5)
                .margin({ top: 8, bottom: 8 })
              Text('llama.cpp（MIT）用于本地 GGUF 推理；OCR 能力来自 HarmonyOS Core Vision Kit；本地模型 Hy-MT2 的版权与许可归腾讯混元。完整列表见「开源致谢」。')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_SECONDARY)
                .width('100%')
                .lineHeight(19)
              Text('数据默认保存在本机；应用不含广告、内购与统计 SDK，也无账号体系。')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
                .width('100%')
                .lineHeight(19)
                .margin({ top: 8 })
            }

            Row({ space: 10 }) {
              Button('开源致谢')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                .backgroundColor(ThemeTokens.PRIMARY)
                .borderRadius(ThemeTokens.RADIUS_PILL)
                .height(36)
                .layoutWeight(1)
                .onClick(() => {
                  this.navStack.pushPathByName(Routes.OPEN_SOURCE, '');
                })
              Button('常见问题')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_SECONDARY)
                .backgroundColor(ThemeTokens.SURFACE_VARIANT)
                .borderRadius(ThemeTokens.RADIUS_PILL)
                .height(36)
                .layoutWeight(1)
                .onClick(() => {
                  this.navStack.pushPathByName(Routes.FAQ, '');
                })
            }
            .width('100%')

            Button('重新查看引导')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_SECONDARY)
              .backgroundColor(ThemeTokens.SURFACE_VARIANT)
              .borderRadius(ThemeTokens.RADIUS_PILL)
              .height(36)
              .width('100%')
              .onClick(() => {
                this.navStack.pushPathByName(Routes.ONBOARDING, '');
              })

            Text('MoyiOhos · 阶段2 · 蓝白阅读')
              .fontSize(10)
              .fontColor(ThemeTokens.TEXT_TERTIARY)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 6, bottom: 12 })
          }
          .width(this.isWide() ? 760 : '100%')
          .padding({
            left: ThemeTokens.PAGE_PADDING,
            right: ThemeTokens.PAGE_PADDING,
            top: 4,
            bottom: 24
          })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Top)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
    .title('关于', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true,
        interactive: true,
        lightEffect: {}
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
  }
}