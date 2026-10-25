import { uiMaterial } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';
import { SettingsKeys, SettingsRepository } from '../data/SettingsRepository';

/** 主题选项。 */
class ThemeOption {
  id: string;
  title: string;
  desc: string;
  available: boolean;
  swatch: string;

  constructor(id: string, title: string, desc: string, available: boolean, swatch: string) {
    this.id = id;
    this.title = title;
    this.desc = desc;
    this.available = available;
    this.swatch = swatch;
  }
}

/** @Builder 按引用传递参数（状态改变可刷新 UI）。 */
interface ThemeRowParams {
  opt: ThemeOption;
  active: boolean;
}

/** 设置卡片容器。 */
@Component
struct ThemeSettingCard {
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
 * 主题外观页（S110 设置侧）：紫夜深色（默认）/ 紫夜纯黑 OLED / 跟随系统，
 * 运行时切换色板并重建 shell；蓝白为浅色，紫夜/OLED 为深色。
 */
@Component
export struct SettingsThemePage {
  @State themeMode: string = 'purple';
  @State hint: string = '';
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private options: Array<ThemeOption> = [
    new ThemeOption('purple', '紫夜深色（默认）', '深紫夜色底 + 紫罗兰主色，低蓝光阅读，全应用统一。', true,
      ThemeTokens.READER_BG_NOCTURNE),
    new ThemeOption('blue', '蓝白配色', '明亮蓝白 + 清晰蓝主色，适合白天与办公；切换后立即重建界面。', true,
      '#F5F9FF'),
    new ThemeOption('oled', '紫夜纯黑 OLED', '纯黑底更省电，适合 OLED 屏幕与夜间阅读；保存后重启生效。', true,
      ThemeTokens.READER_BG_BLACK),
    new ThemeOption('system', '跟随系统', '当前固定深色；保留偏好位，后续版本再跟随系统深浅色。', true,
      ThemeTokens.SURFACE_SECONDARY)
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
    this.themeMode = await SettingsRepository.getString(SettingsKeys.THEME_MODE, 'purple');
  }

  private async pickTheme(id: string): Promise<void> {
    this.themeMode = id;
    // 1) 内存色板立即切换；2) 持久化；3) 通知 shell 重建全部页面读取新 token。
    ThemeTokens.applyMode(id);
    await SettingsRepository.set(SettingsKeys.THEME_MODE, id);
    AppStorage.setOrCreate('starflow_theme_mode', id);
    const rev: number = AppStorage.get<number>('starflow_theme_rev') ?? 0;
    AppStorage.setOrCreate('starflow_theme_rev', rev + 1);
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await ctx.getApplicationContext().setColorMode(id === 'blue'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        : ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (e) {
      // 系统栏/弹窗深浅色是增强项，失败不影响应用内配色。
    }
    this.hint = id === 'blue' ? '蓝白配色已启用' : '主题已切换';
    setTimeout(() => {
      this.hint = '';
    }, 1600);
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
  optionRow(pp: ThemeRowParams) {
    Row({ space: 12 }) {
      Column()
        .width(38)
        .height(38)
        .borderRadius(ThemeTokens.RADIUS_SMALL)
        .backgroundColor(pp.opt.swatch)
        .border({ width: 1, color: ThemeTokens.DIVIDER })

      Column({ space: 3 }) {
        Row({ space: 8 }) {
          Text(pp.opt.title)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
          if (!pp.opt.available) {
            Text('未接入')
              .fontSize(10)
              .fontColor(ThemeTokens.TEXT_HINT)
          }
        }
        Text(pp.opt.desc)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .lineHeight(17)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Radio({ value: pp.opt.id, group: 'theme' })
        .checked(pp.active)
        .onChange((checked: boolean) => {
          if (checked) {
            this.pickTheme(pp.opt.id);
          }
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .onClick(() => {
      this.pickTheme(pp.opt.id);
    })
  }

  @Builder
  previewCard() {
    Column({ space: 10 }) {
      Text('主题预览')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_HINT)
        .width('100%')
      Row({ space: 10 }) {
        Column({ space: 6 }) {
          Text('星译')
            .fontSize(ThemeTokens.FONT_SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
          Text(ThemeTokens.isLight() ? '蓝白阅读 · 明亮' : '紫夜阅读 · 低蓝光')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
          Text('主按钮')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .backgroundColor(ThemeTokens.PRIMARY)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(ThemeTokens.CARD_PADDING)
        .borderRadius(ThemeTokens.RADIUS_SMALL)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      }
      .width('100%')
      Text('预览使用当前色板；选择蓝白配色后返回即可看到全应用重建。')
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_HINT)
        .width('100%')
        .lineHeight(17)
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Scroll() {
        Row() {
          Column({ space: 12 }) {
            Row() {
              Column({ space: 2 }) {
                Text('主题外观')
                  .fontSize(ThemeTokens.FONT_TITLE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeTokens.TEXT_PRIMARY)
                Text(ThemeTokens.isLight() ? '蓝白沉浸光感 · 明亮阅读' : '紫夜阅读设计语言 · 沉浸光感材质')
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

            this.sectionTitle('主题模式', '选择应用配色；蓝白配色切换后立即重建界面')
            ThemeSettingCard() {
              ForEach(this.options, (opt: ThemeOption) => {
                this.optionRow({ opt: opt, active: this.themeMode === opt.id })
              }, (opt: ThemeOption) => opt.id)
            }

            ThemeSettingCard() {
              this.previewCard()
            }

            this.sectionTitle('说明', '关于主题能力的边界，避免误解')
            ThemeSettingCard() {
              this.noteRow('运行时切换', '色板由 ThemeTokens.applyMode() 在运行时切换，选择后重建页面外壳；系统栏颜色在下次启动时完全同步。')
              Divider()
                .color(ThemeTokens.DIVIDER)
                .strokeWidth(0.5)
              this.noteRow('沉浸光感',
                'API 26 的 uiMaterial 沉浸材质已用于底部悬浮 Tab 与各页 NavDestination 标题栏，配合紫夜底色呈现磨砂光感。')
              Divider()
                .color(ThemeTokens.DIVIDER)
                .strokeWidth(0.5)
              this.noteRow('动态取色',
                '当前版本不读取壁纸动态取色（Material You 式取色未接入）；保留选项与偏好位，后续版本再启用。')
              Divider()
                .color(ThemeTokens.DIVIDER)
                .strokeWidth(0.5)
              this.noteRow('阅读背景独立',
                '阅读器背景（黑/紫夜/紫梅/深紫/纸色/白）是独立设置，请在「阅读设置」中调整。')
            }

            Text('提示：OLED 纯黑档位为偏好预留；如需立即获得纯黑阅读体验，请到「阅读设置 → 阅读背景」选择「纯黑」。')
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
    .title('主题外观', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
  }

  @Builder
  noteRow(title: string, desc: string) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      Text(desc)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_HINT)
        .lineHeight(17)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }
}