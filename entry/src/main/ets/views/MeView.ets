import { ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { Routes } from '../common/Routes';
import { BuildInfo } from '../common/BuildInfo';

/** 我的页入口行（图标 + 标题 + 说明 + 目标路由）。 */
interface MeEntry {
  title: string;
  desc: string;
  icon: Resource;
  route: string;
}

/** 我的页分组卡片。 */
interface MeGroup {
  title: string;
  icon: Resource;
  rows: Array<MeEntry>;
}

function makeEntry(title: string, desc: string, icon: Resource, route: string): MeEntry {
  const e: MeEntry = { title: title, desc: desc, icon: icon, route: route };
  return e;
}

function makeGroup(title: string, icon: Resource, rows: Array<MeEntry>): MeGroup {
  const g: MeGroup = { title: title, icon: icon, rows: rows };
  return g;
}

/**
 * 「我的」Tab（stage-2 / S110）：品牌区 + 设置全家桶分组卡片。
 * 入口按上游 me/* 信息架构组织：设置总览、阅读与显示、翻译与引擎、OCR、
 * 模型管理、尖刀验证工作台、常见问题、开源致谢、关于（含重新查看引导）。
 * LG 宽度双列卡片，SM/MD 单列；全部入口 push 全局 NavPathStack。
 */
@Component
export struct MeView {
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  private navStack: NavPathStack = AppEnv.getInstance().navStack;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private groups: Array<MeGroup> = [];

  aboutToAppear(): void {
    this.groups = MeView.buildGroups();
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

  private static buildGroups(): Array<MeGroup> {
    const groups: Array<MeGroup> = [];
    groups.push(makeGroup('设置总览', $r('app.media.ic_settings'), [
      makeEntry('全部设置', '阅读、翻译、OCR、主题与 API 配置', $r('app.media.ic_settings'), Routes.SETTINGS)
    ]));
    groups.push(makeGroup('阅读与显示', $r('app.media.ic_reading'), [
      makeEntry('阅读设置', '背景六档、阅读模式、翻页动画、字号与行距', $r('app.media.ic_reading'),
        Routes.SETTINGS_READING),
      makeEntry('主题外观', '蓝白配色 / 蓝黑夜间', $r('app.media.ic_theme'),
        Routes.SETTINGS_THEME)
    ]));
    groups.push(makeGroup('翻译与引擎', $r('app.media.ic_translate'), [
      makeEntry('翻译设置', '默认引擎、目标语言、上下文轮次、提示词与温度', $r('app.media.ic_translate'),
        Routes.SETTINGS_TRANSLATE),
      makeEntry('API 配置', '必应 / OpenAI 兼容 / 本地 llama 配置与连通性测试', $r('app.media.ic_api'),
        Routes.API_CONFIG)
    ]));
    groups.push(makeGroup('OCR', $r('app.media.ic_ocr'), [
      makeEntry('OCR 设置', '识别语言（日/英/中/韩）、引擎档位与能力探测', $r('app.media.ic_ocr'),
        Routes.SETTINGS_OCR)
    ]));
    groups.push(makeGroup('模型管理', $r('app.media.ic_model'), [
      makeEntry('本地模型', 'GGUF 下载、进度/速度、暂停继续、导入与存储统计', $r('app.media.ic_model'),
        Routes.MODEL_MANAGER)
    ]));
    groups.push(makeGroup('常见问题', $r('app.media.ic_faq'), [
      makeEntry('常见问题', '引擎、模型、OCR、导入与隐私的疑问排查', $r('app.media.ic_faq'), Routes.FAQ)
    ]));
    groups.push(makeGroup('开源致谢', $r('app.media.ic_github'), [
      makeEntry('开源致谢', '上游 StarFlow（星译，LGPL-3.0）、llama.cpp 与系统能力', $r('app.media.ic_github'),
        Routes.OPEN_SOURCE)
    ]));
    groups.push(makeGroup('关于', $r('app.media.ic_about'), [
      makeEntry('关于墨译', '版本、构建模块清单与许可说明', $r('app.media.ic_about'), Routes.ABOUT),
      makeEntry('重新查看引导', '3 页快速上手：导入、格式与引擎', $r('app.media.ic_star'), Routes.ONBOARDING)
    ]));
    return groups;
  }

  /** 按奇偶拆成两列（LG 双列；SM/MD 只用第一列）。 */
  private columnGroups(second: boolean): Array<MeGroup> {
    const out: Array<MeGroup> = [];
    for (let i = 0; i < this.groups.length; i++) {
      if (i % 2 === (second ? 1 : 0)) {
        out.push(this.groups[i]);
      }
    }
    return out;
  }

  private isWide(): boolean {
    return this.sizeClass === WindowSizeClass.LG;
  }

  @Builder
  brandHeader() {
    Row({ space: 14 }) {
      Image($r('app.media.logo_starflow'))
        .width(58)
        .height(58)
        .borderRadius(16)
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text('墨译')
            .fontSize(ThemeTokens.FONT_DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
          Text(ThemeTokens.isLight() ? '蓝白' : '蓝黑夜间')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.PRIMARY)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        }
        .alignItems(VerticalAlign.Center)
        Text('漫画 · 小说 · 文本翻译 · 本地模型')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
        Text(`v${BuildInfo.APP_VERSION} · HarmonyOS ${BuildInfo.HARMONY_API_LEVEL}`)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING + 2)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  entryRow(entry: MeEntry) {
    Row({ space: 12 }) {
      Column() {
        Image(entry.icon)
          .width(20)
          .height(20)
          .fillColor(ThemeTokens.PRIMARY_SOFT)
      }
      .width(34)
      .height(34)
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(entry.title)
          .fontSize(ThemeTokens.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text(entry.desc)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_arrow_right'))
        .width(14)
        .height(14)
        .fillColor(ThemeTokens.TEXT_TERTIARY)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .onClick(() => {
      this.navStack.pushPathByName(entry.route, '');
    })
  }

  @Builder
  groupCard(group: MeGroup) {
    Column() {
      Row({ space: 8 }) {
        Image(group.icon)
          .width(16)
          .height(16)
          .fillColor(ThemeTokens.PRIMARY)
        Text(group.title)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
      }
      .width('100%')
      .margin({ bottom: 2 })

      ForEach(group.rows, (entry: MeEntry, index: number) => {
        if (index > 0) {
          Divider()
            .color(ThemeTokens.DIVIDER)
            .strokeWidth(0.5)
        }
        this.entryRow(entry)
      }, (entry: MeEntry) => `${group.title}-${entry.title}`)
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          this.brandHeader()

          if (this.isWide()) {
            Row({ space: 12 }) {
              Column({ space: 12 }) {
                ForEach(this.columnGroups(false), (group: MeGroup) => {
                  this.groupCard(group)
                }, (group: MeGroup) => `left-${group.title}`)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Column({ space: 12 }) {
                ForEach(this.columnGroups(true), (group: MeGroup) => {
                  this.groupCard(group)
                }, (group: MeGroup) => `right-${group.title}`)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            ForEach(this.groups, (group: MeGroup) => {
              this.groupCard(group)
            }, (group: MeGroup) => group.title)
          }

          Text('数据默认保存在本机 · 模型不上传 · 在线翻译仅发送当前文本')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_TERTIARY)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 4, bottom: 8 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: ThemeTokens.PAGE_PADDING,
          right: ThemeTokens.PAGE_PADDING,
          top: 18,
          bottom: 100
        })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.SURFACE)
  }
}