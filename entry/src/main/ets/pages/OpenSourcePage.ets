import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { Routes } from '../common/Routes';

/** 开源致谢条目。 */
class OssItem {
  name: string;
  license: string;
  desc: string;
  url: string;
  icon: Resource;

  constructor(name: string, license: string, desc: string, url: string, icon: Resource) {
    this.name = name;
    this.license = license;
    this.desc = desc;
    this.url = url;
    this.icon = icon;
  }
}

/** 页面内卡片容器。 */
@Component
struct OssCard {
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
 * 开源致谢页（S110）：上游 StarFlow（星译，LGPL-3.0）、llama.cpp（MIT）、
 * HarmonyOS Core Vision Kit 与预置模型来源说明。
 * 所有链接以可长按复制的文本展示，不内置浏览器跳转。
 */
@Component
export struct OpenSourcePage {
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  private navStack: NavPathStack = AppEnv.getInstance().navStack;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private items: Array<OssItem> = [
    new OssItem('StarFlow（星译 · Android 上游）', 'LGPL-3.0',
      '信息架构、交互行为与视觉概念参照上游开源项目；本应用在 HarmonyOS 上以 ArkTS 独立重写，未直接复制上游代码文本。上游作者与贡献者致谢。',
      'https://github.com/xujunjiex/StarFlow', $r('app.media.ic_github')),
    new OssItem('llama.cpp', 'MIT',
      '端侧 GGUF 推理引擎，以 C++ 源码静态集成并通过 NAPI 暴露给 ArkTS，用于本地 llama 翻译（Hy-MT2）。',
      'https://github.com/ggml-org/llama.cpp', $r('app.media.ic_github')),
    new OssItem('HarmonyOS Core Vision Kit', '系统能力（非开源）',
      '提供系统级文字识别 textRecognition，本应用的 OCR 全部在本机完成，不依赖第三方云服务。',
      'HarmonyOS SDK · @kit.CoreVisionKit', $r('app.media.ic_ocr')),
    new OssItem('HarmonyOS ArkTS / ArkUI SDK', '系统框架',
      '应用基于 ArkTS + ArkUI 声明式开发，使用 API 26 的 uiMaterial 沉浸光感材质、RDB、Preferences 与 Asset Store Kit。',
      'HarmonyOS SDK · API 26', $r('app.media.ic_settings')),
    new OssItem('Hy-MT2 1.8B GGUF（预置本地模型）', '模型许可归腾讯混元',
      'Q4_K_M 量化档由 HuggingFace 分发，1.25bit 档由 ModelScope 分发；模型版权与使用条款遵循模型发布方说明。',
      'huggingface.co/tencent/Hy-MT2-1.8B-GGUF', $r('app.media.ic_model'))
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
  ossRow(item: OssItem) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Image(item.icon)
          .width(16)
          .height(16)
          .fillColor(ThemeTokens.PRIMARY)
        Text(item.name)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(item.license)
          .fontSize(10)
          .fontColor(ThemeTokens.PRIMARY_SOFT)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(item.desc)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .width('100%')
        .lineHeight(19)

      Text(item.url)
        .fontSize(10)
        .fontColor(ThemeTokens.PRIMARY)
        .width('100%')
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Scroll() {
        Row() {
          Column({ space: 12 }) {
            Column({ space: 3 }) {
              Text('开源致谢')
                .fontSize(ThemeTokens.FONT_TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
              Text('墨译站在这些开源项目与系统能力的肩膀上')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            OssCard() {
              Column({ space: 4 }) {
                Text('许可总览')
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeTokens.TEXT_PRIMARY)
                Text('本应用参照上游 StarFlow（星译，LGPL-3.0）的功能与视觉设计，在 HarmonyOS 平台以 ArkTS 独立实现；应用本身不分发上游二进制。第三方组件与模型分别遵循其各自许可，链接可长按复制。')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_SECONDARY)
                  .lineHeight(19)
              }
              .alignItems(HorizontalAlign.Start)
            }

            Column() {
              ForEach(this.items, (item: OssItem, index: number) => {
                if (index > 0) {
                  Divider()
                    .color(ThemeTokens.DIVIDER)
                    .strokeWidth(0.5)
                }
                this.ossRow(item)
              }, (item: OssItem) => item.name)
            }
            .width('100%')
            .padding({ left: ThemeTokens.CARD_PADDING, right: ThemeTokens.CARD_PADDING, top: 2, bottom: 2 })
            .borderRadius(ThemeTokens.RADIUS_CARD)
            .backgroundColor(ThemeTokens.CARD_BG)

            Row({ space: 10 }) {
              Button('查看许可详情')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                .backgroundColor(ThemeTokens.PRIMARY)
                .borderRadius(ThemeTokens.RADIUS_PILL)
                .height(36)
                .layoutWeight(1)
                .onClick(() => {
                  this.navStack.pushPathByName(Routes.ABOUT, '');
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

            Text('说明：上游 StarFlow（星译）为 Android 开源项目；本应用为 HarmonyOS 迁移实现，行为与视觉参照上游，代码为独立编写。')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_TERTIARY)
              .width('100%')
              .lineHeight(18)
              .margin({ top: 2, bottom: 12 })
          }
          .width(this.isWide() ? 760 : '100%')
          .padding({
            left: ThemeTokens.PAGE_PADDING,
            right: ThemeTokens.PAGE_PADDING,
            top: 12,
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
    .title('开源致谢', {
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