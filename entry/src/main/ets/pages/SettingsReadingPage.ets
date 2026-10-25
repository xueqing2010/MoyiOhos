import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';
import { ReaderSettings, SettingsKeys, SettingsRepository } from '../data/SettingsRepository';

/** 阅读背景档位（6 档，与 reader-dev 契约一致）。 */
class BgOption {
  id: string;
  label: string;
  color: string;

  constructor(id: string, label: string, color: string) {
    this.id = id;
    this.label = label;
    this.color = color;
  }
}

/** 单选选项（阅读模式 / 翻页动画）。 */
class ModeOption {
  id: string;
  label: string;

  constructor(id: string, label: string) {
    this.id = id;
    this.label = label;
  }
}

/** @Builder 按引用传递参数（状态改变可刷新 UI）。 */
interface ChipParams {
  label: string;
  active: boolean;
  onTap: () => void;
}

interface SliderParams {
  label: string;
  valueText: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (v: number) => void;
}

interface SwitchParams {
  label: string;
  desc: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}

/** 设置卡片容器（trailing closure 内容）。 */
@Component
struct ReadSettingCard {
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
 * 阅读设置页（S105/S106 设置侧）：背景 6 档预览、阅读模式、翻页动画、
 * 字号/行距/边距、自动翻页间隔、竖排方向、白块合并。
 * 所有修改即时写入 starflow_reader（SettingsRepository 路由），阅读器返回即生效。
 */
@Component
export struct SettingsReadingPage {
  @State bg: string = 'nocturne';
  @State mode: string = 'raw';
  @State pageAnim: string = 'slide';
  @State orientation: number = 2;
  @State vDirection: number = 0;
  @State fontSizeMode: number = 0;
  @State fontSize: number = 16;
  @State lineHeight: number = 130;
  @State pageMargin: number = 8;
  @State autoInterval: number = 5;
  @State whiteMerge: boolean = true;
  @State novelLineHeight: number = 30;
  @State novelMargin: number = 18;
  @State novelDisplayMode: number = 1;
  @State hint: string = '';
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private backgrounds: Array<BgOption> = [
    new BgOption('black', '黑', ThemeTokens.READER_BG_BLACK),
    new BgOption('nocturne', '紫夜', ThemeTokens.READER_BG_NOCTURNE),
    new BgOption('plum', '紫梅', ThemeTokens.READER_BG_PLUM),
    new BgOption('deep', '深紫', ThemeTokens.READER_BG_DEEP),
    new BgOption('paper', '纸色', ThemeTokens.READER_BG_PAPER),
    new BgOption('white', '白', ThemeTokens.READER_BG_WHITE)
  ];
  private modes: Array<ModeOption> = [
    new ModeOption('trans', '仅译文'),
    new ModeOption('orig', '仅原文'),
    new ModeOption('raw', '纯原图')
  ];
  private anims: Array<ModeOption> = [
    new ModeOption('none', '无'),
    new ModeOption('slide', '滑动'),
    new ModeOption('cover', '封面叠放'),
    new ModeOption('curl', '卷曲精简')
  ];

