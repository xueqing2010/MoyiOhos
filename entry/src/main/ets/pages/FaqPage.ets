import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';

/** FAQ 条目。 */
class FaqItem {
  category: string;
  question: string;
  answer: string;

  constructor(category: string, question: string, answer: string) {
    this.category = category;
    this.question = question;
    this.answer = answer;
  }
}

/** @Builder 按引用传递参数（展开态变化可刷新 UI）。 */
interface FaqRowParams {
  item: FaqItem;
  index: number;
  expanded: boolean;
}

/**
 * 常见问题页（S110）：按主题分组的可展开问答，覆盖引擎、模型、OCR、
 * 导入格式、阅读设置、隐私与许可。内容为阶段2实际能力说明。
 */
@Component
export struct FaqPage {
  @State expanded: number = -1;
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private items: Array<FaqItem> = [
    new FaqItem('翻译引擎', '翻译引擎怎么选？',
      '必应免 Key、在线可用，适合快速翻译；OpenAI 兼容质量最好，需在「我的 → API 配置」填写 Base URL、模型与 Key（支持 DeepSeek / 通义千问 / 豆包 / 智谱预设）；本地 llama 完全离线，需先在「模型管理」下载 Hy-MT2 GGUF 模型，首次加载较慢。'),
    new FaqItem('翻译引擎', '没有网络还能用吗？',
      '必应与 OpenAI 兼容引擎需要网络；本地 llama 模型下载完成后可离线翻译。OCR 使用系统 Core Vision Kit，本机推理，不需要网络。'),
    new FaqItem('翻译引擎', '提示词会影响翻译质量吗？',
      '会。「翻译设置 → 提示词编辑」可分别覆盖漫画/游戏/小说/文本模板，留空则回退应用内置模板；模板中的 %TARGET_LANG% / %SOURCE_LANG% 占位符仍会被替换。'),
    new FaqItem('模型管理', '模型下载慢或失败怎么办？',
      'GGUF 模型通常数百 MB 到 1 GB 以上，建议 Wi-Fi 下载。下载支持断点续传与暂停/继续；开始前会检查剩余存储空间，空间不足会直接提示。MD5 校验失败可点「重新下载」。'),
    new FaqItem('模型管理', '为什么 1.25bit 模型标注「暂不支持」？',
      '1.25bit（STQ1_0）依赖上游私有量化补丁，当前版本缺少对应加载实现，因此只展示不提供下载。请使用 Q4_K_M 量化档。'),
    new FaqItem('模型管理', '可以导入自己的 GGUF 吗？',
      '可以。「模型管理 → 导入本地 GGUF」选择文件后按原路径登记，不复制文件；也可通过「自定义 URL」添加任意 GGUF 下载地址。'),
    new FaqItem('OCR', 'OCR 能力探测失败是什么原因？',
      '部分模拟器未内置系统文字识别服务，探测会失败，属预期现象；真机可用。识别语言（日/英/中/韩）作为提示保存，系统引擎本身支持多语言。'),
    new FaqItem('OCR', 'OCR 会上传图片吗？',
      '不会。文字识别在设备本机完成；仅翻译阶段会把识别出的文本发送给你选择的翻译引擎。'),
    new FaqItem('导入与格式', '支持哪些导入格式？',
      '漫画：zip / cbz、图片目录、相册多选；小说：TXT、EPUB、ZIP-HTML（打包的 HTML 章节）。导入向导可改名、选封面、查看页序。'),
    new FaqItem('阅读与显示', '竖排译文逐字错位怎么办？',
      '阶段2已修复竖排逐字定位（corerender LayoutEngine）。可在「阅读设置」调整竖排方向（右→左/左→右）、文字方向（横排/竖排）与白块合并，修改后返回阅读器即生效。'),
    new FaqItem('阅读与显示', '设置改了为什么没生效？',
      '设置与阅读器读写同一份 preferences（starflow_reader），返回阅读器或重新打开页面后生效；阅读器内的渲染设置与本页会互相同步。'),
    new FaqItem('阅读与显示', '主题可以切浅色吗？',
      '当前版本运行时固定紫夜深色（Purple Nocturne），「主题外观」中的 OLED/跟随系统选项仅保存偏好，运行时切换将在后续版本提供。阅读背景可在「阅读设置」内独立切换六档。'),
    new FaqItem('隐私与安全', 'API Key 存在哪里？',
      '优先写入 HarmonyOS Asset Store（设备首次解锁后可用），界面只显示掩码、不回显明文；Asset 不可用时会降级 preferences 并标注低安全模式。'),
    new FaqItem('隐私与安全', '应用会上传我的数据吗？',
      '不会上传漫画图片、阅读记录或账号数据（应用无账号体系、无统计 SDK）。翻译时仅向所选引擎发送当前文本，本地 llama 则完全离线。'),
    new FaqItem('其他', '如何重新查看启动引导？',
      '「我的 → 关于 → 重新查看引导」，或直接打开「我的」页底部的「重新查看引导」入口。'),
    new FaqItem('其他', '开源许可是什么？',
      '上游 StarFlow 为 LGPL-3.0；本地推理使用 llama.cpp（MIT）；OCR 使用 HarmonyOS Core Vision Kit 系统能力。详见「开源致谢」。')
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

  private toggle(index: number): void {
    this.expanded = this.expanded === index ? -1 : index;
  }

  @Builder
  faqRow(pp: FaqRowParams) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(pp.item.category)
          .fontSize(10)
          .fontColor(ThemeTokens.PRIMARY)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        Text(pp.item.question)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Image($r('app.media.ic_arrow_right'))
          .width(13)
          .height(13)
          .fillColor(ThemeTokens.TEXT_TERTIARY)
          .rotate({ angle: pp.expanded ? 90 : 0 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (pp.expanded) {
        Text(pp.item.answer)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .width('100%')
          .lineHeight(19)
          .padding({ top: 4 })
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.toggle(pp.index);
    })
  }

  build() {
    NavDestination() {
      Scroll() {
        Row() {
          Column({ space: 12 }) {
            Column({ space: 3 }) {
              Text('常见问题')
                .fontSize(ThemeTokens.FONT_TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
              Text(`共 ${this.items.length} 条 · 点击展开答案`)
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column() {
              ForEach(this.items, (item: FaqItem, index: number) => {
                if (index > 0) {
                  Divider()
                    .color(ThemeTokens.DIVIDER)
                    .strokeWidth(0.5)
                }
                this.faqRow({ item: item, index: index, expanded: this.expanded === index })
              }, (item: FaqItem) => item.question)
            }
            .width('100%')
            .padding({ left: ThemeTokens.CARD_PADDING, right: ThemeTokens.CARD_PADDING, top: 2, bottom: 2 })
            .borderRadius(ThemeTokens.RADIUS_CARD)
            .backgroundColor(ThemeTokens.CARD_BG)

            Text('没有找到答案？可在「尖刀验证工作台」查看各技术点的最近验证结果，或到上游开源项目提交 issue。')
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
    .title('常见问题', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
  }
}