import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { SettingsRepository } from '../data/SettingsRepository';
import { Artwork } from '../components/Artwork';

/** 引导页数据。 */
class OnboardingSlide {
  title: string;
  subtitle: string;
  bullets: Array<string>;
  /** 彩色引导插画（Artwork.ONBOARDING_*，不要 fillColor 染色）。 */
  art: Resource;
  secondaryIcons: Array<Resource>;

  constructor(title: string, subtitle: string, bullets: Array<string>, art: Resource,
    secondaryIcons: Array<Resource>) {
    this.title = title;
    this.subtitle = subtitle;
    this.bullets = bullets;
    this.art = art;
    this.secondaryIcons = secondaryIcons;
  }
}

/**
 * 启动引导页（S110，3 页 Swipe）：3 页 Swipe 引导（欢迎 / 导入与格式 / 引擎与模型）。
 * 跳过与「开始使用」都会把 onboarding_done 持久化为 true；
 * Lead 在 Index 首启读取 SettingsRepository.isOnboardingDone() 决定是否 push。
 */
@Component
export struct OnboardingPage {
  @State currentIndex: number = 0;
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  @State finishing: boolean = false;
  private navStack: NavPathStack = AppEnv.getInstance().navStack;
  private swiperController: SwiperController = new SwiperController();
  private stopBreakpoint: (() => void) | undefined = undefined;
  private slides: Array<OnboardingSlide> = [
    new OnboardingSlide('欢迎使用星译', '漫画 · 小说 · 文本翻译，一套紫夜阅读体验',
      [
        '漫画与小说书架：本地文件导入后直接阅读',
        '页面 OCR + 译文回填：气泡级排版与竖排支持',
        '文本 / 对话翻译：必应、OpenAI 兼容与本地 llama'
      ],
      Artwork.ONBOARDING_HERO,
      [$r('app.media.ic_tab_shelf'), $r('app.media.ic_tab_translate'), $r('app.media.ic_tab_history')]),
    new OnboardingSlide('导入你的内容', '漫画跑 zip / cbz，小说支持 TXT / EPUB / ZIP-HTML',
      [
        '漫画：ZIP/CBZ、图片目录、相册多选三种通道',
        '小说：TXT 自动分章、EPUB 目录解析、ZIP-HTML 章节',
        '导入向导可改名、选封面、检查页序后再入库'
      ],
      Artwork.ONBOARDING_IMPORT,
      [$r('app.media.ic_import_zip'), $r('app.media.ic_import_folder'), $r('app.media.ic_import_novel')]),
    new OnboardingSlide('选择翻译引擎', '在线免 Key，或下载本地模型离线翻译',
      [
        '必应：免 Key 在线翻译，开箱即用',
        'OpenAI 兼容：DeepSeek / 通义千问 / 豆包 / 智谱，质量更高',
        '本地 llama：下载 Hy-MT2 GGUF 后完全离线推理'
      ],
      Artwork.ONBOARDING_ENGINE,
      [$r('app.media.ic_tab_translate'), $r('app.media.ic_reader_text'), $r('app.media.ic_settings')])
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

  private isLast(): boolean {
    return this.currentIndex === this.slides.length - 1;
  }

  private next(): void {
    if (this.isLast()) {
      this.finish();
      return;
    }
    this.swiperController.showNext();
  }

  private async finish(): Promise<void> {
    if (this.finishing) {
      return;
    }
    this.finishing = true;
    try {
      await SettingsRepository.setOnboardingDone();
    } catch (e) {
      // 偏好写入失败不阻断进入应用
    }
    this.finishing = false;
    this.navStack.pop();
  }

  @Builder
  iconCluster(slide: OnboardingSlide) {
    Column({ space: 12 }) {
      Image(slide.art)
        .width(300)
        .height(168)
        .objectFit(ImageFit.Contain)
        .draggable(false)
      Row({ space: 14 }) {
        ForEach(slide.secondaryIcons, (icon: Resource) => {
          Column() {
            Image(icon)
              .width(22)
              .height(22)
              .fillColor(ThemeTokens.PRIMARY_SOFT)
          }
          .width(46)
          .height(46)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .justifyContent(FlexAlign.Center)
        }, (icon: Resource, index: number) => `${index}-${this.currentIndex}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  slideContent(slide: OnboardingSlide) {
    Column({ space: 12 }) {
      this.iconCluster(slide)

      Text(slide.title)
        .fontSize(ThemeTokens.FONT_DISPLAY)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .textAlign(TextAlign.Center)
      Text(slide.subtitle)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .padding({ left: 8, right: 8 })

      Column({ space: 10 }) {
        ForEach(slide.bullets, (line: string) => {
          Row({ space: 10 }) {
            Image($r('app.media.ic_check'))
              .width(15)
              .height(15)
              .fillColor(ThemeTokens.PRIMARY)
              .margin({ top: 2 })
            Text(line)
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_SECONDARY)
              .lineHeight(20)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (line: string) => line)
      }
      .width('100%')
      .padding(ThemeTokens.CARD_PADDING + 2)
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor(ThemeTokens.CARD_BG)
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  dots() {
    Row({ space: 7 }) {
      ForEach(this.slides, (slide: OnboardingSlide, index: number) => {
        Column()
          .width(this.currentIndex === index ? 20 : 7)
          .height(7)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(this.currentIndex === index ? ThemeTokens.PRIMARY : ThemeTokens.DIVIDER)
      }, (slide: OnboardingSlide, index: number) => `dot-${index}`)
    }
    .justifyContent(FlexAlign.Center)
  }

  build() {
    NavDestination() {
      Row() {
        Column() {
        Row() {
          Text('跳过')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_HINT)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .onClick(() => {
              this.finish();
            })
          Blank()
          Text(`${this.currentIndex + 1} / ${this.slides.length}`)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_TERTIARY)
        }
        .width('100%')
        .padding({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING, top: 6 })

        Swiper(this.swiperController) {
          ForEach(this.slides, (slide: OnboardingSlide) => {
            this.slideContent(slide)
          }, (slide: OnboardingSlide) => slide.title)
        }
        .index(this.currentIndex)
        .loop(false)
        .indicator(false)
        .duration(320)
        .curve(Curve.EaseOut)
        .layoutWeight(1)
        .width('100%')
        .onChange((index: number) => {
          this.currentIndex = index;
        })

        Column({ space: 14 }) {
          this.dots()
          Row({ space: 12 }) {
            if (!this.isLast()) {
              Button('下一步')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                .backgroundColor(ThemeTokens.PRIMARY)
                .borderRadius(ThemeTokens.RADIUS_PILL)
                .height(44)
                .layoutWeight(1)
                .onClick(() => {
                  this.next();
                })
            } else {
              Button('开始使用')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                .backgroundColor(ThemeTokens.PRIMARY)
                .borderRadius(ThemeTokens.RADIUS_PILL)
                .height(44)
                .layoutWeight(1)
                .enabled(!this.finishing)
                .onClick(() => {
                  this.finish();
                })
            }
          }
          .width('100%')
        }
        .width('100%')
        .padding({
          left: ThemeTokens.PAGE_PADDING + 8,
          right: ThemeTokens.PAGE_PADDING + 8,
          bottom: 24
        })
        .alignItems(HorizontalAlign.Center)
        }
        .width(this.isWide() ? 620 : '100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .title('欢迎', {
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