  aboutToAppear(): void {
    this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
      this.sizeClass = c;
    });
    this.load();
  }

  aboutToDisappear(): void {
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  private async load(): Promise<void> {
    const s: ReaderSettings = await SettingsRepository.loadReaderSettings();
    this.bg = s.bg;
    this.mode = s.mode;
    this.pageAnim = s.pageAnim;
    this.orientation = s.orientation;
    this.vDirection = s.direction;
    this.fontSizeMode = s.fontSizeMode;
    this.fontSize = s.fontSize;
    this.lineHeight = s.lineHeight;
    this.pageMargin = s.margin;
    this.autoInterval = s.autoInterval;
    this.whiteMerge = s.whiteMerge;
    this.novelLineHeight = await SettingsRepository.getNumber(SettingsKeys.NOVEL_LINE_HEIGHT, 30);
    this.novelMargin = await SettingsRepository.getNumber(SettingsKeys.NOVEL_MARGIN, 18);
    this.novelDisplayMode = await SettingsRepository.getNumber(SettingsKeys.NOVEL_DISPLAY_MODE, 1);
  }

  private flash(text: string): void {
    this.hint = text;
    setTimeout(() => {
      if (this.hint === text) {
        this.hint = '';
      }
    }, 1200);
  }

  private async pickBg(id: string): Promise<void> {
    this.bg = id;
    await SettingsRepository.set(SettingsKeys.READER_BG, id);
    this.flash('背景已更新');
  }

  private async pickMode(id: string): Promise<void> {
    this.mode = id;
    await SettingsRepository.set(SettingsKeys.READER_MODE, id);
    this.flash('阅读模式已更新');
  }

  private async pickAnim(id: string): Promise<void> {
    this.pageAnim = id;
    await SettingsRepository.set(SettingsKeys.READER_PAGE_ANIM, id);
    this.flash('翻页动画已更新');
  }

  private async pickOrientation(v: number): Promise<void> {
    this.orientation = v;
    await SettingsRepository.set(SettingsKeys.RENDER_ORIENTATION, v);
    this.flash(v === 1 ? '竖排已启用' : '横排已启用');
  }

  private async pickDirection(v: number): Promise<void> {
    this.vDirection = v;
    await SettingsRepository.set(SettingsKeys.RENDER_DIRECTION, v);
    this.flash('竖排列序已更新');
  }

  private async pickFontMode(v: number): Promise<void> {
    this.fontSizeMode = v;
    await SettingsRepository.set(SettingsKeys.RENDER_FONT_MODE, v);
    this.flash(v === 0 ? '字号自动适配气泡' : '固定字号已启用');
  }

  private async changeFontSize(v: number): Promise<void> {
    this.fontSize = Math.round(v);
    this.fontSizeMode = 1;
    await SettingsRepository.set(SettingsKeys.RENDER_FONT_SIZE, this.fontSize);
    await SettingsRepository.set(SettingsKeys.RENDER_FONT_MODE, 1);
  }

  private async changeLineHeight(v: number): Promise<void> {
    this.lineHeight = Math.round(v);
    await SettingsRepository.set(SettingsKeys.READER_LINE_HEIGHT, this.lineHeight);
  }

  private async changeMargin(v: number): Promise<void> {
    this.pageMargin = Math.round(v);
    await SettingsRepository.set(SettingsKeys.READER_MARGIN, this.pageMargin);
  }

  private async changeAutoInterval(v: number): Promise<void> {
    this.autoInterval = Math.round(v);
    await SettingsRepository.set(SettingsKeys.READER_AUTO_INTERVAL, this.autoInterval);
  }

  private async toggleWhiteMerge(v: boolean): Promise<void> {
    this.whiteMerge = v;
    await SettingsRepository.set(SettingsKeys.READER_WHITE_MERGE, v);
    this.flash(v ? '白块合并已开启' : '白块独立绘制');
  }

  private async pickNovelDisplayMode(v: number): Promise<void> {
    this.novelDisplayMode = v;
    await SettingsRepository.set(SettingsKeys.NOVEL_DISPLAY_MODE, v);
    this.flash('小说默认显示模式已更新');
  }

  private async changeNovelLineHeight(v: number): Promise<void> {
    this.novelLineHeight = Math.round(v);
    await SettingsRepository.set(SettingsKeys.NOVEL_LINE_HEIGHT, this.novelLineHeight);
  }

  private async changeNovelMargin(v: number): Promise<void> {
    this.novelMargin = Math.round(v);
    await SettingsRepository.set(SettingsKeys.NOVEL_MARGIN, this.novelMargin);
  }

  private isWide(): boolean {
    return this.sizeClass === WindowSizeClass.LG;
  }

  @Builder
  sectionTitle(title: string, desc: string) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      if (desc.length > 0) {
        Text(desc)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 6, bottom: 2 })
  }

  @Builder
  optionChip(pp: ChipParams) {
    Text(pp.label)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(pp.active ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(pp.active ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_VARIANT)
      .margin({ right: 8, bottom: 6 })
      .onClick(() => {
        pp.onTap();
      })
  }

  @Builder
  sliderRow(pp: SliderParams) {
    Column({ space: 4 }) {
      Row() {
        Text(pp.label)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
        Blank()
        Text(pp.valueText)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.PRIMARY_SOFT)
      }
      .width('100%')

      Slider({
        value: pp.value,
        min: pp.min,
        max: pp.max,
        step: pp.step,
        style: SliderStyle.OutSet
      })
        .selectedColor(ThemeTokens.PRIMARY)
        .trackColor(ThemeTokens.SURFACE_VARIANT)
        .blockColor(ThemeTokens.PRIMARY_SOFT)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          interactive: true,
          lightEffect: {}
        }))
        .width('100%')
        .onChange((v: number) => {
          pp.onChange(v);
        })
    }
    .width('100%')
    .margin({ top: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  switchRow(pp: SwitchParams) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(pp.label)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
        if (pp.desc.length > 0) {
          Text(pp.desc)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: pp.checked })
        .selectedColor(ThemeTokens.PRIMARY)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          interactive: true,
          lightEffect: {}
        }))
        .onChange((isOn: boolean) => {
          pp.onChange(isOn);
        })
    }
    .width('100%')
    .margin({ top: 10 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    NavDestination() {
      Scroll() {
        Row() {
          Column({ space: 12 }) {
            Row() {
              Column({ space: 2 }) {
                Text('阅读与显示')
                  .fontSize(ThemeTokens.FONT_TITLE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeTokens.TEXT_PRIMARY)
                Text('修改即写入 starflow_reader，阅读器返回后立即生效')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_HINT)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (this.hint.length > 0) {
                Text(this.hint)
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.SUCCESS)
                  .maxLines(1)
              }
            }
            .width('100%')

            this.sectionTitle('阅读背景', '紫调纸色与纯黑 OLED 可选，低蓝光阅读')
            ReadSettingCard() {
              Row({ space: 6 }) {
                ForEach(this.backgrounds, (opt: BgOption) => {
                  Column({ space: 5 }) {
                    Column({ space: 2 }) {
                      Text('文')
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(opt.id === 'paper' || opt.id === 'white'
                          ? '#14101F' : ThemeTokens.TEXT_PRIMARY)
                      Text('阅读')
                        .fontSize(8)
                        .fontColor(opt.id === 'paper' || opt.id === 'white'
                          ? '#4A4260' : ThemeTokens.TEXT_SECONDARY)
                    }
                    .width('100%')
                    .height(50)
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                    .borderRadius(ThemeTokens.RADIUS_SMALL)
                    .backgroundColor(opt.color)
                    .border({
                      width: this.bg === opt.id ? 2 : 1,
                      color: this.bg === opt.id ? ThemeTokens.PRIMARY : ThemeTokens.DIVIDER
                    })

                    Text(opt.label)
                      .fontSize(ThemeTokens.FONT_SMALL)
                      .fontColor(this.bg === opt.id ? ThemeTokens.PRIMARY_SOFT : ThemeTokens.TEXT_HINT)
                  }
                  .layoutWeight(1)
                  .onClick(() => {
                    this.pickBg(opt.id);
                  })
                }, (opt: BgOption) => opt.id)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }

            this.sectionTitle('阅读模式', '三态切换：译文 / 原文 / 原图')
            ReadSettingCard() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.modes, (opt: ModeOption) => {
                  this.optionChip({ label: opt.label, active: this.mode === opt.id, onTap: () => {
                    this.pickMode(opt.id);
                  } })
                }, (opt: ModeOption) => opt.id)
              }
              .width('100%')
            }

            this.sectionTitle('翻页动画', '无 / 滑动 / 封面叠放 / 卷曲精简')
            ReadSettingCard() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.anims, (opt: ModeOption) => {
                  this.optionChip({ label: opt.label, active: this.pageAnim === opt.id, onTap: () => {
                    this.pickAnim(opt.id);
                  } })
                }, (opt: ModeOption) => opt.id)
              }
              .width('100%')
            }

            this.sectionTitle('字号', '自动适配气泡，或固定字号（12–40fp）')
            ReadSettingCard() {
              Flex({ wrap: FlexWrap.Wrap }) {
                this.optionChip({ label: '自动适配', active: this.fontSizeMode === 0, onTap: () => {
                  this.pickFontMode(0);
                } })
                this.optionChip({ label: '固定字号', active: this.fontSizeMode === 1, onTap: () => {
                  this.pickFontMode(1);
                } })
              }
              .width('100%')
              this.sliderRow({ label: '字号', valueText: `${this.fontSize} fp`, value: this.fontSize, min: 12, max: 40, step: 1, onChange: (v: number) => {
                this.changeFontSize(v);
              } })
            }

            this.sectionTitle('漫画译文行距与页边距', '译文覆盖渲染的行距与页边距')
            ReadSettingCard() {
              this.sliderRow({ label: '行距', valueText: `${this.lineHeight}%`, value: this.lineHeight, min: 100, max: 200, step: 5, onChange: (v: number) => {
                this.changeLineHeight(v);
              } })
              this.sliderRow({ label: '页边距', valueText: `${this.pageMargin} vp`, value: this.pageMargin, min: 0, max: 32, step: 1, onChange: (v: number) => {
                this.changeMargin(v);
              } })
            }

            this.sectionTitle('自动翻页间隔', '阅读器自动翻页的停留秒数（3–60s）')
            ReadSettingCard() {
              this.sliderRow({ label: '间隔', valueText: `${this.autoInterval} 秒`, value: this.autoInterval, min: 3, max: 60, step: 1, onChange: (v: number) => {
                this.changeAutoInterval(v);
              } })
            }

            this.sectionTitle('小说排版', '小说阅读器的显示模式、行高与左右边距')
            ReadSettingCard() {
              Text('默认显示模式')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .fontColor(ThemeTokens.TEXT_SECONDARY)
                .width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                this.optionChip({ label: '译文', active: this.novelDisplayMode === 0, onTap: () => {
                  this.pickNovelDisplayMode(0);
                } })
                this.optionChip({ label: '原文', active: this.novelDisplayMode === 1, onTap: () => {
                  this.pickNovelDisplayMode(1);
                } })
                this.optionChip({ label: '双语', active: this.novelDisplayMode === 2, onTap: () => {
                  this.pickNovelDisplayMode(2);
                } })
              }
              .width('100%')
              .margin({ top: 6 })
              this.sliderRow({ label: '行高', valueText: `${this.novelLineHeight} vp`, value: this.novelLineHeight, min: 20, max: 48, step: 1, onChange: (v: number) => {
                  this.changeNovelLineHeight(v);
                } })
              this.sliderRow({ label: '左右边距', valueText: `${this.novelMargin} vp`, value: this.novelMargin, min: 0, max: 40, step: 1, onChange: (v: number) => {
                  this.changeNovelMargin(v);
                } })
              Text('小说字号与上方「字号」共用 render_font_size（小说侧按 12–30 生效）；阅读背景同样共用上方六档。')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
                .width('100%')
                .lineHeight(17)
                .margin({ top: 8 })
            }

            this.sectionTitle('竖排与白块', '竖排译文列序与重叠白块处理')
            ReadSettingCard() {
              Text('竖排方向')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .fontColor(ThemeTokens.TEXT_SECONDARY)
                .width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                this.optionChip({ label: '右 → 左（日漫）', active: this.vDirection === 0, onTap: () => {
                  this.pickDirection(0);
                } })
                this.optionChip({ label: '左 → 右', active: this.vDirection === 1, onTap: () => {
                  this.pickDirection(1);
                } })
              }
              .width('100%')
              .margin({ top: 6 })

              Text('文字方向')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .fontColor(ThemeTokens.TEXT_SECONDARY)
                .width('100%')
                .margin({ top: 6 })
              Flex({ wrap: FlexWrap.Wrap }) {
                this.optionChip({ label: '自动', active: this.orientation === 2, onTap: () => {
                  this.pickOrientation(2);
                } })
                this.optionChip({ label: '竖排', active: this.orientation === 1, onTap: () => {
                  this.pickOrientation(1);
                } })
                this.optionChip({ label: '横排', active: this.orientation === 0, onTap: () => {
                  this.pickOrientation(0);
                } })
              }
              .width('100%')
              .margin({ top: 6 })

              Divider()
                .color(ThemeTokens.DIVIDER)
                .strokeWidth(0.5)
                .margin({ top: 8, bottom: 2 })

              this.switchRow({ label: '白块合并', desc: '译文与原文区域重叠时合并为一个白块', checked: this.whiteMerge, onChange: (v: boolean) => {
                  this.toggleWhiteMerge(v);
                } })
            }

            Text('说明：阅读器内「渲染设置」与本页读写同一份 preferences，任一处修改都会同步。')
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
    .title('阅读设置', {
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